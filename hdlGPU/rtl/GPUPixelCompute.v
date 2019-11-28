module GPUPixelCompute
#(	parameter SUBW = 16 )
(
	input			clk,
	
	input			[9:0]	x,	// Bit 0 always ZERO, waste multiplier for now... Switch to 9:1 (TODO OPTIMIZE)
	input			[8:0]	y,
	
	input signed	[SUBW+8:0]	baseR,
	input signed	[SUBW+8:0]	baseG,
	input signed	[SUBW+8:0]	baseB,
	input signed	[SUBW+7:0]	baseU,
	input signed	[SUBW+7:0]	baseV,

	input signed	[SUBW+8:0]	vertR,
	input signed	[SUBW+8:0]	vertG,
	input signed	[SUBW+8:0]	vertB,
	input signed	[SUBW+7:0]	vertU,
	input signed	[SUBW+7:0]	vertV,
	
	input signed	[SUBW+8:0]	horiR,
	input signed	[SUBW+8:0]	horiG,
	input signed	[SUBW+8:0]	horiB,
	input signed	[SUBW+7:0]	horiU,
	input signed	[SUBW+7:0]	horiV,
	
	output			[8:0]		R_L,
	output			[8:0]		G_L,
	output			[8:0]		B_L,
	output			[7:0]		U_L,
	output			[7:0]		V_L,
	
	output			[8:0]		R_R,
	output			[8:0]		G_R,
	output			[8:0]		B_R,
	output			[7:0]		U_R,
	output			[7:0]		V_R
);
	wire signed [10:0] signX = { 1'b0,     x };
	wire signed [10:0] signY = { 1'b0,1'b0,y };
	
	// Waste multiplier again, put X and Y at the same bit precision.
	
	parameter WCol = SUBW+11+9;
	parameter WTex = SUBW+11+8;	// Sub + Resolution X/Y + Component Original Size + 1 sign bit.
	
	// Horizontal offset
	wire signed [WCol-1:0] tRX	= (signX * horiR);
	wire signed [WCol-1:0] tGX	= (signX * horiG);
	wire signed [WCol-1:0] tBX	= (signX * horiB);
	wire signed [WTex-1:0] tUX	= (signX * horiU);
	wire signed [WTex-1:0] tVX	= (signX * horiV);

	// Vertical offset.
	wire signed [WCol-1:0] tRY	= (signY * vertR);
	wire signed [WCol-1:0] tGY	= (signY * vertG);
	wire signed [WCol-1:0] tBY	= (signY * vertB);
	wire signed [WTex-1:0] tUY	= (signY * vertU);
	wire signed [WTex-1:0] tVY	= (signY * vertV);

	// Composed value at pixel x,y
	wire signed [WCol-1:0]	aR	= baseR + tRX + tRY;
	wire signed [WCol-1:0]	aG	= baseG + tGX + tGY;
	wire signed [WCol-1:0]	aB	= baseB + tBX + tBY;
	wire signed [WTex-1:0]	aU	= baseU + tUX + tUY;
	wire signed [WTex-1:0]	aV	= baseV + tVX + tVY;

	assign R_L = aR[SUBW+8:SUBW];
	assign G_L = aG[SUBW+8:SUBW];
	assign B_L = aB[SUBW+8:SUBW];
	assign U_L = aU[SUBW+7:SUBW];
	assign V_L = aV[SUBW+7:SUBW];

	// Composed value at pixel x+1,y
	wire signed [WCol-1:0]	bR = aR + horiR;
	wire signed [WCol-1:0]	bG = aG + horiG;
	wire signed [WCol-1:0]	bB = aB + horiB;
	wire signed [WTex-1:0]	bU = aU + horiU;
	wire signed [WTex-1:0]	bV = aV + horiV;

	assign R_R = bR[SUBW+8:SUBW];
	assign G_R = bG[SUBW+8:SUBW];
	assign B_R = bB[SUBW+8:SUBW];
	assign U_R = bU[SUBW+7:SUBW];
	assign V_R = bV[SUBW+7:SUBW];
endmodule
