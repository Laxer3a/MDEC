/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module gpu_irq (
	input	i_clk,
	input	i_rstIRQ,
	input	i_setIRQ,
	output	o_irq
);
	reg irq_internal;
	always @(posedge i_clk)
		if (i_rstIRQ)
			irq_internal <= 0;
		else if (i_setIRQ)
			irq_internal <= 1;
			
	assign o_irq = irq_internal;
endmodule
