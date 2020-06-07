/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
 **************************************************************************************************************************************/
/*	SDivTrunc
	Input   a         signed number, 
	Output  a smaller signed number. result of the division by the number of bit missing from input.

	Return result rounded toward zero with signed number.
	
	Instanciation :
	SDivTrunc #(.INW(16),.OUTW(8)) mySignedDivisionBy256(.valueIn(signedInput),.valueOut(signedOutput));
 */
module SDivTrunc
#(	parameter INW  = 24,
	parameter OUTW = 18
)
(
	input  signed [ INW-1:0] valueIn,
	output signed [OUTW-1:0] valueOut
);
	parameter DELTAW	= INW - OUTW;
	parameter DELTAWP1	= DELTAW + 1;
	parameter REMAIN    = INW - DELTAWP1;
	
	// Division by D = 8
	//		7 = D-1
	//		4 = D/2
	// Ex : Trunc div 8 -> [Add 7   vs Add 0]
	//      Round div 8 -> [Add 7+4 vs Add 4]

	// Here we implement Trunc Div.
	wire [DELTAW:0] DivN			= valueIn[INW-1] /*Sign*/ ? {1'b0, {DELTAW{1'b1}}} : {DELTAWP1{1'b0}};
	wire [INW-1 :0] outCalcDiv		= valueIn + {{REMAIN{1'b0}},DivN};
	assign valueOut					= outCalcDiv[INW-1:DELTAW];
endmodule
