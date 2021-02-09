/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_render_mem(
	input					i_clk,
	input					i_nrst,
	input					i_rstCmd,
	input					i_rstGPU,

	input					i_rstTextureCache, 	// Parser
	
	//-----------------------------------------
	// Command parser control CLUT internal unit.
	//-----------------------------------------
	input					i_loadClutPage,
	input			[14:0]	i_fifoDataOutClut,
		
	//-----------------------------------------
	// GPU Registers & Loaded Registers
	//-----------------------------------------
	input					DIP_Allow480i,
	input					DIP_AllowDither,
	input					DIP_ForceDither,
	
	input					GPU_REG_CurrentInterlaceField,
	input					GPU_REG_CheckMaskBit,
	input					GPU_REG_ForcePixel15MaskSet,
    input			[1:0]	GPU_REG_Transparency,
    input			[1:0]	GPU_REG_TexFormat,
    input			[3:0]	GPU_REG_TexBasePageX,
    input					GPU_REG_TexBasePageY,
    input					GPU_REG_TextureXFlip,
    input					GPU_REG_TextureYFlip,
    input			[4:0]	GPU_REG_WindowTextureMaskX,
    input			[4:0]	GPU_REG_WindowTextureMaskY,
    input			[4:0]	GPU_REG_WindowTextureOffsetX,
    input			[4:0]	GPU_REG_WindowTextureOffsetY,
	input					GPU_REG_DitherOn,
	
	input	signed [11:0]	RegX0,
	input	signed [11:0]	RegY0,
	input			[8:0] 	RegR0,
	input			[8:0] 	RegG0,
	input			[8:0] 	RegB0,
	input			[7:0] 	RegU0,
	input			[7:0] 	RegV0,
	input	signed [11:0] 	RegX1,
	input	signed [11:0] 	RegY1,
	input			[8:0] 	RegR1,
	input			[8:0] 	RegG1,
	input			[8:0] 	RegB1,
	input			[7:0] 	RegU1,
	input			[7:0] 	RegV1,
	input	signed [11:0] 	RegX2,
	input	signed [11:0] 	RegY2,
	input			[8:0] 	RegR2,
	input			[8:0] 	RegG2,
	input			[8:0] 	RegB2,
	input			[7:0] 	RegU2,
	input			[7:0] 	RegV2,
	input			[9:0] 	GPU_REG_DrawAreaX0,
	input			[9:0] 	GPU_REG_DrawAreaY0,
	input			[9:0] 	GPU_REG_DrawAreaX1,
	input			[9:0] 	GPU_REG_DrawAreaY1,
	input					GPU_REG_DrawDisplayAreaOn,
	input					GPU_REG_IsInterlaced,
	input					GPU_REG_VerticalResolution,
	
	// Command Parser result (can integrate later, just want to build now)
	input					i_bUseTexture,
	input					i_bIsRectCommand, // Use
	input					i_bIsPolyCommand,
	input					i_bIsLineCommand,
	input					i_bIsPerVtxCol,
	input					i_bOpaque,
	input					i_bSemiTransp, // !i_bOpaque ?
		
	input	[2:0]			i_activateRender,
	output					o_renderInactiveNextCycle,
	output					o_active,

	// -------------------------------
	//   Stencil Cache Write/Read
	// -------------------------------
	output					o_stencilFullMode,
	
	output 					o_stencilWriteSig,
	output	[14:0]			o_stencilWriteAdr,
//	output	 [2:0]			o_stencilWritePair,
//	output	 [1:0]			o_stencilWriteSelect,
	output	[15:0]			o_stencilWriteValue,
	output	[15:0]			o_stencilWriteMask,
	
	output 					o_stencilReadSig,
	output	[14:0]			o_stencilReadAdr,
	input	[15:0]			i_stencilReadValue,

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    output           		o_command,        		// 0 = do nothing, 1 Perform a read or write to memory.
    input            		i_busy,           		// Memory busy 1 => can not use.
    output   [1:0]   		o_commandSize,    		// 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           		o_write,          		// 0=READ / 1=WRITE 
    output [ 14:0]   		o_adr,            		// 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   		o_subadr,         		// Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   		o_writeMask,

    input  [255:0]   		i_dataIn,
    input           		i_dataInValid,
    output [255:0]			o_dataOut
);

wire InterlaceRender		= DIP_Allow480i & ((!GPU_REG_DrawDisplayAreaOn) & GPU_REG_IsInterlaced) & GPU_REG_VerticalResolution & (!i_bIsLineCommand); // [Interlace render for line is CLIPPING PER PIXEL !]

typedef enum logic[4:0] {
	RENDER_WAIT					= 5'd0,
	LINE_START					= 5'd1,
	LINE_DRAW					= 5'd2,
	LINE_END					= 5'd3,
	RECT_START					= 5'd4,
	COPY_INIT					= 5'd6,
	TRIANGLE_START				= 5'd7,
	START_LINE_TEST_LEFT		= 5'd9,
	START_LINE_TEST_RIGHT		= 5'd10,
	SCAN_LINE					= 5'd11,
	SCAN_LINE_CATCH_END			= 5'd12,
	SETUP_INTERP				= 5'd13,
	SETUP_INTERP_REAL			= 5'd14,
	RECT_SCAN_LINE				= 5'd15,
	WAIT_3						= 5'd16,
	WAIT_2						= 5'd17,
	WAIT_1						= 5'd18,
	SELECT_PRIMITIVE			= 5'd19,
	FLUSH_SEND					= 5'd20,
	FLUSH_COMPLETE_STATE		= 5'd21
} workState_t;

//----------------------------------------------------	
workState_t nextWorkState,currWorkState;
always @(posedge i_clk)
	if (i_rstGPU | i_rstCmd)
		currWorkState <= RENDER_WAIT;
	else
		currWorkState <= nextWorkState;
//----------------------------------------------------	

// -2048..+2047
wire signed [11:0]	nextLineY,nextLineX,nextPixelX,nextPixelY;
wire signed [11:0]  minTriDAX0,minTriDAY0,maxTriDAX1;
wire signed [11:0]  pixelX,pixelY;

reg loadNext, stencilReadSig,
	resetPixelFound,
	setPixelFound,
	memorizeLineEqu,
    incrementInterpCounter,
	switchDir,
	requClutCacheUpdate,incClutCount,
	setDirectionComplete,
	endClutLoading,
	flush,
	writePixelL,writePixelR;
wire isValidPixelL,isValidPixelR;
wire earlyTriangleReject;
wire edgeDidNOTSwitchLeftRightBB;
wire isNegXAxis;
wire isLineLeftPix,isLineRightPix;
wire isValidHorizontalTriBbox;
wire isNegPreB;
wire reachEdgeTriScan,isRightPLXmaxTri,isInsideBBoxTriRectL,isInsideBBoxTriRectR,isBottomInsideBBox;

wire signed [8:0] pixRL,pixGL,pixBL,pixRR,pixGR,pixBR;
wire signed [7:0] pixUL,pixVL,pixUR,pixVR;

wire memArbOutputIdle;
wire pausePipeline;
	
reg [2:0]	selNextX,selNextY;

wire waitingWork = (currWorkState == RENDER_WAIT);
wire resetDir 	 = waitingWork;

wire dir,pixelFound,completedOneDirection;
wire isNULLDET;

wire isLineInsideDrawArea;
reg [1:0] stencilReadValue;
always @(*) begin
	case (pixelX[3:1])
	3'd0   : stencilReadValue = i_stencilReadValue[ 1: 0];
	3'd1   : stencilReadValue = i_stencilReadValue[ 3: 2];
	3'd2   : stencilReadValue = i_stencilReadValue[ 5: 4];
	3'd3   : stencilReadValue = i_stencilReadValue[ 7: 6];
	3'd4   : stencilReadValue = i_stencilReadValue[ 9: 8];
	3'd5   : stencilReadValue = i_stencilReadValue[11:10];
	3'd6   : stencilReadValue = i_stencilReadValue[13:12];
	default: stencilReadValue = i_stencilReadValue[15:14];
	endcase
end

wire selectPixelWriteMaskLine = (!pixelX[0] & stencilReadValue[0]) | (pixelX[0] & stencilReadValue[1]);
wire isValidLinePixel =	(
							(isLineInsideDrawArea 																			// VALID AREA
							&& ((!InterlaceRender)    || (InterlaceRender && (GPU_REG_CurrentInterlaceField != pixelY[0])))	// NON INTERLACED OR INTERLACE BUT VALID AREA
							&& ((GPU_REG_CheckMaskBit && (!selectPixelWriteMaskLine)) || (!GPU_REG_CheckMaskBit)))
						);

// ------------------------------------------------
//   Scanner
// ------------------------------------------------
gpu_scan gpu_scan_instance(
	.i_clk							(i_clk),

	.i_InterlaceRender				(InterlaceRender),

	.GPU_REG_CurrentInterlaceField	(GPU_REG_CurrentInterlaceField),
	.i_RegX0						(RegX0),
	.i_RegY0						(RegY0),

	// Line Primitive                / Line Primitive
	.i_nextLineX					(nextLineX),
	.i_nextLineY					(nextLineY),

	// Triangle BBox                 / Triangle BBox
	.i_minTriDAX0					(minTriDAX0),
	.i_minTriDAY0					(minTriDAY0),
	.i_maxTriDAX1					(maxTriDAX1),

	// Scan control for all.         / Scan control for all.
	.i_loadNext						(loadNext),	// All primitive
	.i_selNextX						(nextX_t'(selNextX)),	// All primitive except FILL / CopyVV
	.i_selNextY						(nextY_t'(selNextY)),	// All primitive

	// Current pixel                 / Current pixel
	.o_pixelX						(pixelX),
	.o_pixelY						(pixelY),
	.o_nextPixelX					(nextPixelX),
	.o_nextPixelY					(nextPixelY),
	.o_loopIncrNextPixelY			(/* NOT USED ANYMORE, FILL loopIncrNextPixelY*/),


	//---------------------------------------
	//  Independant Triangle Flags Management
	//---------------------------------------

	// Control 
	.i_tri_resetDir					(resetDir),				// Triangle Only but reset at each primitive
	.i_tri_switchDir				(switchDir),			// Triangle Only
	.i_tri_setPixelFound			(setPixelFound),		// Triangle Only
	.i_tri_setDirectionComplete		(setDirectionComplete),	// Triangle Only
	.i_tri_resetPixelFound			(resetPixelFound),		// Triangle Only

	.o_tri_dir						(dir),					// Triangle Only
	.o_tri_pixelFound				(pixelFound),			// Triangle Only
	.o_tri_completedOneDirection	(completedOneDirection)	// Triangle Only
);

wire lineStart			= (currWorkState == LINE_START);
wire assignRectSetup	= waitingWork;							// Same as (currWorkState == WAIT), we reset default...
wire outsideTriangle	= (edgeDidNOTSwitchLeftRightBB && ((!maxTriDAX1[0] && !isValidPixelL) || (maxTriDAX1[0] && !isValidPixelR)));

// ------------------------------------------------
//   Interpolator Setup Counter
// ------------------------------------------------
reg [4:0]	interpolationCounter;
wire useUV = (i_bUseTexture & !i_bIsLineCommand) & (!i_bIsPerVtxCol);
wire [4:0]		nextInterpolationCounter = interpolationCounter +
											`ifdef DOUBLE_DIVUNIT
												5'd2
											`else
												5'd1
											`endif
											;

wire endInterpCounter = (nextInterpolationCounter[4:2] == { 1'b1, i_bUseTexture , 1'b0 });
always @(posedge i_clk) begin
	if (waitingWork) begin
		// 1100.0  <-- RECT : No loading (end counter)
		// 1000.0  <-- UV Only
		// 0010.0  <-- RGB First
		interpolationCounter <= { useUV,i_bIsRectCommand,!useUV, 2'b00 };
	end else begin
		if (incrementInterpCounter)
			interpolationCounter <= nextInterpolationCounter;
	end
end

gpu_setupunit gpu_setupunit_inst(
	.i_clk							(i_clk),

	.i_bIsLineCommand				(i_bIsLineCommand),
	.i_bIsRectCommand				(i_bIsRectCommand),

	// --------------------------
	// Loaded register
	// --------------------------
	.RegX0							(RegX0),
	.RegY0							(RegY0),
	.RegX1							(RegX1),
	.RegY1							(RegY1),
	.RegX2							(RegX2),
	.RegY2							(RegY2),
	
	.RegR0							(RegR0),
	.RegG0							(RegG0),
	.RegB0							(RegB0),
	.RegU0							(RegU0),
	.RegV0							(RegV0),
	.RegR1							(RegR1),
	.RegG1							(RegG1),
	.RegB1							(RegB1),
	.RegU1							(RegU1),
	.RegV1							(RegV1),
	.RegR2							(RegR2),
	.RegG2							(RegG2),
	.RegB2							(RegB2),
	.RegU2							(RegU2),
	.RegV2							(RegV2),

	// --------------------------
	// GPU registers
	// --------------------------
	.GPU_REG_DrawAreaX0				(GPU_REG_DrawAreaX0),
	.GPU_REG_DrawAreaY0				(GPU_REG_DrawAreaY0),
	.GPU_REG_DrawAreaX1				(GPU_REG_DrawAreaX1),
	.GPU_REG_DrawAreaY1				(GPU_REG_DrawAreaY1),

	// --------------------------
	// State machine Control
	// --------------------------
	// Signal when setup primitive
	.i_interpolationCounter			(interpolationCounter),
	.i_assignRectSetup				(assignRectSetup),
	
	// Line runtime logic control from state machine
	.i_memorizeLineEqu				(memorizeLineEqu),
	.i_lineStart					(lineStart),
	.i_loadNext						(loadNext),
	
	.o_isLineInsideDrawArea			(isLineInsideDrawArea),
	.o_isLineLeftPix				(isLineLeftPix),
	.o_isLineRightPix				(isLineRightPix),

	// Triangle runtime feedback
	.o_isNULLDET					(isNULLDET),
	.o_isNegXAxis					(isNegXAxis),
	.o_isValidPixelL				(isValidPixelL),
	.o_isValidPixelR				(isValidPixelR),
	.o_earlyTriangleReject			(earlyTriangleReject),
	.o_edgeDidNOTSwitchLeftRightBB	(edgeDidNOTSwitchLeftRightBB),
	.o_reachEdgeTriScan				(reachEdgeTriScan),
	.o_isValidHorizontalTriBbox		(isValidHorizontalTriBbox),
	.o_isRightPLXmaxTri				(isRightPLXmaxTri),
	.o_isInsideBBoxTriRectL			(isInsideBBoxTriRectL),
	.o_isInsideBBoxTriRectR			(isInsideBBoxTriRectR),
	.o_isBottomInsideBBox			(isBottomInsideBBox),
		
	.o_isNegPreB					(isNegPreB),
		
	.o_nextLineX					(nextLineX),
	.o_nextLineY					(nextLineY),
		
	.o_minTriDAX0					(minTriDAX0),
	.o_maxTriDAX1					(maxTriDAX1),
	.o_minTriDAY0					(minTriDAY0),
	
	// --------------------------
	// Runtime parameters
	// --------------------------
	.i_pixelX						(pixelX),
	.i_pixelY						(pixelY),
		
	.i_scanDirectionR2L				(dir),
		
	.o_pixRL						(pixRL),
	.o_pixGL						(pixGL),
	.o_pixBL						(pixBL),
	.o_pixUL						(pixUL),
	.o_pixVL						(pixVL),
	
	.o_pixRR						(pixRR),
	.o_pixGR						(pixGR),
	.o_pixBR						(pixBR),
	.o_pixUR						(pixUR),
	.o_pixVR						(pixVR)
);

wire textureFormatTrueColor = (GPU_REG_TexFormat[1]); // (10)2 or (11)3
wire TexCacheWrite;
wire   [16:0]   adrTexCacheWrite;
wire   [63:0]   TexCacheData;
wire			requDataTex_c0L,requDataTex_c0R;
wire  [18:0]	adrTexReq_c0L,adrTexReq_c0R;
wire			TexHit_c1L,TexHit_c1R;
wire			TexMiss_c1L,TexMiss_c1R;
wire [15:0]		dataTex_c1L,dataTex_c1R;

directCacheDoublePort directCacheDoublePortInst(
    .i_clk							(i_clk),
    .i_nrst							(i_nrst),
    .i_clearCache					(i_rstTextureCache),

    // [Can spy all write on the bus and maintain cache integrity]
    .i_textureFormatTrueColor		(textureFormatTrueColor),
    .i_write						(TexCacheWrite),
    .i_adressIn						(adrTexCacheWrite),
    .i_dataIn						(TexCacheData),

    .i_requLookupA					(requDataTex_c0L),
    .i_adressLookA					(adrTexReq_c0L),
    .o_dataOutA						(dataTex_c1L),
    .o_isHitA						(TexHit_c1L),
    .o_isMissA						(TexMiss_c1L),

    .i_requLookupB					(requDataTex_c0R),
    .i_adressLookB					(adrTexReq_c0R),
    .o_dataOutB						(dataTex_c1R),
    .o_isHitB						(TexHit_c1R),
    .o_isMissB						(TexMiss_c1R)
);

// ------------------------------------------------
//   CLUT STUFF
// ------------------------------------------------
//wire clutLoading;
parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;
wire isPalettePrimitive = (!GPU_REG_TexFormat[1]) & i_bUseTexture;
wire CLUTIs8BPP			= (GPU_REG_TexFormat == PIX_8BIT);
wire stillRemainingClutPacket;
wire  [14:0]	adrClutCacheUpdate;
wire isLoadingPalette;
wire   [3:0]	currentClutBlockWrite;

gpu_clutManager clutManagerInstance (
	.i_clk							(i_clk),
	.i_rstGPU						(i_rstGPU),

	// [Parser Timing]
	.i_setClutLoading				(i_loadClutPage),
		.i_rstTextureCache				(i_rstTextureCache),
		.i_fifoDataOutClut				(i_fifoDataOutClut),

	.i_isPalettePrimitive			(isPalettePrimitive),

	// [Palette loading Timing]
	// --- Start ---
	
	.i_issuePrimitive				(i_activateRender != RDR_NONE),	// TODO : look if can't optimize with setClutLoading and also i_is4BitPalette
		.i_CLUTIs8BPP					(CLUTIs8BPP),

	// --- Loop ---
	.i_incClutCount					(incClutCount),
	.o_stillRemainingClutPacket 		(stillRemainingClutPacket),

	// --- End
	.i_endClutLoading				(endClutLoading),
		.i_is4BitPalette				(GPU_REG_TexFormat == PIX_4BIT),
//	.o_isClutLoading		(clutLoading),
	
	// CLUT Memory adress for current clut block request.
	.o_adrClutCacheUpdate			(adrClutCacheUpdate),
	.o_isLoadingPalette				(isLoadingPalette),
	.o_currentClutBlock				(currentClutBlockWrite)
);

wire ClutCacheWrite;
wire [255:0]	ClutCacheData;
wire [7:0]		indexPalL,indexPalR;
wire [15:0]		dataClut_c2L,dataClut_c2R;

CLUT_Cache CLUT_CacheInst(
    .i_clk							(i_clk),
    .i_nrst							(i_nrst),
		
    .i_write						(ClutCacheWrite),
    .i_writeBlockIndex				(currentClutBlockWrite),
    .i_Colors						(ClutCacheData),

    .i_readIdxL						(indexPalL),
    .o_colorEntryL					(dataClut_c2L),
		
    .i_readIdxR						(indexPalR),
    .o_colorEntryR					(dataClut_c2R)
);

// ------------------------------------------------
//
// ------------------------------------------------

wire missTC;

reg [14:0]  prevVRAMAdrBlock;
wire [14:0] currVRAMAdrBlock = {     pixelY[8:0],     pixelX[9:4] };

// ---- Local stuff ------
/*
parameter   IS_NOT_NEWBLOCK				= 2'b00,
            IS_NEW_BLOCK_IN_PRIMITIVE	= 2'b01,	// The first time we flush a 16 pixel block, there is NO WRITE of the previous block, but LOAD must be done if doing blending.
            IS_OTHER_BLOCK_IN_PRIMITIVE	= 2'b10,	// For other block we simply do WRITE the previous block, or WRITE + LOAD next block BG if doing blending.
            IS_FLUSH_LAST_PIXEL			= 2'b11;
*/
// [Set to TRUE each time a new pixel to write is going to a different block of 16 pixel in the target buffer]
wire        differentBlock	= (currVRAMAdrBlock != prevVRAMAdrBlock);	// Next Position is a different block.
// Each time we write VALID pixels, check if we need to push a new block state change spike.
wire		doBlockWork 	= (differentBlock | flagIsNewBlock | flush) & (writePixelL | writePixelR);
// TODO : FLUSH

reg flagIsNewBlock;
always @(posedge i_clk) begin
    if (writePixelL | writePixelR) begin
        prevVRAMAdrBlock <= currVRAMAdrBlock;
    end

    // Give priority to SET over RESET, and ONLY when we write an EFFECTIVE PIXEL.
    if (waitingWork) begin
        flagIsNewBlock <= 1;
    end else begin
        // [Inside the primitive, each time we transition]
        if (doBlockWork) begin	// If first block, then clear the first block.
			flagIsNewBlock <= 0;
        end
    end
end

// -----------------------------------------------------------------------
// Case 00 : do nothing
// Case 01 : READ
// Case 10 : WRITE then READ
// Case 11 : WRITE
// -----------------------------------------------------------------------
parameter	TRANSITION_NONE				= 2'b00,
			TRANSITION_READ 			= 2'b01,
			TRANSITION_WRITE_THEN_READ	= 2'b11,
			TRANSITION_WRITE			= 2'b10;

//
// Transition is information associated with the FIRST NEW PIXEL OF A BLOCK
//
reg [1:0] transitionType;
always @(*) begin
	if (doBlockWork) begin
		if (flagIsNewBlock) begin
			transitionType = i_bSemiTransp ? TRANSITION_READ            : TRANSITION_NONE;
		end else begin
			transitionType = i_bSemiTransp ? TRANSITION_WRITE_THEN_READ : TRANSITION_WRITE;
		end
	end else begin
		transitionType = TRANSITION_NONE;
	end
end

wire ditherSetup			= ( GPU_REG_DitherOn & DIP_AllowDither ) | DIP_ForceDither;
wire bDither				= ditherSetup & (i_bIsPerVtxCol | i_bIsLineCommand);

wire requTexCacheUpdateL,requTexCacheUpdateR,updateTexCacheCompleteL,updateTexCacheCompleteR;
wire  [16:0]   adrTexCacheUpdateL,adrTexCacheUpdateR;
wire  [14:0]   loadAdr,saveAdr;
wire	[1:0]  saveBGBlock;

// BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
wire 			importBGBlockSingleClock;
wire [255:0]	exportedBGBlock,importedBGBlock;
wire [15:0]		exportedMSKBGBlock;
wire			pixelInFlight;
wire [1:0]		o_transitionType;

wire savingBGNow;

GPUBackend GPUBackendInstance(
    .clk							(i_clk),
    .i_nrst							(i_nrst),

    // -------------------------------
    // Control line for state machine
    // -------------------------------
    .i_pausePipeline				(pausePipeline),				// Freeze the data in the pipeline. Values stay as is.
    .o_missTC						(missTC),						// Any Cache miss, stop going next pixels.
    .o_pixelInFlight				(pixelInFlight),
	.o_PixelBlockTransition			(o_transitionType),
	.i_flushClearMask				(savingBGNow & flush),
	
    // -------------------------------
    // GPU Setup
    // -------------------------------
    .GPU_REG_Transparency			(GPU_REG_Transparency),
    .GPU_REG_TexFormat				(GPU_REG_TexFormat),
    .noTexture						(!i_bUseTexture),
    .noblend						(i_bOpaque),
    .ditherActive					(bDither),
    .GPU_REG_TexBasePageX			(GPU_REG_TexBasePageX),
    .GPU_REG_TexBasePageY			(GPU_REG_TexBasePageY),
    .GPU_REG_TextureXFlip			(GPU_REG_TextureXFlip),
    .GPU_REG_TextureYFlip			(GPU_REG_TextureYFlip),
    .GPU_REG_WindowTextureMaskX		(GPU_REG_WindowTextureMaskX),
    .GPU_REG_WindowTextureMaskY		(GPU_REG_WindowTextureMaskY),
    .GPU_REG_WindowTextureOffsetX	(GPU_REG_WindowTextureOffsetX),
    .GPU_REG_WindowTextureOffsetY	(GPU_REG_WindowTextureOffsetY),

    // -------------------------------
    // Input Pixels from FrontEnd
    // -------------------------------
	.i_PixelBlockTransition			(transitionType),
    .iScrX_Mul2						(pixelX[9:0]),
    .iScrY							(pixelY[8:0]),

    .iR_L							(pixRL),
    .iG_L							(pixGL),
    .iB_L							(pixBL),
    .i_U_L 							(pixUL),
    .i_V_L 							(pixVL),
    .i_validPixel_L					(writePixelL),
    .i_bgMSK_L						(stencilReadValue[0] | GPU_REG_ForcePixel15MaskSet),

    .iR_R							(pixRR),
    .iG_R							(pixGR),
    .iB_R							(pixBR),
    .i_U_R 							(pixUR),
    .i_V_R 							(pixVR),
    .i_validPixel_R					(writePixelR),
    .i_bgMSK_R						(stencilReadValue[1] | GPU_REG_ForcePixel15MaskSet),

    // -------------------------------
    //  Request to Cache system ?
    // -------------------------------
    .o_requDataTex_c0L				(requDataTex_c0L),
    .o_adrTexReq_c0L				(adrTexReq_c0L	),
    .i_TexHit_c1L					(TexHit_c1L		),
    .i_TexMiss_c1L					(TexMiss_c1L	),
    .i_dataTex_c1L					(dataTex_c1L	),

    // Request Cache Fill
    .o_requTexCacheUpdate_c1L		(requTexCacheUpdateL),
    .o_adrTexCacheUpdate_c0L		(adrTexCacheUpdateL),
    .i_updateTexCacheCompleteL		(updateTexCacheCompleteL),

    // Clut$ Side
    .o_indexPalL					(indexPalL			),	// Temp
    .i_dataClut_c2L					(dataClut_c2L		),

    // --- Tex$ Side ---
    .o_requDataTex_c0R				(requDataTex_c0R),
    .o_adrTexReq_c0R				(adrTexReq_c0R	),
    .i_TexHit_c1R					(TexHit_c1R		),
    .i_TexMiss_c1R					(TexMiss_c1R	),
    .i_dataTex_c1R					(dataTex_c1R	),

    // Request Cache Fill
    .o_requTexCacheUpdate_c1R		(requTexCacheUpdateR),
    .o_adrTexCacheUpdate_c0R		(adrTexCacheUpdateR),
    .i_updateTexCacheCompleteR		(updateTexCacheCompleteR),

    // Clut$ Side
    .o_indexPalR					(indexPalR			),	// Temp
    .i_dataClut_c2R					(dataClut_c2R		),
	
    // -------------------------------
    //   Stencil Cache Write Back
    // -------------------------------
    // Write
    .o_stencilWriteSig				(o_stencilWriteSig),
    .o_stencilWriteAdr				(o_stencilWriteAdr),
//    .o_stencilWritePair			(o_stencilWritePair),
//    .o_stencilWriteSelect			(o_stencilWriteSelect),
    .o_stencilWriteValue			(o_stencilWriteValue),
	.o_stencilWriteMask				(o_stencilWriteMask),

    // -------------------------------
    //   DDR
    // -------------------------------

    // Ask to write BG
    .o_loadAdr						(loadAdr			),
    .o_saveAdr						(saveAdr			),
    .o_exportedBGBlock				(exportedBGBlock	),
    .o_exportedMSKBGBlock			(exportedMSKBGBlock	),

    // BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
    .i_importBGBlockSingleClock		(importBGBlockSingleClock),
    .i_importedBGBlock				(importedBGBlock)
);

// TODO Handle Mask clearning locally
reg saveBGBuffer;
wire saveLoadOnGoing;
wire saveBGDone;
reg  loadBGBuffer;
//wire saveLoadCompleteNextCycle;

reg [2:0] currStateMemXAction,nextStateMemXAction;
reg       pipeimportBGBlockSingleClock;
always @(posedge i_clk) begin
	if (!i_nrst) begin
		currStateMemXAction <= 3'd0;
		pipeimportBGBlockSingleClock <= 0;
	end else begin
		currStateMemXAction          <= nextStateMemXAction;
		pipeimportBGBlockSingleClock <= importBGBlockSingleClock;
	end
end


wire isDoubleTransition = (o_transitionType == TRANSITION_WRITE_THEN_READ);
always @(*) begin
	nextStateMemXAction = currStateMemXAction;
//	memoryTransaction	= 0;
	loadBGBuffer		= 0;
	saveBGBuffer		= 0;

	case (currStateMemXAction)
	3'd0: begin
		if (!missTC) begin
			if (o_transitionType == TRANSITION_READ) begin
				if (!saveLoadOnGoing) begin
					nextStateMemXAction = 3'd1;
				end
				loadBGBuffer		= !saveLoadOnGoing;
			end else if (o_transitionType[1] || flush) begin // TRANSITION_WRITE or WRITE THEN READ
				// If not a WRITE but also a READ, once WRITE VALIDATED, GO TO THE READ WAIT.
				if (!flush && !saveLoadOnGoing && o_transitionType[0]) begin
					nextStateMemXAction = 3'd2;
				end
				saveBGBuffer		= !saveLoadOnGoing;
			end
		end
	end
	3'd1: begin // Wait END READ Operation.
		if (pipeimportBGBlockSingleClock) begin
			nextStateMemXAction = 3'd0;
		end
	end
	3'd2: begin // Wait to push READ OPERATION.
		if (!saveLoadOnGoing) begin
			// READ Now...
			nextStateMemXAction = 3'd1;
		end
		loadBGBuffer		= !saveLoadOnGoing;
	end
	3'd3: begin
	end
	default: begin
	end
	endcase
//	memoryTransaction = 0;
end

wire memoryTransaction= ((o_transitionType != TRANSITION_NONE) & saveLoadOnGoing) | ((o_transitionType[0] | (currStateMemXAction != 3'd0)) & !pipeimportBGBlockSingleClock);
wire requestNextPixel = (!missTC) & (!memoryTransaction);
assign pausePipeline  = !requestNextPixel;	// Busy to write the BG/read BG/TEX$/CLUT$ memory access.

MemArbRender MemArbRender_instance(
	.gpuClk							(i_clk),
	.i_nRst							(i_nrst),
	
	.requTexCacheUpdateL			(requTexCacheUpdateL),
	.adrTexCacheUpdateL				(adrTexCacheUpdateL),
	.updateTexCacheCompleteL		(updateTexCacheCompleteL),
	
	.requTexCacheUpdateR			(requTexCacheUpdateR),
	.adrTexCacheUpdateR				(adrTexCacheUpdateR),
	.updateTexCacheCompleteR		(updateTexCacheCompleteR),
	
	.adrTexCacheWrite				(adrTexCacheWrite),
	.TexCacheWrite					(TexCacheWrite),
	.TexCacheData					(TexCacheData),
	
	.requClutCacheUpdate			(requClutCacheUpdate),
	.adrClutCacheUpdate				(adrClutCacheUpdate),
	
	.ClutCacheWrite					(ClutCacheWrite),
	.ClutCacheData					(ClutCacheData),
	
//	.isBlending						(i_bSemiTransp),
	.saveBGBlock					(saveBGBuffer/*saveBGBlock*/), // TODO : not that TWO BIT SIGNAL
	.saveAdr						(saveAdr),
	.exportedBGBlock				(exportedBGBlock),
	.exportedMSKBGBlock				(exportedMSKBGBlock),
	.o_blockSaved					(saveBGDone),
	.o_blockSaving					(savingBGNow),
	
	.loadBGBlock					(loadBGBuffer),
	.loadAdr						(loadAdr),
	.importBGBlockSingleClock		(importBGBlockSingleClock),
	.importedBGBlock				(importedBGBlock),
	
	.saveLoadOnGoing				(saveLoadOnGoing),
//	.saveLoadCompleteNextCycle		(saveLoadCompleteNextCycle),

//	.resetPipelinePixelStateSpike	(resetPipelinePixelStateSpike),

	.o_outputIdle                   (memArbOutputIdle),
	
	.o_command						(o_command), 
	.i_busy							(i_busy), 
	.o_commandSize					(o_commandSize), 

	.o_write						(o_write), 
	.o_adr							(o_adr), 
	.o_subadr						(o_subadr), 
	.o_writeMask					(o_writeMask),

	.i_dataIn						(i_dataIn),
	.i_dataInValid					(i_dataInValid),
	.o_dataOut						(o_dataOut)
);

always @(*)
begin
	nextWorkState				= currWorkState;
	loadNext					= 0;
	stencilReadSig				= 0;
	resetPixelFound				= 0;
	setPixelFound				= 0;
	memorizeLineEqu				= 0;
	incrementInterpCounter		= 0;
	switchDir					= 0;
	requClutCacheUpdate			= 0;
	incClutCount				= 0;	
	setDirectionComplete		= 0;
	endClutLoading				= 0;
	writePixelL					= 0;
	writePixelR					= 0;
	flush						= 0;
	
	selNextX					= X_ASIS;
	selNextY					= Y_ASIS;
	
    case (currWorkState)
	RENDER_WAIT:
	begin
		case (i_activateRender)
		RDR_SETUP_INTERP	: nextWorkState = SETUP_INTERP;
		RDR_TRIANGLE_START	: nextWorkState = TRIANGLE_START;
		RDR_LINE_START		: nextWorkState = LINE_START;
		RDR_WAIT_3			: nextWorkState = WAIT_3;
		default				: nextWorkState = RENDER_WAIT;
		endcase
	end
	// --------------------------------------------------------------------
	//	 TRIANGLE STATE MACHINE
	// --------------------------------------------------------------------
	SETUP_INTERP:
	begin
		// INSERT LATENCY TO ALLOW COLOR/UV REGISTER TO BE UPDATED
		// BEFORE WE LAUNCH INTERPOLATION.
		// INTERPOLATOR IS PIPELINED AND THIS INSERTION OF EMPTY STATE
		// IS NECESSARY.
		nextWorkState			= SETUP_INTERP_REAL;
	end
	SETUP_INTERP_REAL:
	begin
		nextWorkState			= endInterpCounter ? WAIT_3 : SETUP_INTERP_REAL;
		incrementInterpCounter	= 1;
	end
	WAIT_3: // 4 cycles to wait
	begin
		// Use this state to wait for end previous memory transaction...
		nextWorkState = (!saveLoadOnGoing) ? WAIT_2 : WAIT_3;
	end
	WAIT_2: // 3 cycles to wait
	begin
		// [TODO] That test could be put outside and checked EARLY --> RECT could skip to RECT_START 3 cycle earlier. Safe for now.
		//		  Did that before but did not checked whole condition --> FF7 Station failed some tiles.
		
		incClutCount = ClutCacheWrite;
		// isPalettePrimitive & rPalette4Bit & CLUTIs8BPP is when nothing changed, EXCEPT WE WENT FROM 4 BIT TO 8 BIT !
		if (isLoadingPalette) begin
			// Not using signal updateClutCacheComplete but could... rely on transaction only.
			if (!saveLoadOnGoing) begin // Wait for an on going memory transaction to complete.
				if (stillRemainingClutPacket) begin
					// And request ours. (Making sure we request when counter is not updated)
					requClutCacheUpdate = (!ClutCacheWrite);
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
		endClutLoading	= isPalettePrimitive;	// Reset flag, even if it was already reset. Force 0.
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
		if (earlyTriangleReject || isNULLDET) begin	// Bounding box and draw area do not intersect at all.
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
		if (isValidPixelL | isValidPixelR) begin // Line equation.
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
		if (outsideTriangle)		// And that we are OUTSIDE OF THE TRIANGLE. (if odd/even pixel, select proper L/R validpixel.) (Could be also a clipped triangle with FULL LINE)
		begin
			selNextY		= Y_TRI_NEXT;
			nextWorkState	= isValidHorizontalTriBbox ? START_LINE_TEST_LEFT : FLUSH_SEND;
		end else begin
			resetPixelFound	= 1;
			stencilReadSig	= 1;
			nextWorkState	= SCAN_LINE;
		end
	end
	SCAN_LINE:
	begin
		if (isBottomInsideBBox) begin
			stencilReadSig	= 1;
			//
			// TODO : Can optimize if LR = 10 when dir = 0, or LR = 01 when dir = 1 to directly Y_TRI_NEXT + SCAN_LINE_CATCH_END, save ONE CYCLE per line.
			//		  Warning : Care of single pixel write logic + and non increment of X.

			// TODO : Mask stuff here at IF level too.
			if (isValidPixelL || isValidPixelR) begin // Line Equation.
				// setEnteredTriangle = 1;	REMOVED, Optimization testing enteredTriangle not necessary anymore.

				if (!pixelFound) begin
					setPixelFound	= 1;
				end

				// TODO Pixel writing logic
				if (requestNextPixel) begin
//					resetBlockChange = 1;

					// Write only if pixel pair is valid...

					writePixelL	= isValidPixelL	 & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
					writePixelR	= isValidPixelR	 & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

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
				if (requestNextPixel) begin
					loadNext	= 1;
					if (pixelFound) begin // Pixel Found.
						selNextY		= Y_TRI_NEXT;
						nextWorkState	= SCAN_LINE_CATCH_END;
					end else begin
						// Continue to search for VALID PIXELS...
						selNextX		= X_TRI_NEXT;

						// Trick : Due to FILL CONVENTION, we can reach a line WITHOUT A SINGLE PIXEL !
						// -> Need to detect that we scan too far and met nobody and avoid out of bound search.
						// COMMENTED OUT enteredTriangle test : some triangle do write pixels sparsely when very thin !!!!
						// No choice except scanning until Bbox edge, no early skip...
						if (reachEdgeTriScan) begin
							if (completedOneDirection) begin
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
			nextWorkState	= FLUSH_SEND;
		end
	end
	SCAN_LINE_CATCH_END:
	begin
		if (isValidPixelL || isValidPixelR) begin
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
		if (earlyTriangleReject | isNegXAxis | isNegPreB) begin // VALID FOR RECT TOO : Bounding box and draw area do not intersect at all, or NegativeSize => size = 0.
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
		if (isBottomInsideBBox) begin // Not Y end yet ?
			if (isRightPLXmaxTri) begin // Work by pair. Is left side of pair is inside rendering area. ( < right border )
				if (requestNextPixel) begin
					// Write only if pixel pair is valid...
					writePixelL	  = isInsideBBoxTriRectL & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
					writePixelR	  = isInsideBBoxTriRectR & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

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
			nextWorkState	= FLUSH_SEND;
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
		if (requestNextPixel) begin
			stencilReadSig	= 1;
			selNextX	= X_LINE_NEXT;
			selNextY	= Y_LINE_NEXT;
			loadNext	= 1;
			if ((pixelX == RegX1) && (pixelY == RegY1)) begin
				nextWorkState	= FLUSH_SEND; // Override nextWorkState from setup in this.
			end

			// If pixel is valid and (no mask checking | mask check with value = 0)
			if (isValidLinePixel) begin	// Clipping DrawArea, TODO: Check if masking apply too.
				writePixelL	 = isLineLeftPix;
				writePixelR	 = isLineRightPix;
			end
		end
	end
    FLUSH_SEND:
    begin
        // We stopped emitting pixels, now we have to check that :
        // - No memory transaction is running anymore.
        // - No pixel are in flight.
        if (!saveLoadOnGoing && !pixelInFlight) begin
			// Making sure that flush is done when texture read have completed and the pipeline has written all the pixel to the BG.
			// NOT SURE ABOUT pixelInFlight alone condition to be OK.
			// => Last value outside of pipeline may not be in registers yet.
			flush = 1'b1;
			if (savingBGNow) begin
				nextWorkState = FLUSH_COMPLETE_STATE;
			end
        end
    end
    FLUSH_COMPLETE_STATE:
	begin
		// Output memory transactions drained
		if (memArbOutputIdle)
			nextWorkState = RENDER_WAIT;
	end
	default: begin
		nextWorkState = RENDER_WAIT;
	end
	endcase
end

assign o_stencilFullMode		= 1;
assign o_stencilReadSig			= stencilReadSig;
assign o_stencilReadAdr			= { nextPixelY[8:0], nextPixelX[9:4] };

assign o_active					= (currWorkState != RENDER_WAIT);
assign o_renderInactiveNextCycle= o_active && (nextWorkState == RENDER_WAIT);

endmodule
