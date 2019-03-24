module GTEEngine (
	input         i_clk,
	input         i_nRst,

	//   GTE PORT
	input  [5:0]  i_regID,
	input         i_WritReg,
	input         i_ReadReg,
	input  [31:0] i_dataIn,
	output [31:0] i_dataOut,

	input  [24:0] Instruction,
	input         execute,
	output        o_executing
);

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

wire [58:0] microCode;
reg  [ 8:0] PC;

wire sf              = microCode[57] & instr_sf;
wire lm       		 = microCode[2] & instr_lm;											// MICROCODE:[Override LM Bit to ZERO (0:override,1:Normal)]
wire resetStatus	 = microCode[0];													// MICROCODE:[First Microcode, reset status flags].
wire lastInstruction = microCode[1];													// MICROCODE:[Last  Microcode]

parameter	
	INSTR_RTPS	=6'h01,	INSTR_NCLIP	=6'h06,	INSTR_OP	=6'h0C,	INSTR_DPCS	=6'h10,	INSTR_INTPL	=6'h11,	INSTR_MVMVA	=6'h12,
	INSTR_NCDS	=6'h13,	INSTR_CDP	=6'h14,	INSTR_NCDT	=6'h16,	INSTR_NCCS	=6'h1B,	INSTR_CC 	=6'h1C,	INSTR_NCS 	=6'h1E,
	INSTR_NCT 	=6'h20,	INSTR_SQR 	=6'h28,	INSTR_DCPL 	=6'h29,	INSTR_DPCT 	=6'h2A,	INSTR_AVSZ3	=6'h2D,	INSTR_AVSZ4 =6'h2E,
	INSTR_RTPT	=6'h30,	INSTR_GPF	=6'h3D,	INSTR_GPL	=6'h3E,	INSTR_NCCT	=6'h3F;	
	
reg [ 8:0] startMicroCodeAdr;
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

GTEMicrocode GTEMicrocode_inst(
	.PC			(PC),
	.microCode	(microCode)
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
wire [31:0] vDATA; // Result path to send to DATA register file.
wire [15:0] dividendU16,divisorU16;
wire [16:0] divResU17;

// TODO : Signal for pushR,pushG,pushB (microCode) Note : pushC is done auto same as pushB.
// TODO : Implement value clamping in flag unit and set colorWrValue with Lm_C1/2/3
/*	TODO : regs  value on reset 
	codeReg,
	SX0  ,SX1  ,SX2;
	SY0  ,SY1  ,SY2;
	SZ0  ,SZ1  ,SZ2  ,SZ3;
	IR0  ,IR1  ,IR2  ,IR3;
	CRGB0,CRGB1,CRGB2;
	regCntLead10LZCS;
 */

// TODO Select Register OR outDataA/B
// TODO Select high/low 16 bit from outDataX or outCTRLx 
// v = outA + neg ? outB : (~outB + 1)
//  reg = v ? v + reg

// [From Microcode]
wire  [1:0] select16A,select16B;	// TODO
wire        selAA    , selAB;		// TODO
wire  [1:0] select32A,select32B;	// TODO
wire        shft12A  , shft12B;		// TODO
wire        negB_A   ,negB_A;		// TODO 
wire        readHighA;				// TODO
wire        readHighB;				// TODO


wire [15:0] A16   = 16'd0/* TODO B Clamped out of unit*/;
  
reg [15:0] iD16A;	// Select L/H from Data A path or 16 bit registers.
reg [15:0] i16B_A;	// Select L/H from CTRL A path or ????
reg [15:0] iD16B;	// Select L/H from Data B path or 16 bit registers.
reg [15:0] i16B_B;	// Select L/H from CTRL A path or ????

/*	
	- Select Register SX0/1/2/IR0/IR1/IR2/IR3
	Microcode :
	iD16A = ;
	iD16B = ;
 */
always @(*)
begin
	case (microCode[ 7: 3])
	DATA__IR0 : iD16A = IR0;
	DATA__IR1 : iD16A = IR1;
	DATA__IR2 : iD16A = IR2;
	DATA__IR3 : iD16A = IR3;
	/*
	DATA__SX0 : iD16A = SX0;
	DATA__SX1 : iD16A = SX1;
	DATA__SX2 : iD16A = SX2;
	DATA__SY0 : iD16A = SY0;
	DATA__SY1 : iD16A = SY1;
	DATA__SY2 : iD16A = SY2;
	DATA__SZ0 : iD16A = SZ0;
	DATA__SZ1 : iD16A = SZ1;
	DATA__SZ2 : iD16A = SZ2;
	DATA__SZ3 : iD16A = SZ3;
	*/
	default   : iD16A = readHighA ? outDataA[31:16]:outDataA[15:0];
	endcase
end

always @(*)
begin
	case (microCode[12: 8])
	DATA__IR0 : iD16B = IR0;
	DATA__IR1 : iD16B = IR1;
	DATA__IR2 : iD16B = IR2;
	DATA__IR3 : iD16B = IR3;
	/*
	DATA__SX0 : iD16B = SX0;
	DATA__SX1 : iD16B = SX1;
	DATA__SX2 : iD16B = SX2;
	DATA__SY0 : iD16B = SY0;
	DATA__SY1 : iD16B = SY1;
	DATA__SY2 : iD16B = SY2;
	DATA__SZ0 : iD16B = SZ0;
	DATA__SZ1 : iD16B = SZ1;
	DATA__SZ2 : iD16B = SZ2;
	DATA__SZ3 : iD16B = SZ3;
	*/
	default   : iD16B = readHighB ? outDataB[31:16]:outDataB[15:0];
	endcase
end

GTEComputePath PathA (
    .select16		(select16A	),   // 0:-1,1:0,2:+1,3:data16
    .selA			(selAA		),   // 0:D16 or 1:A16
    .select32		(select32A	),   // i32C,u8Shl16, u8Shl4, i16B
	.negB			(negB_A		),
    .shft12			(shft12A	),   // IMPORTANT : Authorized only for select16 -1/0/+1, else buggy output 
	
    .iD16			(iD16A		),
    .A16			(A16		),
    
    .i32C			(outCTRLA	),
    .i16B			(i16B_A),
    .i8U			(?),
    
    .out			(outA		)
);

GTEComputePath PathB (
    .select16		(select16B	),   // 0:-1,1:0,2:+1,3:data16
    .selA			(selAB		),   // 0:D16 or 1:A16
    .select32		(select32B	),   // i32C,u8Shl16, u8Shl4, i16B
	.negB			(negB_B		),
    .shft12			(shft12B	),   // IMPORTANT : Authorized only for select16 -1/0/+1, else buggy output 
	
    .iD16			(iD16B		),
    .A16			(A16		),
	
    .i32C			(outCTRLB	),
    .i16B			(i16B_B),
    .i8U			(?),
    
    .out			(outB		)
);

wire signed [47:0] outA;
wire signed [47:0] outB;
wire signed [48:0] sumAB    = { outA[47], outA} + { outB[47], outB};
wire signed [49:0] totalSum = {sumAB[48],sumAB} +       accumulator;
reg  signed [49:0] accumulator;
reg         [31:0] fullvalueOut = sf ? totalSum[43:12] : totalSum[31: 0];
reg         [15:0] lowValueOut	= fullvalueOut[15:0];
 
// ----------------------------------------------------------------------------------------------
//   Division Unit.
// ----------------------------------------------------------------------------------------------
GTEFastDiv GTEFastDiv_inst(
	.h			(dividendU16),			// Dividend 16 bit
	.z3			(divisorU16 ),			// Divisor  16 bit
	.divRes		(divResU17  ),			// Result   17 bit !
	.overflow	(DivOvr     )			// Overflow bit
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
	.read	(readDataA		), .readAdr (readAdrDataA	), .outData(outDataA	),	// Read Side
	.write	(writeData		), .writeAdr(writeAdrData	), .inData (inData		)	// Write Side
);

FileReg instDATA_B(
	.clk	(i_clk			),
	.read	(readDataB		), .readAdr (readAdrDataB	), .outData(outDataB	),	// Read Side
	.write	(writeData		), .writeAdr(writeAdrData	), .inData (inData		)	// Write Side
);

FileReg instCTRL_A(
	.clk	(i_clk			),
	.read	(readCTRLA		), .readAdr (readAdrCTRLA	), .outData(outCTRLA	),	// Read Side
	.write	(writeCTRL		), .writeAdr(writeAdrCTRL	), .inData (inCTRL		)	// Write Side
);

FileReg instCTRL_B(
	.clk	(i_clk			),
	.read	(readCTRLB		), .readAdr (readAdrCTRLB	), .outData(outCTRLB	),	// Read Side
	.write	(writeCTRL		), .writeAdr(writeAdrCTRL	), .inData (inCTRL		)	// Write Side
);
// ----------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------
//   CPU Side Register Read/Write
// ----------------------------------------------------------------------------------------------

// Probably not optimal...
wire        accSXY0 = (i_regID == DATA_SXY0);
wire        accSXY1 = (i_regID == DATA_SXY1);
wire        accSXY2 = (i_regID == DATA_SXY2);
wire        accCRGB0= (i_regID == DATACRGB0);
wire        accCRGB1= (i_regID == DATACRGB1);
wire        accCRGB2= (i_regID == DATACRGB2);
wire        accLZCR = (i_regID == DATA_LZCR);
wire		accSZ0  = (i_regID == DATA__SZ0);
wire		accSZ1  = (i_regID == DATA__SZ1);
wire		accSZ2  = (i_regID == DATA__SZ2);
wire		accSZ3  = (i_regID == DATA__SZ3);
wire		accIR0  = (i_regID == DATA__IR0);
wire		accIR1  = (i_regID == DATA__IR1);
wire		accIR2  = (i_regID == DATA__IR2);
wire		accIR3  = (i_regID == DATA__IR3);

wire rDATA = i_ReadReg &   i_regID[5] ;
wire rCTRL = i_ReadReg & (!i_regID[5]);

//	16 bit promotion:
//	Sign ext CTRL 4,12,20 	DATA 1,3,5,8~11
//	Sign   0 CTRL 26~30		DATA 7,16~19
wire rExt  = (i_regID==CTRL_R33_) 
		   | (i_regID==CTRL_L33_)
		   | (i_regID==CTRL_LB3_)			   
		   | (i_regID==DATA__VZ0)
		   | (i_regID==DATA__VZ1)
		   | (i_regID==DATA__VZ2)
		   |((i_regID>=DATA__IR0) && (i_regID<=DATA__IR3))
		   ; // Copy sign = 1
		   
wire rZero =((i_regID>=CTRL__H__) && (i_regID<=CTRL_ZSF4)) 
		   |((i_regID>=DATA__SZ0) && (i_regID<=DATA__SZ3))
		   | (i_regID==DATA__OTZ)
		   ; // 1 = Reset to 0

reg pExt,pNZero;
reg [5:0] pRegID;
always @(posedge i_clk)
begin
	if (i_ReadReg) begin
		pExt   <= rExt;
		pNZero <= !rZero;
		pRegID <= i_regID;
	end
end

wire lowP  = (pRegID[1:0]==2'b00);
wire highP = (pRegID[1:0]==2'b11);
wire bit31Status = (|regStatus[18:11]) | (|regStatus[6:1]); // Bit 13-18 (1:6) and Bit 23-30 (18:11) ORed together.

reg [31:0] vOut;
always @(*)
begin
	if (pRegID[5])
	begin
		if (pRegID[4:0]==DATA_STATUS)
			vOut = { bit31Status, regStatus, 12'b0 };	// Status Register.
		else
			vOut = outCTRLA;
	end else begin
		if (lowP || highP) begin
			if (highP && pRegID[2]) begin
				case (pRegID[1:0])
				2'd0   : vOut = {{17{1'b0}},ORGB_r};	// IRGB in read mode.
				2'd1   : vOut = {{17{1'b0}},ORGB_r};	// ORGB in read mode. MIRROR.
				2'd2   : vOut = outDataA;				// Stored in RegFile.
				default: vOut = {{26{1'b0}},regCntLead10LZCS};
				endcase
			end else begin
				vOut = outDataA;
			end
		end else begin
			case (pRegID[3:0])
			// SZ0 -> RES1
			4'd0   : vOut = {{16{1'b0}}, SZ0};
			4'd1   : vOut = {{16{1'b0}}, SZ1};
			4'd2   : vOut = {{16{1'b0}}, SZ2};
			4'd3   : vOut = {{16{1'b0}}, SZ3};
			4'd4   : vOut = CRGB0;
			4'd5   : vOut = CRGB1;
			4'd6   : vOut = CRGB2;
			4'd7   : vOut = outDataA; // RES1
			// IR0 -> SXP
			4'd8   : vOut = {{16{IR0[15]}} , IR0};
			4'd9   : vOut = {{16{IR1[15]}} , IR1};
			4'd10  : vOut = {{16{IR2[15]}} , IR2};
			4'd11  : vOut = {{16{IR3[15]}} , IR3};
			4'd12  : vOut = {SY0,SX0};
			4'd13  : vOut = {SY1,SX1};
			4'd14  : vOut = {SY2,SX2};
			default: vOut = {SY2,SX2}; // SXP is a mirror. -> Read does not shift.
			endcase
		end
	end
end

wire orB                = vOut[15] & pExt;
wire andB               = orB | pNZero;
wire [15:0] andStageOut = {16{andB}}; // Reset to zero when flag is ZERO.
wire [15:0] orStageOut  = { 16{orB}};

assign i_dataOut = { ((vOut[31:16] & andStageOut) | orStageOut) , vOut[15:0] };
// ----------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------
//   Combinatorial Logic for 0 and 1 lead count for numbers.
// ----------------------------------------------------------------------------------------------
wire [5:0] cntLeadInput; // 1..32 Value output
LeadCountS32 instLeadCount(
	.value	(i_dataIn    ),
	.result	(cntLeadInput)
);

// ----------------------------------------------------------------------------------------------
//   Special REGISTERS, not stored inside the REGISTER FILES.
// ----------------------------------------------------------------------------------------------
reg [15:0] SX0  ,SX1  ,SX2;
reg [15:0] SY0  ,SY1  ,SY2;
reg [15:0] SZ0  ,SZ1  ,SZ2  ,SZ3;
reg [15:0] IR0  ,IR1  ,IR2  ,IR3;
reg [31:0] CRGB0,CRGB1,CRGB2;
reg [ 5:0] regCntLead10LZCS;

// ---- FIFOs ------------------------------------------------------
// From CPU write or internal GTE write.


wire cpuWFifoSPXY = (i_WritReg && (i_regID == DATA_SXYP));								// is CPU Writing to SPXY registers ?
wire        write_SPX	= cpuWFifoSPXY | microCode[26];									// MICROCODE:[Push to SPX FIFO]
wire        write_SPY	= cpuWFifoSPXY | microCode[27];									// MICROCODE:[Push to SPY FIFO]

// Those THREE wires are identical to dataPath16 :
wire [15:0] dataPath16  = i_WritReg ? i_dataIn[15: 0] : lowValueOut;
/*re [15:0] sxInput		= i_WritReg ? i_dataIn[15: 0] : lowValueOut;
wire [15:0] sIRInput	= i_WritReg ? i_dataIn[15: 0] : lowValueOut;
wire [15:0] szInput		= i_WritReg ? i_dataIn[15: 0] : lowValueOut; */
wire [15:0] syInput		= i_WritReg ? i_dataIn[31:16] : lowValueOut;

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


wire   pushR,pushG,pushB,pushC; 					//		= microCode[28];
assign pushC = pushB;	// Trick : use same wire, codeReg register has value anyway !
					
wire   writeCode		= (i_WritReg && (i_regID == DATA_RGBC));
reg [7:0] codeReg;

wire  [3:0] writeSZ;
assign writeSZ[0]		= (i_WritReg && accSZ0);
assign writeSZ[1]		= (i_WritReg && accSZ1);
assign writeSZ[2]		= (i_WritReg && accSZ2);
assign writeSZ[3]		= (i_WritReg && accSZ3);
wire        write_FZ	= microCode[25] /* NEVER : | (i_WritReg && (i_regID == 6'd19))*/; /* CPU DOES NOT PUSH FIFO */
																						// MICROCODE:[Push to Z FIFO]
wire [3:0]  writeIR;
assign writeIR[0]		= (i_WritReg && accIR0) | (writeAdrData == DATA_IR0_5b);
assign writeIR[1]		= (i_WritReg && accIR1) | (writeAdrData == DATA_IR1_5b);
assign writeIR[2]		= (i_WritReg && accIR2) | (writeAdrData == DATA_IR2_5b);
assign writeIR[3]		= (i_WritReg && accIR3) | (writeAdrData == DATA_IR3_5b);

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
	
	// R Fifo
	if (pushR | writeCRGB[0]) CRGB0[ 7: 0] = pushR ? CRGB1[ 7: 0] : i_dataIn[ 7: 0]; // R
	if (pushR | writeCRGB[1]) CRGB1[ 7: 0] = pushR ? CRGB2[ 7: 0] : i_dataIn[ 7: 0]; // R
	if (pushR | writeCRGB[2]) CRGB2[ 7: 0] = pushR ? colorWrValue : i_dataIn[ 7: 0]; // R
	
	// G Fifo
	if (pushG | writeCRGB[0]) CRGB0[15: 8] = pushG ? CRGB1[15: 8] : i_dataIn[15: 8]; // G
	if (pushG | writeCRGB[1]) CRGB1[15: 8] = pushG ? CRGB2[15: 8] : i_dataIn[15: 8]; // G
	if (pushG | writeCRGB[2]) CRGB2[15: 8] = pushG ? colorWrValue : i_dataIn[15: 8]; // G
	
	// B Fifo
	if (pushB | writeCRGB[0]) CRGB0[23:16] = pushB ? CRGB1[23:16] : i_dataIn[23:16]; // B
	if (pushB | writeCRGB[1]) CRGB1[23:16] = pushB ? CRGB2[23:16] : i_dataIn[23:16]; // B
	if (pushB | writeCRGB[2]) CRGB2[23:16] = pushB ? colorWrValue : i_dataIn[23:16]; // B
	
	// Code Fifo
	if (pushC | writeCRGB[0]) CRGB0[31:24] = pushC ? CRGB1[31:24] : i_dataIn[31:24]; // Code
	if (pushC | writeCRGB[1]) CRGB1[31:24] = pushC ? CRGB2[31:24] : i_dataIn[31:24]; // Code
	if (pushC | writeCRGB[2]) CRGB2[31:24] = pushC ? codeReg      : i_dataIn[31:24]; // Code
	
	// Cache codeReg
	if (writeCode) codeReg = i_dataIn[31:24];
	
	// IR0~IR3 Write
	if (writeIR[0]) IR0 = dataPath16;
	if (writeIR[1]) IR1 = dataPath16;
	if (writeIR[2]) IR2 = dataPath16;
	if (writeIR[3]) IR3 = dataPath16;
	
	if (i_WritReg & accLZCR) regCntLead10LZCS = cntLeadInput;
end

wire [15:0] IRGB_rw; // IRGB read is = ORGB_r
wire IRGB_write;

wire ovr = (!IR1[15]) & (|IR1[14:12]);	// Overflow 0x1F
wire ovg = (!IR2[15]) & (|IR2[14:12]);	// Overflow 0x1F
wire ovb = (!IR3[15]) & (|IR3[14:12]);	// Overflow 0x1F
// TODO unflow flow ZERO clip.
wire  [4:0] oRGB_R = (IR1[11:7] & {5{!IR1[15]}}) | {5{ovr}};
wire  [4:0] oRGB_G = (IR2[11:7] & {5{!IR2[15]}}) | {5{ovg}};
wire  [4:0] oRGB_B = (IR3[11:7] & {5{!IR3[15]}}) | {5{ovb}};
// Register r29 output
wire [14:0] ORGB_r = {oRGB_B , oRGB_G , oRGB_R};

// Output
assign o_executing = executing;

endmodule
