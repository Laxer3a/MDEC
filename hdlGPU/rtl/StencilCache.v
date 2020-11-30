/*
	Stencil Cache :
	- Allow to read/write at the same cycle, as long as we do not access the same BRAM module which is :
		stencilWriteAdr[6] != stencilReadAdr[6] for FULL MODE.
		And also smaller constraint in pair mode : SAME PAIR, COMMON SELECT.
	- In case of conflict, WRITE takes the priority. READ data is not guaranteed.(I think ?)
*/

module StencilCache(
	input			clk,

	/*	Full mode has ONE constraint => stencilWriteAdr[6] must be different from stencilReadAdr[6] 
		Else use a single cycle for FULL read or FULL write. */
	input			fullMode,				// Full mode allow to read ALL 16 bit from a single adress.
	input	[15:0]	writeValue16,			// Input  value for full mode.
	input   [15:0]  writeMask16,
	output	[15:0]	readValue16,			// Output value for full mode.
	
	// -------------------------------
	//   Stencil Cache Write Back
	// -------------------------------
	input 			stencilWriteSig,		// Write 									(used also for FULL mode and PAIR MODE)
	input	[14:0]	stencilWriteAdr,		// Where to write							(used also for FULL mode and PAIR MODE)
	input	 [2:0]	stencilWritePair,		// Which pair of pixel (8 pair of 2 pixels)
	input	 [1:0]	stencilWriteSelect,		// Select the pixel to write in the pair.
	input	 [1:0]	stencilWriteValue,		// Value to write to the selected pixel.
	
	// -------------------------------
	//   Stencil Cache Read
	// -------------------------------
	input 			stencilReadSig,			// Read										(used also for FULL mode and PAIR MODE)
	input	[14:0]	stencilReadAdr,			// Where to read 	(block of 16 pixels)	(used also for FULL mode and PAIR MODE)
	input	 [2:0]	stencilReadPair,		// Which pair of pixel (8 pair of 2 pixels)
	input	 [1:0]	stencilReadSelect,		// Select the pixel to read in the pair.
	output	 [1:0]	stencilReadValue		// Value to write to the selected pixel.
);
	/***
		Because of movement on the horizontal and vertical axis during rasterization,
		we want to avoid READ/WRITE on the SAME RAM instance.
		On the X axis, it is garantee with PAIR.
		On the Y axis, we know that it correspond to a 64 entries jump inside the SAME RAM.
		So we will split the RAM into TWO BANKS (ODD/EVEN line).
		
		Adress is recomposed like this [14:7][5:0]
		Bit 6 is used to select BANK (A/B)
	 */
	wire [15:0] outValueA,outValueB;
	wire [13:0] swizzleWriteAdr = {stencilWriteAdr[14:7],stencilWriteAdr[5:0]};
	wire [13:0] swizzleReadAdr  = { stencilReadAdr[14:7], stencilReadAdr[5:0]};
	wire swizzleWBankA	 =   stencilWriteAdr[6]  & stencilWriteSig;
	wire swizzleWBankB	 = (!stencilWriteAdr[6]) & stencilWriteSig;
	wire swizzleRBankA	 =    stencilReadAdr[6]  & stencilReadSig;
	wire swizzleRBankB	 = ( !stencilReadAdr[6]) & stencilReadSig;
	
	wire [15:0] WriteV	 = fullMode ? writeValue16 : {8{stencilWriteValue}};
	
	wire [15:0] weA,weB,rdA,rdB;
	
	wire W0  = stencilWritePair == 3'd0 ;	wire R0  = stencilReadPair == 3'd0 ;
	wire W1  = stencilWritePair == 3'd1 ;	wire R1  = stencilReadPair == 3'd1 ;
	wire W2  = stencilWritePair == 3'd2 ;	wire R2  = stencilReadPair == 3'd2 ;
	wire W3  = stencilWritePair == 3'd3 ;	wire R3  = stencilReadPair == 3'd3 ;
	wire W4  = stencilWritePair == 3'd4 ;	wire R4  = stencilReadPair == 3'd4 ;
	wire W5  = stencilWritePair == 3'd5 ;	wire R5  = stencilReadPair == 3'd5 ;
	wire W6  = stencilWritePair == 3'd6 ;	wire R6  = stencilReadPair == 3'd6 ;
	wire W7  = stencilWritePair == 3'd7 ;	wire R7  = stencilReadPair == 3'd7 ;
	
	// Bank B => Adr[6]=0
	// Bank A => Adr[6]=1
	assign weA[ 0] = (swizzleWBankA & ((W0 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 0])));	assign weB[ 0] = (swizzleWBankB & ((W0 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 0])));
	assign weA[ 1] = (swizzleWBankA & ((W0 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 1])));	assign weB[ 1] = (swizzleWBankB & ((W0 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 1])));
	assign weA[ 2] = (swizzleWBankA & ((W1 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 2])));	assign weB[ 2] = (swizzleWBankB & ((W1 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 2])));
	assign weA[ 3] = (swizzleWBankA & ((W1 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 3])));	assign weB[ 3] = (swizzleWBankB & ((W1 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 3])));
	assign weA[ 4] = (swizzleWBankA & ((W2 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 4])));	assign weB[ 4] = (swizzleWBankB & ((W2 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 4])));
	assign weA[ 5] = (swizzleWBankA & ((W2 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 5])));	assign weB[ 5] = (swizzleWBankB & ((W2 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 5])));
	assign weA[ 6] = (swizzleWBankA & ((W3 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 6])));	assign weB[ 6] = (swizzleWBankB & ((W3 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 6])));
	assign weA[ 7] = (swizzleWBankA & ((W3 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 7])));	assign weB[ 7] = (swizzleWBankB & ((W3 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 7])));
	assign weA[ 8] = (swizzleWBankA & ((W4 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 8])));	assign weB[ 8] = (swizzleWBankB & ((W4 & stencilWriteSelect[0]) | (fullMode & writeMask16[ 8])));
	assign weA[ 9] = (swizzleWBankA & ((W4 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 9])));	assign weB[ 9] = (swizzleWBankB & ((W4 & stencilWriteSelect[1]) | (fullMode & writeMask16[ 9])));
	assign weA[10] = (swizzleWBankA & ((W5 & stencilWriteSelect[0]) | (fullMode & writeMask16[10])));	assign weB[10] = (swizzleWBankB & ((W5 & stencilWriteSelect[0]) | (fullMode & writeMask16[10])));
	assign weA[11] = (swizzleWBankA & ((W5 & stencilWriteSelect[1]) | (fullMode & writeMask16[11])));	assign weB[11] = (swizzleWBankB & ((W5 & stencilWriteSelect[1]) | (fullMode & writeMask16[11])));
	assign weA[12] = (swizzleWBankA & ((W6 & stencilWriteSelect[0]) | (fullMode & writeMask16[12])));	assign weB[12] = (swizzleWBankB & ((W6 & stencilWriteSelect[0]) | (fullMode & writeMask16[12])));
	assign weA[13] = (swizzleWBankA & ((W6 & stencilWriteSelect[1]) | (fullMode & writeMask16[13])));	assign weB[13] = (swizzleWBankB & ((W6 & stencilWriteSelect[1]) | (fullMode & writeMask16[13])));
	assign weA[14] = (swizzleWBankA & ((W7 & stencilWriteSelect[0]) | (fullMode & writeMask16[14])));	assign weB[14] = (swizzleWBankB & ((W7 & stencilWriteSelect[0]) | (fullMode & writeMask16[14])));
	assign weA[15] = (swizzleWBankA & ((W7 & stencilWriteSelect[1]) | (fullMode & writeMask16[15])));	assign weB[15] = (swizzleWBankB & ((W7 & stencilWriteSelect[1]) | (fullMode & writeMask16[15])));
	
	assign rdA[ 0] = (swizzleRBankA & ((R0 & stencilReadSelect[0] ) | fullMode));	assign rdB[ 0] = (swizzleRBankB & ((R0 & stencilReadSelect[0] ) | fullMode));
	assign rdA[ 1] = (swizzleRBankA & ((R0 & stencilReadSelect[1] ) | fullMode));	assign rdB[ 1] = (swizzleRBankB & ((R0 & stencilReadSelect[1] ) | fullMode));
	assign rdA[ 2] = (swizzleRBankA & ((R1 & stencilReadSelect[0] ) | fullMode));	assign rdB[ 2] = (swizzleRBankB & ((R1 & stencilReadSelect[0] ) | fullMode));
	assign rdA[ 3] = (swizzleRBankA & ((R1 & stencilReadSelect[1] ) | fullMode));	assign rdB[ 3] = (swizzleRBankB & ((R1 & stencilReadSelect[1] ) | fullMode));
	assign rdA[ 4] = (swizzleRBankA & ((R2 & stencilReadSelect[0] ) | fullMode));	assign rdB[ 4] = (swizzleRBankB & ((R2 & stencilReadSelect[0] ) | fullMode));
	assign rdA[ 5] = (swizzleRBankA & ((R2 & stencilReadSelect[1] ) | fullMode));	assign rdB[ 5] = (swizzleRBankB & ((R2 & stencilReadSelect[1] ) | fullMode));
	assign rdA[ 6] = (swizzleRBankA & ((R3 & stencilReadSelect[0] ) | fullMode));	assign rdB[ 6] = (swizzleRBankB & ((R3 & stencilReadSelect[0] ) | fullMode));
	assign rdA[ 7] = (swizzleRBankA & ((R3 & stencilReadSelect[1] ) | fullMode));	assign rdB[ 7] = (swizzleRBankB & ((R3 & stencilReadSelect[1] ) | fullMode));
	assign rdA[ 8] = (swizzleRBankA & ((R4 & stencilReadSelect[0] ) | fullMode));	assign rdB[ 8] = (swizzleRBankB & ((R4 & stencilReadSelect[0] ) | fullMode));
	assign rdA[ 9] = (swizzleRBankA & ((R4 & stencilReadSelect[1] ) | fullMode));	assign rdB[ 9] = (swizzleRBankB & ((R4 & stencilReadSelect[1] ) | fullMode));
	assign rdA[10] = (swizzleRBankA & ((R5 & stencilReadSelect[0] ) | fullMode));	assign rdB[10] = (swizzleRBankB & ((R5 & stencilReadSelect[0] ) | fullMode));
	assign rdA[11] = (swizzleRBankA & ((R5 & stencilReadSelect[1] ) | fullMode));	assign rdB[11] = (swizzleRBankB & ((R5 & stencilReadSelect[1] ) | fullMode));
	assign rdA[12] = (swizzleRBankA & ((R6 & stencilReadSelect[0] ) | fullMode));	assign rdB[12] = (swizzleRBankB & ((R6 & stencilReadSelect[0] ) | fullMode));
	assign rdA[13] = (swizzleRBankA & ((R6 & stencilReadSelect[1] ) | fullMode));	assign rdB[13] = (swizzleRBankB & ((R6 & stencilReadSelect[1] ) | fullMode));
	assign rdA[14] = (swizzleRBankA & ((R7 & stencilReadSelect[0] ) | fullMode));	assign rdB[14] = (swizzleRBankB & ((R7 & stencilReadSelect[0] ) | fullMode));
	assign rdA[15] = (swizzleRBankA & ((R7 & stencilReadSelect[1] ) | fullMode));	assign rdB[15] = (swizzleRBankB & ((R7 & stencilReadSelect[1] ) | fullMode));

	wire [15:0] csA = weA | rdA;
	wire [15:0] csB = weB | rdB;
	
	ram_sp_sr_sw RAMCache00A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 0]), .dataOut(outValueA[ 0]), .cs(csA[ 0]),.we(weA[ 0]));
	ram_sp_sr_sw RAMCache01A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 1]), .dataOut(outValueA[ 1]), .cs(csA[ 1]),.we(weA[ 1]));
	ram_sp_sr_sw RAMCache02A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 2]), .dataOut(outValueA[ 2]), .cs(csA[ 2]),.we(weA[ 2]));
	ram_sp_sr_sw RAMCache03A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 3]), .dataOut(outValueA[ 3]), .cs(csA[ 3]),.we(weA[ 3]));
	ram_sp_sr_sw RAMCache04A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 4]), .dataOut(outValueA[ 4]), .cs(csA[ 4]),.we(weA[ 4]));
	ram_sp_sr_sw RAMCache05A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 5]), .dataOut(outValueA[ 5]), .cs(csA[ 5]),.we(weA[ 5]));
	ram_sp_sr_sw RAMCache06A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 6]), .dataOut(outValueA[ 6]), .cs(csA[ 6]),.we(weA[ 6]));
	ram_sp_sr_sw RAMCache07A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 7]), .dataOut(outValueA[ 7]), .cs(csA[ 7]),.we(weA[ 7]));
	ram_sp_sr_sw RAMCache08A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 8]), .dataOut(outValueA[ 8]), .cs(csA[ 8]),.we(weA[ 8]));
	ram_sp_sr_sw RAMCache09A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 9]), .dataOut(outValueA[ 9]), .cs(csA[ 9]),.we(weA[ 9]));
	ram_sp_sr_sw RAMCache10A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[10]), .dataOut(outValueA[10]), .cs(csA[10]),.we(weA[10]));
	ram_sp_sr_sw RAMCache11A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[11]), .dataOut(outValueA[11]), .cs(csA[11]),.we(weA[11]));
	ram_sp_sr_sw RAMCache12A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[12]), .dataOut(outValueA[12]), .cs(csA[12]),.we(weA[12]));
	ram_sp_sr_sw RAMCache13A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[13]), .dataOut(outValueA[13]), .cs(csA[13]),.we(weA[13]));
	ram_sp_sr_sw RAMCache14A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[14]), .dataOut(outValueA[14]), .cs(csA[14]),.we(weA[14]));
	ram_sp_sr_sw RAMCache15A ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[15]), .dataOut(outValueA[15]), .cs(csA[15]),.we(weA[15]));
                                                                                  
	ram_sp_sr_sw RAMCache00B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 0]), .dataOut(outValueB[ 0]), .cs(csB[ 0]),.we(weB[ 0]));
	ram_sp_sr_sw RAMCache01B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 1]), .dataOut(outValueB[ 1]), .cs(csB[ 1]),.we(weB[ 1]));
	ram_sp_sr_sw RAMCache02B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 2]), .dataOut(outValueB[ 2]), .cs(csB[ 2]),.we(weB[ 2]));
	ram_sp_sr_sw RAMCache03B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 3]), .dataOut(outValueB[ 3]), .cs(csB[ 3]),.we(weB[ 3]));
	ram_sp_sr_sw RAMCache04B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 4]), .dataOut(outValueB[ 4]), .cs(csB[ 4]),.we(weB[ 4]));
	ram_sp_sr_sw RAMCache05B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 5]), .dataOut(outValueB[ 5]), .cs(csB[ 5]),.we(weB[ 5]));
	ram_sp_sr_sw RAMCache06B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 6]), .dataOut(outValueB[ 6]), .cs(csB[ 6]),.we(weB[ 6]));
	ram_sp_sr_sw RAMCache07B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 7]), .dataOut(outValueB[ 7]), .cs(csB[ 7]),.we(weB[ 7]));
	ram_sp_sr_sw RAMCache08B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 8]), .dataOut(outValueB[ 8]), .cs(csB[ 8]),.we(weB[ 8]));
	ram_sp_sr_sw RAMCache09B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[ 9]), .dataOut(outValueB[ 9]), .cs(csB[ 9]),.we(weB[ 9]));
	ram_sp_sr_sw RAMCache10B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[10]), .dataOut(outValueB[10]), .cs(csB[10]),.we(weB[10]));
	ram_sp_sr_sw RAMCache11B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[11]), .dataOut(outValueB[11]), .cs(csB[11]),.we(weB[11]));
	ram_sp_sr_sw RAMCache12B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[12]), .dataOut(outValueB[12]), .cs(csB[12]),.we(weB[12]));
	ram_sp_sr_sw RAMCache13B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[13]), .dataOut(outValueB[13]), .cs(csB[13]),.we(weB[13]));
	ram_sp_sr_sw RAMCache14B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[14]), .dataOut(outValueB[14]), .cs(csB[14]),.we(weB[14]));
	ram_sp_sr_sw RAMCache15B ( .clk(clk), .addressIn(swizzleWriteAdr),.addressOut(swizzleReadAdr), .dataIn(WriteV[15]), .dataOut(outValueB[15]), .cs(csB[15]),.we(weB[15]));
	
	//
	// Read Enabled Stuff...
	//
	reg   [2:0] PReadPair;
	reg         PBankA;
//	reg	[19:0]	debugOutAdr;
//	reg		[3:0]	debugOutPixel;
	always @ (posedge clk)
	begin
		PReadPair 			<= stencilReadPair;
		PBankA    			<= stencilReadAdr[6];
		
// VCD Debug purpose, never used outside.
//		debugOutAdr		= { stencilReadAdr , 5'b0 };
//		debugOutPixel	= { stencilReadPair, 1'b0 };
	end
	
	wire [15:0] outValue = PBankA ? outValueA : outValueB;
	assign readValue16 = outValue;
	reg [1:0] pairValueRead;
	always @(*)
	begin
		case (PReadPair)
		3'd0: pairValueRead = outValue[ 1: 0];
		3'd1: pairValueRead = outValue[ 3: 2];
		3'd2: pairValueRead = outValue[ 5: 4];
		3'd3: pairValueRead = outValue[ 7: 6];
		3'd4: pairValueRead = outValue[ 9: 8];
		3'd5: pairValueRead = outValue[11:10];
		3'd6: pairValueRead = outValue[13:12];
		3'd7: pairValueRead = outValue[15:14];
		endcase
	end
	assign stencilReadValue = pairValueRead;
endmodule
