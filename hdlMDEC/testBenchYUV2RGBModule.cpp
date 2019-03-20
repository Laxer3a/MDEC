//----------------------------------------------------------------------------
// Test for full range of values. for -128..+127 for Cr/Cb/Y
// - Verify Signed/Unsigned Conversion
// - Verify Y Only, YUV output
//----------------------------------------------------------------------------


#include <stdio.h>
#include            "VYUV2RGBCompute.h"

#define ASSERT_CHK(cond)		if (!cond) { error(); }

void error() {
	while (1) {
	}
}

int testYUV2RGB() {
	VYUV2RGBCompute* mod = new VYUV2RGBCompute();

	// For now implementation of YUV2RGB Module does NOT use any clock signal.
	// In future implementation, i_valueCr / i_valueCb will be shifted by 1 clock cycle compare to i_valueY input.
	// The testbench must reflect that
	for (int yOnly = 0; yOnly <= 1; yOnly++) {
		for (int uns = 0; uns <= 1; uns++) {
			for (int valueY = -128; valueY < 128; valueY++) {
				for (int valueCr = -128; valueCr < 128; valueCr++) {
					for (int valueCb = -128; valueCb < 128; valueCb++) {

						mod->i_valueY   = valueY  & 0xFF;
						mod->i_valueCr  = valueCr & 0xFF; 
						mod->i_valueCb  = valueCb & 0xFF;
						mod->i_unsigned = uns;
						mod->i_YOnly    = yOnly;

						mod->eval();

						// Here compute the software version

						int RTmp   = yOnly ? 0 : (359 * valueCr);
						int BTmp   = yOnly ? 0 : (454 * valueCb);
						int	GTmpB  = yOnly ? 0 : (valueCb * -88 );
						int	GTmpR  = yOnly ? 0 : (valueCr * -183);

						ASSERT_CHK(mod->YUV2RGBCompute__DOT__RTmp  == (RTmp  & 0x3FFFF));
						ASSERT_CHK(mod->YUV2RGBCompute__DOT__BTmp  == (BTmp  & 0x3FFFF));
						ASSERT_CHK(mod->YUV2RGBCompute__DOT__GTmpB == (GTmpB & 0x3FFFF));
						ASSERT_CHK(mod->YUV2RGBCompute__DOT__GTmpR == (GTmpR & 0x3FFFF));

						int G = (GTmpB>>8) + (GTmpR>>8);

						int outR = (RTmp>>8) + valueY;
						int outG = G         + valueY;
						int outB = (BTmp>>8) + valueY;

						ASSERT_CHK(mod->YUV2RGBCompute__DOT__sumR == (outR & 0x7FF));
						ASSERT_CHK(mod->YUV2RGBCompute__DOT__sumG == (outG & 0x7FF));
						ASSERT_CHK(mod->YUV2RGBCompute__DOT__sumB == (outB & 0x7FF));

						if (outR < -128) { outR = -128; }
						if (outR >  127) { outR =  127; }

						if (outG < -128) { outG = -128; }
						if (outG >  127) { outG =  127; }

						if (outB < -128) { outB = -128; }
						if (outB >  127) { outB =  127; }

						outR ^= mod->i_unsigned << 7;
						outG ^= mod->i_unsigned << 7;
						outB ^= mod->i_unsigned << 7;

						outR &= 0xFF;
						outG &= 0xFF;
						outB &= 0xFF;

						ASSERT_CHK(mod->o_r == outR);
						ASSERT_CHK(mod->o_g == outG);
						ASSERT_CHK(mod->o_b == outB);
					}
				}
				printf("[Cr:-128..+127 & Cb:-128..+127] Y:%i Unsigned:%i Y Only:%i\n",valueY,uns, yOnly);
			}
		}
	}

	delete mod;
	return 1;
}
