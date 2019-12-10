/*
// Cycle 0
input 	valid_c0,
input   pause,
// Cycle 1
output	missT_c1,		// False if not textured (no read, no miss). False if data in T$. True if REAL T$ cache miss only.
output	missC_c1,		// False if true color or not textured. False if palette and in cache, True if Textured+Palette+Not in C$ only.
output  valid_c1,		// Needed ?
// Cycle 2
output  valid_c2,		// Pixel valid outside of pipeline.
						// Write to the buffer.
output  newBuffer,		// --> Force Flush of old buffer before write (PAUSE pipeline)
*/

// pause = missT_c1 | missC_c1 | oBGCacheLine		<-- Stop pipeline when texture Miss, cache miss or need to flush the cache line first.
module GPUPipeCtrl2(
	input	clk,
	input	i_nrst,
	
	
	// --- Value, Fixed per primitive ---
	input	 [1:0]	GPU_REG_TexFormat,
	input	[14:0]	GPU_REG_CLUT,
	input			GPU_TEX_DISABLE,
	
	// --- ALL STAGES : Just STOP ---
	input			pause,
	input			resetLineFlag,
	
	// --- Stage 0 Input ---
	// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
	input [1:0]		iPixelStateSpike, // Beginning of a new primitive.
	input [9:0] 	iScrX,
	input [8:0] 	iScrY,
	input [8:0]		iR,
	input [8:0]		iG,
	input [8:0]		iB,
	input			iBGMSK,
	input			validPixel_c0,
	input  [1:0]	UCoordLSB,
	input [18:0] 	texelAdress_c0,

	// --- Stage 1 Output Control ---
	output			missT_c1,			// TRUE garantee it is about VALID pixel/request.
	output			missC_c1,			// TRUE garantee it is about VALID pixel/request.
	output			validPixel_c1,
	output			pixelInFlight,
	
	// --- Stage 2 Write back Control ---
	output	[1:0]	oPixelStateSpike,
	output			oValidPixel,
	output [ 9:0]	oScrx,
	output [ 8:0]	oScry,
	output [15:0]	oTexel,
	output 			oTransparent,
	output			oBGMSK,
	output  [8:0]	oR,
	output  [8:0]	oG,
	output  [8:0]	oB,

	// --------------------------------------------
	//  Memory Side
	// --------------------------------------------

	// --- Tex$ Side ---
	output			requDataTex_c0,
	output [18:0]	adrTexReq_c0,
	input			TexHit_c1,
	input			TexMiss_c1,
	input  [15:0]	dataTex_c1,
	
	// Request Cache Fill
	output          requTexCacheUpdate_c1,
	output [16:0]   adrTexCacheUpdate_c0,
	input           updateTexCacheComplete,
	
	// Clut$ Side
	output			requDataClut_c1,
	output [7:0]	indexPal,	// Temp
	input			ClutHit_c1,			// 0 Latency between requ and Hit.
	input			ClutMiss_c1,
	input  [15:0]	dataClut_c2,
	
	// Request Cache Fill
	output          requClutCacheUpdate,
	output [14:0]   adrClutCacheUpdate,
	input           updateClutCacheComplete
);
	wire selPauseTex 	= pause & missT_c1;
	wire selPauseClut	= pause & missC_c1;
	
	// -------------------------------------------------------------
	// ---        Stage C0 
	// -------------------------------------------------------------
	
	wire isTrueColor			= (GPU_REG_TexFormat == 2'd2);
	// VALID PIXEL AND TEXTURED.
	wire isTexturedPixel_c0 	= validPixel_c0 & !GPU_TEX_DISABLE;

	// REQUEST TO TEX$ : VALID PIXEL TEXTURED
	assign	requDataTex_c0		= (isTexturedPixel_c0 | missT_c1/* & (!loadingText) & (!requestMissTexture_c1) */) /*| endRequestMissTexture*/; // Note : (!requestMissTexture) not necessary, but makes signal clearer (requ last 1 cycle instead of 2 in case of MISS)
	assign	adrTexReq_c0		= selPauseTex ? PtexelAdress_c1 : texelAdress_c0;
	
	// -------------------------------------------------------------
	// ---        Stage C1
	// -------------------------------------------------------------
	reg			PisTexturedPixel_c1;
	reg 		PisTrueColor_c1;
	reg	[1:0]	PpixelStateSpike_c1;
	reg [9:0] 	PiScrX_c1;
	reg [8:0] 	PiScrY_c1;
	reg [8:0]	PiR_c1;
	reg [8:0]	PiG_c1;
	reg [8:0]	PiB_c1;
	reg			PiBGMSK;
	reg			PValidPixel_c1;
	reg [1:0]	PUCoordLSB_c1;
	reg [18:0] 	PtexelAdress_c1;
	
	// [Convert Texture Data Into palette index (Logic)]
	wire [7:0] index_c1;
	TEXToIndex TEXToIndex_inst(
		// In
		.GPU_REG_TexFormat	(GPU_REG_TexFormat),
		.dataIn				(dataTex_c1),
		.UCoordLSB			(PUCoordLSB_c1),
		// Out
		.indexLookup		(index_c1)
	);
	
	// REQUEST TO CLU$ : VALID PIXEL TEXTURED AND TEX$ HIT AND PALETTE BASED.
	wire    isClutPixel_c1		= PisTexturedPixel_c1 & (!PisTrueColor_c1);
	assign	requDataClut_c1		= ((TexHit_c1     & isClutPixel_c1) /* & (!loadingClut)*/)  /* | endRequestMissClut */;

	// ----------------------------------------------------------------
	// [Lookup palette using selector.]
	assign	indexPal			= /*selPauseClut ? PPindex_c2 :*/ index_c1;   // TODO CIRCULAR ISSUE
	// [Compute Index of Block and adress if Clut$ miss]
	/*	FULL PALETTE DECODING
		-------------------------------
		YYYY.YYYY.Y___.____.____  <-- ignore LSB we count in HALF-WORD			Y = 512 lines of 2048 bytes
		____.____._XXX.XXX_.____												X = Multiple of 32 bytes (16 half word)
		____.____.___I.IIII.III_												I = Index palette 0..255
		
		=> wire [9:0] colIndex = { 2'b0, index } + { GPU_REG_CLUT[5:0] , 5'b0 }; 

		CACHE LINE UPDATE Multiple of 16 colors, 32 bytes.
		-------------------------------
		YYYY.YYYY.Y___.____.____  
		____.____._XXX.XXX_.____
		____.____.___I.III_.____  <-- Cache line is 32 bytes. */
	wire [5:0] colIndex_c1		= { 2'b0, indexPal[7:4] } + GPU_REG_CLUT[5:0];
	assign requClutCacheUpdate	= ClutMiss_c1;
	assign adrClutCacheUpdate	= { GPU_REG_CLUT[14:6] , colIndex_c1 }; // Cache line is 32 byte. ==> 16 Colors.
	// ----------------------------------------------------------------
	
	// Assign to user control outside
	assign	missT_c1		= TexMiss_c1;
	assign	missC_c1		= ClutMiss_c1;
	assign	validPixel_c1	= PValidPixel_c1;
	
	assign requTexCacheUpdate_c1	= TexMiss_c1;
	assign adrTexCacheUpdate_c0		= PtexelAdress_c1[18:2];
	
	// -------------------------------------------------------------
	// ---        Stage C2
	// -------------------------------------------------------------
	reg			PPisTexturedPixel_c2;
	reg 		PPisTrueColor_c2;
	reg	[1:0]	PPpixelStateSpike_c2;
	reg [9:0] 	PPiScrX_c2;
	reg [8:0] 	PPiScrY_c2;
	reg [8:0]	PPiR_c2;
	reg [8:0]	PPiG_c2;
	reg [8:0]	PPiB_c2;
	reg			PPiBGMSK;
	reg			PPValidPixel_c2;
	reg [15:0]	PPdataTex_c2;
	always @ (posedge clk)
	begin
		// FUCK VERILOG FOR ORDERING !!!!
		// I DID TWO SEPERATE BLOCK AND ENDED UP WITH UNPIPELINED FUCKING WORK...
		//
		// HOW CAN A->B->C not be pipelined where you have TWO FUCKING SEPERATE PROCESS WITH A->B and B->C CLOCKED !!!!
		//
		// ENDED UP WITH PUTTING EVERYTHING IN ONE BLOCK IN CORRECT ORDER.
		// BUT THIS IF STAYED AT THE END. FUCK YOU VERILOG. FUCK YOU FUCK YOU FUCK YOU !!!!
		//
		if (!pause | resetLineFlag | (i_nrst == 0)) begin
			PPpixelStateSpike_c2	<= ((i_nrst==0) | resetLineFlag) ? 2'b00 : PpixelStateSpike_c1;	// Reset to ZERO if resetLineFlag
		end
		
		if (!pause || (i_nrst==0)) begin
			PPisTexturedPixel_c2 = PisTexturedPixel_c1;
			PPisTrueColor_c2	= PisTrueColor_c1;
			PPiScrX_c2			= PiScrX_c1;
			PPiScrY_c2			= PiScrY_c1;
			PPiR_c2				= PiR_c1;
			PPiG_c2				= PiG_c1;
			PPiB_c2				= PiB_c1;
			PPiBGMSK			= PiBGMSK;
			PPValidPixel_c2		= (i_nrst==0) ? 1'b0 : PValidPixel_c1;
			PPdataTex_c2		= dataTex_c1;

			PisTrueColor_c1		= isTrueColor;
			PpixelStateSpike_c1	= (i_nrst==0) ? 2'b00 : iPixelStateSpike; // Beginning of a new primitive.
			PiScrX_c1			= iScrX;
			PiScrY_c1			= iScrY;
			PiR_c1				= iR;
			PiG_c1				= iG;
			PiB_c1				= iB;
			PiBGMSK				= iBGMSK;
			PValidPixel_c1		= (i_nrst==0) ? 1'b0 : validPixel_c0;
			PUCoordLSB_c1		= UCoordLSB;
			PisTexturedPixel_c1	= (i_nrst==0) ? 1'b0 : isTexturedPixel_c0;
			PtexelAdress_c1		= texelAdress_c0;
		end
	end
	
	// ----------------------------------------------------------
	//   Texture Color Value out
	// ----------------------------------------------------------
	reg [15:0] pixelOut;
	always @(*) begin
		if (PPisTexturedPixel_c2) begin
			if (PPisTrueColor_c2) begin
				pixelOut = PPdataTex_c2;
			end else begin
				pixelOut = dataClut_c2;
			end
		end else begin
			pixelOut = 16'h7FFF;
		end
	end

	assign pixelInFlight	= PPValidPixel_c2 | PValidPixel_c1;
	assign oPixelStateSpike	= PPpixelStateSpike_c2;
	assign oTransparent		= (!(|pixelOut[14:0])) & (!GPU_TEX_DISABLE); // If all ZERO, then 1., SET TO 0 if TEXTURE DISABLED.
	assign oTexel			= pixelOut;
	assign oValidPixel		= PPValidPixel_c2;
	assign oScrx			= PPiScrX_c2;
	assign oScry			= PPiScrY_c2;
	assign oR 				= PPiR_c2;
	assign oG 				= PPiG_c2;
	assign oB 				= PPiB_c2;
	assign oBGMSK			= PPiBGMSK;
endmodule
