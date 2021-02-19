class Vgpu;

#include "project.h"

// PNG READ
#include "stb_image.h"
// PNG WRITE
#include "stb_image_write.h"
// strlen,atoi, etc...
#include <string.h>
#include <stdlib.h>

// Just as array to store commands for GPU. (Sequence of 32 bit to write)
#include "GPUCommandGen.h"



void drawCheckedBoard(unsigned char* buffer) {
	for (int y=0; y < 512; y++) {
		int py = y & 8;
		for (int x=0; x < 1024; x++) {
				int px = x & 8;

				int d = px ^ py;
				int v = d ? 0x0000 : 0x4210/*0x7FFF*/;
				int r = (x-512)>>4;
				int g = (y-512)>>4;
				v += r + (g<<5);
				buffer[x * 2 + y*2048    ] = ( v     & 0xFF);
				buffer[x * 2 + y*2048 + 1] = ((v>>8) & 0xFF);
		}
	}
}

bool ReadStencil(VGPU_DDR* mod, int x, int y) {
#if  defined(SOURCE_ULTRA) || defined(SOURCE_OLDME)
	int addr = (x >> 4) + (y * 64);

	// Interleaving of blocks.
	int block = (addr & 1) | (((addr>>6) & 3)<<1);
	addr  = ((addr>>1) & 0x1F) | ((addr>>8)<<5);

    u16 v;
	switch (block) {
	case 0: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram0__inst_dpRAM_8k.ram[addr]; break;
	case 1: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram1__inst_dpRAM_8k.ram[addr]; break;
	case 2: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram2__inst_dpRAM_8k.ram[addr]; break;
	case 3: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram3__inst_dpRAM_8k.ram[addr]; break;
	case 4: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram4__inst_dpRAM_8k.ram[addr]; break;
	case 5: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram5__inst_dpRAM_8k.ram[addr]; break;
	case 6: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram6__inst_dpRAM_8k.ram[addr]; break;
	case 7: v = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram7__inst_dpRAM_8k.ram[addr]; break;
	}
	return v & (1<<(x & 0xF));
#endif
#if  defined(SOURCE_LASTME)
	int adrMem = 0;
	unsigned char valMem;
	adrMem = (x>>4) + ((y>>1)<<6);

	if (y & 1) {
		// Bank A for line odd.
		switch (x & 0xF) {
		case  0: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00A__DOT__mem[adrMem]; break;
		case  1: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01A__DOT__mem[adrMem]; break;
		case  2: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02A__DOT__mem[adrMem]; break;
		case  3: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03A__DOT__mem[adrMem]; break;
		case  4: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04A__DOT__mem[adrMem]; break;
		case  5: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05A__DOT__mem[adrMem]; break;
		case  6: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06A__DOT__mem[adrMem]; break;
		case  7: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07A__DOT__mem[adrMem]; break;
		case  8: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08A__DOT__mem[adrMem]; break;
		case  9: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09A__DOT__mem[adrMem]; break;
		case 10: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10A__DOT__mem[adrMem]; break;
		case 11: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11A__DOT__mem[adrMem]; break;
		case 12: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12A__DOT__mem[adrMem]; break;
		case 13: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13A__DOT__mem[adrMem]; break;
		case 14: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14A__DOT__mem[adrMem]; break;
		case 15: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15A__DOT__mem[adrMem]; break;
		}
	} else {
		// Bank B for line even.
		switch (x & 0xF) {
		case  0: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00B__DOT__mem[adrMem]; break;
		case  1: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01B__DOT__mem[adrMem]; break;
		case  2: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02B__DOT__mem[adrMem]; break;
		case  3: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03B__DOT__mem[adrMem]; break;
		case  4: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04B__DOT__mem[adrMem]; break;
		case  5: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05B__DOT__mem[adrMem]; break;
		case  6: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06B__DOT__mem[adrMem]; break;
		case  7: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07B__DOT__mem[adrMem]; break;
		case  8: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08B__DOT__mem[adrMem]; break;
		case  9: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09B__DOT__mem[adrMem]; break;
		case 10: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10B__DOT__mem[adrMem]; break;
		case 11: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11B__DOT__mem[adrMem]; break;
		case 12: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12B__DOT__mem[adrMem]; break;
		case 13: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13B__DOT__mem[adrMem]; break;
		case 14: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14B__DOT__mem[adrMem]; break;
		case 15: valMem = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15B__DOT__mem[adrMem]; break;
		}
	}

	return (valMem&1) == 1;
#else
	return true;
#endif
}

void setStencil(VGPU_DDR* mod, int x,int y, bool v) {
#if  defined(SOURCE_ULTRA) || defined(SOURCE_OLDME)
	int addr = (x >> 4) + (y * 64);

	// Interleaving of blocks.
	int block = (addr & 1) | (((addr>>6) & 3)<<1);
	addr  = ((addr>>1) & 0x1F) | ((addr>>8)<<5);

    u16 va;
	switch (block) {
	case 0: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram0__inst_dpRAM_8k.ram[addr]; break;
	case 1: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram1__inst_dpRAM_8k.ram[addr]; break;
	case 2: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram2__inst_dpRAM_8k.ram[addr]; break;
	case 3: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram3__inst_dpRAM_8k.ram[addr]; break;
	case 4: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram4__inst_dpRAM_8k.ram[addr]; break;
	case 5: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram5__inst_dpRAM_8k.ram[addr]; break;
	case 6: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram6__inst_dpRAM_8k.ram[addr]; break;
	case 7: va = mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram7__inst_dpRAM_8k.ram[addr]; break;
	}

	u16 orp = (v?1:0) << (x&0xF);
	va = (va & (~(1<<(x & 0xF)))) | orp;

	switch (block) {
	case 0: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram0__inst_dpRAM_8k.ram[addr] = va; break;
	case 1: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram1__inst_dpRAM_8k.ram[addr] = va; break;
	case 2: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram2__inst_dpRAM_8k.ram[addr] = va; break;
	case 3: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram3__inst_dpRAM_8k.ram[addr] = va; break;
	case 4: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram4__inst_dpRAM_8k.ram[addr] = va; break;
	case 5: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram5__inst_dpRAM_8k.ram[addr] = va; break;
	case 6: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram6__inst_dpRAM_8k.ram[addr] = va; break;
	case 7: mod->__VlSymsp->TOP__GPU_DDR__gpu_inst__StencilCacheInstance__u_ram7__inst_dpRAM_8k.ram[addr] = va; break;
	}
#endif
#if  defined(SOURCE_LASTME)
	int adrMem = 0;
	unsigned char valMem = v ? 1 : 0;

	adrMem = (x>>4) + ((y>>1)<<6);

	if (y & 1) {
		// Bank A for line odd.
		switch (x & 0xF) {
		case  0: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00A__DOT__mem[adrMem] = valMem; break;
		case  1: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01A__DOT__mem[adrMem] = valMem; break;
		case  2: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02A__DOT__mem[adrMem] = valMem; break;
		case  3: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03A__DOT__mem[adrMem] = valMem; break;
		case  4: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04A__DOT__mem[adrMem] = valMem; break;
		case  5: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05A__DOT__mem[adrMem] = valMem; break;
		case  6: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06A__DOT__mem[adrMem] = valMem; break;
		case  7: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07A__DOT__mem[adrMem] = valMem; break;
		case  8: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08A__DOT__mem[adrMem] = valMem; break;
		case  9: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09A__DOT__mem[adrMem] = valMem; break;
		case 10: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10A__DOT__mem[adrMem] = valMem; break;
		case 11: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11A__DOT__mem[adrMem] = valMem; break;
		case 12: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12A__DOT__mem[adrMem] = valMem; break;
		case 13: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13A__DOT__mem[adrMem] = valMem; break;
		case 14: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14A__DOT__mem[adrMem] = valMem; break;
		case 15: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15A__DOT__mem[adrMem] = valMem; break;
		}
	} else {
		// Bank B for line even.
		switch (x & 0xF) {
		case  0: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00B__DOT__mem[adrMem] = valMem; break;
		case  1: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01B__DOT__mem[adrMem] = valMem; break;
		case  2: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02B__DOT__mem[adrMem] = valMem; break;
		case  3: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03B__DOT__mem[adrMem] = valMem; break;
		case  4: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04B__DOT__mem[adrMem] = valMem; break;
		case  5: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05B__DOT__mem[adrMem] = valMem; break;
		case  6: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06B__DOT__mem[adrMem] = valMem; break;
		case  7: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07B__DOT__mem[adrMem] = valMem; break;
		case  8: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08B__DOT__mem[adrMem] = valMem; break;
		case  9: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09B__DOT__mem[adrMem] = valMem; break;
		case 10: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10B__DOT__mem[adrMem] = valMem; break;
		case 11: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11B__DOT__mem[adrMem] = valMem; break;
		case 12: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12B__DOT__mem[adrMem] = valMem; break;
		case 13: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13B__DOT__mem[adrMem] = valMem; break;
		case 14: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14B__DOT__mem[adrMem] = valMem; break;
		case 15: mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15B__DOT__mem[adrMem] = valMem; break;
		}
	}
#endif
}

void backupFromStencil(VGPU_DDR* mod, u8* refStencil) {
#if  defined(SOURCE_LASTME)
	u8* pBuff= refStencil;
	for (int n=0; n < 32; n++) {
		u8* src = NULL;
		if (!(n & 1)) {
			// Bank A for line odd.
			switch (n>>1) {
			case  0: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00A__DOT__mem; break;
			case  1: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01A__DOT__mem; break;
			case  2: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02A__DOT__mem; break;
			case  3: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03A__DOT__mem; break;
			case  4: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04A__DOT__mem; break;
			case  5: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05A__DOT__mem; break;
			case  6: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06A__DOT__mem; break;
			case  7: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07A__DOT__mem; break;
			case  8: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08A__DOT__mem; break;
			case  9: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09A__DOT__mem; break;
			case 10: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10A__DOT__mem; break;
			case 11: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11A__DOT__mem; break;
			case 12: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12A__DOT__mem; break;
			case 13: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13A__DOT__mem; break;
			case 14: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14A__DOT__mem; break;
			case 15: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15A__DOT__mem; break;
			}
		} else {
			// Bank B for line even.
			switch (n>>1) {
			case  0: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00B__DOT__mem; break;
			case  1: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01B__DOT__mem; break;
			case  2: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02B__DOT__mem; break;
			case  3: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03B__DOT__mem; break;
			case  4: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04B__DOT__mem; break;
			case  5: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05B__DOT__mem; break;
			case  6: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06B__DOT__mem; break;
			case  7: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07B__DOT__mem; break;
			case  8: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08B__DOT__mem; break;
			case  9: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09B__DOT__mem; break;
			case 10: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10B__DOT__mem; break;
			case 11: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11B__DOT__mem; break;
			case 12: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12B__DOT__mem; break;
			case 13: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13B__DOT__mem; break;
			case 14: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14B__DOT__mem; break;
			case 15: src = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15B__DOT__mem; break;
			}
		}
		memcpy(pBuff,src,16384);
		pBuff+=16384;
	}
#endif
}

void backupToStencil(VGPU_DDR* mod, u8* refStencil) {
#if  defined(SOURCE_LASTME)
	u8* pBuff= refStencil;
	for (int n=0; n < 32; n++) {
		u8* dst = NULL;
		if (!(n & 1)) {
			// Bank A for line odd.
			switch (n>>1) {
			case  0: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00A__DOT__mem; break;
			case  1: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01A__DOT__mem; break;
			case  2: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02A__DOT__mem; break;
			case  3: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03A__DOT__mem; break;
			case  4: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04A__DOT__mem; break;
			case  5: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05A__DOT__mem; break;
			case  6: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06A__DOT__mem; break;
			case  7: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07A__DOT__mem; break;
			case  8: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08A__DOT__mem; break;
			case  9: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09A__DOT__mem; break;
			case 10: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10A__DOT__mem; break;
			case 11: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11A__DOT__mem; break;
			case 12: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12A__DOT__mem; break;
			case 13: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13A__DOT__mem; break;
			case 14: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14A__DOT__mem; break;
			case 15: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15A__DOT__mem; break;
			}
		} else {
			// Bank B for line even.
			switch (n>>1) {
			case  0: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache00B__DOT__mem; break;
			case  1: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache01B__DOT__mem; break;
			case  2: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache02B__DOT__mem; break;
			case  3: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache03B__DOT__mem; break;
			case  4: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache04B__DOT__mem; break;
			case  5: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache05B__DOT__mem; break;
			case  6: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache06B__DOT__mem; break;
			case  7: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache07B__DOT__mem; break;
			case  8: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache08B__DOT__mem; break;
			case  9: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache09B__DOT__mem; break;
			case 10: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache10B__DOT__mem; break;
			case 11: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache11B__DOT__mem; break;
			case 12: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache12B__DOT__mem; break;
			case 13: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache13B__DOT__mem; break;
			case 14: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache14B__DOT__mem; break;
			case 15: dst = mod->GPU_DDR__DOT__gpu_inst__DOT__StencilCacheInstance__DOT__RAMCache15B__DOT__mem; break;
			}
		}
		memcpy(dst,pBuff,16384);
		pBuff+=16384;
	}
#endif
}

void loadImageRGB888ToVRAMAsMask(VGPU_DDR* mod, const char* filename, unsigned char* target, int x, int y) {
	// Load PNG
	int w,h,n;
	unsigned char* src = stbi_load(filename, &w, &h, &n, 0);	

	// Transform each pixel RGB888 into a single bit.
	for (int py=0; py < h; py++) {
		int dy = y + py;
		if (dy < 512) {
			for (int px=0; px < w; px++) {
				int dx = x + px;
				if (dx < 1024) {
					int baseSrc = (px+py*w)*3;
					int r = src[baseSrc];
					int g = src[baseSrc+1];
					int b = src[baseSrc+2];

					int v = ((r+g+b) * 76) >> 8;
					bool flagSet = (v >= 128);
					target[((dx+(dy*1024))*2)+1] |= flagSet ? 0x80 : 0x00;

					setStencil(mod,dx,dy,flagSet);
				}
			}
		}
	}

	delete[] src;
}

void loadImageToVRAM(VGPU_DDR* mod, const char* filename, u8* target, int x, int y, bool flagValue) {
	// Load PNG
	int w,h,n;
	unsigned char* src = stbi_load(filename, &w, &h, &n, 0);

	// Transform each pixel RGB888 into a single bit.
	for (int py=0; py < h; py++) {
		int dy = y + py;
		if (dy < 512) {
			for (int px=0; px < w; px++) {
				int dx = x + px;
				if (dx < 1024) {
					int baseSrc = (px+py*w)*3;
					int r = src[baseSrc  ] >> 3;
					int g = src[baseSrc+1] >> 3;
					int b = src[baseSrc+2] >> 3;

					bool otherFlag  = b & 0x10 ? true:false; /* (px & 2) ^ (py & 2) */
					bool flagValue2 = flagValue ? otherFlag : false;

					int baseDst = ((dx+dy*1024)*2);
					target[baseDst  ]  = r | g << 5;
					target[baseDst+1]  = (flagValue2 ? 0x80 : 0x00) | g>>3 | b<<2;

					setStencil(mod,dx,dy,flagValue2);
				}
			}
		}
	}

	delete[] src;
}

void loadImageToVRAMAsCommand(GPUCommandGen& commandGenerator, const char* fileName, int x, int y, bool imgDefaultFlag) {
	// Load PNG
	int w,h,n;
	unsigned char* src = stbi_load(fileName, &w, &h, &n, 0);

	commandGenerator.writeRaw(0xa0000000);
	commandGenerator.writeRaw(x | (y<<16));
	commandGenerator.writeRaw(w | (h<<16));

	int cnt = 0;
	unsigned short prevV = 0;

	for (int py=0; py < h; py++) {
		for (int px=0; px < w; px++) {
			int baseSrc = (px+(py*w))*3;
			int r = src[baseSrc  ] >> 3;
			int g = src[baseSrc+1] >> 3;
			int b = src[baseSrc+2] >> 3;

			bool otherCondition = (px > 128 ? (px&1) : 1);
			unsigned short v = ((imgDefaultFlag & otherCondition)? 0x8000 : 0x0) | r | (g<<5) | (b<<10);
			cnt++;
			if ((cnt & 1) == 0) {
				commandGenerator.writeRaw(v | (prevV<<16));	// 2
			}
			prevV = v;
		}
	}

	if ((cnt & 1) == 1) {
		unsigned short v = 0; // Padding.
		commandGenerator.writeRaw(v | (prevV<<16));	// 2
	}

	// NOP Command
	commandGenerator.writeRaw(0x0);	// 2

	delete[] src;
}

int dumpFrame(VGPU_DDR* mod, const char* name, const char* maskName, unsigned char* buffer, int clockCounter, bool saveMask) {
	static bool first = true;
	static unsigned char* font = NULL;
	if (first) {
		first = false;
		int x;
		int y;
		int n;
		font = stbi_load("Font.png", &x, &y, &n, 0);	
	}

	int errorCount = 0;

	unsigned char* data = new unsigned char[1024*4*512];
	for (int y=0; y < 512; y++) {
		for (int x=0; x < 1024; x++) {
			int adr = (x*2 + y*2048);
			int lsb = buffer[adr];
			int msb = buffer[adr+1];
			int c16 = lsb | (msb<<8);
			int r   = (     c16  & 0x1F);
			int g   = ((c16>>5)  & 0x1F);
			int b   = ((c16>>10) & 0x1F);

			if (x==1 && y==1) { printf("1,1 = %04x\n",c16); }
			if (x==64 && y==1) { printf("64,1 = %04x\n",c16); }
			if (x==1 && y==64) { printf("1,64 = %04x\n",c16); }

			r = (r >> 2) | (r << 3);
			g = (g >> 2) | (g << 3);
			b = (b >> 2) | (b << 3);
			int base = (x + y*1024)*3;
			data[base  ] = r;
			data[base+1] = g;
			data[base+2] = b;
		}
	}

	char str[200];
	itoa(clockCounter,str,10);

	for (int charCnt = 0; charCnt < strlen(str); charCnt++) {
		int ch = str[charCnt];
		int px = (ch & 0xF);
		int py = ((ch>>4) & 0xF);

		unsigned char* charBase = &font[(px*8+py*8*16*8)*3];
		for (int y=0; y < 8; y++) {
			int adrY = (y+512-8) * 1024;
			for (int x=0; x < 8; x++) {
				int baseX = ((x + charCnt*8)+adrY)*3;
				data[baseX  ] = charBase[((x+y*128)*3)  ];
				data[baseX+1] = charBase[((x+y*128)*3)+1];
				data[baseX+2] = charBase[((x+y*128)*3)+2];
			}
		}
	}

	int err = stbi_write_png(name, 1024, 512, 3, data, 1024*3);
	
	if (saveMask) {
		memset(data,0,1024*512*3);

		for (int y=0; y < 512; y++) {
			for (int x=0; x < 1024; x++) {
				int adr = (x*2 + y*2048);
				int base = (x + y*1024)*3;
				bool flag  = buffer[adr+1] & 0x80 ? true : false;
				bool flag2 = false;
				if (mod) { flag2 = ReadStencil(mod,x,y); }
				data[base  ] = flag  ? 0xFF:0x00; // Red  = Is in VRAM but NOT in Stencil !!!
				data[base+1] = flag2 ? 0xFF:0x00;
				data[base+2] = flag2 ? 0xFF:0x00; // Cyan = Is in Stencil but NOT in VRAM Buffer.
				if (flag != flag2) {
					errorCount++;
				}
			}
		}

		for (int charCnt = 0; charCnt < strlen(str); charCnt++) {
			int ch = str[charCnt];
			int px = (ch & 0xF);
			int py = ((ch>>4) & 0xF);

			unsigned char* charBase = &font[(px*8+py*8*16*8)*3];
			for (int y=0; y < 8; y++) {
				int adrY = (y+512-8) * 1024;
				for (int x=0; x < 8; x++) {
					int baseX = ((x + charCnt*8)+adrY)*3;
					data[baseX  ] = charBase[((x+y*128)*3)  ];
					data[baseX+1] = charBase[((x+y*128)*3)+1];
					data[baseX+2] = charBase[((x+y*128)*3)+2];
				}
			}
		}

		stbi_write_png(maskName, 1024, 512, 3, data, 1024*3);
	}
	delete [] data;

	return errorCount;
}
