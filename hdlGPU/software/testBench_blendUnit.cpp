//----------------------------------------------------------------------------
//----------------------------------------------------------------------------

#include <stdio.h>
#include "../rtl/obj_dir/VblendUnit.h"

#define ASSERT_CHK(cond)		if (!cond) { errorBlend(); }

void errorBlend() {
	while (1) {
	}
}

int testBlendUnit() {
	//
	// This module is pure combinatorial computation, no clock needed.
	//
	VblendUnit* mod = new VblendUnit();

	// Can not test FULL range. Too big. (50000 hours est.)
	// WHITE BOX TEST : Verified that code have correct and same path for R/G/B, reduce space from 24 to 8 bit.

	for (int noblend = 0; noblend < 2; noblend++) {	// Off and On
		printf("=== NOBLEND %i\n", noblend);
		mod->noblend = noblend;
		// 24 bit full input.

		for (int n = 0; n <= 255; n++) {
			mod->bg_r = n;
			mod->bg_g = n;
			mod->bg_b = n;

			for (int m = 0; m <= 255; m++) {
				mod->px_r = m;
				mod->px_g = m;
				mod->px_b = m;

				for (int mode = 0; mode <= 3; mode++) {

					mod->mode = mode;

					mod->eval();

					printf("PX %i BX %i mode %i\n",m,n,mode);

					int v;
					switch (mode) {
					case 0:
						if (noblend) {
							v = m;			 // Copy source
						} else {
							v = (m + n) >> 1; // Alpha 50%
						}
						break;
					case 1:
						if (noblend) {
							v = m;			 // Copy source
						} else {
							v = m + n;
							if (v > 255) { v = 255; }
						}
						break;
					case 2:
						if (noblend) {
							v = m;			 // Copy source
						} else {
							v = n - m;
							if (v < 0  ) { v = 0;   }
							if (v > 255) { v = 255; }
						}
						break;
					case 3:
						if (noblend) {
							v = m;			 // Copy source
						} else {
							v = ((n << 2) + m)>>2;
							if (v > 255) { v = 255; }
						}
						break;
						break;
					}

					ASSERT_CHK(v == mod->rOut);
				} // mode
			} // px
		} // bg
	} // noblend

	delete mod;
	return 1;
}

int main() {
	testBlendUnit();
}
