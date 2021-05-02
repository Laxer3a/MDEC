#include <verilated_vcd_c.h>
#include <cstdlib>

class Vspu_counter;
#include "../../../rtl/obj_dir/Vspu_counter.h"

void test_spu_counterTimed(int timeMax) {
	Vspu_counter* mod = new Vspu_counter();
	bool useScan = false;

	VerilatedVcdC   tfp;
	if (useScan) {

		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");

		mod->trace (&tfp, 99);
		tfp.open ("spu_counter_waves.vcd");
	}

	int phaseCnt = 0;

	mod->n_rst = 0; mod->i_clk = 0; mod->eval();
	if (useScan) { tfp.dump(phaseCnt); }
	phaseCnt++;

	mod->n_rst = 0; mod->i_clk = 1; mod->eval();
	if (useScan) { tfp.dump(phaseCnt); }
	phaseCnt++;

	mod->n_rst = 1;

	int  pauseBack  = 0;
	int  queuePause = 0;

	int prevVoiceCounter = -1;

	while (phaseCnt < (timeMax<<1)) {
		mod->i_clk = 0; mod->eval();

		if (useScan) { tfp.dump(phaseCnt); }
		phaseCnt++;

		mod->i_clk = 1; mod->eval();

		static bool prevCondWait = false;

		if (prevVoiceCounter == mod->o_voiceCounter) {
			pauseBack++;
		}
		prevVoiceCounter = mod->o_voiceCounter;

		/*
			TEST :
			- Number of repetitive state : o_voiceCounter identical !
				(so first safe state one does not count and is a normal state)
              + Stock counter
			vs
			- Number of cancelled clock.
		*/

		bool condGo = rand() & 1 /*(total % 7) != 0*/;
		if (!condGo) {
			queuePause++;
		}
		mod->i_onClock			= condGo;

		bool condWait   = (mod->o_currVoice == 7) && (mod->o_voiceCounter == 0);
		mod->i_safeStopState	= condWait;

		mod->eval();

		if (useScan) { tfp.dump(phaseCnt); }
		phaseCnt++;
	}

	tfp.close();

	int drift = queuePause-(pauseBack+mod->spu_counter__DOT__stopCounter)+mod->i_onClock;
	printf("Cycles : %i drift:%i\n",timeMax,drift);
	if (drift != 0) {
		printf("ERROR");
		while (1) {
		}
	}

	delete mod;
}

void testBresenhamCounter() {
	int imaginary = 33800;
	int real      = 40000;
	int enabledCount = 0;
	int disabledCount = 0;

	int curr      = 0;
	while (true) {
		if (curr >= real) {
			curr = curr + imaginary - real;
			printf("1");

			enabledCount++;
		} else {
			curr = curr + imaginary;
			printf("0");

			disabledCount++;
		}
	}
}


void test_spu_counter() {
	srand(5137);

	while (1) {
		test_spu_counterTimed(rand()+45000000);
	}
}
