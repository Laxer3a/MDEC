// testChipSelect.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <stdio.h>
#include <string.h>

#include "VChipSelect.h"

int main()
{
	VChipSelect* mod = new VChipSelect();

	printf (" Scan all possible adresses depending on bios RAM setup and physical ram size.\n Validate our CHIP SELECT BUS DECODING.\n\n");

	// LOCAL SIGNALS
    // Internals; generally not touched by application code
    // Begin mtask footprint  all: 

	for (int platformMemSize = 0; platformMemSize<4; platformMemSize++) {
		for (int biosSize = 0; biosSize < 8; biosSize++) {
			int prevCS_Pins      = -1;
			mod->REG_RAM_SIZE    = biosSize; // 5:8MB  1MB+1MBHiz+6MB Locked
			mod->PhysicalRAMSize = platformMemSize; // 2MB

			printf (" --------------------------------------------\n");
			printf (" --- Memory BIOS Setup : %i , Platform Memory : %i\n",mod->REG_RAM_SIZE,mod->PhysicalRAMSize);
			printf (" --------------------------------------------\n");

			for (unsigned long long n=0; n < 0xFFFFFFFFULL; n+=4) {
				mod->i_address = n;
				mod->eval();

				// INTEGRATED INTO CPU (scratchpad)
				int CS_Pins = mod->o_csPins; // | (mod->o_csScratchPad<<16);
				// int CS_Scratch = mod->o_csScratchPad;
				// int regi = (int)mod->o_region;
				// int hasScratch = mod->o_hasScratchPad;
				if (CS_Pins != prevCS_Pins) {
					printf("Change at %08x : ",(unsigned int)n/*,regi,hasScratch*/);
					bool found = false;
					if (CS_Pins) {
						if (CS_Pins & 65536) { printf("[SCRATCHPAD]"); }
						if (CS_Pins & 8192) { printf("RAM HiZ"); }
						if (CS_Pins & 4096) { printf("RAM"); }
						if (CS_Pins & 2048) { printf("MemCtrl1"); }
						if (CS_Pins & 1024) { printf("PeriphIO"); }
						if (CS_Pins &  512) { printf("MemCtrl2"); }
						if (CS_Pins &  256) { printf("INTCtrl"); }

						if (CS_Pins &  128) { printf("DMACtrl"); }
						if (CS_Pins &   64) { printf("TimerCtrl"); }
						if (CS_Pins &   32) { printf("CDRomCtrl"); }
						if (CS_Pins &   16) { printf("GPUCtrl"); }

						if (CS_Pins &    8) { printf("MDECCtrl"); }
						if (CS_Pins &    4) { printf("SPUCtrl"); }
						if (CS_Pins &    2) { printf("ExpReg2"); }
						if (CS_Pins &    1) { printf("BIOS_CS"); }
					} else {
						printf("[CPU EXCEPTION]");
					}

					printf("\n");
					prevCS_Pins = CS_Pins;
				}
			}
		}
	}

	delete mod;
}
