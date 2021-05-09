#include <inttypes.h>

int filterTablePos[5] = {0, 60, 115, 98, 122};
int filterTableNeg[5] = {0, 0, -52, -55, -60};

int16_t clamp_16bit(int32_t sample) {
    if (sample > 0x7fff) return 0x7fff;
    if (sample < -0x8000) return -0x8000;

    return (int16_t)sample;
}

void decodeSW(uint8_t buffer[16], int32_t prevSample[2], int16_t decoded[28])
{
    // Read ADPCM header
    uint8_t shift = buffer[0] & 0x0f;
    uint8_t filter = (buffer[0] & 0x70) >> 4;  // 0x40 for xa adpcm
    if (shift > 12) shift  = 9;

    if (filter > 4) filter = 4;  // TODO: Not sure, check behaviour on real HW

    int filterPos = filterTablePos[filter];
    int filterNeg = filterTableNeg[filter];

    int idx = 0;

    for (int n = 0; n < 28; n++) {
        // Read currently decoded nibble
        int16_t nibble = buffer[2 + n / 2];
        if (n % 2 == 0) {
            nibble = (nibble & 0x0f);
        } else {
            nibble = (nibble & 0xf0) >> 4;
        }

        // Extend 4bit sample to 16bit
        int32_t sample = (int32_t)(int16_t)(nibble << 12);

        // Shift right by value in header
        sample >>= shift;

        // Mix previous samples
        sample += (prevSample[0] * filterPos + prevSample[1] * filterNeg + 32) / 64;

        // clamp to -0x8000 +0x7fff
		int16_t clamped_sample = clamp_16bit(sample);
        decoded[idx++] = clamped_sample;

        // Move previous samples forward
        prevSample[1] = prevSample[0];
        prevSample[0] = clamped_sample;
    }
}

#include <verilated_vcd_c.h>
class VADPCMDecoder;
#include "../../../rtl/obj_dir/VADPCMDecoder.h"

int scanClock;
VerilatedVcdC   tfp;

void decodeHW(VADPCMDecoder* mod, uint8_t buffer[16], int16_t prevSample[2], int16_t decoded[28], bool useScan)
{
	// Read ADPCM header
	uint8_t shift  =  buffer[0] & 0x0f;
	uint8_t filter = (buffer[0] & 0x70) >> 4;  // 0x40 for xa adpcm

	int idx = 0;
	// read per word
	uint16_t* pWords = (uint16_t*)&buffer[2];
	for (int n = 1; n < 8; n++) {
		uint16_t raw = *pWords++;
		
		for (int samplePos=0; samplePos < 4; samplePos++) {
			mod->i_Shift 			= shift;
			mod->i_Filter			= filter;
			mod->i_inputRAW			= raw;
			mod->i_samplePosition	= samplePos;
			mod->i_PrevSample0		= prevSample[0];
			mod->i_PrevSample1		= prevSample[1];
			
			mod->eval();

			if (useScan) {
				tfp.dump(scanClock);
			}
			scanClock++;
			
			// Move previous samples forward
			prevSample[1] = prevSample[0];
			prevSample[0] = mod->o_sample;
			decoded[((n-1) * 4)+samplePos] = mod->o_sample;
		}
	}
}

// rand,srand
#include <stdlib.h>
// printf
#include <stdio.h>
void test_ADPCMDecoder() {
	srand(1537);

	uint8_t packet   [16];
	int16_t	decodedSW[28];
	int16_t	decodedHW[28];

	int32_t prevSampleSW[2];
	int16_t prevSampleHW[2];

	VADPCMDecoder* mod = new VADPCMDecoder();
	bool useScan = false;

	if (useScan) {
		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");
		mod->trace (&tfp, 99);
		tfp.open ("adpcm_waves.vcd");
	}
	scanClock = 0;

	prevSampleHW[0] = prevSampleHW[1] = 0; 
	prevSampleSW[0] = prevSampleSW[1] = 0; 

	bool error = false;
	while (!error) {
		for (int n=0; n < 16; n++) { packet[n] = rand() & 0xFF; }

		decodeSW(    packet,prevSampleSW,decodedSW);
		decodeHW(mod,packet,prevSampleHW,decodedHW,useScan);
		
		for (int n=0; n < 28; n++) {
			if (decodedSW[n] != decodedHW[n]) {
				printf("DEBUG TO DO !!!! %i\n",n);
				error = true;
			}
		}
	}

	if (useScan) {
		tfp.close();
	}

	delete mod;
	exit(-1);
}