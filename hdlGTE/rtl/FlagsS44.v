/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module FlagsS44(
	input [44:0] v,
	output       isOverflow,
	output       isUnderflow
);
	assign isOverflow = (!v[44]) && v[43];  // Positive number but too big.
	assign isUnderflow=   v[44]  && !v[43]; // Negative number but too big.
endmodule
