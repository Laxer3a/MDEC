/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/* For a SINGLE Texture, 
   Need two instance of those units for dual pixel. */
module TEXToIndex(
	// Texture input
	input	[1:0]	GPU_REG_TexFormat,
	input	[15:0]	dataIn,
	input	[1:0]	UCoordLSB,
	// Compute index from texture input.
	output [7:0]	indexLookup
);
	parameter PIX_4BIT		=2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3; // TODO Include instead.

	reg [3:0] tmpIndex2;
	always @(*) begin
		case (UCoordLSB)
		2'd0: tmpIndex2 = { dataIn[ 3: 0] };
		2'd1: tmpIndex2 = { dataIn[ 7: 4] };
		2'd2: tmpIndex2 = { dataIn[11: 8] };
		2'd3: tmpIndex2 = { dataIn[15:12] };
		endcase
	end
	
	wire [7:0] tmpIndex		= (GPU_REG_TexFormat == PIX_4BIT) ? { 4'd0, tmpIndex2 } : (UCoordLSB[0] ? dataIn[15:8] : dataIn[7:0]);
	assign indexLookup		= tmpIndex;
endmodule
