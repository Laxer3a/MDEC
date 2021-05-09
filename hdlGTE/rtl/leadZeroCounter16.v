module leadZeroCounter16 (
	input       [15:0] i_word,
	output			   o_allZeros,
	output       [3:0] o_leadZeroCount
);
	// Dimitrakopoulos et al. 2008
	integer i;

	// 'Or' Pair Tree
	reg [7:0] or0;
	reg [3:0] or1;
	reg [1:0] or2;

	always @(*) begin
		for (i=0; i<8;i=i+1)
			or0[i] = i_word[2*i+1] | i_word[2*i];
			
		for (i=0; i<4;i=i+1)
			or1[i] =    or0[2*i+1] |    or0[2*i];
			
		for (i=0; i<2;i=i+1)
			or2[i] =    or1[2*i+1] |    or1[2*i];
	end

	reg [3:0] an0;
	// And stage 0
	always @(*)	for (i=0; i<4;i=i+1)
		an0[i] = ((!or0[2*i+1]) & i_word[i*4+1]) | i_word[4*i+3];


	reg [1:0] an10;
	reg [1:0] an11;
	// And stage 1A 1B
	always @(*) for (i=0; i<2;i=i+1) begin
		an10[i] = ((!or1[2*i+1]) & an0[i*2]  ) | an0[2*i+1];
		an11[i] = ((!or1[2*i+1]) & or0[i*4+1]) | or0[4*i+3];
	end
	
	assign o_allZeros         = !(or2[0] | or2[1]);
	assign o_leadZeroCount[3] = !or2[1];
	assign o_leadZeroCount[2] = !(((!or2[1]) &  or1[1]) |  or1[3]);
	assign o_leadZeroCount[1] = !(((!or2[1]) & an11[0]) | an11[1]);
	assign o_leadZeroCount[0] = !(((!or2[1]) & an10[0]) | an10[1]);
endmodule
