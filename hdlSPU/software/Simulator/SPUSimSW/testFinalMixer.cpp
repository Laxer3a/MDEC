#include <inttypes.h>

struct MixingContext {
	// TODO
};

int clamps16(int v) {
	if (v < -32768) { v = -32768; }
	if (v >  32767) { v =  32767; }
}

void decodeSW(MixingContext& input)
{
	/*
	*/
	int volume			 = i_side22Kz ? i_reg_reverbVolRight : i_reg_reverbVolLeft;
	int valueReverb		 = i_accReverb * volume;
	int valueReverbFinal = i_reg_ReverbEnable ? (valueReverb>>15) : 0;

	// Register storage issue for testing...
	/*
	always @(posedge i_clk) begin
		if (i_rst) begin
			reg_CDRomInL 		<= 16'd0; 
			reg_CDRomInR		<= 16'd0; 
			regValueReverbLeft	<= 16'd0;
			regValueReverbRight	<= 16'd0;
		end else begin
			if (i_CDRomInL_valid) begin
				reg_CDRomInL <= i_CDRomInL; 
			end
			if (i_CDRomInR_valid) begin
				reg_CDRomInR <= i_CDRomInR;
			end

			if (i_ctrlSendOut) begin
				if (i_side22Khz) begin
					// Right Side
					regValueReverbRight <= valueReverbFinal;
				end else begin
					// Left Side
					regValueReverbLeft  <= valueReverbFinal;
				end
			end
		end
	end
	*/
	
	int tmpCDRomL	 = reg_CDRomInL * i_reg_CDVolumeL;
	int tmpCDRomR	 = reg_CDRomInR * i_reg_CDVolumeR;
	int CD_addL		 = tmpCDRomL >> 15;
	int CD_addR		 = tmpCDRomR >> 15;
	int CdSideL		 = i_reg_CDAudioEnabled       ? CD_addL : 0;
	int CdSideR		 = i_reg_CDAudioEnabled       ? CD_addR : 0;
	int cdReverbInput= i_reg_CDAudioReverbEnabled ? 0 : (i_side22Khz ? CdSideR : CdSideL);
	int reverbFull	 = i_sumReverb + cdReverbInput;
	int o_lineIn	 = clamps16(reverbFull);
	int volL		 = i_regSPUNotMuted ? (i_regMainVolLeft & 0x7FFF) : 0;
	int volR		 = i_regSPUNotMuted ? (i_regMainVolRight& 0x7FFF) : 0;
	int	sumPostVolL	 = i_sumLeft  * volL;
	int	sumPostVolL	 = i_sumRight * volR;
	int CDAndReverbL = CdSideL + regValueReverbLeft;
	int CDAndReverbR = CdSideR + regValueReverbRight;
	
	int postVolL = (sumPostL >> 14) + CDAndReverbL;
	int postVolR = (sumPostR >> 14) + CDAndReverbR;
	
	outL = clamps16(postVolL);
	outR = clamps16(postVolR);
}

#include <verilated_vcd_c.h>
class VADPCMDecoder;
#include "../../../rtl/obj_dir/VADPCMDecoder.h"

int scanClock;
VerilatedVcdC   tfp;

void decodeHW(VADPCMDecoder* mod, MixingContext& input, bool useScan)
{
}

// rand,srand
#include <stdlib.h>
// printf
#include <stdio.h>
void test_FinalMixer() {
	srand(1537);

	VADPCMDecoder* mod = new VADPCMDecoder();
	bool useScan = false;

	if (useScan) {
		Verilated::traceEverOn(true);
		VL_PRINTF("Enabling GTKWave Trace Output...\n");
		mod->trace (&tfp, 99);
		tfp.open ("adpcm_waves.vcd");
	}
	scanClock = 0;

	bool error = false;
	while (!error) {
		/* Setup random values */

		mixSW(    ?,decodedSW);
		mixHW(mod,?,decodedHW,useScan);

		/* TODO Compare result */
	}

	if (useScan) {
		tfp.close();
	}

	delete mod;
	exit(-1);
}