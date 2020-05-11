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

    input			gpuAdrA2, // Called A2 because multiple of 4
    input			gpuSel,
    output			o_canWrite,

    output			IRQRequest,

    // Video output...
//	output	[7:0]	red,
//	output	[7:0]	green,
//	output	[7:0]	blue,
//	output          owritePixelL,
//	output          owritePixelR,
    output	[31:0]	mydebugCnt,

    //
    // Temporary Memory Interface
    //
    output [19:0]   adr_o,   // ADR_O() address
    input  [31:0]   dat_i,   // DAT_I() data in
    output [31:0]   dat_o,   // DAT_O() data out
    output  [2:0]	cnt_o,
    output  [3:0]   sel_o,
    output			wrt_o,
    output			req_o,
    input			ack_i,

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

    input			write,
    input			read,
    input 	[31:0]	cpuDataIn,
    output reg [31:0]	cpuDataOut,
    output reg			validDataOut
);

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
    SETUP_RX					= 6'd29,
    SETUP_RY					= 6'd30,
    SETUP_GX					= 6'd31,
    SETUP_GY					= 6'd32,
    SETUP_BX					= 6'd33,
    SETUP_BY					= 6'd34,
    SETUP_UX					= 6'd35,
    SETUP_UY					= 6'd36,
    SETUP_VX					= 6'd37,
    SETUP_VY					= 6'd38,
    RECT_SCAN_LINE				= 6'd39,
    WAIT_3						= 6'd40,
    WAIT_2						= 6'd41,
    WAIT_1						= 6'd42,
    SELECT_PRIMITIVE			= 6'd43,
    COPYCV_COPY					= 6'd44,
    RECT_READ_MASK				= 6'd45,
    COPYVC_TOCPU				= 6'd46,
    LINE_END					= 6'd47,
    FLUSH_COMPLETE_STATE		= 6'd48,
    COPY_START_LINE				= 6'd49,
    CPY_ENDLINE					= 6'd50
} workState_t;

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
    Y_TRI_PREV		= 3'd5,
    Y_CV_ZERO		= 3'd6,
    // 7 free...
    Y_ASIS			= 3'd0
} nextY_t;


parameter EQUMSB = 22; // 11bit signed * 11 bit signed.

parameter   IS_NOT_NEWBLOCK				= 2'b00,
            IS_NEW_BLOCK_IN_PRIMITIVE	= 2'b01,	// The first time we flush a 16 pixel block, there is NO WRITE of the previous block, but LOAD must be done if doing blending.
            IS_OTHER_BLOCK_IN_PRIMITIVE	= 2'b10,	// For other block we simply do WRITE the previous block, or WRITE + LOAD next block BG if doing blending.
            IS_FLUSH_LAST_PIXEL			= 2'b11;

parameter PREC = 11;
parameter PRECM1 = PREC-1;
parameter ZERO_PREC = 20'd0, ONE_PREC = 20'h800;

typedef enum logic[3:0] {
    DEFAULT_STATE		=4'd0,
    LOAD_COMMAND		=4'd1,
    COLOR_LOAD			=4'd2,
    VERTEX_LOAD			=4'd3,
    UV_LOAD				=4'd4,
    WIDTH_HEIGHT_STATE	=4'd5,
    LOAD_XY1			=4'd6,
    LOAD_XY2			=4'd7,
    WAIT_COMMAND_COMPLETE = 4'd8,
    COLOR_LOAD_GARAGE   =4'd9,
    VERTEX_LOAD_GARAGE	=4'd10
} state_t;

parameter TRANSP_HALF=2'd0, TRANSP_ADD=2'd1, TRANSP_SUB=2'd2, TRANSP_ADDQUARTER=2'd3;
parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;

parameter XRES_256=2'd0, XRES_320=2'd1, XRES_512=2'd2, XRES_640=2'd3;
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

parameter	MEM_CMD_PIXEL2VRAM	= 3'b001,
            MEM_CMD_FILL		= 3'b010,
            MEM_CMD_RDBURST		= 3'b011,
            MEM_CMD_WRBURST		= 3'b100,
            // Other command to come later...
            MEM_CMD_NONE		= 3'b000;

wire isFifoFullLSB, isFifoFullMSB,isFifoEmptyLSB, isFifoEmptyMSB;
wire isFifoFull;
wire isFifoEmpty;
wire isFifoNotEmpty;
wire rstInFIFO;

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
reg         [1:0] GPU_REG_DMADirection;
reg			[9:0] GPU_REG_DispAreaX;
reg			[8:0] GPU_REG_DispAreaY;
reg			[11:0] GPU_REG_RangeX0;
reg			[11:0] GPU_REG_RangeX1;
reg			[9:0] GPU_REG_RangeY0;
reg			[9:0] GPU_REG_RangeY1;
reg				  GPU_REG_ReverseFlag;
reg					GPU_DisplayEvenOddLinesInterlace;	// TODO
reg					GPU_REG_CurrentInterlaceField;		// TODO

reg [31:0] regGpuInfo;

wire rstGPU;
wire rstCmd;
wire readFifo;
wire saveLoadOnGoing;

reg [2:0]		memoryCommand;

// -2048..+2047
reg signed [11:0] RegX0;
reg signed [11:0] RegY0;
reg  [8:0] RegR0;
reg  [8:0] RegG0;
reg  [8:0] RegB0;
reg  [7:0] RegU0;
reg  [7:0] RegV0;
reg signed [11:0] RegX1;
reg signed [11:0] RegY1;
reg  [8:0] RegR1;
reg  [8:0] RegG1;
reg  [8:0] RegB1;
reg  [7:0] RegU1;
reg  [7:0] RegV1;
reg signed [11:0] RegX2;
reg signed [11:0] RegY2;
reg  [8:0] RegR2;
reg  [8:0] RegG2;
reg  [8:0] RegB2;
reg  [7:0] RegU2;
reg  [7:0] RegV2;
reg [15:0] RegCLUT;
// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
// reg  [9:0] RegTx;
reg [10:0] RegSizeW;
reg [ 9:0] RegSizeH;
reg [ 9:0] OriginalRegSizeH;

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
wire pausePipeline = writePixelOnNewBlock | missTC;	// Busy to write the BG/read BG/TEX$/CLUT$ memory access.
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
wire 			CLUTIs8BPP	= (GPU_REG_TexFormat == 2'b01);
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

reg signed [11:0] pixelX;
reg signed [11:0] nextPixelX; // Wire
reg signed [11:0] pixelY;
reg signed [11:0] nextPixelY; // Wire

wire pixelInFlight;

reg rstTextureCache;
reg storeCommand;
reg resetVertexCounter;
reg increaseVertexCounter;
reg loadRGB,loadUV,loadVertices,loadAllRGB;
reg loadE5Offsets;
reg loadTexPageE1;
reg loadTexWindowSetting;
reg loadDrawAreaTL;
reg loadDrawAreaBR;
reg loadMaskSetting;
reg setIRQ;
reg nextCondUseFIFO;
reg loadClutPage;
reg loadTexPage;
reg loadSize;
reg loadCoord1,loadCoord2;
reg loadRectEdge;
reg [1:0] loadSizeParam;
reg [4:0] issuePrimitive;

wire [4:0] issuePrimitiveReal;

/// issue_t issue;  FUCKING VERILATOR.


reg [7:0] RegCommand;
reg  FifoDataValid;

workState_t currWorkState,nextWorkState;


wire	isNegXAxis;
wire	isNegYAxis;

reg		resetXCounter;
wire	endVertical;

reg			changeX;
nextX_t selNextX;
nextY_t selNextY;
wire signed [11:0]	nextLineX;
wire signed [11:0]  nextLineY;
wire signed [11:0]	minTriDAX0;
wire signed [11:0]	maxTriDAX1;
wire signed [11:0]	minTriDAY0;
wire signed [11:0]	maxTriDAY1;

wire		doBlockWork;

// State machine for triangle
// State to control setup...
reg [2:0]		compoID;
reg				vecID;
reg				resetDir;
reg				switchDir;
reg				loadNext;
reg				setPixelFound;
reg				resetPixelFound;
reg				memorizeLineEqu;
reg IncY;

// reg				readStencil;
// reg	[1:0]		writeStencil2;
reg				assignRectSetup;
// Manage the adress of 16 pixel buffer cache for the BG (read/write) inside the Memory Manager
// Need to be outside because controlled by main state machine.
reg	[14:0]		PixelBGAdr;
reg				isLoaded; ///////////// TODO : MANAGE THAT TOMORROW ////////////////
reg				isWritten; // USE notMemoryBusyCurrCycle in state machine.
reg	[2:0]		setStencilMode;
reg 			writeStencil;
reg				copyCVMode;

wire        [13:0]  initialD;
wire signed [13:0]  nextD;

wire signed [EQUMSB:0] w0L;
wire signed [EQUMSB:0] w1L;
wire signed [EQUMSB:0] w2L;

wire signed [EQUMSB:0] w0R;
wire signed [EQUMSB:0] w1R;
wire signed [EQUMSB:0] w2R;

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

wire signed [11:0]	minXTri;
wire signed [11:0]	maxXTri;

wire				isV0,isV1,isV2;
wire 				isLineRightPix;
wire				isLineLeftPix;

wire				isCCWInsideL;
wire				isCWInsideL;
wire				isCCWInsideR;
wire				isCWInsideR;

wire				earlyTriangleReject;

wire				isValidPixelL,isValidPixelR;
wire				isBottomInsideBBox;
wire				requestNextPixel;

wire signed [11:0]	preB;
wire        		selectPixelWriteMaskLine;
wire				isRightPLXmaxTri;

wire				isLineInsideDrawArea;
wire				isInsideBBoxTriRectL;
wire				isInsideBBoxTriRectR;
// -- mike moved

wire  [5:0] adrXSrc;
wire  [5:0] adrXDst;

wire       performSwitch;
reg         cpyBank;
reg			resetBank, switchBank;
wire xCopyDirectionIncr;
wire [4:0] tmpidx;
wire [3:0] cpyIdx;
wire  [8:0]		scrDstY;
reg	 [ 6:0] counterXDst;


// ------------------ Debug Stuff --------------
reg [31:0] rdebugCnt;
always @(posedge clk)
begin
    if (i_nrst == 0) begin
        rdebugCnt = 32'd0;
    end else begin
        rdebugCnt = rdebugCnt + 32'd1;
    end
end
assign mydebugCnt =rdebugCnt;
// ---------------------------------------------

wire writeFifo		= !gpuAdrA2 & gpuSel & write;
wire writeGP1		=  gpuAdrA2 & gpuSel & write;
assign o_canWrite	= !isFifoFull;
always @(*)
begin
    cpuDataOut	  =  32'hFFFFFFFF; // Not necessary but to avoid bug for now.
    validDataOut = 0;
    if (gpuSel & read) begin
        // Register +4 Read
        if (gpuAdrA2) begin
            cpuDataOut	=  reg1Out;
        end else begin
            if (setStencilMode == 3'd7) begin
                // [TODO VRAM->CPU]
                validDataOut	= 1;
                cpuDataOut		= regGpuInfo;
            end else begin
                validDataOut	= 1;
                cpuDataOut		= regGpuInfo;
            end
        end
    end
end

assign IRQRequest = GPU_REG_IRQSet;

wire [31:0] fifoDataOut;
assign isFifoFull     = isFifoFullLSB  | isFifoFullMSB;
assign isFifoEmpty    = isFifoEmptyLSB & isFifoEmptyMSB;
assign isFifoNotEmpty = !isFifoEmpty;
assign rstInFIFO      = rstGPU | rstCmd;

wire readLFifo, readMFifo;
wire readFifoLSB	= readFifo | readLFifo;
wire readFifoMSB	= readFifo | readMFifo;

wire [55:0] memoryWriteCommand;



reg  [52:0] parameters;
assign memoryWriteCommand = { parameters, memoryCommand};
// assign memoryWriteCommand_o = memoryWriteCommand;
wire commandFIFOaccept = (1'b1 && !saveLoadOnGoing);  // TODO memory command FIFO acceptCommand to implement (well FIFO to implement)

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
    // CPU 2 VRAM : [16,16,2,15,...]
    MEM_CMD_PIXEL2VRAM:    parameters = 	{ { WRPixelL15 , LPixel[14:0] }									// [55:40] LEFT PIXEL
                                            , { WRPixelR15 , RPixel[14:0] }									// [39:24] RIGHT PIXEL !!!! (REVERSED CONVENTION !!!)
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
    default: parameters = 53'd0;
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

    .wr_data_i		(cpuDataIn[31:16]),
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

    .wr_data_i		(cpuDataIn[15:0]),
    .wr_en_i		(writeFifo),

    .rd_data_o		(fifoDataOut[15:0]),
    .rd_en_i		(readFifoLSB),

    .full_o			(isFifoFullLSB),
    .empty_o		(isFifoEmptyLSB)
);

// TODO GPU DMA Stuff
wire gpuReadyReceiveDMA, gpuReceiveCmdReady, dmaDataRequest;
reg  gpuReadySendToCPU;
assign gpuReceiveCmdReady	= !isFifoFull;
assign gpuReadyReceiveDMA	= !isFifoFull;

assign reg1Out = {
                    // Default : 1480.2.000h

                    // Default 1
                    GPU_DisplayEvenOddLinesInterlace,	// 31
                    GPU_REG_DMADirection,				// 29-30
                    gpuReadyReceiveDMA,					// 28

                    // default 4
                    gpuReadySendToCPU,				// 27
                    gpuReceiveCmdReady,				// 26
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

//                  13 bit signed  12 bit signed
// -1024..+1023 Input. + -1024..+1023 Offset => -2048..+2047 12 bit signed.
wire signed [11:0]	fifoDataOutY= { fifoDataOut[26],fifoDataOut[26:16] } + { GPU_REG_OFFSETY[10], GPU_REG_OFFSETY };
wire signed [11:0]	fifoDataOutX= { fifoDataOut[10],fifoDataOut[10: 0] } + { GPU_REG_OFFSETX[10], GPU_REG_OFFSETX };

wire [7:0]	fifoDataOutUR		= fifoDataOut[ 7: 0]; // Same cut for R and U coordinate.
wire [7:0]	fifoDataOutVG		= fifoDataOut[15: 8]; // Same cut for G and V coordinate.
wire [7:0]	fifoDataOutB		= fifoDataOut[23:16];
wire [14:0] fifoDataOutClut		= fifoDataOut[30:16];
// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
//wire [9:0]	fifoDataOutTex		= {fifoDataOut[27],fifoDataOut[24:16]};
wire [9:0]  fifoDataOutWidth	= fifoDataOut[ 9: 0];
//wire [10:0] fifoDataOutW		= fifoDataOut[10: 0]; NOT USED.
wire [8:0]  fifoDataOutHeight	= fifoDataOut[24:16];
//wire [ 9:0] fifoDataOutH    	= fifoDataOut[25:16]; NOT USED.

wire [7:0] command			= /*issue.*/storeCommand ? fifoDataOut[31:24] : RegCommand;

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
wire		is8BitTex		= ((/*issue.*/loadTexPage ? fifoDataOut[24:23] : fifoDataOut[8:7]) == 2'd1);
wire [4:0]	nextClutPacket	= rClutPacketCount + 5'h1F;

always @(posedge clk)
begin
    if (getGPUInfo) begin
        regGpuInfo = gpuInfoMux;
    end

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
        GPU_REG_CurrentInterlaceField <= 1; // Odd field by default (bit 14 = 1 on reset)
        GPU_REG_IRQSet				<= 0;
        GPU_REG_DisplayDisabled		<= 1;
        GPU_REG_DMADirection		<= 2'b00; // Off
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
        RegCLUT						= 16'h8000;	// Invalid CLUT ADR on reset.
        rClutLoading				= 1'b0;
        rClutPacketCount			= 5'd0;
        rPalette4Bit				= 1'b0;

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
            rClutPacketCount		= { is8BitTex , 3'b0, !is8BitTex }; // Load 1 packet or 16
            GPU_REG_TextureDisable	<= /*issue.*/loadTexPage ? fifoDataOut[27]    : fifoDataOut[11];
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
            rClutPacketCount = nextClutPacket; // Decrement -1.
        end

        if (/*issue.*/loadClutPage) begin
            if (newClutValue[15] == 1'b0 && (newClutValue != RegCLUT)) begin
                // Loading only happens when :
                // - Switch from invalid to valid CLUT ADR. (Reset or cache flush)
                // - Switch from valid   do difference valid CLUT ADR.
                //
                // WARNING : rClutPacketCount the number of PACKET TO LOAD IS UPDATED WHEN LOADING THE TEXTURE FORMAT !!!! NOT WHEN CLUT FLAT IS SET !!!!
                //
                rClutLoading	= 1'b1;
            end
            // Load always the value, whatever the value is (valid or invalid)
            RegCLUT		= newClutValue;
        end

        if (endClutLoading) begin
            rClutLoading	= 1'b0;
            rPalette4Bit	= (GPU_REG_TexFormat == PIX_4BIT);
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
            GPU_REG_DMADirection		<= cpuDataIn[1:0];
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
            GPU_REG_VerticalResolution	<= cpuDataIn[2] & cpuDataIn[5];
            GPU_REG_HorizResolution		<= cpuDataIn[1:0];
            GPU_REG_HorizResolution368	<= cpuDataIn[6];
            GPU_REG_ReverseFlag			<= cpuDataIn[7];
        end
    end

    //if (rstGPU) begin
        //RegCommand <= '0;
    //end else begin
        if (/*issue.*/storeCommand) RegCommand <= command;
    //end
    FifoDataValid <= readFifo;
end

// [Command Type]
wire bIsBase0x				= (command[7:5]==3'b000);
wire bIsBase01			= (command[4:0]==5'd1  );
wire bIsBase02			= (command[4:0]==5'd2  );
wire bIsBase1F			= (command[4:0]==5'd31 );

wire bIsPolyCommand			= (command[7:5]==3'b001);
wire bIsRectCommand			= (command[7:5]==3'b011);
wire bIsLineCommand			= (command[7:5]==3'b010);
wire bIsMultiLine   		= command[3] & bIsLineCommand;
wire bIsForECommand			= (command[7:5]==3'b111);
wire bIsCopyVVCommand		= (command[7:5]==3'b100);
wire bIsCopyCVCommand		= (command[7:5]==3'b101);
wire bIsCopyVCCommand		= (command[7:5]==3'b110);
wire bIsFillCommand			= bIsBase0x & bIsBase02;

// End line command if special marker or SECOND vertex when not a multiline command...
wire bIsTerminator			= (fifoDataOut[31:28] == 4'd5) & (fifoDataOut[15:12] == 4'd5);
wire bIsMultiLineTerminator = (bIsLineCommand & bIsMultiLine & bIsTerminator);

// [All attribute of commands]
wire bIsRenderAttrib		= (bIsForECommand & (!command[4]) & (!command[3])) & (command[2:0]!=3'b000) & (command[2:0]!=3'b111); // E*, range 0..7 -> Select E1..E6 Only
wire bIsNop         		= (bIsBase0x & (!(bIsBase01 | bIsBase02 | bIsBase1F)))	// Reject 01,02,1F
                            | (bIsForECommand & (!bIsRenderAttrib));				// Reject E1~E6
wire bIsPolyOrRect  		= (bIsPolyCommand | bIsRectCommand);

// Line are not textured
wire bUseTexture    		= bIsPolyOrRect & command[2] & (!GPU_REG_TextureDisable); 										// Avoid texture fetching if we do LINE, Compute proper color for FILL.
wire bIgnoreColor   		= bUseTexture   & command[0];
wire bSemiTransp    		= command[1];
wire bIs4PointPoly  		= command[3] & bIsPolyCommand;
wire bIsPerVtxCol   		= (bIsPolyCommand | bIsLineCommand) & command[4];

// - Rectangle never dither. ( => bIsPerVtxCol is FALSE)
// - Line      dither if set (even for unique color)
// - Triangle  dither if gouraud is set (textured or not) = bIsPerVtxCol
wire bDither				= GPU_REG_DitherOn & (bIsPerVtxCol | bIsLineCommand);
wire bOpaque        		= !bSemiTransp;

// TODO : Rejection occurs with DX / DY. Not range. wire rejectVertex			= (fifoDataOutX[11] != fifoDataOutX[10]) | (fifoDataOutY[11] != fifoDataOutY[10]); // Primitive with offset out of range -1024..+1023
wire resetReject			= 0/*[TODO] Why ?*/;
wire rejectVertex			= 0;

reg  rejectPrimitive;
always @(posedge clk)
begin
    if (rejectVertex | resetReject) begin
        rejectPrimitive = !resetReject;
    end
end

always @(posedge clk)
begin
    if (/*issue.*/resetVertexCounter /* | rstGPU | rstCmd : Done by STATE RESET. */) begin
        vertCnt			= 2'b00;
        isFirstVertex	= 1;
    end else begin
        vertCnt = vertCnt + /*issue.*/increaseVertexCounter;
        if (/*issue.*/increaseVertexCounter) begin
            isFirstVertex	= 0;
        end
    end
end

wire isPolyFinalVertex	= ((bIs4PointPoly & (vertCnt == 2'd3)) | (!bIs4PointPoly & (vertCnt == 2'd2)));
wire canEmitTriangle	= (vertCnt >= 2'd2);	// 2 or 3 for any tri or quad primitive. intermediate or final.
wire bNotFirstVert		= !isFirstVertex;		// Can NOT use counter == 0. Won't work in MULTILINE. (0/1/2/0/1/2/....)

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
end

wire [3:0] rightPos = RegX0[3:0] + RegSizeW[3:0];
wire [3:0] sxe16	= rightPos + 4'b1111;

always @(*)
begin
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
    counterXSrc = (resetXCounter) ? 7'd0 : counterXSrc + { 6'd0 ,incrementXCounter & (!useDest) };
    counterXDst = (resetXCounter) ? 7'd0 : counterXDst + { 6'd0 ,incrementXCounter &   useDest  };
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


reg dir;
reg memW0,memW1,memW2;

wire 				extIX		= dir & changeX;
always @(*)
begin
    case (selNextX)
        X_TRI_NEXT:		nextPixelX	= pixelX + { {10{extIX}}, changeX, 1'b0 };	// -2,0,+2
        X_LINE_START:	nextPixelX	= RegX0;
        X_LINE_NEXT:	nextPixelX	= nextLineX; // Optimize and merge with case 0
        X_TRI_BBLEFT:	nextPixelX	= { minTriDAX0[11:1], 1'b0 };
        X_TRI_BBRIGHT:	nextPixelX	= { maxTriDAX1[11:1], 1'b0 };
        X_CV_START:		nextPixelX	= { 2'b0, RegX0[9:1], 1'b0 };
        default:		nextPixelX	= pixelX;
    endcase

    case (selNextY)
        Y_LINE_START:	nextPixelY	= RegY0;
        Y_LINE_NEXT:	nextPixelY	= nextLineY;
        Y_TRI_START:	nextPixelY	= minTriDAY0;
        Y_TRI_NEXT:		nextPixelY	= pixelY + { 10'b0      , 1'b1 }; // +1
        Y_TRI_PREV:		nextPixelY	= pixelY + { 11'b1111_1111_111 }; // -1
        Y_CV_ZERO:		nextPixelY	= 12'd0;
        default:		nextPixelY	= pixelY;
    endcase
end


wire storeStencilRead = (memoryCommand == MEM_CMD_RDBURST);
reg [31:0]	stencilReadCache;
reg [31:0]  maskReadCache;

reg pixelFound;
reg enteredTriangle; reg setEnteredTriangle, resetEnteredTriangle;


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
        prevVRAMAdrBlock = currVRAMAdrBlock;
    end

    // Give priority to SET over RESET, and ONLY when we write an EFFECTIVE PIXEL.
    if (setFirstPixel) begin
        flagIsNewBlock = IS_NEW_BLOCK_IN_PRIMITIVE;
    end else begin
        // [Inside the primitive, each time we emit a pixel]
        if (doBlockWork) begin
            if (flagIsNewBlock == IS_NEW_BLOCK_IN_PRIMITIVE) begin
                flagIsNewBlock = IS_OTHER_BLOCK_IN_PRIMITIVE;
            end
        end
    end
end
// -----------------------------------------------------------------------

reg  signed [13:0]  DLine;

always @(posedge clk)
begin
    if (loadNext) begin
        pixelX = nextPixelX;
        pixelY = nextPixelY;
    end
    if (resetDir) begin
        dir    = 0; // Left to Right
    end else begin
        if (switchDir) begin
            dir = !dir;
        end
    end

    if (currWorkState == LINE_START) begin
        DLine = initialD;
    end else begin
        if (loadNext) begin
            DLine = nextD;
        end
    end

    if (resetPixelFound) begin
        pixelFound = 0; // No pixel found.
    end
    if (setPixelFound) begin
        pixelFound = 1;
    end
    if (resetEnteredTriangle) begin
        enteredTriangle = 0;
    end
    if (setEnteredTriangle) begin
        enteredTriangle = 1;
    end
    if (memorizeLineEqu) begin
        // Backup the edge result for FIST PIXEL INSIDE BBOX.
        memW0 = minTriDAX0[0] ? w0R[EQUMSB] : w0L[EQUMSB];
        memW1 = minTriDAX0[0] ? w1R[EQUMSB] : w1L[EQUMSB];
        memW2 = minTriDAX0[0] ? w2R[EQUMSB] : w2L[EQUMSB];
    end

    // BEFORE cpyBank UPDATE !!!
    if (storeStencilRead) begin
        if (cpyBank) begin
            stencilReadCache[31:16] = stencilReadValue16;
            maskReadCache	[31:16] = maskSegmentRead;
            if (clearOtherBank) begin
                maskReadCache	[15:0] = 16'd0;
            end
        end else begin
            stencilReadCache[15: 0] = stencilReadValue16;
            maskReadCache	[15: 0] = maskSegmentRead;
            if (clearOtherBank) begin
                maskReadCache	[31:16] = 16'd0;
            end
        end
    end

    if (clearBank0) begin // storeStencilRead is always False, no priority issues.
        maskReadCache	[15: 0] = 16'd0;
    end

    if (clearBank1) begin // storeStencilRead is always False, no priority issues.
        maskReadCache	[31:16] = 16'd0;
    end

    // AFTER cpyBank is used !!!!
    if (resetBank) begin
        cpyBank = 1'b0;
    end else begin
        cpyBank = cpyBank ^ switchBank;
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

wire tstRightEqu0 = maxTriDAX1[0] ? w0R[EQUMSB] : w0L[EQUMSB];
wire tstRightEqu1 = maxTriDAX1[0] ? w1R[EQUMSB] : w1L[EQUMSB];
wire tstRightEqu2 = maxTriDAX1[0] ? w2R[EQUMSB] : w2L[EQUMSB];

state_t currState,nextLogicalState;
state_t nextState;

always @(posedge clk)
begin
    if (rstGPU | rstCmd) begin
        currState 		<= DEFAULT_STATE;
        currWorkState	<= NOT_WORKING_DEFAULT_STATE;
    end else begin
        currState		<= nextState;
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

assign srcDstY	= pixelY[8:0] + RegY1[8:0];
wire  [9:0]  nextScrY	= nextPixelY[9:0] + RegY0[9:0];
wire [11:0]	nextX		= pixelX + { 12'd2 };
wire [ 9:0]	nextY		= pixelY[9:0] + { 10'd1 };
wire		WidthNot1	= |RegSizeW[10:1];
assign		endVertical	= (nextY == RegSizeH);
assign			scrY	= pixelY[9:0] + RegY0[9:0];

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
        lastPair = 1'b1;
    end
    if (resetLastPair) begin
        lastPair = 1'b0;
    end
    if (setSwap) begin
        swap = RegX0[0];
    end else begin
        swap = swap ^ changeSwap;
    end
    if (readL | readM) begin
        regSaveM = readM;
        regSaveL = readL;
    end
    if (setStencilMode!=3'd0) begin
        stencilMode = setStencilMode;
    end
end
wire isNewBlockPixel;

assign readLFifo = readL;
assign readMFifo = readM;


// --------------------------------------------------------------------------------------------
//   [END] CPU TO VRAM STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

reg				stencilReadSigW; // USED ONLY WHEN READING THE STENCIL ON TARGET BEFORE A WRITE LATER.

wire 			reachEdgeTriScan = (((pixelX > maxXTri) & !dir) || ((pixelX < minXTri) & dir));

wire allowNextRead = (!isLastSegment) | isLongLine;
wire isPalettePrimitive = (!GPU_REG_TexFormat[1]) & bUseTexture;
wire validCLUTLoad = rClutLoading & isPalettePrimitive; // Format is 0 or 1 and clut load is required.
wire updateClutCacheComplete;
reg  requClutCacheUpdate;

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
    selNextX					= X_ASIS;
    selNextY					= Y_ASIS;
    switchDir					= 0;
    resetDir					= 0;
    compoID						= 0;
    vecID						= 0;
    writePixelL					= 0;
    writePixelR					= 0;
//	readStencil					= 0;
//	writeStencil2				= 2'b00;
    changeX						= 0;
    assignRectSetup				= 0;
    setEnteredTriangle			= 0;
    resetEnteredTriangle		= 0;
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

    case (currWorkState)
    NOT_WORKING_DEFAULT_STATE:
    begin
        setFirstPixel			= 1;
        assignRectSetup			= !bIsPerVtxCol;
        resetEnteredTriangle	= 1;	// Put here, no worries about more specific cases.
        case (/*issue.*/issuePrimitive)
        ISSUE_TRIANGLE:
        begin
            setStencilMode		= 3'd1;
            if (bIsPerVtxCol) begin
                nextWorkState = SETUP_RX;
            end else begin
                nextWorkState = (bUseTexture) ? SETUP_UX : TRIANGLE_START;
            end
        end
        ISSUE_RECT:
        begin
            setStencilMode		= 3'd1;
            assignRectSetup	= 1;
            nextWorkState	= validCLUTLoad ? WAIT_3 : RECT_START;
        end
        ISSUE_LINE:
        begin
            setStencilMode		= 3'd1;
            if (bIsPerVtxCol) begin
                nextWorkState = SETUP_RX;
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
        resetDir		= 1;
        copyCVMode		= 1;
        // Reset last pair by default, but if WIDTH == 1 -> different.
        resetLastPair	= WidthNot1;
        setLastPair		= !WidthNot1;
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
        if (commandFIFOaccept & canRead) begin
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
                resetLastPair	= WidthNot1;
            end else begin
                // [MIDDLE OR FIRST SEGMENT]
                //    PRELOAD NEXT SEGMENT...
                if (nextPixelX == XE) begin
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
                changeX		= 1;
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
        nextWorkState = TMP_2;

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
        // Detect edge transition... waiting for data received...
        // Data already present -> Read from both buffer possible.
        // Set gpuReadySendToCPU
    end
    // --------------------------------------------------------------------
    //   TRIANGLE STATE MACHINE
    // --------------------------------------------------------------------
    SETUP_RX:
    begin
        compoID	= 3'd1;	vecID = 1'b0;
        nextWorkState = SETUP_RY;
    end
    SETUP_RY:
    begin
        compoID	= 3'd1;	vecID = 1'b1;
        nextWorkState = SETUP_GX;
    end
    SETUP_GX:
    begin
        compoID	= 3'd2;	vecID = 1'b0;
        nextWorkState = SETUP_GY;
    end
    SETUP_GY:
    begin
        compoID	= 3'd2;	vecID = 1'b1;
        nextWorkState = SETUP_BX;
    end
    SETUP_BX:
    begin
        compoID	= 3'd3;	vecID = 1'b0;
        nextWorkState = SETUP_BY;
    end
    SETUP_BY:
    begin
        compoID	= 3'd3;	vecID = 1'b1;
        if (bUseTexture) begin
            nextWorkState = SETUP_UX;
        end else begin
            // Wait 6 cycle now...
            nextWorkState = WAIT_3;
        end
    end
    SETUP_UX:
    begin
        compoID	= 3'd4;	vecID = 1'b0;
        nextWorkState = SETUP_UY;
    end
    SETUP_UY:
    begin
        compoID	= 3'd4;	vecID = 1'b1;
        nextWorkState = SETUP_VX;
    end
    SETUP_VX:
    begin
        compoID	= 3'd5;	vecID = 1'b0;
        nextWorkState = SETUP_VY;
    end
    SETUP_VY:
    begin
        compoID	= 3'd5;	vecID = 1'b1;
        nextWorkState = WAIT_3;
    end
    WAIT_3: // 4 cycles to wait
    begin
        // Palette change and palette type
        // Or palette unchanged but from 4 bit to 8 bit.
        if (validCLUTLoad || (isPalettePrimitive & rPalette4Bit & (GPU_REG_TexFormat == PIX_8BIT))) begin
            // Not using signal updateClutCacheComplete but could... rely on transaction only.
            if (saveLoadOnGoing == 0) begin // Wait for an on going memory transaction to complete.
                if (rClutPacketCount != 5'd0) begin
                    // And request ours.
                    requClutCacheUpdate = 1;
                    decClutCount		= 1;
                    nextWorkState		= WAIT_3;
                end else begin
                    nextWorkState		= WAIT_2;
                end
            end else begin
                // Just do nothing
                nextWorkState = WAIT_3;
            end
        end else begin
            nextWorkState = WAIT_2;
        end
    end
    WAIT_2: // 3 cycles to wait
    begin
        endClutLoading	= isPalettePrimitive;	// Reset flag, even if it was already reset. Force 0.
                                                // Force also to cache the current primitive pixel format (was it 4 bpp ?)
        nextWorkState	= WAIT_1;
    end
    WAIT_1: // 2 cycles to wait
    begin
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
        resetDir = 1; // dir = LEFT2RIGHT -> X=X+1 when changeX = 1, else X=X-1 when changeX = 1.
        if (earlyTriangleReject) begin	// Bounding box and draw area do not intersect at all.
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
        if ((memW0 == tstRightEqu0) && (memW1 == tstRightEqu1) && (memW2 == tstRightEqu2) 	// Check that TRIANGLE EDGE did not SWITCH between the LEFT and RIGHT side of the bounding box.
         && ((!maxTriDAX1[0] && !isValidPixelL) || (maxTriDAX1[0] && !isValidPixelR)))		// And that we are OUTSIDE OF THE TRIANGLE. (if odd/even pixel, select proper L/R validpixel.) (Could be also a clipped triangle with FULL LINE)
        begin
            selNextY		= Y_TRI_NEXT;
            nextWorkState	= START_LINE_TEST_LEFT;
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
                setEnteredTriangle = 1;

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
                    changeX		= 1;
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
                        changeX			= 1;
                        selNextX		= X_TRI_NEXT;
                        selNextY		= reachEdgeTriScan ? Y_TRI_NEXT : Y_ASIS;
                        // Trick : Due to FILL CONVENTION, we can reach a line WITHOUT A SINGLE PIXEL !
                        // -> Need to detect that we scan too far and met nobody and avoid out of bound search.
                        nextWorkState	= reachEdgeTriScan ? (enteredTriangle ? FLUSH_COMPLETE_STATE : SCAN_LINE_CATCH_END) : SCAN_LINE;
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
            changeX			= 1;
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
        if (earlyTriangleReject | isNegXAxis | preB[11]) begin // VALID FOR RECT TOO : Bounding box and draw area do not intersect at all, or NegativeSize => size = 0.
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
                // TODO Pixel writing logic
                // TODO Mask -> If both invalid, force next pair, without write.
                if (requestNextPixel) begin
                    // Write only if pixel pair is valid...
                    writePixelL   = isInsideBBoxTriRectL & ((GPU_REG_CheckMaskBit && (!stencilReadValue[0])) || (!GPU_REG_CheckMaskBit));
                    writePixelR   = isInsideBBoxTriRectR & ((GPU_REG_CheckMaskBit && (!stencilReadValue[1])) || (!GPU_REG_CheckMaskBit));

                    // Go to next pair whatever, as long as request is asking for new pair...
                    // normally changeX = 1; selNextX = X_TRI_NEXT;  [!!! HERE !!!]
                    changeX		= 1;
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
            if (isLineInsideDrawArea && ((GPU_REG_CheckMaskBit && (!selectPixelWriteMaskLine)) || (!GPU_REG_CheckMaskBit))) begin	// Clipping DrawArea, TODO: Check if masking apply too.
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

always @(*)
begin
    // Read FIFO when fifo is NOT empty or that we can decode the next item in the FIFO.
    // TODO : Assume that FIFO always output the same value as the last read, even if read signal is FALSE ! Simplify state machine a LOT.

    // NOT SUPPORTED WELL --->>>> issue = 0/*'{default:1'b0}*/;
    storeCommand  	= 0;
    loadRGB         = 0;
    loadAllRGB      = 0;
    setIRQ			= 0;
    rstTextureCache	= 0;
    loadE5Offsets		    = 0;
    loadTexPageE1		    = 0;
    loadTexWindowSetting  	= 0;
    loadDrawAreaTL			= 0;
    loadDrawAreaBR			= 0;
    loadMaskSetting			= 0;
    resetVertexCounter		= 0;
    increaseVertexCounter	= 0;
    loadUV					= 0;
    loadVertices			= 0;
    loadClutPage			= 0;
    loadTexPage				= 0;
    loadSize				= 0;
    loadCoord1				= 0;
    loadCoord2				= 0;
    loadRectEdge			= 0;
    loadSizeParam			= 2'd0;
    issuePrimitive			= 5'd0;

    nextCondUseFIFO			= 0;
    nextLogicalState		= DEFAULT_STATE;

    case (currState)
    DEFAULT_STATE:
    begin
        /*issue.*/resetVertexCounter = 1;
        nextCondUseFIFO			= 1;
        nextLogicalState		= LOAD_COMMAND; // Need FIFO
    end
    // Step 0A
    LOAD_COMMAND:				// Here we do NOT check data validity : if we arrive in this state, we know the data is available from the FIFO, and GPU accepts commands.
    begin
        /*issue.*/storeCommand  	= 1;
        /*issue.*/loadRGB           = 1; // Work for all command, just ignored.
        /*issue.*/loadAllRGB        = (bIgnoreColor) ? 1'b1 : (!bIsPerVtxCol);
        /*issue.*/setIRQ			= bIsBase0x & bIsBase1F;
        /*issue.*/rstTextureCache	= bIsBase0x & bIsBase01;
        /*issue.*/loadClutPage		= bIsBase0x & bIsBase01; // Reset CLUT adr, using rstTextureCache for MSB -> Invalid adr.

         // TODO : Can optimize later by using LOAD_COMMAND instead and loop...
         // For now any command reading is MINIMUM EVERY 2 CYCLES.
        // E1~E6
        if (bIsRenderAttrib) begin
            nextLogicalState	= DEFAULT_STATE;
            nextCondUseFIFO		= 0;

            /*issue.*/loadE5Offsets		    = (command[2:0] == 3'd5);
            /*issue.*/loadTexPageE1		    = (command[2:0] == 3'd1);
            /*issue.*/loadTexWindowSetting  = (command[2:0] == 3'd2);
            /*issue.*/loadDrawAreaTL		= (command[2:0] == 3'd3);
            /*issue.*/loadDrawAreaBR		= (command[2:0] == 3'd4);
            /*issue.*/loadMaskSetting		= (command[2:0] == 3'd6);
        end else begin
            // [02/8x~9X/Ax~Bx/Cx~Dx]
            if (bIsCopyVVCommand | bIsCopyCVCommand | bIsCopyVCCommand | bIsFillCommand) begin
                nextLogicalState	= LOAD_XY1;
                nextCondUseFIFO		= 1;
            end else begin
                 // Case E0/E7/E8~EF
                 // Case 00/03~1E/01 Handled.
                if (bIsNop | bIsBase0x) begin
                    nextLogicalState	= DEFAULT_STATE;
                    nextCondUseFIFO		= 0;
                end else begin
                // 2x/3x/4x/5x/6x/7x
                    nextLogicalState	= VERTEX_LOAD;
                    nextCondUseFIFO		= 1;
                end
            end
        end
    end
    LOAD_XY1:
    begin
        /*issue.*/loadCoord1 = 1; /*issue.*/loadCoord2	= 0;
        // bIsCopyVVCommand		Top Left Corner   (YyyyXxxxh) then WIDTH_HEIGHT_STATE
        // bIsCopyCVCommand		Source Coord      (YyyyXxxxh) then LOAD_X2
        // bIsCopyVCCommand		Destination Coord (YyyyXxxxh) then WIDTH_HEIGHT_STATE
        // bIsFillCommand		Top Left Corner   (YyyyXxxxh) then WIDTH_HEIGHT_STATE
        nextCondUseFIFO			= 1;
        nextLogicalState		= bIsCopyVVCommand ? LOAD_XY2 :  WIDTH_HEIGHT_STATE;
    end
    LOAD_XY2:
    begin
        /*issue.*/loadCoord1 = 0; /*issue.*/loadCoord2	= 1;
        nextCondUseFIFO			= 1;
        nextLogicalState		= WIDTH_HEIGHT_STATE;
    end
    // Step 0B
    COLOR_LOAD:
    begin
        //
        /*issue.*/loadRGB           = canIssueWork; // Reach the COLOR_LOAD state while a primitive is rendering... Forbid to LOAD COLOR.
        // Special case to test TERMINATOR (comes instead of COLOR value !!!)
        nextCondUseFIFO			= !(bIsLineCommand & bIsMultiLine & bIsTerminator);
        nextLogicalState		=  (bIsLineCommand & bIsMultiLine & bIsTerminator) ? DEFAULT_STATE : VERTEX_LOAD;
    end
    COLOR_LOAD_GARAGE:
    begin
        // Special case to test TERMINATOR (comes instead of COLOR value !!!)
        nextCondUseFIFO			= canIssueWork;
        nextLogicalState		= canIssueWork ? COLOR_LOAD : COLOR_LOAD_GARAGE;
    end
    VERTEX_LOAD_GARAGE:
    begin
        // Special case to test TERMINATOR (comes instead of COLOR value !!!)
        nextCondUseFIFO			= canIssueWork;
        nextLogicalState		= canIssueWork ? VERTEX_LOAD : VERTEX_LOAD_GARAGE;
    end
    // Step 1
    VERTEX_LOAD:
    begin
        if (bIsRectCommand) begin
            // Command original 27-28 Rect Size   (0=Var, 1=1x1, 2=8x8, 3=16x16) (Rectangle only)
            if (command[4:3]==2'd0) begin
                nextCondUseFIFO		= 1;
                nextLogicalState	= (bUseTexture) ? UV_LOAD : WIDTH_HEIGHT_STATE;
            end else begin
                if (bUseTexture) begin
                    nextCondUseFIFO		= 1;
                    nextLogicalState	= UV_LOAD;
                end else begin
                    nextCondUseFIFO		= 0;
                    /*issue.*/loadSize      = 1; /*issue.*/loadSizeParam = command[4:3];
                    nextLogicalState	= WAIT_COMMAND_COMPLETE;
                    /*issue.*/issuePrimitive		= ISSUE_RECT;
                end
            end
        end else begin
            if (bUseTexture) begin
                // Condition with 'FifoDataValid' necessary :
                // => If not done, state machine skip the 4th vertex loading to load directly 4th texture without loading the coordinates. (fifo not valid as we waited for primitive to complete)
                nextCondUseFIFO		= 1;
                nextLogicalState	= FifoDataValid ? UV_LOAD : VERTEX_LOAD;
            end else begin
                // End command if it is a terminator line or 2 vertex line only
                // Or a 4 point polygon or 3 point polygon.

                // MUST check 'canIssueWork' because the following test check ONLY THE VERTEX COUNTERS related.
                // and when entering the first emitted primitive, counter increments and VALIDATE the state change
                // WHILE the command is still working... So we miss emitting the SECOND TRIANGLE OR MULTILINES remaining.
                if ( canIssueWork & FifoDataValid &
                            ((bIsLineCommand & ((bIsMultiLine & bIsTerminator)|(!bIsMultiLine & (vertCnt == 2'd1))))	// Polyline with FINAL VERTEX or Line with second vertex.
                            |(bIsPolyCommand & isPolyFinalVertex))
                    ) begin
                    nextCondUseFIFO		= 0;	// Instead of FIFO state, it uses
                    nextLogicalState	= WAIT_COMMAND_COMPLETE;  // For now, no optimization of the state machine, FIFO data or not : DEFAULT_STATE.
                    if (bIsPolyCommand) begin // Sure Polygon command
                        // Issue a triangle primitive.
                        /*issue.*/issuePrimitive	= ISSUE_TRIANGLE;
                    end else begin
                        // Line/Polyline
                        // If 5xxx5xxx do not issue a LINE.
                        /*issue.*/issuePrimitive	= (bIsMultiLine & bIsTerminator) ? NO_ISSUE : ISSUE_LINE;
                    end
                end else begin
                    // No need to check for canIssueWork because we emit the FIRST TRIANGLE in this case, so we know that the canIssueWork = 1.

                    // Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
                    // Can not issue if data is not valid.
                    if (canIssueWork) begin
                        if (FifoDataValid & bIsPolyCommand & canEmitTriangle) begin
                            /*issue.*/issuePrimitive		= ISSUE_TRIANGLE;
                        end else begin
                            if (FifoDataValid & bIsLineCommand & bIsMultiLine & bNotFirstVert) begin // Remain the case of intermediate line ONLY (single 2 vertex line handled in upper logic)
                                /*issue.*/issuePrimitive	= ISSUE_LINE;
                            end
                        end
                    end

                    //
                    // The logic of this state machine is that when we reach the current state it is a VALID state.
                    // The problem we fix here is that multiple primitive command (Quad, Multiline) emit a rendering command and we reach the NEXT command parameter and executed it.
                    // As a result, next vertex/color can override the primitive we are just trying to draw...
                    // [This logic is also in the UV_LOAD]
                    //
                    nextCondUseFIFO		= (/*issue.*/issuePrimitive == NO_ISSUE); //	TODO ??? OLD COMMENT Fix, proposed multiline support ((issuePrimitive == NO_ISSUE) | !bIsLineCommand); // 1 before line, !bIsLineCommand is a hack. Because...
                    if (/*issue.*/issuePrimitive != NO_ISSUE) begin
                        nextLogicalState	= (FifoDataValid & bIsPerVtxCol) ? COLOR_LOAD_GARAGE : VERTEX_LOAD_GARAGE; // Next Vertex or stay current vertex until loaded.
                    end else begin
                        nextLogicalState	= (FifoDataValid & bIsPerVtxCol) ? COLOR_LOAD : VERTEX_LOAD; // Next Vertex or stay current vertex until loaded.
                    end
                end
            end
        end

        //
        // TRICKY DETAIL : When emitting multiple primitive, load the next vertex ONLY WHEN THE EMITTED COMMAND IS COMPLETED.
        //                 So we check (issuePrimitive == NO_ISSUE) when requesting next vertex.
        /*issue.*/increaseVertexCounter	= FifoDataValid & (!bUseTexture);	// go to next vertex if do not need UVs, don't care if invalid vertex... cause no issues. PUSH NEW VERTEX ONLY IF NOT BUSY RENDERING.
        /*issue.*/loadVertices			= (!bIsMultiLineTerminator); // Check if not TERMINATOR + line + multiline, else vertices are valid.
        /*issue.*/loadRectEdge			= bIsRectCommand;	// Force to load, dont care, override by UV if set with UV or SIZE if variable.
    end
    UV_LOAD:
    begin
        //

        /*issue.*/increaseVertexCounter	= FifoDataValid & canIssueWork & (!bIsRectCommand);	// Increase vertex counter only when in POLY MODE (LINE never reach here, RECT is the only other)
        /*issue.*/loadUV				= canIssueWork;
        /*issue.*/loadClutPage			= FifoDataValid & isV0 & (!isPolyFinalVertex); // First entry is Clut info, avoid reset when quad.
        /*issue.*/loadTexPage			= isV1; // second entry is TexPage.
        /*issue.*/loadRectEdge			= bIsRectCommand;

        // do not issue primitive if Rectangle or 1st/2nd vertex UV.

        if (bIsRectCommand) begin
            // 27-28 Rect Size   (0=Var, 1=1x1, 2=8x8, 3=16x16) (Rectangle only)
            /*issue.*/loadSizeParam			= command[4:3]; // Optimization, same as commented version.
            /*issue.*/issuePrimitive			= (command[4:3]!=2'd0) ? ISSUE_RECT : NO_ISSUE;
            if (command[4:3]==2'd0) begin
                nextCondUseFIFO		= 1;
                nextLogicalState	= WIDTH_HEIGHT_STATE;
            end else begin
                /*issue.*/loadSize			= 1; // loadSizeParam	<= command[4:3];
                nextCondUseFIFO		= 0;
                nextLogicalState	= WAIT_COMMAND_COMPLETE;
            end
        end else begin
            // Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
            // Can not issue if data is not valid.
            if (FifoDataValid & bIsPolyCommand & canEmitTriangle & canIssueWork) begin
                /*issue.*/issuePrimitive	= ISSUE_TRIANGLE;
            end

            if (isPolyFinalVertex) begin // Is it the final vertex of the command ? (3rd / 4th depending on command)
                // Allow to complete UV LOAD of last vertex and go to COMPLETE
                // only if we can push the triangle and that the incoming FIFO data is valid.
                nextCondUseFIFO		= !(canIssueWork & FifoDataValid);	// Instead of FIFO state, it uses
                nextLogicalState	=  (canIssueWork & FifoDataValid) ? WAIT_COMMAND_COMPLETE : UV_LOAD;	// For now, no optimization of the state machine, FIFO data or not : DEFAULT_STATE.
            end else begin

                //
                // The logic of this state machine is that when we reach the current state it is a VALID state.
                // The problem we fix here is that multiple primitive command (Quad, Multiline) emit a rendering command and we reach the NEXT command parameter and executed it.
                // As a result, next vertex/color can override the primitive we are just trying to draw...
                // [This logic is also in the UV_LOAD]
                //
                nextCondUseFIFO		= (/*issue.*/issuePrimitive == NO_ISSUE); //	TODO ??? OLD COMMENT Fix, proposed multiline support ((issuePrimitive == NO_ISSUE) | !bIsLineCommand); // 1 before line, !bIsLineCommand is a hack. Because...
                if (/*issue.*/issuePrimitive != NO_ISSUE) begin
                    nextLogicalState	= (FifoDataValid & bIsPerVtxCol) ? COLOR_LOAD_GARAGE : VERTEX_LOAD_GARAGE; // Next Vertex or stay current vertex until loaded.
                end else begin
                    nextLogicalState	= (FifoDataValid & bIsPerVtxCol) ? COLOR_LOAD : VERTEX_LOAD; // Next Vertex or stay current vertex until loaded.
                end

                if (bIsPerVtxCol) begin
                    if (/*issue.*/issuePrimitive != NO_ISSUE) begin
                        nextCondUseFIFO		= 0;
                        nextLogicalState	= COLOR_LOAD_GARAGE; // Next Vertex or stay current vertex until loaded.
                    end else begin
                        nextCondUseFIFO		= 1;
                        nextLogicalState	= FifoDataValid ? COLOR_LOAD : UV_LOAD; // Next Vertex or stay current vertex until loaded.
                    end
                end else begin
                    // Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
                    // Can not issue if data is not valid.
                    if (/*issue.*/issuePrimitive != NO_ISSUE) begin
                        nextCondUseFIFO		= 0;
                        nextLogicalState	= VERTEX_LOAD_GARAGE;	// Next Vertex stuff...
                    end else begin
                        nextCondUseFIFO		= 1;
                        nextLogicalState	= VERTEX_LOAD;	// Next Vertex stuff...
                    end
                end
            end
        end
    end
    WIDTH_HEIGHT_STATE:
    begin
        // No$PSX Doc says that two triangles are not generated.
        // We can use 4 lines equation instead of 3.
        // Visually difference can't be made. And pixel pipeline is nearly the same.
        // TODO ?; // Loop to generate 4 vertices... Add w/h to Vertex and UV.
        /*issue.*/loadSize			= 1; /*issue.*/loadSizeParam = SIZE_VAR;

        /*issue.*/loadRectEdge		= bIsRectCommand;

        /*issue.*/issuePrimitive	= (bIsCopyVVCommand | bIsCopyCVCommand | bIsCopyVCCommand) ? ISSUE_COPY : (bIsRectCommand ? ISSUE_RECT : ISSUE_FILL);
        nextCondUseFIFO			= 0;
        nextLogicalState		= WAIT_COMMAND_COMPLETE;
    end
    WAIT_COMMAND_COMPLETE:
    begin
        // (bIsCopyVVCommand | bIsCopyCVCommand | bIsCopyVCCommand | bIsFillCommand)
        nextCondUseFIFO			= 0;
        nextLogicalState		=  canIssueWork ? DEFAULT_STATE : WAIT_COMMAND_COMPLETE;
    end
    default :; // null
    endcase
end

// WE Read from the FIFO when FIFO has data, but also when the GPU is not busy rendering, else we stop loading commands...
// By blocking the state machine, we also block all the controls more easily. (Vertex loading, command issue, etc...)
wire canReadFIFO			= isFifoNotEmpty & canIssueWork;
assign readFifo				= (nextCondUseFIFO & canReadFIFO);
assign nextState			= ((!nextCondUseFIFO) | readFifo) ? nextLogicalState : currState;
assign issuePrimitiveReal	= canIssueWork ? /*issue.*/issuePrimitive : NO_ISSUE;


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

assign isV0 = ((!bIsLineCommand) & (vertCnt == 2'd0) | (vertCnt == 2'd3)) | (bIsLineCommand & !vertCnt[0]); // Vertex 4 primitive load in zero for second triangle.
assign isV1 = ((!bIsLineCommand) & (vertCnt == 2'd1)                    ) | (bIsLineCommand &  vertCnt[0]);
assign isV2 =  (!bIsLineCommand) & (vertCnt == 2'd2);

// Load all 3 component at the same time, save cycles in state machine
// Also use special formula :
// . Vertex Color RGB will be multiplied by Texture RGB. Texture RGB is 0..255 post renormalization.
//   So it is smarter to have Vertex RGB as 256 for MAXIMUM value and just do a simple shift post multiplication and STILL be mathematically correct.
//		- When NOT using texture => we ADD Bit[7] of component to renormalize from 0..255 -> 0..256
//		- When using texture     => Specs says that 0x80 are brightest (same level as FF) -> We multiply by two (shift) only. (add 0) 0x80 -> 0x100
//									So 0.FF -> 0x1FE (510 (1.9921875) instead of 511 (1.99609375)) But because it is overbright with clamped value later on, should be no problem.
//
// . Spec says that when using texture,
wire [8:0] componentFuncR	= bUseTexture    ? { fifoDataOutUR,1'b0 } : { 1'b0, fifoDataOutUR };
wire [8:0] componentFuncG	= bUseTexture    ? { fifoDataOutVG,1'b0 } : { 1'b0, fifoDataOutVG };
wire [8:0] componentFuncB	= bUseTexture    ? {  fifoDataOutB,1'b0 } : { 1'b0,  fifoDataOutB };
// We also avoid to add +1 when using color for FILL command.(shorter test using 0x)
wire bNoTexture				= (!bUseTexture) & (!bIsBase0x);
wire [8:0] componentFuncRA	= componentFuncR + { 8'b00000000, fifoDataOutUR[7] & bNoTexture };
wire [8:0] componentFuncGA	= componentFuncG + { 8'b00000000, fifoDataOutVG[7] & bNoTexture };
wire [8:0] componentFuncBA	= componentFuncB + { 8'b00000000, fifoDataOutB [7] & bNoTexture };
// Finally force WHITE color (256) if no component RGB value are available.
wire [8:0] loadComponentR	= bIgnoreColor   ? 9'b100000000 : componentFuncRA;
wire [8:0] loadComponentG	= bIgnoreColor   ? 9'b100000000 : componentFuncGA;
wire [8:0] loadComponentB	= bIgnoreColor   ? 9'b100000000 : componentFuncBA;

// TODO : SWAP bit. for loading 4th, line segment.
//
reg bPipeIssueTrianglePrimitive;
wire [9:0] copyHeight = { !(|fifoDataOutHeight[8:0]), fifoDataOutHeight };

reg [10:0] widthNext;
reg [ 9:0] heightNext;
reg        writeOrigHeight;

always @(*)
begin
    writeOrigHeight = 0;

    case (/*issue.*/loadSizeParam)
    SIZE_VAR:
    begin
        if (bIsFillCommand) begin
            widthNext = { 1'b0, fifoDataOutWidth[9:4], 4'b0 } + { 6'd0, |fifoDataOutWidth[3:0], 4'b0 };
        end else begin
            if (bIsCopyCVCommand | bIsCopyVCCommand | bIsCopyVVCommand) begin
                widthNext = { !(|fifoDataOutWidth[9:0]), fifoDataOutWidth }; // If value is 0, then 0x400
            end else begin
                widthNext = { 1'b0, fifoDataOutWidth };
            end
        end

        writeOrigHeight = 1;
        if (bIsCopyCVCommand | bIsCopyVCCommand | bIsCopyVVCommand) begin
            heightNext			= copyHeight; // If value is 0, then 0x400
        end else begin
            heightNext			= { 1'b0, fifoDataOutHeight };
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
wire signed [11:0] sizeWM1		  = { 1'b0, widthNext  } + { 12{1'b1}}; //  Width-1
wire signed [11:0] sizeHM1		  = { 2'd0, heightNext } + { 12{1'b1}}; // Height-1

wire isVertexLoadState = (currState == VERTEX_LOAD);
wire signed [11:0] rightEdgeRect  = (isVertexLoadState ? fifoDataOutX : RegX0) + sizeWM1;
wire signed [11:0] bottomEdgeRect = (isVertexLoadState ? fifoDataOutY : RegY0) + sizeHM1;

always @(posedge clk)
begin
    bPipeIssueTrianglePrimitive <= (issuePrimitiveReal == ISSUE_TRIANGLE);
    if (FifoDataValid) begin
        if (isV0 & /*issue.*/loadVertices) RegX0 = fifoDataOutX;
        if (isV0 & /*issue.*/loadVertices) RegY0 = fifoDataOutY;
        if (isV0 & /*issue.*/loadUV	   ) RegU0 = fifoDataOutUR;
        if (isV0 & /*issue.*/loadUV      ) RegV0 = fifoDataOutVG;
        if ((isV0|/*issue.*/loadAllRGB) & /*issue.*/loadRGB) begin
            RegR0 = loadComponentR;
            RegG0 = loadComponentG;
            RegB0 = loadComponentB;
        end

        if (isV1 & /*issue.*/loadVertices) RegX1 = fifoDataOutX;
        if (isV1 & /*issue.*/loadVertices) RegY1 = fifoDataOutY;
        if (/*issue.*/loadRectEdge) begin
            RegX1 = rightEdgeRect;
            RegY1 = RegY0;
            RegX2 = RegX0;
            RegY2 = bottomEdgeRect;
        end
        if (isV1 & /*issue.*/loadUV) RegU1 = fifoDataOutUR;
        if (isV1 & /*issue.*/loadUV) RegV1 = fifoDataOutVG;
        if ((isV1|/*issue.*/loadAllRGB) & /*issue.*/loadRGB) begin
            RegR1 = loadComponentR;
            RegG1 = loadComponentG;
            RegB1 = loadComponentB;
        end

        if (isV2 & /*issue.*/loadVertices) RegX2 = fifoDataOutX;
        if (isV2 & /*issue.*/loadVertices) RegY2 = fifoDataOutY;
        if (isV2 & /*issue.*/loadUV      ) RegU2 = fifoDataOutUR;
        if (isV2 & /*issue.*/loadUV      ) RegV2 = fifoDataOutVG;
        if ((isV2|/*issue.*/loadAllRGB) & /*issue.*/loadRGB) begin
            RegR2 = loadComponentR;
            RegG2 = loadComponentG;
            RegB2 = loadComponentB;
        end

// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
//		if (loadTexPage)  RegTx = fifoDataOutTex;

    //	Better load and add W to RegX0,RegY0,RegX1=RegX0+W ? Same for Y1.
        if (/*issue.*/loadSize) begin
            RegSizeW = widthNext;
            RegSizeH = heightNext;
            if (writeOrigHeight) begin
                OriginalRegSizeH = heightNext;
            end
        end
        if (/*issue.*/loadCoord1) begin
            RegX0 = { 2'd0 , (bIsFillCommand) ? { fifoDataOutWidth[9:4], 4'b0} : fifoDataOutWidth};
            RegY0 = { 3'd0 , fifoDataOutHeight };
        end
        if (/*issue.*/loadCoord2) begin
            RegX1 = { 2'd0 , fifoDataOutWidth  };
            RegY1 = { 3'd0 , fifoDataOutHeight };
        end
    end
end

// ---------------------------------------------------------------------------------------------------------------------
//  [ Setup Stage ]
// ---------------------------------------------------------------------------------------------------------------------

// Range -2047..+2047 (2048 NOT VALID FOR NOW)
// TO CHECK HW : If we use -1024 offset and -1024 vertex, do we get 0 coordinate ?
// [SETUP] Do assign value at loading directly.
wire signed [11:0] nRegX0	= -RegX0;
wire signed [11:0] nRegY0	= -RegY0;
wire signed [11:0] nRegX1	= -RegX1;
wire signed [11:0] nRegY1	= -RegY1;
wire signed [11:0] nRegX2	= -RegX2;
wire signed [11:0] nRegY2	= -RegY2;

// (-2047)+(-2047)..2047+2047 = -4095..+4095
wire signed [12:0]	preA13 	= RegX2 + nRegX0; // X2-X0
wire signed [12:0]	preB13 	= RegY2 + nRegY0; // Y2-Y0
wire signed [12:0]	c13		= RegX1 + nRegX0; // X1-X0
wire signed [12:0]	negc13	= RegX0 + nRegX1; // X0-X1 (-c)
wire signed [12:0]	d13		= RegY1 + nRegY0; // Y1-Y0
wire signed [12:0]  negd13  = RegY0 + nRegY1; // Y0-Y1 (-d)
wire signed [12:0]	e13		= RegX2 + nRegX1; // X2-X1
wire signed [12:0]	f13		= RegY1 + nRegY2; // Y1-Y2

// Permitted RANGE : -511..+511 for Y, -1023..+1023 for X.
//

wire signed [11:0]	preA	= preA13[11:0];
assign				preB 	= preB13[11:0];
wire signed [11:0]	c		= c13	[11:0];
wire signed [11:0]	negc	= negc13[11:0];
wire signed [11:0]	d		= d13	[11:0];
wire signed [11:0]  negd  	= negd13[11:0];
wire signed [11:0]	e		= e13	[11:0];
wire signed [11:0]	f		= f13	[11:0];

// For all coordinate testing.
wire signed [11:0]  extDAX0 = { 2'd0 , GPU_REG_DrawAreaX0 };
wire signed [11:0]  extDAY0 = { 2'd0 , GPU_REG_DrawAreaY0 };
wire signed [11:0]  extDAX1 = { 2'd0 , GPU_REG_DrawAreaX1 };
wire signed [11:0]  extDAY1 = { 2'd0 , GPU_REG_DrawAreaY1 };

wire signed [11:0]  LPixelX = { pixelX[11:1], 1'b0 };
wire signed [11:0]  RPixelX = { pixelX[11:1], 1'b1 };

// Test Current Pixel Pair against [Drawing Area]
// [NEEDED FOR LINES] : Line are scanned independantly from draw area.
wire				isTopInside 		= pixelY  >= extDAY0;
wire				isBottomInside		= pixelY   < extDAY1;
wire				isTopInsideBBox		= pixelY  >= minTriDAY0; // PIXEL IS EXCLUSIVE
assign				isBottomInsideBBox	= pixelY  <= maxTriDAY1; // PIXEL IS INCLUSIVE

wire				isLeftPLXInside	= LPixelX >= extDAX0;
wire				isLeftPRXInside	= RPixelX >= extDAX0;
wire				isRightPLXInside= LPixelX  < extDAX1; // PIXEL IS EXCLUSIVE
wire				isRightPRXInside= RPixelX  < extDAX1; // PIXEL IS EXCLUSIVE
// [NEEDED FOR TRIANGLE AND RECTANGLE] : Intersection of draw area AND bounding box.
wire				isLeftPLXminTri = LPixelX >= minTriDAX0;
wire				isLeftPRXminTri = RPixelX >= minTriDAX0;
assign				isRightPLXmaxTri= LPixelX <= maxTriDAX1; // PIXEL IS INCLUSIVE
wire				isRightPRXmaxTri= RPixelX <= maxTriDAX1; // PIXEL IS INCLUSIVE

wire				isValidHorizontal			= isTopInside     & isBottomInside;
wire				isValidHorizontalTriBbox	= isTopInsideBBox & isBottomInsideBBox;

// Test Current Pixel For Line primitive : Check vertically against the DRAW AREA and select the pixel in the PAIR (odd/even) that match the result of the pixel we want to test.
assign				isLineRightPix			= ( pixelX[0] & isLeftPRXInside & isRightPRXInside);
assign				isLineLeftPix			= (!pixelX[0] & isLeftPLXInside & isRightPLXInside);
assign				isLineInsideDrawArea	= isValidHorizontal & (isLineRightPix | isLineLeftPix);
// Is Inside Triangle & Box rendering (Draw Area Inter. BBox)
assign				isInsideBBoxTriRectL	= isValidHorizontalTriBbox & isLeftPLXminTri & isRightPLXmaxTri;
assign				isInsideBBoxTriRectR	= isValidHorizontalTriBbox & isLeftPRXminTri & isRightPRXmaxTri;
assign				isValidPixelL	= (isCCWInsideL | isCWInsideL) & isInsideBBoxTriRectL;
assign				isValidPixelR	= (isCCWInsideR | isCWInsideR) & isInsideBBoxTriRectR;

// --- For Triangle ---
// Bounding box triangle.
// Vertex0/Vertex1 Box
wire signed [11:0]	minX0X1 = isNegXAxis   ? RegX1 : RegX0;
wire signed [11:0]	maxX0X1 = isNegXAxis   ? RegX0 : RegX1;
wire signed [11:0]	minY0Y1 = isNegYAxis   ? RegY1 : RegY0;
wire signed [11:0]	maxY0Y1 = isNegYAxis   ? RegY0 : RegY1;
// Vertex0/1/2 Box
assign				minXTri = RegX2 < minX0X1 ? RegX2 : minX0X1;
wire signed [11:0]	minYTri = RegY2 < minY0Y1 ? RegY2 : minY0Y1;
assign				maxXTri = RegX2 > maxX0X1 ? RegX2 : maxX0X1;
wire signed [11:0]	maxYTri = RegY2 > maxY0Y1 ? RegY2 : maxY0Y1;

// Primitive Size
wire invalidX2X0   = !((preA13[12:10]==  3'b000) | (preA13[12:10]==  3'b111));
wire invalidX1X0   = !((   c13[12:10]==  3'b000) | (   c13[12:10]==  3'b111));
wire invalidY2Y0   = !((preB13[12: 9]== 4'b0000) | (preB13[12: 9]== 4'b1111));
wire invalidY1Y0   = !((   d13[12: 9]== 4'b0000) | (   d13[12: 9]== 4'b1111));
wire rejectTriSize = invalidX1X0 | invalidX2X0 | invalidY1Y0 | invalidY2Y0; // 1023 pixel in --> direction, 1024 pixel in <-- direction, 511 pixel in V direction, -512 pixel in ^ direction.
// Bounding box vs Draw Area.

// [Setup]
wire				earlyTriRejectLeft   = maxXTri  < extDAX0;
wire				earlyTriRejectTop    = maxYTri  < extDAY0;
wire				earlyTriRejectRight  = minXTri >= extDAX1;
wire				earlyTriRejectBottom = minYTri >= extDAY1;
assign				earlyTriangleReject  = earlyTriRejectLeft | earlyTriRejectRight | earlyTriRejectTop | earlyTriRejectBottom | rejectTriSize;
/* PERFORMANCE OPTIMIZATION
wire				earlyLineReject      = invalidX1X0 | invalidY1Y0; // | earlyLineRejectLeft | earlyLineRejectTop | earlyLineRejectRight | earlyLineRejectBottom;
wire				earlyLineRejectLeft  = maxX0X1  < extDAX0;
wire				earlyLineRejectTop   = maxY0Y1  < extDAY0;
wire				earlyLineRejectRight = minX0X1 >= extDAX1;
wire				earlyLineRejectBottom= minY0Y1 >= extDAY1;
*/

// Thanks to earlyTriangleReject, we know the box are intersecting.
// We know that Box is properly oriented (Min < Max), we assume that DrawArea X0 < X1 too.
// [Setup]
assign				minTriDAX0 = minXTri  < extDAX0 ?  extDAX0    : minXTri;
assign				maxTriDAX1 = maxXTri >= extDAX1 ? (extDAX1 + {12'hFFF}) : maxXTri; // TODO : Do X1-1/Y1-1 at register setup, and change all test for X1/Y1
assign				minTriDAY0 = minYTri  < extDAY0 ?  extDAY0    : minYTri;
assign				maxTriDAY1 = maxYTri >= extDAY1 ? (extDAY1 + {12'hFFF}) : maxYTri;

// --- For Lines
// [Setup] Line
assign              isNegXAxis = c[11];
assign              isNegYAxis = d[11];
wire        [11:0]  absXAxis   = isNegXAxis ? negc : c;
wire        [11:0]  absYAxis   = isNegYAxis ? negd : d;
wire                swapAxis   = absYAxis > absXAxis;
wire signed [11:0]  aDX2       = swapAxis ? absYAxis : absXAxis;
wire signed [11:0]  aDY2       = swapAxis ? absXAxis : absYAxis;
assign				initialD   = { 1'b0 ,aDY2, !swapAxis };

// Runtime Line
wire signed [13:0]  compD      = { 2'b0 , aDX2 };
wire                changeDir  = DLine > compD;
wire        [12:0]  incrDOff   = (~{ aDX2, 1'b0 }) + 13'd1; // -2 * aDX2
wire        [13:0]  incrD      = { 1'b0, aDY2, 1'b0 } + (changeDir ? { incrDOff[12] , incrDOff } : 14'd0);
wire                incXOK     = (changeDir &  (swapAxis)) | (!swapAxis);
wire                incYOK     = (changeDir & (!swapAxis)) |   swapAxis;
wire signed  [1:0]  stepX      = { isNegXAxis & incXOK, incXOK }; // -1/+1 when needed, or 0.
wire signed  [1:0]  stepY      = { isNegYAxis & incYOK, incYOK }; // -1/+1 when needed, or 0.
wire signed [11:0]  incrX      = { {10{stepX[1]}}, stepX };
wire signed [11:0]  incrY      = { {10{stepY[1]}}, stepY };
assign 				nextLineX  = pixelX + incrX;
assign				nextLineY  = pixelY + incrY;
assign				nextD      = DLine + incrD;

// ----
// [Setup] AT Register Loading.
wire signed [11:0]	a		= bIsLineCommand ?    d : preA;
wire signed [11:0]	b		= bIsLineCommand ? negc : preB;
wire signed [11:0]	negb	= -b;
wire signed [11:0]	nega	= -a;

wire signed [21:0]	DETP1	= a*d;
wire signed [21:0]	DETP2	= b*negc;			// -b*c -> b*negc
wire signed [21:0]	DET		= DETP1 + DETP2;	// Same as (a*d) - (b*c)

reg signed [11:0]	mulFA,mulFB;
reg  signed [8:0]	v0C,v1C,v2C;

reg [2:0] compoID2,compoID3,compoID4,compoID5,compoID6;
reg       vecID2,vecID3,vecID4,vecID5,vecID6;
always @(posedge clk)
begin
    compoID6 = compoID5;
    compoID5 = compoID4;
    compoID4 = compoID3;
    compoID3 = compoID2;
    compoID2 = compoID;

    vecID6   = vecID5;
    vecID5   = vecID4;
    vecID4   = vecID3;
    vecID3   = vecID2;
    vecID2   = vecID;
end

always @(*)
begin
    case (compoID)
    default:	begin v0C = RegR0;           v1C = RegR1;           v2C = RegR2;           end
    3'd2:		begin v0C = RegG0;           v1C = RegG1;           v2C = RegG2;           end
    3'd3:		begin v0C = RegB0;           v1C = RegB1;           v2C = RegB2;           end
    3'd4:		begin v0C = { 1'b0, RegU0 }; v1C = { 1'b0, RegU1 }; v2C = { 1'b0, RegU2 }; end
    3'd5:		begin v0C = { 1'b0, RegV0 }; v1C = { 1'b0, RegV1 }; v2C = { 1'b0, RegV2 }; end
    endcase

    if (vecID) begin
        mulFA = negc;	mulFB = a;
    end else begin
        mulFA = d;   	mulFB = negb;
    end
end
wire signed [9:0]   negv0c  = -{ 1'b0 ,v0C };
wire signed [9:0]	C20i	= bIsLineCommand ? 10'd0 : ({ 1'b0 ,v2C } + negv0c);
wire signed [9:0]	C10i	=  { 1'b0 ,v1C } + negv0c; // -512..+511

wire signed [20:0] inputDivA	= mulFA * C20i; // -2048..+2047 x -512..+511 = Signed 21 bit.
wire signed [20:0] inputDivB	= mulFB * C10i;

// Signed 21 bit << 11 bit => 32 bit signed value.
wire signed [31:0] inputDivAShft= { inputDivA, 11'b0 }; // PREC'd0
wire signed [31:0] inputDivBShft= { inputDivB, 11'b0 };
wire signed [PREC+8:0] outputA;
wire signed [PREC+8:0] outputB;

dividerWrapper instDivisorA(
    .clock			( clk ),
    .numerator		( inputDivAShft),
    .denominator	( DET ),
    .output20		( outputA )
);

dividerWrapper instDivisorB(
    .clock			( clk ),
    .numerator 		( inputDivBShft ),
    .denominator 	( DET ),
    .output20 		( outputB )
);

// 11 bit prec + 9 bit = 20 bit.
wire signed [PREC+8:0] perPixelComponentIncrement = outputA + outputB;
// ---------------------------------------------------------------------------------------------------------------------
//  [ Interpolator Storage Stage ]
// ---------------------------------------------------------------------------------------------------------------------

reg signed [PREC+8:0] RSX,RSY,GSX,GSY,BSX,BSY,USX,USY,VSX,VSY; // 1..10 Write, 0:Do nothing.

wire /*reg*/ [3:0]	assignDivResult = { compoID6, vecID6 }; // 1..A, 0 none
always @(posedge clk) begin
    if (assignDivResult == 4'd2) begin RSX = perPixelComponentIncrement; end
    if (assignDivResult == 4'd3) begin RSY = perPixelComponentIncrement; end
    if (assignDivResult == 4'd4) begin GSX = perPixelComponentIncrement; end
    if (assignDivResult == 4'd5) begin GSY = perPixelComponentIncrement; end
    if (assignDivResult == 4'd6) begin BSX = perPixelComponentIncrement; end
    if (assignDivResult == 4'd7) begin BSY = perPixelComponentIncrement; end
    if (assignDivResult == 4'd8) begin USX = perPixelComponentIncrement; end
    if (assignDivResult == 4'd9) begin USY = perPixelComponentIncrement; end
    if (assignDivResult == 4'hA) begin VSX = perPixelComponentIncrement; end
    if (assignDivResult == 4'hB) begin VSY = perPixelComponentIncrement; end
    // Assign rasterization parameter for RECT mode.
    if (assignRectSetup) begin
        RSX = ZERO_PREC;
        RSY = ZERO_PREC;
        GSX = ZERO_PREC;
        GSY = ZERO_PREC;
        BSX = ZERO_PREC;
        BSY = ZERO_PREC;
        USX = ONE_PREC;
        USY = ZERO_PREC;
        VSX = ZERO_PREC;
        VSY = ONE_PREC;
    end
end

// ---------------------------------------------------------------------------------------------------------------------
//  [ Interpolator Compute Stage ]
// ---------------------------------------------------------------------------------------------------------------------

wire signed [11:0] distXV0 = pixelX + nRegX0;
wire signed [11:0] distYV0 = pixelY + nRegY0;
wire signed [11:0] distXV1 = pixelX + nRegX1;
wire signed [11:0] distYV1 = pixelY + nRegY1;
wire signed [11:0] distXV2 = pixelX + nRegX2;
wire signed [11:0] distYV2 = pixelY + nRegY2;

// EQUMSB=22
// D12(e   ,f)-> isTopLeft(D12) -> f    < 0 || (   f == 0) & e    < 0
// D20(nega,b)-> isTopLeft(D20) -> b    < 0 || (   b == 0) & nega < 0
// D01(c,negd)-> isTopLeft(D01) -> negd < 0 || (negd == 0) & c    < 0
wire isTopLeftD12 =    f[11] | ((   f == 12'd0) &    e[11]);
wire isTopLeftD01 = negd[11] | ((negd == 12'd0) &    c[11]);
wire isTopLeftD20 =    b[11] | ((   b == 12'd0) & nega[11]);

wire signed [EQUMSB:0] bias0= {23{isTopLeftD12}}; // -1 if true, 0 if false.
wire signed [EQUMSB:0] bias1= {23{isTopLeftD20}};
wire signed [EQUMSB:0] bias2= {23{isTopLeftD01}};

assign w0L	= (   e*distYV1) + (   f*distXV1) + bias0;
assign w1L	= (nega*distYV2) + (   b*distXV2) + bias1;
assign w2L	= (   c*distYV0) + (negd*distXV0) + bias2;

assign w0R	= w0L + { {11{f[11]}}, f};
assign w1R	= w1L + { {11{b[11]}}, b};
assign w2R	= w2L + { {11{negd[11]}}, negd};

/*
    [Original Implementation in Avocado, based on the famous Ryg article about rasterization.]
    if ((w0L | w1L | w2L) > 0) {    but Avocado always garantee CCW oriented polygon.

    First, we can notice that the condition does not seems accurate :
    By 'oring' we allow one or two line equation >= 0 if another is > 0.

    HW implementation of >= 0 is a LOT easier.
    Did not change a simple pixel on basic triangle I tested.

    For opposite orientation, I use the opposite < 0.
 */
assign isCCWInsideL = !(w0L[EQUMSB] | w1L[EQUMSB] | w2L[EQUMSB]); // Same as : (w0 >= 0) && (w1 >= 0) && (w2 >= 0)
assign isCWInsideL  =  (w0L[EQUMSB] & w1L[EQUMSB] & w2L[EQUMSB]); // Same as : (w0 <  0) && (w1  < 0) && (w2  < 0)

assign isCCWInsideR = !(w0R[EQUMSB] | w1R[EQUMSB] | w2R[EQUMSB]);
assign isCWInsideR  =  (w0R[EQUMSB] & w1R[EQUMSB] & w2R[EQUMSB]);

//
// [Component Interpolation Out]
//
wire signed [PREC+8:0] roundComp = { 9'd0, 1'b1, 10'd0}; // PRECM1'd0
wire signed [PREC+8:0] offR = (distXV0*RSX) + (distYV0*RSY) + roundComp;
wire signed [PREC+8:0] offG = (distXV0*GSX) + (distYV0*GSY) + roundComp;
wire signed [PREC+8:0] offB = (distXV0*BSX) + (distYV0*BSY) + roundComp;
wire signed [PREC+8:0] offU = (distXV0*USX) + (distYV0*USY) + roundComp;
wire signed [PREC+8:0] offV = (distXV0*VSX) + (distYV0*VSY) + roundComp;

wire signed [8:0] pixRL = RegR0 + offR[PREC+8:PREC];
wire signed [8:0] pixGL = RegG0 + offG[PREC+8:PREC];
wire signed [8:0] pixBL = RegB0 + offB[PREC+8:PREC];
wire signed [7:0] pixUL = RegU0 + offU[PREC+7:PREC];
wire signed [7:0] pixVL = RegV0 + offV[PREC+7:PREC];

wire signed [PREC+8:0] offRR = offR + RSX;
wire signed [PREC+8:0] offGR = offG + GSX;
wire signed [PREC+8:0] offBR = offB + BSX;
wire signed [PREC+8:0] offUR = offU + USX;
wire signed [PREC+8:0] offVR = offV + VSX;
wire signed [8:0] pixRR = RegR0 + offRR[PREC+8:PREC];
wire signed [8:0] pixGR = RegG0 + offGR[PREC+8:PREC];
wire signed [8:0] pixBR = RegB0 + offBR[PREC+8:PREC];
wire signed [7:0] pixUR = RegU0 + offUR[PREC+7:PREC];
wire signed [7:0] pixVR = RegV0 + offVR[PREC+7:PREC];


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
assign requestNextPixel = (!missTC) & (!writePixelOnNewBlock) & (!saveLoadOnGoing);
reg lastSaveLoadOnGoing;
reg lastMissTC;
always @(posedge clk)
begin
    lastSaveLoadOnGoing = saveLoadOnGoing;
    lastMissTC			= missTC;
end

wire notMemoryBusyCurrCycle;
wire notMemoryBusyNextCycle;

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
wire [31:0]		readValue32;
wire            dataArrived;
wire			dataConsumed;

wire  [5:0]    XPosClut           = {1'b0,rClutPacketCount} + RegCLUT[5:0];
wire  [14:0]   adrClutCacheUpdate = { RegCLUT[14:6] , XPosClut };

MemoryArbitrator MemoryArbitratorInstance(
    .gpuClk					(clk),
    .i_nRst					(i_nrst),

    // ---TODO Describe all fifo command ---
    .memoryWriteCommand		(memoryWriteCommand),
    .fifoFull				(commandFifoFull),
    .fifoComplete			(commandFifoComplete),

    .o_dataArrived			(dataArrived),
    .o_dataValue			(readValue32),
    .i_dataConsumed			(dataConsumed),

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
    .notMemoryBusyCurrCycle	(notMemoryBusyCurrCycle),
    .notMemoryBusyNextCycle	(notMemoryBusyNextCycle),

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

    // -----------------------------------
    // [Fake Memory SIDE]
    // -----------------------------------

    .adr_o					(adr_o),   // ADR_O() address
    .dat_i					(dat_i),   // DAT_I() data in
    .dat_o					(dat_o),   // DAT_O() data out
    .cnt_o					(cnt_o),
    .sel_o					(sel_o),
    .wrt_o					(wrt_o),
    .req_o					(req_o),
    .ack_i					(ack_i)
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

