/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */
`include "gpu_def.sv"

module gpu_loadedRegs(
	input				i_clk,
	
	//-----------------------------------------
	// DATA IN (Parser control the input)
	//-----------------------------------------
	// Data From FIFO
	input				i_validData,
	input	[31:0]		i_data,
	input	[7:0]		i_command,
	//-----------------------------------------
	// Vertex Control (TARGET)
	input	[1:0]		i_targetVertex,	// 0..2
	
	
	// [From Command Decoder + GPU configuration]
	input 				i_bUseTexture,
	
	//-----------------------------------------
	// OPERATION (set when i_validData VALID)
	//-----------------------------------------
	input				i_loadVertices,	// Load Coordinate from input
	input				i_loadUV,		// Load Texture coordinate from input
	input				i_loadRGB,		// Load Color from input
	input				i_loadAllRGB,	// If i_loadRGB = 1 => force ALL VERTEX TO SAME COLOR.
	input				i_loadCoord1,	// Load Top-Left     Coordinate (Fill, Copy commands)
	input				i_loadCoord2,	// Load Bottom-Right Coordinate (Fill, Copy commands)
	
	input				i_loadSize,		// Load WIDTH/HEIGHT for rectangle primitive.
	input	[1:0]		i_loadSizeParam,// Parameter for 	i_loadSizeParam

	input				i_loadRectEdge,			// Compute the vertices while loading from SIZE.
	input				i_isVertexLoadState,	// Parameter for i_loadRectEdge
	
	//-----------------------------------------
	// Parameters for internal xform
	//-----------------------------------------
	// [Data from General GPU Registers needed when loading vertices]
	input				i_GPU_REG_TextureDisable,
	input signed [10:0]	i_GPU_REG_OFFSETX,
	input signed [10:0]	i_GPU_REG_OFFSETY,
	
	output signed [11:0] o_RegX0,
	output signed [11:0] o_RegY0,
	output         [7:0] o_RegR0,
	output         [7:0] o_RegG0,
	output         [7:0] o_RegB0,
	output         [7:0] o_RegU0,
	output         [7:0] o_RegV0,
	output signed [11:0] o_RegX1,
	output signed [11:0] o_RegY1,
	output         [7:0] o_RegR1,
	output         [7:0] o_RegG1,
	output         [7:0] o_RegB1,
	output         [7:0] o_RegU1,
	output         [7:0] o_RegV1,
	output signed [11:0] o_RegX2,
	output signed [11:0] o_RegY2,
	output         [7:0] o_RegR2,
	output         [7:0] o_RegG2,
	output         [7:0] o_RegB2,
	output         [7:0] o_RegU2,
	output         [7:0] o_RegV2,
	output        [10:0] o_RegSizeW,
	output        [ 9:0] o_RegSizeH,
	output        [ 9:0] o_OriginalRegSizeH
);

//-------------------------------------------
// [Command Decoder give control information]
//-------------------------------------------
wire bIsFillCommand,bIsCopyCommand,bIsBase0x,bIgnoreColor;

gpu_commandDecoder decoder(
	.i_command				(i_command),
	
	.o_bIsBase0x			(bIsBase0x),
	.o_bIsBase01			(),
	.o_bIsBase02			(),
	.o_bIsBase1F			(),
	.o_bIsPolyCommand		(),
	.o_bIsRectCommand		(),
	.o_bIsLineCommand		(),
	.o_bIsMultiLine			(),
	.o_bIsForECommand		(),
	.o_bIsCopyVVCommand		(),
	.o_bIsCopyCVCommand		(),
	.o_bIsCopyVCCommand		(),
	.o_bIsCopyCommand		(bIsCopyCommand),
	.o_bIsFillCommand		(bIsFillCommand),
	.o_bIsRenderAttrib		(),
	.o_bIsNop				(),
	.o_bIsPolyOrRect		(),
	.o_bUseTextureParser	(),
	.o_bSemiTransp			(),
	.o_bOpaque				(),
	.o_bIs4PointPoly		(),
	.o_bIsPerVtxCol			(),
	.o_bIgnoreColor			(bIgnoreColor)
);

// -------------------------------------------------------------------

// -2048..+2047
reg signed [11:0] RegX0;
reg signed [11:0] RegY0;
reg  [7:0] RegR0;
reg  [7:0] RegG0;
reg  [7:0] RegB0;
reg  [7:0] RegU0;
reg  [7:0] RegV0;
reg signed [11:0] RegX1;
reg signed [11:0] RegY1;
reg  [7:0] RegR1;
reg  [7:0] RegG1;
reg  [7:0] RegB1;
reg  [7:0] RegU1;
reg  [7:0] RegV1;
reg signed [11:0] RegX2;
reg signed [11:0] RegY2;
reg  [7:0] RegR2;
reg  [7:0] RegG2;
reg  [7:0] RegB2;
reg  [7:0] RegU2;
reg  [7:0] RegV2;
// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
// reg  [9:0] RegTx;
reg [10:0] RegSizeW;
reg [ 9:0] RegSizeH;
reg [ 9:0] OriginalRegSizeH;


wire [31:0] fifoDataOut				= i_data;

//                  13 bit signed  12 bit signed
// -1024..+1023 Input. + -1024..+1023 Offset => -2048..+2047 12 bit signed.
wire signed [11:0]	fifoDataOutY	= { fifoDataOut[26],fifoDataOut[26:16] } + { i_GPU_REG_OFFSETY[10], i_GPU_REG_OFFSETY };
wire signed [11:0]	fifoDataOutX	= { fifoDataOut[10],fifoDataOut[10: 0] } + { i_GPU_REG_OFFSETX[10], i_GPU_REG_OFFSETX };

wire [7:0]	fifoDataOutUR			= fifoDataOut[ 7: 0]; // Same cut for R and U coordinate.
wire [7:0]	fifoDataOutVG			= fifoDataOut[15: 8]; // Same cut for G and V coordinate.

// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
//wire [9:0]	fifoDataOutTex		= {fifoDataOut[27],fifoDataOut[24:16]};
wire [9:0]  fifoDataOutWidth		= fifoDataOut[ 9: 0];
//wire [10:0] fifoDataOutW			= fifoDataOut[10: 0]; NOT USED.
wire [8:0]  fifoDataOutHeight		= fifoDataOut[24:16];
//wire [ 9:0] fifoDataOutH    		= fifoDataOut[25:16]; NOT USED.

wire [7:0] loadComponentR			= bIgnoreColor   ? 8'd128 : fifoDataOutUR;
wire [7:0] loadComponentG			= bIgnoreColor   ? 8'd128 : fifoDataOutVG;
wire [7:0] loadComponentB			= bIgnoreColor   ? 8'd128 : fifoDataOut[23:16];

// TODO : SWAP bit. for loading 4th, line segment.
//
wire [9:0] copyHeight = { !(|fifoDataOutHeight[8:0]), fifoDataOutHeight };

reg        writeOrigHeight;

reg [10:0] widthNext;
reg [ 9:0] heightNext;
wire signed [11:0] sizeWM1		  	= { 1'b0, widthNext  } + { 12{1'b1}}; //  Width-1
wire signed [11:0] sizeHM1		  	= { 2'd0, heightNext } + { 12{1'b1}}; // Height-1

wire signed [11:0] ldx            	= (i_isVertexLoadState ? fifoDataOutX : RegX0);
wire signed [11:0] ldy            	= (i_isVertexLoadState ? fifoDataOutY : RegY0);
wire signed [11:0] rightEdgeRect  	= ldx + sizeWM1;
wire signed [11:0] bottomEdgeRect 	= ldy + sizeHM1;

always @(*)
begin
    writeOrigHeight = 0;

    case (/*issue.*/i_loadSizeParam)
    SIZE_VAR:
    begin
        if (bIsFillCommand) begin
            widthNext = { 1'b0, fifoDataOutWidth[9:4], 4'b0 } + { 6'd0, |fifoDataOutWidth[3:0], 4'b0 };
        end else begin
            if (bIsCopyCommand) begin
                widthNext = { !(|fifoDataOutWidth[9:0]), fifoDataOutWidth }; // If value is 0, then 0x400
            end else begin
                widthNext = { 1'b0, fifoDataOutWidth };
            end
        end

        writeOrigHeight = 1;
        if (bIsCopyCommand) begin
            heightNext		= copyHeight; // If value is 0, then 0x400
        end else begin
            heightNext		= { 1'b0, fifoDataOutHeight };
        end
    end
    SIZE_1x1:
    begin
        widthNext	= 11'd1;
        heightNext	= 10'd1;
    end
    SIZE_8x8:
    begin
        widthNext	= 11'd8;
        heightNext	= 10'd8;
    end
    SIZE_16x16:
    begin
        widthNext	= 11'd16;
        heightNext	= 10'd16;
    end
    endcase
end

wire   isV0 = (i_targetVertex == 2'd0);
wire   isV1 = (i_targetVertex == 2'd1);
wire   isV2 = (i_targetVertex == 2'd2);

always @(posedge i_clk)
begin
    if (i_validData) begin
        if (isV0 & i_loadVertices) RegX0 <= fifoDataOutX;
        if (isV0 & i_loadVertices) RegY0 <= fifoDataOutY;
        if (isV0 & i_loadUV	     ) RegU0 <= fifoDataOutUR;
        if (isV0 & i_loadUV      ) RegV0 <= fifoDataOutVG;
        if ((isV0|i_loadAllRGB) & i_loadRGB) begin
            RegR0 <= loadComponentR;
            RegG0 <= loadComponentG;
            RegB0 <= loadComponentB;
        end

        if (isV1 & i_loadVertices) RegX1 <= fifoDataOutX;
        if (isV1 & i_loadVertices) RegY1 <= fifoDataOutY;
        if (i_loadRectEdge) begin
            RegX1 <= rightEdgeRect;
            RegY1 <= ldy;
            RegX2 <= ldx;
            RegY2 <= bottomEdgeRect;
        end
        if (isV1 & i_loadUV) RegU1 <= fifoDataOutUR;
        if (isV1 & i_loadUV) RegV1 <= fifoDataOutVG;
        if ((isV1|i_loadAllRGB) & i_loadRGB) begin
            RegR1 <= loadComponentR;
            RegG1 <= loadComponentG;
            RegB1 <= loadComponentB;
        end

        if (isV2 & i_loadVertices) RegX2 <= fifoDataOutX;
        if (isV2 & i_loadVertices) RegY2 <= fifoDataOutY;
        if (isV2 & i_loadUV      ) RegU2 <= fifoDataOutUR;
        if (isV2 & i_loadUV      ) RegV2 <= fifoDataOutVG;
        if ((isV2|i_loadAllRGB) & i_loadRGB) begin
            RegR2 <= loadComponentR;
            RegG2 <= loadComponentG;
            RegB2 <= loadComponentB;
        end

// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
//		if (loadTexPage)  RegTx = fifoDataOutTex;

    //	Better load and add W to RegX0,RegY0,RegX1=RegX0+W ? Same for Y1.
        if (i_loadSize) begin
            RegSizeW <= widthNext;
            RegSizeH <= heightNext;
            if (writeOrigHeight) begin
                OriginalRegSizeH <= heightNext;
            end
        end
        if (i_loadCoord1) begin
            RegX0 <= { 2'd0 , (bIsFillCommand) ? { fifoDataOutWidth[9:4], 4'b0} : fifoDataOutWidth};
            RegY0 <= { 3'd0 , fifoDataOutHeight };
        end
        if (i_loadCoord2) begin
            RegX1 <= { 2'd0 , fifoDataOutWidth  };
            RegY1 <= { 3'd0 , fifoDataOutHeight };
        end
    end
end

assign o_RegX0 = RegX0;
assign o_RegY0 = RegY0;
assign o_RegR0 = RegR0;
assign o_RegG0 = RegG0;
assign o_RegB0 = RegB0;
assign o_RegU0 = RegU0;
assign o_RegV0 = RegV0;
assign o_RegX1 = RegX1;
assign o_RegY1 = RegY1;
assign o_RegR1 = RegR1;
assign o_RegG1 = RegG1;
assign o_RegB1 = RegB1;
assign o_RegU1 = RegU1;
assign o_RegV1 = RegV1;
assign o_RegX2 = RegX2;
assign o_RegY2 = RegY2;
assign o_RegR2 = RegR2;
assign o_RegG2 = RegG2;
assign o_RegB2 = RegB2;
assign o_RegU2 = RegU2;
assign o_RegV2 = RegV2;
assign o_RegSizeW = RegSizeW;
assign o_RegSizeH = RegSizeH;
assign o_OriginalRegSizeH = OriginalRegSizeH;

endmodule
