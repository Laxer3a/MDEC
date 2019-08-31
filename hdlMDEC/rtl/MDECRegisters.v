module MDECRegisters (
	// System
	input					i_clk,
	input					i_nrst,

	output					o_DMA0WriteRequest,	// Write Reg0
	output					o_DMA1ReadRequest,	// Read  Reg0
	
	// Input
	input					i_regSelect,	// +0 or +4
	input					i_write,
	input					i_read,
	input	[31:0]			i_valueIn,
	output	[31:0]			o_valueOut
);

	wire outFifoHasData;
	wire inFifoFull;
	wire canInputData;
	wire commandBusy;
	wire [31:0] reg0Out;

	// Command Setup
	reg  [1:0]  regPixelFormat;
	reg  		regPixelSigned;
	reg  		regPixelSetAlpha;
	reg [16:0]	remaining32BitWord;
	reg			regLoadChromaQuant;
	reg			regAllowDMA0,regAllowDMA1;
	reg			regWaitCommand;
	reg  [4:0]	regCounter;
	
	// --- State Machine ---
	reg  [2:0]	state,nextState;
	// First value is DC, Other values are AC.
	parameter	WAIT_COMMAND=3'd0, LOAD_STREAM=3'd1, LOAD_COS=3'd2, LOAD_LUMA=3'd3, LOAD_CHROMA=3'd4;
	// ---------------------
	reg			pRegSelect;
	
	
	// ---------------------------------------------------------------------------------------------------
	// TODO : FIFO reg0 write FIFO.
	// writeReg0 = fifo.hasData
	//
	wire [31:0] fifoOut = i_valueIn;
//	wire        fifoRead= fifo.hasData && ((state == LOAD_STREAM) || ((state != LOAD_STREAM) && (allowLoad)))
	wire		fifoData= i_write; // TODO pipe(fifoRead)
	// ---------------------------------------------------------------------------------------------------

	wire writeReg1		=   i_regSelect  && i_write;
	
	wire nResetChip		= (i_nrst) || (!(writeReg1 & i_valueIn[31])); // Inverse Reset <- 31 Reset MDEC (0=No change, 1=Abort any command, and set status=80040000h)

	wire writeReg0		= (!i_regSelect) && fifoData;
	wire comm1			= (fifoOut[31:29] == 3'b001);
	wire comm2			= (fifoOut[31:29] == 3'b010);
	wire comm3			= (fifoOut[31:29] == 3'b011);

	always @(posedge i_clk)
	begin
		if (nResetChip) begin
			regPixelFormat   	<= 2'b00;
			regPixelSigned   	<= 0;
			regPixelSetAlpha 	<= 0;
			regLoadChromaQuant	<= 0; // Safer but not necessary.
			remaining32BitWord 	<= 17'h0;
			
			regAllowDMA0		<= 0; // IS DEFAULT CORRECT ?
			regAllowDMA1		<= 0;
			
			regWaitCommand		<= 1;
			state				<= WAIT_COMMAND;
			pRegSelect			<= 0;
		end else begin
			pRegSelect			<= i_regSelect;
			if (writeReg0 && (state == WAIT_COMMAND)) begin
				// -- Read from FIFO
				// Register are updated for ANY command.
				regPixelFormat		<= fifoOut[28:27];
				regPixelSigned		<= fifoOut[26];
				regPixelSetAlpha	<= fifoOut[25];
				regLoadChromaQuant	<= fifoOut[0];
				
				// TODO : Check with a real PSX if value decremented when uploading COS / QUANT (test QUANT 1/2) table with CPU... 64 entry = 64/128 byte or 64 short(COS) 
				//        Would make a LOT of sense to use this counter and avoid having regCounter !!! Then change incrementing to decrementing.
				remaining32BitWord	<= {(comm2 | comm3) ? 16'd64 : fifoOut[15:0], 1'b0};
			end
			if (writeReg1) begin
				// -- Read from Data In directly.
				regAllowDMA0		<= i_valueIn[30]; // 30    Enable Data-In Request  (0=Disable, 1=Enable DMA0 and Status.bit28)
				regAllowDMA1		<= i_valueIn[29]; // 29    Enable Data-Out Request (0=Disable, 1=Enable DMA1 and Status.bit27)
			end
			state <= nextState;
		end
	end
	
	reg resetCounter;
	reg incrementCounter;
	
	always @(posedge i_clk)
	begin
		if (resetCounter) begin
			regCounter <= 5'd0;
		end else if (incrementCounter) begin
			regCounter <= regCounter + 1;
		end
	end
	
	wire		i_cosWrite	= writeReg0 && (state == LOAD_COS);
	wire [4:0]	i_cosIndex	= regCounter;	// 5 bit. [0..31]
	wire [25:0]	i_cosVal	= { fifoOut[28:16] , fifoOut[12:0]};
	
	wire 		i_quantWrt	= writeReg0 && ((state == LOAD_LUMA) || (state == LOAD_CHROMA));
	wire [3:0]	i_quantAdr	= regCounter[3:0];
	wire [27:0]	i_quantVal	= {fifoOut[30:24],fifoOut[22:16],fifoOut[14:8],fifoOut[6:0]};
	wire i_quantTblSelect	= regCounter[4];
	
	wire        writeStream = writeReg0 && (state == LOAD_STREAM);
	always @(*)
	begin
        case (state)
		default: // ,WAIT_COMMAND: (included)
		begin
			resetCounter     = 1;
			incrementCounter = 0;
			if (writeReg0 && (comm1 | comm2 | comm3)) begin
				nextState = comm1 ? LOAD_STREAM : (comm2 ? LOAD_LUMA : LOAD_COS);
			end else begin
				nextState = WAIT_COMMAND;
			end
		end
		LOAD_STREAM:
		begin
			// ---------------------------------------------
			// TODO State machine and RLE feed...
			// ---------------------------------------------
			resetCounter     = 0;
			incrementCounter = 0; // TODO.
		end
		LOAD_COS:
		begin
			resetCounter     = 0;
			if (writeReg0) begin
				if (regCounter == 5'd31) begin
					nextState		 = WAIT_COMMAND;
				end else begin
					nextState 		 = LOAD_COS;
				end
				incrementCounter = 1;
			end else begin
				nextState = LOAD_COS;
				incrementCounter = 0;
			end
		end
		LOAD_LUMA:
		begin
			resetCounter     = 0;
			if (writeReg0) begin
				if (regCounter[3:0] == 4'd15) begin
					if (regLoadChromaQuant) begin // 
						nextState		 = LOAD_CHROMA;
					end else begin
						nextState		 = WAIT_COMMAND;
					end
				end else begin
					nextState 		 = LOAD_LUMA;
				end
				incrementCounter = 1;
			end else begin
				nextState = LOAD_LUMA;
				incrementCounter = 0;
			end
		end
		LOAD_CHROMA:
		begin
			resetCounter     = 0;
			if (writeReg0) begin
				if (regCounter[3:0] == 4'd15) begin
					nextState		 = WAIT_COMMAND;
				end else begin
					nextState 		 = LOAD_CHROMA;
				end
				incrementCounter = 1;
			end else begin
				nextState = LOAD_CHROMA;
				incrementCounter = 0;
			end
		end
        endcase
	end
	
	wire allowLoad;
	wire [15:0] streamIn = remaining32BitWord[0] ? fifoOut[31:16] : fifoOut[15:0];
	wire unusedForNow;
	wire [1:0]  outPixelFormat;
	MDECore mdecInst (
		// System
		.clk			(i_clk),
		.i_nrst			(nResetChip),

		// Setup
		.i_bitSetupDepth(regPixelFormat),
		.i_bitSigned	(regPixelSigned),
		
		// RLE Stream
		.i_dataWrite	(writeStream),
		.i_dataIn		(streamIn),
		.o_allowLoad	(allowLoad),
		
		// Loading of COS Table (Linear, no zigzag)
		.i_cosWrite		(i_cosWrite),
		.i_cosIndex		(i_cosIndex),
		.i_cosVal		(i_cosVal),
		
		// Loading of quant Matrix
		.i_quantWrt		(i_quantWrt),
		.i_quantValue	(i_quantVal),
		.i_quantAdr		(i_quantAdr),
		.i_quantTblSelect(i_quantTblSelect),

		.o_stillIDCT	(commandBusy),
		.o_stillPushingPixel (unusedForNow),	// TODO
		
		.o_depth		(outPixelFormat),
		.o_pixelOut		(wrtPix),
		.o_pixelAddress	(pixIdx), // 16x16 or 8x8 [yyyyxxxx] or [0yyy0xxx]
		.o_rComp		(r),
		.o_gComp		(g),
		.o_bComp		(b)
	);
	
	wire [2:0] currentBlock; // TODO
	wire wrtPix;
	wire [7:0] pixIdx,r,g,b;

	RGB2Fifo RGBFifo_inst(
		.i_clk			(i_clk),
		.i_nrst			(nResetChip),
		
		.i_wrtPix		(wrtPix),
		.format			(outPixelFormat),
		.setBit15		(regPixelSetAlpha),
		.i_pixAdr		(pixIdx),
		.i_r			(r),
		.i_g			(g),
		.i_b			(b),

		.i_readFifo		(i_read),
		.o_fifoHasData	(outFifoHasData),
		.o_dataOut		(reg0Out)
	);

	// Reset State : 0x80040000 [31:Fifo Empty] | [17: 4bit -> Y=4]
	wire [31:0] reg1Out;
	assign reg1Out[31]		= !outFifoHasData;										// 31    Data-Out Fifo Empty (0=No, 1=Empty)
	assign reg1Out[30]		= inFifoFull;											// 30    Data-In Fifo Full   (0=No, 1=Full, or Last word received)
	assign reg1Out[29]		= commandBusy;											// 29    Command Busy  (0=Ready, 1=Busy receiving or processing parameters)
	assign reg1Out[28]		= canInputData & regAllowDMA0;							// 28    Data-In Request  	(set when DMA0 enabled and ready to receive data)
																					// Note : Should be DMA job to check this bit, but CPU seems to expect this flag to be ZERO.
																					// And DMA will read this register AS IS.
	assign reg1Out[27]		= outFifoHasData & regAllowDMA1;						// 27    Data-Out Request	(set when DMA1 enabled and ready to send data)
	assign reg1Out[26:25]	= regPixelFormat;										// 26-25 Data Output Depth  (0=4bit, 1=8bit, 2=24bit, 3=15bit)      ;CMD.28-27
	assign reg1Out[24]		= regPixelSigned;										// 24    Data Output Signed (0=Unsigned, 1=Signed)                  ;CMD.26
	assign reg1Out[23]		= regPixelSetAlpha;										// 23    Data Output Bit15  (0=Clear, 1=Set) (for 15bit depth only) ;CMD.25
	assign reg1Out[22:19]	= 4'b0000;												// 22-19 Not used (seems to be always zero)
	assign reg1Out[18:16]	= currentBlock;											// 18-16 Current Block (0..3=Y1..Y4, 4=Cr, 5=Cb) (or for mono: always 4=Y)
	assign reg1Out[15: 0]	= remaining32BitWord[16:1];								// 15-0  Number of Parameter Words remaining minus 1  (FFFFh=None)  ;CMD.Bit0-15
	
	assign o_valueOut		= pRegSelect ? reg1Out : reg0Out;
endmodule
