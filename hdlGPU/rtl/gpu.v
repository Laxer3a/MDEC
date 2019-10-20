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
	output			hSync,
	output			vSync, // cSync pin exist in real HW : hSync | vSync most likely
	output			hBlank,
	output			vBlank,
	
	// TODO Memory interface here...
	
	input			write,
	input			read,
	input 	[31:0]	cpuDataIn,
	output	[31:0]	cpuDataOut
);

wire writeFifo		= !gpuAdrA2 & gpuSel & write;
wire writeGP1		=  gpuAdrA2 & gpuSel & write;
assign ack			= !isFifoFull;
assign cpuDataOut	=  gpuAdrA2 & gpuSel & read ? reg1Out : 32'd0; // TODO other register output read... 

assign IRQRequest = GPU_REG_IRQSet;

wire [31:0] fifoDataOut;
wire isFifoFull;
wire isFifoEmpty;
wire isFifoNotEmpty = !isFifoEmpty;
wire rstInFIFO = rstGPU | rstCmd;

Fifo
#(
	.DEPTH_WIDTH	(4),
	.DATA_WIDTH		(32)
)
Fifo_inst
(
	.clk			(clk ),
	.rst			(rstInFIFO),

	.wr_data_i		(cpuDataIn),
	.wr_en_i		(writeFifo),

	.rd_data_o		(fifoDataOut),
	.rd_en_i		(readFifo),

	.full_o			(isFifoFull),
	.empty_o		(isFifoEmpty)
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
reg         [9:0] GPU_REG_DrawAreaY0; // 8:0 on old GPU.
reg         [9:0] GPU_REG_DrawAreaX1;
reg         [9:0] GPU_REG_DrawAreaY1; // 8:0 on old GPU.
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
wire signed [12:0]	fifoDataOutY= fifoDataOut[27:16] + { GPU_REG_OFFSETY[10], GPU_REG_OFFSETY };
wire signed [12:0]	fifoDataOutX= fifoDataOut[11: 0] + { GPU_REG_OFFSETX[10], GPU_REG_OFFSETX };

wire [7:0]	fifoDataOutUR		= fifoDataOut[ 7: 0]; // Same cut for R and U coordinate.
wire [7:0]	fifoDataOutVG		= fifoDataOut[15: 8]; // Same cut for G and V coordinate.
wire [7:0]	fifoDataOutB		= fifoDataOut[23:16];
wire [10:0] fifoDataOutW		= fifoDataOut[10: 0];
wire [ 9:0] fifoDataOutH    	= fifoDataOut[25:16];
wire [14:0] fifoDataOutClut		= fifoDataOut[30:16];
wire [9:0]	fifoDataOutTex		= {fifoDataOut[11],fifoDataOut[8:0]};
wire [9:0]  fifoDataOutWidth	= fifoDataOut[ 9: 0];
wire [8:0]  fifoDataOutHeight	= fifoDataOut[24:16];

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

	// TODO implement getGPUInfo.

	// [TODO List of primitive that are implemented and one that are not. Maintain an excel spreadsheet of those]
	
always @(posedge clk)
begin
	if (rstGPU) begin
		GPU_REG_OFFSETX      <= 11'd0;
		GPU_REG_OFFSETY      <= 11'd0;
		GPU_REG_TexBasePageX <= 4'd0;
		GPU_REG_TexBasePageY <= 1'b0;
		GPU_REG_Transparency <= 2'd0;
		GPU_REG_TexFormat    <= 2'd0; // TODO ??
		GPU_REG_DitherOn     <= 1'd0; // TODO ??
		GPU_REG_DrawDisplayAreaOn <= 1'b0; // Default by GP1(00h) definition.
		GPU_REG_TextureDisable <= 1'b0;
		GPU_REG_TextureXFlip <= 1'b0;
		GPU_REG_TextureYFlip <= 1'b0;
		GPU_REG_WindowTextureMaskX   <= 5'd0;
		GPU_REG_WindowTextureMaskY   <= 5'd0;
		GPU_REG_WindowTextureOffsetX <= 5'd0;
		GPU_REG_WindowTextureOffsetY <= 5'd0;
		GPU_REG_DrawAreaX0   <= 10'd0;
		GPU_REG_DrawAreaY0   <= 10'd0; // 8:0 on old GPU.
		GPU_REG_DrawAreaX1   <= 10'd1023; // TODO ??? Allow whole surface by default...
		GPU_REG_DrawAreaY1   <= 10'd1023; // TODO ??? 8:0 on old GPU.
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
		if (loadTexPageE1) begin
			GPU_REG_TexBasePageX <= fifoDataOut[3:0];
			GPU_REG_TexBasePageY <= fifoDataOut[4];
			GPU_REG_Transparency <= fifoDataOut[6:5];
			GPU_REG_TexFormat    <= fifoDataOut[8:7];
			GPU_REG_DitherOn     <= fifoDataOut[9];
			GPU_REG_DrawDisplayAreaOn <= fifoDataOut[10];
			GPU_REG_TextureDisable <= fifoDataOut[11];
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
			GPU_REG_DrawAreaY0 <= fifoDataOut[19:10]; // 8:0 on old GPU.
		end
		if (loadDrawAreaBR) begin
			GPU_REG_DrawAreaX1 <= fifoDataOut[ 9: 0];
			GPU_REG_DrawAreaY1 <= fifoDataOut[19:10]; // 8:0 on old GPU.
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

wire rejectVertex			= (fifoDataOutX[12] != fifoDataOutX[11]) | (fifoDataOutY[12] != fifoDataOutY[11]); // Primitive with offset out of range -1024..+1023
wire resetReject			= 0/*[TODO] Why ?*/;

reg  rejectPrimitive;
always @(posedge clk)
begin
	if (rejectVertex | resetReject) begin
		rejectPrimitive = !resetReject;
	end
end

// 
reg [12:0] RegX0;
reg [12:0] RegY0;
reg  [8:0] RegR0;
reg  [8:0] RegG0;
reg  [8:0] RegB0;
reg  [7:0] RegU0;
reg  [7:0] RegV0;
reg [12:0] RegX1;
reg [12:0] RegY1;
reg  [8:0] RegR1;
reg  [8:0] RegG1;
reg  [8:0] RegB1;
reg  [7:0] RegU1;
reg  [7:0] RegV1;
reg [12:0] RegX2;
reg [12:0] RegY2;
reg  [8:0] RegR2;
reg  [8:0] RegG2;
reg  [8:0] RegB2;
reg  [7:0] RegU2;
reg  [7:0] RegV2;
reg [14:0] RegC ;
reg  [9:0] RegTx;
reg  [9:0] RegSizeW,RegSX0,RegSX1;
reg  [8:0] RegSizeH,RegSY0,RegSY1;


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

reg [3:0] currWorkState;	parameter 	NOT_WORKING_DEFAULT_STATE = 4'd0, 
										LINE_START = 4'd1, LINE_DRAW = 4'd2, LINE_END = 4'd3,
										RECT_START = 4'd4,
										FILL_START = 4'd5,
										COPY_START = 4'd6,
										TRIANGLE_START = 4'd7,
										TMP_1 = 4'd8,
										TMP_2 = 4'd9,
										TMP_3 = 4'd10,
										TMP_4 = 4'd11;
reg [3:0] nextWorkState;

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

always @(*)
begin
	case (currWorkState)
	NOT_WORKING_DEFAULT_STATE:
	begin
		case (issuePrimitive)
		ISSUE_TRIANGLE:	nextWorkState = TRIANGLE_START;
		ISSUE_RECT:		nextWorkState = RECT_START;
		ISSUE_LINE:		nextWorkState = LINE_START;
		ISSUE_FILL:		nextWorkState = FILL_START;
		ISSUE_COPY:		nextWorkState = COPY_START;
		default:		nextWorkState = NOT_WORKING_DEFAULT_STATE;
		endcase
	end
	
	// TODO : Handle primitive rejection inside this state machine and jump directly to NOT_WORKING_DEFAULT_STATE.
	
	
	// --------------------------------------------------------------------
	//   FILL VRAM STATE MACHINE
	// --------------------------------------------------------------------
	FILL_START:
	begin
		nextWorkState = TMP_1;
	end
	// --------------------------------------------------------------------
	//   COPY VRAM STATE MACHINE
	// --------------------------------------------------------------------
	COPY_START:
	begin
		nextWorkState = TMP_1;
	end
	// --------------------------------------------------------------------
	//   TRIANGLE STATE MACHINE
	// --------------------------------------------------------------------
	TRIANGLE_START:
	begin
		nextWorkState = TMP_1;
	end
	// --------------------------------------------------------------------
	//   RECT STATE MACHINE
	// --------------------------------------------------------------------
	RECT_START:
	begin
		nextWorkState = TMP_1;
	end
	// --------------------------------------------------------------------
	//   LINE STATE MACHINE
	// --------------------------------------------------------------------
	LINE_START:
	begin
		nextWorkState = LINE_DRAW;
	end
	LINE_DRAW:
	begin
		nextWorkState = LINE_END;
	end
	LINE_END:
	begin
		nextWorkState = TMP_1;
	end
	// --- TEMP DEBUG STUFF ---
	TMP_1: begin nextWorkState = TMP_2; end
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
		nextLogicalState		= bIsCopyCVCommand ? LOAD_XY2 :  WIDTH_HEIGHT_STATE;
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
		loadRGB					= FifoDataValid;
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
						nextCondUseFIFO		= 1;
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
		loadVertices			= FifoDataValid & (!bIsMultiLineTerminator); // Check if not TERMINATOR + line + multiline, else vertices are valid.
		storeCommand       		= 0;
		loadUV					= 0;
		loadRGB					= 0;
		loadAllRGB				= 0;
		loadClutPage			= 0;
		loadTexPage				= 0;
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
		loadUV					= FifoDataValid & canIssueWork;
		loadRGB					= 0;
		loadVertices			= 0;
		loadAllRGB				= 0;
		loadClutPage			= isV0; // first entry is Clut info.
		loadTexPage				= isV1; // second entry is TexPage.

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
wire bNoTexture				= !bUseTexture;
wire [8:0] componentFuncRA	= componentFuncR + { 8'b00000000, fifoDataOutUR[7] & bNoTexture};
wire [8:0] componentFuncGA	= componentFuncG + { 8'b00000000, fifoDataOutVG[7] & bNoTexture};
wire [8:0] componentFuncBA	= componentFuncB + { 8'b00000000, fifoDataOutB [7] & bNoTexture};
// Finally force WHITE color (256) if no component RGB value are available. 
wire [8:0] loadComponentR	= bIgnoreColor   ? 9'b100000000 : componentFuncRA;
wire [8:0] loadComponentG	= bIgnoreColor   ? 9'b100000000 : componentFuncGA;
wire [8:0] loadComponentB	= bIgnoreColor   ? 9'b100000000 : componentFuncBA;

// TODO : SWAP bit. for loading 4th, line segment.
//
reg bPipeIssueTrianglePrimitive;

always @(posedge clk)
begin
	bPipeIssueTrianglePrimitive <= (issuePrimitiveReal == ISSUE_TRIANGLE);
	if (isV0 & loadVertices) RegX0 <= fifoDataOutX;
	if (isV0 & loadVertices) RegY0 <= fifoDataOutY;
	if (isV0 & loadUV	   ) RegU0 <= fifoDataOutUR;
	if (isV0 & loadUV      ) RegV0 <= fifoDataOutVG;
	if ((isV0|loadAllRGB) & loadRGB) begin
		RegR0 <= loadComponentR;
		RegG0 <= loadComponentG;
		RegB0 <= loadComponentB;
	end
		
	if (isV1 & loadVertices) RegX1 <= fifoDataOutX;
	if (isV1 & loadVertices) RegY1 <= fifoDataOutY;
	if (isV1 & loadUV	   ) RegU1 <= fifoDataOutUR;
	if (isV1 & loadUV      ) RegV1 <= fifoDataOutVG;
	if ((isV1|loadAllRGB) & loadRGB) begin
		RegR1 <= loadComponentR;
		RegG1 <= loadComponentG;
		RegB1 <= loadComponentB;
	end
	
	if (isV2 & loadVertices) RegX2 <= fifoDataOutX;
	if (isV2 & loadVertices) RegY2 <= fifoDataOutY;
	if (isV2 & loadUV	   ) RegU2 <= fifoDataOutUR;
	if (isV2 & loadUV      ) RegV2 <= fifoDataOutVG;
	if ((isV2|loadAllRGB) & loadRGB) begin
		RegR2 <= loadComponentR;
		RegG2 <= loadComponentG;
		RegB2 <= loadComponentB;
	end
	
	if (loadTexPage)  RegTx <= fifoDataOutTex;
	if (loadClutPage) RegC  <= fifoDataOutClut;
//	Better load and add W to RegX0,RegY0,RegX1=RegX0+W ? Same for Y1.
	if (loadSize) begin
		case (loadSizeParam)
		SIZE_VAR:
		begin
			RegSizeW = fifoDataOutWidth;
			RegSizeH = fifoDataOutHeight;
		end
		SIZE_1x1:
		begin
			RegSizeW = 10'd1;
			RegSizeH =  9'd1;
		end
		SIZE_8x8:
		begin
			RegSizeW = 10'd8;
			RegSizeH =  9'd8;
		end
		SIZE_16x16:
		begin
			RegSizeW = 10'd16;
			RegSizeH =  9'd16;
		end
		endcase
	end
	if (loadCoord1) begin
		RegSX0 = fifoDataOutWidth;
		RegSY0 = fifoDataOutHeight;
	end
	if (loadCoord2) begin
		RegSX1 = fifoDataOutWidth;
		RegSY1 = fifoDataOutHeight;
	end
end

// ---------------------------------------------------------------------------------------------------------------------
//   Next Stage : reorder and load primitive.
// ---------------------------------------------------------------------------------------------------------------------

// 4 Compare, got min,max and middle.
wire 		min01ID		= (RegY0 < RegY1);
wire [12:0] min01V		= min01ID ? RegY0 : RegY1;
wire [1:0]	TopID		= (RegY2 < min01V) ? 2'd2 : { 1'b0, min01ID} ;
wire cmp02				= (RegY2 < RegY0);
wire cmp12				= (RegY2 < RegY1);
reg  [1:0]	BottomID;
reg  [1:0]	MiddleID;

// [Compute Top/Bottom/Middle Vertex remapping]
always @(*)
begin
	case (TopID)
	2'd2: begin BottomID = { 1'b0,!min01ID };   MiddleID = { 1'b0, min01ID }; end 	 // max01ID is opposite.
	2'd1: begin BottomID = cmp02 ? 2'd0 : 2'd2; MiddleID = cmp02 ? 2'd2 : 2'd0; end // top is 1, who is bottom ? 0 or 2 ?
	2'd0: begin BottomID = cmp12 ? 2'd1 : 2'd2; MiddleID = cmp12 ? 2'd1 : 2'd2; end // top is 0, who is bottom ? 1 or 2 ?
	default: begin BottomID = 2'b00; MiddleID = 2'b00; end	// Impossible case
	endcase
end

// TODO : Could have huge switch and select based on sorted result and avoid restoring again...
//        Would mean 3 x 7 MUX instead. => Traded 3x7 Mux for 21 Registers.(207 Bits)
reg [12:0] VtxX0,VtxX1,VtxX2;
reg [12:0] VtxY0,VtxY1,VtxY2;
reg  [7:0] VtxU0,VtxU1,VtxU2,VtxV0,VtxV1,VtxV2;
reg  [8:0] VtxR0,VtxR1,VtxR2,VtxG0,VtxG1,VtxG2,VtxB0,VtxB1,VtxB2;
reg [14:0] PrimClut;
reg  [9:0] PrimTx;

// [Load Remapped Vertices info]
always @(posedge clk)
begin
	if (bPipeIssueTrianglePrimitive) begin // Need to load AFTER all Reg* are set (induce 1 clock delay)
		case (TopID)
		2'b00 : begin VtxX0 = RegX0; VtxY0 = RegY0; VtxU0 = RegU0; VtxV0 = RegV0; VtxR0 = RegR0; VtxG0 = RegG0; VtxB0 = RegB0; end
		2'b01 : begin VtxX0 = RegX1; VtxY0 = RegY1; VtxU0 = RegU1; VtxV0 = RegV1; VtxR0 = RegR1; VtxG0 = RegG1; VtxB0 = RegB1; end
		2'b10 : begin VtxX0 = RegX2; VtxY0 = RegY2; VtxU0 = RegU2; VtxV0 = RegV2; VtxR0 = RegR2; VtxG0 = RegG2; VtxB0 = RegB2; end
		2'b11 : begin VtxX0 = RegX0; VtxY0 = RegY0; VtxU0 = RegU0; VtxV0 = RegV0; VtxR0 = RegR0; VtxG0 = RegG0; VtxB0 = RegB0; end
		endcase
		case (BottomID) 
		2'b00 : begin VtxX2 = RegX0; VtxY2 = RegY0; VtxU2 = RegU0; VtxV2 = RegV0; VtxR2 = RegR0; VtxG2 = RegG0; VtxB2 = RegB0; end
		2'b01 : begin VtxX2 = RegX1; VtxY2 = RegY1; VtxU2 = RegU1; VtxV2 = RegV1; VtxR2 = RegR1; VtxG2 = RegG1; VtxB2 = RegB1; end
		2'b10 : begin VtxX2 = RegX2; VtxY2 = RegY2; VtxU2 = RegU2; VtxV2 = RegV2; VtxR2 = RegR2; VtxG2 = RegG2; VtxB2 = RegB2; end
		2'b11 : begin VtxX2 = RegX0; VtxY2 = RegY0; VtxU2 = RegU0; VtxV2 = RegV0; VtxR2 = RegR0; VtxG2 = RegG0; VtxB2 = RegB0; end
		endcase
		case (MiddleID) 
		2'b00 : begin VtxX1 = RegX0; VtxY1 = RegY0; VtxU1 = RegU0; VtxV1 = RegV0; VtxR1 = RegR0; VtxG1 = RegG0; VtxB1 = RegB0; end
		2'b01 : begin VtxX1 = RegX1; VtxY1 = RegY1; VtxU1 = RegU1; VtxV1 = RegV1; VtxR1 = RegR1; VtxG1 = RegG1; VtxB1 = RegB1; end
		2'b10 : begin VtxX1 = RegX2; VtxY1 = RegY2; VtxU1 = RegU2; VtxV1 = RegV2; VtxR1 = RegR2; VtxG1 = RegG2; VtxB1 = RegB2; end
		2'b11 : begin VtxX1 = RegX0; VtxY1 = RegY0; VtxU1 = RegU0; VtxV1 = RegV0; VtxR1 = RegR0; VtxG1 = RegG0; VtxB1 = RegB0; end
		endcase
		PrimTx   = RegTx;
		PrimClut = RegC;
	end
end

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

//	assign red   = (|PrimTx)   ? VtxX2 + VtxX1 + VtxX0 : VtxR0 + VtxR1 + VtxR2;
//	assign green = (|PrimClut) ? VtxY2 + VtxY1 + VtxY0 : VtxG0 + VtxG1 + VtxG2;
//	assign blue  = (|RegSizeW & |RegSizeH) ? VtxU2 + VtxU1 + VtxU0 : VtxB0 + VtxB1 + VtxB2;
endmodule

