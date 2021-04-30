/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "spu_def.sv"

module spu_ReverbCompute(
	input			i_clk,
	input			i_rst,
	
	input			i_side22Khz,
	input			i_reverbInactive,
	
	input			reg_ReverbEnable,
	
	input	[15:0]	i_reg_mBase,
	input	[17:0]	i_reverb_CounterWord,
	input	[15:0]	i_dataFromRAM,

	input	signed [15:0]	i_lineIn,

	input signed [15:0] dAPF1,
	input signed [15:0] dAPF2,
	input signed [15:0] vIIR,
	input signed [15:0] vCOMB1,

	input signed [15:0] vCOMB2,
	input signed [15:0] vCOMB3,
	input signed [15:0] vCOMB4,
	input signed [15:0] vWALL,

	input signed [15:0] vAPF1,
	input signed [15:0] vAPF2,
	input signed [15:0] mLSAME,
	input signed [15:0] mRSAME,

	input signed [15:0] mLCOMB1,
	input signed [15:0] mRCOMB1,
	input signed [15:0] mLCOMB2,
	input signed [15:0] mRCOMB2,

	input signed [15:0] dLSAME,
	input signed [15:0] dRSAME,
	input signed [15:0] mLDIFF,
	input signed [15:0] mRDIFF,

	input signed [15:0] mLCOMB3,
	input signed [15:0] mRCOMB3,
	input signed [15:0] mLCOMB4,
	input signed [15:0] mRCOMB4,

	input signed [15:0] dLDIFF,
	input signed [15:0] dRDIFF,
	input signed [15:0] mLAPF1,
	input signed [15:0] mRAPF1,

	input signed [15:0] mLAPF2,
	input signed [15:0] mRAPF2,
	input signed [15:0] vLIN,
	input signed [15:0] vRIN,
	
	output 	[17:0]	o_reverbAdr,
	output	[15:0]	o_reverbWriteValue,

	// Control to memory access
	output	[2:0]	o_SPUMemWRSel,
	output			o_SPUMemWRRight,
	output			o_ctrlSendOut
);

// State Machine Control Signals.
reg	[3:0]	sideAReg;
reg	[4:0]	sideBReg;
reg			minus2;
reg	[1:0]	selB;
reg			ctrlSendOut;
reg [2:0]	SPUMemWRSel;
reg			isRight;		// When doing write back CD. Left or Right ?

reg [7:0] reverbCnt;
always @(posedge i_clk)
begin
	if (i_reverbInactive || i_rst) begin
		reverbCnt <= 8'd0;
	end else begin
		reverbCnt <= reverbCnt + 8'd1;
	end
end

reg  signed [15:0] mulA;
reg  signed [15:0] mulB;
wire signed [30:0] resMulAB   = mulA * mulB;
wire signed [15:0] resMulAB16 = resMulAB[30:15];  
reg       accAdd;
reg  signed [15:0] accReverb;
wire signed [15:0] addB       = accAdd ? accReverb : 16'd0;
wire signed [16:0] addC       = addB + resMulAB16;
// [TODO] Clamp addC to 16 bit instead of 17 bits.
wire signed [15:0] clampedAddC = addC[15:0];

always @(posedge i_clk)
begin
	accReverb <= clampedAddC;
end

reg [15:0] adrB;
                   //15->17 bit +   0/-1 Half Word.(-2 byte)
wire [17:0] reverbAdrPreRing = {adrB, 2'd0} + {18{minus2}}; // [Read Memory from Reverb Adr stuff]

ReverbWrapAdr ReverbWrapAdrInst(
	.i_offsetRegister	(reverbAdrPreRing),	// Word Offset.
	.i_baseAdr			(i_reg_mBase),		// x8 byte 16 bit reg.
	.i_offsetCounter	(i_reverb_CounterWord),// Word Offset.
	.o_reverbAdr		(o_reverbAdr)			// Word output absolute adr.
);

// Value to write to the SPU RAM for reverb data bus.
assign o_reverbWriteValue	= accReverb;

wire signed [15:0] negvAPF1	= (~vAPF1) + 16'd1;
wire signed [15:0] negvAPF2	= (~vAPF2) + 16'd1;

always @(*)
begin
	// 4 Bit
	case (sideAReg)
	SA_VWALL:	mulA = vWALL;
	SA_VIIR:	mulA = vIIR;
	SA_ZERO:	mulA = 16'h0;
	SA_ONE:		mulA = 16'h7FFF; // Trick, not 1, but 0.99996948 -> 0.99997
	
	SA_COMB1:	mulA = vCOMB1;
	SA_COMB2:	mulA = vCOMB2;
	SA_COMB3:	mulA = vCOMB3;
	SA_COMB4:	mulA = vCOMB4;
	
	SA_VAPF1:	mulA = vAPF1;
	SA_VAPF2:	mulA = vAPF2;
	SA_NVAPF1:	mulA = negvAPF1;
	SA_NVAPF2:	mulA = negvAPF2;
	SA_VIN:		mulA = i_side22Khz ? vRIN : vLIN;
	default:	mulA = 16'h8000; // -1 // SA_NEG_ONE
	endcase

	//  5 Bit
	case (sideBReg)
	SB_DLSAME:  adrB = dLSAME;
	SB_DRSAME:  adrB = dRSAME;
	SB_MLSAME:  adrB = mLSAME;// -2 variant
	SB_MRSAME:  adrB = mRSAME;// -2 variant
	
	SB_DLDIFF:  adrB = dLDIFF;
	SB_DRDIFF:  adrB = dRDIFF;
	SB_MLDIFF:  adrB = mLDIFF;// -2 variant
	SB_MRDIFF:  adrB = mRDIFF;// -2 variant
	
	SB_MLCOMB1: adrB = mLCOMB1;
	SB_MRCOMB1: adrB = mRCOMB1;
	SB_MLCOMB2: adrB = mLCOMB2;
	SB_MRCOMB2: adrB = mRCOMB2;
	
	SB_MLCOMB3: adrB = mLCOMB3;
	SB_MRCOMB3: adrB = mRCOMB3;
	SB_MLCOMB4: adrB = mLCOMB4;
	SB_MRCOMB4: adrB = mRCOMB4;
	
	SB_MLAPF1_ADPF1: adrB = mLAPF1 - dAPF1;
	SB_MRAPF1_ADPF1: adrB = mRAPF1 - dAPF1;
	SB_MLAPF2_ADPF2: adrB = mLAPF2 - dAPF2;
	SB_MRAPF2_ADPF2: adrB = mRAPF2 - dAPF2;
	
	SB_MLAPF1: adrB = mLAPF1;
	SB_MRAPF1: adrB = mRAPF1;
	SB_MLAPF2: adrB = mLAPF2;
	SB_MRAPF2: adrB = mRAPF2;
	default:   adrB = 16'd0; // SB_FAKEREAD
	endcase

	// [Select Lin/Acc/RamOut]
	case (selB)
	SEL_IN:		mulB = i_lineIn;
	SEL_RAM:	mulB = i_dataFromRAM;
	// Not used, mulA used for sign <= SEL_NRAM:   mulB = (~i_dataInRAM) + 16'd1; // -i_dataInRAM
	default:	mulB = accReverb;
	endcase
end

// alias
wire side22Khz = i_side22Khz;

always @(*) begin
	// Keep data in the reverb loop by default... (Accumulator + mul by zero)
	sideAReg	= SA_ZERO;
	sideBReg	= SB_FAKEREAD;
	minus2		= 0;
	selB		= SEL_ACC;
	accAdd		= 1;
	isRight		= 0;
	ctrlSendOut = 0;

	SPUMemWRSel	= NO_SPU_READ;	// Default : NO READ/WRITE SIGNALS

	if (!i_reverbInactive) begin
		case (reverbCnt)
		// [14 Read + 4 Write = ]
		// ---------------------------------------------------------------------------------------------------------
		// W(mLSAME, (Lin + R(dLSAME) * vWALL - R(mLSAME - 2)) * vIIR + R(mLSAME - 2)); (3 Read + 1 Write)
		// ---------------------------------------------------------------------------------------------------------
		// 0 : Acc  = vLin * Sample;		        R(dXSAME)
		8'd0:
		begin sideAReg = SA_VIN;      sideBReg = {SB_DxSAME, side22Khz}; minus2 = 0; selB = SEL_IN;   accAdd = 0; SPUMemWRSel = REVERB_READ; end
		// === 1,2,3 [Wait Read] ===
		8'd4: // 1 : Acc += R(dLSAME) * vWALL;	    R(mXSAME-2)
		begin sideAReg = SA_VWALL;    sideBReg = {SB_MxSAME, side22Khz}; minus2 = 1; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end		
		// === 5,6,7 [Wait Read] ===
		8'd8: // 2 : Acc -= R(mLSAME - 2));			R(mXSAME-2)
		begin sideAReg = SA_NEG_ONE;  sideBReg = {SB_MxSAME, side22Khz}; minus2 = 1; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		8'd9: // 3 : Acc *= vIIR;
		begin sideAReg = SA_VIIR;     sideBReg = SB_FAKEREAD;            minus2 = 1; selB = SEL_ACC;  accAdd = 0; end
		// === 10,11 [Wait Read] ===
		8'd12: // 4 : Acc += R(mLSAME - 2);
		begin sideAReg = SA_ONE;      sideBReg = SB_FAKEREAD;            minus2 = 0; selB = SEL_RAM;  accAdd = 1; end
		8'd13: // 5 : W(mLSAME, Acc);
		begin sideAReg = SA_ZERO;     sideBReg = {SB_MxSAME, side22Khz}; minus2 = 0; selB = SEL_ACC;  accAdd = 0; SPUMemWRSel = reg_ReverbEnable ? REVERB_WRITE : REVERB_READ; end
		// === 14,15,16 Wait Write to complete.
		
		// ---------------------------------------------------------------------------------------------------------
		// W(mLDIFF, (Lin + R(dRDIFF) * vWALL - R(mLDIFF - 2)) * vIIR + R(mLDIFF - 2)); (3 Read + 1 Write)
		// ---------------------------------------------------------------------------------------------------------
		// 0 : Acc  = vLin * Sample;		        R(dRDIFF)
		8'd17:
		begin sideAReg = SA_VIN;      sideBReg = {SB_DxDIFF,!side22Khz}; minus2 = 0; selB = SEL_IN;   accAdd = 0; SPUMemWRSel = REVERB_READ; end
		// === 18,19,20 [Wait Read] ===
		8'd21: // 1 : Acc += R(dLSAME) * vWALL;	    R(mXDIFF-2)
		begin sideAReg = SA_VWALL;    sideBReg = {SB_MxDIFF, side22Khz}; minus2 = 1; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		// === 22,23,24 [Wait Read] ===
		8'd25: // 2 : Acc -= R(mLSAME - 2));			R(mXSAME-2)
		begin sideAReg = SA_NEG_ONE;  sideBReg = {SB_MxDIFF, side22Khz}; minus2 = 1; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		8'd26: // 3 : Acc *= vIIR;
		begin sideAReg = SA_VIIR;     sideBReg = SB_FAKEREAD;            minus2 = 1; selB = SEL_ACC;  accAdd = 0; end
		// === 27,28 [Wait Read] ===
		8'd29: // 4 : Acc += R(mLSAME - 2);
		begin sideAReg = SA_ONE;      sideBReg = SB_FAKEREAD;            minus2 = 0; selB = SEL_RAM;  accAdd = 1; end
		8'd30: // 5 : W(mLSAME, Acc);
		begin sideAReg = SA_ZERO;     sideBReg = {SB_MxDIFF, side22Khz}; minus2 = 0; selB = SEL_ACC;  accAdd = 0; SPUMemWRSel = reg_ReverbEnable ? REVERB_WRITE : REVERB_READ; end
		// === 31,32,33 Wait Write Complete.

		// ---------------------------------------------------------------------------------------------------------
		// Sample Lout = vCOMB1 * R(mLCOMB1) + vCOMB2 * R(mLCOMB2) + vCOMB3 * R(mLCOMB3) + vCOMB4 * R(mLCOMB4);
		//				 4 Read
		// ---------------------------------------------------------------------------------------------------------
		// 12: Acc  = vCOMB1 * R(mLCOMB1);
		8'd34:
		begin sideAReg = SA_ZERO;     sideBReg = {SB_MxCOMB1, side22Khz}; minus2 = 0; selB = SEL_ACC;  accAdd = 0; SPUMemWRSel = REVERB_READ; end
		// === 35,36,37 : Wait Read.
		8'd38:
		begin sideAReg = SA_COMB1;    sideBReg = {SB_MxCOMB2, side22Khz}; minus2 = 0; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		// === 39,40,41 : Wait Read.
		8'd42:
		// 13: Acc += vCOMB2 * Read;   +R(mLCOMB3)
		begin sideAReg = SA_COMB2;    sideBReg = {SB_MxCOMB3, side22Khz}; minus2 = 0; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		// === 43,44,45 : Wait Read.
		8'd46:
		// 14: Acc += vCOMB3 * Read;   +R(mLCOMB4)
		begin sideAReg = SA_COMB3;    sideBReg = {SB_MxCOMB4, side22Khz}; minus2 = 0; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		// === 47,48,49 : Wait Read.
		8'd50:
		// 15: Acc += vCOMB4 * Read;   +R(mLAPF1 - dAPF1)
		begin sideAReg = SA_COMB4; sideBReg ={SB_MxAPF1_ADPF1,side22Khz}; minus2 = 0; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		// === 51,52,53 : Wait Read.
		// ---------------------------------------------------------------------------------------------------------
		// Lout = Lout - (vAPF1 * R(mLAPF1 - dAPF1));
		// W(mLAPF1, Lout);
		//                1 Read + 1 Write
		// ---------------------------------------------------------------------------------------------------------
		// 16: Acc -= (vAPF1 * R(mLAPF1 - dAPF1));
		8'd54:
		begin sideAReg = SA_NVAPF1; sideBReg = SB_FAKEREAD;               minus2 = 0; selB = SEL_RAM; accAdd = 1; end
		// 17 : W(mLAPF1, Acc);
		8'd55: // C : Write Request (Note : use ADD to keep value, different from previous writes)
		begin sideAReg = SA_ZERO;  sideBReg = {SB_MxAPF1, side22Khz};     minus2 = 0; selB = SEL_ACC; accAdd = 1; SPUMemWRSel	= reg_ReverbEnable ? REVERB_WRITE : REVERB_READ; end
		// === 56,57,58 : Wait Write.
		
		// ---------------------------------------------------------------------------------------------------------
		// Lout = Lout * vAPF1 + R(mLAPF1 - dAPF1);
		//                1 Read
		// ---------------------------------------------------------------------------------------------------------
		// 18: Acc *= vAPF1; + Read (mLAPF1 - dAPF1)
		8'd59: 
		begin sideAReg = SA_VAPF1;  sideBReg = {SB_MxAPF1_ADPF1, side22Khz}; minus2 = 0; selB = SEL_ACC;  accAdd = 0; SPUMemWRSel = REVERB_READ; end
		// === 60,61,62 Wait Write
		// 19: Acc += R(mLAPF1 - dAPF1); + Read(mLAPF2 - dAPF2)
		8'd63:
		begin sideAReg = SA_ONE;    sideBReg = {SB_MxAPF2_ADPF2, side22Khz}; minus2 = 0; selB = SEL_RAM;  accAdd = 1; SPUMemWRSel = REVERB_READ; end
		// === 64,65,66 Wait Read
		
		// ---------------------------------------------------------------------------------------------------------
		// Lout = Lout - (vAPF2 * R(mLAPF2 - dAPF2));
		// W(mLAPF2, Lout);
		//                1 Read + 1 Write
		// ---------------------------------------------------------------------------------------------------------
		// 20: Acc -= R(mLAPF2 - dAPF2);
		8'd67:
		begin sideAReg = SA_NVAPF2; sideBReg = SB_FAKEREAD;                  minus2 = 0; selB = SEL_RAM;  accAdd = 1; end
		// 21: W(mLAPF2, Acc);
		8'd68:
		begin sideAReg = SA_ZERO;  sideBReg = {SB_MxAPF2, side22Khz};        minus2 = 0; selB = SEL_ACC;  accAdd = 1; SPUMemWRSel	= reg_ReverbEnable ? REVERB_WRITE : REVERB_READ; end
		// === 69,70,71 Wait Write.
		
		// ---------------------------------------------------------------------------------------------------------
		// Lout = Lout * vAPF2 + R(mLAPF2 - dAPF2);
		//                1 Read
		// ---------------------------------------------------------------------------------------------------------
		// 18: Acc *= vAPF2; + Read (mLAPF2 - dAPF2)
		8'd72:
		begin sideAReg = SA_VAPF2;  sideBReg = {SB_MxAPF2_ADPF2, side22Khz}; minus2 = 0; selB = SEL_ACC;  accAdd = 0; SPUMemWRSel = REVERB_READ; end
		// === 73,74,75
		// 19: Acc += R(mLAPF2 - dAPF2);
		8'd76:
		begin sideAReg = SA_ONE;    sideBReg = SB_FAKEREAD;                  minus2 = 0; selB = SEL_RAM;  accAdd = 1; end
		
		// ---------------------------------------------------------------------------------------------------------
		// [TODO] Add to output audio : Lout * spu->reverbVolume.getLeft()
		// spu->reverbCurrentAddress = wrap(spu, spu->reverbCurrentAddress + 2); when LR complete. (22 Khz)
		// ---------------------------------------------------------------------------------------------------------

		8'd96:
		begin
			SPUMemWRSel			= CD_WR;
		end
		8'd100:
		begin
			SPUMemWRSel			= CD_WR;
			isRight				= 1;
		end
		8'd127:
		begin
			ctrlSendOut			= 1;
		end
		default: // [DEFAULT KEEP REVERB INFORMATION ALIVE FOR NEXT CYCLE]
		begin sideAReg = SA_ZERO;	sideBReg = SB_FAKEREAD;					minus2 = 0; selB = SEL_ACC;	accAdd = 1; end
		endcase
	end
end

assign o_SPUMemWRSel	= SPUMemWRSel;
assign o_SPUMemWRRight	= isRight;
assign o_ctrlSendOut	= ctrlSendOut;

endmodule
