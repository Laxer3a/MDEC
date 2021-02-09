/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
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
    (
    input			clk,
    input			i_nrst,

    // --------------------------------------
    // DIP Switches to control
	input			DIP_AllowDither,
	input			DIP_ForceDither,
	input			DIP_Allow480i,
	input           DIP_ForceInterlaceField,
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
	
//	output	[31:0]	mydebugCnt,
//	output          dbg_canWrite,

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
    output reg         o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input              i_busy,           // Memory busy 1 => can not use.
    output reg [1:0]   o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output reg         o_write,          // 0=READ / 1=WRITE 
    output reg [14:0]  o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output reg [2:0]   o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output reg [15:0]  o_writeMask,

    input  [255:0]     i_dataIn,
    input              i_dataInValid,
    output reg [255:0] o_dataOut,
	
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

//---------------------------------------------------------------
//  REGISTERS
//---------------------------------------------------------------
// Note : we do not have the problem of over transfer in FIFO IN, as DMA know transfer size.
// But in case we still REQ and DMA was reloaded super fast, we would need to put a COUNTER in the GPU
// that would compute size based on command parameters instead of this check...
// wire reqDataDMAIn	= (currWorkState == COPYCV_START) || (currWorkState == COPYCV_COPY);
// wire reqDataDMAOut  = (currWorkState == COPYVC_TOCPU);
//                      CPU to VRAM transfer + in transfer state + FIFO has space to store data.
//                      => Should not overtransfer because DMA knows size.
// DMA REQ
wire       			GPU_REG_IsInterlaced;
wire       			GPU_REG_BufferRGB888;
wire       			GPU_REG_VideoMode;
wire       			GPU_REG_VerticalResolution;
wire [1:0] 			GPU_REG_HorizResolution;
wire       			GPU_REG_HorizResolution368;
wire				GPU_REG_ReverseFlag;
wire       			GPU_REG_DisplayDisabled;
wire				GPU_REG_DrawDisplayAreaOn;

wire [9:0]			GPU_REG_DispAreaX;
wire [8:0]			GPU_REG_DispAreaY;
wire [11:0]			GPU_REG_RangeX0;
wire [11:0]			GPU_REG_RangeX1;
wire [9:0]			GPU_REG_RangeY0;
wire [9:0]			GPU_REG_RangeY1;

wire [1:0]      	GPU_REG_DMADirection;

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

//---------------------------------------------------------------
// HBLANK rising edge detect
//---------------------------------------------------------------
reg display_hblank_q;

always @ (posedge clk)
if (!i_nrst)
    display_hblank_q <= 1'b0;
else
    display_hblank_q <= display_hblank_i;

wire start_of_hblank_w = display_hblank_i & ~display_hblank_q;

//===============================================================
//  Ultra Temporary/Hack Display Module
//===============================================================
wire VBlank = display_vblank_i;

// NOTE: GPU render frame is the opposite to the display field
wire GPU_REG_CurrentInterlaceField = DIP_ForceInterlaceField ? 1'b0 : ~display_field_i;

// Generate odd even line status bit
reg currentLineOddEven;

always @ (posedge clk)
if (!i_nrst)
    currentLineOddEven <= 1'b0;
else if (display_vblank_i)
    currentLineOddEven <= 1'b0;
else if (start_of_hblank_w)
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

//---------------------------------------------------------------
// Plumbing + Helper Logic Equations
//---------------------------------------------------------------

// From Command Decoder
//---------------------------------------------------------------
wire bIsLineCommand,bIsCopyCommand,bIsPolyCommand,bIsRectCommand,bIsCopyVVCommand,bIsCopyVCCommand,bIsCopyCVCommand,bUseTextureParser,bSemiTransp,bOpaque,bIsPerVtxCol;
wire bUseTexture = bUseTextureParser & (!GPU_REG_TextureDisable); // Avoid texture fetching if we do LINE, Compute proper color for FILL.

// From parser
//---------------------------------------------------------------
wire loadVertices,loadUV,loadRGB,loadAllRGB,loadCoord1,loadCoord2,loadSize,loadRectEdge;
wire rstTextureCache,loadE5Offsets,loadTexPageE1,loadTexWindowSetting,loadDrawAreaTL,loadDrawAreaBR,loadMaskSetting,setIRQ,loadClutPage,loadTexPage;
wire [1:0] loadSizeParam;
wire [4:0] issuePrimitive;
wire readFifo;
wire [1:0] vertexID;
wire isVertexLoadState;
wire parserWaitingNewCommand;

wire storeCommand;
reg [7:0] RegCommand;
always @(posedge clk)
	if (storeCommand) RegCommand <= command;
wire [7:0] command			= storeCommand ? fifoDataOut[31:24] : RegCommand;

// From INPUT Fifo
//---------------------------------------------------------------
wire        inst_fifo_space_w;
wire        inst_fifo_ready_w;
wire [31:0] inst_fifo_data_out_w;
wire        inst_fifo_pop_w;

wire [31:0] fifoDataOut;
wire        accept_cv_data_w;
wire        canWriteFIFO	= inst_fifo_space_w;
wire        writeFifo		= (!gpuAdrA2 & gpuSel & write & canWriteFIFO) || (gpu_m2p_valid_o && (GPU_REG_DMADirection == DMA_CPUtoGP0));

wire        isFifoEmpty32  = ~inst_fifo_ready_w;

// Command parser / cpu2vram can pop FIFO
assign      inst_fifo_pop_w = readFifo | accept_cv_data_w;

// From OUTPUT Fifo (vram->cpu/dma)
//---------------------------------------------------------------
wire        vc_pixels_valid_w;
wire [31:0] vc_pixels_data_w;
wire        vc_pixels_pop_w;

wire        cpuReadFifoOut = (gpuSel & !gpuAdrA2) & read;

// Pop the vram->cpu FIFO if sending to the DMA (and it accepts) or when the CPU reads the data
assign      vc_pixels_pop_w = ((GPU_REG_DMADirection == DMA_GP0toCPU) && gpu_p2m_accept_o) || cpuReadFifoOut;

// From IRQ Module
//---------------------------------------------------------------
wire GPU_REG_IRQSet;
assign IRQRequest = GPU_REG_IRQSet;

// From Front-End
//---------------------------------------------------------------
wire rstGPU,rstCmd,rstIRQ;

// From Vertex Register/Loader
//---------------------------------------------------------------
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
wire [10:0] RegSizeW;
wire [ 9:0] RegSizeH;

// From Work Dispatch
//---------------------------------------------------------------
wire waitWork;
wire [2:0]	activateRender;
wire		activateCopy;
wire		activateFill;

// From Stencil Cache
//---------------------------------------------------------------
wire [15:0]	stencilReadValue16;

// From Render Block
//---------------------------------------------------------------
wire inactiveRenderNextCycle;
wire isRenderActive;
wire rdr_stencilReadSig,rdr_stencilWriteSig;
wire [14:0] rdr_stencilWriteAdr,rdr_stencilReadAdr;
wire [15:0]	rdr_stencilWriteValue,rdr_stencilWriteMask;

// I/F memory system
wire rdr_mem_command,rdr_mem_busy,rdr_mem_write,rdr_mem_dataInValid;
wire  [1:0] rdr_mem_commandSize;
wire [15:0] rdr_mem_writeMask;
wire [14:0] rdr_mem_adr;
wire  [2:0] rdr_mem_subadr;
wire [255:0] rdr_mem_dataIn,rdr_mem_dataOut;

// From Copy VV Block
//---------------------------------------------------------------
wire isCopyVVActive,inactiveCopyVVNextCycle;
wire vv_stencilReadSig,vv_stencilWrite;
wire [14:0] vv_stencilWriteAdr,vv_stencilReadAdr;
wire [15:0] vv_stencilWriteValue16,vv_stencilWriteMask16;

// I/F memory system
wire vv_mem_command,vv_mem_busy,vv_mem_write,vv_mem_dataInValid;
wire  [1:0] vv_mem_commandSize;
wire [15:0] vv_mem_writeMask;
wire [14:0] vv_mem_adr;
wire  [2:0] vv_mem_subadr;
wire [255:0] vv_mem_dataIn,vv_mem_dataOut;

// From Copy VC Block
//---------------------------------------------------------------
wire isCopyVCActive;
wire inactiveCopyVCNextCycle;

wire vc_mem_command,vc_mem_busy,vc_mem_write;
wire  [1:0] vc_mem_commandSize;
// wire [15:0] cv_mem_writeMask;
wire [14:0] vc_mem_adr;
wire  [2:0] vc_mem_subadr;
wire [255:0] vc_mem_dataIn;
wire         vc_mem_dataInValid;

// From Copy CV Block
//---------------------------------------------------------------
wire isCopyCVActive,inactiveCopyCVNextCycle;
wire cv_stencilReadSig,cv_stencilWriteSig;
wire [14:0] cv_stencilWriteAdr,cv_stencilReadAdr;
wire [15:0] cv_stencilWriteMask16,cv_stencilWriteValue16;

// I/F memory system
wire cv_mem_command,cv_mem_busy,cv_mem_write;
wire  [1:0] cv_mem_commandSize;
wire [15:0] cv_mem_writeMask;
wire [14:0] cv_mem_adr;
wire  [2:0] cv_mem_subadr;
wire [255:0] cv_mem_dataOut;

// From Copy FILL Block
//---------------------------------------------------------------
wire isFILLActive,inactiveFILLNextCycle;
wire fl_stencilReadSig,fl_stencilWriteSig;
wire [14:0] fl_stencilWriteAdr;
wire [15:0] fl_stencilWriteMask16,fl_stencilWriteValue16;

// I/F memory system
wire fl_mem_command,fl_mem_busy,fl_mem_write;
wire  [1:0] fl_mem_commandSize;
wire [15:0] fl_mem_writeMask;
wire [14:0] fl_mem_adr;
wire  [2:0] fl_mem_subadr;
wire [255:0] fl_mem_dataOut;


//---------------------------------------------------------------
// DMA CONTROL SIGNALS
//---------------------------------------------------------------
reg	   dmaDataRequest; // Bit 25
wire   gpuReadySendToCPU;

assign gpu_m2p_dreq_i   = (GPU_REG_DMADirection == DMA_CPUtoGP0) && isFifoEmpty32;
assign gpu_m2p_accept_i = inst_fifo_space_w;

assign gpu_p2m_dreq_i  = (GPU_REG_DMADirection == DMA_GP0toCPU) && vc_pixels_valid_w;
assign gpu_p2m_valid_i = gpu_p2m_dreq_i;
assign gpu_p2m_data_i  = vc_pixels_data_w;

//---------------------------------------------------------------
// FRONT END
//---------------------------------------------------------------

gpu_irq IRQModule_inst (
	.i_clk							(clk),
	.i_rstIRQ						(rstGPU | rstIRQ),
	.i_setIRQ						(setIRQ),
	.o_irq							(GPU_REG_IRQSet)
);


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
	
	.i_useVCCopyFIFOOut				(isCopyVCActive),
	.i_valueVCCopyFIFOOut			(vc_pixels_data_w),
	
	//-------------------------------------------------------
	//  Inputs
	//-------------------------------------------------------
	.i_statusBit31					(GPU_DisplayEvenOddLinesInterlace),
	.i_statusBit28					(isFifoEmpty32),
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
	.o_GPU_REG_DMADirection			(GPU_REG_DMADirection),

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

wire        inst_fifo_push_w   = writeFifo;
wire [31:0] inst_fifo_data_w   = gpu_m2p_valid_o ? gpu_m2p_data_o : cpuDataIn;

gpu_mem_fifo
#(
     .WIDTH(32)
    ,.DEPTH(16)
    ,.ADDR_W(4)
)
Fifo_inst
(
     .clk_i(clk)
    ,.rst_i(rstGPU | rstCmd)

    ,.push_i(inst_fifo_push_w)
    ,.data_in_i(inst_fifo_data_w)
    ,.accept_o(inst_fifo_space_w)

    ,.valid_o(inst_fifo_ready_w)
    ,.data_out_o(inst_fifo_data_out_w)
    ,.pop_i(inst_fifo_pop_w)
);

assign fifoDataOut = {32{inst_fifo_ready_w}} & inst_fifo_data_out_w;

assign gpuReadySendToCPU = vc_pixels_valid_w 
								/* && copyVCActive DONT USE IT*/;	// Bit 27
		/* Specs says that Gets set after sending GP0(C0h) and its parameters.
		   So we could rely on the state machine... BUT in the case we push data and the state machine ends, the last DATA state in the FIFO ain't visible
		   anymore to outside. Very dangerous.
		   
		   Moreover, that FIFO is only for the C0 command ANYWAY. So we just use the VC data ready flag and it is OK.
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

gpu_commandDecoder commandDecoderInstance(
	.i_command						(command),
		
	.o_bIsBase0x					(),
	.o_bIsBase01					(),
	.o_bIsBase02					(),
	.o_bIsBase1F					(),
	.o_bIsPolyCommand				(bIsPolyCommand),
	.o_bIsRectCommand				(bIsRectCommand),
	.o_bIsLineCommand				(bIsLineCommand),
	.o_bIsMultiLine					(),
	.o_bIsForECommand				(),
	.o_bIsCopyVVCommand				(bIsCopyVVCommand),
	.o_bIsCopyCVCommand				(bIsCopyCVCommand),
	.o_bIsCopyVCCommand				(bIsCopyVCCommand),
	.o_bIsCopyCommand				(bIsCopyCommand),
	.o_bIsFillCommand				(),
	.o_bIsRenderAttrib				(),
	.o_bIsNop						(),
	.o_bIsPolyOrRect				(),
	.o_bUseTextureParser			(bUseTextureParser),
	.o_bSemiTransp					(bSemiTransp),
	.o_bOpaque						(bOpaque),
	.o_bIs4PointPoly				(),
	.o_bIsPerVtxCol					(bIsPerVtxCol),
	.o_bIgnoreColor					()
);


// ------------------------------------------------------------------------------------------
//   PARSER & PARSE REGISTER LOADING
// ------------------------------------------------------------------------------------------

// End line command if special marker or SECOND vertex when not a multiline command...
wire bIsTerminator			= (fifoDataOut[31:28] == 4'd5) & (fifoDataOut[15:12] == 4'd5);

gpu_parser gpu_parser_instance(
	.i_clk							(clk),
	.i_rstGPU						(rstGPU),	// Reset Signal or Reset Command GP1
	
	.i_command						(command),
	.o_waitingNewCommand			(parserWaitingNewCommand),

	.i_gpuBusy						(!waitWork),
	.o_issuePrimitive				(issuePrimitive),

	// Request data to parse
	.o_readFIFO						(readFifo),

	// Valid data from previous request
	.i_dataValid					(inst_fifo_ready_w),
	.i_bIsTerminator				(bIsTerminator),
	
	//================================================
	// Control signals
	//================================================
	.o_storeCommand					(storeCommand		),
	// To Register loading
	//------------------------------------------------
	.o_vertexID						(vertexID			),
	.o_loadVertices					(loadVertices		),
	.o_loadUV						(loadUV				),
	.o_loadRGB						(loadRGB			),
	.o_loadAllRGB					(loadAllRGB			),
	.o_loadCoord1					(loadCoord1			),
	.o_loadCoord2					(loadCoord2			),
	.o_loadSize						(loadSize			),
	.o_loadSizeParam				(loadSizeParam		),
	.o_loadRectEdge					(loadRectEdge		),
	.o_isVertexLoadState			(isVertexLoadState	),

	.o_rstTextureCache				(rstTextureCache	),
	.o_loadE5Offsets				(loadE5Offsets		),
	.o_loadTexPageE1				(loadTexPageE1		),
	.o_loadTexWindowSetting			(loadTexWindowSetting),
	.o_loadDrawAreaTL				(loadDrawAreaTL		),
	.o_loadDrawAreaBR				(loadDrawAreaBR		),
	.o_loadMaskSetting				(loadMaskSetting	),
	.o_setIRQ						(setIRQ				),
	.o_loadClutPage					(loadClutPage		),
	.o_loadTexPage					(loadTexPage		)
);

gpu_loadedRegs gpu_vertexRegisters(
	.i_clk							(clk),
	
	//-----------------------------------------
	// DATA IN (Parser control the input)
	//-----------------------------------------
	// Data From FIFO
	.i_validData					(inst_fifo_ready_w),
	.i_data							(fifoDataOut),
	.i_command						(command),
	//-----------------------------------------
	// Vertex Control (TARGET)
	.i_targetVertex					(vertexID),	// 0..2
	
	.i_bUseTexture					(bUseTexture),
	
	//-----------------------------------------
	// OPERATION (set when i_validData VALID)
	//-----------------------------------------
	.i_loadVertices					(loadVertices	),
	.i_loadUV						(loadUV			),
	.i_loadRGB						(loadRGB		),
	.i_loadAllRGB					(loadAllRGB		),
	.i_loadCoord1					(loadCoord1		),
	.i_loadCoord2					(loadCoord2		),
		
	.i_loadSize						(loadSize		),
	.i_loadSizeParam				(loadSizeParam	),
		
	.i_loadRectEdge					(loadRectEdge	),
	.i_isVertexLoadState			(isVertexLoadState),
	
	//-----------------------------------------
	// Parameters for internal xform
	//-----------------------------------------
	.i_GPU_REG_TextureDisable
									(GPU_REG_TextureDisable),
	// [Data from General GPU Registers needed when loading vertices]
	.i_GPU_REG_OFFSETX				(GPU_REG_OFFSETX),
	.i_GPU_REG_OFFSETY				(GPU_REG_OFFSETY),
			
	.o_RegX0						(RegX0),
	.o_RegY0						(RegY0),
	.o_RegR0						(RegR0),
	.o_RegG0						(RegG0),
	.o_RegB0						(RegB0),
	.o_RegU0						(RegU0),
	.o_RegV0						(RegV0),
	.o_RegX1						(RegX1),
	.o_RegY1						(RegY1),
	.o_RegR1						(RegR1),
	.o_RegG1						(RegG1),
	.o_RegB1						(RegB1),
	.o_RegU1						(RegU1),
	.o_RegV1						(RegV1),
	.o_RegX2						(RegX2),
	.o_RegY2						(RegY2),
	.o_RegR2						(RegR2),
	.o_RegG2						(RegG2),
	.o_RegB2						(RegB2),
	.o_RegU2						(RegU2),
	.o_RegV2						(RegV2),
	.o_RegSizeW						(RegSizeW),
	.o_RegSizeH						(RegSizeH),
	.o_OriginalRegSizeH				(/*OriginalRegSizeH [DEPRECATED]*/) // TODO Remove from module later...
);

// ------------------------------------------------------------------------------------------
//   Work dispatch
// ------------------------------------------------------------------------------------------

gpu_workDispatch gpu_workDispatch_instance(
	.i_clk							(clk),
	.i_rst							(rstGPU | rstCmd),

	// ------------------------------------
	//    Control sub states.
	// ------------------------------------
	// Set when starting new work.
	.i_issuePrimitive				(issuePrimitive),
	// Message to sub state machines...
	.o_activateRender				(activateRender),
	.o_activateFill					(activateFill),
	.o_activateCopy					(activateCopy),
		
	// When sub complete	
	.i_renderInactiveNextCycle		(inactiveRenderNextCycle),
	.i_inactiveCopyCVNextCycle		(inactiveCopyCVNextCycle),
	.i_inactiveCopyVCNextCycle		(inactiveCopyVCNextCycle),
	.i_inactiveCopyVVNextCycle		(inactiveCopyVVNextCycle),
	.i_inactiveFillNextCycle		(inactiveFILLNextCycle),

	// ------------------------------------
	//   Parameters
	// ------------------------------------
	// Current Command type
	.i_bIsPerVtxCol					(bIsPerVtxCol),
	.i_bUseTexture					(bUseTexture),
	.i_bIsCopyVVCommand				(bIsCopyVVCommand),
	.i_bIsCopyCVCommand				(bIsCopyCVCommand),

// DEPRECATED FOR NOW
//	.o_StencilMode					(stencilMode),					// Control for Stencil Cache
	.o_waitWork						(waitWork)						// Assign to ,, , , 
);


// ------------------------------------------------------------------------------------------
//   5 Modules :
//		- Copy CV
//		- Copy VC
//		- Copy VV
//		- FILL
//		- Render Primitive
// ------------------------------------------------------------------------------------------

// ------------------------------------------------------------------------------------------
//		- Copy VC
// ------------------------------------------------------------------------------------------
gpu_SM_CopyVC_mem gpu_SM_CopyVC_mem_instance(
	.i_clk							(clk),
	.i_rst							(!i_nrst),

	.i_activate						(activateCopy & bIsCopyVCCommand),
	.o_exitSig						(inactiveCopyVCNextCycle),
	.o_active						(isCopyVCActive),

	.RegX0							(RegX0),
	.RegY0							(RegY0),
	.RegSizeW						(RegSizeW),
	.RegSizeH						(RegSizeH),

	.o_writeFIFOOut					(vc_pixels_valid_w),
	.o_pairPixelToCPU				(vc_pixels_data_w),
	.i_popPixelPair  				(vc_pixels_pop_w),
			
    .o_command						(vc_mem_command),
    .i_busy							(vc_mem_busy),
    .o_commandSize					(vc_mem_commandSize),
			
    .o_write						(vc_mem_write),
    .o_adr							(vc_mem_adr),
    .o_subadr						(vc_mem_subadr),
    .o_writeMask					(),
			
    .i_dataIn						(vc_mem_dataIn),
    .i_dataInValid					(vc_mem_dataInValid),
    .o_dataOut						()
);

// ------------------------------------------------------------------------------------------
//		- Copy CV
// ------------------------------------------------------------------------------------------

gpu_SM_CopyCV_mem gpu_SM_CopyCV_mem_instance(
	.i_clk							(clk),
	.i_rst							(rstGPU | rstCmd),

	.i_activateCopyCV				(activateCopy & bIsCopyCVCommand),
	.o_CopyInactiveNextCycle		(inactiveCopyCVNextCycle),
	.o_active						(isCopyCVActive),

	.GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit),
	.GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet),
	.RegX0							(RegX0),
	.RegY0							(RegY0),
	.RegSizeW						(RegSizeW),
	.RegSizeH						(RegSizeH),

	.o_stencilFullMode				(),
	
	.o_stencilReadSig				(cv_stencilReadSig),
	.o_stencilReadAdr				(cv_stencilReadAdr),
	.i_stencilReadValue				(stencilReadValue16),

	.o_stencilWriteMask16			(cv_stencilWriteMask16),
	.o_stencilWriteValue16			(cv_stencilWriteValue16),
	.o_stencilWriteSig				(cv_stencilWriteSig),
	.o_stencilWriteAdr				(cv_stencilWriteAdr),

	.i_canReadL						(inst_fifo_ready_w),
	.i_canReadM						(inst_fifo_ready_w),
	.o_readL						(accept_cv_data_w),
	.o_readM						(),
	
	.i_fifoDataOutM					(fifoDataOut[31:16]),
	.i_fifoDataOutL					(fifoDataOut[15: 0]),

    .o_command						(cv_mem_command),
    .i_busy							(cv_mem_busy),
    .o_commandSize					(cv_mem_commandSize),
    .o_write						(cv_mem_write),
    .o_adr							(cv_mem_adr),
    .o_subadr						(cv_mem_subadr),
    .o_writeMask					(cv_mem_writeMask),
    .o_dataOut                      (cv_mem_dataOut)
);

// ------------------------------------------------------------------------------------------
//		- Copy VV
// ------------------------------------------------------------------------------------------

gpu_SM_CopyVV_mem gpu_SM_CopyVV_mem_inst(
	.i_clk							(clk),
	.i_rst							(!i_nrst),

	.i_activate						(activateCopy & bIsCopyVVCommand),
	.o_CopyInactiveNextCycle		(inactiveCopyVVNextCycle),
	.o_active						(isCopyVVActive),

	.RegX0							(RegX0),
	.RegX1							(RegX1),
	.RegY0							(RegY0),
	.RegY1							(RegY1),
	.RegSizeW						(RegSizeW),
	.RegSizeH						(RegSizeH),
	.GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit),
	.GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet),

	.i_stencilReadValue16			(stencilReadValue16),
	.o_stencilReadSig				(vv_stencilReadSig),
	.o_stencilWriteSig				(vv_stencilWrite),
	.o_stencilFullMode				(),
	.o_stencilWriteValue16			(vv_stencilWriteValue16),
	.o_stencilWriteMask16			(vv_stencilWriteMask16),

	.o_stencilReadAdr				(vv_stencilReadAdr),
	.o_stencilWriteAdr				(vv_stencilWriteAdr),

    .o_command						(vv_mem_command),       
    .i_busy							(vv_mem_busy),          
    .o_commandSize					(vv_mem_commandSize),   
    .o_write						(vv_mem_write),         
    .o_adr							(vv_mem_adr),           
    .o_subadr						(vv_mem_subadr),        
    .o_writeMask					(vv_mem_writeMask),
    .i_dataIn						(vv_mem_dataIn),
    .i_dataInValid					(vv_mem_dataInValid),
    .o_dataOut                      (vv_mem_dataOut)
);

// ------------------------------------------------------------------------------------------
//		- FILL
// ------------------------------------------------------------------------------------------

gpu_SM_FILL_mem gpu_SM_FILL_mem_inst(
	.i_clk							(clk),
	.i_rst							(!i_nrst),

	.i_InterlaceRender				(InterlaceRender),
	.GPU_REG_CurrentInterlaceField	(GPU_REG_CurrentInterlaceField),
	.RegR0							(RegR0),
	.RegG0							(RegG0),
	.RegB0							(RegB0),
	.RegX0							(RegX0),
	.RegY0							(RegY0),
	.RegSizeW						(RegSizeW),
	.RegSizeH						(RegSizeH),

	.i_activateFILL					(activateFill),
	.o_FILLInactiveNextCycle		(inactiveFILLNextCycle),
	.o_active						(isFILLActive),

	.o_stencilWriteSig				(fl_stencilWriteSig),
	.o_stencilReadSig				(fl_stencilReadSig),
	.o_stencilFullMode				(),
	.o_stencilWriteValue16			(fl_stencilWriteValue16),
	.o_stencilWriteMask16			(fl_stencilWriteMask16),
	.o_stencilWriteAdr				(fl_stencilWriteAdr),

    .o_command						(fl_mem_command),    
    .i_busy							(fl_mem_busy),       
    .o_commandSize					(fl_mem_commandSize),
    .o_write						(fl_mem_write),      
    .o_adr							(fl_mem_adr),        
    .o_subadr						(fl_mem_subadr),     
    .o_writeMask					(fl_mem_writeMask),
    .o_dataOut                      (fl_mem_dataOut)
);

// ------------------------------------------------------------------------------------------
//		- Render
// ------------------------------------------------------------------------------------------

gpu_SM_render_mem gpu_SM_render_mem_inst(
	.i_clk							(clk),
	.i_nrst							(i_nrst),
	.i_rstCmd						(rstCmd),
	.i_rstGPU						(rstGPU),
	.i_rstTextureCache				(rstTextureCache),
	
	//-----------------------------------------
	// Command parser control CLUT internal unit.
	//-----------------------------------------
	.i_loadClutPage					(loadClutPage),
	.i_fifoDataOutClut				(fifoDataOut[30:16]),
		
	//-----------------------------------------
	// GPU Registers & Loaded Registers
	//-----------------------------------------
	.DIP_Allow480i					(DIP_Allow480i					),
	.DIP_AllowDither				(DIP_AllowDither				),
	.DIP_ForceDither				(DIP_ForceDither				),

	.GPU_REG_CurrentInterlaceField	(GPU_REG_CurrentInterlaceField	),
	.GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit			),
	.GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet	),
    .GPU_REG_Transparency			(GPU_REG_Transparency			),
    .GPU_REG_TexFormat				(GPU_REG_TexFormat				),
    .GPU_REG_TexBasePageX			(GPU_REG_TexBasePageX			),
    .GPU_REG_TexBasePageY			(GPU_REG_TexBasePageY			),
    .GPU_REG_TextureXFlip			(GPU_REG_TextureXFlip			),
    .GPU_REG_TextureYFlip			(GPU_REG_TextureYFlip			),
    .GPU_REG_WindowTextureMaskX		(GPU_REG_WindowTextureMaskX		),
    .GPU_REG_WindowTextureMaskY		(GPU_REG_WindowTextureMaskY		),
    .GPU_REG_WindowTextureOffsetX	(GPU_REG_WindowTextureOffsetX	),
    .GPU_REG_WindowTextureOffsetY	(GPU_REG_WindowTextureOffsetY	),
	.GPU_REG_DitherOn				(GPU_REG_DitherOn				),

	.RegX0							(RegX0							),
	.RegY0							(RegY0							),
	.RegR0							(RegR0							),
	.RegG0							(RegG0							),
	.RegB0							(RegB0							),
	.RegU0							(RegU0							),
	.RegV0							(RegV0							),
	.RegX1							(RegX1							),
	.RegY1							(RegY1							),
	.RegR1							(RegR1							),
	.RegG1							(RegG1							),
	.RegB1							(RegB1							),
	.RegU1							(RegU1							),
	.RegV1							(RegV1							),
	.RegX2							(RegX2							),
	.RegY2							(RegY2							),
	.RegR2							(RegR2							),
	.RegG2							(RegG2							),
	.RegB2							(RegB2							),
	.RegU2							(RegU2							),
	.RegV2							(RegV2							),
	.GPU_REG_DrawAreaX0				(GPU_REG_DrawAreaX0				),
	.GPU_REG_DrawAreaY0				(GPU_REG_DrawAreaY0				),
	.GPU_REG_DrawAreaX1				(GPU_REG_DrawAreaX1				),
	.GPU_REG_DrawAreaY1				(GPU_REG_DrawAreaY1				),
	.GPU_REG_DrawDisplayAreaOn		(GPU_REG_DrawDisplayAreaOn		),
	.GPU_REG_IsInterlaced			(GPU_REG_IsInterlaced			),
	.GPU_REG_VerticalResolution		(GPU_REG_VerticalResolution		),
	
	// Command Parser result (can integrate later, just want to build now)
	.i_bUseTexture					(bUseTexture),
	.i_bIsRectCommand				(bIsRectCommand),
	.i_bIsPolyCommand				(bIsPolyCommand),
	.i_bIsLineCommand				(bIsLineCommand),
	.i_bIsPerVtxCol					(bIsPerVtxCol),
	.i_bOpaque						(bOpaque),
	.i_bSemiTransp					(bSemiTransp), // !i_bOpaque ?

	.i_activateRender				(activateRender),
	.o_renderInactiveNextCycle		(inactiveRenderNextCycle),
	.o_active						(isRenderActive),

	// -------------------------------
	//   Stencil Cache Write/Read
	// -------------------------------
	.o_stencilFullMode				(),

	.o_stencilWriteSig				(rdr_stencilWriteSig),
	.o_stencilWriteAdr				(rdr_stencilWriteAdr),
//	.o_stencilWritePair				(rdr_stencilWritePair),
//	.o_stencilWriteSelect			(rdr_stencilWriteSelect),
	.o_stencilWriteValue			(rdr_stencilWriteValue),
	.o_stencilWriteMask				(rdr_stencilWriteMask),

	.o_stencilReadSig				(rdr_stencilReadSig),
	.o_stencilReadAdr				(rdr_stencilReadAdr),
//	.o_stencilReadPair				(rdr_stencilReadPair),
//	.o_stencilReadSelect			(rdr_stencilReadSelect),
	.i_stencilReadValue				(stencilReadValue16),

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    .o_command						(rdr_mem_command),    
    .i_busy							(rdr_mem_busy),       
    .o_commandSize					(rdr_mem_commandSize),
    .o_write						(rdr_mem_write),      
    .o_adr							(rdr_mem_adr),        
    .o_subadr						(rdr_mem_subadr),     
    .o_writeMask					(rdr_mem_writeMask),
    .i_dataIn						(rdr_mem_dataIn),
    .i_dataInValid					(rdr_mem_dataInValid),
    .o_dataOut						(rdr_mem_dataOut)
);

// ------------------------------------------------------------------------------------------
//	- Stencil Cache
//	- Mux Stencil Access
// ------------------------------------------------------------------------------------------

reg [2:0] portMuxID;
reg srcWriteSig,srcReadSig;

reg [15:0] 	stencilWriteValue16,stencilWriteMask16;
reg			stencilWriteSig;

reg [14:0]	stencilWriteAdr;
reg			stencilReadSig;
reg [14:0]	stencilReadAdr;	

parameter	BLK_RENDER	= 3'd0,
			BLK_CV		= 3'd1,
			BLK_VV		= 3'd2,
			BLK_FILL	= 3'd3,
			BLK_VC		= 3'd4;
			
wire useStencilActive = isCopyCVActive | isCopyVVActive | isFILLActive | isRenderActive; // isCopyVCActive does not use stencil.

always @(*) begin
	casez ({isFILLActive,isCopyVVActive,isCopyCVActive,isRenderActive})
	4'b???1 : portMuxID = BLK_RENDER; // Render
	4'b??10 : portMuxID = BLK_CV; // CV
	4'b?100 : portMuxID = BLK_VV; // VV
	default : portMuxID = isCopyVCActive? BLK_VC : BLK_FILL; // Fill with LOCK TRICK. (VC use this path but read/write desactivated)
	endcase

	case (portMuxID)
	BLK_RENDER : begin			// Render
		stencilReadAdr		= rdr_stencilReadAdr;
		stencilWriteMask16	= rdr_stencilWriteMask;
		stencilWriteValue16 = rdr_stencilWriteValue;
		stencilWriteAdr		= rdr_stencilWriteAdr;
		srcWriteSig			= rdr_stencilWriteSig;
		srcReadSig			= rdr_stencilReadSig;
	end
	BLK_CV : begin			// CV
		stencilReadAdr		= cv_stencilReadAdr;
		stencilWriteMask16	= cv_stencilWriteMask16;
		stencilWriteValue16 = cv_stencilWriteValue16;
		stencilWriteAdr		= cv_stencilWriteAdr;
		srcWriteSig			= cv_stencilWriteSig;
		srcReadSig			= cv_stencilReadSig;
	end
	BLK_VV : begin			// VV
		stencilReadAdr		= vv_stencilReadAdr;
		stencilWriteMask16	= vv_stencilWriteMask16;
		stencilWriteValue16 = vv_stencilWriteValue16;
		stencilWriteAdr		= vv_stencilWriteAdr;
		srcWriteSig			= vv_stencilWrite;
		srcReadSig			= vv_stencilReadSig;
	end
	// BKL_VC | BKL_FILL
	default: begin			// Fill or VC...
		stencilReadAdr		= 15'd0; // OPTM dX
		stencilWriteMask16	= fl_stencilWriteMask16;
		stencilWriteValue16	= fl_stencilWriteValue16;
		stencilWriteAdr		= fl_stencilWriteAdr;
		srcWriteSig			= fl_stencilWriteSig;
		srcReadSig			= 0; // fl_stencilReadSig => TRICK : Fill OR VC BOTH DONT READ STENCIL. ( fl_stencilReadSig = 0 )
	end
	endcase

	// Trick : Lock for other module
	stencilWriteSig = useStencilActive & srcWriteSig;	// Desactive write if VC (useStencilActive=0 for VC active).
	stencilReadSig  = srcReadSig;						// Always desactivated for VC case.
end

wire o_stencilError = stencilWriteSig & stencilReadSig & (stencilWriteAdr == stencilReadAdr);

gpu_stencil_cache
StencilCacheInstance
(
	 .clk_i(clk)
	,.rst_i(~i_nrst)

    ,.stencil_rd_req_i(stencilReadSig)
    ,.stencil_rd_addr_i(stencilReadAdr)
    ,.stencil_rd_value_o(stencilReadValue16)

    ,.stencil_wr_req_i(stencilWriteSig)
    ,.stencil_wr_addr_i(stencilWriteAdr)
    ,.stencil_wr_mask_i(stencilWriteMask16)
    ,.stencil_wr_value_i(stencilWriteValue16)
);

// Render
assign rdr_mem_busy			= i_busy;
assign rdr_mem_dataInValid	= i_dataInValid;
assign rdr_mem_dataIn		= i_dataIn;

// Fill, CV write only
assign fl_mem_busy			= i_busy;
assign cv_mem_busy			= i_busy;

// VV Copy
assign vv_mem_busy			= i_busy;
assign vv_mem_dataInValid	= i_dataInValid;
assign vv_mem_dataIn		= i_dataIn;

// VC Copy
assign vc_mem_busy			= i_busy;
assign vc_mem_dataInValid	= i_dataInValid;
assign vc_mem_dataIn		= i_dataIn;

always @(*) begin
	case (portMuxID)
	BLK_RENDER : begin
		o_command		= rdr_mem_command;
		o_commandSize	= rdr_mem_commandSize;
		o_write			= rdr_mem_write;
		o_adr			= rdr_mem_adr;
		o_subadr		= rdr_mem_subadr;
		o_writeMask		= rdr_mem_writeMask;
		o_dataOut		= rdr_mem_dataOut;
	end
	BLK_CV : begin
		o_command		= cv_mem_command;
		o_commandSize	= cv_mem_commandSize;
		o_write			= cv_mem_write;
		o_adr			= cv_mem_adr;
		o_subadr		= cv_mem_subadr;
		o_writeMask		= cv_mem_writeMask;
		o_dataOut		= cv_mem_dataOut;
	end
	BLK_VV : begin
		o_command		= vv_mem_command;
		o_commandSize	= vv_mem_commandSize;
		o_write			= vv_mem_write;
		o_adr			= vv_mem_adr;
		o_subadr		= vv_mem_subadr;
		o_writeMask		= vv_mem_writeMask;
		o_dataOut		= vv_mem_dataOut;
	end
	BLK_VC : begin
		o_command		= vc_mem_command;
		o_commandSize	= vc_mem_commandSize;
		o_write			= vc_mem_write;
		o_adr			= vc_mem_adr;
		o_subadr		= vc_mem_subadr;
		o_writeMask		=  16'd0;
		o_dataOut		= 256'd0;
	end
	// BLK_FILL
	default: begin
		o_command		= fl_mem_command;
		o_commandSize	= fl_mem_commandSize;
		o_write			= fl_mem_write;
		o_adr			= fl_mem_adr;
		o_subadr		= fl_mem_subadr;
		o_writeMask		= fl_mem_writeMask;
		o_dataOut		= fl_mem_dataOut;
	end
	endcase
end

//-----------------------------------------------------------------
// Checker Interface
//-----------------------------------------------------------------
`ifdef verilator
wire v_dbg_is_busy_w = o_command | isRenderActive | isCopyVCActive | isCopyCVActive | isCopyVVActive | isFILLActive | (~parserWaitingNewCommand) | inst_fifo_ready_w;
function [0:0] get_busy; /*verilator public*/
begin
    get_busy = v_dbg_is_busy_w;
end
endfunction

function [0:0] has_fifo_space; /*verilator public*/
begin
    has_fifo_space = inst_fifo_space_w;
end
endfunction

function [0:0] fifo_empty; /*verilator public*/
begin
    fifo_empty = ~inst_fifo_ready_w;
end
endfunction
`endif

//-----------------------------------------------------------------
// Debug logging
//-----------------------------------------------------------------
`ifdef verilator
always @ (posedge clk)
begin
    if (inst_fifo_push_w && inst_fifo_space_w)
    begin
        $display(" [GPU_M2P] %08x", inst_fifo_data_w);
    end

    if (vc_pixels_valid_w && vc_pixels_pop_w)
    begin
        $display(" [GPU_P2M] %08x", vc_pixels_data_w);
    end

    if (inst_fifo_push_w && !inst_fifo_space_w)
    begin
        $display(" [GPU_M2P] %08x [ERROR: OVERFLOW!!]", inst_fifo_data_w);
    end
end
`endif

endmodule
