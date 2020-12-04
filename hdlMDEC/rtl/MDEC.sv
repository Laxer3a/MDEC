`include "MDEC_Cte.sv"

module MDEC (
	// DIP SWITCH OPTIONS :
	input					DIP_ditherActive,
	
	// System
	input					i_clk,
	input					i_nrst,

	output					o_DMA0REQ,	// Chip request data to be fed...
	input					i_DMA0ACK,	// Chip receive data.
	
	output					o_DMA1REQ,
	input					i_DMA1ACK,
	
	// Input
	input					i_chipSelect,
	input					i_regSelect,	// +0 or +4
	input					i_write,
	input					i_read,
	input	[31:0]			i_valueIn,
	output	[31:0]			o_valueOut
);
	parameter BKL_YONLY = 3'd4; // Use same constant as BKL_CR but want to make code more readable...
	
	wire writeReg0		= ((!i_regSelect) && i_write && i_chipSelect) || i_DMA0ACK;
	wire readReg0		=  (!i_regSelect) && i_read  && i_chipSelect;
	wire writeReg1		=    i_regSelect  && i_write && i_chipSelect;
	wire readReg1		=  ( i_regSelect) && i_read  && i_chipSelect;
	
	wire writeFIFO		= (isStream) && writeReg0;					// Store only parameters for BLOCK STREAM.
	wire  resetChip		= (!i_nrst) || (writeReg1 & i_valueIn[31]); // Reset on 1 parts
	wire nResetChip		= (!resetChip);								// Reset on 0 parts

	/*
		Moved cycle counter and state machine to front, because we are the MASTER and decide DMA REQUEST.
		So we are forced to count the number of WORD BEFORE writing to the FIFO.
		- FIFO IN is used only for block decode and not table loading anymore.
	*/
	// ---------------------------------------------------------------------------------------------------
	//   Input FIFO
	// ---------------------------------------------------------------------------------------------------
	reg			fifoIN_rdL,fifoIN_rdM;
	wire     fifoIN_emptyL = !fifoIN_validL;
	wire     fifoIN_emptyM = !fifoIN_validM;	
	wire 		fifoIN_fullL  ,fifoIN_fullM, fifoIN_validL, fifoIN_validM;
	wire [15:0]	fifoIN_outputM,fifoIN_outputL;
	wire [5:0]  unusedLevelM,unusedLevelL;
	wire		fifoIN_hasData		= (fifoIN_validL&!fifoIN_emptyL) | (fifoIN_validM&!fifoIN_emptyM);
	wire		fifoIN_empty		= fifoIN_emptyL & fifoIN_emptyM;
	wire		fifoIN_full			= fifoIN_fullL  | fifoIN_fullM;

	Fifo2 #(.DEPTH_WIDTH(5),.DATA_WIDTH(16))
	InputFIFOM (
		// System
		.i_clk			(i_clk),
		.i_rst			(resetChip),
		.i_ena			(1),

		.i_w_data		(i_valueIn[31:16]),	// Data In
		.i_w_ena		(writeFIFO),		// Write Signal

		.o_r_data		(fifoIN_outputM),	// Data Out
		.i_r_taken		(fifoIN_rdM),		// Read signal

		.o_w_full		(fifoIN_fullM),
		.o_r_valid		(fifoIN_validM),
		.o_level		(unusedLevelM)
	);

	Fifo2 #(.DEPTH_WIDTH(5),.DATA_WIDTH(16))
	InputFIFOL (
		// System
		.i_clk			(i_clk),
		.i_rst			(resetChip),
		.i_ena			(1),
        
		.i_w_data		(i_valueIn[15:0]),	// Data In
		.i_w_ena		(writeFIFO),		// Write Signal
        
		.o_r_data		(fifoIN_outputL),	// Data Out
		.i_r_taken		(fifoIN_rdL),		// Read signal
        
		.o_w_full		(fifoIN_fullL),
		.o_r_valid		(fifoIN_validL),
		.o_level		(unusedLevelL)
	);
	
	// -------------------------------------------
	// Internal Registers / Command Setup
	// -------------------------------------------
	MDEC_TPIX	regPixelFormat;
	MDEC_SIGN	regPixelSigned;
	MDEC_MASK	regPixelSetMask;
	reg  [16:0]	remainingHalfWord;

	// FOR DMA, I NEEDED THE COUNTER TO BE EXTERNAL, BUT FOR THE STATE MACHINE TO BE INTERNAL !
	// DECIDED TO PUT TWO COUNTER, SORRY FOR THE WASTE
	reg  [16:0] externalRemainingHalfWord;

	reg			regLoadChromaQuant;
	reg			regAllowDMA0,regAllowDMA1;
	
	// --- State Machine ---
	parameter
		WAIT_COMMAND	= 3'd0,
		LOAD_STREAML	= 3'd1,
		LOAD_STREAMH	= 3'd2,
		LOAD_COS		= 3'd3,
		LOAD_LUMA		= 3'd4,
		LOAD_CHROMA		= 3'd5;
		
	reg [2:0] state,nextState;
	
	// ---------------------
	reg			pRegSelect;
	
	wire commandBusy;
	wire [31:0] reg0Out;
	// ---------------------------------------------------------------------------------------------------

	// --- Command Related ---
	parameter
		STREAM_CMD	= 3'd1,
		QUANTI_CMD	= 3'd2,
		COSTBL_CMD	= 3'd3;
	
	wire isWaiting = (state == WAIT_COMMAND);
	wire isLoadCos = (state == LOAD_COS    );
	wire isLoadLum = (state == LOAD_LUMA   );
	wire isLoadChr = (state == LOAD_CHROMA );
	wire isStream  = (state == LOAD_STREAML) || (state == LOAD_STREAMH);
	
	wire [2:0] commandType	= i_valueIn[31:29];
	wire isCommandStream	= (commandType == STREAM_CMD);
	wire isCommandQuant		= (commandType == QUANTI_CMD);
	wire isCommandCosTbl	= (commandType == COSTBL_CMD);
	wire isColorQuant		= i_valueIn[0];
	wire isNewCommand		= writeReg0 && isWaiting;
	
	// --- Counter related ----
	wire [16:0] nextRemainingHalfWord = remainingHalfWord + { 16'hFFFF, !decrementCounter[1] }; // -1 or -2
	reg  [1:0]  decrementCounter;
	wire isLastHalfWord		= (nextRemainingHalfWord == 17'd0);
	
	always @(posedge i_clk)
	begin
		if (resetChip) begin
			regPixelFormat   	= 2'b00;
			regPixelSigned   	= 0;
			regPixelSetMask 	= 0;
			regLoadChromaQuant	= 0; // Safer but not necessary.
			remainingHalfWord 	= 17'h0;
			externalRemainingHalfWord = 17'h0;
			
			regAllowDMA0		= 0;
			regAllowDMA1		= 0;
			
			state				= WAIT_COMMAND;
			pRegSelect			= 0;
		end else begin
			pRegSelect			= i_regSelect;
			if (isNewCommand) begin
				// -- Read from FIFO
				// Register are updated for ANY command.
				regPixelFormat		= i_valueIn[28:27];
				regPixelSigned		= i_valueIn[26];
				regPixelSetMask		= i_valueIn[25];
				regLoadChromaQuant	= isColorQuant;
				
				if (isCommandQuant) begin
					// [Unit in HALF WORD]
					remainingHalfWord			= isColorQuant ? 17'd64 : 17'd32;							// [32 word (128 byte) vs. 16 word (64 byte)] of 32 bit, but we use half word counter internally [64/32].
				end else begin
					// [Unit in WORD] << 1 -> HALF WORD
					remainingHalfWord = {(isCommandCosTbl ? 16'd32 : fifoIN_outputL), 1'b0};	//  32 word of 32 bit = 64 word of 16 bit (Cos Table)
				end
			end else begin
				if (decrementCounter != 2'b00) begin
					remainingHalfWord = nextRemainingHalfWord;
				end
			end
			
			if (writeReg1) begin
				// -- Read from Data In directly.
				regAllowDMA0		= i_valueIn[30]; // 30    Enable Data-In Request  (0=Disable, 1=Enable DMA0 and Status.bit28)
				regAllowDMA1		= i_valueIn[29]; // 29    Enable Data-Out Request (0=Disable, 1=Enable DMA1 and Status.bit27)
			end
			state = nextState;
		end
	end

	wire endMatrix;
	wire allowLoad;
	reg PEndMatrix;
	always @(posedge i_clk) begin PEndMatrix = endMatrix; end
	wire isPass1;
	wire dontPushStream			= (!allowLoad) | PEndMatrix;
	wire canPushStream			= !dontPushStream;
	
	wire isCommandStreamValid	= isCommandStream	& fifoIN_hasData;
	wire validLoad				= canPushStream		& fifoIN_hasData;
	
	always @(*)
	begin
		fifoIN_rdL			= 1'b0;
		fifoIN_rdM			= 1'b0;
		decrementCounter	= 2'd0;
		
        case (state)
		default: // Unknown state, roll to default.
		begin
			nextState			= WAIT_COMMAND;
		end
		WAIT_COMMAND:
		begin
			// Read the command...
			if (isNewCommand && (isCommandStream | isCommandQuant | isCommandCosTbl)) begin
				if (isCommandStream) begin
					nextState = LOAD_STREAML;
				end else begin
					nextState = (isCommandQuant ? LOAD_LUMA : LOAD_COS);
				end
			end else begin
				nextState	= WAIT_COMMAND;
			end
		end
		LOAD_STREAML: // STATE 2.
		begin
			if (validLoad) begin
				// Consume LSB Value
				fifoIN_rdL	= validLoad;
				// Wait for MSB Value now.
				nextState	= LOAD_STREAMH;
			end else begin
				// Wait until work complete or FIFO has LSB data.
				nextState	= LOAD_STREAML;
			end
		end
		LOAD_STREAMH: // STATE 3.
		begin
			if (validLoad) begin
				decrementCounter= 2'd1;
				// Consume 
				fifoIN_rdM	= validLoad;
				if (isLastHalfWord) begin
					nextState 	= WAIT_COMMAND;
				end else begin
					nextState	= LOAD_STREAML;
				end
			end else begin
				nextState = LOAD_STREAMH;
			end
		end
		LOAD_COS:
		begin
			decrementCounter	= { writeReg0, 1'b0 };
			nextState		 	= (isLastHalfWord && writeReg0) ? WAIT_COMMAND : LOAD_COS;
		end
		LOAD_LUMA:
		begin
			decrementCounter	= { writeReg0, 1'b0 };
			if (writeReg0) begin
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
			decrementCounter	= { writeReg0, 1'b0 };
			if (writeReg0) begin
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
	
	// ---- COS Loading ----
	wire		i_cosWrite	= writeReg0 && isLoadCos;
	wire [4:0]	i_cosIndex	= ~(nextRemainingHalfWord[5:1]);	// 31->0 => 0->31
	wire [25:0]	i_cosVal	= { i_valueIn[31:19] , i_valueIn[15:3]};
	// ---- Quantization Table Loading ----
	wire 		i_quantWrt	= writeReg0 && (isLoadLum || isLoadChr);
	wire [3:0]	i_quantAdr	= ~(nextRemainingHalfWord[4:1]);
	wire [27:0]	i_quantVal	= {i_valueIn[30:24],i_valueIn[22:16],i_valueIn[14:8],i_valueIn[6:0]};
	wire i_quantTblSelect	= isLoadLum; // Table 1 for LUMA, 0 for CHROMA.

	// ---- Stream Loading ----
	
	wire isLoadStL = (state == LOAD_STREAML);
	wire isLoadStH = (state == LOAD_STREAMH);
	
	wire        writeStream	= ((isLoadStL || isLoadStH) & canPushStream) /* && allowLoad <--- do not have FIFO lock for now */;		// Use FIFO last output, even if data is not asked.
	// FIRST BLOCK is LSB, SECOND BLOCK IS LSB
	// TODO change name of state L/H by FIRST/SECOND.
	wire [15:0] streamIn	=  isLoadStL ? fifoIN_outputL : fifoIN_outputM;
	
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
		.o_endMatrix	(endMatrix),
		.o_allowLoad	(allowLoad),
//		.writeCoefOutToREG	(writeCoefOutToREG),
//		.selectREGtoIDCT	(selectREGtoIDCT),
		
		// Loading of COS Table (Linear, no zigzag)
		.i_cosWrite		(i_cosWrite),
		.i_cosIndex		(i_cosIndex),
		.i_cosVal		(i_cosVal),
		
		// Loading of quant Matrix
		.i_quantWrt		(i_quantWrt),
		.i_quantValue	(i_quantVal),
		.i_quantAdr		(i_quantAdr),
		.i_quantTblSelect(i_quantTblSelect),

		.o_idctBlockNum	(currentBlock),
		.o_stillIDCT	(commandBusy),
		.i_stopFillY	(!allowWrite),
		
		.o_pixelOut		(wrtPix),
		.o_pixelAddress	(pixIdx), // 16x16 or 8x8 [yyyyxxxx] or [0yyy0xxx]
		.o_rComp		(r),
		.o_gComp		(g),
		.o_bComp		(b)
	);
	
	wire [2:0] currentBlock; // Output for status register.
	wire wrtPix;
	wire [7:0] pixIdx,r,g,b,finalR,finalG,finalB;

	// For now pixel format is not pipelined but use directly register setup.
	// 
	wire [1:0] outPixelFormat = regPixelFormat;
	wire       is15Bit        = outPixelFormat == P15BIT;
	ditherMDEC ditherInst(
		.rIn			(r),
		.gIn			(g),
		.bIn			(b),
		.ditherOn		(DIP_ditherActive && is15Bit),
		.xBuff			(pixIdx[1:0]),
		.yBuff			(pixIdx[5:4]),
		.r				(finalR),
		.g				(finalG),
		.b				(finalB)
	);				

	wire writeRAM;
	reg  allowWrite;
	reg  [7:0] writeAdr;
	wire [7:0] nextWriteAdr			= writeAdr      + 8'd1;
	reg resetWriteAdr;
	
	// FIFO like behavior of read/write counters.
	wire fifoOUT_hasData			= (readAdrLinear != writeAdr);
	
	wire readRAM = (i_DMA1ACK | readReg0) & fifoOUT_hasData;
	
	reg  [7:0] readAdrLinear;
	wire [7:0] nextReadAdrLinear	= readAdrLinear + 8'd1;
	reg resetReadAdr;

	reg  [7:0] readAdrSwizzle;
	
	always @(*)
	begin
		case (outPixelFormat)
		P_4BIT : resetWriteAdr = (nextWriteAdr ==   8'd8);	// One tile  8x8  x4bit / 32bit
		P_8BIT : resetWriteAdr = (nextWriteAdr ==  8'd16);	// One tile  8x8  x8bit / 32bit
		P24BIT : resetWriteAdr = (nextWriteAdr == 8'd192);	// One tile 16x16 x24bit / 32bit
		/*P15BIT*/
		default: resetWriteAdr = (nextWriteAdr == 8'd128);	// One tile 16x16 x16bit / 32bit
		endcase
		
		case (outPixelFormat)
		P_4BIT : resetReadAdr = (nextReadAdrLinear ==   8'd8);	// One tile  8x8  x4bit / 32bit
		P_8BIT : resetReadAdr = (nextReadAdrLinear ==  8'd16);	// One tile  8x8  x8bit / 32bit
		P24BIT : resetReadAdr = (nextReadAdrLinear == 8'd192);	// One tile 16x16 x24bit / 32bit
		/*P15BIT*/
		default: resetReadAdr = (nextReadAdrLinear == 8'd128);	// One tile 16x16 x16bit / 32bit
		endcase
	end
	
	wire [31:0] packedData;
	RGB2Pack RGB2Pack_inst(
		.i_clk			(i_clk),
		.i_nrst			(nResetChip),
		
		.i_wrtPix		(wrtPix & allowWrite),
		.format			(outPixelFormat),
		.setBit15		(regPixelSetMask),
		.i_r			(finalR),
		.i_g			(finalG),
		.i_b			(finalB),

		.o_dataValid	(writeRAM),
		.o_dataPacked	(packedData)
	);

	always @(posedge i_clk)
	begin
		if (resetChip || (resetWriteAdr && writeRAM && allowWrite)) begin
			writeAdr		= 8'd0;
		end else begin
			if (writeRAM && allowWrite) begin
				// Increment dest linearly.
				writeAdr	= nextWriteAdr;
			end
		end

		if (resetChip || (resetReadAdr && readRAM)) begin
			readAdrLinear	= 8'd0;
		end else begin
			if (readRAM) begin
				readAdrLinear	= nextReadAdrLinear;
			end
		end

		if (resetChip) begin
			allowWrite = 1;
		end else begin
			// WRITE IS FULL...
			if (resetWriteAdr) begin
				if (writeRAM && allowWrite) begin
					allowWrite = 0;
				end
			end
				
			if (!allowWrite && readRAM && resetReadAdr) begin
				allowWrite = 1;
			end
		end
	end
	
	// NOTE : Because we linearly increase READ ADR, we could just maintain a mod 6 + div 6 counter directly.
	//        And generate adresses from there.
	wire [2:0] v_mod6;
	wire [4:0] Div3;
	
	// Just 12 ALM
	mod3 mod3_inst(
		.inV	(readAdrLinear[7:1]),
		.outP	(v_mod6[2:1]),
		.divP	(Div3)
	);
	assign v_mod6[0] = readAdrLinear[0];
	
	/*
		No more FIFO.
		16x16 instead or 8x8 in Luma.
		Write in order...
		
		Note : work fine for 16x8 block ! (64 word)
		
		Use a ITEM Counter : 4/6 block length
		Use a LINE Counter : line => Same for both.
		
		Adr = LINE        ( 4 bit)
		Adr = LINE*2+ITEM ( 8 bit)
		Adr = LINE*4+ITEM (16 bit)
		Adr = LINE*6+ITEM (24 bit)
		
		------------------------
		  DIRECT ADR WRITE (LINEAR) 32 BIT WORD ADR
		------------------------
		
		------------------------
		  READ ADR CPU (LINEAR) 32 BIT WORD ADR
		  0.. 7  ( 4 bit)
		  0..15  ( 8 bit)
		  0..127 (16 bit)
		  0..191 (24 bit)

		------------------------
		  READ ADR DMA (SWIZZLED) 32 BIT WORD ADR
		  Take CPU counter and transform into DMA counter
		  Mode 4/8 bit = SAME
		  Mode 16  bit = 7:6,4:2,5,1:0
	 */
	
	//	  mod3 = mod3Func(adr[7:1]);
	//	  div3 = div3Func(adr[7:1]);
	//	  Mod6 = {mod3,Adr[0]}
	//	  Div6 = {div3,     0}
	// Mode 24  bit = (Div6 * 6) + Div6
	wire [4:0] swizzleLine = { Div3[4],Div3[2:1],Div3[3],Div3[0] }; // Division by 6 actually, see mod3 input.
	wire [6:0] mul3        = { 2'b0, swizzleLine } + { 1'b0, swizzleLine , 1'b0 };
	always @(*) begin
		// Swizzle 
		
		case (outPixelFormat)
		P_4BIT : readAdrSwizzle = readAdrLinear;
		P_8BIT : readAdrSwizzle = readAdrLinear;
		P24BIT : readAdrSwizzle = { mul3, 1'b0 } /* Mul 6 */ + { 5'd0 ,v_mod6 };
		/*P15BIT*/
		default: readAdrSwizzle = {readAdrLinear[7:6],readAdrLinear[4:2],readAdrLinear[5],readAdrLinear[1:0]};
		endcase
	end

	wire [31:0] packOut;
	// CPU READ override DMA READ -> FINE.
	wire [7:0] readAdrSel = readReg0 ? readAdrLinear : readAdrSwizzle;

	RAM768 RAM768_inst(
		.i_clk			(i_clk),
		
		.i_dataIn		(packedData),
		.i_dataAdr		(writeAdr),
		.i_dataWr		(writeRAM),
		
		// No readRAM !!! Just for counters. We always put out data with 1 cycle latency.
		.i_dataAdrRd	(readAdrSel),
		.o_dataOut		(packOut)
	);

	// Reset State : 0x80040000 [31:Fifo Empty] | [17: 4bit -> Y=4]
	wire [31:0] reg1Out;
	assign reg1Out[31]			= !fifoOUT_hasData;												// 31    Data-Out Fifo Empty (0=No, 1=Empty)
	assign reg1Out[30]			= fifoIN_full;													// 30    Data-In Fifo Full   (0=No, 1=Full, or Last word received)
	assign reg1Out[29]			= !isWaiting || commandBusy;									// 29    Command Busy  (0=Ready, 1=Busy receiving or processing parameters)
	assign reg1Out[28]			= o_DMA0REQ;													// 28    Data-In Request  	(set when DMA0 enabled and ready to receive data)
																								// Note : Should be DMA job to check this bit, but CPU seems to expect this flag to be ZERO.
																								// And DMA will read this register AS IS.
	assign reg1Out[27]			= o_DMA1REQ;													// 27    Data-Out Request	(set when DMA1 enabled and ready to send data)
	assign reg1Out[26:25]		= regPixelFormat;												// 26-25 Data Output Depth  (0=4bit, 1=8bit, 2=24bit, 3=15bit)      ;CMD.28-27
	assign reg1Out[24]			= regPixelSigned;												// 24    Data Output Signed (0=Unsigned, 1=Signed)                  ;CMD.26
	assign reg1Out[23]			= regPixelSetMask;												// 23    Data Output Bit15  (0=Clear, 1=Set) (for 15bit depth only) ;CMD.25
	assign reg1Out[22:19]		= 4'b0000;														// 22-19 Not used (seems to be always zero)

	wire   isYOnly          	= &currentBlock; // 7 (BLK_Y_) => 1 else 0.

	// 18-16 Current Block (0..3=Y1..Y4, 4=Cr, 5=Cb) (or for mono: always 4=Y)
	assign reg1Out[18:16]		= isYOnly ? BKL_YONLY : currentBlock;
	
	assign reg1Out[15: 0]		= nextRemainingHalfWord[16:1]; 									// 15-0  Number of Parameter Words remaining minus 1  (FFFFh=None)  ;CMD.Bit0-15
	
	// ---------------------------------------------------------------------------------------------------
	assign o_valueOut			= pRegSelect ? reg1Out : packOut;
	
	assign o_DMA1REQ			=  regAllowDMA1			// DMA Enabled
								&& fifoOUT_hasData
								&& (!i_DMA1ACK);		// No burst like thing... Performance issue ?

	// 
	assign o_DMA0REQ			= !isWaiting 		// State machine is loading parameters for command (include counter valid).
								&& regAllowDMA0		// and DMA Enabled
								&& (!fifoIN_full) 	// and FIFO has space
								&& (!i_DMA0ACK);	// and Currently not receiving data from previous REQ cycle. (allow also to handle state change and not request further data)
	// ---------------------------------------------------------------------------------------------------
endmodule
