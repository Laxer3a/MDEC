/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module clampSPositiveFlg
#(	parameter INW  = 16,	// -32768..+32767
	parameter OUTW = 8		//      0..+255
)
(
	input  signed [ INW-1:0] valueIn,
	output        [OUTW-1:0] valueOut,
	output					 negClamp,
	output					 posClamp
);
	// Neg Sign  => 0
	wire isPos					= !valueIn[INW-1];
	wire [OUTW-1:0] andStage	= {OUTW{isPos}};
	
	// Pos > 255 => 255
	wire overF					= |valueIn[INW-2:OUTW];
	
	assign valueOut = ( valueIn[OUTW-1:0] | {OUTW{overF}} ) & andStage;
	assign negClamp = !isPos;
	assign posClamp = overF;
endmodule