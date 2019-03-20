module GTEEngine (
	input         i_clk,
	input         i_nRst,

	//   GTE PORT
	input  [5:0]  i_regID,
	input         i_WritReg,
	input         i_ReadReg,
	input  [31:0] i_dataIn,
	output [31:0] i_dataOut,

	input  [24:0] instruction,
	input         execute,
	output        o_executing
);

/*
	TODO : MicroCode index for SF override. -> CHECK also emu source/doc.
	TODO : Div unit plugged.
	TODO : CPU Side READ.
 */

// -----------------------------------------------------------
//   Constants for feel good code.
// -----------------------------------------------------------
`include "GTEConsts.vh"

// ----------------------------------------------------------------------------------------------
//   Microcoded Instructions
// ----------------------------------------------------------------------------------------------
// Instruction Mnemonic
reg       instr_sf,instr_lm;		
reg	[5:0] opcode = Instruction[ 5: 0];
// Only in command MVMVA
reg [1:0] instr_cv,instr_vec,instr_mx;
reg       executing;

wire [63:0] microCode;
reg  [ 8:0] PC;

wire sf              = microCode[?] & instr_sf;
wire lm       		 = microCode[2] & instr_lm;											// MICROCODE:[Override LM Bit to ZERO (0:override,1:Normal)]
wire resetStatus	 = microCode[0];													// MICROCODE:[First Microcode, reset status flags].
wire lastInstruction = microCode[1];													// MICROCODE:[Last  Microcode]

parameter	
	INSTR_RTPS	=5'h01,	INSTR_NCLIP	=5'h06,	INSTR_OP	=5'h0C,	INSTR_DPCS	=5'h10,	INSTR_INTPL	=5'h11,	INSTR_MVMVA	=5'h12,
	INSTR_NCDS	=5'h13,	INSTR_CDP	=5'h14,	INSTR_NCDT	=5'h16,	INSTR_NCCS	=5'h1B,	INSTR_CC 	=5'h1C,	INSTR_NCS 	=5'h1E,
	INSTR_NCT 	=5'h20,	INSTR_SQR 	=5'h28,	INSTR_DCPL 	=5'h29,	INSTR_DPCT 	=5'h2A,	INSTR_AVSZ3	=5'h2D,	INSTR_AVSZ4 =5'h2E,
	INSTR_RTPT	=5'h30,	INSTR_GPF	=5'h3D,	INSTR_GPL	=5'h3E,	INSTR_NCCT	=5'h3F;	
	
wire [ 8:0] startMicroCodeAdr;
always @(Instruction)
begin
	case (Instruction[5:0])
	INSTR_RTPS	:	startMicroCodeAdr =   9'd0; // 15;
	INSTR_NCLIP	:	startMicroCodeAdr =  9'd15; //  8;
	INSTR_OP	:	startMicroCodeAdr =  9'd23; //  6;
	INSTR_DPCS	:	startMicroCodeAdr =  9'd29; //  8;
	INSTR_INTPL	:	startMicroCodeAdr =  9'd37; //  8;
	INSTR_MVMVA	:	startMicroCodeAdr =  9'd45; //  8;
	INSTR_NCDS	:	startMicroCodeAdr =  9'd53; // 19;
	INSTR_CDP	:	startMicroCodeAdr =  9'd72; // 13;
	INSTR_NCDT	:	startMicroCodeAdr =  9'd85; // 44;
	INSTR_NCCS	:	startMicroCodeAdr = 9'd129; // 17;
	INSTR_CC 	:	startMicroCodeAdr = 9'd146; // 11;
	INSTR_NCS 	:	startMicroCodeAdr = 9'd157; // 14;
	INSTR_NCT 	:	startMicroCodeAdr = 9'd171; // 30;
	INSTR_SQR 	:	startMicroCodeAdr = 9'd201; //  5;
	INSTR_DCPL 	:	startMicroCodeAdr = 9'd206; //  8;
	INSTR_DPCT 	:	startMicroCodeAdr = 9'd214; // 17;
	INSTR_AVSZ3	:	startMicroCodeAdr = 9'd231; //  5;
	INSTR_AVSZ4 :	startMicroCodeAdr = 9'd236; //  6;
	INSTR_RTPT	:	startMicroCodeAdr = 9'd242; // 23;
	INSTR_GPF	:	startMicroCodeAdr = 9'd265; //  5;
	INSTR_GPL	:	startMicroCodeAdr = 9'd270; //  5;
	INSTR_NCCT	:	startMicroCodeAdr = 9'd275; // 39;
	default     :	startMicroCodeAdr = 9'd314; //  1;
	endcase
end

GTEMicroCode GTEMicroCode_inst(
	PC			(PC),
	microCode	(microCode)
);

always @(posedge i_clk)
begin
	if (execute && (!executing)) begin
		executing = 1;
		instr_sf  = Instruction[19];		// 0:No fraction, 1:12 Bit Fraction
		instr_lm  = Instruction[10];		// 0:Clamp to MIN, 1:Clamp to ZERO.
		// MVMVA only.
		instr_cv  = Instruction[14:13];		// 0:TR,       1:BK,    2:FC/Bugged, 3:None
		instr_vec = Instruction[16:15];		// 0:V0,       1:V1,    2:V2,        3:IR/Long
		instr_mx  = Instruction[18:17];		// 0:Rotation, 1:Light, 2:Color,     3:Reserved
		PC        = startMicroCodeAdr;
	end else if (lastInstruction || i_nRst) begin
		executing = 0;
		PC		  = 9'd314;
	end
end


// ----------------------------------------------------------------------------------------------
//   Computation data path.
// ----------------------------------------------------------------------------------------------
reg signed [48:0] internalResult;
reg [31:0] fullvalueOut = sf ? internalResult[43:12] : internalResult[31: 0];
reg [15:0] lowValueOut	= fullvalueOut[15:0];

// ----------------------------------------------------------------------------------------------
//   Division Unit.
// ----------------------------------------------------------------------------------------------
GTEFastDiv GTEFastDiv_inst(
	.h			(?),			// Dividend 16 bit
	.z3			(?),			// Divisor  16 bit
	.divRes		(?),			// Result   17 bit !
	.overflow	(DivOvr)	// Overflow bit
);

// ----------------------------------------------------------------------------------------------
//   Status Flags Registers
// ----------------------------------------------------------------------------------------------
wire AxPos,AxNeg,FPos,FNeg,G,H,B,C,D,DivOvr;
reg [18:0] regStatus;

GTEOverflowFLAGS GTEFlagInst(
	.v			(internalResult),
	.sf			(sf),
	.lm			(lm),
	.AxPos		(AxPos),
	.AxNeg		(AxNeg),
	.FPos		(FPos),
	.FNeg		(FNeg),
	.G			(G),
	.H			(H),
	.B			(B),
	.C			(C),
	.D			(D)
);

always @(posedge i_clk)
begin
	if (resetStatus) begin
		regStatus = 19'd0;
	end else begin
		// Implemented as sticky flag -> write only if 1.
		if (AxPos & microCode[39]) regStatus[18] = AxPos;
		if (AxPos & microCode[40]) regStatus[17] = AxPos;
		if (AxPos & microCode[41]) regStatus[16] = AxPos;
		if (AxNeg & microCode[42]) regStatus[15] = AxNeg;
		if (AxNeg & microCode[43]) regStatus[14] = AxNeg;
		if (AxNeg & microCode[44]) regStatus[13] = AxNeg;
		if (B     & microCode[45]) regStatus[12] = B;
		if (B     & microCode[46]) regStatus[11] = B;
		if (B     & microCode[47]) regStatus[10] = B;
		if (C     & microCode[48]) regStatus[ 9] = C;
		if (C     & microCode[49]) regStatus[ 8] = C;
		if (C     & microCode[50]) regStatus[ 7] = C;
		if (D     & microCode[51]) regStatus[ 6] = D;
		if (DivOvr& microCode[52]) regStatus[ 5] = DivOvr;
		if (FPos  & microCode[53]) regStatus[ 4] = FPos;
		if (FNeg  & microCode[54]) regStatus[ 3] = FNeg;
		if (G     & microCode[55]) regStatus[ 2] = G;
		if (G     & microCode[56]) regStatus[ 1] = G;
		if (H     & microCode[57]) regStatus[ 0] = H;
	end
end 
// ----------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------
//   FILE REGISTERS
//
//   2x 32 Bit DATA FILE REGISTERS. (DataA, DataB) all DUAL PORT
//   2x 32 Bit CTRL FILE REGISTERS. (CTRLA, CTRLB) all DUAL PORT
//
//   CPU can read (from A) / write (same value on both A&B) from it.
//   When CPU does not access, parallel reading is possible from
//   microcode setup.
// ----------------------------------------------------------------------------------------------
wire [31:0] outDataA,outDataB;
wire [31:0] outCTRLA,outCTRLB;

wire		cpuWData	 = i_WritReg & (!i_regID[5]);
wire		cpuWCTRL	 = i_WritReg & ( i_regID[5]);

wire [31:0] inData		 = i_WritReg ? i_dataIn : vDATA;
wire [31:0] inCTRL		 = i_dataIn; // Only CPU can write to the registers.
wire		readCTRLA	 = i_ReadReg ?   i_regID[5] : !i_WritReg;
wire		readDataA	 = i_ReadReg ? (!i_regID[5]): !i_WritReg;
wire  [4:0] readAdrDataA = i_ReadReg ? i_regID[4:0] : microCode[ 7: 3];					// MICROCODE:[DATA File A READ]
wire  [4:0] readAdrDataB =                            microCode[12: 8];					// MICROCODE:[DATA File B READ]
wire  [4:0] readAdrCTRLA = i_ReadReg ? i_regID[4:0] : microCode[17:13];					// MICROCODE:[CTRL File A READ]
wire  [4:0] readAdrCTRLB =                            microCode[22:18];					// MICROCODE:[CTRL File B READ]
wire		readCTRLB	 = !i_WritReg; // Avoid reading when CPU write.
wire		readDataB	 = !i_WritReg; // Avoid reading when CPU write.
wire		writeData	 = cpuWData  | microCode[23];									// MICROCODE:[DATA WRITE]
wire		writeCTRL	 = cpuWCTRL  | microCode[24];									// MICROCODE:[CTRL WRITE]
wire  [4:0]	writeAdrData = cpuWData  ? i_regID[4:0] : microCode[33:29];					// MICROCODE:[DATA ADR WRITE]
wire  [4:0]	writeAdrCTRL = cpuWCTRL  ? i_regID[4:0] : microCode[38:34];					// MICROCODE:[CTRL ADR WRITE]

FileReg instDATA_A(
	.clk	(i_clk			),
	.read	(readDataA		), .readAdr (readAdrDataA	), .outData	(outDataA	),	// Read Side
	.write	(writeData		), .writeAdr(writeAdrData	), .inData	(inData		)	// Write Side
);

FileReg instDATA_B(
	.clk	(i_clk			),
	.read	(readDataB		), .readAdr (readAdrDataB	), .outData(outDataB	),	// Read Side
	.write	(writeData		), .writeAdr(writeAdrData	), .inData (inData		)	// Write Side
);

FileReg instCTRL_A(
	.clk	(i_clk			),
	.read	(readCTRLA		), .readAdr (readAdrCTRLA	), .outData	(outCTRLA	),	// Read Side
	.write	(writeCTRL		), .writeAdr(writeAdrCTRL	), .inData	(inCTRL		)	// Write Side
);

FileReg instCTRL_B(
	.clk	(i_clk			),
	.read	(readCTRLB		), .readAdr (readAdrCTRLB	), .outData(outCTRLB	),	// Read Side
	.write	(writeCTRL		), .writeAdr(writeAdrCTRL	), .inData	(inCTRL		)	// Write Side
);
// ----------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------
//   CPU Side Register Read/Write
// ----------------------------------------------------------------------------------------------
	// Probably not optimal...
	wire        accSXY0 = (i_regID == 6'd12);
	wire        accSXY1 = (i_regID == 6'd13);
	wire        accSXY2 = (i_regID == 6'd14);
	wire        accCRGB0= (i_regID == 6'd20);
	wire        accCRGB1= (i_regID == 6'd21);
	wire        accCRGB2= (i_regID == 6'd22);
	wire		accSZ0  = (i_regID == 6'd16);
	wire		accSZ1  = (i_regID == 6'd17);
	wire		accSZ2  = (i_regID == 6'd18);
	wire		accSZ3  = (i_regID == 6'd19);
	wire		accIR0  = (i_regID == 6'd8 );
	wire		accIR1  = (i_regID == 6'd9 );
	wire		accIR2  = (i_regID == 6'd10);
	wire		accIR3  = (i_regID == 6'd11);

// [CPU Write to Data And CTRL done]
// - Direct mapping of write signal / adress / data bus to RegisterFile / Registers by instruction decoder.
// - Read Values from 
//		wire [31:0] outDataA;
//		wire [31:0] outCTRLA;
//		+ (readDataA & i_ReadReg) pipelined (answer at next cycle)
//		+ (readCTRLA & i_ReadReg) pipelined (answer at next cycle)
//		+ Depending on pipelined address -> other registers. + formatting.
//		// Decode as input, pipeline the flag !
	/*
	---
	CPU Write : All done.
		-> writeSignal : writeData/writeCTRL/Proper register write (12/13/14 SXY*, 16/17/18/19 SZ*, 20/21/22 CRGB*) 
		-> writeAdr    : writeAdrData/writeAdrCTRL
		-> writeData   : inData/inCTRL
	---
	CPU Read  :
		-> read Signal : readDataA/readCTRLA
		-> read Adr    : readAdrDataA/readAdrCTRLA
		-> readData    : outDataA vs outCTRLA vs Real Registers. 
	*/

	wire rDATA = i_ReadReg &   i_regID[5] ;
	wire rCTRL = i_ReadReg & (!i_regID[5]);
	
	//	16 bit promotion:
	//	Sign ext CTRL 4,12,20 	DATA 1,3,5,8~11
	//	Sign   0 CTRL 26~30		DATA 7,16~19
	wire rExt  = (i_regID[4:0]==CTRL_R33_) 
	           | (i_regID[4:0]==CTRL_L33_)
			   | (i_regID[4:0]==CTRL_LB3_) 
			   | (i_regID[4:0]==DATA__VZ0)
			   | (i_regID[4:0]==DATA__VZ1)
			   | (i_regID[4:0]==DATA__VZ2)
			   |((i_regID[4:0]>=DATA__IR0) && (i_regID[4:0]<=DATA__IR3))
			   ;
			   
	wire rZero =((i_regID[4:0]>=CTRL__H__) && (i_regID[4:0]<=CTRL_ZSF4)) 
	           |((i_regID[4:0]>=DATA__SZ0) && (i_regID[4:0]<=DATA__SZ3))
			   | (i_regID[4:0]==DATA__OTZ)
			   ;
			   
	// TODO pipeline those 4 flags, return value from REG file or register.
// ----------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------
//   Special REGISTERS, not stored inside the REGISTER FILES.
// ----------------------------------------------------------------------------------------------
reg [15:0] SX0  ,SX1  ,SX2;
reg [15:0] SY0  ,SY1  ,SY2;
reg [15:0] SZ0  ,SZ1  ,SZ2  ,SZ3;
reg [15:0] IR0  ,IR1  ,IR2  ,IR3;
reg [31:0] CRGB0,CRGB1,CRGB2;

// ---- FIFOs ------------------------------------------------------
// From CPU write or internal GTE write.


wire cpuWFifoSPXY = (i_WritReg && (i_regID == 6'd15));									// is CPU Writing to SPXY registers ?
wire        write_SPX	= cpuWFifoSPXY | microCode[26];									// MICROCODE:[Push to SPX FIFO]
wire        write_SPY	= cpuWFifoSPXY | microCode[27];									// MICROCODE:[Push to SPY FIFO]

// Those THREE wires are identical to dataPath16 :
wire [15:0] dataPath16  = i_WritReg ? i_dataIn[15: 0] : lowValueOut;
/*re [15:0] sxInput		= i_WritReg ? i_dataIn[15: 0] : lowValueOut;
wire [15:0] sIRInput	= i_WritReg ? i_dataIn[15: 0] : lowValueOut;
wire [15:0] szInput		= i_WritReg ? i_dataIn[15: 0] : lowValueOut; */
wire [15:0] syInput		= i_WritReg ? i_dataIn[31:15] : lowValueOut;
wire [31:0] sCRGBInput	= i_WritReg ? i_dataIn[31: 0] : fullvalueOut;

// Use when CPU write only.
wire  [2:0] writeSXY;
wire  [2:0] writeCRGB;
// No microcode, only CPU can write directly to FIFO registers without shift.

assign writeSXY[0]		= (i_WritReg && accSXY0); 
assign writeSXY[1]		= (i_WritReg && accSXY1);
assign writeSXY[2]		= (i_WritReg && accSXY2);
assign writeCRGB[0]		= (i_WritReg && accCRGB0);
assign writeCRGB[1]		= (i_WritReg && accCRGB1);
assign writeCRGB[2]		= (i_WritReg && accCRGB2);	/*TODO:CPU WRITE DOES FIFO OR NOT, ONLY GTE INTERNAL ?*/
wire   write_FCRGB		= microCode[28];			/* TODO : | (i_WritReg && (i_regID == 6'd22))         */
													// MICROCODE:[Push to CRGB FIFO]

wire  [3:0] writeSZ;
assign writeSZ[0]		= (i_WritReg && accSZ0);
assign writeSZ[1]		= (i_WritReg && accSZ1);
assign writeSZ[2]		= (i_WritReg && accSZ2);
assign writeSZ[3]		= (i_WritReg && accSZ3);
wire        write_FZ	= microCode[25] /* NEVER : | (i_WritReg && (i_regID == 6'd19))*/; /* CPU DOES NOT PUSH FIFO */
																						// MICROCODE:[Push to Z FIFO]
wire [3:0]  writeIR;
assign writeIR[0]		= (i_WritReg && accIR0) | (writeAdrData == 5'd8 );
assign writeIR[1]		= (i_WritReg && accIR1) | (writeAdrData == 5'd9 );
assign writeIR[2]		= (i_WritReg && accIR2) | (writeAdrData == 5'd10);
assign writeIR[3]		= (i_WritReg && accIR3) | (writeAdrData == 5'd11);

always @(posedge i_clk)
begin
	// SX Fifo
	if (write_SPX | writeSXY[0]) SX0 = write_SPX ? SX1 : dataPath16;
	if (write_SPX | writeSXY[1]) SX1 = write_SPX ? SX2 : dataPath16;
	if (write_SPX | writeSXY[2]) SX2 = dataPath16;
	// SY Fifo
	if (write_SPY | writeSXY[0]) SY0 = write_SPY ? SY1 : syInput;
	if (write_SPY | writeSXY[1]) SY1 = write_SPY ? SY2 : syInput;
	if (write_SPY | writeSXY[2]) SY2 = syInput;
	// SZ Fifo
	if (write_FZ  | writeSZ[0]) SZ0 = write_FZ  ? SZ1 : dataPath16;
	if (write_FZ  | writeSZ[1]) SZ1 = write_FZ  ? SZ2 : dataPath16;
	if (write_FZ  | writeSZ[2]) SZ2 = write_FZ  ? SZ3 : dataPath16;
	if (write_FZ  | writeSZ[3]) SZ3 = dataPath16;
	// CRGB Fifo
	if (write_FCRGB | writeCRGB[0]) CRGB0 = write_FCRGB ? CRGB1 : sCRGBInput;
	if (write_FCRGB | writeCRGB[1]) CRGB1 = write_FCRGB ? CRGB2 : sCRGBInput;
	if (write_FCRGB | writeCRGB[2]) CRGB2 = sCRGBInput;
	// IR0~IR3 Write
	if (writeIR[0]) IR0 = dataPath16;
	if (writeIR[1]) IR1 = dataPath16;
	if (writeIR[2]) IR2 = dataPath16;
	if (writeIR[3]) IR3 = dataPath16;
end

wire [15:0] IRGB_rw; // IRGB read is = ORGB_r
wire IRGB_write;

wire ovr = (!IR1[15]) & (|IR1[14:12]);	// Overflow 0x1F
wire ovg = (!IR2[15]) & (|IR2[14:12]);	// Overflow 0x1F
wire ovb = (!IR3[15]) & (|IR3[14:12]);	// Overflow 0x1F
wire  [4:0] oRGB_R = (IR1[11:7] & {5{!IR1[15]}}) | {5{ovr}};
wire  [4:0] oRGB_G = (IR2[11:7] & {5{!IR2[15]}}) | {5{ovg}};
wire  [4:0] oRGB_B = (IR3[11:7] & {5{!IR3[15]}}) | {5{ovb}};
// Register r29 output
wire [14:0] ORGB_r = {oRGB_B , oRGB_G , oRGB_R};

// Output
assign o_executing = executing;

/*	ORGB_r conversion is delicate :	Div 128. SIGNED + Saturate unsigned.
	[15:0] -> [15:7]=[8:0] (-256..+255 -> 0..255)
	bit[15] -> reset to 0.
	IR1[14:10] && {5{!IR1[15]}}
	
	cop2r29 - ORGB - Color conversion Output (R)
           (-32768..+32767)
	[15:7] (  -256..255   )
	

Collapses 16:16:16 bit RGB (range 0000h..0F80h) to 5:5:5 bit RGB (range
0..1Fh). Negative values (8000h..FFFFh/80h) are saturated to 00h, large
positive values (1000h..7FFFh/80h) are saturated to 1Fh, there are no overflow
or saturation flags set in cop2r63 though.
  0-4    Red   (0..1Fh) (R)  ;IR1 divided by 80h, saturated to +00h..+1Fh
  5-9    Green (0..1Fh) (R)  ;IR2 divided by 80h, saturated to +00h..+1Fh
  10-14  Blue  (0..1Fh) (R)  ;IR3 divided by 80h, saturated to +00h..+1Fh
  15-31  Not used (always zero) (Read only)
Any changes to IR1,IR2,IR3 are reflected to this register (and, actually also
to IRGB) (ie. ORGB is simply a read-only mirror of IRGB).
*/

//  0-4    Red   (0..1Fh) (R/W)  ;multiplied by 80h, and written to IR1
//  5-9    Green (0..1Fh) (R/W)  ;multiplied by 80h, and written to IR2
//  10-14  Blue  (0..1Fh) (R/W)  ;multiplied by 80h, and written to IR3

endmodule
