`include "MDEC_Cte.sv"

module IDCT (
	// System
	input				clk,
	input				i_nrst,

	// Coefficient input
	input				i_write,
	input	[5:0]		i_writeIdx,
	input	MDEC_BLCK	i_blockNum,
	input	[11:0]		i_coefValue,
	input				i_matrixComplete,	// Warning this bit CAN BECOME 1, independantly FROM i_write (See streamInput specs) !
	output				o_canLoadMatrix,	// ALLOW LOADING OF MATRIX ELEMENT WHEN NOT BUSY OR PASS 1 & EXCEPT LAST ELEMENT OF MATRIX
//	output				o_pass1,
	

	// Loading of COS Table (Linear, no zigzag)
	input				i_cosWrite,
	input	[ 4:0]		i_cosIndex,
	input	[25:0]		i_cosVal,
	
	// Output in order value out
	input				i_pauseIDCT_YBlock,
	output	 [7:0]		o_value,
	output				o_writeValue,
	output 	 MDEC_BLCK	o_blockNum,
	output				o_busyIDCT,
	output	 [5:0]		o_writeIndex
);

//----- IGNORE FOR NOW -------------
	// Allow to load matrix when IDCT is not busy OR that we are in the second pass.
	// No need to worry, about internal 64 bit flag reset on pass 0->1, stream input will take >= 1 cycle to send the next data in any case.
	// No need to worry about stream forced to wait in the middle...
	assign o_canLoadMatrix	= (!idctBusy /*| ((pass == 1)  & ((!i_matrixComplete) & !rMatrixComplete))*/);
//	assign o_pass1			= pass;
// ---------------------------------

	//----------------------------------------------
	//  COS TABLE ACCESS AND SETUP
	//  -> DUAL TABLE for ODD and EVEN 'X' lines.
	//  -> Seen as SINGLE table when LOADING.
	//----------------------------------------------
	
	// Public READ Address for COS tables.
	wire [ 4:0]	addrCos;
	// Public RETURN Values for cos tables.
	wire signed [12:0] cosA;
	wire signed [12:0] cosB;
	
	// --- Internal ---
	
	// LUT Table
	reg signed [12:0] COSTBLA[31:0];
	reg signed [12:0] COSTBLB[31:0];

	// Internal Address buffering
	reg  [4:0] cosAdr_reg;
	
	always @ (posedge clk)
	begin
		// Write
		if (i_cosWrite)
		begin
			COSTBLA[i_cosIndex] = i_cosVal[12: 0];
			COSTBLB[i_cosIndex] = i_cosVal[25:13];
		end
		// Read
		cosAdr_reg = addrCos;
	end
	// Continuous assignment implies read returns NEW data.
	// This is the natural behavior of the TriMatrix memory
	// blocks in Single Port mode.
	assign cosA = COSTBLA[cosAdr_reg];
	assign cosB = COSTBLB[cosAdr_reg];

	wire [5:0]  pass0ReadAdr = {KCnt,YCnt};
	//----------------------------------------------
	//  Read/Write Storage Pass 0.
	//  Including read trick for source.
	//----------------------------------------------
	// Public READ  : Value   for COEF tables pass 0
	wire		[11:0]	readCoefTableValue;
	// Public READ  : Address 'pass0ReadAdr'
	//
	// Public WRITE : i_writeIdx, i_write, i_coefValue for input
	
	//----- INTERNAL STUFF -------------------------
	// Can NOT use isLoadedBits[63..0] BECAUSE I NEED A CLEAR INSTANT ON ALL BITS.
	// Thus doing adressing, read/write myself.
	reg 		[63:0] 	isLoadedBits;
	reg					isLoaded;
	// [Direct READ 0 Cycle for Bit 0..63 with demultiplexer]
	wire				isLoadedTmp = isLoadedBits[pass0ReadAdr];
	
	reg signed	[11:0]	coefTable[63:0];
	reg			 [5:0]	coefTableAdr_reg;
	
	
	MDEC_BLCK			blockID;
	wire passTransition = (pass==1 && pPass==0);
	always @ (posedge clk)
	begin
		if (i_nrst==0 || passTransition)	// Reset the loaded flag of coefficients, allow next matrix loading when we enter the second pass IDCT.
		begin
			isLoadedBits	= 64'd0;
		end
		else
		begin
			if (i_write)
			begin
				coefTable[i_writeIdx] <= i_coefValue;
				
				// Load block ID on DC loading.
				if (i_writeIdx == 6'd0) begin
					blockID = i_blockNum;
				end
				
				isLoadedBits[i_writeIdx] = 1'b1;
			end
		end
		coefTableAdr_reg = pass0ReadAdr;
		isLoaded         = isLoadedTmp;
	end
	// [Internally, not loaded items return 0]
	assign readCoefTableValue = isLoaded ? coefTable[coefTableAdr_reg] : 12'd0;
	//----- END INTERNAL STUFF -----
	
	
	//----------------------------------------------
	//  Read Storage Pass 1.
	//  -> Can write TWO values at different sub tables.
	//  -> Unified read for a single value.
	//----------------------------------------------
	// Public READ ADR
	wire [4:0]  pass1ReadAdr = {YCnt[2:1],KCnt};	
	//
	// Public READ Value   for COEF tables pass 0
	wire		[12:0]	readCoefTable2Value;
	//
	// Public WRITE ENABLE
	wire				writeCoefTable2;
	// Public WRITE ADDRESS
	wire		[ 4:0]	writeCoefTable2Index;
	// Public WRITE VALUE
	wire		[12:0]	writeValueA;
	wire		[12:0]	writeValueB;
	
	reg signed	[12:0]	coefTable2A[31:0];
	reg signed	[12:0]	coefTable2B[31:0];
	reg			 [4:0]	coefTable2Adr_reg;
	reg					tblSelect;
	
	always @ (posedge clk)
	begin
		if (writeCoefTable2)
		begin
			coefTable2A[writeCoefTable2Index] = writeValueA;
			coefTable2B[writeCoefTable2Index] = writeValueB;
		end
		coefTable2Adr_reg = pass1ReadAdr;
		tblSelect		  = YCnt[0];
	end
	wire signed [12:0] ValueA  = coefTable2A[coefTable2Adr_reg];
	wire signed [12:0] ValueB  = coefTable2B[coefTable2Adr_reg];
	assign readCoefTable2Value = tblSelect ? ValueB : ValueA;
	
	//----------------------------------------------
	//  GENERAL COUNTER AND STATE MACHINE FOR IDCT
	//----------------------------------------------
	
	// BIT [Pass 0/1][Y:0..7][X:0..3][K:0..7]
	reg	 [8:0]	idctCounter;
	reg			idctBusy;
	
	// Helper for code maintenance.
	wire 		pass		= idctCounter  [8];	// 1 BIT
	wire [2:0]	YCnt		= idctCounter[7:5];	// 3 BIT
	wire [1:0]	XCnt		= idctCounter[4:3];	// 2 BIT
	wire [2:0]	KCnt		= idctCounter[2:0];	// 3 BIT
	wire        isLast      = (KCnt == 3'b111);
	wire		freezeIDCT	= i_pauseIDCT_YBlock & pass;	// Freeze only during pass 2 when outputting Y Blocks.
	reg			pFreeze,ppFreeze;	
	reg			pLast,ppLast,pPass,ppPass;
	always @ (posedge clk) begin pLast  <= isLast; pPass  <=  pass; end
	always @ (posedge clk) begin ppLast <=  pLast; ppPass <= pPass; end

	assign addrCos	= {KCnt,XCnt};

	//-------------------------------------------------------
	reg			rMatrixComplete;
	MDEC_BLCK 	idctBlockNum;
	
	always @ (posedge clk)
	begin
		if (i_nrst==0)
		begin
			idctCounter 	= 9'd0;
			idctBusy    	= 0;
			pFreeze			= 0;
			rMatrixComplete	= 0;
		end else begin
			pFreeze			= freezeIDCT;
			
			if (!pPass & pass) begin 
				// Copy Block ID when entering pass1
				// Will allow to optimize later to load new matrix when entering pass1.
				// By reading blockID at this clock, we know we always take
				// the OLD value of the current matrix, even if a NEW matrix
				// is written right now at this same cycle.
				idctBlockNum	= blockID;
			end
			
			if (idctBusy)
			begin
				if (i_matrixComplete) begin
					rMatrixComplete = 1'b1;
				end
				
				if (idctCounter == 511)
				begin
					idctCounter = 9'd0;
					idctBusy	= 0; 	// Stop IDCT until new block loading complete.
				end
				else
				begin
					idctCounter = idctCounter + { 8'd0 , !freezeIDCT }; // Add 1 only when NOT freezed.
				end
			end else begin
				// We skip the matrix complete flag if we are busy computing a IDCT.
				// Normally should never happen : Our busy flag will maintain that data is not pushed while computing.
				if (rMatrixComplete | i_matrixComplete)
				begin
					idctBusy		= 1;
					rMatrixComplete	= 0;
				end
			end
		end
	end
	
	
	//-------------------------------------------------------
	// CYCLE 0 : READ COS / READ COEF Table Latency
	//-------------------------------------------------------
	
	//-------------------------------------------------------
	// CYCLE 1 : USE COS Values, 
	//-------------------------------------------------------
	// (Cycle 1 : Result Come back)
	// Sign extend 20 bit to 23 bit for pass 0 values.
	// Read 23 bit directly         for pass 1 values.
	wire signed [12:0] coefV   = readCoefTable2Value;
	wire signed [11:0] coef12A = pass ? cosA[12:1] : readCoefTableValue;
	wire signed [11:0] coef12B = pass ? cosB[12:1] : readCoefTableValue;
	wire signed [12:0] coef13A = pass ? coefV      : cosA;
	wire signed [12:0] coef13B = pass ? coefV      : cosB;
	
	
	wire signed [24:0] mul0  = (coef12A * coef13A); // 12x13 bit = 25 bit.
	wire signed [24:0] mul1  = (coef12B * coef13B); 

	// TO OPTIMIZE : Accumulator should not need 20 bit but 18 (actually 17 ?)
	//        We do NOT use the accumulator result for the top bits anyway.
	wire signed [19:0] ext_mul0 = {{3{mul0[23]}},mul0[23:7]};
	wire signed [19:0] ext_mul1 = {{3{mul1[23]}},mul1[23:7]};
	
	// Accumulators
	reg signed  [19:0] acc0;
	reg signed  [19:0] acc1;

	// 1 piped signal.
	reg          [2:0] pYCnt,pKCnt,ppYCnt,pppYCnt;
	reg			 [1:0] pXCnt,ppXCnt,pppXCnt;
	always @ (posedge clk)
	begin
		pppXCnt	<= ppXCnt;
		pppYCnt	<= ppYCnt;
		
		ppXCnt	<= pXCnt;
		ppYCnt	<= pYCnt;
		
		// Pipeline also the X,Y address to match accumulator write timing.
		pXCnt	<= XCnt;
		pYCnt	<= YCnt;
		pKCnt	<= KCnt;
	end
	
	//-------------------------------------------------------
	// CYCLE 2 : Accumulator latency
	//-------------------------------------------------------
	always @ (posedge clk)
	begin
		if (!pFreeze) begin
			if (pKCnt != 0)
			begin
				acc0 = acc0 + ext_mul0;
				acc1 = acc1 + ext_mul1;
			end else begin
				acc0 = ext_mul0;
				acc1 = ext_mul1;
			end
		/* Same without else
		else
			// Keep our accumulator out of work when freezing.
			acc0 <= acc0;
			acc1 <= acc1;
		*/
		end
		ppFreeze = pFreeze;
	end

	// Remove 4 bit at output of pass1 (and pass2)
	wire signed [12:0] v0 = acc0[16:4];
	wire signed [12:0] v1 = acc1[16:4];

	// Write Accumulator result when At beginning of next line. For last line, wait for beginning of first line of next pass.
	wire   writeOut             = ppLast && ppPass && (!ppFreeze);	// When arrived to last element done in pass 1
	assign writeCoefTable2		= ppLast && (!ppPass);				// When arrived to last element done in pass 0
	assign writeCoefTable2Index = {ppXCnt,ppYCnt};
	
	// Write back values for Pass1 to buffer.
	assign writeValueA			= v0;
	assign writeValueB			= v1;
	
	// ----------------------------------------------------------------------------------------------------------------------------------
	// For external output, need to shift values (like a shift register) for both, and have o_writeValue maintained for multiple cycles.
	// Cycle n = write v0, n+1 = write v1
	// ----------------------------------------------------------------------------------------------------------------------------------

	//
	// Pass 2 Value requires again to remove 2 more bit (need to remove 6 bits from accumulator, and we removed only 4 at that point : v0/v1)
	//
	reg signed [9:0] pv1;
	reg pWriteOut;
	always @ (posedge clk)
	begin
		pv1       = v1[11:2];										// Remove the 2 bits for V1
		pWriteOut = writeOut;
	end
	
	wire  [9:0] vBeforeSDiv2   = pWriteOut ? pv1     : v0[11:2];	// Remove the 2 bits for V0.
	// ---------------------------------------
	// Signed division by 2.
	// ---------------------------------------
	wire  [9:0] div2step1      = vBeforeSDiv2 + { 9'b0,vBeforeSDiv2[9] };
	wire  [8:0] div2step2      = div2step1[9:1]; // result div 2 signed. (-256..+255)
	// ---------------------------------------
	// Saturated Arithmetic [9:0]-256..+255 -> [7:0][-128..+127]
	// ---------------------------------------
	wire        tooPos      = !div2step2[8]  &  div2step2[7];		// 01 => 1 = Too big  , 0 = OK
	wire		tooNeg		=  div2step2[8]  & !div2step2[7];		// 10 => 1 = Too small, 0 = OK
	wire		notTooNeg	= !tooNeg;
	wire  [7:0] overflow8   = {tooNeg,{7{tooPos}}};
	wire  [7:0] rst8        = {!tooPos,{7{notTooNeg}}};
	wire  [7:0] clamped8Bit = (div2step2[7:0] & rst8) | overflow8;
	
	// Signed saturated arithmetic result.
	assign o_value = clamped8Bit;
	
	wire   [1:0] outX			= pWriteOut ? pppXCnt : ppXCnt;
	wire   [2:0] outY			= pWriteOut ? pppYCnt : ppYCnt; // Probably could work with pppYCnt directly, but this multiplexer is cheap and does the proper job.
	assign o_writeValue			= (!writeOut && pWriteOut) || writeOut;
	assign o_busyIDCT			= idctBusy;
	assign o_writeIndex			= {outY,{outX,pWriteOut}}; // Generate correct X odd and even values when pushing out values.
	assign o_blockNum			= idctBlockNum;
	// ----------------------------------------------------------------------------------------------------------------------------------
endmodule
