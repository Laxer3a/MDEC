module MDECRegisters (
	// System
	input					i_clk,
	input					i_nrst,

	output					o_canWriteReg0,		// Write OK? (FIFO)
	output					o_DMA0WriteRequest,	// Write Reg0
	output					o_DMA1ReadRequest,	// Read  Reg0
	
	// Input
	input					i_regSelect,	// +0 or +4
	input					i_write,
	input					i_read,
	input	[31:0]			i_valueIn,
	output	[31:0]			o_valueOut
);
	wire writeReg1		=   i_regSelect  && i_write;
	wire writeReg0		= (!i_regSelect) && i_write;
	wire  resetChip		= (!i_nrst) || (writeReg1 & i_valueIn[31]); // Reset on 1 part
	wire nResetChip		= (!resetChip);								// Reset on 0 part

	/*
	. If we send a signal to block write from DMA / CPU.
	  The flag must be set BEFORE (at least 1 cycle before), else writer may simply loose a write.
	. If the FIFO is only for REG_0 with command 1 --> We can't have this specification.
	  Thus FIFO must be at the command entrance, even for COS / Quantize table logic, and other loading.
	  The other being non blocking, that should not be an issue.
	. Also, the state machine will forbid changing the table during IDCT computation.
	
	  => [FIFO is located at FRONT] before the state machine.
	*/
	// ---------------------------------------------------------------------------------------------------
	//   Input FIFO
	// ---------------------------------------------------------------------------------------------------
	reg			fifoIN_rd;
	wire 		fifoIN_full,fifoIN_empty;
	wire		fifoIN_hasData = !fifoIN_empty;
	wire [31:0]	fifoIN_output;
	
	// TODO : we assume that FIFO output the last read value always, even if read signal is not called.
	Fifo #(.DEPTH_WIDTH(5),.DATA_WIDTH(32))
	InputFIFO (
		// System
		.clk			(i_clk),
		.rst			(resetChip),

		.wr_data_i		(i_valueIn),	// Data In
		.wr_en_i		(writeReg0),	// Write Signal

		.rd_data_o		(fifoIN_output),// Data Out
		.rd_en_i		(fifoIN_rd),	// Read signal

		.full_o			(fifoIN_full),
		.empty_o		(fifoIN_empty)
	);
	
	// -------------------------------------------
	// Internal Registers / Command Setup
	// -------------------------------------------
	reg  [1:0]  regPixelFormat;
	reg  		regPixelSigned;
	reg  		regPixelSetAlpha;
	reg  [16:0]	remainingHalfWord;
	reg			regLoadChromaQuant;
	reg			regAllowDMA0,regAllowDMA1;
	
	// --- State Machine ---
	reg [2:0]	state;
	reg [2:0]	nextState;
	
	// First value is DC, Other values are AC.
	parameter	WAIT_COMMAND=3'd0, LOAD_STREAMW=3'd1, LOAD_STREAML=3'd2, LOAD_STREAMH=3'd3, LOAD_COS=3'd4, LOAD_LUMA=3'd5, LOAD_CHROMA=3'd6;
	// ---------------------
	reg			pRegSelect;
	
	wire commandBusy;
	wire [31:0] reg0Out;
	// ---------------------------------------------------------------------------------------------------

	// --- Command Related ---
	wire isCommandStream	= (fifoIN_output[31:29] == 3'b001);
	wire isCommandQuant		= (fifoIN_output[31:29] == 3'b010);
	wire isCommandCosTbl	= (fifoIN_output[31:29] == 3'b011);
	wire isColorQuant		= fifoIN_output[0];
	wire isNewCommand		= isFIFOInDataValid && (state == WAIT_COMMAND);

	// --- Counter related ----
	wire [16:0] nextRemainingHalfWord = remainingHalfWord + { 16'b1111111111111111, !decrementCounter[1] }; // -1 or -2
	reg  [1:0]  decrementCounter;
	wire isLastHalfWord		= (nextRemainingHalfWord == 17'd0);
	
	always @(posedge i_clk)
	begin
		if (resetChip) begin
			regPixelFormat   	<= 2'b00;
			regPixelSigned   	<= 0;
			regPixelSetAlpha 	<= 0;
			regLoadChromaQuant	<= 0; // Safer but not necessary.
			remainingHalfWord 	<= 17'h0;
			
			regAllowDMA0		<= 1; // TODO D CHECK : IS DEFAULT CORRECT ?
			regAllowDMA1		<= 1; // Better allow than disable ?
			
			state				<= WAIT_COMMAND;
			pRegSelect			<= 0;
		end else begin
			pRegSelect			<= i_regSelect;
			if (isNewCommand) begin
				// -- Read from FIFO
				// Register are updated for ANY command.
				regPixelFormat		<= fifoIN_output[28:27];
				regPixelSigned		<= fifoIN_output[26];
				regPixelSetAlpha	<= fifoIN_output[25];
				regLoadChromaQuant	<= isColorQuant;
				
				if (isCommandQuant) begin
					// [Unit in HALF WORD]
					remainingHalfWord <= isColorQuant ? 17'd64 : 17'd32;							// [32 word (128 byte) vs. 16 word (64 byte)] of 32 bit, but we use half word counter internally [64/32].
				end else begin
					// [Unit in WORD] << 1 -> HALF WORD
					remainingHalfWord <= {(isCommandCosTbl ? 16'd32 : fifoIN_output[15:0]), 1'b0};	//  32 word of 32 bit = 64 word of 16 bit (Cos Table)
				end
			end else begin
				if (decrementCounter != 2'b00) begin
					remainingHalfWord <= nextRemainingHalfWord;
				end
			end
			
			if (writeReg1) begin
				// -- Read from Data In directly.
				regAllowDMA0		<= i_valueIn[30]; // 30    Enable Data-In Request  (0=Disable, 1=Enable DMA0 and Status.bit28)
				regAllowDMA1		<= i_valueIn[29]; // 29    Enable Data-Out Request (0=Disable, 1=Enable DMA1 and Status.bit27)
			end
			state <= nextState;
		end
	end
		
	reg isFIFOInDataValid;
	always @(posedge i_clk)
	begin
		isFIFOInDataValid <= fifoIN_rd;
	end
		
	wire isCommandStreamValid = isCommandStream & isFIFOInDataValid;
	wire validLoad            = allowLoad & fifoIN_hasData;
	always @(*)
	begin
        case (state)
		default: // Unknown state, roll to default.
		begin
			fifoIN_rd			= 1'b0;
			decrementCounter	= 2'd0;
			nextState			= WAIT_COMMAND;
		end
		WAIT_COMMAND:
		begin
			fifoIN_rd			= validLoad; // Stream do not load in advance.
			decrementCounter	= 2'd0;
			if (isFIFOInDataValid & (isCommandStream | isCommandQuant | isCommandCosTbl)) begin
				nextState = isCommandStream ? (validLoad ? LOAD_STREAML : LOAD_STREAMW) : (isCommandQuant ? LOAD_LUMA : LOAD_COS);
			end else begin
				nextState = WAIT_COMMAND;
			end
		end
		LOAD_STREAMW:	// STATE 1 : LOAD_STREAM_WAIT.
		begin
			//
			// Do NOT launch a READ here.
			// We arrive where the data has been LOADED already... or not if FIFO is empty.
			// 
			fifoIN_rd			= validLoad;
			nextState			= validLoad ? LOAD_STREAML : LOAD_STREAMW;
			decrementCounter	= 2'd0;	// No data available in this state.
		end
		LOAD_STREAML: // STATE 2.
		begin
			// Data IS ALWAYS valid : Read initiated by W or H.
			fifoIN_rd			= 1'b0;
			decrementCounter	= 2'b00;
			if (allowLoad) begin
				nextState		= LOAD_STREAMH;
			end else begin
				// Loop until accept Half Word.
				nextState		= LOAD_STREAML;
			end
		end
		LOAD_STREAMH: // STATE 3.
		begin
			if (allowLoad) begin
				decrementCounter= 2'b01;
				fifoIN_rd		= validLoad;
				if (isLastHalfWord) begin
					nextState 	= WAIT_COMMAND;
				end else begin
					if (validLoad) begin
						nextState	= LOAD_STREAML;
					end else begin
						// Wait until data or allow is possible...
						nextState	= LOAD_STREAMW;
					end
				end
			end else begin
				// Loop until accept Half Word.
				fifoIN_rd			= 1'b0;
				nextState			= LOAD_STREAMH;
				decrementCounter	= 2'b00;
			end
		end
		LOAD_COS:
		begin
			fifoIN_rd			= fifoIN_hasData;
			decrementCounter	= { isFIFOInDataValid, 1'b0 };
			if (isFIFOInDataValid) begin
				nextState		 	= (isLastHalfWord) ? WAIT_COMMAND : LOAD_COS;
			end else begin
				nextState			= LOAD_COS;
			end
		end
		LOAD_LUMA:
		begin
			fifoIN_rd			= fifoIN_hasData;
			decrementCounter	= { isFIFOInDataValid, 1'b0 };
			if (isFIFOInDataValid) begin
				if (nextRemainingHalfWord[4:1]==4'b0000) begin
					if (regLoadChromaQuant) begin
						nextState		= LOAD_CHROMA;
					end else begin
						nextState		= WAIT_COMMAND;
					end
				end else begin
					nextState 		= LOAD_LUMA;
				end
			end else begin
				nextState = LOAD_LUMA;
			end
		end
		LOAD_CHROMA:
		begin
			fifoIN_rd			= fifoIN_hasData;
			decrementCounter	= { isFIFOInDataValid, 1'b0 };
			if (isFIFOInDataValid) begin
				if (nextRemainingHalfWord[4:1]==4'b0000) begin
					nextState		= WAIT_COMMAND;
				end else begin
					nextState 		= LOAD_CHROMA;
				end
			end else begin
				nextState = LOAD_CHROMA;
			end
		end
        endcase
	end

	//----------------------------------------------------------------------------------
	// All input signals for MDECore based on state and current FIFO output.
	//----------------------------------------------------------------------------------
	
	wire isLoadCos = (state == LOAD_COS);
	wire isLoadLum = (state == LOAD_LUMA);
	wire isLoadChr = (state == LOAD_CHROMA);
	wire isLoadStL = (state == LOAD_STREAML);
	wire isLoadStH = (state == LOAD_STREAMH);
	
	// ---- COS Loading ----
	wire		i_cosWrite	= isFIFOInDataValid && isLoadCos;
	wire [4:0]	i_cosIndex	= ~(nextRemainingHalfWord[5:1]);	// 31->0 => 0->31
	wire [25:0]	i_cosVal	= { fifoIN_output[28:16] , fifoIN_output[12:0]};
	// ---- Quantization Table Loading ----
	wire 		i_quantWrt	= isFIFOInDataValid && (isLoadLum || isLoadChr);
	wire [3:0]	i_quantAdr	= ~(nextRemainingHalfWord[4:1]);
	wire [27:0]	i_quantVal	= {fifoIN_output[30:24],fifoIN_output[22:16],fifoIN_output[14:8],fifoIN_output[6:0]};
	wire i_quantTblSelect	= isLoadLum; // Table 1 for LUMA, 0 for CHROMA.

	// ---- Stream Loading ----
	
	wire        writeStream	= (isLoadStL || isLoadStH) && allowLoad;		// Use FIFO last output, even if data is not asked.
	// FIRST BLOCK is LSB, SECOND BLOCK IS LSB
	// TODO change name of state L/H by FIRST/SECOND.
	wire [15:0] streamIn	=  isLoadStL ? fifoIN_output[15:0] : fifoIN_output[31:16];
	wire allowLoad;

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

		.i_stopFillY	(stopFill),
		.o_idctBlockNum	(currentBlock),
		.o_stillIDCT	(commandBusy),
		
		.o_pixelOut		(wrtPix),
		.o_pixelAddress	(pixIdx), // 16x16 or 8x8 [yyyyxxxx] or [0yyy0xxx]
		.o_rComp		(r),
		.o_gComp		(g),
		.o_bComp		(b)
	);
	
	wire [2:0] currentBlock; // Output for status register.
	wire wrtPix;
	wire [7:0] pixIdx,r,g,b;
	wire stopFill;

	// For now pixel format is not pipelined but use directly register setup.
	// 
	wire [1:0]  outPixelFormat = regPixelFormat;

	wire fifoOUT_hasData;
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
		.stopFill		(stopFill),

		.i_readFifo		(i_read),
		.o_fifoHasData	(fifoOUT_hasData),
		.o_dataOut		(reg0Out)
	);

	// Reset State : 0x80040000 [31:Fifo Empty] | [17: 4bit -> Y=4]
	wire [31:0] reg1Out;
	assign reg1Out[31]		= !fifoOUT_hasData;												// 31    Data-Out Fifo Empty (0=No, 1=Empty)
	assign reg1Out[30]		= fifoIN_full;													// 30    Data-In Fifo Full   (0=No, 1=Full, or Last word received)
	assign reg1Out[29]		= (state != WAIT_COMMAND) || commandBusy || (!fifoIN_empty);	// 29    Command Busy  (0=Ready, 1=Busy receiving or processing parameters)
	assign reg1Out[28]		= !fifoIN_full & regAllowDMA0;									// 28    Data-In Request  	(set when DMA0 enabled and ready to receive data)
																							// Note : Should be DMA job to check this bit, but CPU seems to expect this flag to be ZERO.
																							// And DMA will read this register AS IS.
	assign reg1Out[27]		= fifoOUT_hasData & regAllowDMA1;								// 27    Data-Out Request	(set when DMA1 enabled and ready to send data)
	assign reg1Out[26:25]	= regPixelFormat;												// 26-25 Data Output Depth  (0=4bit, 1=8bit, 2=24bit, 3=15bit)      ;CMD.28-27
	assign reg1Out[24]		= regPixelSigned;												// 24    Data Output Signed (0=Unsigned, 1=Signed)                  ;CMD.26
	assign reg1Out[23]		= regPixelSetAlpha;												// 23    Data Output Bit15  (0=Clear, 1=Set) (for 15bit depth only) ;CMD.25
	assign reg1Out[22:19]	= 4'b0000;														// 22-19 Not used (seems to be always zero)

	wire   isYOnly          = |currentBlock;
	wire   isCrCb			= (currentBlock < 3'd2);

	// 18-16 Current Block (0..3=Y1..Y4, 4=Cr, 5=Cb) (or for mono: always 4=Y)
	// IDCT Values :
	//  000=Cr, 		
	//  001=Cb, 		
	//  010=Y0,
	//  011=Y1, 		
	//  100=Y2, 		
	//  101=Y3, 		
	//  111=Y only mode	 --> Remapped to 0..5
	assign reg1Out[18:16]	= isYOnly ? 3'd4 : (isCrCb ? { 2'b10, currentBlock[0]} : { 1'b0, !currentBlock[1] , currentBlock[0]}); 
	
	assign reg1Out[15: 0]	= nextRemainingHalfWord[16:1]; 							// 15-0  Number of Parameter Words remaining minus 1  (FFFFh=None)  ;CMD.Bit0-15
	
	// ---------------------------------------------------------------------------------------------------
	assign o_valueOut			= pRegSelect ? reg1Out : reg0Out;
	assign o_DMA1ReadRequest	= reg1Out[27];
	assign o_DMA0WriteRequest	= reg1Out[28];
	assign o_canWriteReg0		= !fifoIN_full;
	// ---------------------------------------------------------------------------------------------------
endmodule
