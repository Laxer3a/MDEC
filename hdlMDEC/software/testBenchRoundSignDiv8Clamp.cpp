//----------------------------------------------------------------------------
// Test for full range of values. for -128..+127 for Cr/Cb/Y
// - Verify Signed/Unsigned Conversion
// - Verify Y Only, YUV output
//----------------------------------------------------------------------------


#include <stdio.h>
#include "../rtl/obj_dir/Vtest_lib_saturated.h"

typedef short			s16;
typedef unsigned short	u16;
typedef char            s8;
typedef unsigned char	u8;

#define ASSERT_CHK(cond)		if (!cond) { error(); }
/*
void error() {
	while (1) {
	}
}
*/
void error();

#if 0
int C_Equivalent(int input) {
	input += 4;
	input /= 8;
	if (input < -2048) { input = -2048; }
	if (input >  2047) { input =  2047; }
	
	if (input < 0) {
		if (input == -1) {
			return input;
		} else {
			return (input / 2) * 2;
		}
	} else {
		return (input / 2) * 2;
	}
}

int testRoundDiv8AndClamp() {
	VroundDiv8AndClamp* mod = new VroundDiv8AndClamp();
	// 24 bit signed range.
	for (int n = (-1<<23); n < ((1<<23)-1); n++) {
		mod->valueIn = n & 0xFFFFFF;
		mod->eval();
		
		if (mod->valueOut != C_Equivalent(n)) {
			ASSERT_CHK(false);
		}
	}

	delete mod;
	return 1;
}
#endif

#if 1

#include <stdio.h>
#include "../rtl/obj_dir/Vtest_lib_saturated.h"

typedef short			s16;
typedef unsigned short	u16;
typedef char            s8;
typedef unsigned char	u8;

void testSaturatedFunction() {
	Vtest_lib_saturated* mod = new Vtest_lib_saturated();
	s16 inputSV;
	u16 inputUV;

	for (int n = 0; n < 65536; n++) {
		inputSV = n;
		inputUV = n;

		mod->signedInput	= inputSV;
		mod->unsignedInput	= inputUV;

		mod->eval();

		s8 outRange = mod->signedSRange;
		u8 outSPos  = mod->unsignedSPositive;
		u8 outUPos	= mod->unsignedUPositive;
		s16 outRound = mod->signedRountToZeroExM1;

		s16 C_range = inputSV;
		if (C_range < -128) { C_range = -128; }
		if (C_range >  127) { C_range =  127; }

		s16 C_Pos   = inputSV;
		if (C_Pos   <    0) { C_Pos =   0; }
		if (C_Pos   >  255) { C_Pos = 255; }

		u16 C_UPos  = inputUV;
		if (C_UPos  > 255) { C_UPos = 255; }

		s16 C_RoundT0M1 = inputSV;
		if (C_RoundT0M1 & 1) {
			if (C_RoundT0M1 != -1) {
				if (C_RoundT0M1 > 0) {
					C_RoundT0M1--;
				} else {
					C_RoundT0M1++;
				}
			}
		}

		if (C_range != outRange) {
			printf("error %i\n", n);
		}
		if (C_Pos   != outSPos ) {
			printf("error %i\n", n);
		}
		if (C_UPos  != outUPos ) {
			printf("error %i\n", n);
		}
		if (C_RoundT0M1 != outRound) {
			printf("error %i\n", n);
		}

	}

	delete mod;
}
#endif
