module MemoryArbitratorFat(
	input			gpuClk,
	input			busClk,
	input			i_nRst,

	// -----------------------------------
	// [GPU FIFO COMMAND SIDE MODE]
	// -----------------------------------

	// ---TODO Describe all fifo command ---
	input  [55:0]	memoryWriteCommand, // if [2:0] not ZERO -> Write to FIFO.
	output          fifoFull,			//
	output			fifoComplete,		// = Empty signal + all mem operation completed. Needed to know that primitive work is complete.

	// -----------------------------------
	// [GPU BUS SIDE MODE]
	// -----------------------------------

	// -- TEX$ Stuff --
	// TEX$ Cache miss from L Side
	input           requTexCacheUpdateL,
	input  [16:0]   adrTexCacheUpdateL,
	output          updateTexCacheCompleteL,
	// TEX$ Cache miss from R Side
	input           requTexCacheUpdateR,
	input  [16:0]   adrTexCacheUpdateR,
	output          updateTexCacheCompleteR,
	// TEX$ feed updated $ data to cache.
	output [16:0]   adrTexCacheWrite,
	output          TexCacheWrite,
	output [63:0]   TexCacheData,

	// -- CLUT$ Stuff --
	// CLUT$ Load Request
	input           requClutCacheUpdate,
	input  [14:0]   adrClutCacheUpdate,
	output          updateClutCacheComplete,

	// CLUT$ feed updated $ data to cache.
	output          ClutCacheWrite,
	output  [2:0]   ClutWriteIndex,
	output [31:0]   ClutCacheData,

	input			isBlending,
	input  [14:0]	saveAdr,
	input	[1:0]	saveBGBlock,			// 00:Do nothing, 01:First Block, 10 : Second and further blocks.
											// First block does nothing if no blending (no BG load)
											// Second block does LOAD/SAVE or LOAD only based on state.
	input [255:0]	exportedBGBlock,
	input  [15:0]	exportedMSKBGBlock,

	// BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
	input  [14:0]	loadAdr,
	output			importBGBlockSingleClock,
	output  [255:0]	importedBGBlock,

	output			saveLoadOnGoing,

	output			resetPipelinePixelStateSpike,
	output			resetMask,				// Reset the list of used pixel inside the block for next block processing.

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    output           o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input            i_busy,           // Memory busy 1 => can not use.
    output   [1:0]   o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]   o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   o_writeMask,

    input  [255:0]   i_dataIn,
    input            i_dataInValid,
    output [255:0]   o_dataOut
);
	
// ====================================================================================================
//
//    GPU COMMAND SIDE : Push as many things as possible into the FIFO
//
// ====================================================================================================

// --------------------------------------------------------------
// Private/Local
wire		doBGWork     = saveBGBlock[0] | saveBGBlock[1];
wire		spikeBGBlock;
reg			lastsaveBGBlock;
always @(posedge gpuClk) begin lastsaveBGBlock = doBGWork; end
// --------------------------------------------------------------
// PUBLIC SIGNAL IN DESIGN
wire	isFirstBlockBlending	= ((saveBGBlock == 2'b01) & isBlending);
assign	spikeBGBlock			= doBGWork & !lastsaveBGBlock;
wire	isTexReq				= requTexCacheUpdateL  | requTexCacheUpdateR;
// --------------------------------------------------------------

parameter	MEM_CMD_PIXEL2VRAM	= 3'b001,
			MEM_CMD_FILL		= 3'b010,
			MEM_CMD_RDBURST		= 3'b011,
			MEM_CMD_WRBURST		= 3'b100,
			// Other command to come later...
			MEM_CMD_NONE		= 3'b000;

// ---------------------------------------
//   write back to Tex$
wire   isTexL,isTexR;
wire [255:0] res_data;
assign TexCacheData				= res_data[63:0];
assign TexCacheWrite			= validRead & (isTexL|isTexR); // ACK down
assign adrTexCacheWrite			= backupTexAdr; 		// Write happened when ACK to ZERO (after data
assign updateTexCacheCompleteL	= validRead & isTexL;	// Normally was done 1 cycle sooner
assign updateTexCacheCompleteR	= validRead & isTexR;	// Normally was done 1 cycle sooner
// ---------------------------------------
wire	isCLUT;
reg [2:0] idxCnt;
wire	lastCLUT				= (idxCnt==3'd7);
// CLUT$ Load Request
assign updateClutCacheComplete	= lastCLUT;
// CLUT$ feed updated $ data to cache.
assign ClutCacheWrite			= validRead & isCLUT;
assign ClutWriteIndex			= idxCnt; // 0..7
reg [31:0] s_data32; 
always @(*) begin 
	case (idxCnt)
	3'd0: s_data32 = res_data[ 31:  0];
	3'd1: s_data32 = res_data[ 63: 32];
	3'd2: s_data32 = res_data[ 95: 64];
	3'd3: s_data32 = res_data[127: 96];
	3'd4: s_data32 = res_data[159:128];
	3'd5: s_data32 = res_data[191:160];
	3'd6: s_data32 = res_data[223:192];
	default: s_data32 = res_data[255:224];
	endcase
end
assign ClutCacheData					= s_data32;
// ---------------------------------------
assign resetMask						= (state == WRITE_BG);
wire isBlendingBlock					= (isBlending && (saveBGBlock != 2'd3));
assign resetPipelinePixelStateSpike		= ((state == WRITE_BG) && (!isBlendingBlock)) || ((state == READ_BG) && validRead);
assign importBGBlockSingleClock			= (state == READ_BG) && validRead;
// Data Read. Straight into GPU.
assign importedBGBlock					= res_data;
// ---------------------------------------

wire fifoFULL;

// FIFO CMD :
//       Bit0=Write
// DONE [000:READBG ][15 Bit Adr]----------------------
// DONE [001:WRITEBG][15 Bit Adr][256 Bit][16 bit Mask]
// DONE [010:READ8  ][15 Bit Adr]         [11][2 bit:Adr]0[2---]
// DONE [011:WRITEPR][15 Bit Adr]    [32B][11][3 bit:Adr] [2msk]
//      [100:READBRT][15 Bit Adr]         [Msk Read   ] + CpyBankFlag + clearOtherBank + 1'b1(23) ?
//      [101:WRITBRT][15 Bit Adr]         [StencilRead] + writeBankOld + GPUREG_ForcePixel15 + GPU_Reg_CheckMaskBit + clearBank0 + clearBank1 + cpyIdx

// If FIFO FULL or waiting for read result => Consider locked by transaction.
wire validRead;

assign saveLoadOnGoing = fifoFULL | (state != WAIT_CMD);

wire [16:0] adrTexRead = requTexCacheUpdateL ? adrTexCacheUpdateL : adrTexCacheUpdateR;
reg  [16:0] backupTexAdr;

// --------------------------------------------------
// [CONVERT GPU COMMAND AND PACK INTO FIFO]
// --------------------------------------------------
parameter   WAIT_CMD			= 3'd0,
			READ_BG				= 3'd1,
			READ_CLUT			= 3'd2,
			READ_TEX_L			= 3'd3,
			READ_TEX_R			= 3'd4,
			WRITE_BG			= 3'd5,
			READ_BG_START		= 3'd6;
			
reg [2:0]   state;
reg [2:0]   nextState;

assign isTexL    = (state     == READ_TEX_L);
assign isTexR    = (state     == READ_TEX_R);
assign isCLUT    = (state     == READ_CLUT );
wire   resetRead = (nextState == WAIT_CMD  ) && (isTexL | isTexR | isCLUT | (state == READ_BG));

reg [289:0] command;
reg         writeFIFO;
reg			saveTexAdr;
always @(*)
begin
	// By default not a read command...
	writeFIFO	= 1;
	command 	= 290'dx;
	nextState	= state;
	saveTexAdr	= 0;
	
	if ((!fifoFULL) && ((state == WAIT_CMD) || (state == READ_BG_START))) begin
		if (memoryWriteCommand[2:0] != 0) begin
			case (memoryWriteCommand[2:0])
			MEM_CMD_PIXEL2VRAM:
			begin
				command =	{ 
							// 11 + 3 + 2
							  11'dx, memoryWriteCommand[6:4], memoryWriteCommand[23:22] 
							// 224 + 32 
							, 224'dx , memoryWriteCommand[55:24]							// 32 Bit Data
							// 15 bit (14:0)
							, memoryWriteCommand[21:7] 
							// 3 Bit
							, 3'b011
							};	// 11 Bit : Ignore, 3 Bit : Adr sub block, 2 bit : pixel mask.  
			end
			MEM_CMD_RDBURST:
			begin
				command = 	{ 
							  memoryWriteCommand[55:40] 
							, 250'dx , memoryWriteCommand[23:22] , 3'd0 , memoryWriteCommand[3]	// 6 bit parameters.
							, memoryWriteCommand[21:7] 
							, 3'b100 
							};
			end
			MEM_CMD_WRBURST:
			begin
				command = 	{ 
							  memoryWriteCommand[55:40] 
							, 246'dx, memoryWriteCommand[27:22] ,memoryWriteCommand[6:3]
							, memoryWriteCommand[21:7] 
							, 3'b101 
							};
			end
			default: // MEM_CMD_FILL:
			begin
				command = 	{ 
							  16'hFFFF
							, {15{memoryWriteCommand[55:40]}}/*Ignore*/ , memoryWriteCommand[55:40] 
							, memoryWriteCommand[21:7] 
							, 3'b001 
							}; 
			end
			endcase
		end else begin
			if (state == WAIT_CMD) begin
				if (spikeBGBlock & (saveBGBlock[1] | isFirstBlockBlending)) begin
					if (isFirstBlockBlending) begin
						// READ BG
						command	=	{ 
									  16'dx 
									, 256'dx 
									, loadAdr 
									, 3'b000 
									};
						nextState	= READ_BG;
					end else begin
						// WRITE BG
						command =	{
									  exportedMSKBGBlock 
									, exportedBGBlock 
									, saveAdr 
									, 3'b001 
									};
						nextState	= WRITE_BG;
					end
				end else begin
					if (requClutCacheUpdate) begin
						nextState	= READ_CLUT;
						command		= { 
										  16'dx 
										, 256'dx 
										, adrClutCacheUpdate 
										, 3'b000 
									};
					end else begin
						if (isTexReq) begin
							saveTexAdr	= 1;
							command 	=	{
											  { 11'dx, adrTexRead[1:0], 1'd0, 2'dx } 
											, 256'dx 
											, adrTexRead[16:2] 
											, 3'b010 
											};
							nextState	= requTexCacheUpdateL ? READ_TEX_L : READ_TEX_R;
						end else begin
							//
							// Nothing to do to the FIFO.
							//
							writeFIFO	= 0;
						end
					end
				end
			end else begin
				command		= {
					  16'dx 
					, 256'dx 
					, loadAdr 
					, 3'b000 
				};
				nextState	= READ_BG;
			end
		end
	end else begin
		if (((state != WAIT_CMD) && (state != READ_BG_START))) begin
			case (state)
			READ_CLUT: begin
				if (validRead) begin
					nextState = (lastCLUT        ? WAIT_CMD      :    state);
				end
			end
			WRITE_BG: begin
				nextState = (isBlendingBlock ? READ_BG_START : WAIT_CMD);
			end
			READ_TEX_L: begin
				if (validRead) begin
					nextState = WAIT_CMD;
				end
			end
			READ_TEX_R: begin
				if (validRead) begin
					nextState = WAIT_CMD;
				end
			end
			READ_BG: begin
				if (validRead) begin
					nextState = WAIT_CMD;
				end
			end
			/*
			WAIT_CMD:			nextState = WAIT_CMD;
			*/
			// WAIT_CMD         NEVER REACH HERE
			// READ_BG_START	NEVER REACH HERE  (MUST NEVER !!!)
			default:			nextState = WAIT_CMD;
			endcase
		end
		writeFIFO	= 0;
	end
end

always @(posedge gpuClk)
begin
	if (i_nRst == 0) begin
		state = WAIT_CMD;
	end else begin
		state = nextState;
		
		if (saveTexAdr) begin
			backupTexAdr = adrTexRead;
		end
	end
end

always @(posedge gpuClk)
begin
	if (state == WAIT_CMD) begin
		idxCnt = 3'd0;
	end else begin
		idxCnt = idxCnt + {2'd0, ClutCacheWrite};
	end
end

reg sendCommandToMemory;
wire [289:0] cmdExec;

wire rdEmpty;
// FIFO is 3 + 15 + 256 + 16
MultiClockDomain FIFOCommand(
	.rdClk		(busClk),
	.wrClk		(gpuClk),
	.aclr		(!i_nRst),
	
	.data		(command),	// Input
	.wrreq		(writeFIFO),	// Write input
	.wrfull		(fifoFULL),

	.rdreq		(sendCommandToMemory), // Same flag to request FIFO pop.
	.q			(cmdExec),
	.rdempty	(rdEmpty)
);
wire hasCommand = !rdEmpty;

// ====================================================================================================
//
//    BUS COMMAND SIDE : Push as many things as possible into the FIFO
//
// ====================================================================================================

parameter	CMD_32BYTE		= 2'd1,
			CMD_8BYTE		= 2'd0,
			CMD_4BYTE		= 2'd2;
			
reg [1:0]	commandSize;
reg			waitRead;
reg			resetWait;
reg [15:0]	storageMask;
reg [31:0]	maskBank;
reg [511:0] vvReadCache;
reg         bankID;

reg loadBank;
reg loadVVIndexW;
reg loadVVBank;
reg clearBanksCheck;

always @(*) begin
	sendCommandToMemory = 0;
	resetWait			= 0;
	
	case (cmdExec[2:0])
	3'd2   : commandSize = CMD_8BYTE;
	3'd3   : commandSize = CMD_4BYTE;
	default: commandSize = CMD_32BYTE;
	endcase
	
	case (cmdExec[2:0]) 
	3'd4: begin // READBRT
		loadBank		= 1;
		loadVVIndexW	= 0;
		clearBanksCheck	= 0;
	end
	3'd5: begin // WRITEBRT
		loadBank		= 1;
		loadVVIndexW	= 1;
		clearBanksCheck	= 1;
	end
	default: begin
		loadBank		= 0;
		loadVVIndexW	= 0;
		clearBanksCheck	= 0;
	end
	endcase
	
	if (!i_busy && hasCommand /* && (!waitRead)*/) begin  // If we check for i_busy, then we wait for read too...
		sendCommandToMemory = 1;
	end
	
	if (waitRead && i_dataInValid) begin
		resetWait = 1;
	end
end

wire [15:0] cmdMask = cmdExec[289:274];

always @(posedge busClk) begin
	if (i_nRst == 0) begin
		waitRead	= 0;
		loadVVBank	= 0;
		bankID		= 0;
	end else begin
		// Send command and is READ COMMAND.
		if (sendCommandToMemory && (!cmdExec[0])) begin
			waitRead = 1;
		end
		
		if (waitRead && resetWait) begin
			waitRead	= 0;
			loadVVBank	= 0;
		end

		// [Read BURST Command ONLY]
		if (loadBank & !loadVVIndexW) begin
			// Bank ID used only in READ (when result comes back)
			bankID		= cmdExec[16];
			loadVVBank	= 1;
			if (cmdExec[16]) begin
				maskBank[31:16] = cmdMask;	// Pixel Select Mask
				if (cmdExec[20]) begin				// Clear other bank ?
					maskBank[15:0] = 16'd0;
				end
			end else begin
				maskBank[15:0] = cmdMask;	// Pixel Select Mask
				if (cmdExec[20]) begin				// Clear other bank ?
					maskBank[31:16] = 16'd0;
				end
			end
		end
		
		// Mask Bank will clear for the NEXT READ/WRITE sequence.
		if (clearBanksCheck) begin
			if (cmdExec[20]) begin
				maskBank[15: 0] = 16'd0;
			end
			if (cmdExec[21]) begin
				maskBank[31:16] = 16'd0;
			end
		end
	end
end

always @(posedge busClk) begin
	if (waitRead && loadVVBank && i_dataInValid) begin
		if (bankID) begin
			vvReadCache[511:256] = i_dataIn;
		end else begin
			vvReadCache[255:  0] = i_dataIn;
		end
	end
end

wire [4:0] rotationAmount	= {cmdExec[16],cmdExec[25:22]};
wire [255:0] storage;
ROL512 ROL512_inst(
	.inp		(vvReadCache),
	.rot		(rotationAmount),
	.out		(storage)
);

reg [31:0] tmpMsk;
always @(*) begin
	// 1st step
	tmpMsk = rotationAmount[4] ? { maskBank[15:0] , maskBank[31:16] } : maskBank;
	// 2nd step
	case (rotationAmount[3:0])
	4'h0: storageMask = tmpMsk[15: 0];
	4'h1: storageMask = tmpMsk[16: 1];
	4'h2: storageMask = tmpMsk[17: 2];
	4'h3: storageMask = tmpMsk[18: 3];
	4'h4: storageMask = tmpMsk[19: 4];
	4'h5: storageMask = tmpMsk[20: 5];
	4'h6: storageMask = tmpMsk[21: 6];
	4'h7: storageMask = tmpMsk[22: 7];
	4'h8: storageMask = tmpMsk[23: 8];
	4'h9: storageMask = tmpMsk[24: 9];
	4'hA: storageMask = tmpMsk[25:10];
	4'hB: storageMask = tmpMsk[26:11];
	4'hC: storageMask = tmpMsk[27:12];
	4'hD: storageMask = tmpMsk[28:13];
	4'hE: storageMask = tmpMsk[29:14];
	4'hF: storageMask = tmpMsk[30:15];
	endcase
end

wire VV_GPU_ChkMsk		= cmdExec[18];
wire VV_GPU_ForceMsk	= cmdExec[17];

wire [255:0] currVVPixelWFinal		= { 
	VV_GPU_ForceMsk | storage[255], storage[254:240],
	VV_GPU_ForceMsk | storage[239], storage[238:224],
	VV_GPU_ForceMsk | storage[223], storage[222:208],
	VV_GPU_ForceMsk | storage[207], storage[206:192],
	
	VV_GPU_ForceMsk | storage[191], storage[190:176],
	VV_GPU_ForceMsk | storage[175], storage[174:160],
	VV_GPU_ForceMsk | storage[159], storage[158:144],
	VV_GPU_ForceMsk | storage[143], storage[142:128],
	
	VV_GPU_ForceMsk | storage[127], storage[126:112],
	VV_GPU_ForceMsk | storage[111], storage[110: 96],
	VV_GPU_ForceMsk | storage[ 95], storage[ 94: 80],
	VV_GPU_ForceMsk | storage[ 79], storage[ 78: 64],
	
	VV_GPU_ForceMsk | storage[ 63], storage[ 62: 48],
	VV_GPU_ForceMsk | storage[ 47], storage[ 46: 32],
	VV_GPU_ForceMsk | storage[ 31], storage[ 30: 16],
	VV_GPU_ForceMsk | storage[ 15], storage[ 14:  0]
};

wire [15:0] currVVPixelWFinalSel	= ({16{!VV_GPU_ChkMsk}} | (~cmdMask /*Here is it a stencil, not a mask*/)) & storageMask; // Write all pixels if VV_GPU_ChkMsk=0, else write Pixel when Stencil IS 0.

assign o_write		= cmdExec[0];
assign o_command	= sendCommandToMemory;
assign o_dataOut	= (cmdExec[2:0] != 3'b101) ? cmdExec[273: 18] : currVVPixelWFinal;
assign o_writeMask	= (cmdExec[2:0] != 3'b101) ? cmdMask          : currVVPixelWFinalSel;
assign o_adr		= cmdExec[17:3];
// Access 4/8 byte or 32 byte.
assign o_subadr		= ((cmdExec[2:0] == 3'b010) || (cmdExec[2:0] == 3'b011)) ? cmdExec[278:276] : 3'd0;
assign o_commandSize= commandSize;

// DONE [000:READBG ][15 Bit Adr]----------------------
// DONE [001:WRITEBG][15 Bit Adr][256 Bit][16 bit Mask]
// DONE [010:READ8  ][15 Bit Adr]         [10][2 bit:Adr]0[2---]
// DONE [011:WRITEPR][15 Bit Adr]    [32B][10][3 bit:Adr ][2msk]
//      [100:READBRT][15 Bit Adr]         [Msk Read   ] + CpyBankFlag + clearOtherBank + 1'b1(23) ?
//      [101:WRITBRT][15 Bit Adr]         [StencilRead] + writeBankOld + GPUREG_ForcePixel15 + GPU_Reg_CheckMaskBit + clearBank0 + clearBank1 + cpyIdx
//       110
//       111

wire resEmpty;

// FIFO is 256, depth 1.
MultiClockDomain2 ResultFIFO(
	.rdClk		(gpuClk),
	.wrClk		(busClk),
	.aclr		(!i_nRst),
	
	.data		(i_dataIn),	// Input
	.wrreq		(i_dataInValid && !loadVVBank),	// Write input if we do not use bank.
	.wrfull		(/*Ignore*/),

	.rdreq		(resetRead),
	.q			(res_data),
	.rdempty	(resEmpty)
);

assign validRead = !resEmpty;

endmodule

//------------------------
//  Buffer ROL implementation
//------------------------

module ROL512(
	input  [511:0]		inp,
	input	   [4:0]    rot,
	output [255:0]		out
);

	// wire [511:0] a = inp;
	wire [511:0] a = rot[4] ? { inp[255:0] , inp[511:256] } : inp;

	reg [255:0] br;
	always @(*)
	begin
		/*
		case (rot)
		5'd0 : br = a[255: 0];
		5'd1 : br = a[271:16];
		5'd2 : br = a[287:32];
		5'd3 : br = a[303:48];
		5'd4 : br = a[319:64];
		5'd5 : br = a[335:80];
		5'd6 : br = a[351:96];
		5'd7 : br = a[367:112];
		5'd8 : br = a[383:128];
		5'd9 : br = a[399:144];
		5'd10: br = a[415:160];
		5'd11: br = a[431:176];
		5'd12: br = a[447:192];
		5'd13: br = a[463:208];
		5'd14: br = a[479:224];
		5'd15: br = a[495:240];
		5'd16: br = a[511:256];
		5'd17: br = { a[ 15:0], a[511:272] };
		5'd18: br = { a[ 31:0], a[511:288] };
		5'd19: br = { a[ 47:0], a[511:304] };
		5'd20: br = { a[ 63:0], a[511:320] };
		5'd21: br = { a[ 79:0], a[511:336] };
		5'd22: br = { a[ 95:0], a[511:352] };
		5'd23: br = { a[111:0], a[511:368] };
		5'd24: br = { a[127:0], a[511:384] };
		5'd25: br = { a[143:0], a[511:400] };
		5'd26: br = { a[159:0], a[511:416] };
		5'd27: br = { a[175:0], a[511:432] };
		5'd28: br = { a[191:0], a[511:448] };
		5'd29: br = { a[207:0], a[511:464] };
		5'd30: br = { a[223:0], a[511:480] };
		5'd31: br = { a[239:0], a[511:496] };
		endcase
		*/
		case (rot[3:0])
		4'd0 : br = a[255: 0];
		4'd1 : br = a[271:16];
		4'd2 : br = a[287:32];
		4'd3 : br = a[303:48];
		4'd4 : br = a[319:64];
		4'd5 : br = a[335:80];
		4'd6 : br = a[351:96];
		4'd7 : br = a[367:112];
		4'd8 : br = a[383:128];
		4'd9 : br = a[399:144];
		4'd10: br = a[415:160];
		4'd11: br = a[431:176];
		4'd12: br = a[447:192];
		4'd13: br = a[463:208];
		4'd14: br = a[479:224];
		4'd15: br = a[495:240];
		endcase
	end

	assign out = br;

endmodule
