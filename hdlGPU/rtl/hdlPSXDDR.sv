/**
	-------------------------- PSX SIDE PROTOCOL -------------------
    // [Interface is telling the GPU that it is busy (1) : GPU should never send any command while busy.]
	output           o_busy

	// [GPU telling that it is requesting to do a memory operation (will NEVER happen when o_busy is 1)
	// 1 = Do an operation (read or write)
	input            i_command
	
	// Type of operation (0=READ / 1=WRITE)
    input            i_write
	
	// Size of operation (0 = 8 byte, 1 = 32 byte, 2 = 4 Byte)
    input   [1:0]    i_commandSize
	
	// Address to perform operation, In block of 32 byte (32768 block of 32 byte)
    input [ 14:0]    i_adr
	
	// Sub adress for 8 byte and 4 byte operations. [xx0] in 8 byte mode, [xxy] in 4 byte mode, [000] when 32 byte mode.
	// => { i_adr, i_subAddr } gives you always an adress in 4 byte word.
    input   [2:0]    i_subadr    
	
	// When performing a write, it is possible to skip writing per 16 bit block. (mask 1 bit = data 16 bit of data)
	// Masked write are always 32 byte mode. Other possible write are 4 byte but are not masked.
    input  [15:0]    i_writeMask

    output  [255:0]  o_dataOut,
    output           o_dataOutValid,
    input [255:0]    i_dataIn

// Note 1 : Full Address in byte is composed like this : { i_adr , i_subadr , 2'b00 }  in ALL CASES (as subadr is guaranteed to be 000 by the client for now, no mux needed)
// Note 2 : Client will guarantee that if o_busy is 1, i_command will be 0.
// Note 3 : Some LATER optimization (NOT NOW ! AFTER TEST !) may be possible from the server by setting o_busy to 0 at the last cycle ( so we can set i_command at the next cycle ).

	-------------------------- AVALON SIDE PROTOCOL -------------------
	DDR (Memory) Connections :  https://www.intel.com/content/dam/www/programmable/us/en/pdfs/literature/manual/mnl_avalon_spec.pdf
	                            Especially from p.14 ~ 37
								
								Tutorial / Info :
								https://youtu.be/8GAqT3nzHeQ?t=21
								
 */
module hdlPSXDDR(
  // Global Connections
  input i_clk,
  input i_nRst,
  
  // Client (PSX) Connections
  input				i_command,				// 0 = do nothing, 1 = read/write operation
  input				i_writeElseRead,		// 0 = read, 1 = write
  input [ 1:0]		i_commandSize,			// 
  input [14:0]		i_targetAddr,			// 1 MB memory splitted into 32768 block of 32 byte.
  input [ 2:0]		i_subAddr,
  input [15:0]		i_writeMask,
  input [255:0]		i_dataClient,
  output			o_busyClient,
  output			o_dataValidClient,		// When 1, PSX makes no request.
  output [255:0]	o_dataClient,
  
  // DDR (Memory) Connections
  output [16:0]		o_targetAddr,
  output [ 2:0]		o_burstLength,
  input				i_busyMem,				// Wait Request (Busy = 1, Wait = 1 same meaning)
  output			o_writeEnableMem,		// 
  output			o_readEnableMem,		//
  output [63:0]		o_dataMem,
  output [7:0]		o_byteEnableMem,

  input				i_dataValidMem,
  input  [63:0]		i_dataMem
);

parameter	CMD_32BYTE		= 2'd1,
			CMD_8BYTE		= 2'd0,
			CMD_4BYTE		= 2'd2;

	reg dataToPSXValid;
	
	
	// --------------- State Machine ------------------
	typedef enum logic[2:0] {
		DEFAULT_STATE		=3'd0,
		READ_STATE1         =3'd1,
		WRITE_STATE1        =3'd2,
		WAIT_RECEIVE_READ   =3'd3
	} state_t;
	state_t currState, nextState;
	always @(posedge i_clk) begin currState = (!i_nRst) ? DEFAULT_STATE : nextState; end
	
	reg   [1:0] blkCounterEmit;
	reg   [1:0] blkCounterRecv;
	
	// On cycle 0, when PSX requst mem to DDR,
	reg readSigDDR, writeSigDDR;
	
	wire lastRequest = blkCounterEmit==lastCounter;
	
	always @(*) begin
		readSigDDR		= 1'b0;
		writeSigDDR		= 1'b0;
		nextState		= currState;
		
		case (currState)
		
		// Default : emit READ or WRITE SETUP if we have a command
		//           don't care about the state of the DDR (busy or not)
		//           just emit and change of state for a single clock.
		default/*DEFAULT_STATE included*/: begin
			if (i_command) begin
				nextState	= i_writeElseRead ? WRITE_STATE1 : READ_STATE1;
				// CANT DO readSigDDR => Adr not loaded YET !!!!
			end
		end
		
		// Continue to emit the READ SETUP for multiple clock until we get ACK by DDR.
		READ_STATE1: begin
			if (i_busyMem == 0) begin
				readSigDDR	= 1; // Request Read when memory not busy.
				if (lastRequest) begin nextState = WAIT_RECEIVE_READ; end
			end
		end

		WAIT_RECEIVE_READ: begin
			if (i_dataValidMem && (blkCounterRecv==lastCounter)) begin
				nextState = DEFAULT_STATE;
			end
		end
		
		
		WRITE_STATE1: begin
			if (i_busyMem == 0) begin
				writeSigDDR = 1'b1;
				if (lastRequest) begin nextState = DEFAULT_STATE; end
			end
		end

		endcase
	end
	
	reg [255:0] dataInOut;
	reg  [15:0] dataMask;
	reg         is32Bit;
	reg         isUnAlign;
	reg			isWrite;
	reg	  [1:0] lastCounter;
	
	reg [14:0] burstAdr;
	reg  [2:0] burstAdrSub;
	always @(posedge i_clk) begin
	   if ( (nextState == WRITE_STATE1 || nextState == READ_STATE1) && currState==DEFAULT_STATE ) begin
		 burstAdr    = i_targetAddr;
		 burstAdrSub = i_subAddr;
	   end
	end

	
	//-----------------------------------------------------
	//  Load values when a PSX command is received.
	//-----------------------------------------------------
	always @(posedge i_clk)
	begin
		// Store the values for writing to DDR.
		is32Bit   = i_command && (i_commandSize == CMD_4BYTE);
		isUnAlign = i_command && i_subAddr[0];
		isWrite	  = i_command && i_writeElseRead;
		
		// Delay of one cycle when doing transition from end of read burst to next command.
		dataToPSXValid = (currState == WAIT_RECEIVE_READ) && (nextState == DEFAULT_STATE);
		
		if (isWrite) begin
			dataInOut = i_dataClient;
		end
		
		// Set Mask (we don't check isWrite to simplify logic but dataMask is used only with Write)
		if ((currState == DEFAULT_STATE) && i_command) begin
			if (i_writeElseRead) begin
				if (i_commandSize == CMD_4BYTE) begin
					dataMask   = { 12'd0, i_subAddr[0] ? 4'hC : 4'h3 };
				end else begin
					dataMask   = i_writeMask; // 32 byte. (8 Byte WRITE NEVER HAPPEN DONT CARE)
				end
			end else begin
				dataMask = 16'hFFFF;
			end
		end
		
		// Write to the correct section when we read data.
		if (i_dataValidMem) begin
			case (blkCounterRecv)
			// Handle the case of reformatting the data to 32 bit on an odd adr.
			2'd0   : dataInOut[ 63:  0] = (is32Bit && isUnAlign) ? { 32'd0 , i_dataMem[63:32] } : i_dataMem;
			2'd1   : dataInOut[127: 64] = i_dataMem;
			2'd2   : dataInOut[191:128] = i_dataMem;
			default: dataInOut[255:192] = i_dataMem;
			endcase
		end
	end
	
	//-----------------------------------------------------
	//  Counter and MAX Counter for type of command.
	//-----------------------------------------------------
	always @(posedge i_clk)
	begin
		if (i_command) begin
			blkCounterEmit <= 2'd0;
			blkCounterRecv <= 2'd0;

			case (i_commandSize)
			CMD_8BYTE : lastCounter <= 2'd0;
			CMD_32BYTE: lastCounter <= 2'd3;
			CMD_4BYTE : lastCounter <= 2'd0;
			default   : lastCounter <= 2'd0;
			endcase
		end else begin
			blkCounterRecv <= blkCounterRecv + { 1'b0 , i_dataValidMem           }; // Increment when receive READ value.
			blkCounterEmit <= blkCounterEmit + { 1'b0 , writeSigDDR | readSigDDR }; // Increment on READ/WRITE request. 
		end
	end

	//-----------------------------------------------------
	// PSX OUT
	//-----------------------------------------------------
	//assign o_busyClient			= (currState != DEFAULT_STATE) && (nextState != DEFAULT_STATE); // Can say NOT busy on the LAST CYCLE of current transaction.
	assign o_busyClient			= (currState != DEFAULT_STATE); // Can say NOT busy on the LAST CYCLE of current transaction.
	assign o_dataValidClient	= dataToPSXValid;
	assign o_dataClient			= dataInOut;
	
	//-----------------------------------------------------
	// DDR OUT
	//-----------------------------------------------------
	
	// Select the proper block of 64 bit into the 256 bit register to SEND to DDR for write.
	// -------------------------------------------------------------------------------------
	reg [63:0] dataOutDDR;
	always @(*)
	begin
		case (blkCounterEmit)
		// Handle the case of reformatting the data to 32 bit on an odd adr.
		2'd0   : dataOutDDR = dataInOut[ 63:  0];
		2'd1   : dataOutDDR = dataInOut[127: 64];
		2'd2   : dataOutDDR = dataInOut[191:128];
		default: dataOutDDR = dataInOut[255:192];
		endcase
	end
	assign o_dataMem			= dataOutDDR;

	// Used for a single cycle when start burst, so direct signals from PSX request.
	// -------------------------------------------------------------------------------------

	wire [1:0] lowPart			= burstAdrSub[2:1] + blkCounterEmit;
	assign o_targetAddr			= { burstAdr, lowPart };
	
	assign o_burstLength		= (i_commandSize == CMD_32BYTE) ? 3'd4 : 3'd1;
	
	assign o_readEnableMem		= readSigDDR;	// Already set only in (currState==READ_STATE1)
	assign o_writeEnableMem		= writeSigDDR && (currState==WRITE_STATE1);
	
	reg [7:0] mask;
	always @(*)
	begin
		case (blkCounterEmit)
		// Handle the case of reformatting the data to 32 bit on an odd adr.
		2'd0   : mask = { dataMask[ 3],dataMask[ 3],dataMask[ 2],dataMask[ 2],dataMask[ 1],dataMask[ 1],dataMask[ 0],dataMask[ 0] };
		2'd1   : mask = { dataMask[ 7],dataMask[ 7],dataMask[ 6],dataMask[ 6],dataMask[ 5],dataMask[ 5],dataMask[ 4],dataMask[ 4] };
		2'd2   : mask = { dataMask[11],dataMask[11],dataMask[10],dataMask[10],dataMask[ 9],dataMask[ 9],dataMask[ 8],dataMask[ 8] };
		default: mask = { dataMask[15],dataMask[15],dataMask[14],dataMask[14],dataMask[13],dataMask[13],dataMask[12],dataMask[12] };
		endcase
	end
	assign o_byteEnableMem = mask;
endmodule
