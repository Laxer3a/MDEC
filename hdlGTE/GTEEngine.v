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
// Only in command MVMVA
reg [1:0] instr_cv,instr_vec,instr_mx;
reg       executing;

reg  [ 8:0] PC;

parameter	
	// 22 Instructions
	INSTR_RTPS	=6'h01,	INSTR_NCLIP	=6'h06,	INSTR_OP	=6'h0C,	INSTR_DPCS	=6'h10,	INSTR_INTPL	=6'h11,	INSTR_MVMVA	=6'h12,
	INSTR_NCDS	=6'h13,	INSTR_CDP	=6'h14,	INSTR_NCDT	=6'h16,	INSTR_NCCS	=6'h1B,	INSTR_CC 	=6'h1C,	INSTR_NCS 	=6'h1E,
	INSTR_NCT 	=6'h20,	INSTR_SQR 	=6'h28,	INSTR_DCPL 	=6'h29,	INSTR_DPCT 	=6'h2A,	INSTR_AVSZ3	=6'h2D,	INSTR_AVSZ4 =6'h2E,
	INSTR_RTPT	=6'h30,	INSTR_GPF	=6'h3D,	INSTR_GPL	=6'h3E,	INSTR_NCCT	=6'h3F;	
	
reg [ 8:0] startMicroCodeAdr;
always @(Instruction)
begin
	// 22 Instructions
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

always @(posedge i_clk)
begin
	pClampB <= clampB;
	if (execute && (!executing)) begin
		executing = 1;
		instr_sf  = Instruction[19];		// 0:No fraction, 1:12 Bit Fraction
		instr_lm  = Instruction[10];		// 0:Clamp to MIN, 1:Clamp to ZERO.
		// MVMVA only.
		instr_cv  = Instruction[14:13];		// 0:TR,       1:BK,    2:FC/Bugged, 3:None
		instr_vec = Instruction[16:15];		// 0:V0,       1:V1,    2:V2,        3:IR/Long
		instr_mx  = Instruction[18:17];		// 0:Rotation, 1:Light, 2:Color,     3:Reserved
		PC        = startMicroCodeAdr;
	end else if (gteLastMicroInstruction || i_nRst) begin
		executing = 0;
		PC		  = 9'd314;
	end
end


// TODO : Signal for gtePshR,gtePshG,gtePshB (microCode) Note : gtePshC is done auto same as gtePshB.
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

// Control status for microcode.
wire		gteLastMicroInstruction;

// State Machine Control for Writing to custom registers.
wire		gtePshR,gtePshG,gtePshB; 					//		= microCode[28];
wire		gtePshC	= gtePshB;	// Trick : use same wire, codeReg register has value anyway !
wire		gteWrtSZ3;
wire		gteWrtSPX,gteWrtSPY;
wire		gteWriteShadowIR,gteCpyShadowIR;
wire [3:0]	gteWrtIR;

wire		gteSF;
wire		gteLM;
wire		gteResetStatus;
wire [14:0] gteFlagMask;
wire		gteForceSF_B;

wire   gteWriteToDataFile;
wire   gteWriteToCtrlFile; // ALWAYS FALSE FOR NOW -> No such feature.
wire [4:0] gteReadAdrDataA,gteReadAdrDataB,gteReadAdrCtrlA,gteReadAdrCtrlB;
wire [4:0] gteWriteAdrData,gteWriteAdrCtrl;
wire [4:0] gteReadCustomRegA,gteReadCustomRegB;

/*
	TODO : WRITE BACK TO DATA REGISTER FILE (Handle all clamped values written back to register files)
		A : MAC1/2/3
		F : MAC0
		D : OTZ

	TODO :
	A : Feedback to computation path as 32 bit input.
*/

// [From Microcode]
wire  [1:0] select16A,select16B;
wire        selAA    , selAB;	
wire  [1:0] select32A,select32B;
wire        shft12A  , shft12B;	
wire        negB_A   ,negB_B;
wire        readHighA;			
wire        readHighB;
wire  [1:0] selectColA,selectColB;

GTEMicrocode GTEMicrocode_inst(
	.PC			(PC),
	
	.instr_sf	(instr_sf),
	.instr_lm 	(instr_lm),
	.instr_cv 	(instr_cv),
	.instr_vec	(instr_vec),
	.instr_mx 	(instr_mx),
	
	.gteLastMicroInstruction	(gteLastMicroInstruction),
	
	// Special Register write control.
	.gtePshR		(gtePshR),
	.gtePshG		(gtePshG),
	.gtePshB		(gtePshB),
	.gteWrtSZ3		(gteWrtSZ3),
	.gteWrtSPX		(gteWrtSPX),
	.gteWrtSPY		(gteWrtSPY),
	.gteWrtShadowIR	(gteWriteShadowIR),
	.gteCpyShadowIR	(gteCpyShadowIR),
	.gteWrtIR		(gteWrtIR),
	
	// Special Register READ
	.gteReadCustomRegA(gteReadCustomRegA),
	.gteReadCustomRegB(gteReadCustomRegB),
	
	// Flags Management
	.gteLM			(gteLM),
	.gteSF			(gteSF),
	.gteResetStatus	(gteResetStatus),
	.gteForceSF_B	(gteForceSF_B),
	.gteFlagMask	(gteFlagMask),
	
	// Register File Read
	.gteReadAdrDataA(gteReadAdrDataA),
	.gteReadAdrDataB(gteReadAdrDataB),
	.gteReadAdrCtrlA(gteReadAdrCtrlA),
    .gteReadAdrCtrlB(gteReadAdrCtrlB),
	.readHighA		(readHighA),
	.readHighB		(readHighB),
	.selectColA		(selectColA),
	.selectColB		(selectColB),
	
	
	// Register File Write
	.gteWriteToDataFile	(gteWriteToDataFile),
	.gteWriteToCtrlFile	(gteWriteToCtrlFile),
	.gteWriteAdrData	(gteWriteAdrData),
	.gteWriteAdrCtrl	(gteWriteAdrCtrl),
	
	// Computation path...
	.select16A			(select16A	),
	.selAA				(selAA		),
	.select32A			(select32A	),
	.shft12A			(shft12A	),
	.negB_A				(negB_A		),
	                     
	.select16B			(select16B	),
	.selAB				(selAB		),
	.select32B			(select32B	),
	.shft12B			(shft12B	),
	.negB_B				(negB_B		)
);


// ----------------------------------------------------------------------------------------------
//   Computation data path.
// ----------------------------------------------------------------------------------------------
wire [31:0] vDATA; // Result path to send to DATA register file.
wire [15:0] dividendU16,divisorU16;
wire [16:0] divResU17;

reg [15:0] pClampB; // B Clamped out of unit -> Shift by one cycle (else combinatorial feedback)
  
reg [15:0] iD16A;	// Select L/H from Data A path or 16 bit registers.
reg [15:0] i16B_A;	// Select L/H from CTRL A path or ????
reg [15:0] iD16B;	// Select L/H from Data B path or 16 bit registers.
reg [15:0] i16B_B;	// Select L/H from CTRL A path or ????
reg  [7:0] u8A,u8B;

/*	
	- Select Register SX0/1/2/IR0/IR1/IR2/IR3
	Microcode :
	iD16A = ;
	iD16B = ;
 */
always @(*)
begin
	case (gteReadCustomRegA)
	D5TA_IR0 : iD16A = IR0;
	D5TA_IR1 : iD16A = IR1;
	D5TA_IR2 : iD16A = IR2;
	D5TA_IR3 : iD16A = IR3;
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
	
	case (selectColA)
	2'd1    : u8A = outDataA[15: 8];
	2'd2    : u8A = outDataA[23:16];
	default : u8A = outDataA[ 7: 0];
	endcase

	case (selectColB)
	2'd1    : u8B = outDataA[15: 8];
	2'd2    : u8B = outDataA[23:16];
	default : u8B = outDataA[ 7: 0];
	endcase
end

always @(*)
begin
	case (gteReadCustomRegB)
	D5TA_IR0 : iD16B = IR0;
	D5TA_IR1 : iD16B = IR1;
	D5TA_IR2 : iD16B = IR2;
	D5TA_IR3 : iD16B = IR3;
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

wire inputR_A	= { (ctrlShift4A ? RegR0 : RegR) , 4'd0 };
wire inputG_B	= { (ctrlShift4B ? RegG0 : RegG) , 4'd0 };
wire inputB_C	= { (ctrlShift4C ? RegB0 : RegB) , 4'd0 };

wire nilValue   = 0;
GTEComputePathA Path (
	.sel1			(sel1A),	// 3 bit
	.sel2			(sel2A),	// 3 bit
	
	.sel1In0		(),
	.sel1In1		(),
	.sel1In2		(),
	.sel1In3		(),
	.sel1In4		(),
	
	.sel2In0		(),
	.sel2In1		(),
	.sel2In2		(),
	.sel2In3		(),
	.sel2In4		(),
	.sel2In5		(),
	.sel2In6		(),
	.sel2In7		(),
	
	.outV			()
);


wire signed [47:0] outA;
wire signed [47:0] outB;
wire signed [48:0] sumAB    = { outA[47], outA} + { outB[47], outB};
wire signed [49:0] totalSum = {sumAB[48],sumAB} +       accumulator;
reg  signed [49:0] accumulator;
wire        [31:0] fullvalueOut = clippedA;
wire        [15:0] lowValueOut	= fullvalueOut[15:0];
 
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
wire [31:0] clippedA;
wire [15:0] clampB;
wire [ 7:0]	clampC;
wire [15:0] clampD;
wire [10:0]	clampG;
wire [12:0]	clampH;

GTEOverflowFLAGS GTEFlagInst(
	.v			(totalSum),
	.sf			(gteSF),
	.lm			(gteLM),
	.forceSF_BFlag(gteForceSF_B),
	.AxPos		(AxPos),
	.AxNeg		(AxNeg),
	.FPos		(FPos),
	.FNeg		(FNeg),
	.G			(G),
	.H			(H),
	.B			(B),
	.C			(C),
	.D			(D),
	
	.OutA		(clippedA),
	.OutB		(clampB),
	.OutC		(clampC),
	.OutD		(clampD),
	.OutG		(clampG),
	.OutH		(clampH)
);

always @(posedge i_clk)
begin
	if (gteResetStatus) begin
		regStatus = 19'd0;
	end else begin
		// Implemented as sticky flag -> write only if 1.
		if (AxPos & gteFlagMask[14]) regStatus[18] = AxPos;
		if (AxPos & gteFlagMask[13]) regStatus[17] = AxPos;
		if (AxPos & gteFlagMask[12]) regStatus[16] = AxPos;
		if (AxNeg & gteFlagMask[14]) regStatus[15] = AxNeg;
		if (AxNeg & gteFlagMask[13]) regStatus[14] = AxNeg;
		if (AxNeg & gteFlagMask[12]) regStatus[13] = AxNeg;
		if (B     & gteFlagMask[11]) regStatus[12] = B;
		if (B     & gteFlagMask[10]) regStatus[11] = B;
		if (B     & gteFlagMask[ 9]) regStatus[10] = B;
		if (C     & gteFlagMask[ 8]) regStatus[ 9] = C;
		if (C     & gteFlagMask[ 7]) regStatus[ 8] = C;
		if (C     & gteFlagMask[ 6]) regStatus[ 7] = C;
		if (D     & gteFlagMask[ 5]) regStatus[ 6] = D;
		if (DivOvr& gteFlagMask[ 4]) regStatus[ 5] = DivOvr;
		if (FPos  & gteFlagMask[ 3]) regStatus[ 4] = FPos;
		if (FNeg  & gteFlagMask[ 3]) regStatus[ 3] = FNeg;
		if (G     & gteFlagMask[ 2]) regStatus[ 2] = G;
		if (G     & gteFlagMask[ 1]) regStatus[ 1] = G;
		if (H     & gteFlagMask[ 0]) regStatus[ 0] = H;
	end
end 
// ----------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------
//   FILE REGISTERS
//
//   3x 32 Bit DATA FILE REGISTERS. (DataA, DataB, DataC) all DUAL PORT
//   2x 32 Bit CTRL FILE REGISTERS. (CTRLA, CTRLB, CTRLC, CTRLD) all DUAL PORT
//
//   CPU can read (from A) / write (same value on both A&B) from it.
//   When CPU does not access, parallel reading is possible from
//   microcode setup.
// ----------------------------------------------------------------------------------------------
wire [31:0] outDataA,outDataB,outDataC;
wire [31:0] outCTRLA,outCTRLB,outCTRLC,outCTRLD;

wire		cpuWData	 = i_WritReg & (!i_regID[5]);	// CPU Write and Register is 31.. 0 
wire		cpuWCTRL	 = i_WritReg & ( i_regID[5]);	// CPU Write and Register is 63..32

wire [31:0] inData		 = i_WritReg ? i_dataIn : vDATA;
wire [31:0] inCTRL		 = i_dataIn; // Only CPU can write to the registers.
// ----------------------------------------------------------------------------------------------------------------------------------
wire		readDataA	 = i_ReadReg ? (!i_regID[5]): !i_WritReg;
wire  [4:0] readAdrDataA = i_ReadReg ? i_regID[4:0] : gteReadAdrDataA;					// MICROCODE:[DATA File A READ]
wire  [4:0] readAdrDataB =                            gteReadAdrDataB;					// MICROCODE:[DATA File B READ]
wire		readCTRLA	 = i_ReadReg ?   i_regID[5] : !i_WritReg;
wire  [4:0] readAdrCTRLA = i_ReadReg ? i_regID[4:0] : gteReadAdrCtrlA;					// MICROCODE:[CTRL File A READ]
wire  [4:0] readAdrCTRLB =                            gteReadAdrCtrlB;					// MICROCODE:[CTRL File B READ]

wire		readDataB	 = !i_WritReg; // Avoid reading when CPU write.
wire		writeData	 = cpuWData  | gteWriteToDataFile;								// MICROCODE:[DATA WRITE]
wire  [4:0]	writeAdrData = cpuWData  ? i_regID[4:0] : gteWriteAdrData;					// MICROCODE:[DATA ADR WRITE]
wire		readCTRLB	 = !i_WritReg; // Avoid reading when CPU write.
wire		writeCTRL	 = cpuWCTRL  | gteWriteToCtrlFile;								// MICROCODE:[CTRL WRITE]
wire  [4:0]	writeAdrCTRL = cpuWCTRL  ? i_regID[4:0] : gteWriteAdrCtrl;					// MICROCODE:[CTRL ADR WRITE]

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

FileReg instDATA_C(
	.clk	(i_clk			),
	.read	(readDataC		), .readAdr (readAdrDataC	), .outData(outDataC	),	// Read Side
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

FileReg instCTRL_C(
	.clk	(i_clk			),
	.read	(readCTRLC		), .readAdr (readAdrCTRLC	), .outData(outCTRLC	),	// Read Side
	.write	(writeCTRL		), .writeAdr(writeAdrCTRL	), .inData (inCTRL		)	// Write Side
);

FileReg instCTRL_D(
	.clk	(i_clk			),
	.read	(readCTRLD		), .readAdr (readAdrCTRLD	), .outData(outCTRLD	),	// Read Side
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
wire rExt  = (i_regID==CT____R33) 
		   | (i_regID==CT____L33)
		   | (i_regID==CT____LB3)			   
		   | (i_regID==DATA__VZ0)
		   | (i_regID==DATA__VZ1)
		   | (i_regID==DATA__VZ2)
		   |((i_regID>=DATA__IR0) && (i_regID<=DATA__IR3))
		   ; // Copy sign = 1
		   
wire rZero =((i_regID>=CT______H) && (i_regID<=CT___ZSF4)) 
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
reg [15:0] IR0  ,IR1  ,IR2  ,IR3, IRShadow1, IRShadow2;
reg [31:0] CRGB0,CRGB1,CRGB2;
reg [ 5:0] regCntLead10LZCS;

// ---- FIFOs ------------------------------------------------------
// From CPU write or internal GTE write.



// Those THREE wires are identical to dataPath16 :
/*
	All clamped values written to custom register handled correctly.
 */
wire [15:0] dataPathIR123 = i_WritReg ? i_dataIn[15: 0] : clampB;
wire [15:0] dataPathIR0   = i_WritReg ? i_dataIn[15: 0] : { 3'b000, clampH };
wire [15:0] dataPathZ3    = i_WritReg ? i_dataIn[15: 0] : clampD;
wire [ 7:0] colorWrValue  = clampC;

wire [15:0] extClampG     = { {5{clampG[10]}}, clampG };
wire [15:0] dataPathSY	  = i_WritReg ? i_dataIn[31:16] : extClampG;
wire [15:0] dataPathSX	  = i_WritReg ? i_dataIn[15: 0] : extClampG;

// Use when CPU write only.
wire [2:0] cpuWrtSXY;
wire [2:0] cpuWrtCRGB;
wire [3:0] cpuWrtSZ;
wire [3:0] cpuWrtIR;
// No microcode, only CPU can write directly to FIFO registers without shift.

assign cpuWrtSXY [0]	= (i_WritReg && accSXY0); 
assign cpuWrtSXY [1]	= (i_WritReg && accSXY1);
assign cpuWrtSXY [2]	= (i_WritReg && accSXY2);

assign cpuWrtCRGB[0]	= (i_WritReg && accCRGB0);
assign cpuWrtCRGB[1]	= (i_WritReg && accCRGB1);
assign cpuWrtCRGB[2]	= (i_WritReg && accCRGB2);	/*TODO:CPU WRITE DOES FIFO OR NOT, ONLY GTE INTERNAL ?*/

assign cpuWrtSZ[0]		= (i_WritReg && accSZ0);
assign cpuWrtSZ[1]		= (i_WritReg && accSZ1);
assign cpuWrtSZ[2]		= (i_WritReg && accSZ2);
assign cpuWrtSZ[3]		= (i_WritReg && accSZ3);

assign cpuWrtIR[0]		= (i_WritReg && accIR0);
assign cpuWrtIR[1]		= (i_WritReg && accIR1);
assign cpuWrtIR[2]		= (i_WritReg && accIR2);
assign cpuWrtIR[3]		= (i_WritReg && accIR3);

wire   writeCode		= (i_WritReg && (i_regID == DATA_RGBC));
reg [7:0] codeReg;

wire   cpuWFifoSPXY		= (i_WritReg && (i_regID == DATA_SXYP)); // TODO : is CPU Writing to SPXY registers ?
wire   wrtFSPX          = cpuWFifoSPXY | gteWrtSPX;	// Write FIFO from CPU or GTE.
wire   wrtFSPY          = cpuWFifoSPXY | gteWrtSPY;	// Write FIFO from CPU or GTE.

always @(posedge i_clk)
begin
	// SX Fifo
	if (wrtFSPX | cpuWrtSXY[0]) SX0 = wrtFSPX ? SX1 : i_dataIn[15: 0];
	if (wrtFSPX | cpuWrtSXY[1]) SX1 = wrtFSPX ? SX2 : i_dataIn[15: 0];
	if (wrtFSPX | cpuWrtSXY[2]) SX2 = dataPathSX;
	// SY Fifo
	if (wrtFSPY | cpuWrtSXY[0]) SY0 = wrtFSPY ? SY1 : i_dataIn[31:16];
	if (wrtFSPY | cpuWrtSXY[1]) SY1 = wrtFSPY ? SY2 : i_dataIn[31:16];
	if (wrtFSPY | cpuWrtSXY[2]) SY2 = dataPathSY;
	// SZ Fifo
	if (gteWrtSZ3 |  cpuWrtSZ[0]) SZ0 = gteWrtSZ3  ? SZ1 : i_dataIn[15: 0];
	if (gteWrtSZ3 |  cpuWrtSZ[1]) SZ1 = gteWrtSZ3  ? SZ2 : i_dataIn[15: 0];
	if (gteWrtSZ3 |  cpuWrtSZ[2]) SZ2 = gteWrtSZ3  ? SZ3 : i_dataIn[15: 0];
	if (gteWrtSZ3 |  cpuWrtSZ[3]) SZ3 = dataPathZ3;
	
	// R Fifo
	if (gtePshR  | cpuWrtCRGB[0]) CRGB0[ 7: 0] = gtePshR ? CRGB1[ 7: 0] : i_dataIn[ 7: 0]; // R
	if (gtePshR  | cpuWrtCRGB[1]) CRGB1[ 7: 0] = gtePshR ? CRGB2[ 7: 0] : i_dataIn[ 7: 0]; // R
	if (gtePshR  | cpuWrtCRGB[2]) CRGB2[ 7: 0] = gtePshR ? colorWrValue : i_dataIn[ 7: 0]; // R
	
	// G Fifo
	if (gtePshG  | cpuWrtCRGB[0]) CRGB0[15: 8] = gtePshG ? CRGB1[15: 8] : i_dataIn[15: 8]; // G
	if (gtePshG  | cpuWrtCRGB[1]) CRGB1[15: 8] = gtePshG ? CRGB2[15: 8] : i_dataIn[15: 8]; // G
	if (gtePshG  | cpuWrtCRGB[2]) CRGB2[15: 8] = gtePshG ? colorWrValue : i_dataIn[15: 8]; // G
	
	// B Fifo
	if (gtePshB  | cpuWrtCRGB[0]) CRGB0[23:16] = gtePshB ? CRGB1[23:16] : i_dataIn[23:16]; // B
	if (gtePshB  | cpuWrtCRGB[1]) CRGB1[23:16] = gtePshB ? CRGB2[23:16] : i_dataIn[23:16]; // B
	if (gtePshB  | cpuWrtCRGB[2]) CRGB2[23:16] = gtePshB ? colorWrValue : i_dataIn[23:16]; // B
	
	// Code Fifo
	if (gtePshC  | cpuWrtCRGB[0]) CRGB0[31:24] = gtePshC ? CRGB1[31:24] : i_dataIn[31:24]; // Code
	if (gtePshC  | cpuWrtCRGB[1]) CRGB1[31:24] = gtePshC ? CRGB2[31:24] : i_dataIn[31:24]; // Code
	if (gtePshC  | cpuWrtCRGB[2]) CRGB2[31:24] = gtePshC ? codeReg      : i_dataIn[31:24]; // Code
	
	// Cache codeReg
	if (writeCode) codeReg = i_dataIn[31:24];
	
	// IR0~IR3 Write
	if (cpuWrtIR[0] | gteWrtIR[0]     			  )	IR0 = dataPathIR0;
	if (cpuWrtIR[1] | gteWrtIR[1] | gteCpyShadowIR)	IR1 = gteCpyShadowIR ? IRShadow1 : dataPathIR123;
	if (cpuWrtIR[2] | gteWrtIR[2] | gteCpyShadowIR)	IR2 = gteCpyShadowIR ? IRShadow2 : dataPathIR123;
	if (cpuWrtIR[3] | gteWrtIR[3]                 )	IR3 = dataPathIR123;
	
	if (gteWriteShadowIR) begin
		// 2 Register fifo...
		IRShadow1 = IRShadow2;
		IRShadow2 = dataPathIR123;
	end
	
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
