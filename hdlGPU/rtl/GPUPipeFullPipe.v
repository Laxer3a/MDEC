// TODO : Add Index inside pipeline to write to the FIFO command system (write pixel into BURST BUFFER)
// TODO : noTexture is Register setup GPU_TEX_DISABLE + combinatorial with runtime state.
// TODO : requDataClutL/R : Unused by CLUT_Cache, read all the time. (Avoid issue when LOADING CACHE...)
// TODO : Implement finalMask_L, finalMask_R : for now hardcoded to 1.
// TODO : Caller of FullPipe need to arbitrate multiple request from LEFT and RIGHT (ex. texture miss at both pixel seperatly, same for CLUT)
// TODO : Get BG when necessary -> Burst of 8 pixel ? 16 pixel ? : rBG_L,gBG_L,bBG_L,rBG_R,gBG_R,bBG_R

module GPUPipeFullPipe(
	input	clk,
	input	i_nrst,
	
	// [Register of GPU]
	input	 [1:0]	GPU_REG_TexFormat,
	input	[14:0]	GPU_REG_CLUT,
	input			noTexture,
	input	 [3:0]	GPU_REG_TexBasePageX,
	input			GPU_REG_TexBasePageY,
	input			GPU_REG_TextureXFlip,
	input			GPU_REG_TextureYFlip,
	input 	[4:0]	GPU_REG_WindowTextureMaskX,
	input 	[4:0]	GPU_REG_WindowTextureMaskY,
	input 	[4:0]	GPU_REG_WindowTextureOffsetX,
	input 	[4:0]	GPU_REG_WindowTextureOffsetY,
	
	input			noblend,
	input			ditherActive,
	input   [1:0]	GPU_REG_Transparency,
	
	input 			clearCache,
	
	// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
	input [9:0] 	iScrX_Mul2,
	input [8:0] 	iScrY,
	
	input [8:0]		iR_L,
	input [8:0]		iG_L,
	input [8:0]		iB_L,
	input [7:0]		U_L,
	input [7:0]		V_L,
	input			validPixel_L,
	
	input [8:0]		iR_R,
	input [8:0]		iG_R,
	input [8:0]		iB_R,
	input [7:0]		U_R,
	input [7:0]		V_R,
	input			validPixel_R,
	
	// To Left Side (Control signal to push next pixel set)
	output			OkNext_L,
	output			OkNext_R,

	// Request Cache Fill
	output          requTexCacheUpdateL,
	output [16:0]   adrTexCacheUpdateL,
	input           updateTexCacheCompleteL,
	
	output          requTexCacheUpdateR,
	output [16:0]   adrTexCacheUpdateR,
	input           updateTexCacheCompleteR,
	
	input  [16:0]   adrTexCacheWrite,
	input           TexCacheWrite,
	input  [63:0]   TexCacheData,
	
	// Request Cache Fill
	output          requClutCacheUpdateL,
	output [14:0]   adrClutCacheUpdateL,
	input           updateClutCacheCompleteL,
	
	output          requClutCacheUpdateR,
	output [14:0]   adrClutCacheUpdateR,
	input           updateClutCacheCompleteR,
	
	input           ClutCacheWrite,
	input   [2:0]   ClutWriteIndex,
	input  [31:0]   ClutCacheData,
	
	// Right Side
	output [31:0]	write32,
	output  [1:0]	pixelValid,
	output			writePixel
);

	// Tex$ Side
	wire			requDataTexL;
	wire			requDataTexR;
		
	// Clut$ Side
	wire			requDataClut;
	wire [7:0]		indexL,indexR;
	wire			ClutHitL,ClutHitR;
	wire  [15:0]	dataClutL,dataClutR;
	
	wire textureFormatTrueColor = (GPU_REG_TexFormat != 2'd2);
	
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
		
		.texelAdress_L						(adrTexReqL_1),	// HalfWord adress.
		.texelAdress_R						(adrTexReqR_1)	// HalfWord adress.
	);
	
	wire [18:0]		adrTexReqL_1,adrTexReqR_1;	// Unit to pipe
	
	directCacheDoublePort directCacheDoublePortInst(
		.clk								(clk),
		.i_nrst								(i_nrst),
		.clearCache							(clearCache),
		
		// [Can spy all write on the bus and maintain cache integrity]
		.textureFormatTrueColor				(textureFormatTrueColor),
		.write								(TexCacheWrite),
		.adressIn							(adrTexCacheWrite),
		.dataIn								(TexCacheData),
		
		.adressLookA						(adrTexReqL_2),
		.dataOutA							(dataTexL),
		.isHitA								(TexHit_L),

		.adressLookB						(adrTexReqR_2),
		.dataOutB							(dataTexR),
		.isHitB								(TexHit_R)
	);
	
	wire [18:0]	adrTexReqL_2,adrTexReqR_2;	// pipe to cache
	wire		TexHit_L,TexHit_R;
	wire [15:0] dataTexL,dataTexR;
	
	CLUT_Cache CLUT_CacheInst(
		.clk								(clk),
		.i_nrst								(i_nrst),
		
		.CLUT_ID							(GPU_REG_CLUT),
		
		.write								(ClutCacheWrite),
		.writeIdxInBlk						(ClutWriteIndex),
		.ColorIn							(ClutCacheData),

		.readIdx1							(indexL),
		.isHit1								(ClutHitL),
		.colorEntry1						(dataClutL),
		
		.readIdx2							(indexR),
		.isHit2								(ClutHitR),
		.colorEntry2						(dataClutR)
	);
	
	wire requDataClutL,requDataClutR;

	wire [1:0] iXLsbL = { iScrX_Mul2[1] , 1'b0 };
	wire [1:0] iXLsbR = { iScrX_Mul2[1] , 1'b1 };
	
	GPUPipeCtrl GPUPipeCtrlInstanceL (
		.clk								(clk),
		.i_nrst								(i_nrst),
		
		.GPU_REG_TexFormat					(GPU_REG_TexFormat),
		.GPU_REG_CLUT						(GPU_REG_CLUT),
		.GPU_TEX_DISABLE					(noTexture),
		
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.iScrX								(iXLsbL),
		.iScrY								(iScrY[1:0]),
		.iR									(iR_L),
		.iG									(iG_L),
		.iB									(iB_L),
		
		.validPixel							(validPixel_L),
		.UCoordLSB							(U_L[1:0]),
		.texelAdress						(adrTexReqL_1),
		
		// To Left Side
		.OkNextOtherUnit					(OkNext_R),
		.OkNext								(OkNext_L),

		// Tex$ Side
		.requDataTex						(requDataTexL),
		.adrTexReq							(adrTexReqL_2),
		.TexHit								(TexHit_L),
		.dataTex							(dataTexL),
		
		// Request Cache Fill
		.requTexCacheUpdate					(requTexCacheUpdateL),
		.adrTexCacheUpdate					(adrTexCacheUpdateL),
		.updateTexCacheComplete				(updateTexCacheCompleteL),
		
		// Clut$ Side
		.requDataClut						(requDataClutL),
		.index								(indexL),
		.ClutHit							(ClutHitL),
		.dataClut							(dataClutL),
		
		// Request Cache Fill
		.requClutCacheUpdate				(requClutCacheUpdateL),
		.adrClutCacheUpdate					(adrClutCacheUpdateL),
		.updateClutCacheComplete			(updateClutCacheCompleteL),
		
		// Right Side
		.oValidPixel						(oValidPixelL),
		.oScrx								(oScrxL),
		.oScry								(oScryL),
		.oTexel								(texelL),
		.oTransparent						(oTransparentL),
		.oR									(oR_L),
		.oG									(oG_L),
		.oB									(oB_L)
	);
	
	GPUPipeCtrl GPUPipeCtrlInstanceR (
		.clk								(clk),
		.i_nrst								(i_nrst),
		
		.GPU_REG_TexFormat					(GPU_REG_TexFormat),
		.GPU_REG_CLUT						(GPU_REG_CLUT),
		.GPU_TEX_DISABLE					(noTexture),
		
		// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
		.iScrX								(iXLsbR),
		.iScrY								(iScrY[1:0]),
		.iR									(iR_R),
		.iG									(iG_R),
		.iB									(iB_R),
		
		.validPixel							(validPixel_R),
		.UCoordLSB							(U_R[1:0]),
		.texelAdress						(adrTexReqR_1),
		
		// To Left Side
		.OkNextOtherUnit					(OkNext_L),
		.OkNext								(OkNext_R),

		// Tex$ Side
		.requDataTex						(requDataTexR),
		.adrTexReq							(adrTexReqR_2),
		.TexHit								(TexHit_R),
		.dataTex							(dataTexR),
		
		// Request Cache Fill
		.requTexCacheUpdate					(requTexCacheUpdateR),
		.adrTexCacheUpdate					(adrTexCacheUpdateR),
		.updateTexCacheComplete				(updateTexCacheCompleteR),
		
		// Clut$ Side
		.requDataClut						(requDataClutR),
		.index								(indexR),
		.ClutHit							(ClutHitR),
		.dataClut							(dataClutR),
		
		// Request Cache Fill
		.requClutCacheUpdate				(requClutCacheUpdateR),
		.adrClutCacheUpdate					(adrClutCacheUpdateR),
		.updateClutCacheComplete			(updateClutCacheCompleteR),
		
		// Right Side
		.oValidPixel						(oValidPixelR),
		.oScrx								(oScrxR),
		.oScry								(oScryR),
		.oTexel								(texelR),
		.oTransparent						(oTransparentR),
		.oR									(oR_R),
		.oG									(oG_R),
		.oB									(oB_R)
	);
	
	wire [15:0]	texelL,texelR;
	wire		oTransparentL,oTransparentR;
	wire [8:0]	oR_L,oG_L,oB_L,
				oR_R,oG_R,oB_R;
	wire [1:0]	oScrxL,oScryL,
				oScrxR,oScryR;
	wire		oValidPixelL,oValidPixelR;

	// ALL FURTHER STAGE HAVE ZERO CYCLE DELAY : ALL COMBINATORIAL / COMPUTATION.
	// So no pipeline is necessary for now... (oScrx, oScry)
	
	// === 0 Cycle Delay Stage ===
	
	Shading ShadingInstanceL (
		.rTex								(texelL[ 4: 0]),
		.gTex								(texelL[ 9: 5]),
		.bTex								(texelL[14:10]),
		.noTexture							(noTexture),
		
		.rGouraud							(oR_L),
		.gGouraud							(oG_L),
		.bGouraud							(oB_L),
		
		.rOut								(rShaded_L),
		.gOut								(gShaded_L),
		.bOut								(bShaded_L)
	);
		
	Shading ShadingInstanceR (
		.rTex								(texelR[ 4: 0]),
		.gTex								(texelR[ 9: 5]),
		.bTex								(texelR[14:10]),
		.noTexture							(noTexture),
		
		.rGouraud							(oR_R),
		.gGouraud							(oG_R),
		.bGouraud							(oB_R),
		
		.rOut								(rShaded_R),
		.gOut								(gShaded_R),
		.bOut								(bShaded_R)
	);
		
	wire [7:0]	rShaded_L,gShaded_L,bShaded_L,
				rShaded_R,gShaded_R,bShaded_R;
	wire [7:0]	rBG_L,gBG_L,bBG_L,
				rBG_R,gBG_R,bBG_R;

	
	// === 0 Cycle Delay Stage ===
	blendUnit blendUnitL(
		.bg_r								(rBG_L),
		.bg_g								(gBG_L),
		.bg_b								(bBG_L),

		.px_r								(rShaded_L),
		.px_g								(gShaded_L),
		.px_b								(bShaded_L),

		.px_STP								(texelL[15]),
		.px_transparent						(oTransparentL),

		.noblend							(noblend),
		.modeGPU							(GPU_REG_Transparency),

		.rOut								(Rbld_L),
		.gOut								(Gbld_L),
		.bOut								(Bbld_L)
	);				
						
	blendUnit blendUnitR(
		.bg_r								(rBG_R),
		.bg_g								(gBG_R),
		.bg_b								(bBG_R),

		.px_r								(rShaded_R),
		.px_g								(gShaded_R),
		.px_b								(bShaded_R),

		.px_STP								(texelR[15]),
		.px_transparent						(oTransparentR),

		.noblend							(noblend),
		.modeGPU							(GPU_REG_Transparency),

		.rOut								(Rbld_R),
		.gOut								(Gbld_R),
		.bOut								(Bbld_R)
	);				

	wire [7:0]	Rbld_L,Gbld_L,Bbld_L,
				Rbld_R,Gbld_R,Bbld_R;

	// === 0 Cycle Delay Stage ===
	dither ditherL(
		.rIn								(Rbld_L),
		.gIn								(Gbld_L),
		.bIn								(Bbld_L),
		.ditherOn							(ditherActive),
		.xBuff								(oScrxL),	// Pipeline X/Y LSB, INDEX in BURST WRITE ?
		.yBuff								(oScryL),
		.r									(finalR_L),
		.g									(finalG_L),
		.b									(finalB_L)
	);				

	dither ditherR(
		.rIn								(Rbld_R),
		.gIn								(Gbld_R),
		.bIn								(Bbld_R),
		.ditherOn							(ditherActive),
		.xBuff								(oScrxR),
		.yBuff								(oScryR),
		.r									(finalR_R),
		.g									(finalG_R),
		.b									(finalB_R)
	);
	
	wire [4:0]	finalR_L,finalG_L,finalB_L,
				finalR_R,finalG_R,finalB_R;

	wire finalMask_L = 1'b1;
	wire finalMask_R = 1'b1;

	assign write32		= {	finalMask_R,finalB_R,finalG_R,finalR_R,
							finalMask_L,finalB_L,finalG_L,finalR_L };
	assign pixelValid	= { oValidPixelR,oValidPixelL };
	assign writePixel	= 1'b1;
endmodule
