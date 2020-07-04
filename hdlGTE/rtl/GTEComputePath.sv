// ----------------------------------------------------------------------------------------------
//   Compute Path
// ----------------------------------------------------------------------------------------------
`include "GTEDefine.hv"

module GTEComputePath(
    input                   i_clk,
    input                   i_nRst,

	input                   isMVMVA,
	input   gteWriteBack    i_wb,
    input   CTRL            i_instrParam,
    input   gteComputeCtrl  i_computeCtrl,
    input   SgteREG         i_registers,
    output  gteCtrl         o_RegCtrl
);

wire signed [43:0]  outAddSel;
wire signed [34:0]  outSel1,outSel2,outSel3;

reg [15:0] TMP1,TMP2,TMP3;

wire [7:0] colR = i_computeCtrl.selCol0 ? i_registers.CRGB0.r : i_registers.CRGB.r;
wire [7:0] colG = i_computeCtrl.selCol0 ? i_registers.CRGB0.g : i_registers.CRGB.g;
wire [7:0] colB = i_computeCtrl.selCol0 ? i_registers.CRGB0.b : i_registers.CRGB.b;

wire [16:0] divRes;
reg  [16:0] divResREG;

// Handle special weird case of OP() instruction. Use IR0 path to inject IR in various order.
reg [15:0] selIR0_1,selIR0_2,selIR0_3;
always @(*) begin
	case (i_computeCtrl.selOpInstr)
	// Standard : IR0 is mapped to everybody.
	2'd0:    begin selIR0_1 = i_registers.IR0; selIR0_2 = i_registers.IR0; selIR0_3 = i_registers.IR0; end
	// Step 1 OP() : IR3 to unit2, IR2 to unit3.
	2'd1:    begin selIR0_1 = i_registers.IR0; selIR0_2 = i_registers.IR3; selIR0_3 = i_registers.IR2; end
	// Step 2 OP() : TMP3 to unit1, TMP1 to unit3 
	2'd2:    begin selIR0_1 = TMP3;            selIR0_2 = i_registers.IR0; selIR0_3 = TMP1;            end
	// Step 3 OP() : 
	default: begin selIR0_1 = TMP2;            selIR0_2 = TMP1;            selIR0_3 = i_registers.IR0; end
	endcase
end

wire [15:0] minusR = {4'd15, ~i_registers.CRGB.r, 4'd15} + 16'd1;

GTESelPath SelMuxUnit1 (
  .ctrl    (i_computeCtrl.sel1),

  .isMVMVA (isMVMVA),
  .vec     (i_instrParam.vec),
  .mx      (i_instrParam.mx),

  .MAT0_C0 (i_registers.R11),
  .MAT1_C0 (i_registers.R21),
  .MAT2_C0 (i_registers.R31),

  .MAT0_C1 (i_registers.L11),
  .MAT1_C1 (i_registers.L21),
  .MAT2_C1 (i_registers.L31),
  
  .MAT0_C2 (i_registers.LR1),
  .MAT1_C2 (i_registers.LG1),
  .MAT2_C2 (i_registers.LB1),

  .MAT3_C0 (minusR),
  .MAT3_C1 (i_registers.R13),
  .MAT3_C2 (i_registers.R22),
  
  .color (colR),
  .IRn (i_registers.IR1),
  .SZ (i_registers.SZ1),
  .DQA(i_registers.DQA),
  .HS3Z(divResREG),
  .V0c (i_registers.VX0),
  .V1c (i_registers.VX1),
  .V2c (i_registers.VX2),
  .tmpReg (TMP1),
  .Z3 (i_registers.ZSF3),
  .Z4 (i_registers.ZSF4),
  .IR0 (selIR0_1),
  .outstuff(outSel1)
);

GTESelPath SelMuxUnit2 (
  .ctrl    (i_computeCtrl.sel2),

  .isMVMVA (isMVMVA),
  .vec     (i_instrParam.vec),
  .mx      (i_instrParam.mx),

  .MAT0_C0 (i_registers.R12),
  .MAT1_C0 (i_registers.R22),
  .MAT2_C0 (i_registers.R32),
  
  .MAT0_C1 (i_registers.L12),
  .MAT1_C1 (i_registers.L22),
  .MAT2_C1 (i_registers.L32),
  
  .MAT0_C2 (i_registers.LR2),
  .MAT1_C2 (i_registers.LG2),
  .MAT2_C2 (i_registers.LB2),
  
  .MAT3_C0 ({4'd0, i_registers.CRGB.r, 4'd0}),
  .MAT3_C1 (i_registers.R13),
  .MAT3_C2 (i_registers.R22),
  
  .color (colG),
  .IRn (i_registers.IR2),
  .SZ (i_registers.SZ2),
  .DQA(16'd0), // DQA not used in SEL2.
  .HS3Z(divResREG),
  .V0c (i_registers.VY0),
  .V1c (i_registers.VY1),
  .V2c (i_registers.VY2),
  .tmpReg (TMP2),
  .Z3 (i_registers.ZSF3),
  .Z4 (i_registers.ZSF4),
  .IR0 (selIR0_2),
  .outstuff(outSel2)
);

GTESelPath SelMuxUnit3 (
  .ctrl    (i_computeCtrl.sel3),

  .isMVMVA (isMVMVA),
  .vec     (i_instrParam.vec),
  .mx      (i_instrParam.mx),
  
  .MAT0_C0 (i_registers.R13),
  .MAT1_C0 (i_registers.R23),
  .MAT2_C0 (i_registers.R33),
  
  .MAT0_C1 (i_registers.L13),
  .MAT1_C1 (i_registers.L23),
  .MAT2_C1 (i_registers.L33),
  
  .MAT0_C2 (i_registers.LR3),
  .MAT1_C2 (i_registers.LG3),
  .MAT2_C2 (i_registers.LB3),
  
  .MAT3_C0 (i_registers.IR0),
  .MAT3_C1 (i_registers.R13),
  .MAT3_C2 (i_registers.R22),
  
  .color (colB),
  .IRn (i_registers.IR3),
  .SZ (i_registers.SZ3),
  .DQA(16'd0), // DQA not used in SEL3.
  .HS3Z(16'd0),
  .V0c (i_registers.VZ0),
  .V1c (i_registers.VZ1),
  .V2c (i_registers.VZ2),
  .tmpReg (TMP3),
  .Z3 (i_registers.ZSF3),
  .Z4 (i_registers.ZSF4),
  .IR0 (selIR0_3),
  .outstuff(outSel3)
);

reg signed [ 8:0] colSide;
reg signed [15:0] PrevSide;
always @(*) begin
	case (i_computeCtrl.addSel.id)
	2'd0    : begin PrevSide = TMP1; colSide = { 1'b0, i_registers.CRGB.r }; end
	2'd1    : begin PrevSide = TMP2; colSide = { 1'b0, i_registers.CRGB.g }; end
	default : begin PrevSide = TMP3; colSide = { 1'b0, i_registers.CRGB.b }; end
	endcase
end

wire signed [23:0] specialRGBMulTMP = PrevSide * colSide;

GTESelAddPath selAddInst (
	.ctrl		(i_computeCtrl.addSel),
	
	.i_SF		(i_instrParam.sf),
	.isMVMVA	(isMVMVA),
	.cv			(i_instrParam.cv),

	.TRX		(i_registers.TRX),
	.TRY		(i_registers.TRY),
	.TRZ		(i_registers.TRZ),

	.RBK		(i_registers.RBK),
	.GBK		(i_registers.GBK),
	.BBK		(i_registers.BBK),

	.RFC		(i_registers.RFC),
	.GFC		(i_registers.GFC),
	.BFC		(i_registers.BFC),

	.MAC1		(i_registers.MAC1),
	.MAC2		(i_registers.MAC2),
	.MAC3		(i_registers.MAC3),

	.OF0		(i_registers.OFX),
	.OF1		(i_registers.OFY),
	.DQB		(i_registers.DQB),
	
	.NCDS_CDP_DPCL_Special	(specialRGBMulTMP),

	.R			(colR),
	.G			(colG),
	.B			(colB),

	.TMP1		(TMP1),
	.TMP2		(TMP2),
	.TMP3		(TMP3),

	.SZ0		(i_registers.SZ0),
	.ZFS4		(i_registers.ZSF4),
	
	.outstuff(outAddSel)
);

wire        divOverflow;
GTEFastDiv GTEFastDiv_Inst(
	.h			(i_registers.H),	// Dividend
	.z3			(i_registers.SZ3),	// Divisor
	.divRes		(divRes),			// Result
	.overflow	(divOverflow)		// Overflow bit
);

// Seperate sum because we will have intermediate flag check.
wire [34:0]  outSel1P = i_computeCtrl.negSel[0] ? (~outSel1 + 35'd1) : outSel1;
wire [34:0]  outSel2P = i_computeCtrl.negSel[1] ? (~outSel2 + 35'd1) : outSel2;
wire [34:0]  outSel3P = i_computeCtrl.negSel[2] ? (~outSel3 + 35'd1) : outSel3;

wire [45:0]  part1Sum = {outAddSel[43],outAddSel[43],outAddSel} + {{11{outSel1P[34]}},outSel1P};
wire [45:0]  part2Sum = part1Sum + {{11{outSel2P[34]}},outSel2P};
wire [45:0]  finalSum = part2Sum + {{11{outSel3P[34]}},outSel3P};

wire useSFWrite32     = i_instrParam.sf & i_computeCtrl.useSFWrite32;

wire [31:0] valWriteBack32 = useSFWrite32 ? finalSum[43:12] : finalSum[31:0];

// -------------------------------------------------------------------------------

wire [15:0] clampZ;
wire flagBit18;
GTEOverflowFLAGS GTEOverflowFLAGS_Instance(
	.v					(finalSum),
	.sf					(/*None*/),
	.lm					(/*None*/),
	.forceSF_BFlag		(/*None*/),
	
	.AxPos				(/*None*/),	// Use  0 bit shift.
	.AxNeg				(/*None*/),	// Use  0 bit shift.
	.FPos				(/*None*/),	// Use  0 bit shift.
	.FNeg				(/*None*/),	// Use  0 bit shift.
	.G					(/*None*/),		// Use >> 16 bit shift.
	.H					(/*None*/),		// Use >> 12 bit shift.

	.B					(/*None*/),		// Depend on SF.
	.C					(/*None*/),		// Depend on SF+4.
	.D					(flagBit18),

	.OutA				(/*None*/),
	.OutB				(/*None*/),
	.OutC				(/*None*/),
	.OutD				(clampZ),
	.OutG				(/*None*/),
	.OutH				(/*None*/)
);

// -------------------------------------------------------------------------------

assign o_RegCtrl.val   = valWriteBack32[11:4]; // TODO : Saturate [0..255]

//CASE 0/1
// ir[i] = clip(value , 0x7fff, lm ? 0 : -0x8000, saturatedBits);
// ir[3] = clip(mac[3], 0x7fff, lm ? 0 : -0x8000);               // RTP --> TAKE CARE OF mac[3] value there... shifted ???
// ===> THOSE REALLY NEED CARE -> RTP is weird, and clip(value, ...) depends a lot on who is doing the call.
//      Need to systematically log all the callers, and check one by one !
//
//CASE 2
//   otz = clip(value >> 12, 0xffff, 0x0000, Flag::SZ3_OTZ_SATURATED); // AVZ3/4
//   pushScreenZ((int32_t)(mac3 >> 12)); ==> clip(z, 0xffff, 0x0000, Flag::SZ3_OTZ_SATURATED); // PUSH Z, same as AVZ3/4
//CASE 3
//   clip(x, 0x3ff, -0x400, Flag::SX2_SATURATED); // Push X,Y
wire [15:0] val16;
assign o_RegCtrl.val16 = val16;
assign o_RegCtrl.val32 = valWriteBack32;

always @(*) begin
	if (i_wb.pushZ | i_wb.wrOTZ) begin
		// Case 2.
		val16 = clampZ;
	end else begin
		// [TODO] Fake.
		val16 = finalSum[15:0];
	end
end

always @(posedge i_clk) begin
	if (i_computeCtrl.assignIRtoTMP) begin
		TMP1 = i_registers.IR1;
		TMP2 = i_registers.IR2;
		TMP3 = i_registers.IR3;
	end
	if (i_computeCtrl.wrTMP1) begin TMP1 = val16; end
	if (i_computeCtrl.wrTMP2) begin TMP2 = val16; end
	if (i_computeCtrl.wrTMP3) begin TMP3 = val16; end
	if (i_computeCtrl.wrDivRes) begin divResREG = divRes; end
end

endmodule
