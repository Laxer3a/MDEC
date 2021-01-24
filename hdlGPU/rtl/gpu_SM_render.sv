/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_render(
	input				i_clk,
	input				i_rst,
	
	input				i_bUseTexture,
	input				i_bIsRectCommand, // Use
	input				i_bIsPolyCommand,
	
	input	[2:0]		i_activateRender,
	output				o_renderInactiveNextCycle,
	output				o_lineStart,

	// Can we push memory commands ?
	input				i_commandFIFOaccept,

	input				i_saveLoadOnGoing,
	input				i_pixelInFlight,

	output				o_incrementInterpCounter,
	input				i_endInterpCounter,
	
	input				i_isLoadingPalette,
	input				i_stillRemainingClutPacket,
	output				o_requClutCacheUpdate,
	output				o_decClutCount,				// Same signal AS requClutCacheUpdate
	input				i_isPalettePrimitive,		// Could just reset always ?
	output				o_endClutLoading,			// May be avoid using i_isPalettePrimitive ?
	
	output				o_writeStencil,
	output				o_loadNext,
	output	[2:0]		o_selNextX,
	output	[2:0]		o_selNextY,
	output				o_resetXCounter,
	output				o_incrementXCounter,
	output	[2:0]		o_memoryCommand,
	output				o_stencilReadSig,
	output				o_setPixelFound,
	output				o_memorizeLineEqu,
	output				o_switchDir,
	output				o_writePixelL,
	output				o_writePixelR,
	output				o_setDirectionComplete,
	output				o_resetPixelFound,
	output				o_flush,

	//-----------------------------------------
	// Current pixel pair
	//-----------------------------------------
	input				i_isValidPixelL,
	input				i_isValidPixelR,
	
	//-----------------------------------------
	// Scan/Geometry feedback
	//-----------------------------------------
	// Fill
	input				i_emptySurface,
	input				i_isLastSegment,
	input				i_endVertical,

	// Triangles / Rect
	input				i_earlyTriangleReject,		// Gather outside and make single input ?
	input				i_isNULLDET,
	
	input				i_outsideTriangle,			// i_edgeDidNOTSwitchLeftRightBB	// Check that TRIANGLE EDGE did not SWITCH between the LEFT and RIGHT side of the bounding box.
													// && ((!maxTriDAX1[0] && !i_isValidPixelL) || (maxTriDAX1[0] && !i_isValidPixelR)))	
	
	input				i_isNegXAxis,
	input				i_isNegPreB,
	input				i_isValidHorizontalTriBbox,
	input				i_isBottomInsideBBox,
	input				i_pixelFound,
	input				i_requestNextPixel,
	input				GPU_REG_CheckMaskBit,
	input	[1:0]		stencilReadValue,
	input				i_reachEdgeTriScan,
	input				i_completedOneDirection,
	// Rect
	input				i_isInsideBBoxTriRectL,
	input				i_isInsideBBoxTriRectR,
	input				i_isRightPLXmaxTri,
	// Lines
	input				i_isValidLinePixel,			// isLineInsideDrawArea	/*Valid Area*/	&& ((!InterlaceRender)	  || (InterlaceRender && (GPU_REG_CurrentInterlaceField != pixelY[0])))	// NON INTERLACED OR INTERLACE BUT VALID AREA
													//                      				&& ((GPU_REG_CheckMaskBit && (!selectPixelWriteMaskLine)) || (!GPU_REG_CheckMaskBit))
	input				i_isLineLeftPix,
	input				i_isLineRightPix,
	input				i_endPixelLine				//	<= (pixelX == RegX1) && (pixelY == RegY1)
);

typedef enum logic[4:0] {
	RENDER_WAIT					= 5'd0,
	LINE_START					= 5'd1,
	LINE_DRAW					= 5'd2,
	LINE_END					= 5'd3,
	RECT_START					= 5'd4,
	FILL_START					= 5'd5,
	COPY_INIT					= 5'd6,
	TRIANGLE_START				= 5'd7,
	FILL_LINE  					= 5'd8,
	START_LINE_TEST_LEFT		= 5'd9,
	START_LINE_TEST_RIGHT		= 5'd10,
	SCAN_LINE					= 5'd11,
	SCAN_LINE_CATCH_END			= 5'd12,
	SETUP_INTERP				= 5'd13,
	RECT_SCAN_LINE				= 5'd14,
	WAIT_3						= 5'd15,
	WAIT_2						= 5'd16,
	WAIT_1						= 5'd17,
	SELECT_PRIMITIVE			= 5'd18,
	FLUSH_COMPLETE_STATE		= 5'd19
} workState_t;

//----------------------------------------------------	
workState_t nextWorkState,currWorkState;
always @(posedge i_clk)
	if (i_rst)
		currWorkState <= RENDER_WAIT;
	else
		currWorkState <= nextWorkState;
//----------------------------------------------------	

reg loadNext, resetXCounter,writeStencil,stencilReadSig,incrementXCounter,
	resetPixelFound,
	setPixelFound,
	memorizeLineEqu,
    incrementInterpCounter,
	switchDir,
	requClutCacheUpdate,decClutCount,	// Same signal
	setDirectionComplete,
	endClutLoading,
	flush,
	writePixelL,writePixelR;
	
reg [2:0]	selNextX,selNextY;
reg [2:0]	memoryCommand;

always @(*)
begin
	nextWorkState				= currWorkState;
	loadNext					= 0;
	resetXCounter				= 0;
	writeStencil				= 0;
	stencilReadSig				= 0;
	incrementXCounter			= 0;
	resetPixelFound				= 0;
	setPixelFound				= 0;
	memorizeLineEqu				= 0;
	incrementInterpCounter		= 0;
	switchDir					= 0;
	requClutCacheUpdate			= 0;
	decClutCount				= 0;	
	setDirectionComplete		= 0;
	endClutLoading				= 0;
	writePixelL					= 0;
	writePixelR					= 0;
	flush						= 0;
	
	selNextX					= X_ASIS;
	selNextY					= Y_ASIS;
	memoryCommand				= MEM_CMD_NONE;
	
    case (currWorkState)
	RENDER_WAIT:
	begin
		case (i_activateRender)
		RDR_SETUP_INTERP	: nextWorkState = SETUP_INTERP;
		RDR_TRIANGLE_START	: nextWorkState = TRIANGLE_START;
		RDR_LINE_START		: nextWorkState = LINE_START;
		RDR_FILL_START		: nextWorkState = FILL_START;
		RDR_WAIT_3			: nextWorkState = WAIT_3;
		default				: nextWorkState = RENDER_WAIT;
		endcase
	end
	// --------------------------------------------------------------------
	//	 FILL VRAM STATE MACHINE
	// --------------------------------------------------------------------
	FILL_START:	// Actually FILL LINE START.
	begin
		if (i_emptySurface) begin
			nextWorkState = RENDER_WAIT;
		end else begin
			// Next Cycle H=H-1, and we can parse from H-1 to 0 for each line...
			// Reset X Counter. + Now we fill from H-1 to ZERO... force decrement here.
			loadNext		= 1;
			selNextY		= Y_CV_ZERO;
			resetXCounter	= 1;
			nextWorkState	= FILL_LINE;
		end
	end
	FILL_LINE:
	begin
		// Forced to decrement at each step in X
		// [FILL COMMAND : [16 Bit 0BGR][16 bit empty][Adr 15 bit][4 bit empty][010]
		if (i_commandFIFOaccept) begin // else it will wait...
			memoryCommand		= MEM_CMD_FILL;
			writeStencil		= 1;
			if (i_isLastSegment) begin
				loadNext	  = 1;
				selNextY	  = Y_TRI_NEXT;
				resetXCounter = 1;
				nextWorkState = (i_endVertical) ? RENDER_WAIT : FILL_LINE;
			end else begin
				incrementXCounter	= 1;// SRC COUNTER
			end
		end
	end
	// --------------------------------------------------------------------
	//	 TRIANGLE STATE MACHINE
	// --------------------------------------------------------------------
	SETUP_INTERP:
	begin
		nextWorkState			= i_endInterpCounter ? WAIT_3 : SETUP_INTERP;
		incrementInterpCounter	= 1;
	end
	WAIT_3: // 4 cycles to wait
	begin
		// Use this state to wait for end previous memory transaction...
		nextWorkState = (!i_saveLoadOnGoing) ? WAIT_2 : WAIT_3;
	end
	WAIT_2: // 3 cycles to wait
	begin
		// [TODO] That test could be put outside and checked EARLY --> RECT could skip to RECT_START 3 cycle earlier. Safe for now.
		//		  Did that before but did not checked whole condition --> FF7 Station failed some tiles.
		
		// validCLUTLoad is when CLUT reloading was set
		// isPalettePrimitive & rPalette4Bit & CLUTIs8BPP is when nothing changed, EXCEPT WE WENT FROM 4 BIT TO 8 BIT !
		if (i_isLoadingPalette) begin
			// Not using signal updateClutCacheComplete but could... rely on transaction only.
			if (!i_saveLoadOnGoing) begin // Wait for an on going memory transaction to complete.
				if (i_stillRemainingClutPacket) begin
					// And request ours.
					requClutCacheUpdate = 1;
					decClutCount		= 1;
					nextWorkState		= WAIT_2;
				end else begin
					nextWorkState		= WAIT_1;
				end
			end else begin
				// Just do nothing
				nextWorkState = WAIT_2;
			end
		end else begin
			nextWorkState = WAIT_1;
		end
	end
	WAIT_1: // 2 cycles to wait
	begin
		endClutLoading	= i_isPalettePrimitive;	// Reset flag, even if it was already reset. Force 0.
												// Force also to cache the current primitive pixel format (was it 4 bpp ?)
		nextWorkState	= SELECT_PRIMITIVE;
	end
	SELECT_PRIMITIVE:	// 1 Cycle to wait... send to primitive (with 1 cycle wait too...)
	begin				// Need 4 more cycle after that.
		if (i_bIsRectCommand) begin
			nextWorkState = RECT_START;
		end else begin
			if (i_bIsPolyCommand) begin
				nextWorkState = TRIANGLE_START;
			end else begin
				nextWorkState = LINE_START; /* RECT NEVER REACH HERE : No Division setup */
			end
		end
	end
	TRIANGLE_START:
	begin
		loadNext = 1;
		if (i_earlyTriangleReject || i_isNULLDET) begin	// Bounding box and draw area do not intersect at all.
			nextWorkState	= RENDER_WAIT;
		end else begin
			nextWorkState	= START_LINE_TEST_LEFT;
			selNextX	= X_TRI_BBLEFT;	// Set currX = BBoxMinX intersect X Draw Area.
			selNextY	= Y_TRI_START;	// Set currY = BBoxMinY intersect Y Draw Area.
		end

		// Triangle use PSTORE COMMAND. (2 pix per clock)
		//				BWRITE
		//
		// [CLOAD COMMAND : [111][Adress 17 bit] (Texture)
		// Use C(ache)LOAD to load a cache line for TEXTURE with 8 BYTE. This command will be upgraded if cache design changes...
		// Clut CACHE uses BSTORE command.
	end
	START_LINE_TEST_LEFT:
	begin
		if (i_isValidPixelL | i_isValidPixelR) begin // Line equation.
			nextWorkState = SCAN_LINE;
			stencilReadSig	= 1;
		end else begin
			memorizeLineEqu = 1;
			nextWorkState	= START_LINE_TEST_RIGHT;
			loadNext		= 1;
			selNextX		= X_TRI_BBRIGHT;// Set next X = BBox RIGHT intersected with DrawArea.
		end
	end
	START_LINE_TEST_RIGHT:
	begin
		loadNext	= 1;
		selNextX	= X_TRI_BBLEFT;	// Set currX = BBoxMinX intersect X Draw Area.
		// Test Bbox left (included) has SAME line equation result as right (excluded) result of line equation.
		// If so, mean that we are at the same area defined by the equation.
		// We also test that we are NOT a valid pixel inside the triangle.
		// We use L/R result based on RIGHT edge coordinate (odd/even).
		if (i_outsideTriangle)		// And that we are OUTSIDE OF THE TRIANGLE. (if odd/even pixel, select proper L/R validpixel.) (Could be also a clipped triangle with FULL LINE)
		begin
			selNextY		= Y_TRI_NEXT;
			nextWorkState	= i_isValidHorizontalTriBbox ? START_LINE_TEST_LEFT : FLUSH_COMPLETE_STATE;
		end else begin
			resetPixelFound	= 1;
			stencilReadSig	= 1;
			nextWorkState	= SCAN_LINE;
		end
	end
	SCAN_LINE:
	begin
		if (i_isBottomInsideBBox) begin
			stencilReadSig	= 1;
			//
			// TODO : Can optimize if LR = 10 when dir = 0, or LR = 01 when dir = 1 to directly Y_TRI_NEXT + SCAN_LINE_CATCH_END, save ONE CYCLE per line.
			//		  Warning : Care of single pixel write logic + and non increment of X.

			// TODO : Mask stuff here at IF level too.
			if (i_isValidPixelL || i_isValidPixelR) begin // Line Equation.
				// setEnteredTriangle = 1;	REMOVED, Optimization testing enteredTriangle not necessary anymore.

				if (!i_pixelFound) begin
					setPixelFound	= 1;
				end

				// TODO Pixel writing logic
				if (i_requestNextPixel) begin
//					resetBlockChange = 1;

					// Write only if pixel pair is valid...

					writePixelL	= i_isValidPixelL	 & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
					writePixelR	= i_isValidPixelR	 & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

					// writeStencil2 = { writePixelR , writePixelL };

					// Go to next pair whatever, as long as request is asking for new pair...
					// normally changeX = 1; selNextX = X_TRI_NEXT;	 [!!! HERE !!!]
					loadNext	= 1;
					selNextX	= X_TRI_NEXT;
				end
			end else begin
				// Makes GPU slower but fixed part of a bug (only a part !)
				// When GPU is busy with some memory (like fetching Texture, write back BG, read BG for blending)
				// I stop the triangle scanning...
				// Logically I should not.
				if (i_requestNextPixel) begin
					loadNext	= 1;
					if (i_pixelFound) begin // Pixel Found.
						selNextY		= Y_TRI_NEXT;
						nextWorkState	= SCAN_LINE_CATCH_END;
					end else begin
						// Continue to search for VALID PIXELS...
						selNextX		= X_TRI_NEXT;

						// Trick : Due to FILL CONVENTION, we can reach a line WITHOUT A SINGLE PIXEL !
						// -> Need to detect that we scan too far and met nobody and avoid out of bound search.
						// COMMENTED OUT enteredTriangle test : some triangle do write pixels sparsely when very thin !!!!
						// No choice except scanning until Bbox edge, no early skip...
						if (i_reachEdgeTriScan) begin
							if (i_completedOneDirection) begin
								selNextY				= Y_TRI_NEXT;
								nextWorkState			= SCAN_LINE_CATCH_END;
							end else begin
								switchDir				= 1;
								setDirectionComplete	= 1;
								selNextY				= Y_ASIS;
								nextWorkState			= SCAN_LINE;
							end
						end else begin
							selNextY				= Y_ASIS;
							nextWorkState			= SCAN_LINE;
						end
					end
				end // else do nothing.
			end
		end else begin
			nextWorkState	= FLUSH_COMPLETE_STATE;
		end
	end
	SCAN_LINE_CATCH_END:
	begin
		if (i_isValidPixelL || i_isValidPixelR) begin
			loadNext		= 1;
			selNextX		= X_TRI_NEXT;
		end else begin
			switchDir		= 1;
			resetPixelFound	= 1;
			nextWorkState	= SCAN_LINE;
		end
	end
	// --------------------------------------------------------------------
	//	 RECT STATE MACHINE
	// --------------------------------------------------------------------
	RECT_START:
	begin
		// Rect use PSTORE COMMAND. (2 pix per clock)
		nextWorkState	= RECT_SCAN_LINE;
		stencilReadSig	= 1;
		if (i_earlyTriangleReject | i_isNegXAxis | i_isNegPreB) begin // VALID FOR RECT TOO : Bounding box and draw area do not intersect at all, or NegativeSize => size = 0.
			nextWorkState	= RENDER_WAIT;	// Override state.
		end else begin
			loadNext		= 1;
			selNextX		= X_TRI_BBLEFT;	// Set currX = BBoxMinX intersect X Draw Area.
			selNextY		= Y_TRI_START;	// Set currY = BBoxMinY intersect Y Draw Area.
		end
	end
	RECT_SCAN_LINE:
	begin
		stencilReadSig	= 1;
		if (i_isBottomInsideBBox) begin // Not Y end yet ?
			if (i_isRightPLXmaxTri) begin // Work by pair. Is left side of pair is inside rendering area. ( < right border )
				if (i_requestNextPixel) begin
					// Write only if pixel pair is valid...
					writePixelL	  = i_isInsideBBoxTriRectL & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
					writePixelR	  = i_isInsideBBoxTriRectR & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

					// Go to next pair whatever, as long as request is asking for new pair...
					// normally changeX = 1; selNextX = X_TRI_NEXT;	 [!!! HERE !!!]
					loadNext	= 1;
					selNextX	= X_TRI_NEXT;
				end
			end else begin
				loadNext	= 1;
				selNextX	= X_TRI_BBLEFT;
				selNextY	= Y_TRI_NEXT;
				// No state change... Work on next line...
			end
			nextWorkState	= RECT_SCAN_LINE;
		end else begin
			nextWorkState	= FLUSH_COMPLETE_STATE;
		end
	end
	// --------------------------------------------------------------------
	//	 LINE STATE MACHINE
	// --------------------------------------------------------------------
	LINE_START:
	begin
		/* Line Setup, Triangle setup may be... */
		loadNext		= 1;
		stencilReadSig	= 1;
		selNextX		= X_LINE_START;
		selNextY		= Y_LINE_START;
		nextWorkState	= LINE_DRAW;
	end
	LINE_DRAW:
	begin
		if (i_requestNextPixel) begin
			stencilReadSig	= 1;
			selNextX	= X_LINE_NEXT;
			selNextY	= Y_LINE_NEXT;
			loadNext	= 1;
			if (i_endPixelLine) begin
				nextWorkState	= FLUSH_COMPLETE_STATE; // Override nextWorkState from setup in this.
			end

			// If pixel is valid and (no mask checking | mask check with value = 0)
			if (i_isValidLinePixel) begin	// Clipping DrawArea, TODO: Check if masking apply too.
				writePixelL	 = i_isLineLeftPix;
				writePixelR	 = i_isLineRightPix;
			end
		end
	end
    FLUSH_COMPLETE_STATE:
    begin
        // We stopped emitting pixels, now we have to check that :
        // - No memory transaction is running anymore.
        // - No pixel are in flight.
        if (!i_saveLoadOnGoing && !i_pixelInFlight) begin
            flush = 1'b1;
            nextWorkState = RENDER_WAIT;
        end
    end
	default: begin
		nextWorkState = RENDER_WAIT;
	end
	endcase
end

assign o_loadNext				= loadNext;
assign o_resetXCounter			= resetXCounter;
assign o_writeStencil			= writeStencil;
assign o_stencilReadSig			= stencilReadSig;
assign o_incrementXCounter		= incrementXCounter;
assign o_resetPixelFound		= resetPixelFound;
assign o_setPixelFound			= setPixelFound;
assign o_memorizeLineEqu		= memorizeLineEqu;
assign o_incrementInterpCounter	= incrementInterpCounter;
assign o_switchDir				= switchDir;
assign o_requClutCacheUpdate	= requClutCacheUpdate;
assign o_decClutCount			= decClutCount;
assign o_setDirectionComplete	= setDirectionComplete;
assign o_endClutLoading			= endClutLoading;
assign o_writePixelL			= writePixelL;
assign o_writePixelR			= writePixelR;
assign o_selNextX				= selNextX;
assign o_selNextY				= selNextY;
assign o_memoryCommand			= memoryCommand;
assign o_flush					= flush;

assign o_renderInactiveNextCycle= (currWorkState != RENDER_WAIT) && (nextWorkState == RENDER_WAIT);
assign o_lineStart				= (currWorkState == LINE_START);
endmodule

