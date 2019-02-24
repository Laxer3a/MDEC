module IDCT (
	// System
	input			clk,
	input			i_nrst,

	// Coefficient input
	input			i_write,
	input	[5:0]	i_writeIdx,
	input	[2:0]	i_blockNum,
	input	[19:0]	i_coefValue,
	input			i_matrixComplete,
	output			o_canLoadMatrix,

	// Loading of COS Table (Linear, no zigzag)
	input			i_cosWrite,
	input	[ 4:0]	i_cosIndex,
	input	[25:0]	i_cosVal,
	
	// Output in order value out
	output	[22:0]	o_value,
	output			o_writeValue,
	output			o_busyIDCT,
	output	 [5:0]	o_writeIndex
);
	// Allow to load matrix when IDCT is not busy OR that we are in the second pass.
	// No need to worry, about internal 64 bit flag reset on pass 0->1, stream input will take >= 1 cycle to send the next data in any case.
	assign o_canLoadMatrix = (!idctBusy | (pass == 1));
	
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
	wire [4:0] cosSubW = i_cosIndex[5:1];
	
	always @ (posedge clk)
	begin
		// Write
		if (i_cosWrite)
		begin
			COSTBLA[cosSubW] <= i_cosVal[12: 0];
			COSTBLB[cosSubW] <= i_cosVal[25:13];
		end
		// Read
		cosAdr_reg <= addrCos;
	end
	// Continuous assignment implies read returns NEW data.
	// This is the natural behavior of the TriMatrix memory
	// blocks in Single Port mode.
	assign cosA = COSTBLA[cosAdr_reg];
	assign cosB = COSTBLB[cosAdr_reg];

	//----------------------------------------------
	//  Read Storage Pass 0 and 1
	//  [Common Address]
	//----------------------------------------------
	// Public READ Address for COEF tables pass 0 AND 1 !
	wire		 [5:0]	readAdrCoefTable;
	
	//----------------------------------------------
	//  Read/Write Storage Pass 0.
	//  Including read trick for source.
	//----------------------------------------------
	// Public READ  : Value   for COEF tables pass 0
	wire		[19:0]	readCoefTableValue;
	// Public READ  : Address 'readAdrCoefTable'
	//
	// Public WRITE : i_writeIdx, i_write, i_coefValue for input
	
	//----- INTERNAL STUFF -------------------------
	// Can NOT use isLoadedBits[63..0] BECAUSE I NEED A CLEAR INSTANT ON ALL BITS.
	// Thus doing adressing, read/write myself.
	reg 		[63:0] 	isLoadedBits;
	reg					isLoaded;
	reg					isLoadedTmp;
	
	reg signed	[19:0]	coefTable[63:0];
	reg			 [5:0]	coefTableAdr_reg;
	
	// [Direct READ 0 Cycle for Bit 0..63 with demultiplexer]
	always @ (*)
	begin
		case (readAdrCoefTable)
		'd0  : isLoadedTmp = isLoadedBits[ 0];
		'd1  : isLoadedTmp = isLoadedBits[ 1];
		'd2  : isLoadedTmp = isLoadedBits[ 2];
		'd3  : isLoadedTmp = isLoadedBits[ 3];
		'd4  : isLoadedTmp = isLoadedBits[ 4];
		'd5  : isLoadedTmp = isLoadedBits[ 5];
		'd6  : isLoadedTmp = isLoadedBits[ 6];
		'd7  : isLoadedTmp = isLoadedBits[ 7];
		'd8  : isLoadedTmp = isLoadedBits[ 8];
		'd9  : isLoadedTmp = isLoadedBits[ 9];
		'd10 : isLoadedTmp = isLoadedBits[10];
		'd11 : isLoadedTmp = isLoadedBits[11];
		'd12 : isLoadedTmp = isLoadedBits[12];
		'd13 : isLoadedTmp = isLoadedBits[13];
		'd14 : isLoadedTmp = isLoadedBits[14];
		'd15 : isLoadedTmp = isLoadedBits[15];
		'd16 : isLoadedTmp = isLoadedBits[16];
		'd17 : isLoadedTmp = isLoadedBits[17];
		'd18 : isLoadedTmp = isLoadedBits[18];
		'd19 : isLoadedTmp = isLoadedBits[19];
		'd20 : isLoadedTmp = isLoadedBits[20];
		'd21 : isLoadedTmp = isLoadedBits[21];
		'd22 : isLoadedTmp = isLoadedBits[22];
		'd23 : isLoadedTmp = isLoadedBits[23];
		'd24 : isLoadedTmp = isLoadedBits[24];
		'd25 : isLoadedTmp = isLoadedBits[25];
		'd26 : isLoadedTmp = isLoadedBits[26];
		'd27 : isLoadedTmp = isLoadedBits[27];
		'd28 : isLoadedTmp = isLoadedBits[28];
		'd29 : isLoadedTmp = isLoadedBits[29];
		'd30 : isLoadedTmp = isLoadedBits[30];
		'd31 : isLoadedTmp = isLoadedBits[31];
		'd32 : isLoadedTmp = isLoadedBits[32];
		'd33 : isLoadedTmp = isLoadedBits[33];
		'd34 : isLoadedTmp = isLoadedBits[34];
		'd35 : isLoadedTmp = isLoadedBits[35];
		'd36 : isLoadedTmp = isLoadedBits[36];
		'd37 : isLoadedTmp = isLoadedBits[37];
		'd38 : isLoadedTmp = isLoadedBits[38];
		'd39 : isLoadedTmp = isLoadedBits[39];
		'd40 : isLoadedTmp = isLoadedBits[40];
		'd41 : isLoadedTmp = isLoadedBits[41];
		'd42 : isLoadedTmp = isLoadedBits[42];
		'd43 : isLoadedTmp = isLoadedBits[43];
		'd44 : isLoadedTmp = isLoadedBits[44];
		'd45 : isLoadedTmp = isLoadedBits[45];
		'd46 : isLoadedTmp = isLoadedBits[46];
		'd47 : isLoadedTmp = isLoadedBits[47];
		'd48 : isLoadedTmp = isLoadedBits[48];
		'd49 : isLoadedTmp = isLoadedBits[49];
		'd50 : isLoadedTmp = isLoadedBits[50];
		'd51 : isLoadedTmp = isLoadedBits[51];
		'd52 : isLoadedTmp = isLoadedBits[52];
		'd53 : isLoadedTmp = isLoadedBits[53];
		'd54 : isLoadedTmp = isLoadedBits[54];
		'd55 : isLoadedTmp = isLoadedBits[55];
		'd56 : isLoadedTmp = isLoadedBits[56];
		'd57 : isLoadedTmp = isLoadedBits[57];
		'd58 : isLoadedTmp = isLoadedBits[58];
		'd59 : isLoadedTmp = isLoadedBits[59];
		'd60 : isLoadedTmp = isLoadedBits[60];
		'd61 : isLoadedTmp = isLoadedBits[61];
		'd62 : isLoadedTmp = isLoadedBits[62];
		default : isLoadedTmp = isLoadedBits[63];
		endcase
	end
	
	always @ (posedge clk)
	begin
		if (i_nrst==0 || (pass=1 && pPass=0))	// Reset the loaded flag of coefficients, allow next matrix loading when we enter the second pass IDCT.
		begin
			isLoadedBits = 64'd0;
		end
		else
		begin
			if (i_write)
			begin
				coefTable[i_writeIdx] <= i_coefValue;
				
				case (i_writeIdx)
				'd0  : isLoadedBits[ 0] = 1'b1;
				'd1  : isLoadedBits[ 1] = 1'b1;
				'd2  : isLoadedBits[ 2] = 1'b1;
				'd3  : isLoadedBits[ 3] = 1'b1;
				'd4  : isLoadedBits[ 4] = 1'b1;
				'd5  : isLoadedBits[ 5] = 1'b1;
				'd6  : isLoadedBits[ 6] = 1'b1;
				'd7  : isLoadedBits[ 7] = 1'b1;
				'd8  : isLoadedBits[ 8] = 1'b1;
				'd9  : isLoadedBits[ 9] = 1'b1;
				'd10 : isLoadedBits[10] = 1'b1;
				'd11 : isLoadedBits[11] = 1'b1;
				'd12 : isLoadedBits[12] = 1'b1;
				'd13 : isLoadedBits[13] = 1'b1;
				'd14 : isLoadedBits[14] = 1'b1;
				'd15 : isLoadedBits[15] = 1'b1;
				'd16 : isLoadedBits[16] = 1'b1;
				'd17 : isLoadedBits[17] = 1'b1;
				'd18 : isLoadedBits[18] = 1'b1;
				'd19 : isLoadedBits[19] = 1'b1;
				'd20 : isLoadedBits[20] = 1'b1;
				'd21 : isLoadedBits[21] = 1'b1;
				'd22 : isLoadedBits[22] = 1'b1;
				'd23 : isLoadedBits[23] = 1'b1;
				'd24 : isLoadedBits[24] = 1'b1;
				'd25 : isLoadedBits[25] = 1'b1;
				'd26 : isLoadedBits[26] = 1'b1;
				'd27 : isLoadedBits[27] = 1'b1;
				'd28 : isLoadedBits[28] = 1'b1;
				'd29 : isLoadedBits[29] = 1'b1;
				'd30 : isLoadedBits[30] = 1'b1;
				'd31 : isLoadedBits[31] = 1'b1;
				'd32 : isLoadedBits[32] = 1'b1;
				'd33 : isLoadedBits[33] = 1'b1;
				'd34 : isLoadedBits[34] = 1'b1;
				'd35 : isLoadedBits[35] = 1'b1;
				'd36 : isLoadedBits[36] = 1'b1;
				'd37 : isLoadedBits[37] = 1'b1;
				'd38 : isLoadedBits[38] = 1'b1;
				'd39 : isLoadedBits[39] = 1'b1;
				'd40 : isLoadedBits[40] = 1'b1;
				'd41 : isLoadedBits[41] = 1'b1;
				'd42 : isLoadedBits[42] = 1'b1;
				'd43 : isLoadedBits[43] = 1'b1;
				'd44 : isLoadedBits[44] = 1'b1;
				'd45 : isLoadedBits[45] = 1'b1;
				'd46 : isLoadedBits[46] = 1'b1;
				'd47 : isLoadedBits[47] = 1'b1;
				'd48 : isLoadedBits[48] = 1'b1;
				'd49 : isLoadedBits[49] = 1'b1;
				'd50 : isLoadedBits[50] = 1'b1;
				'd51 : isLoadedBits[51] = 1'b1;
				'd52 : isLoadedBits[52] = 1'b1;
				'd53 : isLoadedBits[53] = 1'b1;
				'd54 : isLoadedBits[54] = 1'b1;
				'd55 : isLoadedBits[55] = 1'b1;
				'd56 : isLoadedBits[56] = 1'b1;
				'd57 : isLoadedBits[57] = 1'b1;
				'd58 : isLoadedBits[58] = 1'b1;
				'd59 : isLoadedBits[59] = 1'b1;
				'd60 : isLoadedBits[60] = 1'b1;
				'd61 : isLoadedBits[61] = 1'b1;
				'd62 : isLoadedBits[62] = 1'b1;
				default : isLoadedBits[63] = 1'b1;
				endcase
			end
		end
		coefTableAdr_reg <= readAdrCoefTable;
		isLoaded         <= isLoadedTmp;
	end
	// [Internally, not loaded items return 0]
	assign readCoefTableValue = isLoaded ? coefTable[coefTableAdr_reg] : 20'd0;
	//----- END INTERNAL STUFF -----
	
	
	//----------------------------------------------
	//  Read Storage Pass 1.
	//  -> Can write TWO values at different sub tables.
	//  -> Unified read for a single value.
	//----------------------------------------------
	// Public Shared (declared already)
	// wire		 [5:0]	readAdrCoefTable;
	//
	// Public READ Value   for COEF tables pass 0
	wire		[22:0]	readCoefTable2Value;
	//
	// Public WRITE ENABLE
	wire				writeCoefTable2;
	// Public WRITE ADDRESS
	wire		[ 4:0]	writeCoefTable2Index;
	// Public WRITE VALUE
	wire		[22:0]	writeValueA;
	wire		[22:0]	writeValueB;
	
	reg signed	[22:0]	coefTable2A[31:0];
	reg signed	[22:0]	coefTable2B[31:0];
	reg			 [5:0]	coefTable2Adr_reg;
	
	
	always @ (posedge clk)
	begin
		if (writeCoefTable2)
		begin
			coefTable2A[writeCoefTable2Index] <= writeValueA;
			coefTable2B[writeCoefTable2Index] <= writeValueB;
		end
		coefTable2Adr_reg<= readAdrCoefTable;
	end
	wire   [4:0] subTblAdr     = { coefTable2Adr_reg[5:4],coefTable2Adr_reg[2:0] };
	assign readCoefTable2Value = coefTable2Adr_reg[3] ? coefTable2B[subTblAdr] : coefTable2A[subTblAdr];
	
	//----------------------------------------------
	//  GENERAL COUNTER AND STATE MACHINE FOR IDCT
	//----------------------------------------------
	
	// BIT [Pass 0/1][Y:0..7][X:0..3][K:0..7]
	reg	 [8:0]	idctCounter;
	reg			idctBusy;
	reg			rblockNum;
	
	// Helper for code maintenance.
	wire 		pass		= idctCounter  [8];	// 1 BIT
	wire [2:0]	YCnt		= idctCounter[7:5];	// 3 BIT
	wire [1:0]	XCnt		= idctCounter[4:3];	// 2 BIT
	wire [2:0]	KCnt		= idctCounter[2:0];	// 3 BIT
	wire        isLast      = (KCnt == 3'b111);

	reg			pLast,ppLast,pPass,ppPass;
	always @ (posedge clk) begin pLast  <= isLast; pPass  <=  pass; end
	always @ (posedge clk) begin ppLast <=  pLast; ppPass <= pPass; end

	assign addrCos	= {KCnt,XCnt};

	//-------------------------------------------------------
	always @ (posedge clk)
	begin
		if (i_nrst==0)
		begin
			idctCounter = 9'd0;
			idctBusy    = 0;
		end else begin
			if (idctBusy)
			begin
				if (idctCounter == 511)
				begin
					idctCounter = 9'd0;
					idctBusy	= 0; 	// Stop IDCT until new block loading complete.
				end
				else
					idctCounter = idctCounter + 1'b1/*(1'b1 Avoid size warning)*/;
			end else begin
				// We skip the matrix complete flag if we are busy computing a IDCT.
				// Normally should never happen : Our busy flag will maintain that data is not pushed while computing.
				if (i_matrixComplete)
				begin
					idctBusy = 1;
				end
			end
		end
	end
	//-------------------------------------------------------

	// For BOTH Table 0 and Table 1 (Cycle 0)
	assign readAdrCoefTable = pass ? {YCnt,KCnt} /* Pass1 */ : {KCnt,YCnt} /* Pass0 */;
	
	// (Cycle 1 : Result Come back)
	// Sign extend 20 bit to 23 bit for pass 0 values.
	// Read 23 bit directly         for pass 1 values.
	wire signed [22:0] coef0 = pPass ? readCoefTable2Value : { {3{readCoefTableValue[19]}}, readCoefTableValue[19:0] };
	
	wire signed [35:0] mul0  = (coef0 * cosA); // 23x16 bit = 39 bit.
	wire signed [35:0] mul1  = (coef0 * cosB); 

	// Sign extend the result of multiplication.
	wire signed [38:0] ext_mul0 = { {3{mul0[35]}}, mul0[35:0] };
	wire signed [38:0] ext_mul1 = { {3{mul1[35]}}, mul1[35:0] };
	
	// Accumulators
	reg signed  [38:0] acc0;
	reg signed  [38:0] acc1;

	// 1 piped signal.
	reg          [2:0] pYCnt,pKCnt, ppYCnt;
	reg			 [1:0] pXCnt,ppXCnt;
	always @ (posedge clk)
	begin
		// Pipeline also the X,Y address to match accumulator write timing.
		pXCnt <= XCnt;
		pYCnt <= YCnt;
		pKCnt <= KCnt;
	end
	
	always @ (posedge clk)
	begin
		if (pKCnt != 0)
		begin
			acc0 <= acc0 + ext_mul0;
			acc1 <= acc1 + ext_mul1;
		end else begin
			acc0 <= ext_mul0;
			acc1 <= ext_mul1;
		end
		
		ppXCnt <= pXCnt;
		ppYCnt <= pYCnt;
	end

	// (Cycle 2)
	// Divide by 65536.0 fixed point value.
	wire signed [22:0] v0 = acc0[35:13];
	wire signed [22:0] v1 = acc1[35:13];

	// Write Accumulator result when At beginning of next line. For last line, wait for beginning of first line of next pass.
	wire   writeOut             = ppLast && ppPass;		// When arrived to last element done in pass 1
	assign writeCoefTable2		= ppLast && (!ppPass);	// When arrived to last element done in pass 0
	assign writeCoefTable2Index = {ppXCnt,ppYCnt};
	assign writeValueA			= v0;
	assign writeValueB			= v1;

	// ----------------------------------------------------------------------------------------------------------------------------------
	// For external output, need to shift values (like a shift register) for both, and have o_writeValue maintained for multiple cycles.
	// Cycle n = write v0, n+1 = write v1
	// ----------------------------------------------------------------------------------------------------------------------------------
	reg signed [22:0] pv1;
	reg pWriteOut;
	reg [1:0] pppXCnt;
	reg [2:0] pppYCnt;
	always @ (posedge clk)
	begin
		pv1       <= v1;
		pWriteOut <= writeOut;
		pppXCnt   <= ppXCnt;
		pppYCnt   <= ppYCnt;
	end
	
	assign o_value				= pWriteOut ? pv1     : v0;
	wire   [1:0] outX			= pWriteOut ? pppXCnt : ppXCnt;
	wire   [2:0] outY			= pWriteOut ? pppYCnt : ppYCnt; // Probably could work with pppYCnt directly, but this multiplexer is cheap and does the proper job.
	assign o_writeValue			= (!writeOut && pWriteOut) || writeOut;
	assign o_busyIDCT			= idctBusy;
	assign o_writeIndex			= {outY,{outX,pWriteOut}}; // Generate correct X odd and even values when pushing out values.
	// ----------------------------------------------------------------------------------------------------------------------------------
endmodule
