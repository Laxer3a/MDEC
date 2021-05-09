#include <inttypes.h>
#include "avoSPU/voice.h"

void decodeSW(spu::Voice v)
{
	v.processEnvelope();
}

#include <verilated_vcd_c.h>
class Vspu_ADSRUpdate;
#include "../../../rtl/obj_dir/Vspu_ADSRUpdate.h"

int scanClockADSR;
VerilatedVcdC   tfpADSR;

void decodeHW(Vspu_ADSRUpdate* mod, spu::Voice v, bool useScan)
{
	mod->i_validSampleStage2	= 1;	// Always 1 (Processing a sample, needing to update ADSR)
	mod->i_reg_SPUEnable		= 1;	// SPU Always Enabled.

	// Convert 
	mod->i_curr_KON				= 0;
	mod->i_curr_AdsrVOL			= v.adsrVolume._reg;

	/*	
		  ____lower 16bit (at 1F801C08h+N*10h)___________________________________
		  15    Attack Mode       (0=Linear, 1=Exponential)
		  -     Attack Direction  (Fixed, always Increase) (until Level 7FFFh)
		  14-10 Attack Shift      (0..1Fh = Fast..Slow)
		  9-8   Attack Step       (0..3 = "+7,+6,+5,+4")
		  -     Decay Mode        (Fixed, always Exponential)
		  -     Decay Direction   (Fixed, always Decrease) (until Sustain Level)
		  7-4   Decay Shift       (0..0Fh = Fast..Slow)
		  -     Decay Step        (Fixed, always "-8")
		  3-0   Sustain Level     (0..0Fh)  ;Level=(N+1)*800h
	*/
	spu::ADSR& adsr = v.adsr;
	
	mod->i_curr_AdsrLo			= (adsr.attackMode<<15) | (adsr.attackShift<<10) | (adsr.attackStep<<8) 
								| (adsr.decayShift<<4)  | (adsr.sustainLevel);

	/*
		  ____upper 16bit (at 1F801C0Ah+N*10h)___________________________________
		  31    Sustain Mode      (0=Linear, 1=Exponential)
		  30    Sustain Direction (0=Increase, 1=Decrease) (until Key OFF flag)
		  29    Not used?         (should be zero)
		  28-24 Sustain Shift     (0..1Fh = Fast..Slow)
		  23-22 Sustain Step      (0..3 = "+7,+6,+5,+4" or "-8,-7,-6,-5") (inc/dec)
		  21    Release Mode      (0=Linear, 1=Exponential)
		  -     Release Direction (Fixed, always Decrease) (until Level 0000h)
		  20-16 Release Shift     (0..1Fh = Fast..Slow)
		  -     Release Step      (Fixed, always "-8")
	*/
	mod->i_curr_AdsrHi			= (adsr.sustainMode<<15) | (adsr.sustainDirection<<14) | (adsr.sustainShift<<8) | (adsr.sustainStep<<6)
								| (adsr.releaseMode<<5)  | (adsr.releaseShift);

	// HW has no 'Off' it is Release with 0 cycle.
	mod->i_curr_AdsrState		= (v.state == spu::Voice::State::Off) ? 3 /*Release*/ : (int)v.state;
	mod->i_curr_AdsrCycleCount	= (v.state == spu::Voice::State::Off) ? 0             : v.adsrWaitCycles;

	mod->eval();

	if (useScan) {
		tfpADSR.dump(scanClockADSR);
	}
	scanClockADSR++;

//	output					o_updateADSRVolReg	= i_validSampleStage2 & reach 0
//	output					o_clearKON,			= o_updateADSRVolReg
	mod->o_updateADSRState; // bool
	mod->o_nextAdsrState;	// 4 states.

	mod->o_updateADSRVolReg;
	mod->o_nextAdsrVol;		// Signed value. (15 bit -> Take care when int to C

	mod->o_nextAdsrCycle;	// 23 bit
}

// rand,srand
#include <stdlib.h>
// printf
#include <stdio.h>
void test_VoicProcessEnvellope() {
	srand(1537);

	Vspu_ADSRUpdate* mod = new Vspu_ADSRUpdate();
	bool useScan = false;

	if (useScan) {
		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");
		mod->trace (&tfpADSR, 99);
		tfpADSR.open ("adsrupdate_waves.vcd");
	}
	scanClockADSR = 0;

	bool error = false;
	while (!error) {
		spu::Voice swv;
		// RANDOMIZE ?;

		spu::Voice hwv;
		memcpy(&hwv,&swv,sizeof(spu::Voice)); // WARNING : vector class copy bad (sample only), but members only OK.

		
		decodeSW(swv);
		decodeHW(mod,hwv,useScan);

		// COMPARE RESULT
		/*				
		for (int n=0; n < 28; n++) {
			if (decodedSW[n] != decodedHW[n]) {
				printf("DEBUG TO DO !!!! %i\n",n);
				error = true;
			}
		}
		*/
	}

	if (useScan) {
		tfpADSR.close();
	}

	delete mod;
	exit(-1);
}
