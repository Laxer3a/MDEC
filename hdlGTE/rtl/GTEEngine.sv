/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "GTEDefine.hv"

module GTEEngine (
	input         i_clk,
	input         i_nRst,				// NEGATIVE RESET !!! (1=Working, 0=Reset)

	input  E_REG  i_regID,				// Register ID to write or read. (READ ALWAYS HAPPEN, 0 LATENCY to o_dataOut, please use when o_executing=0)
	input         i_WritReg,			// Write to 'Register ID' = i_dataIn.
	
	input		  i_DIP_USEFASTGTE,		// Control signal coming from the console (not the CPU, from outside at runtime or compile option)
	input		  i_DIP_FIXWIDE,		// Same
	
//	input         i_ReadReg, 			// DEPRECATED

	input  [31:0] i_dataIn,				// Register Write value.
	output [31:0] o_dataOut,			// Register Read  value.

	input  [24:0] i_Instruction,		// Instruction to execute
	input         i_run,				// Instruction valid
	output        o_executing			// BUSY, only read/write/execute when o_executing = 0
);

// ComputePath => Register Write
gteCtrl			gteWR;
// Register    => Compute Path (Values)
SgteREG			gteREG;
// MicroCode   => Compute Path (Control)
gteComputeCtrl	computeCtrl;
// MicroCode   => Register Write
gteWriteBack    writeBack;
// Main        => Compute Path (Control)
// Instruction Decoder and Instruction Parameter (=> GTE Control too)
CTRL            ctrl;

reg             isMVMVA;
wire            isMVMVAWire  = (i_Instruction[5:0] == 6'h12);
wire            isBuggyMVMVA = isMVMVAWire & (i_Instruction[14:13] == 2'd2);
// Control status for microcode.
wire            gteLastMicroInstruction;

// ----------------------------------------------------------------------------------------------
// Register instancing and manage CPU or GTE write back.
// ----------------------------------------------------------------------------------------------

GTERegs GTERegs_inst (
	.i_clk			(i_clk),
	.i_nRst			(i_nRst),

	.i_loadInstr	(loadInstr),	// MUST : reset FLAG when instruction start.

	.i_wb			(writeBack),
	.gteWR			(gteWR),	// Input
	.gteREG			(gteREG),	// Output
	
	.i_regID		(i_regID),
	.i_WritReg		(i_WritReg),
	.i_dataIn		(i_dataIn),
	.o_dataOut		(o_dataOut)
);

// ----------------------------------------------------------------------------------------------
//   Compute Path
// ----------------------------------------------------------------------------------------------

CTRL            ctrlInput;
assign ctrlInput.lm  = loadInstr ? i_Instruction[10]    : ctrl.lm;
assign ctrlInput.sf  = loadInstr ? i_Instruction[19]    : ctrl.sf;
assign ctrlInput.cv  = loadInstr ? i_Instruction[14:13] : ctrl.cv;
assign ctrlInput.vec = loadInstr ? i_Instruction[16:15] : ctrl.vec;
assign ctrlInput.mx  = loadInstr ? i_Instruction[18:17] : ctrl.mx;
assign ctrlInput.executing = ctrl.executing; // Not used.

GTEComputePath GTEComputePath_inst(
	.i_clk			(i_clk),
	.i_nRst			(i_nRst),

	.isMVMVA        (isMVMVA | isMVMVAWire),
	.WIDE			(i_DIP_FIXWIDE),
	
	.i_instrParam	(ctrlInput),				// Instruction Parameter bits
	.i_computeCtrl	(computeCtrl),		// Control from Microcode Module.
	.i_DIP_FIXWIDE	(i_DIP_FIXWIDE),

	.i_wb			(writeBack),		// Write Back Signal
	.i_registers	(gteREG),			// Values  from Register Module.
	.o_RegCtrl		(gteWR)				// Write back to registers.
);

// ----------------------------------------------------------------------------------------------
//   Microcode RAM/ROM
// ----------------------------------------------------------------------------------------------

GTEMicroCode GTEMicroCode_inst(
	.i_clk			(i_clk),			// Pass clock if BRAM is used for storage...
	.isNewInstr		(loadInstr),
	.Instruction	(i_Instruction[5:0]),
	.i_PC			(vPC),
	.i_USEFAST		(i_DIP_USEFASTGTE),
	
	.o_writeBack	(writeBack),
	.o_ctrl			(computeCtrl),
	.o_lastInstr	(gteLastMicroInstruction)
);

// ----------------------------------------------------------------------------------------------
//   Microcode Management : PC, Start Adress and Microcode ROM.
// ----------------------------------------------------------------------------------------------

reg  [ 8:0] PC,vPC;
wire [ 8:0] startMicroCodeAdr;

GTEMicrocodeStart GTEMicrocodeStart_inst(
	.IsNop			(!ctrl.executing),
	.isBuggyMVMVA	(isBuggyMVMVA),
	.Instruction	(i_Instruction[5:0]),
	.StartAddress	(startMicroCodeAdr)
);

wire loadInstr = i_run && (!ctrl.executing);

// Allow to have PC value zero latency (pre PC reg write)
always @(*)
begin
	if (loadInstr) begin
		vPC = startMicroCodeAdr;
	end else begin
		if (!ctrl.executing) begin
			vPC = 9'd0; // NOP is first entry in ROM. (Special zero latency case ?)
		end else begin
			vPC = PC + 9'd1;
		end
	end
end

always @(posedge i_clk)
begin
	// Instruction Loading.
	if (loadInstr) begin
		ctrl.sf  <= i_Instruction[19];		// 0:No fraction, 1:12 Bit Fraction
		ctrl.lm  <= i_Instruction[10];		// 0:Clamp to MIN, 1:Clamp to ZERO.
		// MVMVA only.
		ctrl.cv  <= i_Instruction[14:13];		// 0:TR,       1:BK,    2:FC/Bugged, 3:None
		ctrl.vec <= i_Instruction[16:15];		// 0:V0,       1:V1,    2:V2,        3:IR/Long
		ctrl.mx	 <= i_Instruction[18:17];		// 0:Rotation, 1:Light, 2:Color,     3:Reserved
	end

	// Executing lock flag.
	if (gteLastMicroInstruction || (i_nRst == 1'b0)) begin
		ctrl.executing			<= 1'b0;
		PC						<= 9'd0;
		isMVMVA					<= 1'b0;
	end else begin
		PC	<= vPC;
		if (loadInstr) begin
		    isMVMVA				<= isMVMVAWire; 				// MVMVA.
			ctrl.executing		<= 1'b1; 						// No !gteLastMicroInstruction; needed (because gteLastMicroInstruction reset executing).
		end
	end
end

// Output
assign o_executing = ctrl.executing;

endmodule
