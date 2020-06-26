// ----------------------------------------------------------------------------------------------
//   Compute Path
// ----------------------------------------------------------------------------------------------
`include "GTEDefine.hv"

module GTEComputePath(
    input                   i_clk,
    input                   i_nRst,

    input   CTRL            i_instrParam,
    input   gteComputeCtrl  i_computeCtrl,
    input   SgteREG         i_registers,
    output  gteCtrl         o_RegCtrl
);

reg [15:0] TMP1,TMP2,TMP3;


GTESelPath SelMuxUnit1 (
  .ctrl    (i_computeCtrl.sel1),

  .MAT0_C0 (i_registers.R11),
  .MAT1_C0 (i_registers.R21),
  .MAT2_C0 (i_registers.R31),
  .MAT0_C1 (i_registers.L11),
  .MAT1_C1 (i_registers.L21),
  .MAT2_C1 (i_registers.L31),
  .MAT0_C2 (i_registers.LR1),
  .MAT1_C2 (i_registers.LG1),
  .MAT2_C2 (i_registers.LB1),
  .color (i_registers.CRGB.r),
  .IRn (i_registers.IR1),
  .SZ (i_registers.SZ1),
  .V0c (i_registers.VX0),
  .V1c (i_registers.VX1),
  .V2c (i_registers.VX2),
  .tmpReg (TMP1),
  .Col_C0 (i_registers.CRGB0.r),
  .Col_C1 (i_registers.CRGB1.r),
  .Col_C2 (i_registers.CRGB2.r),
  .Z3 (i_registers.ZSF3),
  .Z4 (i_registers.ZSF4),
  .IR0 (i_registers.IR0),
);


GTESelPath SelMuxUnit2 (
  .ctrl    (i_computeCtrl.sel2),

  .MAT0_C0 (i_registers.R12),
  .MAT1_C0 (i_registers.R22),
  .MAT2_C0 (i_registers.R32),
  .MAT0_C1 (i_registers.L12),
  .MAT1_C1 (i_registers.L22),
  .MAT2_C1 (i_registers.L32),
  .MAT0_C2 (i_registers.LR2),
  .MAT1_C2 (i_registers.LG2),
  .MAT2_C2 (i_registers.LB2),
  .color (i_registers.CRGB.g),
  .IRn (i_registers.IR2),
  .SZ (i_registers.SZ2),
  .V0c (i_registers.VY0),
  .V1c (i_registers.VY1),
  .V2c (i_registers.VY2),
  .tmpReg (TMP2),
  .Col_C0 (i_registers.CRGB0.g),
  .Col_C1 (i_registers.CRGB1.g),
  .Col_C2 (i_registers.CRGB2.g),
  .Z3 (i_registers.ZSF3),
  .Z4 (i_registers.ZSF4),
  .IR0 (i_registers.IR0),
);


GTESelPath SelMuxUnit3 (
  .ctrl    (i_computeCtrl.sel3),

  .MAT0_C0 (i_registers.R13),
  .MAT1_C0 (i_registers.R23),
  .MAT2_C0 (i_registers.R33),
  .MAT0_C1 (i_registers.L13),
  .MAT1_C1 (i_registers.L23),
  .MAT2_C1 (i_registers.L33),
  .MAT0_C2 (i_registers.LR3),
  .MAT1_C2 (i_registers.LG3),
  .MAT2_C2 (i_registers.LB3),
  .color (i_registers.CRGB.b),
  .IRn (i_registers.IR3),
  .SZ (i_registers.SZ3),
  .V0c (i_registers.VZ0),
  .V1c (i_registers.VZ1),
  .V2c (i_registers.VZ2),
  .tmpReg (TMP3),
  .Col_C0 (i_registers.CRGB0.b),
  .Col_C1 (i_registers.CRGB1.b),
  .Col_C2 (i_registers.CRGB2.b),
  .Z3 (i_registers.ZSF3),
  .Z4 (i_registers.ZSF4),
  .IR0 (i_registers.IR0),
);

endmodule
