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
  .MAT0_C1 (i_registers.R21),
  .MAT0_C2 (i_registers.R31),

  .MAT1_C0 (i_registers.L11),
  .MAT1_C1 (i_registers.L21),
  .MAT1_C2 (i_registers.L31),
  
  .MAT2_C0 (i_registers.LR1),
  .MAT2_C1 (i_registers.LG1),
  .MAT2_C2 (i_registers.LB1),

  .MAT3_C0 (minusR),
  .MAT3_C1 (i_registers.R13),
  .MAT3_C2 (i_registers.R22),
  
  .SX      (i_registers.SX0),
  .SYA     (i_registers.SY1),
  .SYB     (i_registers.SY2),
  
  .color (colR),
  .IRn (i_registers.IR1),
  .SZ (i_registers.SZ1),
  .DQA(i_registers.DQA),
  .HS3Z(divRes),
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
  .MAT0_C1 (i_registers.R22),
  .MAT0_C2 (i_registers.R32),
  
  .MAT1_C0 (i_registers.L12),
  .MAT1_C1 (i_registers.L22),
  .MAT1_C2 (i_registers.L32),
  
  .MAT2_C0 (i_registers.LR2),
  .MAT2_C1 (i_registers.LG2),
  .MAT2_C2 (i_registers.LB2),
  
  .MAT3_C0 ({4'd0, i_registers.CRGB.r, 4'd0}),
  .MAT3_C1 (i_registers.R13),
  .MAT3_C2 (i_registers.R22),

  .SX      (i_registers.SX1),
  .SYA     (i_registers.SY2),
  .SYB     (i_registers.SY0),
  
  .color (colG),
  .IRn (i_registers.IR2),
  .SZ (i_registers.SZ2),
  .DQA(16'd0), // DQA not used in SEL2.
  .HS3Z(divRes),
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
  .MAT0_C1 (i_registers.R23),
  .MAT0_C2 (i_registers.R33),
  
  .MAT1_C0 (i_registers.L13),
  .MAT1_C1 (i_registers.L23),
  .MAT1_C2 (i_registers.L33),
  
  .MAT2_C0 (i_registers.LR3),
  .MAT2_C1 (i_registers.LG3),
  .MAT2_C2 (i_registers.LB3),
  
  .MAT3_C0 (i_registers.IR0),
  .MAT3_C1 (i_registers.R13),
  .MAT3_C2 (i_registers.R22),
  
  .SX      (i_registers.SX2),
  .SYA     (i_registers.SY0),
  .SYB     (i_registers.SY1),
  
  .color (colB),
  .IRn (i_registers.IR3),
  .SZ (i_registers.SZ3),
  .DQA(16'd0), // DQA not used in SEL3.
  .HS3Z(17'd0),
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

// HW Timing TRICK :
// - Cycle 0 : Compute value to put to Z Stack (Z Component done first !)
// - Cycle 1 : Z Stack updated. (Div compute first part)
// - Cycle 2 : Fast Div Pipeline (Div pipeline to second part)
// - Cycle 3 : Value output of pipeline !!!!
// NOW : SZ3 and H won't change from Cycle 1+, so no need to save values !
wire        divOverflow;
GTEFastDiv GTEFastDiv_Inst(
	.i_clk		(i_clk),
	.h			(i_registers.H),	// Dividend
	.z3			(i_registers.SZ3),	// Divisor
	.divRes		(divRes),			// Result
	.overflow	(divOverflow)		// Overflow bit
);

// Seperate sum because we will have intermediate flag check.
wire [34:0]  outSel1P = i_computeCtrl.negSel[0] ? (~outSel1 + 35'd1) : outSel1;
wire [34:0]  outSel2P = i_computeCtrl.negSel[1] ? (~outSel2 + 35'd1) : outSel2;
wire [34:0]  outSel3P = i_computeCtrl.negSel[2] ? (~outSel3 + 35'd1) : outSel3;

wire [44:0]  part1Sum = {outAddSel[43],outAddSel} + {{10{outSel1P[34]}},outSel1P};

wire [3:0] isOverflowS44 ;
wire [3:0] isUnderflowS44;
wire       isOverflowS32,isUnderflowS32;

FlagsS44 FlagS44Local1(
	.v			(part1Sum),
	.isOverflow	(isOverflowS44 [0]),
	.isUnderflow(isUnderflowS44[0])
);

wire [44:0]  part1SumPostExt = { i_computeCtrl.check44Local ? part1Sum[43] : part1Sum[44] , part1Sum[43:0] };
wire [44:0]  part2Sum = part1SumPostExt + {{10{outSel2P[34]}},outSel2P};

FlagsS44 FlagS44Local2(
	.v			(part2Sum),
	.isOverflow	(isOverflowS44 [1]),
	.isUnderflow(isUnderflowS44[1])
);

/*
reg  [44:0]  pipe_part2Sum;
always @(posedge i_clk) begin
	pipe_part2Sum = part2Sum;
end
*/

reg  [44:0]  tempSumREG;
wire [44:0]  part2SumPostExt = { i_computeCtrl.check44Local ? /*pipe_*/part2Sum[43] : /*pipe_*/part2Sum[44], /*pipe_*/part2Sum[43:0] };
wire [44:0]  finalSumBeforeExt = part2SumPostExt + {{10{outSel3P[34]}},outSel3P} + (i_computeCtrl.useStoreFull ? tempSumREG : 45'd0);

FlagsS44 FlagS44Local3(
	.v			(finalSumBeforeExt),
	.isOverflow	(isOverflowS44 [2]),
	.isUnderflow(isUnderflowS44[2])
);

wire [44:0]  finalSum = { i_computeCtrl.check44Local ? finalSumBeforeExt[43] : finalSumBeforeExt[44] , finalSumBeforeExt[43:0] };

FlagsS44 FlagS44Global(
	.v			(finalSum),
	.isOverflow	(isOverflowS44 [3]),
	.isUnderflow(isUnderflowS44[3])
);

FlagsS32 FlagS32Global(
	.v			(finalSum),
	.isOverflow	(isOverflowS32 ),
	.isUnderflow(isUnderflowS32)
);

wire [15:0] otzValue;
wire [15:0] IR0Value;
wire isUO_OTZ;
wire isUO_IR0;

FlagClipOTZ FlagClipOTZ_inst(
	.i_overflowS32			(isOverflowS32),
	.i_underflowS32			(isUnderflowS32),
	.v						({finalSum[44],finalSum[31:12]}),	// Sign + 16 bit (27:12)
	
	.isUnderOrOverflow		(isUO_OTZ),
	.clampOut				(otzValue),			// 0..FFFFh

	.isUnderOrOverflowIR0	(isUO_IR0),
	.clampOutIR0			(IR0Value)			// 0..1000h (!!! Not FFFh !!!)
);

wire [15:0] xyValue;
wire isXY_UOFlow;
FlagClipXY FlagClipXY_inst(
	.v					({finalSum[44],finalSum[31:16]}), 		// 11 bit (27:16)
	.i_overflowS32		(isOverflowS32),
	.i_underflowS32		(isUnderflowS32),
	
	.isUnderOrOverflow	(isXY_UOFlow),
	.clampOut			(xyValue)			// -400h..+3ffh as 16 bit.
);

wire [7:0] colorPostClip;
wire [15:0] IRnPostClip;
wire ou_IRn;
wire ou_Color;

wire useLM = i_computeCtrl.isIRnCheckUseLM & i_instrParam.lm;

FlagClipIRnColor FlagClipIRnColor_Inst(
	.i_v44			(finalSum),
	.i_sf			(useSFWrite32),
	.i_LM			(useLM),
	.i_useFixedSFLM	(i_computeCtrl.lmFalseForIR3Saturation),
	
	.o_OU_IRn		(ou_IRn),
	.o_OU_Color		(ou_Color),
	
	.clampOut		(IRnPostClip),
	.clampOutCol	(colorPostClip)
);

wire useSFWrite32     = i_instrParam.sf & i_computeCtrl.useSFWrite32;

wire [31:0] valWriteBack32 = useSFWrite32 ? finalSum[43:12] : finalSum[31:0];

wire overFlow44       = (( isOverflowS44[3] & i_computeCtrl.check44Global) || (( |isOverflowS44[2:0]) & i_computeCtrl.check44Local));
wire underFlow44      = ((isUnderflowS44[3] & i_computeCtrl.check44Global) || ((|isUnderflowS44[2:0]) & i_computeCtrl.check44Local));

wire writeFlag30      = (i_computeCtrl.maskID == 2'd1) && overFlow44;
wire writeFlag29      = (i_computeCtrl.maskID == 2'd2) && overFlow44;
wire writeFlag28      = (i_computeCtrl.maskID == 2'd3) && overFlow44;
wire writeFlag27      = (i_computeCtrl.maskID == 2'd1) && underFlow44;
wire writeFlag26      = (i_computeCtrl.maskID == 2'd2) && underFlow44;
wire writeFlag25      = (i_computeCtrl.maskID == 2'd3) && underFlow44;
wire writeFlag24      = (i_computeCtrl.maskID == 2'd1) && i_computeCtrl.checkIRn   && ou_IRn;
wire writeFlag23      = (i_computeCtrl.maskID == 2'd2) && i_computeCtrl.checkIRn   && ou_IRn;
wire writeFlag22      = (i_computeCtrl.maskID == 2'd3) && i_computeCtrl.checkIRn   && ou_IRn;
wire writeFlag21      = (i_computeCtrl.maskID == 2'd1) && i_computeCtrl.checkColor && ou_Color;
wire writeFlag20      = (i_computeCtrl.maskID == 2'd2) && i_computeCtrl.checkColor && ou_Color;
wire writeFlag19      = (i_computeCtrl.maskID == 2'd3) && i_computeCtrl.checkColor && ou_Color;

wire writeFlag18      = (      isUO_OTZ & i_computeCtrl.checkOTZ);
wire writeFlag17      =     divOverflow & i_computeCtrl.checkDIV ;
wire writeFlag16      = (isOverflowS32  & i_computeCtrl.check32Global);
wire writeFlag15      = (isUnderflowS32 & i_computeCtrl.check32Global);
wire writeFlag14      = (   isXY_UOFlow & i_computeCtrl.checkXY & (!i_computeCtrl.X0_or_Y1)); // X Selected.
wire writeFlag13      = (   isXY_UOFlow & i_computeCtrl.checkXY & ( i_computeCtrl.X0_or_Y1)); // Y Selected.
wire writeFlag12      = (      isUO_IR0 & i_computeCtrl.checkIR0);

// -------------------------------------------------------------------------------
assign o_RegCtrl.updateFlags =	{
	writeFlag30,
	writeFlag29,
	writeFlag28,
	writeFlag27,
	writeFlag26,
	writeFlag25,
	writeFlag24,
	writeFlag23,
	writeFlag22,
	writeFlag21,
	writeFlag20,
	writeFlag19,
	writeFlag18,
	writeFlag17,
	writeFlag16,
	writeFlag15,
	writeFlag14,
	writeFlag13,
	writeFlag12
};

/*
	Generic write back :
	MAC0    Hard coded (can use same MAC1?)
	MAC1..3 same unit.
	IR 1..3 except that IR3 is Z in RTCP (Different path) => Same CLIP unit, with just different setup.
	IR0     Hard coded clip
	X/Y     Hard coded clip
	Color   Hard coded clip
 */
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
assign o_RegCtrl.MAC0  = finalSum[31:0];
assign o_RegCtrl.MAC13 = valWriteBack32;
assign o_RegCtrl.colV  = colorPostClip;
assign o_RegCtrl.OTZV  = otzValue;
assign o_RegCtrl.XYV   = xyValue; // TODO : also for Z ? 
assign o_RegCtrl.IR0   = IR0Value;
assign o_RegCtrl.IR13  = IRnPostClip;

always @(posedge i_clk) begin
	if (i_computeCtrl.assignIRtoTMP) begin
		TMP1 = i_registers.IR1;
		TMP2 = i_registers.IR2;
		TMP3 = i_registers.IR3;
	end
	if (i_computeCtrl.wrTMP1)   begin TMP1 = IRnPostClip; end
	if (i_computeCtrl.wrTMP2)   begin TMP2 = IRnPostClip; end
	if (i_computeCtrl.wrTMP3)   begin TMP3 = IRnPostClip; end
//	if (i_computeCtrl.wrDivRes) begin divResREG = divRes; end NOT USED ANYMORE, BUT WANT TO KEEP ROM SIGNAL FOR NOW [TODO CLEAN AFTER DEBUG]
	if (i_computeCtrl.storeFull) begin tempSumREG = (~finalSum + 45'd1); end // Negative value. TODO OPTIMIZE : Move to NEG post REG ?
end

endmodule
