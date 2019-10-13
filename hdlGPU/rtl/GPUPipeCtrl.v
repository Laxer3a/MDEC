/*
	Memory Controller Priority :
	Priority 1 - Pixel Write back to DDR.
	Priority 2 - BG Fetch => Avoid FIFO full in pipeline. Want to get BG to push OUT ASAP.
	Priority 3 - Texture over clut.
	Priority 4 - Clut.
*/

module GPUPipeCtrl(
	input	clk,
	input	i_nrst,
	
	input	 [1:0]	GPU_REG_TexFormat,
	input	[14:0]	GPU_REG_CLUT,
	input			GPU_TEX_DISABLE,
	
	// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
	input [1:0] 	iScrX,
	input [1:0] 	iScrY,
	input [7:0]		iR,
	input [7:0]		iG,
	input [7:0]		iB,
	
	input			validPixel,
	input  [1:0]	UCoordLSB,
	input [19:0] 	texelAdress,
	
	// To Left Side
	input			OkNextOtherUnit,
	output			OkNext,

	// Tex$ Side
	output			requDataTex,
	output [19:0]	adrTexReq,	// Temp
	input			TexHit,
	input  [15:0]	dataTex,	// Temp 
	
	// Request Cache Fill
	output          requTexCacheUpdate,
	output [19:0]   adrTexCacheUpdate,
	input           updateTexCacheComplete,
	
	// Clut$ Side
	output			requDataClut,
	output [7:0]	index,	// Temp
	input			ClutHit,
	input  [15:0]	dataClut,
	
	// Request Cache Fill
	output          requClutCacheUpdate,
	output [19:0]   adrClutCacheUpdate,
	input           updateClutCacheComplete,
	
	// Right Side
	output			oValidPixel,
	output [ 1:0]	oScrx,
	output [ 1:0]	oScry,
	output [15:0]	oPixel,
	output 			oTransparent,
	output  [7:0]	oR,
	output  [7:0]	oG,
	output  [7:0]	oB
);
	wire isTrueColor = (GPU_REG_TexFormat == 2'd2);

	TEXToIndex TEXToIndex_inst(
		.clk				(clk),
		// In
		.GPU_REG_TexFormat	(GPU_REG_TexFormat),
		.dataIn				(dataTex),
		.UCoordLSB			(pUCoordLSB),
		// Out
		.indexLookup		(index)
	);
	
	// VALID PIXEL AND TEXTURED.
	wire	isTexturedPixel 	= validPixel & !GPU_TEX_DISABLE;
	wire    isClutPixel			= pIsTexturedPixel & (!isTrueColor);

	// REQUEST TO TEX$ : VALID PIXEL TEXTURED

	// TODO : use & OkNextOtherUnit to avoid sending request while Cache is updated ?
	assign	requDataTex			= (isTexturedPixel & (!loadingText) & (!requestMissTexture) ) | endRequestMissTexture; // Note : (!requestMissTexture) not necessary, but makes signal clearer (requ last 1 cycle instead of 2 in case of MISS)
	assign	adrTexReq			= texelAdress;
	
	// REQUEST TO CLU$ : VALID PIXEL TEXTURED AND TEX$ HIT AND PALETTE BASED.
	assign	requDataClut		= ((TexHit     & isClutPixel) & (!loadingClut)) | endRequestMissClut;

	// Pixel after TEX$ Hit and CLU$ check (no read yet)
	// A valid pixel is Palette CLU$+TEX$ or True color with TEX$ only.
	wire 	outTexValidPixel	= (TexHit & (ClutHit | isTrueColor));

	// Hit in texture and Clut ? go to next pixel.
	// TexHit and ClutHit are at the SAME cycle.
	// If the pixel is NOT TEXTURED or EMPTY(/INVALID), request next too.
	// If the pixel is TRUE COLOR, request ignore Clut result.
	assign	OkNext				= outTexValidPixel | (!pIsTexturedPixel);

	// After our current pixel is VALITED, we must make sure that OTHER unit are OK too.
	// Else we have to wait...
	wire    outTexValidPixelWithOtherUnit = outTexValidPixel & OkNextOtherUnit;
	
	reg pIsTexturedPixel;
	reg pOutTexValidPixel;
	reg [1:0] pUCoordLSB;
	always @ (posedge clk)
	begin
		// Post CLUT
		pOutTexValidPixel	<= outTexValidPixelWithOtherUnit;
		pIsTexturedPixel	<= isTexturedPixel;
		pUCoordLSB			<= UCoordLSB;
	end
	
	// Data Requested VALID and NOT IN CACHE.
	wire TexCacheMiss = pIsTexturedPixel & (!TexHit);
	
	// --------------------------------------------------------
	//   Loader Blocking Texture usage while loading
	//   cache miss line
	// --------------------------------------------------------
	reg loadingText;
	reg requestMissTexture, endRequestMissTexture;
	always @ (posedge clk)
	begin
		if ((i_nrst == 0) || (endRequestMissTexture == 1'b1)) begin
			loadingText <= 1'b0;
		end else begin
			if (requestMissTexture == 1'b1) begin
				loadingText <= 1'b1;
			end
		end
	end
	
	always @(*)
	begin
		requestMissTexture    = (TexCacheMiss & (!loadingText));
		endRequestMissTexture = (loadingText & updateTexCacheComplete);
	end
	assign requTexCacheUpdate = requestMissTexture;
	assign adrTexCacheUpdate  = texelAdress; // NO NEED FOR PIPELINING. If FAIL, NEXT=0 -> Input is the same as previous cycle...
	// ----------------------------------------------------------
	
	// --------------------------------------------------------
	//   Loader Blocking Texture usage while loading
	//   cache miss line
	// --------------------------------------------------------
	reg loadingClut;
	reg requestMissClut, endRequestMissClut;
	always @ (posedge clk)
	begin
		if ((i_nrst == 0) || (endRequestMissClut)) begin
			loadingClut <= 1'b0;
		end else begin
			if (requestMissClut) begin
				loadingClut <= 1'b1;
			end
		end
	end
	
	always @(*)
	begin
		requestMissClut		= (TexHit & (!ClutHit) & isClutPixel & (!loadingClut));
		endRequestMissClut	= (loadingClut & updateClutCacheComplete);
	end
	assign requClutCacheUpdate = requestMissClut;
	
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
		____.____.___I.III_.____  <-- Cache line is 32 bytes.
		
	 */
	wire [5:0] colIndex = { 2'b0, index[7:4] } + GPU_REG_CLUT[5:0];
	
	// FULL ADDRESS DECODING----
	// CACHE LINE ADD
	assign adrClutCacheUpdate  = { GPU_REG_CLUT[14:6] , colIndex, 5'b0 }; // Cache line is 32 byte. ==> 16 Colors.
	// ----------------------------------------------------------
		
	// Select "CLUT" or "TEXTURE" or "WHITE with 0 mask value".
	wire [15:0] pixelOut	= GPU_TEX_DISABLE ? 16'h7FFF : ((!isTrueColor) ? dataClut          : dataTex);
	assign oPixel			= pixelOut;
	assign oValidPixel		= GPU_TEX_DISABLE ? 1'b1     : ((!isTrueColor) ? pOutTexValidPixel : outTexValidPixel);
	assign oTransparent		= !(|pixelOut[14:0]); // If all ZERO, then 1.

	// ---- Pipelining of RGB / Scr coord
	reg [1:0] 	ScrX1,ScrX2;
	reg [1:0] 	ScrY1,ScrY2;
	reg [7:0]	R1,R2,G1,G2,B1,B2;

	// Pipe 1
	always @ (posedge clk)
	begin ScrX1 <= iScrX; ScrY1 <= iScrY; R1 <= iR; G1 <= iG; B1 <= iB; end

	// Pipe 2
	always @ (posedge clk)
	begin ScrX2 <= ScrX1; ScrY2 <= ScrY1; R2 <= R1; G2 <= G1; B2 <= B1; end

	// Select output due to latency...
	assign oScrx	= isTrueColor ? ScrX1 : ScrX2;
	assign oScry	= isTrueColor ? ScrY1 : ScrY2;
	assign oR 		= isTrueColor ? R1 : R2;
	assign oG 		= isTrueColor ? G1 : G2;
	assign oB 		= isTrueColor ? B1 : B2;
endmodule
