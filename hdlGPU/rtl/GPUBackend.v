module GPUBackend(
	input			clk,
	input			i_nrst,
	
	// -------------------------------
	// Control line for state machine
	// -------------------------------
	input			i_pausePipeline,			// Freeze the data in the pipeline. Values stay as is.
	output			o_missTC,					// Any Cache miss, stop going next pixels.
	output			o_pixelInFlight,
	// Management on BG Block
	output			o_writePixelOnNewBlock,	// Tells us that the current pixel WRITE to a new BG block, write to the REGISTER this clock if not paused (upper logic will use create the input pausePipeline with combinatorial to avoid write with this flag)
	input			i_resetPipelinePixelStateSpike,	// 1/ Clear 'o_writePixelOnNewBlock' flag. 
	input			i_resetPixelMask,		// 2/ Clear MASK for new block.
	
	// -------------------------------
	// GPU Setup
	// -------------------------------
	input	 [1:0]	GPU_REG_Transparency,
	input	 [1:0]	GPU_REG_TexFormat,
	input			noTexture,
	input			noblend,
	input			ditherActive,
	input	 [3:0]	GPU_REG_TexBasePageX,
	input			GPU_REG_TexBasePageY,
	input			GPU_REG_TextureXFlip,
	input			GPU_REG_TextureYFlip,
	input 	[4:0]	GPU_REG_WindowTextureMaskX,
	input 	[4:0]	GPU_REG_WindowTextureMaskY,
	input 	[4:0]	GPU_REG_WindowTextureOffsetX,
	input 	[4:0]	GPU_REG_WindowTextureOffsetY,
	
	// -------------------------------
	// Input Pixels from FrontEnd
	// -------------------------------
	input [1:0]		iPixelStateSpike,		// 00:Ignored, 01:First time, 10:Second and others...
	input [9:0] 	iScrX_Mul2,
	input [8:0] 	iScrY,
	
	input [8:0]		iR_L,
	input [8:0]		iG_L,
	input [8:0]		iB_L,
	input [7:0]		U_L,
	input [7:0]		V_L,
	input			validPixel_L,
	input			bgMSK_L,
	
	input [8:0]		iR_R,
	input [8:0]		iG_R,
	input [8:0]		iB_R,
	input [7:0]		U_R,
	input [7:0]		V_R,
	input			validPixel_R,
	input			bgMSK_R,
	
	// -------------------------------
	//   Flush until 
	// -------------------------------
	input			flushLastBlock,
	
	// -------------------------------
	//  Request to Cache system ?
	// -------------------------------
	output			requDataTex_c0L,
	output [18:0]	adrTexReq_c0L,
	input			TexHit_c1L,
	input			TexMiss_c1L,
	input  [15:0]	dataTex_c1L,
	
	// Request Cache Fill
	output          requTexCacheUpdate_c1L,
	output [16:0]   adrTexCacheUpdate_c0L,
	input           updateTexCacheCompleteL,
	
	// Clut$ Side
	output [7:0]	indexPalL,	// Temp
	input  [15:0]	dataClut_c2L,

	// --- Tex$ Side ---
	output			requDataTex_c0R,
	output [18:0]	adrTexReq_c0R,
	input			TexHit_c1R,
	input			TexMiss_c1R,
	input  [15:0]	dataTex_c1R,
	
	// Request Cache Fill
	output          requTexCacheUpdate_c1R,
	output [16:0]   adrTexCacheUpdate_c0R,
	input           updateTexCacheCompleteR,
	
	// Clut$ Side
	output [7:0]	indexPalR,	// Temp
	input  [15:0]	dataClut_c2R,
	
	// -------------------------------
	//   Stencil Cache Write Back
	// -------------------------------
	// Write
	output 			stencilWriteSig,
	// Where to write
	output [14:0]	stencilWriteAdr,
	output  [2:0]	stencilWritePair,
	// Where inside the pair
	output	[1:0]	stencilWriteSelect,
	// Value to write
	output	[1:0]	stencilWriteValue,

	// -------------------------------
	//   DDR 
	// -------------------------------
	
	// Ask to write BG 
	output  [14:0]	loadAdr,
	output  [14:0]	saveAdr,
	output	 [1:0]	saveBGBlock,			// Stay 1 for long, should use 0->1 TRANSITION on user side.
	output [255:0]	exportedBGBlock,
	output  [15:0]	exportedMSKBGBlock,
	
	// BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
	input			importBGBlockSingleClock,
	input  [255:0]	importedBGBlock
);
	reg [255:0] cacheBG;
	reg  [15:0] cacheBGMsk;
	wire missT_c1L,missT_c1R;
	wire [18:0]	adrTexReqL,adrTexReqR;
	wire pixelInFlightL,pixelInFlightR;

	// ...Inter plumbing...
	wire [1:0] oPixelStateSpikeL,oPixelStateSpikeR;
	wire oValidPixelL,oValidPixelR;
	wire [ 9:0]	oScrxL,oScrxR;
	wire [ 8:0]	oScryL,oScryR;
	wire [15:0]	oTexelL,oTexelR;
	wire oTransparentL,oTransparentR;
	wire [8:0]	oRL,oRR,oGL,oGR,oBL,oBR;
	wire oBGMSK_L,oBGMSK_R;

	wire [31:0] writeBack32;
	
	reg  [14:0] lastWriteAdrReg;
	
	assign exportedBGBlock			= cacheBG;
	assign exportedMSKBGBlock		= cacheBGMsk;

	assign o_missTC					= missT_c1L | missT_c1R;

	// Do operation on the bus for READ/WRITE WHEN :
	// - Load BG on first block if BLENDING ENABLED
	// - Load/Save BG on next blocks
	// - Skip if value is = 00.
//	always @ (posedge clk) begin
//		AssertionFalse1: assert (oNewBGCacheLineL == oNewBGCacheLineR) else $error( "Can not be different");
//	end
	
	// -----------------------------------------------
	// Convert UV to Adress Space
	// -----------------------------------------------
	TEXUnit TEXUnitInstance(
		// Register SETUP
		.GPU_REG_TexBasePageX				(GPU_REG_TexBasePageX),
		.GPU_REG_TexBasePageY				(GPU_REG_TexBasePageY),
		.GPU_REG_TextureXFlip				(GPU_REG_TextureXFlip),
		.GPU_REG_TextureYFlip				(GPU_REG_TextureYFlip),
		.GPU_REG_TexFormat					(GPU_REG_TexFormat),
		.GPU_REG_WindowTextureMaskX			(GPU_REG_WindowTextureMaskX),
		.GPU_REG_WindowTextureMaskY			(GPU_REG_WindowTextureMaskY),
		.GPU_REG_WindowTextureOffsetX		(GPU_REG_WindowTextureOffsetX),
		.GPU_REG_WindowTextureOffsetY		(GPU_REG_WindowTextureOffsetY),
		
		// Dynamic stuff...
		.coordU_L							(U_L),
		.coordV_L							(V_L),
		.coordU_R							(U_R),
		.coordV_R							(V_R),
		
		.texelAdress_L						(adrTexReqL),	// HalfWord adress.
		.texelAdress_R						(adrTexReqR)	// HalfWord adress.
	);

	wire [9:0] leftX 	=  iScrX_Mul2;
	wire [9:0] rightX	= {iScrX_Mul2[9:1],1'b1};
	
	assign o_pixelInFlight = pixelInFlightL | pixelInFlightR;
	
	GPUPipeCtrl2 GPUPipeCtrl2L(
		.clk				(clk),
		.i_nrst				(i_nrst),
		
		// --- Value, Fixed per primitive ---
		.GPU_REG_TexFormat	(GPU_REG_TexFormat),
		.GPU_TEX_DISABLE	(noTexture),
		
		// --- ALL STAGES : Just STOP ---
		.pause				(i_pausePipeline),
		.resetPipelinePixelStateSpike(i_resetPipelinePixelStateSpike),
		.pixelInFlight		(pixelInFlightL),

		
		// --- Stage 0 Input ---
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.iPixelStateSpike	(iPixelStateSpike),
		.iScrX				(leftX),
		.iScrY				(iScrY),
		.iR					(iR_L),
		.iG					(iG_L),
		.iB					(iB_L),
		.iBGMSK				(bgMSK_L),
		
		.validPixel_c0		(validPixel_L),
		.UCoordLSB			(U_L[1:0]),
		.texelAdress_c0		(adrTexReqL),

		// --- Stage 1 Output Control ---
		.missT_c1			(missT_c1L),			// TRUE garantee it is about VALID pixel/request.
		
		// --- Stage 2 Write back Control ---
		.oPixelStateSpike	(oPixelStateSpikeL),
		.oValidPixel		(oValidPixelL),
		.oScrx				(oScrxL),
		.oScry				(oScryL),
		.oTexel				(oTexelL),
		.oTransparent		(oTransparentL),
		.oR					(oRL),
		.oG					(oGL),
		.oB					(oBL),
		.oBGMSK				(oBGMSK_L),
		
		// --------------------------------------------
		//  Memory Side
		// --------------------------------------------

		.requDataTex_c0				(requDataTex_c0L		),
		.adrTexReq_c0				(adrTexReq_c0L			),
		.TexHit_c1					(TexHit_c1L				),
		.TexMiss_c1					(TexMiss_c1L			),
		.dataTex_c1					(dataTex_c1L			),
                                     
		.requTexCacheUpdate_c1		(requTexCacheUpdate_c1L	),
		.adrTexCacheUpdate_c0		(adrTexCacheUpdate_c0L	),
		.updateTexCacheComplete		(updateTexCacheCompleteL),
                                     
		.indexPal					(indexPalL				),	// Temp
		.dataClut_c2				(dataClut_c2L			)
	);

	GPUPipeCtrl2 GPUPipeCtrl2R(
		.clk				(clk),
		.i_nrst				(i_nrst),
		
		// --- Value, Fixed per primitive ---
		.GPU_REG_TexFormat	(GPU_REG_TexFormat),
		.GPU_TEX_DISABLE	(noTexture),
		
		// --- ALL STAGES : Just STOP ---
		.pause				(i_pausePipeline),
		.resetPipelinePixelStateSpike(i_resetPipelinePixelStateSpike),
		.pixelInFlight		(pixelInFlightR),
		
		// --- Stage 0 Input ---
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.iPixelStateSpike	(iPixelStateSpike),
		.iScrX				(rightX),
		.iScrY				(iScrY),
		.iR					(iR_R),
		.iG					(iG_R),
		.iB					(iB_R),
		.iBGMSK				(bgMSK_R),
		
		.validPixel_c0		(validPixel_R),
		.UCoordLSB			(U_R[1:0]),
		.texelAdress_c0		(adrTexReqR),

		// --- Stage 1 Output Control ---
		.missT_c1			(missT_c1R),			// TRUE garantee it is about VALID pixel/request.
		
		// --- Stage 2 Write back Control ---
		.oPixelStateSpike	(oPixelStateSpikeR),
		.oValidPixel		(oValidPixelR),
		.oScrx				(oScrxR),
		.oScry				(oScryR),
		.oTexel				(oTexelR),
		.oTransparent		(oTransparentR),
		.oR					(oRR),
		.oG					(oGR),
		.oB					(oBR),
		.oBGMSK				(oBGMSK_R),
		
		// --------------------------------------------
		//  Memory Side
		// --------------------------------------------

		.requDataTex_c0				(requDataTex_c0R		),
		.adrTexReq_c0				(adrTexReq_c0R			),
		.TexHit_c1					(TexHit_c1R				),
		.TexMiss_c1					(TexMiss_c1R			),
		.dataTex_c1					(dataTex_c1R			),
                                     
		.requTexCacheUpdate_c1		(requTexCacheUpdate_c1R	),
		.adrTexCacheUpdate_c0		(adrTexCacheUpdate_c0R	),
		.updateTexCacheComplete		(updateTexCacheCompleteR),
                                     
		.indexPal					(indexPalR				),	// Temp
		.dataClut_c2				(dataClut_c2R			)
	);

	wire finalValidL = (!oTransparentL) & oValidPixelL;
	wire finalValidR = (!oTransparentR) & oValidPixelR;
	
	// ---------------------------------------------
	// READ BACKGROUND PIXEL FOR BLENDING (Value ignored if not used)
	// ---------------------------------------------
	reg [31:0] pixelBG32;
	always @(*)
	begin
		case (oScrxL[3:1])
		3'd0: pixelBG32 = cacheBG[ 31:  0];
		3'd1: pixelBG32 = cacheBG[ 63: 32];
		3'd2: pixelBG32 = cacheBG[ 95: 64];
		3'd3: pixelBG32 = cacheBG[127: 96];
		3'd4: pixelBG32 = cacheBG[159:128];
		3'd5: pixelBG32 = cacheBG[191:160];
		3'd6: pixelBG32 = cacheBG[223:192];
		3'd7: pixelBG32 = cacheBG[255:224];
		endcase
	end
	
	// ---------------------------------------------
	// [ All blending and RGB computation]
	//   Combinatorial...
	// ---------------------------------------------
	GPUComputeOnly GPUComputeOnlyInstance(
		// [Register of GPU]
		.GPU_REG_Transparency		(GPU_REG_Transparency),
		.noTexture					(noTexture),
		.noblend					(noblend),
		.ditherActive				(ditherActive),
		
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.iScrX_Mul2					(oScrxL), // For both.
		.iScrY						(oScryL),
		
		// Texture Output
		.texelL						(oTexelL),
		.texelR						(oTexelR),
		.iTransparentL				(oTransparentL),
		.iTransparentR				(oTransparentR),
		.iBGMskL					(oBGMSK_L),
		.iBGMskR					(oBGMSK_R),
		
		// Gouraud Side output
		.iR_L						(oRL),
		.iG_L						(oGL),
		.iB_L						(oBL),
		.iR_R						(oRR),
		.iG_R						(oGR),
		.iB_R						(oBR),

		// BG If needed.
		.rBG_L						(pixelBG32[ 4: 0]),
		.gBG_L						(pixelBG32[ 9: 5]),
		.bBG_L						(pixelBG32[14:10]),
		.rBG_R						(pixelBG32[20:16]),
		.gBG_R						(pixelBG32[25:21]),
		.bBG_R						(pixelBG32[30:26]),
		
		// Final PIXEL to write back.
		.write32					(writeBack32)
	);
	
	// ---------------------------------------------
	// WRITE PACK TO BACKGROUND
	// ---------------------------------------------	
	reg PTexHit_c1R,PTexHit_c1L;
	always @(posedge clk)
	begin
		if (!i_pausePipeline && TexHit_c1R && TexHit_c1L) begin
			PTexHit_c1R <= TexHit_c1R;
			PTexHit_c1L <= TexHit_c1L;
		end
	end
	wire validTextureL		= PTexHit_c1L;
	wire validTextureR		= PTexHit_c1R;
	wire writeSigL			= finalValidL & ((validTextureL & !noTexture) | noTexture);
	wire writeSigR			= finalValidR & ((validTextureR & !noTexture) | noTexture);
	
	// MEMO BEFORE_TEXTURE : writeSig = (oValidPixelR | oValidPixelL);
	reg PPausePipeline;
	always @(posedge clk)
	begin
		PPausePipeline <= i_pausePipeline;
	end
	wire        writeSig	= !i_pausePipeline & (writeSigL | writeSigR);
	wire [14:0] writeAdr 	= { oScryL, oScrxL[9:4] }; // TODO : Same as loadAdr
	wire  [1:0] selPair		= {oValidPixelR,oValidPixelL};
	wire  [2:0] pairID		= oScrxL[3:1];
	
	assign stencilWriteAdr		= writeAdr;				// 14:0 <- Block adress.
	assign stencilWriteSig		= writeSig;				// 1	<- Perform write.
	assign stencilWriteValue	= {	writeBack32[31] & oValidPixelR,
									writeBack32[15] & oValidPixelL };	// 1:0	<- Value to write back. = BGMSK_R (original/sticky bit) with Force set flag & ACTIVE PIXEL.
	assign stencilWriteSelect	= selPair;				// 1:0	<- Which pixel need update.
	assign stencilWritePair		= pairID;				// 2:0	<- Pair ID

	assign loadAdr					= { oScryL, oScrxL[9:4] };
	assign saveAdr					= lastWriteAdrReg;
	
	always @(posedge clk)
	begin
		if (writeSig) begin
			lastWriteAdrReg <= writeAdr;
			if (finalValidR) begin
				case (pairID)
				3'd0: begin cacheBG[ 31: 16] <= writeBack32[31:16]; cacheBGMsk[ 1] <= selPair[1]; end
				3'd1: begin cacheBG[ 63: 48] <= writeBack32[31:16]; cacheBGMsk[ 3] <= selPair[1]; end
				3'd2: begin cacheBG[ 95: 80] <= writeBack32[31:16]; cacheBGMsk[ 5] <= selPair[1]; end
				3'd3: begin cacheBG[127:112] <= writeBack32[31:16]; cacheBGMsk[ 7] <= selPair[1]; end
				3'd4: begin cacheBG[159:144] <= writeBack32[31:16]; cacheBGMsk[ 9] <= selPair[1]; end
				3'd5: begin cacheBG[191:176] <= writeBack32[31:16]; cacheBGMsk[11] <= selPair[1]; end
				3'd6: begin cacheBG[223:208] <= writeBack32[31:16]; cacheBGMsk[13] <= selPair[1]; end
				3'd7: begin cacheBG[255:240] <= writeBack32[31:16]; cacheBGMsk[15] <= selPair[1]; end
				endcase
			end

			if (finalValidL) begin
				case (pairID)
				3'd0: begin cacheBG[ 15:  0] <= writeBack32[15: 0]; cacheBGMsk[ 0] <= selPair[0]; end
				3'd1: begin cacheBG[ 47: 32] <= writeBack32[15: 0]; cacheBGMsk[ 2] <= selPair[0]; end
				3'd2: begin cacheBG[ 79: 64] <= writeBack32[15: 0]; cacheBGMsk[ 4] <= selPair[0]; end
				3'd3: begin cacheBG[111: 96] <= writeBack32[15: 0]; cacheBGMsk[ 6] <= selPair[0]; end
				3'd4: begin cacheBG[143:128] <= writeBack32[15: 0]; cacheBGMsk[ 8] <= selPair[0]; end
				3'd5: begin cacheBG[175:160] <= writeBack32[15: 0]; cacheBGMsk[10] <= selPair[0]; end
				3'd6: begin cacheBG[207:192] <= writeBack32[15: 0]; cacheBGMsk[12] <= selPair[0]; end
				3'd7: begin cacheBG[239:224] <= writeBack32[15: 0]; cacheBGMsk[14] <= selPair[0]; end
				endcase
			end
		end else begin
			if (importBGBlockSingleClock) begin
				cacheBG		<= importedBGBlock;
			end
			if (i_resetPixelMask) begin
				cacheBGMsk	<= 16'd0;
			end
		end
	end
	
	// 00 : [Nothing]
	// 01 : First pair,
	// 10 : Next Pair,
	// 11 : Last Pair / Flush.
	wire [1:0] pairCode				= ((oPixelStateSpikeL == 2'b01) & noblend) ? 2'b00 : (oPixelStateSpikeL | {flushLastBlock,flushLastBlock});
	reg  [1:0] PpairCode;
	wire doBlockOp					= pairCode[0] | pairCode[1]; /* | oNewBGCacheLineR*/ // Should be the SAME, only one item needed
	reg  PdoBlockOp;
	
	// Operating step is given to the memory module. (None,First,Second & Others)
	assign saveBGBlock				= pairCode;
	assign o_writePixelOnNewBlock	= doBlockOp;

	always @(posedge clk)
	begin
		PpairCode  <= pairCode;
		PdoBlockOp <= doBlockOp;
	end
endmodule
