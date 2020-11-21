module DMAChannel
(	
	input			i_clk,
	input			i_nrst,
	
	// ----------------------------------------------------------
	// Controller side... [TODO LOGIC, Add signals here...]
	input			DREQ,
	output			DACK,
	output	[23:0]	dmaAddr,
	// ----------------------------------------------------------
	
	//
	// CPU Side
	//
	input			i_select,
	input	[1:0]	i_adr,
	input	[31:0]	i_data,
	input			i_write,
	input			i_read,
	output	[31:0]	o_data
);

typedef enum logic { TO_RAM  =1'b0, FROM_RAM =1'b1 	} ETRANSFER;
typedef enum logic { PL4_STEP=1'b0, MIN4_STEP=1'b1 	} ESTEP;
typedef enum logic { NO_CHOP =1'b0, CHOPPING =1'b1	} ECHOPPING;
typedef enum logic[1:0] { 
	AT_ONCE  = 2'd0,			// OTC / CDROM
	SYNC2DMA = 2'd1,			// MDEC/SPU/GPU VRAM
	LINK_LIST= 2'd2,			// GPU Commandlist
	RESERVE  = 2'd3 								} ESYNCMODE;

reg	[23:0]				baseAddr;
reg	[16:0]				wordCount;
reg	[16:0]				currWordCount;
reg	[15:0]				blkCount;

ETRANSFER				transferDirection;
ESTEP					step;
ECHOPPING				choppingEnable;
ESYNCMODE				syncMode;

reg	[2:0]				choppingDMAWindowSize;
reg	[2:0]				choppingCPUWindowSize;
reg						start_Enable_Busy;

reg						startTriggerManual;
reg						unknown_pause_SyncMode0Only;
reg						unknown2;

// wire [23:0] nextBaseAddr = ...;
// 1F8010F4 : DICR, bit15 -> Force IRQ


wire 		setupDMA	= i_select &  i_write;
wire		readDMAReg	= i_select & !i_write;
wire        hasZeros    = !(|i_data[15:0]);

always @(posedge i_clk)
begin
	if (i_nrst == 1'b0) begin
		baseAddr 				<= 24'd0;
		wordCount				<= 17'd0;
		blkCount 				<= 16'd0;
		transferDirection		<= ETRANSFER'(1'd0);
		step					<= ESTEP'	(1'd0);
		choppingEnable			<= ECHOPPING'(1'd0);
		syncMode				<= ESYNCMODE'(2'd0);
		choppingDMAWindowSize	<= 3'd0;
		choppingCPUWindowSize	<= 3'd0;
		start_Enable_Busy		<= i_data[24];		// TODO : Weird, can not set zero while doing something... only write '1' ?
		startTriggerManual		<= i_data[28];
		unknown_pause_SyncMode0Only	<= i_data[29];
		unknown2				<= i_data[30];
	end else begin
		if (setupDMA) begin
			case (i_adr[1:0])
			2'd0: baseAddr 				<= i_data[23: 0];
			2'd1: begin
					  wordCount				<= { hasZeros, i_data[15: 0]};
					  blkCount 				<= i_data[31:16];
				  end
			2'd2: begin
					  transferDirection		<= ETRANSFER'(i_data[0]);
					  step					<= ESTEP'(i_data[1]);
					  choppingEnable		<= ECHOPPING'(i_data[8]);
					  syncMode				<= ESYNCMODE'(i_data[10:9]);
					  choppingDMAWindowSize	<= i_data[18:16];
					  choppingCPUWindowSize	<= i_data[22:20];
					  start_Enable_Busy		<= i_data[24];		// TODO : Weird, can not set zero while doing something... only write '1' ?
					  startTriggerManual	<= i_data[28];
					  unknown_pause_SyncMode0Only	<= i_data[29];
					  unknown2				<= i_data[30];
				  end
			2'd3: // [Do nothing]
				  begin
				  end
			endcase
		end
	end
end

reg [31:0] vOut;
always@(*) begin
	// Read those registers setup...
	case (i_adr[1:0])
	2'd0: vOut = { 8'd0, baseAddr };
	2'd1: vOut = { blkCount
				 , wordCount[15:0] }; // TODO : What about runtime ? What about SyncMode ? May be not wordCount...
	2'd2: vOut = {
					{1'b0}
					,unknown2
					,unknown_pause_SyncMode0Only
					,startTriggerManual
					,{3'd0}
					,start_Enable_Busy
					,{1'b0}
					,choppingCPUWindowSize
					,{1'b0}
					,choppingDMAWindowSize
					,{5'd0}
					,syncMode
					,choppingEnable
					,{6'd0}
					,step
					,transferDirection
				 };
	default: vOut = 32'd0; // TODO : What is done ?
	endcase
end
assign o_data = vOut;
endmodule




// ----------------------------------------------------------
//   All the Channels
// ----------------------------------------------------------
module DMAController
(	
	input			i_clk,
	input			i_nrst,
	
	// ----------------------------------------------------------
	// Controller side... [TODO LOGIC, Add signals here...]
	input	[6:0]	DREQ,
	output	[6:0]	DACK,
	output	[23:0]	dmaAddr,
	//
	// ALL CHIP INCOMING/OUTGOING DATA 32 BIT / 16 BIT
	//
	// ----------------------------------------------------------
	
	//
	// CPU Side
	//
	input			i_CS,
	input	[4:0]	i_adr_W32,	// 32 Word of 32 bit.
	input	[31:0]	i_data,
	input			i_write,
	input			i_read,
	output	[31:0]	o_data
);

/*
  1F80108xh DMA0 channel 0  MDECin  (RAM to MDEC)
  1F80109xh DMA1 channel 1  MDECout (MDEC to RAM)
  1F8010Axh DMA2 channel 2  GPU (lists + image data)
  1F8010Bxh DMA3 channel 3  CDROM   (CDROM to RAM)
  1F8010Cxh DMA4 channel 4  SPU
  1F8010Dxh DMA5 channel 5  PIO (Expansion Port)
  1F8010Exh DMA6 channel 6  OTC (reverse clear OT) (GPU related)
*/

wire cpuWrite = i_CS & i_write;
wire cpuRead  = i_CS & i_read;
wire [1:0] regID   = i_adr_W32[1:0];
wire [2:0] channel = i_adr_W32[4:2];
wire sel0     = channel == 3'd0;
wire sel1     = channel == 3'd1;
wire sel2     = channel == 3'd2;
wire sel3     = channel == 3'd3;
wire sel4     = channel == 3'd4;
wire sel5     = channel == 3'd5;
wire sel6     = channel == 3'd6;
wire sel7     = channel == 3'd7;

wire [31:0] dataOut[6:0];

DMAChannel DMAChannelMdecIn0 (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[0]),
	.DACK		(DACK[0]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel0),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[0])
);

DMAChannel DMAChannelMdecOut1 (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[1]),
	.DACK		(DACK[1]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel1),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[1])
);

DMAChannel DMAChannelGPU (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[2]),
	.DACK		(DACK[2]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel2),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[2])
);

DMAChannel DMAChannelCDRom (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[3]),
	.DACK		(DACK[3]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel3),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[3])
);

DMAChannel DMAChannelSPU (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[4]),
	.DACK		(DACK[4]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel4),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[4])
);

DMAChannel DMAChannelPIO (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[5]),
	.DACK		(DACK[5]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel5),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[5])
);

//
// TODO [DMA6 is not using any chip but himself to write in RAM]
//       Different beast.
//
DMAChannel DMAChannelOTC (	
	.i_clk		(i_clk),
	.i_nrst		(i_nrst),
	
	.DREQ		(DREQ[6]),
	.DACK		(DACK[6]),
	.dmaAddr	(/*TODO*/),

	.i_select	(sel5),
	.i_adr		(regID),
	.i_data		(i_data),
	.i_write	(cpuWrite),
	.i_read		(cpuRead),
	.o_data		(dataOut[6])
);

/*
  1F8010F0h DPCR - DMA Control register
  1F8010F4h DICR - DMA Interrupt register
*/
// DPCR
reg [2:0]	DMAPriority [6:0];
reg	[6:0]	masterEnable;
reg [3:0]   unknown28_31;
// DICR
reg [5:0]	unknown5_0;
reg [6:0]	IRQEnable;
reg	[6:0]	IRQFlags;
reg			IRQMasterEnable;
reg 		IRQMasterFlag;

//---------------------------------------------------
//  CPU Read OUT (Everything)
//---------------------------------------------------
reg [31:0] pDataOut;
always @(posedge i_clk) begin
	case (channel)
	// DMA CHANNELS
	3'd0 : pDataOut <= dataOut[0];
	3'd1 : pDataOut <= dataOut[1];
	3'd2 : pDataOut <= dataOut[2];
	3'd3 : pDataOut <= dataOut[3];
	3'd4 : pDataOut <= dataOut[4];
	3'd5 : pDataOut <= dataOut[5];
	3'd6 : pDataOut <= dataOut[6];
	// GLOBAL STUFF
	3'd7 : begin
		case (regID)
		2'd0   : pDataOut <= {
					unknown28_31,
					masterEnable[6],
					DMAPriority [6],
					masterEnable[5],
					DMAPriority [5],
					masterEnable[4],
					DMAPriority [4],
					masterEnable[3],
					DMAPriority [3],
					masterEnable[2],
					DMAPriority [2],
					masterEnable[1],
					DMAPriority [1],
					masterEnable[0],
					DMAPriority [0]
				};
		2'd1   : pDataOut <= {
					IRQMasterFlag,
					IRQFlags,
					IRQMasterEnable,	// 1 bit
					IRQEnable,			// 6 bit
					1'd0,				// TODO REAL HW ???? FORCE IRQ READ ???
					9'd0,
					unknown5_0
				};
		2'd2   : pDataOut <= 32'h7FFAC68B; // TODO (usually 7FFAC68Bh? or 0BFAC688h) change to  (changes to 7FE358D1h after DMA transfer)
		default: pDataOut <= 32'h00FFFFF7;
		endcase
	end
	endcase
end
assign o_data = pDataOut;

//---------------------------------------------------
//  CPU Write IN (Global stuff only)
//---------------------------------------------------

always @(posedge i_clk)
begin
	if (i_nrst == 1'b0) begin
	end else begin
		if (cpuWrite & sel7) begin
			case (regID)
			2'd0: begin
					unknown28_31	<= i_data[31:28];
			        masterEnable[6] <= i_data[27];
			        DMAPriority [6] <= i_data[26:24];
			        masterEnable[5] <= i_data[23];
			        DMAPriority [5] <= i_data[22:20];
			        masterEnable[4] <= i_data[19];
			        DMAPriority [4] <= i_data[18:16];
			        masterEnable[3] <= i_data[15];
			        DMAPriority [3] <= i_data[14:12];
			        masterEnable[2] <= i_data[11];
			        DMAPriority [2] <= i_data[10: 8];
			        masterEnable[1] <= i_data[ 7];
			        DMAPriority [1] <= i_data[ 6: 4];
			        masterEnable[0] <= i_data[ 3];
			        DMAPriority [0] <= i_data[ 2: 0];
				  end
			2'd1: begin
					IRQMasterFlag	<= i_data[31];
					IRQFlags		<= i_data[30:24];
					IRQMasterEnable	<= i_data[23];
					IRQEnable		<= i_data[22:16];
					// TODO BIT 15 handing ? Store ? Only execute ?
					unknown5_0		<= i_data[ 5: 0];
				  end
			default: // [Do nothing]
				  begin
				  end
			endcase
		end
	end
end
endmodule
