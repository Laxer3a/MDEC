/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module LeadCountS32(
	input [31:0]	value,
	output [5:0]	result
);
	wire       msb_allZeroes;
	wire [3:0] msb_leadCount;
	wire       lsb_allZeroes;
	wire [3:0] lsb_leadCount;

	leadZeroCounter16 instMSB (
		.i_word				(value[31:16]),
		.o_allZeros			(msb_allZeroes),
		.o_leadZeroCount	(msb_leadCount)
	);

	leadZeroCounter16 instLSB (
		.i_word				(value[15:0]),
		.o_allZeros			(lsb_allZeroes),
		.o_leadZeroCount	(lsb_leadCount)
	);
	
	wire		o_allZeros		= lsb_allZeroes & msb_allZeroes;
	wire [3:0]	o_validResult	= {4{!o_allZeros}};
	
	assign	result			= { o_allZeros, 
								msb_allZeroes & !lsb_allZeroes, 
								o_validResult & (msb_allZeroes ? lsb_leadCount : msb_leadCount )
							};
endmodule
