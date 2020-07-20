module FlagsS44(
	input [44:0] v,
	output       isOverflow,
	output       isUnderflow
);
	assign isOverflow = (!v[44]) && v[43];  // Positive number but too big.
	assign isUnderflow=   v[44]  && !v[43]; // Negative number but too big.
endmodule
