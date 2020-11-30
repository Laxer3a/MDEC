module CLUT_Cache(
	input			i_clk,
	input			i_nrst,
	
	// Forced to do 8x32 bit cache line fill when CLUT lookup empty. (16 colors)
	// --> Simplify for 4 bit texture. 1 Load
	input			i_write,
	input [3:0]		i_writeBlockIndex,
	input [2:0]		i_writeIdxInBlk,
	input [31:0]	i_Colors,

	input 	[7:0]	i_readIdxL,
	output [15:0]	o_colorEntryL,
	
	input  	[7:0]	i_readIdxR,
	output [15:0]	o_colorEntryR
);
	reg [31:0] CLUTStorage[127:0];	// 128x2 Colors.
	reg [ 7:0] pRaddrL;
	reg [ 7:0] pRaddrR;
	wire [6:0] writeIdx = {i_writeBlockIndex,i_writeIdxInBlk};	
	
	always @ (posedge i_clk)
	begin
		if (i_write) // Low 32 bit.
		begin
			CLUTStorage[writeIdx] <= i_Colors;
		end
		pRaddrL	<= i_readIdxL;
		pRaddrR	<= i_readIdxR;
	end
	
	wire [31:0] vL			= CLUTStorage[pRaddrL[7:1]];
	wire [31:0] vR			= CLUTStorage[pRaddrR[7:1]];

	assign o_colorEntryL	= pRaddrL[0] ? vL[31:16] : vL[15:0];
	assign o_colorEntryR	= pRaddrR[0] ? vR[31:16] : vR[15:0];
endmodule
