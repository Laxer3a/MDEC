/*	clampSRange
	Input   a         signed number, 
	Output  a smaller signed number clamped to power of 2 (- 2^(OUTW-1)..2^(OUTW-1)-1) 
	
	Instanciation :
	clampSRange #(.INW(16),.OUTW(8)) myClampSRange(.valueIn(signedInput),.valueOut(signedSRange));
 */
module clampSRange
#(	parameter INW  = 16,	// -32768..+32767
	parameter OUTW = 8		//   -128..+127
)
(
	input  signed [ INW-1:0] valueIn,
	output signed [OUTW-1:0] valueOut
);
	// Overflow
	wire overF	= |valueIn[INW-2:OUTW-1];
	wire isOne  = &valueIn[INW-2:OUTW-1];

	//
	wire sgn    = valueIn[INW-1];
	wire andV   = (sgn  &  isOne		) | (!sgn & !overF);	// When [ < 0 and all one] OR [ >=0 and all zero ] -> Authorize value in final bit.
																// else overflow, reset to 0.
	wire orV    = (!sgn & overF);								// If positive AND overflow, clamp to MAX.

	parameter WT = OUTW-1;
	wire [OUTW-2:0]  orStage = {WT{ orV}};
	wire [OUTW-2:0] andStage = {WT{andV}};
	
	assign valueOut = { valueIn[INW-1], ((valueIn[OUTW-2:0]  & andStage) | orStage) };
endmodule
