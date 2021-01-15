/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/*	Round Toward zero signed number EXCEPT -1
	
	Input   a SIGNED number, 
	Output  a SIGNED number rounded by the policy.
	
	Instanciation :
	roundTowardZeroExceptM1 #(.WIDTH(16)) myRTZEM1(.valueIn(signedInput),.valueOut(signedOutput));
*/
module roundTowardZeroExceptM1
#(	parameter WIDTH  = 16	// -32768..+32767
)
(
	input  signed [WIDTH-1:0] valueIn,
	output        [WIDTH-1:0] valueOut
);
	parameter WM1 = WIDTH-1;
	
	wire isMinus1	= &valueIn; 							// [1 if value is -1]
	wire isOdd      =  valueIn[0]   & (!isMinus1);			// If ODD and not minus ONE.
	wire posV       = !valueIn[WM1] &       isOdd;			// Fill with ONE for Positive ODD value.

	assign valueOut = valueIn + { {WM1{posV}} , isOdd };	// Add +1 if negative, -1 if positive for VALID numbers.

endmodule
