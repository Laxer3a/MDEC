/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module CLUT_Cache(
	input			i_clk,
	input			i_nrst,
	
	// Forced to do 8x32 bit cache line fill when CLUT lookup empty. (16 colors)
	// --> Simplify for 4 bit texture. 1 Load
	input			i_write,
	input   [3:0]	i_writeBlockIndex,
	input [255:0]	i_Colors,

	input 	[7:0]	i_readIdxL,
	output [15:0]	o_colorEntryL,
	
	input  	[7:0]	i_readIdxR,
	output [15:0]	o_colorEntryR
);
	reg [255:0] CLUTStorage[15:0];	// 16x16 Colors.
	reg [ 7:0] pRaddrL;
	reg [ 7:0] pRaddrR;
	
	always @ (posedge i_clk)
	begin
		if (i_write) // Low 32 bit.
		begin
			CLUTStorage[i_writeBlockIndex] <= i_Colors;
		end
		pRaddrL	<= i_readIdxL;
		pRaddrR	<= i_readIdxR;
	end
	
	wire [255:0] vL			= CLUTStorage[pRaddrL[7:4]];
	wire [255:0] vR			= CLUTStorage[pRaddrR[7:4]];


	reg [15:0] colorL;
	always @(*) begin
		case (pRaddrL[3:0])
		4'h0    : colorL = vL[ 15:  0];
		4'h1    : colorL = vL[ 31: 16];
		4'h2    : colorL = vL[ 47: 32];
		4'h3    : colorL = vL[ 63: 48];
		4'h4    : colorL = vL[ 79: 64];
		4'h5    : colorL = vL[ 95: 80];
		4'h6    : colorL = vL[111: 96];
		4'h7    : colorL = vL[127:112];
		4'h8    : colorL = vL[143:128];
		4'h9    : colorL = vL[159:144];
		4'hA    : colorL = vL[175:160];
		4'hB    : colorL = vL[191:176];
		4'hC    : colorL = vL[207:192];
		4'hD    : colorL = vL[223:208];
		4'hE    : colorL = vL[239:224];
		default : colorL = vL[255:240];
		endcase
	end

	reg [15:0] colorR;
	always @(*) begin
		case (pRaddrR[3:0])
		4'h0    : colorR = vR[ 15:  0];
		4'h1    : colorR = vR[ 31: 16];
		4'h2    : colorR = vR[ 47: 32];
		4'h3    : colorR = vR[ 63: 48];
		4'h4    : colorR = vR[ 79: 64];
		4'h5    : colorR = vR[ 95: 80];
		4'h6    : colorR = vR[111: 96];
		4'h7    : colorR = vR[127:112];
		4'h8    : colorR = vR[143:128];
		4'h9    : colorR = vR[159:144];
		4'hA    : colorR = vR[175:160];
		4'hB    : colorR = vR[191:176];
		4'hC    : colorR = vR[207:192];
		4'hD    : colorR = vR[223:208];
		4'hE    : colorR = vR[239:224];
		default : colorR = vR[255:240];
		endcase
	end
	
	assign o_colorEntryL	= colorL;
	assign o_colorEntryR	= colorR;
endmodule
