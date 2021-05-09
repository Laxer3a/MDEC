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
`include "spu_def.sv"

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

wire    [2:0]	SPUMemWRSel;
reg 	[17:0]	internal_adrRAM;
reg		[15:0]	internal_dataOutRAM;

wire writeSPURAM;
assign			o_adrRAM		= internal_adrRAM;
assign 			o_dataReadRAM   = (!writeSPURAM) & (SPUMemWRSel[0] | SPUMemWRSel[1]); // Avoid doing READ when not needed.
assign 			o_dataWriteRAM  = writeSPURAM;
assign			o_dataOutRAM	= internal_dataOutRAM;

wire [17:0] reverbAdr;
wire [15:0] reverbWriteValue;
wire [17:0] reg_dataTransferAddrCurr;
wire  [8:0] regRingBufferIndex;
wire isRight;
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

// Current Voice Registers
wire 	 			currV_NON,currV_KON,currV_PMON,currV_EON;
wire [15:0] 		currV_startAddr,currV_repeatAddr,currV_adpcmCurrAdr;
wire [16:0] 		currV_adpcmPos;
wire [31:0] 		currV_adpcmPrev;
wire signed [14:0] 	currV_VolumeL,currV_VolumeR;
wire [14:0] 		currV_AdsrVol;
wire [15:0] 		currV_AdsrLo,currV_AdsrHi;
wire  [1:0] 		currV_AdsrState;
wire [22:0] 		currV_AdsrCycleCount;
wire [15:0] 		currV_sampleRate;
// 'Enable' registers
wire 				reg_SPUIRQEnable,reg_ReverbEnable,reg_SPUEnable,reg_SPUNotMuted,reg_CDAudioEnabled,reg_CDAudioReverbEnabled;
// Mixing Audio Volume Register
wire signed [15:0]	reg_CDVolumeL,reg_CDVolumeR,reg_mainVolLeft,reg_mainVolRight,reg_reverbVolLeft,reg_reverbVolRight;
// Reverb registers.
wire signed [15:0]  dAPF1,dAPF2,vIIR,vCOMB1, vCOMB2,vCOMB3,vCOMB4,vWALL, vAPF1,vAPF2,mLSAME,mRSAME;
wire signed [15:0]  mLCOMB1,mRCOMB1,mLCOMB2,mRCOMB2, dLSAME,dRSAME,mLDIFF,mRDIFF, mLCOMB3,mRCOMB3,mLCOMB4,mRCOMB4;
wire signed [15:0]  dLDIFF,dRDIFF,mLAPF1,mRAPF1,mLAPF2,mRAPF2,vLIN,vRIN;

wire [15:0]			dataOutw;
wire  [1:0]			reg_SPUTransferMode;
wire [15:0]			reg_ramIRQAddr;
wire [15:0]			reg_mBase;
wire  [17:0] 		reverb_CounterWord;
wire	[3:0]		reg_NoiseFrequShift;
wire	[3:0]		reg_NoiseFrequStep;

spu_front spu_front_inst (
	.i_clk					(i_clk				),
	.n_rst                  (n_rst               ),

	.i_SPUCS                (SPUCS               ),
	.i_SRD                  (SRD                 ),
	.i_SWRO                 (SWRO                ),
	.i_addr			        (addr			     ),
	.i_dataIn               (dataIn              ),

	.i_currVoice            (currVoice           ),

	.i_check_Kevent         (check_Kevent        ),
	.i_clearKON             (clearKON            ),
	.i_incrXFerAdr          (incrXFerAdr         ),
	.i_ctrlSendOut          (ctrlSendOut         ),
	.i_setAsStart           (setAsStart          ),
	.i_setEndX              (setEndX             ),
	.i_isRepeatADPCMFlag    (isRepeatADPCMFlag   ),
	.i_isNotEndADPCMBlock   (isNotEndADPCMBlock  ),
	.i_updateVoiceADPCMAdr  (updateVoiceADPCMAdr ),
	.i_updateVoiceADPCMPos  (updateVoiceADPCMPos ),
	.i_updateVoiceADPCMPrev (updateVoiceADPCMPrev),
	.i_updateADSRVolReg     (updateADSRVolReg    ),
	.i_updateADSRState      (updateADSRState     ),
	.i_validSampleStage2    (validSampleStage2   ),

	.i_side22Khz            (side22Khz           ),

	.i_nextNewBlock         (nextNewBlock        ),

	.i_nextADPCMPos         (nextADPCMPos        ),
	.i_reg_tmpAdpcmPrev     (reg_tmpAdpcmPrev    ),
	.i_nextAdsrCycle        (nextAdsrCycle       ),
	.i_nextAdsrVol          (nextAdsrVol         ),
	.i_nextAdsrState        (nextAdsrState       ),
	
	.i_dataTransferBusy		(dataTransferBusy),
	.i_dataTransferWriteReq (dataTransferWriteReq),
	.i_dataTransferReadReq  (dataTransferReadReq),
	.i_dataTransferRDReq    (dataTransferRDReq),
	.i_reg_SPUIRQSet        (reg_SPUIRQSet),
	
	.o_currV_startAddr		(currV_startAddr	),	
	.o_currV_NON		    (currV_NON		     ),
	.o_currV_repeatAddr		(currV_repeatAddr	),
	.o_currV_adpcmCurrAdr	(currV_adpcmCurrAdr	 ),
	.o_currV_adpcmPos		(currV_adpcmPos		 ),
	.o_currV_adpcmPrev		(currV_adpcmPrev	),
	.o_currV_KON	        (currV_KON	         ),
	.o_currV_PMON	        (currV_PMON	         ),
	.o_currV_EON		    (currV_EON		     ),
	.o_currV_VolumeL	    (currV_VolumeL	     ),
	.o_currV_VolumeR	    (currV_VolumeR	     ),
	.o_currV_AdsrVol	    (currV_AdsrVol	     ),
	.o_currV_AdsrLo	        (currV_AdsrLo	     ),
	.o_currV_AdsrHi	        (currV_AdsrHi	     ),
	.o_currV_AdsrState	    (currV_AdsrState	 ),
	.o_currV_AdsrCycleCount (currV_AdsrCycleCount),
	.o_currV_sampleRate     (currV_sampleRate    ),
	
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
	
	.o_dAPF1					(dAPF1),
	.o_dAPF2	                (dAPF2),
	.o_vIIR	                    (vIIR),
	.o_vCOMB1	                (vCOMB1),

	.o_vCOMB2	                (vCOMB2	),
	.o_vCOMB3	                (vCOMB3	),
	.o_vCOMB4	                (vCOMB4	),
	.o_vWALL	                (vWALL	),

	.o_vAPF1                    (vAPF1),
	.o_vAPF2	                (vAPF2	),
	.o_mLSAME                   (mLSAME),
	.o_mRSAME	                (mRSAME	),

	.o_mLCOMB1	                (mLCOMB1),
	.o_mRCOMB1	                (mRCOMB1),
	.o_mLCOMB2	                (mLCOMB2),
	.o_mRCOMB2	                (mRCOMB2),

	.o_dLSAME	                (dLSAME	),
	.o_dRSAME	                (dRSAME	),
	.o_mLDIFF	                (mLDIFF	),
	.o_mRDIFF	                (mRDIFF	),

	.o_mLCOMB3	                (mLCOMB3),
	.o_mRCOMB3	                (mRCOMB3),
	.o_mLCOMB4	                (mLCOMB4),
	.o_mRCOMB4	                (mRCOMB4),

	.o_dLDIFF	                (dLDIFF	),
	.o_dRDIFF	                (dRDIFF	),
	.o_mLAPF1	                (mLAPF1	),
	.o_mRAPF1	                (mRAPF1	),

	.o_mLAPF2	                (mLAPF2	),
	.o_mRAPF2	                (mRAPF2	),
	.o_vLIN	                    (vLIN	),
	.o_vRIN	                    (vRIN	),
	
	.o_dataOutw				(dataOutw)
);

// -----------------------------------------------------------------
// REGISTER READ / WRITE SECTION
// -----------------------------------------------------------------
wire isD8				= (addr[9:8]==2'b01);
wire isD80_DFF			= (isD8 && addr[7]);							// Latency 0 : D80~DFF

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
wire [4:0] currVoice;
wire [4:0] voiceCounter;
wire		side22Khz;
wire		ctrl44Khz;

wire		clockEnableDivider;
wire		freezableState;

bresenhamCounter
#(	.REALCOUNTERFREQU		(200),	// 40   Mhz / 200000
	.SLOWERIMAGINARYFREQU	(169),	// 33.8 Mhz / 200000
	.BITSIZE				(9)
) bresenhamCounter_instance (
	.i_clk		(i_clk),
	.i_rst		(!n_rst),
	.o_enable	(clockEnableDivider)
);

spu_counter spu_counter_inst(
	.i_clk				(i_clk),
	.n_rst				(n_rst),
	
	.i_onClock			(1'b1/*clockEnableDivider*/),	// Always Enabled for now, bresenham counter ignored.
	.i_safeStopState	(1'b0/*freezableState*/),
	
	.o_ctrl44Khz		(ctrl44Khz),
	.o_side22Khz		(side22Khz),
	.o_voiceCounter		(voiceCounter),
	.o_currVoice		(currVoice)
);

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
wire reverbInactive = (currVoice[4:3] != 2'd3);

// REQ in READ  MODE IS SENDING DATA
// REQ in WRITE MODE IS KEEPING REQUESTING UNTIL FIFO IS FULL.
assign SPUDREQ = (isDMAXferRD & readSPU) | (isDMAXferWR && !isFIFOFull);

wire [2:0] ReverbMemWRSel,voiceSPUMemWRSel;
wire signed [15:0] lineIn;

spu_ReverbCompute spu_ReverbCompute_inst(
	.i_clk					(i_clk),
	.i_rst					(!n_rst),

	.i_side22Khz			(side22Khz),
	.i_reverbInactive		(reverbInactive),
	
	.reg_ReverbEnable		(reg_ReverbEnable),
	
	.i_reg_mBase			(reg_mBase),
	.i_reverb_CounterWord	(reverb_CounterWord),
	.i_dataFromRAM			(i_dataInRAM),
	
	.dAPF1					(dAPF1	),
	.dAPF2					(dAPF2	),
	.vIIR					(vIIR	),
	.vCOMB1					(vCOMB1	),

	.vCOMB2					(vCOMB2	),
	.vCOMB3					(vCOMB3	),
	.vCOMB4					(vCOMB4	),
	.vWALL					(vWALL	),

	.vAPF1					(vAPF1	),
	.vAPF2					(vAPF2	),
	.mLSAME					(mLSAME	),
	.mRSAME					(mRSAME	),

	.mLCOMB1				(mLCOMB1),
	.mRCOMB1				(mRCOMB1),
	.mLCOMB2				(mLCOMB2),
	.mRCOMB2				(mRCOMB2),

	.dLSAME					(dLSAME	),
	.dRSAME					(dRSAME	),
	.mLDIFF					(mLDIFF	),
	.mRDIFF					(mRDIFF	),

	.mLCOMB3				(mLCOMB3),
	.mRCOMB3				(mRCOMB3),
	.mLCOMB4				(mLCOMB4),
	.mRCOMB4				(mRCOMB4),

	.dLDIFF					(dLDIFF	),
	.dRDIFF					(dRDIFF	),
	.mLAPF1					(mLAPF1	),
	.mRAPF1					(mRAPF1	),

	.mLAPF2					(mLAPF2	),
	.mRAPF2					(mRAPF2	),
	.vLIN					(vLIN	),
	.vRIN					(vRIN	),
	
	.i_lineIn				(lineIn),
	
	.o_freezableState		(freezableState),
	
	.o_reverbAdr			(reverbAdr),
	.o_reverbWriteValue		(reverbWriteValue),
	
	.o_SPUMemWRSel			(ReverbMemWRSel),
	.o_SPUMemWRRight		(isRight),
	.o_ctrlSendOut			(ctrlSendOut)
);

spu_voiceStates spu_voiceStates_inst(
	.i_isDMAXferRD			(isDMAXferRD		 ),
	.i_isVoice1             (isVoice1            ),
	.i_isVoice3             (isVoice3            ),
	.i_nextNewBlock         (nextNewBlock        ),
	.i_nextNewLine          (nextNewLine         ),
	.i_reverbInactive       (reverbInactive      ),
	.i_voiceCounter         (voiceCounter        ),
	.i_dataInRAM            (i_dataInRAM         ),
	.i_currVoice            (currVoice           ),

	.o_loadPrev			    (loadPrev			 ),
	.o_updatePrev			(updatePrev			 ),
	.o_check_Kevent		    (check_Kevent		 ),
	.o_storePrevVxOut		(storePrevVxOut		 ),
	.o_clearSum			    (clearSum			 ),
	.o_setEndX				(setEndX			 ),
	.o_setAsStart			(setAsStart			 ),
	.o_zeroIndex			(zeroIndex			 ),
	.o_SPUMemWRSel			(voiceSPUMemWRSel	 ),
	.o_updateVoiceADPCMAdr	(updateVoiceADPCMAdr ),
	.o_updateVoiceADPCMPos  (updateVoiceADPCMPos ),
	.o_updateVoiceADPCMPrev (updateVoiceADPCMPrev),
	.o_adpcmSubSample		(adpcmSubSample		 ),
	.o_isNotEndADPCMBlock	(isNotEndADPCMBlock	 ),
	.o_isRepeatADPCMFlag	(isRepeatADPCMFlag	 ),
	.o_readSPU              (readSPU             ),
	.o_kickFifoRead         (kickFifoRead        )
);

// Select between the two state machines.
assign SPUMemWRSel = reverbInactive ? voiceSPUMemWRSel : ReverbMemWRSel;

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
	
	.i_inputRAW		(i_dataInRAM),
	.i_samplePosition(adpcmSubSample),

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

	.i_reg_SPUEnable		(reg_SPUEnable),
	.i_curr_KON				(currV_KON),
	.i_curr_AdsrVOL			(currV_AdsrVol),
	.i_curr_AdsrLo			(currV_AdsrLo),
	.i_curr_AdsrHi			(currV_AdsrHi),
	.i_curr_AdsrState		(currV_AdsrState),
	.i_curr_AdsrCycleCount	(currV_AdsrCycleCount),
	
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

wire signed	[20:0] sumLeft,sumRight,sumReverb;

spu_AudioAccumulator spu_AudioAccumulatorInstance (
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
		
	.i_storePrevVxOut		(storePrevVxOut),
	.o_prevVxOut			(prevChannelVxOut),
	.o_currVxOut			(currChannelVxOut),
	.o_sumLeft				(sumLeft),
	.o_sumRight				(sumRight),
	.o_sumReverb			(sumReverb)
);

spu_AudioMixer spu_AudioMixerInstance (
	.i_clk					(i_clk),
	.i_rst					(!n_rst),

	.i_sumLeft				(sumLeft),
	.i_sumRight				(sumRight),
	.i_sumReverb			(sumReverb),
	
	.i_side22Khz			(side22Khz),
	.i_ctrlSendOut			(ctrlSendOut),	// When mixing the last sample -> Send out to the audio DAC.
	
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
	.o_VALIDOUT				(VALIDOUT)
);

endmodule
