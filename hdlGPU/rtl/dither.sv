/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/* Validated by Verilator testdither.cpp */
module dither(
	input [7:0] rIn,
	input [7:0] gIn,
	input [7:0] bIn,
	input       ditherOn,
	input [1:0] xBuff,
	input [1:0] yBuff,
	output [4:0] r,
	output [4:0] g,
	output [4:0] b
);

	reg signed [2:0] offset;
	always @(*)
	begin
		case ({ yBuff[0] , xBuff[1] ^ yBuff[1], xBuff[0] })
		3'h0 : offset = -3'd4;
		3'h1 : offset =  3'd0;
		3'h2 : offset = -3'd3;
		3'h3 : offset =  3'd1;
		3'h4 : offset =  3'd2;
		3'h5 : offset = -3'd2;
		3'h6 : offset =  3'd3;
		3'h7 : offset = -3'd1;
		/* No need for full {yBuff,xBuff} 4x4 matrix.
		4'h8 : offset = -3'd3;
		4'h9 : offset =  3'd1;
		4'hA : offset = -3'd4;
		4'hB : offset =  3'd0;
		4'hC : offset =  3'd3;
		4'hD : offset = -3'd1;
		4'hE : offset =  3'd2;
		4'hF : offset = -3'd2;
		*/
		endcase
	end

	// Enable or not dithering (add 0 if not)
	wire signed [2:0] postOffset = ditherOn ? offset : 3'd0;
	// Extend to 9 bit
	wire [9:0] off9 = { {7{postOffset[2]}}, postOffset };
	// Perform 
	wire [9:0] rsum = { 2'b0 , rIn } + off9;
	wire [9:0] gsum = { 2'b0 , gIn } + off9;
	wire [9:0] bsum = { 2'b0 , bIn } + off9;

	wire [7:0] rclamp;
	wire [7:0] gclamp;
	wire [7:0] bclamp;
	
	clampSPositive #(.INW(10),.OUTW(8)) clampSPositive_R(.valueIn(rsum),.valueOut(rclamp));
	clampSPositive #(.INW(10),.OUTW(8)) clampSPositive_G(.valueIn(gsum),.valueOut(gclamp));
	clampSPositive #(.INW(10),.OUTW(8)) clampSPositive_B(.valueIn(bsum),.valueOut(bclamp));
	
	assign r = rclamp[7:3];
	assign g = gclamp[7:3];
	assign b = bclamp[7:3];
endmodule
