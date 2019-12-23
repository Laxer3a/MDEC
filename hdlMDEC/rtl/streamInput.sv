`include "MDEC_Cte.sv"

/*
---------------------------------------------------------------
  MDEC Stream Specification :
---------------------------------------------------------------

1 - MDEC receive stream of 16 bit unsigned value.
2 - The stream is a list of block, ending with 0xFE00.
3 - Each block describe a UVY video 8x8 sparse matrix (in order Cr,Cb, Y0,Y1,Y2,Y3) or a list of Y block if 'Y only mode' is set.
	- First value is for Matrix [0,0] : [Scale  6 bit][Coefficient 10 bit signed]
	- Following values are            : [Offset 6 bit][Coefficient 10 bit signed]
	
	With CurrentIndex = PreviousIndex + 1 + Offset for current value. (CurrentIndex = 0 for first value)
	- Note that Index is in ZIGZAG order, not LINEAR ORDER when writing in the destination matrix in RLE mode. (but LINEAR in FULL mode(scale=0)).
	- Stream ends when End Of Block(EOB)[111111 6 bit][10_0000_0000 10 bit value]
	
	If [Scale] is ZERO, then we have a FULL 64 entry block in LINEAR order AND not SPARSE.
	Also end of block (EOB) works but becomes optionnal.

	Note :	Implementation will lock if 'Y only mode' per matrix stream. Switch between entries will be ignored.
			The value to be used for the flag is with the FIRST item on the block stream.
4 -	After this unit, output coefficient are multiplied using different rules :
  - Is inside a UV or Y block ?							(o_blockNum)
  - Is inside a LINEAR non sparse uncompressed block	(o_fullBlockType)
  - Is it the element at [0,0]							(o_isDC)
    (Quantization table use the o_zagIndex to read linearly)
	
---------------------------------------------------------------
  Unit Specification :
---------------------------------------------------------------
Inputs :
- assert i_dataWrite at the same time you input a 16 bit i_dataIn value.
- Negative reset do reset the internal in 1 cycle.

Outputs:
- o_dataWrt signal says all the others o_* are valid EXCEPT for o_blockComplete (independant)
	Block can be complete AT    the last valid item (item at index 63)
	Block can be complete AFTER the last valid item (value 0xFE00)
- o_scale is maintained through the RLE block, user has no need to keep the scale value from
  first item. It is already taken care of.
- o_fullBlockType value is also guaranteed for the whole block length.
- o_blockNum (0=Y1, 1=Y2, 2=Y3, 3=Y4, 4=Cr, 5=Cb | 7=Y only mode)
- o_blockComplete : the previous element (o_dataWrt = 0) or this current element (o_dataWrt = 1) is the last one.
  (Reason : signal is issue when encounter EOB on standard block, or issued at the same time of last element when FULL LINEAR type).
*/

module streamInput(
	input				clk,
	input				i_nrst,
	input				bDataWrite,
	input [15:0]		i_dataIn,
	input 				i_YOnly,
	
//	output				o_outOfRangeblockIndex,
	
	output				o_dataWrt,
	output[9:0]			o_dataOut,
	output[5:0]			o_scale,
	output				o_isDC,
	output[5:0]			o_index,			// Linear or Z order for storage
	output[5:0]			o_linearIndex,		// Linear index for Quant Read.
	output				o_fullBlockType,
	output MDEC_BLCK	o_blockNum,			// Need to propagate info with data, easier for control logic.
	output				o_blockComplete
);
	// --------------------------------------------------------
	// [alias, basic flag for current data reading]
	wire[5:0]	offset			= i_dataIn[15:10];
	wire[9:0]	coef			= i_dataIn[ 9: 0];
	
	// Full Uncompressed block, when 1st input offset(scale) is ZERO.
	// This value is valid only for one cycle, we save it in rIsFullBlock
	wire		isFullBlock		= (offset == 0);
	reg 		rIsFullBlock;

	// Is current input is EndOfBlock marker ?
	wire		isEOB			= (i_dataIn == 16'hFE00);

	// --------------------------------------------------------
	// [Internal Stuff]
	reg [5:0]	indexCounter;	// Current item counter.
	reg [5:0]	scalereg;		// Stored special offset from 1st item (Scale value)

	// --- State Machine ---
	reg [1:0]	state,nextState;
	// First value is DC, Other values are AC.
	parameter	LOAD_DC=2'b0, LOAD_OTHER=2'b1;
	// ---------------------
	
	wire[5:0]	nextIdx			= (indexCounter + 6'b000001 + offset);
	wire		isDC			= (state == LOAD_DC);

	// Current Offset in the matrix in ZigZag Order
	// When DC we force to ZERO (as offset value is a SCALE factor for other purpose)
	wire[5:0]	currIdx			= isDC ? 6'b000000 : nextIdx; // (Note : 1'b1 to adder to avoid 32 bit warning)

	// Block is complete with current input :
	// if OEB input or full uncompressed block with last item (no EOB is possible)
	// Generated only ONCE. (per sequence, included empty sequences)
	wire		isBlockComplete	= ((isEOB) | (currIdx[5:0] == 63)) & bDataWrite;
	// (state!=LOAD_DC) : Add protection here about avoid increment counter with empty FE00 sequences...
	wire		isValidBlockComplete	= isBlockComplete & (!isDC);

	/*
	// -----------------------------------------------------------
	// Detect a block with an invalid index.
	// Not in the MDEC spec, but could be usefull as we do not how to deal with this case in the specs.
	// If 
	//
	reg			outOfRangeblockIndex;
	always @(posedge clk) begin
		if (i_nrst==0) begin
			outOfRangeblockIndex <= 1'b0;
		end else
			if (currIdx[6]) begin
				outOfRangeblockIndex <= 1'b1;
			end
		end
	end
	assign o_outOfRangeblockIndex = outOfRangeblockIndex;
	// -----------------------------------------------------------
	*/
	
	// if (i_idctBusy && isBlockComplete) then
	//	waitUntil i_idctBusy = 0;
	//	assign blockComplete = 1;
	// end
	assign	o_blockComplete	= isValidBlockComplete;
	
	// --------------------------------------------------------
	//   Block handling the U,V,Y0,Y1,Y2,Y3 counter.
	//   - Handle special case when Y only mode is enabled.
	//	 ON RESET : 0 if CHROMA register setup / 2 if MONO setup
	//	 ON Y SET : 2.
	//   - Load Value only on DC for monochrome
	//	 - Switch from monochrome to chroma handled by 1 cycle no job state guaranteed by MDEC architecture.
	//	 - Increment only when reaching next block.
    //   => Protected against i_YOnly changes.
    //
	reg         prevYOnly;
	always @(posedge clk) begin
		prevYOnly = i_YOnly;
	end
	
	MDEC_BLCK	rBlockCounter, nextBlockCounter;
	always @(posedge clk) begin
		rBlockCounter	= nextBlockCounter;
	end
	
	always @(*) begin
		if ((i_nrst == 0) | (i_YOnly) | (i_YOnly ^ prevYOnly)) begin
			nextBlockCounter	= { 1'b1, i_YOnly, i_YOnly };	// Reset set Counter to 4 for Color or 7 for always Y.
		end else begin
			if (isValidBlockComplete)	// Increment block counter only with VALID stream (no empty FE00)
			begin
				if (rBlockCounter == BLK_CB)
					nextBlockCounter = BLK_Y1;
				else
					nextBlockCounter = rBlockCounter + 3'b001;
			end else begin
				nextBlockCounter = rBlockCounter;
			end
		end
	end
	// --------------------------------------------------------

	// --------------------------------------------------------
	//   Block Handle saving of DC Coefficient.
	//                       of Uncompressed full block state.
	//                input coefficient counter.
	
	// Move the equation outside did the simulator work... Sigh...
	wire condFullBlock = isFullBlock & (!isEOB);
	
	always @(posedge clk) begin
		if (i_nrst == 0)
		begin
			indexCounter	= 0;
			scalereg		= 0; // Not necessary, but cleaner.
			rIsFullBlock	= 0; // Not necessary, but cleaner.
		end else begin
			if (bDataWrite)
			begin
				if (isDC)
				begin
					scalereg	 = offset;
					rIsFullBlock = condFullBlock; // Make sure EMPTY EOB is not counted.
				end
				
				if (isBlockComplete) // Empty FE00 sequence reset counter too, no pb.
					indexCounter = 0;
				else
					indexCounter = currIdx;
			end
		end
	end
	// --------------------------------------------------------

	
	// --------------------------------------------------------
	// ---- STATE MACHINE : Combinatorial part ----
	always @(*) begin
		case (state)
		LOAD_DC:
			if (bDataWrite & (!isEOB))	// Test that if we have a sequence of FE00 of empty block, we stay on LOAD_DC
				nextState = LOAD_OTHER;
			else
				nextState = state;
		LOAD_OTHER:
			if (bDataWrite & isBlockComplete)
				nextState = LOAD_DC;
			else
				nextState = state;
		default:
			nextState = LOAD_DC;
		endcase
	end
	// ---- STATE MACHINE : Clocked part ----
	always @(posedge clk) begin
		state = (i_nrst == 0) ? LOAD_DC : nextState;
	end
	// --------------------------------------------------------

	// --------------------------------------------------------
	// ZAG Logic Decode / ROM like.
	// --------------------------------------------------------
	wire [5:0] currIdx6Bit = currIdx[5:0];
	
	reg [5:0] z; // PUT HERE BECAUSSE MODELSIM DID NOT LIKE AFTER !!!!
    always @(*)
    begin
        case (currIdx6Bit)
        'd0  : z = 6'd0;
        'd1  : z = 6'd1;
        'd2  : z = 6'd8;
        'd3  : z = 6'd16;
        'd4  : z = 6'd9;
        'd5  : z = 6'd2;
        'd6  : z = 6'd3;
        'd7  : z = 6'd10;
        'd8  : z = 6'd17;
        'd9  : z = 6'd24;
        'd10 : z = 6'd32;
        'd11 : z = 6'd25;
        'd12 : z = 6'd18;
        'd13 : z = 6'd11;
        'd14 : z = 6'd4;
        'd15 : z = 6'd5;
        'd16 : z = 6'd12;
        'd17 : z = 6'd19;
        'd18 : z = 6'd26;
        'd19 : z = 6'd33;
        'd20 : z = 6'd40;
        'd21 : z = 6'd48;
        'd22 : z = 6'd41;
        'd23 : z = 6'd34;
        'd24 : z = 6'd27;
        'd25 : z = 6'd20;
        'd26 : z = 6'd13;
        'd27 : z = 6'd6;
        'd28 : z = 6'd7;
        'd29 : z = 6'd14;
        'd30 : z = 6'd21;
        'd31 : z = 6'd28;
        'd32 : z = 6'd35;
        'd33 : z = 6'd42;
        'd34 : z = 6'd49;
        'd35 : z = 6'd56;
        'd36 : z = 6'd57;
        'd37 : z = 6'd50;
        'd38 : z = 6'd43;
        'd39 : z = 6'd36;
        'd40 : z = 6'd29;
        'd41 : z = 6'd22;
        'd42 : z = 6'd15;
        'd43 : z = 6'd23;
        'd44 : z = 6'd30;
        'd45 : z = 6'd37;
        'd46 : z = 6'd44;
        'd47 : z = 6'd51;
        'd48 : z = 6'd58;
        'd49 : z = 6'd59;
        'd50 : z = 6'd52;
        'd51 : z = 6'd45;
        'd52 : z = 6'd38;
        'd53 : z = 6'd31;
        'd54 : z = 6'd39;
        'd55 : z = 6'd46;
        'd56 : z = 6'd53;
        'd57 : z = 6'd60;
        'd58 : z = 6'd61;
        'd59 : z = 6'd54;
        'd60 : z = 6'd47;
        'd61 : z = 6'd55;
        'd62 : z = 6'd62;
        'd63 : z = 6'd63;
        endcase
    end

	// --------------------------------------------------------
	// [Outputs]
	assign	o_dataWrt		= (bDataWrite & (!isEOB) & i_nrst);
	assign	o_dataOut		= coef;
	wire    wFullBlockType  = (isDC & isFullBlock) | ((!isDC) & rIsFullBlock);
	assign	o_scale			= (isDC | wFullBlockType)	? {1'b0,{wFullBlockType,!wFullBlockType},3'b000}	// Scale = 8 if fullblockType=0, or 16 if 1 or i_scale.
														: scalereg;
	assign	o_isDC			= isDC;
	assign	o_fullBlockType	= wFullBlockType;
	assign  o_blockNum		= nextBlockCounter; // Can not use register, because we need value for DC, current first item.
	assign	o_index			= rIsFullBlock ? currIdx6Bit : z; // Index order depends on block type 
	assign	o_linearIndex	= currIdx6Bit;
endmodule
