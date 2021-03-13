/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "GTEDefine.hv"

typedef enum bit[1:0] {
	R_MAT	= 2'd0,
	L_MAT	= 2'd1,
	C_MAT	= 2'd2,
	E_MAT	= 2'd3
} ESELMT;

typedef enum bit[2:0] {
	MAT_C0	= 3'd0,
	MAT_C1	= 3'd1,
	MAT_C2	= 3'd2,
	PLUS1_  = 3'd3,
	MINUS1  = 3'd4,
	ECOLOR  = 3'd5
} ELEFTSEL;

// ---- Unit 1..3 ----
// DPCS Step 1 : selLeft = NEG1FIXED, colSrc=3, selRight = color  OR  
//                        [ N/A               ] selRight = ZERO
// DPCS Step 2 : selLeft = IRn       [N/A     ] selRight = IR0 OR
//                        [ N/A               ] selRight = ZERO

module GTESelPath(
	input gteSelCtrl ctrl,
	
	input            isMVMVA,
	input  [1:0]     vec,
	input  [1:0]     mx,
	input			 WIDE,	// TODO SUPPORT
	
	// -----------------
	// --- LEFT SIDE ---
	// -----------------
	
//	input       signedLeft,
	
	input [ 7:0] color,
	input [15:0] IRn,
	// -----
	input [15:0] MAT0_C0,
	input [15:0] MAT0_C1,
	input [15:0] MAT0_C2,
	// -----
	input [15:0] MAT1_C0,
	input [15:0] MAT1_C1,
	input [15:0] MAT1_C2,
	// -----
	input [15:0] MAT2_C0,
	input [15:0] MAT2_C1,
	input [15:0] MAT2_C2,
	// -----
	input [15:0] MAT3_C0,
	input [15:0] MAT3_C1,
	input [15:0] MAT3_C2,
	// -----
	input [15:0] SZ,
	input [15:0] DQA,
	input [16:0] HS3Z,
	input [15:0] SX,
	
	// -----------------
	// --- RIGHT SIDE---
	// -----------------
	// --- Reuse i_color too here.
	input [15:0] Z3,
	input [15:0] Z4,
	input [15:0] IR0,
	input [15:0] tmpReg,
	input [15:0] V0c,
	input [15:0] V1c,
	input [15:0] V2c,
	input [15:0] SYA,
	input [15:0] SYB,
	
	// --- Reuse i_IRn
	output signed [34:0] outstuff
);
	reg [15:0] mc1,mc2,mc3;
	
	// TODO_WIDE : Change to [19:0]
	reg [17:0] vComp;
	
	wire [1:0] mat    = isMVMVA ? mx  : ctrl.mat;
	wire [1:0] vcompo = isMVMVA ? vec : ctrl.vcompo;
	
	always @(*) begin
		case (mat)
		2'd0   : mc1 = MAT0_C0; // S
		2'd1   : mc1 = MAT1_C0; // S
		2'd2   : mc1 = MAT2_C0; // S
		default: mc1 = MAT3_C0; // Weird matrix bug.
		endcase

		case (mat)
		2'd0   : mc2 = MAT0_C1;
		2'd1   : mc2 = MAT1_C1;
		2'd2   : mc2 = MAT2_C1;
		default: mc2 = MAT3_C1;
		endcase

		case (mat)
		2'd0   : mc3 = MAT0_C2;
		2'd1   : mc3 = MAT1_C2;
		2'd2   : mc3 = MAT2_C2;
		default: mc3 = MAT3_C2;
		endcase
		
		// TODO_WIDE : { , 00 } all values except HS3Z setup x3 or x4.
		case (vcompo)
		2'd0   : vComp = {{2{V0c[15]}}, V0c };  // S
		2'd1   : vComp = {{2{V1c[15]}}, V1c };  // S
		2'd2   : vComp = {{2{V2c[15]}}, V2c };  // S
		// U Unsigned 17 bit !!!! when not MVMVA, else IRn
		default: vComp = ((ctrl.vcompo == 2'd0) ? {{2{IRn[15]}}, IRn } : {{2{tmpReg[15]}}, tmpReg });
		endcase
	end

	reg signed [16:0] leftSide;
	wire [3:0] selLeft = ctrl.selLeft; // For verilator debug. Bad SV support.
	always @(*) begin
		case (selLeft)
		4'd0 :   leftSide = { mc1[15], mc1};		//   SIGNED
		4'd1 :   leftSide = { mc2[15], mc2};		//   SIGNED
		4'd2 :   leftSide = { mc3[15], mc3};		//   SIGNED
		4'd3 :   leftSide = { 5'd0, color, 4'd0 };	// UNSIGNED
		4'd4 :   leftSide = { IRn[15], IRn};		//   SIGNED
		4'd5 :   leftSide = { 1'b0, SZ };			// UNSIGNED
		4'd6 :   leftSide = { DQA[15], DQA};		//   SIGNED
		4'd7 :   leftSide = 17'd4096;             // DEFAULT 7
		4'd8 :   leftSide = { SX[15] , SX };		//   SIGNED
		default: leftSide = 17'd0;
		endcase
	end

	// TODO_WIDE : Change to 19:0 + { , 00 } all values except vComp
	reg signed [17:0] rightSide;
	wire [3:0] selRight = ctrl.selRight; // For verilator debug. Bad SV support.
	always @(*) begin
		case (selRight)
		4'd0 :   rightSide = vComp;
		4'd1 :   rightSide = {{2{tmpReg[15]}}, tmpReg };
		// Do not have more than 8 at this level, Z3,Z4,ZERO at higher mux.
		4'd2 :   rightSide = {{2{Z3[15]}}, Z3 };
		4'd3 :   rightSide = {{2{Z4[15]}}, Z4 };
		4'd4 :   rightSide = 18'd0; // ZERO.
		4'd5 :   rightSide = {{2{IRn[15]}},IRn};
		4'd6 :   rightSide = {{2{IR0[15]}},IR0};
		4'd7 :   rightSide = { 6'd0, color, 4'd0 };
		4'd8 :   rightSide = {{2{SYA[15]}}, SYA };
		4'd9 :   rightSide = {{2{SYB[15]}}, SYB };
		4'd10:	 rightSide = { 1'b0, HS3Z };
		default: rightSide = 18'd0;
		endcase
	end
	
	// TODO_WIDE : result[36:0]
	wire signed [34:0] result = rightSide * leftSide;

	// TODO_WIDE : result[36:2]
	assign outstuff = result;
endmodule
