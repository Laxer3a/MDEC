module CLUT_Cache(
	input			clk,
	input			i_nrst,
	
	input [14:0]	CLUT_ID,
	input 			resetCache,
	
	// Forced to do 8x32 bit cache line fill when CLUT lookup empty. (16 colors)
	// --> Simplify for 4 bit texture. 1 Load
	input			write,
	input [2:0]		writeIdxInBlk,
	input [31:0]	ColorIn,

	input			requ1,
	input [7:0]		readIdx1,
	output			isHit1,		// One cycle sooner than colorEntry1 output. (same time as READ)
	output			isMiss1,
	output [15:0]	colorEntry1,
	
	input			requ2,
	input [7:0]		readIdx2,
	output			isHit2,		// One cycle sooner than colorEntry2 output. (same time as READ)
	output			isMiss2,
	output [15:0]	colorEntry2
);

	// 128x2 Colors.
	reg [31:0] CLUTStorage[127:0];
	reg [15:0] Loaded;
	reg [ 7:0] pRaddrA;
	reg [ 7:0] pRaddrB;
	
	// Memory manager solve 1 before 2.
	wire [3:0] blocIdx = isHit1 ? /*1 Is working = use 2*/ readIdx2[7:4] : readIdx1[7:4];
	wire [6:0] writeIdx = {blocIdx,writeIdxInBlk};
	// Detect change of clut.
	wire clearCacheInternal = (CLUT_ID != CLUT_Internal);
	reg [14:0] CLUT_Internal;
	always @ (posedge clk)
	begin
		CLUT_Internal = CLUT_ID;
	end
	
	always @ (posedge clk)
	begin
		if (write /*|| (pUpdate & !pAdressIn[3])*/) // Low 32 bit.
		begin
			CLUTStorage[writeIdx] = ColorIn;
		end
		pRaddrA	= readIdx1;
		pRaddrB	= readIdx2;
		
		if ((i_nrst == 0) | clearCacheInternal | resetCache) begin
			Loaded[ 0] = 1'b0;
			Loaded[ 1] = 1'b0;
			Loaded[ 2] = 1'b0;
			Loaded[ 3] = 1'b0;
			Loaded[ 4] = 1'b0;
			Loaded[ 5] = 1'b0;
			Loaded[ 6] = 1'b0;
			Loaded[ 7] = 1'b0;
			Loaded[ 8] = 1'b0;
			Loaded[ 9] = 1'b0;
			Loaded[10] = 1'b0;
			Loaded[11] = 1'b0;
			Loaded[12] = 1'b0;
			Loaded[13] = 1'b0;
			Loaded[14] = 1'b0;
			Loaded[15] = 1'b0;
		end else begin
			if (write) begin
				// When we load in cache, we will write 8 32bit word. (16 colors)
				// It will be guaranteed by the state machine.
				// So we just rewrite the LOADED flag 8 times.
				case (blocIdx)
				4'd0  : Loaded[ 0] = 1'b1;
				4'd1  : Loaded[ 1] = 1'b1;
				4'd2  : Loaded[ 2] = 1'b1;
				4'd3  : Loaded[ 3] = 1'b1;
				4'd4  : Loaded[ 4] = 1'b1;
				4'd5  : Loaded[ 5] = 1'b1;
				4'd6  : Loaded[ 6] = 1'b1;
				4'd7  : Loaded[ 7] = 1'b1;
				4'd8  : Loaded[ 8] = 1'b1;
				4'd9  : Loaded[ 9] = 1'b1;
				4'd10 : Loaded[10] = 1'b1;
				4'd11 : Loaded[11] = 1'b1;
				4'd12 : Loaded[12] = 1'b1;
				4'd13 : Loaded[13] = 1'b1;
				4'd14 : Loaded[14] = 1'b1;
				4'd15 : Loaded[15] = 1'b1;
				endcase
			end
		end
	end
	
	wire cached1		= Loaded[readIdx1[7:4]];
	wire cached2		= Loaded[readIdx2[7:4]];
	assign isHit1		= cached1 & requ1;
	assign isMiss1		= !cached1 & requ1;
	assign isHit2		= cached2 & requ2;
	assign isMiss2		= !cached2 & requ2;
	
	wire [31:0] vA		= CLUTStorage[pRaddrA[7:1]];
	wire [31:0] vB		= CLUTStorage[pRaddrB[7:1]];
	assign colorEntry1	= pRaddrA[0] ? vA[31:16] : vA[15:0];
	assign colorEntry2	= pRaddrB[0] ? vB[31:16] : vB[15:0];
endmodule
