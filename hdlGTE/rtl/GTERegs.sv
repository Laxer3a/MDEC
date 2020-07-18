// -----------------------------------------------------------
//   Constants & Struct for feel good code.
// -----------------------------------------------------------
`include "GTEDefine.hv"

module GTERegs (
	input         i_clk,
	input         i_nRst,


	input		  i_loadInstr,

	// Temp stuff
	input  gteWriteBack i_wb,
	input  gteCtrl  gteWR,
	output SgteREG  gteREG,
	
	//   GTE PORT
	input  E_REG  i_regID,
	input         i_WritReg,
//	input         i_ReadReg,
	input  [31:0] i_dataIn,
	output [31:0] o_dataOut
);

// ----------------------------------------------------------------------------------------------
//   [REGISTERS] + Management.
// ----------------------------------------------------------------------------------------------

// Special Registers with GTE write back. + FIFO Style stuff.
COLOR CRGB0,CRGB1,CRGB2;
reg signed [15:0] SX0  ,SX1  ,SX2;
reg signed [15:0] SY0  ,SY1  ,SY2;
reg signed [15:0] SZ0  ,SZ1  ,SZ2 , SZ3;

// Write back from GTE & CPU
reg signed [15:0] IR0,IR1,IR2,IR3;
reg signed [31:0] MAC0,MAC1,MAC2,MAC3;
reg signed [15:0] OTZ;

// CPU Writable only registers.
COLOR CRGB;
reg signed [15:0] R11,R12,R13,R21,R22,R23,R31,R32,R33;
reg signed [15:0] L11,L12,L13,L21,L22,L23,L31,L32,L33;
reg signed [15:0] LR1,LR2,LR3,LG1,LG2,LG3,LB1,LB2,LB3;
reg signed [31:0] TRX,TRY,TRZ,RBK,GBK,BBK,RFC,GFC,BFC,RES1;
reg signed [15:0] H,DQA,ZSF3,ZSF4;
reg signed [31:0] OFX,OFY,DQB,REG_lzcs;

reg signed [15:0] VX0,VY0,VZ0,VX1,VY1,VZ1,VX2,VY2,VZ2;
/*
--  31   Error Flag (Bit30..23, and 18..13 ORed together) (Read only)
-------------------------------------------------------------------------------
18  30   MAC1 Result larger than 43 bits and positive
17  29   MAC2 Result larger than 43 bits and positive
16  28   MAC3 Result larger than 43 bits and positive
15  27   MAC1 Result larger than 43 bits and negative
14  26   MAC2 Result larger than 43 bits and negative
13  25   MAC3 Result larger than 43 bits and negative
12  24   IR1 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
11  23   IR2 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
-------------------------------------------------------------------------------
10  22   IR3 saturated to +0000h..+7FFFh (lm=1) or to -8000h..+7FFFh (lm=0)
 9  21   Color-FIFO-R saturated to +00h..+FFh
 8  20   Color-FIFO-G saturated to +00h..+FFh
 7  19   Color-FIFO-B saturated to +00h..+FFh
-------------------------------------------------------------------------------
 6  18   SZ3 or OTZ saturated to +0000h..+FFFFh
 5  17   Divide overflow. RTPS/RTPT division result saturated to max=1FFFFh
 4  16   MAC0 Result larger than 31 bits and positive
 3  15   MAC0 Result larger than 31 bits and negative
 2  14   SX2 saturated to -0400h..+03FFh
 1  13   SY2 saturated to -0400h..+03FFh
-------------------------------------------------------------------------------
 0  12   IR0 saturated to +0000h..+1000h
 */
reg        [18:0] FLAGS;
wire   FLAG_31 = (|FLAGS[18:11]) | (|FLAGS[6:1]); // 30~23 | 18~13

// ----------------------------------------------------------------------------------------------
//   Export for Compute Path
// ----------------------------------------------------------------------------------------------
assign gteREG.VX0 = VX0;
assign gteREG.VY0 = VY0;
assign gteREG.VZ0 = VZ0;

assign gteREG.VX1 = VX1;
assign gteREG.VY1 = VY1;
assign gteREG.VZ1 = VZ1;

assign gteREG.VX2 = VX2;
assign gteREG.VY2 = VY2;
assign gteREG.VZ2 = VZ2;

assign gteREG.IR0 = IR0;
assign gteREG.IR1 = IR1;
assign gteREG.IR2 = IR2;
assign gteREG.IR3 = IR3;

assign gteREG.MAC0 = MAC0;
assign gteREG.MAC1 = MAC1;
assign gteREG.MAC2 = MAC2;
assign gteREG.MAC3 = MAC3;

assign gteREG.R11 = R11; assign gteREG.L11 = L11; assign gteREG.LR1 = LR1;
assign gteREG.R12 = R12; assign gteREG.L12 = L12; assign gteREG.LR2 = LR2;
assign gteREG.R13 = R13; assign gteREG.L13 = L13; assign gteREG.LR3 = LR3;
assign gteREG.R21 = R21; assign gteREG.L21 = L21; assign gteREG.LG1 = LG1;
assign gteREG.R22 = R22; assign gteREG.L22 = L22; assign gteREG.LG2 = LG2;
assign gteREG.R23 = R23; assign gteREG.L23 = L23; assign gteREG.LG3 = LG3;
assign gteREG.R31 = R31; assign gteREG.L31 = L31; assign gteREG.LB1 = LB1;
assign gteREG.R32 = R32; assign gteREG.L32 = L32; assign gteREG.LB2 = LB2;
assign gteREG.R33 = R33; assign gteREG.L33 = L33; assign gteREG.LB3 = LB3;

assign gteREG.TRX = TRX; assign gteREG.TRY = TRY; assign gteREG.TRZ = TRZ;
assign gteREG.RBK = RBK; assign gteREG.GBK = GBK; assign gteREG.BBK = BBK;
assign gteREG.RFC = RFC; assign gteREG.GFC = GFC; assign gteREG.BFC = BFC;

assign gteREG.CRGB0 = CRGB0;
assign gteREG.CRGB1 = CRGB1;
assign gteREG.CRGB2 = CRGB2;
assign gteREG.CRGB  = CRGB ;

assign gteREG.SX0   = SX0; assign gteREG.SX1   = SX1; assign gteREG.SX2   = SX2;
assign gteREG.SY0   = SY0; assign gteREG.SY1   = SY1; assign gteREG.SY2   = SY2;
assign gteREG.SZ0   = SZ0; assign gteREG.SZ1   = SZ1; assign gteREG.SZ2   = SZ2; assign gteREG.SZ3 = SZ3;

assign gteREG.OTZ   = OTZ;
assign gteREG.H     = H;
assign gteREG.DQA   = DQA;
assign gteREG.ZSF3  = ZSF3;
assign gteREG.ZSF4  = ZSF4;

assign gteREG.OFX   = OFX;
assign gteREG.OFY   = OFY;
assign gteREG.DQB   = DQB;

// ----------------------------------------------------------------------------------------------
// ---- COLOR FIFO  -----------------------------------------------------------------------------
// ----------------------------------------------------------------------------------------------
//   From CPU write or internal GTE write.
// [Read / Write from CPU]

wire   accCRGB0= (i_regID == DR_RGB0);
wire   accCRGB1= (i_regID == DR_RGB1);
wire   accCRGB2= (i_regID == DR_RGB2);
wire   accCRGB = (i_regID == DR_RGBC);

wire [3:0] cpuWrtCRGB	= {4{i_WritReg}} & { accCRGB, accCRGB2, accCRGB1 , accCRGB0 };
// ---------------------------------------------------------------
// CPU can directly write to 0/1/2 but no FIFO.
// GTE can only push to the FIFO instead when writing.
// ---------------------------------------------------------------
always @(posedge i_clk)
begin
	if (i_nRst == 1'b0) begin
		CRGB0.r = 8'd0; CRGB1.r = 8'd0; CRGB2.r = 8'd0; CRGB.r = 8'd0;
		CRGB0.g = 8'd0; CRGB1.g = 8'd0; CRGB2.g = 8'd0; CRGB.g = 8'd0;
		CRGB0.b = 8'd0; CRGB1.b = 8'd0; CRGB2.b = 8'd0; CRGB.b = 8'd0;
		CRGB0.c = 8'd0; CRGB1.c = 8'd0; CRGB2.c = 8'd0; CRGB.c = 8'd0;
	end else begin
		// R Fifo
		if (i_wb.pushR | cpuWrtCRGB[0]) CRGB0.r = i_wb.pushR ? CRGB1.r   : i_dataIn[ 7: 0]; // R
		if (i_wb.pushR | cpuWrtCRGB[1]) CRGB1.r = i_wb.pushR ? CRGB2.r   : i_dataIn[ 7: 0]; // R
		if (i_wb.pushR | cpuWrtCRGB[2]) CRGB2.r = i_wb.pushR ? gteWR.colV: i_dataIn[ 7: 0]; // R
		// G Fifo
		if (i_wb.pushG | cpuWrtCRGB[0]) CRGB0.g = i_wb.pushG ? CRGB1.g   : i_dataIn[15: 8]; // G
		if (i_wb.pushG | cpuWrtCRGB[1]) CRGB1.g = i_wb.pushG ? CRGB2.g   : i_dataIn[15: 8]; // G
		if (i_wb.pushG | cpuWrtCRGB[2]) CRGB2.g = i_wb.pushG ? gteWR.colV: i_dataIn[15: 8]; // G
		// B    Fifo
		// Code Fifo (Move on BLUE)
		if (i_wb.pushB | cpuWrtCRGB[0]) CRGB0.b = i_wb.pushB ? CRGB1.b   : i_dataIn[23:16]; // B
		if (i_wb.pushB | cpuWrtCRGB[1]) CRGB1.b = i_wb.pushB ? CRGB2.b   : i_dataIn[23:16]; // B
		if (i_wb.pushB | cpuWrtCRGB[2]) CRGB2.b = i_wb.pushB ? gteWR.colV: i_dataIn[23:16]; // B
		if (i_wb.pushB | cpuWrtCRGB[0]) CRGB0.c = i_wb.pushB ? CRGB1.c   : i_dataIn[31:24]; // Code
		if (i_wb.pushB | cpuWrtCRGB[1]) CRGB1.c = i_wb.pushB ? CRGB2.c   : i_dataIn[31:24]; // Code
		if (i_wb.pushB | cpuWrtCRGB[2]) CRGB2.c = i_wb.pushB ? CRGB.c    : i_dataIn[31:24]; // Code
		
		// Cache codeReg
		if (cpuWrtCRGB[3]) begin
			CRGB.r = i_dataIn[ 7: 0];
			CRGB.g = i_dataIn[15: 8];
			CRGB.b = i_dataIn[23:16];
			CRGB.c = i_dataIn[31:24];
		end
	end
end
// ----------------------------------------------------------------------------------------------
// ---- XYZ FIFO    -----------------------------------------------------------------------------
// ----------------------------------------------------------------------------------------------
wire   accSXY0 = (i_regID == DR_SXY0);
wire   accSXY1 = (i_regID == DR_SXY1);
wire   accSXY2 = (i_regID == DR_SXY2);
wire   accSXYP = (i_regID == DR_SXYP);
wire   accSZ0  = (i_regID == DR_SZ0_);
wire   accSZ1  = (i_regID == DR_SZ1_);
wire   accSZ2  = (i_regID == DR_SZ2_);
wire   accSZP  = (i_regID == DR_SZP_);

wire [3:0] cpuWrtSXY	= {4{i_WritReg}} & { accSXYP, accSXY2, accSXY1, accSXY0 };
wire [3:0] cpuWrtSZ		= {4{i_WritReg}} & {  accSZP,  accSZ2,  accSZ1,  accSZ0 };

// FIFO Write, by CPU or GPU.
wire       wrtFSPX      = cpuWrtSXY[3] | i_wb.pushX;	// Write FIFO from CPU or GTE.
wire       wrtFSPY      = cpuWrtSXY[3] | i_wb.pushY;	// Write FIFO from CPU or GTE.
wire       wrtFSPZ      = i_wb.pushZ;					// Write FIFO from GTE ONLY.

// Data Value = CPU or GTE write ?
wire [15:0] dataPathSY	= i_WritReg ? i_dataIn[31:16] : gteWR.XYV;
wire [15:0] dataPathSX 	= i_WritReg ? i_dataIn[15: 0] : gteWR.XYV;
wire [15:0] dataPathSZ	= i_WritReg ? i_dataIn[15: 0] : gteWR.OTZV;

always @(posedge i_clk)
begin
	if (i_nRst == 1'b0) begin
		SX0 = 16'd0; SX1 = 16'd0; SX2 = 16'd0;
		SY0 = 16'd0; SY1 = 16'd0; SY2 = 16'd0;
		SZ0 = 16'd0; SZ1 = 16'd0; SZ2 = 16'd0; SZ3 = 16'd0;
	end else begin
		// SX Fifo
		if (wrtFSPX | cpuWrtSXY[0]) SX0 = wrtFSPX ? SX1 : i_dataIn[15: 0];
		if (wrtFSPX | cpuWrtSXY[1]) SX1 = wrtFSPX ? SX2 : i_dataIn[15: 0];
		if (wrtFSPX | cpuWrtSXY[2]) SX2 = dataPathSX;
		// SY Fifo
		if (wrtFSPY | cpuWrtSXY[0]) SY0 = wrtFSPY ? SY1 : i_dataIn[31:16];
		if (wrtFSPY | cpuWrtSXY[1]) SY1 = wrtFSPY ? SY2 : i_dataIn[31:16];
		if (wrtFSPY | cpuWrtSXY[2]) SY2 = dataPathSY;
		// SZ Fifo : No$ spec wrong : GTE ONLY FIFO. Not CPU SIDE !
		if (wrtFSPZ | cpuWrtSZ [0]) SZ0 = wrtFSPZ ? SZ1 : i_dataIn[15: 0];
		if (wrtFSPZ | cpuWrtSZ [1]) SZ1 = wrtFSPZ ? SZ2 : i_dataIn[15: 0];
		if (wrtFSPZ | cpuWrtSZ [2]) SZ2 = wrtFSPZ ? SZ3 : i_dataIn[15: 0];
		if (wrtFSPZ | cpuWrtSZ [3]) SZ3 = dataPathSZ;
	end
end

// ----------------------------------------------------------------------------------------------
// ---- CPU & GTE WRITE REGISTERS ---------------------------------------------------------------
// ----------------------------------------------------------------------------------------------
wire wrIRGB = i_WritReg & (i_regID == DR_IRGB);
wire [15:0] R16 = { 4'd0 , i_dataIn[ 4: 0] , 7'd0 };
wire [15:0] G16 = { 4'd0 , i_dataIn[ 9: 5] , 7'd0 };
wire [15:0] B16 = { 4'd0 , i_dataIn[14:10] , 7'd0 };

always @(posedge i_clk)
begin
	if (i_nRst == 1'b0) begin
		OTZ = 16'd0;
		IR0 = 16'd0; IR1 = 16'd0; IR2 = 16'd0; IR3 = 16'd0;
		MAC0= 32'd0; MAC1= 32'd0; MAC2= 32'd0; MAC3= 32'd0;
		FLAGS = 19'd0;
	end else begin
		// OTZ
		if (((i_regID == DR_OTZ_) & i_WritReg) | i_wb.wrOTZ  ) OTZ = i_wb.wrOTZ   ? gteWR.OTZV : i_dataIn[15: 0];
		// IRO,IR1,IR2,IR3
		if (((i_regID == DR_IR0_) & i_WritReg) | i_wb.wrIR[0]) IR0 = i_wb.wrIR[0] ? gteWR.IR0  : i_dataIn[15: 0];
		if (((i_regID == DR_IR1_) & i_WritReg) | wrIRGB | i_wb.wrIR[1]) begin
			if (wrIRGB) begin
				IR1 = R16;
			end else begin
				IR1 = i_wb.wrIR[1] ? gteWR.IR13 : i_dataIn[15: 0];
			end
		end
		if (((i_regID == DR_IR2_) & i_WritReg) | wrIRGB | i_wb.wrIR[2]) begin
			if (wrIRGB) begin
				IR2 = G16;
			end else begin
				IR2 = i_wb.wrIR[2] ? gteWR.IR13 : i_dataIn[15: 0];
			end
		end
		if (((i_regID == DR_IR3_) & i_WritReg) | wrIRGB | i_wb.wrIR[3]) begin
			if (wrIRGB) begin
				IR3 = B16;
			end else begin
				IR3 = i_wb.wrIR[3] ? gteWR.IR13 : i_dataIn[15: 0];
			end
		end
		// MAC0,MAC1,MAC2,MAC3
		if (((i_regID == DR_MAC0) & i_WritReg) | i_wb.wrMAC[0]) MAC0 = i_wb.wrMAC[0] ? gteWR.MAC0  : i_dataIn;
		if (((i_regID == DR_MAC1) & i_WritReg) | i_wb.wrMAC[1]) MAC1 = i_wb.wrMAC[1] ? gteWR.MAC13 : i_dataIn;
		if (((i_regID == DR_MAC2) & i_WritReg) | i_wb.wrMAC[2]) MAC2 = i_wb.wrMAC[2] ? gteWR.MAC13 : i_dataIn;
		if (((i_regID == DR_MAC3) & i_WritReg) | i_wb.wrMAC[3]) MAC3 = i_wb.wrMAC[3] ? gteWR.MAC13 : i_dataIn;
		
		if ((i_regID == CR_FLAGS___) & i_WritReg) begin
			FLAGS = i_dataIn[30:12];
		end else begin
			if (i_loadInstr) begin
				FLAGS = gteWR.updateFlags;
			end else begin
				FLAGS = FLAGS | gteWR.updateFlags; 
			end
		end
	end
end

// ----------------------------------------------------------------------------------------------
// ---- CPU WRITE ONLY REGISTERS ----------------------------------------------------------------
// ----------------------------------------------------------------------------------------------

always @(posedge i_clk)
begin
	if (i_nRst == 1'b0) begin
		R11 = 16'd0; R12 = 16'd0; R13 = 16'd0;
		R21 = 16'd0; R22 = 16'd0; R23 = 16'd0;
		R31 = 16'd0; R32 = 16'd0; R33 = 16'd0;
		L11 = 16'd0; L12 = 16'd0; L13 = 16'd0;
		L21 = 16'd0; L22 = 16'd0; L23 = 16'd0;
		L31 = 16'd0; L32 = 16'd0; L33 = 16'd0;
		LR1 = 16'd0; LR2 = 16'd0; LR3 = 16'd0;
		LG1 = 16'd0; LG2 = 16'd0; LG3 = 16'd0;
		LB1 = 16'd0; LB2 = 16'd0; LB3 = 16'd0;
				
		H   = 16'd0; DQA = 16'd0;
		ZSF3= 16'd0; ZSF4= 16'd0;
		
		TRX = 32'd0; TRY = 32'd0; TRZ = 32'd0;
		RBK = 32'd0; GBK = 32'd0; BBK = 32'd0;
		RFC = 32'd0; GFC = 32'd0; BFC = 32'd0;
		
		OFX = 32'd0; OFY = 32'd0;
		DQB = 32'd0;
		
		RES1 = 32'd0;
		REG_lzcs = 32'd0;
		
		VY0 = 16'd0; VX0 = 16'd0; VZ0 = 16'd0;
		VY1 = 16'd0; VX1 = 16'd0; VZ1 = 16'd0;
		VY2 = 16'd0; VX2 = 16'd0; VZ2 = 16'd0;
		
	end else begin
		// VX0,VY0,VZ0
		if ((i_regID == DR_VXY0) & i_WritReg) VY0 = i_dataIn[31:16];
		if ((i_regID == DR_VXY0) & i_WritReg) VX0 = i_dataIn[15: 0];
		if ((i_regID == DR_VZ0_) & i_WritReg) VZ0 = i_dataIn[15: 0];
		// VX1,VY1,VZ1
		if ((i_regID == DR_VXY1) & i_WritReg) VY1 = i_dataIn[31:16];
		if ((i_regID == DR_VXY1) & i_WritReg) VX1 = i_dataIn[15: 0];
		if ((i_regID == DR_VZ1_) & i_WritReg) VZ1 = i_dataIn[15: 0];
		// VX2,VY2,VZ2
		if ((i_regID == DR_VXY2) & i_WritReg) VY2 = i_dataIn[31:16];
		if ((i_regID == DR_VXY2) & i_WritReg) VX2 = i_dataIn[15: 0];
		if ((i_regID == DR_VZ2_) & i_WritReg) VZ2 = i_dataIn[15: 0];
		// ------------------------------------------------------
		if ((i_regID == CR_RT11RT12) & i_WritReg) begin
			R12 = i_dataIn[31:16];
			R11 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_RT13RT21) & i_WritReg) begin
			R21 = i_dataIn[31:16];
			R13 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_RT22RT23) & i_WritReg) begin
			R23 = i_dataIn[31:16];
			R22 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_RT31RT32) & i_WritReg) begin
			R32 = i_dataIn[31:16];
			R31 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_RT33____) & i_WritReg) begin
			R33 = i_dataIn[15: 0];
		end
		// ------------------------------------------------------
		if ((i_regID == CR_L11L12__) & i_WritReg) begin
			L12 = i_dataIn[31:16];
			L11 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_L13L21__) & i_WritReg) begin
			L21 = i_dataIn[31:16];
			L13 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_L22L23__) & i_WritReg) begin
			L23 = i_dataIn[31:16];
			L22 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_L31L32__) & i_WritReg) begin
			L32 = i_dataIn[31:16];
			L31 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_L33_____) & i_WritReg) begin
			L33 = i_dataIn[15: 0];
		end
		// ------------------------------------------------------
		if ((i_regID == CR_LR1LR2__) & i_WritReg) begin
			LR2 = i_dataIn[31:16];
			LR1 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_LR3LG1__) & i_WritReg) begin
			LG1 = i_dataIn[31:16];
			LR3 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_LG2LG3__) & i_WritReg) begin
			LG3 = i_dataIn[31:16];
			LG2 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_LB1LB2__) & i_WritReg) begin
			LB2 = i_dataIn[31:16];
			LB1 = i_dataIn[15: 0];
		end
		if ((i_regID == CR_LB3_____) & i_WritReg) begin
			LB3 = i_dataIn[15: 0];
		end
		// ------------------------------------------------------
		if ((i_regID == CR_H_______) & i_WritReg) H   = i_dataIn[15:0];
		if ((i_regID == CR_DQA_____) & i_WritReg) DQA = i_dataIn[15:0];
		if ((i_regID == CR_ZSF3____) & i_WritReg) ZSF3= i_dataIn[15:0];
		if ((i_regID == CR_ZSF4____) & i_WritReg) ZSF4= i_dataIn[15:0];
		
		if ((i_regID == CR_TRX_____) & i_WritReg) TRX = i_dataIn;
		if ((i_regID == CR_TRY_____) & i_WritReg) TRY = i_dataIn;
		if ((i_regID == CR_TRZ_____) & i_WritReg) TRZ = i_dataIn;
		if ((i_regID == CR_RBK_____) & i_WritReg) RBK = i_dataIn;
		if ((i_regID == CR_GBK_____) & i_WritReg) GBK = i_dataIn;
		if ((i_regID == CR_BBK_____) & i_WritReg) BBK = i_dataIn;
		if ((i_regID == CR_RFC_____) & i_WritReg) RFC = i_dataIn;
		if ((i_regID == CR_GFC_____) & i_WritReg) GFC = i_dataIn;
		if ((i_regID == CR_BFC_____) & i_WritReg) BFC = i_dataIn;
		
		if ((i_regID == CR_OFX_____) & i_WritReg) OFX = i_dataIn;
		if ((i_regID == CR_OFY_____) & i_WritReg) OFY = i_dataIn;
		if ((i_regID == CR_DQB_____) & i_WritReg) DQB = i_dataIn;

		if ((i_regID == DR_RES1    ) & i_WritReg) RES1 = i_dataIn;
		if ((i_regID == DR_LZCS    ) & i_WritReg) REG_lzcs = i_dataIn;
	end
end

wire [5:0] cntLeadInput; // 1..32 Value output
LeadCountS32 instLeadCount(
	.value	(REG_lzcs),
	.result	(cntLeadInput)
);

wire [5:0] pRegID = i_regID; // In case we need pipelining, for now just making the READ back to CPU
reg [31:0] vOut;

wire [4:0] R5,G5,B5;
M16TO5 M16TO5InstR( .i(IR1), .o(R5) );
M16TO5 M16TO5InstG( .i(IR2), .o(G5) );
M16TO5 M16TO5InstB( .i(IR3), .o(B5) );

always @(*)
begin
	if (pRegID[5])
	begin
		case ({1'b1, pRegID[4:0]})
		CR_RT11RT12	: vOut = { R12,R11 };
		CR_RT13RT21	: vOut = { R21,R13 };
		CR_RT22RT23	: vOut = { R23,R22 };
		CR_RT31RT32	: vOut = { R32,R31 };
		
		CR_RT33____	: vOut = {{16{R33[15]}}, R33};
		CR_TRX_____	: vOut = TRX;
		CR_TRY_____	: vOut = TRY;
		CR_TRZ_____	: vOut = TRZ;
		
		CR_L11L12__	: vOut = { L12,L11 };
		CR_L13L21__	: vOut = { L21,L13 };
		CR_L22L23__	: vOut = { L23,L22 };
		CR_L31L32__	: vOut = { L32,L31 };
		
		CR_L33_____	: vOut = {{16{L33[15]}}, L33};
		CR_RBK_____	: vOut = RBK;
		CR_GBK_____	: vOut = GBK;
		CR_BBK_____	: vOut = BBK;
		
		CR_LR1LR2__	: vOut = { LR2,LR1 };
		CR_LR3LG1__	: vOut = { LG1,LR3 };
		CR_LG2LG3__	: vOut = { LG3,LG2 };
		CR_LB1LB2__	: vOut = { LB2,LB1 };
		
		CR_LB3_____	: vOut = {{16{LB3[15]}}, LB3};
		CR_RFC_____	: vOut = RFC;
		CR_GFC_____	: vOut = GFC;
		CR_BFC_____	: vOut = BFC;
		
		CR_OFX_____	: vOut = OFX;
		CR_OFY_____	: vOut = OFY;
		CR_H_______ : vOut = {{16{  H[15]}},   H}; // Bug on purpose : H is unsigned 16 bit but GTE return signed extended to CPU.
		CR_DQA_____	: vOut = {{16{DQA[15]}}, DQA};
		
		CR_DQB_____	: vOut = DQB;
		CR_ZSF3____	: vOut = {{16{ZSF3[15]}},ZSF3};
		CR_ZSF4____	: vOut = {{16{ZSF4[15]}},ZSF4};
		default     : vOut = { FLAG_31, FLAGS, 12'd0 };
		endcase
	end else begin
		case ({1'b0,pRegID[4:0]})
		DR_VXY0	  : vOut = { VY0, VX0 };
		DR_VZ0_   : vOut = {{16{VZ0[15]}}, VZ0};
		DR_VXY1	  : vOut = { VY1, VX1 };
		DR_VZ1_   : vOut = {{16{VZ1[15]}}, VZ1};
		
		DR_VXY2	  : vOut = { VY2, VX2 };
		DR_VZ2_   : vOut = {{16{VZ2[15]}}, VZ2};
		DR_RGBC   : vOut = { CRGB.c , CRGB.b , CRGB.g , CRGB.r  };
		DR_OTZ_	  : vOut = { 16'd0, OTZ };

		DR_IR0_   : vOut = {{16{IR0[15]}}, IR0};
		DR_IR1_   : vOut = {{16{IR1[15]}}, IR1};
		DR_IR2_   : vOut = {{16{IR2[15]}}, IR2};
		DR_IR3_   : vOut = {{16{IR3[15]}}, IR3};
		
		DR_SXY0   : vOut = { SY0, SX0 };
		DR_SXY1   : vOut = { SY1, SX1 };
		DR_SXY2   : vOut = { SY2, SX2 };
		DR_SXYP   : vOut = { SY2, SX2 };

		DR_SZ0_	  : vOut = {{16'd0}, SZ0};
		DR_SZ1_   : vOut = {{16'd0}, SZ1};
		DR_SZ2_	  : vOut = {{16'd0}, SZ2};
		DR_SZP_	  : vOut = {{16'd0}, SZ3};
		
		DR_RGB0   : vOut = { CRGB0.c, CRGB0.b, CRGB0.g, CRGB0.r };
		DR_RGB1   : vOut = { CRGB1.c, CRGB1.b, CRGB1.g, CRGB1.r };
		DR_RGB2   : vOut = { CRGB2.c, CRGB2.b, CRGB2.g, CRGB2.r };
		DR_RES1   : vOut = RES1;
		
		DR_MAC0   : vOut = MAC0;
		DR_MAC1   : vOut = MAC1;
		DR_MAC2   : vOut = MAC2;
		DR_MAC3   : vOut = MAC3;
		
		DR_IRGB   : vOut = { 17'd0, B5, G5, R5 };
		DR_ORGB   : vOut = { 17'd0, B5, G5, R5 };

		DR_LZCS	  : vOut = { REG_lzcs };
		DR_LZCR	  : vOut = { 26'd0, cntLeadInput };
		default   : vOut = 32'd0;
		endcase
	end
end

assign o_dataOut = vOut;

endmodule
