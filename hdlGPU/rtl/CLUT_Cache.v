module CLUT_Cache(
	input			clk,
	input			i_nrst,
	
	input [15:0]	CLUT_ID,
	
	// Forced to do 8x32 bit cache line fill when CLUT lookup empty. (16 colors)
	// --> Simplify for 4 bit texture. 1 Load
	input				write,
	input [6:0]		writeIdx,
	input [31:0]	ColorIn,

	input [7:0]		readIdx1,
	output			isHit1,		// One cycle sooner than colorEntry1 output. (same time as READ)
	output [15:0]	colorEntry1,
	
	input [7:0]		readIdx2,
	output			isHit2,		// One cycle sooner than colorEntry2 output. (same time as READ)
	output [15:0]	colorEntry2
);

	// 128x2 Colors.
	reg [31:0] CLUTStorage[127:0];
	reg [15:0] Loaded;
	reg [ 7:0] pRaddrA;
	reg [ 7:0] pRaddrB;

	// Detect change of clut.
	wire clearCache = (CLUT_ID != CLUT_Internal);
	reg [15:0] CLUT_Internal;
	always @ (posedge clk)
	begin
		CLUT_Internal <= CLUT_ID;
	end
	
	always @ (posedge clk)
	begin
		if (write /*|| (pUpdate & !pAdressIn[3])*/) // Low 32 bit.
		begin
			CLUTStorage[writeIdx] <= ColorIn;
		end
		pRaddrA	<= readIdx1;
		pRaddrB	<= readIdx2;
		
		if ((i_nrst == 0) | clearCache) begin
			Loaded[ 0] <= 1'b0;
			Loaded[ 1] <= 1'b0;
			Loaded[ 2] <= 1'b0;
			Loaded[ 3] <= 1'b0;
			Loaded[ 4] <= 1'b0;
			Loaded[ 5] <= 1'b0;
			Loaded[ 6] <= 1'b0;
			Loaded[ 7] <= 1'b0;
			Loaded[ 8] <= 1'b0;
			Loaded[ 9] <= 1'b0;
			Loaded[10] <= 1'b0;
			Loaded[11] <= 1'b0;
			Loaded[12] <= 1'b0;
			Loaded[13] <= 1'b0;
			Loaded[14] <= 1'b0;
			Loaded[15] <= 1'b0;
		end else begin
			if (write) begin
				// When we load in cache, we will write 8 32bit word. (16 colors)
				// It will be guaranteed by the state machine.
				// So we just rewrite the LOADED flag 8 times.
				case (writeIdx[6:3])
				4'd0  : Loaded[ 0] <= 1'b1;
				4'd1  : Loaded[ 1] <= 1'b1;
				4'd2  : Loaded[ 2] <= 1'b1;
				4'd3  : Loaded[ 3] <= 1'b1;
				4'd4  : Loaded[ 4] <= 1'b1;
				4'd5  : Loaded[ 5] <= 1'b1;
				4'd6  : Loaded[ 6] <= 1'b1;
				4'd7  : Loaded[ 7] <= 1'b1;
				4'd8  : Loaded[ 8] <= 1'b1;
				4'd9  : Loaded[ 9] <= 1'b1;
				4'd10 : Loaded[10] <= 1'b1;
				4'd11 : Loaded[11] <= 1'b1;
				4'd12 : Loaded[12] <= 1'b1;
				4'd13 : Loaded[13] <= 1'b1;
				4'd14 : Loaded[14] <= 1'b1;
				4'd15 : Loaded[15] <= 1'b1;
				endcase
			end
		end
	end
	
	assign isHit1		= Loaded[readIdx1[7:4]];
	assign isHit2		= Loaded[readIdx2[7:4]];
	wire [31:0] vA		= CLUTStorage[pRaddrA[7:1]];
	wire [31:0] vB		= CLUTStorage[pRaddrB[7:1]];
	assign colorEntry1	= pRaddrA[0] ? vA[31:16] : vA[15:0];
	assign colorEntry2	= pRaddrB[0] ? vB[31:16] : vB[15:0];
endmodule
