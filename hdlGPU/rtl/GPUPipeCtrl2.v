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
	input			GPU_TEX_DISABLE,
	
	// --- ALL STAGES : Just STOP ---
	input			pause,
	input			resetPipelinePixelStateSpike,
	
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
	output [7:0]	indexPal,	// Temp
	input  [15:0]	dataClut_c2
);
	reg [18:0] 	PtexelAdress_c1;
	
	// -------------------------------------------------------------
	// ---        Stage C0 
	// -------------------------------------------------------------
	
	wire isTrueColor			= GPU_REG_TexFormat[1];// Not == 2'd2.  2 and 3 considered both as TRUE COLOR.
	// VALID PIXEL AND TEXTURED.
	wire isTexturedPixel_c0 	= validPixel_c0 & !GPU_TEX_DISABLE;
	wire isPaletteTex			= isTexturedPixel_c0 & !isTrueColor;

	// REQUEST TO TEX$ : VALID PIXEL TEXTURED
	assign	requDataTex_c0		= (isTexturedPixel_c0 | missT_c1);
	assign	adrTexReq_c0		= pause ? PtexelAdress_c1 : texelAdress_c0;
	
	// -------------------------------------------------------------
	// ---        Stage C1
	// -------------------------------------------------------------
	reg			PisTexturedPixel_c1;
	reg			PisPaletteTex;
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
	
	// Assign to user control outside
	assign	missT_c1		= TexMiss_c1;
	
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
	reg			PPisPaletteTex;
	reg [15:0]	PPdataTex_c2;
	reg  [7:0]  PPdataIndex;
	
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
		if (!pause | resetPipelinePixelStateSpike | (i_nrst == 0)) begin
			PPpixelStateSpike_c2	= ((i_nrst==0) | resetPipelinePixelStateSpike) ? 2'b00 : PpixelStateSpike_c1;	// Reset to ZERO if resetLineFlag
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
			PPisPaletteTex		= PisPaletteTex;
			PPdataTex_c2		= PisTrueColor_c1 ? dataTex_c1 : {8'b0, index_c1};
			PPdataIndex         = index_c1;
//			PPdataTex_c2		= dataTex_c1;

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
			PisPaletteTex		= isPaletteTex;
			PtexelAdress_c1		= texelAdress_c0;
		end
	end
	
	// ----------------------------------------------------------------
	// [Lookup palette using selector.]
	assign	indexPal			= !pause ? index_c1 : PPdataIndex;
	// ----------------------------------------------------------------
	
	reg [15:0] storeClut;
	always @ (posedge clk)
	begin
		if (!pause) begin
			storeClut = dataClut_c2;
		end
	end
	
	// ----------------------------------------------------------
	//   Texture Color Value out
	// ----------------------------------------------------------
	wire [15:0] selPalette  = /*pause ? storeClut : */dataClut_c2;
	wire [15:0] selPix      = PPisTrueColor_c2     ? PPdataTex_c2 : selPalette;
	wire [15:0] pixelOut    = PPisTexturedPixel_c2 ?       selPix :   16'h7FFF;
	
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
