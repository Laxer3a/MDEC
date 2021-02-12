/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module GPUBackend(
	input			clk,
	input			i_nrst,
	
	// -------------------------------
	// Control line for state machine
	// -------------------------------
	input			i_pausePipeline,			// Freeze the data in the pipeline. Values stay as is.
	output			o_missTC,					// Any Cache miss, stop going next pixels.
	output			o_pixelInFlight,
	output	[1:0]	o_PixelBlockTransition,
	input			i_flushClearMask,
	
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
	input [1:0]		i_PixelBlockTransition,
	input [9:0] 	iScrX_Mul2,
	input [8:0] 	iScrY,
	
	input [8:0]		iR_L,
	input [8:0]		iG_L,
	input [8:0]		iB_L,
	input [7:0]		i_U_L,
	input [7:0]		i_V_L,
	input			i_validPixel_L,
	input			i_bgMSK_L,
	
	input [8:0]		iR_R,
	input [8:0]		iG_R,
	input [8:0]		iB_R,
	input [7:0]		i_U_R,
	input [7:0]		i_V_R,
	input			i_validPixel_R,
	input			i_bgMSK_R,
	
	// -------------------------------
	//  Request to Cache system ?
	// -------------------------------
	output			o_requDataTex_c0L,
	output [18:0]	o_adrTexReq_c0L,
	input			i_TexHit_c1L,
	input			i_TexMiss_c1L,
	input  [15:0]	i_dataTex_c1L,
	
	// Request Cache Fill
	output          o_requTexCacheUpdate_c1L,
	output [16:0]   o_adrTexCacheUpdate_c0L,
	input           i_updateTexCacheCompleteL,
	
	// Clut$ Side
	output [7:0]	o_indexPalL,	// Temp
	input  [15:0]	i_dataClut_c2L,

	// --- Tex$ Side ---
	output			o_requDataTex_c0R,
	output [18:0]	o_adrTexReq_c0R,
	input			i_TexHit_c1R,
	input			i_TexMiss_c1R,
	input  [15:0]	i_dataTex_c1R,
	
	// Request Cache Fill
	output          o_requTexCacheUpdate_c1R,
	output [16:0]   o_adrTexCacheUpdate_c0R,
	input           i_updateTexCacheCompleteR,
	
	// Clut$ Side
	output [7:0]	o_indexPalR,	// Temp
	input  [15:0]	i_dataClut_c2R,
	
	// -------------------------------
	//   Stencil Cache Write Back
	// -------------------------------
	// Write
	output 			o_stencilWriteSig,
	// Where to write
	output [14:0]	o_stencilWriteAdr,
//	output  [2:0]	o_stencilWritePair,
	// Where inside the pair
//	output	[1:0]	o_stencilWriteSelect,
	// Value to write
	output [15:0]	o_stencilWriteMask,
	output [15:0]	o_stencilWriteValue,

	// -------------------------------
	//   DDR 
	// -------------------------------
	
	// Ask to write BG 
	output  [14:0]	o_loadAdr,
	output  [14:0]	o_saveAdr,
	output [255:0]	o_exportedBGBlock,
	output  [15:0]	o_exportedMSKBGBlock,
	
	// BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
	input			i_importBGBlockSingleClock,
	input  [255:0]	i_importedBGBlock
);

	reg [255:0] cacheBG;
	reg  [15:0] cacheBGMsk;
	reg  [15:0] stencilValue;
	wire missT_c1L,missT_c1R;
	wire [18:0]	adrTexReqL,adrTexReqR;
	wire pixelInFlightL,pixelInFlightR;

	// ...Inter plumbing...
	wire [1:0] oPixelStateSpikeL;
	wire oValidPixelL,oValidPixelR;
	wire [ 9:0]	oScrxL,oScrxR;
	wire [ 8:0]	oScryL,oScryR;
	wire [15:0]	oTexelL,oTexelR;
	wire oTransparentL,oTransparentR;
	wire [8:0]	oRL,oRR,oGL,oGR,oBL,oBR;
	wire oBGMSK_L,oBGMSK_R;

	wire [31:0] writeBack32;
	
	reg  [14:0] lastWriteAdrReg;
	
	assign o_exportedBGBlock		= cacheBG;
	assign o_exportedMSKBGBlock		= cacheBGMsk;
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
		.coordU_L							(i_U_L),
		.coordV_L							(i_V_L),
		.coordU_R							(i_U_R),
		.coordV_R							(i_V_R),
		
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
		.pixelInFlight		(pixelInFlightL),
		
		// --- Stage 0 Input ---
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.i_PixelBlockTransition	(i_PixelBlockTransition),
		.iScrX				(leftX),
		.iScrY				(iScrY),
		.iR					(iR_L),
		.iG					(iG_L),
		.iB					(iB_L),
		.iBGMSK				(i_bgMSK_L),
		
		.validPixel_c0		(i_validPixel_L),
		.UCoordLSB			(i_U_L[1:0]),
		.texelAdress_c0		(adrTexReqL),

		// --- Stage 1 Output Control ---
		.missT_c1			(missT_c1L),			// TRUE garantee it is about VALID pixel/request.
		
		// --- Stage 2 Write back Control ---
		.o_PixelBlockTransition(o_PixelBlockTransition),
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

		.requDataTex_c0				(o_requDataTex_c0L		),
		.adrTexReq_c0				(o_adrTexReq_c0L		),
		.TexHit_c1					(i_TexHit_c1L			),
		.TexMiss_c1					(i_TexMiss_c1L			),
		.dataTex_c1					(i_dataTex_c1L			),
                                     
		.requTexCacheUpdate_c1		(o_requTexCacheUpdate_c1L),
		.adrTexCacheUpdate_c0		(o_adrTexCacheUpdate_c0L),
		.updateTexCacheComplete		(i_updateTexCacheCompleteL),
                                     
		.indexPal					(o_indexPalL			),	// Temp
		.dataClut_c2				(i_dataClut_c2L			)
	);

	GPUPipeCtrl2 GPUPipeCtrl2R(
		.clk				(clk),
		.i_nrst				(i_nrst),
		
		// --- Value, Fixed per primitive ---
		.GPU_REG_TexFormat	(GPU_REG_TexFormat),
		.GPU_TEX_DISABLE	(noTexture),
		
		// --- ALL STAGES : Just STOP ---
		.pause				(i_pausePipeline),
		.pixelInFlight		(pixelInFlightR),
		
		// --- Stage 0 Input ---
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.i_PixelBlockTransition(/*Unused*/),
		.iScrX				(/* UNUSED */),
		.iScrY				(/* UNUSED */),
		.iR					(iR_R),
		.iG					(iG_R),
		.iB					(iB_R),
		.iBGMSK				(i_bgMSK_R),
		
		.validPixel_c0		(i_validPixel_R),
		.UCoordLSB			(i_U_R[1:0]),
		.texelAdress_c0		(adrTexReqR),

		// --- Stage 1 Output Control ---
		.missT_c1			(missT_c1R),			// TRUE garantee it is about VALID pixel/request.
		
		// --- Stage 2 Write back Control ---
		.o_PixelBlockTransition(/*Unused*/),
		.oValidPixel		(oValidPixelR),
		.oScrx				(/* UNUSED */),
		.oScry				(/* UNUSED */),
		.oTexel				(oTexelR),
		.oTransparent		(oTransparentR),
		.oR					(oRR),
		.oG					(oGR),
		.oB					(oBR),
		.oBGMSK				(oBGMSK_R),
		
		// --------------------------------------------
		//  Memory Side
		// --------------------------------------------

		.requDataTex_c0				(o_requDataTex_c0R		),
		.adrTexReq_c0				(o_adrTexReq_c0R		),
		.TexHit_c1					(i_TexHit_c1R			),
		.TexMiss_c1					(i_TexMiss_c1R			),
		.dataTex_c1					(i_dataTex_c1R			),
                                     
		.requTexCacheUpdate_c1		(o_requTexCacheUpdate_c1R),
		.adrTexCacheUpdate_c0		(o_adrTexCacheUpdate_c0R),
		.updateTexCacheComplete		(i_updateTexCacheCompleteR),
                                     
		.indexPal					(o_indexPalR			),	// Temp
		.dataClut_c2				(i_dataClut_c2R			)
	);

	wire finalValidL = (!oTransparentL) & oValidPixelL;
	wire finalValidR = (!oTransparentR) & oValidPixelR;
	
	// ---------------------------------------------
	// READ BACKGROUND PIXEL FOR BLENDING (Value ignored if not used)
	// ---------------------------------------------
	reg [14:0] pixelBGL;
	reg [14:0] pixelBGR;
	always @(*)
	begin
		case (oScrxL[3:1])
		3'd0: begin pixelBGL = cacheBG[ 14:  0]; pixelBGR = cacheBG[ 30: 16]; end
		3'd1: begin pixelBGL = cacheBG[ 46: 32]; pixelBGR = cacheBG[ 62: 48]; end
		3'd2: begin pixelBGL = cacheBG[ 78: 64]; pixelBGR = cacheBG[ 94: 80]; end
		3'd3: begin pixelBGL = cacheBG[110: 96]; pixelBGR = cacheBG[126:112]; end
		3'd4: begin pixelBGL = cacheBG[142:128]; pixelBGR = cacheBG[158:144]; end
		3'd5: begin pixelBGL = cacheBG[174:160]; pixelBGR = cacheBG[190:176]; end
		3'd6: begin pixelBGL = cacheBG[206:192]; pixelBGR = cacheBG[222:208]; end
		3'd7: begin pixelBGL = cacheBG[238:224]; pixelBGR = cacheBG[254:240]; end
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
//		.iTransparentL				(oTransparentL),
//		.iTransparentR				(oTransparentR),
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
		.rBG_L						(pixelBGL[ 4: 0]),
		.gBG_L						(pixelBGL[ 9: 5]),
		.bBG_L						(pixelBGL[14:10]),
		.rBG_R						(pixelBGR[ 4: 0]),
		.gBG_R						(pixelBGR[ 9: 5]),
		.bBG_R						(pixelBGR[14:10]),
		
		// Final PIXEL to write back.
		.write32					(writeBack32)
	);
	
	// ---------------------------------------------
	// WRITE PACK TO BACKGROUND
	// ---------------------------------------------	
	reg PTexHit_c1R,PTexHit_c1L;
	always @(posedge clk)
	begin
		if (!i_pausePipeline && i_TexHit_c1R && i_TexHit_c1L) begin
			PTexHit_c1R <= i_TexHit_c1R;
			PTexHit_c1L <= i_TexHit_c1L;
		end
	end
	
	wire writeCacheLine			= o_PixelBlockTransition[1] & (!i_pausePipeline);
	wire validTextureL			= PTexHit_c1L;
	wire validTextureR			= PTexHit_c1R;
	wire writeSigL				= finalValidL & ((validTextureL & !noTexture) | noTexture);
	wire writeSigR				= finalValidR & ((validTextureR & !noTexture) | noTexture);
	
	// MEMO BEFORE_TEXTURE : writeSig = (oValidPixelR | oValidPixelL);
	wire        writeSig		= !i_pausePipeline & (writeSigL | writeSigR);
	wire [14:0] writeAdr 		= { oScryL, oScrxL[9:4] }; // TODO : Same as loadAdr
	
	assign o_stencilWriteAdr	= lastWriteAdrReg;		// 14:0 <- Block adress.
	assign o_stencilWriteSig	= writeCacheLine;		// 1	<- Perform write.

	assign o_loadAdr			= writeAdr;
	assign o_saveAdr			= lastWriteAdrReg;
	
	always @(posedge clk)
	begin
		/*	1. Block can be SAVED, while next pixel written for next cycle
			2. MASK RESET while SAVING (clear at next cycle)
			   BUT WRITE OF NEXT PIXEL OCCURS NOW
			=> [Cache BGMSK reset must be BEFORE writeSig !!!] */
		if (writeCacheLine | i_flushClearMask) begin
			cacheBGMsk			<= 16'd0;
			// cacheBG			<= 256'd0; // ONLY FOR DEBUG.
		end
		if (i_importBGBlockSingleClock) begin
			cacheBG		<= i_importedBGBlock;
		end
		if (writeSig) begin
			lastWriteAdrReg <= writeAdr;
			if (finalValidR) begin
				case (oScrxL[3:1])
				3'd0: begin cacheBG[ 31: 16] <= writeBack32[31:16]; cacheBGMsk[ 1] <= oValidPixelR; end
				3'd1: begin cacheBG[ 63: 48] <= writeBack32[31:16]; cacheBGMsk[ 3] <= oValidPixelR; end
				3'd2: begin cacheBG[ 95: 80] <= writeBack32[31:16]; cacheBGMsk[ 5] <= oValidPixelR; end
				3'd3: begin cacheBG[127:112] <= writeBack32[31:16]; cacheBGMsk[ 7] <= oValidPixelR; end
				3'd4: begin cacheBG[159:144] <= writeBack32[31:16]; cacheBGMsk[ 9] <= oValidPixelR; end
				3'd5: begin cacheBG[191:176] <= writeBack32[31:16]; cacheBGMsk[11] <= oValidPixelR; end
				3'd6: begin cacheBG[223:208] <= writeBack32[31:16]; cacheBGMsk[13] <= oValidPixelR; end
				3'd7: begin cacheBG[255:240] <= writeBack32[31:16]; cacheBGMsk[15] <= oValidPixelR; end
				endcase
			end

			if (finalValidL) begin
				case (oScrxL[3:1])
				3'd0: begin cacheBG[ 15:  0] <= writeBack32[15: 0]; cacheBGMsk[ 0] <= oValidPixelL; end
				3'd1: begin cacheBG[ 47: 32] <= writeBack32[15: 0]; cacheBGMsk[ 2] <= oValidPixelL; end
				3'd2: begin cacheBG[ 79: 64] <= writeBack32[15: 0]; cacheBGMsk[ 4] <= oValidPixelL; end
				3'd3: begin cacheBG[111: 96] <= writeBack32[15: 0]; cacheBGMsk[ 6] <= oValidPixelL; end
				3'd4: begin cacheBG[143:128] <= writeBack32[15: 0]; cacheBGMsk[ 8] <= oValidPixelL; end
				3'd5: begin cacheBG[175:160] <= writeBack32[15: 0]; cacheBGMsk[10] <= oValidPixelL; end
				3'd6: begin cacheBG[207:192] <= writeBack32[15: 0]; cacheBGMsk[12] <= oValidPixelL; end
				3'd7: begin cacheBG[239:224] <= writeBack32[15: 0]; cacheBGMsk[14] <= oValidPixelL; end
				endcase
			end
		end
	end

	assign	o_stencilWriteMask	= cacheBGMsk;
	assign	o_stencilWriteValue	= { cacheBG[255],cacheBG[239],cacheBG[223],cacheBG[207],cacheBG[191],cacheBG[175],cacheBG[159],cacheBG[143] ,
								    cacheBG[127],cacheBG[111],cacheBG[ 95],cacheBG[ 79],cacheBG[ 63],cacheBG[ 47],cacheBG[ 31],cacheBG[ 15] };
endmodule
