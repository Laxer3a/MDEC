/*
XA-ADPCM Header Bytes

  0-3   Shift  (0..12) (0=Loudest) (13..15=Reserved/Same as 9)   OK
  4-5   Filter (0..3) (only four filters, unlike SPU-ADPCM which has five)
   or
  4-6   Filter (0..4) SPU-ADPCM
  6-7   Unused (should be 0)
---------------------------  
    auto shift = buffer[0] & 0x0f;	// OK
    if (shift > 9) shift = 9;
	
	// 
    auto filter = (buffer[0] & 0x70) >> 4;  // 0x40 for xa adpcm

    assert(filter <= 4);
    if (filter > 4) filter = 4;  // TODO: Not sure, check behaviour on real HW
  
*/

/*
	Timing :
	- When we add PITCH to sample -> We compute the NEXT sample offset.
	
	- Let's imagine we have 24 cycles budget per channel :
	-------------------------------------------------------------------------------------------------
Things to do by steps (can be done in the same cycle) :
	Step 0
		.REQ BRAM read 1/adr channel and 2/pitch 3/currentSample fixed counter.	
	
		// TODO Can do ADSR in //ism.
	
	Step 1
		.Add Adr and Compute NEXT address.	
		.Decide if NEXT 4 sample block or not ?	
		.Decide which 16 bit block to read (still current or next)
		.Decide if block ended and load new block.	
		isNewBlock -> tmp register.	
		isNextLine -> tmp register. (or !isSameLine), 1 also if isNewBlock.	
		
		.BRAM WRITE back adr (fixed point including pitch) in the same cycle.
		
		.DRAM REQUEST : Ask for HEADER if new block	
		 (NEED SHIFT and FILTER loaded FIRST)
		/else can use the slot to do a FIFO write for data transfer...	
	
	Step2
		.IF HEADER REQUEST => Receive Header, WRITE store it in channel BRAM
		.If uncached ADPCM => DRAM REQUEST : Ask for ADPCM block. (custom optimization, we can force read of 
		.If cached   ADPCM => /else can do FIFO work.
	Step3
		.If ADPCM Request  => Write to ADPCM Data Bank.
	Step4
		.BRAM Request for HEADER/ADPCM State/Data/SampleCounter/etc.... (need to put the adress)
	Step5 (multiple cycle consecutive)
		StepA
		.BRAM ALL : Read Header, Read ADPCM Decoder PreviousSample(s) -> Setup the ADPCM decoder, Read Sample Counter
		StepB
		.Output Sample 0
		StepC
		.Output Sample 1
		StepD
		.Output Sample 2
		StepE
		.Output Sample 3
		
		Select at A/B/C/D 
			-> WRITE BACK PreviousSample
			-> Output value to ADSR stage.
		
		Wait until channel next, goto step 0.
		
	--- Group 1 ---
	Cycle 0 : 	
	Cycle 1 : 	
				
				
				
				
				
				
				
				
				
	Cycle 2 :	
	Cycle 3 :
	--- Group 2 ---
	Cycle 4 :
	Cycle 5 :
	Cycle 6 :
	Cycle 7 :
	--- Group 3 ---
	Cycle 8 :
	Cycle 9 :
	Cycle 10:
	Cycle 11:
	--- Group 4 ---
	Cycle 12:
	Cycle 13:
	Cycle 14:
	Cycle 15:
	--- Group 5 ---
	Cycle 16:
	Cycle 17:
	Cycle 18:
	Cycle 19:
	--- Group 6 ---
	Cycle 20:
	Cycle 21:
	Cycle 22:
	Cycle 23:
	
	-------------------------------------------------------------------------------------------------
	
	
	Sample Block
	[ Header 16 bit  ]
	[ A 8 B ][ C 8 D ]	4
	[ A 8 B ][ C 8 D ]	4
	[ A 8 B ][ C 8 D ]	4
	[ A 8 B ][ C 8 D ]	4
	[ A 8 B ][ C 8 D ]	4
	[ A 8 B ][ C 8 D ]	4
	[ A 8 B ][ C 8 D ]	4	= 28 sample per block.
 */


module ADPCMDecoder(
	input			clk,
	
	input			start,
	input			[3:0]	inShift,
	input			[2:0]	inFilter,
	
	input 			[15:0]	inputRAW,
	input signed	[15:0]	sampleRAWStart,

	input signed	[15:0]	inPrevSample,
	input signed    [15:0]  inPrevPrevSample,
	input            [2:0]  lastSamplePos,	// Will tell use if we need to recompute the sample or reuse it. (100 : from previous block)
	
	output			[1:0]	count,
	output signed	[15:0]	outSample,
	output signed   [15:0]  outPrevSample,
	output signed   [15:0]  outPrevPrevSample,
	
	/* Block status...
	input loopEnd,
	input loopRepeat,
	input loopStart,
	*/
)

wire [3:0] shift  = (inShift < 4'd13) ? inShift  : 4'd9;
wire [2:0] filter = (inShift < 4'd5 ) ? inFilter : 4'd4;
wire signed [7:0] filterPos;
wire signed [7:0] filterNeg;

always (*)
begin
	case (filter)
	default	: begin filterPos <= 8'd0;   filterNeg <=   8'd0; end;
	4'd0	: begin filterPos <= 8'd0;   filterNeg <=   8'd0; end;
	4'd1 	: begin filterPos <= 8'd60;  filterNeg <=   8'd0; end;
	4'd2 	: begin filterPos <= 8'd115; filterNeg <= -8'd52; end;
	4'd3 	: begin filterPos <= 8'd98;  filterNeg <= -8'd55; end;
	4'd4 	: begin filterPos <= 8'd122; filterNeg <= -8'd60; end;
	endcase
end

reg [3:0] nibble;
always (*)
begin
	case (internalCounter)
	2'd0	: nibble <= inputRAW[ 3: 0];
	2'd1 	: nibble <= inputRAW[ 7: 4];
	2'd2 	: nibble <= inputRAW[11: 8];
	2'd3 	: nibble <= inputRAW[15:12];
	endcase
end

// 12 Shift nibble >>
//  2 stage shifter. (smaller FIRST, circuit smaller and faster)
reg [6:0] firstStageNibble;
always (*)
begin
	case (shift[1:0])
	2'd0 	: firstStageNibble <= { nibble , 3'b000  };
	2'd1 	: firstStageNibble <= { 1'b0   , nibble , 2'b00 };
	2'd2 	: firstStageNibble <= { 2'b00  , nibble , 1'b0  };
	2'd3	: firstStageNibble <= { 3'b000 , nibble  };
	endcase
end

reg [15:0] baseSample;
always (*)
begin
	case (shift[3:2])	// 4/8/12
	// From 0..11 Work fine
	2'd0 	: baseSample <= { firstStageNibble, 9'd0  };
	2'd1 	: baseSample <= { 4'd0, firstStageNibble, 5'd0 };
	2'd2 	: baseSample <= { 8'd0, firstStageNibble, 1'd0 };
	// For 12 Specific case.
	2'd3	: baseSample <= { 12'd0, nibble };
	endcase
end

always(clk)
begin
	if (start)
	begin
		counter <= "00";
	else
	end
end
/*
    s = (t SHL shift) + ((old*f0 + older*f1+32)/64);
    s = MinMax(s,-8000h,+7FFFh)
    halfword[dst]=s, dst=dst+2, older=old, old=s
 */

// sample += (prevSample[0] * filterPos + prevSample[1] * filterNeg + 32) / 64;

endmodule
