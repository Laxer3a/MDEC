module CLUT_Cache(
	input			i_clk,
	input			i_nrst,
	
	input [14:0]	i_CLUT_ID,
	input			i_checkCLUT,
	output			o_needLoading,
	
	// Forced to do 8x32 bit cache line fill when CLUT lookup empty. (16 colors)
	// --> Simplify for 4 bit texture. 1 Load
	input			i_write,
	input [6:0]		i_writeIdx128,
	input [31:0]	i_Colors,

	input			i_requL,
	input [7:0]		i_readIdxL,
	output [15:0]	o_colorEntryL,
	
	input			i_requR,
	input [7:0]		i_readIdxR,
	output [15:0]	o_colorEntryR
);
	reg [14:0] CLUT_Internal;		// Cache Address of loaded CLUT
	reg [31:0] CLUTStorage[127:0];	// 128x2 Colors.
	reg [ 7:0] pRaddrL;
	reg [ 7:0] pRaddrR;
	
	// Detect change of clut.
	always @ (posedge i_clk)
	begin
		if (i_checkCLUT) begin
			CLUT_Internal = i_CLUT_ID;
		end
	end
	
	always @ (posedge i_clk)
	begin
		if (i_write) // Low 32 bit.
		begin
			CLUTStorage[i_writeIdx128] = i_Colors;
		end
		pRaddrL	= i_readIdxL;
		pRaddrR	= i_readIdxR;
	end
	
	wire [31:0] vL			= CLUTStorage[pRaddrL[7:1]];
	wire [31:0] vR			= CLUTStorage[pRaddrR[7:1]];

	assign o_colorEntryL	= pRaddrL[0] ? vL[31:16] : vL[15:0];
	assign o_colorEntryR	= pRaddrR[0] ? vR[31:16] : vR[15:0];
	assign o_needLoading	= (i_CLUT_ID != CLUT_Internal) && i_checkCLUT;
endmodule
