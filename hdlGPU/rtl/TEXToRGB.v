/* For a SINGLE Texture, 
   Need two instance of those units for dual pixel. */
module TEXToRGB(
	input				clk,
	input	 [1:0]	GPU_REG_TexFormat,
	input [15:0]	dataIn,
	input  [1:0]	UCoordLSB,
	input        	dataValid,

	// Request CLUT Cache Entry (Latency 0)
	output          lookupValid,
	output [7:0]	indexLookup,
	input			isClutValid,	// Latency 0 : it is register output wire, no latency, mux from indexLookup
	// (Latency 1)
	input  [15:0]	ClutValue,		// Latency 1 : Pixel Color
	
	// Latency 1 Pixel compare to dataIn
	output [4:0]	red,
	output [4:0]	green,
	output [4:0]	blue,
	output			STP,
	output 			transparentBlack,
	output          pixelValid			// 0 if input pixel is not valid or CLUT invalid previous cycle.
);
	parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3; // TODO Include instead.

	assign lookupValid = dataValid;
	reg internalPixelValid;
	
	reg [3:0] tmpIndex2;
	always @(*) begin
		case (UCoordLSB)
		2'd0: tmpIndex2 = { dataIn[ 3: 0] };
		2'd1: tmpIndex2 = { dataIn[ 7: 4] };
		2'd2: tmpIndex2 = { dataIn[11: 8] };
		2'd3: tmpIndex2 = { dataIn[15:12] };
		endcase
	end
	wire [7:0] tmpIndex = (GPU_REG_TexFormat == PIX_4BIT) ? { 4'd0, tmpIndex2 } : (UCoordLSB[0] ? dataIn[15:8] : dataIn[7:0]);
	assign indexLookup = tmpIndex;
	
	// Need 1 cycle latency in case of RGB true color...
	reg [15:0] pipeRGB;
	always @(posedge clk)
	begin
		pipeRGB					<= dataIn;
		internalPixelValid	<= (GPU_REG_TexFormat == PIX_16BIT) ? dataValid : isClutValid;
	end
	
	assign pixelValid = internalPixelValid;
	wire [4:0] tr = (GPU_REG_TexFormat == PIX_16BIT) ? pipeRGB[ 4: 0] : ClutValue[ 4: 0];
	wire [4:0] tg = (GPU_REG_TexFormat == PIX_16BIT) ? pipeRGB[ 9: 5] : ClutValue[ 9: 5];
	wire [4:0] tb = (GPU_REG_TexFormat == PIX_16BIT) ? pipeRGB[14:10] : ClutValue[14:10];
	assign red        = tr;
	assign green      = tg;
	assign blue       = tb;
	assign transparentBlack = !((|tr) | (|tg) | (|tb)); // If all ZERO, then 1.
	assign STP        = (GPU_REG_TexFormat == PIX_16BIT) ? pipeRGB[15] : ClutValue[15];
endmodule
