/*	
	Playstation MDEC YUV -> RGB Hardware conversion.
	Done by Laxer3A
	-------------------------------------------------
	Combinatioral Computation of YUV->RGB Conversion.
	-------------------------------------------------
	
	Formula :
	---------------------------------------------------
	R=(359/256 * Cr)                 + Y
	G=(-88/256 * Cb)+(-183/256 * Cr) + Y
	B=(454/256 * Cb)                 + Y
	
	* Input Values from Cr/Cb/Y are already clamped -128..+127
	* Values from RGB are also clamped [0..255] 
	  or [-128..+127] depending on i_unsigned bit.
	---------------------------------------------------
*/
module YUV2RGBCompute (
	input					i_YOnly,
	input 					i_signed,

	input	signed 	[7:0]	i_valueY,
	input	signed 	[7:0]	i_valueCr,
	input	signed 	[7:0]	i_valueCb,
	
	output	[7:0]			o_r,
	output	[7:0]			o_g,
	output	[7:0]			o_b
);
	//  A/ Specs from PCSXR and MAME using more bits.	
	//	wire signed [11:0]	rFact  =  12'd1434; // PSCXR : 1434 / MAME : 1435
	//	wire signed [11:0]	gFactB = -12'd351 ; // PSCXR : -351 / MAME : -351
	//	wire signed [11:0]	gFactR = -12'd728 ; // PSCXR : -728 / MAME : -731
	//	wire signed [11:0]	bFact  =  12'd1807; // PSCXR : 1807 / MAME : 1814
	// 
	//  B/ AmiDog 2014-03-26 15:07:04 ( http://board.psxdev.ru/topic/9/page/2/ )
	//	The MDEC seems to be using fixed point math with a 12-bit fractional part, just as the GTE and GPU does in places.
	//	Using these coefficients:
	//	RCr ( 5744)
	//	GCr (-2928)
	//	GCb (-1408)
	//	BCb ( 7264)
	//
	//  C/ AmiDog November 5th, 2014, 8:42 pm http://www.psxdev.net/forum/viewtopic.php?f=70&t=551&start=20
	//     & Akari (Fixed by Amidog)
	//	G=(-88/256 * B)+(-183/256 * R)
	//	R=(359/256 * R)
	//	B=(454/256 * B)
	// ------------------------------------------------------------------
	//   => TRUST NO ONE ! But C/ seems to be taken from HW and correct.
	// ------------------------------------------------------------------

	wire signed [9:0]	rFact  = i_YOnly ? 10'd0 :  10'd359;
	wire signed [9:0]	gFactB = i_YOnly ? 10'd0 : -10'd88;
	wire signed [9:0]	gFactR = i_YOnly ? 10'd0 : -10'd183;
	wire signed [9:0]	bFact  = i_YOnly ? 10'd0 :  10'd454;

	// Ok, fixed sized multplication
	// And FAT implementation : 4 multiplier.
	wire signed [17:0]	RTmp   = i_valueCr * rFact;		// 8 x 10 
	wire signed [17:0]	GTmpB  = i_valueCb * gFactB;	// Range : [0x3D458..0x02C00]
	wire signed [17:0]	GTmpR  = i_valueCr * gFactR;	// Range : [0x3A537..0x05B80]
	wire signed [17:0]	BTmp   = i_valueCb * bFact;		// 
	
	// -1024..+1023
	wire signed [10:0]	sgnY	= {{3{i_valueY[7]}} , i_valueY };
	wire signed [10:0]	sumR	=  { RTmp[17],RTmp[17:8] } + sgnY;
	wire signed [11:0] 	sumG	= { GTmpB[17],GTmpB[17],GTmpB[17:8] } + { GTmpR[17] , GTmpR[17], GTmpR[17:8] } + { i_valueY[7], sgnY };
	wire signed [10:0]	sumB	=  { BTmp[17],BTmp[17:8] } + sgnY;
	
	// ---------------------------------------
	// -1024..+1023 -> -128..+127
	// ---------------------------------------
	// [10 Sign][9..7][6..0] -> Clamp      OR STAGE     AND STAGE  isNZero isOne
	//        0  0000  xxxx  : 0..+127        0             1        0      0
	//        0  1010  xxxx  : +127           1             1        1      0
	//        1  1111  xxxx  : -128..-1       0             1        1      1
	//		  1  1010  xxxx  : -128           x(0)          0        1      0      <--- X Because AND stage is AFTER OR stage.
	//
	// Compute Flags for saturated arithmetic
	wire isNZeroR= |sumR[ 9:7];
	wire isNZeroG= |sumG[10:7];
	wire isNZeroB= |sumB[ 9:7];
	wire isOneR  = &sumR[ 9:7];
	wire isOneG  = &sumG[10:7];
	wire isOneB  = &sumB[ 9:7];
	wire orR     = (!sumR[10]) & (isNZeroR);				// [+ Value] and has non zero                    -> OR  1
	wire andR    = ((sumR[10]) & ( isOneR)) | (!sumR[10]);	// [- Value] and has all one   or positive value -> AND 1 
	wire orG     = (!sumG[11]) & (isNZeroG);				// [+ Value] and has non zero                    -> OR  1
	wire andG    = ((sumG[11]) & ( isOneG)) | (!sumG[11]);	// [- Value] and has all one   or positive value -> AND 1 
	wire orB     = (!sumB[10]) & (isNZeroB);				// [+ Value] and has non zero                    -> OR  1
	wire andB    = ((sumB[10]) & ( isOneB)) | (!sumB[10]);	// [- Value] and has all one   or positive value -> AND 1 
	// Signed saturated arithmetic.
	wire [6:0] lowR = (sumR[6:0] | {7{orR}}) & {7{andR}};
	wire [6:0] lowG = (sumG[6:0] | {7{orG}}) & {7{andG}};
	wire [6:0] lowB = (sumB[6:0] | {7{orB}}) & {7{andB}};
	// ---------------------------------------

	// Conversion signed/unsigned
	wire sigUnsigned = !i_signed;
	assign o_r = {sumR[10] ^ sigUnsigned,lowR}; // -128..127 -> 0..255 if unsigned enabled
	assign o_g = {sumG[11] ^ sigUnsigned,lowG}; // -128..127 -> 0..255
	assign o_b = {sumB[10] ^ sigUnsigned,lowB}; // -128..127 -> 0..255
endmodule
