/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
	
	Many many thanks to Jakub Czekanski (Author of PSX Emulator Avocado : https://github.com/JaCzekanski/Avocado )
	for tirelessly answering all my questions and the many hours spent discussing the PSX specs.
	
	I also used his implementation to debug the chip but also to check some part of the specs.
	Without his work, my time spent on the project would have been much longer.
	
 **************************************************************************************************************************************/
/*	READ / WRITE Special Behavior :
	- Overwrite of current voice MAIN VOLUME ignored.
	- Write of 1F801DBCh is not supported (UNKNOWN REGISTER), Read is FAKE hardcoded value.
	- Write of 1F801DA0h is not supported (UNKNOWN REGISTER), Read is FAKE hardcoded value.
	- 1F801E60h R/W Not supported.
	----- Unmet in games ----
	TODO : Implement Sweep.	(Per channel, Per Main)
*/
`include "spu_def.v"

module SPU(
	 input			i_clk
	,input			n_rst
	
	// CPU Side
	// CPU can do 32 bit read/write but they are translated into multiple 16 bit access.
	// CPU can do  8 bit read/write but it will receive 16 bit. Write will write 16 bit. (See No$PSX specs)
	,input			SPUCS	// We have only 11 adress bit, so for read and write, we tell the chip is selected.
	
	// No ACK/REQ on CPU SIDE
	,input			SRD
	,input			SWRO
	,input	[ 9:0]	addr			// Here Sony spec is probably in HALF-WORD (9 bit), we keep in BYTE for now. (10 bit)
	,input	[15:0]	dataIn
	,output	[15:0]	dataOut
	,output			dataOutValid	// Always 1 cycle after SRD.
	,output			SPUINT
	
	// CPU DMA stuff.
	// When SPU is in DMA READ mode:
	// -SPUDREQ is HIGH when DATA is pushed to DMA + 'o_dataOutRAM' got the value.
	// -SPUDACK is HIGH signal to signal read the NEXT data block. 
	//  SPUDREQ will emit at regular interval the value, if missed, just wait for the NEXT emission (generally 24 cycle later but can be a LOT more)
	//  It is prefered to answer SPUDACK within 20 cycles. But if you did not miss the flag, I guess it will always be shorter.
	//
	// When SPU is in DMA WRITE mode:
	// -SPUDREQ is HIGH all the time except when FIFO is FULL (always requesting new data)
	// -SPUDACK is HIGH and 'i_dataInRAM' has the value.
	,output			SPUDREQ
	,input			SPUDACK

	// RAM Side
	,output	[17:0]	o_adrRAM
	,output			o_dataReadRAM
	,output			o_dataWriteRAM
	,input	[15:0]	i_dataInRAM
	,output	[15:0]	o_dataOutRAM
	
	// From CD-Rom, serial stuff in original HW,
	// 
	,input  signed [15:0]	CDRomInL
	,input  signed [15:0]	CDRomInR
	,input			inputL
	,input			inputR
	
	// Audio DAC Out
	,output [15:0]	AOUTL
	,output [15:0]	AOUTR
	,output 		VALIDOUT
);

reg [23:0] debugCnt; always @(posedge i_clk)
begin debugCnt <= (n_rst == 0) ? 24'd0 : debugCnt + 24'd1; end

reg      [2:0]	SPUMemWRSel;
reg 	[17:0]	internal_adrRAM;
reg		[15:0]	internal_dataOutRAM;

wire writeSPURAM;
assign			o_adrRAM		= internal_adrRAM;
assign 			o_dataReadRAM    = (!writeSPURAM) & (SPUMemWRSel[0] | SPUMemWRSel[1]); // Avoid doing READ when not needed.
assign 			o_dataWriteRAM   = writeSPURAM;

assign			o_dataOutRAM	= internal_dataOutRAM;

wire [17:0] reverbAdr;
wire [15:0] reverbWriteValue;
wire [17:0] reg_dataTransferAddrCurr;
wire [8:0] regRingBufferIndex;
always @(*) begin
	// Write Section
	case (SPUMemWRSel)
	VOICE_RD  : internal_adrRAM = adrRAM;
	FIFO_RD   : internal_adrRAM = reg_dataTransferAddrCurr;
	VOICE_WR  : internal_adrRAM = {8'd1,isVoice3,regRingBufferIndex};
	CD_WR     : internal_adrRAM = {8'd0,isRight ,regRingBufferIndex};
	FIFO_WRITE: internal_adrRAM = reg_dataTransferAddrCurr;
	// REVERB_READ:
	// REVERB_WRITE:
	default   : internal_adrRAM = reverbAdr; // Reverb
	endcase
end

wire [15:0] storedCDRomInL,storedCDRomInR,currChannelVxOut;
always @(*) begin
	// Garbage in case of read, but ignored...
	case (SPUMemWRSel[1:0])
	FIFO_MD		: internal_dataOutRAM = fifoDataOut;
	VOICEMD		: internal_dataOutRAM = currChannelVxOut;
	CDROMMD		: internal_dataOutRAM = isRight ? storedCDRomInR : storedCDRomInL;
	default		: internal_dataOutRAM = reverbWriteValue; // REVB_MD
	endcase
end

wire readFIFO;
wire isFIFOFull;
wire emptyFifo;
wire isFIFOHasData = !emptyFifo; // fifo_r_valid;
wire	[15:0]	fifoDataOut;

wire [5:0] fifo_level;	// TODO : Use FIFO 32 element used == FULL signal.
Fifo
#(
	.DEPTH_WIDTH	(5),
	.DATA_WIDTH		(16)
)
InternalFifo
(
	.clk			(i_clk),
	.rst			(!n_rst),
	
	.wr_data_i		(dataIn),
	.wr_en_i		(writeFIFO),

	.rd_data_o		(fifoDataOut),
	.rd_en_i		(readFIFO),

	.full_o			(isFIFOFull),
	.empty_o		(emptyFifo)
);


wire internalWrite = SWRO & SPUCS;
wire internalRead  = SRD  & SPUCS;

// --------------------------------------------------------------------------------------
//		[FRONT END : Registers]
// --------------------------------------------------------------------------------------

reg			reg_SPUIRQSet;

reg [31:0]  reg_tmpAdpcmPrev;

wire [15:0] 		currV_startAddr;
wire 	 			currV_NON;
wire [15:0] 		currV_repeatAddr;
wire [15:0] 		currV_adpcmCurrAdr;
wire [16:0] 		currV_adpcmPos;
wire [31:0] 		currV_adpcmPrev;
wire 				currV_KON;
wire 				currV_PMON;
wire 				currV_EON;
wire signed [14:0] 	currV_VolumeL;
wire signed [14:0] 	currV_VolumeR;
wire [14:0] 		currV_AdsrVol;
wire [15:0] 		currV_AdsrLo;
wire [15:0] 		currV_AdsrHi;
wire  [1:0] 		currV_AdsrState;
wire [22:0] 		currV_AdsrCycleCount;
wire [15:0] 		currV_sampleRate;
wire [15:0]			dataOutw;	
wire  [1:0]			reg_SPUTransferMode;

wire			reg_SPUIRQEnable;			//  DAA.6
wire [15:0]	reg_ramIRQAddr;				// DA4 Sound RAM IRQ Address
wire [15:0]	reg_mBase;					// 32 bit ?
wire  [17:0] reverb_CounterWord;
wire			reg_ReverbEnable;			//  DAA.7
wire	[3:0]	reg_NoiseFrequShift;		//  DAA.13-10
wire	[3:0]	reg_NoiseFrequStep;			//  DAA.9-8 -> Modified at setup.
wire 		reg_SPUEnable;				//  DAA.15

wire			reg_SPUNotMuted;			//  DAA.14
wire			reg_CDAudioEnabled;			//  DAA.0
wire			reg_CDAudioReverbEnabled;	//  DAA.2
wire signed [15:0]	reg_CDVolumeL;		// DB0 CD Audio Input Volume Left  (CD-DA / XA-ADPCM)
wire signed [15:0]	reg_CDVolumeR;		// DB2 CD Audio Input Volume Right (CD-DA / XA-ADPCM)
wire signed [15:0]	reg_mainVolLeft;	// D80 Mainvolume Left
wire signed [15:0]	reg_mainVolRight;	// D82 Mainvolume Left
wire signed [15:0]	reg_reverbVolLeft;
wire signed [15:0]	reg_reverbVolRight;

// Reverb mapped registers.
wire signed [15:0] dAPF1,dAPF2,vIIR,vCOMB1, vCOMB2,vCOMB3,vCOMB4,vWALL, vAPF1,vAPF2,mLSAME,mRSAME;
wire signed [15:0] mLCOMB1,mRCOMB1,mLCOMB2,mRCOMB2, dLSAME,dRSAME,mLDIFF,mRDIFF, mLCOMB3,mRCOMB3,mLCOMB4,mRCOMB4;
wire signed [15:0] dLDIFF,dRDIFF,mLAPF1,mRAPF1,mLAPF2,mRAPF2,vLIN,vRIN;

sup_tmp_front sup_tmp_front_inst (
	.i_clk					(i_clk				),
	.n_rst                  (n_rst               ),

	.SPUCS                  (SPUCS               ),
	.SRD                    (SRD                 ),
	.SWRO                   (SWRO                ),
	.addr			        (addr			     ),
	.dataIn                 (dataIn              ),

	.currVoice              (currVoice           ),

	.negNoiseStep           (negNoiseStep        ),
	.check_Kevent           (check_Kevent        ),
	.clearKON               (clearKON            ),
	.incrXFerAdr            (incrXFerAdr         ),
	.ctrlSendOut            (ctrlSendOut         ),
	.setAsStart             (setAsStart          ),
	.setEndX                (setEndX             ),
	.isRepeatADPCMFlag      (isRepeatADPCMFlag   ),
	.isNotEndADPCMBlock     (isNotEndADPCMBlock  ),
	.updateVoiceADPCMAdr    (updateVoiceADPCMAdr ),
	.updateVoiceADPCMPos    (updateVoiceADPCMPos ),
	.updateVoiceADPCMPrev   (updateVoiceADPCMPrev),
	.updateADSRVolReg       (updateADSRVolReg    ),
	.updateADSRState        (updateADSRState     ),
	.validSampleStage2      (validSampleStage2   ),

	.side22Khz              (side22Khz           ),

	.nextNewBlock           (nextNewBlock        ),

	.nextADPCMPos           (nextADPCMPos        ),
	.reg_tmpAdpcmPrev       (reg_tmpAdpcmPrev    ),
	.nextAdsrCycle          (nextAdsrCycle       ),
	.nextAdsrVol            (nextAdsrVol         ),
	.nextAdsrState          (nextAdsrState       ),
	
	.dataTransferBusy		(dataTransferBusy),
	.dataTransferWriteReq   (dataTransferWriteReq),
	.dataTransferReadReq    (dataTransferReadReq),
	.dataTransferRDReq      (dataTransferRDReq),
	.reg_SPUIRQSet          (reg_SPUIRQSet),
	
	.currV_startAddr		(currV_startAddr	),	
	.currV_NON		        (currV_NON		     ),
	.currV_repeatAddr		(currV_repeatAddr	),
	.currV_adpcmCurrAdr	    (currV_adpcmCurrAdr	 ),
	.currV_adpcmPos		    (currV_adpcmPos		 ),
	.currV_adpcmPrev		(currV_adpcmPrev	),
	.currV_KON	            (currV_KON	         ),
	.currV_PMON	            (currV_PMON	         ),
	.currV_EON		        (currV_EON		     ),
	.currV_VolumeL	        (currV_VolumeL	     ),
	.currV_VolumeR	        (currV_VolumeR	     ),
	.currV_AdsrVol	        (currV_AdsrVol	     ),
	.currV_AdsrLo	        (currV_AdsrLo	     ),
	.currV_AdsrHi	        (currV_AdsrHi	     ),
	.currV_AdsrState	    (currV_AdsrState	 ),
	.currV_AdsrCycleCount   (currV_AdsrCycleCount),
	.currV_sampleRate       (currV_sampleRate    ),
	
	.o_reg_SPUIRQEnable				(reg_SPUIRQEnable),
	.o_reg_ramIRQAddr               (reg_ramIRQAddr),
	.o_reg_mBase                    (reg_mBase),
	.o_reverb_CounterWord           (reverb_CounterWord),
	.o_reg_ReverbEnable             (reg_ReverbEnable),
	.o_reg_NoiseFrequShift          (reg_NoiseFrequShift),
	.o_reg_NoiseFrequStep           (reg_NoiseFrequStep),
	.o_reg_SPUEnable                (reg_SPUEnable),
	.o_reg_SPUNotMuted	            (reg_SPUNotMuted),
	.o_reg_CDAudioEnabled           (reg_CDAudioEnabled),
	.o_reg_CDAudioReverbEnabled     (reg_CDAudioReverbEnabled),
	.o_reg_CDVolumeL                (reg_CDVolumeL),
	.o_reg_CDVolumeR                (reg_CDVolumeR),
	.o_reg_mainVolLeft              (reg_mainVolLeft),
	.o_reg_mainVolRight             (reg_mainVolRight),
	.o_reg_reverbVolLeft            (reg_reverbVolLeft),
	.o_reg_reverbVolRight	        (reg_reverbVolRight),
	
	.o_reg_dataTransferAddrCurr	(reg_dataTransferAddrCurr),
	.o_regRingBufferIndex		(regRingBufferIndex),
	.o_reg_SPUTransferMode		(reg_SPUTransferMode),
	
	.dAPF1						 (dAPF1),
	.dAPF2	                     (dAPF2),
	.vIIR	                     (vIIR),
	.vCOMB1	                     (vCOMB1),

	.vCOMB2	                     (vCOMB2	),
	.vCOMB3	                     (vCOMB3	),
	.vCOMB4	                     (vCOMB4	),
	.vWALL	                     (vWALL	),

	.vAPF1                       (vAPF1),
	.vAPF2	                     (vAPF2	),
	.mLSAME                      (mLSAME),
	.mRSAME	                     (mRSAME	),

	.mLCOMB1	                 (mLCOMB1),
	.mRCOMB1	                 (mRCOMB1),
	.mLCOMB2	                 (mLCOMB2),
	.mRCOMB2	                 (mRCOMB2),

	.dLSAME	                     (dLSAME	),
	.dRSAME	                     (dRSAME	),
	.mLDIFF	                     (mLDIFF	),
	.mRDIFF	                     (mRDIFF	),

	.mLCOMB3	                 (mLCOMB3),
	.mRCOMB3	                 (mRCOMB3),
	.mLCOMB4	                 (mLCOMB4),
	.mRCOMB4	                 (mRCOMB4),

	.dLDIFF	                     (dLDIFF	),
	.dRDIFF	                     (dRDIFF	),
	.mLAPF1	                     (mLAPF1	),
	.mRAPF1	                     (mRAPF1	),

	.mLAPF2	                     (mLAPF2	),
	.mRAPF2	                     (mRAPF2	),
	.vLIN	                     (vLIN	),
	.vRIN	                     (vRIN	),
	
	.o_dataOutw				(dataOutw)
);

// -----------------------------------------------------------------
// REGISTER READ / WRITE SECTION
// -----------------------------------------------------------------
reg [3:0] negNoiseStep;
always @(*) begin
	case (dataIn[9:8])
	2'b00: negNoiseStep = 4'b1100;	// -4
	2'b01: negNoiseStep = 4'b1011;	// -5
	2'b10: negNoiseStep = 4'b1010;	// -6
	2'b11: negNoiseStep = 4'b1001;	// -7
	endcase
end

wire isD8				= (addr[9:8]==2'b01);
wire isD80_DFF			= (isD8 && addr[7]);							// Latency 0 : D80~DFF
wire isChannel			= ((addr[9:8]==2'b00) | (isD8 & !addr[7])); 	// Latency 0 : C00~D7F
wire [4:0] channelAdr	= addr[8:4];

// Detect write transition
wire isDMAXferWR    = (reg_SPUTransferMode == XFER_DMAWR);
wire isDMAXferRD    = (reg_SPUTransferMode == XFER_DMARD);

// UNUSED FOR NOW : wire isManualXferWR = (reg_SPUTransferMode == XFER_MANUAL);
// CPU can write anytime. (See writeFIFO) (DMA and CPU can't write at the same time ANYWAY, mutually exclusive)
// Mode=Stop / Mode=ManualWrite work with CPU only. (SPUDACK won't come)

wire dataTransferBusy		= isFIFOHasData /* Busy as long as the FIFO has data in DMA/CPU write */
                            | isDMAXferRD   /* Always true when DMA READ */;
							
wire dataTransferReadReq 	= reg_SPUTransferMode[1] & reg_SPUTransferMode[0];
wire dataTransferWriteReq	= reg_SPUTransferMode[1] & (!reg_SPUTransferMode[0]);
wire dataTransferRDReq		= reg_SPUTransferMode[1];

// [Write to FIFO only on transition from internalwrite from 0->1 but allow BURST with DMA transfer] 
//  --> PROTECTED FOR EDGE TRANSITION : WRITE during multiple cycle else would perform multiple WRITE of the same value !!!!
// Implicit in writeFIFO, not used : wire isCPUXFer = (reg_SPUTransferMode == XFER_MANUAL);
wire writeFIFO = (internalWrite & isD80_DFF & (!addr[6]) & (addr[5:1] == 5'h14)) | (isDMAXferWR & SPUDACK);
/*
reg PInternalWrite;
always @(posedge i_clk)
begin
	if (n_rst == 0) begin
		PInternalWrite <= 1'b0;
	end else begin
		PInternalWrite <= internalWrite;
	end
end
*/

reg updateVoiceADPCMAdr,updateADSRState,updateADSRVolReg,clearKON;
wire [22:0] nextAdsrCycle;
wire  [1:0]	nextAdsrState;
wire [14:0] nextAdsrVol;



reg [15:0] pipeDataOut;
always @ (posedge i_clk) 
begin
	pipeDataOut <= dataOutw;
end

assign dataOut		= readSPU ? i_dataInRAM : pipeDataOut;

reg internalReadPipe;
reg incrXFerAdr;
always @ (posedge i_clk) 
begin
	internalReadPipe	<= internalRead;
	incrXFerAdr			<= readFIFO | (SPUDACK && isDMAXferRD);
end


// Pipe read. For now everything answer at the NEXT clock, ONCE.
// BUT READ SPU IS NOT MODIFYING THE CPU BUS. (dataOut can be SPU VRAM out with DMA too)
assign dataOutValid	= internalReadPipe/* | readSPU */; 

// -----------------------------------------------------------------
// INTERNAL TIMING & STATE SECTION
// -----------------------------------------------------------------
reg  [5:0] currVoice6Bit;
wire [4:0] currVoice = currVoice6Bit[4:0];
reg  [4:0] voiceCounter;

wire isLastCycle = (voiceCounter == 5'd23);
// reg  [9:0] counter768;
// wire [9:0] nextCounter768 = counter768 + 10'd1;
wire ctrl44Khz = (currVoice == 5'd31) && isLastCycle;
wire side22Khz = currVoice6Bit[5]; // Left / Right side for Reverb.
always @(posedge i_clk)
begin
	if (n_rst == 0)
	begin
		voiceCounter		<= 5'd0;
		currVoice6Bit		<= 6'd0;
	end else begin
		if (isLastCycle) begin
			voiceCounter 	<= 5'd0;
			currVoice6Bit	<= currVoice6Bit + 6'd1;
		end else begin
			voiceCounter 	<= voiceCounter + 5'd1; 
		end
	end
end

reg [3:0] currV_shift;
reg [2:0] currV_filter;
wire signed [15:0] sampleOutADPCMRAW;

always @(posedge i_clk)
begin
	if (loadPrev) begin
		currV_shift		<= i_dataInRAM[3:0];
		currV_filter	<= i_dataInRAM[6:4];
	end
	
	if (reg_SPUIRQEnable && (reg_ramIRQAddr==o_adrRAM[17:2])) begin
		reg_SPUIRQSet <= 1'b1;
	end
	if (reg_SPUIRQEnable == 1'b0 /* || (n_rst == 0) */) begin // On Reset, enable will reset the IRQ with 1 cycle latency... No need for n_rst signal.
		// Acknowledge if IRQ was set.
		reg_SPUIRQSet <= 1'b0;
	end
	if (loadPrev) begin
		reg_tmpAdpcmPrev <= currV_adpcmPrev;
	end
	if (updatePrev) begin
		reg_tmpAdpcmPrev <= { reg_tmpAdpcmPrev[15:0], sampleOutADPCMRAW };
	end
end

assign SPUINT = reg_SPUIRQSet;

reg voiceIncrement;						// Goto the next voice.
reg [2:0] decodeSample;
reg updatePrev, loadPrev;
reg [1:0] adpcmSubSample;
reg check_Kevent;

reg zeroIndex;
wire  [3:0] idxBuff			= zeroIndex ? 4'd0 : { 1'b0, currV_adpcmPos[16:14]} + 4'd1; // Change from Base 0 index to Base 1 index in adr.
wire [17:0] adrRAM			= { currV_adpcmCurrAdr, 2'd0 } + {13'd0,idxBuff[3:0]};
reg  setEndX, setAsStart, isRepeatADPCMFlag; // ADPCM internal block FLAG : Start/End flags.
reg  isNotEndADPCMBlock;
reg  storePrevVxOut;
reg	ctrlSendOut;
reg	clearSum;
reg readSPU;
reg updateVoiceADPCMPos;
reg updateVoiceADPCMPrev;
wire isVoice1		= (currVoice == 5'd1);
wire isVoice3		= (currVoice == 5'd3);

reg [7:0] reverbCnt;
always @(posedge i_clk)
begin
	if (currVoice[4:3] != 2'd3) begin
		reverbCnt <= 8'd0;
	end else begin
		reverbCnt <= reverbCnt + 8'd1;
	end
end

reg  signed [15:0] mulA;
reg  signed [15:0] mulB;
wire signed [15:0] lineIn;
wire signed [30:0] resMulAB   = mulA * mulB;
wire signed [15:0] resMulAB16 = resMulAB[30:15];  
wire signed [15:0] addB       = accAdd ? accReverb : 16'd0;
wire signed [16:0] addC       = addB + resMulAB16;
// [TODO] Clamp addC to 16 bit instead of 17 bits.
wire signed [15:0] clampedAddC = addC[15:0];

reg  signed [15:0] accReverb;
always @(posedge i_clk)
begin
	accReverb <= clampedAddC;
end

reg [15:0] adrB;

reg [3:0] sideAReg;
reg [4:0] sideBReg;
reg       minus2;
reg [1:0] selB;
reg       accAdd;
reg		  isRight;

                   //15->17 bit +   0/-1 Half Word.(-2 byte)
wire [17:0] reverbAdrPreRing = {adrB, 2'd0} + {18{minus2}}; // [Read Memory from Reverb Adr stuff]


ReverbWrapAdr ReverbWrapAdrInst(
	.i_offsetRegister	(reverbAdrPreRing),	// Word Offset.
	.i_baseAdr			(reg_mBase),		// x8 byte 16 bit reg.
	.i_offsetCounter	(reverb_CounterWord),// Word Offset.
	.o_reverbAdr		(reverbAdr)			// Word output absolute adr.
);

// Value to write to the SPU RAM for reverb data bus.
assign reverbWriteValue	= accReverb;

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
	SA_VIN:		mulA = side22Khz ? vRIN : vLIN;
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
	SEL_IN:		mulB = lineIn;
	SEL_RAM:	mulB = i_dataInRAM;
	// Not used, mulA used for sign <= SEL_NRAM:   mulB = (~i_dataInRAM) + 16'd1; // -i_dataInRAM
	default:	mulB = accReverb;
	endcase
end

// REQ in READ  MODE IS SENDING DATA
// REQ in WRITE MODE IS KEEPING REQUESTING UNTIL FIFO IS FULL.
assign SPUDREQ = (isDMAXferRD & readSPU) | (isDMAXferWR && !isFIFOFull);

always @(*)
begin
	loadPrev			= 0;
	updatePrev			= 0;
	check_Kevent		= 0;
	storePrevVxOut		= 0;
	clearSum			= 0;
	ctrlSendOut			= 0;
	setEndX				= 0;
	setAsStart			= 0;
	zeroIndex			= 0;
	SPUMemWRSel			= NO_SPU_READ;	// Default : NO READ/WRITE SIGNALS
	updateVoiceADPCMAdr	= 0;
	updateVoiceADPCMPos = 0;
	updateVoiceADPCMPrev= 0;
	adpcmSubSample		= 0;
	isNotEndADPCMBlock	= 0;
	isRepeatADPCMFlag	= 0;
	readSPU				= 0;

	// Keep data in the reverb loop by default...
	sideAReg			= SA_ZERO;
	sideBReg			= SB_FAKEREAD;
	minus2				= 0;
	selB				= SEL_ACC;
	accAdd				= 1;
	
	isRight				= 0;
	kickFifoRead		= 0;
	
	if (currVoice[4:3] != 2'd3) begin // [Channel 0..23 Timing are VOICES in original SPU]
		case (voiceCounter)
		5'd0:
		begin
			// Cycle 0 : currVoice register output updated.
			check_Kevent		= 1;
		end
		5'd1:
		begin
			// If check_Kevent --> Here, updated currV_adpcmCurrAdr
			SPUMemWRSel			= VOICE_RD;
			zeroIndex			= 1;
			
			// Need to preload header to setup Status stuff...
			// Upgrade address counter if needed.
		end
		// 2/3/4
		5'd5:
		begin
			// Here Header info is loaded and processed if necessary.
			loadPrev			= 1;
			setEndX				= i_dataInRAM[ 8]; // 1 : Register flag 'ended', mark block as 'last'
			isNotEndADPCMBlock	= !i_dataInRAM[8]; //							 mark block as 'normal'
			isRepeatADPCMFlag	= i_dataInRAM[ 9];
			setAsStart			= i_dataInRAM[10]; // 4 : Register block as loop start.
			
			SPUMemWRSel			= VOICE_RD; // Sample 0
			// Load correct Sample block based on current sample position and base block adress.
		end
		// 6/7/8
		5'd9:
		begin
			// For each sample 0..3 ( currV_adpcmPos[13:12] )
			// Check if we match currV_adpcmPos[13:12]
			// -> Push sample to gaussian interpolator.
			// At sample 3

			// [Do nothing on memory side for now... Use for XFER]
			
			updatePrev			= 1;
			adpcmSubSample		= 0;
		end
		5'd10:
		begin
			updatePrev			= 1;
			adpcmSubSample		= 1;
		end
		5'd11:
		begin
			updatePrev			= 1;
			adpcmSubSample		= 2;
		end
		5'd12:
		begin
			updatePrev			= 1;
			adpcmSubSample		= 3;
			// Before the first sample of the first channel is sent, we reset the accumulators.
			// We put it here, but it can be moved around if needed,
			// it must just take in account the last sample of channel 23 pipeline latency and start of channel 0 when looping.
			clearSum			= (currVoice == 5'd0);
		end
		
		5'd13:
		begin
			kickFifoRead		= 1;
		end
		//
		// The interpolator takes 5 CYCLE to output, prefer to maintain channel active for that amount of cycle....
		//
		5'd14:
		begin
			// SPUMemWRSel			= FIFO_WRITE; // Allow only ONCE XFer per voice...
			SPUMemWRSel = isDMAXferRD ? FIFO_RD : FIFO_WRITE; // Allow only ONCE XFer per voice...
		end
		5'd15:
		begin
			// [XFER WAIT 1]
		end
		5'd16:
		begin
			// [XFER WAIT 2]
		end
		5'd17:
			// [XFER WAIT 3]
		begin
		end
		5'd18:
		begin
			// Will increment the counter... ?
			// Will only accept to go to the next value if ACK is reading/accepting the value...
			readSPU			= isDMAXferRD;
			
			storePrevVxOut	= 1;
			// -> If NEXT sample is OUTSIDE AND CONTINUE, SAVE sample2/sample3 (previous needed for decoding)
			//       NEXT sample is OUTSIDE AND JUMP, set 0/0.
			// 
			if (isVoice1 | isVoice3) begin
				SPUMemWRSel			= VOICE_WR;
			end // else use FIFO to purge...

			// --------------------------------
			// ADPCM Line/Block Management
			// --------------------------------
			updateVoiceADPCMAdr = nextNewBlock;
			updateVoiceADPCMPos = 1;
			updateVoiceADPCMPrev= nextNewLine;	// Store PREV ADPCM when we move to the next 16 bit only.(different line in same ADPCM block or new ADPCM block)
		end
		default:
		begin
			// Do nothing.
		end
		endcase
	end else begin  // [Channel 24..31 x 24 cycle = REVERB, FIFO Transfer, WRITE BACK CD/VOICES]
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

// Allow transfer from FIFO any cycle where RAM not busy...
wire isFIFOWR       = (SPUMemWRSel==FIFO_WRITE);
reg kickFifoRead;
// We have data, valid timing and transfer mode is not STOPPED or DMA_READ
assign readFIFO		= isFIFOHasData & kickFifoRead & ((reg_SPUTransferMode != XFER_STOP) && (reg_SPUTransferMode != XFER_DMARD));
reg pipeReadFIFO;
always @(posedge i_clk) begin
	pipeReadFIFO <= readFIFO;
end

// A.[Write when FIFO data available AND mode is read FIFO (CPU WRITE/DMA WRITE)] DMA Transfer/CPU Transfer to SPU RAM.
// B.[Write when mode is not read FIFO to SPU RAM but write back to SPU RAM     ] Ex. Reverb, Voice1/3, CD Channels.
assign writeSPURAM	= pipeReadFIFO | (!isFIFOWR & SPUMemWRSel[2]);

// --------------------------------------------------------------------------------------
//		Stage 0A : ADPCM Adress computation (common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire  [16:0] nextADPCMPos;
wire         nextNewBlock,nextNewLine;
reg   [15:0] prevChannelVxOut;

spu_ADPCMnextAdr spu_ADPCMnextAdr_inst(
	.i_currV_adpcmPos		(currV_adpcmPos),
	.i_currV_sampleRate		(currV_sampleRate),
	.i_prevChannelVxOut		(prevChannelVxOut),
	.i_currPMON				(currV_PMON),
	
	.o_nextADPCMPos			(nextADPCMPos),
	.o_nextNewBlock			(nextNewBlock),
	.o_nextNewLine			(nextNewLine)
);

// --------------------------------------------------------------------------------------
//		Stage 0 : ADPCM Input -> Output		(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire isNullADSR         = (currV_AdsrVol==15'd0);
wire newSampleReady		= (adpcmSubSample == currV_adpcmPos[13:12]) & updatePrev;	// Only when state machine output SAMPLE from SPU RAM and valid ADPCM out.
wire launchInterpolator = (adpcmSubSample == 2'd3) & updatePrev;					// Interpolator must run when no more write done.

ADPCMDecoder ADPCMDecoderUnit(
	.i_Shift		(currV_shift),
	.i_Filter		(currV_filter),
	
	.inputRAW		(i_dataInRAM),
	.samplePosition	(adpcmSubSample),

	.i_PrevSample0	(reg_tmpAdpcmPrev[15: 0]),
	.i_PrevSample1	(reg_tmpAdpcmPrev[31:16]),
	.o_sample		(sampleOutADPCMRAW)
);
// To avoid buffer noise : When Attack|Release is ZERO -> Push ZERO sample into ring buffer too.
wire signed [15:0] sampleOutADPCM   = (isNullADSR) ? 16'd0 : sampleOutADPCMRAW;

// --------------------------------------------------------------------------------------
//	[COMPLETED] Stage 1 : Gaussian Filter
// --------------------------------------------------------------------------------------

wire signed [15:0]	voiceSample;
wire				validSampleStage2;
//                           --5 bit-- --3 bit Nibble Blk (1..7)-- -- 2 bit Sample ID (0..3) --
wire [9:0] ringBufferADR = { currVoice,  newSampleReady ? { currV_adpcmPos[16:14]  ,   adpcmSubSample } : readRingBuffAdr};
wire [15:0] readSample;
wire [4:0] readRingBuffAdr;
InterRingBuff InterRingBuffInstance
(	.i_clk			(i_clk),
	.i_data			(sampleOutADPCM),
	.i_wordAddr		(ringBufferADR),
	.i_we			(newSampleReady),		// Write when doing updatePrev, else READ.
	.o_q			(readSample)
);

Interpolator Interpolator_inst(
	.i_clk					(i_clk),
	
	// 5 Cycle latency between input and output.
	.i_go					(launchInterpolator),
	.i_interpolator			(currV_adpcmPos[11: 4]),
	.i_newPos				(currV_adpcmPos[16:12]),	// [3 bit : 4 sample line | 2 bit pos in line]
	.i_sample				(readSample),
	.o_readRingBuffAdr		(readRingBuffAdr),
	.o_sample_c5			(voiceSample),
	.o_validSample			(validSampleStage2)
);

// --------------------------------------------------------------------------------------
//	[COMPLETED]	Stage Z  : Noise Output        	(once per audio sample, every 768 cycle)
// --------------------------------------------------------------------------------------
wire [15:0] noiseLevel;
NoiseUnit NoiseUnit_inst(
	.clk					(i_clk),
	.i_nrst					(n_rst),
	.i_ctrl44Khz			(ctrl44Khz),
	.i_noiseShift			(reg_NoiseFrequShift),
	.i_noiseStep 			(reg_NoiseFrequStep),
	.o_noiseOut  			(noiseLevel)
);

// --------------------------------------------------------------------------------------
//	[COMPLETED]	Stage 2 : Select ADPCM / Noise 	(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire signed [15:0] ChannelValue			= currV_NON ? noiseLevel : (validSampleStage2 ? voiceSample : 16'd0); // [TODO ADDED DEBUG WITH VALID SAMPLE. -> REMOVE]

spu_ADSRUpdate spu_ADSRUpdate_instance (
	.i_validSampleStage2	(validSampleStage2),

	.reg_SPUEnable			(reg_SPUEnable),
	.curr_KON				(currV_KON),
	.curr_AdsrVOL			(currV_AdsrVol),
	.curr_AdsrLo			(currV_AdsrLo),
	.curr_AdsrHi			(currV_AdsrHi),
	.curr_AdsrState			(currV_AdsrState),
	.curr_AdsrCycleCount	(currV_AdsrCycleCount),
	
	.o_updateADSRState		(updateADSRState),
	.o_updateADSRVolReg		(updateADSRVolReg),
	.o_clearKON				(clearKON),

	.o_nextAdsrState		(nextAdsrState),
	.o_nextAdsrVol			(nextAdsrVol),
	.o_nextAdsrCycle		(nextAdsrCycle)
);

/*
	4. Detect value threshold and change state.
 */

spu_AudioMixer spu_AudioMixerInstance (
	.i_clk					(i_clk),
	.i_rst					(!n_rst),
	
	.i_side22Khz			(side22Khz),
	// Mixing this channel to the output
	.i_ChannelValue			(ChannelValue),
	.i_vxOutValid			(validSampleStage2),

	.i_AdsrVol				(currV_AdsrVol),
	.i_currV_EON			(currV_EON),
	.i_currV_VolumeL		(currV_VolumeL),
	.i_currV_VolumeR		(currV_VolumeR),

	.i_ctrlSendOut			(ctrlSendOut),	// When mixing the last sample -> Send out to the audio DAC.
	.i_clearSum				(clearSum),
	
	
	// Register from outside
	.i_reg_SPUNotMuted			(reg_SPUNotMuted),
	.i_reg_CDAudioEnabled		(reg_CDAudioEnabled),
	.i_reg_CDAudioReverbEnabled	(reg_CDAudioReverbEnabled),
	.i_reg_CDVolumeL			(reg_CDVolumeL),
	.i_reg_CDVolumeR			(reg_CDVolumeR),
	.i_reg_mainVolLeft			(reg_mainVolLeft),
	.i_reg_mainVolRight			(reg_mainVolRight),
	.i_reg_reverbVolLeft		(reg_reverbVolLeft),
	.i_reg_reverbVolRight		(reg_reverbVolRight),
	.i_reg_ReverbEnable			(reg_ReverbEnable),

/*
	//-------------------------------------------
	//  Register Control From Bus
	//-------------------------------------------
	input  [4:0]			i_channelAdr,
	input 					i_writeLVolume,
	input 					i_writeRVolume,
	input 					i_readLVolume,
	input 					i_ReadRVolume,
	input	[15:0]			i_writeValue,
	output	[15:0]			o_readValue,
*/
	
	// From CD Rom Drive Audio
	.i_CDRomInL_valid		(inputL),
	.i_CDRomInL				(CDRomInL),
	.i_CDRomInR_valid		(inputR),
	.i_CDRomInR				(CDRomInR),
	
	// Register keeping current loaded CD Audio sample
	.o_storedCDRomInL		(storedCDRomInL),
	.o_storedCDRomInR		(storedCDRomInR),

	// Final mix for reverb write back
	.i_accReverb			(reverbWriteValue),
	// [TODO] Add signal here I guess ?
	.o_lineIn				(lineIn),
	
	// To DAC, final samples.
	.o_AOUTL				(AOUTL),
	.o_AOUTR				(AOUTR),
	.o_VALIDOUT				(VALIDOUT),
	
	.i_storePrevVxOut		(storePrevVxOut),
	.o_prevVxOut			(prevChannelVxOut),
	.o_currVxOut			(currChannelVxOut)
);

endmodule
