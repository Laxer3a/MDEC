/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module M16TO5 (
	input [15:0] i,		// Signed  16 bit.
	output [4:0] o);	// Clamped Unsigned 5 bit
	
	/*
	clampSPositive  
	#(	.INW (16),	// -32768..+32767
		.OUTW(5)		//      0..+255
	)
	SPClmp_inst
	(
		.valueIn	(i),
		.valueOut	(o)
	);*/
	
	// / 128 signed with clamping to 0 (negative clamped to 0)
	wire [4:0] unsignedUPositive;
	clampUPositive #(.INW(8),.OUTW(5)) myClampUPositive(.valueIn(i[14:7]),.valueOut(unsignedUPositive));
	assign o = i[15] ? 5'd0 : unsignedUPositive;
endmodule
