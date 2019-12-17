module dividerWrapper(
	input					clock,
	input signed  [31:0]	numerator,
	input signed  [21:0]	denominator,
	output signed [19:0]	output20
);

//
// [For verilator] Simulate a 6 clock latency pipelined divider unit.
//
`ifdef VERILATOR
	reg signed [31:0] num1,num2,num3,num4,num5;
	reg signed [21:0] den1,den2,den3,den4,den5;

	always @(posedge clock)
	begin
		num5 = num4; den5 = den4;
		num4 = num3; den4 = den3;
		num3 = num2; den3 = den2;
		num2 = num1; den2 = den1;
		num1 = numerator;
		den1 = denominator;
	end
	wire signed [31:0] divisor   = { {10{den5[21]}} ,den5 };
	wire signed [31:0] resultDiv = num5 / divisor;
	assign output20 = resultDiv[19:0];
`else
	wire signed [21:0] remain_sig;
	wire signed [31:0] quot;
	div6	div6_inst (
		.clock ( clock ),
		.denom ( denominator ),
		.numer ( numerator ),
		.quotient ( quot ),
		.remain ( remain_sig )
	);
	assign output20 = quot[19:0];
`endif

endmodule
