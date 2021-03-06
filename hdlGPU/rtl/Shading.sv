/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module Shading(
	input	[4:0] rTex,
	input	[4:0] gTex,
	input	[4:0] bTex,
	input		  noTexture,
	
	input   [7:0] rGouraud,
	input   [7:0] gGouraud,
	input   [7:0] bGouraud,
	
	output  [7:0] rOut,
	output  [7:0] gOut,
	output  [7:0] bOut
);

/*
	// ----------------------------------
	// All unsigned math...
	// ----------------------------------

	// Texture between 0..31, 31 as 1.0
	// if no texture -> white. (OR Stage)
	wire [4:0] orSt = {5{noTexture}};
	wire [4:0] tR =  rTex | orSt;
	wire [4:0] tG =  gTex | orSt;
	wire [4:0] tB =  bTex | orSt;

	// Gouraud between 0..511 (0.0 -> 1.99) with 256=1.0
	// Result is [12:5] clamped.
	// [13:0] is 9.5 fixed point format.
	// [13:5] is 9.0 fixed point format. (+511..0)
	// [12:5] is 8.0 clamp result.
	wire [13:0] mR = rGouraud * tR;
	wire [13:0] mG = gGouraud * tG;
	wire [13:0] mB = bGouraud * tB;

	clampUPositive #(.INW(9),.OUTW(8)) ClampPosR(.valueIn(mR[13:5]),.valueOut(rOut));
	clampUPositive #(.INW(9),.OUTW(8)) ClampPosG(.valueIn(mG[13:5]),.valueOut(gOut));
	clampUPositive #(.INW(9),.OUTW(8)) ClampPosB(.valueIn(mB[13:5]),.valueOut(bOut));
*/

	// ----------------------------------
	// All unsigned math...
	// ----------------------------------

	// Texture between 0..31, 31 as 1.0
	wire [4:0] tR = rTex;
	wire [4:0] tG = gTex;
	wire [4:0] tB = bTex;

	// Gouraud between 0..510, RAW=255 (510)
	wire [13:0] mR = { rGouraud, 1'b0 } * tR;
	wire [13:0] mG = { gGouraud, 1'b0 } * tG;
	wire [13:0] mB = { bGouraud, 1'b0 } * tB;
	
	wire [7:0]  mROut,mGOut,mBOut;

	// >> 5, clamp max 255.
	clampUPositive #(.INW(9),.OUTW(8)) ClampPosR(.valueIn(mR[13:5]),.valueOut(mROut));
	clampUPositive #(.INW(9),.OUTW(8)) ClampPosG(.valueIn(mG[13:5]),.valueOut(mGOut));
	clampUPositive #(.INW(9),.OUTW(8)) ClampPosB(.valueIn(mB[13:5]),.valueOut(mBOut));

	assign rOut = noTexture ? rGouraud : mROut; // No shift happened, no pb.
	assign gOut = noTexture ? gGouraud : mGOut; // No shift happened, no pb.
	assign bOut = noTexture ? bGouraud : mBOut; // No shift happened, no pb.
endmodule
