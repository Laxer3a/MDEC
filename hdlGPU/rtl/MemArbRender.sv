/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
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
	output [255:0]  ClutCacheData,

	input			saveBGBlock,
	input  [14:0]	saveAdr,
	input [255:0]	exportedBGBlock,
	input  [15:0]	exportedMSKBGBlock,
	output			o_blockSaving,
	output			o_blockSaved,

	// BG Loaded in different clock domain completed loading, instant transfer of 16 bit BG.
	input			loadBGBlock,
	input  [14:0]	loadAdr,
	output			importBGBlockSingleClock,
	output  [255:0]	importedBGBlock,

	output			saveLoadOnGoing,
//	output			saveLoadCompleteNextCycle,

	output          o_outputIdle,           // All memory transactions drained

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
			READ_TEX_R			= 3'd4;
			/*WRITE_BG			= 3'd5*/

wire        fifo_space_w;

reg [2:0]   state;
reg [2:0]   nextState;
wire	    isCLUT;

// --------------------------------------------------------------
// Data Read. Straight into GPU.
wire   askReadWrite						= (saveBGBlock | loadBGBlock);
assign importedBGBlock					= res_data;
assign saveLoadOnGoing					= ~fifo_space_w;
// assign saveLoadCompleteNextCycle		= saveLoadOnGoing && (nextState == WAIT_CMD);
assign isTexL							= (state == READ_TEX_L);
assign isTexR							= (state == READ_TEX_R);
assign isCLUT							= (state == READ_CLUT );
assign importBGBlockSingleClock			= (state == READ_BG   ) && validRead;
// --------------------------------------------------------------
//   CLUT STUFF
// --------------------------------------------------------------
assign ClutCacheWrite	= validRead & isCLUT;
assign ClutCacheData	= i_dataIn;

// --------------------------------------------------------------

wire [16:0] adrTexRead = requTexCacheUpdateL ? adrTexCacheUpdateL : adrTexCacheUpdateR;

reg			command;
reg 		pipeWrite;
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

always @(posedge gpuClk) begin
	if (!i_nRst)
		pipeWrite <= 0;
	else
		pipeWrite <= writeMemory;
end

always @(*)
begin
	// By default create a command, we erase the flag in the ELSE.
	command		= 0;
	writeMemory	= 0;
	commandSize	= CMD_32BYTE;
	
	nextState	= state;
	saveTexAdr	= 0;
	adrSelect	= ADR_BGWRITE; // Default
	
	case (state)
	WAIT_CMD: begin
		if (fifo_space_w) begin
			if (requClutCacheUpdate) begin
				adrSelect	= ADR_CLUTREAD;
				nextState	= READ_CLUT;
				command		= 1;
			end else begin
				if (requTexCacheUpdateL  | requTexCacheUpdateR) begin
					saveTexAdr	= 1;
					commandSize = CMD_8BYTE;
					adrSelect	= ADR_TEXREAD;
					nextState	= requTexCacheUpdateL ? READ_TEX_L : READ_TEX_R;
					command		= 1;
				end else if (askReadWrite) begin
						// Read Higher Priority than write...
					command		= 1;
					if (loadBGBlock) begin
						// READ BG
						adrSelect	= ADR_BGREAD;
						nextState	= READ_BG;
					end else begin
						// WRITE BG
						writeMemory	= 1;
						adrSelect	= ADR_BGWRITE; // Default value anyway
						// nextState	= WAIT_CMD;		// No special State for WRITE !
														// Write when valid
					end
				end
			end
		end
	end
	READ_CLUT: begin
		if (validRead) begin
			nextState = WAIT_CMD;
		end
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
	default: nextState = WAIT_CMD;
	endcase
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

assign o_blockSaved	= pipeWrite;
assign o_blockSaving= writeMemory;
assign o_outputIdle = ~o_command;

//-----------------------------------------------------------------
// Memory Request
//-----------------------------------------------------------------
reg [14:0] outputAdr;

always @(*) begin
	case (adrSelect)
	ADR_BGWRITE	:			outputAdr = saveAdr;
	ADR_BGREAD	:			outputAdr = loadAdr;
	ADR_CLUTREAD:			outputAdr = adrClutCacheUpdate;
	default /*ADR_TEXREAD*/	outputAdr = adrTexRead[16:2];
	endcase
end

wire [2:0] subadr_w = (commandSize != CMD_32BYTE) ? {adrTexRead[1:0],1'b0} : 3'd0; // Not necessary problably but cleaner.
	
gpu_mem_fifo
#(
     .WIDTH(256 + 16 + 2 + 1 + 15 + 3)
    ,.DEPTH(2)
    ,.ADDR_W(1)
)
u_mem_req
(
     .clk_i(gpuClk)
    ,.rst_i(~i_nRst)

    ,.push_i(command)
    ,.data_in_i({subadr_w, outputAdr, writeMemory, commandSize, exportedMSKBGBlock, exportedBGBlock})
    ,.accept_o(fifo_space_w)

    // Outputs
    ,.data_out_o({o_subadr, o_adr, o_write, o_commandSize, o_writeMask, o_dataOut})
    ,.valid_o(o_command)
    ,.pop_i(~i_busy)
);

endmodule

/*
wire isBlendingBlock					= (isBlending && (saveBGBlock != 2'd3));
assign resetPipelinePixelStateSpike		= ((state == WRITE_BG) && (!isBlendingBlock)) || ((state == READ_BG) && validRead);
	input	[1:0]	saveBGBlock,			// 00:Do nothing, 01:First Block, 10 : Second and further blocks.
											// First block does nothing if no blending (no BG load)
											// Second block does LOAD/SAVE or LOAD only based on state.
	input			isBlending,

// --------------------------------------------------------------
//   MANAGEMENT OF BATCH BETWEEN READ/WRITE TARGET BUFFER BLOCK.
// --------------------------------------------------------------
	output			resetPipelinePixelStateSpike,
	output			resetMask,				// Reset the list of used pixel inside the block for next block processing.
assign resetMask						= ( state == WRITE_BG);
// Private/Local
wire		doBGWork     = saveBGBlock[0] | saveBGBlock[1];
reg			lastsaveBGBlock;
always @(posedge gpuClk) begin lastsaveBGBlock <= doBGWork; end
// --------------------------------------------------------------
// PUBLIC SIGNAL IN DESIGN
wire	isFirstBlockBlending	= ((saveBGBlock == 2'b01) & isBlending);
wire	spikeBGBlock			= doBGWork & !lastsaveBGBlock;
// --------------------------------------------------------------
				nextState = (isBlendingBlock ? READ_BG_START : WAIT_CMD);
*/
