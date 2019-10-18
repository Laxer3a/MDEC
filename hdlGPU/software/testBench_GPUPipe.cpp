#if 0
//----------------------------------------------------------------------------
// Test for full range of values => RGB 16 millions
// Test for all screen space combination (x 0..3, y 0..3)
// Test for dither on/off
// Total 2^29 tests.
//----------------------------------------------------------------------------

#include <stdio.h>
#include "../rtl/obj_dir/VGPUPipeWrapCtrl.h"

#define VCSCANNER_IMPL
#include "../../common_software/VCScanner.h"

#define ASSERT_CHK(cond)		if (!cond) { errorPipeline(); }

void errorPipeline() {
	while (1) {
	}
}

VCScanner*		pScan;
VGPUPipeWrapCtrl*	mod;
int resetSig;

int clockCnt = 0;

void pushPixels();
void cacheLoading();

void clock() {
	mod->clk    = 0;
	mod->eval();
	pScan->eval(clockCnt++);

	mod->i_nrst = resetSig;

	mod->clk    = 1;
	mod->eval();

	cacheLoading();
	pushPixels  ();
	mod->eval(); // Propagate signal from CacheLoading / PushPixels along (combinatorial)
	pScan->eval(clockCnt++);
}

struct PixelRecords {
	int texelAdress;
	int x;
	int y; 
	int r; 
	int g; 
	int b;
	int U_LSB;
};

PixelRecords pixelsInfo[] = {
	// Cache = 8 Byte => 4 Texel.
	// [0..3],[4..7],[8..B],[C..F]
	{ 0xA, 0, 0, 0xA, 0xA, 0xA, 0 },
	{ 0xB, 0, 0, 0xB, 0xB, 0xB, 1 },
	{ 0xC, 0, 0, 0xC, 0xC, 0xC, 2 },
	{ 0xD, 0, 0, 0xD, 0xD, 0xD, 3 },
	{ 0xE, 0, 0, 0xD, 0xD, 0xD, 0 },
	{ 0xF, 0, 0, 0xD, 0xD, 0xD, 1 },
	{ 0x0, 0, 0, 0x0, 0x0, 0x0, 0 },
	{ 0x1, 0, 0, 0x1, 0x1, 0x1, 0 },
	{ 0x2, 0, 0, 0x2, 0x2, 0x2, 0 },
	{ 0x3, 0, 0, 0x3, 0x3, 0x3, 0 },
};

int counterPixel = 0;

void setInput(int texelAdress, int x, int y, int r, int g, int b, int U_LSB) {
	mod->validPixel = 1;
	mod->iScrX = x & 3;
	mod->iScrY = x & 3;
	mod->iR = r & 0xFF;
	mod->iG = g & 0xFF;
	mod->iB = b & 0xFF;
	mod->texelAdress = texelAdress;
	mod->UCoordLSB = U_LSB & 3; // 2 bit
}

void setNoInput() {
	mod->validPixel = 0;
}

void pushPixels() {
	if (mod->OkNext) {
		if (mod->i_nrst == 1) {
			PixelRecords& pix = pixelsInfo[counterPixel++];
			setInput(pix.texelAdress, pix.x, pix.y, pix.r, pix.g, pix.b, pix.U_LSB);
		} else {
			counterPixel = 0;
			setNoInput();
		}
	}
}

int state = 0;
int memoryAdr;

unsigned long long GetU64Word(int adr) {
	unsigned long long v = 0;
	for (int n=0; n < 4; n++) {
		v |= ((unsigned long long)adr+n)<<(16*n);
	}
	return v;
}

void cacheLoading() {
	mod->updateTexCacheComplete = 0;
	mod->adrTexCacheWrite = 0xFFFFF;
	mod->TexCacheWrite	= 0;

	if ((state == 0) & mod->requTexCacheUpdate) {
		state = 1;
		memoryAdr = (mod->adrTexCacheUpdate >> 3) << 3; // Cache line are 8 byte.
	} else {
		if (state != 0) {
			if (state == 2) {
				mod->TexCacheWrite	= 1;
				mod->TexCacheData	= GetU64Word(memoryAdr);
				mod->adrTexCacheWrite = memoryAdr++;
				mod->updateTexCacheComplete = 1;
				state = 0;
			} else {
				state++;
			}
		}
	}
}

void setTextureEnable(bool enable) {
	mod->GPU_TEX_DISABLE = enable ? 0 : 1; // Inverse of enable.
}

void setTrueColor() { mod->GPU_REG_TexFormat = 2; }
void set8Bit()      { mod->GPU_REG_TexFormat = 1; }
void set4Bit()      { mod->GPU_REG_TexFormat = 0; }

int testPipeline() {
	//
	// This module is pure combinatorial computation, no clock needed.
	//
	pScan = new VCScanner();
	pScan->init(500); // TODO : MUST TURN API ATOMIC.

	mod = new VGPUPipeWrapCtrl();

	#define MODULE mod
	#define SCAN   pScan

	#define VL_IN(NAME,size,s2)			SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIGA(NAME,size,s2,cnt)	SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_IN8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_IN16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_IN64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIGW(NAME,size,s2,storageSize,depth)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME,depth, (((u8*)& MODULE ->## NAME[1]) - ((u8*)& MODULE ->## NAME[0])));

	VL_IN8(clk,0,0);
	VL_IN8(i_nrst,0,0);
	VL_IN8(GPU_REG_TexFormat,1,0);
	VL_IN8(GPU_TEX_DISABLE,0,0);
	VL_IN8(iScrX,1,0);
	VL_IN8(iScrY,1,0);
	VL_IN8(iR,7,0);
	VL_IN8(iG,7,0);
	VL_IN8(iB,7,0);
	VL_IN8(validPixel,0,0);
	VL_IN8(UCoordLSB,1,0);
	VL_IN8(OkNextOtherUnit,0,0);
	VL_OUT8(OkNext,0,0);
	VL_OUT8(requTexCacheUpdate,0,0);
	VL_IN8(TexCacheWrite,0,0);
	VL_IN8(updateTexCacheComplete,0,0);
	VL_OUT8(requClutCacheUpdate,0,0);
	VL_IN8(ClutCacheWrite,0,0);
	VL_IN8(ClutWriteIndex,6,0);
	VL_IN8(updateClutCacheComplete,0,0);
	VL_OUT8(oValidPixel,0,0);
	VL_OUT8(oScrx,1,0);
	VL_OUT8(oScry,1,0);
	VL_OUT8(oTransparent,0,0);
	VL_OUT8(oR,7,0);
	VL_OUT8(oG,7,0);
	VL_OUT8(oB,7,0);
	VL_IN16(GPU_REG_CLUT,14,0);
	VL_IN16(CLUT_ID,15,0);
	VL_OUT16(oPixel,15,0);
	VL_IN(texelAdress,19,0);
	VL_OUT(adrTexCacheUpdate,19,0);
	VL_IN(adrTexCacheWrite,19,0);
	VL_OUT(adrClutCacheUpdate,19,0);
	VL_IN(ClutCacheData,31,0);
	VL_IN64(TexCacheData,63,0);

	// LOCAL SIGNALS
	// Internals; generally not touched by application code
	// Begin mtask footprint  all: 
	VL_SIG8(GPUPipeWrapCtrl__DOT__clk,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__i_nrst,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPU_REG_TexFormat,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPU_TEX_DISABLE,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__iScrX,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__iScrY,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__iR,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__iG,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__iB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__validPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__UCoordLSB,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__OkNextOtherUnit,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__OkNext,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__requTexCacheUpdate,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__TexCacheWrite,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__updateTexCacheComplete,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__requClutCacheUpdate,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__ClutCacheWrite,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__ClutWriteIndex,6,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__updateClutCacheComplete,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oValidPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oScrx,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oScry,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oTransparent,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oR,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oG,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__oB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__requDataTexA,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__TexHitA,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__requDataClut,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__index,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__ClutHit,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__clearCache,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__textureFormatTrueColor,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__TexHitB,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__requDataTexB,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__indexB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__ClutHitB,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__clk,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__i_nrst,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__clearCache,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__textureFormatTrueColor,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__write,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__isHitA,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__isHitB,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__pRaddrA,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__pRaddrB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__pIndexA,2,1);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__pIndexB,2,1);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__lookActiveA,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__lookActiveB,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__lookTagA,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__lookTagB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__pLookActiveA,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__pLookActiveB,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__clk,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__i_nrst,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__write,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__writeIdx,6,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__readIdx1,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__isHit1,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__readIdx2,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__isHit2,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__pRaddrA,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__pRaddrB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__clearCache,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__clk,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__i_nrst,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__GPU_REG_TexFormat,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__GPU_TEX_DISABLE,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__iScrX,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__iScrY,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__iR,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__iG,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__iB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__validPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__UCoordLSB,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__OkNextOtherUnit,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__OkNext,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__requDataTex,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TexHit,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__requTexCacheUpdate,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__updateTexCacheComplete,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__requDataClut,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__index,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__ClutHit,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__requClutCacheUpdate,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__updateClutCacheComplete,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oValidPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oScrx,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oScry,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oTransparent,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oR,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oG,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oB,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__isTrueColor,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__isTexturedPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__isClutPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__outTexValidPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__outTexValidPixelWithOtherUnit,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__pIsTexturedPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__pOutTexValidPixel,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__pUCoordLSB,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TexCacheMiss,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__loadingText,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__requestMissTexture,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__endRequestMissTexture,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__loadingClut,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__requestMissClut,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__endRequestMissClut,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__colIndex,5,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__ScrX1,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__ScrX2,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__ScrY1,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__ScrY2,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__R1,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__R2,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__G1,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__G2,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__B1,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__B2,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__clk,0,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__GPU_REG_TexFormat,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__UCoordLSB,1,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__indexLookup,7,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__tmpIndex2,3,0);
	VL_SIG8(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__tmpIndex,7,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPU_REG_CLUT,14,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__CLUT_ID,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__oPixel,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__dataTexA,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__dataClut,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__dataTexB,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__dataClutB,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__dataOutA,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__dataOutB,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__dOutA,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__dOutB,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__CLUT_ID,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__colorEntry1,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__colorEntry2,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__Loaded,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__CLUT_Internal,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__GPU_REG_CLUT,14,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__dataTex,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__dataClut,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__oPixel,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__pixelOut,15,0);
	VL_SIG16(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__TEXToIndex_inst__DOT__dataIn,15,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__texelAdress,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__adrTexCacheUpdate,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__adrTexCacheWrite,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__adrClutCacheUpdate,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__ClutCacheData,31,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__adrTexReq,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__adrTexReqB,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__adressIn,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__adressLookA,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__adressLookB,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__swizzleAddr,19,0);
//	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__Active,255,0);
	VL_SIGA(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__Active,0,0,8,256);

	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__D0A,71,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__D0B,71,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__ColorIn,31,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__vA,31,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__vB,31,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__texelAdress,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__adrTexReq,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__adrTexCacheUpdate,19,0);
	VL_SIG(GPUPipeWrapCtrl__DOT__GPUPipeCtrlInstance__DOT__adrClutCacheUpdate,19,0);
	VL_SIG64(GPUPipeWrapCtrl__DOT__TexCacheData,63,0);
	VL_SIG64(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__dataIn,63,0);
	
	VL_SIGW(GPUPipeWrapCtrl__DOT__directCacheDoublePortInst__DOT__RAMStorage,71,0,3,256);
	VL_SIGW(GPUPipeWrapCtrl__DOT__CLUT_CacheInst__DOT__CLUTStorage,31,0,1,128);

	// LOCAL VARIABLES
	// Internals; generally not touched by application code
	// Begin mtask footprint  all: 
	VL_SIG8(__Vclklast__TOP__clk,0,0);


	pScan->addPlugin(new ValueChangeDump_Plugin("gpuLog.vcd"));

	// RESET
	resetSig = 0;

	/*
	cache->write = 0;
	cache->adressIn = 0;
	cache->dataIn = 0;
	*/
	clock();
	clock();
	clock();
	clock();
	resetSig   = 1;
	clock();

	// Enable Texture, true color mode for now...
	setTextureEnable(true);
	setTrueColor();

	// setInput(0xA, 0, 0, 0xA, 0xA, 0xA, 0); // Adr,RGB = Pixel A, as in ABCDEF
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();

	delete mod;
	delete pScan;

	return 1;
}

int main() {
	testPipeline();
}
#endif
