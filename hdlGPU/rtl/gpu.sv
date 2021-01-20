/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/*
    POSSIBLE OPTIMIZATION :
    - Line outside draw area check optimization can be added.
    - Triangle Setup avoid R,G,B setup division latency if all same vertex color (or white) : (!bIsPerVtxCol) | bIgnoreColor ?
    - Triangle 'snake' parsing can be optimized in cycle count.
    - State Machine for RGBUV setup division latency can be optimized. (Now 6 cycle latency implementation -> 5 or 4 ?)
    - Use an INVERSE instead of division per component. --> Inverse of DET can be computed a few step earlier.
        While loading UVRGB... as soon as coordinates are loaded.
    - If target Mhz can not be reached,
        Store intermediate result from previous state into registers.
        Ex : Copy, Triangle stuff, etc...
 */
module gpu
//	import gpuPack::*;
    (
    input			clk,
    input			i_nrst,

    // --------------------------------------
    // DIP Switches to control
	input			DIP_AllowDither,
	input			DIP_ForceDither,
	input			DIP_Allow480i,
    // --------------------------------------

    output			IRQRequest,

	// WRITE/UPLOAD : Outside->GPU
	// - GPU Request data on REQ
	// - Data valid on ACK.
	// GPU->Outside
	// - Data valid on REQ.
	// - DMA Validate the value and requires the next one. with ACK.
	//
	// NOTE : DMA Controller MUST ignore REQ pin and NOT ISSUE ACK when not active.
	output          gpu_m2p_dreq_i,
	input           gpu_m2p_valid_o,
	input [ 31:0]   gpu_m2p_data_o,
	output          gpu_m2p_accept_i,

	output           gpu_p2m_dreq_i,
	output           gpu_p2m_valid_i,
	output  [ 31:0]  gpu_p2m_data_i,
	input            gpu_p2m_accept_o,
	
	output	[31:0]	mydebugCnt,
	output          dbg_canWrite,

    // --------------------------------------
    // Timing / Display
    // --------------------------------------
	// [Current display thingy on FPGA BOARD]
    // GPU -> Display
    output [  9:0]  display_res_x_o,
    output [  8:0]  display_res_y_o,
    output [  9:0]  display_x_o,
    output [  8:0]  display_y_o,
    output          display_interlaced_o,
    output          display_pal_o,
    // Display -> GPU
    input           display_field_i,
    input           display_hblank_i,
    input           display_vblank_i,
	// --------------------------------------
	
	/* My old interface
	input			i_gpuPixClk,
	output			o_HBlank,
	output			o_VBlank,
	output			o_HSync,
	output			o_VSync,
	output			o_DotClk,
	output			o_DotEnable,
	output [9:0]	o_HorizRes,
	output [8:0]	o_VerticalRes,
	output [9:0]	o_DisplayBaseX,
	output [8:0]	o_DisplayBaseY,
	output			o_IsInterlace,
	output			o_CurrentField,
	*/
	
    // --------------------------------------
    // Memory Interface
    // --------------------------------------
	/*
    output [19:0]   adr_o,   // ADR_O() address
    input  [31:0]   dat_i,   // DAT_I() data in
    output [31:0]   dat_o,   // DAT_O() data out
    output  [2:0]	cnt_o,
    output  [3:0]   sel_o,
    output			wrt_o,
    output			req_o,
    input			ack_i,
	*/
	input			 clkBus,
    output           o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input            i_busy,           // Memory busy 1 => can not use.
    output   [1:0]   o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]   o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   o_writeMask,

    input  [255:0]   i_dataIn,
    input            i_dataInValid,
    output [255:0]   o_dataOut,
	
    /*
    output			hSync,
    output			vSync, // cSync pin exist in real HW : hSync | vSync most likely
    output			hBlank,
    output			vBlank,
    */

    /*
    input	[14:0]	iaddrWord,
    input	[15:0]	iwriteBitSelect,
    input	[15:0]	iwriteBitValue,
    output	[15:0]	oStencilOut,
    */

    // --------------------------------------
	//   CPU Bus
    // --------------------------------------
    input			gpuAdrA2, // Called A2 because multiple of 4
    input			gpuSel,
    input			write,
    input			read,
    input 	[31:0]	cpuDataIn,
    output  [31:0]	cpuDataOut,
    output 			validDataOut
);

wire isFifoFullLSB, isFifoFullMSB,isFifoEmptyLSB, isFifoEmptyMSB;
wire isINFifoFull;
wire isFifoEmpty32;
wire isFifoNotEmpty32;
wire rstInFIFO;

// Note : we do not have the problem of over transfer in FIFO IN, as DMA know transfer size.
// But in case we still REQ and DMA was reloaded super fast, we would need to put a COUNTER in the GPU
// that would compute size based on command parameters instead of this check...
// wire reqDataDMAIn	= (currWorkState == COPYCV_START) || (currWorkState == COPYCV_COPY);
// wire reqDataDMAOut  = (currWorkState == COPYVC_TOCPU);
//                      CPU to VRAM transfer + in transfer state + FIFO has space to store data.
//                      => Should not overtransfer because DMA knows size.
// DMA REQ
typedef enum logic[1:0] {
	DMA_DirOff		= 2'd0,
	DMA_FIFO		= 2'd1,
	DMA_CPUtoGP0	= 2'd2,
	DMA_GP0toCPU	= 2'd3
} DMADirection;

DMADirection      GPU_REG_DMADirection;
reg firstRead;
reg unconsummed;
wire [31:0] outFIFO_readV;

assign gpu_m2p_dreq_i   = ((GPU_REG_DMADirection == DMA_CPUtoGP0) && (isFifoEmptyLSB && isFifoEmptyMSB));
assign gpu_m2p_accept_i = 1'b1;

assign gpu_p2m_dreq_i  = ((GPU_REG_DMADirection == DMA_GP0toCPU) && (!firstRead) && unconsummed);
assign gpu_p2m_valid_i = gpu_p2m_dreq_i;
assign gpu_p2m_data_i  = outFIFO_readV;

// Notes: Manually sending/reading data by software (non-DMA) is ALWAYS possible, regardless of the GP1(04h) setting. The GP1(04h) setting does affect the meaning of GPUSTAT.25.

typedef enum logic[5:0] {
    NOT_WORKING_DEFAULT_STATE	= 6'd0,
    LINE_START					= 6'd1,
    LINE_DRAW					= 6'd2,
    RECT_START					= 6'd3,
    FILL_START					= 6'd4,
    COPY_INIT					= 6'd5,
    TRIANGLE_START				= 6'd6,
    FILL_LINE  					= 6'd7,
    COPYCV_START 				= 6'd8,
    COPYVC_START 				= 6'd9,
    CPY_RS1						= 6'd10,
    CPY_R1						= 6'd11,
    CPY_RS2						= 6'd12,
    CPY_R2						= 6'd13,
    CPY_LWS1					= 6'd14,
    CPY_LW1						= 6'd15,
    CPY_LRS						= 6'd16,
    CPY_LR						= 6'd17,
    CPY_WS2						= 6'd18,
    CPY_W2						= 6'd19,
    CPY_WS3						= 6'd20,
    CPY_W3						= 6'd21,
    START_LINE_TEST_LEFT		= 6'd22,
    START_LINE_TEST_RIGHT		= 6'd23,
    SCAN_LINE					= 6'd24,
    SCAN_LINE_CATCH_END			= 6'd25,
    TMP_2 						= 6'd26,
    TMP_3 						= 6'd27,
    TMP_4 						= 6'd28,
    SETUP_INTERP				= 6'd29,
    RECT_SCAN_LINE				= 6'd30,
    WAIT_3						= 6'd31,
    WAIT_2						= 6'd32,
    WAIT_1						= 6'd33,
    SELECT_PRIMITIVE			= 6'd34,
    COPYCV_COPY					= 6'd35,
    RECT_READ_MASK				= 6'd36,
    COPYVC_TOCPU				= 6'd37,
    LINE_END					= 6'd38,
    FLUSH_COMPLETE_STATE		= 6'd39,
    COPY_START_LINE				= 6'd40,
    CPY_ENDLINE					= 6'd41,
	COPYVC_WAITFLUSH			= 6'd42
} workState_t;

// Quartus did not like
`ifdef VERILATOR
//parameter
typedef enum logic[2:0] {
    X_TRI_NEXT		= 3'd1,
    X_LINE_START	= 3'd2,
    X_LINE_NEXT		= 3'd3,
    X_TRI_BBLEFT	= 3'd4,
    X_TRI_BBRIGHT	= 3'd5,
    X_ASIS			= 3'd0,
    // 7 free...
    X_CV_START		= 3'd6
} nextX_t;

//parameter
typedef enum logic[2:0] {
    Y_LINE_START	= 3'd1,
    Y_LINE_NEXT		= 3'd2,
    Y_TRI_START		= 3'd3,
    Y_TRI_NEXT		= 3'd4,
    Y_CV_ZERO		= 3'd5,
    // 6,7 free...
    Y_ASIS			= 3'd0
} nextY_t;
`endif

parameter   IS_NOT_NEWBLOCK				= 2'b00,
            IS_NEW_BLOCK_IN_PRIMITIVE	= 2'b01,	// The first time we flush a 16 pixel block, there is NO WRITE of the previous block, but LOAD must be done if doing blending.
            IS_OTHER_BLOCK_IN_PRIMITIVE	= 2'b10,	// For other block we simply do WRITE the previous block, or WRITE + LOAD next block BG if doing blending.
            IS_FLUSH_LAST_PIXEL			= 2'b11;

parameter TRANSP_HALF=2'd0, TRANSP_ADD=2'd1, TRANSP_SUB=2'd2, TRANSP_ADDQUARTER=2'd3;
parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;

parameter XRES_256  =2'd0, XRES_320   =2'd1, XRES_512  =2'd2, XRES_640  =2'd3;
parameter DMADIR_OFF=2'd0, DMADIR_FIFO=2'd1, DMADIR_C2G=2'd2, DMADIR_G2C=2'd3;

parameter SIZE_VAR	= 2'd0, SIZE_1x1 = 2'd1, SIZE_8x8 = 2'd2, SIZE_16x16 = 2'd3;
parameter NO_ISSUE = 5'd0, ISSUE_TRIANGLE = 5'b00001,ISSUE_RECT = 5'b00010,ISSUE_LINE = 5'b00100,ISSUE_FILL = 5'b01000,ISSUE_COPY = 5'b10000;

/* VERILATOR DID NOT LIKE IT !!!!!
typedef struct packed {
    logic       storeCommand;
    logic       resetVertexCounter;
    logic       increaseVertexCounter;
    logic       loadRGB,loadUV,loadVertices,loadAllRGB;
    logic       loadE5Offsets;
    logic       loadTexPageE1;
    logic       loadTexWindowSetting;
    logic       loadDrawAreaTL;
    logic       loadDrawAreaBR;
    logic       loadMaskSetting;
    logic       setIRQ;
    logic       rstTextureCache;
    logic       loadClutPage;
    logic       loadTexPage;
    logic       loadSize;
    logic       loadCoord1,loadCoord2;
    logic       loadRectEdge;
    logic       preCheckCLUT;
    logic [1:0] loadSizeParam;
    logic [4:0] issuePrimitive;
 } issue_t;
 */
wire bIsCopyVVCommand,bIsCopyCVCommand,bIsRectCommand,bIsPolyCommand,bSemiTransp,bOpaque,bIsCopyCommand,bUseTextureParser,bIsPerVtxCol,bIsLineCommand;
wire [1:0] loadSizeParam;
wire [4:0] issuePrimitive;

parameter	MEM_CMD_PIXEL2VRAM	= 3'b001,
            MEM_CMD_FILL		= 3'b010,
            MEM_CMD_RDBURST		= 3'b011,
            MEM_CMD_WRBURST		= 3'b100,
			MEM_CMD_VRAM2CPU	= 3'b101,
            // Other command to come later...
            MEM_CMD_NONE		= 3'b000;

// ----------------------------- Parsing Stage -----------------------------------
reg signed [10:0] GPU_REG_OFFSETX;
reg signed [10:0] GPU_REG_OFFSETY;
reg         [3:0] GPU_REG_TexBasePageX;
reg               GPU_REG_TexBasePageY;
reg         [1:0] GPU_REG_Transparency;
reg         [1:0] GPU_REG_TexFormat;
reg               GPU_REG_DitherOn;
reg               GPU_REG_DrawDisplayAreaOn;
reg               GPU_REG_TextureDisable;
reg               GPU_REG_TextureXFlip;
reg               GPU_REG_TextureYFlip;
reg         [4:0] GPU_REG_WindowTextureMaskX;
reg         [4:0] GPU_REG_WindowTextureMaskY;
reg         [4:0] GPU_REG_WindowTextureOffsetX;
reg         [4:0] GPU_REG_WindowTextureOffsetY;
reg         [9:0] GPU_REG_DrawAreaX0;
reg         [9:0] GPU_REG_DrawAreaY0;				// 8:0 on old GPU.
reg         [9:0] GPU_REG_DrawAreaX1;
reg         [9:0] GPU_REG_DrawAreaY1;				// 8:0 on old GPU.
reg               GPU_REG_ForcePixel15MaskSet;		// Stencil force to 1.
reg               GPU_REG_CheckMaskBit; 			// Stencil Read/Compare Enabled

reg               GPU_REG_IRQSet;
reg               GPU_REG_DisplayDisabled;
reg               GPU_REG_IsInterlaced;
reg               GPU_REG_BufferRGB888;
reg               GPU_REG_VideoMode;
reg               GPU_REG_VerticalResolution;
reg         [1:0] GPU_REG_HorizResolution;
reg               GPU_REG_HorizResolution368;
reg				  GPU_REG_ReverseFlag;

//---------------------------------------------------------------
//  Video Module START
//---------------------------------------------------------------
reg			[9:0]	GPU_REG_DispAreaX;
reg			[8:0]	GPU_REG_DispAreaY;
reg			[11:0]	GPU_REG_RangeX0;
reg			[11:0]	GPU_REG_RangeX1;
reg			[9:0]	GPU_REG_RangeY0;
reg			[9:0]	GPU_REG_RangeY1;

/* === MY OLD VIDEO SYSTEM ===
wire				GPU_REG_CurrentInterlaceField;
wire 		[9:0]	horizRes;
wire				currentLineOddEven,VBlank;

GPUVideo GPUVideo_inst(
	.i_gpuPixClk		(i_gpuPixClk),
	.i_nRst				(i_nrst),

	.i_PAL				(GPU_REG_VideoMode),
	.i_IsInterlace		(GPU_REG_IsInterlaced),

	.GPU_REG_HorizResolution368	(GPU_REG_HorizResolution368),
	.GPU_REG_HorizResolution	(GPU_REG_HorizResolution),

	.GPU_REG_RangeX0	(GPU_REG_RangeX0),
	.GPU_REG_RangeX1	(GPU_REG_RangeX1),
	.GPU_REG_RangeY0	(GPU_REG_RangeY0),
	.GPU_REG_RangeY1	(GPU_REG_RangeY1),

	.o_dotClockFlag		(o_DotClk),
	.o_dotEnableFlag	(o_DotEnable),
	.o_hbl				(o_HBlank),
	.o_vbl				(VBlank),
	.o_hSync			(o_HSync),
	.o_vSync			(o_VSync),

	.currentInterlaceField	(GPU_REG_CurrentInterlaceField),
	.widthDisplay		(horizRes),
	.currentLineOddEven	(currentLineOddEven)
);

assign o_HorizRes		= horizRes;
assign o_IsInterlace	= (GPU_REG_VerticalResolution & GPU_REG_IsInterlaced);
assign o_VerticalRes	= o_IsInterlace ? 9'd480 : 9'd240;
assign o_CurrentField   = GPU_REG_IsInterlaced & (!GPU_REG_CurrentInterlaceField);	// Note : DISPLAY CURRENT FIELD IS OPPOSITE TO RENDER CURRENT FIELD (
assign o_DisplayBaseX	= GPU_REG_DispAreaX;
assign o_DisplayBaseY	= GPU_REG_DispAreaY;
assign o_VBlank			= VBlank;
*/

//===============================================================
//  Ultra Temporary/Hack Display Module
//===============================================================
wire VBlank = display_vblank_i;

// NOTE: GPU render frame is the opposite to the display field
wire GPU_REG_CurrentInterlaceField = ~display_field_i;

// Generate odd even line status bit
reg currentLineOddEven;

always @ (posedge clk)
if (!i_nrst)
    currentLineOddEven <= 1'b0;
else if (display_vblank_i)
    currentLineOddEven <= 1'b0;
else if (display_hblank_i)
    currentLineOddEven <= ~currentLineOddEven;

reg [9:0] horizRes;

always @ *
begin
    horizRes = 10'd368;

    if (!GPU_REG_HorizResolution368)
    begin
        case (GPU_REG_HorizResolution)
        2'd0 /*256*/: horizRes = 10'd256;
        2'd1 /*320*/: horizRes = 10'd320;
        2'd2 /*512*/: horizRes = 10'd512;
        2'd3 /*640*/: horizRes = 10'd640;
        endcase
    end
end

assign display_res_x_o      = horizRes;
assign display_res_y_o      = (GPU_REG_VerticalResolution & GPU_REG_IsInterlaced) ? 9'd480 : 9'd240;
assign display_interlaced_o	= GPU_REG_IsInterlaced;
assign display_x_o          = GPU_REG_DispAreaX;
assign display_y_o          = GPU_REG_DispAreaY;
assign display_pal_o        = GPU_REG_VideoMode;

//---------------------------------------------------------------
//  Video Module END
//---------------------------------------------------------------

//---------------------------------------------------------------------------------------------------
// Stuff to handle INTERLACED RENDERING !!!
//
// If [DISABLE WRITE ON DISPLAY] + [INTERLACE] + [RESOLUTION==480] + [NOT A COPY COMMAND] : SPECIAL RENDERING MODE ENABLED
wire GPU_DisplayEvenOddLinesInterlace	= VBlank ? 1'd0 : (GPU_REG_VerticalResolution ? GPU_REG_CurrentInterlaceField : currentLineOddEven);

// [Interlace render generate 1 for primitive supporting it : LINE,RECT,TRIANGLE,FILL IF VALID]
wire InterlaceRender					= DIP_Allow480i & ((!GPU_REG_DrawDisplayAreaOn) & GPU_REG_IsInterlaced) & GPU_REG_VerticalResolution & (!bIsCopyCommand) & (!bIsLineCommand);
// HACK: Disable interlace support
//wire InterlaceRender = 1'b0;

reg [31:0] regGpuInfo;

wire rstGPU;
wire rstCmd;
wire readFifo;
wire saveLoadOnGoing;

reg [2:0]		memoryCommand;

// -2048..+2047
wire signed [11:0] RegX0;
wire signed [11:0] RegY0;
wire  [8:0] RegR0;
wire  [8:0] RegG0;
wire  [8:0] RegB0;
wire  [7:0] RegU0;
wire  [7:0] RegV0;
wire signed [11:0] RegX1;
wire signed [11:0] RegY1;
wire  [8:0] RegR1;
wire  [8:0] RegG1;
wire  [8:0] RegB1;
wire  [7:0] RegU1;
wire  [7:0] RegV1;
wire signed [11:0] RegX2;
wire signed [11:0] RegY2;
wire  [8:0] RegR2;
wire  [8:0] RegG2;
wire  [8:0] RegB2;
wire  [7:0] RegU2;
wire  [7:0] RegV2;


reg [15:0] RegCLUT;
wire [10:0] RegSizeW;
wire [ 9:0] RegSizeH;
wire [ 9:0] OriginalRegSizeH;

// FIFO is empty or next stage still busy processing the last primitive.

reg [1:0] vertCnt;
reg       isFirstVertex;

// For RECT Commands.


wire [31:0] reg1Out;

// [UNCONNECTED FOR NOW]
wire commandFifoFull, commandFifoComplete;

wire  [1:0]		saveBGBlock;
wire [14:0]		saveAdr,loadAdr;
wire [255:0]	exportedBGBlock;
wire [15:0]		exportedMSKBGBlock;
// BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
wire 			importBGBlockSingleClock;
wire [255:0]	importedBGBlock;


// ------------------------------------------------
//    Plumbing GPUBackend<->MemoryArbitrator
// ------------------------------------------------
// -- TEX$ Stuff --
// TEX$ Cache miss from L Side
// TEX$ Cache miss from R Side
wire           requTexCacheUpdateL_i,requTexCacheUpdateR_i;
wire  [16:0]   adrTexCacheUpdateL_i,adrTexCacheUpdateR_i;
wire           updateTexCacheCompleteL_o,updateTexCacheCompleteR_o;
// ------------------------------------------------

// [Main State machine signals from pipeline]
wire missTC;
wire writePixelOnNewBlock;
wire pausePipeline = commandFifoFull | writePixelOnNewBlock | missTC;	// Busy to write the BG/read BG/TEX$/CLUT$ memory access.
wire resetPipelinePixelStateSpike;
// MEMO BEFORE_TEXTURE : resetPixelOnNewBlock only, no !lastMissTC
wire resetMask;

// ------------------------------------------------
//    Plumbing MemoryArbitrator<->CLUT
// ------------------------------------------------
// CLUT$ feed updated $ data to cache.
wire        	ClutCacheWrite;
wire  [2:0]		ClutWriteIndex;
wire [31:0]		ClutCacheData;
wire			clutNeedLoading;

wire [7:0]		indexPalL,indexPalR;
wire [15:0]		dataClut_c2L,dataClut_c2R;
wire 			CLUTIs8BPP	= (GPU_REG_TexFormat == PIX_8BIT);
wire			busyCLUT;
// ------------------------------------------------

// ------------------------------------------------
//    Plumbing
// ------------------------------------------------
// TEX$ feed updated $ data to cache.
wire            TexCacheWrite;
wire   [16:0]   adrTexCacheWrite;
wire   [63:0]   TexCacheData;

wire			requDataTex_c0L,requDataTex_c0R;
wire  [18:0]	adrTexReq_c0L,adrTexReq_c0R;
wire			TexHit_c1L,TexHit_c1R;
wire			TexMiss_c1L,TexMiss_c1R;
wire [15:0]		dataTex_c1L,dataTex_c1R;

wire [1:0]		stencilReadValue;

wire  [9:0]		scrY;

wire pixelInFlight;

wire signed [11:0] pixelX,pixelY;

reg [7:0] RegCommand;

workState_t currWorkState,nextWorkState;

reg		resetXCounter;
wire	endVertical;

nextX_t selNextX;
nextY_t selNextY;

wire		doBlockWork;

// State machine for triangle
// State to control setup...
reg [4:0]		interpolationCounter;
reg             setInterCounter, setInterTexOnly, incrementInterpCounter;
`define DOUBLE_DIVUNIT
wire [4:0]		nextInterpolationCounter = 
											`ifdef DOUBLE_DIVUNIT
												5'd2
											`else
												5'd1
											`endif
											;
always @(posedge clk) begin
	if (setInterCounter) begin
		interpolationCounter <= { 1'b0,setInterTexOnly,!setInterTexOnly, 2'b00 };
	end else begin
		if (incrementInterpCounter)
			interpolationCounter <= nextInterpolationCounter;
	end
end

reg				resetDir;
reg				switchDir;
reg				loadNext;
reg				setPixelFound;
reg				setDirectionComplete;
reg				resetPixelFound;
reg				completedOneDirection;
reg				memorizeLineEqu;
reg IncY;

// reg				readStencil;
// reg	[1:0]		writeStencil2;
reg				assignRectSetup;
// Manage the adress of 16 pixel buffer cache for the BG (read/write) inside the Memory Manager
// Need to be outside because controlled by main state machine.
reg	[14:0]		PixelBGAdr;
// reg isLoaded;
// reg isWritten; // USE notMemoryBusyCurrCycle in state machine.
reg	[2:0]		setStencilMode;
reg 			writeStencil;
reg				copyCVMode;

// ------------------------------------------------------------------------
//   Plumbing
reg				stencilFullMode;
reg  	[15:0]	stencilWriteValue16, stencilWriteMask16;

wire  	[15:0]	stencilReadValue16;
wire 			stencilWriteSig;
reg				stencilReadSig;
wire  	[14:0]	stencilWriteAdr,stencilReadAdr;
wire  	 [2:0]	stencilReadPair,stencilWritePair;
wire	 [1:0]	stencilReadSelect,stencilWriteValue,stencilWriteSelect;

reg 			stencilWriteSigC;
reg  	[14:0]	stencilWriteAdrC;
reg 	[2:0]	stencilWritePairC;
reg	 	[1:0]	stencilWriteSelectC,stencilWriteValueC;
// ------------------------------------------------------------------------



wire				requestNextPixel;

wire        		selectPixelWriteMaskLine;

// -- mike moved

wire  [5:0] adrXSrc;
wire  [5:0] adrXDst;

wire       performSwitch;
reg         cpyBank;
reg			resetBank, switchBank;
wire xCopyDirectionIncr;
wire [4:0] tmpidx;
wire [3:0] cpyIdx;
wire [8:0]	scrDstY;
reg	 [ 6:0] counterXDst;


// ------------------ Debug Stuff --------------

reg [31:0] rdebugCnt;
always @(posedge clk)
begin
    if (i_nrst == 0) begin
        rdebugCnt <= 32'd0;
    end else begin
        rdebugCnt <= rdebugCnt + 32'd1;
    end
end
assign mydebugCnt =rdebugCnt;
wire   canWriteFIFO = !isINFifoFull;
assign dbg_canWrite = canWriteFIFO;

// ---------------------------------------------

// [FIFO Signal for the VRAM Read to CPU]
wire outFIFO_empty;
wire outFIFO_full;

wire writeFifo		= (!gpuAdrA2 & gpuSel & write & canWriteFIFO) || (gpu_m2p_valid_o && (GPU_REG_DMADirection == DMA_CPUtoGP0));
wire writeGP1		=  gpuAdrA2 & gpuSel & write;
wire cpuReadFifoOut = (gpuSel & !gpuAdrA2) & read;

// READ FIFO WHEN :
// - Data is already available in the FIFO.
// - When it is a CPU READ
//   OR WHEN DOING DMA TRANSFER
// - When force FIFO to present value first time before.
// - When it is reading current value, kick the next value with DMA_ACK.
wire        outFIFO_read = ((((GPU_REG_DMADirection == DMA_GP0toCPU) && (!unconsummed || firstRead))) || cpuReadFifoOut) && (!outFIFO_empty);

// Pipeline FIFO read to validate data out (1 cycle latency)
reg pReadFifoOut;
reg pACK;
always @(posedge clk) begin
    if (i_nrst == 0) begin
        pReadFifoOut <= 1'd0;
		unconsummed  <= 1'b1;
    end else begin
		if (outFIFO_read) begin
			firstRead   <= 1'b0;
			unconsummed <= 1'b1;
		end else begin
			if ((gpu_p2m_accept_o || cpuReadFifoOut) & unconsummed) begin
				unconsummed <= 1'b0;
			end
		end
		if (currWorkState == COPYVC_START) begin
			firstRead   <= 1'b1;
		end
		pReadFifoOut <= outFIFO_read;
    end
end

// [TODO NEXT STEP BUS]
//---------------------------------------------------------------
//  Handling READ including pipelined latency for read result.
//---------------------------------------------------------------
reg [31:0] pDataOut;
reg        pDataOutValid;
reg [31:0] dataOut;
reg        dataOutValid;
always @(*)
begin
	// Register +4 Read
	if (gpuAdrA2) begin
		dataOut	=  reg1Out;
	end else begin
		if ((RegCommand == 8'hC0) && (currWorkState != NOT_WORKING_DEFAULT_STATE)) begin
			dataOut = outFIFO_readV;
		end else begin
			dataOut	= regGpuInfo;
		end
	end
end

always @(posedge clk) begin
	pDataOut		<= dataOut;
	pDataOutValid	<= (gpuSel & read);
end
assign cpuDataOut	= pDataOut;
assign validDataOut = pDataOutValid;
//---------------------------------------------------------------
//END [TODO NEXT STEP BUS]

assign IRQRequest = GPU_REG_IRQSet;

wire [31:0] fifoDataOut;
assign isINFifoFull     = isFifoFullLSB  | isFifoFullMSB;
assign isFifoEmpty32    = isFifoEmptyLSB | isFifoEmptyMSB;
assign isFifoNotEmpty32 = !isFifoEmpty32;
assign rstInFIFO        = rstGPU | rstCmd;

wire readLFifo, readMFifo;
wire readFifoLSB	= readFifo | readLFifo;
wire readFifoMSB	= readFifo | readMFifo;

wire [55:0] memoryWriteCommand;



reg  [52:0] parameters;
assign memoryWriteCommand = { parameters, memoryCommand};

wire commandFIFOaccept = ((!commandFifoFull) && !saveLoadOnGoing);

reg	swap;
reg				regSaveL,regSaveM;
wire [15:0] LPixel = swap ? fifoDataOut[31:16] : fifoDataOut[15: 0];
wire [15:0] RPixel = swap ? fifoDataOut[15: 0] : fifoDataOut[31:16];
wire validL        = swap ? regSaveM : regSaveL;
wire validR        = swap ? regSaveL : regSaveM;
reg flush;

reg	 [ 6:0] counterXSrc /* ,counterXDst*/;
wire [5:0] scrSrcX = adrXSrc[5:0] + RegX0[9:4];
wire [5:0] scrDstX = adrXDst[5:0] + RegX1[9:4];
wire cmd1ValidL = (validL & !GPU_REG_CheckMaskBit) | (validL & (!stencilReadValue[0]));
wire cmd1ValidR = (validR & !GPU_REG_CheckMaskBit) | (validR & (!stencilReadValue[1]));
wire WRPixelL15 = LPixel[15] | GPU_REG_ForcePixel15MaskSet; // No sticky bit from source.
wire WRPixelR15 = RPixel[15] | GPU_REG_ForcePixel15MaskSet; // No sticky bit from source.

wire  [15:0] maskRead16;
reg			clearBank0, clearBank1;
reg			clearOtherBank;
wire		writeBankOld = performSwitch & (cpyBank ^ (!xCopyDirectionIncr));
always @(*)
begin
    case (memoryCommand)
	MEM_CMD_VRAM2CPU:      parameters = 	{ 16'dx															// [55:40] IGNORE, SAME AS MEM_CMD_PIXEL2VRAM
                                            , 16'dx															// [39:24] IGNORE
                                            , 2'dx															// [23:22]
                                            , { scrY[8:0], pixelX[9:4] }									// [21: 7]
                                            , pixelX[3:1]													// [ 6: 4]
                                            , 1'dx
                                            };
    // CPU 2 VRAM : [16,16,2,15,...]
    MEM_CMD_PIXEL2VRAM:    parameters = 	{ { WRPixelR15 , RPixel[14:0] }									// [55:40] RIGHT PIXEL
                                            , { WRPixelL15 , LPixel[14:0] }									// [39:24] LEFT PIXEL
                                            , cmd1ValidR, cmd1ValidL										// [23:22]
                                            , { scrY[8:0], pixelX[9:4] }									// [21: 7]
                                            , pixelX[3:1]													// [ 6: 4]
                                            , flush 														// [    3]
                                            };
    // FILL MEMORY SEGMENT
    MEM_CMD_FILL:			parameters =	{ { 1'b0, RegB0[7:3] , RegG0[7:3] , RegR0[7:3] }				// [55:40]
                                            , 16'd0															// [39:24]
                                            , 1'b1 // Dont care, but used in check SW.						// [23]
                                            , 1'b0															// [22]
                                            , { scrY[8:0], scrSrcX }										// [21:7]
                                            , 3'd0															// [ 6:4]
                                            , 1'b1															// [   3]
                                            };
    // READ A 16 PIXEL DATA BURST.
    MEM_CMD_RDBURST:		parameters =	{ maskRead16													// [55:40] Mask
                                            , 16'd0															// [39:24]
                                            , 1'b1 															// [23]
                                            , clearOtherBank												// [22]
                                            , { scrY[8:0], scrSrcX }										// [21:7]
                                            , 3'd0															// [ 6:4]  Clear Opposite Bnk
                                            , cpyBank														// [   3]  Bank
                                            };
    // WRITE A 16 PIXEL DATA BURST.
    MEM_CMD_WRBURST:		parameters =	{ stencilReadValue16											// [55:40]
                                            , 12'd0															// [39:28]
                                            , cpyIdx														// [27:24]
                                            , clearBank1													// [23]
                                            , clearBank0													// [22]
                                            , { scrDstY[8:0], scrDstX }										// [21:7]
                                            , 1'b0															// [   6]
                                            , GPU_REG_CheckMaskBit											// [   5]
                                            , GPU_REG_ForcePixel15MaskSet									// [   4]
                                            , writeBankOld									/* Old Bank */	// [   3]
                                            };
    default: parameters = 53'dx;
    endcase
end

Fifo
#(
    .DEPTH_WIDTH	(4),
    .DATA_WIDTH		(16)
)
Fifo_instMSB
(
    .clk			(clk ),
    .rst			(rstInFIFO),

    .wr_data_i		(gpu_m2p_valid_o ? gpu_m2p_data_o[31:16] : cpuDataIn[31:16]),
    .wr_en_i		(writeFifo),

    .rd_data_o		(fifoDataOut[31:16]),
    .rd_en_i		(readFifoMSB),

    .full_o			(isFifoFullMSB),
    .empty_o		(isFifoEmptyMSB)
);

Fifo
#(
    .DEPTH_WIDTH	(4),
    .DATA_WIDTH		(16)
)
Fifo_instLSB
(
    .clk			(clk ),
    .rst			(rstInFIFO),

    .wr_data_i		(gpu_m2p_valid_o ? gpu_m2p_data_o[15:0] : cpuDataIn[15:0]),
    .wr_en_i		(writeFifo),

    .rd_data_o		(fifoDataOut[15:0]),
    .rd_en_i		(readFifoLSB),

    .full_o			(isFifoFullLSB),
    .empty_o		(isFifoEmptyLSB)
);

reg		dmaDataRequest;												// Bit 25
wire	gpuReadySendToCPU	= (!outFIFO_empty) 
								/* && copyVCActive DONT USE IT*/;	// Bit 27
		/* Specs says that Gets set after sending GP0(C0h) and its parameters.
		   So we could rely on the state machine... BUT in the case we push data and the state machine ends, the last DATA state in the FIFO ain't visible
		   anymore to outside. Very dangerous.
		   
		   Moreover, that FIFO is only for the C0 command ANYWAY. So we just use the FLAG outFIFO_empty and it is OK.
		*/
								
/*
	- Notes: Manually sending/reading data by software (non-DMA) is ALWAYS possible, 
	  regardless of the GP1(04h) setting. The GP1(04h) setting does affect the meaning of GPUSTAT.25.
	  
	- Non-DMA transfers seem to be working at any time, but GPU-DMA Transfers seem to be working ONLY during V-Blank 
	  (outside of V-Blank, portions of the data appear to be skipped, and the following words arrive at wrong addresses), 
	  unknown if it's possible to change that by whatever configuration settings...? 
	  That problem appears ONLY for continous DMA aka VRAM transfers (linked-list DMA aka Ordering Table works even outside V-Blank).
	  
	- Status Bit
		25    DMA / Data Request, meaning depends on GP1(04h) DMA Direction:
			  When GP1(04h)=0=Off          ---> Always zero (0)
			  When GP1(04h)=1=FIFO         ---> FIFO State  (0=Full, 1=Not Full)
			  When GP1(04h)=2=CPUtoGP0     ---> Same as GPUSTAT.28
			  When GP1(04h)=3=GPUREADtoCPU ---> Same as GPUSTAT.27
		
			This is the DMA Request bit, however, the bit is also useful for non-DMA transfers, especially in the FIFO State mode.
			
		26    Ready to receive Cmd Word   (0=No, 1=Ready)  ;GP0(...) ;via GP0
			Gets set when the GPU wants to receive a command. 
			If the bit is cleared, then the GPU does either want to receive data, or it is busy with a command execution (and doesn't want to receive anything).
			
		27    Ready to send VRAM to CPU   (0=No, 1=Ready)  ;GP0(C0h) ;via GPUREAD
			Gets set after sending GP0(C0h) and its parameters, and stays set until all data words are received; used as DMA request in DMA Mode 3.
			
		28    Ready to receive DMA Block  (0=No, 1=Ready)  ;GP0(...) ;via GP0
			Normally, this bit gets cleared when the command execution is busy 
			(ie. once when the command and all of its parameters are received), however, for Polygon and Line Rendering commands, 
			the bit gets cleared immediately after receiving the command word (ie. before receiving the vertex parameters). 
			The bit is used as DMA request in DMA Mode 2, accordingly, the DMA would probably hang if the Polygon/Line parameters 
			are transferred in a separate DMA block (ie. the DMA probably starts ONLY on command words).
			
		29-30 DMA Direction (0=Off, 1=?, 2=CPUtoGP0, 3=GPUREADtoCPU)    ;GP1(04h).0-1
 */
always @(*) begin
	case (GPU_REG_DMADirection)
	DMA_DirOff   : dmaDataRequest = 1'b0;
	DMA_FIFO     : dmaDataRequest = canWriteFIFO;
	DMA_CPUtoGP0 : dmaDataRequest = isFifoEmpty32; 		// Same as gpuReadyReceiveDMA;	// Follow No$ specs, delegate signal logic to GPUSTAT.28 interpretation.
	DMA_GP0toCPU : dmaDataRequest = gpuReadySendToCPU;	// Follow No$ specs, delegate signal logic to GPUSTAT.27 interpretation.
	endcase
end

// [TODO NEXT STEP BUS]
wire parserWaitingNewCommand;
assign reg1Out = {
                    // Default : 1480.2.000h

                    // Default 1
                    GPU_DisplayEvenOddLinesInterlace,	// 31
                    GPU_REG_DMADirection,				// 29-30
                    (currWorkState == NOT_WORKING_DEFAULT_STATE), // 28

                    // default 4
                    gpuReadySendToCPU,				// 27
                    isFifoEmpty32 && parserWaitingNewCommand && (currWorkState == NOT_WORKING_DEFAULT_STATE),     // 26
                    dmaDataRequest,					// 25
                    GPU_REG_IRQSet,					// 24

                    // default 80
                    GPU_REG_DisplayDisabled,		// 23
                    GPU_REG_IsInterlaced,			// 22
                    GPU_REG_BufferRGB888,			// 21
                    GPU_REG_VideoMode,				// 20 (0=NTSC, 1=PAL)
                    GPU_REG_VerticalResolution,		// 19 (0=240, 1=480, when Bit22=1)
                    GPU_REG_HorizResolution,		// 17-18 (0=256, 1=320, 2=512, 3=640)
                    GPU_REG_HorizResolution368,		// 16 (0=256/320/512/640, 1=368)
                    // default 2
                    GPU_REG_TextureDisable,			// 15
                    GPU_REG_ReverseFlag,			// 14
                    (GPU_REG_CurrentInterlaceField & GPU_REG_IsInterlaced) | (!GPU_REG_IsInterlaced),	// 13
                    GPU_REG_CheckMaskBit,			// 12
                    // default 000
                    GPU_REG_ForcePixel15MaskSet,	// 11
                    GPU_REG_DrawDisplayAreaOn,		// 10
                    GPU_REG_DitherOn,				// 9
                    GPU_REG_TexFormat,				// 7-8
                    GPU_REG_Transparency,			// 5-6
                    GPU_REG_TexBasePageY,			// 4
                    GPU_REG_TexBasePageX			// 0-3
                };


wire cmdGP1			= writeGP1 & (cpuDataIn[29:27] == 3'd0); // Short cut for most commands.
assign rstGPU  		=(cmdGP1   & (cpuDataIn[26:24] == 3'd0)) | (i_nrst == 0);
assign rstCmd  		= cmdGP1   & (cpuDataIn[26:24] == 3'd1);
wire rstIRQ  		= cmdGP1   & (cpuDataIn[26:24] == 3'd2);
wire setDisp 		= cmdGP1   & (cpuDataIn[26:24] == 3'd3);
wire setDmaDir		= cmdGP1   & (cpuDataIn[26:24] == 3'd4);
wire setDispArea	= cmdGP1   & (cpuDataIn[26:24] == 3'd5);
wire setDispRangeX	= cmdGP1   & (cpuDataIn[26:24] == 3'd6);
wire setDispRangeY	= cmdGP1   & (cpuDataIn[26:24] == 3'd7);
wire setDisplayMode	= writeGP1 & (cpuDataIn[29:24] == 6'd8);
// Command GP1-09 not supported.
wire getGPUInfo		= writeGP1 & (cpuDataIn[29:28] == 2'd1); // 0h1X command.

/*	GP1(10h) - Get GPU Info
    GP1(11h..1Fh) - Mirrors of GP1(10h), Get GPU Info
    After sending the command, the result can be read (immediately) from GPUREAD register (there's no NOP or other delay required) (namely GPUSTAT.Bit27 is used only for VRAM-Reads, but NOT for GPU-Info-Reads, so do not try to wait for that flag).
      0-23  Select Information which is to be retrieved (via following GPUREAD)
    On Old 180pin GPUs, following values can be selected:
      00h-01h = Returns Nothing (old value in GPUREAD remains unchanged)
      02h     = Read Texture Window setting  ;GP0(E2h) ;20bit/MSBs=Nothing
      03h     = Read Draw area top left      ;GP0(E3h) ;19bit/MSBs=Nothing
      04h     = Read Draw area bottom right  ;GP0(E4h) ;19bit/MSBs=Nothing
      05h     = Read Draw offset             ;GP0(E5h) ;22bit
      06h-07h = Returns Nothing (old value in GPUREAD remains unchanged)
      08h-FFFFFFh = Mirrors of 00h..07h
    On New 208pin GPUs, following values can be selected:
      00h-01h = Returns Nothing (old value in GPUREAD remains unchanged)
      02h     = Read Texture Window setting  ;GP0(E2h) ;20bit/MSBs=Nothing
      03h     = Read Draw area top left      ;GP0(E3h) ;20bit/MSBs=Nothing
      04h     = Read Draw area bottom right  ;GP0(E4h) ;20bit/MSBs=Nothing
      05h     = Read Draw offset             ;GP0(E5h) ;22bit
      06h     = Returns Nothing (old value in GPUREAD remains unchanged)
      07h     = Read GPU Type (usually 2)    ;see "GPU Versions" chapter		/// EXTENSION GPU
      08h     = Unknown (Returns 00000000h) (lightgun on some GPUs?)
      09h-0Fh = Returns Nothing (old value in GPUREAD remains unchanged)
      10h-FFFFFFh = Mirrors of 00h..0Fh
 */
reg [31:0] gpuInfoMux;
always @(*)
begin
    case (cpuDataIn[3:0])	// NEW GPU SPEC, 2:0 on OLD GPU
    4'd0:
        gpuInfoMux = regGpuInfo;
    4'd1:
        gpuInfoMux = regGpuInfo;
    4'd2:
        // Texture Window Setting.
        gpuInfoMux = { 12'd0, GPU_REG_WindowTextureOffsetY, GPU_REG_WindowTextureOffsetX, GPU_REG_WindowTextureMaskY,GPU_REG_WindowTextureMaskX };
    4'd3:
        // Draw Top Left
        gpuInfoMux = { 12'd0, GPU_REG_DrawAreaY0,GPU_REG_DrawAreaX0}; // 20 bit on new GPU, 19 bit on OLD GPU.
    4'd4:
        // Draw Bottom Right
        gpuInfoMux = { 12'd0, GPU_REG_DrawAreaY1,GPU_REG_DrawAreaX1};
    4'd5:
        // Draw Offset
        gpuInfoMux = { 10'd0, GPU_REG_OFFSETY, GPU_REG_OFFSETX };
    4'd6:
        gpuInfoMux = regGpuInfo;
    4'd7:
        gpuInfoMux = 32'h00000002;
    4'd8:
        gpuInfoMux = 32'd0;
    default:	// 0x9..F
        gpuInfoMux = regGpuInfo;
    endcase
end

wire [15:0] newClutValue = { /*issue.*/rstTextureCache, fifoDataOutClut };
reg   		rClutLoading;
reg			endClutLoading; // From state machine.
reg			decClutCount;
reg	 [4:0]	rClutPacketCount;
reg         rPalette4Bit;
wire [4:0]	nextClutPacket	= rClutPacketCount + 5'h1F;

always @(posedge clk)
if (getGPUInfo)
	regGpuInfo <= gpuInfoMux;
	
always @(posedge clk)
begin
    if (rstGPU) begin
        GPU_REG_OFFSETX				<= 11'd0;
        GPU_REG_OFFSETY				<= 11'd0;
        GPU_REG_TexBasePageX		<= 4'd0;
        GPU_REG_TexBasePageY		<= 1'b0;
        GPU_REG_Transparency		<= 2'd0;
        GPU_REG_TexFormat			<= 2'd0; //
        GPU_REG_DitherOn			<= 1'd0; //
        GPU_REG_DrawDisplayAreaOn	<= 1'b0; // Default by GP1(00h) definition.
        GPU_REG_TextureDisable		<= 1'b0;
        GPU_REG_TextureXFlip		<= 1'b0;
        GPU_REG_TextureYFlip		<= 1'b0;
        GPU_REG_WindowTextureMaskX	<= 5'd0;
        GPU_REG_WindowTextureMaskY	<= 5'd0;
        GPU_REG_WindowTextureOffsetX<= 5'd0;
        GPU_REG_WindowTextureOffsetY<= 5'd0;
        GPU_REG_DrawAreaX0			<= 10'd0;
        GPU_REG_DrawAreaY0			<= 10'd0; // 8:0 on old GPU.
        GPU_REG_DrawAreaX1			<= 10'd1023;	//
        GPU_REG_DrawAreaY1			<= 10'd511;		//
        GPU_REG_ForcePixel15MaskSet <= 0;
        GPU_REG_CheckMaskBit		<= 0;
        GPU_REG_IRQSet				<= 0;
        GPU_REG_DisplayDisabled		<= 1;
        GPU_REG_DMADirection		<= DMA_DirOff; // Off
        GPU_REG_IsInterlaced		<= 0;
        GPU_REG_BufferRGB888		<= 0;
        GPU_REG_VideoMode			<= 0;
        GPU_REG_VerticalResolution	<= 0;
        GPU_REG_HorizResolution		<= 2'b0;
        GPU_REG_HorizResolution368	<= 0;
        GPU_REG_ReverseFlag			<= 0;

        GPU_REG_DispAreaX			<= 10'd0;
        GPU_REG_DispAreaY			<=  9'd0;
        GPU_REG_RangeX0				<= 12'h200;		// 200h
        GPU_REG_RangeX1				<= 12'hC00;		// 200h + 256x10
        GPU_REG_RangeY0				<= 10'h10;		//  10h
        GPU_REG_RangeY1				<= 10'h100; 	//  10h + 240
        RegCLUT						<= 16'h8000;	// Invalid CLUT ADR on reset.
        rClutLoading				<= 1'b0;
        rClutPacketCount			<= 5'd0;
        rPalette4Bit				<= 1'b0;

    end else begin
        if (/*issue.*/loadE5Offsets) begin
            GPU_REG_OFFSETX <= fifoDataOut[10: 0];
            GPU_REG_OFFSETY <= fifoDataOut[21:11];
        end
        if (/*issue.*/loadTexPageE1 || /*issue.*/loadTexPage) begin
            GPU_REG_TexBasePageX 	<= /*issue.*/loadTexPage ? fifoDataOut[19:16] : fifoDataOut[3:0];
            GPU_REG_TexBasePageY 	<= /*issue.*/loadTexPage ? fifoDataOut[20]    : fifoDataOut[4];
            GPU_REG_Transparency 	<= /*issue.*/loadTexPage ? fifoDataOut[22:21] : fifoDataOut[6:5];
            GPU_REG_TexFormat    	<= /*issue.*/loadTexPage ? fifoDataOut[24:23] : fifoDataOut[8:7];
            GPU_REG_TextureDisable	<= /*issue.*/loadTexPage ? fifoDataOut[27]    : fifoDataOut[11];
        end
        if (/*issue.*/issuePrimitive != NO_ISSUE) begin
            rClutPacketCount		<= { CLUTIs8BPP , 3'b0, !CLUTIs8BPP }; // Load 1 packet or 16
        end
        if (/*issue.*/loadTexPageE1) begin // Texture Attribute only changed by E1 Command.
            GPU_REG_DitherOn     <= fifoDataOut[9];
            GPU_REG_DrawDisplayAreaOn <= fifoDataOut[10];
            GPU_REG_TextureXFlip <= fifoDataOut[12];
            GPU_REG_TextureYFlip <= fifoDataOut[13];
        end
        if (/*issue.*/loadTexWindowSetting) begin
            GPU_REG_WindowTextureMaskX   <= fifoDataOut[4:0];
            GPU_REG_WindowTextureMaskY   <= fifoDataOut[9:5];
            GPU_REG_WindowTextureOffsetX <= fifoDataOut[14:10];
            GPU_REG_WindowTextureOffsetY <= fifoDataOut[19:15];
        end

        if (decClutCount) begin
            rClutPacketCount <= nextClutPacket; // Decrement -1.
        end

        if (/*issue.*/loadClutPage) begin
            if (newClutValue[15] == 1'b0 && (newClutValue != RegCLUT)) begin
                // Loading only happens when :
                // - Switch from invalid to valid CLUT ADR. (Reset or cache flush)
                // - Switch from valid   do difference valid CLUT ADR.
                //
                // WARNING : rClutPacketCount the number of PACKET TO LOAD IS UPDATED WHEN LOADING THE TEXTURE FORMAT !!!! NOT WHEN CLUT FLAT IS SET !!!!
                //
                rClutLoading	<= 1'b1;
            end
            // Load always the value, whatever the value is (valid or invalid)
            RegCLUT		<= newClutValue;
        end

        if (endClutLoading) begin
            rClutLoading	<= 1'b0;
            rPalette4Bit	<= (GPU_REG_TexFormat == PIX_4BIT);
        end

        if (/*issue.*/loadDrawAreaTL) begin
            GPU_REG_DrawAreaX0 <= fifoDataOut[ 9: 0];
            GPU_REG_DrawAreaY0 <= { 1'b0, fifoDataOut[18:10] }; // 19:10 on NEW GPU.
        end
        if (/*issue.*/loadDrawAreaBR) begin
            GPU_REG_DrawAreaX1 <= fifoDataOut[ 9: 0];
            GPU_REG_DrawAreaY1 <= { 1'b0, fifoDataOut[18:10] }; // 19:0 on NEW GPU.
        end
        if (/*issue.*/loadMaskSetting) begin
            GPU_REG_ForcePixel15MaskSet <= fifoDataOut[0];
            GPU_REG_CheckMaskBit		<= fifoDataOut[1];
        end
        if (rstIRQ | /*issue.*/setIRQ) begin
            GPU_REG_IRQSet				<= /*issue.*/setIRQ;
        end
        if (setDisp) begin
            GPU_REG_DisplayDisabled		<= cpuDataIn[0];
        end
        if (setDmaDir) begin
            GPU_REG_DMADirection		<= DMADirection'(cpuDataIn[1:0]);
        end
        if (setDispArea) begin
            GPU_REG_DispAreaX			<= cpuDataIn[ 9: 0];
            GPU_REG_DispAreaY			<= cpuDataIn[18:10];
        end
        if (setDispRangeX) begin
            GPU_REG_RangeX0				<= cpuDataIn[11: 0];
            GPU_REG_RangeX1				<= cpuDataIn[23:12];
        end
        if (setDispRangeY) begin
            GPU_REG_RangeY0				<= cpuDataIn[ 9: 0];
            GPU_REG_RangeY1				<= cpuDataIn[19:10];
        end
        if (setDisplayMode) begin
            GPU_REG_IsInterlaced		<= cpuDataIn[5];
            GPU_REG_BufferRGB888		<= cpuDataIn[4];
            GPU_REG_VideoMode			<= cpuDataIn[3];
            GPU_REG_VerticalResolution	<= cpuDataIn[2];
            GPU_REG_HorizResolution		<= cpuDataIn[1:0];
            GPU_REG_HorizResolution368	<= cpuDataIn[6];
            GPU_REG_ReverseFlag			<= cpuDataIn[7];
        end
    end

    //if (rstGPU) begin
        //RegCommand <= '0;
    //end else begin
    //end
end
// END [TODO NEXT STEP BUS]

wire [14:0] fifoDataOutClut			= fifoDataOut[30:16];

//-------------------------------------------------------------
// Run time stuff based on command decoder
//-------------------------------------------------------------
reg  FifoDataValid;
always @(posedge clk)
    FifoDataValid <= readFifo;

always @(posedge clk)
	if (storeCommand) RegCommand <= command;

// End line command if special marker or SECOND vertex when not a multiline command...
wire bIsTerminator			= (fifoDataOut[31:28] == 4'd5) & (fifoDataOut[15:12] == 4'd5);

// - Rectangle never dither. ( => bIsPerVtxCol is FALSE)
// - Line      dither if set (even for unique color)
// - Triangle  dither if gouraud is set (textured or not) = bIsPerVtxCol
wire ditherSetup			= ( GPU_REG_DitherOn & DIP_AllowDither ) | DIP_ForceDither;
wire bDither				= ditherSetup & (bIsPerVtxCol | bIsLineCommand);
//-------------------------------------------------------------

wire [7:0] command			= storeCommand ? fifoDataOut[31:24] : RegCommand;

wire [1:0] vertexID;
wire isVertexLoadState;

gpu_commandDecoder commandDecoderInstance(
	.i_command				(command),

	.o_bIsBase0x			(),
	.o_bIsBase01			(),
	.o_bIsBase02			(),
	.o_bIsBase1F			(),
	.o_bIsPolyCommand		(bIsPolyCommand),
	.o_bIsRectCommand		(bIsRectCommand),
	.o_bIsLineCommand		(bIsLineCommand),
	.o_bIsMultiLine			(),
	.o_bIsForECommand		(),
	.o_bIsCopyVVCommand		(bIsCopyVVCommand),
	.o_bIsCopyCVCommand		(bIsCopyCVCommand),
	.o_bIsCopyVCCommand		(),
	.o_bIsCopyCommand		(bIsCopyCommand),
	.o_bIsFillCommand		(),
	.o_bIsRenderAttrib		(),
	.o_bIsNop				(),
	.o_bIsPolyOrRect		(),
	.o_bUseTextureParser	(bUseTextureParser),
	.o_bSemiTransp			(bSemiTransp),
	.o_bOpaque				(bOpaque),
	.o_bIs4PointPoly		(),
	.o_bIsPerVtxCol			(bIsPerVtxCol)
);

// Runtime flag (Non textured lines, RAW Texture mode, etc...)
wire bUseTexture    		= bUseTextureParser & (!GPU_REG_TextureDisable); 										// Avoid texture fetching if we do LINE, Compute proper color for FILL.
wire bIgnoreColor   		= bUseTexture       & command[0];

wire rstTextureCache,loadE5Offsets,loadTexPageE1,loadTexWindowSetting,loadDrawAreaTL,loadDrawAreaBR,loadMaskSetting,setIRQ,loadClutPage,loadTexPage;
wire storeCommand;
wire loadVertices,loadUV,loadRGB,loadAllRGB,loadCoord1,loadCoord2,loadSize,loadRectEdge;

gpu_parser gpu_parser_instance(
	.i_clk				(clk),
	.i_rstGPU			(rstGPU),	// Reset Signal or Reset Command GP1
	
	.i_command			(command),
	.o_waitingNewCommand(parserWaitingNewCommand),

	.i_gpuBusy			(!canIssueWork),
	.o_issuePrimitive	(issuePrimitive),

	// Request data to parse
	.i_isFifoNotEmpty32	(isFifoNotEmpty32),
	.o_readFIFO			(readFifo),

	// Valid data from previous request
	.i_dataValid		(FifoDataValid),
	.i_bIsTerminator	(bIsTerminator),
	
	// Runtime flag depending on command and GPU setup.
	.i_bIgnoreColor		(bIgnoreColor),
	
	//================================================
	// Control signals
	//================================================
	.o_storeCommand		(storeCommand		),
	// To Register loading
	//------------------------------------------------
	.o_vertexID			(vertexID			),
	.o_loadVertices		(loadVertices		),
	.o_loadUV			(loadUV				),
	.o_loadRGB			(loadRGB			),
	.o_loadAllRGB		(loadAllRGB			),
	.o_loadCoord1		(loadCoord1			),
	.o_loadCoord2		(loadCoord2			),
	.o_loadSize			(loadSize			),
	.o_loadSizeParam	(loadSizeParam		),
	.o_loadRectEdge		(loadRectEdge		),
	.o_isVertexLoadState(isVertexLoadState	),

	.o_rstTextureCache	(rstTextureCache	),
	.o_loadE5Offsets	(loadE5Offsets		),
	.o_loadTexPageE1	(loadTexPageE1		),
	.o_loadTexWindowSetting(loadTexWindowSetting),
	.o_loadDrawAreaTL	(loadDrawAreaTL		),
	.o_loadDrawAreaBR	(loadDrawAreaBR		),
	.o_loadMaskSetting	(loadMaskSetting	),
	.o_setIRQ			(setIRQ				),
	.o_loadClutPage		(loadClutPage		),
	.o_loadTexPage		(loadTexPage		)
);

gpu_loadedRegs gpu_vertexRegisters(
	.i_clk				(clk),
	
	//-----------------------------------------
	// DATA IN (Parser control the input)
	//-----------------------------------------
	// Data From FIFO
	.i_validData		(FifoDataValid),
	.i_data				(fifoDataOut),
	.i_command			(command),
	//-----------------------------------------
	// Vertex Control (TARGET)
	.i_targetVertex		(vertexID),	// 0..2
	
	.i_bUseTexture		(bUseTexture),
	.i_bIgnoreColor		(bIgnoreColor),
	
	//-----------------------------------------
	// OPERATION (set when i_validData VALID)
	//-----------------------------------------
	.i_loadVertices		(loadVertices	),
	.i_loadUV			(loadUV			),
	.i_loadRGB			(loadRGB		),
	.i_loadAllRGB		(loadAllRGB		),
	.i_loadCoord1		(loadCoord1		),
	.i_loadCoord2		(loadCoord2		),

	.i_loadSize			(loadSize		),
	.i_loadSizeParam	(loadSizeParam	),

	.i_loadRectEdge		(loadRectEdge	),
	.i_isVertexLoadState(isVertexLoadState),
	
	//-----------------------------------------
	// Parameters for internal xform
	//-----------------------------------------
	.i_GPU_REG_TextureDisable
						(GPU_REG_TextureDisable),
	// [Data from General GPU Registers needed when loading vertices]
	.i_GPU_REG_OFFSETX	(GPU_REG_OFFSETX),
	.i_GPU_REG_OFFSETY	(GPU_REG_OFFSETY),
	
	.o_RegX0			(RegX0),
	.o_RegY0			(RegY0),
	.o_RegR0			(RegR0),
	.o_RegG0			(RegG0),
	.o_RegB0			(RegB0),
	.o_RegU0			(RegU0),
	.o_RegV0			(RegV0),
	.o_RegX1			(RegX1),
	.o_RegY1			(RegY1),
	.o_RegR1			(RegR1),
	.o_RegG1			(RegG1),
	.o_RegB1			(RegB1),
	.o_RegU1			(RegU1),
	.o_RegV1			(RegV1),
	.o_RegX2			(RegX2),
	.o_RegY2			(RegY2),
	.o_RegR2			(RegR2),
	.o_RegG2			(RegG2),
	.o_RegB2			(RegB2),
	.o_RegU2			(RegU2),
	.o_RegV2			(RegV2),
	.o_RegSizeW			(RegSizeW),
	.o_RegSizeH			(RegSizeH),
	.o_OriginalRegSizeH	(OriginalRegSizeH)
);

//--------------------------------------------------------------------
// Control feedback
wire isNULLDET,isNegXAxis,isValidPixelL,isValidPixelR,earlyTriangleReject,edgeDidNOTSwitchLeftRightBB,isNegPreB;
wire isValidHorizontalTriBbox,isRightPLXmaxTri,isInsideBBoxTriRectL,isInsideBBoxTriRectR,isBottomInsideBBox,isLineInsideDrawArea,isLineLeftPix,isLineRightPix;
wire reachEdgeTriScan;
// Next Pixel for line algorithm
wire signed [11:0] nextLineX,nextLineY,nextPixelX,nextPixelY;
// Bounding box info for triangle
wire signed [11:0] minTriDAX0,maxTriDAX1,minTriDAY0;

wire signed [ 9:0] loopIncrNextPixelY;

wire lineStart			= (currWorkState == LINE_START);

wire dir;

gpu_scan gpu_scan_instance(
	.i_clk							(clk),

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
	.i_selNextX						(selNextX),	// All primitive except FILL / CopyVV
	.i_selNextY						(selNextY),	// All primitive

	// Current pixel                 / Current pixel
	.o_pixelX						(pixelX),
	.o_pixelY						(pixelY),
	.o_nextPixelX					(nextPixelX),
	.o_nextPixelY					(nextPixelY),
	.o_loopIncrNextPixelY			(loopIncrNextPixelY),


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


/* 
	TODO VERIFY IF FUNCTION IS IMPLEMENTED OR NOT (GUARDBAND)
	This code below is not used / DEPRECATED => Check with early triangle reject ???

// TODO : Rejection occurs with DX / DY. Not range. wire rejectVertex			= (fifoDataOutX[11] != fifoDataOutX[10]) | (fifoDataOutY[11] != fifoDataOutY[10]); // Primitive with offset out of range -1024..+1023
wire resetReject			= 0; // [TODO] Why ?
wire rejectVertex			= 0;

reg  rejectPrimitive;
always @(posedge clk)
begin
    if (rejectVertex | resetReject) begin
        rejectPrimitive <= !resetReject;
    end
end
*/

wire canIssueWork       = (currWorkState == NOT_WORKING_DEFAULT_STATE);

// When line start, ask to decrement
reg         useDest;
reg			incrementXCounter;

//
// This computation is tricky : RegSizeH is the size (ex 200 lines).
// 1/ We will perform rendering from 200 to 1, 0 is EXIT value. (number of line to work on).
// 2/ But the adress is RegSizeH-1. (So we had 0x3FF, same thing)
// 3/ We have also the DIRECTION of the line-by-line processing. Copy may not work depending on Source and Dest Y and block length. So we choose the copy direction too.

// Copy from TOP to BOTTOM when doing COPY from LOWER ADR to HIGHER ADR, and OPPOSITE TO AVOID FEEDBACK DURING COPY.
// This flag also impact the FILL order but not the feature itself (Value SY1 depend on previouss commands or reset).

// TODO OPTIMIZE : comparison already exist... Replace later...

// Increment when Dst < Src. : (V1-V0 < 0) => Diff Sign 1 |  Valid for ALL axis (X and Y)
// Decrement when Dst > Src. : (V1-V0 > 0) => Diff Sign 0 |  Src = Vertex0, Dst = Vertex1 => V1-V0

assign xCopyDirectionIncr = isNegXAxis;

wire  [9:0] OppRegSizeH			= OriginalRegSizeH - RegSizeH;

//
// Same for X Axis. Except we use an INCREMENTING COUNTER INSTEAD OF DEC FOR THE SAME AXIS.

wire [10:0] fullSizeSrc			= RegSizeW + { 7'd0, RegX0[3:0] };
wire [10:0] fullSizeDst			= RegSizeW + { 7'd0, RegX1[3:0] };

wire        srcDistExact16Pixel	= !(|fullSizeSrc[3:0]);
wire        dstDistExact16Pixel	= !(|fullSizeDst[3:0]);

wire  [6:0] lengthBlockSrcHM1	= fullSizeSrc[10:4] + {7{srcDistExact16Pixel}};	// If exact 16, retract 1 block. (Add -1)
wire  [6:0] lengthBlockDstHM1	= fullSizeDst[10:4] + {7{dstDistExact16Pixel}};

wire  [6:0] OppAdrXSrc			= lengthBlockSrcHM1 - counterXSrc;
wire  [6:0] OppAdrXDst			= lengthBlockDstHM1 - counterXDst;

assign adrXSrc = xCopyDirectionIncr ? counterXSrc[5:0] : OppAdrXSrc[5:0];
assign adrXDst = xCopyDirectionIncr ? counterXDst[5:0] : OppAdrXDst[5:0];

// wire  [6:0] fullX				= (useDest           ? adrXDst : adrXSrc)          + { 1'b0, useDest ? RegX1[9:4] : RegX0[9:4] };


reg  [15:0] maskLeft;
reg  [15:0] maskRight;
wire [3:0]  rightPos = RegX0[3:0] + RegSizeW[3:0];
wire [3:0]  sxe16    = rightPos + 4'b1111;
always @(*)
begin
    case (RegX0[3:0])
    4'h0: maskLeft = 16'b1111_1111_1111_1111; // Pixel order is ->, While bit are MSB <- LSB.
    4'h1: maskLeft = 16'b1111_1111_1111_1110;
    4'h2: maskLeft = 16'b1111_1111_1111_1100;
    4'h3: maskLeft = 16'b1111_1111_1111_1000;
    4'h4: maskLeft = 16'b1111_1111_1111_0000;
    4'h5: maskLeft = 16'b1111_1111_1110_0000;
    4'h6: maskLeft = 16'b1111_1111_1100_0000;
    4'h7: maskLeft = 16'b1111_1111_1000_0000;
    4'h8: maskLeft = 16'b1111_1111_0000_0000;
    4'h9: maskLeft = 16'b1111_1110_0000_0000;
    4'hA: maskLeft = 16'b1111_1100_0000_0000;
    4'hB: maskLeft = 16'b1111_1000_0000_0000;
    4'hC: maskLeft = 16'b1111_0000_0000_0000;
    4'hD: maskLeft = 16'b1110_0000_0000_0000;
    4'hE: maskLeft = 16'b1100_0000_0000_0000;
 default: maskLeft = 16'b1000_0000_0000_0000;
    endcase
    
	case (rightPos)
    // Special case : lastSegment is actually the PREVIOUS segment. Empty segment never occurs because of computation.
    // The END (EXCLUDED) pixel from the segment is the beginning of a new chunk that will be never loaded.
    // See computation of 'lengthBlockSrcHM1'
    4'h0: maskRight = 16'b1111_1111_1111_1111; // Pixel order is ->, While bit are MSB <- LSB.
    // Normal cases...
    4'h1: maskRight = 16'b0000_0000_0000_0001;
    4'h2: maskRight = 16'b0000_0000_0000_0011;
    4'h3: maskRight = 16'b0000_0000_0000_0111;
    4'h4: maskRight = 16'b0000_0000_0000_1111;
    4'h5: maskRight = 16'b0000_0000_0001_1111;
    4'h6: maskRight = 16'b0000_0000_0011_1111;
    4'h7: maskRight = 16'b0000_0000_0111_1111;
    4'h8: maskRight = 16'b0000_0000_1111_1111;
    4'h9: maskRight = 16'b0000_0001_1111_1111;
    4'hA: maskRight = 16'b0000_0011_1111_1111;
    4'hB: maskRight = 16'b0000_0111_1111_1111;
    4'hC: maskRight = 16'b0000_1111_1111_1111;
    4'hD: maskRight = 16'b0001_1111_1111_1111;
    4'hE: maskRight = 16'b0011_1111_1111_1111;
 default: maskRight = 16'b0111_1111_1111_1111;
    endcase
end

always @(posedge clk)
begin
    counterXSrc <= (resetXCounter) ? 7'd0 : counterXSrc + { 6'd0 ,incrementXCounter & (!useDest) };
    counterXDst <= (resetXCounter) ? 7'd0 : counterXDst + { 6'd0 ,incrementXCounter &   useDest  };
end

reg  switchReadStoreBlock; // TODO this command will ALSO do loading the CACHE STENCIL locally (2x16 bit registers)

wire emptySurface			= (RegSizeH == 10'd0) | (RegSizeW == 11'd0);

// Needed for state machine.
wire isLastSegment  		= (counterXSrc==lengthBlockSrcHM1);
wire isLastSegmentDst		= (counterXDst==lengthBlockDstHM1);

wire isFirstSegmentMask		= (adrXSrc    ==6'd0);
wire isLastSegmentMask 		= (adrXSrc    ==lengthBlockSrcHM1[5:0]);

wire [15:0] maskSegmentRead	= (isFirstSegmentMask ? maskLeft  : 16'hFFFF)
                            & (isLastSegmentMask  ? maskRight : 16'hFFFF);

assign maskRead16			= maskSegmentRead;

wire dblLoadL2R				= RegX1[3:0] < RegX0[3:0];
// RegX0 - RegX1 + (dblLoadL2R ? 16 : 0)

assign  tmpidx = { dblLoadL2R , RegX0[3:0] } + { 1'b1, ~RegX1[3:0] } + 5'd1;
assign  cpyIdx = tmpidx[3:0];

assign   performSwitch	= |cpyIdx; // If ZERO, NO SWITCH !
wire dblLoadR2L				= sxe16 < cpyIdx;
wire isDoubleLoad			= xCopyDirectionIncr ? dblLoadL2R : dblLoadR2L;
wire isLongLine				= RegSizeW[9] | RegSizeW[10]; // At least >= 512

wire storeStencilRead = (memoryCommand == MEM_CMD_RDBURST);
reg [31:0]	stencilReadCache;
reg [31:0]  maskReadCache;

reg pixelFound;
// reg enteredTriangle;  								EARLY OPTIMIZATION REMOVED FOR NOW.
// reg setEnteredTriangle, resetEnteredTriangle;		Same related

reg			writePixelL,writePixelR;

// -----------------------------------------------------------------------
// ----  INPUT ----
// INPUT : pixelX pixelY
// INPUT : writePixelL writePixelR
// [Set to TRUE by state machine each time we start a new primitive]
reg         setFirstPixel;
// ---- OUTPUT ----
// [Generate a spike when entering a new working block first pixel.]
// - Spike is generated by comparison of previous block adress.		(differentBlock)  <-- will happen only when the pipeline is not STALLED by construction.
// - Spike is generated by first write on first block 				(flagIsNewBlock==IS_NEW_BLOCK_IN_PRIMITIVE)
// And we check that we are writing pixels of course. (avoid spike elsewhere)
reg [1:0]	flagIsNewBlock;												// Register Flag set containing the change during SCANNING, it does NOT represent the PIXEL WRITE BACK OUTPUT ! (2 cycle latency)
wire [1:0] pixelStateSpike	= doBlockWork ? flagIsNewBlock : IS_NOT_NEWBLOCK;

reg [14:0]  prevVRAMAdrBlock;
wire [14:0] currVRAMAdrBlock = {     pixelY[8:0],     pixelX[9:4] };

// ---- Local stuff ------
// [Set to TRUE each time a new pixel to write is going to a different block of 16 pixel in the target buffer]
wire        differentBlock	 = (currVRAMAdrBlock != prevVRAMAdrBlock);	// Next Position is a different block.
// Each time we write VALID pixels, check if we need to push a new block state change spike.
assign		doBlockWork 	= (differentBlock | (flagIsNewBlock==IS_NEW_BLOCK_IN_PRIMITIVE)) & (writePixelL | writePixelR);

always @(posedge clk) begin
    if (writePixelL | writePixelR) begin
        prevVRAMAdrBlock <= currVRAMAdrBlock;
    end

    // Give priority to SET over RESET, and ONLY when we write an EFFECTIVE PIXEL.
    if (setFirstPixel) begin
        flagIsNewBlock <= IS_NEW_BLOCK_IN_PRIMITIVE;
    end else begin
        // [Inside the primitive, each time we emit a pixel]
        if (doBlockWork) begin
            if (flagIsNewBlock == IS_NEW_BLOCK_IN_PRIMITIVE) begin
                flagIsNewBlock <= IS_OTHER_BLOCK_IN_PRIMITIVE;
            end
        end
    end
end
// -----------------------------------------------------------------------

always @(posedge clk)
begin
    // BEFORE cpyBank UPDATE !!!
    if (storeStencilRead) begin
        if (cpyBank) begin
            stencilReadCache[31:16] <= stencilReadValue16;
            maskReadCache	[31:16] <= maskSegmentRead;
            if (clearOtherBank) begin
                maskReadCache	[15:0] <= 16'd0;
            end
        end else begin
            stencilReadCache[15: 0] <= stencilReadValue16;
            maskReadCache	[15: 0] <= maskSegmentRead;
            if (clearOtherBank) begin
                maskReadCache	[31:16] <= 16'd0;
            end
        end
    end

    if (clearBank0) begin // storeStencilRead is always False, no priority issues.
        maskReadCache	[15: 0] <= 16'd0;
    end

    if (clearBank1) begin // storeStencilRead is always False, no priority issues.
        maskReadCache	[31:16] <= 16'd0;
    end

    // AFTER cpyBank is used !!!!
    if (resetBank) begin
        cpyBank <= 1'b0;
    end else begin
        cpyBank <= cpyBank ^ switchBank;
    end

end

reg  [15:0] stencilReadRemapped;
reg  [15:0] maskReadRemapped;
// Mask and [Full_selection_if_GPU_DRAW_ALWAYS or inverse_stencilRead_At_target]

always @(*)
begin
    // TODO : Replace with Logarithm shift stage. ( << 1, << 2, << 4, << 8, << 16 )
    case ({writeBankOld,cpyIdx})
    5'h00: begin stencilReadRemapped =  stencilReadCache[15: 0];                         maskReadRemapped =  maskReadCache[15: 0];                         end
    5'h01: begin stencilReadRemapped =  stencilReadCache[16: 1];                         maskReadRemapped =  maskReadCache[16: 1];                         end
    5'h02: begin stencilReadRemapped =  stencilReadCache[17: 2];                         maskReadRemapped =  maskReadCache[17: 2];                         end
    5'h03: begin stencilReadRemapped =  stencilReadCache[18: 3];                         maskReadRemapped =  maskReadCache[18: 3];                         end
    5'h04: begin stencilReadRemapped =  stencilReadCache[19: 4];                         maskReadRemapped =  maskReadCache[19: 4];                         end
    5'h05: begin stencilReadRemapped =  stencilReadCache[20: 5];                         maskReadRemapped =  maskReadCache[20: 5];                         end
    5'h06: begin stencilReadRemapped =  stencilReadCache[21: 6];                         maskReadRemapped =  maskReadCache[21: 6];                         end
    5'h07: begin stencilReadRemapped =  stencilReadCache[22: 7];                         maskReadRemapped =  maskReadCache[22: 7];                         end
    5'h08: begin stencilReadRemapped =  stencilReadCache[23: 8];                         maskReadRemapped =  maskReadCache[23: 8];                         end
    5'h09: begin stencilReadRemapped =  stencilReadCache[24: 9];                         maskReadRemapped =  maskReadCache[24: 9];                         end
    5'h0A: begin stencilReadRemapped =  stencilReadCache[25:10];                         maskReadRemapped =  maskReadCache[25:10];                         end
    5'h0B: begin stencilReadRemapped =  stencilReadCache[26:11];                         maskReadRemapped =  maskReadCache[26:11];                         end
    5'h0C: begin stencilReadRemapped =  stencilReadCache[27:12];                         maskReadRemapped =  maskReadCache[27:12];                         end
    5'h0D: begin stencilReadRemapped =  stencilReadCache[28:13];                         maskReadRemapped =  maskReadCache[28:13];                         end
    5'h0E: begin stencilReadRemapped =  stencilReadCache[29:14];                         maskReadRemapped =  maskReadCache[29:14];                         end
    5'h0F: begin stencilReadRemapped =  stencilReadCache[30:15];                         maskReadRemapped =  maskReadCache[30:15];                         end
    5'h10: begin stencilReadRemapped =  stencilReadCache[31:16];                         maskReadRemapped =  maskReadCache[31:16];                         end
    5'h11: begin stencilReadRemapped = {stencilReadCache   [0],stencilReadCache[31:17]}; maskReadRemapped = {maskReadCache   [0],maskReadCache[31:17]}; end
    5'h12: begin stencilReadRemapped = {stencilReadCache[ 1:0],stencilReadCache[31:18]}; maskReadRemapped = {maskReadCache[ 1:0],maskReadCache[31:18]}; end
    5'h13: begin stencilReadRemapped = {stencilReadCache[ 2:0],stencilReadCache[31:19]}; maskReadRemapped = {maskReadCache[ 2:0],maskReadCache[31:19]}; end
    5'h14: begin stencilReadRemapped = {stencilReadCache[ 3:0],stencilReadCache[31:20]}; maskReadRemapped = {maskReadCache[ 3:0],maskReadCache[31:20]}; end
    5'h15: begin stencilReadRemapped = {stencilReadCache[ 4:0],stencilReadCache[31:21]}; maskReadRemapped = {maskReadCache[ 4:0],maskReadCache[31:21]}; end
    5'h16: begin stencilReadRemapped = {stencilReadCache[ 5:0],stencilReadCache[31:22]}; maskReadRemapped = {maskReadCache[ 5:0],maskReadCache[31:22]}; end
    5'h17: begin stencilReadRemapped = {stencilReadCache[ 6:0],stencilReadCache[31:23]}; maskReadRemapped = {maskReadCache[ 6:0],maskReadCache[31:23]}; end
    5'h18: begin stencilReadRemapped = {stencilReadCache[ 7:0],stencilReadCache[31:24]}; maskReadRemapped = {maskReadCache[ 7:0],maskReadCache[31:24]}; end
    5'h19: begin stencilReadRemapped = {stencilReadCache[ 8:0],stencilReadCache[31:25]}; maskReadRemapped = {maskReadCache[ 8:0],maskReadCache[31:25]}; end
    5'h1A: begin stencilReadRemapped = {stencilReadCache[ 9:0],stencilReadCache[31:26]}; maskReadRemapped = {maskReadCache[ 9:0],maskReadCache[31:26]}; end
    5'h1B: begin stencilReadRemapped = {stencilReadCache[10:0],stencilReadCache[31:27]}; maskReadRemapped = {maskReadCache[10:0],maskReadCache[31:27]}; end
    5'h1C: begin stencilReadRemapped = {stencilReadCache[11:0],stencilReadCache[31:28]}; maskReadRemapped = {maskReadCache[11:0],maskReadCache[31:28]}; end
    5'h1D: begin stencilReadRemapped = {stencilReadCache[12:0],stencilReadCache[31:29]}; maskReadRemapped = {maskReadCache[12:0],maskReadCache[31:29]}; end
    5'h1E: begin stencilReadRemapped = {stencilReadCache[13:0],stencilReadCache[31:30]}; maskReadRemapped = {maskReadCache[13:0],maskReadCache[31:30]}; end
    5'h1F: begin stencilReadRemapped = {stencilReadCache[14:0],stencilReadCache   [31]}; maskReadRemapped = {maskReadCache[14:0],maskReadCache   [31]}; end
    endcase
end

always @(posedge clk)
begin
    if (rstGPU | rstCmd) begin
        currWorkState	<= NOT_WORKING_DEFAULT_STATE;
    end else begin
        currWorkState	<= nextWorkState;
    end
end

// --------------------------------------------------------------------------------------------
//   CPU TO VRAM STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

// [Computation value needed for control setup]
wire			canRead	= (!isFifoEmptyLSB) | (!isFifoEmptyMSB);
//                          X       + WIDTH              - [1 or 2]
wire [11:0]		XE		= { RegX0 } + { 1'b0, RegSizeW } + {{11{1'b1}}, RegX0[0] ^ RegSizeW[0]};		// We can NOT use 10:0 range, because we compare nextX with XE to find the END. Full width of 1024 equivalent to ZERO size.
wire  [9:0]  nextScrY	= nextPixelY[9:0] + RegY0[9:0];

wire		WidthNot1	= |RegSizeW[10:1];
assign		endVertical	= (loopIncrNextPixelY >= RegSizeH);
assign			scrY	= pixelY[9:0] + RegY0[9:0];
assign       scrDstY	= pixelY[8:0] + RegY1[8:0];

// [Registers]
// reg  [11:0]		currX;
// reg  [ 9:0]		currY;
reg				lastPair;
reg		[2:0]	stencilMode;

// [Control bit]
reg setLastPair, resetLastPair;
reg changeSwap;
reg setSwap;
reg readL;
reg readM;

always @(posedge clk)
begin
    if (setLastPair) begin
        lastPair <= 1'b1;
    end
    if (resetLastPair) begin
        lastPair <= 1'b0;
    end
    if (setSwap) begin
        swap <= RegX0[0];
    end else begin
        swap <= swap ^ changeSwap;
    end
    if (readL | readM) begin
        regSaveM <= readM;
        regSaveL <= readL;
    end
    if (setStencilMode!=3'd0) begin
        stencilMode <= setStencilMode;
    end
end
wire isNewBlockPixel;

assign readLFifo = readL;
assign readMFifo = readM;
// --------------------------------------------------------------------------------------------
//   [END] CPU TO VRAM STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

reg				stencilReadSigW; // USED ONLY WHEN READING THE STENCIL ON TARGET BEFORE A WRITE LATER.

wire allowNextRead = (!isLastSegment) | isLongLine;
wire isPalettePrimitive = (!GPU_REG_TexFormat[1]) & bUseTexture;
wire validCLUTLoad = rClutLoading & isPalettePrimitive; // Format is 0 or 1 and clut load is required.
wire updateClutCacheComplete;
reg  requClutCacheUpdate;


// --------------------------------------------------------------------------------------------
//   VRAM TO CPU : STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

wire copyVCActive = (currWorkState == COPYVC_TOCPU);
wire exitSig;
wire [2:0] cvs_nextX, cvs_nextY;

wire [1:0] aSelABDX;
wire       bSelAB;
wire       wbSel;
wire       pushNextCycle;

wire       memReadPairValid;
wire [31:0] memReadPairValue;

reg [31:0] pairPixelToCPU;
reg [15:0] DPixelReg;

wire nextPairIsLineLast = (nextPixelX == XE);
wire currPairIsLineLast = (pixelX     == XE);
wire readPairFromVRAM;
wire hasReadSpace;

// [Sub State machine for VC Copy command]
CVCopyState CVCopyState_Inst(
	.clk			(clk),
	.nRst			(i_nrst),
	
	.active			(copyVCActive),
	.isWidthNot1	(WidthNot1),
	.xb_0			(RegX0[0]),
	.wb_0			(RegSizeW[0]),
	
    .canNearPush(1'b0),
	.canPush			(!outFIFO_full & hasReadSpace),
	.endVertical		(endVertical),
	.nextPairIsLineLast	(nextPairIsLineLast),
	.currPairIsLineLast	(currPairIsLineLast),
	.readACK			(memReadPairValid),
	
	.o_nextX		(cvs_nextX),
	.o_nextY		(cvs_nextY),
	.read			(readPairFromVRAM),
	.exitSig		(exitSig),
	.o_aSelABDX		(aSelABDX),
	.o_bSelAB		(bSelAB),
	.o_writeFIFOOut (pushNextCycle),
	.o_wbSel		(wbSel)
);

reg pipeToFIFOOut;
always @(posedge clk)
begin
	// A Part
	case (aSelABDX)
	/*SELA_A = */2'd0: pairPixelToCPU[15:0] <= memReadPairValue[15:0];
	/*SELA_B = */2'd1: pairPixelToCPU[15:0] <= memReadPairValue[31:16];
	/*SELA_D = */2'd2: pairPixelToCPU[15:0] <= DPixelReg;
	/*SELA__ = */2'd3: begin /*Nothing*/ end
	endcase
	
	// B Part
	if (wbSel) begin
		pairPixelToCPU[31:16] <= bSelAB ? memReadPairValue[31:16] : memReadPairValue[15:0];
	end
	
	if (memReadPairValid) begin
		DPixelReg <= memReadPairValue[31:16];
	end
	pipeToFIFOOut <= pushNextCycle;
end

SSCfifo
#(
    .DEPTH_WIDTH	(2),
    .DATA_WIDTH		(32)
)
FifoPixOut_inst
(
    .clk			(clk ),
    .rst			(rstInFIFO),

    .wr_data_i		(pairPixelToCPU),
    .wr_en_i		(pipeToFIFOOut),

    .rd_data_o		(outFIFO_readV),
    .rd_en_i		(outFIFO_read),

    .full_o			(outFIFO_full),
    .empty_o		(outFIFO_empty)
);

//--------------------------------------------------------------------
// Work State machine
//--------------------------------------------------------------------
always @(*)
begin
    // -----------------------
    // Default Value Section
    // -----------------------
    memoryCommand				= MEM_CMD_NONE;
    nextWorkState				= currWorkState;
    incrementXCounter			= 0;
    resetXCounter				= 0;
    switchReadStoreBlock		= 0;
    useDest						= 0; // Source adr computation by default...
    memorizeLineEqu				= 0;
    loadNext					= 0;
    setPixelFound				= 0;
    resetPixelFound				= 0;
	setDirectionComplete		= 0;
    selNextX					= X_ASIS;
    selNextY					= Y_ASIS;
    switchDir					= 0;
    resetDir					= 0;
    writePixelL					= 0;
    writePixelR					= 0;
//	readStencil					= 0;
//	writeStencil2				= 2'b00;
    assignRectSetup				= 0;

//  setEnteredTriangle			= 0; // Disabled due to optimization.
//  resetEnteredTriangle		= 0;

//	resetBlockChange			= 0;
    setFirstPixel				= 0;
    setStencilMode				= 3'd0;
    writeStencil				= 0;
    stencilReadSig				= 0;
    stencilReadSigW				= 0;
    copyCVMode					= 0;

    resetBank					= 0;
    switchBank					= 0;
    clearOtherBank				= 0;
    clearBank0					= 0;
    clearBank1					= 0;

    // -----------------------
    //  CPU TO VRAM SIGNALS
    // -----------------------
    setLastPair = 0; resetLastPair = 0; setSwap = 0; changeSwap = 1'b0;
    readL				= 0;
    readM				= 0;
    flush				= 0;
    // -----------------------

    endClutLoading		= 0;
    decClutCount		= 0;
    requClutCacheUpdate	= 0;

// TODOSTENCIL	stencilWriteBitSelect	= 16'h0000;
// TODOSTENCIL	stencilWriteBitValue	= 16'h0000;
// TODOSTENCIL	stencilWordAdr	= 15'd0;
	setInterCounter			= (nextWorkState == SETUP_INTERP);
	setInterTexOnly			= 0; // Default start value.
	incrementInterpCounter	= 0; // Incr by 1 with single divide unit, 2 with two units.

    case (currWorkState)
    NOT_WORKING_DEFAULT_STATE:
    begin
        setFirstPixel			= 1;
        assignRectSetup			= !bIsPerVtxCol;
        // resetEnteredTriangle	= 1;	// Put here, no worries about more specific cases. // Removed due to optimization enteredTriangle flag not used anymore.
        resetDir				= 1;

        case (/*issue.*/issuePrimitive)
        ISSUE_TRIANGLE:
        begin
            setStencilMode		= 3'd1;
            if (bIsPerVtxCol) begin
                nextWorkState = SETUP_INTERP;
            end else begin
				setInterTexOnly = bUseTexture;
                nextWorkState   = (bUseTexture) ? SETUP_INTERP : TRIANGLE_START;
            end
        end
        ISSUE_RECT:
        begin
            setStencilMode		= 3'd1;
            assignRectSetup	= 1;
            nextWorkState	= WAIT_3; // Force checking palette fully.
        end
        ISSUE_LINE:
        begin
            setStencilMode		= 3'd1;
            if (bIsPerVtxCol) begin
                nextWorkState = SETUP_INTERP;
            end else begin
                nextWorkState = /*(bUseTexture) ? SETUP_UX :*/ LINE_START;	// Impossible : bUseTexture always false with LINES.
            end
        end
        ISSUE_FILL:
        begin
            setStencilMode		= 3'd2;
            nextWorkState = FILL_START;
        end
        ISSUE_COPY:
            if (bIsCopyVVCommand) begin
                setStencilMode		= 3'd6;
                nextWorkState		= COPY_INIT;
            end else if (bIsCopyCVCommand) begin
                setStencilMode		= 3'd3;
                nextWorkState		= COPYCV_START;
            end else begin
                // bIsCopyVCCommandbegin obviously...
                // STENCIL MODE NOT USED (no read, no write), BUT USED TO KNOW DIRECTION FOR CPU READ...
                setStencilMode		= 3'd7;
                nextWorkState		= COPYVC_START;
            end
        default:
            nextWorkState = currWorkState;
        endcase
    end
    // --------------------------------------------------------------------
    //   FILL VRAM STATE MACHINE
    // --------------------------------------------------------------------
    FILL_START:	// Actually FILL LINE START.
    begin
        if (emptySurface) begin
            nextWorkState = NOT_WORKING_DEFAULT_STATE;
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
        if (commandFIFOaccept) begin // else it will wait...
            memoryCommand		= MEM_CMD_FILL;
            writeStencil		= 1;
            if (isLastSegment) begin
                loadNext      = 1;
                selNextY      = Y_TRI_NEXT;
                resetXCounter = 1;
                nextWorkState = (endVertical) ? NOT_WORKING_DEFAULT_STATE : FILL_LINE;
            end else begin
                incrementXCounter	= 1;// SRC COUNTER
            end
        end
    end
    // --------------------------------------------------------------------
    //   COPY VRAM STATE MACHINE
    // --------------------------------------------------------------------

    COPY_INIT:
    begin
        nextWorkState		= COPY_START_LINE;
        selNextY = Y_CV_ZERO; loadNext = 1;
    end

    COPY_START_LINE:
    begin
        // [CPY_START] : Beginning of a line.
        // Copy never have 'empty surfaces'

        // Do start current line...
        nextWorkState		= CPY_RS1;
        resetBank			= 1;
        resetXCounter		= 1; // No load loadNext here.

        // TODO resetStencilTmp		= 1;
    end
    CPY_RS1: // Read Stencil.
    begin
        stencilReadSig	= 1; // Adr setup auto.
        if (commandFIFOaccept) begin
            nextWorkState = CPY_R1;
        // else nextWorkState stay the same
        end
    end

    CPY_R1:
    begin
        // Here we know that commandFIFOaccept is 1 (Previous state)
        // Store (Stencil & Mask) in temporary here
        incrementXCounter	= 1; useDest = 0; // Increment Source.
        // TODO storeStencilTmp		= 1;
        // TODO switchBank			= 1;
        clearOtherBank		= 1;
        memoryCommand		= MEM_CMD_RDBURST;

        if (allowNextRead) begin
            if (isDoubleLoad) begin
                nextWorkState	= CPY_RS2;
            end else begin
                nextWorkState	= CPY_LWS1;
            end
        end else begin
            nextWorkState		= CPY_WS2;
        end

        if (isDoubleLoad) begin
            if (allowNextRead) begin
                switchBank		= performSwitch;
            end else begin
                switchBank		= !performSwitch;
            end
        end else begin
            switchBank		= performSwitch;
        end

        //-------------------
        /* OLD BUGGY CODE
        if (allowNextRead) begin
            if (isDoubleLoad) begin
                switchBank		= performSwitch;
                nextWorkState	= CPY_RS2;
            end else begin
                // If PerformSwitch = 1 => Double bank switch -> No Switch !
                // If PerformSwitch = 0 => Single bank switch -> 1  Switch !
                switchBank		= !performSwitch;
                nextWorkState	= CPY_LWS1;
            end
        end else begin
            switchBank			= performSwitch;
            nextWorkState		= CPY_WS2;
        end
        */
    end
    CPY_RS2:
    begin
        stencilReadSig	= 1; // Adr setup auto.
        if (commandFIFOaccept) begin
            nextWorkState = CPY_R2;
        // else nextWorkState stay the same
        end
    end
    CPY_R2:
    begin
        incrementXCounter	= 1; useDest = 0; // Increment Source.
        // TODO storeStencilTmp		= 1;
        memoryCommand		= MEM_CMD_RDBURST;
        switchBank			= performSwitch;

        if (allowNextRead) begin
            nextWorkState	= CPY_LWS1;
        end else begin
            nextWorkState	= CPY_WS2;
        end
    end

    CPY_LWS1:
    begin
        stencilReadSigW		= 1;

        if (commandFIFOaccept) begin
            nextWorkState	= CPY_LW1;
        // else nextWorkState stay the same
        end
    end
    CPY_LW1:
    begin
        incrementXCounter	= 1; useDest = 1;
        memoryCommand		= MEM_CMD_WRBURST;
        writeStencil		= 1;
        nextWorkState		= CPY_LRS;
    end
    CPY_LRS:
    begin
        stencilReadSig	= 1; // Adr setup auto.
        if (commandFIFOaccept) begin
            nextWorkState	= CPY_LR;
        // else nextWorkState stay the same
        end
    end
    CPY_LR:
    begin
        incrementXCounter	= 1; useDest = 0; // Increment Source.

        memoryCommand		= MEM_CMD_RDBURST;
        switchBank			= performSwitch;

        if (!isLastSegment/* = allowNextRead, do NOT check isLongLine ! */) begin
            nextWorkState	= CPY_LWS1;
        end else begin
            nextWorkState	= CPY_WS2;
        end
    end

    CPY_WS2:
    begin
        stencilReadSigW		= 1;

        if (commandFIFOaccept) begin
            nextWorkState	= CPY_W2;
        // else nextWorkState stay the same
        end
    end
    CPY_W2:
    begin
        // Here : at this cycle we receive value from stencil READ.
        // And do now a STENCIL WRITE.
        incrementXCounter	= 1; useDest = 1;
        memoryCommand		= MEM_CMD_WRBURST;
        writeStencil		= 1;

        clearBank0			= !cpyBank;
        clearBank1			= cpyBank;
        switchBank			= performSwitch;

        if (!isLastSegmentDst) begin
            nextWorkState	= CPY_WS3;
        end else begin
            nextWorkState	= CPY_ENDLINE;
        end
    end
    CPY_WS3:
    begin
        stencilReadSigW		= 1;

        if (commandFIFOaccept) begin
            nextWorkState	= CPY_W3;
        // else nextWorkState stay the same
        end
    end
    CPY_W3:
    begin
        memoryCommand		= MEM_CMD_WRBURST;
        writeStencil		= 1;
        nextWorkState		= CPY_ENDLINE;
    end
    CPY_ENDLINE:
    begin
        selNextY			= Y_TRI_NEXT; loadNext = 1;

        if (endVertical) begin
            // End of copy primitive...
            nextWorkState	= NOT_WORKING_DEFAULT_STATE;
        end else begin
            nextWorkState	= COPY_START_LINE;
        end
    end

    // --------------------------------------------------------------------
    //   COPY CPU TO VRAM.
    // --------------------------------------------------------------------
    COPYCV_START:
    begin
        selNextX		= X_CV_START;
        selNextY		= Y_CV_ZERO;
        loadNext		= 1;
        setSwap			= 1;
        copyCVMode		= 1;
        // Reset last pair by default, but if WIDTH == 1 -> different.
        resetLastPair	= !((!WidthNot1) | nextPairIsLineLast);
        setLastPair		=   (!WidthNot1) | nextPairIsLineLast;
        // We set first pair read here, flag not need to be set for next state !
        // No Zero Size W/H Test -> IMPOSSIBLE By definition.
        if (canRead) begin
            // Read ALL DATA 1 item in advance -> Remove FIFO LATENCY /*issue.*/
            readL = 1'b1;
            readM = !RegX0[0] & (WidthNot1);
            nextWorkState = COPYCV_COPY;
            stencilReadSig	= 1;
        end
    end
    COPYCV_COPY:
    begin
//		stencilSourceAdr        = 0;
        // TRICKY :
        // -----------------------------
        // At the current pixel X,Y we preload the FIFO for the NEXT X,Y coordinate.
        // So setup of readL/readM are ONE PAIR in advance compare to the scanning...
        // -----------------------------
        stencilReadSig	= 1;
        copyCVMode		= 1;
		// Accept to process when :
		// - Can write the memory transaction.
		// - Has next data ready OR it is the LAST memory transaction.
        if (commandFIFOaccept & (canRead | (lastPair & endVertical))) begin
            memoryCommand = MEM_CMD_PIXEL2VRAM;
            nextWorkState = COPYCV_COPY;
            writeStencil  = 1;
            loadNext	  = 1;

            // [Last pair]
            if (lastPair) begin
                if (endVertical) begin
                    nextWorkState	= NOT_WORKING_DEFAULT_STATE;
                    // PURGE...
                    readL		= 1'b0;
                    readM		= RegSizeW[0] & RegSizeH[0]; // Pump out unused pixel in FIFO.
                    flush		= 1'b1;
                end else begin
                    selNextY	= Y_TRI_NEXT;
                    if (WidthNot1) begin
                        // WIDTH != 1, standard case
                        /* FIRST SEGMENT PATTERN
                            W=0	W=0	W=1	W=1
                            X=0	X=1	X=0	X=1
                        L=	1	1	1	!currY[0]
                        M=	1	0	1	currY[0]
                        */
                        case ({RegSizeW[0],RegX0[0]})
                        2'b00: begin
                            readL = 1'b1; readM = 1'b1;
                        end
                        2'b01: begin
                            readL = 1'b1; readM = 1'b0;
                        end
                        2'b10: begin
                            readL = 1'b1; readM = 1'b1;
                        end
                        2'b11: begin
                            readL = !nextPixelY[0]; readM = nextPixelY[0];
                        end
                        endcase
                        changeSwap  = RegSizeW[0] & WidthNot1; // If width=1, do NOT swap.
                    end else begin
                        // Only 1 pixel WIDTH pattern...
                        // Alternate ODD/EVEN lines...
                        readL		= !nextPixelY[0];
                        readM		=  nextPixelY[0];
                        changeSwap	= 1'b1;
                    end
                end
                selNextX		= X_CV_START;
                resetLastPair	= WidthNot1 & (!nextPairIsLineLast);
            end else begin
                // [MIDDLE OR FIRST SEGMENT]
                //    PRELOAD NEXT SEGMENT...
                if (nextPairIsLineLast) begin
                    /* LAST SEGMENT PATTERN
                        W=0	W=0	W=1		W=1
                        X=0	X=1	X=0		X=1
                    L = 1	0	!Y[0]	1
                    M = 1	1	Y[0]	1	*/
                    case ({RegSizeW[0],RegX0[0]})
                    2'b00: begin
                        readL = 1'b1; readM = 1'b1;
                    end
                    2'b01: begin
                        readL = 1'b0; readM = 1'b1;
                    end
                    2'b10: begin
                        // L on first line (even), M on second (odd)
                        readL = !pixelY[0]; readM = pixelY[0];
                    end
                    2'b11: begin
                        readL = 1'b1; readM = 1'b1;
                    end
                    endcase

                    setLastPair	= 1'b1; // TODO : Rename FirstPair into LastPair.
                end else begin
                    readL = 1'b1;
                    readM = 1'b1;
                end
                selNextX	= X_TRI_NEXT;
            end
        end
    end
    // --------------------------------------------------------------------
    //   COPY VRAM TO CPU.
    // --------------------------------------------------------------------
    COPYVC_START:
    begin
        // [PREAD COMMAND: [100][Index 5 bit] -> Next cycle have 16 bit through special port.
        // Use BSTORE Command for burst loading.
//		stencilSourceAdr        = 0;
        nextWorkState	= COPYVC_TOCPU;
        selNextX		= X_CV_START;
        selNextY		= Y_CV_ZERO;
		loadNext		= 1;
		
        /*
            Start : Request First Block. (X[3] is block ID (0/1))
                    If ((XLeft & 7)==7)
                        State = Start2
                    else
                        Wait
            Start2:	Request 2nd block    (![X3])
            Wait  : [Wait Command FIFO empty & Complete flag]
                    If ok -> Wait CPU
            WaitCPU:
                    if ((NextXLeft & 7)==7 || ==0) {
                        State = ReadNext
                    else

                    if (cpuReadValid) // Read GP0.
                        incX += 2;
                        Write pixel back.
                            State = Start2
                        } else {
                            State = AsIs;
                        }
                    else
                        wait cpu to read pixel...
                        State = AsIs;
                    end
         */
    end
    COPYVC_TOCPU:
    begin
		if (exitSig) begin
			nextWorkState = COPYVC_WAITFLUSH;
		end
		
		//
		// Done by sub state machine module...
		//
		
		memoryCommand = readPairFromVRAM ? MEM_CMD_VRAM2CPU : MEM_CMD_NONE;

		selNextX	= nextX_t'(cvs_nextX);
		selNextY	= nextY_t'(cvs_nextY);
		loadNext	= 1;
		
        // Detect edge transition... waiting for data received...
        // Data already present -> Read from both buffer possible.
        // Set gpuReadySendToCPU
    end
	COPYVC_WAITFLUSH:
	begin
		if (outFIFO_empty) begin
			nextWorkState = NOT_WORKING_DEFAULT_STATE;
		end
	end
    // --------------------------------------------------------------------
    //   TRIANGLE STATE MACHINE
    // --------------------------------------------------------------------
    SETUP_INTERP:
    begin
		nextWorkState = (nextInterpolationCounter[4:2] == { 1'b1, bUseTexture , 1'b0 }) ? WAIT_3 : SETUP_INTERP;
		incrementInterpCounter = 1;
    end
    WAIT_3: // 4 cycles to wait
    begin
        // Use this state to wait for end previous memory transaction...
        nextWorkState = (saveLoadOnGoing == 0) ? WAIT_2 : WAIT_3;
    end
    WAIT_2: // 3 cycles to wait
    begin
		// [TODO] That test could be put outside and checked EARLY --> RECT could skip to RECT_START 3 cycle earlier. Safe for now.
		//        Did that before but did not checked whole condition --> FF7 Station failed some tiles.
		
		// validCLUTLoad is when CLUT reloading was set
		// isPalettePrimitive & rPalette4Bit & CLUTIs8BPP is when nothing changed, EXCEPT WE WENT FROM 4 BIT TO 8 BIT !
        if (validCLUTLoad || (isPalettePrimitive & rPalette4Bit & CLUTIs8BPP)) begin
            // Not using signal updateClutCacheComplete but could... rely on transaction only.
            if (saveLoadOnGoing == 0) begin // Wait for an on going memory transaction to complete.
                if (rClutPacketCount != 5'd0) begin
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
        endClutLoading	= isPalettePrimitive;	// Reset flag, even if it was already reset. Force 0.
                                                // Force also to cache the current primitive pixel format (was it 4 bpp ?)
        nextWorkState = SELECT_PRIMITIVE;
    end
    SELECT_PRIMITIVE: 	// 1 Cycle to wait... send to primitive (with 1 cycle wait too...)
    begin				// Need 4 more cycle after that.
        if (bIsRectCommand) begin
            nextWorkState = RECT_START;
        end else begin
            if (bIsPolyCommand) begin
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
            nextWorkState	= NOT_WORKING_DEFAULT_STATE;
        end else begin
            nextWorkState	= START_LINE_TEST_LEFT;
            selNextX	= X_TRI_BBLEFT;	// Set currX = BBoxMinX intersect X Draw Area.
            selNextY	= Y_TRI_START;	// Set currY = BBoxMinY intersect Y Draw Area.
        end

        // Triangle use PSTORE COMMAND. (2 pix per clock)
        //              BWRITE
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
            loadNext 		= 1;
            selNextX		= X_TRI_BBRIGHT;// Set next X = BBox RIGHT intersected with DrawArea.
        end
    end
    START_LINE_TEST_RIGHT:
    begin
        loadNext 	= 1;
        selNextX	= X_TRI_BBLEFT;	// Set currX = BBoxMinX intersect X Draw Area.
        // Test Bbox left (included) has SAME line equation result as right (excluded) result of line equation.
        // If so, mean that we are at the same area defined by the equation.
        // We also test that we are NOT a valid pixel inside the triangle.
        // We use L/R result based on RIGHT edge coordinate (odd/even).
        if ( edgeDidNOTSwitchLeftRightBB	// Check that TRIANGLE EDGE did not SWITCH between the LEFT and RIGHT side of the bounding box.
         && ((!maxTriDAX1[0] && !isValidPixelL) || (maxTriDAX1[0] && !isValidPixelR)))		// And that we are OUTSIDE OF THE TRIANGLE. (if odd/even pixel, select proper L/R validpixel.) (Could be also a clipped triangle with FULL LINE)
        begin
            selNextY		= Y_TRI_NEXT;
            nextWorkState	= isValidHorizontalTriBbox ? START_LINE_TEST_LEFT : FLUSH_COMPLETE_STATE;
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
            //        Warning : Care of single pixel write logic + and non increment of X.

            // TODO : Mask stuff here at IF level too.
            if (isValidPixelL || isValidPixelR) begin // Line Equation.
                // setEnteredTriangle = 1;  REMOVED, Optimization testing enteredTriangle not necessary anymore.

                if (pixelFound == 0) begin
                    setPixelFound	= 1;
                end

                // TODO Pixel writing logic
                if (requestNextPixel) begin
//					resetBlockChange = 1;

                    // Write only if pixel pair is valid...

                    writePixelL	= isValidPixelL  & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
                    writePixelR	= isValidPixelR  & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

                    // writeStencil2 = { writePixelR , writePixelL };

                    // Go to next pair whatever, as long as request is asking for new pair...
                    // normally changeX = 1; selNextX = X_TRI_NEXT;  [!!! HERE !!!]
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
                    if (pixelFound == 1) begin // Pixel Found.
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
            nextWorkState	= FLUSH_COMPLETE_STATE;
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
    //   RECT STATE MACHINE
    // --------------------------------------------------------------------
    RECT_START:
    begin
        // Rect use PSTORE COMMAND. (2 pix per clock)
        nextWorkState	= RECT_SCAN_LINE;
        stencilReadSig	= 1;
        if (earlyTriangleReject | isNegXAxis | isNegPreB) begin // VALID FOR RECT TOO : Bounding box and draw area do not intersect at all, or NegativeSize => size = 0.
            nextWorkState	= NOT_WORKING_DEFAULT_STATE;	// Override state.
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
                    writePixelL   = isInsideBBoxTriRectL & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
                    writePixelR   = isInsideBBoxTriRectR & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

                    // Go to next pair whatever, as long as request is asking for new pair...
                    // normally changeX = 1; selNextX = X_TRI_NEXT;  [!!! HERE !!!]
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
    //   LINE STATE MACHINE
    // --------------------------------------------------------------------
    LINE_START:
    begin
        /* Line Setup, Triangle setup may be... */
        loadNext	= 1;
        stencilReadSig	= 1;
        selNextX	= X_LINE_START;
        selNextY	= Y_LINE_START;
        nextWorkState = LINE_DRAW;
    end
    LINE_DRAW:
    begin
        if (requestNextPixel) begin
            stencilReadSig	= 1;
            selNextX	= X_LINE_NEXT;
            selNextY	= Y_LINE_NEXT;
            loadNext	= 1;

            if ((pixelX == RegX1) && (pixelY == RegY1)) begin
                nextWorkState	= FLUSH_COMPLETE_STATE; // Override nextWorkState from setup in this.
            end

            // If pixel is valid and (no mask checking | mask check with value = 0)
            if (isLineInsideDrawArea 																		// VALID AREA
			&& ((!InterlaceRender)    || (InterlaceRender && (GPU_REG_CurrentInterlaceField != pixelY[0])))	// NON INTERLACED OR INTERLACE BUT VALID AREA
			&& ((GPU_REG_CheckMaskBit && (!selectPixelWriteMaskLine)) || (!GPU_REG_CheckMaskBit))) begin	// Clipping DrawArea, TODO: Check if masking apply too.
                writePixelL	 = isLineLeftPix;
                writePixelR	 = isLineRightPix;
            end
        end
    end
    FLUSH_COMPLETE_STATE:
    begin
        // We stopped emitting pixels, now we have to check that :
        // - No memory transaction is running anymore.
        // - No pixel are in flight.
        if (!saveLoadOnGoing && !pixelInFlight) begin
            flush = 1'b1;
            nextWorkState = NOT_WORKING_DEFAULT_STATE;
        end
    end
    // --- TEMP DEBUG STUFF ---
    TMP_2: begin nextWorkState = TMP_3; end
    TMP_3: begin nextWorkState = TMP_4; end
    TMP_4: begin nextWorkState = NOT_WORKING_DEFAULT_STATE; end
    default:
    begin
        nextWorkState = NOT_WORKING_DEFAULT_STATE;
    end
    endcase
end


StencilCache StencilCacheInstance(
    .clk					(clk),

    .fullMode				(stencilFullMode),
    .writeValue16			(stencilWriteValue16),
    .writeMask16			(stencilWriteMask16),
    .readValue16			(stencilReadValue16),

    // -------------------------------
    //   Stencil Cache Write Back
    // -------------------------------
    .stencilWriteSig		(stencilWriteSigC),		// Write (use for FULL mode and PAIR MODE, in FULL mode Write=0 -> EQUAL READ)
    .stencilWriteAdr		(stencilWriteAdrC),		// Where to write
    .stencilWritePair		(stencilWritePairC),
    .stencilWriteSelect		(stencilWriteSelectC),		// Where inside the pair
    .stencilWriteValue		(stencilWriteValueC),		// Value to write

    // -------------------------------
    //   Stencil Cache Read
    // -------------------------------
    .stencilReadSig			(stencilReadSig | stencilReadSigW),		// Write
    .stencilReadAdr			(stencilReadAdr),		// Where to read
    .stencilReadPair		(stencilReadPair),
    .stencilReadSelect		(stencilReadSelect),
    .stencilReadValue		(stencilReadValue)		// Value to write
);

wire	[15:0]	stencilWMaskCpy   = maskReadRemapped    & ({16{!GPU_REG_CheckMaskBit}} | (~stencilReadValue16));
wire	[15:0]	stencilWValueCpy  = stencilReadRemapped |  {16{GPU_REG_ForcePixel15MaskSet}};

always @(*)
begin
    stencilWriteValue16	= stencilMode[2] ? stencilWValueCpy : 16'd0;	// For now... FILL ONLY.
    stencilWriteMask16	= stencilMode[2] ? stencilWMaskCpy  : 16'hFFFF;	// For now... FILL ONLY.

    if (stencilMode[1:0] == 2'd2) begin
        // Work for FILL command OR VRAM<->VRAM Command.
        stencilFullMode		= 1;
        stencilWriteSigC	= writeStencil;
        stencilWriteAdrC	= { stencilMode[2] ? scrDstY[8:0] : scrY[8:0]
                                , stencilMode[2] ?      scrDstX : scrSrcX   };
    end else begin
        // Work for Triangle/Line/Rect primtive
        // CPU->VRAM
        stencilFullMode		= 0;
        stencilWriteSigC	= (stencilMode == 3'd3) ? writeStencil               : stencilWriteSig;
        stencilWriteAdrC	= (stencilMode == 3'd3) ? { scrY[8:0], pixelX[9:4] } : stencilWriteAdr;
    end

    if (stencilMode == 3'd3) begin
        // CPU->VRAM
        stencilWritePairC	= pixelX[3:1];
        stencilWriteSelectC	= { cmd1ValidR , cmd1ValidL };
        stencilWriteValueC	= { WRPixelR15 , WRPixelL15 };
    end else begin
        // Triangle/Line/Rect (Ignored for FILL VRAM)
        stencilWritePairC	= stencilWritePair;
        stencilWriteSelectC	= stencilWriteSelect;
        stencilWriteValueC	= stencilWriteValue;
    end
end

wire    [14:0]  VVReadAdrStencil = stencilReadSigW ? { scrDstY[8:0] , scrDstX } : { scrY[8:0] , scrSrcX };

assign stencilReadAdr		= stencilMode[2] ? VVReadAdrStencil	// VRAM<->VRAM Mode Only
                                             : { copyCVMode ? nextScrY[8:0] : nextPixelY[8:0], nextPixelX[9:4] };		// Other modes.
assign stencilReadPair		= { nextPixelX[3:1] };						//
// Select 11 for other primitives, or the correct pixel for the read for LINES.
assign stencilReadSelect	= { !bIsLineCommand | nextPixelX[0] , !bIsLineCommand | (!nextPixelX[0]) };

// [BYTE PIXEL ADR FROM X/Y]
// YYYY.YYYY.YXXX.XXXX.XXX0 Byte.
// YYYY.YYYY.YXXX.XXX_.____ {

assign selectPixelWriteMaskLine = (!pixelX[0] & stencilReadValue[0]) | (pixelX[0] & stencilReadValue[1]);

// TODO OPTIMIZE : can probably compute nextCondUseFIFO outside with : (nextLogicalState != WAIT_COMMAND_COMPLETE) & (nextLogicalState != DEFAULT_STATE)

reg bPipeIssueTrianglePrimitive;
always @(posedge clk)
begin
    bPipeIssueTrianglePrimitive <= (issuePrimitive == ISSUE_TRIANGLE);
end



/*
// Compute diff :
    Y1-Y0
    Y2-Y0
    X2-X0

    Primitive wide 1024 pixel max, height 512 pixel max.

    So, to support the worst case (0 at one edge, 1 at another edge), the smallest step we need 10 bit of sub precision (ie add 1/1024 at each step.

    => I will not bother about the Y and X direction like the original HW is probably doing.
    => I will keep the same precision for ALL attributes. Same computation unit, etc...


*/
// Texcoord = (Texcoord AND (NOT (Mask*8))) OR ((Offset AND Mask)*8)

//	assign green = (|PrimClut) ? VtxY2 + VtxY1 + VtxY0 : VtxG0 + VtxG1 + VtxG2;
//	assign blue  = (|RegSizeW & |RegSizeH) ? VtxU2 + VtxU1 + VtxU0 : VtxB0 + VtxB1 + VtxB2;
// wire requestLPix, requestRPix;

// Do NOT REQUEST pixel if :
// - Memory is busy reading Texture or Clut.
// - Start a new block.
// -
assign requestNextPixel = (!missTC) & (!writePixelOnNewBlock) & (!saveLoadOnGoing) & (!commandFifoFull);

// wire notMemoryBusyCurrCycle;
// wire notMemoryBusyNextCycle;

// [Cache Texture swizzling vary with Texture Format]
wire textureFormatTrueColor = (GPU_REG_TexFormat[1]); // (10)2 or (11)3
directCacheDoublePort directCacheDoublePortInst(
    .i_clk								(clk),
    .i_nrst								(i_nrst),
    .i_clearCache						(/*issue.*/rstTextureCache),

    // [Can spy all write on the bus and maintain cache integrity]
    .i_textureFormatTrueColor			(textureFormatTrueColor),
    .i_write							(TexCacheWrite),
    .i_adressIn							(adrTexCacheWrite),
    .i_dataIn							(TexCacheData),

    .i_requLookupA						(requDataTex_c0L),
    .i_adressLookA						(adrTexReq_c0L),
    .o_dataOutA							(dataTex_c1L),
    .o_isHitA							(TexHit_c1L),
    .o_isMissA							(TexMiss_c1L),

    .i_requLookupB						(requDataTex_c0R),
    .i_adressLookB						(adrTexReq_c0R),
    .o_dataOutB							(dataTex_c1R),
    .o_isHitB							(TexHit_c1R),
    .o_isMissB							(TexMiss_c1R)
);

/*
//---------------------------------------------------------------------
// PERFORMANCE COUNTER FOR TEX$ MISS / SUCCESS
//---------------------------------------------------------------------
reg pipeReqA; reg pipeReqB;
reg pipepipeReqA; reg pipepipeReqB;
reg prevTexHit_c1L; reg prevTexHit_c1R;

always @(posedge clk)
begin
	pipeReqA 		<= requDataTex_c0L;
	pipeReqB 		<= requDataTex_c0R;
	pipepipeReqA	<= pipeReqA;
	pipepipeReqB	<= pipeReqB;
	prevTexHit_c1L	<= TexHit_c1L;
	prevTexHit_c1R	<= TexHit_c1R;
end

reg [22:0] HitACounter;
reg [22:0] HitBCounter;
reg [22:0] TotalACounter;
reg [22:0] TotalBCounter;

always @(posedge clk)
begin
	if (writeGP1) begin
		HitACounter   <= 23'd0;
		TotalACounter <= 23'd0;
		HitBCounter   <= 23'd0;
		TotalBCounter <= 23'd0;
	end else begin
		if (TexHit_c1L) begin
			HitACounter   <= HitACounter   + 23'd1;
			TotalACounter <= TotalACounter + 23'd1; 
		end else begin
			// !TexHit_c1L
			// - (prevHit=1 & pipeReqA)
			// - pipeReg & !pipepipeReg
			if ((!pipepipeReqA & pipeReqA) | (pipeReqA & prevTexHit_c1L)) begin
				TotalACounter <= TotalACounter + 23'd1;
			end
		end

		if (TexHit_c1R) begin
			HitBCounter   <= HitBCounter   + 23'd1;
			TotalBCounter <= TotalBCounter + 23'd1; 
		end else begin
			if ((!pipepipeReqA & pipeReqA) | (pipeReqA & prevTexHit_c1L)) begin
				TotalBCounter <= TotalBCounter + 23'd1;
			end
		end
		
	end
end
//---------------------------------------------------------------------
*/
wire signed [8:0] pixRL,pixGL,pixBL,pixRR,pixGR,pixBR;
wire signed [7:0] pixUL,pixVL,pixUR,pixVR;

gpu_setupunit gpu_setupunit_inst(
	.i_clk						(clk),

	.i_bIsLineCommand			(bIsLineCommand),

	// --------------------------
	// Loaded register
	// --------------------------
	.RegX0						(RegX0),
	.RegY0						(RegY0),
	.RegX1						(RegX1),
	.RegY1						(RegY1),
	.RegX2						(RegX2),
	.RegY2						(RegY2),

	.RegR0						(RegR0),
	.RegG0						(RegG0),
	.RegB0						(RegB0),
	.RegU0						(RegU0),
	.RegV0						(RegV0),
	.RegR1						(RegR1),
	.RegG1						(RegG1),
	.RegB1						(RegB1),
	.RegU1						(RegU1),
	.RegV1						(RegV1),
	.RegR2						(RegR2),
	.RegG2						(RegG2),
	.RegB2						(RegB2),
	.RegU2						(RegU2),
	.RegV2						(RegV2),

	// --------------------------
	// GPU registers
	// --------------------------
	.GPU_REG_DrawAreaX0			(GPU_REG_DrawAreaX0),
	.GPU_REG_DrawAreaY0			(GPU_REG_DrawAreaY0),
	.GPU_REG_DrawAreaX1			(GPU_REG_DrawAreaX1),
	.GPU_REG_DrawAreaY1			(GPU_REG_DrawAreaY1),

	// --------------------------
	// State machine Control
	// --------------------------
	// Signal when setup primitive
	.i_interpolationCounter		(interpolationCounter),
	.i_assignRectSetup			(assignRectSetup),
	
	// Line runtime logic control from state machine
	.i_memorizeLineEqu			(memorizeLineEqu),
	.i_lineStart				(lineStart),
	.i_loadNext					(loadNext),

	.o_isLineInsideDrawArea		(isLineInsideDrawArea),
	.o_isLineLeftPix			(isLineLeftPix),
	.o_isLineRightPix			(isLineRightPix),

	// Triangle runtime feedback
	.o_isNULLDET				(isNULLDET),
	.o_isNegXAxis				(isNegXAxis),
	.o_isValidPixelL			(isValidPixelL),
	.o_isValidPixelR			(isValidPixelR),
	.o_earlyTriangleReject		(earlyTriangleReject),
	.o_edgeDidNOTSwitchLeftRightBB	(edgeDidNOTSwitchLeftRightBB),
	.o_reachEdgeTriScan			(reachEdgeTriScan),
	
	.o_isValidHorizontalTriBbox	(isValidHorizontalTriBbox),
	.o_isRightPLXmaxTri			(isRightPLXmaxTri),
	.o_isInsideBBoxTriRectL		(isInsideBBoxTriRectL),
	.o_isInsideBBoxTriRectR		(isInsideBBoxTriRectR),
	.o_isBottomInsideBBox		(isBottomInsideBBox),
	
	.o_isNegPreB				(isNegPreB),
	
	.o_nextLineX				(nextLineX),
	.o_nextLineY				(nextLineY),
	
	.o_minTriDAX0				(minTriDAX0),
	.o_maxTriDAX1				(maxTriDAX1),
	.o_minTriDAY0				(minTriDAY0),
	
	// --------------------------
	// Runtime parameters
	// --------------------------
	.i_pixelX					(pixelX),
	.i_pixelY					(pixelY),
	
	.i_scanDirectionR2L			(dir),
	
	.o_pixRL					(pixRL),
	.o_pixGL					(pixGL),
	.o_pixBL					(pixBL),
	.o_pixUL					(pixUL),
	.o_pixVL					(pixVL),

	.o_pixRR					(pixRR),
	.o_pixGR					(pixGR),
	.o_pixBR					(pixBR),
	.o_pixUR					(pixUR),
	.o_pixVR					(pixVR)
);


// ------------------------------------------------
CLUT_Cache CLUT_CacheInst(
    .i_clk								(clk),
    .i_nrst								(i_nrst),

    .i_write							(ClutCacheWrite),
    .i_writeBlockIndex					(rClutPacketCount[3:0]),
    .i_writeIdxInBlk					(ClutWriteIndex),
    .i_Colors							(ClutCacheData),

    .i_readIdxL							(indexPalL),
    .o_colorEntryL						(dataClut_c2L),

    .i_readIdxR							(indexPalR),
    .o_colorEntryR						(dataClut_c2R)
);

// ------------------------------------------------
// wire [31:0]		readValue32;
// wire            dataArrived;
// wire			dataConsumed;

// [TODO NEXT STEP BUS]
wire  [5:0]    XPosClut           = {1'b0, nextClutPacket/*rClutPacketCount*/} + RegCLUT[5:0];
wire  [14:0]   adrClutCacheUpdate = { RegCLUT[14:6] , XPosClut };
// END [TODO NEXT STEP BUS]

MemoryArbitratorFat MemoryArbitratorInstance(
    .gpuClk					(clk),
	.busClk					(clkBus),
    .i_nRst					(i_nrst),

    // ---TODO Describe all fifo command ---
    .memoryWriteCommand		(memoryWriteCommand),
    .o_fifoFull				(commandFifoFull),
    .fifoComplete			(commandFifoComplete),
	.o_hasReadSpace			(hasReadSpace),

//    .o_dataArrived			(dataArrived),
//    .o_dataValue			(readValue32),
//    .i_dataConsumed			(dataConsumed),

    // -----------------------------------
    // [GPU BUS SIDE MODE]
    // -----------------------------------

    // -- TEX$ Stuff --
    // TEX$ Cache miss from L Side
    .requTexCacheUpdateL	(requTexCacheUpdateL_i),
    .adrTexCacheUpdateL		(adrTexCacheUpdateL_i),
    .updateTexCacheCompleteL(updateTexCacheCompleteL_o),

    // TEX$ Cache miss from R Side
    .requTexCacheUpdateR	(requTexCacheUpdateR_i),
    .adrTexCacheUpdateR		(adrTexCacheUpdateR_i),
    .updateTexCacheCompleteR(updateTexCacheCompleteR_o),

    // TEX$ feed updated $ data to cache.
    .TexCacheWrite			(TexCacheWrite),
    .adrTexCacheWrite		(adrTexCacheWrite),
    .TexCacheData			(TexCacheData),

    // -- CLUT$ Stuff --
    .requClutCacheUpdate	(requClutCacheUpdate),
    .adrClutCacheUpdate		(adrClutCacheUpdate),
    .updateClutCacheComplete(updateClutCacheComplete),

    // CLUT$ feed updated $ data to cache.
    .ClutCacheWrite			(ClutCacheWrite),
    .ClutWriteIndex			(ClutWriteIndex),
    .ClutCacheData			(ClutCacheData),

    // -- BG Read Stuff --
    /*
    .bgRequest				(bgRequest_i	),
    .bgRequestAdr			(bgRequestAdr_i	),
    .validbgPixel			(validbgPixel_o	),	// 0 Cycle Delay if data available in Cache.
    .bgPixel				(bgPixel_o		),	// 0 Cycle Delay if data available in Cache.

    // -- BG Write Stuff --
    .write32				(write32_i),
    .bgWriteAdr				(bgWriteAdr_i),
    .pixelValid				(pixelValid_i),
    .flushBG				(flushBG_i),
    .writePixelDone			(writePixelDone_o),

    .notMemoryBusyCurrCycle	(notMemoryBusyCurrCycle),
    .notMemoryBusyNextCycle	(notMemoryBusyNextCycle),
    */
//    .notMemoryBusyCurrCycle	(notMemoryBusyCurrCycle),
//    .notMemoryBusyNextCycle	(notMemoryBusyNextCycle),

    // Ask to write/read BG
    .isBlending							(bSemiTransp),
    .saveAdr							(saveAdr),
    .loadAdr							(loadAdr),
    .saveBGBlock						(saveBGBlock | {flush , flush}),			// Stay 1 for long, should use 0->1 TRANSITION on user side.
    .exportedBGBlock					(exportedBGBlock),
    .exportedMSKBGBlock					(exportedMSKBGBlock),
    .saveLoadOnGoing					(saveLoadOnGoing),

    // BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
    .importBGBlockSingleClock			(importBGBlockSingleClock),
    .importedBGBlock					(importedBGBlock),

    .resetPipelinePixelStateSpike		(resetPipelinePixelStateSpike),
    .resetMask							(resetMask),

	// Read 32 value direct port for VRAM->CPU
	.readPairValid						(memReadPairValid),
	.readPairValue						(memReadPairValue),

    // -----------------------------------
    // [Memory SIDE]
    // -----------------------------------
	.o_command							(o_command		),    // 0 = do nothing, 1 Perform a read or write to memory.
	.i_busy								(i_busy			),    // Memory busy 1 => can not use.
	.o_commandSize						(o_commandSize	),    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)

	.o_write							(o_write		),    // 0=READ / 1=WRITE 
	.o_adr								(o_adr			),    // 1 MB memory splitted into 32768 block of 32 byte.
	.o_subadr							(o_subadr		),    // Block of 8 or 4 byte into a 32 byte block.
	.o_writeMask						(o_writeMask	),

	.i_dataIn							(i_dataIn		),
	.i_dataInValid						(i_dataInValid	),
	.o_dataOut                          (o_dataOut		)

	/*
    .adr_o					(adr_o),   // ADR_O() address
    .dat_i					(dat_i),   // DAT_I() data in
    .dat_o					(dat_o),   // DAT_O() data out
    .cnt_o					(cnt_o),
    .sel_o					(sel_o),
    .wrt_o					(wrt_o),
    .req_o					(req_o),
    .ack_i					(ack_i)
	*/
);

GPUBackend GPUBackendInstance(
    .clk								(clk),
    .i_nrst								(i_nrst),

    // -------------------------------
    // Control line for state machine
    // -------------------------------
    .i_pausePipeline					(pausePipeline),			// Freeze the data in the pipeline. Values stay as is.
    .o_missTC							(missTC),					// Any Cache miss, stop going next pixels.
    // Management on BG Block
    .o_writePixelOnNewBlock				(writePixelOnNewBlock),	// Tells us that the current pixel WRITE to a new BG block, write to the REGISTER this clock if not paused (upper logic will use create the input pausePipeline with combinatorial to avoid write with this flag)
    .i_resetPipelinePixelStateSpike		(resetPipelinePixelStateSpike),	// 1/ Clear 'o_writePixelOnNewBlock' flag.
    .i_resetPixelMask					(resetMask),					// 2/ Clear MASK for new block.
    // -------------------------------
    // GPU Setup
    // -------------------------------
    .GPU_REG_Transparency				(GPU_REG_Transparency			),
    .GPU_REG_TexFormat					(GPU_REG_TexFormat				),
    .noTexture							(!bUseTexture					),
    .noblend							(bOpaque						),
    .ditherActive						(bDither						),
    .GPU_REG_TexBasePageX				(GPU_REG_TexBasePageX			),
    .GPU_REG_TexBasePageY				(GPU_REG_TexBasePageY			),
    .GPU_REG_TextureXFlip				(GPU_REG_TextureXFlip			),
    .GPU_REG_TextureYFlip				(GPU_REG_TextureYFlip			),
    .GPU_REG_WindowTextureMaskX			(GPU_REG_WindowTextureMaskX		),
    .GPU_REG_WindowTextureMaskY			(GPU_REG_WindowTextureMaskY		),
    .GPU_REG_WindowTextureOffsetX		(GPU_REG_WindowTextureOffsetX	),
    .GPU_REG_WindowTextureOffsetY		(GPU_REG_WindowTextureOffsetY	),

    // -------------------------------
    // Input Pixels from FrontEnd
    // -------------------------------
    .iPixelStateSpike					(pixelStateSpike), // Input Flag to the pipeline.
    .iScrX_Mul2							(pixelX[9:0]),
    .iScrY								(pixelY[8:0]),

    .iR_L								(pixRL),
    .iG_L								(pixGL),
    .iB_L								(pixBL),
    .U_L 								(pixUL),
    .V_L 								(pixVL),
    .validPixel_L						(writePixelL),
    .bgMSK_L							(stencilReadValue[0] | GPU_REG_ForcePixel15MaskSet),

    .iR_R								(pixRR),
    .iG_R								(pixGR),
    .iB_R								(pixBR),
    .U_R 								(pixUR),
    .V_R 								(pixVR),
    .validPixel_R						(writePixelR),
    .bgMSK_R							(stencilReadValue[1] | GPU_REG_ForcePixel15MaskSet),

    // -------------------------------
    //  Request to Cache system ?
    // -------------------------------
    .requDataTex_c0L					(requDataTex_c0L),
    .adrTexReq_c0L						(adrTexReq_c0L	),
    .TexHit_c1L							(TexHit_c1L		),
    .TexMiss_c1L						(TexMiss_c1L	),
    .dataTex_c1L						(dataTex_c1L	),

    // Request Cache Fill
    .requTexCacheUpdate_c1L				(requTexCacheUpdateL_i),
    .adrTexCacheUpdate_c0L				(adrTexCacheUpdateL_i),
    .updateTexCacheCompleteL			(updateTexCacheCompleteL_o),

    // Clut$ Side
    .indexPalL							(indexPalL			),	// Temp
    .dataClut_c2L						(dataClut_c2L		),

    // --- Tex$ Side ---
    .requDataTex_c0R					(requDataTex_c0R),
    .adrTexReq_c0R						(adrTexReq_c0R	),
    .TexHit_c1R							(TexHit_c1R		),
    .TexMiss_c1R						(TexMiss_c1R	),
    .dataTex_c1R						(dataTex_c1R	),

    // Request Cache Fill
    .requTexCacheUpdate_c1R				(requTexCacheUpdateR_i),
    .adrTexCacheUpdate_c0R				(adrTexCacheUpdateR_i),
    .updateTexCacheCompleteR			(updateTexCacheCompleteR_o),

    // Clut$ Side
    .indexPalR							(indexPalR			),	// Temp
    .dataClut_c2R						(dataClut_c2R		),

    // -------------------------------
    //   Stencil Cache Write Back
    // -------------------------------
    // Write
    .stencilWriteSig					(stencilWriteSig	),
    .stencilWriteAdr					(stencilWriteAdr	),
    .stencilWritePair					(stencilWritePair	),
    .stencilWriteSelect					(stencilWriteSelect	),
    .stencilWriteValue					(stencilWriteValue	),

    // -------------------------------
    //   Flush until
    // -------------------------------
    .flushLastBlock						(flush),
    .o_pixelInFlight					(pixelInFlight),

    // -------------------------------
    //   DDR
    // -------------------------------

    // Ask to write BG
    .loadAdr							(loadAdr			),
    .saveAdr							(saveAdr			),
    .saveBGBlock						(saveBGBlock		),			// Stay 1 for long, should use 0->1 TRANSITION on user side.
    .exportedBGBlock					(exportedBGBlock	),
    .exportedMSKBGBlock					(exportedMSKBGBlock	),

    // BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
    .importBGBlockSingleClock			(importBGBlockSingleClock),
    .importedBGBlock					(importedBGBlock)
);


endmodule

