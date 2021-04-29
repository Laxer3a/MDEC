#include "gpu_ref.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <Windows.h>

#define USE_WORD_INPUT	(0)

#if 0

u8 refRect		[256*5*32];
u8 refQuadNoTex	[64*64*(32*5+1)*2];
u8 refQuadTex	[18000000];
u8 otherShit    [1];
u16 vram        [1024*512];

extern void dumpFrameBasic(const char* name, u16* buffer);

// Pass the test.
int blendTest(int it5, int bg5, int mode, int ref) {
	int FR   = it5;
	int BG_R = bg5;
	switch (mode-1) {
	case 0:
		FR = (BG_R+FR)>>1;
		break;
	case 1:
		FR = BG_R+FR;
		break;
	case 2:
		FR = BG_R - FR;
		break;
	case 3:
		FR = BG_R+(FR>>2);
		break;
	default:
		break;
	}

	if (FR <  0) { FR = 0;  }
	if (FR > 31) { FR = 31; }

	if (ref != FR) {
		return FR - 1000;
	}
	return ref;
}

int blendTestTexRAW(int tex5, int bg5, int mode, int ref) {

	if (tex5 == 0) { return -1; }

	int color = tex5;
	int err = blendTest(color, bg5, mode, ref);
	if (err < 0) {
		printf("T5:%i, BG5:%i, MODE:%i, V:%i, REF:%i", err +1000, ref);
	}
	return err;
}

int blendTestTexMod(int tex5, int it8, int bg5, int mode, int ref) {

	if (tex5 == 0) { return -1; }

	if (it8 > 127) { it8 = 127; }

	// tex5 : between 0.. 31
	// it8  : between 0..127
	// color: 5 bit
//	int color = (((tex5 * (it8>>3))>>5)<<3);

	int color = ((tex5 * it8) / 128);

	// <<3 ,just have fake 8 bit input
	int err = blendTest(color, bg5, mode, ref);
	if (err < 0) {
		printf("T5:%i, IT8:%i, BG5:%i, MODE:%i, V:%i, REF:%i\n", tex5, it8, bg5, mode, err +1000, ref);
	}
	return err;
}

void loadRefRect(const char* fileName) {
	FILE* paramF = fopen(fileName,"rb");
	if (paramF) {
		fseek(paramF,0,SEEK_END); int size = ftell(paramF); fseek(paramF,0,SEEK_SET);
		while (!feof(paramF)) {
			char buffer[200];
			u32 a;
			u32 b;
			if (fscanf(paramF,"%08x=%08x\n",&a,&b)) {
				a<<=1;
				refRect[a  ] = b;
				refRect[a+1] = b>>16;
			}
		}
		fclose(paramF);
	}

	// Test Blending functions.
	for (int mode = 1; mode < 5; mode++) {
		for (int bg = 0; bg < 32; bg++) {
			for (int it8 = 0; it8 < 256; it8++) {
				blendTest(it8>>3,bg,mode,refRect[it8 + (256*bg) + (256*32*mode)]);
			}
		}
	}	
}

void loadRefQuadTex(const char* fileName) {
	/*
	FILE* paramF = fopen(fileName,"rb");
	int idx = 0;
	if (paramF) {
		fseek(paramF,0,SEEK_END); int size = ftell(paramF); fseek(paramF,0,SEEK_SET);
		while (!feof(paramF)) {
			char buffer[200];
			u32 a;
			u32 b;
			if (fscanf(paramF,"%08x=%08x\n",&a,&b)) {
				if (a != 0xFFFFFFFF) {
					a<<=1;
					refQuadTex[idx++] = b;
					refQuadTex[idx++] = b>>16;
				}
			}
		}
		fclose(paramF);
	}
	*/
	int idx = 16841728; // Size loaded from text.... Buffer is bigger.
	FILE* f = fopen("quadTex.bin","wb");
	fread(refQuadTex,1,18000000,f);
	fclose(f);

	// 2 x (128x4) x 
#if 0
	int idxE=0; 
	int x2=0;
	int y2=0;
	int count = 0;
	int epoq  = 0;
	int block = 0;
	while (idxE < idx) {
		for (int y=0;y < 4;y++) {
			for (int x=0;x < 128;x++) {
				vram[x+x2+((y+y2)*1024)] = refQuadTex[idxE++] << epoq;
			}
		}
		block++;
		if (block == 258) {
			epoq = 5;
		}
		y2 += 4;
		if (y2 == 512) {
			y2 = 0;
			x2 += 128;
			if (x2 == 1024) {
				x2 = 0;
				if (count == 0) {
					dumpFrameBasic("quad_tex0.png", vram);
				} else if (count == 1) {
					dumpFrameBasic("quad_tex1.png", vram);
				} else if (count == 2) {
					dumpFrameBasic("quad_tex2.png", vram);
				} else if (count == 3) {
					dumpFrameBasic("quad_tex3.png", vram);
				} else if (count == 4) {
					dumpFrameBasic("quad_tex4.png", vram);
				} else if (count == 5) {
					dumpFrameBasic("quad_tex5.png", vram);
				} else if (count == 6) {
					dumpFrameBasic("quad_tex6.png", vram);
				} else if (count == 7) {
					dumpFrameBasic("quad_tex7.png", vram);
				} else if (count == 8) {
					dumpFrameBasic("quad_tex8.png", vram);
				} else if (count == 9) {
					dumpFrameBasic("quad_tex9.png", vram);
				} else if (count == 10) {
					dumpFrameBasic("quad_tex10.png", vram);
				} else if (count == 11) {
					dumpFrameBasic("quad_tex11.png", vram);
				} else if (count == 12) {
					dumpFrameBasic("quad_tex12.png", vram);
				} else if (count == 13) {
					dumpFrameBasic("quad_tex13.png", vram);
				} else if (count == 14) {
					dumpFrameBasic("quad_tex14.png", vram);
				} else if (count == 15) {
					dumpFrameBasic("quad_tex15.png", vram);
				} else if (count == 16) {
					dumpFrameBasic("quad_tex16.png", vram);
				} else if (count == 17) {
					dumpFrameBasic("quad_tex17.png", vram);
				} else if (count == 18) {
					dumpFrameBasic("quad_tex18.png", vram);
				} else if (count == 19) {
					dumpFrameBasic("quad_tex19.png", vram);
				} else if (count == 20) {
					dumpFrameBasic("quad_tex20.png", vram);
				} else if (count == 21) {
					dumpFrameBasic("quad_tex21.png", vram);
				} else if (count == 22) {
					dumpFrameBasic("quad_tex22.png", vram);
				} else if (count == 23) {
					dumpFrameBasic("quad_tex23.png", vram);
				} else if (count == 24) {
					dumpFrameBasic("quad_tex24.png", vram);
				} else if (count == 25) {
					dumpFrameBasic("quad_tex25.png", vram);
				} else if (count == 26) {
					dumpFrameBasic("quad_tex26.png", vram);
				} else if (count == 27) {
					dumpFrameBasic("quad_tex27.png", vram);
				} else if (count == 28) {
					dumpFrameBasic("quad_tex28.png", vram);
				} else if (count == 29) {
					dumpFrameBasic("quad_tex29.png", vram);
				} else if (count == 30) {
					dumpFrameBasic("quad_tex30.png", vram);
				} else if (count == 31) {
					dumpFrameBasic("quad_tex31.png", vram);
				} else if (count == 32) {
					dumpFrameBasic("quad_tex32.png", vram);
				} else if (count == 33) {
					dumpFrameBasic("quad_tex33.png", vram);
				} else if (count == 34) {
					dumpFrameBasic("quad_tex34.png", vram);
				} 
				memset(vram,0,1024*512*2);
				count++;
			}
		}
	}
	dumpFrameBasic("quad_no_tex32.png", vram);
#endif

	int base = 0;

// Screwed up for now, no dither...
#if 0
	// Test Blending functions.
	for (int dither=0; dither < 2; dither++) {
		for (int x=0; x<32; x++) {
			int tex5 = x; // Component in, simulate texture in
			for (int y2=0; y2 < 4; y2++) {
				for (int x2=0; x2 < 4; x2++) {
					blendTestTexRAW(tex5,0/*NA BG*/,0/*Mode*/,refQuadTex[base + (x2+(x*4)) + (y2*128)]);
				}
			}
		}
		base += 128*4;

		for (int mode = 1; mode < 5; mode++) {
			for (int bg = 0; bg < 32; bg++) {
				for (int x=0; x<32; x++) {
					int tex5 = x; // Component in, simulate texture in
					for (int y2=0; y2 < 4; y2++) {
						for (int x2=0; x2 < 4; x2++) {
							// TEX ONLY
							blendTestTexRAW(tex5,bg,mode,refQuadTex[base + (x2+(x*4)) + (y2*128)]);
						}
					}
				}
				base += 128*4;
			}
		}
	}
#endif

	base = 258 * (128*4);

	for (int dither=0; dither < 2; dither++) {
		for (int c=0; c<129; c++) {
			for (int x=0; x<32; x++) {
				int tex5 = x; // Component in, simulate texture in
				for (int y2=0; y2 < 4; y2++) {
					for (int x2=0; x2 < 4; x2++) {
						blendTestTexMod(tex5,c,0/*NA BG*/,0/*Mode*/,refQuadTex[base + (x2+(x*4)) + (y2*128)]);
					}
				}
			}
			base += 128*4;
		}

		for (int mode = 1; mode < 5; mode++) {
			for (int bg = 0; bg < 32; bg++) {
				for (int x=0; x<32; x++) {
					int tex5 = x; // Component in, simulate texture in
					for (int c=0; c<129; c++) {
						for (int y2=0; y2 < 4; y2++) {
							for (int x2=0; x2 < 4; x2++) {
								// TEX ONLY
								blendTestTexMod(tex5,c,bg,mode,refQuadTex[base + (x2+(x*4)) + (y2*128)]);
							}
						}
					}
					base += 128*4;
				}
			}
		}
	}
}

void loadRefQuadNoTex(const char* fileName) {
	FILE* paramF = fopen(fileName,"rb");
	if (paramF) {
		fseek(paramF,0,SEEK_END); int size = ftell(paramF); fseek(paramF,0,SEEK_SET);
		int idx = 0;
		while (!feof(paramF)) {
			char buffer[200];
			u32 a;
			u32 b;
			if (fscanf(paramF,"%08x=%08x\n",&a,&b)) {
				if (a != 0xFFFFFFFF) {
					a<<=1;
					refQuadNoTex[idx++] = b;
					refQuadNoTex[idx++] = b>>16;
				}
			}
			if (idx >= 64*64*((32*4)+1)*2) {
				break;
			}
		}
		fclose(paramF);
	}

#if 0
	int idx=0; 
	int x2=0;
	int y2=0;
	int count = 0;
	while (idx < (64*64*((32*4)+1)*2)) {
		for (int y=0;y < 64;y++) {
			for (int x=0;x < 64;x++) {
				vram[x+x2+((y+y2)*1024)] = refQuadNoTex[idx++];
			}
		}
		x2 += 64;
		if (x2 == 1024) {
			x2 = 0;
			y2 += 64;
			if (y2 == 512) {
				y2 = 0;
				if (count == 0) {
					dumpFrameBasic("quad_no_tex0.png", vram);
				} else if (count == 1) {
					dumpFrameBasic("quad_no_tex1.png", vram);
				} else if (count == 2) {
					dumpFrameBasic("quad_no_tex2.png", vram);
				} else if (count == 3) {
					dumpFrameBasic("quad_no_tex3.png", vram);
				}
				memset(vram,0,1024*512*2);
				count++;
			}
		}
	}
	dumpFrameBasic("quad_no_tex2.png", vram);
#endif

	// Test Blending functions.
	int base = 0;
	for (int dither=0; dither < 2; dither++) {
		for (int y=0; y<16; y++) {
			for (int x=0; x<16; x++) {
				int it8 = x + (y<<4); // Component in
				for (int y2=0; y2 < 4; y2++) {
					for (int x2=0; x2 < 4; x2++) {
						blendTest(it8,0/*NA*/,0,refQuadNoTex[base + (x2+(x*4)) + ((y2+(y*4))*64)]);
					}
				}
			}
		}
		base += 64*64;

		for (int mode = 1; mode < 5; mode++) {
			for (int bg = 0; bg < 32; bg++) {
				for (int y=0; y<16; y++) {
					for (int x=0; x<16; x++) {
						for (int y2=0; y2 < 4; y2++) {
							for (int x2=0; x2 < 4; x2++) {
								int it8 = x + (y<<4); // Component in
								blendTest(it8,bg,mode,refQuadNoTex[base + (x2+(x*4)) + ((y2+(y*4))*64)]);
							}
						}
					}
				}
				base += 64*64;
			}
		}
	}
}
#endif


u16 ConvertRGBTo555(u8 r8,u8 g8,u8 b8) {
	return (r8 >> 3) | ((g8 >> 3) << 5) | ((b8 >> 3) << 10);
}

void Convert555ToRGB(u16 rgb555, int& rN, int& gN, int& bN) {
	int rT = (rgb555 & 0x1F);
	int gT = ((rgb555>>5) & 0x1F);
	int bT = ((rgb555>>10) & 0x1F);
/*
	rN = ((rT<<3) | (rT >> 2)) + (rT>>4);
	gN = ((gT<<3) | (gT >> 2)) + (gT>>4);
	bN = ((bT<<3) | (bT >> 2)) + (bT>>4);
 */
	rN = ((rT<<3) | (rT >> 2));
	gN = ((gT<<3) | (gT >> 2));
	bN = ((bT<<3) | (bT >> 2));
}

void Get555(u16 rgb555, int& rN, int& gN, int& bN) {
	rN = (rgb555 & 0x1F);
	gN = ((rgb555>>5) & 0x1F);
	bN = ((rgb555>>10) & 0x1F);
}

int C5T8(int t5) {
	return ((t5<<3) | (t5 >> 2));
}

void Convert16To32(u8* buffer, u8* data) {
	for (int y=0; y < 512; y++) {
		for (int x=0; x < 1024; x++) {
			int adr = (x*2 + y*2048);
			int lsb = buffer[adr];
			int msb = buffer[adr+1];
			int c16 = lsb | (msb<<8);
			int r   = (     c16  & 0x1F);
			int g   = ((c16>>5)  & 0x1F);
			int b   = ((c16>>10) & 0x1F);
			r = (r >> 2) | (r << 3);
			g = (g >> 2) | (g << 3);
			b = (b >> 2) | (b << 3);
			int base = (x + y*1024)*4;
			data[base  ] = b;
			data[base+1] = g;
			data[base+2] = r;
			data[base+3] = 255;
		}
	}
}

GPURdrCtx::GPURdrCtx() {
	// Reset everything to zero for now.
	memset(this,0,sizeof(GPURdrCtx));
	GP1_MasterTexDisable = false;
}

u16  GPURdrCtx::sampleTexture(u8 Upixel, u8 Vpixel) {
	int U = Upixel;
	int V = Vpixel;
	u16 pixel;

	switch (this->textFormat2) {
	case 0:
	{
		// 4 Bit
		int subPix = U & 3;
		U = (U>>2) + (this->pageX4);
		V = V      + (this->pageY1);
		int vramAdr = (U & 0x3FF) + (V*1024);
		pixel = this->swBuffer[vramAdr];
		u8 palIndex = (pixel >> (subPix * 4)) & 0xf;
		pixel = this->palette[palIndex];
	}
	break;
	case 1:
	{
		// 8 Bit
		int subPix = U & 1;
		U = (U>>1)  + (this->pageX4);
		V = V       + (this->pageY1);
		int vramAdr = (U & 0x3FF) + (V*1024);
		pixel = this->swBuffer[vramAdr];
		u8 palIndex = (pixel >> (subPix * 8)) & 0xFF;
		pixel = this->palette[palIndex];
	}
	break;
	case 2:
	case 3:
		// 15 bit.
	{
		U = U + this->pageX4;
		V = V + this->pageY1;
				
		int vramAdr = (U & 0x3FF) + (V*1024);
		pixel = this->swBuffer[vramAdr];
	}
	break;
			
	} // End switch case.

	return pixel;
}

void GPURdrCtx::textureUnit(int U, int V, u8& Upixel, u8& Vpixel) {

	/*	DITHERING ATTEMPT

	constexpr int8_t ditherTableU[4][4] = {
		{ 0, 8, 2, 10 },
		{12, 4,14,  6 },
		{ 3,11, 1,  9 },
		{15, 7,13,  5 },
	};
					
	constexpr int8_t ditherTableV[4][4] = {
		{5,13,7,15 },
		{9,1,11,3},
		{6,14,4,12},
		{10,2,8, 0},
	};


	// Put as 
	int idxX = x & 3;
	int idxY = y & 3;

	int vu = ditherTableU[idxX][idxY];
	int vv = ditherTableV[idxX][idxY];

	U += (((vu-7)<<(PREC-4))*4)>>4;
	V += (((vv-7)<<(PREC-4))*4)>>4;

	*/

	// Texture is repeated outside of 256x256 window
	U &= 0xFF;
	V &= 0xFF;

	// Texture masking
	// texel = (texel AND(NOT(Mask * 8))) OR((Offset AND Mask) * 8)
	U = (U & ~(this->texMaskX5 * 8)) | ((this->texOffsX5 & this->texMaskX5) * 8);
	V = (V & ~(this->texMaskY5 * 8)) | ((this->texOffsY5 & this->texMaskY5) * 8);
	
	Upixel = U;
	Vpixel = V;
}

// #define COLOR_PERFECT

// target,tr,tg,tb,tBit15,transp, cR, cG, c
u16 GPURdrCtx::blend(int x, int y, u16 target, bool allowBlend,/*bool transp,*/ bool tBit15,int FR,int FG,int FB) {
	// ([Bit 15 of Texel skip transp -> Full opaque] || noTexture)

	// [Same conditions as HW]
	// case ({px_transparent,px_STP,!noblend})
	// 011
	// [10]0  If 'transp' then tBit15 is ZERO ALWAYS BY CONSTRUCTION (transp => TEX pixel 16 bit == 0)
	// [10]1
	// -> Simplifies to :
	// 011
	// 1 x
	//
	bool blend = (allowBlend & this->rtUseSemiTransp);
	if (blend) {
		int BG_R,BG_G,BG_B;
#if 1
		Convert555ToRGB(target,BG_R,BG_G,BG_B);
#else
		Get555(target,BG_R,BG_G,BG_B);
		FR >>= 3;
		FG >>= 3;
		FB >>= 3;
#endif

		if (this->semiTransp2 == 0) {
			// Do nothing, as 0.5
			BG_R <<= 1;
			BG_G <<= 1;
			BG_B <<= 1;
		} else {
			BG_R <<= 2;
			BG_G <<= 2;
			BG_B <<= 2;
		}

		// Overrride output
		switch (this->semiTransp2) {
		case 0:
			// 0.5
			FR <<= 1;
			FG <<= 1;
			FB <<= 1;
			break;
		case 1:
			FR <<= 2;
			FG <<= 2;
			FB <<= 2;
			break;
		case 2:
			FR = -(FR<<2);
			FG = -(FG<<2);
			FB = -(FB<<2);
			break;
		case 3:
			// Default 0.25
			break;
		}

		FR = (BG_R + FR)>>2;
		FG = (BG_G + FG)>>2;
		FB = (BG_B + FB)>>2;

		// HW Has rounding here. because we export 8 to dither unit.
		if (FR < 0)   { FR = 0; }
		if (FG < 0)   { FG = 0; }
		if (FB < 0)   { FB = 0; }
#if 1
		if (FR > 255) { FR = 255; }
		if (FG > 255) { FG = 255; }
		if (FB > 255) { FB = 255; }
#else
		if (FR > 255) { FR = 31; }
		if (FG > 255) { FG = 31; }
		if (FB > 255) { FB = 31; }
		FR = C5T8(FR);
		FG = C5T8(FG);
		FB = C5T8(FB);
#endif
	}

	static const int ditherTable[4][4] = {
		{-4, +0, -3, +1},  //
		{+2, -2, +3, -1},  //
		{-3, +1, -4, +0},  //
		{+3, -1, +2, -2}   //
	};

	/*	- Dither enable (in Texpage command) affects ONLY polygons that do use Gouraud Shading or Texture Blending.
		- If dithering is enabled (via Texpage command), then both monochrome and shaded lines are drawn with dithering (this differs from monochrome polygons and monochrome rectangles).
		- Rectangle => gouroud shading is not possible => dithering isn't applied.

		POLYGONs (triangles/quads) are dithered ONLY if they do use gouraud shading or texture blending.
		LINEs are dithered (no matter if they are mono or do use gouraud shading).
		RECTs are NOT dithered (no matter if they do use texture blending).
	*/

	//  Dither Enable  (Disable for Rectangle)
	//  +                                                                             Texture x Color     or   PerVtx (Gouraud)
	if (this->dither && ((this->disableTexture && this->GP1_MasterTexDisable) || (this->rtIsTexModRGB || this->rtIsPerVtx || this->isLine))) {
		int d = ditherTable[y & 3][x & 3];
		FR += d;
		FG += d;
		FB += d;
	}

	// Color Clamping	
	if (FR < 0)   { FR = 0; }
	if (FG < 0)   { FG = 0; }
	if (FB < 0)   { FB = 0; }
	if (FR > 255) { FR = 255; }
	if (FG > 255) { FG = 255; }
	if (FB > 255) { FB = 255; }

	return ConvertRGBTo555(FR,FG,FB) | (tBit15 ? 0x8000 : 0x0000);
}

void GPURdrCtx::pixelPipeline(s16 x, s16 y, Interpolator& interp) {
	bool tBit15;
	
	// Out of buffer, clipping.
	if (x < 0 || x > 1023) { return; }
	if (y < 0 || y >  511) { return; }

	// Both register inclusive ( TODO : X1,Y1 sure ? 1023 max seem inclusive)
	if ((x < this->drAreaX0_10) || (x > this->drAreaX1_10)) { return; } 
	if ((y < this->drAreaY0_9)  || (y > this->drAreaY1_9 )) { return; }

	int cR = interp.rinterp;
	int cG = interp.ginterp;
	int cB = interp.binterp;

	bool transp = false;
	bool allowBlend;

	if ((this->disableTexture && this->GP1_MasterTexDisable) || !this->rtIsTextured) {
		tBit15		= false;
		allowBlend	= true;
	} else {
		u8 tr,tg,tb;
		u8 uCoord,vCoord;
		this->textureUnit(interp.uinterp,interp.vinterp,/*out*/uCoord,/*out*/vCoord);

#if 0
		{
			int U = (uCoord>>2) + (this->pageX4);
			int V = vCoord      + (this->pageY1);
			long long int vramAdr = (U & 0x3FF) + (V*1024);	//	printf("X:%i,Y:%i->U:%i,V:%i->Adr:%p\n",x,y,uCoord,vCoord,vramAdr);
		}
#endif

		u16 texel = this->sampleTexture(uCoord,vCoord);
		tr		=  texel      & 0x1F;
		tg		= (texel>> 5) & 0x1F;
		tb		= (texel>>10) & 0x1F;
		tBit15  = (texel>>15) & 0x1 ? true : false;
		allowBlend = tBit15;

		if (texel == 0) {
			return;
		}

		// When texturing interp x 2.
		if (this->rtIsTexModRGB) {

#ifdef COLOR_PERFECT
			// [Supposedly perfect]
			cR = ((cR*2) * tr) / 31;
			cG = ((cG*2) * tg) / 31;
			cB = ((cB*2) * tb) / 31;
#else
			// HW
			cR = ((cR*2) * tr) / 32;
			cG = ((cG*2) * tg) / 32;
			cB = ((cB*2) * tb) / 32;
#endif

			if (cR > 255) { cR = 255; }
			if (cG > 255) { cG = 255; }
			if (cB > 255) { cB = 255; }
		// else RAW mode.
		} else {
			// HW use multiplication by x255 then div 256.

#ifdef COLOR_PERFECT
			// [Supposedly perfect]
			cR = (tr << 3) | (tr>>2);
			cG = (tg << 3) | (tg>>2);
			cB = (tb << 3) | (tb>>2);
#else
			// GPU HW 5 -> 8 Bit conversion crappy...
			// But should be ok for blending anyway.
			// HW use 128 (white) x 2
			cR = (tr * 256) / 32;	
			cG = (tg * 256) / 32;
			cB = (tb * 256) / 32;
#endif
		}
	}

	int idx = x + y*1024;
	u16 target    = this->swBuffer[idx];
	bool isMarked = (target >> 15) ? true : false;

	if (!this->checkMask || (this->checkMask && !isMarked)) {
		u16 color = this->blend(x,y,target,allowBlend,tBit15, cR, cG, cB);
		this->swBuffer[idx] = color | ((this->forceMask|isMarked) ? 0x8000 : 0x0);
		// printf("%i,%i = (%i,%i,%i)\n",x,y,(color>>0)&0x1F,(color>>5)&0x1F,(color>>10)&0x1F);
	}
}

int min3(int a, int b, int c) {
	int p1 = a < b ? a  : b;
	return  p1 < c ? p1 : c;
}

int max3(int a, int b, int c) {
	int p1 = a > b ? a  : b;
	return  p1 > c ? p1 : c;
}

int maxM(int a, int b) {
	return a > b ? a  : b;
}

int minM(int a, int b) {
	return a < b ? a  : b;
}

// Is Horizontal and going from 
static bool isTopLeft(const Vertex& e) { return e.y < 0 || (e.y == 0 && e.x < 0); }
static bool isTopLeft(int x, int y)    { return   y < 0 || (  y == 0 &&   x < 0); }

int orient2d(const Vertex& a, const Vertex& b, const Vertex& c)
{
    return (b.x-a.x)*(c.y-a.y) - (b.y-a.y)*(c.x-a.x);
}

bool PrimitiveSetup::BBox(GPURdrCtx& psx, Vertex** ppVertex, int vCount) {
	int minX = 0x7FFFFFFF;
	int minY = 0x7FFFFFFF;
	int maxX = 0x80000000;
	int maxY = 0x80000000;

	for (int n=0; n < vCount; n++) {
		Vertex& v = *ppVertex[n];
		minX = minM(minX, v.x);
		minY = minM(minY, v.y);
		maxX = maxM(maxX, v.x);
		maxY = maxM(maxY, v.y);
	}

	minXTri = minX;
	maxXTri = maxX;
	minYTri = minY;
	maxYTri = maxY;

	sizeW = maxX - minX;
	sizeH = maxY - minY;

	if (minX > psx.drAreaX1_10) { return true; }
	if (minY > psx.drAreaY1_9 ) { return true; }
	if (maxX < psx.drAreaX0_10) { return true; }
	if (maxY < psx.drAreaY0_9 ) { return true; }

	// Clip against screen bounds (valid for all, different from HW logic, but same result)
	minTriDAX0 = maxM(minX, psx.drAreaX0_10);
	maxTriDAX1 = minM(maxX, psx.drAreaX1_10);

	minTriDAY0 = maxM(minY, psx.drAreaY0_9);
	maxTriDAY1 = minM(maxY, psx.drAreaY1_9);

	if (sizeW > 1023) { return true; }
	if (sizeH >  511) { return true; }
	return false;
}

bool PrimitiveSetup::SetupRect(GPURdrCtx& psx, Vertex** ppVertex) {

	if (BBox(psx, ppVertex,4)) {
		return false;
	}

	uxR   = 0;
	vyR   = 0;

	uxG   = 0;
	vyG   = 0;

	uxB   = 0;
	vyB   = 0;

	uxU   = (psx.texXFlip ? -1 : 1)<<PREC;
	vyU   = 0;

	uxV   = 0;
	vyV   = (psx.texYFlip ? -1 : 1)<<PREC;

	return true;
}

bool PrimitiveSetup::Setup(GPURdrCtx& psx, Vertex** ppVertex, bool isLineCommand) {

	// ---------------------------------------------------
	//   Per Triangle
	// ---------------------------------------------------
	// 1. Triangle as a 2D Matrix
	//
	//  11 bit signed coord, 11 bit delta X, 10 bit delta Y (overflow -> reject)
	//
	// => Compute a,b,d,c as 12 bit and compute rejection here...
	//    but will use a,b,c,d wire as 11 bit for further computation.

	if (BBox(psx,ppVertex,isLineCommand ? 2 : 3)) {
		return false;
	}

	Vertex& v0 = *ppVertex[0];
	Vertex& v1 = *ppVertex[1];
	Vertex& v2 = *ppVertex[isLineCommand ? 0 : 2]; // Just a trap to use the same code...

	int nv0x	= -v0.x;
	int nv0y	= -v0.y;
	a = v2.x + nv0x;
	b = v2.y + nv0y;
	c = v1.x + nv0x;
	d = v1.y + nv0y;
	e = v2.x - v1.x;
	f = v1.y - v2.y;

	special = ((f==0) || (b==0) || (d == 0));

	// Primitive wider than 1024 pixel
	if (!isLineCommand) {
		if (!(((a>>10)==0) || ((a>>10)==-1))) {
			return false;
		}
	}
	if (!(((c>>10)==0) || ((c>>10)==-1))) {
		return false;
	}

	// Primitive taller than 1024 pixel
	if (!isLineCommand) {
		if (!(((b>>9)==0) || ((b>>9)==-1))) {
			return false;
		}
	}
	if (!(((d>>9)==0) || ((d>>9)==-1))) {
		return false;
	}

	// Line primitive
	if (isLineCommand) {
		isNegXAxis = c < 0;
		isNegYAxis = d < 0;
		int  absXAxis   = isNegXAxis ? -c : c;
		int  absYAxis   = isNegYAxis ? -d : d;
		swapAxis    = absYAxis > absXAxis;
		aDX2		= swapAxis   ? absYAxis : absXAxis;
		aDY2		= swapAxis   ? absXAxis : absYAxis;
		int  initialD   = (aDY2<<1) | (swapAxis ? 0:1); // It is !swapAXIS, INVERSE OF SWAP AXIS !!!
		DLine = initialD;
	}

	if (isLineCommand) {
		a = d;
		b = -c;
	}

	// Delta constants
	const Vertex D12(e,  f);
	const Vertex D20(-a, b);
	const Vertex D01(c, -d); // Warning Y is V0-V1, not V1-V0

	// Fill rule
	bias[0] = isTopLeft(D12) ? -1 : 0;
	bias[1] = isTopLeft(D20) ? -1 : 0;
	bias[2] = isTopLeft(D01) ? -1 : 0;

	// 2. DET result 
	int D  = a*d - b*c;
	DET = D;
	DETPOS = (DET>=0);

	if (DET == 0 && (!isLineCommand)) {
		return false;
	}

	int C20iR = isLineCommand ? 0 : v2.r - v0.r;
	int C10iR = v1.r - v0.r;
	int C20iG = isLineCommand ? 0 : v2.g - v0.g;
	int C10iG = v1.g - v0.g;
	int C20iB = isLineCommand ? 0 : v2.b - v0.b;
	int C10iB = v1.b - v0.b;
	int C20iU = isLineCommand ? 0 : v2.u - v0.u;
	int C10iU = v1.u - v0.u;
	int C20iV = isLineCommand ? 0 : v2.v - v0.v;
	int C10iV = v1.v - v0.v;

//	int PREC = 11; // 9 or 10... Float also generate same line error.

	// 10b + 8b + 10b = 28
	if (D != 0) {
		int uhiR  = (( d * C20iR)<<PREC)/D;
		int vhiR  = ((-c * C20iR)<<PREC)/D;
		int uviR  = ((-b * C10iR)<<PREC)/D;
		int vviR  = (( a * C10iR)<<PREC)/D;
		uxR   = uhiR+uviR;
		vyR   = vhiR+vviR;
	} else {
		uxR   = 0;
		vyR   = 0;
	}

	// 2 DIV Unit in // is NICE. -> Faster setup, but easier addition too. (Same timing)
	if (D != 0) {
		int uhiG  = (( d * C20iG)<<PREC)/D;
		int vhiG  = ((-c * C20iG)<<PREC)/D;
		int uviG  = ((-b * C10iG)<<PREC)/D;
		int vviG  = (( a * C10iG)<<PREC)/D;
		uxG   = uhiG+uviG;
		vyG   = vhiG+vviG;
	} else {
		uxG   = 0;
		vyG   = 0;
	}

	if (D != 0) {
		int uhiB  = (( d * C20iB)<<PREC)/D;
		int vhiB  = ((-c * C20iB)<<PREC)/D;
		int uviB  = ((-b * C10iB)<<PREC)/D;
		int vviB  = (( a * C10iB)<<PREC)/D;
		uxB   = uhiB+uviB;
		vyB   = vhiB+vviB;
	} else {
		uxB   = 0;
		vyB   = 0;
	}

	if (D != 0) {
		int uhiU  = (( d * C20iU)<<PREC)/D;
		int vhiU  = ((-c * C20iU)<<PREC)/D;
		int uviU  = ((-b * C10iU)<<PREC)/D;
		int vviU  = (( a * C10iU)<<PREC)/D;
		uxU   = (uhiU+uviU);
		vyU   = vhiU+vviU;
	} else {
		uxU   = 0;
		vyU   = 0;
	}

	if (D != 0) {
		int uhiV  = (( d * C20iV)<<PREC)/D;
		int vhiV  = ((-c * C20iV)<<PREC)/D;
		int uviV  = ((-b * C10iV)<<PREC)/D;
		int vviV  = (( a * C10iV)<<PREC)/D;
		uxV   = uhiV+uviV;
		vyV   = (vhiV+vviV);
	} else {
		uxV   = 0;
		vyV   = 0;
	}

	return true;
}

void PrimitiveSetup::NextLinePixel() {
	bool changeDir = DLine > aDX2;
	int incrDOff   = (~(aDX2<<1)) + 1; // -2 * aDX2
	int incrD      = (aDY2<<1) + (changeDir ? incrDOff : 0);
	bool incXOK    = (changeDir &  (swapAxis)) | (!swapAxis);
	bool incYOK    = (changeDir & (!swapAxis)) |   swapAxis;

	stepX      = (isNegXAxis ? -1:+1) * (incXOK ? 1:0);
	stepY      = (isNegYAxis ? -1:+1) * (incYOK ? 1:0);
	DLine      = DLine + incrD;
}

void PrimitiveSetup::LineEqu(int x, int y, Vertex** ppVertex, int* equ) {
	Vertex& v0 = *ppVertex[0];
	Vertex& v1 = *ppVertex[1];
	Vertex& v2 = *ppVertex[2];

	int distYV1 = y - v1.y;	
	int distXV1 = x - v1.x;

	int distYV2 = y - v2.y;	
	int distXV2 = x - v2.x;

	int distYV0 = y - v0.y;	
	int distXV0 = x - v0.x;

	equ[0] = (   e*distYV1) + (   f*distXV1) + bias[0];
	equ[1] = ((-a)*distYV2) + (   b*distXV2) + bias[1];
	equ[2] = (   c*distYV0) + ((-d)*distXV0) + bias[2];
}

bool PrimitiveSetup::perPixelTriangle	(int x, int y, Vertex** ppVtx) {
	LineEqu(x, y, ppVtx, w);
//	wire isCCWInsideL 					= !(w0L[EQUMSB] | w1L[EQUMSB] | w2L[EQUMSB]); // Same as : (w0 >= 0) && (w1 >= 0) && (w2 >= 0)
	bool isCCWInside =  ((w[0] >= 0)&(w[1] >= 0)&(w[2] >= 0));	// All positive.
//	wire isCWInsideL  					=  (w0L[EQUMSB] & w1L[EQUMSB] & w2L[EQUMSB]); // Same as : (w0 <  0) && (w1  < 0) && (w2  < 0)
	bool isCWInside  =  ((w[0] & w[1] & w[2])<0);				// All Negative.

	return isCCWInside | isCWInside;
}

void PrimitiveSetup::perPixelInterp		(int x, int y, Vertex** ppVtx, Interpolator& interp) {
	Vertex* pV0 = ppVtx[0];
	int distX = x - pV0->x;
	int distY = y - pV0->y;

	int offR  = (distX*uxR + distY*vyR) + (1<<(PREC-1));
	int offG  = (distX*uxG + distY*vyG) + (1<<(PREC-1));
	int offB  = (distX*uxB + distY*vyB) + (1<<(PREC-1));
	int offU  = (distX*uxU + distY*vyU) + (1<<(PREC-1));
	int offV  = (distX*uxV + distY*vyV) + (1<<(PREC-1));

	interp.rinterp = pV0->r +  (offR>>PREC);
	interp.ginterp = pV0->g +  (offG>>PREC);
	interp.binterp = pV0->b +  (offB>>PREC);
	interp.uinterp = pV0->u +  (offU>>PREC);
	interp.vinterp = pV0->v +  (offV>>PREC);
}

int GPURdrCtx::RenderTriangleGPU(Vertex* pVertex, u8 id0, u8 id1, u8 id2) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

	primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/);

	isLine = false;
	
	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TRIANGLE_START = 7,
		START_LINE_TEST_LEFT = 9,
		START_LINE_TEST_RIGHT = 10,
		SCAN_LINE = 11,
		SCAN_LINE_CATCH_END = 12,
		EXIT = 50,
	};

	enum XSel {
		BBOX_LEFT,
		BBOX_RIGHT,
		NEXT_PIXELX,
		AS_IS_X
	};

	enum YSel {
		BBOX_TOP,
		AS_IS_Y,
		NEXT_PIXELY,
	};

	ScanState	state		= TRIANGLE_START;
	XSel		selX		= BBOX_LEFT;
	YSel        selY		= BBOX_TOP;

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	p.x = primitiveSetup.minTriDAX0;

	int		prevZoneCode	= 0;
	int		dir				= 1;

	bool	isPixelFound			= false;
	bool	completedOneDirection	= false;
	int		memCode = 0;

	bool	earlyTriRejectLeft   = primitiveSetup.maxXTri  < drAreaX0_10;
	bool	earlyTriRejectTop    = primitiveSetup.maxYTri  < drAreaY0_9;
	bool	earlyTriRejectRight  = primitiveSetup.minXTri  > drAreaX1_10;
	bool	earlyTriRejectBottom = primitiveSetup.minYTri  > drAreaY1_9;

	bool	earlyTriangleReject	= earlyTriRejectLeft | earlyTriRejectRight | earlyTriRejectTop | earlyTriRejectBottom | ((primitiveSetup.sizeH >= 512) || (primitiveSetup.sizeW >= 1024));

	while (true) {
		// Evaluate Line Equations
		int w[3];
		primitiveSetup.LineEqu(p.x, p.y,ppVertex, w);

		// --- Zone Code ---
		int zoneCode = 0;
		bool outSideLeft  = p.x < primitiveSetup.minTriDAX0;
		bool outSideRight = p.x > primitiveSetup.maxTriDAX1;
		bool outSideTop   = p.y < primitiveSetup.minTriDAY0;
		bool outSideBottom= p.y > primitiveSetup.maxTriDAY1;

		if (w[0] < 0)					{ zoneCode |= 1; } 
		if (w[1] < 0)					{ zoneCode |= 2; }
		if (w[2] < 0)					{ zoneCode |= 4; }
		// Make sure we are always '000' as inside the triangle (reverse code)
		if (primitiveSetup.DETPOS)		{ zoneCode = ~zoneCode & 7; }
		// Add another new code :-)
		if (outSideLeft | outSideRight) { zoneCode |= 8; }

		// -----------------------------------------------------------------------------------------------
		bool insideTriangle = (zoneCode == 0);
		
		// -----------------------------------------------------------------------------------------------

		// TODO

		//wire				isLeftPLXminTri = LPixelX >= minTriDAX0;
		//assign				isRightPLXmaxTri= LPixelX <= maxTriDAX1;
		//wire				isValidHorizontalTriBbox	= isTopInsideBBox & isBottomInsideBBox;
		bool isTopInsideBBox        = !outSideTop;
		bool isBottomInsideBBox		= !outSideBottom;
		bool isValidHorizontalTriBbox = isTopInsideBBox & isBottomInsideBBox;
		bool isInsideBBoxTriRect	= isValidHorizontalTriBbox & /*isLeftPLXminTri*/(!outSideLeft) & /*isRightPLXmaxTri*/(!outSideRight);
		bool isValidPixel			= insideTriangle & isInsideBBoxTriRect;
		bool edgeDidNOTSwitchLeftRightBB	= (zoneCode & 7) == memCode;
		bool outsideTriangle				= edgeDidNOTSwitchLeftRightBB & !isValidPixel;
		bool reachEdgeTriScan			= (((p.x > primitiveSetup.maxXTri) & (dir==1)) || ((p.x < primitiveSetup.minXTri) & (dir==-1)));

		if ((p.x >=0 && p.x <= 1023) && (p.y >= 0) && (p.y <= 511)) {
			this->swBuffer[p.x     + p.y * 1024] = 0x0FF0;
		}

		ScanState tmpPrevState = state;
//		printf("STATE : %i (%i,%i)\n",state, p.x,p.y);
		switch (state) {
		// Scanout
		// Scanin
		case TRIANGLE_START:
			if (earlyTriangleReject || (primitiveSetup.DET == 0)) {
				state = EXIT;
			} else {
				state = START_LINE_TEST_LEFT;
				selX = BBOX_LEFT;
				selY = BBOX_TOP;
			}
			break;
		case START_LINE_TEST_LEFT:
			selY	= AS_IS_Y;
			if (isValidPixel) {
				state	= SCAN_LINE;
				selX	= AS_IS_X;
			} else {
				memCode = zoneCode & 7;
				state	= START_LINE_TEST_RIGHT;
				selX	= BBOX_RIGHT; // Set next X = BBox RIGHT intersected with DrawArea.
			}
			break;
		case START_LINE_TEST_RIGHT:
			selX		= BBOX_LEFT;
			if (outsideTriangle) {
				selY			= NEXT_PIXELY;
				state			= isValidHorizontalTriBbox ? START_LINE_TEST_LEFT : EXIT;
			} else {
				selY	= AS_IS_Y;
				// At the same time.
				isPixelFound			= false;
				completedOneDirection	= false;
				state			= SCAN_LINE;
			}
			break;
		case SCAN_LINE:
			if (isBottomInsideBBox) {
				if (isValidPixel) { // Line Equation.
					if (!isPixelFound) {
						isPixelFound	= true;
					}

					// primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
					// this->pixelPipeline(p.x,p.y,interp);
					this->swBuffer[p.x     + p.y * 1024] = 0x00FF;
				
					// performRefresh(0,0);

					//printf("NS Tri : %i,%i\n",p.x,p.y);
					pixelCounter++;

					selX	= NEXT_PIXELX;
					selY	= AS_IS_Y;
				} else {
					if (isPixelFound) { // Pixel Found.
						selX	= AS_IS_X;
						selY	= NEXT_PIXELY;
						state	= SCAN_LINE_CATCH_END;
					} else {
						// Continue to search for VALID PIXELS...
						selX		= NEXT_PIXELX;

						// Trick : Due to FILL CONVENTION, we can reach a line WITHOUT A SINGLE PIXEL !
						// -> Need to detect that we scan too far and met nobody and avoid out of bound search.
						// COMMENTED OUT enteredTriangle test : some triangle do write pixels sparsely when very thin !!!!
						// No choice except scanning until Bbox edge, no early skip...
						if (reachEdgeTriScan) {
							if (completedOneDirection) {
								selY			= NEXT_PIXELY;
								state			= SCAN_LINE_CATCH_END;
							} else {
								dir				= -dir;
								completedOneDirection = 1;
								selY			= AS_IS_Y;
								state			= SCAN_LINE;
							}
						} else {
							selY			= AS_IS_Y;
							state			= SCAN_LINE;
						}
					}
				}
			} else {
				selY	= AS_IS_Y;
				selX	= AS_IS_X;
				state	= EXIT;
			}
			break;
		case SCAN_LINE_CATCH_END:
			selY	= AS_IS_Y;
			if (isValidPixel) {
				selX	= NEXT_PIXELX;
			} else {
				dir				= -dir;
				selX	= AS_IS_X;
				
				// At the same time.
				isPixelFound	= false;
				completedOneDirection	= false;
				state			= SCAN_LINE;
			}

			break;
		case EXIT:
			goto outLoop;
		}

		switch (selX) {
		case BBOX_LEFT		: p.x = primitiveSetup.minTriDAX0; break;
		case BBOX_RIGHT		: p.x = primitiveSetup.maxTriDAX1;break;
		case NEXT_PIXELX	: p.x += dir; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}

		switch (selY) {
		case BBOX_TOP		: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case NEXT_PIXELY	: p.y += offsetY; break;
		case AS_IS_Y		: /* Do nothing*/ break;
		}


#if 0
		performRefresh(0,0);
#endif
	}

outLoop:
	return pixelCounter;
}

// PAIR VERSION
#if 0
int GPURdrCtx::RenderTriangleNSPair(Vertex* pVertex, u8 id0, u8 id1, u8 id2, int refColor) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

//	triangleCounter++;

	if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
		// Skip primitive.
		return 0;
	}

	isLine = false;

	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TESTLEFT,
		TESTRIGHT,
		SEARCH_OUT,
		SNAKE,
		CLIP_CASE,
		EXIT,
	};

	enum XSel {
		BBOX_LEFT,
		BBOX_RIGHT,
		NEXT_PIXELX,
		AS_IS_X
	};

	enum YSel {
		BBOX_TOP,
		AS_IS_Y,
		NEXT_PIXELY,
	};

	ScanState	state		= TESTLEFT;
	ScanState   prevState	= TESTLEFT;
	XSel		selX		= BBOX_LEFT;
	YSel        selY		= BBOX_TOP;

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	// Pair Work.
	p.x = (primitiveSetup.minTriDAX0>>1)<<1;
//	p.x = primitiveSetup.minTriDAX0;

	int		saveZoneCode	= 0;
	int		dir				= 2;
	bool	foundFirst	= false;
	bool	wasInside   = false;
	bool	wasVertical = false;

	bool    first       = true;

	u16 fColor = 0x00FF;

	while (p.y <= primitiveSetup.maxTriDAY1) {
		bool renderDebug = false;

		// Evaluate Line Equations
		int w0[3];
		int w1[3];
		primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);

		// --- Zone Code ---
		int zoneCode[2];
		zoneCode[0] = 0;
		zoneCode[1] = 0;

		bool outSideLeft0  = p.x     < primitiveSetup.minTriDAX0;
		bool outSideRight0 = p.x     > primitiveSetup.maxTriDAX1;
		bool outSideLeft1  = (p.x+1) < primitiveSetup.minTriDAX0;
		bool outSideRight1 = (p.x+1) > primitiveSetup.maxTriDAX1;

		bool outSideLeft   = outSideLeft0  & outSideLeft1;
		bool outSideRight  = outSideRight0 & outSideRight1;

		if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
		if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
		if (w0[2] >= 0)					{ zoneCode[0] |= 4; }

		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }

		// Make sure we are always '111' as inside the triangle (reverse code)
		if (!primitiveSetup.DETPOS)		{
			zoneCode[0] = ~zoneCode[0] & 7; 
			zoneCode[1] = ~zoneCode[1] & 7; 
		}

		// WARNING : DONE BEFORE DIR CHANGES in STATE.
		int zoneCodePair = dir > 0 ? zoneCode[1] : zoneCode[0];

		// Add another new code :-)
//		if (outSideLeft0 ) { zoneCode[0] |= 8;  }
//		if (outSideRight0) { zoneCode[0] |= 16; }
	/*
		if (outSideLeft1 ) { zoneCode[1] |= 8;  }
		if (outSideRight1) { zoneCode[1] |= 16; }
	*/
		// -----------------------------------------------------------------------------------------------
		bool insideTriangle = (zoneCode[0] == 0) || (zoneCode[1] == 0);
		// -----------------------------------------------------------------------------------------------

		bool saveCode    = false;
		bool reverseCode = false;

#if 1
		if ((p.x >=0 && p.x <= 1023) && (p.y >= 0) && (p.y <= 511)) {
			this->swBuffer[p.x     + p.y * 1024] = 0x0FF0;
			this->swBuffer[(p.x+1) + p.y * 1024] = 0x0FF0;
		}
#endif
		// PAIR STUFF : outsideLeft and outsideRight are BOTH PIXEL OUT LEFT or RIGHT => outSideLeft = outSideLeft0 & outSideLeft1, same for outsideRight.
		//				insideTriangle = insideTriangleLeft | insideTriangleRight
		//				zoneCode       = (dir > 0) ? zoneCode[1] : zoneCode[0]
		//					PB : dir with TESTLEFT right. Should be -1 at LEFT, +1 at RIGHT

		prevState = state;
#define DBG_TRI	(1)

#if DBG_TRI
		printf("State :%i,%i,%i\n",state,p.x,p.y);
#endif
		switch (state) {
		// Scanout
		// Scanin
		case TESTLEFT:
			if (insideTriangle) {
				state = SNAKE;
				selX  = AS_IS_X;	
				selY  = AS_IS_Y;
			} else {
				saveCode = true;
				state = TESTRIGHT;
				selX  = BBOX_RIGHT;
				selY  = AS_IS_Y;
				dir   = -dir;
			}
			break;
		case TESTRIGHT:
			if (otherSide(zoneCodePair,saveZoneCode)) { // Enter a different region makes a bit goes to ZERO.
				// Scan back 
				state = SNAKE;
				saveCode = true;
				first   = false;
				selX  = AS_IS_X;
				selY  = AS_IS_Y;
			} else {
				// Same side
				state= TESTLEFT;
				selY = NEXT_PIXELY;
				selX = BBOX_LEFT;
				dir  = -dir;
				first = true;
			}
			break;
		case SNAKE:
			if (insideTriangle && (!(outSideLeft || outSideRight))) {
				if (zoneCode[0] == 0 && (!(outSideLeft0|outSideRight0))) {
//					printf("%i,%i\n",p.x,p.y);
	#if CHECK_AGAINSTREF
					int offset = p.x + p.y * 1024;
//					if (this->swBuffer[offset] == refColor) {
						this->swBuffer[offset] = 0x00FF;
//					}
					pixelCounter++;
	#else
					primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
					this->pixelPipeline(p.x,p.y,interp);
					pixelCounter++;
	#endif
				}
				if (zoneCode[1] == 0 && (!(outSideLeft1|outSideRight1))) {
//					printf("%i,%i\n",p.x+1,p.y);
	#if CHECK_AGAINSTREF
					int offset = (p.x+1) + p.y * 1024;
//					if (this->swBuffer[offset] == refColor) {
						this->swBuffer[offset] = 0x00FF;
//					}
					pixelCounter++;
	#else
					primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
					this->pixelPipeline(p.x,p.y,interp);
					pixelCounter++;
	#endif
				}

				selX	= NEXT_PIXELX;
				selY	= AS_IS_Y;
			} else {
				if (outSideLeft) {
					selX	= NEXT_PIXELX;
					selY	= NEXT_PIXELY;
					state   = CLIP_CASE;
					dir     = 2;
				} else if (outSideRight) {
					selX	= NEXT_PIXELX;
					selY	= NEXT_PIXELY;
					state   = CLIP_CASE;
					dir     = -2;
				} else {
					if (first || otherSide(zoneCodePair,saveZoneCode)) {
						first   = false;
						saveCode = true;
						state   = SEARCH_OUT;
						selX	= AS_IS_X;
						selY	= NEXT_PIXELY;
					} else {
						selX	= NEXT_PIXELX;
						selY	= AS_IS_Y;
					}
				}
			}
			break;
		case CLIP_CASE:
			if (!insideTriangle) {
				first    = false;
			}
			saveCode    = !insideTriangle;
			reverseCode = insideTriangle;
			state       = insideTriangle ? SNAKE : TESTLEFT;
			first		= !insideTriangle;
			dir         = insideTriangle ? dir : 2;
			selX	    = insideTriangle ? AS_IS_X : BBOX_LEFT;
			selY	    = AS_IS_Y;
			break;
		case SEARCH_OUT:
			// - We scan until we exit the triangle on the left or right, turn around and render the whole line
			// - Need to handle the case where clipping is better the exit left or right too.
			//
			renderDebug = true;
			selY	= AS_IS_Y;
			if ((!insideTriangle) || (outSideLeft || outSideRight)) { // Force to scan and render...
				state	= SNAKE;
				if (outSideLeft) {
					selX	= BBOX_LEFT;
					dir		= 2;
				} else {
					if (outSideRight) {
						selX	= BBOX_RIGHT;
						dir		= -2;
					} else {
						selX	= AS_IS_X;
						saveCode = true;
						dir		 = -dir;
					}
				}
			} else {
				selX	= NEXT_PIXELX;
			}
			break;
		case EXIT:
			goto outLoop;
		}

#if 0
		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0>>1)<<1;   break;
		case BBOX_RIGHT		: p.x = ((primitiveSetup.maxTriDAX1>>1)<<1)+1;break;
		case NEXT_PIXELX	: p.x += dir*2; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}
#else
		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0);   break;
		case BBOX_RIGHT		: p.x =  (primitiveSetup.maxTriDAX1);   break;
		case NEXT_PIXELX	: p.x += dir; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}
#endif

		switch (selY) {
		case BBOX_TOP		: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case NEXT_PIXELY	: p.y += offsetY; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}


		// if (selY == NEXT_PIXELY) {
		// }

		// Copy
		if (saveCode) {
			saveZoneCode = zoneCodePair & 0x7;
		}
		if (reverseCode) {
			saveZoneCode = ~zoneCodePair & 0x7;
		}

#if DBG_TRI
		static int cnt = 0; cnt++; /*if ((cnt & 0xF)==0)*/ { performRefresh(0,0); }
#endif
	}

outLoop:
	/*
	for (p.y = primitiveSetup.minTriDAY0 + startOffset; p.y <= primitiveSetup.maxTriDAY1; p.y += offsetY) {
		for (p.x = primitiveSetup.minTriDAX0; p.x <= primitiveSetup.maxTriDAX1; p.x++) {

			// If p is on or inside all edges, render pixel.
			if (primitiveSetup.perPixelTriangle(p.x,p.y,ppVertex)) {
				this->pixelPipeline(p.x,p.y,interp);
				pixelCounter++;
			}
		}
	}
	*/

	return pixelCounter;
}

int GPURdrCtx::RenderTriangleNSPair(Vertex* pVertex, u8 id0, u8 id1, u8 id2, int refColor) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

	triangleCounter++;

	if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
		// Skip primitive.
		return 0;
	}

	isLine = false;

	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TESTLEFT,
		TESTRIGHT,
		SEARCH_OUT,
		SNAKE,
		CLIP_CASE,
		EXIT,
	};

	enum XSel {
		BBOX_LEFT,
		BBOX_RIGHT,
		NEXT_PIXELX,
		AS_IS_X
	};

	enum YSel {
		BBOX_TOP,
		AS_IS_Y,
		NEXT_PIXELY,
	};

	ScanState	state		= TESTLEFT;
	ScanState   prevState	= TESTLEFT;
	XSel		selX		= BBOX_LEFT;
	YSel        selY		= BBOX_TOP;

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	// Pair Work.
	p.x = (primitiveSetup.minTriDAX0>>1)<<1;
//	p.x = primitiveSetup.minTriDAX0;

	int		saveZoneCode	= 0;
	int		dir				= 2;
	bool	foundFirst	= false;
	bool	wasInside   = false;
	bool	wasVertical = false;

	bool    first       = true;
	bool	loop		= false;
	int		found		= 0;

	u16 fColor = 0x00FF;

	while (p.y <= primitiveSetup.maxTriDAY1) {
		bool renderDebug = false;

		// Evaluate Line Equations
		int w0[3];
		int w1[3];
		primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);

		// --- Zone Code ---
		int zoneCode[2];
		zoneCode[0] = 0;
		zoneCode[1] = 0;

		bool outSideLeft0  = p.x     < primitiveSetup.minTriDAX0;
		bool outSideRight0 = p.x     > primitiveSetup.maxTriDAX1;
		bool outSideLeft1  = (p.x+1) < primitiveSetup.minTriDAX0;
		bool outSideRight1 = (p.x+1) > primitiveSetup.maxTriDAX1;

		bool outSideLeft   = outSideLeft0  & outSideLeft1;
		bool outSideRight  = outSideRight0 & outSideRight1;

		if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
		if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
		if (w0[2] >= 0)					{ zoneCode[0] |= 4; }

		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }

		// Make sure we are always '111' as inside the triangle (reverse code)
		if (!primitiveSetup.DETPOS)		{
			zoneCode[0] = ~zoneCode[0] & 7; 
			zoneCode[1] = ~zoneCode[1] & 7; 
		}

		// WARNING : DONE BEFORE DIR CHANGES in STATE.
		int zoneCodePair = dir > 0 ? zoneCode[1] : zoneCode[0];

		// Add another new code :-)
//		if (outSideLeft0 ) { zoneCode[0] |= 8;  }
//		if (outSideRight0) { zoneCode[0] |= 16; }
	/*
		if (outSideLeft1 ) { zoneCode[1] |= 8;  }
		if (outSideRight1) { zoneCode[1] |= 16; }
	*/
		// -----------------------------------------------------------------------------------------------
		bool insideTriangle = (zoneCode[0] == 0) || (zoneCode[1] == 0);
		// -----------------------------------------------------------------------------------------------

		bool saveCode    = false;
		bool reverseCode = false;

#if 1
		if ((p.x >=0 && p.x <= 1023) && (p.y >= 0) && (p.y <= 511)) {
			this->swBuffer[(p.x  )   + p.y * 1024] = 0x0FF0;
			this->swBuffer[(p.x+1)   + p.y * 1024] = 0x0FF0;
		}
#endif
		// PAIR STUFF : outsideLeft and outsideRight are BOTH PIXEL OUT LEFT or RIGHT => outSideLeft = outSideLeft0 & outSideLeft1, same for outsideRight.
		//				insideTriangle = insideTriangleLeft | insideTriangleRight
		//				zoneCode       = (dir > 0) ? zoneCode[1] : zoneCode[0]
		//					PB : dir with TESTLEFT right. Should be -1 at LEFT, +1 at RIGHT

		prevState = state;
//		printf("PairState :%i,%i Code:%i",p.x,p.y, zoneCodePair);
		switch (state) {
		// Scanout
		// Scanin
		case TESTLEFT:
//			printf("TEST LEFT\n");
			if (insideTriangle && (!loop)) {
				state = SNAKE;
				selX  = AS_IS_X;	
				selY  = AS_IS_Y;
			} else {
				saveCode = true;
				state = TESTRIGHT;
				selX  = BBOX_RIGHT;
				selY  = AS_IS_Y;
				dir   = -2;
			}
			break;
		case TESTRIGHT:
//			printf("TEST RIGHT\n");
			if (otherSide(zoneCodePair,saveZoneCode) && (!loop)) { // Enter a different region makes a bit goes to ZERO.
				// Scan back 
				state = SNAKE;
				saveCode = true;
				first   = false;
				selX  = AS_IS_X;
				selY  = AS_IS_Y;
				loop  = true;		// FALSE IN Y+2 INCREMENT !!!! IN HW !!! DONT FORGET !!!
			} else {
				// Same side
				state= TESTLEFT;
				selY = NEXT_PIXELY;
				selX = BBOX_LEFT;
				dir  = 2;
				first = true;
			}
			break;
		case SNAKE:
//			printf("SNAKE\n");
			saveCode = true;
			if (insideTriangle && (!(outSideLeft || outSideRight))) {
				if (zoneCode[0] == 0 && (!(outSideLeft0|outSideRight0))) {
//					printf("L %i,%i\n",p.x,p.y);
	#if CHECK_AGAINSTREF
					int offset = p.x + p.y * 1024;
//					if (this->swBuffer[offset] == refColor) {
						this->swBuffer[offset] = 0x00FF;
//					}
					pixelCounter++;
	#else
					primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
					this->pixelPipeline(p.x,p.y,interp);
					pixelCounter++;
	#endif
				}
				if (zoneCode[1] == 0 && (!(outSideLeft1|outSideRight1))) {
//					printf("R %i,%i\n",p.x+1,p.y);
	#if CHECK_AGAINSTREF
					int offset = (p.x+1) + p.y * 1024;
//					if (this->swBuffer[offset] == refColor) {
						this->swBuffer[offset] = 0x00FF;
//					}
					pixelCounter++;
	#else
					primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
					this->pixelPipeline(p.x,p.y,interp);
					pixelCounter++;
	#endif
				}

				found   = 1;
				selX	= NEXT_PIXELX;
				selY	= AS_IS_Y;
			} else {
				if (outSideLeft | outSideRight) {
#if 0
					selX	= NEXT_PIXELX;
					selY	= NEXT_PIXELY;
					state   = CLIP_CASE;
					dir     = outSideLeft ? 2 : -2;
#else
					if (found) {
						selX	= NEXT_PIXELX;
						selY	= NEXT_PIXELY;
						state   = CLIP_CASE;
						dir     = outSideLeft ? 2 : -2;
					} else {
						selY	= AS_IS_Y;
						selX	= BBOX_LEFT;
						state   = TESTLEFT;
						first   = true;
						dir     = 2;
					}
#endif
				} else {
					if (first || otherSide(zoneCodePair,saveZoneCode)) {
						first   = false;
						saveCode = true;

#if 0
						if (found) {
#endif
							state   = SEARCH_OUT;
							found   = 0;
							selX	= AS_IS_X;
							selY	= NEXT_PIXELY;
#if 0
						} else {

							/*
								KIND OF HACK, BUT COULD HAVE A BETTER GENERIC WAY : 
								1/ Any line that EXIT with no pixel drawn.
								2/ That hasnt been tested with a TEST_LEFT/TEST_RIGHT pair already.
									Run the TEST_LEFT/RIGHT.

									BUT there is a LOT OF WASTE => We dont want to scan a line with no pixel again. ???
								
								==> May be this hack is worse, BUT more efficient !!!
							*/

							selY	= AS_IS_Y;
							selX	= BBOX_LEFT;
							state   = TESTLEFT;
							first   = true;
							dir     = 2;
						}
#endif
					} else {
						selX	= NEXT_PIXELX;
						selY	= AS_IS_Y;
					}
				}
			}
			break;
		case CLIP_CASE:
//			printf("CLIP_CASE\n");
			if (!insideTriangle) {
				first    = false;
			}
			saveCode    = !insideTriangle;
			reverseCode = insideTriangle;
			state       = insideTriangle ? SNAKE : TESTLEFT;
			first		= !insideTriangle;
			dir         = insideTriangle ? dir : 2;
			selX	    = insideTriangle ? AS_IS_X : BBOX_LEFT;
			selY	    = AS_IS_Y;
			break;
		case SEARCH_OUT:
//			printf("SEARCH_OUT\n");
			// - We scan until we exit the triangle on the left or right, turn around and render the whole line
			// - Need to handle the case where clipping is better the exit left or right too.
			//
			renderDebug = true;
			selY	= AS_IS_Y;
			if ((!insideTriangle) || (outSideLeft || outSideRight)) { // Force to scan and render...
				state	= SNAKE;
				found	= 0;
				
				if (outSideLeft) {
					selX	= BBOX_LEFT;
					dir		= 2;
				} else {
					if (outSideRight) {
						selX	= BBOX_RIGHT;
						dir		= -2;
					} else {
						selX	= AS_IS_X;
						saveCode = otherSide(zoneCodePair,saveZoneCode);
						dir		 = otherSide(zoneCodePair,saveZoneCode) ? dir : -dir;
					}
				}
			} else {
				found	= 1;
				selX	= NEXT_PIXELX;
			}
			break;
		case EXIT:
			goto outLoop;
		}

#if 0
		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0>>1)<<1;   break;
		case BBOX_RIGHT		: p.x = ((primitiveSetup.maxTriDAX1>>1)<<1)+1;break;
		case NEXT_PIXELX	: p.x += dir*2; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}
#else
		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0);   break;
		case BBOX_RIGHT		: p.x =  (primitiveSetup.maxTriDAX1);   break;
		case NEXT_PIXELX	: p.x += dir; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}
#endif

		switch (selY) {
		case BBOX_TOP		: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case NEXT_PIXELY	: p.y += offsetY; loop = false; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}


		performRefresh(0,0);
		// if (selY == NEXT_PIXELY) {
		// }

		// Copy
		if (saveCode) {
			saveZoneCode = zoneCodePair & 0x7;
		}
		if (reverseCode) {
			saveZoneCode = ~zoneCodePair & 0x7;
		}
	}

outLoop:
	/*
	for (p.y = primitiveSetup.minTriDAY0 + startOffset; p.y <= primitiveSetup.maxTriDAY1; p.y += offsetY) {
		for (p.x = primitiveSetup.minTriDAX0; p.x <= primitiveSetup.maxTriDAX1; p.x++) {

			// If p is on or inside all edges, render pixel.
			if (primitiveSetup.perPixelTriangle(p.x,p.y,ppVertex)) {
				this->pixelPipeline(p.x,p.y,interp);
				pixelCounter++;
			}
		}
	}
	*/

	return pixelCounter;
}
#endif

void GPURdrCtx::RenderRect(Vertex* pVertex) {
	Interpolator interp;
	Vertex* ppVertex[4];
	for (int n=0; n < 4; n++) { ppVertex[n] = &pVertex[n]; }

	primitiveSetup.SetupRect(*this,ppVertex);
	
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	bool backupDither = this->dither;

	// Rect force to false.
	isLine = false;
	this->dither = false;

	// Warning HERE IT IS A RECT : we use < and NOT the <= operator !!! (Width is NOT INCLUDED)
	for (p.y = primitiveSetup.minTriDAY0 + startOffset; p.y <= primitiveSetup.maxTriDAY1; p.y += offsetY) {
		for (p.x = primitiveSetup.minTriDAX0; p.x <= primitiveSetup.maxTriDAX1; p.x++) {
			// If p is on or inside all edges, render pixel.
			primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
			this->pixelPipeline(p.x,p.y,interp);
			pixelCounter++;
		}
	}

	this->dither = backupDither;
}

void GPURdrCtx::RenderLine(Vertex* pVertex, u8 v0, u8 v1) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[v0];
	ppVertex[1] = &pVertex[v1];

	if (!primitiveSetup.Setup(*this,ppVertex,true /*IS A LINE*/)) {
		// Skip primitive.
		return;
	}

	Vertex p = *ppVertex[0];
	Interpolator interp;
	bool itr = this->interlaced;

	isLine = true;
	if (p.x == 16 && p.y == 100) {
		printf("HERE");
	}

	while (true) {
		bool isOdd = p.y & 1 ? true : false;
		if ((!itr) || (itr & (isOdd != this->currentInterlaceFrameOdd))) {
			primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
			this->pixelPipeline(p.x,p.y,interp);
		}

		if ((p.x == ppVertex[1]->x) && (p.y == ppVertex[1]->y)) {
			break;
		}
		primitiveSetup.NextLinePixel();
		p.x += primitiveSetup.stepX;
		p.y += primitiveSetup.stepY;
	}

	isLine = false;
}

void GPURdrCtx::performRefresh(int command, int commandID) {
	if (callback) {
		callback(*this,userContext,command>>24,commandID);
	}
}

enum ParserState {
	COMMAND,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_SIZE,
	LOAD_COLOR,
	EXEC_PRIMITIVE,
};

ParserState stateParser;

enum EPrimitives {
	SPECIAL_CMD		= 0,
	PRIM_TRI		= 1,
	PRIM_LINE		= 2,
	PRIM_RECT		= 3,
	CP_VRAM_VRAM	= 4,
	CP_CPU_VRAM		= 5,
	CP_VRAM_CPU		= 6,
	SPECIAL_SETTINGS= 7,
};

bool	isMultiCmd;
bool	isPerVtxCol;
EPrimitives primitive;
bool	isSizedPrimitive;
bool	isFirstVertex;
int		isHardCodedSize;
int		width,height;
int		vtxCount;
int		vtxCountMax;
u32		operand;
u32		command;
bool	continueLoop;
bool	checkExecPrimitive;

Vertex  vtx[4];

ParserState getVertexOrColorOrEnd() {
	if (isPerVtxCol && continueLoop) {
		return LOAD_COLOR;
	} else {
		isFirstVertex = false;
		vtxCount++;
		return continueLoop ? LOAD_VERTEX : COMMAND;
	}
}

void GPURdrCtx::checkSizeLoad() {
	if (isSizedPrimitive) {
		checkExecPrimitive = true;
		switch (isHardCodedSize)
		{
		case 0:
			checkExecPrimitive = false;
			stateParser = LOAD_SIZE;
			break;
		case 1:
			width = 1; height = 1;
			break;
		case 2:
			width = 8; height = 8;
			break;
		case 3:
			width = 16; height = 16;
			break;
		default:
			break;
		}
	}
}

void GPURdrCtx::execPrimitive() {
	bool issued = false;
	switch (primitive) {
	case PRIM_TRI:
		continueLoop = (vtxCount != (vtxCountMax-1));

		if (vtxCount == 2) {
			issued = true;
			RenderTriangle(vtx,0,1,2);
		}
		if (vtxCount == 3) {
			issued = true;
			RenderTriangle(vtx,3,1,2);
		}

		break;
	case PRIM_LINE:
		if (vtxCount == 0) {
			continueLoop = true;
		} else {
			bool render = true;
			continueLoop = isMultiCmd;
			if (isMultiCmd) {
				continueLoop = ((operand >> 24) != 0x55);
				render = continueLoop;
				// Trick
				vtxCount--;
			}

			if (render) {
				issued = true;
				RenderLine(vtx,0,1);
			}
			vtx[0].x = vtx[1].x;
			vtx[0].y = vtx[1].y;
		}

		if (!continueLoop) {
			vtxCount = 0;
		}
		break;
	case PRIM_RECT:
		// Convert rect into triangle.
		for (int n=1;n < 4; n++) {
			vtx[n] = vtx[0];
		}

		// BBox is INCLUSIVE.
		// But     x+w, y+h is EXCLUSIVE.
		// => x1=x+w and IS RENDERED, same for y1.
		width--;
		height--;

		vtx[1].x += width; vtx[1].y +=      0; vtx[1].u += width; vtx[1].v +=      0; 
		vtx[2].x +=     0; vtx[2].y += height; vtx[2].u +=     0; vtx[2].v += height;
		vtx[3].x += width; vtx[3].y += height; vtx[3].u += width; vtx[3].v += height;

		// Width/Height with -1 post loader will 
		// generate a negative value, width of 1 will make width = 0.
		if (width >= 0 && height >= 0) {
			issued = true;
			RenderRect(vtx);
		}

		continueLoop = false;

		break;

	case SPECIAL_CMD:
		// [TODO : Patch width , height based on FILL, VRAM Copy commands...]

		if ((command >> 24) == 0x2) {
			vtx[0].x += offsetX_s11;
			vtx[0].y += offsetY_s11;

			vtx[0].x &= 0x3F0;
			vtx[0].y &= 0x1FF;
			width	  = ((width & 0x3FF)+15) & (~0xF);
			height    = height & 0x1FF;
			// Contains color
			issued = true;
			referenceFILL(vtx[0].x,vtx[0].y, width, height, this->interlaced, this->currentInterlaceFrameOdd, 
				(vtx[vtxCount & 3].r)       |
				(vtx[vtxCount & 3].g<<8)    |
				(vtx[vtxCount & 3].b<<16) );
		} else {
			// assert(false); // NEVER TESTED / IMPLEMENTED.
		}
		continueLoop = false;
		break;
	case CP_VRAM_VRAM:
		// [TODO INVOKE]
		// assert(false); // NEVER TESTED / IMPLEMENTED.
		continueLoop = false;
		break;
	case CP_VRAM_CPU:
		// [TODO INVOKE]
		// assert(false); // NEVER TESTED / IMPLEMENTED.
		continueLoop = false;
		break;
	case CP_CPU_VRAM:
		// [TODO INVOKE]
		continueLoop = false;
		break;
	}

	if (issued) {
		static int commandID = 0;
		performRefresh(command,commandID);
		commandID++;
	}
}

ParserState commandTriMono[] = {
	LOAD_VERTEX,
	LOAD_VERTEX,
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandQuadMono[] = {
	LOAD_VERTEX,
	LOAD_VERTEX,
	LOAD_VERTEX,
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandTriTex[] = {
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	COMMAND,
};

ParserState commandQuadTex[] = {
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	COMMAND,
};

ParserState commandTriGou[] = {
	LOAD_VERTEX,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_COLOR,
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandQuadGou[] = {
	LOAD_VERTEX,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_COLOR,
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandTriTexGou[] = {
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	COMMAND,
};

ParserState commandQuadTexGou[] = {
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_COLOR,
	LOAD_VERTEX,
	LOAD_TEXTURE,
	COMMAND,
};

ParserState commandLineMono[] = {
	LOAD_VERTEX,
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandLineGou[] = {
	LOAD_VERTEX,
	LOAD_COLOR,
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandSingle[] = {
	COMMAND,
};

ParserState commandRectMono[] = {
	LOAD_VERTEX,
	COMMAND,
};

ParserState commandRectSizeMono[] = {
	LOAD_VERTEX,
	LOAD_SIZE,
	COMMAND,
};

ParserState commandRectTex[] = {
	LOAD_VERTEX,
	LOAD_TEXTURE,
	COMMAND,
};

ParserState commandRectSizeTex[] = {
	LOAD_VERTEX,
	LOAD_TEXTURE,
	LOAD_SIZE,
	COMMAND,
};

ParserState commandFill[] = {
	LOAD_VERTEX,
	LOAD_SIZE,
	COMMAND,
};

ParserState commandC2V_V2C[] = {
	LOAD_VERTEX,
	LOAD_SIZE,
	COMMAND,
};

ParserState commandCopy[] = {
	LOAD_VERTEX,
	LOAD_VERTEX,
	LOAD_SIZE,
	COMMAND,
};


#if USE_WORD_INPUT
// Multiline special.

ParserState* commandParserTable[256] = {
	// 0..7
	commandSingle,
	commandSingle,
	commandFill,		// 0x02
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 8..15
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 16..23
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 24..31
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,

	// 
	// 0..7
	commandTriMono, // 0x20
	commandTriMono,
	commandTriMono,
	commandTriMono, // 0x23
	commandTriTex,
	commandTriTex,
	commandTriTex,
	commandTriTex,
	// 8..15
	commandQuadMono, // 0x28
	commandQuadMono,
	commandQuadMono,
	commandQuadMono, // 0x2B
	commandQuadTex,
	commandQuadTex,
	commandQuadTex,
	commandQuadTex, // 0x2F

	// 16..23
	commandTriGou,
	commandTriGou,
	commandTriGou,
	commandTriGou,
	commandTriTexGou,
	commandTriTexGou,
	commandTriTexGou,
	commandTriTexGou,
	// 24..31
	commandQuadGou,
	commandQuadGou,
	commandQuadGou,
	commandQuadGou,
	commandQuadTexGou,
	commandQuadTexGou,
	commandQuadTexGou,
	commandQuadTexGou,


	// 0..7
	commandLineMono,
	commandLineMono,
	commandLineMono,
	commandLineMono,
	commandLineMono,
	commandLineMono,
	commandLineMono,
	commandLineMono,
	// 8..15
	commandMultiLine,
	commandMultiLine,
	commandMultiLine,
	commandMultiLine,
	commandMultiLine,
	commandMultiLine,
	commandMultiLine,
	commandMultiLine,

	// 16..23
	commandLineGou,
	commandLineGou,
	commandLineGou,
	commandLineGou,
	commandLineGou,
	commandLineGou,
	commandLineGou,
	commandLineGou,
	// 24..31
	commandMultiLineGou,
	commandMultiLineGou,
	commandMultiLineGou,
	commandMultiLineGou,
	commandMultiLineGou,
	commandMultiLineGou,
	commandMultiLineGou,
	commandMultiLineGou,

	// 0..7
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 8..15
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 16..23
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 24..31
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,

	// 0..7
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 8..15
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 16..23
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 24..31
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,

	// 0..7
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 8..15
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 16..23
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 24..31
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,

	// 0..7
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 8..15
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 16..23
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 24..31
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,

	// 0..7
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 8..15
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 16..23
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	// 24..31
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,
	commandSingle,

};
#endif

void GPURdrCtx::writeGP0(u32 word) {
	checkExecPrimitive = false;

	switch (stateParser) {
	case LOAD_COLOR:
		loadColor(word);
		isFirstVertex = false;
		vtxCount++;
		stateParser = continueLoop ? LOAD_VERTEX : COMMAND;
		break;
	case LOAD_SIZE:
		{
			// [Load Size]
			operand = word;
			width	=   operand     & 0x03FF;
			height	= (operand>>16) & 0x01FF;
			checkExecPrimitive = true;
			stateParser = COMMAND;
		}
		break;
	case LOAD_TEXTURE:
		{
			operand = word;
			// Read TexCoord + Palette or texPage or nothing (step 0,1, Nothing=2,3)
			// [Load UV]
			vtx[vtxCount & 3].u = operand & 0xFF;
			vtx[vtxCount & 3].v = (operand>>8) & 0xFF;
			switch (vtxCount) {
			case 0:
				rtClutX = ((operand >> 16)     & 0x3F) * 16;
				rtClutY = (operand >> (16+6)) & 0x1FF;
				break;
			case 1: 
				pageX4  = ((operand >> 16) & 0xF) * 64;
				pageY1  = ((operand >> 20) & 0x1) * 256;
				semiTransp2  = (operand >> 21) & 0x3;
				textFormat2  = (operand >> 23) & 0x3;
				disableTexture	= ((operand>>(11+16)) & 0x1) ? true : false;
				break;
			// Other don't care...
			}
			stateParser = getVertexOrColorOrEnd();
			checkExecPrimitive = true;
			checkSizeLoad();
		}
		break;
	case LOAD_VERTEX:
		{
			// -----------------------------------------
			// [Load Vertex]
			operand = word;
			s16 x = (((s32)operand)<<(16+5))>>(16+5);
			s16 y = (((s32)operand)<<    5 )>>(16+5);
			u8  topV = (operand>>24);
			vtx[vtxCount & 3].x= x + offsetX_s11;
			vtx[vtxCount & 3].y= y + offsetY_s11;
			// -----------------------------------------
			
			if (rtIsTextured) {
				stateParser = LOAD_TEXTURE;
			} else {
				checkExecPrimitive = true;
				stateParser = getVertexOrColorOrEnd();
				checkSizeLoad();
			}
		}
		break;
	case COMMAND:
		{
			printf("------------\nCOMMAND %08x\n",word);
			command			= word;
			continueLoop	= true;

			isMultiCmd		= (command >> 27) & 1; // Quad or polyline...
			isPerVtxCol		= (command >> 28) & 1; // Gouraud... But we interpolated always.
			primitive		= (EPrimitives)((command >> 29) & 7);

			isSizedPrimitive= false;
			isFirstVertex   = true;
			isHardCodedSize = 0;
			width,height	= 0;
			vtxCount		= 0;
			vtxCountMax		= 0;
			operand			= command;

			// ---------- For rendering ------------------
			rtIsTexModRGB	= !((command >> 24) & 1);	// Textured Tri or Rect only. 
			rtIsTextured	=   (command >> 26) & 1;
			rtUseSemiTransp =   (command >> 25) & 1;
			rtIsPerVtx      =  isPerVtxCol;

			switch (primitive) {
			case SPECIAL_CMD:
				// Nop, unssupported, FillRect, IRQ, ...
				switch (command>>24) {
				case 0:
					continueLoop = false; // Nop
					break;
				case 2:
					// Fill command.
					isSizedPrimitive = true;
					break;

				}
				rtIsTextured		= false;
				break;
			case PRIM_TRI:
				vtxCountMax			= isMultiCmd ? 4 : 3;
				break;
			case PRIM_LINE:
				rtIsTextured		= false;
				break;
			case PRIM_RECT:
				isSizedPrimitive	= true;
				isHardCodedSize		= ((command >> 27) & 0x3); // (0=Var, 1=1x1, 2=8x8, 3=16x16)
				break;
			case CP_VRAM_VRAM:
				isSizedPrimitive	= true;
				isPerVtxCol			= false;
				isFirstVertex		= false;
				rtIsTextured		= false;
				break;
			case CP_VRAM_CPU:
				isSizedPrimitive	= true;
				isPerVtxCol			= false;
				isFirstVertex		= false;
				rtIsTextured		= false;
				break;
			case CP_CPU_VRAM:
				isSizedPrimitive 	= true;
				isPerVtxCol			= false;
				isFirstVertex		= false;
				rtIsTextured		= false;
				break;
			case SPECIAL_SETTINGS:
				continueLoop = false;

				switch (command>>24) {
				case 0xE1:
					pageX4			= (command & 0xF) * 64;
					pageY1			= ((command>>4) & 0x1) * 256;
					semiTransp2		= (command>>5) & 0x3;
					textFormat2		= (command>>7) & 0x3;

					dither			= (command>>9) & 0x1;
					displayAreaEnable = (command>>10) & 0x1;
					disableTexture	= (command>>11) & 0x1;
					texXFlip		= (command>>12) & 0x1;
					texYFlip		= (command>>13) & 0x1;
					break;
				case 0xE2:
					texMaskX5		= command & 0x1F;
					texMaskY5		= (command>>5) & 0x1F;
					texOffsX5		= (command>>10) & 0x1F;
					texOffsY5		= (command>>15) & 0x1F;
					break;
				case 0xE3:
					drAreaX0_10		= (command>>0 ) & 0x3FF;
					drAreaY0_9		= (command>>10) & 0x1FF;
					break;
				case 0xE4:
					drAreaX1_10		= (command>>0 ) & 0x3FF;
					drAreaY1_9		= (command>>10) & 0x1FF;
					break;
				case 0xE5:
					offsetX_s11		= ((command<<(16+5))>>(16+5));
					offsetY_s11		= ((command<<(  10))>>(16+5));
					break;
				case 0xE6:
					forceMask		= command & 1 ? true : false;
					checkMask		= command & 2 ? true : false;
					break;
				}
				rtIsTextured		= false;
				break;
			}

			if (continueLoop) {
				loadColor(command);
			}
			stateParser = continueLoop ? LOAD_VERTEX : COMMAND;
		}
		break;
	}

	if (checkExecPrimitive) {
		execPrimitive();
		if (isPerVtxCol && continueLoop) {
			stateParser = LOAD_COLOR;
		}
	}

}

void GPURdrCtx::writeGP1(u32 word) {

}

void GPURdrCtx::loadColor(u32 operand) {
	// -----------------------------------------
	// Always before vertex
	// -----------------------------------------
	
	if (!rtIsTexModRGB && rtIsTextured) {
		operand = 0xFFFFFF; // Force white color for RGB.
	}

	if (isPerVtxCol || isFirstVertex) {
		// [Load Color]
		vtx[vtxCount & 3].r = (operand    ) & 0xFF;
		vtx[vtxCount & 3].g = (operand>>8 ) & 0xFF;
		vtx[vtxCount & 3].b = (operand>>16) & 0xFF;
	} else {
		vtx[vtxCount & 3].r = vtx[0].r;
		vtx[vtxCount & 3].g = vtx[0].g;
		vtx[vtxCount & 3].b = vtx[0].b;
	}
}

void GPURdrCtx::commandDecoder(u32* pStream, u64* pTimeStamps, u8* isGP1, u32 size, postRendercallback callback_, void* userContext_, u64 maxTime) {
	u32* pStreamE = &pStream[size];

	callback	= callback_;
	userContext = userContext_;

	Vertex vtx[4];


	int commandID = 0;
nextCommand:

#if USE_WORD_INPUT

	while (pStreamE != pStream) {
		u32 command = *pStream++;
		writeGP0(command);
	}
#else
	u32 command = *pStream++;
    u64 time    = *pTimeStamps++;

    if (time > maxTime) {
        return;
    }

	if (*isGP1++) {
		if ((command >> 24) == 0x08) {
		#if 0
					GP1(08h) - Display mode

		  0-1   Horizontal Resolution 1     (0=256, 1=320, 2=512, 3=640) ;GPUSTAT.17-18
		  2     Vertical Resolution         (0=240, 1=480, when Bit5=1)  ;GPUSTAT.19
		  3     Video Mode                  (0=NTSC/60Hz, 1=PAL/50Hz)    ;GPUSTAT.20
		  4     Display Area Color Depth    (0=15bit, 1=24bit)           ;GPUSTAT.21
		  5     Vertical Interlace          (0=Off, 1=On)                ;GPUSTAT.22
		  6     Horizontal Resolution 2     (0=256/320/512/640, 1=368)   ;GPUSTAT.16
		  7     "Reverseflag"               (0=Normal, 1=Distorted)      ;GPUSTAT.14
		#endif
			this->interlaced = command & ((1<<2) | (1<<5));
		}
		if ((command>>24) == 0x09) {
			this->GP1_MasterTexDisable = (command & 1) ? true : false;
		}

		if (pStream == pStreamE)
			return ;
		goto nextCommand;
	}

	enum EPrimitives {
		SPECIAL_CMD		= 0,
		PRIM_TRI		= 1,
		PRIM_LINE		= 2,
		PRIM_RECT		= 3,
		CP_VRAM_VRAM	= 4,
		CP_CPU_VRAM		= 5,
		CP_VRAM_CPU		= 6,
		SPECIAL_SETTINGS= 7,
	};

	bool	isMultiCmd		= (command >> 27) & 1; // Quad or polyline...
	bool	isPerVtxCol		= (command >> 28) & 1; // Gouraud... But we interpolated always.
	EPrimitives primitive	= (EPrimitives)((command >> 29) & 7);

	bool	isSizedPrimitive=false;
	bool	isFirstVertex   =true;
	int		isHardCodedSize =0;
	int		width,height = 0;
	int		vtxCount     = 0;
	int		vtxCountMax	= 0;
	u32		operand			= command;

	// ---------- For rendering ------------------
	rtIsTexModRGB	  = !((command >> 24) & 1);	// Textured Tri or Rect only. 
	rtIsTextured	  =   (command >> 26) & 1;
	rtUseSemiTransp =   (command >> 25) & 1;
	rtIsPerVtx      =  isPerVtxCol;
//	u16    Clut;
//	u16    PageTex;
//	u8		ClutX;
	// -------------------------------------------

	bool continueLoop = true;

//	printf("[%i] EXECUTE :%x\n",commandID, command>>24);

	switch (primitive) {
	case SPECIAL_CMD:
		// Nop, unssupported, FillRect, IRQ, ...
		switch (command>>24) {
		case 0:
			continueLoop = false; // Nop
			break;
		case 2:
			// Fill command.
			isSizedPrimitive = true;
			break;
		case 1:
			continueLoop = false; // Nop
			break;
		}
		rtIsTextured		= false;
		break;
	case PRIM_TRI:
		vtxCountMax			= isMultiCmd ? 4 : 3;
		break;
	case PRIM_LINE:
		rtIsTextured		= false;
		break;
	case PRIM_RECT:
		isSizedPrimitive	= true;
		isHardCodedSize		= ((command >> 27) & 0x3); // (0=Var, 1=1x1, 2=8x8, 3=16x16)
		break;
	case CP_VRAM_VRAM:
		isSizedPrimitive	= true;
		isPerVtxCol			= false;
		isFirstVertex		= false;
		rtIsTextured		= false;
		break;
	case CP_VRAM_CPU:
		isSizedPrimitive	= true;
		isPerVtxCol			= false;
		isFirstVertex		= false;
		rtIsTextured		= false;
		break;
	case CP_CPU_VRAM:
		isSizedPrimitive 	= true;
		isPerVtxCol			= false;
		isFirstVertex		= false;
		rtIsTextured		= false;
		break;
	case SPECIAL_SETTINGS:
		continueLoop = false;

		switch (command>>24) {
		case 0xE1:
			pageX4			= (command & 0xF) * 64;
			pageY1			= ((command>>4) & 0x1) * 256;
			semiTransp2		= (command>>5) & 0x3;
			textFormat2		= (command>>7) & 0x3;

			dither			= (command>>9) & 0x1;
			displayAreaEnable = (command>>10) & 0x1;
			disableTexture	= (command>>11) & 0x1;
			texXFlip		= (command>>12) & 0x1;
			texYFlip		= (command>>13) & 0x1;
			break;
		case 0xE2:
			texMaskX5		= command & 0x1F;
			texMaskY5		= (command>>5) & 0x1F;
			texOffsX5		= (command>>10) & 0x1F;
			texOffsY5		= (command>>15) & 0x1F;
			break;
		case 0xE3:
			drAreaX0_10		= (command>>0 ) & 0x3FF;
			drAreaY0_9		= (command>>10) & 0x1FF;
			break;
		case 0xE4:
			drAreaX1_10		= (command>>0 ) & 0x3FF;
			drAreaY1_9		= (command>>10) & 0x1FF;
			break;
		case 0xE5:
			offsetX_s11		= ((command<<(16+5))>>(16+5));
			offsetY_s11		= ((command<<(  10))>>(16+5));
			break;
		case 0xE6:
			forceMask		= command & 1 ? true : false;
			checkMask		= command & 2 ? true : false;
			break;
		}
		rtIsTextured		= false;
		break;
	}

	while (continueLoop) {

		// -----------------------------------------
		// Always before vertex
		// -----------------------------------------
	
		if (!rtIsTexModRGB && rtIsTextured) {
			operand = 0xFFFFFF; // Force white color for RGB.
		}

		if (isPerVtxCol || isFirstVertex) {
			// [Load Color]
			vtx[vtxCount & 3].r = (operand    ) & 0xFF;
			vtx[vtxCount & 3].g = (operand>>8 ) & 0xFF;
			vtx[vtxCount & 3].b = (operand>>16) & 0xFF;
		} else {
			vtx[vtxCount & 3].r = vtx[0].r;
			vtx[vtxCount & 3].g = vtx[0].g;
			vtx[vtxCount & 3].b = vtx[0].b;
		}

		// -----------------------------------------
		// [Load Vertex]
		operand = *pStream++; pTimeStamps++;
		s16 x = (((s32)operand)<<(16+5))>>(16+5);
		s16 y = (((s32)operand)<<    5 )>>(16+5);
		u8  topV = (operand>>24);
		vtx[vtxCount & 3].x= x + offsetX_s11;
		vtx[vtxCount & 3].y= y + offsetY_s11;
		// -----------------------------------------

		if (rtIsTextured) {
			operand = *pStream++; pTimeStamps++;

			// Read TexCoord + Palette or texPage or nothing (step 0,1, Nothing=2,3)
			// [Load UV]
			vtx[vtxCount & 3].u = operand & 0xFF;
			vtx[vtxCount & 3].v = (operand>>8) & 0xFF;
			switch (vtxCount) {
			case 0:
				rtClutX = ((operand >> 16)     & 0x3F) * 16;
				rtClutY = (operand >> (16+6)) & 0x1FF;
				memcpy(palette,&this->swBuffer[rtClutX + rtClutY*1024],256*2);
				break;
			case 1: 
				pageX4  = ((operand >> 16) & 0xF) * 64;
				pageY1  = ((operand >> 20) & 0x1) * 256;
				semiTransp2  = (operand >> 21) & 0x3;
				textFormat2  = (operand >> 23) & 0x3;
				disableTexture	= ((operand>>(11+16)) & 0x1) ? true : false;
				break;
			// Other don't care...
			}
		}

		if (isSizedPrimitive) {
			switch (isHardCodedSize)
			{
			case 0:
				// [Load Size]
				operand = *pStream++; pTimeStamps++;
				width	=   operand     & 0x03FF;
				height	= (operand>>16) & 0x01FF;
				break;
			case 1:
				width = 1; height = 1;
				break;
			case 2:
				width = 8; height = 8;
				break;
			case 3:
				width = 16; height = 16;
				break;
			default:
				break;
			}
		}

		switch (primitive) {
		case PRIM_TRI:
			continueLoop = (vtxCount != (vtxCountMax-1));

			if (vtxCount == 2) {
				RenderTriangle(vtx,0,1,2);
			}
			if (vtxCount == 3) {
				RenderTriangle(vtx,3,1,2);
			}

			break;
		case PRIM_LINE:
			if (vtxCount == 0) {
				continueLoop = true;
			} else {
				bool render = true;
				continueLoop = isMultiCmd;
				if (isMultiCmd) {
					if (isPerVtxCol) {
						continueLoop = ((operand >> 24) != 0x55);
					} else {
						continueLoop = (topV != 0x55);
					}
					render = continueLoop;
					// Trick
					vtxCount--;
				}

				if (render) {
					RenderLine(vtx,0,1);
				}
				vtx[0].x = vtx[1].x;
				vtx[0].y = vtx[1].y;
			}

			if (!continueLoop) {
				vtxCount = 0;
			}
			break;
		case PRIM_RECT:
			// Convert rect into triangle.
			for (int n=1;n < 4; n++) {
				vtx[n] = vtx[0];
			}

			// BBox is INCLUSIVE.
			// But     x+w, y+h is EXCLUSIVE.
			// => x1=x+w and IS RENDERED, same for y1.
			width--;
			height--;

			vtx[1].x += width; vtx[1].y +=      0; vtx[1].u += width; vtx[1].v +=      0; 
			vtx[2].x +=     0; vtx[2].y += height; vtx[2].u +=     0; vtx[2].v += height;
			vtx[3].x += width; vtx[3].y += height; vtx[3].u += width; vtx[3].v += height;

			// Width/Height with -1 post loader will 
			// generate a negative value, width of 1 will make width = 0.
			if (width >= 0 && height >= 0) {
				RenderRect(vtx);
			}

			continueLoop = false;

			break;

		case SPECIAL_CMD:
			// [TODO : Patch width , height based on FILL, VRAM Copy commands...]

			if ((command >> 24) == 0x2) {
				vtx[0].x += offsetX_s11;
				vtx[0].y += offsetY_s11;

				vtx[0].x &= 0x3F0;
				vtx[0].y &= 0x1FF;
				width	  = ((width & 0x3FF)+15) & (~0xF);
				height    = height & 0x1FF;
				// Contains color
				referenceFILL(vtx[0].x,vtx[0].y, width, height, this->interlaced, this->currentInterlaceFrameOdd, 
					(vtx[vtxCount & 3].r)       |
					(vtx[vtxCount & 3].g<<8)    |
					(vtx[vtxCount & 3].b<<16) );
			} else {
				// assert(false); // NEVER TESTED / IMPLEMENTED.
			}
			continueLoop = false;
			break;
		case CP_VRAM_VRAM:
			// [TODO INVOKE]
			// assert(false); // NEVER TESTED / IMPLEMENTED.
			continueLoop = false;
			break;
		case CP_VRAM_CPU:
			// [TODO INVOKE]
			// assert(false); // NEVER TESTED / IMPLEMENTED.
			continueLoop = false;
			break;
		case CP_CPU_VRAM:
			// [TODO INVOKE]
			continueLoop = false;
			break;
		}

		if (isPerVtxCol && continueLoop) {
			operand	= *pStream++; // Load NEXT COLOR IF NEEDED.
            pTimeStamps++;
		}

		isFirstVertex = false;
		vtxCount++;
	}


	if (pStream != pStreamE) {
		performRefresh(command,commandID);
		commandID++;
		goto nextCommand;
	}
#endif
}

void GPURdrCtx::referenceFILL(int x, int y, int w, int h, bool interlaced, bool renderOddFrame, u32 bgr) {
	/*
	Masking and Rounding for FILL Command parameters

		Xpos=(Xpos AND 3F0h)                       ;range 0..3F0h, in steps of 10h
		Ypos=(Ypos AND 1FFh)                       ;range 0..1FFh
		Xsiz=((Xsiz AND 3FFh)+0Fh) AND (NOT 0Fh)   ;range 0..400h, in steps of 10h
		Ysiz=((Ysiz AND 1FFh))                     ;range 0..1FFh
	*/
	// Proper Coordinate mapping for FILL.
	x =  x & 0x3F0;	
	y =  y & 0x1FF;
	w = ((w & 0x3FF) + 15) & ~0xF;
	h =  h & 0x1FF;

	// Color conversion to target RGB555
	u8 b = ((bgr>>16)>>3) & 0x1F;
	u8 g = ((bgr>> 8)>>3) & 0x1F;
	u8 r = ((bgr>> 0)>>3) & 0x1F;
	u16 color = r | (g<<5) | (b<<10); // Bit 15 not set with FILL

	bool startOdd		= y & 1 ? true : false;
	int startOffsetH	= ((startOdd ^ renderOddFrame)&interlaced) ? 1 : 0;

	for (int ph = startOffsetH; ph < h; ph += (interlaced ? 2 : 1)) {
		for (int pw = 0; pw < w; pw++) {
			// Handle proper buffer rolling over the axis.
			int idx = ((pw+x) & 0x3FF) + (((ph+y) & 0x1FF) * 1024);
			swBuffer[idx] = color;			 
		}
	}
	if (w > 16) {
		performRefresh(0,0);
	}
}

void referenceCV(u16* buffer, u32* source, int x, int y, int w, int h) {
	/*
	  Xpos=(Xpos AND 3FFh)                       ;range 0..3FFh
	  Ypos=(Ypos AND 1FFh)                       ;range 0..1FFh
	  Xsiz=((Xsiz-1) AND 3FFh)+1                 ;range 1..400h
	  Ysiz=((Ysiz-1) AND 1FFh)+1                 ;range 1..200h	
	*/
	x = x & 0x3FF;
	y = y & 0x1FF;
	w = ((w-1) & 0x3FF) + 1;
	h = ((h-1) & 0x1FF) + 1;

	// Same Simulated command in ideal buffer
	// Ideal buffer
	int id = 0;
	for (int ph=0; ph < h; ph++) {
		for (int pw=0; pw < w; pw++) {
			int m = id & 1;
			u16 v = source[id>>1] >> (m*16);
			// Handle proper buffer rolling over the axis.
			buffer[((x+pw)&0x3FF) + (((y+ph)&0x1FF)*1024)] = v;
			id++;
		}
	}
}

void referenceVV(u16* buffer, u32* source, int x, int y, int w, int h) {
	// TODO.
}
