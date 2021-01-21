/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module gpu_frontend(
	input					i_clk,
	input					i_nRst,
	
	//----------------------------
	//  CPU Side
	//----------------------------
	input					gpuSel,
	input					gpuAdrA2,
	input					write,
	input					read,
	
	input	[31:0]			cpuDataIn,
	output	[31:0]			cpuDataOut,
	output					cpuDataOutValid,
	
	output					o_rstGPU,
	output					o_rstCmd,
	output					o_rstIRQ,
	
	//----------------------------
	//  FIFO Out when CPU read VRAM
	//----------------------------
	input					i_useVCCopyFIFOOut,	// /*RegCommand == 0xC0 && (currWorkState != NOT_WORKING_DEFAULT_STATE)*/
	input	[31:0]			i_valueVCCopyFIFOOut,
	
	//----------------------------
	//  Information for status bit.
	//----------------------------
	input 					i_statusBit31,
	input 					i_statusBit28,
	input 					i_statusBit27,
	input 					i_statusBit26,
	input 					i_statusBit25,
	input					i_statusBit24,
	input 					i_statusBit13,
	
	//----------------------------
	//  Information for Register Read.
	//----------------------------
	input               	GPU_REG_TextureDisable,
	input               	GPU_REG_CheckMaskBit,
	input               	GPU_REG_ForcePixel15MaskSet,
	input               	GPU_REG_DrawDisplayAreaOn,
	input               	GPU_REG_DitherOn,
	input         [1:0] 	GPU_REG_TexFormat,
	input         [1:0] 	GPU_REG_Transparency,
	input         [3:0] 	GPU_REG_TexBasePageX,
	input               	GPU_REG_TexBasePageY,
	input         [4:0] 	GPU_REG_WindowTextureOffsetX,
	input         [4:0] 	GPU_REG_WindowTextureOffsetY,
	input         [4:0] 	GPU_REG_WindowTextureMaskX,
	input         [4:0] 	GPU_REG_WindowTextureMaskY,
	input         [9:0] 	GPU_REG_DrawAreaX0,
	input         [9:0] 	GPU_REG_DrawAreaY0,
	input         [9:0] 	GPU_REG_DrawAreaX1,
	input         [9:0] 	GPU_REG_DrawAreaY1,
	input signed [10:0] 	GPU_REG_OFFSETX,
	input signed [10:0] 	GPU_REG_OFFSETY,

	// Output GP1 Registers
	output       			o_GPU_REG_IsInterlaced,
	output       			o_GPU_REG_BufferRGB888,
	output       			o_GPU_REG_VideoMode,
	output       			o_GPU_REG_VerticalResolution,
	output [1:0] 			o_GPU_REG_HorizResolution,
	output       			o_GPU_REG_HorizResolution368,
	output					o_GPU_REG_ReverseFlag,
	output       			o_GPU_REG_DisplayDisabled,
		
	output [9:0]			o_GPU_REG_DispAreaX,
	output [8:0]			o_GPU_REG_DispAreaY,
	output [11:0]			o_GPU_REG_RangeX0,
	output [11:0]			o_GPU_REG_RangeX1,
	output [9:0]			o_GPU_REG_RangeY0,
	output [9:0]			o_GPU_REG_RangeY1,

	output DMADirection 	o_GPU_REG_DMADirection
		
);

//---------------------------------------------------------------
//  Video Module Registers
//---------------------------------------------------------------
reg               	GPU_REG_IsInterlaced;
reg               	GPU_REG_BufferRGB888;
reg               	GPU_REG_VideoMode;
reg               	GPU_REG_VerticalResolution;
reg         [1:0] 	GPU_REG_HorizResolution;
reg               	GPU_REG_HorizResolution368;
reg				  	GPU_REG_ReverseFlag;
reg               	GPU_REG_DisplayDisabled;
reg			[9:0]	GPU_REG_DispAreaX;
reg			[8:0]	GPU_REG_DispAreaY;
reg			[11:0]	GPU_REG_RangeX0;
reg			[11:0]	GPU_REG_RangeX1;
reg			[9:0]	GPU_REG_RangeY0;
reg			[9:0]	GPU_REG_RangeY1;

DMADirection		GPU_REG_DMADirection;

reg [31:0] regGpuInfo;

wire [31:0] reg1Out = {
	// Default : 1480.2.000h
	i_statusBit31,
	GPU_REG_DMADirection,				// 29-30
	i_statusBit28, 						// 28

	i_statusBit27,						// 27
	i_statusBit26,     					// 26
	i_statusBit25,						// 25
	i_statusBit24,						// 24

	GPU_REG_DisplayDisabled,			// 23
	GPU_REG_IsInterlaced,				// 22
	GPU_REG_BufferRGB888,				// 21
	GPU_REG_VideoMode,					// 20 (0=NTSC, 1=PAL)
	GPU_REG_VerticalResolution,			// 19 (0=240, 1=480, when Bit22=1)
	GPU_REG_HorizResolution,			// 17-18 (0=256, 1=320, 2=512, 3=640)
	GPU_REG_HorizResolution368,			// 16 (0=256/320/512/640, 1=368)

	GPU_REG_TextureDisable,				// 15
	GPU_REG_ReverseFlag,				// 14
	i_statusBit13,						// 13
	GPU_REG_CheckMaskBit,				// 12

	GPU_REG_ForcePixel15MaskSet,		// 11
	GPU_REG_DrawDisplayAreaOn,			// 10
	GPU_REG_DitherOn,					// 9
	GPU_REG_TexFormat,					// 7-8
	GPU_REG_Transparency,				// 5-6
	GPU_REG_TexBasePageY,				// 4
	GPU_REG_TexBasePageX				// 0-3
};

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
		if (i_useVCCopyFIFOOut) begin
			dataOut = i_valueVCCopyFIFOOut;
		end else begin
			dataOut	= regGpuInfo;
		end
	end
end

always @(posedge i_clk) begin
	pDataOut		<= dataOut;
	pDataOutValid	<= (gpuSel & read);
end

assign cpuDataOut		= pDataOut;
assign cpuDataOutValid	= pDataOutValid;
//---------------------------------------------------------------

/*
	statusBit31 = GPU_DisplayEvenOddLinesInterlace,
	statusBit28 = (currWorkState == NOT_WORKING_DEFAULT_STATE)
	statusBit27 = gpuReadySendToCPU
	statusBit26 = isFifoEmpty32 && parserWaitingNewCommand && (currWorkState == NOT_WORKING_DEFAULT_STATE)
	statusBit25 = dmaDataRequest
	statusBit24 = GPU_REG_IRQSet
	statusBit13 = (GPU_REG_CurrentInterlaceField & GPU_REG_IsInterlaced) | (!GPU_REG_IsInterlaced)
*/
	
wire parserWaitingNewCommand;

wire writeGP1		=  gpuAdrA2 & gpuSel & write;

wire cmdGP1			= writeGP1 & (cpuDataIn[29:27] == 3'd0); // Short cut for most commands.
wire rstGPU  		=(cmdGP1   & (cpuDataIn[26:24] == 3'd0)) | (!i_nRst);
wire rstCmd  		= cmdGP1   & (cpuDataIn[26:24] == 3'd1);
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

always @(posedge i_clk)
if (getGPUInfo)
	regGpuInfo <= gpuInfoMux;
	
always @(posedge i_clk)
begin
	// -------------------------------------------
	// Command though CPU port write
	// -------------------------------------------
	if (rstGPU) begin
		GPU_REG_DisplayDisabled		<= 1;
		GPU_REG_DMADirection		<= DMA_DirOff; // Off
		GPU_REG_DispAreaX			<= 10'd0;
		GPU_REG_DispAreaY			<=  9'd0;
		GPU_REG_RangeX0				<= 12'h200;		// 200h
		GPU_REG_RangeX1				<= 12'hC00;		// 200h + 256x10
		GPU_REG_RangeY0				<= 10'h10;		//  10h
		GPU_REG_RangeY1				<= 10'h100; 	//  10h + 240
		GPU_REG_IsInterlaced		<= 0;
		GPU_REG_BufferRGB888		<= 0;
		GPU_REG_VideoMode			<= 0;
		GPU_REG_VerticalResolution	<= 0;
		GPU_REG_HorizResolution		<= 2'b0;
		GPU_REG_HorizResolution368	<= 0;
		GPU_REG_ReverseFlag			<= 0;
	end else begin
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
end

assign o_rstGPU = rstGPU;
assign o_rstCmd = rstCmd;
assign o_rstIRQ = rstIRQ;

assign o_GPU_REG_IsInterlaced		= GPU_REG_IsInterlaced;
assign o_GPU_REG_BufferRGB888		= GPU_REG_BufferRGB888;
assign o_GPU_REG_VideoMode			= GPU_REG_VideoMode;
assign o_GPU_REG_VerticalResolution	= GPU_REG_VerticalResolution;
assign o_GPU_REG_HorizResolution	= GPU_REG_HorizResolution;
assign o_GPU_REG_HorizResolution368	= GPU_REG_HorizResolution368;
assign o_GPU_REG_ReverseFlag		= GPU_REG_ReverseFlag;
assign o_GPU_REG_DisplayDisabled	= GPU_REG_DisplayDisabled;

assign o_GPU_REG_DispAreaX			= GPU_REG_DispAreaX;
assign o_GPU_REG_DispAreaY			= GPU_REG_DispAreaY;
assign o_GPU_REG_RangeX0	 		= GPU_REG_RangeX0;
assign o_GPU_REG_RangeX1	 		= GPU_REG_RangeX1;
assign o_GPU_REG_RangeY0	 		= GPU_REG_RangeY0;
assign o_GPU_REG_RangeY1	 		= GPU_REG_RangeY1;

assign o_GPU_REG_DMADirection		= GPU_REG_DMADirection;

endmodule
