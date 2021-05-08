/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/*	Bresenham counter, works only if REALCOUNTERFREQU >= SLOWERIMAGINARYFREQU.

	It will generate a 'enabled' PWM signal matching the conversion from faster real clock to imaginary slower clock.
	
	Instanciation :
	
	bresenhamCounter #(.REALCOUNTERFREQU(40000),.SLOWERIMAGINARYFREQU(33800),.BITSIZE(16)) 
	bresenhamCounter_instance (
		.i_clk		(i_clk),
		.i_rst		(i_rst),
		.o_enable	(enable)
	);

	Note : Bit size must match the biggest real counter frequ + slower imaginary frequency sum width , then allow negative numbers.
	Note : Number can be reduced by common integer divisor.
			Ex : 40000 and 33800 => 400 and 338 => 200 (2x2x2x5x5) and 169 (13x13).
	
*/
module bresenhamCounter
#(	parameter REALCOUNTERFREQU  	= 200,
	parameter SLOWERIMAGINARYFREQU	= 169,
	parameter BITSIZE				= 9		// sum=200+169, -sum,+sum range support.
)
(
	input	i_clk,
	input	i_rst,
	output	o_enable
);

parameter DIFF = SLOWERIMAGINARYFREQU - REALCOUNTERFREQU;
reg signed [BITSIZE:0] counter;
wire bigger = (counter >= REALCOUNTERFREQU);
always @(posedge i_clk)
begin
	if (i_rst)
	begin
		// Make sure it works for equal frequency.
		counter <= SLOWERIMAGINARYFREQU;
	end else begin
		counter <= counter + (bigger ? DIFF : SLOWERIMAGINARYFREQU );
	end
end

assign o_enable = bigger;

endmodule
