/*
	POSSIBLE OPTIMIZATION :
	- Line outside draw area check optimization can be added.
	- Triangle Setup avoid R,G,B setup division latency if all same vertex color (or white) : (!bIsPerVtxCol) | bIgnoreColor ?
	- Triangle 'snake' parsing can be optimized in cycle count.
	- State Machine for RGBUV setup division latency can be optimized. (Now 6 cycle latency implementation -> 5 or 4 ?)
	- Use an INVERSE instead of division per component. --> Inverse of DET can be computed a few step earlier.
		While loading UVRGB... as soon as coordinates are loaded.
 */
module gpu(
	input			clk,
	input			i_nrst,
	
	input			gpuAdrA2, // Called A2 because multiple of 4
	input			gpuSel,
	output			ack,
	
	output			IRQRequest,
	
	// Video output...
	output	[7:0]	red,
	output	[7:0]	green,
	output	[7:0]	blue,
	/*
	output			hSync,
	output			vSync, // cSync pin exist in real HW : hSync | vSync most likely
	output			hBlank,
	output			vBlank,
	
	// TODO Memory interface here...
	*/
	
	output			pixelStencilOut,
	
	input			acceptCommand,
	output [55:0]	memoryWriteCommand,
	
	input			write,
	input			read,
	input 	[31:0]	cpuDataIn,
	output reg [31:0]	cpuDataOut
);

wire writeFifo		= !gpuAdrA2 & gpuSel & write;
wire writeGP1		=  gpuAdrA2 & gpuSel & write;
assign ack			= !isFifoFull;
always @(*)
begin
	if (gpuSel & read) begin
		// Register +4 Read
		if (gpuAdrA2) begin
			cpuDataOut	=  reg1Out;
		end else begin
		// Register +0 Read
		// TODO : if has 0xCX command, then return proper VRAM values...
			cpuDataOut	=  regGpuInfo;
		end
	end else begin
		cpuDataOut	=  32'hFFFFFFFF; // Not necessary but to avoid bug for now.
	end
end

assign IRQRequest = GPU_REG_IRQSet;

wire [31:0] fifoDataOut;
wire isFifoFullLSB, isFifoFullMSB,isFifoEmptyLSB, isFifoEmptyMSB;
wire isFifoFull     = isFifoFullLSB  | isFifoFullMSB;
wire isFifoEmpty    = isFifoEmptyLSB & isFifoEmptyMSB;
wire isFifoNotEmpty = !isFifoEmpty;
wire rstInFIFO      = rstGPU | rstCmd;

wire readLFifo, readMFifo;
wire readFifoLSB	= readFifo | readLFifo;
wire readFifoMSB	= readFifo | readMFifo;

assign memoryWriteCommand[ 2:0] = memoryCommand;
assign memoryWriteCommand[55:3] = parameters;
reg  [52:0] parameters;

wire [15:0] LPixel = swap ? fifoDataOut[31:16] : fifoDataOut[15: 0];
wire [15:0] RPixel = swap ? fifoDataOut[15: 0] : fifoDataOut[31:16];
wire validL        = swap ? regSaveM : regSaveL;
wire validR        = swap ? regSaveL : regSaveM;
reg flush;

wire [5:0] scrSrcX = counterXSrc[5:0] + RegX0[9:4];
always @(*)
begin
	case (memoryCommand)
	// CPU 2 VRAM : [16,16,2,15,...]
	3'd1:    parameters = 	{ { LPixel[15] | GPU_REG_ForcePixel15MaskSet    , LPixel[14:0]}
							, { RPixel[15] | GPU_REG_ForcePixel15MaskSet , RPixel[14:0]}
							, validL
							, validR
							, { scrY[8:0], currX[9:4] } 
							, currX[3:1]
							, flush 
							};
	// FILL MEMORY SEGMENT
	3'd2:    parameters =	{ { 1'b0, RegB0[7:3] , RegG0[7:3] , RegR0[7:3] }               
							, 16'd0
							, 1'b1 // Dont care, but used in check SW.
							, 1'b0
							, { scrY[8:0], scrSrcX }
							, 3'd0
							, 1'b1
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

// TODO DMA Stuff
wire gpuReadyReceiveDMA, gpuReadySendToCPU, gpuReceiveCmdReady, dmaDataRequest;

assign gpuReceiveCmdReady	= !isFifoFull;
assign gpuReadyReceiveDMA	= !isFifoFull; // TODO later when doing DMA tranfer...

wire [31:0] reg1Out = { 
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

// ----------------------------- Parsing Stage -----------------------------------
reg signed [10:0] GPU_REG_OFFSETX;
reg signed [10:0] GPU_REG_OFFSETY;
reg         [3:0] GPU_REG_TexBasePageX;
reg               GPU_REG_TexBasePageY;
reg         [1:0] GPU_REG_Transparency; parameter TRANSP_HALF=2'd0, TRANSP_ADD=2'd1, TRANSP_SUB=2'd2, TRANSP_ADDQUARTER=2'd3;
reg         [1:0] GPU_REG_TexFormat;	parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;
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
reg         [1:0] GPU_REG_HorizResolution;	parameter XRES_256=2'd0, XRES_320=2'd1, XRES_512=2'd2, XRES_640=2'd3;
reg               GPU_REG_HorizResolution368;
reg         [1:0] GPU_REG_DMADirection;		parameter DMADIR_OFF=2'd0, DMADIR_FIFO=2'd1, DMADIR_C2G=2'd2, DMADIR_G2C=2'd3;
reg			[9:0] GPU_REG_DispAreaX;
reg			[8:0] GPU_REG_DispAreaY;
reg			[11:0] GPU_REG_RangeX0;
reg			[11:0] GPU_REG_RangeX1;
reg			[9:0] GPU_REG_RangeY0;
reg			[9:0] GPU_REG_RangeY1;
reg				  GPU_REG_ReverseFlag;
reg					GPU_DisplayEvenOddLinesInterlace; // TODO
reg					GPU_REG_CurrentInterlaceField; // TODO

// For RECT Commands.
parameter SIZE_VAR	= 2'd0, SIZE_1x1 = 2'd1, SIZE_8x8 = 2'd2, SIZE_16x16 = 2'd3;

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

wire [7:0] command			= storeCommand ? fifoDataOut[31:24] : RegCommand;

reg [7:0] RegCommand;
reg  FifoDataValid;

wire cmdGP1			= writeGP1 & (cpuDataIn[29:27] == 3'd0); // Short cut for most commands.
wire rstGPU  		=(cmdGP1   & (cpuDataIn[26:24] == 3'd0)) | (i_nrst == 0);
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
reg [31:0] regGpuInfo;
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
		GPU_REG_TexFormat			<= 2'd0; // TODO ??
		GPU_REG_DitherOn			<= 1'd0; // TODO ??
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
		GPU_REG_DrawAreaX1			<= 10'd1023;	// TODO ??? Allow whole surface by default...
		GPU_REG_DrawAreaY1			<= 10'd511;		// TODO ??? 10'd1023 on old GPU.
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
		GPU_REG_RangeX0				<= 12'h200;	// 200h
		GPU_REG_RangeX1				<= 12'hC00;	// 200h + 256x10
		GPU_REG_RangeY0				<= 10'h10;	//  10h
		GPU_REG_RangeY1				<= 10'h100; //  10h + 240
	end else begin
		if (loadE5Offsets) begin
			GPU_REG_OFFSETX <= fifoDataOut[10: 0];
			GPU_REG_OFFSETY <= fifoDataOut[21:11]; 
		end
		if (loadTexPageE1 || loadTexPage) begin
			GPU_REG_TexBasePageX 	<= loadTexPage ? fifoDataOut[19:16] : fifoDataOut[3:0];
			GPU_REG_TexBasePageY 	<= loadTexPage ? fifoDataOut[20]    : fifoDataOut[4];
			GPU_REG_Transparency 	<= loadTexPage ? fifoDataOut[22:21] : fifoDataOut[6:5];
			GPU_REG_TexFormat    	<= loadTexPage ? fifoDataOut[24:23] : fifoDataOut[8:7];
			GPU_REG_TextureDisable	<= loadTexPage ? fifoDataOut[27]    : fifoDataOut[11];
		end
		if (loadTexPageE1) begin // Texture Attribute only changed by E1 Command.
			GPU_REG_DitherOn     <= fifoDataOut[9];
			GPU_REG_DrawDisplayAreaOn <= fifoDataOut[10];
			GPU_REG_TextureXFlip <= fifoDataOut[12];
			GPU_REG_TextureYFlip <= fifoDataOut[13];
		end
		if (loadTexWindowSetting) begin
			GPU_REG_WindowTextureMaskX   <= fifoDataOut[4:0];
			GPU_REG_WindowTextureMaskY   <= fifoDataOut[9:5];
			GPU_REG_WindowTextureOffsetX <= fifoDataOut[14:10];
			GPU_REG_WindowTextureOffsetY <= fifoDataOut[19:15];
		end
		if (loadDrawAreaTL) begin
			GPU_REG_DrawAreaX0 <= fifoDataOut[ 9: 0];
			GPU_REG_DrawAreaY0 <= { 1'b0, fifoDataOut[18:10] }; // 19:10 on NEW GPU.
		end
		if (loadDrawAreaBR) begin
			GPU_REG_DrawAreaX1 <= fifoDataOut[ 9: 0];
			GPU_REG_DrawAreaY1 <= { 1'b0, fifoDataOut[18:10] }; // 19:0 on NEW GPU.
		end
		if (loadMaskSetting) begin
			GPU_REG_ForcePixel15MaskSet <= fifoDataOut[0];
			GPU_REG_CheckMaskBit		<= fifoDataOut[1];
		end
		if (rstIRQ | setIRQ) begin
			GPU_REG_IRQSet				<= setIRQ;
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

	if (storeCommand) begin RegCommand <= command; end
	FifoDataValid <= readFifo;
end

// [Command Type]
wire bIsPolyCommand			= (command[7:5]==3'b001);
wire bIsRectCommand			= (command[7:5]==3'b011);
wire bIsLineCommand			= (command[7:5]==3'b010);
wire bIsForECommand			= (command[7:5]==3'b111);
wire bIsCopyVVCommand		= (command[7:5]==3'b100);
wire bIsCopyCVCommand		= (command[7:5]==3'b101);
wire bIsCopyVCCommand		= (command[7:5]==3'b110);
wire bIsFillCommand			= bIsBase0x & bIsBase02;

wire bIsBase0x				= (command[7:5]==3'b000);
	wire bIsBase01			= (command[4:0]==5'd1  );
	wire bIsBase02			= (command[4:0]==5'd2  );
	wire bIsBase1F			= (command[4:0]==5'd31 );
	
// End line command if special marker or SECOND vertex when not a multiline command...
wire bIsTerminator			= (fifoDataOut[31:28] == 4'd5) & (fifoDataOut[15:12] == 4'd5);
wire bIsMultiLineTerminator = (bIsLineCommand & bIsMultiLine & bIsTerminator);

wire bIsPrimitiveLoaded;	// TODO : Execute next stage

// [All attribute of commands]
wire bIsRenderAttrib		= (bIsForECommand & (!command[4]) & (!command[3])) & (command[2:0]!=3'b000) & (command[2:0]!=3'b111); // E*, range 0..7 -> Select E1..E6 Only
wire bIsNop         		= (bIsBase0x & (!(bIsBase01 | bIsBase02 | bIsBase1F)))	// Reject 01,02,1F
							| (bIsForECommand & (!bIsRenderAttrib));				// Reject E1~E6
wire bIsPolyOrRect  		= (bIsPolyCommand | bIsRectCommand);

// Line are not textured
wire bIgnoreColor   		= bUseTexture   & !command[0];
wire bSemiTransp    		= command[1];
wire bUseTexture    		= bIsPolyOrRect &  command[2]; 										// Avoid texture fetching if we do LINE, Compute proper color for FILL.
wire bIs4PointPoly  		= command[3] & bIsPolyCommand;
wire bIsMultiLine   		= command[3] & bIsLineCommand;
wire bIsPerVtxCol   		= (bIsPolyCommand | bIsLineCommand) & command[4];
// Rectangle no dither.
wire bDither				= GPU_REG_DitherOn & (!bIsRectCommand);
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
reg [14:0] RegC ;
// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
// reg  [9:0] RegTx;
reg [10:0] RegSizeW;
reg [ 9:0] RegSizeH;
reg [ 9:0] OriginalRegSizeH;

// FIFO is empty or next stage still busy processing the last primitive.

reg [1:0] vertCnt;
reg       isFirstVertex;
always @(posedge clk)
begin
	if (resetVertexCounter /* | rstGPU | rstCmd : Done by STATE RESET. */) begin
		vertCnt			= 2'b00;
		isFirstVertex	= 1;
	end else begin
		vertCnt = vertCnt + increaseVertexCounter;
		if (increaseVertexCounter) begin
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

// Increment when Dst < Src. : (V1-V0 < 0) |  Valid for ALL axis (X and Y)
// Decrement when Dst > Src. : (V1-V0 > 0) |  Src = Vertex0, Dst = Vertex1 => V1-V0
wire yCopyDirectionIncr			= isNegYAxis;
wire xCopyDirectionIncr			= isNegXAxis;

wire  [9:0] OppRegSizeH			= OriginalRegSizeH - RegSizeH;
wire  [9:0] fullY				= (yCopyDirectionIncr ? (RegSizeH + 10'h3FF) : OppRegSizeH) + { useDest ? RegY1[9:0] : RegY0[9:0] };	// Proper Top->Bottom or reverse order based on copy direction.

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

wire  [6:0] adrXSrc				= xCopyDirectionIncr ? counterXSrc : OppAdrXSrc;
wire  [6:0] adrXDst				= xCopyDirectionIncr ? counterXDst : OppAdrXDst;

wire  [6:0] fullX				= (useDest           ? adrXDst : adrXSrc)          + { 1'b0, useDest ? RegX1[9:4] : RegX0[9:4] };

wire [18:0] adrWord				= { fullY[8:0],fullX, 3'd0 }; // 32 Bit Word Adress.
reg	 [ 6:0] counterXSrc,counterXDst;
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
wire       isSrcDstEQ = (RegSizeW[3:0] == 0);
wire       isSrcDstLT = (RegX0[3:0] < rightPos);
wire       isSrcDstGT = (RegX0[3:0] > rightPos);

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
reg  resetXCounter;

wire emptySurface			= (RegSizeH == 10'd0) | (RegSizeW == 11'd0);
wire isFirstSegment 		= (counterXSrc==0);
wire isLastSegment  		= (counterXSrc==lengthBlockSrcHM1);
wire isLastSegmentDst		= (counterXDst==lengthBlockDstHM1);
wire [15:0] currMaskLeft	= (isFirstSegment ? maskLeft  : 16'hFFFF);
wire [15:0] currMaskRight	= (isLastSegment  ? maskRight : 16'hFFFF);
wire [15:0] maskSegmentRead	= currMaskLeft & currMaskRight;

reg signed [11:0] pixelX; 
reg signed [11:0] nextPixelX; // Wire
reg signed [11:0] pixelY; 
reg signed [11:0] nextPixelY; // Wire

reg dir;
reg memW0,memW1,memW2;


parameter 	X_TRI_NEXT		= 3'd1,
			X_LINE_START	= 3'd2,
			X_LINE_NEXT		= 3'd3,
			X_TRI_BBLEFT	= 3'd4,
			X_TRI_BBRIGHT	= 3'd5,
			X_ASIS			= 3'd0;
			
parameter	Y_LINE_START	= 3'd1,
			Y_LINE_NEXT		= 3'd2,
			Y_TRI_START		= 3'd3,
			Y_TRI_NEXT		= 3'd4,
			Y_ASIS			= 3'd0;

wire 				extIX		= dir & changeX;
always @(*)
begin
	case (selNextX)
	X_TRI_NEXT:		nextPixelX	= pixelX + { {10{extIX}}, changeX, 1'b0 };	// -2,0,+2
	X_LINE_START:	nextPixelX	= RegX0;
	X_LINE_NEXT:	nextPixelX	= nextLineX; // Optimize and merge with case 0
	X_TRI_BBLEFT:	nextPixelX	= { minTriDAX0[11:1], 1'b0 };
	X_TRI_BBRIGHT:	nextPixelX	= { maxTriDAX1[11:1], 1'b0 };
	default:		nextPixelX	= pixelX;
	endcase
			
	case (selNextY)
	Y_LINE_START:	nextPixelY	= RegY0;
	Y_LINE_NEXT:	nextPixelY	= nextLineY;
	Y_TRI_START:	nextPixelY	= minTriDAY0;
	Y_TRI_NEXT:		nextPixelY	= pixelY + { 10'b0, 1'b1 };
	default:		nextPixelY	= pixelY;
	endcase
end
	
reg pixelFound;
reg enteredTriangle; reg setEnteredTriangle, resetEnteredTriangle;

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
end

wire tstRightEqu0 = maxTriDAX1[0] ? w0R[EQUMSB] : w0L[EQUMSB];
wire tstRightEqu1 = maxTriDAX1[0] ? w1R[EQUMSB] : w1L[EQUMSB];
wire tstRightEqu2 = maxTriDAX1[0] ? w2R[EQUMSB] : w2L[EQUMSB];

reg [5:0] currWorkState,nextWorkState;	parameter
										NOT_WORKING_DEFAULT_STATE	= 6'd0, 
										LINE_START					= 6'd1, 
										LINE_DRAW					= 6'd2,
										RECT_START					= 6'd3,
										FILL_START					= 6'd4,
										COPY_START					= 6'd5,
										TRIANGLE_START				= 6'd6,
										FILL_LINE  					= 6'd7,
										COPYCV_START 				= 6'd8,
										COPYVC_START 				= 6'd9,
										CPY_LINE_START_UNALIGNED	= 6'd10,
										CPY_LINE_BLOCK				= 6'd11,
										CPY_WUN_BLOCK				= 6'd12,
										CPY_WR_BLOCK				= 6'd13,
										START_LINE_TEST_LEFT		= 6'd14,
										START_LINE_TEST_RIGHT		= 6'd15,
										SCAN_LINE					= 6'd16,
										SCAN_LINE_CATCH_END			= 6'd17,
										LINE_READ_MASK				= 6'd18,
										TMP_2 						= 6'd19,
										TMP_3 						= 6'd20,
										TMP_4 						= 6'd21,
										SETUP_RX					= 6'd22,
										SETUP_RY					= 6'd23,
										SETUP_GX					= 6'd24,
										SETUP_GY					= 6'd25,
										SETUP_BX					= 6'd26,
										SETUP_BY					= 6'd27,
										SETUP_UX					= 6'd28,
										SETUP_UY					= 6'd29,
										SETUP_VX					= 6'd30,
										SETUP_VY					= 6'd31,
										RECT_SCAN_LINE				= 6'd32,
										WAIT_3						= 6'd33,
										WAIT_2						= 6'd34,
										WAIT_1						= 6'd35,
										SELECT_PRIMITIVE			= 6'd36,
										COPYCV_COPY					= 6'd37;

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

// TODO :
wire			canWrite = 1'b1;

// [Computation value needed for control setup]

wire			canRead	= (!isFifoEmptyLSB) | (!isFifoEmptyMSB);
//                          X       + WIDTH              - [1 or 2]
wire [11:0]		XE		= { RegX0 } + { 1'b0, RegSizeW } + {{11{1'b1}}, RegX0[0] ^ RegSizeW[0]};		// We can NOT use 10:0 range, because we compare nextX with XE to find the END. Full width of 1024 equivalent to ZERO size.
wire  [9:0]		scrY	= currY + RegY0[9:0];
wire [11:0]	nextX		= currX + { 12'd2 };
wire [ 9:0]	nextY		= currY + { 10'd1 };
wire		WidthNot1	= |RegSizeW[10:1];
wire		endVertical	= (nextY == RegSizeH);

// [Registers]
reg  [11:0]		currX;
reg  [ 9:0]		currY;
reg				regSaveL,regSaveM;
reg				swap;
reg				lastPair;

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
	if (setY) begin
		currY = 0;
	end
	if (incY) begin
		currY = nextY;
	end
	if (setX) begin
		currX = {2'b0, RegX0[9:1], 1'b0};
	end
	if (incX) begin
		currX = nextX;
	end
	
	if (readL | readM) begin
		regSaveM = readM;
		regSaveL = readL;
	end
end

// [Control bit]
reg setLastPair, resetLastPair;
reg changeSwap;
reg setSwap;
reg incY,setY,incX,setX;
reg readL;
reg readM;
assign readLFifo = readL;
assign readMFifo = readM;


// --------------------------------------------------------------------------------------------
//   [END] CPU TO VRAM STATE SIGNALS & REGISTERS
// --------------------------------------------------------------------------------------------


// State machine for triangle
// State to control setup...
reg [2:0]		compoID;
reg				vecID;
reg				changeX;
reg				resetDir;
reg				switchDir;
reg				loadNext;
reg				setPixelFound;
reg				resetPixelFound;
reg				memorizeLineEqu;
reg IncY;
reg [2:0] selNextX;
reg [2:0] selNextY;

wire			requestNextPixel = 1'b1;
reg				writePixelL,writePixelR;
// reg				readStencil;
reg				writeStencil;
reg				assignRectSetup;

reg [2:0]		memoryCommand;
wire 			reachEdgeTriScan = (((pixelX > maxXTri) & !dir) || ((pixelX < minXTri) & dir));
always @(*)
begin
	// -----------------------
	// Default Value Section
	// -----------------------
	memoryCommand				= 3'b000;
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
	writeStencil				= 0;
	changeX						= 0;
	assignRectSetup				= 0;
	setEnteredTriangle			= 0;
	resetEnteredTriangle		= 0;
	
	// -----------------------
	//  CPU TO VRAM SIGNALS
	// -----------------------
	setLastPair = 0; resetLastPair = 0; setSwap = 0; incY = 0; setY = 0; setX = 1'b0; incX = 1'b0; changeSwap = 1'b0;
	readL				= 0;
	readM				= 0;
	flush				= 0;
	// -----------------------
	
	
	case (currWorkState)
	NOT_WORKING_DEFAULT_STATE:
	begin
		assignRectSetup			= !bIsPerVtxCol;
		resetEnteredTriangle	= 1;	// Put here, no worries about more specific cases.
		case (issuePrimitive)
		ISSUE_TRIANGLE:
		begin
			if (bIsPerVtxCol) begin
				nextWorkState = SETUP_RX;
			end else begin
				nextWorkState = (bUseTexture) ? SETUP_UX : TRIANGLE_START;
			end
		end
		ISSUE_RECT:
		begin
			assignRectSetup	= 1;
			nextWorkState	= RECT_START;
		end
		ISSUE_LINE:
		begin
			if (bIsPerVtxCol) begin
				nextWorkState = SETUP_RX;
			end else begin
				nextWorkState = (bUseTexture) ? SETUP_UX : LINE_START;
			end
		end
		ISSUE_FILL:		nextWorkState = FILL_START;
		ISSUE_COPY:		
			if (bIsCopyVVCommand) begin
				nextWorkState = COPY_START;
			end else if (bIsCopyCVCommand) begin
				nextWorkState = COPYCV_START;
			end else begin
				// bIsCopyVCCommandbegin obviously...
				nextWorkState = COPYVC_START;
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
			setY = 1; // Reset H Counter.
			nextWorkState				= FILL_LINE;
		end
	end
	FILL_LINE:
	begin
		// Forced to decrement at each step in X
		// [FILL COMMAND : [16 Bit 0BGR][16 bit empty][Adr 15 bit][4 bit empty][010]
		if (acceptCommand) begin
			memoryCommand		= 3'd2;
			if (isLastSegment) begin
				incY = 1;
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
	COPY_START:
	begin
		// [CPY_START]
		if (emptySurface) begin
			nextWorkState = NOT_WORKING_DEFAULT_STATE;
		end else begin
			if (RegX0[3:0]!=0 & (isFirstSegment!=isLastSegment)) begin	// Non aligned start AND length out of range.
				nextWorkState = CPY_LINE_START_UNALIGNED;
			end else begin
				nextWorkState = CPY_LINE_BLOCK;
			end
		end
	end
	CPY_LINE_START_UNALIGNED:// [CPY_LINE_START_UNALIGNED]
	begin
		if (acceptCommand) begin
			// TODO : ReadBlock(adr);
			incrementXCounter		= 1; // SRC COUNTER
			switchReadStoreBlock	= 1;
			nextWorkState			= CPY_LINE_BLOCK;
		end
	end
	CPY_LINE_BLOCK:	// [CPY_LINE_BLOCK]
	begin
		if (acceptCommand) begin
			// TODO : ReadBlock(adr);
			incrementXCounter		= 1; // SRC COUNTER
			switchReadStoreBlock	= 1;
			
			// -------------------
			// !!! FAKE !!! : Just to validate the READ PART of the state machine.
			// -------------------
			if (isLastSegment) begin
				resetXCounter				= 1;
				// TODO incY = 1, resetXCounter does not modify Y now.
				nextWorkState				= (emptySurface) ? NOT_WORKING_DEFAULT_STATE : COPY_START;
			end else begin
				incrementXCounter			= 1; // DST COUNTER
				nextWorkState				= CPY_LINE_BLOCK;
			end
			// --- END FAKE ----------------
			/* 
				TODO WRITE REAL LOGIC
			if (RegSX1[3:0]!=0) begin
				nextWorkState = CPY_WUN_BLOCK;
			end else begin
				nextWorkState = CPY_WR_BLOCK;
			end
			*/
		end
	end
	CPY_WUN_BLOCK:	// [CPY_WUN_BLOCK]
	begin
		/* TODO : State machine write part.
		useDest = 1;
		if (acceptCommand) begin
			// TODO : WriteBlock(adr)
			incrementXCounter		= 1; // DST COUNTER
			nextWorkState			= CPY_WR_BLOCK;
		end
		*/
	end
	CPY_WR_BLOCK:
	begin
		/* TODO : State machine write part.
		useDest = 1;
		if (acceptCommand) begin
			// TODO : WriteBlock(adr)
			if (isLastSegmentDst) begin
				decrementH_ResetXCounter	= 1;
				nextWorkState				= (emptySurface) ? NOT_WORKING_DEFAULT_STATE : COPY_START;
			end else begin
				incrementXCounter			= 1; // DST COUNTER
				nextWorkState				= CPY_LINE_BLOCK;
			end
		end
		*/
	end
	
		// 1.May need to reassembly 16 bit pixel into 32 bit write due to alignement.
		// 2.May need to repacket into into 8x32 bit packet for write.
		//		[Must be done at FIFO outside]
		// =>	A. Outside will have TWO memory of 16 pixel. (ODD / EVEN PIXELS)
		//   	B. Burst load will be 16 pixels.
		//		C. Read Command are :
		//			Read  [store to +0/+16 offset][15 bit adr][16 bit mask from Stencil & Valid pixel mask]
		//			[READ ARE ALWAYS 32 BYTE ALIGNED, ALSO ALIGNED IN STORE (0/16 pixels)]
		//			Write [OffsetX        (4 bit)][15 bit adr][16 bit mask from Stencil & Valid pixel mask] 
		//			[WRITE ARE ALWAYS 32 BYTE ALIGNED, BUT READ IN THE STORE is PIXEL INDEX BASED]
		//
		// [BSTORE COMMAND : [001][Adr 15 bit][Store 1 Bit (0/16)][16 Bit Mask] = 35 bit
		// [BWRITE COMMAND : [010][Adr 15 bit][Store 4 Bit Offset][16 Bit Mask] = 38 bit
		//
		// 3. + Handle masking with CACHE.
		//		Read  from STENCIL CACHE.
		//		Write to   STENCIL CACHE.
		// 4. State machine for pixel block size and copy...
		// 5. Handle that SourceY < DestY or > Desty (copy order must be different !)
		
		// .Is Aligned ?
		//  .1 Read, 1 Write
		// else
		//  .2 Read, 1 Write
		
	// --------------------------------------------------------------------
	//   COPY CPU TO VRAM.
	// --------------------------------------------------------------------
	COPYCV_START:
	begin
		setX = 1'b1; //LOAD_X0_NOBIT0;
		setY = 1'b1; //LOAD_Y0;
		setSwap			= 1;
		// Reset last pair by default, but if WIDTH == 1 -> different.
		resetLastPair	= WidthNot1;
		setLastPair		= !WidthNot1;
		// We set first pair read here, flag not need to be set for next state !
		// No Zero Size W/H Test -> IMPOSSIBLE By definition.
		if (canRead) begin
			// Read ALL DATA 1 item in advance -> Remove FIFO LATENCY ISSUE.
			readL = 1'b1;
			readM = !RegX0[0] & (WidthNot1);
			nextWorkState	= COPYCV_COPY;
		end
	end
	COPYCV_COPY:
	begin
		// TRICKY :
		// -----------------------------
		// At the current pixel X,Y we preload the FIFO for the NEXT X,Y coordinate.
		// So setup of readL/readM are ONE PAIR in advance compare to the scanning...
		// -----------------------------
		if (acceptCommand & canRead) begin
			memoryCommand = 3'd1;
			
			// [Last pair]
			if (lastPair) begin
				if (endVertical) begin
					nextWorkState	= NOT_WORKING_DEFAULT_STATE;
					// PURGE...
					readL		= 1'b0;
					readM		= RegSizeW[0] & RegSizeH[0]; // Pump out unused pixel in FIFO.
					flush		= 1'b1;
				end else begin
					incY		= 1'b1;
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
							readL = !nextY[0]; readM = nextY[0];
						end
						endcase
						changeSwap  = RegSizeW[0] & WidthNot1; // If width=1, do NOT swap.
					end else begin
						// Only 1 pixel WIDTH pattern...
						// Alternate ODD/EVEN lines...
						readL		= !nextY[0];
						readM		=  nextY[0];
						changeSwap	= 1'b1;
					end
				end
				setX			= 1'b1;
				resetLastPair	= WidthNot1;
			end else begin
				// [MIDDLE OR FIRST SEGMENT]
				//    PRELOAD NEXT SEGMENT...
				if (nextX == XE) begin
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
						readL = !currY[0]; readM = currY[0];
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
				incX  = 1'b1;
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
		nextWorkState = TMP_2;
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
	/*
	WAIT_4: // 5 cycles to wait, we have division pipeline to wait for...
	begin
		nextWorkState = WAIT_3;
	end
	*/
	WAIT_3: // 4 cycles to wait
	begin
		nextWorkState = WAIT_2;
	end
	WAIT_2: // 3 cycles to wait
	begin
		nextWorkState = WAIT_1;
	end
	WAIT_1: // 2 cycles to wait
	begin
		nextWorkState = SELECT_PRIMITIVE;
	end
	SELECT_PRIMITIVE: 	// 1 Cycle to wait... send to primitive (with 1 cycle wait too...)
	begin				// Need 4 more cycle after that.
		if (bIsPolyCommand) begin
			nextWorkState = TRIANGLE_START;
		end else begin
			nextWorkState = LINE_START; /* RECT NEVER REACH HERE : No Division setup */
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
			nextWorkState	= SCAN_LINE;
		end
	end
	SCAN_LINE:
	begin
		if (isBottomInsideBBox) begin
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
					// Write only if pixel pair is valid...
					
					writePixelL	= isValidPixelL /*& mask stuff */;
					writePixelR	= isValidPixelR /*& mask stuff */;
					
					// Go to next pair whatever, as long as request is asking for new pair...
					// normally changeX = 1; selNextX = X_TRI_NEXT;  [!!! HERE !!!]
					changeX		= 1;
					loadNext	= 1;
					selNextX	= X_TRI_NEXT;
				end
			end else begin
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
					nextWorkState	= reachEdgeTriScan ? (enteredTriangle ? NOT_WORKING_DEFAULT_STATE : SCAN_LINE_CATCH_END) : SCAN_LINE;
				end
			end
		end else begin
			// TODO : change adress to flush all pixel write.
			nextWorkState = NOT_WORKING_DEFAULT_STATE;
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
		if (isBottomInsideBBox) begin // Not Y end yet ?
			if (isRightPLXmaxTri) begin // Work by pair. Is left side of pair is inside rendering area. ( < right border )
				// TODO Pixel writing logic
				// TODO Mask -> If both invalid, force next pair, without write.
				if (requestNextPixel) begin
					// Write only if pixel pair is valid...
					
					//if (maskLRValid & DrawAreaClipping) begin
					writePixelL = isInsideBBoxTriRectL /* MASK */;
					writePixelR = isInsideBBoxTriRectR /* MASK */;
					//end
					
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
		end else begin
			nextWorkState = NOT_WORKING_DEFAULT_STATE;
		end
	end
	
	// --------------------------------------------------------------------
	//   LINE STATE MACHINE
	// --------------------------------------------------------------------
	LINE_START:
	begin
		/* Line Setup, Triangle setup may be... */
		loadNext	= 1;
		selNextX	= X_LINE_START;
		selNextY	= Y_LINE_START;
		nextWorkState = GPU_REG_CheckMaskBit ? LINE_READ_MASK : LINE_DRAW;
	end
	LINE_READ_MASK:
	begin
//		readStencil	  = 1;
		nextWorkState = LINE_DRAW;
	end
	LINE_DRAW:
	begin
		/*	TODO :
			- If using blending, first request BG for current pixel.
			- Line have no texture --> Bit 15 written is always 0.   (STENCIL CACHE UPDATE TOO)
				Line / Untextured
				=> (0 | GPU_REG_ForcePixel15MaskSet) => Bit 15 write = GPU_REG_ForcePixel15MaskSet for lines. 
				Textured
				=> Texture Bit 15 | GPU_REG_ForcePixel15MaskSet
			- if (((GPU_REG_CheckMaskBit) & ReadStencil==0) | !GPU_REG_CheckMaskBit)
			
			If GPU_REG_CheckMaskBit have a READ STATE first -> (2 state/cycle per pixel)
		 */
		nextWorkState = GPU_REG_CheckMaskBit ? LINE_READ_MASK : LINE_DRAW;

		if (requestNextPixel) begin
			loadNext	= 1;
			selNextX	= X_LINE_NEXT;
			selNextY	= Y_LINE_NEXT;
			
			if ((pixelX == RegX1) && (pixelY == RegY1)) begin
				nextWorkState	= NOT_WORKING_DEFAULT_STATE; // Override nextWorkState from setup in this.
			end
			
			// If pixel is valid and (no mask checking | mask check with value = 0)
			if (isLineInsideDrawArea && ((GPU_REG_CheckMaskBit && (!selectPixelWriteMask)) || (!GPU_REG_CheckMaskBit))) begin	// Clipping DrawArea, TODO: Check if masking apply too.
				writePixelL	 = isLineLeftPix;
				writePixelR	 = isLineRightPix;
				writeStencil = 1;
			end
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

reg resetVertexCounter;
reg increaseVertexCounter;
reg loadRGB,loadUV,loadVertices,loadAllRGB;
reg storeCommand;
reg loadE5Offsets;
reg loadTexPageE1;
reg loadTexWindowSetting;
reg loadDrawAreaTL;
reg loadDrawAreaBR;
reg loadMaskSetting;
reg setIRQ;
reg rstTextureCache;
reg nextCondUseFIFO;
reg loadClutPage;
reg loadTexPage;
reg loadSize;
reg loadCoord1,loadCoord2;
reg loadRectEdge;
reg [1:0] loadSizeParam;
reg [4:0] issuePrimitive;	parameter	NO_ISSUE = 5'd0, ISSUE_TRIANGLE = 5'b000001,ISSUE_RECT = 5'b00010,ISSUE_LINE = 5'b00100,ISSUE_FILL = 5'b01000,ISSUE_COPY = 5'b10000;
wire [4:0] issuePrimitiveReal;

parameter	DEFAULT_STATE		=4'd0,
			LOAD_COMMAND		=4'd1,
			COLOR_LOAD			=4'd2,
			VERTEX_LOAD			=4'd3,
			UV_LOAD				=4'd4,
			WIDTH_HEIGHT_STATE	=4'd5,
			LOAD_XY1			=4'd6,
			LOAD_XY2			=4'd7,
			WAIT_COMMAND_COMPLETE = 4'd8;
			
reg  [3:0] currState,nextLogicalState;
wire [3:0] nextState;

always @(*)
begin
	// Read FIFO when fifo is NOT empty or that we can decode the next item in the FIFO.
	// TODO : Assume that FIFO always output the same value as the last read, even if read signal is FALSE ! Simplify state machine a LOT.
	loadRectEdge = 0;
	
	case (currState)
	DEFAULT_STATE:
	begin
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 1;
		increaseVertexCounter	= 0;
		storeCommand			= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		issuePrimitive			= NO_ISSUE;
		nextCondUseFIFO			= 1;
		nextLogicalState		= LOAD_COMMAND; // Need FIFO
	end
	// Step 0A
	LOAD_COMMAND:				// Here we do NOT check data validity : if we arrive in this state, we know the data is available from the FIFO, and GPU accepts commands.
	begin
		loadCoord1				= 0; loadCoord2	= 0;
		resetVertexCounter 		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 1;
		loadUV					= 0;
		loadRGB					= 1; // Work for all command, just ignored.
		loadVertices			= 0;
		loadAllRGB				= (bIgnoreColor) ? 1'b1 : (!bIsPerVtxCol);
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		setIRQ					= bIsBase0x & bIsBase1F;
		rstTextureCache			= bIsBase0x & bIsBase01;
		issuePrimitive			= NO_ISSUE;

		 // TODO : Can optimize later by using LOAD_COMMAND instead and loop...
		 // For now any command reading is MINIMUM EVERY 2 CYCLES.
		 
		// E1~E6
		if (bIsRenderAttrib) begin
			nextLogicalState	= DEFAULT_STATE;
			nextCondUseFIFO		= 0;
			
			loadE5Offsets		= (command[2:0] == 3'd5);
			loadTexPageE1		= (command[2:0] == 3'd1);
			loadTexWindowSetting= (command[2:0] == 3'd2);
			loadDrawAreaTL		= (command[2:0] == 3'd3);
			loadDrawAreaBR		= (command[2:0] == 3'd4);
			loadMaskSetting		= (command[2:0] == 3'd6);
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
		
			loadE5Offsets 		= 0;
			loadTexPageE1		= 0;
			loadTexWindowSetting = 0;
			loadDrawAreaTL		= 0;
			loadDrawAreaBR		= 0;
			loadMaskSetting		= 0;
		end
	end
	LOAD_XY1:
	begin
		loadCoord1				= 1; loadCoord2	= 0;
		// bIsCopyVVCommand		Top Left Corner   (YyyyXxxxh) then WIDTH_HEIGHT_STATE
		// bIsCopyCVCommand		Source Coord      (YyyyXxxxh) then LOAD_X2
		// bIsCopyVCCommand		Destination Coord (YyyyXxxxh) then WIDTH_HEIGHT_STATE
		// bIsFillCommand		Top Left Corner   (YyyyXxxxh) then WIDTH_HEIGHT_STATE
		
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		issuePrimitive			= NO_ISSUE;
		nextCondUseFIFO			= 1;
		nextLogicalState		= bIsCopyVVCommand ? LOAD_XY2 :  WIDTH_HEIGHT_STATE;
	end
	LOAD_XY2:
	begin
		loadCoord1				= 0; loadCoord2	= 1;
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		issuePrimitive			= NO_ISSUE;
		nextCondUseFIFO			= 1;
		nextLogicalState		= WIDTH_HEIGHT_STATE;
	end
	// Step 0B
	COLOR_LOAD:
	begin
		//
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 1;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		issuePrimitive			= NO_ISSUE;
		// Special case to test TERMINATOR (comes instead of COLOR value !!!)
		nextCondUseFIFO			= !(bIsLineCommand & bIsMultiLine & bIsTerminator);
		nextLogicalState		=  (bIsLineCommand & bIsMultiLine & bIsTerminator) ? DEFAULT_STATE : VERTEX_LOAD;
	end
	// Step 1
	VERTEX_LOAD:
	begin
		if (bIsRectCommand) begin
			// Command original 27-28 Rect Size   (0=Var, 1=1x1, 2=8x8, 3=16x16) (Rectangle only)
			if (command[4:3]==2'd0) begin
				nextCondUseFIFO		= 1;
				loadSize			= 0; loadSizeParam = 2'b0;
				nextLogicalState	= (bUseTexture) ? UV_LOAD : WIDTH_HEIGHT_STATE;
				issuePrimitive		= NO_ISSUE;
			end else begin
				if (bUseTexture) begin
					nextCondUseFIFO		= 1;
					loadSize			= 0; loadSizeParam	= 2'b0;
					nextLogicalState	= UV_LOAD;
					issuePrimitive		= NO_ISSUE;
				end else begin
					nextCondUseFIFO		= 0;
					loadSize			= 1; loadSizeParam	= command[4:3];
					nextLogicalState	= WAIT_COMMAND_COMPLETE;
					issuePrimitive		= ISSUE_RECT;
				end
			end
		end else begin
			loadSize			= 0; loadSizeParam = 2'b0;
			if (bUseTexture) begin
				// Condition with 'FifoDataValid' necessary :
				// => If not done, state machine skip the 4th vertex loading to load directly 4th texture without loading the coordinates. (fifo not valid as we waited for primitive to complete)
				nextCondUseFIFO		= 1;
				nextLogicalState	= FifoDataValid ? UV_LOAD : VERTEX_LOAD;
				issuePrimitive		= NO_ISSUE;
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
						issuePrimitive	= ISSUE_TRIANGLE;
					end else begin
						// Line/Polyline
						// If 5xxx5xxx do not issue a LINE.
						issuePrimitive	= (bIsMultiLine & bIsTerminator) ? NO_ISSUE : ISSUE_LINE;
					end
				end else begin
					// No need to check for canIssueWork because we emit the FIRST TRIANGLE in this case, so we know that the canIssueWork = 1.
					
					// Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
					// Can not issue if data is not valid.
					if (canIssueWork) begin
						if (FifoDataValid & bIsPolyCommand & canEmitTriangle) begin
							issuePrimitive		= ISSUE_TRIANGLE;
						end else begin
							if (FifoDataValid & bIsLineCommand & bIsMultiLine & bNotFirstVert) begin // Remain the case of intermediate line ONLY (single 2 vertex line handled in upper logic)
								issuePrimitive	= ISSUE_LINE;
							end else begin
								issuePrimitive	= NO_ISSUE;
							end
						end
					end else begin
						issuePrimitive	= NO_ISSUE;
					end
				
					if (bIsPerVtxCol) begin
						nextCondUseFIFO		= 1; // TODO : Fix, proposed multiline support ((issuePrimitive == NO_ISSUE) | !bIsLineCommand); // 1 before line, !bIsLineCommand is a hack. Because...
						nextLogicalState	= FifoDataValid ? COLOR_LOAD : VERTEX_LOAD; // Next Vertex or stay current vertex until loaded.
					end else begin
						nextCondUseFIFO		= (issuePrimitive == NO_ISSUE);
						nextLogicalState	= VERTEX_LOAD;	// Next Vertex stuff...
					end
				end
			end
		end
		
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		//
		// TRICKY DETAIL : When emitting multiple primitive, load the next vertex ONLY WHEN THE EMITTED COMMAND IS COMPLETED.
		//                 So we check (issuePrimitive == NO_ISSUE) when requesting next vertex.
		increaseVertexCounter	= FifoDataValid & (!bUseTexture);	// go to next vertex if do not need UVs, don't care if invalid vertex... cause no issues. PUSH NEW VERTEX ONLY IF NOT BUSY RENDERING.
		loadVertices			= (!bIsMultiLineTerminator); // Check if not TERMINATOR + line + multiline, else vertices are valid.
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadRectEdge			= bIsRectCommand;	// Force to load, dont care, override by UV if set with UV or SIZE if variable.
	end
	UV_LOAD:
	begin
		//
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= FifoDataValid & canIssueWork & (!bIsRectCommand);	// Increase vertex counter only when in POLY MODE (LINE never reach here, RECT is the only other)
		storeCommand       		= 0;
		loadUV					= canIssueWork;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= isV0; // first entry is Clut info.
		loadTexPage				= isV1; // second entry is TexPage.
		loadRectEdge			= bIsRectCommand;

		// do not issue primitive if Rectangle or 1st/2nd vertex UV.
		
		if (bIsRectCommand) begin
			// 27-28 Rect Size   (0=Var, 1=1x1, 2=8x8, 3=16x16) (Rectangle only)
			loadSizeParam			= command[4:3]; // Optimization, same as commented version.
			issuePrimitive			= (command[4:3]!=2'd0) ? ISSUE_RECT : NO_ISSUE;
			if (command[4:3]==2'd0) begin
				loadSize			= 0; // loadSizeParam <= 2'b0;
				nextCondUseFIFO		= 1;
				nextLogicalState	= WIDTH_HEIGHT_STATE;
			end else begin
				loadSize			= 1; // loadSizeParam	<= command[4:3];
				nextCondUseFIFO		= 0;
				nextLogicalState	= WAIT_COMMAND_COMPLETE;
			end
		end else begin
			loadSize 				= 0; loadSizeParam = 2'b0;
			
			// Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
			// Can not issue if data is not valid.
			if (FifoDataValid & bIsPolyCommand & canEmitTriangle & canIssueWork) begin
				issuePrimitive	= ISSUE_TRIANGLE;
			end else begin
				issuePrimitive	= NO_ISSUE;
			end
			
			if (isPolyFinalVertex) begin // Is it the final vertex of the command ? (3rd / 4th depending on command)
				// Allow to complete UV LOAD of last vertex and go to COMPLETE
				// only if we can push the triangle and that the incoming FIFO data is valid.
				nextCondUseFIFO		= !(canIssueWork & FifoDataValid);	// Instead of FIFO state, it uses
				nextLogicalState	=  (canIssueWork & FifoDataValid) ? WAIT_COMMAND_COMPLETE : UV_LOAD;	// For now, no optimization of the state machine, FIFO data or not : DEFAULT_STATE.
			end else begin
				if (bIsPerVtxCol) begin
					nextCondUseFIFO		= 1;
					nextLogicalState	= FifoDataValid ? COLOR_LOAD : UV_LOAD; // Next Vertex or stay current vertex until loaded.
				end else begin
					// Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
					// Can not issue if data is not valid.
					nextCondUseFIFO		= (issuePrimitive == NO_ISSUE);
					nextLogicalState	= VERTEX_LOAD;	// Next Vertex stuff...
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
		loadSize				= 1; loadSizeParam = SIZE_VAR;
		
		loadRectEdge			= bIsRectCommand;
		
		// TODO, just set here to avoid latching.
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		issuePrimitive			= (bIsCopyVVCommand | bIsCopyCVCommand | bIsCopyVCCommand) ? ISSUE_COPY : (bIsRectCommand ? ISSUE_RECT : ISSUE_FILL);
		nextCondUseFIFO			= 0;
		nextLogicalState		= WAIT_COMMAND_COMPLETE;
	end
	WAIT_COMMAND_COMPLETE:
	begin
		// (bIsCopyVVCommand | bIsCopyCVCommand | bIsCopyVCCommand | bIsFillCommand)
		
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		issuePrimitive			= NO_ISSUE;
		nextCondUseFIFO			= 0;
		
		nextLogicalState		=  canIssueWork ? DEFAULT_STATE : WAIT_COMMAND_COMPLETE;
	end
	default:
	begin
		loadE5Offsets			= 0; loadTexPageE1 = 0; loadTexWindowSetting = 0; loadDrawAreaTL = 0; loadDrawAreaBR = 0; loadMaskSetting = 0;
		loadCoord1				= 0; loadCoord2	= 0;
		setIRQ					= 0;
		resetVertexCounter		= 0;
		increaseVertexCounter	= 0;
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
		loadSize				= 0; loadSizeParam = 2'b0;
		issuePrimitive			= NO_ISSUE;
		nextCondUseFIFO			= 0;
		
		nextLogicalState		= DEFAULT_STATE;
	end
	endcase
end

StencilCache StencilCacheInstance(
	.clk			(clk),
	.addrWord		(stencilWordAdr),	// [19:0] : 1 MByte, [18:0] : 0.5 MegaHWord
	.writeBitSelect	(stencilWriteBitSelect),
	.writeBitValue	(stencilWriteBitValue),
	.StencilOut		(stencilReadBit)
);

// assign pixelStencilOut = selectPixelWriteMask;
always @(*)
begin
	case (pixelX[3:0])
	4'h0: selectPixelWriteMask = stencilReadBit[ 0];
	4'h1: selectPixelWriteMask = stencilReadBit[ 1];
	4'h2: selectPixelWriteMask = stencilReadBit[ 2];
	4'h3: selectPixelWriteMask = stencilReadBit[ 3];
	4'h4: selectPixelWriteMask = stencilReadBit[ 4];
	4'h5: selectPixelWriteMask = stencilReadBit[ 5];
	4'h6: selectPixelWriteMask = stencilReadBit[ 6];
	4'h7: selectPixelWriteMask = stencilReadBit[ 7];
	4'h8: selectPixelWriteMask = stencilReadBit[ 8];
	4'h9: selectPixelWriteMask = stencilReadBit[ 9];
	4'hA: selectPixelWriteMask = stencilReadBit[10];
	4'hB: selectPixelWriteMask = stencilReadBit[11];
	4'hC: selectPixelWriteMask = stencilReadBit[12];
	4'hD: selectPixelWriteMask = stencilReadBit[13];
	4'hE: selectPixelWriteMask = stencilReadBit[14];
	default: selectPixelWriteMask = stencilReadBit[15];
	endcase

	case (pixelX[3:0])
	4'h0: stencilWriteBitSelect 	= { 15'd0, writeStencil };
	4'h1: stencilWriteBitSelect 	= { 14'd0, writeStencil , 1'd0 };
	4'h2: stencilWriteBitSelect 	= { 13'd0, writeStencil , 2'd0 };
	4'h3: stencilWriteBitSelect 	= { 12'd0, writeStencil , 3'd0 };
	4'h4: stencilWriteBitSelect 	= { 11'd0, writeStencil , 4'd0 };
	4'h5: stencilWriteBitSelect 	= { 10'd0, writeStencil , 5'd0 };
	4'h6: stencilWriteBitSelect 	= {  9'd0, writeStencil , 6'd0 };
	4'h7: stencilWriteBitSelect 	= {  8'd0, writeStencil , 7'd0 };
	4'h8: stencilWriteBitSelect 	= {  7'd0, writeStencil , 8'd0 };
	4'h9: stencilWriteBitSelect 	= {  6'd0, writeStencil , 9'd0 };
	4'hA: stencilWriteBitSelect 	= {  5'd0, writeStencil ,10'd0 };
	4'hB: stencilWriteBitSelect 	= {  4'd0, writeStencil ,11'd0 };
	4'hC: stencilWriteBitSelect 	= {  3'd0, writeStencil ,12'd0 };
	4'hD: stencilWriteBitSelect 	= {  2'd0, writeStencil ,13'd0 };
	4'hE: stencilWriteBitSelect 	= {  1'd0, writeStencil ,14'd0 };
	default: stencilWriteBitSelect	= {        writeStencil, 15'd0 };
	endcase

	stencilWriteBitValue = { 16{GPU_REG_ForcePixel15MaskSet} }; // TODO : When TEXTURED => (Value of texture | GPU_REG_ForcePixel15MaskSet)... Write back a lot more complex.
end

// [BYTE PIXEL ADR FROM X/Y]
// YYYY.YYYY.YXXX.XXXX.XXX0 Byte.
// YYYY.YYYY.YXXX.XXX_.____ {  
wire [14:0]	stencilWordAdr = { pixelY[8:0], pixelX[9:4] };	// [19:0] : 1 MByte, [18:0] : 0.5 MegaHWord

								// Work by 16 HWord (pixels) => [14:0] 32k x 16 pixel block (32 byte => 16 bit cache)
reg [15:0]	stencilWriteBitSelect, stencilWriteBitValue;
wire [15:0] stencilReadBit;
reg         selectPixelWriteMask;


// TODO OPTIMIZE : can probably compute nextCondUseFIFO outside with : (nextLogicalState != WAIT_COMMAND_COMPLETE) & (nextLogicalState != DEFAULT_STATE)

// WE Read from the FIFO when FIFO has data, but also when the GPU is not busy rendering, else we stop loading commands...
// By blocking the state machine, we also block all the controls more easily. (Vertex loading, command issue, etc...)
wire canReadFIFO			= isFifoNotEmpty & canIssueWork;
wire readFifo				= (nextCondUseFIFO & canReadFIFO);
assign nextState			= ((!nextCondUseFIFO) | readFifo) ? nextLogicalState : currState;
assign issuePrimitiveReal	= canIssueWork ? issuePrimitive : NO_ISSUE;




wire isV0 = ((!bIsLineCommand) & (vertCnt == 2'd0) | (vertCnt == 2'd3)) | (bIsLineCommand & !vertCnt[0]); // Vertex 4 primitive load in zero for second triangle.
wire isV1 = ((!bIsLineCommand) & (vertCnt == 2'd1)                    ) | (bIsLineCommand &  vertCnt[0]);
wire isV2 =  (!bIsLineCommand) & (vertCnt == 2'd2);

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
	
	case (loadSizeParam)
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
		if (isV0 & loadVertices) RegX0 = fifoDataOutX;
		if (isV0 & loadVertices) RegY0 = fifoDataOutY;
		if (isV0 & loadUV	   ) RegU0 = fifoDataOutUR;
		if (isV0 & loadUV      ) RegV0 = fifoDataOutVG;
		if ((isV0|loadAllRGB) & loadRGB) begin
			RegR0 = loadComponentR;
			RegG0 = loadComponentG;
			RegB0 = loadComponentB;
		end
			
		if (isV1 & loadVertices) RegX1 = fifoDataOutX;
		if (isV1 & loadVertices) RegY1 = fifoDataOutY;
		if (loadRectEdge) begin
			RegX1 = rightEdgeRect;
			RegY1 = RegY0;
			RegX2 = RegX0;
			RegY2 = bottomEdgeRect;
		end
		if (isV1 & loadUV	   ) RegU1 = fifoDataOutUR;
		if (isV1 & loadUV      ) RegV1 = fifoDataOutVG;
		if ((isV1|loadAllRGB) & loadRGB) begin
			RegR1 = loadComponentR;
			RegG1 = loadComponentG;
			RegB1 = loadComponentB;
		end
		
		if (isV2 & loadVertices) RegX2 = fifoDataOutX;
		if (isV2 & loadVertices) RegY2 = fifoDataOutY;
		if (isV2 & loadUV	   ) RegU2 = fifoDataOutUR;
		if (isV2 & loadUV      ) RegV2 = fifoDataOutVG;
		if ((isV2|loadAllRGB) & loadRGB) begin
			RegR2 = loadComponentR;
			RegG2 = loadComponentG;
			RegB2 = loadComponentB;
		end

// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
//		if (loadTexPage)  RegTx = fifoDataOutTex;

		if (loadClutPage) RegC  = fifoDataOutClut;
	//	Better load and add W to RegX0,RegY0,RegX1=RegX0+W ? Same for Y1.
		if (loadSize) begin
			RegSizeW = widthNext;
			RegSizeH = heightNext;
			if (writeOrigHeight) begin
				OriginalRegSizeH = heightNext;
			end
		end
		if (loadCoord1) begin
			RegX0 = { 2'd0 , (bIsFillCommand) ? { fifoDataOutWidth[9:4], 4'b0} : fifoDataOutWidth};
			RegY0 = { 3'd0 , fifoDataOutHeight };
		end
		if (loadCoord2) begin
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
wire signed [11:0]	preB 	= preB13[11:0];
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
wire				isBottomInsideBBox	= pixelY  <= maxTriDAY1; // PIXEL IS INCLUSIVE

wire				isLeftPLXInside	= LPixelX >= extDAX0;
wire				isLeftPRXInside	= RPixelX >= extDAX0;
wire				isRightPLXInside= LPixelX  < extDAX1; // PIXEL IS EXCLUSIVE
wire				isRightPRXInside= RPixelX  < extDAX1; // PIXEL IS EXCLUSIVE
// [NEEDED FOR TRIANGLE AND RECTANGLE] : Intersection of draw area AND bounding box.
wire				isLeftPLXminTri = LPixelX >= minTriDAX0;
wire				isLeftPRXminTri = RPixelX >= minTriDAX0;
wire				isRightPLXmaxTri= LPixelX <= maxTriDAX1; // PIXEL IS INCLUSIVE
wire				isRightPRXmaxTri= RPixelX <= maxTriDAX1; // PIXEL IS INCLUSIVE

wire				isValidHorizontal			= isTopInside     & isBottomInside;
wire				isValidHorizontalTriBbox	= isTopInsideBBox & isBottomInsideBBox;

// Test Current Pixel For Line primitive : Check vertically against the DRAW AREA and select the pixel in the PAIR (odd/even) that match the result of the pixel we want to test.
wire				isLineRightPix			= ( pixelX[0] & isLeftPRXInside & isRightPRXInside);
wire				isLineLeftPix			= (!pixelX[0] & isLeftPLXInside & isRightPLXInside);
wire				isLineInsideDrawArea	= isValidHorizontal & (isLineRightPix | isLineLeftPix);
// Is Inside Triangle & Box rendering (Draw Area Inter. BBox)
wire				isInsideBBoxTriRectL	= isValidHorizontalTriBbox & isLeftPLXminTri & isRightPLXmaxTri;
wire				isInsideBBoxTriRectR	= isValidHorizontalTriBbox & isLeftPRXminTri & isRightPRXmaxTri;
wire				isValidPixelL	= (isCCWInsideL | isCWInsideL) & isInsideBBoxTriRectL;
wire				isValidPixelR	= (isCCWInsideR | isCWInsideR) & isInsideBBoxTriRectR;

// --- For Triangle ---
// Bounding box triangle.
// Vertex0/Vertex1 Box
wire signed [11:0]	minX0X1 = isNegXAxis   ? RegX1 : RegX0;
wire signed [11:0]	maxX0X1 = isNegXAxis   ? RegX0 : RegX1;
wire signed [11:0]	minY0Y1 = isNegYAxis   ? RegY1 : RegY0;
wire signed [11:0]	maxY0Y1 = isNegYAxis   ? RegY0 : RegY1;
// Vertex0/1/2 Box
wire signed [11:0]	minXTri = RegX2 < minX0X1 ? RegX2 : minX0X1;
wire signed [11:0]	minYTri = RegY2 < minY0Y1 ? RegY2 : minY0Y1;
wire signed [11:0]	maxXTri = RegX2 > maxX0X1 ? RegX2 : maxX0X1;
wire signed [11:0]	maxYTri = RegY2 > maxY0Y1 ? RegY2 : maxY0Y1;

// Primitive Size
wire invalidX2X0   = !((preA13[12:10]==  3'b000) | (preA13[12:10]==  3'b111));
wire invalidX1X0   = !((   c13[12:10]==  3'b000) | (   c13[12:10]==  3'b111));
wire invalidY2Y0   = !((preB13[12: 9]== 4'b0000) | (preB13[12: 9]== 4'b1111));
wire invalidY1Y0   = !((   d13[12: 9]== 4'b0000) | (   d13[12: 9]== 4'b1111));
wire rejectTriSize = invalidX1X0 | invalidX2X0 | invalidY1Y0 | invalidY2Y0; // 1023 pixel in --> direction, 1024 pixel in <-- direction, 511 pixel in V direction, -512 pixel in ^ direction.
// Bounding box vs Draw Area.
wire				earlyTriRejectLeft   = maxXTri  < extDAX0;
wire				earlyTriRejectTop    = maxYTri  < extDAY0;
wire				earlyTriRejectRight  = minXTri >= extDAX1;
wire				earlyTriRejectBottom = minYTri >= extDAY1;
/* PERFORMANCE OPTIMIZATION
wire				earlyLineRejectLeft  = maxX0X1  < extDAX0;
wire				earlyLineRejectTop   = maxY0Y1  < extDAY0;
wire				earlyLineRejectRight = minX0X1 >= extDAX1;
wire				earlyLineRejectBottom= minY0Y1 >= extDAY1;
*/
wire				earlyTriangleReject  = earlyTriRejectLeft | earlyTriRejectRight | earlyTriRejectTop | earlyTriRejectBottom | rejectTriSize;
wire				earlyLineReject      = invalidX1X0 | invalidY1Y0 /* | earlyLineRejectLeft | earlyLineRejectTop | earlyLineRejectRight | earlyLineRejectBottom */;

// Thanks to earlyTriangleReject, we know the box are intersecting.
// We know that Box is properly oriented (Min < Max), we assume that DrawArea X0 < X1 too.
wire signed [11:0]	minTriDAX0 = minXTri  < extDAX0 ?  extDAX0    : minXTri;
wire signed [11:0]	maxTriDAX1 = maxXTri >= extDAX1 ? (extDAX1 + {12'hFFF}) : maxXTri; // TODO : Do X1-1/Y1-1 at register setup, and change all test for X1/Y1
wire signed [11:0]	minTriDAY0 = minYTri  < extDAY0 ?  extDAY0    : minYTri;
wire signed [11:0]	maxTriDAY1 = maxYTri >= extDAY1 ? (extDAY1 + {12'hFFF}) : maxYTri;

// --- For Lines
// Setup Line
wire                isNegXAxis = c[11];
wire                isNegYAxis = d[11];
wire        [11:0]  absXAxis   = isNegXAxis ? negc : c;
wire        [11:0]  absYAxis   = isNegYAxis ? negd : d;
wire                swapAxis   = absYAxis > absXAxis;
wire signed [11:0]  aDX2       = swapAxis ? absYAxis : absXAxis;
wire signed [11:0]  aDY2       = swapAxis ? absXAxis : absYAxis;
wire        [13:0]  initialD   = { 1'b0 ,aDY2, !swapAxis };

// Runtime Line
wire                changeDir  = DLine > { 2'b0 , aDX2 };
wire        [12:0]  incrDOff   = (~{ aDX2, 1'b0 }) + 13'd1; // -2 * aDX2
wire        [13:0]  incrD      = { 1'b0, aDY2, 1'b0 } + (changeDir ? { incrDOff[12] , incrDOff } : 14'd0);
wire                incXOK     = (changeDir &  (swapAxis)) | (!swapAxis);
wire                incYOK     = (changeDir & (!swapAxis)) |   swapAxis;
wire signed  [1:0]  stepX      = { isNegXAxis & incXOK, incXOK }; // -1/+1 when needed, or 0.
wire signed  [1:0]  stepY      = { isNegYAxis & incYOK, incYOK }; // -1/+1 when needed, or 0.
wire signed [11:0]  incrX      = { {10{stepX[1]}}, stepX };
wire signed [11:0]  incrY      = { {10{stepY[1]}}, stepY };
wire signed [11:0]  nextLineX  = pixelX + incrX;
wire signed [11:0]  nextLineY  = pixelY + incrY;
wire signed [13:0]  nextD      = DLine + incrD;
reg  signed [13:0]  DLine;

// ----

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

parameter PREC = 11;
parameter PRECM1 = PREC-1;
parameter ZERO_PREC = 20'd0, ONE_PREC = 20'h800;

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
always @(posedge clk)
begin
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

parameter EQUMSB = 22; // 11bit signed * 11 bit signed.
 
// EQUMSB=22
// D12(e   ,f)-> isTopLeft(D12) -> f    < 0 || (   f == 0) & e    < 0
// D20(nega,b)-> isTopLeft(D20) -> b    < 0 || (   b == 0) & nega < 0
// D01(c,negd)-> isTopLeft(D01) -> negd < 0 || (negd == 0) & c    < 0
wire isTopLeftD12 =    f[11] | ((   f == 12'd0) &    e[11]);
wire isTopLeftD01 = negd[11] | ((negd == 12'd0) &    c[11]);
wire isTopLeftD20 =    b[11] | ((   b == 12'd0) & nega[11]);

wire signed [EQUMSB:0] bias0= {23{isTopLeftD12}}; // -1 if true, 0 if false.
wire signed [EQUMSB:0] bias1= {23{isTopLeftD01}};
wire signed [EQUMSB:0] bias2= {23{isTopLeftD20}};

wire signed [EQUMSB:0] w0L	= (   e*distYV1) + (   f*distXV1) + bias0;
wire signed [EQUMSB:0] w1L	= (nega*distYV2) + (   b*distXV2) + bias1;
wire signed [EQUMSB:0] w2L	= (   c*distYV0) + (negd*distXV0) + bias2;

wire signed [EQUMSB:0] w0R	= w0L + { {11{f[11]}}, f};
wire signed [EQUMSB:0] w1R	= w1L + { {11{b[11]}}, b};
wire signed [EQUMSB:0] w2R	= w2L + { {11{negd[11]}}, negd};

/*
	[Original Implementation in Avocado, based on the famous Ryg article about rasterization.]
	if ((w0L | w1L | w2L) > 0) {    but Avocado always garantee CCW oriented polygon.
	
	First, we can notice that the condition does not seems accurate :
	By 'oring' we allow one or two line equation >= 0 if another is > 0.
	
	HW implementation of >= 0 is a LOT easier.
	Did not change a simple pixel on basic triangle I tested.
	
	For opposite orientation, I use the opposite < 0.
 */
wire isCCWInsideL = !(w0L[EQUMSB] | w1L[EQUMSB] | w2L[EQUMSB]);
wire isCWInsideL  =  (w0L[EQUMSB] & w1L[EQUMSB] & w2L[EQUMSB]);

wire isCCWInsideR = !(w0R[EQUMSB] | w1R[EQUMSB] | w2R[EQUMSB]);
wire isCWInsideR  =  (w0R[EQUMSB] & w1R[EQUMSB] & w2R[EQUMSB]);

//
// [Component Interpolation Out]
//
wire signed [PREC+8:0] roundComp = { 9'd0, 1'b1, 10'd0}; // PRECM1'd0
wire signed [PREC+8:0] offR = (distXV0*RSX) + (distYV0*RSY) + roundComp;
wire signed [PREC+8:0] offG = (distXV0*GSX) + (distYV0*GSY) + roundComp;
wire signed [PREC+8:0] offB = (distXV0*BSX) + (distYV0*BSY) + roundComp;
wire signed [PREC+8:0] offU = (distXV0*USX) + (distYV0*USY) + roundComp[PREC+7:0];
wire signed [PREC+8:0] offV = (distXV0*VSX) + (distYV0*VSY) + roundComp[PREC+7:0];

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


// TODO bAcceptPrimitive flag for previous stage.
// Triangle setup.
// Rectangle setup. => Use 4th line equation.
// TODO Own state machine here... need multiple cycle to process the interpolant for RGBUV
//			Probably pipelined division...
//			End up with the following registers :
//				UX UY UR UG UB = Value to add for screen space X or Y 1 pixel
// 

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

// TODO : When testing inside pixel, compute the screen space pixel adress 1 cycle sooner, IF Stencil compare ACTIVATED AND compare the Stencil cache result = 1. CAN early REJECT pixel.
//			Note take care of that logic for line / rect too.

wire [8:0] aR = pixRL + pixRR + pixUR;
wire [8:0] aG = pixGL + pixGR + pixVR;
wire [8:0] aB = pixBL + pixBR + pixVL + pixUL;
assign red   = aR[8:1];
assign green = aG[8:1];
assign blue  = aB[8:1];
//	assign green = (|PrimClut) ? VtxY2 + VtxY1 + VtxY0 : VtxG0 + VtxG1 + VtxG2;
//	assign blue  = (|RegSizeW & |RegSizeH) ? VtxU2 + VtxU1 + VtxU0 : VtxB0 + VtxB1 + VtxB2;
endmodule

