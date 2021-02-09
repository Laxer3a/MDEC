/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

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
wire       		GPU_REG_IsInterlaced;
wire       		GPU_REG_BufferRGB888;
wire       		GPU_REG_VideoMode;
wire       		GPU_REG_VerticalResolution;
wire [1:0] 		GPU_REG_HorizResolution;
wire       		GPU_REG_HorizResolution368;
wire			GPU_REG_ReverseFlag;
wire       		GPU_REG_DisplayDisabled;
wire			GPU_REG_DrawDisplayAreaOn;

wire [9:0]		GPU_REG_DispAreaX;
wire [8:0]		GPU_REG_DispAreaY;
wire [11:0]		GPU_REG_RangeX0;
wire [11:0]		GPU_REG_RangeX1;
wire [9:0]		GPU_REG_RangeY0;
wire [9:0]		GPU_REG_RangeY1;

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

parameter   IS_NOT_NEWBLOCK				= 2'b00,
            IS_NEW_BLOCK_IN_PRIMITIVE	= 2'b01,	// The first time we flush a 16 pixel block, there is NO WRITE of the previous block, but LOAD must be done if doing blending.
            IS_OTHER_BLOCK_IN_PRIMITIVE	= 2'b10,	// For other block we simply do WRITE the previous block, or WRITE + LOAD next block BG if doing blending.
            IS_FLUSH_LAST_PIXEL			= 2'b11;

parameter TRANSP_HALF=2'd0, TRANSP_ADD=2'd1, TRANSP_SUB=2'd2, TRANSP_ADDQUARTER=2'd3;
parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;

parameter XRES_256  =2'd0, XRES_320   =2'd1, XRES_512  =2'd2, XRES_640  =2'd3;
parameter DMADIR_OFF=2'd0, DMADIR_FIFO=2'd1, DMADIR_C2G=2'd2, DMADIR_G2C=2'd3;

wire bIsCopyVVCommand,bIsCopyCVCommand,bIsCopyVCCommand,bIsRectCommand,bIsPolyCommand,bSemiTransp,bOpaque,bIsCopyCommand,bUseTextureParser,bIsPerVtxCol,bIsLineCommand;
wire [1:0] loadSizeParam;
wire [4:0] issuePrimitive;

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

//-----------------------------------------
// CPU write/read GP0/GP1/FifoOut
//-----------------------------------------

wire stillDoingVRAMCPUXFER = (RegCommand == 8'hC0) & (!waitWork);
wire parserWaitingNewCommand;
wire rstGPU,rstCmd,rstIRQ;
wire GPU_REG_IRQSet;

gpu_irq IRQModule_inst (
	.i_clk							(clk),
	.i_rstIRQ						(rstGPU | rstIRQ),
	.i_setIRQ						(setIRQ),
	.o_irq							(GPU_REG_IRQSet)
);

wire signed [10:0] 	GPU_REG_OFFSETX;
wire signed [10:0] 	GPU_REG_OFFSETY;
wire         [3:0] 	GPU_REG_TexBasePageX;
wire               	GPU_REG_TexBasePageY;
wire         [1:0] 	GPU_REG_Transparency;
wire         [1:0] 	GPU_REG_TexFormat;
wire               	GPU_REG_DitherOn;
wire               	GPU_REG_TextureDisable;
wire               	GPU_REG_TextureXFlip;
wire               	GPU_REG_TextureYFlip;
wire         [4:0] 	GPU_REG_WindowTextureMaskX;
wire         [4:0] 	GPU_REG_WindowTextureMaskY;
wire         [4:0] 	GPU_REG_WindowTextureOffsetX;
wire         [4:0] 	GPU_REG_WindowTextureOffsetY;
wire         [9:0] 	GPU_REG_DrawAreaX0;
wire         [9:0] 	GPU_REG_DrawAreaY0;
wire         [9:0] 	GPU_REG_DrawAreaX1;
wire         [9:0] 	GPU_REG_DrawAreaY1;
wire               	GPU_REG_ForcePixel15MaskSet;
wire               	GPU_REG_CheckMaskBit;

gpu_frontend gpu_frontend_instance (
	.i_clk							(clk),
	.i_nRst							(i_nrst),
	
	.gpuSel							(gpuSel),
	.gpuAdrA2						(gpuAdrA2),
	.write							(write),
	.read							(read),
	
	.cpuDataIn						(cpuDataIn),
	.cpuDataOut						(cpuDataOut),
	.cpuDataOutValid				(validDataOut),
	
	.o_rstGPU						(rstGPU),
	.o_rstCmd						(rstCmd),
	.o_rstIRQ						(rstIRQ),
	
	.i_useVCCopyFIFOOut				(stillDoingVRAMCPUXFER),
	.i_valueVCCopyFIFOOut			(outFIFO_readV),
	
	//-------------------------------------------------------
	//  Inputs
	//-------------------------------------------------------
	.i_statusBit31					(GPU_DisplayEvenOddLinesInterlace),
	.i_statusBit28					(waitWork),
	.i_statusBit27					(gpuReadySendToCPU),
	.i_statusBit26					(isFifoEmpty32 && parserWaitingNewCommand && waitWork),
	.i_statusBit25					(dmaDataRequest),
	.i_statusBit24					(GPU_REG_IRQSet),
	.i_statusBit13					((GPU_REG_CurrentInterlaceField & GPU_REG_IsInterlaced) | (!GPU_REG_IsInterlaced)),

	//-------------------------------------------------------
	//  Inputs
	//-------------------------------------------------------
	.GPU_REG_TextureDisable			(GPU_REG_TextureDisable),
	.GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit),
	.GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet),
	.GPU_REG_DrawDisplayAreaOn		(GPU_REG_DrawDisplayAreaOn),
	.GPU_REG_DitherOn				(GPU_REG_DitherOn),
	.GPU_REG_TexFormat				(GPU_REG_TexFormat),
	.GPU_REG_Transparency			(GPU_REG_Transparency),
	.GPU_REG_TexBasePageX			(GPU_REG_TexBasePageX),
	.GPU_REG_TexBasePageY			(GPU_REG_TexBasePageY),
	.GPU_REG_WindowTextureMaskX		(GPU_REG_WindowTextureMaskX),
	.GPU_REG_WindowTextureMaskY		(GPU_REG_WindowTextureMaskY),
	.GPU_REG_DrawAreaX0				(GPU_REG_DrawAreaX0),
	.GPU_REG_DrawAreaY0				(GPU_REG_DrawAreaY0),
	.GPU_REG_DrawAreaX1				(GPU_REG_DrawAreaX1),
	.GPU_REG_DrawAreaY1				(GPU_REG_DrawAreaY1),
	.GPU_REG_OFFSETX				(GPU_REG_OFFSETX),
	.GPU_REG_OFFSETY				(GPU_REG_OFFSETY),
	.GPU_REG_WindowTextureOffsetX	(GPU_REG_WindowTextureOffsetX),
	.GPU_REG_WindowTextureOffsetY	(GPU_REG_WindowTextureOffsetY),

	//-------------------------------------------------------
	//  Outputs
	//-------------------------------------------------------
	.o_GPU_REG_DMADirection			(DMADirection'(GPU_REG_DMADirection)),

	.o_GPU_REG_IsInterlaced			(GPU_REG_IsInterlaced),
	.o_GPU_REG_BufferRGB888			(GPU_REG_BufferRGB888),
	.o_GPU_REG_VideoMode			(GPU_REG_VideoMode),
	.o_GPU_REG_VerticalResolution	(GPU_REG_VerticalResolution),
	.o_GPU_REG_HorizResolution		(GPU_REG_HorizResolution),
	.o_GPU_REG_HorizResolution368	(GPU_REG_HorizResolution368),
	.o_GPU_REG_ReverseFlag			(GPU_REG_ReverseFlag),
	.o_GPU_REG_DisplayDisabled		(GPU_REG_DisplayDisabled),

	.o_GPU_REG_DispAreaX			(GPU_REG_DispAreaX),
	.o_GPU_REG_DispAreaY			(GPU_REG_DispAreaY),
	.o_GPU_REG_RangeX0				(GPU_REG_RangeX0),
	.o_GPU_REG_RangeX1				(GPU_REG_RangeX1),
	.o_GPU_REG_RangeY0				(GPU_REG_RangeY0),
	.o_GPU_REG_RangeY1				(GPU_REG_RangeY1)
);

GPURegisters_GP0 GPURegisters_GP0_instance (
	.i_clk							(clk),
	.rstGPU							(rstGPU),

	//-------------------------------
	//  INPUT : Loading From Parser
	//-------------------------------
	.loadE5Offsets					(loadE5Offsets),
	.loadTexPageE1					(loadTexPageE1),
	.loadTexPage					(loadTexPage),
	.loadTexWindowSetting			(loadTexWindowSetting),
	.loadDrawAreaTL					(loadDrawAreaTL),
	.loadDrawAreaBR					(loadDrawAreaBR),
	.loadMaskSetting				(loadMaskSetting),
	.fifoDataOut					(fifoDataOut),

	//-------------------------------
	//  OUTPUT : GP0 Registers      
	//-------------------------------
	.o_GPU_REG_OFFSETX				(GPU_REG_OFFSETX),
	.o_GPU_REG_OFFSETY				(GPU_REG_OFFSETY),
	.o_GPU_REG_TexBasePageX			(GPU_REG_TexBasePageX),
	.o_GPU_REG_TexBasePageY			(GPU_REG_TexBasePageY),
	.o_GPU_REG_Transparency			(GPU_REG_Transparency),
	.o_GPU_REG_TexFormat			(GPU_REG_TexFormat),
	.o_GPU_REG_DitherOn				(GPU_REG_DitherOn),
	.o_GPU_REG_DrawDisplayAreaOn	(GPU_REG_DrawDisplayAreaOn),
	.o_GPU_REG_TextureDisable		(GPU_REG_TextureDisable),
	.o_GPU_REG_TextureXFlip			(GPU_REG_TextureXFlip),
	.o_GPU_REG_TextureYFlip			(GPU_REG_TextureYFlip),
	.o_GPU_REG_WindowTextureMaskX	(GPU_REG_WindowTextureMaskX),
	.o_GPU_REG_WindowTextureMaskY	(GPU_REG_WindowTextureMaskY),
	.o_GPU_REG_WindowTextureOffsetX	(GPU_REG_WindowTextureOffsetX),
	.o_GPU_REG_WindowTextureOffsetY	(GPU_REG_WindowTextureOffsetY),
	.o_GPU_REG_DrawAreaX0			(GPU_REG_DrawAreaX0),
	.o_GPU_REG_DrawAreaY0			(GPU_REG_DrawAreaY0),
	.o_GPU_REG_DrawAreaX1			(GPU_REG_DrawAreaX1),
	.o_GPU_REG_DrawAreaY1			(GPU_REG_DrawAreaY1),
	.o_GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet),
	.o_GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit)
);

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

reg		resetXCounter;
wire	endVertical;

wire [2:0] selNextX_VC , selNextY_VC
          ,selNextX_VV , selNextY_VV
          ,selNextX_CV , selNextY_CV
          ,selNextX_RDR, selNextY_RDR;
nextX_t selNextX;
nextY_t selNextY;

wire		doBlockWork;

// State machine for triangle
// State to control setup...
reg [4:0]		interpolationCounter;
reg             setInterCounter, incrementInterpCounter;
wire [4:0]		nextInterpolationCounter = interpolationCounter +
											`ifdef DOUBLE_DIVUNIT
												5'd2
											`else
												5'd1
											`endif
											;







/*
bIsPolyCommand
bIsRectCommand
bIsLineCommand
bUseTexture = (bUseTextureParser & GPU ENABLE TEXTURE)
bIgnoreColor = Texture only, no color modulation (independant on texture used or not)
bIsPerVtxCol

// Runtime flag (Non textured lines, RAW Texture mode, etc...)


*/




wire useUV = (bUseTexture & !bIsLineCommand) & (!bIsPerVtxCol);
wire endInterpCounter = (nextInterpolationCounter[4:2] == { 1'b1, bUseTexture , 1'b0 });
always @(posedge clk) begin
	if (setInterCounter) begin
		// 1100.0  <-- RECT : No loading (end counter)
		// 1000.0  <-- UV Only
		// 0010.0  <-- RGB First
		interpolationCounter <= { useUV,bIsRectCommand,!useUV, 2'b00 };
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
reg 			writeStencil;

// ------------------------------------------------------------------------
//   Plumbing
reg				stencilFullMode;
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

wire xCopyDirectionIncr;
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
wire cpuReadFifoOut = (gpuSel & !gpuAdrA2) & read;

// READ FIFO WHEN :
// - Data is already available in the FIFO.
// - When it is a CPU READ
//   OR WHEN DOING DMA TRANSFER
// - When force FIFO to present value first time before.
// - When it is reading current value, kick the next value with DMA_ACK.
wire        outFIFO_read = ((((GPU_REG_DMADirection == DMA_GP0toCPU) && (!unconsummed || firstRead))) || cpuReadFifoOut) && (!outFIFO_empty);

// Pipeline FIFO read to validate data out (1 cycle latency)
reg pACK;
always @(posedge clk) begin
    if (i_nrst == 0) begin
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
		if (activateCopy && bIsCopyVCCommand) begin
			firstRead   <= 1'b1;
		end
    end
end

assign IRQRequest = GPU_REG_IRQSet;

wire [31:0] fifoDataOut;
assign isINFifoFull     = isFifoFullLSB  | isFifoFullMSB;
assign isFifoEmpty32    = isFifoEmptyLSB | isFifoEmptyMSB;
assign isFifoNotEmpty32 = !isFifoEmpty32;
assign rstInFIFO        = rstGPU | rstCmd;

wire readL, readM;
wire readFifoLSB	= readFifo | readL;
wire readFifoMSB	= readFifo | readM;

wire [55:0] memoryWriteCommand;
reg  [52:0] parameters;
assign memoryWriteCommand = { parameters, memoryCommand};

wire commandFIFOaccept = ((!commandFifoFull) && !saveLoadOnGoing);

wire swap,saveL,saveM;
reg  flush;
wire [15:0] LPixel = swap ? fifoDataOut[31:16] : fifoDataOut[15: 0];
wire [15:0] RPixel = swap ? fifoDataOut[15: 0] : fifoDataOut[31:16];
wire validL        = swap ? saveM : saveL;
wire validR        = swap ? saveL : saveM;

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
wire		cpyBank;
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
	.o_bIsCopyVCCommand		(bIsCopyVCCommand),
	.o_bIsCopyCommand		(bIsCopyCommand),
	.o_bIsFillCommand		(),
	.o_bIsRenderAttrib		(),
	.o_bIsNop				(),
	.o_bIsPolyOrRect		(),
	.o_bUseTextureParser	(bUseTextureParser),
	.o_bSemiTransp			(bSemiTransp),
	.o_bOpaque				(bOpaque),
	.o_bIs4PointPoly		(),
	.o_bIsPerVtxCol			(bIsPerVtxCol),
	.o_bIgnoreColor			()
);

// Runtime flag (Non textured lines, RAW Texture mode, etc...)
wire bUseTexture    		= bUseTextureParser & (!GPU_REG_TextureDisable); 										// Avoid texture fetching if we do LINE, Compute proper color for FILL.

wire rstTextureCache,loadE5Offsets,loadTexPageE1,loadTexWindowSetting,loadDrawAreaTL,loadDrawAreaBR,loadMaskSetting,setIRQ,loadClutPage,loadTexPage;
wire storeCommand;
wire loadVertices,loadUV,loadRGB,loadAllRGB,loadCoord1,loadCoord2,loadSize,loadRectEdge;

gpu_parser gpu_parser_instance(
	.i_clk				(clk),
	.i_rstGPU			(rstGPU),	// Reset Signal or Reset Command GP1
	
	.i_command			(command),
	.o_waitingNewCommand(parserWaitingNewCommand),

	.i_gpuBusy			(!waitWork),
	.o_issuePrimitive	(issuePrimitive),

	// Request data to parse
	.i_isFifoNotEmpty32	(isFifoNotEmpty32),
	.o_readFIFO			(readFifo),

	// Valid data from previous request
	.i_dataValid		(FifoDataValid),
	.i_bIsTerminator	(bIsTerminator),
	
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

wire dir;

wire loadNext_VV,loadNext_CV,loadNext_RDR;
wire isCopyVCActive, isCopyVVActive, isCopyCVActive;
wire [2:0] memoryCommand_VV,memoryCommand_CV,memoryCommand_VC,memoryCommand_RDR;
wire resetXCounter_VV, resetXCounter_RDR, incrementXCounter_VV, incrementXCounter_RDR;
wire writeStencil_VV,writeStencil_CV,writeStencil_RDR;
wire stencilReadSig_VV,stencilReadSig_CV,stencilReadSig_RDR;
wire flush_CV,flush_RDR;

always @(*) begin
	if (isCopyVCActive) begin
		loadNext = 1;
		selNextX = nextX_t'(selNextX_VC);
		selNextY = nextY_t'(selNextY_VC);
		memoryCommand		= memoryCommand_VC;
		resetXCounter		= 0;
		incrementXCounter	= 0;
		writeStencil		= 0;
		stencilReadSig		= 0;
		flush				= 0;
	end else if (isCopyVVActive) begin
		loadNext = loadNext_VV;
		selNextX = nextX_t'(selNextX_VV); // Unused
		selNextY = nextY_t'(selNextY_VV);
		memoryCommand		= memoryCommand_VV;
		resetXCounter		= resetXCounter_VV;
		incrementXCounter	= incrementXCounter_VV;
		writeStencil		= writeStencil_VV;
		stencilReadSig		= stencilReadSig_VV;
		flush				= 0;
	end else if (isCopyCVActive) begin
		loadNext = loadNext_CV;
		selNextX = nextX_t'(selNextX_CV);
		selNextY = nextY_t'(selNextY_CV);
		memoryCommand		= memoryCommand_CV;
		resetXCounter		= 0;
		incrementXCounter	= 0;
		writeStencil		= writeStencil_CV;
		stencilReadSig		= stencilReadSig_CV;
		flush				= flush_CV;
	end else begin
		loadNext = loadNext_RDR;
		selNextX = nextX_t'(selNextX_RDR);
		selNextY = nextY_t'(selNextY_RDR);
		memoryCommand		= memoryCommand_RDR;
		resetXCounter		= resetXCounter_RDR;
		incrementXCounter	= incrementXCounter_RDR;
		writeStencil		= writeStencil_RDR;
		stencilReadSig		= stencilReadSig_RDR;
		flush				= flush_RDR;
	end
end

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

wire [3:0] rightPos;
// wire  [6:0] fullX				= (useDest           ? adrXDst : adrXSrc)          + { 1'b0, useDest ? RegX1[9:4] : RegX0[9:4] };
gpu_masking gpu_masking_inst(
	.RegX0_4bit				(RegX0[3:0]),
	.RegSizeW_4bit			(RegSizeW[3:0]),
	
	.i_adrXSrc				(adrXSrc),
	.i_lengthBlkSrcHM1_6bit	(lengthBlockSrcHM1[5:0]),
	
	.o_rightPos				(rightPos),
	.o_maskRead16			(maskRead16)
);

wire [3:0]  sxe16    		= rightPos + 4'b1111;
wire dblLoadL2R				= RegX1[3:0] < RegX0[3:0];

wire [4:0] tmpidx			= { dblLoadL2R , RegX0[3:0] } + { 1'b1, ~RegX1[3:0] } + 5'd1;
wire [3:0] cpyIdx			= tmpidx[3:0];

wire dblLoadR2L				= sxe16 < cpyIdx;
wire isDoubleLoad			= xCopyDirectionIncr ? dblLoadL2R : dblLoadR2L;

wire  performSwitch			= |cpyIdx; // If ZERO, NO SWITCH !

always @(posedge clk)
begin
    counterXSrc <= (resetXCounter) ? 7'd0 : counterXSrc + { 6'd0 ,incrementXCounter & (!useDest) };
    counterXDst <= (resetXCounter) ? 7'd0 : counterXDst + { 6'd0 ,incrementXCounter &   useDest  };
end

reg  switchReadStoreBlock; // TODO this command will ALSO do loading the CACHE STENCIL locally (2x16 bit registers)

// Needed for state machine.
wire emptySurface				= (RegSizeH == 10'd0) | (RegSizeW == 11'd0);
wire isLastSegment  			= (counterXSrc==lengthBlockSrcHM1);
wire isLastSegmentDst			= (counterXDst==lengthBlockDstHM1);

// RegX0 - RegX1 + (dblLoadL2R ? 16 : 0)

wire isLongLine				= RegSizeW[9] | RegSizeW[10]; // At least >= 512

reg [31:0]	stencilReadCache;

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

reg  [15:0] stencilReadRemapped;
reg  [15:0] maskReadRemapped;
// Mask and [Full_selection_if_GPU_DRAW_ALWAYS or inverse_stencilRead_At_target]
wire [31:0] maskReadCache;

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

// --------------------------------------------------------------------------------------------
//   CPU TO VRAM STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

// [Computation value needed for control setup]
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
reg		[2:0]	stencilMode;

// [Control bit]

wire isNewBlockPixel;

// --------------------------------------------------------------------------------------------
//   [END] CPU TO VRAM STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

reg				stencilReadSigW; // USED ONLY WHEN READING THE STENCIL ON TARGET BEFORE A WRITE LATER.

wire allowNextRead = (!isLastSegment) | isLongLine;
wire isPalettePrimitive = (!GPU_REG_TexFormat[1]) & bUseTexture;


// --------------------------------------------------------------------------------------------
//   VRAM TO CPU : STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------

wire        memReadPairValid;
wire [31:0] memReadPairValue;

wire [31:0] pairPixelToCPU;
wire		writeFIFOOut;

wire nextPairIsLineLast = (nextPixelX == XE);
wire currPairIsLineLast = (pixelX     == XE);
wire readPairFromVRAM;
wire hasReadSpace;


// [Sub State machine for VC Copy command]
gpu_SM_CopyVC gpu_SM_CopyVC_instance(
	.clk				(clk),
	.nRst				(i_nrst),

	.i_activate			(activateCopy & bIsCopyVCCommand),
	.o_active			(isCopyVCActive),
	.o_exitSig			(inactiveCopyVCNextCycle),
	
	// Control
	.isWidthNot1		(WidthNot1),
	.xb_0				(RegX0[0]),
	.wb_0				(RegSizeW[0]),
	
	.endVertical		(endVertical),
	.nextPairIsLineLast	(nextPairIsLineLast),
	.currPairIsLineLast	(currPairIsLineLast),

	.o_nextX			(selNextX_VC),
	.o_nextY			(selNextY_VC),
	.o_memoryCommand	(memoryCommand_VC),

	// From Memory System
	.o_read				(readPairFromVRAM),	// To
	.i_readACK			(memReadPairValid),	// From
	.i_readPairValue	(memReadPairValue), // From

	// To FIFO
    .canNearPush		(1'b0),
	.i_canPush			(!outFIFO_full & hasReadSpace),
	.i_outFIFO_empty	(outFIFO_empty),
	.o_writeFIFOOut 	(writeFIFOOut),
	.o_pairPixelToCPU	(pairPixelToCPU)
);

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
    .wr_en_i		(writeFIFOOut),

    .rd_data_o		(outFIFO_readV),
    .rd_en_i		(outFIFO_read),

    .full_o			(outFIFO_full),
    .empty_o		(outFIFO_empty)
);

//--------------------------------------------------------------------
// Work State machine
//--------------------------------------------------------------------
reg endClutLoading,decClutCount,requClutCacheUpdate;
wire isLoadingPalette, stillRemainingClutPacket;

wire [2:0]	activateRender;
wire		activateCopy;

wire renderInactiveNextCycle,inactiveCopyCVNextCycle,inactiveCopyVCNextCycle,inactiveCopyVVNextCycle,waitWork;

gpu_workDispatch gpu_workDispatch_instance(
	.i_clk						(clk),
	.i_rst						(rstGPU | rstCmd),

	// ------------------------------------
	//    Control sub states.
	// ------------------------------------
	// Set when starting new work.
	.i_issuePrimitive			(issuePrimitive),
	// Message to sub state machines...
	.o_activateRender			(activateRender),
	.o_activateCopy				(activateCopy),
	// When sub complete
	.i_renderInactiveNextCycle	(renderInactiveNextCycle),
	.i_inactiveCopyCVNextCycle	(inactiveCopyCVNextCycle),
	.i_inactiveCopyVCNextCycle	(inactiveCopyVCNextCycle),
	.i_inactiveCopyVVNextCycle	(inactiveCopyVVNextCycle),

	// ------------------------------------
	//   Parameters
	// ------------------------------------
	// Current Command type
	.i_bIsPerVtxCol				(bIsPerVtxCol),
	.i_bUseTexture				(bUseTexture),
	.i_bIsCopyVVCommand			(bIsCopyVVCommand),
	.i_bIsCopyCVCommand			(bIsCopyCVCommand),
	
	.o_StencilMode				(stencilMode),					// Control for Stencil Cache
	.o_waitWork					(waitWork)						// Assign to ,, , , 
);

assign setInterCounter		= waitWork;
assign setFirstPixel		= waitWork;
assign assignRectSetup		= waitWork;
assign resetDir				= waitWork;

gpu_SM_CopyVV gpu_SM_CopyVV_instance(
	.i_clk						(clk),
	.i_rst						(rstGPU | rstCmd),

	.i_maskSegmentRead			(maskRead16),
	.i_stencilReadValue16		(stencilReadValue16),

	.i_commandFIFOaccept		(commandFIFOaccept),
	.i_allowNextRead			(allowNextRead),
	.i_isDoubleLoad				(isDoubleLoad),
	.i_performSwitch			(performSwitch),
	.i_isLastSegment			(isLastSegment),
	.i_isLastSegmentDst			(isLastSegmentDst),
	.i_endVertical				(endVertical),

	.i_activateCopyVV			(activateCopy & bIsCopyVVCommand),
	.o_CopyInactiveNextCycle	(inactiveCopyVVNextCycle),
	.o_active					(isCopyVVActive),
	
	.o_loadNext					(loadNext_VV),
	.o_selNextX					(selNextX_VV),
	.o_selNextY					(selNextY_VV),
	.o_memoryCommand			(memoryCommand_VV),
	
	.o_resetXCounter			(resetXCounter_VV),
	.o_incrementXCounter		(incrementXCounter_VV),
	.o_stencilReadSig			(stencilReadSig_VV),
	.o_writeStencil				(writeStencil_VV),
	.o_cpyBank					(cpyBank),
	.o_useDest					(useDest),
	.o_clearOtherBank			(clearOtherBank),
	.o_stencilReadSigW			(stencilReadSigW),
	.o_clearBank0				(clearBank0),
	.o_clearBank1				(clearBank1),
	
	.o_maskReadCache			(maskReadCache),
	.o_stencilReadCache			(stencilReadCache)
);

wire lineStart;
gpu_SM_render gpu_SM_render_instance(
	.i_clk						(clk),
	.i_rst						(rstGPU | rstCmd),

	// Parameters
	.i_bUseTexture				(bUseTexture),
	.i_bIsRectCommand			(bIsRectCommand),
	.i_bIsPolyCommand			(bIsPolyCommand),
	
	// Control
	.i_activateRender			(activateRender),
	.o_renderInactiveNextCycle	(renderInactiveNextCycle),
	
	.o_lineStart				(lineStart),

	// Can we push memory commands ?
	.i_commandFIFOaccept		(commandFIFOaccept),

	.i_saveLoadOnGoing			(saveLoadOnGoing),
	.i_pixelInFlight			(pixelInFlight),

	.o_incrementInterpCounter	(incrementInterpCounter),
	.i_endInterpCounter			(endInterpCounter),

	.i_isLoadingPalette			(isLoadingPalette),
	.i_stillRemainingClutPacket	(stillRemainingClutPacket),
	.o_requClutCacheUpdate		(requClutCacheUpdate),
	.o_decClutCount				(decClutCount),				// Same signal AS requClutCacheUpdate
	.i_isPalettePrimitive		(isPalettePrimitive),		// Could just reset always ?
	.o_endClutLoading			(endClutLoading),			// May be avoid using i_isPalettePrimitive ?

	.o_writeStencil				(writeStencil_RDR),
	.o_loadNext					(loadNext_RDR),
	.o_selNextX					(selNextX_RDR),
	.o_selNextY					(selNextY_RDR),
	.o_memoryCommand			(memoryCommand_RDR),
	
	.o_resetXCounter			(resetXCounter_RDR),
	.o_incrementXCounter		(incrementXCounter_RDR),
	.o_stencilReadSig			(stencilReadSig_RDR),
	.o_setPixelFound			(setPixelFound),
	.o_memorizeLineEqu			(memorizeLineEqu),
	.o_switchDir				(switchDir),
	.o_writePixelL				(writePixelL),
	.o_writePixelR				(writePixelR),
	.o_setDirectionComplete		(setDirectionComplete),
	.o_resetPixelFound			(resetPixelFound),
	.o_flush					(flush_RDR),

	//-----------------------------------------
	// Current pixel pair
	//-----------------------------------------
	.i_isValidPixelL			(isValidPixelL),
	.i_isValidPixelR			(isValidPixelR),
	
	//-----------------------------------------
	// Scan/Geometry feedback
	//-----------------------------------------
	// Fill
	.i_emptySurface				(emptySurface),
	.i_isLastSegment			(isLastSegment),
	.i_endVertical				(endVertical),

	// Triangles / Rect
	.i_earlyTriangleReject		(earlyTriangleReject),		// Gather outside and make single input ?
	.i_isNULLDET				(isNULLDET),

	// Check that TRIANGLE EDGE did not SWITCH between the LEFT and RIGHT side of the bounding box.
	.i_outsideTriangle			(edgeDidNOTSwitchLeftRightBB && ((!maxTriDAX1[0] && !isValidPixelL) || (maxTriDAX1[0] && !isValidPixelR))),

	.i_isNegXAxis				(isNegXAxis),
	.i_isNegPreB				(isNegPreB),
	.i_isValidHorizontalTriBbox	(isValidHorizontalTriBbox),
	.i_isBottomInsideBBox		(isBottomInsideBBox),
	.i_pixelFound				(pixelFound),
	.i_requestNextPixel			(requestNextPixel),
	.GPU_REG_CheckMaskBit		(GPU_REG_CheckMaskBit),
	.stencilReadValue			(stencilReadValue),
	.i_reachEdgeTriScan			(reachEdgeTriScan),
	.i_completedOneDirection	(completedOneDirection),

	.i_isInsideBBoxTriRectL		(isInsideBBoxTriRectL),
	.i_isInsideBBoxTriRectR		(isInsideBBoxTriRectR),
	.i_isRightPLXmaxTri			(isRightPLXmaxTri),

	// NON INTERLACED OR INTERLACE BUT VALID AREA
			
	
	.i_isValidLinePixel			(
									(isLineInsideDrawArea 																			// VALID AREA
									&& ((!InterlaceRender)    || (InterlaceRender && (GPU_REG_CurrentInterlaceField != pixelY[0])))	// NON INTERLACED OR INTERLACE BUT VALID AREA
									&& ((GPU_REG_CheckMaskBit && (!selectPixelWriteMaskLine)) || (!GPU_REG_CheckMaskBit)))
								),

	.i_isLineLeftPix			(isLineLeftPix),
	.i_isLineRightPix			(isLineRightPix),
	.i_endPixelLine				((pixelX == RegX1) && (pixelY == RegY1))
);


gpu_SM_CopyCV gpu_SM_CopyCV_instance(
	.i_clk						(clk),
	.i_rst						(rstGPU | rstCmd),

	.i_activateCopyCV			(activateCopy & bIsCopyCVCommand),
	.o_CopyInactiveNextCycle	(inactiveCopyCVNextCycle),
	.o_active					(isCopyCVActive),
	
	.i_RegX0_0					(RegX0[0]),
	.i_pixelY_0					(pixelY[0]),
	.i_nextPixelY_0				(nextPixelY[0]),
	.i_RegSizeW_0				(RegSizeW[0]),
	.i_RegSizeH_0				(RegSizeH[0]),
	.i_WidthNot1				(WidthNot1),
	.i_endVertical				(endVertical),

	.i_canReadL					(!isFifoEmptyLSB),
	.i_canReadM					(!isFifoEmptyMSB),
	.i_nextPairIsLineLast		(nextPairIsLineLast),
	.i_commandFIFOaccept		(commandFIFOaccept),
                         
	.o_loadNext					(loadNext_CV),
	.o_selNextX					(selNextX_CV),
	.o_selNextY					(selNextY_CV),
	.o_memoryCommand			(memoryCommand_CV),
                         
	.o_swap						(swap),			// FIFO swap
	.o_stencilReadSig			(stencilReadSig_CV),
	.o_writeStencil				(writeStencil_CV),
	.o_flush					(flush_CV),
	.o_saveL					(saveL),
	.o_saveM					(saveM),
	
	.o_readL					(readL),
	.o_readM					(readM)
);

StencilCache StencilCacheInstance(
    .clk					(clk),

    .fullMode				(stencilFullMode),
    .writeValue16			(stencilMode[2] ? stencilWValueCpy : 16'd0),	// For now... FILL ONLY.
    .writeMask16			(stencilMode[2] ? stencilWMaskCpy  : 16'hFFFF),	// For now... FILL ONLY.
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
                                             : { isCopyCVActive ? nextScrY[8:0] : nextPixelY[8:0], nextPixelX[9:4] };		// Other modes.
assign stencilReadPair		= { nextPixelX[3:1] };						//
// Select 11 for other primitives, or the correct pixel for the read for LINES.
assign stencilReadSelect	= { !bIsLineCommand | nextPixelX[0] , !bIsLineCommand | (!nextPixelX[0]) };

// [BYTE PIXEL ADR FROM X/Y]
// YYYY.YYYY.YXXX.XXXX.XXX0 Byte.
// YYYY.YYYY.YXXX.XXX_.____ {

assign selectPixelWriteMaskLine = (!pixelX[0] & stencilReadValue[0]) | (pixelX[0] & stencilReadValue[1]);

// TODO OPTIMIZE : can probably compute nextCondUseFIFO outside with : (nextLogicalState != WAIT_COMMAND_COMPLETE) & (nextLogicalState != DEFAULT_STATE)
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


wire  [14:0]	adrClutCacheUpdate;
wire   [3:0]	currentClutBlockWrite;

//wire clutLoading;
gpu_clutManager clutManagerInstance (
	.i_clk					(clk),
	.i_rstGPU				(rstGPU),

	// [Parser Timing]
	.i_setClutLoading		(loadClutPage),
		.i_rstTextureCache		(rstTextureCache),
		.i_fifoDataOutClut		(fifoDataOut[30:16]),

	.i_isPalettePrimitive	(isPalettePrimitive),

	// [Palette loading Timing]
	// --- Start ---
	.i_issuePrimitive		(issuePrimitive != NO_ISSUE),	// TODO : look if can't optimize with setClutLoading and also i_is4BitPalette
		.i_CLUTIs8BPP			(CLUTIs8BPP),

	// --- Loop ---
	.i_decClutCount			(decClutCount),
	.o_stillRemainingClutPacket (stillRemainingClutPacket),

	// --- End
	.i_endClutLoading		(endClutLoading),
		.i_is4BitPalette		(GPU_REG_TexFormat == PIX_4BIT),
//	.o_isClutLoading		(clutLoading),
	
	// CLUT Memory adress for current clut block request.
	.o_adrClutCacheUpdate	(adrClutCacheUpdate),
	.o_isLoadingPalette		(isLoadingPalette),
	.o_currentClutBlock		(currentClutBlockWrite)
);

// ------------------------------------------------
CLUT_Cache CLUT_CacheInst(
    .i_clk					(clk),
    .i_nrst					(i_nrst),

    .i_write				(ClutCacheWrite),
    .i_writeBlockIndex		(currentClutBlockWrite),
    .i_writeIdxInBlk		(ClutWriteIndex),
    .i_Colors				(ClutCacheData),

    .i_readIdxL				(indexPalL),
    .o_colorEntryL			(dataClut_c2L),

    .i_readIdxR				(indexPalR),
    .o_colorEntryR			(dataClut_c2R)
);

// ------------------------------------------------
// wire [31:0]		readValue32;
// wire            dataArrived;
// wire			dataConsumed;

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
    .updateClutCacheComplete(/* DEPRECATED : updateClutCacheComplete*/),

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

