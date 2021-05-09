#include <inttypes.h>

struct LoopContext {
	uint16_t baseReg;

	// Software version
	uint32_t reverbCurrentAddress;
	
	// Hardware version
	uint32_t offsetCounter;
};

uint32_t wrap(uint32_t reverbBaseReg, uint32_t address) {
    const uint32_t reverbBase = reverbBaseReg * 8;

    uint32_t rel = address - reverbBase;
    rel = rel % ( (1024 * 512)/*spu->RAM_SIZE*/ - reverbBase);

    return (reverbBase + rel) & 0x7fffe;
}

uint32_t decodeSW(LoopContext& input, int address)
{
    return wrap(input.baseReg, input.reverbCurrentAddress + address);
}

void incrCurrAddrSW(LoopContext& input) {
	input.reverbCurrentAddress = wrap(input.baseReg, input.reverbCurrentAddress + 2);
}


#include <verilated_vcd_c.h>
class VReverbWrapAdr;
#include "../../../rtl/obj_dir/VReverbWrapAdr.h"

uint64_t scanClock_rvw;
VerilatedVcdC   tfp_rvw;

uint32_t decodeHW(VReverbWrapAdr* mod, LoopContext& input, int address, bool useScan)
{
	// HW is in word, input parameter is in byte like Software.
	address>>=1;
	
	mod->i_offsetRegister	= address;				// 18 bit Word Offset. (include -1)
	mod->i_baseAdr			= input.baseReg;		// 16 bit 
	mod->i_offsetCounter	= input.offsetCounter;	// 18 bit
	
	mod->eval();
	if (useScan) {
		tfp_rvw.dump(scanClock_rvw);
	}
	scanClock_rvw++;
	
	return mod->o_reverbAdr<<1;
}

void incrCurrAddrHW(LoopContext& input) {
	// Done in HW in another part but here done in C.
	
	//  if counter == last valid index -> loop to zero.
	if (input.offsetCounter == ((~input.baseReg << 2) | 0x3)) {
		input.offsetCounter = 0;
	} else {
		input.offsetCounter++;
	}
}

// rand,srand
#include <stdlib.h>
// printf
#include <stdio.h>
// memset
#include <memory.h>

void test_ReverbWrapAddress() {
	srand(1537);

	VReverbWrapAdr* mod = new VReverbWrapAdr();
	bool useScan = true;

	if (useScan) {
		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");
		mod->trace (&tfp_rvw, 99);
		tfp_rvw.open ("reverbaddr_waves.vcd");
	}
	scanClock_rvw = 0;

	bool error = false;
	LoopContext ctx;
	ctx.baseReg					= 1;
	
	// Condition must be identical at start.

	uint8_t* mapSW = new uint8_t[256*1024];
	uint8_t* mapHW = new uint8_t[256*1024];

	int tryCount = 0;

	while (!error) {
		/* Setup random values */
		ctx.baseReg   = rand() &  0xFFFF;  // [64K x 8 = 512 KB]
		uint32_t addr = rand() & 0x7FFFF;  // [512 KB]
		
		memset(mapSW,0,256*1024);
		memset(mapHW,0,256*1024);

		ctx.reverbCurrentAddress	= 0;	// SW
		ctx.offsetCounter			= 0;	// HW

		int minSW = 0x7FFFFFFF;
		int maxSW = -1;
		int minHW = 0x7FFFFFFF;
		int maxHW = -1;

		// offset counter defined by range space.
		for (int offset=0; offset<512*1024; offset+=2) {
			uint32_t resultSW = decodeSW(    ctx,addr);
			uint32_t resultHW = decodeHW(mod,ctx,addr,useScan);

			// Array in word, not byte
			int wSW = resultSW>>1;
			int wHW = resultHW>>1;

			mapSW[wSW] = 1; // Mark
			mapHW[wHW] = 1;
			if (wSW < minSW) { minSW = wSW; }
			if (wHW < minHW) { minHW = wHW; }
			if (wSW > maxSW) { maxSW = wSW; }
			if (wHW > maxHW) { maxHW = wHW; }

			if (wSW >= 256*1024) { printf("ERROR SW"); }
			if (wHW >= 256*1024) { printf("ERROR HW"); }

			incrCurrAddrSW(ctx);
			incrCurrAddrHW(ctx);
		}
		
		int cmp = memcmp(mapSW,mapHW,256*1024);
		printf("BaseReg : %04x, Reg Adr : %05x => RANGE SW:%05x-%05x HW:%05x-%05x",ctx.baseReg,addr,minSW,maxSW,minHW,maxHW);
		if (cmp != 0) {
//			uint8_t* outputPng = new uint8_t[512*512*4];
			printf(" FAIL !\n");		
		} else {
			printf("\n");
		}
		tryCount++;
	}

	if (useScan) {
		tfp_rvw.close();
	}

	delete mod;
	delete mapSW;
	delete mapHW;
	exit(-1);
}
