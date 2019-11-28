/*	All combinatorial stuff... */
module GPUComputeOnly(
	// [Register of GPU]
	input			noTexture,
	input			noblend,
	input			ditherActive,
	input   [1:0]	GPU_REG_Transparency,
	
	// Left Side (All values stay the same from previous cycle if OkNext is FALSE)
	input [9:0] 	iScrX_Mul2,
	input [8:0] 	iScrY,
	
	// Texture Output
	input [15:0]	texelL,
	input [15:0]	texelR,
	input			iTransparentL,
	input			iTransparentR,
	
	// Gouraud Side output
	input [8:0]		iR_L,
	input [8:0]		iG_L,
	input [8:0]		iB_L,
	input [8:0]		iR_R,
	input [8:0]		iG_R,
	input [8:0]		iB_R,

	// BG If needed.
	input [4:0]		rBG_L,
	input [4:0]		gBG_L,
	input [4:0]		bBG_L,
	input [4:0]		rBG_R,
	input [4:0]		gBG_R,
	input [4:0]		bBG_R,
	
	// Bit 15 for Left and Right pixel.
	input 			finalBit15_L,
	input			finalBit15_R,

	// Final PIXEL to write back.
	output [31:0]	write32
);
	wire [8:0]	oR_L,oG_L,oB_L,
				oR_R,oG_R,oB_R;
	
	Shading ShadingInstanceL (
		.rTex								(texelL[ 4: 0]),
		.gTex								(texelL[ 9: 5]),
		.bTex								(texelL[14:10]),
		.noTexture							(noTexture),
		
		.rGouraud							(iR_L),
		.gGouraud							(iG_L),
		.bGouraud							(iB_L),
		
		.rOut								(rShaded_L),
		.gOut								(gShaded_L),
		.bOut								(bShaded_L)
	);
		
	Shading ShadingInstanceR (
		.rTex								(texelR[ 4: 0]),
		.gTex								(texelR[ 9: 5]),
		.bTex								(texelR[14:10]),
		.noTexture							(noTexture),
		
		.rGouraud							(iR_R),
		.gGouraud							(iG_R),
		.bGouraud							(iB_R),
		
		.rOut								(rShaded_R),
		.gOut								(gShaded_R),
		.bOut								(bShaded_R)
	);
		
	wire [7:0]	rShaded_L,gShaded_L,bShaded_L,
				rShaded_R,gShaded_R,bShaded_R;
				
	// === 0 Cycle Delay Stage ===
	blendUnit blendUnitL(
		.bg_r								(rBG_L),
		.bg_g								(gBG_L),
		.bg_b								(bBG_L),

		.px_r								(rShaded_L),
		.px_g								(gShaded_L),
		.px_b								(bShaded_L),

		.px_STP								(texelL[15]),
		.px_transparent						(iTransparentL),

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
		.px_transparent						(iTransparentR),

		.noblend							(noblend),
		.modeGPU							(GPU_REG_Transparency),

		.rOut								(Rbld_R),
		.gOut								(Gbld_R),
		.bOut								(Bbld_R)
	);				

	wire [7:0]	Rbld_L,Gbld_L,Bbld_L,
				Rbld_R,Gbld_R,Bbld_R;
				
	wire [1:0] iXLsbL = { iScrX_Mul2[1] , 1'b0 };
	wire [1:0] iXLsbR = { iScrX_Mul2[1] , 1'b1 };

	// === 0 Cycle Delay Stage ===
	dither ditherL(
		.rIn								(Rbld_L),
		.gIn								(Gbld_L),
		.bIn								(Bbld_L),
		.ditherOn							(ditherActive),
		.xBuff								(iXLsbL),	// Pipeline X/Y LSB, INDEX in BURST WRITE ?
		.yBuff								(iScrY[1:0]),
		.r									(finalR_L),
		.g									(finalG_L),
		.b									(finalB_L)
	);				

	dither ditherR(
		.rIn								(Rbld_R),
		.gIn								(Gbld_R),
		.bIn								(Bbld_R),
		.ditherOn							(ditherActive),
		.xBuff								(iXLsbR),
		.yBuff								(iScrY[1:0]),
		.r									(finalR_R),
		.g									(finalG_R),
		.b									(finalB_R)
	);
	
	wire [4:0]	finalR_L,finalG_L,finalB_L,finalR_R,finalG_R,finalB_R;
	assign write32		= {	finalBit15_R,finalB_R,finalG_R,finalR_R, finalBit15_L,finalB_L,finalG_L,finalR_L };
endmodule
