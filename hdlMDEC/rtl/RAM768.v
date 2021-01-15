/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

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
