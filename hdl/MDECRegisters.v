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
	wire [31:0] reg1Out;
	wire [31:0] reg0Out;

	// Command Setup
	reg  [1:0]  regPixelFormat;
	reg  		regPixelSigned;
	reg  		regPixelSetAlpha;
	reg [15:0]	remaining32BitWord;
	reg			regLoadChromaQuant;
	
	reg			regWaitCommand;
	
	// --- State Machine ---
	reg 		state,nextState;
	// First value is DC, Other values are AC.
	parameter	WAIT_COMMAND=0, LOAD_STREAM=1, LOAD_COS=2, LOAD_LUMA=3, LOAD_CHROMA=4;
	// ---------------------
	
	wire validInput		= (i_regSelect == 0) && i_write;
	wire validSetup     = i_regSelect && i_write;
	
	// -----------------------------------------------------------------------------
	// [TODO] : put block instance and use 'resetChip' signal for ALL sub systems in MDEC.
	// -----------------------------------------------------------------------------
	wire resetChip      = (i_nrst==0) || (!(validSetup & i_valueIn[31])); // Inverse Reset <- 31 Reset MDEC (0=No change, 1=Abort any command, and set status=80040000h)
	
	wire validCommand	= (validInput && regWaitCommand);
	wire comm1			= (i_valueIn[31:29] == 3'b001);
	wire comm2			= (i_valueIn[31:29] == 3'b010);
	wire comm3			= (i_valueIn[31:29] == 3'b011);

	always @(posedge i_clk)
	begin
		if (resetChip) begin
			regPixelFormat   	<= 2'b00;
			regPixelSigned   	<= 0;
			regPixelSetAlpha 	<= 0;
			regLoadChromaQuant	<= 0; // Safer but not necessary.
			remaining32BitWord 	<= 16'h0;
			
			regAllowDMA0		<= 0; // IS DEFAULT CORRECT ?
			regAllowDMA1		<= 0;
			
			regWaitCommand		<= 1;
			state				<= WAIT_COMMAND;
		end else begin
			if (validCommand) begin
				// Register are updated for ANY command.
				regPixelFormat		<= i_valueIn[28:27];
				regPixelSigned		<= i_valueIn[26];
				regPixelSetAlpha	<= i_valueIn[25];
				regLoadChromaQuant	<= i_valueIn[0];
				
				// TODO : Check with a real PSX if value decremented when uploading COS / QUANT (test QUANT 1/2) table with CPU... 64 entry = 64/128 byte or 64 short(COS) 
				//        Would make a LOT of sense to use this counter and avoid having regCounter !!! Then change incrementing to decrementing.
				remaining32BitWord	<= (comm2 | comm3) ? 16'd64 : i_valueIn[15:0];
				regWaitCommand		<= 0;
			end
			if (validSetup) begin
				regAllowDMA0		<= i_valueIn[30]; // 30    Enable Data-In Request  (0=Disable, 1=Enable DMA0 and Status.bit28)
				regAllowDMA1		<= i_valueIn[29]; // 29    Enable Data-Out Request (0=Disable, 1=Enable DMA1 and Status.bit27)
			end
			state				<= nextState;
		end
	end
	
	wire resetCounter;
	wire incrementCounter;
	
	always @(posedge i_clk)
	begin
		if (resetCounter) begin
			regCounter <= 5'd0;
		end else if (incrementCounter)
			regCounter <= regCounter + 1;
		end
	end
	
	wire		i_cosWrite	= validInput && (state == LOAD_COS);
	wire [4:0]	i_cosIndex	= regCounter;	// 5 bit. [0..31]
	wire [25:0]	i_cosVal	= { i_valueIn[28:16] , i_valueIn[12:0]};
	
	wire 		i_quantWrt	= validInput && ((state == LOAD_LUMA) || (state == LOAD_CHROMA));
	wire [3:0]	i_quantAdr	= regCounter[3:0];
	wire [27:0]	i_quantVal	= {i_valueIn[30:24],i_valueIn[22:16],i_valueIn[14:8],i_valueIn[6:0]};
	wire i_quantTblSelect	= regCounter[4];
	
	always @(*)
	begin
        case (state)
		WAIT_COMMAND:
			if (validCommand && (comm1 | comm2 | comm3)) begin
				nextState = comm1 ? LOAD_STREAM : (comm2 ? LOAD_LUMA : LOAD_COS);
			end else begin
				nextState = WAIT_COMMAND;
			end
			resetCounter     = 1;
			incrementCounter = 0;
		LOAD_STREAM:
			// ---------------------------------------------
			// TODO State machine and RLE feed...
			// ---------------------------------------------
			resetCounter     = 0;
		LOAD_COS:
			resetCounter     = 0;
			if (validInput) begin
				if (regCounter == 5'd31) begin
					nextState		 = WAIT_COMMAND;
				end else begin
					nextState 		 = LOAD_COS;
				end
				incrementCounter = 1;
			else
				nextState = LOAD_COS;
				incrementCounter = 0;
			end
		LOAD_LUMA:
			resetCounter     = 0;
			if (validInput) begin
				if (regCounter[3:0] == 4'd15) begin
					if (regLoadChromaQuant) begin // 
						nextState		 = LOAD_CHROMA;
					else
						nextState		 = WAIT_COMMAND;
					end
				end else begin
					nextState 		 = LOAD_LUMA;
				end
				incrementCounter = 1;
			else
				nextState = LOAD_LUMA;
				incrementCounter = 0;
			end
		LOAD_CHROMA:
			resetCounter     = 0;
			if (validInput) begin
				if (regCounter[3:0] == 4'd15) begin
					nextState		 = WAIT_COMMAND;
				end else begin
					nextState 		 = LOAD_CHROMA;
				end
				incrementCounter = 1;
			else
				nextState = LOAD_CHROMA;
				incrementCounter = 0;
			end
        endcase
	end
	
	// [TODO] A-Write Word output state machine.
	// [TODO] B-reg0Out     = outFifoHasData ? FIFO_OUT : 32'd0;
	// [TODO] B-Add all blocks, add FIFO IN and OUT.
	// [TODO] C-Handshaking and arbitration
	// [TODO] D-Fix computation size.
	
	// Reset State : 0x80040000 [31:Fifo Empty] | [17: 4bit -> Y=4]
	reg1Out[31] = !outFifoHasData;											// 31    Data-Out Fifo Empty (0=No, 1=Empty)
	reg1Out[30] = inFifoFull;												// 30    Data-In Fifo Full   (0=No, 1=Full, or Last word received)
	reg1Out[29] = commandBusy;												// 29    Command Busy  (0=Ready, 1=Busy receiving or processing parameters)
	reg1Out[28] = canInputData & regAllowDMA0;								// 28    Data-In Request  	(set when DMA0 enabled and ready to receive data)
																			// Note : Should be DMA job to check this bit, but CPU seems to expect this flag to be ZERO.
																			// And DMA will read this register AS IS.
	reg1Out[27]		= outFifoHasData & regAllowDMA1;						// 27    Data-Out Request	(set when DMA1 enabled and ready to send data)
	reg1Out[26:25]	= regPixelFormat;										// 26-25 Data Output Depth  (0=4bit, 1=8bit, 2=24bit, 3=15bit)      ;CMD.28-27
	reg1Out[24]		= regPixelSigned;										// 24    Data Output Signed (0=Unsigned, 1=Signed)                  ;CMD.26
	reg1Out[23]		= regPixelSetAlpha;										// 23    Data Output Bit15  (0=Clear, 1=Set) (for 15bit depth only) ;CMD.25
	reg1Out[22:19]	= 4'b0000;												// 22-19 Not used (seems to be always zero)
	reg1Out[18:16]	= currentBlock;											// 18-16 Current Block (0..3=Y1..Y4, 4=Cr, 5=Cb) (or for mono: always 4=Y)
	reg1Out[15: 0]	= remaining32BitWord;									// 15-0  Number of Parameter Words remaining minus 1  (FFFFh=None)  ;CMD.Bit0-15
	
	o_valueOut		= i_regSelect ? reg1Out : reg0Out;
endmodule
