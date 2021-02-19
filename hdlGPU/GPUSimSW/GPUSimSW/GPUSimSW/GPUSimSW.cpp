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

void RenderCommandSoftware(u8* bufferRGBA, u8* srcBuffer, GPUCommandGen& commandGenerator,struct mfb_window *window);

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

u8* buffer32Bit;

extern int testsuite();

GPUCommandGen*	gCommandReg;
GPUCommandGen* getCommandGen() {
	return gCommandReg;
}

u8* heatMapRGB;
u8* heatMapEntries[64*512];
int  heatMapEntriesCount = 0;

void SetWriteHeat(int adr) {
	u8* basePix = &heatMapRGB[(adr>>2)*64];
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

void SetReadHeat(int adr) {
	u8* basePix = &heatMapRGB[(adr>>2)*64];
	for (int n=0; n < heatMapEntriesCount; n++) {
		if (heatMapEntries[n] == basePix) {
			// Update R
			for (int n=0; n < 16; n++) {
				basePix[(n*4) + 1] = 255;
			}
			break;
		}
	}
	
	if (heatMapEntriesCount < 64*512) {
		heatMapEntries[heatMapEntriesCount++] = basePix;
		for (int n=0; n < 16; n++) {
			basePix[n*4 + 1] = 255;
		}
	}
}

void UpdateHeatMap() {
	for (int n=0; n < heatMapEntriesCount; n++) {
		u8* basePix = heatMapEntries[n];
		
		
		if ((basePix[0] != 0) || (basePix[1] != 0)) {
			bool exitR = basePix[0] <= 32;
			bool exitG = basePix[1] <= 32;

			if (!exitR) {
				u8 v = basePix[0] - 1;
				for (int n=0; n < 16; n++) {
					basePix[(n*4)] = v;
				}
				if (v==32) {
					exitR = true;
				}
			}

			if (!exitG) {
				u8 v = basePix[1] - 1;
				for (int n=0; n < 16; n++) {
					basePix[(n*4)+1] = v;
				}
				if (v==32) {
					exitG = true;
				}
			}

			if (exitG & exitR) {
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

#include <Windows.h>

int main(int argcount, char** args)
{
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
	int sL    = 0;

	enum DEMO {
		NO_TEXTURE,
		TEXTURE_TRUECOLOR_BLENDING,
		TEXTURE_PALETTE_BLENDING,
		COPY_CMD,
		COPY_FROMRAM,
		TEST_EMU_DATA,
		USE_AVOCADO_DATA,
		PALETTE_FAIL_LATEST,
		INTERLACE_TEST,
		POLY_FAIL,
		COPY_TORAM,
		TESTSUITE,
		CAR_SHADOW,
		TEST_A,
	};

	DEMO manual		= TEST_A;
//	DEMO manual		= USE_AVOCADO_DATA;
//	DEMO manual		= TESTSUITE;

	FILE* binSrc = NULL;
	bool useHeatMap  = true;

	// SW/HW
	bool useSWRender = true;

	// HW
	bool useScanRT   = false;
	int  lengthCycle = 50000;

	// 9,17,12 = Very good test for stencil.
	int source = 25; // ,5 : SW Namco Logo wrong, Score

	switch (source) {
	case 0:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Station","rb");				break; // GOOD COMPLETE
	case 1:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Station2","rb");				break; // GOOD COMPLETE
	case 2:  binSrc = fopen("E:\\JPSX\\Avocado\\FF7Fight","rb");				break; // GOOD COMPLETE
	case 3:  binSrc = fopen("E:\\JPSX\\Avocado\\RidgeRacerMenu","rb");			break; // GOOD COMPLETE
	case 4:  binSrc = fopen("E:\\JPSX\\Avocado\\RidgeRacerGame","rb");			break; // GOOD COMPLETE
	case 5:  binSrc = fopen("E:\\JPSX\\Avocado\\RidgeScore","rb");				break; // GOOD COMPLETE
	case 6:  binSrc = fopen("E:\\JPSX\\Avocado\\StarOceanMenu","rb");			break; // GOOD COMPLETE But gbreak; litch. Happen also in SW Raster => Bad data most likely.
	case 7:  binSrc = fopen("E:\\JPSX\\Avocado\\TexTrueColorStarOcean","rb");	break; // GOOD COMPLEbreak; TE.
	case 8:  binSrc = fopen("E:\\JPSX\\Avocado\\Rectangles","rb");				break; // GOOD COMPLETE
	case 9:  binSrc = fopen("E:\\JPSX\\Avocado\\MegamanInGame","rb");			break; // GOOD COMPLETE
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
	case 22:  binSrc = fopen("F:\\bios.gpudump","rb");							break; // GOOD COMPLETE
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



	bool useScan = (fileName ? (!skipScan) : useScanRT) & !useSWRender;

	// ------------------------------------------------------------------
	// Export Buffer as PNG ?
	// ------------------------------------------------------------------
	// Put background for debug.
	const bool	useCheckedBoard				= false;

	// ------------------------------------------------------------------
	// Fake VRAM PSX
	// ------------------------------------------------------------------
	unsigned char* buffer     = new unsigned char[1024*1024];
	unsigned char* refBuffer  = new unsigned char[1024*1024];
	unsigned char* softbuffer = new unsigned char[1024*1024];
	unsigned char* refStencil = new unsigned char[16384 * 32]; 

	int readCount = 0;

	memset(buffer,0,1024*1024);
//	memset(&buffer[2048],0x00,2048*511);
//	rasterTest((u16*)buffer);

	if (useCheckedBoard) {
		drawCheckedBoard(buffer);
	}

	// ------------------------------------------------------------------
	// [Instance of verilated GPU & custom VCD Generator]
	// ------------------------------------------------------------------
	VGPU_DDR* mod		= new VGPU_DDR();
	VCScanner*	pScan   = new VCScanner();
				pScan->init(4000);

	srand(17);
	for (int y=0;y<512;y++) {
		for (int x=0;x<1024;x++) {
			u16* p = (u16*)&buffer[x*2 + y*2048];
			int v = /*(((x & 16)!=0) ^((y&1)!=0)) & (x & 1);*/(rand() & 1);
			*p = v << 15;

			setStencil(mod,x,y,v ? true : false);
		}
	}

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
	mod->i_busyMem				        = 0;
	mod->i_dataValidMem					= 0;
	mod->i_dataMem						= 0;

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
	GPUCommandGen	commandGenerator;

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
		commandGenerator.writeRaw(0xe1000400);
//		commandGenerator.writeRaw(0xe3000000);
//		commandGenerator.writeRaw(0xe403c140);
		commandGenerator.writeRaw(0xe6000002);
		commandGenerator.writeRaw(0x2000b714);
		commandGenerator.writeRaw(0x007700ca);
		commandGenerator.writeRaw(0x00e900d1);
		commandGenerator.writeRaw(0x00370128);

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

	if (useSWRender) {
		RenderCommandSoftware(bufferRGBA, buffer, commandGenerator,window);
		return 0;
	}

	Sleep(5000);

	bool log
#ifdef RELEASE
		= false;
#else
		= true;
#endif

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
			if (updateBuff) {
//			if (((clockCnt & 0x3F)==0)) {
				Convert16To32(buffer, bufferRGBA);
//				Convert16To32((u8*)swBuffer, bufferRGBA);

				int state = mfb_update(window,bufferRGBA);

				updateBuff = false;

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

		mod->i_busyMem = rand() & 1;

		mod->clk    = 1;
		mod->eval();

		if (useHeatMap) {
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

		if (mod->o_writeEnableMem == 1 /* && (mod->i_busyMem == 0)*/) {
			if (beginTransaction) {
				burstSize  = mod->o_burstLength;
				burstAdr   = mod->o_targetAddr;
				beginTransaction = (burstSize <= 1);
				if (useHeatMap) { SetWriteHeat(burstAdr); }
			} else {
				burstAdr  += 1;
				burstSize--;
				if (burstSize == 1) {
					beginTransaction = true;
					burstSize = 0;
				}
			}

			int baseAdr = burstAdr << 3;
			if (baseAdr != (mod->o_targetAddr<<3)) {
				printf("WRITE ERROR !\n");
				error = 1;
				// pScan->shutdown();
			}


			int selPix = mod->o_byteEnableMem;

			if (selPix &  1) { buffer[baseAdr  ] =  mod->o_dataMem      & 0xFF; }
			if (selPix &  2) { buffer[baseAdr+1] = (mod->o_dataMem>> 8) & 0xFF; }
			if (selPix &  4) { buffer[baseAdr+2] = (mod->o_dataMem>>16) & 0xFF; }
			if (selPix &  8) { buffer[baseAdr+3] = (mod->o_dataMem>>24) & 0xFF; }

			if (selPix & 16) { buffer[baseAdr+4] = (mod->o_dataMem>>32) & 0xFF; }
			if (selPix & 32) { buffer[baseAdr+5] = (mod->o_dataMem>>40) & 0xFF; }
			if (selPix & 64) { buffer[baseAdr+6] = (mod->o_dataMem>>48) & 0xFF; }
			if (selPix &128) { buffer[baseAdr+7] = (mod->o_dataMem>>56) & 0xFF; }
		} else {
			error = 0;
		}

		static bool transactionRead = false;
		if (transactionRead) {

			//
			// WARNING REUSE ADR SET AT CYCLE BEFORE
			//
			int	baseAdr = burstAdr<<3;

			mod->i_dataValidMem = 1;

			int selPix = mod->o_byteEnableMem;

			u64 result = 0;

			if (selPix &  1) { result |= ((u64)buffer[baseAdr+0])<<0;  }
			if (selPix &  2) { result |= ((u64)buffer[baseAdr+1])<<8;  }
			if (selPix &  4) { result |= ((u64)buffer[baseAdr+2])<<16; }
			if (selPix &  8) { result |= ((u64)buffer[baseAdr+3])<<24; }

			if (selPix & 16) { result |= ((u64)buffer[baseAdr+4])<<32; }
			if (selPix & 32) { result |= ((u64)buffer[baseAdr+5])<<40; }
			if (selPix & 64) { result |= ((u64)buffer[baseAdr+6])<<48; }
			if (selPix &128) { result |= ((u64)buffer[baseAdr+7])<<56; }

			mod->i_dataMem      = result;

	//		mod->eval();
			//
			// INCREMENT FOR NEXT READ.
			//
			burstAdr  += 1;
			burstSizeRead--;
			if (burstSizeRead == 0) {
				transactionRead = false;
			}
		} else {
			mod->i_dataValidMem = 0;
//			mod->eval();
		}

		if (mod->o_readEnableMem == 1/* && (mod->i_busyMem == 0)*/) {
			if (!transactionRead) {
				burstSizeRead = mod->o_burstLength;
				burstAdr   = mod->o_targetAddr;
				readCount++;
				if (useHeatMap) { SetReadHeat(burstAdr); }
				transactionRead = true;
			}
		}

		// -----------------------------------------
		//   [REGISTER SETUP OF GPU FROM BUS]
		// -----------------------------------------
		mod->i_write		= 0;
		mod->i_gpuSel		= 0;
		mod->i_gpuAdrA2		= 0;
		mod->i_cpuDataIn	= 0;

		// Cheat... should read system register like any normal CPU...
		static int currRec = 0;

		if (mod->o_dbg_canWrite) {

			bool isGPUWaiting = true; // (mod->GPU_DDR__DOT__gpu_inst__DOT__gpu_parser_instance__DOT__currState == 0 /*DEFAULT_STATE wait*/);
			static int cycleCounter = 0;

			bool uploadData = false;
			if (commandGenerator.stillHasCommand()) {
				if (isGPUWaiting) {
					uploadData = (cycleCounter % 2000)==0;
				} else {
					if (!commandGenerator.isCommandStart() && ((cycleCounter % 2000)==0)) {
						uploadData = true;					
					}
				}
			}

			if (uploadData) {
				mod->i_gpuSel		= 1;
				if (commandGenerator.isGP1()) {
					mod->i_gpuAdrA2		= 1;
				} else {
					mod->i_gpuAdrA2		= 0;
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

	 mfb_close(window);

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

 	int errorCount = dumpFrame(mod, "output.png", "output_msk.png",buffer,clockCnt>>1, true);
	if (errorCount) {
		printf("STENCIL PROBLEM"); while (1) {}
	}
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

void RenderCommandSoftware(u8* bufferRGBA, u8* srcBuffer, GPUCommandGen& commandGenerator,struct mfb_window *window) {
	u8* swBuffer = new u8[1024*1024];
	memcpy(swBuffer, srcBuffer, 1024*1024);

	u32 commandCount;
	u32* p = commandGenerator.getRawCommands(commandCount);
	u8* pGP1 = commandGenerator.getGP1Args();
	// PSX Context.
	GPURdrCtx psxGPU;
	psxGPU.swBuffer		= (u16*)swBuffer;

	// Call back context
	MyCtx cbCtx;
	cbCtx.window		= window;
	cbCtx.bufferRGBA	= bufferRGBA;

	// Run the rendering of the commands...
	psxGPU.commandDecoder(p,pGP1,commandCount,rendercallback,&cbCtx);

	dumpFrame(NULL, "output_sw.png", "output_msk_sw.png",swBuffer,0, true);

	delete[] swBuffer;
}
