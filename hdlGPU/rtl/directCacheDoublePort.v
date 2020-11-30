/*
	PS1 GPU Memory is 1MB => 1024x1024 Byte => 20 bit adress bus.
	
	Future possible optimization :
	- Larger 128 Bit Entry.
	- Swizzling
	- 2Way Cache / 4Way / 8way Cache
	
	- Use 512 Bit Active BRAM on posedge, read cache on negedge. => Work at same freq, allow 
 */

module directCacheDoublePort(
	input			i_clk,
	input			i_nrst,
	input			i_clearCache,
	
	// [Can spy all write on the bus and maintain cache integrity]
	input			i_textureFormatTrueColor,
	input			i_write,
//	input			update,		// If update 32 bit.
	input	[16:0]	i_adressIn,
	input	[63:0]	i_dataIn,		// Upper module responsability to make 64 bit atomic write.
	
	input			i_requLookupA,
	input	[18:0]	i_adressLookA,
	output	[15:0]	o_dataOutA,
	output			o_isHitA,
	output			o_isMissA,

	input			i_requLookupB,
	input	[18:0]	i_adressLookB,
	output	[15:0]	o_dataOutB,
	output			o_isHitB,
	output			o_isMissB
);
	reg stickyMissA, stickyMissB;
	
	// LINEAR MAPPING :
	// ccccPPPPPbbbbbLLL aaa <-- One line width for block in  16 bpp. (32 pixel   , 64 byte per line)
	// cccPPPPPPbbbbbbLL aaa <-- One line width for block in 8/4 bpp. (32/64 pixel, 32 byte per line)
	// wire [19:0] swizzleAddr = adressIn; // Straight
	
	// SWIZZLED MAPPING : remapped to IN THE cache as : (no need to swizzle outside, cache can implement it internally and just output 16 bit for an address read)
	// --------------------------
	// ccccbbbbb|PPPPPLLL aaa <-- One line width for block in  16 bpp. (32 pixel   , 64 byte per line)
	// cccbbbbbb|PPPPPPLL aaa <-- One line width for block in 8/4 bpp. (32/64 pixel, 32 byte per line)
	wire [16:0] swizzleAddr = i_textureFormatTrueColor 	? {    i_adressIn[16:13],   i_adressIn[7:3],    i_adressIn[12:8],   i_adressIn[2:0]}  // 4,5,5,3
														: {    i_adressIn[16:14],   i_adressIn[7:2],    i_adressIn[13:8],   i_adressIn[1:0]}; // 5,6,6,2
	wire [16:0] swizzleLookA= i_textureFormatTrueColor 	? { i_adressLookA[18:15],i_adressLookA[9:5],i_adressLookA[14:10],i_adressLookA[4:2]}  // 4,5,5,3
														: { i_adressLookA[18:16],i_adressLookA[9:4],i_adressLookA[15:10],i_adressLookA[3:2]}; // 5,6,6,2
	wire [16:0] swizzleLookB= i_textureFormatTrueColor 	? { i_adressLookB[18:15],i_adressLookB[9:5],i_adressLookB[14:10],i_adressLookB[4:2]}  // 4,5,5,3
														: { i_adressLookB[18:16],i_adressLookB[9:4],i_adressLookB[15:10],i_adressLookB[3:2]}; // 5,6,6,2

	// ------------- 4 KB Version ----------
	// [20:12][11:3][2:0]		512 Entries x 8 Byte (4x2) = 4 KB.
	//   9 bit 9bit  3bit
	// ------------- 2 KB Version ----------
	// [20:11][10:3][2:0]		256 Entries x 8 Byte (4x2) = 2 KB.
	//  10 bit 8bit  3bit
	reg [72:0]	RAMStorage[255:0];
	reg [255:0]	Active;
	reg [7:0]	pRaddrA,pRaddrB;

	reg [2:1]	pIndexA,pIndexB;
	reg [8:0]	pRTagA,pRTagB;
	
	always @ (posedge i_clk)
	begin
		if (i_write)
		begin
			RAMStorage[swizzleAddr[7:0]]	<= { swizzleAddr[16:8], i_dataIn[63: 0] };
		end
		
		pRaddrA	<= swizzleLookA[7:0];
		pRaddrB	<= swizzleLookB[7:0];
		pRTagA	<= swizzleLookA[16:8];
		pRTagB	<= swizzleLookB[16:8];
	end

	wire  [72:0]	D0A = RAMStorage[pRaddrA];	// Latency 1 (Pipelined address : RAM read)
	wire  [72:0]	D0B = RAMStorage[pRaddrB];

	wire       lookActiveA	= Active[pRaddrA];	// Latency 1 (Use pipelined adress to read register at same time as DOA)
	wire       lookActiveB	= Active[pRaddrB];
	reg 	   pRequLookupA;
	reg 	   pRequLookupB;
	wire [8:0] lookTagA	= D0A[72:64];
	wire [8:0] lookTagB	= D0B[72:64];
	
	wire [63:0] APixels	= D0A[63:0];
	wire [63:0] BPixels	= D0B[63:0];

	// Return HIT when NOT looking up for data...
	wire hitA       	= ((lookTagA == pRTagA) & lookActiveA);
	wire hitB			= ((lookTagB == pRTagB) & lookActiveB);
	wire spikeMissA 	= ((!hitA) & pRequLookupA);
	wire spikeMissB 	= ((!hitB) & pRequLookupB);

	assign o_isHitA		=   hitA   & pRequLookupA;
	assign o_isHitB		=   hitB   & pRequLookupB;
	assign o_isMissA	= spikeMissA | (stickyMissA & !hitA);	// Note : Sticky BIT does not RETURN 1 when isHit is generated.
	assign o_isMissB	= spikeMissB | (stickyMissB & !hitB);

	always @ (posedge i_clk)
	begin
		pRequLookupA = i_requLookupA;
		pRequLookupB = i_requLookupB;
		
		if (o_isHitA) begin
			stickyMissA <= 0;
		end else begin
			if (o_isMissA) begin
				stickyMissA <= 1;
			end
		end
		if (o_isHitB) begin
			stickyMissB <= 0;
		end else begin
			if (o_isMissB) begin
				stickyMissB <= 1;
			end
		end
	end
	
	reg [15:0] dOutA;
	always @(*) begin
	case (pIndexA)
	2'd0 : dOutA = APixels[15: 0];
	2'd1 : dOutA = APixels[31:16];
	2'd2 : dOutA = APixels[47:32];
	2'd3 : dOutA = APixels[63:48];
	endcase
	end
	assign o_dataOutA	= dOutA;
	
	reg [15:0] dOutB;
	always @(*) begin
	case (pIndexB)
	2'd0 : dOutB = BPixels[15: 0];
	2'd1 : dOutB = BPixels[31:16];
	2'd2 : dOutB = BPixels[47:32];
	2'd3 : dOutB = BPixels[63:48];
	endcase
	end
	assign o_dataOutB	= dOutB;
	
	always @ (posedge i_clk)
	begin
		if ((i_nrst == 0) | i_clearCache) begin
			Active <= 256'd0;
		end else begin
			if (i_write) begin
				Active[swizzleAddr[7:0]] <= 1'b1;
			end // End write
		end

		pIndexA	<= i_adressLookA[1:0];
		pIndexB	<= i_adressLookB[1:0];
	end
endmodule
