/*	clampUPositive
	Input   a UNSIGNED number (0..2^INW -1), 
	Output  a UNSIGNED number clamped to power of 2 (0..2^OUTW -1) 
	If you need the number as SIGNED, it is user responsability to concatenate a 0 
	
	Instanciation :
	clampUPositive #(.INW(16),.OUTW(8)) myClampUPositive(.valueIn(unsignedInput),.valueOut(unsignedUPositive));
*/
module clampUPositive
#(	parameter INW  = 16,	//      0..+65535
	parameter OUTW = 8		//      0..+255
)
(
	input  [ INW-1:0] valueIn,
	output [OUTW-1:0] valueOut
);
	wire isNZero            = |valueIn[INW-1:OUTW];
	wire [OUTW-1:0] orStage = {OUTW{isNZero}};
	assign valueOut = valueIn[OUTW-1:0] | orStage;
endmodule
