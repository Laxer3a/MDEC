/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module DPRam
#(parameter DW = 16,
  parameter AW = 5
)
(
	input clk,
	input [DW-1:0] data_a, data_b,
	input [AW-1:0] addr_a, addr_b,
	input we_a, we_b,
	output reg [DW-1:0] q_a, q_b
);
	// Declare the RAM variable
	reg [DW-1:0] ram[(2**AW)-1:0];
	
	// Port A
	always @ (posedge clk)
	begin
		if (we_a) 
		begin
			ram[addr_a] <= data_a;
			q_a <= data_a;
		end
		else 
		begin
			q_a <= ram[addr_a];
		end
	end
	
	// Port B
	always @ (posedge clk)
	begin
		if (we_b)
		begin
			ram[addr_b] <= data_b;
			q_b <= data_b;
		end
		else
		begin
			q_b <= ram[addr_b];
		end
	end
endmodule
