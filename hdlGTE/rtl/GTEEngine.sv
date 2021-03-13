/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
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
//	input		  i_ReadReg,
	
	input		  i_DIP_USEFASTGTE,		// Control signal coming from the console (not the CPU, from outside at runtime or compile option)
	input		  i_DIP_FIXWIDE,		// Same
	
	input  [31:0] i_dataIn,				// Register Write value.
	output [31:0] o_dataOut,			// Register Read  value.

	input  [24:0] i_Instruction,		// Instruction to execute
	input         i_run,				// Instruction valid
	output        o_executing
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
wire			isBuggyMVMVA = isMVMVAWire & (i_Instruction[14:13] == 2'd2);
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
	.i_WritReg		(i_WritReg & (!o_executing)),	// Filter
	.i_dataIn		(i_dataIn),
	.o_dataOut		(o_dataOut)
);

// ----------------------------------------------------------------------------------------------
//   Compute Path
// ----------------------------------------------------------------------------------------------

GTEComputePath GTEComputePath_inst(
	.i_clk			(i_clk),
	.i_nRst			(i_nRst),

	.isMVMVA        (isMVMVA),
	.WIDE			(i_DIP_FIXWIDE),
	
	.i_instrParam	(ctrl),				// Instruction Parameter bits
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
	.o_writeBack	(writeBack),
	.o_ctrl			(computeCtrl),
	.o_lastInstr	(gteLastMicroInstruction)
);

// ----------------------------------------------------------------------------------------------
//   Microcode Management : PC, Start Adress and Microcode ROM.
// ----------------------------------------------------------------------------------------------

wire loadInstr;
wire isExecuting = (rPC != 8'd0);

reg  [ 7:0] rPC;
wire [ 7:0] startMicroCodeAdr;
wire [ 7:0] vPC = loadInstr ? startMicroCodeAdr : (gteLastMicroInstruction ? 8'd0 : rPC);
wire [ 7:0] vPC1= vPC + {7'd0, isExecuting | loadInstr };

wire PCcond     = (!i_nRst) || (gteLastMicroInstruction && (!loadInstr));
wire [ 7:0] nPC = PCcond          ? 8'd0 : vPC1;

wire [ 5:0] officialCycleCount;
reg  [ 5:0] OfficialTimingCounter;

GTEMicrocodeStart GTEMicrocodeStart_inst(
	.isBuggyMVMVA	(isBuggyMVMVA),
	.Instruction	(i_Instruction[5:0]),
	.StartAddress	(startMicroCodeAdr),
	.officialCycleCount	(officialCycleCount)
);

assign loadInstr = i_run && (!o_executing);

always @(posedge i_clk) begin
	rPC <= nPC;
end

wire decrementingOfficialTimer = (OfficialTimingCounter != 6'd0);
reg pDIP_USEFASTGTE;
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
		isMVMVA	 <= isMVMVAWire; 				// MVMVA.
		pDIP_USEFASTGTE <= i_DIP_USEFASTGTE;
	end

	// Executing lock flag.
	if (i_nRst == 1'b0) begin
		isMVMVA	 <= 1'b0;
	end

	if ((!i_nRst) || (pDIP_USEFASTGTE)) begin
		OfficialTimingCounter	<= 6'd0;
	end else begin
		if (loadInstr) begin
			OfficialTimingCounter <= officialCycleCount;
		end else begin
			if (decrementingOfficialTimer) begin
				// Remove -1 when not 0.
				OfficialTimingCounter <= OfficialTimingCounter + 6'h3F;
			end
		end
	end
end

// Output
assign o_executing = isExecuting | decrementingOfficialTimer;

endmodule
