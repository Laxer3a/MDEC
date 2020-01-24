/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
 **************************************************************************************************************************************/
module InterRingBuff
(
	input			i_clk,
	input 	[15:0]	i_data,
	input 	 [9:0]	i_wordAddr,
	input			i_we,
	output	[15:0]	o_q
);
	// Declare the RAM variable
	reg [15:0] ram[1023:0];
	
	// Variable to hold the registered read address
	reg [9:0] addr_reg;
	
	always @ (posedge i_clk)
	begin
	// Write
		if (i_we)
		begin
			ram[i_wordAddr] = i_data;
		end
		
		addr_reg			= i_wordAddr;
	end
		
	assign o_q = ram[addr_reg];
endmodule
