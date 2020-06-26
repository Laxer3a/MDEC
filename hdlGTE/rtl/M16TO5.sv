module M16TO5 (
	input [15:0] i,		// Signed  16 bit.
	output [4:0] o);	// Clamped Unsigned 5 bit
	
	clampSPositive  
	#(	.INW (16),	// -32768..+32767
		.OUTW(5)		//      0..+255
	)
	SPClmp_inst
	(
		.valueIn	(i),
		.valueOut	(o)
	);
	
endmodule
