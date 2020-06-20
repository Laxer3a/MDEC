module M16TO5 (
	input [15:0] i,
	output [4:0] o);
		
	/*	wire ovr = (!IR1[15]) & (|IR1[14:12]);	// Overflow 0x1F
		wire ovg = (!IR2[15]) & (|IR2[14:12]);	// Overflow 0x1F
		wire ovb = (!IR3[15]) & (|IR3[14:12]);	// Overflow 0x1F
		// TODO unflow flow ZERO clip.
		wire  [4:0] oRGB_R = (IR1[11:7] & {5{!IR1[15]}}) | {5{ovr}};
		wire  [4:0] oRGB_G = (IR2[11:7] & {5{!IR2[15]}}) | {5{ovg}};
		wire  [4:0] oRGB_B = (IR3[11:7] & {5{!IR3[15]}}) | {5{ovb}};
	
	*/
	assign o = i[4:0]; // TODO properwork
	
endmodule
