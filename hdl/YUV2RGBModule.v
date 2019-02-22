/*
	Playstation YUV -> RGB Hardware conversion.

	Computation Specs :
	
	Values from Cr/Cb/Y are already clamped -128..+127
	Values from RGB are also clamped out 0..255
	
	------------------------------------
	G=(-88/256 * B)+(-183/256 * R)
	R=(359/256 * R)
	B=(454/256 * B)
	------------------------------------


 */
module YUV2RGBCompute (
	// System
	input					clk,
	input					i_nrst,

	// Input
	input					i_wrt,
	input					i_YOnly,
	input			[5:0]	i_writeIdx,
	input	signed [22:0]	i_valueY,
	input			[1:0]	i_YBlockNum,

	// Read Cr
	// Read Cb
	// No need for Read Signal, always. Write higher priority, and values ignore when invalid address.
	output 			[5:0]	o_readAdr,
	input	signed [22:0]	i_valueCr,
	input	signed [22:0]	i_valueCb,
	
	// Output in order value out
	output					o_wPix,
	output  [7:0]			o_pix,
	output	[7:0]			o_r,
	output	[7:0]			o_g,
	output	[7:0]			o_b,
);
	/*
	- 1 Cycle Latency when reading Cr/Cb
	*/
	wire [1:0] adrXSub	= i_writeIdx[5:4];
	wire [1:0] adrYSub	= i_writeIdx[2:1];
	wire [2:0] adrX		= i_writeIdx[5:3];
	wire [2:0] adrY		= i_writeIdx[2:0];
	wire       tileX	= i_YBlockNum[0];
	wire       tileY	= i_YBlockNum[1];
	
	// Read address for Cr/Cb 8x8 block.
	assign o_readAdr	= {tileY,adrYSub,tileX,adrXSub};
	// Setup Read Signal for tables.
	assign o_read		= i_wrt;
	// Write address for 16x16 block.
	/*TODO PIPELINE i_ to match computations cycles*/
	assign o_pix  		= i_YOnly	? { 2'b00  , i_writeIdx }
									: {tileY,adrY,tileX,adrX};

	/*TODO PIPELINE */
	assign o_wPix		= i_wrt;
	
	wire signed [11:0]	rFact  =  12'd1434; // PSCXR : 1434 / MAME : 1435
	wire signed [11:0]	gFactB = -12'd351 ; // PSCXR : -351 / MAME : -351
	wire signed [11:0]	gFactR = -12'd728 ; // PSCXR : -728 / MAME : -731
	wire signed [11:0]	bFact  =  12'd1807; // PSCXR : 1807 / MAME : 1814

	// Ok, fixed sized multplication
	// And FAT implementation : 4 multiplier.
	wire signed [34:0]	RTmp   = i_valueCr * rFact;
	wire signed [34:0]	GTmpB  = i_valueCb * gFactB;
	wire signed [34:0]	GTmpR  = i_valueCr * gFactR;
	wire signed [34:0]	BTmp   = i_valueCb * bFact;
	
	wire signed sumR           =  RTmp[34:10] + pValueY;
	wire signed sumG           = GTmpB[34:10] + GTmpR[34:10] + pValueY; 
	wire signed sumB           =  BTmp[34:10] + pValueY;
	
	// Clamp[Min/Max -128..+127] -> then Xor bit 7 = Signed -> Unsigned
	// Or add 128, then clamp 0..255

	// Detect -128..+127 range is same as 
	// [vvvvvvvvvvv][bbbbbbbb]
	// If v all = last b bit : no overflow/no overflow.
	// 1....1 = 1xxx xxxx -> In range negative
	// [Any0] = 1xxx xxxx -> Fail Underflow/Overflow (check last bit)
	// [Any1] = 0xxx xxxx -> Fail Overflow
	// 0....0 = 0xxx xxxx -> In range positive
	
	/*	
		==========================
		What are they doing wrong?
		==========================

		A good fellow named Gabriele Gorla suggested to me a reason why we're seeing different colors. He took the time to cleanup and review the PCSX emulator code. During that process he discovered that its YCbCr to RGB conversion was incorrect. Specifically, while the correct equation is this: 

		[ 1.0    0.0       1.402  ]   [ y  ]   [ r ]
		[ 1.0   -0.3437   -0.7143 ] * [ cb ] = [ g ]
		[ 1.0    1.772     0.0    ]   [ cr ]   [ b ]

		it was incorrectly using this equation:

		[ 1.0    0.0       1.402  ]   [ y  ]   [ b ]
		[ 1.0   -0.3437   -0.7143 ] * [ cr ] = [ g ]
		[ 1.0    1.772     0.0    ]   [ cb ]   [ r ]

		He fixed it and now PCSX output looks almost identical to jPSXdec.

		As a test, I changed jPSXdec to use that incorrect math, and the output looked very similar to all those that got it wrong.
	
	
	
		[No$ Specs]
		yuv_to_rgb(xx,yy)
		  for y=0 to 7
			for x=0 to 7
			  R=[Crblk+((x+xx)/2)+((y+yy)/2)*8], B=[Cbblk+((x+xx)/2)+((y+yy)/2)*8]
			  G=(-0.3437*B)+(-0.7143*R), R=(1.402*R), B=(1.772*B)
			  Y=[Yblk+(x)+(y)*8]
			  R=MinMax(-128,127,(Y+R))
			  G=MinMax(-128,127,(Y+G))
			  B=MinMax(-128,127,(Y+B))
			  if unsigned then BGR=BGR xor 808080h  ;aka add 128 to the R,G,B values
			  dst[(x+xx)+(y+yy)*16]=BGR
			next x
		  next y
		Note: The exact fixed point resolution for "yuv_to_rgb" is unknown. And,
		there's probably also some 9bit limit (similar as in "y_to_mono").

		y_to_mono
		  for i=0 to 63
			Y=[Yblk+i]
			Y=Y AND 1FFh                  ;clip to signed 9bit range
			Y=MinMax(-128,127,Y)          ;saturate from 9bit to signed 8bit range
			if unsigned then Y=Y xor 80h  ;aka add 128 to the Y value
			dst[i]=Y
		  next i
	
	
// PSCXR
#define	MULR(a)			((1434 * (a))) 
#define	MULG2(a, b)		((-351 * (a) - 728 * (b)))
#define	MULB(a)			((1807 * (a))) 
#define MULY(a)			((a) << 10)

	
	// PCXR : 1434/-731/-351/1807
	// MAME : 1435/-731/-351/1814

INT32 mdec_cr_to_r( INT32 n_cr ) { return ( 1435 * n_cr ) >> 10; }
INT32 mdec_cr_to_g( INT32 n_cr ) { return ( -731 * n_cr ) >> 10; }
INT32 mdec_cb_to_g( INT32 n_cb ) { return ( -351 * n_cb ) >> 10; }
INT32 mdec_cb_to_b( INT32 n_cb ) { return ( 1814 * n_cb ) >> 10; }

	  mdec_clamp8( p_n_y[ 0 ] + n_g )
	  mdec_clamp8( p_n_y[ 0 ] + n_r )
	  mdec_clamp8( p_n_y[ 0 ] + n_b )



UINT16 mdec_clamp8( INT32 n_r ) { return m_p_n_mdec_clamp8[ n_r + 128 + 256 ]; }
	n_r = mdec_cr_to_r( n_cr );
	n_g = mdec_cr_to_g( n_cr ) + mdec_cb_to_g( n_cb );
	n_b = mdec_cb_to_b( n_cb );

	r = ( mdec_clamp8( p_n_y[ 0 ] + n_g ) << 8 ) | mdec_clamp8( p_n_y[ 0 ] + n_r );
	g = ( mdec_clamp8( p_n_y[ 1 ] + n_r ) << 8 ) | mdec_clamp8( p_n_y[ 0 ] + n_b );
	b = ( mdec_clamp8( p_n_y[ 1 ] + n_b ) << 8 ) | mdec_clamp8( p_n_y[ 1 ] + n_g );
		
	 */
	
endmodule
