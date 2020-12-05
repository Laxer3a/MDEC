//----------------------------------------------------------------------------
// Test for full range of values. for -128..+127 for Cr/Cb/Y
// - Verify Signed/Unsigned Conversion
// - Verify Y Only, YUV output
//----------------------------------------------------------------------------


#define VM_TRACE	(1)

#include <verilated.h>

#include <stdio.h>
//#include "../rtl/obj_dir/VfusedStreamCompute.h"
class VMDEC;
#include "../rtl/obj_dir/VMDEC.h"

#define VCSCANNER_IMPL
#include "VCScanner.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define ADD_WIRE(f,p,NAME)			f->addMember( PatchName(#NAME), WIRE, BIN,1,& p ->## NAME );
#define ADD_WIREV(f,p,NAME,size,s2)	f->addMember( PatchName(#NAME), WIRE, BIN,(size+1),& p ->## NAME );
#define ADD_REG(f,p,NAME)			f->addMember( PatchName(#NAME), REG, BIN,1,& p ->## NAME );
#define ADD_REGV(f,p,NAME,size,s2)	f->addMember( PatchName(#NAME), REG, BIN,(size+1),& p ->## NAME );

const char* PatchName(const char* originalName) {
	char* res;
	char* dst = res = strdup(originalName);
	while (*dst) {
		if (strncmp(originalName, "__DOT__",7) != 0) {
			*dst++ = *originalName++;
		} else {
			*dst++ = '.';
			originalName += 7;
		}
	}
	*dst++ = 0;

	return res;
}

typedef unsigned int   u32;
typedef unsigned short u16;
typedef unsigned char   u8;

VCScanner*	myCapture = NULL;

int IFIX(int value, int prec) {
	return ((value << (32-prec)) >> (32-prec));
}

#include <iostream>
#include <fstream>
#include <string>

using namespace std;

unsigned char* readFile(const string& sFileName, int * iSize) {

	// open the file
	cout << "  Opening input file " << sFileName << "\n";
	ifstream oInFile (sFileName.c_str(), ios::in|ios::binary|ios::ate);
	if (!oInFile.is_open())
	{
		cout << "  Unable to open input file " << sFileName << "\n";
		exit(1);
	}

	// find the file size
	ifstream::pos_type size = oInFile.tellg();

	cout << "  File is " << size << " bytes long\n";

	// allocate a buffer that size
	char * acInBuffer = new char [size];
	// move to the start of the file
	oInFile.seekg (0, ios::beg);
	if (!oInFile.good())
	{
		cout << "  Error reading input file\n";
		exit(1);
	}
	// read the entire file
	oInFile.read (acInBuffer, size);
	if (!oInFile.good())
	{
		cout << "  Error reading input file\n";
		exit(1);
	}
	// close the file
	oInFile.close();
	if (!oInFile.good())
	{
		cout << "  Error reading input file\n";
		exit(1);
	}

	cout << "  Finished reading input file\n";

	oInFile.close();

	*iSize = (int)size;

	return (unsigned char*)acInBuffer;
}




#define ASSERT_CHK(cond)		if (!cond) { error(); }

void error() {
	while (1) {
	}
}

class TestMDEC {
public:
	int  init();
	void run(int maxClock_);
	void release();
	void dumpPic(int n);

protected:
	void drawPixel(int x, int y, int r, int g, int b);
	void updateOutput();

	void reset(int clockCount);
	void clock();

	void writeReg0	(u32 value);
	void writeReg1	(u32 value);
	u32  readReg0	();
	u32  readReg1	();

	void uploadQuantTable();
	void uploadCOSTable();
	void uploadData();


	/*
	void transfer();

	void nop();
	void flush();
	void writeData(u16 data, bool yOnly);
	void writeQuant(const u8* data, int quantAdr4Bit, bool tblSelect);
	void uploadQuantTable();
	*/
private:
	VMDEC*			pMDEC;
	int				globalClock;
	int				maxTimeClock;
	unsigned char* buff;
	bool			flag_exit;
	bool			useMovieDump;
};

void TestMDEC::run(int maxClk) {
	maxTimeClock = maxClk;
	uploadQuantTable();
	uploadCOSTable();
	uploadData();
}

void TestMDEC::clock() {
	static int captTime = 0;
	if (globalClock < maxTimeClock) {

		pMDEC->eval();					// Clock does not change, but propagate correctly input to output with pure combinatorial.
		if (myCapture) myCapture->eval(captTime++);	// Capture properly the signals now.

										// Transition [1->0]
		pMDEC->i_clk = 0;

		// Eval() just to perform a transition.
		pMDEC->eval();

		//
#if 0
	// To run if we change input on negative edge...
		pFused->eval();
#endif
		// Just need it for clock change()
		// TODO : Could optimize here.
		if (myCapture) myCapture->eval(captTime++);

		globalClock++;

		pMDEC->i_clk = 1;
		pMDEC->eval();
	} else {
		flag_exit = true;
	}
}

void TestMDEC::drawPixel(int x, int y, int r, int g, int b) {
	int adr = (x +( y * 512)) * 3;
	buff[adr + 0] = r;
	buff[adr + 1] = g;
	buff[adr + 2] = b;
}

void TestMDEC::updateOutput() {
	static int PCounter = 0;

	for (int n=0; n < 31; n++) {
		u32 r = readReg1();
		// Not empty...
		if ((r & (1<<31)) == 0) {
			// Read...
			u32 r = readReg0();

			int pBlock = PCounter / 64;
			int pBlock4 = pBlock / 4;
			int YBlock = pBlock4 % ((240-16) / 16);
			int XBlock = pBlock4 / ((240-16) / 16);
			if (PCounter % 64 == 0) {
				printf("Block %i [%i,%i]\n", pBlock, XBlock, YBlock);
			}



			PCounter++;
		} else {
			printf("---FIFO EMPTY ---\n");
		}
	}

	/*
	if (pMDEC->MDEC__DOT__wrtPix) {
		int adrYX = pMDEC->MDEC__DOT__pixIdx;
		// printf("Adr XY : %i,%i\n", (adrYX>>4) & 0xF, (adrYX & 0xF));
		int r = pMDEC->MDEC__DOT__r;
		int g = pMDEC->MDEC__DOT__g;
		int b = pMDEC->MDEC__DOT__b;


		int r5 = ((r >> 3) << 3) | (r >> 5);
		int g5 = ((g >> 3) << 3) | (g >> 5);
		int b5 = ((b >> 3) << 3) | (b >> 5);

		drawPixel((XBlock * 16) + (adrYX & 15), (YBlock * 16) + (adrYX >> 4), r5, g5, b5);

		if (PCounter % 16 == 0 && useMovieDump) {
			static int FrameID = 0;
			dumpPic(FrameID++);
		}

	}
	*/
}

void TestMDEC::reset(int clockCount) {
	globalClock = 0;
	pMDEC->i_nrst = 0;
	for (int n = 0; n < clockCount; n++) {
		clock();
	}

	pMDEC->i_nrst = 1;
	clock();
}

void TestMDEC::dumpPic(int n) {
	char buffName[1000];
	if (n != -1) {
		sprintf(buffName, "movie\\image%i.png", n);
	} else {
		sprintf(buffName, "image.png", n);
	}
	int err = stbi_write_png(buffName, 512, 240, 3, buff, 512 * 3);
}

void TestMDEC::release() {
	dumpPic(-1);
	delete[] buff;
	delete myCapture;
	delete pMDEC;
}

#define MODULE pMDEC
#define SCAN   myCapture

// ----------
// TRICK WITH MACRO TO REGISTER THE MEMBERS OF THE VERILATED INSTANCE INTO MY VCD SCANNER...
// ----------



int TestMDEC::init() {
	bool useCapture = true;

	buff = new unsigned char[512 * 240 * 3];
	useMovieDump = false;

	globalClock = 0;
	maxTimeClock = 0x7FFFFFFF;
	flag_exit = false;
	pMDEC = new VMDEC();

	myCapture = NULL;
	if (useCapture) {
		myCapture = new VCScanner();
		myCapture->init(2000);
	}

	//	VL_IN8(i_freezePipe,0,0);

	/*
	VL_OUT8(o_dataWrt,0,0);
	VL_OUT8(o_scale,5,0);
	VL_OUT8(o_isDC,0,0);
	VL_OUT8(o_index,5,0);
	VL_OUT8(o_zagIndex,5,0);
	VL_OUT8(o_fullBlockType,0,0);
	VL_OUT8(o_blockNum,2,0);
	VL_OUT8(o_blockComplete,0,0);
	*/
	//	VL_OUT16(o_dataOut,9,0);
	#undef VL_IN
	#undef VL_OUT
	#undef VL_SIG
	#undef VL_IN8
	#undef VL_SIG8
	#undef VL_IN16
	#undef VL_OUT16
	#undef VL_SIG16
	#undef VL_IN64
	#undef VL_OUT64
	#undef VL_SIG64
	#undef VL_SIGW

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

	if (myCapture) {
		// PORTS
		// The application code writes and reads these signals to
		// propagate new values into/out from the Verilated model.
		// Begin mtask footprint  all: 
		VL_IN8(i_clk,0,0);
		VL_IN8(DIP_ditherActive,0,0);
		VL_IN8(i_nrst,0,0);
		VL_OUT8(o_DMA0REQ,0,0);
		VL_IN8(i_DMA0ACK,0,0);
		VL_OUT8(o_DMA1REQ,0,0);
		VL_IN8(i_DMA1ACK,0,0);
		VL_IN8(i_CS,0,0);
		VL_IN8(i_regSelect,0,0);
		VL_IN8(i_write,0,0);
		VL_IN8(i_read,0,0);
		VL_IN(i_valueIn,31,0);
		VL_OUT(o_valueOut,31,0);
    
		// LOCAL SIGNALS
		// Internals; generally not touched by application code
		// Begin mtask footprint  all: 
		VL_SIG8(MDEC__DOT__DIP_ditherActive,0,0);
		VL_SIG8(MDEC__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__o_DMA0REQ,0,0);
		VL_SIG8(MDEC__DOT__i_DMA0ACK,0,0);
		VL_SIG8(MDEC__DOT__o_DMA1REQ,0,0);
		VL_SIG8(MDEC__DOT__i_DMA1ACK,0,0);
		VL_SIG8(MDEC__DOT__i_CS,0,0);
		VL_SIG8(MDEC__DOT__i_regSelect,0,0);
		VL_SIG8(MDEC__DOT__i_write,0,0);
		VL_SIG8(MDEC__DOT__i_read,0,0);
		VL_SIG8(MDEC__DOT__readReg0,0,0);
		VL_SIG8(MDEC__DOT__readReg1,0,0);
		VL_SIG8(MDEC__DOT__writeReg1,0,0);
		VL_SIG8(MDEC__DOT__writeReg0,0,0);
		VL_SIG8(MDEC__DOT__writeFIFO,0,0);
		VL_SIG8(MDEC__DOT__resetChip,0,0);
		VL_SIG8(MDEC__DOT__nResetChip,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_rdL,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_rdM,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_emptyL,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_emptyM,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_fullL,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_fullM,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_validL,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_validM,0,0);
		VL_SIG8(MDEC__DOT__unusedLevelM,5,0);
		VL_SIG8(MDEC__DOT__unusedLevelL,5,0);
		VL_SIG8(MDEC__DOT__fifoIN_hasData,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_empty,0,0);
		VL_SIG8(MDEC__DOT__fifoIN_full,0,0);
		VL_SIG8(MDEC__DOT__regPixelFormat,1,0);
		VL_SIG8(MDEC__DOT__regPixelSigned,0,0);
		VL_SIG8(MDEC__DOT__regPixelSetMask,0,0);
		VL_SIG8(MDEC__DOT__regLoadChromaQuant,0,0);
		VL_SIG8(MDEC__DOT__regAllowDMA0,0,0);
		VL_SIG8(MDEC__DOT__regAllowDMA1,0,0);
		VL_SIG8(MDEC__DOT__state,2,0);
		VL_SIG8(MDEC__DOT__nextState,2,0);
		VL_SIG8(MDEC__DOT__pRegSelect,0,0);
		VL_SIG8(MDEC__DOT__commandBusy,0,0);
		VL_SIG8(MDEC__DOT__isWaiting,0,0);
		VL_SIG8(MDEC__DOT__isLoadCos,0,0);
		VL_SIG8(MDEC__DOT__isLoadLum,0,0);
		VL_SIG8(MDEC__DOT__isLoadChr,0,0);
		VL_SIG8(MDEC__DOT__isStream,0,0);
		VL_SIG8(MDEC__DOT__commandType,2,0);
		VL_SIG8(MDEC__DOT__isCommandStream,0,0);
		VL_SIG8(MDEC__DOT__isCommandQuant,0,0);
		VL_SIG8(MDEC__DOT__isCommandCosTbl,0,0);
		VL_SIG8(MDEC__DOT__isColorQuant,0,0);
		VL_SIG8(MDEC__DOT__isNewCommand,0,0);
		VL_SIG8(MDEC__DOT__decrementCounter,1,0);
		VL_SIG8(MDEC__DOT__isLastHalfWord,0,0);
		VL_SIG8(MDEC__DOT__endMatrix,0,0);
		VL_SIG8(MDEC__DOT__allowLoad,0,0);
		VL_SIG8(MDEC__DOT__PEndMatrix,0,0);
		VL_SIG8(MDEC__DOT__isPass1,0,0);
		VL_SIG8(MDEC__DOT__dontPushStream,0,0);
		VL_SIG8(MDEC__DOT__canPushStream,0,0);
		VL_SIG8(MDEC__DOT__isCommandStreamValid,0,0);
		VL_SIG8(MDEC__DOT__validLoad,0,0);
		VL_SIG8(MDEC__DOT__i_cosWrite,0,0);
		VL_SIG8(MDEC__DOT__i_cosIndex,4,0);
		VL_SIG8(MDEC__DOT__i_quantWrt,0,0);
		VL_SIG8(MDEC__DOT__i_quantAdr,3,0);
		VL_SIG8(MDEC__DOT__i_quantTblSelect,0,0);
		VL_SIG8(MDEC__DOT__isLoadStL,0,0);
		VL_SIG8(MDEC__DOT__isLoadStH,0,0);
		VL_SIG8(MDEC__DOT__writeStream,0,0);
		VL_SIG8(MDEC__DOT__currentBlock,2,0);
		VL_SIG8(MDEC__DOT__wrtPix,0,0);
		VL_SIG8(MDEC__DOT__pixIdx,7,0);
		VL_SIG8(MDEC__DOT__r,7,0);
		VL_SIG8(MDEC__DOT__g,7,0);
		VL_SIG8(MDEC__DOT__b,7,0);
		VL_SIG8(MDEC__DOT__finalR,7,0);
		VL_SIG8(MDEC__DOT__finalG,7,0);
		VL_SIG8(MDEC__DOT__finalB,7,0);
		VL_SIG8(MDEC__DOT__allowWrite,0,0);
//		VL_SIG8(MDEC__DOT__ignoreStopFill,0,0);
		VL_SIG8(MDEC__DOT__outPixelFormat,1,0);
		VL_SIG8(MDEC__DOT__is15Bit,0,0);
		VL_SIG8(MDEC__DOT__writeRAM,0,0);
		VL_SIG8(MDEC__DOT__writeAdr,7,0);
		VL_SIG8(MDEC__DOT__nextWriteAdr,7,0);
		VL_SIG8(MDEC__DOT__resetWriteAdr,0,0);
		VL_SIG8(MDEC__DOT__readRAM,0,0);
		VL_SIG8(MDEC__DOT__fifoOUT_hasData,0,0);
		VL_SIG8(MDEC__DOT__readAdrSel,7,0);
		VL_SIG8(MDEC__DOT__isYOnly,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__i_rst,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__i_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__i_w_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__i_r_taken,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__o_level,5,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__o_w_full,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__o_r_valid,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__w_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__r_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__r_ena_g,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__r_addr,4,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__w_addr,4,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__level,5,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__full_i,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__empty_i,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__valid,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__pRaddr,4,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__fullNow,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOM__DOT__Pvalid,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__i_rst,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__i_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__i_w_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__i_r_taken,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__o_level,5,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__o_w_full,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__o_r_valid,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__w_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__r_ena,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__r_ena_g,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__r_addr,4,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__w_addr,4,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__level,5,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__full_i,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__empty_i,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__valid,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__pRaddr,4,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__fullNow,0,0);
		VL_SIG8(MDEC__DOT__InputFIFOL__DOT__Pvalid,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__clk,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_bitSetupDepth,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_bitSigned,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_dataWrite,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_endMatrix,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_allowLoad,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_cosWrite,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_cosIndex,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_quantWrt,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_quantAdr,3,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_quantTblSelect,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__i_stopFillY,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_idctBlockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_stillIDCT,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_pixelOut,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_pixelAddress,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_rComp,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_gComp,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__o_bComp,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__isPass1,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YOnly,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__busyIDCT,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__canLoadMatrix,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__freezeStreamAndCompute,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__bDataWrite,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__dataWrt_b,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__scale_b,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__isDC_b,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__index_b,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__linearIndex_b,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__fullBlockType_b,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__blockNum_b,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__blockComplete_b,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__write_c,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeIdx_c,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__blockNum_c,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeValueBlock,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__matrixComplete_c,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__write_c2,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeIdx_c2,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__blockNum_c2,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__matrixComplete_c2,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__isYOnlyBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__isYBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__pauseIDCTYBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__value_d,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeValue_d,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeIndex_d,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeY,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeCr,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__writeCb,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__readAdrCrCbTable,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__readCrValue,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__readCbValue,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__readAdrCrCbTable_reg,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__clk,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__bDataWrite,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__i_YOnly,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_dataWrt,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_scale,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_isDC,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_index,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_linearIndex,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_fullBlockType,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_blockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_blockComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__offset,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__isFullBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__rIsFullBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__isEOB,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__indexCounter,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__scalereg,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__state,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__nextState,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__nextIdx,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__isDC,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__currIdx,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__isBlockComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__isValidBlockComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__prevYOnly,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__rBlockCounter,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__nextBlockCounter,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__condFullBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__currIdx6Bit,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__z,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__wFullBlockType,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_dataWrt,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_scale,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_isDC,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_index,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_linearIndex,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_fullBlockType,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_blockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_matrixComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_freezePipe,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_quantWrt,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_quantAdr,3,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_quantTblSelect,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__o_write,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__o_writeIdx,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__o_blockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__o_matrixComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__valueQuant,6,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__quantAdr_reg,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__writeAdr,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pipeQuantReadIdx,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__selectTable,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__quantReadIdx,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pWrite,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pIndex,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pBlk,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pMatrixComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pFullBlkType,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__signedScale,6,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__quant,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__outWriteSignal,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__rndPartAndDiv8,3,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__overF,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__isOne,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__sgn,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__andV,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__orV,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myRTZEM1__DOT__isMinus1,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myRTZEM1__DOT__isOdd,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myRTZEM1__DOT__posV,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__clk,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_write,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_writeIdx,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_blockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_matrixComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__o_canLoadMatrix,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_cosWrite,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_cosIndex,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_pauseIDCT_YBlock,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__o_value,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__o_writeValue,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__o_blockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__o_busyIDCT,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__o_writeIndex,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__addrCos,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__cosAdr_reg,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pass0ReadAdr,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__isLoaded,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__isLoadedTmp,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coefTableAdr_reg,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__blockID,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__passTransition,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pass1ReadAdr,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__writeCoefTable2,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__writeCoefTable2Index,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coefTable2Adr_reg,4,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__tblSelect,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__idctBusy,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pass,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__YCnt,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__XCnt,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__KCnt,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__isLast,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__freezeIDCT,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pFreeze,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ppFreeze,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pLast,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ppLast,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pPass,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ppPass,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__rMatrixComplete,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__idctBlockNum,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pYCnt,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pKCnt,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ppYCnt,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pppYCnt,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pXCnt,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ppXCnt,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pppXCnt,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__writeOut,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pWriteOut,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__tooPos,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__tooNeg,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__notTooNeg,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__overflow8,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__rst8,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__clamped8Bit,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__outX,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__outY,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_wrt,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_YOnly,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_signed,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_writeIdx,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_valueY,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_YBlockNum,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__o_readAdr,5,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_valueCr,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__i_valueCb,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__o_wPix,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__o_pix,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__o_r,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__o_g,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__o_b,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__adrX,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__adrXSub,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__adrY,2,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__adrYSub,1,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__tileX,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__tileY,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__pix,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__p_YOnly,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__p_signed,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__p_valueY,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__p_Wrt,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__p_WrtIdx,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__i_YOnly,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__i_signed,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__i_valueY,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__i_valueCr,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__i_valueCb,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__o_r,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__o_g,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__o_b,7,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__isNZeroR,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__isNZeroG,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__isNZeroB,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__isOneR,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__isOneG,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__isOneB,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__orR,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__andR,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__orG,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__andG,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__orB,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__andB,0,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__lowR,6,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__lowG,6,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__lowB,6,0);
		VL_SIG8(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__sigUnsigned,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__rIn,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__gIn,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__bIn,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__ditherOn,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__xBuff,1,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__yBuff,1,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__r,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__g,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__b,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__offset,2,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__postOffset,2,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__rclamp,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__gclamp,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__bclamp,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_R__DOT__valueOut,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_R__DOT__isPos,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_R__DOT__andStage,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_R__DOT__overF,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_G__DOT__valueOut,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_G__DOT__isPos,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_G__DOT__andStage,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_G__DOT__overF,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_B__DOT__valueOut,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_B__DOT__isPos,0,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_B__DOT__andStage,7,0);
		VL_SIG8(MDEC__DOT__ditherInst__DOT__clampSPositive_B__DOT__overF,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__i_nrst,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__i_wrtPix,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__format,1,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__setBit15,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__i_r,7,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__i_g,7,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__i_b,7,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__o_dataValid,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__R,7,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__G,7,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__B,7,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__Cl,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__count,2,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__pWrite,0,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v0,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v1,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v2,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v3,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v4,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v5,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v6,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__v7,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__GreyM,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__GreyL,3,0);
		VL_SIG8(MDEC__DOT__RGB2Pack_inst__DOT__selectReg,0,0);
		VL_SIG8(MDEC__DOT__RAM768_inst__DOT__i_clk,0,0);
		VL_SIG8(MDEC__DOT__RAM768_inst__DOT__i_dataAdr,7,0);
		VL_SIG8(MDEC__DOT__RAM768_inst__DOT__i_dataWr,0,0);
		VL_SIG8(MDEC__DOT__RAM768_inst__DOT__i_dataAdrRd,7,0);
		VL_SIG16(MDEC__DOT__fifoIN_outputM,15,0);
		VL_SIG16(MDEC__DOT__fifoIN_outputL,15,0);
		VL_SIG16(MDEC__DOT__streamIn,15,0);
		VL_SIG16(MDEC__DOT__InputFIFOM__DOT__i_w_data,15,0);
		VL_SIG16(MDEC__DOT__InputFIFOM__DOT__o_r_data,15,0);
		VL_SIG16(MDEC__DOT__InputFIFOL__DOT__i_w_data,15,0);
		VL_SIG16(MDEC__DOT__InputFIFOL__DOT__o_r_data,15,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__i_dataIn,15,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__dataOut_b,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__coefValue_c,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__coefValue_c2,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__i_dataIn,15,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__o_dataOut,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__streamInput_inst__DOT__coef,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_dataIn,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_debug,15,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__o_coefValue,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pMultF,15,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pDebug,15,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__pOutCalc,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__roundedOddTowardZeroExceptMinus1,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__outSelCalc,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__valueOut,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__clippedOutCalc,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__valueOut,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__orStage,10,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__andStage,10,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myRTZEM1__DOT__valueIn,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myRTZEM1__DOT__valueOut,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_coefValue,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__cosA,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__cosB,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__readCoefTableValue,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__readCoefTable2Value,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__writeValueA,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__writeValueB,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ValueA,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ValueB,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__idctCounter,8,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coefV,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coef12A,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coef12B,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coef13A,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__coef13B,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__v0,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__v1,12,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__pv1,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__vBeforeSDiv2,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__div2step1,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__div2step2,8,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__rFact,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__gFactB,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__gFactR,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__bFact,9,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__sgnY,10,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__sumR,10,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__sumG,11,0);
		VL_SIG16(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__sumB,10,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__off9,9,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__rsum,9,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__gsum,9,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__bsum,9,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__clampSPositive_R__DOT__valueIn,9,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__clampSPositive_G__DOT__valueIn,9,0);
		VL_SIG16(MDEC__DOT__ditherInst__DOT__clampSPositive_B__DOT__valueIn,9,0);
		VL_SIG16(MDEC__DOT__RGB2Pack_inst__DOT__groupBits,11,0);
		VL_SIG16(MDEC__DOT__RGB2Pack_inst__DOT__v8,15,0);
		VL_SIG16(MDEC__DOT__RGB2Pack_inst__DOT__v9,15,0);
		VL_SIG(MDEC__DOT__i_valueIn,31,0);
		VL_SIG(MDEC__DOT__o_valueOut,31,0);
		VL_SIG(MDEC__DOT__remainingHalfWord,16,0);
		VL_SIG(MDEC__DOT__externalRemainingHalfWord,16,0);
		VL_SIG(MDEC__DOT__reg0Out,31,0);
		VL_SIG(MDEC__DOT__nextRemainingHalfWord,16,0);
		VL_SIG(MDEC__DOT__i_cosVal,25,0);
		VL_SIG(MDEC__DOT__i_quantVal,27,0);
		VL_SIG(MDEC__DOT__packedData,31,0);
		VL_SIG(MDEC__DOT__packOut,31,0);
		VL_SIG(MDEC__DOT__reg1Out,31,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__i_cosVal,25,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__i_quantValue,27,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__i_quantValue,27,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__fullValueQuant,27,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__multF,16,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__outCalc,23,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__valueIn,23,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__outCalcRoundDiv,23,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__shift3,20,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__ComputeCoef_inst__DOT__inst_roundDiv8AndClamp__DOT__myClampSRange__DOT__valueIn,20,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__i_cosVal,25,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__mul0,24,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__mul1,24,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ext_mul0,19,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__ext_mul1,19,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__acc0,19,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__acc1,19,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__RTmp,17,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__GTmpB,17,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__GTmpR,17,0);
		VL_SIG(MDEC__DOT__mdecInst__DOT__YUV2RGBInstance__DOT__YUV2RGBCompute_inst__DOT__BTmp,17,0);
		VL_SIG(MDEC__DOT__RGB2Pack_inst__DOT__o_dataPacked,31,0);
		VL_SIG(MDEC__DOT__RGB2Pack_inst__DOT__reg0,31,0);
		VL_SIG(MDEC__DOT__RGB2Pack_inst__DOT__reg1,31,0);
		VL_SIG(MDEC__DOT__RAM768_inst__DOT__i_dataIn,31,0);
		VL_SIG(MDEC__DOT__RAM768_inst__DOT__o_dataOut,31,0);
		VL_SIG64(MDEC__DOT__mdecInst__DOT__IDCTinstance__DOT__isLoadedBits,63,0);

	}

	// [AFTER SETUP OF CONNECTIONS]
	if (myCapture) myCapture->addPlugin(new ValueChangeDump_Plugin("testBench_streamInput2.vcd"));

	// Make sure we do not have write pin starting to do stupid things at startup...
	pMDEC->i_write	= 0;
	pMDEC->i_read	= 0;

	// Reset the circuit.
	reset(5);

	/*
	VstreamInput
	input			i_dataWrite,
	input [15:0]	i_dataIn,
	input 			i_YOnly,
	*/

	/*
	VcomputeCoef
	// Quant Table Loading
	input					i_quantWrt,
	input	[27:0]			i_quantValue,
	input	[3:0]			i_quantAdr,
	input					i_quantTblSelect,

	output					o_write,
	output	[5:0]			o_writeIdx,
	output	[2:0]			o_blockNum,
	output	signed [11:0]	o_coefValue,
	output          		o_matrixComplete
	*/
	// Result [-2..+3]
	//	printf("Error range [%i,%i]\n",minD,maxD);

	return 1;
}

void TestMDEC::writeReg0(u32 value) {
	// Read Status flag...
	pMDEC->i_CS = 1;
	pMDEC->i_regSelect  = 1;
	pMDEC->i_write      = 0;
	pMDEC->i_read		= 1;
	clock();
	clock(); // 1 Clock delay...
	while ((pMDEC->o_valueOut & (1<<30)) && (flag_exit==false)) {
		clock();
		updateOutput();
	}

	// Now FIFO not full...

	pMDEC->i_CS = 1;
	pMDEC->i_write		= 1;
	pMDEC->i_read		= 0;
	pMDEC->i_regSelect	= 0;
	pMDEC->i_valueIn	= value;
	pMDEC->eval();
//	printf("W0: %08x\n", value);
	clock();

	pMDEC->i_write		= 0;
	pMDEC->i_read		= 0;
	pMDEC->i_CS = 0;
}

void TestMDEC::writeReg1(u32 value) {
	pMDEC->i_write		= 1;
	pMDEC->i_read		= 0;

	pMDEC->i_regSelect	= 1;
	pMDEC->i_CS = 1;
	pMDEC->i_valueIn	= value;
	clock();
	pMDEC->i_write		= 0;
	pMDEC->i_CS = 0;
}

u32 TestMDEC::readReg0() {
	pMDEC->i_write= 0;
	pMDEC->i_read = 1;
	pMDEC->i_regSelect = 0;
	pMDEC->i_CS = 1;
	pMDEC->DIP_ditherActive = 1;
	clock();
	printf("Read : %x\n", pMDEC->o_valueOut);
	clock();
	printf("Read : %x\n", pMDEC->o_valueOut);
	pMDEC->DIP_ditherActive = 0;
	return pMDEC->o_valueOut;
}

u32 TestMDEC::readReg1() {
	pMDEC->i_write= 0;
	pMDEC->i_read = 1;
	pMDEC->i_CS = 1;
	pMDEC->i_regSelect = 1;
	clock();
	printf("Read : %x\n", pMDEC->o_valueOut);
	clock();
	printf("Read : %x\n", pMDEC->o_valueOut);
	return pMDEC->o_valueOut;
}

void TestMDEC::uploadQuantTable() {
	const u8 PSX_DEFAULT_QUANTIZATION_MATRIX_ZIG_ZAG[64 * 2] =
	{
		 2,  16,  16,  19,  16,  19,  22,  22,	// LUMA
		22,  22,  22,  22,  26,  24,  26,  27,
		27,  27,  26,  26,  26,  26,  27,  27,
		27,  29,  29,  29,  34,  34,  34,  29,
		29,  29,  27,  27,  29,  29,  32,  32,
		34,  34,  37,  38,  37,  35,  35,  34,
		35,  38,  38,  40,  40,  40,  48,  48,
		46,  46,  56,  56,  58,  69,  69,  83,

		 2,  16,  16,  19,  16,  19,  22,  22,	// CHROMA
		22,  22,  22,  22,  26,  24,  26,  27,
		27,  27,  26,  26,  26,  26,  27,  27,
		27,  29,  29,  29,  34,  34,  34,  29,
		29,  29,  27,  27,  29,  29,  32,  32,
		34,  34,  37,  38,  37,  35,  35,  34,
		35,  38,  38,  40,  40,  40,  48,  48,
		46,  46,  56,  56,  58,  69,  69,  83
	};

 	for (int m = 0; m < 2; m++) {
		writeReg0(0x40000000 | m); // Command to upload Quant Matrices for LUMA only and then LUMA + CHROMA

		// Equivalent to command m_n_mdec0_command = 0x40000001;
		// => Load Table 0 and 1.
		const u8* data = PSX_DEFAULT_QUANTIZATION_MATRIX_ZIG_ZAG;
		for (int n = 0; n < (((m==0) ? 32 : 64) * 2) / 4; n++) {
			/*
			if (n == 16 || n == 8) {
				clock();
				clock();
				clock();
				clock();
				clock();
				clock();
			}
			*/
			writeReg0(*((u32*)data));
			data += 4;
		}

		// Stop write...
		clock();
		clock();
		clock();
		clock();
		clock();
		clock();
		clock();
		clock();
		clock();
	}
}

void TestMDEC::uploadCOSTable() {
	writeReg0(0x60000000); // Command to upload Quant Matrices for BOTH.	

	short PSX_COSINE_INIT[64] = { // assuming little-endian system
		23170,  23170,  23170,  23170,  23170,  23170,  23170,  23170,
		32138,  27245,  18204,   6392,  -6393, -18205, -27246, -32139,
		30273,  12539, -12540, -30274, -30274, -12540,  12539,  30273,
		27245,  -6393, -32139, -18205,  18204,  32138,   6392, -27246,
		23170, -23171, -23171,  23170,  23170, -23171, -23171,  23170,
		18204, -32139,   6392,  27245, -27246,  -6393,  32138, -18205,
		12539, -30274,  30273, -12540, -12540,  30273, -30274,  12539,
		6392, -18205,  27245, -32139,  32138, -27246,  18204,  -6393,
	};

	const int COSINE_SIZE = sizeof(PSX_COSINE_INIT);
	u16* data = (u16*)PSX_COSINE_INIT;
	for (int n = 0; n < ((64*2) / 4); n++) {
		writeReg0(*((u32*)data));
		/*
		if (n == 16 || n == 8) {
			
			clock();
			clock();
			clock();
			clock();
			clock();
			clock();
		}
		*/
		data += 2;
	}

	// Stop write...
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

}

void TestMDEC::uploadData() {
	int fileSize;

	const char* name =
//		"OPENINGE.MOV[0]_320x224[1369].mdec";
//		"finalfantasyVII_movie-gold4.mov[0]_320x224[352].mdec";
		"G_INFO-frame289_320x240.mdec";
	u8* data = readFile(name, &fileSize);

	int wordCount = (fileSize / 4);
	printf("------\n");
	/*
	  31-29 Command (1=decode_macroblock)
	  28-27 Data Output Depth  (0=4bit, 1=8bit, 2=24bit, 3=15bit)      ;STAT.26-25
	  26    Data Output Signed (0=Unsigned, 1=Signed)                  ;STAT.24
	  25    Data Output Bit15  (0=Clear, 1=Set) (for 15bit depth only) ;STAT.23
	  24-16 Not used (should be zero)
	  15-0  Number of Parameter Words (size of compressed data)
	 */
	const int DECODE_MACROBLOCK = 0x20000000;
	const int BIT24 = 0x2<<27;
	const int BIT16 = 0x3<<27;
	const int BIT8  = 0x1<<27;
	const int BIT4  = 0x0;

	const int SIGNED = 1<<26;
	const int UNSIGNED = 0<<26;

	const int BITSET = 1<<25;
	const int BITUNSET = 0;

	writeReg0(DECODE_MACROBLOCK | BIT24 | UNSIGNED | BITSET | wordCount);

	for (int n = 0; n < (fileSize / 4); n++) {
		writeReg0(*((u32*)data));
		data += 4;

		if ((n > 0) && ((n & 0x1F) == 0)) {
			updateOutput();
		}
	}




	for (int n = 0; n < 20000; n++) {
		clock();
	}
}

#if 0
class TestStreamAndCompute {
public:
	int  init		();
	void run		();
	void release	();

protected:
	void reset		(int clockCount);
	void transfer	();
	void clock		();

	void nop					();
	void flush					();
	void writeData	(u16 data, bool yOnly);
	void writeQuant	(const u8* data, int quantAdr4Bit, bool tblSelect);
	void uploadQuantTable();
	void uploadFakeQuantTable();

	void testEmptyBlockStream	();
	void testScale0Block		();
	void testOthers				();

	void uploadStreamColor		(u8* data, int length);

private:
	VfusedStreamCompute*	pFused;
	int				globalClock;
};

void TestStreamAndCompute::reset(int clockCount) {
	globalClock = 0;
	pFused->i_nrst = 0;
	for (int n = 0; n < clockCount; n++) {
		clock();
	}

	pFused->i_nrst = 1;
	clock();
}

void TestStreamAndCompute::release() {
	delete myCapture;
	delete pFused;
}

void TestStreamAndCompute::transfer() {
	if (pFused->o_dataWrt & (pFused->clk == 0)) {
		printf("@%i Write to Coef[%i/Zag=%i]=%i (Scale %i) BlockNum=%i %s %s %s\n",
			globalClock,
			pFused->o_index,
			pFused->o_linearIndex,
			IFIX(pFused->o_dataOut,10),
			pFused->o_scale,
			pFused->o_blockNum,
			pFused->o_fullBlockType ? "LIN" : "ZAG",
			pFused->o_isDC          ? "DC"  : "",
			pFused->o_blockComplete ? "LAST" : ""
		);
	}

	if (pFused->clk == 0) {
		if (pFused->o_dataWrt) {
			printf("@%i Out of Coef[%i]=%i Block=%i %s\n",
				globalClock,
				pFused->o_index,
				IFIX(pFused->o_dataOut,12),
				pFused->o_blockNum,
				pFused->o_blockComplete ? "Matrix Complete" : ""
			);
		} else if (pFused->o_blockComplete) {
			printf("@%i Out to Coef - MatrixComplete (%i %i)\n", globalClock,(int)pFused->o_blockComplete, (int)pFused->o_blockNum);
			/*
			printf(
				"i_clk=%i\ni_nrst=%i\ni_dataWrt=%i\ni_scale=%i\ni_isDC=%i\ni_index=%i\ni_zagIndex=%i\ni_fullBlockType=%i\ni_blockNum=%i\ni_matrixComplete=%i\ni_freezePipe=%i\ni_quantWrt=%i\ni_quantAdr=%i\ni_quantTblSelect=%i\no_write=%i\no_writeIdx=%i\no_blockNum=%i\no_matrixComplete=%i\ni_dataIn=%i\no_coefValue=%i\ni_quantValue=%i\ncomputeCoef__DOT__pFreeze=%i\ncomputeCoef__DOT__storeQuantVal=%i\ncomputeCoef__DOT__Reg1W=%i\ncomputeCoef__DOT__Reg2W=%i\ncomputeCoef__DOT__useReg2=%i\ncomputeCoef__DOT__valueQuant=%i\ncomputeCoef__DOT__storedQuant=%i\ncomputeCoef__DOT__quantAdr_reg=%i\ncomputeCoef__DOT__pipeQuantReadIdx=%i\ncomputeCoef__DOT__pWrite=%i\ncomputeCoef__DOT__pIndex=%i\ncomputeCoef__DOT__pBlk=%i\ncomputeCoef__DOT__pMatrixComplete=%i\ncomputeCoef__DOT__pFullBlkType=%i\ncomputeCoef__DOT__ppWrite=%i\ncomputeCoef__DOT__ppIndex=%i\ncomputeCoef__DOT__ppBlk=%i\ncomputeCoef__DOT__ppMatrixComplete=%i\ncomputeCoef__DOT__pMultF=%i\n",
				 (int)pCompute->i_clk								
				,(int)pCompute->i_nrst								
				,(int)pCompute->i_dataWrt							
				,(int)pCompute->i_scale								
				,(int)pCompute->i_isDC								
				,(int)pCompute->i_index								
				,(int)pCompute->i_zagIndex							
				,(int)pCompute->i_fullBlockType						
				,(int)pCompute->i_blockNum							
				,(int)pCompute->i_matrixComplete					
				,(int)pCompute->i_freezePipe						
				,(int)pCompute->i_quantWrt							
				,(int)pCompute->i_quantAdr							
				,(int)pCompute->i_quantTblSelect					
				,(int)pCompute->o_write								
				,(int)pCompute->o_writeIdx							
				,(int)pCompute->o_blockNum							
				,(int)pCompute->o_matrixComplete					
				,(int)pCompute->i_dataIn							
				,(int)pCompute->o_coefValue							
				,(int)pCompute->i_quantValue						
				,(int)pCompute->computeCoef__DOT__pFreeze			
				,(int)pCompute->computeCoef__DOT__storeQuantVal		
				,(int)pCompute->computeCoef__DOT__Reg1W				
				,(int)pCompute->computeCoef__DOT__Reg2W				
				,(int)pCompute->computeCoef__DOT__useReg2			
				,(int)pCompute->computeCoef__DOT__valueQuant		
				,(int)pCompute->computeCoef__DOT__storedQuant		
				,(int)pCompute->computeCoef__DOT__quantAdr_reg		
				,(int)pCompute->computeCoef__DOT__pipeQuantReadIdx	
				,(int)pCompute->computeCoef__DOT__pWrite			
				,(int)pCompute->computeCoef__DOT__pIndex			
				,(int)pCompute->computeCoef__DOT__pBlk				
				,(int)pCompute->computeCoef__DOT__pMatrixComplete	
				,(int)pCompute->computeCoef__DOT__pFullBlkType		
				,(int)pCompute->computeCoef__DOT__ppWrite			
				,(int)pCompute->computeCoef__DOT__ppIndex			
				,(int)pCompute->computeCoef__DOT__ppBlk				
				,(int)pCompute->computeCoef__DOT__ppMatrixComplete	
				,(int)pCompute->computeCoef__DOT__pMultF						
			);
			*/
		}
	}
}

void TestStreamAndCompute::clock() {
	static int captTime = 0;
	pFused->eval();					// Clock does not change, but propagate correctly input to output with pure combinatorial.
	myCapture->eval(captTime++);	// Capture properly the signals now.

	// Transition [1->0]
	pFused->clk	= 0;

	if (pFused->i_dataWrite) {
		printf("@%i Input Stream %x %s\n",
			globalClock,
			pFused->i_dataIn,
			pFused->i_YOnly ? "MONO" : "CHROMA"
		);
	}

	// Eval() just to perform a transition.
	pFused->eval();

	//
	#if 0
		// To run if we change input on negative edge...
		pFused->eval();
	#endif
	// Just need it for clock change()
	// TODO : Could optimize here.
	myCapture->eval(captTime++);

	globalClock++;

	pFused->clk	= 1;
	pFused->eval();
}

void TestStreamAndCompute::writeData(u16 data, bool yOnly) {
	pFused->i_dataWrite	= 1;
	pFused->i_dataIn		= data;
	pFused->i_YOnly		= yOnly;
//	printf("\t#20\n");
//	printf("\t\ti_dataWrite = 1'b%i; i_dataIn = 16'd%i; i_YOnly = 1'b%i;\n",1,(int)data,yOnly ? 1 : 0);
	clock();
	pFused->i_dataWrite	= 0;
}

void TestStreamAndCompute::writeQuant(const u8* data, int quantAdr4Bit, bool tblSelect) {
	u32 v = (data[0] & 0x7F) | ((data[1] & 0x7F) << 7) | ((data[2] & 0x7F) << 14) | ((data[3] & 0x7F) << 21); 
	pFused->i_quantWrt			= 1;
	pFused->i_quantValue		= v;
	pFused->i_quantAdr			= quantAdr4Bit;
	pFused->i_quantTblSelect	= tblSelect ? 1 : 0;

// 	printf("\t#20\n");
//	printf("\t\ti_quantWrt = 1'b%i; i_quantAdr = 4'd%i; i_quantValue = 28'd%i;\n",1,quantAdr4Bit,tblSelect ? 1 : 0,v);
	clock();
}

void TestStreamAndCompute::testEmptyBlockStream() {
	//
	printf("---------------Empty block stream -------\n");
	for (int n=0; n < 4; n++) {
		writeData(0xFE00,1);
	}

	nop();
}

void TestStreamAndCompute::nop() {
	pFused->i_dataIn		= 0;
	pFused->i_YOnly		= 0;
	pFused->i_dataWrite	= 0;
	clock();
}

void TestStreamAndCompute::flush() {
	nop();
	nop();
	nop();
}

#define COM16(a,b) (((a&0x3F)<<10)|(b & 0x3FF))

void TestStreamAndCompute::testScale0Block() {
	printf("--------------- Linear block stream -------\n");
	for (int n=0; n < 64; n++) {
		writeData(COM16(0,n),0);
	}
	// Flush output...
	nop();
	nop();
	nop();
}

void TestStreamAndCompute::testOthers() {
	printf("--------------- Zigzag block stream end at 63, no EOB -------\n");
	writeData(COM16( 1,0x100),0);
	writeData(COM16(31,0x200),0);
	writeData(COM16(30,0x300),0);

	// Flush output...
	flush();

	printf("--------------- Zigzag block stream end at 63, with EOB -------\n");
	writeData(COM16( 1, 5),0);
	writeData(COM16(31, 7),0);
	writeData(COM16(30,11),0);
	writeData(0xFE00,0);

	// Flush output...
	flush();

	printf("--------------- Invalid Zigzag block, higher than 63. with EOB -------\n");
	writeData(COM16( 1, 5),0);
	writeData(COM16(43, 7),0);
	writeData(COM16(30,11),0);
	writeData(0xFE00,0);

	// Flush output...
	flush();

	printf("--------------- Invalid Zigzag block, higher than 63. without EOB, loop -------\n");
	writeData(COM16( 1, 5),0);	// 0
	writeData(COM16(43, 7),0);	// 44
	writeData(COM16(30,11),0);	// 75 -> 11
	writeData(COM16(51,11),0);	// 11+1+51 -> 63

	flush();

	writeData(COM16( 1, 5),1);
	writeData(COM16(31, 7),1);
	writeData(COM16(30,11),1);
	writeData(0xFE00,0);

	flush();

	writeData(COM16( 1, 5),1);
	writeData(COM16(31, 7),1);
	writeData(COM16(30,11),1);
	writeData(0xFE00,0);

	flush();

	writeData(COM16( 1, 5),1);
	writeData(COM16(31, 7),1);
	writeData(COM16(30,11),1);
	writeData(0xFE00,0);

	flush();

	writeData(COM16( 1, 1),1);
	pFused->i_freezePipe = 1;
	writeData(COM16( 1, 2),1);	// 1 Value later is GOOD.
	writeData(0x6666,1);
	writeData(0x6666,1);
	writeData(0x6666,1);
	pFused->i_freezePipe = 0;
	writeData(0x6666,1);		// 1 Value later is GARBAGE.
	writeData(COM16( 1, 3),1);
	writeData(COM16( 1, 5),1);
	writeData(COM16( 1, 1),1);
	writeData(COM16( 1, 2),1);
	writeData(COM16( 1, 5),1);
	writeData(COM16( 1, 1),1);
	writeData(COM16( 1, 2),1);
	writeData(0xFE00,1);

	flush();
	flush();
	flush();
}

void TestStreamAndCompute::uploadStreamColor(u8* data, int length) {
	u8 freezePattern[19] = { 0,0,0,1, 0,0,1,1, 0,0,1,1, 1,0,0,1, 0,1,0 };

	u8 misterFreeze = 0;
	pFused->i_freezePipe = 0;
	u8 prevFreeze = 0;

	for (int n=0; n < length; ) {
		u16 v;
		if (pFused->i_freezePipe) {
			v = 0x5555;
		} else {
			v = data[n] | (data[n + 1] << 8);
			n += 2;
		}
		prevFreeze           = pFused->i_freezePipe;
		pFused->i_freezePipe = freezePattern[misterFreeze];
		writeData(v, 0);	// Garbage to simplify debug.
		misterFreeze++;
		if (misterFreeze == 19) { misterFreeze = 0; }

		if (v == 0xFE00) {
			printf("--------\n");
		}
	}

	writeData(0xFE00,0);
	writeData(0xFE00,0);
	writeData(0xFE00,0);
	writeData(0xFE00,0);
}

void TestStreamAndCompute::uploadFakeQuantTable() {
	u8 fakeTable[64*2];

	for (int n=0; n < 64; n++) {
		fakeTable[n] = n+1;
	}

	for (int n=0; n < 64; n++) {
		fakeTable[n+64] = 65-n;
	}

	// Equivalent to command m_n_mdec0_command = 0x40000001;
	// => Load Table 0 and 1.
	const u8* data = fakeTable;
	for (int n=0; n < (64*2)/4; n++) {
		writeQuant(data,(n & 0xF), (n >> 4) ? true : false);
		data += 4;
	}

	// Stop write...
	pFused->i_quantWrt			= 0;
	pFused->i_quantValue		= 0;
	pFused->i_quantAdr			= 0;
	pFused->i_quantTblSelect	= 0;
	clock();
}

void TestStreamAndCompute::uploadQuantTable() {
	const u8 PSX_DEFAULT_QUANTIZATION_MATRIX_ZIG_ZAG[64 * 2] =
	{
		2,  16,  16,  19,  16,  19,  22,  22,
		22,  22,  22,  22,  26,  24,  26,  27,
		27,  27,  26,  26,  26,  26,  27,  27,
		27,  29,  29,  29,  34,  34,  34,  29,
		29,  29,  27,  27,  29,  29,  32,  32,
		34,  34,  37,  38,  37,  35,  35,  34,
		35,  38,  38,  40,  40,  40,  48,  48,
		46,  46,  56,  56,  58,  69,  69,  83,

		2,  16,  16,  19,  16,  19,  22,  22,
		22,  22,  22,  22,  26,  24,  26,  27,
		27,  27,  26,  26,  26,  26,  27,  27,
		27,  29,  29,  29,  34,  34,  34,  29,
		29,  29,  27,  27,  29,  29,  32,  32,
		34,  34,  37,  38,  37,  35,  35,  34,
		35,  38,  38,  40,  40,  40,  48,  48,
		46,  46,  56,  56,  58,  69,  69,  83
	};

	// Equivalent to command m_n_mdec0_command = 0x40000001;
	// => Load Table 0 and 1.
	const u8* data = PSX_DEFAULT_QUANTIZATION_MATRIX_ZIG_ZAG;
	for (int n = 0; n < (64 * 2) / 4; n++) {
		writeQuant(data, (n & 0xF), (n >> 4) ? true : false);
		data += 4;
	}

	// Stop write...
	pFused->i_quantWrt = 0;
	pFused->i_quantValue = 0;
	pFused->i_quantAdr = 0;
	pFused->i_quantTblSelect = 0;
	clock();
}

int TestStreamAndCompute::init() {
	globalClock = 0;
	pFused	= new VfusedStreamCompute();

	myCapture = new VCScanner();
	myCapture->init(200);


//	VL_IN8(i_freezePipe,0,0);

/*
	VL_OUT8(o_dataWrt,0,0);
	VL_OUT8(o_scale,5,0);
	VL_OUT8(o_isDC,0,0);
	VL_OUT8(o_index,5,0);
	VL_OUT8(o_zagIndex,5,0);
	VL_OUT8(o_fullBlockType,0,0);
	VL_OUT8(o_blockNum,2,0);
	VL_OUT8(o_blockComplete,0,0);
*/
//	VL_OUT16(o_dataOut,9,0);

		ADD_WIRE	(myCapture,pFused,clk);
		ADD_WIRE	(myCapture,pFused,i_nrst);

		ADD_WIRE	(myCapture,pFused,i_dataWrite);
		ADD_WIREV	(myCapture,pFused,i_dataIn,16);
		ADD_WIRE	(myCapture,pFused,i_YOnly);

		ADD_WIRE	(myCapture,pFused,i_quantWrt);
		ADD_WIREV	(myCapture,pFused,i_quantValue,28);
		ADD_WIREV	(myCapture,pFused,i_quantAdr,4);
		ADD_WIRE	(myCapture,pFused,i_quantTblSelect);

		ADD_WIRE	(myCapture,pFused,i_freezePipe);

		// Output inputStream Unit
		ADD_WIRE	(myCapture,pFused,o_dataWrt);
		ADD_WIREV	(myCapture,pFused,o_dataOut,10);
		ADD_WIREV	(myCapture,pFused,o_scale,6);
		ADD_WIRE	(myCapture,pFused,o_isDC);
		ADD_WIREV	(myCapture,pFused,o_index,6);
		ADD_WIREV	(myCapture,pFused,o_linearIndex,6);
		ADD_WIRE	(myCapture,pFused,o_fullBlockType);
		ADD_WIREV	(myCapture,pFused,o_blockNum,3);
		ADD_WIRE	(myCapture,pFused,o_blockComplete);

		ADD_WIRE	(myCapture,pFused,o_Coefwrite);
		ADD_WIREV	(myCapture,pFused,o_CoefwriteIdx,6);
		ADD_WIREV	(myCapture,pFused,o_CoefValue,12);
		ADD_WIREV	(myCapture,pFused,o_CoefBlockNum,3);
		ADD_WIRE	(myCapture,pFused,o_CoefMatrixComplete);

//		ADD_WIREV	(myCapture, pFused, debug, 24);

		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__rIsFullBlock);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__indexCounter,7);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__scalereg,6);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__state,2);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__nextState,2);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__currIdx,7);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__isBlockComplete);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__isValidBlockComplete);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__rBlockCounter,3);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__prevYOnly);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__myStreamInput__DOT__z,6);
//		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pFreeze);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__storeQuantVal);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__Reg1W);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__Reg2W);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__useReg2);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__valueQuant,7);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__storedQuant,7);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__quantAdr_reg,5);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pipeQuantReadIdx,2);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pWrite);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pIndex,6);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pBlk,3);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pMatrixComplete);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pFullBlkType);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__ppWrite);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__ppIndex,6);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__ppBlk,3);
		ADD_WIRE	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__ppMatrixComplete);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pMultF,16);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__pOutCalc,12);
//		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__clippedOutCalc,12);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__outSelCalc,12);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__fullValueQuant,28);
		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__outCalc,24);
//		ADD_WIREV	(myCapture,pFused,fusedStreamCompute__DOT__mycomputeCoef__DOT__outCalcRoundDiv,24);



	// [AFTER SETUP OF CONNECTIONS]
	myCapture->addPlugin(new ValueChangeDump_Plugin("testBench_streamInput.vcd"));

	// Make sure we do not have write pin starting to do stupid things at startup...
	pFused->i_dataWrite = 0;

	// Reset the circuit.
	reset(5);

	/*
		VstreamInput
		input			i_dataWrite,
		input [15:0]	i_dataIn,
		input 			i_YOnly,
	*/

	/*
		VcomputeCoef
		// Quant Table Loading
		input					i_quantWrt,
		input	[27:0]			i_quantValue,
		input	[3:0]			i_quantAdr,
		input					i_quantTblSelect,

		output					o_write,
		output	[5:0]			o_writeIdx,
		output	[2:0]			o_blockNum,
		output	signed [11:0]	o_coefValue,
		output          		o_matrixComplete
	*/
	// Result [-2..+3]
//	printf("Error range [%i,%i]\n",minD,maxD);
	
	return 1;
}

void TestStreamAndCompute::run() {
	// Reset done at this stage.

	// Update Quant Table
//	uploadFakeQuantTable();
	uploadQuantTable();

	// Test empty packets...
	pFused->i_YOnly = 0; // COLOR MODE for now.
	testEmptyBlockStream();

	/*
		TODO :
		- Test pipeline freeze/unfreeze
		- Test end block with 63 without EOB
		- Test end block 63 WITH EOB
		- Test Scale 0 block
		- Test Scale n block
	 */
#if 0
	testScale0Block();

	testOthers();

	uploadQuantTable();
#endif
	//
	// 1. Upload the Quantization Table
	//
	int fileSize;
	u8* data = readFile("G_INFO-frame289_320x240.mdec", &fileSize);
	uploadStreamColor(data,fileSize);




	/*
		. Issue of byte order when loading the table...
			Table of 8 bit mapped to memory ?
	*/
	//
	// 2. Send various stream of data to validate computation...
	//
	/*
		. Test Pattern with SCALE  = 0
		. Test Pattern with SCALE != 0
		. Test Pattern with YOnly
			Test Also changes are runtime... what can possible go wrong ?
		. Test Pattern with a lot of FE00 (seems it does NOTHING on REAL HW)

		The input value must be less than 10 bit.
		Also because we want to check the computation, we will use input value like :

		Input :
		3	5	7	11	13	17	19	23	
		29	31	37	41	43	47	53	59	
		61	67	71	73	79	83	89	97	
		101	103	107	109	113	127	131	137
		139	149	151	157	163	167	173	179	
		181	191	193	197	199	211	223	227	
		229	233	239	241	251	257	263	269	
		271	277	281	283	293	307	311	313	

		Quantization Table :
		UV Table
		1   3   5   7   9   11  13  17
		1   2   3   4   5   6   7   8
		1   2   3   4   5   6   7   8
		1   2   3   4   5   6   7   8
		1   2   3   4   5   6   7   8
		1   2   3   4   5   6   7   8
		1   2   3   4   5   6   7   8
		1   2   3   4   5   6   7   8

			
	 */

	//
	// 3. Finally sending a whole frame to decode...
	//		[Log the result for other stage input]
	//
}
#endif


// int testRoundDiv8AndClamp();
void testSaturatedFunction();

int main() {
//	testRoundDiv8AndClamp();
//	testSaturatedFunction();

	TestMDEC test;


	VMDEC	original;
	VMDEC	workInstance;

	/*
	// ----- Save Work ----
	FILE* myFile; // create your file here...
	fwrite(&workInstance,1,sizeof(VMDECRegisters), myFile);
	// Close your file here...


	// ----- Load Work ----
	FILE* myFile; // open your file here...
	fread(&workInstance, 1, sizeof(VMDECRegisters), myFile);
	// Patch things we have broken with our loading...
	workInstance.__VlSymsp	= original.__VlSymsp;
	workInstance.name		= original.name;
	// Close your file.
	*/


	printf("%i\n", sizeof(VMDEC));

	test.init	();
	test.run	(105000);
	test.release();
}

