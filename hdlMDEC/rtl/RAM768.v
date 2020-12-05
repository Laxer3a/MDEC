module RAM768(
	input			i_clk,
	input [31:0]	i_dataIn,
	input  [7:0]	i_dataAdr,
	input			i_dataWr,
	
	// No readRAM !!! Just for counters. We always put out data with 1 cycle latency.
	input  [7:0]	i_dataAdrRd,
	output [31:0]	o_dataOut
);
	reg [31:0] ram[191:0];
	
	always @(posedge i_clk)
	begin
		if (i_dataWr) begin
			ram[i_dataAdr] <= i_dataIn;
		end

		// Always read
		o_dataOut <= ram[i_dataAdrRd];
	end
	
endmodule
