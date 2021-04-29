// GPUSimSW.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <stdio.h>
#include <memory.h>

#include "GPUCommandGen.h"

class VGPU_DDR;
#define NEWGPU

#include "project.h"

// class VGPUVideo;
// #include "../../../rtl/obj_dir/VGPUVideo.h"

#include <verilated_vcd_c.h>

// My own scanner to generate VCD file.
#define VCSCANNER_IMPL
#include "VCScanner.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "MiniFB.h"

#include "gpu_ref.h"

void RenderCommandSoftware(u8* bufferRGBA, u8* srcBuffer, u64 maxTime, GPUCommandGen& commandGenerator,struct mfb_window *window);
void RandomBenchTriangle(u8* bufferRGBA, struct mfb_window *window);
void ThinTriangles(u8* bufferRGBA, struct mfb_window *window);
void TestSuite(u8* bufferRGBA, struct mfb_window *window);


extern void loadImageToVRAMAsCommand(GPUCommandGen& commandGenerator, const char* fileName, int x, int y, bool imgDefaultFlag);
extern void loadImageToVRAM(VGPU_DDR* mod, const char* filename, u8* target, int x, int y, bool flagValue);
extern int dumpFrame(VGPU_DDR* mod, const char* name, const char* maskName, unsigned char* buffer, int clockCounter, bool saveMask);
extern void registerVerilatedMemberIntoScanner(VGPU_DDR* mod, VCScanner* pScan);
// extern void registerVerilatedMemberIntoScannerVideo(VGPUVideo* mod, VCScanner* pScan);
extern void addEnumIntoScanner(VCScanner* pScan);
extern void drawCheckedBoard(unsigned char* buffer);
extern void backupFromStencil(VGPU_DDR* mod, u8* refStencil);
extern void backupToStencil(VGPU_DDR* mod, u8* refStencil);
extern bool ReadStencil(VGPU_DDR* mod, int x, int y);
extern void setStencil(VGPU_DDR* mod, int x,int y, bool v);

void Convert16To32(u8* buffer, u8* data);
void commandDecoder(u32* pStream, u32 size, struct mfb_window* window);

void dumpFrameBasic(const char* name, u16* buffer) {
	dumpFrame(NULL, name, NULL, (unsigned char*)buffer, 0, false);
}

#if defined(SOURCE_ULTRA) || defined(SOURCE_OLDME) 
#include "../../../newRTLFromUltra/obj_dir/VGPU_DDR__Syms.h"
int GetCurrentParserState(VGPU_DDR* mod) {
	return ((VGPU_DDR__Syms*)mod->__VlSymsp)->TOP__GPU_DDR__gpu_inst__gpu_parser_instance.currState;
}
#endif

#ifdef SOURCE_LASTME
int GetCurrentParserState(VGPU_DDR* mod) {
	return mod->GPU_DDR__DOT__gpu_inst__DOT__gpu_parser_instance__DOT__currState;
}
#endif

unsigned int RGB	(int r, int g, int b)	{ return (r & 0xFF) | ((g & 0xFF)<<8) | ((b & 0xFF)<<16);	}
unsigned int Point	(int x, int y)			{ return (x & 0x7FFF) | ((y & 0x7FFF)<<16);					}
unsigned int UV     (int u, int v)			{ return (u & 0xFF) | ((v & 0xFF)<<8);						}

u8* buffer32Bit;

extern int testsuite();

GPUCommandGen*	gCommandReg;
GPUCommandGen* getCommandGen() {
	return gCommandReg;
}

u8* heatMapRGB;
u8* heatMapEntries[64*512];
int  heatMapEntriesCount = 0;

struct CacheSim {
	int CACHE_LINE_BIT = 10;	// 1024 entries -> 32 KB for 1024.
	int CACHE_LINE		= 1<<CACHE_LINE_BIT;
	
	CacheSim(int mode, int lineCount) {
		swizzlingMode = mode;
		CACHE_LINE_BIT	= lineCount;
		CACHE_LINE		= 1<<CACHE_LINE_BIT;
		valid = new bool[CACHE_LINE];
		tag   = new u32 [CACHE_LINE];
		fetch = new u32 [CACHE_LINE];
		memset(valid,false,CACHE_LINE * sizeof(bool));
		prefetch[0] = -1;
		prefetch[1] = -1;
		prefetch[2] = -1;
		prefetch[3] = -1;
	}

	~CacheSim() {
		delete[] valid;
		delete[] tag;
		delete[] fetch;
	}

	int		swizzlingMode;
	// 
	bool*	valid;
	u32*	tag;
	u32*	fetch;
	u32		prefetch[4];
	
	bool isCacheHit(u32 addr) {
#if 0
		return true;
#else
		// Go through internal conversion
		u32 saddr = addrSwizzling(addr);

		// 
		u32 index  = saddr & (CACHE_LINE-1);
		u32 tagA   = saddr >> CACHE_LINE_BIT;
		if (valid[index] && (tagA == tag[index])) {
			return true;
		} else {
			for (int n=0; n < 4; n++) {
				if (prefetch[n] == saddr) {
					// Copy prefetched line to cache real.
					markCache(addr,-1);

					markCache(addr-1,0);
					markCache(addr+1,1);
					markCache(addr+64,2);
					return true;
				}
			}

			return false; // No entry.
		}
#endif
	}

	void markCache(u32 addr, int prefetchSlot) {
		// Go through internal conversion
		u32 saddr = addrSwizzling(addr);
		u32 tagA  = saddr >> CACHE_LINE_BIT;
		u32 index = saddr & (CACHE_LINE-1);

		if (prefetchSlot == -1) {
			valid[index]	= true;
			tag  [index]	= tagA;
		} else {
			prefetch[prefetchSlot] = saddr;
		}
	}
	
	u32 addrSwizzling(u32 addr) {
		u32 newAddr = addr;
		int adrBlockH;
		int adrBlockX;
		int adrBlockV;
		int adrBlockY;

		switch (swizzlingMode) {
		case 1:
			// 64x64
			adrBlockH  = addr & 0x3;			// 4x16 = 64 pixel
			adrBlockX  = (addr>>2) & 0xF;		// 16 block of 64 pixels.

			adrBlockV  = (addr >> 6) & 63;		// 64 vertical.
			adrBlockY  = ((addr >> 6)>>6) & 7;  // 8 block
			newAddr = adrBlockH | (adrBlockV<<2) | (adrBlockX<<(2+6)) | (adrBlockY<<(2+6+4));
			break;
		case 2:
			// 128x64
			adrBlockH  = addr & 0x7;			// 8x16 = 128 pixel
			adrBlockX  = (addr>>3) & 0x7;		// 8 block of 128 pixels.

			adrBlockV  = (addr >> 6) & 63;		// 64 vertical.
			adrBlockY  = ((addr >> 6)>>6) & 7;  // 8 block
			newAddr = adrBlockH | (adrBlockV<<3) | (adrBlockX<<(3+6)) | (adrBlockY<<(3+6+3));
			break;
		case 3:
			// 256x64
			adrBlockH  = addr & 0xF;			// 8x16 = 128 pixel
			adrBlockX  = (addr>>4) & 0x3;		// 8 block of 128 pixels.

			adrBlockV  = (addr >> 6) & 63;		// 64 vertical.
			adrBlockY  = ((addr >> 6)>>6) & 7;  // 8 block
			newAddr = adrBlockH | (adrBlockV<<4) | (adrBlockX<<(4+6)) | (adrBlockY<<(4+6+2));
			break;
		case 4:
			// 64x128
			adrBlockH  = addr & 0x3;			// 4x16 = 64 pixel
			adrBlockX  = (addr>>2) & 0xF;		// 16 block of 64 pixels.

			adrBlockV  = (addr >> 6) & 127;		// 128 vertical.
			adrBlockY  = ((addr >> 6)>>7) & 3;
			newAddr = adrBlockH | (adrBlockV<<2) | (adrBlockX<<(2+7)) | (adrBlockY<<(2+7+4));
			break;
		case 5:
			// 128x128
			adrBlockH  = addr & 0x7;			// 8x16 = 128 pixel
			adrBlockX  = (addr>>3) & 0x7;		// 8 block of 128 pixels.

			adrBlockV  = (addr >> 6) & 127;		// 128 vertical.
			adrBlockY  = ((addr >> 6)>>7) & 3;
			newAddr = adrBlockH | (adrBlockV<<3) | (adrBlockX<<(3+7)) | (adrBlockY<<(3+7+3));
			break;
		case 6:
			// 256x128
			// YYYYYYYYY.XXXXXX
			// 876543210.543210
			// YYVVVVVVV.XXHHHH => 22VVVVVVVHHHH
			adrBlockH  = addr & 0xF;			// 16x16 = 256 pixel
			adrBlockX  = (addr>>4) & 3;			// 
			adrBlockV  = (addr >> 6) & 127;		// 128 vertical.
			adrBlockY  = ((addr >> 6)>>7) & 3;
			newAddr = adrBlockH | (adrBlockV<<4) | (adrBlockX<<(4+7)) | (adrBlockY<<(4+7+2));
		case 7:
			// 64x256
			adrBlockH  = addr & 0x3;			// 4x16 = 64 pixel
			adrBlockX  = (addr>>2) & 0xF;		// 16 block of 64 pixels.

			adrBlockV  = (addr >> 6) & 255;		// 256 vertical.
			adrBlockY  = ((addr >> 6)>>8) & 1;
			newAddr = adrBlockH | (adrBlockV<<2) | (adrBlockX<<(2+8)) | (adrBlockY<<(2+8+4));
			break;
		case 8:
			// 128x256
			adrBlockH  = addr & 0x7;			// 8x16 = 128 pixel
			adrBlockX  = (addr>>3) & 0x7;		// 8 block of 128 pixels.

			adrBlockV  = (addr >> 6) & 255;		// 256 vertical.
			adrBlockY  = ((addr >> 6)>>8) & 1;
			newAddr = adrBlockH | (adrBlockV<<3) | (adrBlockX<<(3+8)) | (adrBlockY<<(3+8+3));
			break;
		case 9:
			// 256x256
			adrBlockH  = addr & 0xF;			// 16x16 = 256 pixel
			adrBlockX  = (addr>>4) & 3;			// 

			adrBlockV  = (addr >> 6) & 255;		// 256 vertical.
			adrBlockY  = ((addr >> 6)>>8) & 1;
			newAddr = adrBlockH | (adrBlockV<<4) | (adrBlockX<<(4+8)) | (adrBlockY<<(4+8+2));
			break;
		default:
			// No remapping.
			newAddr = addr;
			break;	
		}
		return newAddr;
	}
};

void SetWriteHeat(int adr) {
	// Convert 32 byte block ID into pixel start.
	adr *= 64;
	u8* basePix = &heatMapRGB[adr];
	for (int n=0; n < heatMapEntriesCount; n++) {
		if (heatMapEntries[n] == basePix) {
			// Update R
			for (int n=0; n < 16; n++) {
				basePix[n*4] = 255;
			}
			break;
		}
	}
	
	if (heatMapEntriesCount < 64*512) {
		heatMapEntries[heatMapEntriesCount++] = basePix;
		for (int n=0; n < 16; n++) {
			basePix[n*4] = 255;
		}
	}
}

void SetReadHeat(int adr, bool cacheMiss) {
	// Convert 32 byte block ID into pixel start.
	u8* basePix = &heatMapRGB[adr*64];
	int offset = cacheMiss ? 2 : 1;
	for (int n=0; n < heatMapEntriesCount; n++) {
		if (heatMapEntries[n] == basePix) {
			// Update R
			for (int n=0; n < 16; n++) {
				basePix[(n*4) + offset] = 255;
			}
			break;
		}
	}
	
	if (heatMapEntriesCount < 64*512) {
		heatMapEntries[heatMapEntriesCount++] = basePix;
		for (int n=0; n < 16; n++) {
			basePix[n*4 + offset] = 255;
		}
	}
}

void UpdateHeatMap() {
	for (int n=0; n < heatMapEntriesCount; n++) {
		u8* basePix = heatMapEntries[n];
		
		if ((basePix[0] != 0) || (basePix[1] != 0) || (basePix[2] != 0)) {
			bool exitR = basePix[0] <= 24;
			bool exitG = basePix[1] <= 24;
			bool exitB = basePix[2] <= 24;

			if (!exitR) {
				u8 v = basePix[0] - 1;
				for (int n=0; n < 16; n++) {
					basePix[(n*4)] = v;
				}
				if (v==24) {
					exitR = true;
				}
			}

			if (!exitG) {
				u8 v = basePix[1] - 1;
				for (int n=0; n < 16; n++) {
					basePix[(n*4)+1] = v;
				}
				if (v==24) {
					exitG = true;
				}
			}

			if (!exitB) {
				u8 v = basePix[2] - 1;
				for (int n=0; n < 16; n++) {
					basePix[(n*4)+2] = v;
				}
				if (v==24) {
					exitB = true;
				}
			}

			if (exitG & exitR & exitB) {
				// Memcpy
				for (int m=n+1; m < heatMapEntriesCount; m++) {
					heatMapEntries[m-1] = heatMapEntries[m]; 
				}
				// Remove entry
				heatMapEntriesCount--;
			}
		}
	}
}

#include <stdio.h>

void dumpInclude(FILE* src, const char* outfilename) {
	fseek(src,0,SEEK_END); int size = ftell(src); fseek(src,0,SEEK_SET);
			
	u32* buffer = new u32[size/4];
	fread(buffer,1,size, src);

	FILE* dst = fopen(outfilename,"wb");

	fprintf(dst,"#ifndef FRAME_DUMP\n");
	fprintf(dst,"#define FRAME_DUMP\n");
	fprintf(dst,"\n");
	fprintf(dst,"static const u32* FRAME_DATA[] = {\n");
		for (int n=0; n < (size/4);) {
			int remainM32 = ((size/4) - n);
			remainM32 = (remainM32 > 32) ? 32 : remainM32;  
			for (int m=0; m < remainM32; m++) {
				fprintf(dst,"0x%08x,",buffer[n]);
				n++;
			}
			fprintf(dst,"\n");
		}
	fprintf(dst,"};\n");
	fprintf(dst,"\n");
	fprintf(dst,"static const u32 FRAME_SIZE = %i;\n", (size / 4));
	fprintf(dst,"\n");
	fprintf(dst,"#endif\n");
	fclose(dst);
	delete[] buffer;
}

void dumpInclude(const char* inputFile, const char* outputFile) {
	FILE* srcF = fopen(inputFile,"rb");
	dumpInclude(srcF,outputFile);
	fclose(srcF);
}

void compareBuffers(u8* buffer, u8* refBuffer) {
	u16* pM = (u16*)refBuffer;
	u16* pR = (u16*)buffer;
	int count = 0;

	for (int y=0; y < 512; y++) {
		for (int x=0; x < 1024; x++) {
			int idx = x + y*1024;
			if (pM[idx] != pR[idx]) {
				printf("%04x <-> %04x (%i,%i)\n",pR[idx],pM[idx],x,y);
				count++;
			}
		}
	}

	if (count) {
		printf("SW vs RTL : %i pixels.",count);
	}
}


#include <Windows.h>

void cacheMapping() {
	u8* buffer = new u8[1024*512*3];
	
	for (int y=0; y < 512; y++) {
		for (int x=0; x < 64; x++) {
			int idxUnique = x+(y*64);
			int idxClmp   = idxUnique & 0x3FF;
			// A[19:18],A[10:7],A[17:11],A[6:0] -> A[14:13],A[5:2],A[11:6],A[1:0]
			// gpu_addr_i[15],gpu_addr_i[6:2],gpu_addr_i[14:7],gpu_addr_i[1:0]
			int idxByte   = (x+y*64)*32;
			
			int idxCache  = (x & 3) | ((y & 0x7F)<<2);
//				idxCache>>=5; // Byte to adr line (32 byte)
//                idxCache &= 0x3FF;

			for (int p=0; p<16; p++) {
				int r = idxCache & 0xF;
				int b = (idxCache>>6) & 0xF;
				int g = (idxCache>>4) & 0x3;
				buffer[idxUnique*16*3 + p*3 + 0] = r<<4;
				buffer[idxUnique*16*3 + p*3 + 1] = g<<6;
				buffer[idxUnique*16*3 + p*3 + 2] = b<<4;
			}
		}
	}

	stbi_write_png("cache2D.png", 1024, 512, 3, buffer, 1024*3);
	delete[] buffer;
}



typedef struct
{
    char     name[16];
    uint32_t size;
} t_log_fs_entry;

void loadDump(const char* fileName, VGPU_DDR* mod, u16* bufferD) {
    FILE* f = fopen(fileName,"rb");
    fseek(f,0,SEEK_END);
    int size = ftell(f);
    u8* data = new u8[size];

    fseek(f,SEEK_SET,0);
    fread(data,1,size,f);

    // Load Each chunk.
    u8* parse = data;
    while (parse < &data[size]) {
        t_log_fs_entry* pEntry = (t_log_fs_entry*)parse;

        if (!strcmp(pEntry->name,"mips_ctx.bin")) {
        }

        if (!strcmp(pEntry->name,"io.bin")) {
        }

        if (!strcmp(pEntry->name,"scratch.bin")) {
        }

        if (!strcmp(pEntry->name,"vram.bin")) {
			u16* src = (u16*)&parse[sizeof(t_log_fs_entry)];
			u16* dst = bufferD;
			for (int y=0; y < 512; y++) {
				for (int x=0; x < 1024; x++) {
					u16 v = *src++;
					bool bBit    = (v & 0x8000) ? true : false;
					setStencil(mod,x,y,bBit);
					*dst++ = v;
				}
			}
        }

        if (!strcmp(pEntry->name,"main.bin")) {
			/*
            memcpy(bufferRAM,&parse[sizeof(t_log_fs_entry)],1024*1024*2);
            // all Cached
            memset(bufferRAML,1,1024*1024*2);
			*/
        }

        if (strcmp(pEntry->name,"bios.bin")) {
        }

        parse += pEntry->size + 16 + 4;            
    }

    delete[] data;
    fclose(f);
}

u8* findEOL(u8* start) {
	// Stop on next char after EOL
	// + patch EOL with 0
	
	// or stop at char zero.
	// [TODO]
    while (*start!=0 && *start!=0xA) {
        start++;
    }

    if (*start == 0xA) {
        *start = 0;
        start++;
    }

    return start;
}

u8* found(u8* start, u8* sub) {
    const char* res;
    if (res = strstr((const char*)start,(const char*)sub)) {
        res += strlen((const char*)sub);
        return (u8*)res;
    }
    return NULL;
}

u64 ValueHexAfter(u8* start, u8* pattern) {
	// Only space and hexa.
	// Stop on others.
	// Only space and 0..9
	// Stop on others.
    u8* res = found(start, pattern);
    u64 result = -1;
    if (res) {
        result = 0;

        while (*res == ' ') {
            res++;
        }

        // parse all spaces
        while ((*res >= '0' && *res <= '9') || (*res >= 'a' && *res <='f') || (*res >= 'A' && *res <= 'F')) {
            int v = 0;
            if (*res >= '0' && *res <= '9') {
                v = (*res - '0');
            } else {
                if (*res >= 'A' && *res <= 'F') {
                    v = (*res - 'A') + 10;
                } else {
                    v = (*res - 'a') + 10;
                }
            }
            result = (result * 16) + v;
            res++;
        }
    }

    return result;
}

u64 ValueIntAfter(u8* start, u8* pattern) {
	// Only space and 0..9
	// Stop on others.
    u8* res = found(start, pattern);
    u64 result = -1;
    if (res) {
        result = 0;

        while (*res == ' ') {
            res++;
        }

        // parse all spaces
        while (*res >= '0' && *res <= '9') {
            result = (result * 10) + (*res - '0');
            res++;
        }
    }
    return result;
}

u64 GetTime(u8* start, u64& lastTime) {
	u64 result = ValueIntAfter(start, (u8*)" @ ");
    if ((result != -1) && result > lastTime) {
        lastTime = result;
    }
    return result;
}


void loadGPUCommands(const char* fileName, GPUCommandGen& commandGenerator) {
    FILE* file = fopen(fileName, "rb");

    if (!file) { return; }

	// 50 MB, cut in TWO.
	const int FULL = 50*1024*1024;
	const int HALF = FULL / 2;
	
	u8* block = new u8[FULL + 1];
	block[FULL] = 0;
	u8* halfp = &block[HALF];

    fseek(file,0,SEEK_END);	
	u64 size      = ftell(file);
    fseek(file,0,SEEK_SET);

	u32 blocksize = HALF;
	u8* parse     = block;
	
	u64 lastTime  = 0;
	u32 lastAddr  = 0;
	u32 lastMask  = 0;
    int lastDMAchannel = 0;
	
	int state = 0;
	int line  = 0;

    u64 finalTime = 0;

    u64 dmaStartTime = 0;

    fread(block,size < FULL ? size : FULL, 1, file);
    if (size < FULL) {
        block[size] = 0;
        size = 0;
    } else {
        size -= FULL;
    }

	while (true) {
		line++;

		if ((line & 0xFFF) == 0) {
			printf("Parsed line : %i\n",line);
		}

#if 1
        if (line > 1100000) {
            break;
        }
#endif
	
		// [TODO Parse line]
		// 1. Find end of line
		u8* start = parse;
		u8* param;
		parse = findEOL(parse);
		
		// 2. Find sub string within range
		switch (state) {
		case 0:
			if (param = found(start, (u8*)"IO Access (W) [")) {
				// IO Access (W) [DMA]:     1f8010f0 = 0f6f4b21 [mask=f] [delta=5 @ 390044]
				// Find until ] char, get device with same name.
				u8* p = param;
				u8* p2;
				
				u32 addr = ValueHexAfter(p,(u8*)"]:");
				u32 value= ValueHexAfter(p,(u8*)"= ");
				u8  mask = ValueHexAfter(p,(u8*)"mask=");

				u64 time = GetTime(p, finalTime);
				
				if (param=found(p,(u8*)"GPU")) {
					commandGenerator.setTime(time);
					if ((addr & 0x7) == 0) {
						commandGenerator.writeRaw(value);
					} else {
						commandGenerator.writeGP1(value);
					}
//                    if ((addr == 0x1F801814) && ((value>>24) == 0x05)) {
				}
			} else
			if (param = found(start, (u8*)"[DMA] Activating transfer CH")) {
                lastDMAchannel = param[0] - '0';
			} else
			if (param = found(start, (u8*)"M2P]")) {
                u32 value = ValueHexAfter(param,(u8*)" ");
                switch (lastDMAchannel) {
                case 2:
					commandGenerator.writeRaw(value);
					break;
				default:
                    break;
                }
            } else {
				// Ignore.
			}
			break;
		case 1:

			state = 0;
			break;
		}
		
		// 3. Load into correct device.
	
		if (*parse == 0) {
			break;
		}
		
		// parse now point to next line.
		if (parse >= halfp) {
			memcpy(block,halfp,HALF);
			parse -= HALF;
			fread (halfp,blocksize,1,file);
			size  -= blocksize;
			halfp[blocksize] = 0;
			if (size < HALF) {
				blocksize = size;
			}
		}
	}
}


int main(int argcount, char** args)
{
	int swizzleMode = 0;
	int cacheLineCount  = 10;
	int contentNumber = 0;
	if (argcount > 3) {
		// Swizzle type
		swizzleMode = atoi(args[1]);		// 0..9
		// Memory cache line log2
		cacheLineCount = atoi(args[2]);		// 9,10,11,12
		// Content number.
		contentNumber = atoi(args[3]);		// -1,1,2,3,4,5,6,7,9,28,29
	}
	// 2,3,4,5,6,7,9,28,29

//	cacheMapping();
//	return 0;

//	return mainTestVRAMVRAM();
//	return mainTestDMAUpload(true);

	// loadRefRect("RecTable.txt");
	// loadRefQuadNoTex("QuadNoTexOnly.txt");
//	loadRefQuadTex("QuadTexOnly.txt");

//	loadRecords("demo.txt");
	int parseArg = 1;
	int sFrom = -1;
	int sTo   = -1;
	const char* fileName = NULL;

	bool skipScan = false;
/*
	while (parseArg < argcount) {
		if (strcmp(args[parseArg],"-nolog")==0) {
			skipScan = true;
			parseArg++;
		} else
		if (strcmp(args[parseArg],"-block")==0) {
			sscanf(args[parseArg+1], "%i", &sFrom);
			sscanf(args[parseArg+2], "%i", &sTo);
			parseArg+=3;
		} else {
			fileName = args[parseArg++];
		}
	}
*/
	int sL    = 0;

	enum DEMO {
		NO_TEXTURE,
		TEXTURE_TRUECOLOR_BLENDING,
		TEXTURE_PALETTE_BLENDING,
		COPY_CMD,
		COPY_FROMRAM,
		TEST_EMU_DATA,
		USE_AVOCADO_DATA,
		USE_DUMP_SIM,
		PALETTE_FAIL_LATEST,
		INTERLACE_TEST,
		POLY_FAIL,
		COPY_TORAM,
		TESTSUITE,
		CAR_SHADOW,
		TEST_A,
	};

	DEMO manual		= USE_AVOCADO_DATA;
	int source = 3; // ,5 : SW Namco Logo wrong, Score
	
//	DEMO manual		= USE_DUMP_SIM;
	const char* dumpFileName   = "E:\\MDEC\\gran_turismo2.dump";
	const char* log_inFileName = "E:\\MDEC\\single_frame_gt2_91.txt";

//	DEMO manual		= TESTSUITE;
	switch (contentNumber) {
	case -1:
		manual = USE_DUMP_SIM;
		break;
	default:
		manual = USE_AVOCADO_DATA;
		source = contentNumber;
		break;
	}

//	manual		= TEST_A;

	bool compare     = false;

	FILE* binSrc = NULL;
	bool useHeatMap  = true;

	// SW/HW
	bool useSWRender = false;

	// HW
	bool useScanRT   = false;
	int  lengthCycle = 750000;

	bool removeVisuals = false;


	const int READ_LATENCY = 20;

	// 9,17,12 = Very good test for stencil.

	// - Get cycle count !!!
	// Content
	// -1,
	// Cache format:
	// Size:line count (9..12 =>16..128KB 10 bit=32 KB)
	// Swizzling :

	switch (source) {
	case  0:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Station","rb");				break; // GOOD COMPLETE
	case  1:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Station2","rb");			break; // GOOD COMPLETE
	case  2:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Fight","rb");				break; // GOOD COMPLETE
	case  3:  binSrc = fopen("E:\\JPSX\\Avocado\\RidgeRacerMenu","rb");			break; // GOOD COMPLETE
	case  4:  binSrc = fopen("E:\\JPSX\\Avocado\\RidgeRacerGame","rb");			break; // GOOD COMPLETE
	case  5:  binSrc = fopen("E:\\JPSX\\Avocado\\RidgeScore","rb");				break; // GOOD COMPLETE
	case  6:  binSrc = fopen("E:\\JPSX\\Avocado\\StarOceanMenu","rb");			break; // GOOD COMPLETE But gbreak; litch. Happen also in SW Raster => Bad data most likely.
	case  7:  binSrc = fopen("E:\\JPSX\\Avocado\\TexTrueColorStarOcean","rb");	break; // GOOD COMPLEbreak; TE.
	case  8:  binSrc = fopen("E:\\JPSX\\Avocado\\Rectangles","rb");				break; // GOOD COMPLETE
	case  9:  binSrc = fopen("E:\\JPSX\\Avocado\\MegamanInGame","rb");			break; // GOOD COMPLETE
	case 10:  binSrc = fopen("E:\\JPSX\\Avocado\\Megaman_Menu","rb");			break; // GOOD COMPLETE
	case 11:  binSrc = fopen("E:\\JPSX\\Avocado\\Megaman1","rb");				break; // GOOD COMPLETE
	case 12:  binSrc = fopen("E:\\JPSX\\Avocado\\JumpingFlashMenu","rb");		break; // GOOD COMPLETE
	case 13:  binSrc = fopen("E:\\JPSX\\Avocado\\PolygonBoot","rb");			break; // GOOD COMPLETE
	case 14:  binSrc = fopen("E:\\JPSX\\Avocado\\MenuPolygon2","rb");			break; // GOOD COMPLETE
	case 15:  binSrc = fopen("E:\\JPSX\\Avocado\\MenuFF7","rb");				break; // GOOD COMPLETE
	case 16:  binSrc = fopen("E:\\JPSX\\Avocado\\LoaderRidge","rb");			break; // GOOD COMPLETE
	case 17:  binSrc = fopen("E:\\JPSX\\Avocado\\Lines","rb");					break; // GOOD COMPLETE
	case 18:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Station2_export","rb");		break; // BROKE . Waibreak; t VRAM->CPU transfer.
	case 19:  binSrc = fopen("E:\\AvocadoDump\\RRFlag.gpudrawlist","rb");		break; // GOOD COMPLETE
	case 20:  binSrc = fopen("E:\\AvocadoDump\\RRChase3.gpudrawlist","rb");		break; // GOOD COMPLETE
	case 21:  binSrc = fopen("E:\\AvocadoDump\\FF7_3.gpudrawlist","rb");		break; // GOOD COMPLETE
	case 22:  binSrc = fopen("E:\\AvocadoDump\\dumpBiosAnim.gpudrawlist","rb");							break; // GOOD COMPLETE
	case 23:  binSrc = fopen("F:\\tekken3.gpudrawlist","rb");					break; // GOOD COMPLETE
	case 24:  binSrc = fopen("E:\\AvocadoDump\\trex.gpudrawlist","rb");			break;
	case 25:  binSrc = fopen("E:\\AvocadoDump\\PlaystationLogo.gpudrawlist","rb");			break;
	case 26:  binSrc = fopen("E:\\AvocadoDump\\CottonGame.gpudrawlist","rb");			break; // Multiline crashy...
	case 27:  binSrc = fopen("E:\\AvocadoDump\\CottonMenu.gpudrawlist","rb");			break;
	case 28:  binSrc = fopen("E:\\AvocadoDump\\GhostInTheShellMenu.gpudrawlist","rb");			break;
	case 29:  binSrc = fopen("E:\\AvocadoDump\\DestructionDerby.gpudrawlist","rb");			break;
	case 30:  binSrc = fopen("E:\\AvocadoDump\\CottonGame.gpudrawlist","rb");			break;
	}

	// dumpInclude(binSrc,"frame_dump.h");

	// ------------------------------------------------------------------
	// SETUP : Export VCD Log for GTKWave ?
	// ------------------------------------------------------------------



	bool useScan = (fileName ? (!skipScan) : useScanRT) /* & !useSWRender*/;

	// ------------------------------------------------------------------
	// Export Buffer as PNG ?
	// ------------------------------------------------------------------
	// Put background for debug.
	const bool	useCheckedBoard				= false;
	const bool useVRAMDump					= true;

	// ------------------------------------------------------------------
	// Fake VRAM PSX
	// ------------------------------------------------------------------
	unsigned char* buffer     = new unsigned char[1024*1024];
	unsigned char* refBuffer  = new unsigned char[1024*1024];
	unsigned char* softbuffer = new unsigned char[1024*1024];
	unsigned char* refStencil = new unsigned char[16384 * 32]; 

	int readCount = 0;
	int uniqueReadCount = 0;
	int readHit = 0;
	int readMiss = 0;
	bool* uniqueReadsAdr = new bool[1024*1024];
	memset(uniqueReadsAdr,0,1024*1024*sizeof(bool));

	memset(buffer,0,1024*1024);
//	memset(&buffer[2048],0x00,2048*511);
//	rasterTest((u16*)buffer);


	// ------------------------------------------------------------------
	// [Instance of verilated GPU & custom VCD Generator]
	// ------------------------------------------------------------------
	VGPU_DDR* mod		= new VGPU_DDR();
	VCScanner*	pScan   = new VCScanner();
				pScan->init(4000);

	if (useCheckedBoard) {
		drawCheckedBoard(buffer);
		u16* p = (u16*)buffer;
		int id = 0;
		for (int y=0; y < 512; y++) {
			for (int x=0; x < 1024; x++) {
				*p++ = id & 0x7FFF;
				id++;
			}
		}
	}

	if (useVRAMDump) {
		FILE* fd = fopen("dump.vram","rb");
		u16* buff16 = (u16*)buffer;
		fread(buffer,sizeof(u16),1024*512,fd);

		// ----- Sync Stencil cache and VRAM state.
		for (int y=0; y < 512; y++) {
			for (int x=0; x < 1024; x++) {
				bool bBit    = (buff16[x + (y*1024)] & 0x8000) ? true : false;
				setStencil(mod,x,y,bBit);
			}
		}
		fclose(fd);
	}

#if 0
	u16 fuckPointList[] = {
				 0x1efb
				,0xa9e3
				,0xe146
				,0x007c
				,0x62c2
				,0x0854
				,0x27f8
				,0x231b
				,0xe9e8
				,0xcde7
				,0x438d
				,0x0f76
				,0x255a
				,0xf92e
				,0x7263
				,0xc233
				,0xd79f

				,0x5490
				,0xbe1e
				,0xb7e5
				,0x8302
				,0xc7a8
				,0x1011
				,0xc777
				,0x6e4d
				,0x56cd
				,0x6ee1
				,0xe53b
				,0x0487
				,0x1b60
				,0xd574
				,0x808a
				,0x7276
				,0x81db

				,0x8f60
				,0xc044
				,0x0386
				,0x47c9
				,0x3aa2
				,0x97d9
				,0x3e66
				,0x872d
				,0x1de3
				,0xd8b5
				,0x9aa6
				,0x33c7
				,0x3fb3
				,0x78b0
				,0x99e2
				,0x7b57
				,0x481f

				,0x49a6
				,0x5d28
				,0x2c9d
				,0x9234
				,0x8b3e
				,0x51b3
				,0xdbea
				,0xc3e7
				,0x139e
				,0x01f4
				,0xa830
				,0xd2f8
				,0xce9c
				,0xd4c6
				,0xb57c
				,0x2f5a
				,0x780f

				,0x6f64
				,0x4ec7
				,0xc951
				,0x40e4
				,0x28b7
				,0x8c6e
				,0x2527
				,0x5cae
				,0x8042
				,0x26c4
				,0x05d8
				,0x7e29
				,0x6585
				,0xff75
				,0x4368
				,0x2d13
				,0x3041

				,0x35e7
				,0xb6b6
				,0xf7b1
				,0xaf3f
				,0xf79a
				,0x105e
				,0x719f
				,0xcf9c
				,0xb7d5
				,0xd1c4
				,0x5ba7
				,0xf81a
				,0x5765
				,0x6758
				,0xcc9d
				,0x5d6f
				,0x8412

				,0x6498
				,0x5f53
				,0xfc90
				,0x030c
				,0x4b90
				,0x206a
				,0x6bdd
				,0xbae5
				,0x2c60
				,0x78a4
				,0x1940
				,0xc10d
				,0xf637
				,0x3940
				,0x6377
				,0x5c01
				,0x5c39

				,0x4e52
				,0x8914
				,0x954c
				,0xadae
				,0xb0db
				,0x1773
				,0x8e0b
				,0xd403
				,0x785b
				,0x0a49
				,0xf191
				,0x2fc8
				,0x5411
				,0x4092
				,0x378d
				,0x5638
				,0xa787

				,0x63ee
				,0xd1d1
				,0x49bc
				,0xe538
				,0x5dcb
				,0xb6ad
				,0x09ea
				,0x0c6e
				,0x1e98
				,0xa3e1
				,0x3174
				,0xed29
				,0xab7c
				,0x1818
				,0x73ee
				,0x9599
				,0x70da

				,0x6920
				,0xd5bd
				,0x9820
				,0x1edd
				,0x2439
				,0x3bea
				,0x1f17
				,0x0353
				,0xe06e
				,0xb692
				,0x07f4
				,0x06d2
				,0x8e15
				,0x15e7
				,0x17d3
				,0x1022
				,0x0d70

				,0x99f0
				,0x87ea
				,0xf529
				,0x2279
				,0x4a5d
				,0x21c3
				,0xa18c
				,0xa2fb
				,0x006d
				,0xb338
				,0x59ed
				,0xb062
				,0x2cb3
				,0xe9b4
				,0x2577
				,0xaae3
				,0x1aac

				,0x1d2d
				,0x224f
				,0xfa39
				,0x5a24
				,0xc63b
				,0x010b
				,0x3fc3
				,0x75d6
				,0xb8ba
				,0xad6f
				,0x1228
				,0x55d4
				,0x8064
				,0xd3be
				,0xfb19
				,0xa69d
				,0x0acd

				,0x2b90
				,0x51d8
				,0x4566
				,0x2c87
				,0xeaef
				,0x4a2b
				,0x18bc
				,0xbf0b
				,0xf482
				,0xdc66
				,0x0ff2
				,0x1775
				,0x7cfc
				,0x0fc0
				,0xa69b
				,0xefcc
				,0x9b28

				,0xa723
				,0xf7fc
				,0xdc4d
				,0x55be
				,0x7803
				,0x095e
				,0x30a7
				,0x102f
				,0xe1b0
				,0x2f94
				,0xedec
				,0xee1a
				,0x41cb
				,0x4d30
				,0x05ae
				,0x1493
				,0x7be0

				,0x0eeb
				,0x73ac
				,0x8fbd
				,0x4c98
				,0x2baf
				,0x6c69
				,0x6301
				,0x8e26
				,0xa538
				,0xa982
				,0x5145
				,0xcef3
				,0x8ba1
				,0x4671
				,0x7fd8
				,0xb196
				,0xa719

				,0xb98a
				,0x9367
				,0x8fa7
				,0x84a1
				,0x2765
				,0x1a52
				,0x84b5
				,0xd1f1
				,0x3bba
				,0xf465
				,0x97bc
				,0xa64c
				,0x489b
				,0xf343
				,0x3378
				,0x1d68
				,0x166e

				,0x2ac0
				,0x7e7b
				,0xa650
				,0x2312
				,0xa097
				,0x9849
				,0x37ce
				,0x7dcf
				,0x9ffb
				,0x9dcc
				,0x8de5
				,0xb603
				,0xcecc
				,0xdecf
				,0xd253
				,0x4842
				,0x51d0
		};

	#if 0
		srand(17);
		int idxppt = 0;
		for (int y=0;y<256;y++) {
			for (int x=0;x<256;x++) {
				u16* p = (u16*)&buffer[x*2 + y*2048];
				int v = /*(((x & 16)!=0) ^((y&1)!=0)) & (x & 1);*/ (rand()<<15) & 0x8000;
				*p = v;
	//			printf("%i",v>>15);
				setStencil(mod,x,y,v>>15 ? true : false);
			}
	//		printf("\n");
		}
	#else
		FILE* fData = fopen("E:\\PSFPGA-TEST-SOC1\\gpu_tb\\psf_gpu\\dump.vram","rb");
		fread(buffer,512*1024*2,1,fData);
		for (int y=0;y<512;y++) {
			for (int x=0;x<1024;x++) {
				u16 p = ((u16*)buffer)[x + y*1024];
				setStencil(mod,x,y,p>>15 ? true : false);
			}
		}
		fclose(fData);
		memcpy(refBuffer,buffer,1024*1024);
	#endif
#endif

	/*
	for (int y=0;y<512;y++) {
		for (int x=0;x<2048;x++) {
			if (((x & 32)!=0)^((y^1)!=0)) {
				u8 v;
				if (x & 2) {
					v = y & 1 ? 0xFF : 0;
				} else {
					v = y & 1 ? 0 : 0xFF;
				}
				if (x & 1) {
					if (v & 0x80) {
						setStencil(mod,x>>1,y,v & 0x80 ? true : false);
					}
				}
				buffer[x + y*2048] = v;
			} else {
				buffer[x + y*2048] = 0;
			}
		}
	}
	*/


	VerilatedVcdC   tfp;
	if (useScan) {
		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");

		mod->trace (&tfp, 99);
		tfp.open (VCD_FILE_NAME);
	}

	// ------------------ Register debug info into VCD ------------------
	int currentCommandID      =  0;
	u8 error = 0;

	// Follow commands.
	pScan->addMemberFullPath("COMMAND_ID", WIRE, BIN, 32, &currentCommandID, -1, 0);
	pScan->addMemberFullPath("ERROR",      WIRE, BIN,  1, &error           , -1, 0);
	pScan->addMemberFullPath("ERROR",      WIRE, BIN,  1, &error           , -1, 0);
	// ------------------------------------------------------------------

	registerVerilatedMemberIntoScanner(mod, pScan);
	addEnumIntoScanner(pScan);
	
	// ------------------------------------------------------------------
	// Reset the chip for a few cycles at start...
	// ------------------------------------------------------------------
	unsigned long long clockCnt  = 0;
	mod->i_nrst = 0;
	for (int n=0; n < 10; n++) {
		mod->clk = 0; mod->eval(); 
		if (useScan) { tfp.dump(clockCnt); }
		clockCnt++;
		mod->clk = 1; mod->eval();
		if (useScan) { tfp.dump(clockCnt); }
		clockCnt++;

	}
	mod->i_nrst = 1;

	// Not busy by default...
	mod->i_busy					        = 0;
	mod->i_dataInValid					= 0;
//	mod->o_dataOut						= 0;

	mod->i_DIP_AllowDither = 1;
	mod->i_DIP_ForceDither = 0;
	mod->i_DIP_Allow480i   = 1;

	// input			i_dataValidMem,
	// input  [63:0]	i_dataMem
	// input			i_busyMem,				// Wait Request (Busy = 1, Wait = 1 same meaning)
	// output [16:0]	o_targetAddr,
	// output [ 2:0]	o_burstLength,
	// output			o_writeEnableMem,		//
	// output			o_readEnableMem,		//
	// output [63:0]	o_dataMem,
	// output [7:0]	o_byteEnableMem,

	/*	
		I decided to setup the textures as GPU commands,
		this will allow you to extract the information more easily for simulation on another platform.
	*/

	// This is the object used in the main loop to store/send 32 bit word to the GPU.
	GPUCommandGen	commandGenerator(true);

	gCommandReg = &commandGenerator;

	if (useScan) {
		pScan->addPlugin(new ValueChangeDump_Plugin("gpuLogFat.vcd"));
	}

#if 1

	// doUploadTest(mod, commandGenerator, buffer, true, pScan, tfp);

	DEMO demo = fileName ? USE_AVOCADO_DATA : manual;
	if (demo == TEXTURE_TRUECOLOR_BLENDING) {
		// Load Gradient128x64.png at [0,0] in VRAM as true color 1555 (bit 15 = 0).
		// => Generate GPU upload stream. Will be used as TEXTURE SOURCE for TRUE COLOR TEXTURING.
		// loadImageToVRAM(mod,"Gradient128x64.png",buffer,0,0,true);
	}

	if (demo == NO_TEXTURE) {
		// loadImageToVRAM(mod,"TileTest.png",buffer,0,0,true);
	}

	if (demo == INTERLACE_TEST) {
		commandGenerator.writeRaw(0xE1000000 | 1<<10);
		commandGenerator.writeRaw(0xE2000000);
		commandGenerator.writeRaw(0xE3000000 | (0<<0) | (0<<10));
		commandGenerator.writeRaw(0xE4000000 | (1023<<0) | (511<<10));
		commandGenerator.writeRaw(0xE5000000 | (0<<0) | (0<<11));
		commandGenerator.writeRaw(0xE6000000);

		commandGenerator.writeRaw(0x02000000);
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x01000200);

/* 0x30 Tri / 0x38 (Quad)
  1st  Color1+Command    (CcBbGgRrh)
  2nd  Vertex1           (YyyyXxxxh)
  3rd  Color2            (00BbGgRrh)
  4th  Vertex2           (YyyyXxxxh)
  5th  Color3            (00BbGgRrh)
  6th  Vertex3           (YyyyXxxxh)
 (7th) Color4            (00BbGgRrh) (if any)
 (8th) Vertex4           (YyyyXxxxh) (if any)

*/
		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(10,1));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(1+64,1));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(1,1+64));

		/*
		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(128,1));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(128+64,1));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(128+64,1+64));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(128+64,128));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(128+64,128+64));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(128,128+64));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(1,128));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(1+64,128+64));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(1,128+64));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(133,26));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(171,81));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(38,160));


		commandGenerator.writeRaw(0xE5000000 | (256<<0) | (0<<11));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(1,1));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(1,1+64));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(1+64,1));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(128,1));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(128+64,1+64));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(128+64,1));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(128+64,128));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(128,128+64));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(128+64,128+64));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(1,128));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(1,128+64));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(1+64,128+64));

		commandGenerator.writeRaw(0x30000000 | RGB(64,64,64));
		commandGenerator.writeRaw(             Point(133,26));
		commandGenerator.writeRaw(             RGB(64, 64,128));
		commandGenerator.writeRaw(             Point(38,160));
		commandGenerator.writeRaw(             RGB(128,64,64));
		commandGenerator.writeRaw(             Point(171,81));
		*/

		/*
		commandGenerator.writeGP1(0x08000000 | (1<<2) | (1<<5));	// 480i setup.

		commandGenerator.writeRaw(0x02FF00FF);
		commandGenerator.writeRaw(0x00000040); // At 0,0
		commandGenerator.writeRaw(0x00100020); // H:16,W:16

		commandGenerator.writeRaw(0x40FF0000);
		commandGenerator.writeRaw(0x00500050);
		commandGenerator.writeRaw(0x00A00250);

		commandGenerator.writeRaw(0x32FFFFFF);    // Color1+Command.  Shaded three-point polygon, semi-transparent.
		commandGenerator.writeRaw(0x00000000);    // Vertex 1. (YyyyXxxxh)
		commandGenerator.writeRaw(0x00FFFFFF);    // Color2.   (00BbGgRrh)  
		commandGenerator.writeRaw(0x00000035);    // Vertex 2. (YyyyXxxxh)
		commandGenerator.writeRaw(0x00FFFFFF);    // Color3.   (00BbGgRrh)  
		commandGenerator.writeRaw(0x00910020);    // Vertex 3. (YyyyXxxxh)

		commandGenerator.writeRaw(0x02FF00FF);
		commandGenerator.writeRaw(0x00010080); // At 0,0
		commandGenerator.writeRaw(0x00100020); // H:16,W:16

		commandGenerator.writeRaw(0x0200FF00);
		commandGenerator.writeRaw(0x01D00000); // At 0,0
		commandGenerator.writeRaw(0x00800040); // H:16,W:16

		commandGenerator.writeRaw(0x02FF00FF);
		commandGenerator.writeRaw(0x00000180); // At 0,0
		commandGenerator.writeRaw(0x00800080); // H:16,W:16

		*/
	}

	if (demo == COPY_CMD) {
		loadImageToVRAM(mod,"Airship.png",buffer,0,0,true);
		memcpy(refBuffer,buffer,1024*1024);
		backupFromStencil(mod,refStencil);

//		loadImageToVRAMAsCommand(commandGenerator,"Line1.png",0,0,true);
		
		/*
		// loadImageToVRAMAsCommand(commandGenerator, "Gradient128x64.png", 0, 0,true);
		commandGenerator.writeRaw(0xa0000000);
		commandGenerator.writeRaw(16 | (0<<16));	// @16,0
		commandGenerator.writeRaw(64 | (1<<16));	// 32 pixel x1
		for (int n=0; n < 32; n++) { // 16 pairs.
			int v = (n*2);
			// 0,2,4,6 Are marked with '1' bit mask.
			commandGenerator.writeRaw((0x8000| (16+v)) | ((v+16+1)<<16));
		}
		*/

		commandGenerator.writeRaw(0xE6000000);						// Set Bit mask, no check.
	}

	if (demo == TEXTURE_PALETTE_BLENDING) {
		// -------------------------------------------------
		// Upload a 4 bit 32x32 pixel texture at 512,64
		// -------------------------------------------------
		commandGenerator.writeRaw(0xa0000000);
		commandGenerator.writeRaw(0 | (0<<16));
		commandGenerator.writeRaw(8 /*8 halfword*/ | (32<<16));
		for (int n=0; n < 32; n++) {
			commandGenerator.writeRaw(0x76543210); commandGenerator.writeRaw(0xFEDCBA98); commandGenerator.writeRaw(0x76543210); commandGenerator.writeRaw(0xFEDCBA98);	// 32 pixel texture 
		}

		// -------------------------------------------------
		// Upload a 4 bit palette : 16 entries. at 512,96
		// -------------------------------------------------
		commandGenerator.writeRaw(0xa0000000); 
		commandGenerator.writeRaw(0 | (64<<16));
		commandGenerator.writeRaw(16 /*8 halfword*/ | (1<<16));
		commandGenerator.writeRaw(0x11118000);
		commandGenerator.writeRaw(0x33332222);
		commandGenerator.writeRaw(0x55554444);
		commandGenerator.writeRaw(0x77776666);
		commandGenerator.writeRaw(0x99998888);
		commandGenerator.writeRaw(0xBBBBAAAA);
		commandGenerator.writeRaw(0xDDDDCCCC);
		commandGenerator.writeRaw(0xFFFFEEEE);
	}

	if (demo == TEST_EMU_DATA) {
		u32 commandsL[] = {
			0xe3000000,
			0xe4077e7f,

			0xe5000000,

			0xe100020a,

			0xe2000000,

			0xcccccccc,
			0x0,
			0x1e00280,
			0xcccccccc,
			0xf000c0,
			0x8cb2,
			0x700140,
			0x8cb2,
			0x1700140,
			0xb2,
			0xf001c0,
			0xcccccccc,
			0xf401b8,
			0x8cb2,
			0x7c0140,
			0x8cb2,
			0x16c0140,
			0xcccccccc,
			0xec00c8,
			0x8cb2,
			0x740140,
			0x8cb2,
			0x1640140,
			0xe3000000,
			0xe4077e7f,
			0xe5000000,
			0xe100020a,
			0xe2000000,
			0xcccccccc,
			0x0,
			0x1e00280,
			0xcccccccc,
			0xf000c0,
			0x8cb2,
			0x700140,
			0x8cb2,
			0x1700140,
			0xb2,
			0xf001c0,
			0xcccccccc,
			0xf501b6,
			0x8cb2,
			0x7e013f,
			0x8cb2,
			0x16c013f,
			0xcccccccc,
			0xeb00ca,
			0x8cb2,
			0x740141,
			0x8cb2,
			0x1620141,
		};


	}
	// ------------------------------------------------------------------
	// Reset the chip for a few cycles at start...
	// ------------------------------------------------------------------

	// Force MASK WRITE (easier for debug)
//	commandGenerator.writeRaw(0xE6000001);

	if (demo == TESTSUITE) {
		testsuite();
	}

	switch (demo) {
	case TEST_A:
	{
		/*
		commandGenerator.writeRaw(0xE3000000 | (0<<0) | (0<<10));
		commandGenerator.writeRaw(0xE4000000 | (320<<0) | (240<<10));

        commandGenerator.writeRaw(0x2200FFFF);
        commandGenerator.writeRaw(0x171c7aac);
        commandGenerator.writeRaw(0x271db0f7);
        commandGenerator.writeRaw(0x001d88ba);
		*/
/*
		// Fail Single pixel.
        commandGenerator.writeRaw(0x2cccd0d4);
        commandGenerator.writeRaw(0x01be00fa);
        commandGenerator.writeRaw(0x53751e17);
        commandGenerator.writeRaw(0x0153010d);
        commandGenerator.writeRaw(0x0348f913);
        commandGenerator.writeRaw(0x0111003b);
        commandGenerator.writeRaw(0x776cc799);
        commandGenerator.writeRaw(0x00270105);
        commandGenerator.writeRaw(0x320869a3);
*/
/*
                commandGenerator.writeRaw(0x265fa7b1);
                commandGenerator.writeRaw(0x01cd0101);
                commandGenerator.writeRaw(0x224a6692);
                commandGenerator.writeRaw(0x001e0086);
                commandGenerator.writeRaw(0x4248164d);
                commandGenerator.writeRaw(0x00ed0087);
                commandGenerator.writeRaw(0x13ca588e);
*/

/*
                commandGenerator.writeRaw(0x24FFFFFF);
                commandGenerator.writeRaw(Point(257, 237));
                commandGenerator.writeRaw(0x224a0000 | UV(0x92,0x66));
                commandGenerator.writeRaw(Point(134,30));
                commandGenerator.writeRaw(0x42480000 | UV(0x4D,0x16));
                commandGenerator.writeRaw(Point(135,237));
                commandGenerator.writeRaw(UV(0x8E,0x58));
*/

				commandGenerator.writeRaw(0x01000000);
                commandGenerator.writeRaw(0x35599b7f);
                commandGenerator.writeRaw(0x00190102);
                commandGenerator.writeRaw(0x11ad0f2c);
                commandGenerator.writeRaw(0x2d9e6a75);
                commandGenerator.writeRaw(0x0097006c);
                commandGenerator.writeRaw(0x4a48d631);
                commandGenerator.writeRaw(0x12baf6e4);
                commandGenerator.writeRaw(0x00ed0095);
                commandGenerator.writeRaw(0x0a280f6d);
/*
                commandGenerator.writeRaw(0x24FFFFFF);
                commandGenerator.writeRaw(Point(257, 177));
                commandGenerator.writeRaw(0x224a0000 | UV(255,0));
                commandGenerator.writeRaw(Point(134,30));
                commandGenerator.writeRaw(0x42480000 | UV(0,255));
                commandGenerator.writeRaw(Point(135,177));
                commandGenerator.writeRaw(UV(255,128));
*/

/*
		// Fail 239 pixels.
//  1st  Color1+Command    (CcBbGgRrh)
        commandGenerator.writeRaw(0x3cb875f0);
//  2nd  Vertex1           (YyyyXxxxh)
        commandGenerator.writeRaw(Point(251,164)); // 
//  3rd  Texcoord1+Palette (ClutYyXxh)
        commandGenerator.writeRaw(0x2f9ef876);
//  4th  Color2            (00BbGgRrh)
        commandGenerator.writeRaw(0x0609f6df);
//  5th  Vertex2           (YyyyXxxxh)
        commandGenerator.writeRaw(Point(20,103));
//  6th  Texcoord2+Texpage (PageYyXxh)
        commandGenerator.writeRaw(0x0c98772f);
//  7th  Color3            (00BbGgRrh)
        commandGenerator.writeRaw(0x12149a1c);
//  8th  Vertex3           (YyyyXxxxh)
        commandGenerator.writeRaw(Point(50,339));
//  9th  Texcoord3         (0000YyXxh)
        commandGenerator.writeRaw(0x1f2c50fe);
// (10th) Color4           (00BbGgRrh) (if any)
        commandGenerator.writeRaw(0x2b1613ae);
// (11th) Vertex4          (YyyyXxxxh) (if any)
        commandGenerator.writeRaw(Point(8,129));
// (12th) Texcoord4        (0000YyXxh) (if any)
        commandGenerator.writeRaw(0x21193333);	// 0x33 -> 51,51
*/

/*
		commandGenerator.writeRaw(0x20FF00FF);
		commandGenerator.writeRaw(0x00000020);
		commandGenerator.writeRaw(0x00400000);
		commandGenerator.writeRaw(0x00400040);
*/
/*
		commandGenerator.writeRaw(0xe1000008);
		commandGenerator.writeRaw(0xe3000000);
		commandGenerator.writeRaw(0xe403c140);
		commandGenerator.writeRaw(0xe6000000);

        commandGenerator.writeRaw(0x2cccd0d4);
        commandGenerator.writeRaw(0x01be00fa);
        commandGenerator.writeRaw(0x53751e17);
        commandGenerator.writeRaw(0x0153010d);
        commandGenerator.writeRaw(0x0348f913);
        commandGenerator.writeRaw(0x0111003b);
        commandGenerator.writeRaw(0x776cc799);
        commandGenerator.writeRaw(0x00270105);
        commandGenerator.writeRaw(0x320869a3);
*/
	}								
	break;
	case CAR_SHADOW:
	{
		commandGenerator.writeRaw(0x29FFFFFF);
		commandGenerator.writeRaw(0x006f008a);
		commandGenerator.writeRaw(0x006e00a1);
		commandGenerator.writeRaw(0x0071008a);
		commandGenerator.writeRaw(0x007000a1);

		commandGenerator.writeRaw(0x290000FF);
		commandGenerator.writeRaw(0x0071008a);
		commandGenerator.writeRaw(0x007000a1);
		commandGenerator.writeRaw(0x0074008a);
		commandGenerator.writeRaw(0x007300a0);

		commandGenerator.writeRaw(0x2b00FF00);
		commandGenerator.writeRaw(0x0075008c);
		commandGenerator.writeRaw(0x0075009b);
		commandGenerator.writeRaw(0x0076008a);
		commandGenerator.writeRaw(0x007600a1);

		commandGenerator.writeRaw(0x2bFF0000);
		commandGenerator.writeRaw(0x0075008c);
		commandGenerator.writeRaw(0x0075009b);
		commandGenerator.writeRaw(0x0076008a);
		commandGenerator.writeRaw(0x007600a1);

		commandGenerator.writeRaw(0x2bFFFF00);
		commandGenerator.writeRaw(0x0076008a);
		commandGenerator.writeRaw(0x007600a1);
		commandGenerator.writeRaw(0x0078008b);
		commandGenerator.writeRaw(0x007700a5);

		commandGenerator.writeRaw(0x2b00FFFF);
		commandGenerator.writeRaw(0x0076008a);
		commandGenerator.writeRaw(0x007600a1);
		commandGenerator.writeRaw(0x0078008b);
		commandGenerator.writeRaw(0x007700a5);
	}
	break;
	case NO_TEXTURE:
	{
		commandGenerator.writeRaw(0xE6000003);						// Set Bit mask, no check.

		commandGenerator.writeRaw(0x300000FF);
		commandGenerator.writeRaw(0x0017FF80);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x00000100);
		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(0x01000027);

/*
		commandGenerator.writeRaw(0x40808080);
		commandGenerator.writeRaw(Point(260,0));
		commandGenerator.writeRaw(Point(460,120));
*/
		commandGenerator.writeRaw(0x40808080);
		commandGenerator.writeRaw(Point(256,0));
		commandGenerator.writeRaw(Point(256,15));

/*
		commandGenerator.writeRaw(0x300000FF);
		commandGenerator.writeRaw(0x0017FF80);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x00000100);
		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(0x00800057);
*/
/*
		commandGenerator.writeRaw(0x300000FF);
		commandGenerator.writeRaw(Point(73,48));
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(Point(72,51));
		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(Point(75,49));
*/

#if 0
		// fill rect
		commandGenerator.writeRaw(0x02808080);
		commandGenerator.writeRaw(0x00000000); // At 0,00
		commandGenerator.writeRaw(0x00400040); // H:16,W:16
#endif

#if 0
		// TRIANGLE
		commandGenerator.writeRaw(0x32FF0000);
		commandGenerator.writeRaw(0x00100010);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x0010004F);
		commandGenerator.writeRaw(0x000000FF);
		commandGenerator.writeRaw(0x004F004F);

#endif

#if 0
		// RECT FILL TEST
		commandGenerator.writeRaw(0x6000FF00); // Green, Rect (Variable Size)
		commandGenerator.writeRaw(0x00080008); // [8,8]
		commandGenerator.writeRaw(0x00100010); // 16x16

		// RECT FILL TEST
		commandGenerator.writeRaw(0x6000FFFF); // Green, Rect (Variable Size)
		commandGenerator.writeRaw(0x00180018); // [8,8]
		commandGenerator.writeRaw(0x00100010); // 16x16

		// RECT FILL TEST
		commandGenerator.writeRaw(0x60FFFF00); // Green, Rect (Variable Size)
		commandGenerator.writeRaw(0x00280028); // [8,8]
		commandGenerator.writeRaw(0x00100010); // 16x16
#endif

#if 0
		commandGenerator.writeRaw(0x25FFFFFF); // 0x25 / 0x27
		commandGenerator.writeRaw(0x00600060);	// X,Y
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x00600120);	// X,Y
		commandGenerator.writeRaw(0x00000340 | (((2<<7))<<16));
		commandGenerator.writeRaw(0x00E000A0);	// X,Y
		commandGenerator.writeRaw(0x00002020);

		
		commandGenerator.writeRaw(0x64FFFF00); // Green, Rect (Variable Size)
		commandGenerator.writeRaw(0x01800080); // [8,8]
		commandGenerator.writeRaw(0x00000000); // [8,8]
		commandGenerator.writeRaw(0x00400040); // 16x16
#endif

/*
  1st  Color+Command     (CcBbGgRrh) (color is ignored for raw-textures)
  2nd  Vertex1           (YyyyXxxxh)
  3rd  Texcoord1+Palette (ClutYyXxh)
  4th  Vertex2           (YyyyXxxxh)
  5th  Texcoord2+Texpage (PageYyXxh)
  6th  Vertex3           (YyyyXxxxh)
  7th  Texcoord3         (0000YyXxh)
 (8th) Vertex4           (YyyyXxxxh) (if any)
 (9th) Texcoord4         (0000YyXxh) (if any)
*/

/*
		commandGenerator.writeRaw(0x25FFFFFF); // 0x25 / 0x27
		commandGenerator.writeRaw(0x00600060);	// X,Y
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x00600120);	// X,Y
		commandGenerator.writeRaw(0x00000340 | (((2<<7))<<16));
		commandGenerator.writeRaw(0x00E000A0);	// X,Y
		commandGenerator.writeRaw(0x00002020);

		// TRIANGLE BLEND
#if 1
		commandGenerator.writeRaw(0x32FF0000);
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x000000F0);
		commandGenerator.writeRaw(0x000000FF);
		commandGenerator.writeRaw(0x00F000F0);
#endif
		// Simple vertices, no texture, nothing...

		commandGenerator.writeRaw(0x28ffffff);
		commandGenerator.writeRaw(0xffb9011c);
		commandGenerator.writeRaw(0xffb901bc);
		commandGenerator.writeRaw(0xffcd012e);
		commandGenerator.writeRaw(0xffcd012e);
*/

		/*
		commandGenerator.writeRaw(0x32FFFFFF);    // Color1+Command.  Shaded three-point polygon, semi-transparent.
		commandGenerator.writeRaw(0x00000000);    // Vertex 1. (YyyyXxxxh)
		commandGenerator.writeRaw(0x00FFFFFF);    // Color2.   (00BbGgRrh)  
		commandGenerator.writeRaw(0x00000015);    // Vertex 2. (YyyyXxxxh)
		commandGenerator.writeRaw(0x00FFFFFF);    // Color3.   (00BbGgRrh)  
		commandGenerator.writeRaw(0x00090010);    // Vertex 3. (YyyyXxxxh)
		*/

		/*
		commandGenerator.writeRaw(0x300000FF);    // Color1+Command.  Shaded three-point polygon, semi-transparent.
		commandGenerator.writeRaw(0x00000000);    // Vertex 1. (YyyyXxxxh)
		commandGenerator.writeRaw(0x0000FF00);    // Color2.   (00BbGgRrh)  
		commandGenerator.writeRaw(0x0000000F);    // Vertex 2. (YyyyXxxxh)
		commandGenerator.writeRaw(0x00FF0000);    // Color3.   (00BbGgRrh)  
		commandGenerator.writeRaw(0x000F000F);    // Vertex 3. (YyyyXxxxh)
		*/

#if 0
		commandGenerator.writeRaw(0x02FF0000);
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x00F00050);
						  			
		commandGenerator.writeRaw(0x0200FF00);
		commandGenerator.writeRaw(0x00000050);
		commandGenerator.writeRaw(0x00F00050);
						  			
		commandGenerator.writeRaw(0x020000FF);
		commandGenerator.writeRaw(0x000000A0);
		commandGenerator.writeRaw(0x00F00050);
						  			
		commandGenerator.writeRaw(0x02FFFFFF);
		commandGenerator.writeRaw(0x000000F0);
		commandGenerator.writeRaw(0x00F00050);
						  			
		commandGenerator.writeRaw(0x320000FF);
		commandGenerator.writeRaw(0x00400040);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x00400100);
		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(0x00C00080);

		commandGenerator.writeRaw(0x320000FF);
		commandGenerator.writeRaw(0x00150015);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x00550115);
		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(0x00D50095);
#endif
		/*
		commandGenerator.writeRaw(0x320000FF);
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x0000000F);
		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(0x000F000F);
		*/
#if 0
		// ------------------------------------------------
		// CPU->VRAM
		commandGenerator.writeRaw(0xA0000000);
		// At 0,0
		commandGenerator.writeRaw(0x00000000);
		// 6x2 pixels
		commandGenerator.writeRaw(0x00020006);
		// Pixels
		commandGenerator.writeRaw(0x03E0001F);
		commandGenerator.writeRaw(0x7FFF7C00);
		commandGenerator.writeRaw(0x03FF7C1F);
		commandGenerator.writeRaw(0x7C1F03FF);
		commandGenerator.writeRaw(0x7C007FFF);
		commandGenerator.writeRaw(0x001F03E0);

#endif
/*
		commandGenerator.writeRaw(0x25FFFFFF);
		commandGenerator.writeRaw(0x00600060);
		commandGenerator.writeRaw(0x00000000);
		commandGenerator.writeRaw(0x00600120);
		commandGenerator.writeRaw(0x000020FF | (((2<<7))<<16));
		commandGenerator.writeRaw(0x00E000A0);
		commandGenerator.writeRaw(0x00006025);
*/
		/*
		commandGenerator.writeRaw(0x30FF0000);    // Color1+Command.  Shaded three-point polygon, opaque.
		commandGenerator.writeRaw(0x00000000);    // Vertex 1. (YyyyXxxxh)  Y=0. X=0
		commandGenerator.writeRaw(0x0000FF00);    // Color2.   (00BbGgRrh)
		commandGenerator.writeRaw(0x0000009F);    // Vertex 2. (YyyyXxxxh)  Y=0. X=64
		commandGenerator.writeRaw(0x000000FF);    // Color3.   (00BbGgRrh)
		commandGenerator.writeRaw(0x007F0020);    // Vertex 3. (YyyyXxxxh)  Y=64. X=64
		*/

		 /*
		commandGenerator.writeRaw(0x380000b2);
		commandGenerator.writeRaw((192<<0) | (240<<16));
		commandGenerator.writeRaw(0x00008cb2);
		commandGenerator.writeRaw((320<<0) | (112<<16));
		commandGenerator.writeRaw(0x00008cb2);
		commandGenerator.writeRaw((320<<0) | (368<<16));
		commandGenerator.writeRaw(0x000000b2);
		commandGenerator.writeRaw((448<<0) | (240<<16));
		*/
	}
	break;
	case TEXTURE_TRUECOLOR_BLENDING:
	{
		commandGenerator.writeRaw(0xE6000000);						// Set Bit mask, no check.

#if 1
		/*
		commandGenerator.writeRaw(0x7FFF001F); // 01
		commandGenerator.writeRaw(0x7C007C1F); // 23
		commandGenerator.writeRaw(0x000003E0); // 45
		commandGenerator.writeRaw(0x03E07C00); // 67
		commandGenerator.writeRaw(0x7FFF0000); // 89
		commandGenerator.writeRaw(0x03E07FFF); // AB
		commandGenerator.writeRaw(0x7FFF0000); // CD
		commandGenerator.writeRaw(0x00007C00); // EF
		*/
		
		// 4x4 pixel texture upload.
		commandGenerator.writeRaw(0xA0000000); // Copy rect from CPU to VRAM
		commandGenerator.writeRaw(0x00000000); // to 0,0
		commandGenerator.writeRaw(0x00040004); // Size 4,4

		commandGenerator.writeRaw(0xFC00801F); // 01
		commandGenerator.writeRaw(0x8000FFFF); // 23

		commandGenerator.writeRaw(0xFC1FFFFF); // 45
		commandGenerator.writeRaw(0x8000FFFF); // 67

		commandGenerator.writeRaw(0xFFFFFFFF); // 89
		commandGenerator.writeRaw(0xFFF0FFF0); // AB

		commandGenerator.writeRaw(0xFFFFFFFF); // CD
		commandGenerator.writeRaw(0xFFF1FFF1); // EF

		commandGenerator.writeRaw(0xA0000000); // Copy rect from CPU to VRAM
		commandGenerator.writeRaw(0x00000004); // to 0,0
		commandGenerator.writeRaw(0x00040001); // Size 4,4

		commandGenerator.writeRaw(0x83E083E0); // 01
		commandGenerator.writeRaw(0x83E083E0); // 23
		
		commandGenerator.writeRaw(0x25FFFFFF);
		commandGenerator.writeRaw(0x00100010);
		commandGenerator.writeRaw(0xFFF30000);
		
		commandGenerator.writeRaw(0x00100110);
		commandGenerator.writeRaw((( 0 | (0<<4) | (0<<5) | (2<<7) | (0<<9) | (0<<11) )<<16 ) | 0x0004);                        // [15:8,7:0] Texture [4,0]
		commandGenerator.writeRaw(0x01100110);
		commandGenerator.writeRaw(0x00000404);                        // Texture [4,4]
		/*



		//---------------
		//   Tri, textured
		//---------------
		commandGenerator.writeRaw(0x25AABBCC);                        // Polygon, 3 pts, opaque, raw texture
		// Vertex 1
//		commandGenerator.writeRaw(0x00550050);                        // [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 0)
		commandGenerator.writeRaw(0x00100010);

		commandGenerator.writeRaw(0xFFF30000);                        // [31:16]Color LUT : NONE, value ignored
																// [15:8,7:0] Texture [0,0]
		// Vertex 2
//		commandGenerator.writeRaw(0x00050090);                        // [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 1)
		commandGenerator.writeRaw(0x00100110);                        // [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 1)
		commandGenerator.writeRaw((( 0 | (0<<4) | (0<<5) | (2<<7) | (0<<9) | (0<<11) )<<16 ) | 0x0004);                        // [15:8,7:0] Texture [4,0]
		// Vertex 3
//		commandGenerator.writeRaw(0x00800155);                        // [15:0] XCoordinate, [31:16] Y Coordinate
		commandGenerator.writeRaw(0x01100110);                        // [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 1)
		commandGenerator.writeRaw(0x00000404);                        // Texture [4,4]
		*/
#else
		commandGenerator.writeRaw(0x30AABBCC);
		commandGenerator.writeRaw(0x01100100);

		commandGenerator.writeRaw(0x00FF0000);
		commandGenerator.writeRaw(0x00100180);

		commandGenerator.writeRaw(0x0000FF00);
		commandGenerator.writeRaw(0x01200230);						// [15:0] XCoordinate, [31:16] Y Coordinate

#endif
	}
	break;
	case TEXTURE_PALETTE_BLENDING:
	{
		//commandGenerator.writeRaw(0xn (8)	);
		// DO NOT MAKE THE TRIANGLE TOO LARGE : BUG MOSTLY DISAPPEAR BECAUSE CACHE MISS DONT OCCUR MUCH PER PIXEL... Only edge show the bug.
		// This is the best size to see the problem.
		/*
		commandGenerator.writeRaw(0x2cFFFFFF);
		commandGenerator.writeRaw(0x00800000);	// XY
		commandGenerator.writeRaw(0x10000000);
		commandGenerator.writeRaw(0x00800080);	// XY
		commandGenerator.writeRaw(0x00000020);
		commandGenerator.writeRaw(0x01000000);	// XY
		commandGenerator.writeRaw(0x00002000);
		commandGenerator.writeRaw(0x01000080);	// XY
		commandGenerator.writeRaw(0x00002020);
		*/

		commandGenerator.writeRaw(0x25AABBCC);						// Polygon, 3 pts, opaque, raw texture
		// Vertex 1
		commandGenerator.writeRaw(0x00400000);						// [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 0)
		commandGenerator.writeRaw(
			((0 | (0<<6))<<16) | 0x0000							// 512,96 Palette, TexUV[0,0]
		);
		// Vertex 2
		commandGenerator.writeRaw(0x00400040);						// [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 1)
		commandGenerator.writeRaw((
			// 4 BPP !!!!
			(0) | (0<<4) | (0<<5) | (0<<7) | (0<<9) | (0<<11)			// [31:16] Texture at 0(4x64),0 TRUE COLOR
			)<<16                   | 0x001F);						// [15:8,7:0] Texture [1F,0]
																	// Vertex 3
		commandGenerator.writeRaw(0x00800000);						// [15:0] XCoordinate, [31:16] Y Coordinate
		commandGenerator.writeRaw(0x00001F1F);						// Texture [1F,1F]
		break;
	}
	case POLY_FAIL:

#if 0
		/*
		commandGenerator.writeRaw(0xe2000000);
		commandGenerator.writeRaw(0xe3000000);
		commandGenerator.writeRaw(0xe403bd3f);
		commandGenerator.writeRaw(0xe5000000);
		commandGenerator.writeRaw(0xe6000000);
		commandGenerator.writeRaw(0xe100060a);

		commandGenerator.writeRaw(0x2c808080);
		commandGenerator.writeRaw(0x00500132);
		commandGenerator.writeRaw(0x7b0c7000);
		commandGenerator.writeRaw(0x00510132);
		commandGenerator.writeRaw(0x00187f00);
		commandGenerator.writeRaw(0x00510141);
		commandGenerator.writeRaw(0x0913707f);
		*/
		commandGenerator.writeRaw(0xE3000000);
		commandGenerator.writeRaw(0xE4077e7f);

		commandGenerator.writeRaw(0x30ff8080);
		commandGenerator.writeRaw(0x00f00140);
		commandGenerator.writeRaw(0x00200000);
		commandGenerator.writeRaw(0x00f0001e);
		commandGenerator.writeRaw(0x00200000);
		commandGenerator.writeRaw(0x015e0034);

		commandGenerator.writeRaw(0x30ff8080);
		commandGenerator.writeRaw(0x00f00140);
		commandGenerator.writeRaw(0x00200000);
		commandGenerator.writeRaw(0x00810034);
		commandGenerator.writeRaw(0x00200000);
		commandGenerator.writeRaw(0x00f0001e);
#endif
		break;
	case PALETTE_FAIL_LATEST:
		{
		u16* buff16 = (u16*)buffer;
		u16* pFill = &buff16[(1024*480) + 256];

		if (1) {
			// Patch palette.
			*pFill++ = 0x0000;
			*pFill++ = 0x1111;
			*pFill++ = 0x2222;
			*pFill++ = 0x3333;
			*pFill++ = 0x4444;
			*pFill++ = 0x5555;
			*pFill++ = 0x6666;
			*pFill++ = 0x7777;
			*pFill++ = 0x8888;
			*pFill++ = 0x9999;
			*pFill++ = 0xAAAA;
			*pFill++ = 0xBBBB;
			*pFill++ = 0xCCCC;
			*pFill++ = 0xDDDD;
			*pFill++ = 0xEEEE;
			*pFill++ = 0xFFFF;

			for (int y=0; y < 64; y++) {
				pFill = &buff16[(y*1024) + 896];
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
				// 16 pix
				*pFill++ = 0x3210;
				*pFill++ = 0x7654;
				*pFill++ = 0xBA98;
				*pFill++ = 0xFEDC;
			}
		}

		commandGenerator.writeRaw(0x2c808080);
		commandGenerator.writeRaw(0x017e00c8);
		commandGenerator.writeRaw(0x78100000);
		commandGenerator.writeRaw(0x017e01b8);
		commandGenerator.writeRaw(0x000e00ef);
		commandGenerator.writeRaw(0x01ba00c8);
		commandGenerator.writeRaw(0x00003b00);
		commandGenerator.writeRaw(0x01ba01b8);
		commandGenerator.writeRaw(0x00003bef);
		}

		break;
	case USE_DUMP_SIM:
		loadDump		(dumpFileName,mod,(u16*)buffer);
		loadGPUCommands	(log_inFileName,commandGenerator);
		break;
	case USE_AVOCADO_DATA:
	{
		if (fileName) {
			if (binSrc) {
				fclose(binSrc);
			}
			fopen(fileName,"rb");		// GOOD COMPLETE
		}
		
		// ----- Read VRAM
		u16* buff16 = (u16*)buffer;
		fread(buffer,sizeof(u16),1024*512,binSrc);

		// ----- Sync Stencil cache and VRAM state.
		for (int y=0; y < 512; y++) {
			for (int x=0; x < 1024; x++) {
				bool bBit    = (buff16[x + (y*1024)] & 0x8000) ? true : false;
				setStencil(mod,x,y,bBit);
			}
		}

		// ---- Setup
		u32 setupCommandCount;
		fread(&setupCommandCount, sizeof(u32), 1, binSrc);
		for (int n=0; n < setupCommandCount; n++) {
			u32 cmdSetup;
			fread(&cmdSetup, sizeof(u32),1, binSrc);
			commandGenerator.writeRaw(cmdSetup);
		}

#if 0
		int removeList[] = { 
			11,12,13,14,15,16,17,18,19,
			20,21,22,23,24,25,26,27,28,29,
			30,31,32,33,34,35,36,37,38,39,
			40,41,42,43,44,45,46,47,48,49,
			50,51,52,53,54,55,56,57,58,59,
			60,61,62,63,64,65,66,
			//	67
		};
#endif

		// ---- Commands itself.
		u32 logCommandCount;
		fread(&logCommandCount, sizeof(u32), 1, binSrc);
		for (int n=0; n < logCommandCount; n++) {
			u32 cmdLengthRAW;
			fread(&cmdLengthRAW, sizeof(u32),1, binSrc);

			bool removeCommand = false;
#if 0
			for (int s=0; s < sizeof(removeList)/sizeof(int); s++) {
				if (removeList[s] == n) {
					removeCommand = true;
				}
			}
#endif


			u32 cmdLength = cmdLengthRAW & 0xFFFFFF;

			if ((cmdLengthRAW & 0xFF000000) == 0) {
//				printf("Cmd Length : %i ",cmdLength);
//				bool ignoreCommand = (n < 79940) || ( n > 80005);
				bool ignoreCommand = false;
				bool isLine = false;
				int  lineCnt = 0;
				bool isMulti = false;
				bool isColored = false;

				for (int m=0; m < cmdLength; m++) {
					u32 operand;
					fread(&operand, sizeof(u32),1, binSrc);
					if (!removeCommand) {

						if (m==0) {
							if (!ignoreCommand) {
								// printf("// LOG COMMAND Number %i [%x] (%i op)\n",n+1,operand>>24,cmdLength);
							}
							isLine    = (((operand>>24) & 0xE0) == 0x40);
							isMulti   = (operand>>24) & 0x08;
							isColored = (operand>>24) & 0x10;
							lineCnt = 0;

							bool isVCCopy = (operand>>24) == 0xC0;
							// bool isCVCopy = (operand>>24) == 0xA0;
							if (((operand>>24) == 0x80) || (isVCCopy) /*|| (isCVCopy)*/) {
								ignoreCommand = true;
								/*
								if (isCVCopy) {
									fread(&operand, sizeof(u32),1, binSrc);
									fread(&operand, sizeof(u32),1, binSrc); // H,W
									int w=operand & 0xFFFF;
									int h=(operand>>16) & 0xFFFF;
									int count = (w*h);
									count += count & 1;

									// Ridiculous error...
									fread(&operand, sizeof(u32),1, binSrc);
									fread(&operand, sizeof(u32),1, binSrc);
									m = 4;
								}
								*/
								if (isVCCopy) {
									fread(&operand, sizeof(u32),1, binSrc);
									fread(&operand, sizeof(u32),1, binSrc); // H,W
									m = 3;
								}
							}

							if (isLine) {
	//							ignoreCommand = true;
							}
						}

						if (!ignoreCommand) {
							commandGenerator.writeRaw(operand, m==0, 0);
							if (isLine) {
								printf("LINE commandGenerator.writeRaw(0x%08x);\n",operand);
								switch (lineCnt)
								{
								case 0:
									if (isMulti && (m!=0) && ((operand & 0x50005000) == 0x50005000)) {
										printf("END LINE MULTI.\n");
										lineCnt = 0;
									} else {
										printf("\nColor : %x\n",operand & 0xFFFFFF);
										lineCnt = 1;
									}
									break;
								case 1:
									if (isMulti && ((operand & 0x50005000) == 0x50005000)) {
										printf("END LINE MULTI.\n");
									} else {
										printf("Vertex : %i,%i\n",((int)(operand & 0xFFFF)<<16)>>16,(((int)(operand))>>16));
										if (isColored) {
											lineCnt = 0;
										} else {
											lineCnt = 1; // As Is
										}
									}
									break;
								case 2: break;
								case 3: break;
								default:
									break;
								}
							} else {
//								printf("commandGenerator.writeRaw(0x%08x);\n",operand);
							}
						}
					}
				}
			} else {
				for (int m=0; m < cmdLength; m++) {
					u32 operand;
					fread(&operand, sizeof(u32),1, binSrc);
//					if ((cmdLengthRAW >> 24) == 1) {
						printf("GP1:%08x\n",operand);
						commandGenerator.writeGP1(operand);
//					}
				}
			}
			if (feof(binSrc)) {
				break;
			}
		}

		fclose(binSrc);
	}
	break;
	case COPY_FROMRAM:
		{

			// Random stuff

		}

	break;
	case COPY_TORAM:
		{
			u8* target = buffer;
			// Transform each pixel RGB888 into a single bit.
			for (int py=0; py < 512; py++) {
				for (int px=0; px < 1024; px++) {
					int baseDst = ((px+py*1024)*2);
					target[baseDst  ]  = px;
					target[baseDst+1]  = py;
				}
			}
		}

		commandGenerator.writeRaw(0xC0000000);
		commandGenerator.writeRaw((0)|(0<<16));
		commandGenerator.writeRaw((2<<16) | 4); // W=4,H=2
	break;
	case COPY_CMD:
	{
		commandGenerator.writeRaw(0x80000000);
		commandGenerator.writeRaw((256)|(256<<16));
		commandGenerator.writeRaw(( 64)|( 64<<16));
		commandGenerator.writeRaw((16<<16) | 16); // W=16,H=16
#if 0
		int from =  3;
//		int to   = 12;
//		int l    =  31;
/*
		commandGenerator.writeRaw(0x80000000);
		commandGenerator.writeRaw(0x00000010);		// X=16,Y=0 SRC
		commandGenerator.writeRaw((   0)|(1<<16));	// X=0 ,Y=1 DST
		commandGenerator.writeRaw(0x00010000 | 17); // W=17,H=1
		*/

//		for (int from = 16; from < 32; from++) {

		int y = 50;
		// SrcX = 0..15
		// DstX = 0..15
		// Src > Dst and Src < Dst
//		for (int l = 1; l < 2; l++) {
		int l = 150;
		int srcX = 128;
//			for (int srcX=128; srcX < (128+16); srcX++) 
			//int x = 0;
			{

				int dstX = 128;
//				for (int dstX=(10); dstX < 400; dstX++) 
				{
					srcX = dstX;
					int v = 0;
//					for (v = 0; v < 8; v++)
					{
						commandGenerator.writeRaw(0x80000000);
						commandGenerator.writeRaw(srcX);
						commandGenerator.writeRaw((dstX+(v)*60) | (y<<16)); // Y Position
						commandGenerator.writeRaw((0x0001<<16) | l);
					}
					y++;
				}
			}
//		}
		/*
		commandGenerator.writeRaw(              from);
		commandGenerator.writeRaw((128 << 16) | (to));	// Y,X Dest
		commandGenerator.writeRaw((  1 << 16) |  (l)); // Height, Width
		test(from, to, l, adrStorage, &adrStorageCount);
		*/
#endif
	}
	break;
	}
	
	commandGenerator.writeRaw(0); // NOP
#endif

#if 0
	// FILL TEST
	commandGenerator.writeRaw(0x028000FF); // Red + Half Blue
	commandGenerator.writeRaw(0x00000000); // 0,0
	commandGenerator.writeRaw(0x00100010); // 16,16
#endif

#if 0
	// RECT FILL TEST
	commandGenerator.writeRaw(0x6000FF00); // Green, Rect (Variable Size)
	commandGenerator.writeRaw(0x00080008); // [8,8]
	commandGenerator.writeRaw(0x00100010); // 16x16
#endif

#if 0
	// GENERIC POLYGON FILL
	commandGenerator.writeRaw(0x380000b2);
	commandGenerator.writeRaw((192<<0) | (240<<16));
	commandGenerator.writeRaw(0x00008cb2);
	commandGenerator.writeRaw((320<<0) | (112<<16));
	commandGenerator.writeRaw(0x00008cb2);
	commandGenerator.writeRaw((320<<0) | (368<<16));
	commandGenerator.writeRaw(0x000000b2);
	commandGenerator.writeRaw((448<<0) | (240<<16));
#endif

#if 0
// GP0(40h) - Monochrome line, opaque
// GP0(42h) - Monochrome line, semi-transparent
	commandGenerator.writeRaw(0x4000FFFF);
	commandGenerator.writeRaw(0x00000000);
	commandGenerator.writeRaw(0x00100010);

	commandGenerator.writeRaw(0x40FF0000);
	commandGenerator.writeRaw(0x00000000);
	commandGenerator.writeRaw(0x00400010);
#endif

#if 0
	// Test CPU->VRAM
	loadImageToVRAMAsCommand(commandGenerator,"Gradient128x64.png",0,0,false);
#endif

#if 0
	//
	// TEXTURED POLYGON
	//
	loadImageToVRAM(mod,"Gradient128x64.png",buffer,0,0,false);
	commandGenerator.writeRaw(0x24FFFFFF);						// Polygon, 3 pts, opaque, raw texture
	// Vertex 1
	commandGenerator.writeRaw(0x01100100);						// [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 0)
	commandGenerator.writeRaw(0xFFF30000);						// [31:16]Color LUT : NONE, value ignored
																// [15:8,7:0] Texture [0,0]
	// Vertex 2
	commandGenerator.writeRaw(0x00100180);						// [15:0] XCoordinate, [31:16] Y Coordinate (VERTEX 1)
	commandGenerator.writeRaw(((
		0 | (0<<4) | (0<<5) | (2<<7) | (0<<9) | (0<<11)			// [31:16] Texture at 0(4x64),0 ******4BPP******
		)<<16 )                  | 0x001F);						// [15:8,7:0] Texture [1F,0]
																// Vertex 3
	commandGenerator.writeRaw(0x01200230);						// [15:0] XCoordinate, [31:16] Y Coordinate
	commandGenerator.writeRaw(0x00001F1F);						// Texture [1F,1F]
#endif

#if 0
	//commandGenerator.writeRaw(0xE100000F);

	
#endif

	// prepairListOfGPUCommands(0); // Simple Polygon, no texture, no alpha blending.
	// prepairListOfGPUCommands(1);	// Simple Polygon, true color texture, no alpha blending.
	// prepairListOfGPUCommands(2);	// Simple Polygon, 4 bit texture, no alpha blending.

	// ------------------------------------------------------------------
	// MAIN LOOP
	// ------------------------------------------------------------------

	int SrcY = 17;
	int DstY = 57;

	// Test pattern
	bool performTest = true;


	int XSrc = 16;
	int XDst = 17;
	int W    = 1;
	int mode = 0;

#if 0
	for (mode = 0; mode < 4; mode++) 
	{
		for (XSrc = 16; XSrc <= 31; XSrc++) 
		{
			for (XDst = 0; XDst <= 47; XDst++) 
			{
				printf("Mode:%i SrcX:%i DstX:%i W:1..64\n",mode, XSrc,XDst);
				for (W = 1; W <= 64; W++) 
				{

				// Rollback and clean everything...
				memcpy(buffer    ,refBuffer,1024*1024);
				memcpy(softbuffer,refBuffer,1024*1024);
				backupToStencil(mod,refStencil);

				if (verifyStencilVRAM(mod, (u16*)softbuffer)) {
					printf("STENCIL$ DIFFERENCE");
					while (1) { printf(""); };
				}


				commandGenerator.writeRaw(0xE6000000 | mode);						// Set Bit mask, no check.

				// Prepare HW Command
				commandGenerator.writeRaw(0x80000000);
				commandGenerator.writeRaw((SrcY<<16) + XSrc);
				commandGenerator.writeRaw((DstY<<16) + XDst);
				commandGenerator.writeRaw(0x00010000 | W); 

				bool isChecking = mode & 2 ? true : false;
				bool isForcing  = mode & 1 ? true : false;


				// Execute SW Command
				softVVCopy(XSrc,SrcY,XDst,DstY,W,1,(u16*)softbuffer, isChecking, isForcing);
#endif


	int waitCount = 0;

	u8* bufferRGBA     = new u8[1024*1024*4];
	heatMapRGB = &bufferRGBA[1024*512*4];
	memset(heatMapRGB,0,1024*512*4);

	buffer32Bit = bufferRGBA;
	struct mfb_window *window = mfb_open_ex("my display", 1024, useHeatMap ? 1024 : 512, WF_RESIZABLE);
	if (!window)
		return 0;
	mfb_set_viewport(window,0,0,1024,useHeatMap ? 1024 : 512);

	int stuckState = 0;
	int prevCommandParseState = -1;
	int prevCommandWorkState  = -1;

	int readTexture = 0;
	int readBGOrClut = 0;
	int writeCount = 0;

//	TestSuite(bufferRGBA, window);

//	ThinTriangles(bufferRGBA, window);
//	RandomBenchTriangle(bufferRGBA, window);

	if (useSWRender || compare) {
		RenderCommandSoftware(bufferRGBA, buffer,(u64)-1,commandGenerator,window);
		printTotalTimeCycle();
		return 0;
	}

//	Sleep(5000);

	bool log
#ifdef RELEASE
		= false;
#else
		= true;
#endif

	CacheSim* cache = new CacheSim(swizzleMode,cacheLineCount);

	int primitiveCount = 0;

	bool updateBuff = false;
	while (
//		(waitCount < 20)					// If GPU stay in default command wait mode for more than 20 cycle, we stop simulation...
//		&& (stuckState < 2500)
		(clockCnt < lengthCycle)
		&& (((currentCommandID <= sTo+1) && (sTo >= 0)) || (sTo == -1))
	)
	{
		// By default consider stuck...
		stuckState++;

		bool savePic = false;
		// updateBuff = ((clockCnt>>1) & 0xFFF) == 0;
		updateBuff = false;

		if (log) {
			// If some work is done, reset stuckState.
			if (GetCurrentParserState(mod) != prevCommandParseState) { 
#if 1
				VCMember* pCurrState = pScan->findMemberFullPath("GPU_DDR.gpu_inst.gpu_parser_instance.currState");
//				printf("NEW STATE : %s (Data=%08x)\n", pCurrState->getEnum()[mod->GPU_DDR__DOT__gpu_inst__DOT__gpu_parser_instance__DOT__currState].outputString /*,clockCnt >> 1*/,mod->GPU_DDR__DOT__gpu_inst__DOT__fifoDataOut);
	//			printf("NEW STATE : %i\n", mod->gpu__DOT__currState);
#endif
				stuckState = 0; prevCommandParseState = GetCurrentParserState(mod); 
				if (prevCommandParseState == 1) {	// switched to LOAD_COMMAND
//					printf("\t[%i] COMMAND : %x (%i/%i)\n",currentCommandID,mod->GPU_DDR__DOT__gpu_inst__DOT__command, mod->GPU_DDR__DOT__gpu_inst__DOT__HitACounter, mod->GPU_DDR__DOT__gpu_inst__DOT__TotalACounter);
//					printf("\t[%i] COMMAND : %x\n",currentCommandID,mod->GPU_DDR__DOT__gpu_inst__DOT__command);
					currentCommandID++;				// Increment current command ID.
					updateBuff = true;
				}
			}
	
			//
			// Update window every 2048 cycle.
			//
			if (updateBuff && !removeVisuals) {
//			if (((clockCnt & 0x3F)==0)) {
				Convert16To32(buffer, bufferRGBA);
//				Convert16To32((u8*)swBuffer, bufferRGBA);

				int state = mfb_update(window,bufferRGBA);
				static int prevClockCnt = 0;
				updateBuff = false;

				int diffClock = clockCnt - prevClockCnt;
				// printf("Clock %i (%i)\n",clockCnt,currentCommandID);
				prevClockCnt = clockCnt;				

				if (state < 0)
					break;
			}
		}

/*
		if ( GetCurrentParserState(mod) == 0 && 
			// Wait for Memory fifo to be empty...
			(mod->GPU_DDR__DOT__gpu_inst__DOT__MemoryArbitratorInstance__DOT__FIFOCommand__DOT__fifo_fwftInst__DOT__empty == 1)) {
			waitCount++; 
		} else {
			waitCount = 0; 
		}
*/

		mod->clk    = 0;
		mod->eval();

		// Generate VCD if needed
		if (useScan) {
			if ((sFrom==-1) || ((currentCommandID >= sFrom) && (currentCommandID <= sTo))) {
				tfp.dump(clockCnt);
			}
		}
		clockCnt++;

		static int busyCounter = 0;
		static bool isRead = false;
		static int readAdr = 0;
		static int readSize= 0;
		enum ESTATE {
			DEFAULT = 0,

		};

		mod->i_busy = rand() & 1;

		mod->clk    = 1;
		mod->eval();

		if (useHeatMap && !removeVisuals) {
			if ((clockCnt>>1 & 31) == 0) {
				UpdateHeatMap();
				int state = mfb_update(window,bufferRGBA);
			}
		}

		// Write Request
		// 
		static bool beginTransaction = true;
		static int  burstSize        = 0;
		static int  burstSizeRead    = 0;
		static int  burstAdr         = 0;


		if (mod->o_write == 1 && mod->o_command && (mod->i_busy == 0)) {
			switch (mod->o_commandSize) {
			case 1:
				burstSize  = 4;
				break;
			case 0:	// 8 Not supported for write.
			case 2:	// 4 Not supported anymore
			default:
				while (1) {}; break;
			}
			burstAdr   = (mod->o_adr<<5) + (mod->o_subadr<<2);
			beginTransaction = false;
			if (useHeatMap) { SetWriteHeat(burstAdr>>5); }

			int baseAdr = burstAdr;

			writeCount++;
/*
			if (baseAdr != (mod->o_targetAddr<<3)) {
				printf("WRITE ERROR !\n");
				error = 1;
				// pScan->shutdown();
			}
*/

			int selPix = mod->o_writeMask;

			u32 w = mod->o_dataOut[0];
			if (selPix & 0x01) { buffer[baseAdr  ] =  w      & 0xFF; }
			if (selPix & 0x01) { buffer[baseAdr+1] = (w>> 8) & 0xFF; }
			if (selPix & 0x02) { buffer[baseAdr+2] = (w>>16) & 0xFF; }
			if (selPix & 0x02) { buffer[baseAdr+3] = (w>>24) & 0xFF; }

			w = mod->o_dataOut[1];
			if (selPix & 0x04) { buffer[baseAdr+4] = (w>> 0) & 0xFF; }
			if (selPix & 0x04) { buffer[baseAdr+5] = (w>> 8) & 0xFF; }
			if (selPix & 0x08) { buffer[baseAdr+6] = (w>>16) & 0xFF; }
			if (selPix & 0x08) { buffer[baseAdr+7] = (w>>24) & 0xFF; }

			w = mod->o_dataOut[2];
			if (selPix & 0x10) { buffer[baseAdr+8] = (w>> 0) & 0xFF; }
			if (selPix & 0x10) { buffer[baseAdr+9] = (w>> 8) & 0xFF; }
			if (selPix & 0x20) { buffer[baseAdr+10]= (w>>16) & 0xFF; }
			if (selPix & 0x20) { buffer[baseAdr+11]= (w>>24) & 0xFF; }

			w = mod->o_dataOut[3];
			if (selPix & 0x40) { buffer[baseAdr+12]= (w>> 0) & 0xFF; }
			if (selPix & 0x40) { buffer[baseAdr+13]= (w>> 8) & 0xFF; }
			if (selPix & 0x80) { buffer[baseAdr+14]= (w>>16) & 0xFF; }
			if (selPix & 0x80) { buffer[baseAdr+15]= (w>>24) & 0xFF; }

			w = mod->o_dataOut[4];
			if (selPix & 0x0100) { buffer[baseAdr+16] =  w      & 0xFF; }
			if (selPix & 0x0100) { buffer[baseAdr+17] = (w>> 8) & 0xFF; }
			if (selPix & 0x0200) { buffer[baseAdr+18] = (w>>16) & 0xFF; }
			if (selPix & 0x0200) { buffer[baseAdr+19] = (w>>24) & 0xFF; }

			w = mod->o_dataOut[5];
			if (selPix & 0x0400) { buffer[baseAdr+20] = (w>>0) & 0xFF; }
			if (selPix & 0x0400) { buffer[baseAdr+21] = (w>>8) & 0xFF; }
			if (selPix & 0x0800) { buffer[baseAdr+22] = (w>>16) & 0xFF; }
			if (selPix & 0x0800) { buffer[baseAdr+23] = (w>>24) & 0xFF; }

			w = mod->o_dataOut[6];
			if (selPix & 0x1000) { buffer[baseAdr+24] = (w>>0) & 0xFF; }
			if (selPix & 0x1000) { buffer[baseAdr+25] = (w>>8) & 0xFF; }
			if (selPix & 0x2000) { buffer[baseAdr+26] = (w>>16) & 0xFF; }
			if (selPix & 0x2000) { buffer[baseAdr+27] = (w>>24) & 0xFF; }

			w = mod->o_dataOut[7];
			if (selPix & 0x4000) { buffer[baseAdr+28] = (w>>0) & 0xFF; }
			if (selPix & 0x4000) { buffer[baseAdr+29] = (w>>8) & 0xFF; }
			if (selPix & 0x8000) { buffer[baseAdr+30] = (w>>16) & 0xFF; }
			if (selPix & 0x8000) { buffer[baseAdr+31] = (w>>24) & 0xFF; }
		} else {
			error = 0;
		}

		static bool transactionRead = false;
		static int readLatency = 0;
		if (transactionRead && (readLatency==0)) {

			//
			// WARNING REUSE ADR SET AT CYCLE BEFORE
			//
			int	baseAdr = burstAdr;
			int itemCount;
			switch (burstSizeRead) {
			case 1:
				// 32 byte read.
				itemCount = 8;
				break;
			case 0:
				// 8 byte read.
				itemCount = 2;
				break;
			default:
				// 4 byte read.
				while (1) {}
				break;
			}
			mod->i_dataInValid = 1;

			u32 result = 0;

			for (int n=0; n < itemCount; n++) {
				result  = ((u64)buffer[baseAdr+0])<<0; 
				result |= ((u64)buffer[baseAdr+1])<<8; 
				result |= ((u64)buffer[baseAdr+2])<<16;
				result |= ((u64)buffer[baseAdr+3])<<24;
				baseAdr += 4;
				mod->i_dataIn[n] = result;
			}

	//		mod->eval();
			//
			// INCREMENT FOR NEXT READ.
			//
			transactionRead = false;
		} else {
			mod->i_dataInValid = 0;
			if (readLatency > 0) { readLatency--; }
//			mod->eval();
		}

		if ((mod->o_write == 0) && mod->o_command && (mod->i_busy == 0)) {
			if (!transactionRead) {
				burstSizeRead	= mod->o_commandSize;
				burstAdr		= (mod->o_adr<<5) | (mod->o_subadr<<2);
				readCount++;
				if (burstSizeRead == 0) {
					readTexture++;
				} else {
					readBGOrClut++;
				}

				if (uniqueReadsAdr[mod->o_adr] == false) {
					uniqueReadsAdr[mod->o_adr] = true;
					uniqueReadCount++;
				}

				transactionRead = true;

				if (cache->isCacheHit(mod->o_adr)) {
					readLatency = 1;
					readHit++;
				} else {
					readLatency = READ_LATENCY;
					cache->markCache(mod->o_adr,-1);
					cache->markCache(mod->o_adr+1,0);
					cache->markCache(mod->o_adr-1,1);
					cache->markCache(mod->o_adr+64,2);
//					cache->markCache(mod->o_adrPrefetch,-1);
//					printf("Dist %i\n",mod->o_adr - mod->o_adrPrefetch);
					// cache->markCache(mod->o_adr+2,3);
					readMiss++;
				}
				if (useHeatMap) { SetReadHeat(burstAdr>>5,readLatency > 1); }
			}
		}

		// -----------------------------------------
		//   [REGISTER SETUP OF GPU FROM BUS]
		// -----------------------------------------
		mod->i_write		= 0;
		mod->i_gpuSel		= 0;
		mod->i_gpuAdrA		= 0;
		mod->i_cpuDataIn	= 0;

		// Cheat... should read system register like any normal CPU...
		static int currRec = 0;

		if (mod->o_dbg_canWrite) {

			bool isGPUWaiting = true; // (mod->GPU_DDR__DOT__gpu_inst__DOT__gpu_parser_instance__DOT__currState == 0 /*DEFAULT_STATE wait*/);
			static int cycleCounter = 0;

			bool uploadData = false;
			if (commandGenerator.stillHasCommand()) {
				if (isGPUWaiting) {
					uploadData = (cycleCounter % 3)==0;
				} else {
					if (!commandGenerator.isCommandStart() && ((cycleCounter % 3)==0)) {
						uploadData = true;					
					}
				}
			}

			if (uploadData) {
				mod->i_gpuSel		= 1;
				if (commandGenerator.isGP1()) {
					mod->i_gpuAdrA		= 1;
				} else {
					mod->i_gpuAdrA		= 0;
				}
				mod->i_write		= 1;
				mod->i_cpuDataIn	= commandGenerator.getRawCommand();
//					printf("Send Command : %08x\n",mod->i_cpuDataIn);
			}
			
			cycleCounter++;
		}

		if (useScan) {
			if ((sFrom==-1) || ((currentCommandID >= sFrom) && (currentCommandID <= sTo))) {
				tfp.dump(clockCnt);
			}
		}

		// ----
		// PNG SCREEN SHOT PER CYCLE IF NEEDED.
		// ----
		clockCnt++;

		static int doNothing = 0;
		if (mod->o_dbg_busy & (~(8|16))) {
			doNothing = 0;
		} else {
			doNothing++;
			if (doNothing > 200) {
				break;
			}
		}
	}

	//
	// End Test, check buffer
	//
#if 0
	// 1. Verify coherency Stencil vs VRAM.

	// 2. Verify coherency VRAM vs Soft VRAM.
	if (performTest && mymemcmp(softbuffer,buffer,1024*1024)!=0) {
		printf(" DIFFERENCE !");
		dumpFrame(mod, "soft.png", "output_msk.png",softbuffer,clockCnt>>1, true);
		dumpFrame(mod, "hard.png", "output_msk.png",buffer    ,clockCnt>>1, true);
//		while (1) { printf(""); };
	}

	if (verifyStencilVRAM(mod, (u16*)softbuffer)) {
		printf("STENCIL$ DIFFERENCE");
//		while (1) { printf(""); };
	}

				}
			}
		}
	}
#endif

	//
	// ALWAYS WRITE A FRAME AT THE END : BOTH STENCIL AND VRAM.
	//
	/*
	printf("\n");
	for (int y=0; y < 2048*16; y+=2048) {
		for (int n=0; n < 16*2; n++) {
			printf("%02x ", buffer[n + y]);
		}
		printf("\n");
	}
	*/
	printf("Content ID %i / CacheLines %i / Cache Structure %i\n",contentNumber,cacheLineCount,swizzleMode);
	printf("Cycle Count : %i\n",clockCnt / 2);
	printf("Read Memory : %i\n",readMiss);
	printf("Read Hit : %i\n",readHit);
	printf("Read Miss : %i\n",readMiss);
	printf("Unique Read Count : %i\n",uniqueReadCount);
	printf("Read Count Texture : %i\n",readTexture);
	printf("Read Count BG or Clut : %i\n",readBGOrClut);
	printf("Write Count : %i\n",writeCount);

	fflush(stdout);

	if (argcount > 3) {
		char bufferName[256];
		char bufferNameMsk[256];
		sprintf(bufferName,"output_%i_%i_%i.png",swizzleMode,cacheLineCount,contentNumber);
		sprintf(bufferNameMsk,"output_msk%i_%i_%i.png",swizzleMode,cacheLineCount,contentNumber);
 		int errorCount = dumpFrame(mod, bufferName, bufferNameMsk,buffer,clockCnt>>1, true);
	} else {
 		int errorCount = dumpFrame(mod, "output.png", "output_msk.png",buffer,clockCnt>>1, true);
		if (errorCount) {
	//		printf("STENCIL PROBLEM"); while (1) {}
		}
	}

	if (compare) {
		compareBuffers(buffer, refBuffer);
	}

	 mfb_close(window);

	delete cache;

	delete [] buffer;
	delete [] refBuffer;
	pScan->shutdown();
	tfp.close();
}

typedef unsigned char u8;
typedef unsigned int  u32;
typedef unsigned short u16;

static u32* GP0 = (u32*)0x1F801810;
#ifdef _WIN32
u16* vrambuffer;

void dumpVRAM(const char* name, u16* buffer) {
	unsigned char* data = new unsigned char[1024 * 4 * 512];

	for (int y = 0; y < 512; y++) {
		for (int x = 0; x < 1024; x++) {
			int adr = (x+ (y*1024));
			int c16 = buffer[adr];
			int r = (c16 & 0x1F);
			int g = ((c16 >> 5) & 0x1F);
			int b = ((c16 >> 10) & 0x1F); // 
			r = (r >> 2) | (r << 3);
			g = (g >> 2) | (g << 3);
			b = (b >> 2) | (b << 3);
			int base = (x + y * 1024) * 3;
			data[base] = r;
			data[base + 1] = g;
			data[base + 2] = b;
		}
	}

	int err = stbi_write_png(name, 1024, 512, 3, data, 1024 * 3);
	delete[] data;
}

#endif

/* Create a group of unique pixels */
void fillTexture(u16* buff64k) {
	for (int n = 0; n < 65536; n++) {
		buff64k[n] = n;
	}
}

void uploadToGPU(u16* buff512_128, u16 offX) {
#ifdef _WIN32
	for (int y = 0; y < 512; y++) {
		for (int x = 0; x < 128; x++) {
			vrambuffer[x + offX + (y * 1024)] = buff512_128[x + (y * 128)];
		}
	}
#else
	*GP0 = 0xA0000000;
	*GP0 = 0x00000000 | offX;
	*GP0 = 0x02000080; // 128x512

	u32* p32 = (u32*)buff512_128;
	for (int n = 0; n < 32768; n++) { // 32768 x 2 pixels
		*GP0 = *p32++;
	}
#endif
}

// Copy VRAM from-to
void vramCmd(u16 sx, u16 sy, u16 dx, u16 dy, u16 w, u16 h) {
#ifdef _WIN32
	printf("%i,%i->%i,%i (%i,%i) (V[%i,%i]\n", sx, sy, dx, dy, w, h, (int)dx - (int)sx, (int)dy - (int)sy);
	bool forceY = false;
	int srcY	= ((sy > dy) | forceY) ? sy : (sy + h - 1);
	int dstY    = ((sy > dy) | forceY) ? dy : (dy + h - 1);
	int dirY	= ((sy > dy) | forceY) ? +1 : -1;

	while (h != 0) {
		int tw = w;

		int srcX = (sx > dx) ? sx : (sx + w - 1);
		int dstX = (sx > dx) ? dx : (dx + w - 1);
		int dirX = (sx > dx) ? +1 : -1;

		while (tw != 0) {
// DEBUG : Show parts read and write during VRAM copy.
//			vrambuffer[(srcY * 1024) + srcX] = 0xFFFF;
//			vrambuffer[(dstY * 1024) + dstX] = 0xAAAA;
			vrambuffer[(dstY * 1024) + dstX] = vrambuffer[(srcY * 1024) + srcX];

			tw--;
			srcX += dirX;
			dstX += dirX;
		}
		h--;
		srcY += dirY;
		dstY += dirY;
	}
#else
	*GP0 = 0x80000000;
	*GP0 = ((sy << 16) | sx);
	*GP0 = ((dy << 16) | dx);
	*GP0 = ((h << 16) | w);
#endif
}

#include "gpu_ref.h"

struct MyCtx {
	struct mfb_window*	window;
	u8*					bufferRGBA;

};

void rendercallback(GPURdrCtx& ctx, void* userContext,u8 commandID, u32 commandNumber) {
	// Refresh display.
	MyCtx* pCtx = (MyCtx*)userContext;
	Convert16To32((u8*)ctx.swBuffer,pCtx->bufferRGBA);
	int state = mfb_update(pCtx->window,pCtx->bufferRGBA);
	// printf("%02x (%i)\n",commandID,commandNumber);
}

void RenderCommandSoftware(u8* bufferRGBA, u8* srcBuffer, u64 maxTime, GPUCommandGen& commandGenerator,struct mfb_window *window) {
	u8* swBuffer = new u8[1024*1024];
	memcpy(swBuffer, srcBuffer, 1024*1024);

	u32 commandCount;
	u32* p = commandGenerator.getRawCommands(commandCount);
	u64* pStamp = commandGenerator.getRawTiming(commandCount);

	u8* pGP1 = commandGenerator.getGP1Args();
	// PSX Context.
	GPURdrCtx psxGPU;
	psxGPU.swBuffer		= (u16*)swBuffer;

	// Call back context
	MyCtx cbCtx;
	cbCtx.window		= window;
	cbCtx.bufferRGBA	= bufferRGBA;

	// Run the rendering of the commands...
	psxGPU.commandDecoder(p,pStamp,pGP1,commandCount,rendercallback,&cbCtx, maxTime);

	dumpFrame(NULL, "output_sw.png", "output_msk_sw.png",swBuffer,0, true);

	memcpy(srcBuffer, swBuffer, 1024*1024);
	delete[] swBuffer;
}

#include <random>
#include <memory>
#include <functional>
 
void RandomBenchTriangle(u8* bufferRGBA, struct mfb_window *window) {
	u8* swBuffer = new u8[1024*1024];
	memset(swBuffer, 0, 1024*1024);

	// PSX Context.
	GPURdrCtx psxGPU;
	psxGPU.swBuffer		= (u16*)swBuffer;

	// Call back context
	MyCtx cbCtx;
	cbCtx.window		= window;
	cbCtx.bufferRGBA	= bufferRGBA;
	psxGPU.callback	   = rendercallback;
	psxGPU.userContext = &cbCtx;

    using namespace std::placeholders;  // for _1, _2, _3...
 
    // common use case: binding a RNG with a distribution
    std::mt19937 ex(0xDEADBEEF);
    std::mt19937 ey(0x12384586);
    std::mt19937 es(0xCAFEBABE);
    std::uniform_int_distribution<> dx(0, 1023);
    std::uniform_int_distribution<> dy(0, 511);
    std::uniform_int_distribution<> bb(1, 15);
    auto rand_coordx = std::bind(dx, ex); // a copy of e is stored in rnd
    auto rand_coordy = std::bind(dy, ey); // a copy of e is stored in rnd
    auto rand_clip   = std::bind(bb, es); // a copy of e is stored in rnd

	psxGPU.offsetX_s11	= 0;		
	psxGPU.offsetY_s11	= 0;
//	psxGPU.interlaced = true;

	while (1) {
		Vertex p[3];

		psxGPU.drAreaX0_10	= rand_coordx() / 2;		
		psxGPU.drAreaY0_9	= rand_coordy() / 2;
		psxGPU.drAreaX1_10	= psxGPU.drAreaX0_10 + rand_clip()*32;
		psxGPU.drAreaY1_9	= psxGPU.drAreaY1_9  + rand_clip()*16;

		p[0].x = rand_coordx();
		p[0].y = rand_coordy();

		p[1].x = rand_coordx();
		p[1].y = rand_coordy();

		p[2].x = rand_coordx();
		p[2].y = rand_coordy();

		printf("TRI : [%i,%i],[%i,%i],[%i,%i] in [%i,%i,%i,%i]\n",
			p[0].x,
			p[0].y,
			p[1].x,
			p[1].y,
			p[2].x,
			p[2].y,

			psxGPU.drAreaX0_10,
			psxGPU.drAreaY0_9,
			psxGPU.drAreaX1_10,	
			psxGPU.drAreaY1_9
		);

		psxGPU.RenderTriangle(p,0,1,2);
	}

	delete[] swBuffer;
}

 void RenderTriangleTest(GPURdrCtx& psxGPU, int* clipping, int x0, int y0, int x1, int y1, int x2, int y2) {
	psxGPU.drAreaX0_10	= clipping[0];
	psxGPU.drAreaY0_9	= clipping[1];
	psxGPU.drAreaX1_10	= clipping[2];
	psxGPU.drAreaY1_9	= clipping[3];

	Vertex p[3];
	p[0].x = x0;
	p[0].y = y0;

	p[1].x = x1;
	p[1].y = y1;

	p[2].x = x2;
	p[2].y = y2;

	psxGPU.RenderTriangle(p,0,1,2);
}

void TestSuite(u8* bufferRGBA, struct mfb_window *window) {
	// ------------------------------------------------------------

	u8* swBuffer = new u8[1024*1024];
	memset(swBuffer, 0, 1024*1024);

	// PSX Context.
	GPURdrCtx psxGPU;
	psxGPU.swBuffer		= (u16*)swBuffer;

	// Call back context
	MyCtx cbCtx;
	cbCtx.window		= window;
	cbCtx.bufferRGBA	= bufferRGBA;
	psxGPU.callback	   = rendercallback;
	psxGPU.userContext = &cbCtx;

	// ------------------------------------------------------------

	psxGPU.interlaced = false;

	int clipping[4];

	clipping[0] =   0; clipping[1] =   0; 
	clipping[2] = 319; clipping[1] = 239;
 
	RenderTriangleTest(psxGPU,clipping,
		5,0,
		0,10,
		10,10
	);

	RenderTriangleTest(psxGPU,clipping,
		297,2,
		361,2,
		297,130
	);

	RenderTriangleTest(psxGPU,clipping,
		361,130,
		361,2,
		297,130
	);

	RenderTriangleTest(psxGPU,clipping,
		-23,2,
		41,2,
		-23,130
	);

	RenderTriangleTest(psxGPU,clipping,
		-2,83,
		-12,96,
		2,84
	);

	RenderTriangleTest(psxGPU,clipping,
		-2,100,
		-9,100,
		1,95
	);

	RenderTriangleTest(psxGPU,clipping,
		 8,84,
		 1,95,
		14,83
	);

	RenderTriangleTest(psxGPU,clipping,
		 -18,235,
		 88,227,
		 12,209
	);

	RenderTriangleTest(psxGPU,clipping,
		 308,137,
		 329,137,
		 319,139
	);

	RenderTriangleTest(psxGPU,clipping,
		 274,93,
		 737,93,
		 417,1113
	);

	// Non Optimal
	RenderTriangleTest(psxGPU,clipping,
		 301,57,
		 291,89,
		 336,45
	);

	// Non Optimal
	RenderTriangleTest(psxGPU,clipping,
		 312,25,
		 301,57,
		 350,4
	);

	// Pair Fail
	clipping[0] = 128; clipping[1] = 128; clipping[2] = 149; clipping[3] = 215;
	RenderTriangleTest(psxGPU,clipping,
		 185,161,
		 142,173,
		 142,171
	);

	psxGPU.interlaced = true;

	clipping[0] = 502; clipping[1] = 190; clipping[2] = 886; clipping[3] = 6191;
	RenderTriangleTest(psxGPU,clipping,
		 633,292,
		1021,128,
		 842,229
	);

	clipping[0] = 0; clipping[1] = 20; clipping[2] = 367; clipping[3] = 467;
	RenderTriangleTest(psxGPU,clipping,
		 336,110,
		 336,180,
		 271,111
	);

	RenderTriangleTest(psxGPU,clipping,
		404,426,
		355,378,
		230,423
	);

	RenderTriangleTest(psxGPU,clipping,
		224,389,
		223,386,
		232,395
	);

	RenderTriangleTest(psxGPU,clipping,
		223,405,
		211,398,
		212,401
	);


	psxGPU.interlaced = false;

	// ------------------------------------------------------------
	delete[] swBuffer;
}

void ThinTriangles(u8* bufferRGBA, struct mfb_window *window) {
	u8* swBuffer = new u8[1024*1024];
	memset(swBuffer, 0, 1024*1024);

	// PSX Context.
	GPURdrCtx psxGPU;
	psxGPU.swBuffer		= (u16*)swBuffer;

	// Call back context
	MyCtx cbCtx;
	cbCtx.window		= window;
	cbCtx.bufferRGBA	= bufferRGBA;
	psxGPU.callback	   = rendercallback;
	psxGPU.userContext = &cbCtx;

    using namespace std::placeholders;  // for _1, _2, _3...
 
    // common use case: binding a RNG with a distribution
	float t      = 0.0f;

	float angle  = 0.0f;

	float radius = 0.0f;

	psxGPU.offsetX_s11	= 0;		
	psxGPU.offsetY_s11	= 0;

	float cx = 128.0f;
	float cy = 128.0f;

	while (1) {
		Vertex p[3];

		// Opposite
		float angleOpp = angle - 3.1415925f;
		float oppL     = angleOpp - (3.14f * (t / 1200) / 180);
		float oppR     = angleOpp + (3.14f * (t / 1000) / 180);

		radius = sin(t / 1000.0f) * 50;

		p[0].x = cx + (cos(angle) * radius);
		p[0].y = cy + (sin(angle) * radius);

		p[1].x = cx + (cos(oppL) * radius);
		p[1].y = cy + (sin(oppL) * radius);

		p[2].x = cx + (cos(oppR) * radius);
		p[2].y = cy + (sin(oppR) * radius);

		cx += 1.0f;
		if (cx > 179.0f) {
			cx = 77.0f;
			cy += 1.0f;
			if (cy > 179.0f) {
				cy = 77.0f;
			}
		}
	
		static int size = 0;
		size++; // 16384 combination of clip
		psxGPU.drAreaX0_10	= 128;
		psxGPU.drAreaY0_9	= 128;
		psxGPU.drAreaX1_10	= 128 + (size & 0x7F);
		psxGPU.drAreaY1_9	= 128 + ((size>>7) & 0x7F);


		printf("TRI : [%i,%i],[%i,%i],[%i,%i] in [%i,%i,%i,%i]\n",
			p[0].x,
			p[0].y,
			p[1].x,
			p[1].y,
			p[2].x,
			p[2].y,

			psxGPU.drAreaX0_10,
			psxGPU.drAreaY0_9,
			psxGPU.drAreaX1_10,	
			psxGPU.drAreaY1_9
		);

		psxGPU.RenderTriangle(p,0,1,2);


		// Head
		angle += 0.0001f;

		// General T
		t += 1.0f;
		if (t > 10000.0f) {
			t = 1.0f;
		}
	}

	delete[] swBuffer;
}
