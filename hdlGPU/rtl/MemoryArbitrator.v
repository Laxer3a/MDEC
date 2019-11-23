/*
	-------------------
	[Memory Arbitrator]
	-------------------
	
	1. This module will manage ALL read/write occur between the GPU and the DDR Memory.
	
	2. This module has TWO mode :
		-> The FIFO mode, that queue command, and do NOT worry about the waiting the result of the previous command.
		Well, actually it will have to execute the command in order (easy and logical with a FIFO anyway).
		But it will not have to wait for other sync signal from the GPU.
		
		[TODO : Describe all the command from FIFO mode]
		
		-> The bus mode where different port will request different things. (TEX$,CLUT$,BG READ, BG WRITE BACK)
		
	3.	[A] Both mode WILL NEVER happen at the same time : the FIFO mode is mainly for VRAM FILL/VRAM COPY stuff.
		The bus mode is for feeding various part of the GPU while 
		
		[B] Bus mode (TEX$, CLUT$, BG Read, BG Write has fixed priorities)
			Here are the priorities :
			From highest to lowest = BG Read >> CLUT$ >> TEX$ >> BG Write. (Very important to have the pixel pipeline easier to implement)
			
			To simplify things, L side has priority over R side (TEX$ and CLUT$)
			
			Expect those buses to request at the same time most of the time.
			
	4.	For BG READ, one must maintain a BURST size cache (16 or 8 pixels), and when the bgRequestAdr is different from currently cached, load another one.

	5.  TEX$
		Adress is 17 bit because the complete VRAM memory space is 20 bit. (1 MegaBYTE) but cache entry are 8 BYTES.
		So the requested cache line is the adress of a 8 byte chunk [xxxx.xxxx.xxxx.xxxx.x000]
		
		At the same time TexCacheWrite is set to HIGH with the 8 byte data (64 bit wide TexCacheData data bus),
		one must also tell to the TEX$ L or R side (the one doing the request) that data is arrived.
		(Something like updateTexCacheCompleteL = requTexCacheUpdateL & TexCacheWrite, same for R)
		
	6.	CLUT$
		Same system as TEX$, except that :
		- The blocks are multiple of 32 byte instead of 8 byte. So read will occur by chunk of 32 bytes and not 8.
		
		- Updating the CLUT$ cache is taking multiple cycle : the update BUS is 4 byte WIDE : 

			 Adress in BYTE from request :
			[xxxx.xxxx.xxxx.xxx0.0000] -> [abcd.efgh.ijkl.mno0.0000]
			
			Index when writing back is then :
			ClutWriteIndex [6:0] is bit [lmnoIII] : lmno from request adress. III is index from 0 to 7 (8 block of 32 bit in order)
			
			It will take 8 cycle once data arrived (updateClutCacheComplete* can be set on the last write) to update the 32 byte block inside the cache.
			
			Fire updateClutCacheComplete* the same way on the LAST element feed.
	
	7. BG Read and BG Write
	
	[There will be a completly different module also competing for DDR access, it may even work on a different clock too, and is not part of this circuit.
	 It is the system reading the VRAM for the CRT display...]
 */

module MemoryArbitrator(
	input			gpuClk,
	input			i_nRst,
	
	// -----------------------------------
	// [GPU FIFO COMMAND SIDE MODE]
	// -----------------------------------

	// ---TODO Describe all fifo command ---
	input  [55:0]	memoryWriteCommand, // if [2:0] not ZERO -> Write to FIFO.
	output          fifoFull,			// 
	output			fifoComplete,		// = Empty signal + all mem operation completed. Needed to know that primitive work is complete.
	
	// --- TODO There will be one more bus here, when we want TO READ the pixel from some command (VRAM->CPU Xfer need that)

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
	// CLUT$ Cache miss from L Side
	input           requClutCacheUpdateL,
	input  [14:0]   adrClutCacheUpdateL,
	output          updateClutCacheCompleteL,
	// CLUT$ Cache miss from R Side
	input           requClutCacheUpdateR,
	input  [14:0]   adrClutCacheUpdateR,
	output          updateClutCacheCompleteR,
	// CLUT$ feed updated $ data to cache.
	output          ClutCacheWrite,
	output  [2:0]   ClutWriteIndex,
	output [31:0]   ClutCacheData,
	
	// -- BG Read Stuff --
	input          bgRequest,
	input  [17:0]  bgRequestAdr,
	output         validbgPixel,
	output [31:0]  bgPixel,
	
	// -- BG Write Stuff --
	input  [31:0]  write32,
	input  [17:0]  bgWriteAdr,		// HOW TO DETECT CHANGE IN CHUNK ? Write BURST...
	input   [1:0]  pixelValid, 		// Can select pixel we want to DO NOT WRITE. (Mask)
	input		   flushBG,
	output         writePixelDone,	// Needed ? Most likely... Timing issue here : do want to push 2 pixel per cycle when things going WELL. Should be able to have this flag set with combinatorial only...
									// Memory side will need to manage a 8x32 bit block of memory block allowing to FLUSH the block ( bgWriteAdr[17:3] different from previous pixel write ). Most likely will generate the writePixelDone.

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------
	
	// Own clock ? -> http://www.asic.co.in/Index_files/digital_files/clock_domain_crossin.htm

	// For now support slow Wishbone...
    output [19:0]   adr_o,   // ADR_O() address
    input  [31:0]   dat_i,   // DAT_I() data in
    output [31:0]   dat_o,   // DAT_O() data out
	output  [2:0]	cnt_o,
    output  [3:0]   sel_o,   // SEL_O() select output
	output   wrt_o,
	output 	 req_o,
    input    ack_i
);

reg [255:0] cacheBGRead;
reg  [15:0] cacheBGMsk;
reg  [14:0] cacheBGAdr;
reg  [17:0] baseAdr;
reg  [31:0] regDatI;
wire isDifferentBG = (cacheBGAdr != bgWriteAdr[17:3]);

assign ClutCacheData		= dat_i;
assign bgPixel		 		= dat_i;

assign TexCacheData[63:32]	= dat_i;
assign TexCacheData[31: 0]  = regDatI;
assign adrTexCacheWrite		= baseAdr[17:1];

assign ClutWriteIndex		= currX[2:0];

assign ClutCacheWrite		= s_writeGPU & (regReadMode[3:1] == 3'd2);
assign TexCacheWrite		= s_writeGPU & (regReadMode[3:1] == 3'd3);
assign validbgPixel			= s_writeGPU & (regReadMode[3:1] == 3'd1);
assign writePixelDone		= s_writePixelDone;
assign updateTexCacheCompleteL	= s_updateTexCacheCompleteL;
assign updateTexCacheCompleteR	= s_updateTexCacheCompleteR;
assign updateClutCacheCompleteL	= s_updateClutCacheCompleteL;
assign updateClutCacheCompleteR	= s_updateClutCacheCompleteR;

//
// GPU Side State machine...
//
reg [2:0] currState;
parameter	DEFAULT_STATE = 3'b000, READ_STATE = 3'b001, WRITE_BLOCK = 3'b010;

always @(posedge gpuClk)
begin
	if (i_nRst == 1'b0) begin
		currState	= DEFAULT_STATE;
		cacheBGAdr	= 15'h7FFF;
		cacheBGMsk	= 16'd0;
		currX		= 4'd0;
	end else begin
		currState	= nextState;
		
		if (ReadMode[3:1] != 3'd0) begin
			regReadMode = ReadMode;
		end
		
		if (writePixelInternal) begin
			case (bgWriteAdr[2:0])
			3'd0: begin cacheBGRead[ 31:  0] = write32; cacheBGMsk[ 1: 0] = pixelValid; end
			3'd1: begin cacheBGRead[ 63: 32] = write32; cacheBGMsk[ 3: 2] = pixelValid; end
			3'd2: begin cacheBGRead[ 95: 64] = write32; cacheBGMsk[ 5: 4] = pixelValid; end
			3'd3: begin cacheBGRead[127: 96] = write32; cacheBGMsk[ 7: 6] = pixelValid; end
			3'd4: begin cacheBGRead[159:128] = write32; cacheBGMsk[ 9: 8] = pixelValid; end
			3'd5: begin cacheBGRead[191:160] = write32; cacheBGMsk[11:10] = pixelValid; end
			3'd6: begin cacheBGRead[223:192] = write32; cacheBGMsk[13:12] = pixelValid; end
			3'd7: begin cacheBGRead[255:224] = write32; cacheBGMsk[15:14] = pixelValid; end
			endcase
		end
		
		if (s_storeAdr) begin
			baseAdr = s_busAdr[19:2];
		end
		
		if (s_store) begin
			regDatI = dat_i;
		end
		
		if (incrX) begin
			currX = currX + 4'b0001;
		end else begin
			if (resetX) begin
				currX = 0;
			end
		end
	end
end

// Output
reg [19:0]	s_busAdr;	assign adr_o = s_busAdr;
reg  [2:0]  s_cnt;		assign cnt_o = s_cnt;
reg         s_busREQ;	assign req_o = s_busREQ;
reg  [1:0]  busWMSK;	assign sel_o = {busWMSK[1],busWMSK[1],busWMSK[0],busWMSK[0]};
reg [31:0]	busDataW;	assign dat_o = busDataW;
reg			busWRT;		assign wrt_o = !readStuff;
// Input
wire [31:0]	busDataR = dat_i;
wire busACK		= ack_i;



reg readStuff;
reg [2:0] nextState;
reg writePixelInternal;
reg [3:0] currX;
reg       incrX, resetX;
reg s_store;
reg s_writeGPU;
reg s_storeAdr;
reg s_writePixelDone;
reg	s_updateTexCacheCompleteL;
reg	s_updateTexCacheCompleteR;
reg	s_updateClutCacheCompleteL;
reg	s_updateClutCacheCompleteR;

wire isClutReq 		= requClutCacheUpdateL | requClutCacheUpdateR;
wire isTexReq  		= requTexCacheUpdateL  | requTexCacheUpdateR;
wire hasValidPixels = pixelValid[0] | pixelValid[1];
reg [3:0] ReadMode, regReadMode;
always @(*)
begin
	// Default
	readStuff			= 1'b1;
	nextState			= currState;
	writePixelInternal	= 1'b0;
	resetX				= 1'b0;
	incrX				= 1'b0;
	busWMSK				= 2'b00;
	busDataW			= 32'd0;
	s_cnt				= 3'd0;
	s_busAdr			= 20'd0;
	s_busREQ			= 1'b0;
	ReadMode			= 4'd0;
	s_store				= 1'b0;
	s_storeAdr			= 1'b0;
	s_writeGPU			= 1'b0;
	s_writePixelDone	= 1'b0;
	s_updateTexCacheCompleteL	= 1'b0;
	s_updateTexCacheCompleteR	= 1'b0;
	s_updateClutCacheCompleteL	= 1'b0;
	s_updateClutCacheCompleteR	= 1'b0;
	
	case (currState)
	default:
	begin
		// [Do nothing]
		nextState = DEFAULT_STATE;
	end
	DEFAULT_STATE:
	begin
		if (!busACK) begin
			if (bgRequest) begin
				// [READ] For now read two pixel per block.
				// ... BG Read ...
				s_busAdr	= { bgRequestAdr, 2'b00 }; // Adr by 2 pixel 16 bit.
				s_busREQ	= 1'b1;
				s_storeAdr	= 1'b1;
				s_cnt       = 3'd0; // 1 block of 32 bit.
				ReadMode	= 4'b0010;
				nextState	= READ_STATE;
			end else begin
				if (isClutReq) begin
					// [READ]
					// ... CLUT$ Update ...
					ReadMode = { 3'b010, requClutCacheUpdateR };
					s_storeAdr	= 1'b1;
					if (requClutCacheUpdateL) begin
						// Left First...
						s_busAdr	= { adrClutCacheUpdateL, 5'd0 }; // Adr by 32 byte block.
						s_busREQ	= 1'b1;
						s_cnt       = 3'd7; // 8 block of 32 bit.
						nextState	= READ_STATE;
					end else begin
						// Right Second...
						s_busAdr	= { adrClutCacheUpdateR, 5'd0 }; // Adr by 32 byte block.
						s_busREQ	= 1'b1;
						s_cnt       = 3'd7; // 8 block of 32 bit.
						nextState	= READ_STATE;
					end
				end else begin
					if (isTexReq) begin
						ReadMode = { 3'b011, requClutCacheUpdateR };
						s_storeAdr	= 1'b1;
						// [READ]
						// ... TEX$ Update ...
						if (requTexCacheUpdateL) begin
							// Left First...
							s_busAdr	= { adrTexCacheUpdateL, 3'd0 }; // Adr by 8 byte block.
							s_busREQ	= 1'b1;
							s_cnt       = 3'd1; // 2 block of 32 bit.
							nextState	= READ_STATE;
						end else begin
							// Right Second...
							s_busAdr	= { adrTexCacheUpdateR, 3'd0 }; // Adr by 8 byte block.
							s_busREQ	= 1'b1;
							s_cnt       = 3'd1; // 2 block of 32 bit.
							nextState	= READ_STATE;
						end
					end else begin
						if (hasValidPixels | flushBG) begin
							
							readStuff = 0;
							if (isDifferentBG | flushBG) begin
								// [WRITE]
								// Write back.
								s_busREQ	= 1'b1;
								s_storeAdr	= 1'b1;
								s_busAdr	= { cacheBGAdr, 5'd0 };
								
								// TODO : Could optimize BURST size based on cacheBGMsk complete.
								s_cnt		= 3'd7;
								
								nextState	= WRITE_BLOCK;
							end else begin
								// Store locally pixels...
								s_writePixelDone	= 1;
								writePixelInternal	= 1;
							end
						end else begin
							// [READ/WRITE]
							// readStuff = 1 or 0; // TODO
							// FIFO & CO
							// FILL COMMAND BURST.
						end
					end
				end
			end
		end
	end
	READ_STATE:
	begin
		if (busACK) begin
			incrX = 1'b1;
			case (regReadMode[3:1])
			3'd1: // BG read 32 byte.
			begin
				s_writeGPU = 1'b1;
			end
			3'd2: // Clut 32 byte
			begin
				s_writeGPU = 1'b1;
				if (currX[3:0] == 4'b111) begin
					// Last value write (only 2)
					s_updateClutCacheCompleteL = !regReadMode[0];
					s_updateClutCacheCompleteR =  regReadMode[0];
				end else begin
				end
			end
			3'd3: // Texture 8 byte
			begin
				if (currX[2:0] == 3'b000) begin
					s_store = 1;
				end else begin
					// Last value write (only 2)
					s_updateTexCacheCompleteL = !regReadMode[0];
					s_updateTexCacheCompleteR =  regReadMode[0];
					s_writeGPU = 1'b1;
				end
			end
			default:
			begin
			end
			endcase
		end else begin
			nextState = DEFAULT_STATE;
		end
	end
	WRITE_BLOCK:
	begin
		readStuff	= 1'b0;
		// TODO : Could optimize BURST size based on cacheBGMsk complete.
//		s_cnt		= currX[2:0];
		
		// [Write Burst]
		if (busACK) begin
			if (currX != 4'd8) begin
				s_busAdr = { cacheBGAdr, currX[2:0], 2'b0 };
				case (currX[2:0])
				3'd0: begin busDataW = cacheBGRead[ 31:  0]; busWMSK = cacheBGMsk[ 1: 0]; end
				3'd1: begin busDataW = cacheBGRead[ 63: 32]; busWMSK = cacheBGMsk[ 3: 2]; end
				3'd2: begin busDataW = cacheBGRead[ 95: 64]; busWMSK = cacheBGMsk[ 5: 4]; end
				3'd3: begin busDataW = cacheBGRead[127: 96]; busWMSK = cacheBGMsk[ 7: 6]; end
				3'd4: begin busDataW = cacheBGRead[159:128]; busWMSK = cacheBGMsk[ 9: 8]; end
				3'd5: begin busDataW = cacheBGRead[191:160]; busWMSK = cacheBGMsk[11:10]; end
				3'd6: begin busDataW = cacheBGRead[223:192]; busWMSK = cacheBGMsk[13:12]; end
				3'd7: begin busDataW = cacheBGRead[255:224]; busWMSK = cacheBGMsk[15:14]; end
				endcase
				
				incrX		= 1'b1;
				s_busREQ	= 1'b1;
			end else begin
				nextState	= DEFAULT_STATE;
				resetX		= 1'b1;
				s_busREQ	= 1'b0;
			end
		end
	end
	endcase
end

endmodule
