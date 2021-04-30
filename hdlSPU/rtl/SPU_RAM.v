/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
	Fake ram with :
	- Last memory data kept available for further re-read.
	- Latency of 4 cycles.
 **************************************************************************************************************************************/
module SPU_RAM
(
	input			i_clk,
	input 	[15:0]	i_data,
	input 	[17:0]	i_wordAddr,
	input			i_re,
	input			i_we,
	input	[ 1:0]	i_byteSelect,
	
	output	[15:0]	o_q
);

	// Declare the RAM variable
	reg [15:0] ram[262143:0];
	
	// Variable to hold the registered read address
	reg [17:0] addr_reg;
	
	always @ (posedge i_clk)
	begin
		// Write
		if (i_we)
		begin
			ram[i_wordAddr] <= i_data[15:0];
		end
		
		addr_reg <= i_wordAddr;
	end
	
	// DEAD if not valid or correct value (1 cycle after READ signal)
	wire [15:0] readV = ram[addr_reg];

	reg [15:0] data1;
	reg [15:0] data2;
	reg [15:0] data3;
	reg readByteSelect_reg;
	reg readByteSelect_reg1;
	reg readByteSelect_reg2;
	reg readByteSelect_reg3;
	always @ (posedge i_clk)
	begin
		// Pipeline +3 cycles for data valid.
		readByteSelect_reg	<= i_re;
		readByteSelect_reg1 <= readByteSelect_reg;
		readByteSelect_reg2 <= readByteSelect_reg1;
		readByteSelect_reg3 <= readByteSelect_reg2;

		// Update pipeline value along the line if VALID only.
		if (readByteSelect_reg)
			data1 <= readV;
		if (readByteSelect_reg1)
			data2 <= data1;
		if (readByteSelect_reg2)
			data3 <= data2;
	end
	assign o_q = data3;
endmodule
