module CLUT_Cache(
	input			clk,
	input			i_nrst,
	
	input [14:0]	CLUT_ID,
	input			checkCLUT,
	output			needLoading,
	
	// Forced to do 8x32 bit cache line fill when CLUT lookup empty. (16 colors)
	// --> Simplify for 4 bit texture. 1 Load
	input			write,
	input [6:0]		writeIdx128,
	input [31:0]	ColorIn,

	input			requ1,
	input [7:0]		readIdx1,
	output [15:0]	colorEntry1,
	
	input			requ2,
	input [7:0]		readIdx2,
	output [15:0]	colorEntry2
);
	assign needLoading = clearCacheInternal;

	// 128x2 Colors.
	reg [31:0] CLUTStorage[127:0];
	reg [ 7:0] pRaddrA;
	reg [ 7:0] pRaddrB;
	
	// Detect change of clut.
	wire clearCacheInternal = (CLUT_ID != CLUT_Internal) && checkCLUT;
	reg [14:0] CLUT_Internal;
	always @ (posedge clk)
	begin
		if (checkCLUT) begin
			CLUT_Internal = CLUT_ID;
		end
	end
	
	always @ (posedge clk)
	begin
		if (write) // Low 32 bit.
		begin
			CLUTStorage[writeIdx128] = ColorIn;
		end
		pRaddrA	= readIdx1;
		pRaddrB	= readIdx2;
	end
	
	wire [31:0] vA		= CLUTStorage[pRaddrA[7:1]];
	wire [31:0] vB		= CLUTStorage[pRaddrB[7:1]];
	assign colorEntry1	= pRaddrA[0] ? vA[31:16] : vA[15:0];
	assign colorEntry2	= pRaddrB[0] ? vB[31:16] : vB[15:0];
endmodule
