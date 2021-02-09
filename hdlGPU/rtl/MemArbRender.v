/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module MemArbRender (
	input			gpuClk,
	input			i_nRst,

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
//	output          updateClutCacheComplete,  DEPRECATED

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

    output           o_command,        		// 0 = do nothing, 1 Perform a read or write to memory.
    input            i_busy,           		// Memory busy 1 => can not use.
    output   [1:0]   o_commandSize,    		// 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           o_write,          		// 0=READ / 1=WRITE 
    output [ 14:0]   o_adr,            		// 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   o_subadr,         		// Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   o_writeMask,

    input  [255:0]   i_dataIn,
    input            i_dataInValid,
    output [255:0]   o_dataOut
);

// --------------------------------------------------------------
//   MANAGEMENT OF BATCH BETWEEN READ/WRITE TARGET BUFFER BLOCK.
// --------------------------------------------------------------
// Private/Local
wire		doBGWork     = saveBGBlock[0] | saveBGBlock[1];
reg			lastsaveBGBlock;
always @(posedge gpuClk) begin lastsaveBGBlock <= doBGWork; end
// --------------------------------------------------------------
// PUBLIC SIGNAL IN DESIGN
wire	isFirstBlockBlending	= ((saveBGBlock == 2'b01) & isBlending);
wire	spikeBGBlock			= doBGWork & !lastsaveBGBlock;
// --------------------------------------------------------------


// ---------------------------------------
// Stupid Alias to DDR Side data input
wire        validRead = i_dataInValid;
wire [255:0] res_data = i_dataIn;
// ---------------------------------------
//   write back to Tex$
wire   isTexL,isTexR;
assign TexCacheData				= res_data[63:0];
assign TexCacheWrite			= validRead & (isTexL|isTexR); // ACK down
reg  [16:0] backupTexAdr;
assign adrTexCacheWrite			= backupTexAdr; 		// Write happened when ACK to ZERO (after data
assign updateTexCacheCompleteL	= validRead & isTexL;	// Normally was done 1 cycle sooner
assign updateTexCacheCompleteR	= validRead & isTexR;	// Normally was done 1 cycle sooner

// --------------------------------------------------------------
//   COMMAND TYPE
// --------------------------------------------------------------
parameter   WAIT_CMD			= 3'd0,
			READ_BG				= 3'd1,
			READ_CLUT			= 3'd2,
			READ_TEX_L			= 3'd3,
			READ_TEX_R			= 3'd4,
			WRITE_BG			= 3'd5,
			READ_BG_START		= 3'd6;

reg [2:0]   state;
reg [2:0]   nextState;
// --------------------------------------------------------------
assign resetMask						= ( state == WRITE_BG);
wire isBlendingBlock					= (isBlending && (saveBGBlock != 2'd3));
assign resetPipelinePixelStateSpike		= ((state == WRITE_BG) && (!isBlendingBlock)) || ((state == READ_BG) && validRead);
assign importBGBlockSingleClock			= ( state == READ_BG ) && validRead;
// Data Read. Straight into GPU.
assign importedBGBlock					= res_data;
assign saveLoadOnGoing					= (state != WAIT_CMD);
assign isTexL							= (state == READ_TEX_L);
assign isTexR							= (state == READ_TEX_R);
assign isCLUT							= (state == READ_CLUT );
wire   resetRead						= (nextState == WAIT_CMD  ) && (isTexL | isTexR | isCLUT | (state == READ_BG));

// --------------------------------------------------------------
//   CLUT STUFF
// --------------------------------------------------------------
wire	isCLUT;
reg [2:0] idxCnt;
wire	lastCLUT				= (idxCnt==3'd7);
// CLUT$ Load Request
// assign updateClutCacheComplete	= lastCLUT; <--- Deprecated
// CLUT$ feed updated $ data to cache.
assign ClutCacheWrite			= validRead & isCLUT;
assign ClutWriteIndex			= idxCnt; // 0..7
reg [31:0] s_data32; 
always @(*) begin 
	case (idxCnt)
	3'd0   : s_data32 = res_data[ 31:  0];
	3'd1   : s_data32 = res_data[ 63: 32];
	3'd2   : s_data32 = res_data[ 95: 64];
	3'd3   : s_data32 = res_data[127: 96];
	3'd4   : s_data32 = res_data[159:128];
	3'd5   : s_data32 = res_data[191:160];
	3'd6   : s_data32 = res_data[223:192];
	default: s_data32 = res_data[255:224];
	endcase
end

always @(posedge gpuClk)
begin
	if (state == WAIT_CMD) begin
		idxCnt <= 3'd0;
	end else begin
		idxCnt <= idxCnt + {2'd0, ClutCacheWrite};
	end
end
assign ClutCacheData					= s_data32;

// --------------------------------------------------------------

wire [16:0] adrTexRead = requTexCacheUpdateL ? adrTexCacheUpdateL : adrTexCacheUpdateR;

reg			command;
reg         writeMemory;
reg			saveTexAdr;
reg [1:0]	commandSize;

parameter	CMD_32BYTE		= 2'd1,
			CMD_8BYTE		= 2'd0,
			CMD_4BYTE		= 2'd2;
			
parameter	ADR_BGWRITE		= 2'd0,
			ADR_BGREAD		= 2'd1,
			ADR_CLUTREAD	= 2'd2,
			ADR_TEXREAD		= 2'd3;

reg [1:0]	adrSelect;

always @(*)
begin
	// By default create a command, we erase the flag in the ELSE.
	command		= 1;
	writeMemory	= 0;
	commandSize	= CMD_32BYTE;
	
	nextState	= state;
	saveTexAdr	= 0;
	adrSelect	= ADR_BGWRITE; // Default
	
	if ((!i_busy) && ((state == WAIT_CMD) || (state == READ_BG_START))) begin
		if (state == WAIT_CMD) begin
			if (spikeBGBlock & (saveBGBlock[1] | isFirstBlockBlending)) begin
				if (isFirstBlockBlending) begin
					// READ BG
					adrSelect	= ADR_BGREAD;
					nextState	= READ_BG;
				end else begin
					// WRITE BG
					writeMemory	= 1;
					adrSelect	= ADR_BGWRITE;
					nextState	= WRITE_BG;
				end
			end else begin
				if (requClutCacheUpdate) begin
					adrSelect	= ADR_CLUTREAD;
					nextState	= READ_CLUT;
				end else begin
					if (requTexCacheUpdateL  | requTexCacheUpdateR) begin
						saveTexAdr	= 1;
						commandSize = CMD_8BYTE;
						adrSelect	= ADR_TEXREAD;
						nextState	= requTexCacheUpdateL ? READ_TEX_L : READ_TEX_R;
					end else begin
						//
						// Nothing to do to the FIFO.
						//
						command	= 0;
					end
				end
			end
		end else begin
			adrSelect	= ADR_BGREAD;
			nextState	= READ_BG;
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
		command	= 0;
	end
end

always @(posedge gpuClk)
begin
	if (i_nRst == 0) begin
		state <= WAIT_CMD;
	end else begin
		state <= nextState;
		
		if (saveTexAdr) begin
			backupTexAdr <= adrTexRead;
		end
	end
end

assign o_command	= command;
assign o_write		= writeMemory;
assign o_commandSize= commandSize;

assign o_dataOut	= exportedBGBlock;
assign o_writeMask	= exportedMSKBGBlock;

reg [14:0] outputAdr;
always @(*) begin
	case (adrSelect)
	ADR_BGWRITE	:			outputAdr = saveAdr;
	ADR_BGREAD	:			outputAdr = loadAdr;
	ADR_CLUTREAD:			outputAdr = adrClutCacheUpdate;
	default /*ADR_TEXREAD*/	outputAdr = adrTexRead[16:2];
	endcase
end

assign o_adr		= outputAdr;
assign o_subadr		= (commandSize != CMD_32BYTE) ? {adrTexRead[1:0],1'b0} : 3'd0; // Not necessary problably but cleaner.
	
endmodule
