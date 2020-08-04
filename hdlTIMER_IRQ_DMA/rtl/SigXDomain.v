module SigXDomain(
	input	clkOut,
	input	in,
	output	out
);

// Two-stages shift-register to synchronize 'in' to the clk 'clkOut' clock domain
reg [1:0] SyncSig_clkOut;
always @(posedge clkOut) SyncSig_clkOut[0] <= in;
always @(posedge clkOut) SyncSig_clkOut[1] <= SyncSig_clkOut[0];

assign out = SyncSig_clkOut[1];

endmodule
