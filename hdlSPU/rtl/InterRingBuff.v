/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

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
			ram[i_wordAddr] <= i_data;
		end
		
		addr_reg			<= i_wordAddr;
	end
		
	assign o_q = ram[addr_reg];
endmodule
