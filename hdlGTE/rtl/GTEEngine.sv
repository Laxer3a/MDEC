`include "GTEDefine.hv"

module GTEEngine (
	input         i_clk,
	input         i_nRst,

	input  E_REG  i_regID,
	input         i_WritReg,
//	input         i_ReadReg,
	input  [31:0] i_dataIn,
	output [31:0] o_dataOut,

	input  [24:0] i_Instruction,
	input         i_run,		
	output        o_executing	// SET TO ZERO AT LAST CYCLE OF EXECUTION !!!! Shave off a cycle.
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

GTEComputePath GTEComputePath_inst(
	.i_clk			(i_clk),
	.i_nRst			(i_nRst),

	.isMVMVA        (isMVMVA | isMVMVAWire),
	.i_instrParam	(ctrl),				// Instruction Parameter bits
	.i_computeCtrl	(computeCtrl),		// Control from Microcode Module.
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
		    isMVMVA				<= isMVMVAWire; // MVMVA.
			ctrl.executing		<= 1'b1;
		end
	end
end

// Output
assign o_executing = ctrl.executing;

endmodule
