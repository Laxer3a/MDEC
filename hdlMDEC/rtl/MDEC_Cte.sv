`ifndef  MDEC_CONST
`define  MDEC_CONST

// -----------------------------------------------------
// Pixel format output supported by the MDEC chip.
// -----------------------------------------------------
typedef bit[1:0] MDEC_TPIX;
parameter
	P_4BIT	= 0,
	P_8BIT	= 1,
	P24BIT	= 2,
	P15BIT	= 3;

// -----------------------------------------------------
// MDEC Support Signed/Unsigned values for 4 bit and 8 bit
// Pixel Format output.
// -----------------------------------------------------
typedef bit MDEC_SIGN;
parameter
	UNS			= 0,
	SGN			= 1;

// -----------------------------------------------------
// MDEC Support Setting a MASK bit for 15 Bit RGB
// Pixel Format output.
// -----------------------------------------------------
typedef bit MDEC_MASK;
parameter
	CLR			= 0,
	SET			= 1;

// -----------------------------------------------------
// Block ID in the data stream.
// Color Sequence is : BLK_CR, BLK_CB, BLK_Y1, BLK_Y2,
//                     BLK_Y3, BLK_Y4.
// -----------------------------------------------------
typedef bit[2:0] MDEC_BLCK;
parameter
	BLK_Y1		= 0,
	BLK_Y2		= 1,
	BLK_Y3		= 2,
	BLK_Y4		= 3,
	BLK_CR		= 4,
	BLK_CB		= 5,
	// [6 Not used]
	BLK_Y_		= 7;

`endif
