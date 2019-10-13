/* For a SINGLE Texture, 
   Need two instance of those units for dual pixel. */
module TEXToRGB(
	input			clk,
	input	[1:0]	GPU_REG_TexFormat,
	input	[15:0]	dataIn,
	input	[1:0]	UCoordLSB,
	input			dataValid,

	// Request CLUT Cache Entry (Latency 0)
	output			lookupValid,
	output [7:0]	indexLookup,
	input  [15:0]	ClutValue,		// Latency 1 : Pixel Color
	
	output [15:0]	outPixel,
	output 			transparentBlack
);
	parameter PIX_4BIT		=2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3; // TODO Include instead.

	assign lookupValid		= dataValid;
	
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
	
	wire [15:0] tmpPixel	= (GPU_REG_TexFormat == PIX_16BIT) ? dataIn : ClutValue;
	assign outPixel			= tmpPixel;
	assign transparentBlack	= !(|tmpPixel[14:0]); // If all ZERO, then 1.
	assign pixelValid		= internalPixelValid;
endmodule
