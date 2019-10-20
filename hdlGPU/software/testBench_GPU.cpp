//----------------------------------------------------------------------------
// Test for full range of values => RGB 16 millions
// Test for all screen space combination (x 0..3, y 0..3)
// Test for dither on/off
// Total 2^29 tests.
//----------------------------------------------------------------------------
#include <stdio.h>
#include "../rtl/obj_dir/Vgpu.h"

#define VCSCANNER_IMPL
#include "../../common_software/VCScanner.h"

#define ASSERT_CHK(cond)		if (!cond) { errorPipeline(); }

void errorPipeline() {
	while (1) {
	}
}

VCScanner*	pScan;
Vgpu*		mod;
int resetSig;

int clockCnt = 0;

void pushPixels();
void cacheLoading();

void clock() {
	mod->clk    = 0;
	mod->eval();
	pScan->eval(clockCnt++);

	mod->i_nrst = resetSig;

	mod->clk    = 1;
	mod->eval();

	mod->eval(); // Propagate signal from CacheLoading / PushPixels along (combinatorial)
	pScan->eval(clockCnt++);
}

/*
	GP1(00h) - Reset GPU
		0-23  Not used (zero)

		Resets the GPU to the following values:
		GP1(01h)      ;clear fifo
		GP1(02h)      ;ack irq (0)
		GP1(03h)      ;display off (1)
		GP1(04h)      ;dma off (0)
		GP1(05h)      ;display address (0)
		GP1(06h)      ;display x1,x2 (x1=200h, x2=200h+256*10)
		GP1(07h)      ;display y1,y2 (y1=010h, y2=010h+240)
		GP1(08h)      ;display mode 320x200 NTSC (0)
		GP0(E1h..E6h) ;rendering attributes (0)

		Accordingly, GPUSTAT becomes 14802000h. The x1,y1 values are too small, ie. the upper-left edge isn't visible. Note that GP1(09h) is NOT affected by the reset command.

	GP1(01h) - Reset Command Buffer
		0-23  Not used (zero)
		Resets the command buffer.

	GP1(02h) - Acknowledge GPU Interrupt (IRQ1)
		0-23  Not used (zero)                                        ;GPUSTAT.24
		Resets the IRQ flag in GPUSTAT.24. The flag can be set via GP0(1Fh).

	GP1(03h) - Display Enable
		0     Display On/Off   (0=On, 1=Off)                         ;GPUSTAT.23
		1-23  Not used (zero)

		Turns display on/off. "Note that a turned off screen still gives the flicker of NTSC on a PAL screen if NTSC mode is selected."
		The "Off" settings displays a black picture (and still sends /SYNC signals to the television set). (Unknown if it still generates vblank IRQs though?)

	GP1(04h) - DMA Direction / Data Request
		0-1  DMA Direction (0=Off, 1=FIFO, 2=CPUtoGP0, 3=GPUREADtoCPU) ;GPUSTAT.29-30
		2-23 Not used (zero)

		Notes: Manually sending/reading data by software (non-DMA) is ALWAYS possible, regardless of the GP1(04h) setting. The GP1(04h) setting does affect the meaning of GPUSTAT.25.

		Display start/end
		Specifies where the display area is positioned on the screen, and how much data gets sent to the screen. The screen sizes of the display area are valid only if the horizontal/vertical start/end values are default. By changing these you can get bigger/smaller display screens. On most TV's there is some black around the edge, which can be utilised by setting the start of the screen earlier and the end later. The size of the pixels is NOT changed with these settings, the GPU simply sends more data to the screen. Some monitors/TVs have a smaller display area and the extended size might not be visible on those sets. "(Mine is capable of about 330 pixels horizontal, and 272 vertical in 320*240 mode)"

	GP1(05h) - Start of Display area (in VRAM)
		0-9   X (0-1023)    (halfword address in VRAM)  (relative to begin of VRAM)
		10-18 Y (0-511)     (scanline number in VRAM)   (relative to begin of VRAM)
		19-23 Not used (zero)
		Upper/left Display source address in VRAM. The size and target position on screen is set via Display Range registers; target=X1,Y2; size=(X2-X1/cycles_per_pix), (Y2-Y1).

	GP1(06h) - Horizontal Display range (on Screen)
		0-11   X1 (260h+0)       ;12bit       ;\counted in 53.222400MHz units,
		12-23  X2 (260h+320*8)   ;12bit       ;/relative to HSYNC

		Specifies the horizontal range within which the display area is displayed. For resolutions other than 320 pixels it may be necessary to fine adjust the value to obtain an exact match (eg. X2=X1+pixels*cycles_per_pix).
		The number of displayed pixels per line is "(((X2-X1)/cycles_per_pix)+2) AND NOT 3" (ie. the hardware is rounding the width up/down to a multiple of 4 pixels).
		Most games are using a width equal to the horizontal resolution (ie. 256, 320, 368, 512, 640 pixels). A few games are using slightly smaller widths (probably due to programming bugs). Pandemonium 2 is using a bigger "overscan" width (ensuring an intact picture without borders even on mis-calibrated TV sets).
		The 260h value is the first visible pixel on normal TV Sets, this value is used by MOST NTSC games, and SOME PAL games (see below notes on Mis-Centered PAL games).

	GP1(07h) - Vertical Display range (on Screen)
		0-9   Y1 (NTSC=88h-(224/2), (PAL=A3h-(264/2))  ;\scanline numbers on screen,
		10-19 Y2 (NTSC=88h+(224/2), (PAL=A3h+(264/2))  ;/relative to VSYNC
		20-23 Not used (zero)

		Specifies the vertical range within which the display area is displayed. The number of lines is Y2-Y1 (unlike as for the width, there's no rounding applied to the height). If Y2 is set to a much too large value, then the hardware stops to generate vblank interrupts (IRQ0).
		The 88h/A3h values are the middle-scanlines on normal TV Sets, these values are used by MOST NTSC games, and SOME PAL games (see below notes on Mis-Centered PAL games).
		The 224/264 values are for fullscreen pictures. Many NTSC games display 240 lines (overscan with hidden lines). Many PAL games display only 256 lines (underscan with black borders).

	GP1(08h) - Display mode
		0-1   Horizontal Resolution 1     (0=256, 1=320, 2=512, 3=640) ;GPUSTAT.17-18
		2     Vertical Resolution         (0=240, 1=480, when Bit5=1)  ;GPUSTAT.19
		3     Video Mode                  (0=NTSC/60Hz, 1=PAL/50Hz)    ;GPUSTAT.20
		4     Display Area Color Depth    (0=15bit, 1=24bit)           ;GPUSTAT.21
		5     Vertical Interlace          (0=Off, 1=On)                ;GPUSTAT.22
		6     Horizontal Resolution 2     (0=256/320/512/640, 1=368)   ;GPUSTAT.16
		7     "Reverseflag"               (0=Normal, 1=Distorted)      ;GPUSTAT.14
		8-23  Not used (zero)
*/
struct command {
	u8	adress;
	u32 command;
};
command commandArray[] = {
// GP	Value
//	{ 1,	0x00000000	},		// Reset GPU State.
	/*
	{ 1,	0x03000000	},		// Display On
	{ 1,	0x03000001	},		// Display Off
	{ 1,	0x04000000	},		// DMA Direction Off
	{ 1,	0x04000001	},		// DMA Direction FIFO
	{ 1,	0x04000002	},		// DMA Direction CPUtoGP0
	{ 1,	0x04000003	},		// DMA Direction GPUReadToCPU
	{ 1,	0x04000000	},		// DMA Direction Off
	{ 1,	0x0501247B	},		// X=123, Y=73 Start Display Area
	{ 1,	0x06F23821	},		// X1=0x821 X2=0xF23
	{ 1,	0x07000000 | (123<<10) | (17) },	// Y1=17  Y2=123
	{ 1,	0x08000000  },
	{ 1,	0x08000003  },
	{ 1,	0x08000000 | (1<<2)  },	// Hirez Vert without interlace.
	{ 1,	0x08000000 | (1<<2) | (1<<5) }, // Hirez Vert with interlace.
	{ 1,	0x08000000 | (1<<3) | (1<<4) | (1<<6) | (1<<7) },
	{ 1,	0x08000000  },
	*/
	
	//
	// Test 00..1F [Done]
	// Test 20..2F
	// Test 30..3F
	// Test 40..4F
	// Test 50..5F
	// Test 60..6F
	// Test 70..7F
	// Test 80..8F
	// Test 90..9F
	//
	//
	/*
	{ 0,    0x01000000 },
	{ 0,    0x01000000 },	// Reset Cache
	{ 0,    0x02AABBCC },	// Fill VRAM
		{ 0,    0x02AA7BB7 },	// Top Left
		{ 0,    0x02DD6CC6 },	// Width/Height
	{ 0,    0x03000000 },
	{ 0,    0x04000000 },
	{ 0,    0x05000000 },
	{ 0,    0x06000000 },
	{ 0,    0x07000000 },
	{ 0,    0x08000000 },
	{ 0,    0x09000000 },
	{ 0,    0x0A000000 },
	{ 0,    0x0B000000 },
	{ 0,    0x0C000000 },
	{ 0,    0x0D000000 },
	{ 0,    0x0E000000 },
	{ 0,    0x0F000000 },
	{ 0,    0x10000000 },
	{ 0,    0x11000000 },
	{ 0,    0x12000000 },
	{ 0,    0x13000000 },
	{ 0,    0x14000000 },
	{ 0,    0x15000000 },
	{ 0,    0x16000000 },
	{ 0,    0x17000000 },
	{ 0,    0x18000000 },
	{ 0,    0x19000000 },
	{ 0,    0x1A000000 },
	{ 0,    0x1B000000 },
	{ 0,    0x1C000000 },
	{ 0,    0x1D000000 },
	{ 0,    0x1E000000 },
	{ 0,    0x1F000000 },
	*/
	/*
		C = Command
		V = Load Vertex
		T = Load Texture Info
		L = Load coLors.
		* = Emit Primitive
	*/
#if 0
	// CVVV*
	{ 0,    0x20AABBCC },		// Polygon, 3 pts, opaque
		{ 0,    0x00110001 },
		{ 0,    0x00320022 },
		{ 0,    0x00530043 },
	{ 0,    0x21AABBCC },		// Polygon, 3 pts, opaque ( texture-blending disabled over non textured...)
		{ 0,    0x00110001 },
		{ 0,    0x00320022 },
		{ 0,    0x00530043 },
	{ 0,    0x22AABBCC },		// Polygon, 3 pts, semi transp
		{ 0,    0x00110001 },
		{ 0,    0x00320022 },
		{ 0,    0x00530043 },
	{ 0,    0x23AABBCC },		// Polygon, 3 pts, semi transp ( texture-blending disabled over non textured...)
		{ 0,    0x00110001 },
		{ 0,    0x00320022 },
		{ 0,    0x00530043 },
	// CVTVTVT*
	{ 0,    0x24AABBCC },		// Polygon, 3 pts, opaque, texture blending
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	{ 0,    0x25AABBCC },		// Polygon, 3 pts, opaque, raw texture
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	{ 0,    0x26AABBCC },		// Polygon, 3 pts, semi, texture blending
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	{ 0,    0x27AABBCC },		// Polygon, 3 pts, semi, raw texture
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	// CVVV*V*
	{ 0,    0x28AABBCC },		// Polygon, 4 pts, opaque
		{ 0,    0x00910081 },
		{ 0,    0x00B200A2 },
		{ 0,    0x00D300C3 },
		{ 0,    0xFFF3FFE3 },
	{ 0,    0x29AABBCC },		// Polygon, 4 pts, opaque ( texture-blending disabled over non textured...)
		{ 0,    0x00910081 },
		{ 0,    0x00B200A2 },
		{ 0,    0x00D300C3 },
		{ 0,    0xFFF3FFE3 },
	{ 0,    0x2AAABBCC },		// Polygon, 4 pts, semi transp
		{ 0,    0x00910081 },
		{ 0,    0x00B200A2 },
		{ 0,    0x00D300C3 },
		{ 0,    0xFFF3FFE3 },
	{ 0,    0x2BAABBCC },		// Polygon, 4 pts, semi transp ( texture-blending disabled over non textured...)
		{ 0,    0x00910081 },
		{ 0,    0x00B200A2 },
		{ 0,    0x00D300C3 },
		{ 0,    0xFFF3FFE3 },

	// CVTVTVT*VT*
	{ 0,    0x2CAABBCC },		// Polygon, 4 pts, opaque, texture blending
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
		{ 0,    0x00740064 },
		{ 0,    0xFFFAF5F9 },
	{ 0,    0x2DAABBCC },		// Polygon, 4 pts, opaque, raw texture
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
		{ 0,    0x00740064 },
		{ 0,    0xFFFAF5F9 },
	{ 0,    0x2EAABBCC },		// Polygon, 4 pts, semi, texture blending
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
		{ 0,    0x00740064 },
		{ 0,    0xFFFAF5F9 },
	{ 0,    0x2FAABBCC },		// Polygon, 4 pts, semi, raw texture
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
		{ 0,    0x00740064 },
		{ 0,    0xFFFAF5F9 },

	// CVLVLV*
	{ 0,    0x30AABBCC },		// Polygon, 3 pts, opaque
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFA2B1C0 },	// L
		{ 0,    0x00320022 },	// V
		{ 0,    0xFEA5B4C3 },	// L
		{ 0,    0x00530043 },	// V
	{ 0,    0x31AABBCC },		// Polygon, 3 pts, opaque ( texture-blending disabled over non textured...)
		{ 0,    0x00110001 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
	{ 0,    0x32AABBCC },		// Polygon, 3 pts, semi transp
		{ 0,    0x00110001 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
	{ 0,    0x33AABBCC },		// Polygon, 3 pts, semi transp ( texture-blending disabled over non textured...)
		{ 0,    0x00110001 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
	// CVTLVTLVT*
	{ 0,    0x34AABBCC },		// Polygon, 3 pts, opaque, texture blending
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	{ 0,    0x35AABBCC },		// Polygon, 3 pts, opaque, raw texture
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	{ 0,    0x36AABBCC },		// Polygon, 3 pts, semi, texture blending
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	{ 0,    0x37AABBCC },		// Polygon, 3 pts, semi, raw texture
		{ 0,    0x00110001 },
		{ 0,    0xFFF3F2F1 },
		{ 0,    0xFFA2B1C0 },
		{ 0,    0x00320022 },
		{ 0,    0xFFF6F5F4 },
		{ 0,    0xFEA5B4C3 },
		{ 0,    0x00530043 },
		{ 0,    0xFFF8F5F7 },
	// CVLVLV*LV*
	{ 0,    0x38AABBCC },		// Polygon, 4 pts, semi transp
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFA2B1C0 },	// L
		{ 0,    0x00320022 },	// V
		{ 0,    0xFEA5B4C3 },	// L
		{ 0,    0x00530043 },	// V
		{ 0,    0xFEA5B4C4 },	// L
		{ 0,    0x00770064 },	// V
	{ 0,    0x39AABBCC },		// Polygon, 4 pts, semi transp
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFA2B1C0 },	// L
		{ 0,    0x00320022 },	// V
		{ 0,    0xFEA5B4C3 },	// L
		{ 0,    0x00530043 },	// V
		{ 0,    0xFEA5B4C4 },	// L
		{ 0,    0x00770064 },	// V
	{ 0,    0x3AAABBCC },		// Polygon, 4 pts, semi transp
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFA2B1C0 },	// L
		{ 0,    0x00320022 },	// V
		{ 0,    0xFEA5B4C3 },	// L
		{ 0,    0x00530043 },	// V
		{ 0,    0xFEA5B4C4 },	// L
		{ 0,    0x00770064 },	// V
	{ 0,    0x3BAABBCC },		// Polygon, 4 pts, semi transp ( texture-blending disabled over non textured...)
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFA2B1C0 },	// L
		{ 0,    0x00320022 },	// V
		{ 0,    0xFEA5B4C3 },	// L
		{ 0,    0x00530043 },	// V
		{ 0,    0xFEA5B4C4 },	// L
		{ 0,    0x00770064 },	// V

	// CVTLVTLVT*LVT*
	{ 0,    0x3CAABBCC },		// Polygon, 4 pts, opaque, texture blending
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFF3F2F1 },	// T
		{ 0,    0xFFA2B1C0 },	// C
		{ 0,    0x00320022 },	// V
		{ 0,    0xFFF6F5F4 },	// T
		{ 0,    0xFEA5B4C3 },	// C
		{ 0,    0x00530043 },	// V
		{ 0,    0xFFF9F8F7 },	// T
		{ 0,    0xFDA8B7C6 },	// C
		{ 0,    0x00740064 },	// V
		{ 0,    0xFFFCFBFA },	// T
	{ 0,    0x3DAABBCC },		// Polygon, 4 pts, opaque, raw texture
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFF3F2F1 },	// T
		{ 0,    0xFFA2B1C0 },	// C
		{ 0,    0x00320022 },	// V
		{ 0,    0xFFF6F5F4 },	// T
		{ 0,    0xFEA5B4C3 },	// C
		{ 0,    0x00530043 },	// V
		{ 0,    0xFFF9F8F7 },	// T
		{ 0,    0xFDA8B7C6 },	// C
		{ 0,    0x00740064 },	// V
		{ 0,    0xFFFCFBFA },	// T
	{ 0,    0x3EAABBCC },		// Polygon, 4 pts, semi, texture blending
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFF3F2F1 },	// T
		{ 0,    0xFFA2B1C0 },	// C
		{ 0,    0x00320022 },	// V
		{ 0,    0xFFF6F5F4 },	// T
		{ 0,    0xFEA5B4C3 },	// C
		{ 0,    0x00530043 },	// V
		{ 0,    0xFFF9F8F7 },	// T
		{ 0,    0xFDA8B7C6 },	// C
		{ 0,    0x00740064 },	// V
		{ 0,    0xFFFCFBFA },	// T
	{ 0,    0x3FAABBCC },		// Polygon, 4 pts, semi, raw texture
		{ 0,    0x00110001 },	// V
		{ 0,    0xFFF3F2F1 },	// T
		{ 0,    0xFFA2B1C0 },	// C
		{ 0,    0x00320022 },	// V
		{ 0,    0xFFF6F5F4 },	// T
		{ 0,    0xFEA5B4C3 },	// C
		{ 0,    0x00530043 },	// V
		{ 0,    0xFFF9F8F7 },	// T
		{ 0,    0xFDA8B7C6 },	// C
		{ 0,    0x00740064 },	// V
		{ 0,    0xFFFCFBFA },	// T
#endif
	{0,	0x02AABBCC},		// FILL RECT
		{ 0, 0xAAAACCCC },
		{ 0, 0x11112222 },

	{0, 0x80AABBCC},		// VRAM to VRAM
		{ 0, 0xAAAACCCC },
		{ 0, 0x11112222 },
		{ 0, 0x33334444 },
	{0, 0xA0AABBCC},		// CPU to VRAM
		{ 0, 0xAAAACCCC },
		{ 0, 0x00010002 },
		{ 0, 0x33334444 },
	{0, 0xC0AABBCC},		// VRAM to CPU
		{ 0, 0xAAAACCCC },
		{ 0, 0x00010002 },
		{ 0, 0x33334444 },


	{0, 0x80AABBCC},
		{ 0, 0xAAAACCCC },
		{ 0, 0x11112222 },


	/*
	// CVV*
	{0, 0x40080808},	// 40/41/42/43/44/45/46/47
		{0, 0x00010002},
		{0, 0x00040003},
	*/
	// CVV*V*...V*S
	{0, 0x48080808},	// 48/49/4A/4B/4C/4D/4E/4F
		{0, 0x00010002},
		{0, 0x00040003},	// Line 1
		{0, 0x00060005},	// Line 2
		{0, 0x50005000},	// [Stop]

	// CVLV*
	{0, 0x50080808},	// 50/51/52/53/54/55/56/57
		{0, 0x00010002}, // XY
		{0, 0x00AABBCC}, // COL
		{0, 0x00040003}, // XY

	// CVLV*LV*...LV*S
	{0, 0x58080808},	// 58/59/5A/5B/5C/5D/5E/5F
		{0, 0x00010002}, // XY
		{0, 0x00AABBCC}, // COL
		{0, 0x00040003}, // XY
		{0, 0x00DDEEFF}, // COL
		{0, 0x00060005}, // XY
		{0, 0x00112233}, // COL
		{0, 0x00080007}, // XY
		{0, 0x50005000}, // COL
#if 0
	/*
	GP0(60h) -  (opaque)
	61
	GP0(62h) - Monochrome Rectangle (variable size) (semi-transparent)
	63
	(3rd) Width+Height      (YsizXsizh) (variable size only) (max 1023x511)
	*/
	// Monochrome Rectangle (variable size)
	{0, 0x60080808}, // 61/62/63
	{0, 0x00010002},
	{0, 0x001F003F},

	{0, 0x61080808},
	{0, 0x00010002},
	{0, 0x001F003F},

	{0, 0x62080808},
	{0, 0x00010002},
	{0, 0x001F003F},

	{0, 0x63080808},
	{0, 0x00010002},
	{0, 0x001F003F},

	/*
	GP0(68h) - Monochrome Rectangle (1x1) (Dot) (opaque)
	69
	GP0(6Ah) - Monochrome Rectangle (1x1) (Dot) (semi-transparent)
	6B
	GP0(70h) - Monochrome Rectangle (8x8) (opaque)
	71
	GP0(72h) - Monochrome Rectangle (8x8) (semi-transparent)
	73
	GP0(78h) - Monochrome Rectangle (16x16) (opaque)
	79
	GP0(7Ah) - Monochrome Rectangle (16x16) (semi-transparent)
	7B

	1st  Color+Command     (CcBbGgRrh)
	2nd  Vertex            (YyyyXxxxh)
	*/

	{0, 0x68080808},	// 69/6A/6B/70/71/72/73/78/79/7A/7B
		{0, 0x00010002},

	{0, 0x69080808},
		{0, 0x00010002},

	{0, 0x6A080808},
		{0, 0x00010002},

	{0, 0x6B080808},
		{0, 0x00010002},

	{0, 0x70080808},
		{0, 0x00010002},

	{0, 0x71080808},
		{0, 0x00010002},

	{0, 0x72080808},
		{0, 0x00010002},

	{0, 0x73080808},
		{0, 0x00010002},

	{0, 0x78080808},
		{0, 0x00010002},

	{0, 0x79080808},
		{0, 0x00010002},

	{0, 0x7A080808},
		{0, 0x00010002},

	{0, 0x7B080808},
		{0, 0x00010002},

	/*
	GP0(64h) - Textured Rectangle, variable size, opaque, texture-blending
	GP0(65h) - Textured Rectangle, variable size, opaque, raw-texture
	GP0(66h) - Textured Rectangle, variable size, semi-transp, texture-blending
	GP0(67h) - Textured Rectangle, variable size, semi-transp, raw-texture
	(4th) Width+Height      (YsizXsizh) (variable size only) (max 1023x511)
	*/

	{0, 0x64080808},	// 65/66/67
		{0, 0x00010002},
		{0, 0xCCCCDDEE},
		{0, 0x001F003F},

	{0, 0x65080808},
		{0, 0x00010002},
		{0, 0xCCCCDDEE},
		{0, 0x001F003F},

	{0, 0x66080808},
		{0, 0x00010002},
		{0, 0xCCCCDDEE},
		{0, 0x001F003F},

	{0, 0x67080808},
		{0, 0x00010002},
		{0, 0xCCCCDDEE},
		{0, 0x001F003F},

	/*
	GP0(6Ch) - Textured Rectangle, 1x1 (nonsense), opaque, texture-blending
	GP0(6Dh) - Textured Rectangle, 1x1 (nonsense), opaque, raw-texture
	GP0(6Eh) - Textured Rectangle, 1x1 (nonsense), semi-transp, texture-blending
	GP0(6Fh) - Textured Rectangle, 1x1 (nonsense), semi-transp, raw-texture
	GP0(74h) - Textured Rectangle, 8x8, opaque, texture-blending
	GP0(75h) - Textured Rectangle, 8x8, opaque, raw-texture
	GP0(76h) - Textured Rectangle, 8x8, semi-transparent, texture-blending
	GP0(77h) - Textured Rectangle, 8x8, semi-transparent, raw-texture
	GP0(7Ch) - Textured Rectangle, 16x16, opaque, texture-blending
	GP0(7Dh) - Textured Rectangle, 16x16, opaque, raw-texture
	GP0(7Eh) - Textured Rectangle, 16x16, semi-transparent, texture-blending
	GP0(7Fh) - Textured Rectangle, 16x16, semi-transparent, raw-texture

	1st  Color+Command     (CcBbGgRrh) (color is ignored for raw-textures)
	2nd  Vertex            (YyyyXxxxh) (upper-left edge of the rectangle)
	3rd  Texcoord+Palette  (ClutYyXxh) (for 4bpp Textures Xxh must be even!)
	*/

	{0, 0x6C080808},	// 6D/6E/6F/74/75/76/77/7C/7D/7E/7F
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x6D080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x6E080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x6F080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x74080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x75080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x76080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x77080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x7C080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x7D080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x7E080808},	
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},

	{0, 0x7F080808},
		{0, 0x00010002},	
		{0, 0xCCCCDDEE},
#endif
#if 0
	// E0~FF except E1~E6
	{0, 0xE0000000},
	{0, 0xE7000000},
	{0, 0xE8000000},
	{0, 0xE9000000},
	{0, 0xEA000000},
	{0, 0xEB000000},
	{0, 0xEC000000},
	{0, 0xED000000},
	{0, 0xEE000000},
	{0, 0xEF000000},
	{0, 0xF0000000},
	{0, 0xF1000000},
	{0, 0xF2000000},
	{0, 0xF3000000},
	{0, 0xF4000000},
	{0, 0xF5000000},
	{0, 0xF6000000},
	{0, 0xF7000000},
	{0, 0xF8000000},
	{0, 0xF9000000},
	{0, 0xFA000000},
	{0, 0xFB000000},
	{0, 0xFC000000},
	{0, 0xFD000000},
	{0, 0xFE000000},
	{0, 0xFF000000},
	// E1-E6
	{0, 0xE100FFFF},
	{0, 0xE20FFFFF},
	{0, 0xE3FFFFFF},
	{0, 0xE4FFFFFF},
	{0, 0xE5FFFFFF},
	{0, 0xE6000001},
	{0, 0xE6000010},
	{0, 0xE6000000},
#endif


	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },
	{ 0,    0x0000FFFF },

	{ 0,    0x0000FFFF },
	{ 0,    0x07000000 },
	{ 0,    0x07000000 },
	{ 0,    0x07000000 },
	{ 0,    0x07000000 },

};

int commandCount = 0;
int waitCycle    = 1;

void pushCommands() {
	static int currCycleCount = 0;

	if (commandCount < (sizeof(commandArray) / sizeof(command)) && (currCycleCount == 0)) {
		mod->gpuAdrA2	= commandArray[commandCount].adress;
		mod->gpuSel		= 1;
		if (mod->ack) {
			mod->write		= 1;
			mod->cpuDataIn	= commandArray[commandCount++].command;
		} else {
			mod->write		= 0;
			mod->cpuDataIn	= 0xDEADBEEF;
		}
	} else {
		mod->write		= 0;
		mod->gpuAdrA2	= 0;
		mod->gpuSel		= 0;
		mod->cpuDataIn = 0xCDCDCDCD;
	}
	currCycleCount++;
	if (currCycleCount == waitCycle) {
		currCycleCount = 0;
	}
}

enum STATE {
	DEFAULT_STATE		= 0,
	LOAD_COMMAND		= 1,
	COLOR_LOAD			= 2,
	VERTEX_LOAD			= 3,
	UV_LOAD				= 4,
	WIDTH_HEIGHT_STATE	= 5,
	LOAD_XY1			= 6,
	LOAD_XY2			= 7,
	WAIT_COMMAND_COMPLETE =  8
};

enum WORK_STATE {
	NOT_WORKING_DEFAULT_STATE = 0,
	LINE_START = 1,
	// LINE_DRAW = 4'd2, LINE_END = 4'd3,
	RECT_START = 4,
	FILL_START = 5,
	COPY_START = 6,
	TRIANGLE_START = 7,
	/*
	TMP_1 = 4'd8,
	TMP_2 = 4'd9,
	TMP_3 = 4'd10,
	TMP_4 = 4'd11;
	*/
};

void checkGPUState() {
	static int cycleCount = 0;
	printf("@%i ", cycleCount++);
	switch ((STATE)mod->gpu__DOT__currState) {
	case DEFAULT_STATE:			printf("DEFAULT_STATE "); break;
	case LOAD_COMMAND:			printf("LOAD_COMMAND [0x%x]", mod->gpu__DOT__command); break;
	case COLOR_LOAD:			printf("  COLOR_LOAD (L:%i Value:%x) ",mod->gpu__DOT__loadRGB,mod->gpu__DOT__fifoDataOut); break;
	case VERTEX_LOAD:			if (mod->gpu__DOT__loadVertices) { printf("  VERTEX_LOAD "); } else { printf("  (VERTEX LOAD WAIT COMPLETE) "); } 
								printf("(L:%i Value:%x) ",mod->gpu__DOT__loadVertices,mod->gpu__DOT__fifoDataOut);
								break;
	case UV_LOAD:				if (mod->gpu__DOT__loadUV) { printf("  UV_LOAD (L:%i Value:%x) ",mod->gpu__DOT__loadUV,mod->gpu__DOT__fifoDataOut);  } else { printf("  (UV LOAD WAIT COMPLETE) "); } break;
	case WIDTH_HEIGHT_STATE:	printf("  WIDTH_HEIGHT_STATE (L:%i Value:%x) ",mod->gpu__DOT__loadSize,mod->gpu__DOT__fifoDataOut); break;
	case LOAD_XY1:				printf("  LOAD_XY1 "); break;
	case LOAD_XY2:				printf("  LOAD_XY2 "); break;
	case WAIT_COMMAND_COMPLETE:	printf("  WAIT_COMMAND_COMPLETE "); break;
	}

	switch ((WORK_STATE)mod->gpu__DOT__currWorkState) {
	case LINE_START: printf("LINE START "); break;
	case RECT_START: printf("RECT START "); break;
	case FILL_START: printf("FILL START "); break;
	case COPY_START: printf("COPY START "); break;
	case TRIANGLE_START: printf("TRIANGLE START "); break;
	case NOT_WORKING_DEFAULT_STATE: break;
	default: printf("(FAKE) PRIMITIVE RENDER... "); break;
	}
	printf("\n");
}

int testGPU() {
	//
	// This module is pure combinatorial computation, no clock needed.
	//
	pScan = new VCScanner();
	pScan->init(500); // TODO : MUST TURN API ATOMIC.

	mod = new Vgpu();

	#define MODULE mod
	#define SCAN   pScan

	#define VL_IN(NAME,size,s2)			SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIGA(NAME,size,s2,cnt)	SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_IN8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_IN16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_IN64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_OUT64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIG64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
	#define VL_SIGW(NAME,size,s2,storageSize,depth)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME,depth, (((u8*)& MODULE ->## NAME[1]) - ((u8*)& MODULE ->## NAME[0])));

	{
		// PORTS
		// The application code writes and reads these signals to
		// propagate new values into/out from the Verilated model.
		// Begin mtask footprint  all: 
		VL_IN8(clk,0,0);
		VL_IN8(i_nrst,0,0);
		VL_IN8(gpuAdrA2,0,0);
		VL_IN8(gpuSel,0,0);
		VL_OUT8(ack,0,0);
		VL_OUT8(IRQRequest,0,0);
		VL_IN8(write,0,0);
		VL_IN8(read,0,0);
		VL_IN(cpuDataIn,31,0);
		VL_OUT(cpuDataOut,31,0);

		// LOCAL SIGNALS
		// Internals; generally not touched by application code
		// Begin mtask footprint  all: 
		VL_SIG8(gpu__DOT__clk,0,0);
		VL_SIG8(gpu__DOT__i_nrst,0,0);
		VL_SIG8(gpu__DOT__gpuAdrA2,0,0);
		VL_SIG8(gpu__DOT__gpuSel,0,0);
		VL_SIG8(gpu__DOT__ack,0,0);
		VL_SIG8(gpu__DOT__IRQRequest,0,0);
		VL_SIG8(gpu__DOT__write,0,0);
		VL_SIG8(gpu__DOT__writeFifo,0,0);
		VL_SIG8(gpu__DOT__writeGP1,0,0);
		VL_SIG8(gpu__DOT__isFifoFull,0,0);
		VL_SIG8(gpu__DOT__isFifoEmpty,0,0);
		VL_SIG8(gpu__DOT__isFifoNotEmpty,0,0);
		VL_SIG8(gpu__DOT__rstInFIFO,0,0);
		VL_SIG8(gpu__DOT__gpuReadyReceiveDMA,0,0);
		VL_SIG8(gpu__DOT__gpuReadySendToCPU,0,0);
		VL_SIG8(gpu__DOT__gpuReceiveCmdReady,0,0);
		VL_SIG8(gpu__DOT__dmaDataRequest,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_TexBasePageX,3,0);
		VL_SIG8(gpu__DOT__GPU_REG_TexBasePageY,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_Transparency,1,0);
		VL_SIG8(gpu__DOT__GPU_REG_TexFormat,1,0);
		VL_SIG8(gpu__DOT__GPU_REG_DitherOn,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_DrawDisplayAreaOn,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_TextureDisable,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_TextureXFlip,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_TextureYFlip,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_WindowTextureMaskX,4,0);
		VL_SIG8(gpu__DOT__GPU_REG_WindowTextureMaskY,4,0);
		VL_SIG8(gpu__DOT__GPU_REG_WindowTextureOffsetX,4,0);
		VL_SIG8(gpu__DOT__GPU_REG_WindowTextureOffsetY,4,0);
		VL_SIG8(gpu__DOT__GPU_REG_ForcePixel15MaskSet,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_CheckMaskBit,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_IRQSet,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_DisplayDisabled,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_IsInterlaced,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_BufferRGB888,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_VideoMode,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_VerticalResolution,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_HorizResolution,1,0);
		VL_SIG8(gpu__DOT__GPU_REG_HorizResolution368,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_DMADirection,1,0);
		VL_SIG8(gpu__DOT__GPU_REG_ReverseFlag,0,0);
		VL_SIG8(gpu__DOT__GPU_DisplayEvenOddLinesInterlace,0,0);
		VL_SIG8(gpu__DOT__GPU_REG_CurrentInterlaceField,0,0);
		VL_SIG8(gpu__DOT__fifoDataOutUR,7,0);
		VL_SIG8(gpu__DOT__fifoDataOutVG,7,0);
		VL_SIG8(gpu__DOT__fifoDataOutB,7,0);
		VL_SIG8(gpu__DOT__command,7,0);
		VL_SIG8(gpu__DOT__RegCommand,7,0);
		VL_SIG8(gpu__DOT__FifoDataValid,0,0);
		VL_SIG8(gpu__DOT__cmdGP1,0,0);
		VL_SIG8(gpu__DOT__rstGPU,0,0);
		VL_SIG8(gpu__DOT__rstCmd,0,0);
		VL_SIG8(gpu__DOT__rstIRQ,0,0);
		VL_SIG8(gpu__DOT__setDisp,0,0);
		VL_SIG8(gpu__DOT__setDmaDir,0,0);
		VL_SIG8(gpu__DOT__setDispArea,0,0);
		VL_SIG8(gpu__DOT__setDispRangeX,0,0);
		VL_SIG8(gpu__DOT__setDispRangeY,0,0);
		VL_SIG8(gpu__DOT__setDisplayMode,0,0);
		VL_SIG8(gpu__DOT__getGPUInfo,0,0);
		VL_SIG8(gpu__DOT__bIsPolyCommand,0,0);
		VL_SIG8(gpu__DOT__bIsRectCommand,0,0);
		VL_SIG8(gpu__DOT__bIsLineCommand,0,0);
		VL_SIG8(gpu__DOT__bIsForECommand,0,0);
		VL_SIG8(gpu__DOT__bIsCopyVVCommand,0,0);
		VL_SIG8(gpu__DOT__bIsCopyCVCommand,0,0);
		VL_SIG8(gpu__DOT__bIsCopyVCCommand,0,0);
		VL_SIG8(gpu__DOT__bIsFillCommand,0,0);
		VL_SIG8(gpu__DOT__bIsBase0x,0,0);
		VL_SIG8(gpu__DOT__bIsBase01,0,0);
		VL_SIG8(gpu__DOT__bIsBase02,0,0);
		VL_SIG8(gpu__DOT__bIsBase1F,0,0);
		VL_SIG8(gpu__DOT__bIsTerminator,0,0);
//		VL_SIG8(gpu__DOT__bEndLine,0,0);
//		VL_SIG8(gpu__DOT__bIsValidVertex,0,0);
		VL_SIG8(gpu__DOT__bIsPrimitiveLoaded,0,0);
		VL_SIG8(gpu__DOT__bIsRenderAttrib,0,0);
		VL_SIG8(gpu__DOT__bIsNop,0,0);
		VL_SIG8(gpu__DOT__bIsPolyOrRect,0,0);
		VL_SIG8(gpu__DOT__bIgnoreColor,0,0);
		VL_SIG8(gpu__DOT__bSemiTransp,0,0);
		VL_SIG8(gpu__DOT__bUseTexture,0,0);
		VL_SIG8(gpu__DOT__bIs4PointPoly,0,0);
		VL_SIG8(gpu__DOT__bIsMultiLine,0,0);
		VL_SIG8(gpu__DOT__bIsPerVtxCol,0,0);
		VL_SIG8(gpu__DOT__bNoTexture,0,0);
		VL_SIG8(gpu__DOT__bDither,0,0);
		VL_SIG8(gpu__DOT__bOpaque,0,0);
		VL_SIG8(gpu__DOT__rejectVertex,0,0);
		VL_SIG8(gpu__DOT__resetReject,0,0);
		VL_SIG8(gpu__DOT__rejectPrimitive,0,0);
		VL_SIG8(gpu__DOT__RegU0,7,0);
		VL_SIG8(gpu__DOT__RegV0,7,0);
		VL_SIG8(gpu__DOT__RegU1,7,0);
		VL_SIG8(gpu__DOT__RegV1,7,0);
		VL_SIG8(gpu__DOT__RegU2,7,0);
		VL_SIG8(gpu__DOT__RegV2,7,0);
		VL_SIG8(gpu__DOT__vertCnt,1,0);
//		VL_SIG8(gpu__DOT__canOutputTriangle,0,0);
		VL_SIG8(gpu__DOT__isPolyFinalVertex,0,0);
		VL_SIG8(gpu__DOT__bNotFirstVert,0,0);
		VL_SIG8(gpu__DOT__resetVertexCounter,0,0);
		VL_SIG8(gpu__DOT__increaseVertexCounter,0,0);
		VL_SIG8(gpu__DOT__loadRGB,0,0);
		VL_SIG8(gpu__DOT__loadUV,0,0);
		VL_SIG8(gpu__DOT__loadVertices,0,0);
		VL_SIG8(gpu__DOT__loadAllRGB,0,0);
		VL_SIG8(gpu__DOT__storeCommand,0,0);
		VL_SIG8(gpu__DOT__loadE5Offsets,0,0);
		VL_SIG8(gpu__DOT__loadTexPageE1,0,0);
		VL_SIG8(gpu__DOT__loadTexWindowSetting,0,0);
		VL_SIG8(gpu__DOT__loadDrawAreaTL,0,0);
		VL_SIG8(gpu__DOT__loadDrawAreaBR,0,0);
		VL_SIG8(gpu__DOT__loadMaskSetting,0,0);
		VL_SIG8(gpu__DOT__setIRQ,0,0);
		VL_SIG8(gpu__DOT__rstTextureCache,0,0);
		VL_SIG8(gpu__DOT__nextCondUseFIFO,0,0);
		VL_SIG8(gpu__DOT__loadClutPage,0,0);
		VL_SIG8(gpu__DOT__loadTexPage,0,0);
		VL_SIG8(gpu__DOT__loadSize,0,0);
		VL_SIG8(gpu__DOT__loadCoord1,0,0);
		VL_SIG8(gpu__DOT__loadCoord2,0,0);
		VL_SIG8(gpu__DOT__loadSizeParam,1,0);
//		VL_SIG8(gpu__DOT__bIssuePrimitive,0,0);
		VL_SIG8(gpu__DOT__currState,3,0);
		VL_SIG8(gpu__DOT__nextLogicalState,3,0);
		VL_SIG8(gpu__DOT__nextState,3,0);
		VL_SIG8(gpu__DOT__canReadFIFO,0,0);
		VL_SIG8(gpu__DOT__readFifo,0,0);
		VL_SIG8(gpu__DOT__isV0,0,0);
		VL_SIG8(gpu__DOT__isV1,0,0);
		VL_SIG8(gpu__DOT__isV2,0,0);
//		VL_SIG8(gpu__DOT__bPipeIssuePrimitive,0,0);
		VL_SIG8(gpu__DOT__min01ID,0,0);
		VL_SIG8(gpu__DOT__TopID,1,0);
		VL_SIG8(gpu__DOT__cmp02,0,0);
		VL_SIG8(gpu__DOT__cmp12,0,0);
		VL_SIG8(gpu__DOT__BottomID,1,0);
		VL_SIG8(gpu__DOT__MiddleID,1,0);
		VL_SIG8(gpu__DOT__VtxU0,7,0);
		VL_SIG8(gpu__DOT__VtxU1,7,0);
		VL_SIG8(gpu__DOT__VtxU2,7,0);
		VL_SIG8(gpu__DOT__VtxV0,7,0);
		VL_SIG8(gpu__DOT__VtxV1,7,0);
		VL_SIG8(gpu__DOT__VtxV2,7,0);
//		VL_SIG8(gpu__DOT__bCanPushPrimitive,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__clk,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__rst,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__wr_en_i,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__rd_en_i,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__full_o,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__empty_o,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__write_pointer,4,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__read_pointer,4,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__empty_int,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__full_or_empty,0,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__raddr,3,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__pRaddr,3,0);
		VL_SIG8(gpu__DOT__Fifo_inst__DOT__pRd_en_i,0,0);
		VL_SIG16(gpu__DOT__GPU_REG_OFFSETX,10,0);
		VL_SIG16(gpu__DOT__GPU_REG_OFFSETY,10,0);
		VL_SIG16(gpu__DOT__GPU_REG_DrawAreaX0,9,0);
		VL_SIG16(gpu__DOT__GPU_REG_DrawAreaY0,9,0);
		VL_SIG16(gpu__DOT__GPU_REG_DrawAreaX1,9,0);
		VL_SIG16(gpu__DOT__GPU_REG_DrawAreaY1,9,0);
		VL_SIG16(gpu__DOT__GPU_REG_DispAreaX,9,0);
		VL_SIG16(gpu__DOT__GPU_REG_DispAreaY,8,0);
		VL_SIG16(gpu__DOT__GPU_REG_RangeX0,11,0);
		VL_SIG16(gpu__DOT__GPU_REG_RangeX1,11,0);
		VL_SIG16(gpu__DOT__GPU_REG_RangeY0,9,0);
		VL_SIG16(gpu__DOT__GPU_REG_RangeY1,9,0);
		VL_SIG16(gpu__DOT__fifoDataOutY,12,0);
		VL_SIG16(gpu__DOT__fifoDataOutX,12,0);
		VL_SIG16(gpu__DOT__fifoDataOutW,10,0);
		VL_SIG16(gpu__DOT__fifoDataOutH,9,0);
		VL_SIG16(gpu__DOT__fifoDataOutClut,14,0);
		VL_SIG16(gpu__DOT__fifoDataOutTex,9,0);
		VL_SIG16(gpu__DOT__fifoDataOutWidth,9,0);
		VL_SIG16(gpu__DOT__fifoDataOutHeight,8,0);
		VL_SIG16(gpu__DOT__RegX0,12,0);
		VL_SIG16(gpu__DOT__RegY0,12,0);
		VL_SIG16(gpu__DOT__RegR0,8,0);
		VL_SIG16(gpu__DOT__RegG0,8,0);
		VL_SIG16(gpu__DOT__RegB0,8,0);
		VL_SIG16(gpu__DOT__RegX1,12,0);
		VL_SIG16(gpu__DOT__RegY1,12,0);
		VL_SIG16(gpu__DOT__RegR1,8,0);
		VL_SIG16(gpu__DOT__RegG1,8,0);
		VL_SIG16(gpu__DOT__RegB1,8,0);
		VL_SIG16(gpu__DOT__RegX2,12,0);
		VL_SIG16(gpu__DOT__RegY2,12,0);
		VL_SIG16(gpu__DOT__RegR2,8,0);
		VL_SIG16(gpu__DOT__RegG2,8,0);
		VL_SIG16(gpu__DOT__RegB2,8,0);
		VL_SIG16(gpu__DOT__RegC,14,0);
		VL_SIG16(gpu__DOT__RegTx,9,0);
		VL_SIG16(gpu__DOT__RegSizeW,9,0);
		VL_SIG16(gpu__DOT__RegSX0,9,0);
		VL_SIG16(gpu__DOT__RegSX1,9,0);
		VL_SIG16(gpu__DOT__RegSizeH,8,0);
		VL_SIG16(gpu__DOT__RegSY0,8,0);
		VL_SIG16(gpu__DOT__RegSY1,8,0);
		VL_SIG16(gpu__DOT__componentFuncR,8,0);
		VL_SIG16(gpu__DOT__componentFuncG,8,0);
		VL_SIG16(gpu__DOT__componentFuncB,8,0);
		VL_SIG16(gpu__DOT__componentFuncRA,8,0);
		VL_SIG16(gpu__DOT__componentFuncGA,8,0);
		VL_SIG16(gpu__DOT__componentFuncBA,8,0);
		VL_SIG16(gpu__DOT__loadComponentR,8,0);
		VL_SIG16(gpu__DOT__loadComponentG,8,0);
		VL_SIG16(gpu__DOT__loadComponentB,8,0);
		VL_SIG16(gpu__DOT__min01V,12,0);
		VL_SIG16(gpu__DOT__VtxX0,12,0);
		VL_SIG16(gpu__DOT__VtxX1,12,0);
		VL_SIG16(gpu__DOT__VtxX2,12,0);
		VL_SIG16(gpu__DOT__VtxY0,12,0);
		VL_SIG16(gpu__DOT__VtxY1,12,0);
		VL_SIG16(gpu__DOT__VtxY2,12,0);
		VL_SIG16(gpu__DOT__VtxR0,8,0);
		VL_SIG16(gpu__DOT__VtxR1,8,0);
		VL_SIG16(gpu__DOT__VtxR2,8,0);
		VL_SIG16(gpu__DOT__VtxG0,8,0);
		VL_SIG16(gpu__DOT__VtxG1,8,0);
		VL_SIG16(gpu__DOT__VtxG2,8,0);
		VL_SIG16(gpu__DOT__VtxB0,8,0);
		VL_SIG16(gpu__DOT__VtxB1,8,0);
		VL_SIG16(gpu__DOT__VtxB2,8,0);
		VL_SIG16(gpu__DOT__PrimClut,14,0);
		VL_SIG16(gpu__DOT__PrimTx,9,0);
		VL_SIG(gpu__DOT__cpuDataIn,31,0);
		VL_SIG(gpu__DOT__cpuDataOut,31,0);
		VL_SIG(gpu__DOT__fifoDataOut,31,0);
		VL_SIG(gpu__DOT__reg1Out,31,0);
	}

	pScan->addPlugin(new ValueChangeDump_Plugin("gpuLog.vcd"));

	// RESET
	resetSig = 0;

	/*
	cache->write = 0;
	cache->adressIn = 0;
	cache->dataIn = 0;
	*/
	clock();
	clock();
	clock();
	clock();
	resetSig   = 1;
	clock();
	while (true) {
		pushCommands();
		clock();
		checkGPUState();
	}
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();
	clock();

	delete mod;
	delete pScan;

	return 1;
}

int main() {
	testGPU();
}
