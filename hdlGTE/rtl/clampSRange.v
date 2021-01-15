/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/*	clampSRange
	Input   a         signed number, 
	Output  a smaller signed number clamped to power of 2 (- 2^(OUTW-1)..2^(OUTW-1)-1) 
	
	Instanciation :
	clampSRange #(.INW(16),.OUTW(8)) myClampSRange(.valueIn(signedInput),.valueOut(signedSRange));
 */
module clampSRange
#(	parameter INW  = 16,	// -32768..+32767
	parameter OUTW = 8		//   -128..+127
)
(
	input  signed [ INW-1:0] valueIn,
	output signed [OUTW-1:0] valueOut
);
	// Overflow
	wire overF	= |valueIn[INW-2:OUTW-1];
	wire isOne  = &valueIn[INW-2:OUTW-1];

	//
	wire sgn    = valueIn[INW-1];
	wire andV   = (sgn  &  isOne		) | (!sgn & !overF);	// When [ < 0 and all one] OR [ >=0 and all zero ] -> Authorize value in final bit.
																// else overflow, reset to 0.
	wire orV    = (!sgn & overF);								// If positive AND overflow, clamp to MAX.

	parameter WT = OUTW-1;
	wire [OUTW-2:0]  orStage = {WT{ orV}};
	wire [OUTW-2:0] andStage = {WT{andV}};
	
	assign valueOut = { valueIn[INW-1], ((valueIn[OUTW-2:0]  & andStage) | orStage) };
endmodule
