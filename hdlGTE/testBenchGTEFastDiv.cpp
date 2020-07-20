//----------------------------------------------------------------------------
// Test for full range of values
// - Division Unit of GTE.
// - LeadZeroCount Unit of GTE.
//----------------------------------------------------------------------------


#include <stdio.h>
#include "./rtl/obj_dir/VGTEFastDiv.h"
#include "obj_dir/VLeadCountS32.h"

#define ASSERT_CHK(cond)		if (!cond) { error(); }


void error() {
	printf("ERROR\n");
	while (1) {
	}
}

unsigned int count_leading_zeroes16(unsigned short x) {
	unsigned n = 0;
	if (x == 0) return sizeof(x) * 8;
	while (1) {
		if (x & (1<<15)) break;
		n ++;
		x <<= 1;
	}
	return n;
}

unsigned int min(unsigned int a, unsigned int b) {
	return a < b ? a : b;
}

int testGTEFastDiv() {
	VGTEFastDiv* mod = new VGTEFastDiv();

	int minD = 0;
	int maxD = 0;

	// For now implementation of GTEFastDiv Module does NOT use any clock signal.
	// In future implementation, it may change but at least let's validate the logic.

	// WHOLE INPUT SPACE VALIDATION :
	for (unsigned int h= 0; h < 65536; h++) {
		for (unsigned int z3 = 0; z3 < 65536; z3++) {

			mod->h   = h;
			mod->z3  = z3; 
			mod->eval();

			static const unsigned char unr_table[257] = {
				0xFF,0xFD,0xFB,0xF9,0xF7,0xF5,0xF3,0xF1,0xEF,0xEE,0xEC,0xEA,0xE8,0xE6,0xE4,0xE3, //-
				0xE1,0xDF,0xDD,0xDC,0xDA,0xD8,0xD6,0xD5,0xD3,0xD1,0xD0,0xCE,0xCD,0xCB,0xC9,0xC8, // 00h..3Fh
				0xC6,0xC5,0xC3,0xC1,0xC0,0xBE,0xBD,0xBB,0xBA,0xB8,0xB7,0xB5,0xB4,0xB2,0xB1,0xB0, //
				0xAE,0xAD,0xAB,0xAA,0xA9,0xA7,0xA6,0xA4,0xA3,0xA2,0xA0,0x9F,0x9E,0x9C,0x9B,0x9A, ///

				0x99,0x97,0x96,0x95,0x94,0x92,0x91,0x90,0x8F,0x8D,0x8C,0x8B,0x8A,0x89,0x87,0x86, //-
				0x85,0x84,0x83,0x82,0x81,0x7F,0x7E,0x7D,0x7C,0x7B,0x7A,0x79,0x78,0x77,0x75,0x74, // 40h..7Fh
				0x73,0x72,0x71,0x70,0x6F,0x6E,0x6D,0x6C,0x6B,0x6A,0x69,0x68,0x67,0x66,0x65,0x64, //
				0x63,0x62,0x61,0x60,0x5F,0x5E,0x5D,0x5D,0x5C,0x5B,0x5A,0x59,0x58,0x57,0x56,0x55, ///

				0x54,0x53,0x53,0x52,0x51,0x50,0x4F,0x4E,0x4D,0x4D,0x4C,0x4B,0x4A,0x49,0x48,0x48, //-
				0x47,0x46,0x45,0x44,0x43,0x43,0x42,0x41,0x40,0x3F,0x3F,0x3E,0x3D,0x3C,0x3C,0x3B, // 80h..BFh
				0x3A,0x39,0x39,0x38,0x37,0x36,0x36,0x35,0x34,0x33,0x33,0x32,0x31,0x31,0x30,0x2F, //
				0x2E,0x2E,0x2D,0x2C,0x2C,0x2B,0x2A,0x2A,0x29,0x28,0x28,0x27,0x26,0x26,0x25,0x24, ///

				0x24,0x23,0x22,0x22,0x21,0x20,0x20,0x1F,0x1E,0x1E,0x1D,0x1D,0x1C,0x1B,0x1B,0x1A, //-
				0x19,0x19,0x18,0x18,0x17,0x16,0x16,0x15,0x15,0x14,0x14,0x13,0x12,0x12,0x11,0x11, // C0h..FFh
				0x10,0x0F,0x0F,0x0E,0x0E,0x0D,0x0D,0x0C,0x0C,0x0B,0x0A,0x0A,0x09,0x09,0x08,0x08, //
				0x07,0x07,0x06,0x06,0x05,0x05,0x04,0x04,0x03,0x03,0x02,0x02,0x01,0x01,0x00,0x00, ///
				0x00 
			}; //    ;<-- one extra table entry (for "(d-7FC0h)/80h"=100h)    ;-100h

			unsigned int n;
			unsigned int overflow;

			// Here compute the software version
			if (h < z3*2) {										// check if overflow
				unsigned int z = count_leading_zeroes16(z3);	// z=0..0Fh (for 16bit SZ3)
				n = (h  << z);									// n=0..7FFF8000h
				unsigned int d = (z3 << z);
				
				// Commented out because reading internal value, may NOT be available !
				// ASSERT_CHK(mod->GTEFastDiv__DOT__b3 == d);
				unsigned int u = unr_table[(d-0x7FC0) >> 7];

				// Commented out because reading internal value, may NOT be available !
				// ASSERT_CHK(mod->GTEFastDiv__DOT__uLUT == u);
				u +=  0x101;									// u=200h..101h

				d = ((0x2000080 - (d * u)) >> 8);				// d=10000h..0FF01h
				d = ((0x0000080 + (d * u)) >> 8);				// d=20000h..10000h
				
				// C Implementation need to be carefull (64 bit mul here)
				unsigned long long mnd = ((unsigned long long)n*((unsigned long long)d));

				// Commented out because reading internal value, may NOT be available !
				// ASSERT_CHK(mod->GTEFastDiv__DOT__mnd == mnd);

				n = min(0x1FFFF, ((mnd + 0x8000) >> 16));		// n=0..1FFFFh
				overflow = 0;
			} else {
				n = 0x1FFFF;
				overflow = 1;
			}

			// HW Reference C Implementation give same result as HW verilog.
			ASSERT_CHK(mod->divRes   == n);
			ASSERT_CHK(mod->overflow == overflow);

			// Now, implementation a REAL division, according to those specs :
			// --------------------------------------------------------------------------------------
			// GTE Division Inaccuracy (for RTPS/RTPT commands)
			// --------------------------------------------------------------------------------------
			//	Basically, the GTE division does (attempt to) work as so (using 33bit maths):
			//	n = (((H*20000h/SZ3)+1)/2)
			//	alternatly, below would give (almost) the same result (using 32bit maths):
			//	n = ((H*10000h+SZ3/2)/SZ3)
			//  in both cases, the result is saturated about as so:
			//  if n>1FFFFh or division_by_zero then n=1FFFFh, FLAG.Bit17=1, FLAG.Bit31=1			
			// --------------------------------------------------------------------------------------
			// 32 bitversion : unsigned int uin = z3 ? ((((h*0x10000)+z3)/2)/z3) : 0x20000; // Create overflow.
			// 33 bit version :
			unsigned int uin = z3 ? ((((((unsigned long long)h)*0x20000)/z3)+1)/2) : 0x20000; // Create overflow.
			unsigned int softOverflow = 0;

			if (uin>0x1FFFF) {
				uin=0x1FFFF;
				softOverflow = 1;
			}

			//
			// Check approximative software operation described with DIVISION.
			// and check this software approx deviation against the [HW + C implementation of HW]
			//
			if ((softOverflow != overflow) || (uin != n)) {
				int del = ((int)uin) - ((int)n);
				if (del < minD) {
					minD = del;
				}
				
				if (del>maxD) {
					maxD = del;
				}
			} 
			// --------------------------------------------------------------------------------------
		}
		printf("Test : %i\n",h);
	}

	// Result [-2..+3]
	printf("Error range [%i,%i]\n",minD,maxD);
	
	delete mod;
	return 1;
}

int GTE_countLeadingZeroes(uint32_t n) {
    int zeroes = 0;
    if ((n & 0x80000000) == 0) n = ~n;

    while ((n & 0x80000000) != 0) {
        zeroes++;
        n <<= 1;
    }
    return zeroes;
}

int testGTELeadingZeroes() {
	VLeadCountS32* mod = new VLeadCountS32();
	unsigned int n = 0;
	unsigned int r;
	do {
		// HW
		mod->value = n;
		mod->eval();
		// SW
		r = GTE_countLeadingZeroes(n);
		if (r != mod->result) {
			printf("ERROR\n");
			return 0;
		}
		if ((n & 0xFFFF) == 0x0) {
			printf("%x\n",n);
		}
	} while ((n++)!=0xFFFFFFFF);

	return 1;
}
