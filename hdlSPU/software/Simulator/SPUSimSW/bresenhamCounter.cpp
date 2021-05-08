#include <verilated_vcd_c.h>
#include <cstdlib>

class VbresenhamCounter;
#include "../../../rtl/obj_dir/VbresenhamCounter.h"

void testBresenhamCounter_SW() {
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


void testBresenhamCounter_HW() {
	VbresenhamCounter* mod = new VbresenhamCounter();
	bool useScan = false;

	VerilatedVcdC   tfp;
	if (useScan) {

		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");

		mod->trace (&tfp, 99);
		tfp.open ("bresenhamCounter_waves.vcd");
	}

	int enabledCount = 0;
	int disabledCount = 0;

	int phaseCnt = 0;

	mod->i_rst = 1; mod->i_clk = 0; mod->eval();
	if (useScan) { tfp.dump(phaseCnt); }
	phaseCnt++;

	mod->i_rst = 1; mod->i_clk = 1; mod->eval();
	if (useScan) { tfp.dump(phaseCnt); }
	phaseCnt++;

	mod->i_rst = 0;

	while (phaseCnt < 660000000) {
		mod->i_clk = 0; mod->eval();
		if (useScan) { tfp.dump(phaseCnt); }
		phaseCnt++;

		mod->i_clk = 1; mod->eval();
		if (useScan) { tfp.dump(phaseCnt); }
		phaseCnt++;
		
		if (mod->o_enable) {
			enabledCount++;
		} else {
			disabledCount++;
		}
	}

	printf("Enabled:%i\n",enabledCount);
	printf("Disabled:%i\n",disabledCount);

	tfp.close();

	delete mod;
}
