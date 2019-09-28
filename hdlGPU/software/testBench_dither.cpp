//----------------------------------------------------------------------------
// Test for full range of values => RGB 16 millions
// Test for all screen space combination (x 0..3, y 0..3)
// Test for dither on/off
// Total 2^29 tests.
//----------------------------------------------------------------------------

#include <stdio.h>
#include "../rtl/obj_dir/Vdither.h"

#define ASSERT_CHK(cond)		if (!cond) { errorDither(); }

void errorDither() {
	while (1) {
	}
}

int testDither() {
	//
	// This module is pure combinatorial computation, no clock needed.
	//
	Vdither* mod = new Vdither();

	for (int dither = 0; dither < 2; dither++) {	// Off and On
		printf("=== DITHER %i\n", dither);
		mod->ditherOn = dither;
		// 24 bit full input.
		for (int ri = 0; ri <= 255; ri++) {
		if ((ri & 0xF) == 0) {
			printf("Red %i\n", ri);
		}

		for (int gi = 0; gi <= 255; gi++) {
		for (int bi = 0; bi <= 255; bi++) {
			mod->rIn = ri;
			mod->gIn = gi;
			mod->bIn = bi;
			for (int y = 0; y <= 3; y++) {
				for (int x = 0; x <= 3; x++) {
					mod->xBuff = x;
					mod->yBuff = y;

//					mod->eval();

					// C Reference implementation.
					int rOut;
					int gOut;
					int bOut;

					if (dither == 0) {
						rOut = ri >> 3; // Cut 3 bit, end of story.
						gOut = gi >> 3; // Cut 3 bit, end of story.
						bOut = bi >> 3; // Cut 3 bit, end of story.
					} else {
						static const int tbl[4][4] = {
							-4, 0 ,-3 ,+1,
							+2, -2, +3, -1,
							-3, +1, -4, +0,
							+3, -1, +2, -2
						};

						int offset = tbl[y][x];

						int tr = ri + offset;
						if (tr < 0) { tr = 0; }
						if (tr > 255) { tr = 255; }
						rOut = tr >> 3;

						int tg = gi + offset;
						if (tg < 0) { tg = 0; }
						if (tg > 255) { tg = 255; }
						gOut = tg >> 3;

						int tb = bi + offset;
						if (tb < 0) { tb = 0; }
						if (tb > 255) { tb = 255; }
						bOut = tb >> 3;
					}

					ASSERT_CHK(mod->r == rOut);
					ASSERT_CHK(mod->g == gOut);
					ASSERT_CHK(mod->b == bOut);
				} // x
			} // y
		} // b
		} // g
		} // r
	} // ditherOff/On
	delete mod;
	return 1;
}

/*
int main() {
	testDither();
}
*/
