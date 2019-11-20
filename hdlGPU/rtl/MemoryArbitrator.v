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
	output  [6:0]   ClutWriteIndex,
	output [31:0]   ClutCacheData,
	
	// -- BG Read Stuff --
	input          bgRequest,
	input  [17:0]  bgRequestAdr,
	output         validbgPixel,
	output [31:0]  bgPixel,
	
	// -- BG Write Stuff --
	input  [31:0]  write32,
	input  [17:0]  bgWriteAdr,
	input   [1:0]  pixelValid, 		// Can select pixel we want to DO NOT WRITE. (Mask)
	output         writePixelDone	// Needed ? Most likely... Timing issue here : do want to push 2 pixel per cycle when things going WELL. Should be able to have this flag set with combinatorial only...
									// Memory side will need to manage a 8x32 bit block of memory block allowing to FLUSH the block ( bgWriteAdr[17:3] different from previous pixel write ). Most likely will generate the writePixelDone.

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------
	
	// Own clock, 

	// ---TODO, import all needed signals---
	// -> Need to support byte (well 16 bit MASK) and burst...

);

endmodule
