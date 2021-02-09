/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_scan(
	input					i_clk,

	//
	input					i_InterlaceRender,

	// Register
	input					GPU_REG_CurrentInterlaceField,
	input	signed [11:0]	i_RegX0,
	input	signed [11:0]	i_RegY0,
	
	// Line primitive
	input	signed [11:0] 	i_nextLineX,
	input	signed [11:0] 	i_nextLineY,

	// Triangle BBox
	input	signed [11:0]	i_minTriDAX0,
	input	signed [11:0]	i_minTriDAY0,
	input	signed [11:0]	i_maxTriDAX1,

	// Control
	// from outside
	input					i_loadNext,					// All primitive
	input 	nextX_t			i_selNextX,					// All primitive except FILL / CopyVV
	input	nextY_t			i_selNextY,					// All primitive
	
	input					i_tri_resetDir,				// Triangle Only but reset at each primitive
	input					i_tri_switchDir,			// Triangle Only
	input					i_tri_setPixelFound,		// Triangle Only
	input					i_tri_setDirectionComplete,	// Triangle Only
	input					i_tri_resetPixelFound,		// Triangle Only
	
	output	signed [11:0] 	o_pixelX,
	output	signed [11:0] 	o_pixelY,
	output	signed [11:0] 	o_nextPixelX,
	output	signed [11:0] 	o_nextPixelY,
	output  signed [ 9:0]   o_loopIncrNextPixelY,
	
	output					o_tri_dir,						// Triangle Only
	output					o_tri_pixelFound,				// Triangle Only
	output					o_tri_completedOneDirection		// Triangle Only
);

//---------------------------------------------------------------------------------------------------
// Stuff to handle INTERLACED RENDERING !!!
// So Start coordinate offset +0/+1 is only valid for RECT, TRIANGLE, FILL. It depends on the current field.
wire renderYOffsetInterlace		= (i_InterlaceRender ? (i_minTriDAY0[0] ^ GPU_REG_CurrentInterlaceField) : 1'b0);

reg dir;
reg pixelFound;
reg completedOneDirection;
reg signed [11:0] pixelX, pixelY,nextPixelX,nextPixelY;

wire signed [11:0] nextLineY = pixelY + { 9'b0 , i_InterlaceRender , !i_InterlaceRender };	// +1 for normal mode, +2 for interlaced locked render primitives

assign o_loopIncrNextPixelY = nextLineY[9:0];


always @(*)
begin
    case (i_selNextX)
        X_TRI_NEXT:		nextPixelX	= pixelX + { {10{dir}}, 2'b10 };	// -2,0,+2
        X_LINE_START:	nextPixelX	= i_RegX0;
        X_LINE_NEXT:	nextPixelX	= i_nextLineX; // Optimize and merge with case 0
        X_TRI_BBLEFT:	nextPixelX	= { i_minTriDAX0[11:1], 1'b0 };
        X_TRI_BBRIGHT:	nextPixelX	= { i_maxTriDAX1[11:1], 1'b0 };
        X_CV_START:		nextPixelX	= { 2'b0, i_RegX0[9:1], 1'b0 };
        default:		nextPixelX	= pixelX;
    endcase

    case (i_selNextY)
        Y_LINE_START:	nextPixelY	= i_RegY0;
        Y_LINE_NEXT:	nextPixelY	= i_nextLineY;
        Y_TRI_START:	nextPixelY	= i_minTriDAY0 + { 11'd0 , renderYOffsetInterlace };
        Y_TRI_NEXT:		nextPixelY	= nextLineY;
        Y_CV_ZERO:		nextPixelY	= { 11'd0, renderYOffsetInterlace };
        default:		nextPixelY	= pixelY;
    endcase
end

always @(posedge i_clk)
begin
    if (i_loadNext) begin
        pixelX <= nextPixelX;
        pixelY <= nextPixelY;
    end
	
	//-------------------------------------
	//  [Triangle Scanner Stuff]
	//-------------------------------------
    if (i_tri_resetDir) begin
        dir    <= 0; // Left to Right
    end else begin
        if (i_tri_switchDir) begin
            dir <= !dir;
        end
    end

    if (i_tri_resetPixelFound || i_tri_resetDir) begin
        pixelFound				<= 0; // No pixel found.
		completedOneDirection	<= 0; // Scan in one direction.
    end
    if (i_tri_setPixelFound) begin
        pixelFound 				<= 1;
    end
	if (i_tri_setDirectionComplete) begin
		completedOneDirection	<= 1; // Completed Scan in one direction.
	end
	/* Early optimization removed.
    if (resetEnteredTriangle) begin
        enteredTriangle = 0;
    end
    if (setEnteredTriangle) begin
        enteredTriangle = 1;
    end
	*/
end

assign o_pixelX						= pixelX;
assign o_pixelY						= pixelY;
assign o_tri_pixelFound 			= pixelFound;
assign o_tri_dir					= dir;
assign o_tri_completedOneDirection	= completedOneDirection;
assign o_nextPixelX					= nextPixelX;
assign o_nextPixelY					= nextPixelY;

endmodule
