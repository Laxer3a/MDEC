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
	// When SPU is in DMA READ mode, out 'SPUDREQ' is always '1' EXCEPT when data is output. In this case, SPUDACK is 1.
	// When DMA is reading, SPUDREQ = 0, then read dataOut
	// ______XXXXXXXXXX_XXXXXXXXXX_XXXXXXXXXX_XXXXXXXXXX_XXXXXXXXXX_XXXXXXXXXX_XXXXXXXXXX_______
	,output			SPUDREQ
	// ____________XXXXX______XXXXX______XXXXX______XXXXX______XXXXX______XXXXX______XXXXX______
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
begin debugCnt = (n_rst == 0) ? 24'd0 : debugCnt + 24'd1; end

/* Decide if we loop ADSR cycle counter when reach 0 or 1 ?
	0 = Number of cycle + 1 evaluation !
	1 = Number of cycle exactly.
*/
parameter		CHANGE_ADSR_AT = 23'd1;

reg      [2:0]	SPUMemWRSel;
reg 	[17:0]	internal_adrRAM;
reg		[15:0]	internal_dataOutRAM;

wire writeSPURAM;
assign			o_adrRAM		= internal_adrRAM;
assign 			o_dataReadRAM    = (!writeSPURAM) & (SPUMemWRSel[0] | SPUMemWRSel[1]); // Avoid doing READ when not needed.
assign 			o_dataWriteRAM   = writeSPURAM;

assign			o_dataOutRAM	= internal_dataOutRAM;

parameter	VOICEMD				= 2'd1,
			FIFO_MD				= 2'd2,
			REVB_MD				= 2'd3,
			CDROMMD				= 2'd0;
//
//                                   +--------- Write (1) / Read (0)
//                                   |++------  0:CD, 1:Voice, 2:Fifo, 3:Reverb for read or writeback.
//                                   |||
//                                   |||
//                                   |||
parameter	VOICE_RD			= 3'b001,
			FIFO_RD				= 3'b010,
			REVERB_READ			= 3'b011,
			NO_SPU_READ			= 3'b000,
			//---------------------------
			VOICE_WR			= 3'b101,
			FIFO_WRITE			= 3'b110,
			REVERB_WRITE		= 3'b111,
			CD_WR				= 3'b100;

reg [8:0] regRingBufferIndex;
wire [17:0] reverbAdr;
wire [15:0] reverbWriteValue;
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

always @(*) begin
	// Garbage in case of read, but ignored...
	case (SPUMemWRSel[1:0])
	FIFO_MD		: internal_dataOutRAM = fifoDataOut;
	VOICEMD		: internal_dataOutRAM = vxOut;
	CDROMMD		: internal_dataOutRAM = isRight ? reg_CDRomInR : reg_CDRomInL;
	default		: internal_dataOutRAM = reverbWriteValue; // REVB_MD
	endcase
end

wire readFIFO;
wire isFIFOFull;
wire isFIFOHasData = fifo_r_valid;
wire	[15:0]	fifoDataOut;

wire fifo_r_valid;
wire [6:0] fifo_level;	// TODO : Use FIFO 32 element used == FULL signal.
Fifo2
#(
	.DEPTH_WIDTH	(6),
	.DATA_WIDTH		(16)
)
InternalFifo
(
	.i_clk			(i_clk),
	.i_rst			(!n_rst),
	.i_ena			(1),
	
	.i_w_data		(dataIn),
	.i_w_ena		(writeFIFO),

	.o_r_data		(fifoDataOut),
	.i_r_taken		(readFIFO),

	.o_level		(fifo_level),

	.o_w_full		(isFIFOFull),
	.o_r_valid		(fifo_r_valid)
);


wire internalWrite = SWRO & SPUCS;
wire internalRead  = SRD  & SPUCS;

// --------------------------------------------------------------------------------------
//		[FRONT END : Registers]
// --------------------------------------------------------------------------------------
reg [15:0]	reg_volumeL			[23:0];	// Cn0 Voice Volume Left
reg [15:0]	reg_volumeR			[23:0];	// Cn2 Voice Volume Right
reg [15:0]	reg_sampleRate		[23:0];	// Cn4 VxPitch
reg [15:0]	reg_startAddr		[23:0];	// Cn6 ADPCM Start  Address
reg [14:0]	reg_currentAdsrVOL	[23:0];	// CnC Voice Current ADSR Volume
reg [15:0]	reg_repeatAddr		[23:0];	// CnE ADPCM Repeat Address
reg [15:0]	reg_adsrLo			[23:0];
reg [15:0]	reg_adsrHi			[23:0];

parameter	ADSR_ATTACK		= 2'd0, // May need bit 2 for ADSR_STOPPED ?
			ADSR_DECAY		= 2'd1,
			ADSR_SUSTAIN	= 2'd2,
			ADSR_RELEASE	= 2'd3;
reg [ 1:0]	reg_adsrState		[23:0];

reg [31:0]  reg_adpcmPrev		[23:0];	// [NWRITE]
reg [31:0]  reg_tmpAdpcmPrev;
reg [16:0]	reg_adpcmPos		[23:0];
reg [15:0]  reg_adpcmCurrAdr	[23:0];
reg [22:0]  reg_adsrCycleCount[23:0];

reg [23:0]	reg_ignoreLoadRepeatAddress;

reg signed [15:0]	reg_mainVolLeft;	// D80 Mainvolume Left
reg signed [15:0]	reg_mainVolRight;	// D82 Mainvolume Left
reg signed [15:0]	reg_reverbVolLeft;
reg signed [15:0]	reg_reverbVolRight;
reg [23:0]	reg_kon;					// D88 Voice Key On  (32 bit W)
reg [23:0]	reg_koff;					// D8C Voice Key Off (32 bit W)
reg [23:0]	reg_kEvent;
reg [23:0]	reg_kMode;
reg [23:0]	reg_pmon;					// D90 Voice Pitch Modulation Enabled Flags (PMON)
reg [23:0]	reg_non;					// D94 Voice Noise Enable (32 bit W)
reg [23:0]	reg_eon;
reg [23:0]	reg_endx;					// D9C Voice Status (ENDX)
reg [15:0]	reg_reverb			[31:0];
reg [15:0]	reg_mBase;					// 32 bit ?
reg [15:0]	reg_ramIRQAddr;				// DA4 Sound RAM IRQ Address
reg [15:0]	reg_dataTransferAddr;		// DA6 Sound RAM Data Transfer Address
reg [17:0]  reg_dataTransferAddrCurr;	// Real Counter.

reg signed [15:0]	reg_CDVolumeL;		// DB0 CD Audio Input Volume Left  (CD-DA / XA-ADPCM)
reg signed [15:0]	reg_CDVolumeR;		// DB2 CD Audio Input Volume Right (CD-DA / XA-ADPCM)
reg signed [15:0]	reg_ExtVolumeL;		// DB4 External Input Volume Left
reg signed [15:0]	reg_ExtVolumeR;		// DB6 External Input Volume Right
										// DB8 Current Main Volume Left / DBA Right
										// Exx Voice Current Volume Left / Right (32 bit)
										
										// DAA SPU Control Register (SPUCNT)
reg 		reg_SPUEnable;				//  DAA.15
reg			reg_SPUNotMuted;			//  DAA.14
reg	[3:0]	reg_NoiseFrequShift;		//  DAA.13-10
reg	[3:0]	reg_NoiseFrequStep;			//  DAA.9-8 -> Modified at setup.
reg [1:0]	reg_NoiseStepStore;
reg			reg_ReverbEnable;			//  DAA.7
reg			reg_SPUIRQEnable;			//  DAA.6

parameter	XFER_STOP   = 2'd0,
			XFER_MANUAL = 2'd1,
			XFER_DMAWR  = 2'd2,
			XFER_DMARD  = 2'd3;
reg	[1:0]	reg_SPUTransferMode;		//  DAA.5-4

reg			reg_ExtReverbEnabled;		//  DAA.3
reg			reg_CDAudioReverbEnabled;	//  DAA.2
reg			reg_ExtEnabled;				//  DAA.1
reg			reg_CDAudioEnabled;			//  DAA.0
reg	[15:0]	regSoundRAMDataXFerCtrl;	// DAC Sound RAM Data Transfer Control
										// DAE SPU Status Register (SPUSTAT) (Read only)
reg			reg_SPUIRQSet;

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
// [NREAD] wire isReverb			= isD80_DFF & addr[6];							// Latency 1 : DC0~DFF
wire isChannel			= ((addr[9:8]==2'b00) | (isD8 & !addr[7])); 	// Latency 1 : C00~D7F
wire [4:0] channelAdr	= addr[8:4];

// Detect write transition
wire isDMAXferWR  = (reg_SPUTransferMode == XFER_DMAWR);
wire isDMAXferRD  = (reg_SPUTransferMode == XFER_DMARD);
// TODO is better ? : wire dataTransferBusy		= (isDMAXferWR & fifo_r_valid) | isDMAXferRD;
wire dataTransferBusy		= (reg_SPUTransferMode != XFER_STOP) & fifo_r_valid;	// [TODO : works only for write , not read]
wire dataTransferReadReq 	= reg_SPUTransferMode[1] & reg_SPUTransferMode[0];
wire dataTransferWriteReq	= reg_SPUTransferMode[1] & (!reg_SPUTransferMode[0]);
wire dataTransferRDReq		= reg_SPUTransferMode[1];

// [Write to FIFO only on transition from internalwrite from 0->1 but allow BURST with DMA transfer] 
//  --> PROTECTED FOR EDGE TRANSITION : WRITE during multiple cycle else would perform multiple WRITE of the same value !!!!
// Implicit in writeFIFO, not used : wire isCPUXFer = (reg_SPUTransferMode == XFER_MANUAL);
wire writeFIFO = internalWrite & (!PInternalWrite | isDMAXferWR) & isD80_DFF & (!addr[6]) & (addr[5:1] == 5'h14);
reg PInternalWrite;
always @(posedge i_clk)
begin
	if (n_rst == 0) begin
		PInternalWrite = 1'b0;
	end else begin
		PInternalWrite = internalWrite;
	end
end

reg updateVoiceADPCMAdr;
reg regIsLastADPCMBlk;
reg reg_isRepeatADPCMFlag;

always @(posedge i_clk)
begin
	if (n_rst == 0)
	begin
		reg_mainVolLeft				= 16'h0;
		reg_mainVolRight			= 16'h0;
		reg_reverbVolLeft			= 16'h0;
		reg_reverbVolRight			= 16'h0;
		reg_kon						= 24'h0;
		reg_koff					= 24'h0;
		reg_kEvent					= 24'h0;
		reg_kMode					= 24'h0;
		reg_pmon					= 24'h0;
		reg_non						= 24'h0;
		reg_eon						= 24'h0;
		reg_mBase					= 16'h0;
		reg_ramIRQAddr				= 16'h0;
		reg_dataTransferAddr		= 16'h0;
		reg_CDVolumeL				= 16'h0;
		reg_CDVolumeR				= 16'h0;
		reg_ExtVolumeL				= 16'h0;
		reg_ExtVolumeR				= 16'h0;
		reg_SPUEnable				= 1'b0;
		reg_SPUNotMuted				= 1'b0;
		reg_NoiseFrequShift			= 4'b0000;
		reg_NoiseFrequStep			= 4'b1100;
		reg_NoiseStepStore			= 2'b00;
		reg_ReverbEnable			= 1'b0;
		reg_SPUIRQEnable			= 1'b0;
		reg_SPUTransferMode			= 2'b00;	// STOP Transfer by default.
		reg_ExtReverbEnabled		= 1'b0;
		reg_CDAudioReverbEnabled	= 1'b0;
		reg_ExtEnabled				= 1'b0;
		reg_CDAudioEnabled			= 1'b0;
		regSoundRAMDataXFerCtrl		= 16'h4;
		reg_ignoreLoadRepeatAddress	= 24'd0;
		reg_endx					= 24'd0;
		regRingBufferIndex			= 9'd0;
		regIsLastADPCMBlk			= 1'b0;
		reg_isRepeatADPCMFlag		= 1'b0;
		reverb_CounterWord			= 18'd0;
	end else begin
		if (internalWrite) begin
			if (isD80_DFF) begin		// D80~DFF
				// 011xxx.xxxx
				if (addr[6]==0) begin	// D80~DBF
					// 0110xx.xxxx
					case (addr[5:1])	
					// D8x ---------------
					// [Address IN WORD, not in BYTE LIKE COMMENTS !!! Take care]
					5'h00:	reg_mainVolLeft		= dataIn;			// 1F801D80h - 180h
					5'h01:	reg_mainVolRight	= dataIn;			// 1F801D82h - 182h
					5'h02:	reg_reverbVolLeft	= dataIn;			// 1F801D84h - 184h
					5'h03:	reg_reverbVolRight	= dataIn;			// 1F801D86h - 186h
					5'h04:	begin
								reg_kon [15: 0]		= dataIn;		// 1F801D88h - 188h
								if (dataIn [0] & (reg_kEvent [ 0]==0)) begin reg_kEvent [0] = 1; reg_kMode [0] = 1; end
								if (dataIn [1] & (reg_kEvent [ 1]==0)) begin reg_kEvent [1] = 1; reg_kMode [1] = 1; end
								if (dataIn [2] & (reg_kEvent [ 2]==0)) begin reg_kEvent [2] = 1; reg_kMode [2] = 1; end
								if (dataIn [3] & (reg_kEvent [ 3]==0)) begin reg_kEvent [3] = 1; reg_kMode [3] = 1; end
								if (dataIn [4] & (reg_kEvent [ 4]==0)) begin reg_kEvent [4] = 1; reg_kMode [4] = 1; end
								if (dataIn [5] & (reg_kEvent [ 5]==0)) begin reg_kEvent [5] = 1; reg_kMode [5] = 1; end
								if (dataIn [6] & (reg_kEvent [ 6]==0)) begin reg_kEvent [6] = 1; reg_kMode [6] = 1; end
								if (dataIn [7] & (reg_kEvent [ 7]==0)) begin reg_kEvent [7] = 1; reg_kMode [7] = 1; end
								if (dataIn [8] & (reg_kEvent [ 8]==0)) begin reg_kEvent [8] = 1; reg_kMode [8] = 1; end
								if (dataIn [9] & (reg_kEvent [ 9]==0)) begin reg_kEvent [9] = 1; reg_kMode [9] = 1; end
								if (dataIn[10] & (reg_kEvent [10]==0)) begin reg_kEvent[10] = 1; reg_kMode[10] = 1; end
								if (dataIn[11] & (reg_kEvent [11]==0)) begin reg_kEvent[11] = 1; reg_kMode[11] = 1; end
								if (dataIn[12] & (reg_kEvent [12]==0)) begin reg_kEvent[12] = 1; reg_kMode[12] = 1; end
								if (dataIn[13] & (reg_kEvent [13]==0)) begin reg_kEvent[13] = 1; reg_kMode[13] = 1; end
								if (dataIn[14] & (reg_kEvent [14]==0)) begin reg_kEvent[14] = 1; reg_kMode[14] = 1; end
								if (dataIn[15] & (reg_kEvent [15]==0)) begin reg_kEvent[15] = 1; reg_kMode[15] = 1; end
							end
					5'h05:	begin									// 1F801D8Ah - 18Ah
								reg_kon [23:16]		= dataIn[7:0];
								if (dataIn [0] & (reg_kEvent [16]==0)) begin reg_kEvent[16] = 1; reg_kMode[16] = 1; end
								if (dataIn [1] & (reg_kEvent [17]==0)) begin reg_kEvent[17] = 1; reg_kMode[17] = 1; end
								if (dataIn [2] & (reg_kEvent [18]==0)) begin reg_kEvent[18] = 1; reg_kMode[18] = 1; end
								if (dataIn [3] & (reg_kEvent [19]==0)) begin reg_kEvent[19] = 1; reg_kMode[19] = 1; end
								if (dataIn [4] & (reg_kEvent [20]==0)) begin reg_kEvent[20] = 1; reg_kMode[20] = 1; end
								if (dataIn [5] & (reg_kEvent [21]==0)) begin reg_kEvent[21] = 1; reg_kMode[21] = 1; end
								if (dataIn [6] & (reg_kEvent [22]==0)) begin reg_kEvent[22] = 1; reg_kMode[22] = 1; end
								if (dataIn [7] & (reg_kEvent [23]==0)) begin reg_kEvent[23] = 1; reg_kMode[23] = 1; end
							end
					5'h06:	begin									// 1F801D8Ch - 18Ch
								reg_koff[15: 0]		= dataIn;			
								if (dataIn [0] & (reg_kEvent [ 0]==0)) begin reg_kEvent [0] = 1; reg_kMode [0] = 0; end
								if (dataIn [1] & (reg_kEvent [ 1]==0)) begin reg_kEvent [1] = 1; reg_kMode [1] = 0; end
								if (dataIn [2] & (reg_kEvent [ 2]==0)) begin reg_kEvent [2] = 1; reg_kMode [2] = 0; end
								if (dataIn [3] & (reg_kEvent [ 3]==0)) begin reg_kEvent [3] = 1; reg_kMode [3] = 0; end
								if (dataIn [4] & (reg_kEvent [ 4]==0)) begin reg_kEvent [4] = 1; reg_kMode [4] = 0; end
								if (dataIn [5] & (reg_kEvent [ 5]==0)) begin reg_kEvent [5] = 1; reg_kMode [5] = 0; end
								if (dataIn [6] & (reg_kEvent [ 6]==0)) begin reg_kEvent [6] = 1; reg_kMode [6] = 0; end
								if (dataIn [7] & (reg_kEvent [ 7]==0)) begin reg_kEvent [7] = 1; reg_kMode [7] = 0; end
								if (dataIn [8] & (reg_kEvent [ 8]==0)) begin reg_kEvent [8] = 1; reg_kMode [8] = 0; end
								if (dataIn [9] & (reg_kEvent [ 9]==0)) begin reg_kEvent [9] = 1; reg_kMode [9] = 0; end
								if (dataIn[10] & (reg_kEvent [10]==0)) begin reg_kEvent[10] = 1; reg_kMode[10] = 0; end
								if (dataIn[11] & (reg_kEvent [11]==0)) begin reg_kEvent[11] = 1; reg_kMode[11] = 0; end
								if (dataIn[12] & (reg_kEvent [12]==0)) begin reg_kEvent[12] = 1; reg_kMode[12] = 0; end
								if (dataIn[13] & (reg_kEvent [13]==0)) begin reg_kEvent[13] = 1; reg_kMode[13] = 0; end
								if (dataIn[14] & (reg_kEvent [14]==0)) begin reg_kEvent[14] = 1; reg_kMode[14] = 0; end
								if (dataIn[15] & (reg_kEvent [15]==0)) begin reg_kEvent[15] = 1; reg_kMode[15] = 0; end
							end
					5'h07:	begin									// 1F801D8Eh - 18Eh
								reg_koff[23:16]		= dataIn[7:0];		
								if (dataIn [0] & (reg_kEvent [16]==0)) begin reg_kEvent[16] = 1; reg_kMode[16] = 0; end
								if (dataIn [1] & (reg_kEvent [17]==0)) begin reg_kEvent[17] = 1; reg_kMode[17] = 0; end
								if (dataIn [2] & (reg_kEvent [18]==0)) begin reg_kEvent[18] = 1; reg_kMode[18] = 0; end
								if (dataIn [3] & (reg_kEvent [19]==0)) begin reg_kEvent[19] = 1; reg_kMode[19] = 0; end
								if (dataIn [4] & (reg_kEvent [20]==0)) begin reg_kEvent[20] = 1; reg_kMode[20] = 0; end
								if (dataIn [5] & (reg_kEvent [21]==0)) begin reg_kEvent[21] = 1; reg_kMode[21] = 0; end
								if (dataIn [6] & (reg_kEvent [22]==0)) begin reg_kEvent[22] = 1; reg_kMode[22] = 0; end
								if (dataIn [7] & (reg_kEvent [23]==0)) begin reg_kEvent[23] = 1; reg_kMode[23] = 0; end
							end
					// D9x ---------------
					5'h08:	reg_pmon[15: 1]		= dataIn[15:1];		// 1F801D90h - 190h /* By reset also reg_pmon[0] = 1'b0; */
					5'h09:	reg_pmon[23:16]		= dataIn[7:0];		// 1F801D92h - 192h
					5'h0A:	reg_non [15: 0]		= dataIn;			// 1F801D94h - 194h
					5'h0B:	reg_non [23:16]		= dataIn[7:0];		// 1F801D96h - 196h
					5'h0C:	reg_eon [15: 0]		= dataIn;			// 1F801D98h - 198h
					5'h0D:	reg_eon [23:16]		= dataIn[7:0];		// 1F801D9Ah - 19Ah
					// 5'h0E: Do nothing ENDX is READONLY.			// 1F801D9Ch - 19Ch
					// 5'h0F: Do nothing ENDX is READONLY.			// 1F801D9Eh - 19Eh
					// DAx ---------------
					// 5'h10: [1F801DA0] Do nothing... (WEIRD reg)
					5'h11:	begin
								reg_mBase			= dataIn;		// 1F801DA2h - 1A2h
								reverb_CounterWord	= 18'd0;
							end
					5'h12:	reg_ramIRQAddr		= dataIn;			// 1F801DA4h - 1A4h
					5'h13:	begin									// 1F801DA6h - 1A6h
								// Adress (dataIn) is multiple x8 in byte adress.
								reg_dataTransferAddr	 = dataIn;
								reg_dataTransferAddrCurr = {dataIn, 2'd0}; // x8 in byte -> 4x in half-word.
							end
					5'h14:	begin									// 1F801DA8h - 1A8h
								// FIFO INPUT implemented, just not done here.
							end
					5'h15:	begin // SPU Control register			// 1F801DAAh - 1AAh
							reg_SPUEnable		= dataIn[15];
							reg_SPUNotMuted		= dataIn[14];
							reg_NoiseFrequShift	= dataIn[13:10];
							reg_NoiseFrequStep	= negNoiseStep; // See logic with dataIn[9:8];
							reg_NoiseStepStore	= dataIn[9:8];
							reg_ReverbEnable	= dataIn[7];
							reg_SPUIRQEnable	= dataIn[6];
							reg_SPUTransferMode	= dataIn[5:4];
							reg_ExtReverbEnabled		= dataIn[3];
							reg_CDAudioReverbEnabled	= dataIn[2];
							reg_ExtEnabled		= dataIn[1];
							reg_CDAudioEnabled	= dataIn[0];
							end
					5'h16:	regSoundRAMDataXFerCtrl = dataIn;
					// 5'h17:	SPUSTAT is READ ONLY.
					// DBx ---------------
					5'h18:	reg_CDVolumeL		= dataIn;
					5'h19:	reg_CDVolumeR		= dataIn;
					5'h1A:	reg_ExtVolumeL		= dataIn;
					5'h1B:	reg_ExtVolumeR		= dataIn;
					// 5'h1C: Current Main Volume Left
					// 5'h1D: Current Main Volume Right
					// 5'h1E: 4B/DF
					// 5'h1F: 80/21
					default: ;/* Do nothing */
					endcase
				end else begin	// DC0~DFF
					// 0111xx.xxxx
					reg_reverb[addr[5:1]] <= dataIn;
				end
			end else begin
				if (isChannel) begin
					// 00xxxx.xxxx
					// 010xxx.xxxx
					if (addr[3:1]==3'b000) begin
						// 1F801xx0h - Voice 0..23 Volume Left
						reg_volumeL[channelAdr]	= dataIn;
					end
					if (addr[3:1]==3'b001) begin
						// 1F801xx2h - Voice 0..23 Volume Right
						reg_volumeR[channelAdr]	= dataIn;
					end
					if (addr[3:1]==3'b010) begin
						// 1F801xx4h - Voice 0..23 ADPCM Sample Rate    (R/W) [15:0] (VxPitch)
						reg_sampleRate[channelAdr]	= dataIn;
					end
					if (addr[3:1]==3'b011) begin
						// 1F801xx6h - Voice 0..23 ADPCM Start Address
						reg_startAddr[channelAdr]	= dataIn;
					end
					if (addr[3:1]==3'b100) begin
						// 1F801xx8h LSB - Voice 0..23 Attack/Decay/Sustain/Release (ADSR) (32bit) [15:0]x2
						reg_adsrLo[channelAdr]		= dataIn;
					end
					if (addr[3:1]==3'b101) begin
						// 1F801xx8h (xxA) MSB - Voice 0..23 Attack/Decay/Sustain/Release (ADSR) (32bit) [15:0]x2
						reg_adsrHi[channelAdr]		= dataIn;
					end
					if (addr[3:1]==3'b110) begin
						// 1F801xxCh - Voice 0..23 Current ADSR volume (R/W) (0..+7FFFh) (or -8000h..+7FFFh on manual write)
						reg_currentAdsrVOL[channelAdr]	= dataIn[14:0];
					end
					if (addr[3:1]==3'b111) begin
						reg_ignoreLoadRepeatAddress[channelAdr] = 1'b1;
						reg_repeatAddr[channelAdr] = dataIn;
					end
				end // else 1xxxxx.xxxx <--- ELSE
					// Current volume L/R channels. (1F801E00h..1F801E5Fh)
					// 1E60~1FFFF Unknown/Unused
			end
		end // end write

		//
		// [OUTSIDE OF WRITE]
		//
		if (check_Kevent) begin
			if (reg_kEvent[currVoice]) begin	// KON or KOFF occured to this channel...
				// Force reset counter to accept new 'state'.
				reg_adsrCycleCount[currVoice] = CHANGE_ADSR_AT;
				if (reg_kMode[currVoice]) begin // Voice start [TODO : have bit that said voice is stopped and check it : reg_endx ?]
					reg_currentAdsrVOL[currVoice] = 15'd0;
					reg_adpcmCurrAdr[currVoice] = currV_startAddr;
					reg_adsrState	[currVoice] = ADSR_ATTACK;
					reg_adpcmPos	[currVoice] = 17'd0;
					reg_endx		[currVoice] = 1'b0;
					reg_adpcmPrev	[currVoice] = 32'd0;
					
					if (reg_ignoreLoadRepeatAddress[currVoice] == 1'b0) begin
						reg_repeatAddr[currVoice] = currV_startAddr;
					end

					// Optionnal... can't stay for ever... ? What's the point, else everything ends up 1.
					// reg_kon			[currVoice] = 1'b0;
				end else begin
					reg_adsrState	[currVoice] = ADSR_RELEASE;
					reg_koff		[currVoice] = 1'b0;
				end
			end
			reg_kEvent			[currVoice] = 1'b0; // Reset Event.
		end
		
		if (clearKON) begin
			reg_kon[currVoice] = 1'b0;
		end
		
		
		if (setAsStart) begin
			reg_repeatAddr	[currVoice] = currV_adpcmCurrAdr;
		end
		
		if (setEndX) begin
			reg_isRepeatADPCMFlag	= isRepeatADPCMFlag; // Store value for later usage a few cycles later...
			regIsLastADPCMBlk		= 1'b1;
		end else if (isNotEndADPCMBlock) begin
			regIsLastADPCMBlk		= 1'b0;
		end
		
		if (updateVoiceADPCMAdr) begin
			if (regIsLastADPCMBlk && (!NON)) begin		// NON checked here : we don't want RELEASE and ENDX to happen in Noise Mode. -> Garbage ADPCM can modify things.
				reg_endx		[currVoice] = 1'b1;
				if ((!reg_isRepeatADPCMFlag)) begin 	// Voice must be in ADPCM mode to use flag.
					reg_adsrState	  [currVoice] = ADSR_RELEASE;
					reg_currentAdsrVOL[currVoice] = 15'd0;
				end
			end
			reg_adpcmCurrAdr[currVoice] = regIsLastADPCMBlk ? currV_repeatAddr : {currV_adpcmCurrAdr + 16'd2};	// Skip 16 byte for next ADPCM block.
		end
		
		if (updateVoiceADPCMPos) begin
			// If next block, point to the correct SAMPLE and SUB sample position.
			// else           point to the correct SAMPLE with INDEX and sub sample position.
			reg_adpcmPos[currVoice]		= { {nextNewBlock ? 3'd0 : nextADPCMPos[16:14]} , nextADPCMPos[13:0] };
		end

		if (updateVoiceADPCMPrev) begin
			reg_adpcmPrev[currVoice]	= reg_tmpAdpcmPrev;
		end

		if (incrXFerAdr) begin
			reg_dataTransferAddrCurr = reg_dataTransferAddrCurr + 18'd1; // One half-word increment.
		end
		
		if (ctrlSendOut) begin
			regRingBufferIndex = regRingBufferIndex + 9'd1;
		end
		
		// Updated each time a new sample is issued over the voice.
		if (validSampleStage2) begin
			reg_adsrCycleCount[currVoice]	= nextAdsrCycle;
		end
		// Updated each time a new sample AND counter reach ZERO.
		if (validSampleStage2 & reachZero) begin
			reg_currentAdsrVOL[currVoice]	= nextAdsrVol;
		end
		if (changeADSRState) begin
			reg_adsrState[currVoice]		= nextAdsrState;
		end
		if (ctrlSendOut & side22Khz) begin
			//  if counter == last valid index -> loop to zero.
			if (reverb_CounterWord == {~reg_mBase,2'b11}) begin
				// reverb_CounterWord+1   >= 262144 -  reg_mBase
				// reverb_CounterWord+1-1 >= 262144 -  reg_mBase   -1
				// reverb_CounterWord     >= 262144 + ~reg_mBase+1 -1
				// reverb_CounterWord     >=          ~reg_mBase+1 -1  (262144 out of range 17:0, loop counter, not needed), +1-1 simplify.
				// replace                ==          ~reg_mBase
				reverb_CounterWord = 18'd0;
			end else begin
				reverb_CounterWord = reverb_CounterWord + 18'd1;
			end
		end
	end // end reset
end // end always block

reg [15:0] dataOutw;

assign dataOut		= readSPU ? i_dataInRAM : dataOutw;

reg internalReadPipe;
reg incrXFerAdr;
always @ (posedge i_clk) 
begin
	internalReadPipe	= internalRead;
	incrXFerAdr			= readFIFO | readSPU;
end

assign dataOutValid	= internalReadPipe; // Pipe read. For now everything answer at the NEXT clock, ONCE.

// Read output
always @ (*)
begin
	if (isD80_DFF) begin			// D80~DFF
		if (addr[6]==0) begin		// D80~DBF
			case (addr[5:1])
			// D8x
			5'h00:	dataOutw = reg_mainVolLeft;				// 1F801D80h
			5'h01:	dataOutw = reg_mainVolRight;			// 1F801D82h
			5'h02:	dataOutw = reg_reverbVolLeft;			// 1F801D84h
			5'h03:	dataOutw = reg_reverbVolRight;			// 1F801D86h
			5'h04:	dataOutw = reg_kon [15: 0];				// 1F801D88h
			5'h05:	dataOutw = { 8'd0, reg_kon [23:16] };	// 1F801D8Ah
			5'h06:	dataOutw = reg_koff[15: 0];				// 1F801D8Ch
			5'h07:	dataOutw = { 8'd0, reg_koff[23:16] };	// 1F801D8Eh
			// D9x
			5'h08:	dataOutw = reg_pmon[15: 0];				// 1F801D90h Force channel ZERO to have no PMON at WRITE.
			5'h09:	dataOutw = { 8'd0, reg_pmon[23:16] };
			5'h0A:	dataOutw = reg_non [15: 0];				// 1F801D94h
			5'h0B:	dataOutw = { 8'd0, reg_non [23:16] };
			5'h0C:	dataOutw = reg_eon [15: 0];				// 1F801D98h
			5'h0D:	dataOutw = { 8'd0, reg_eon [23:16] };
			5'h0E:	dataOutw = reg_endx[15: 0];				// 1F801D9Ch
			5'h0F:	dataOutw = { 8'd0, reg_endx[23:16] };
			// DAx
			5'h10:	dataOutw = 16'h9D78;					// 1F801DA0h - Some kind of a read-only status register.. or just garbage..0-15
			5'h11:	dataOutw = reg_mBase;					// 1F801DA2h
			5'h12:	dataOutw = reg_ramIRQAddr;				// 1F801DA4h
			5'h13:	dataOutw = reg_dataTransferAddr;		// 1F801DA6h
			5'h14:	dataOutw = 16'hFF; 						// 1F801DA8h Can't read FIFO.
			5'h15:	begin 									// 1F801DAAh SPU Control register
					dataOutw = { 	reg_SPUEnable,
									reg_SPUNotMuted,
									reg_NoiseFrequShift,
									reg_NoiseStepStore /* cant use converted value to reg_NoiseFrequStep*/,
									reg_ReverbEnable,
									reg_SPUIRQEnable,
									reg_SPUTransferMode,
									reg_ExtReverbEnabled,
									reg_CDAudioReverbEnabled,
									reg_ExtEnabled,
									reg_CDAudioEnabled	
								};
					end
			5'h16:	dataOutw = regSoundRAMDataXFerCtrl;		// 1F801DACh Sound RAM Data Transfer Control
			5'h17:	dataOutw = {
									// SPU Status Register (SPUSTAT) Read only.
									//  15-12 Unknown/Unused (seems to be usually zero)
									4'd0,
									//  11    Writing to First/Second half of Capture Buffers (0=First, 1=Second)
									regRingBufferIndex[8],
									//  10    Data Transfer Busy Flag          (0=Ready, 1=Busy)
									dataTransferBusy,
									//  9     Data Transfer DMA Read Request   (0=No, 1=Yes)
									dataTransferReadReq,
									//  8     Data Transfer DMA Write Request  (0=No, 1=Yes)
									dataTransferWriteReq,
									//  7     Data Transfer DMA Read/Write Request ;seems to be same as SPUCNT.Bit5
									dataTransferRDReq,
									//  6     IRQ9 Flag                        (0=No, 1=Interrupt Request)
									reg_SPUIRQSet,
									//  5-0   Current SPU Mode   (same as SPUCNT.Bit5-0, but, applied a bit delayed)
									reg_SPUTransferMode,
									reg_ExtReverbEnabled,
									reg_CDAudioReverbEnabled,
									reg_ExtEnabled,
									reg_CDAudioEnabled
								};
			// DBx
			5'h18:	dataOutw = reg_CDVolumeL;
			5'h19:	dataOutw = reg_CDVolumeR;
			5'h1A:	dataOutw = reg_ExtVolumeL;
			5'h1B:	dataOutw = reg_ExtVolumeR;
			5'h1C:	dataOutw = reg_mainVolLeft;	 // Current Main Volume Left  : cheat
			5'h1D:	dataOutw = reg_mainVolRight; // Current Main Volume Right : cheat
			5'h1E: 	dataOutw = 16'h4BDF; // Weird 1DBC
			5'h1F:	dataOutw = 16'h8021; // Weird 1DBE
			endcase
		end else begin				// DC0~DFF
			dataOutw = reg_reverb[addr[5:1]];
		end
	end else if (isChannel) begin	// C00~D7F
		case (addr[3:1])
		3'b000:dataOutw = reg_volumeL		[channelAdr];
		3'b001:dataOutw = reg_volumeR		[channelAdr];
		3'b010:dataOutw = reg_sampleRate	[channelAdr];
		3'b011:dataOutw = reg_startAddr		[channelAdr];
		3'b100:dataOutw = reg_adsrLo		[channelAdr];
		3'b101:dataOutw = reg_adsrHi		[channelAdr];
		3'b110:dataOutw = {1'b0,reg_currentAdsrVOL[channelAdr]};
		3'b111:dataOutw = reg_repeatAddr	[channelAdr];
		endcase
	end else begin					// E00-FFF
		// [1E00~1E7F]
		// 111|0.0xxx.xxxx
		if (addr[8:7] == 2'b00) begin
			// Current volume L/R channels. (1F801E00h..1F801E5Fh)
			if (addr[6:4] < 3'd6) begin
				// 96 bytes
				if (addr[1]) begin
					dataOutw = reg_volumeR[channelAdr];
				end else begin
					dataOutw = reg_volumeL[channelAdr];
				end
			end else begin
				// 32 bytes
				// >= 1F801E60~EFF
				case (addr[4:1])			// Hard coded stupid stuff, but never know for backward comp.
				4'h0 : dataOutw = 16'h7E61;
				4'h1 : dataOutw = 16'hA996;
				4'h2 : dataOutw = 16'h4739;
				4'h3 : dataOutw = 16'hF91E;
				4'h4 : dataOutw = 16'hE1E1;
				4'h5 : dataOutw = 16'h80DD; 
				4'h6 : dataOutw = 16'hE817;
				4'h7 : dataOutw = 16'h7FFB;
				4'h8 : dataOutw = 16'hFBBF;
				4'h9 : dataOutw = 16'h1D6C;
				4'hA : dataOutw = 16'h8FEC; 
				4'hB : dataOutw = 16'hF304;
				4'hC : dataOutw = 16'h0623;
				4'hD : dataOutw = 16'h8945;
				4'hE : dataOutw = 16'hC16D;
				4'hF : dataOutw = 16'h3182;
				endcase
			end
		end else begin
			// 111|0.1xxx.xxxx
			// 111|1.0xxx.xxxx
			// 111|1.1xxx.xxxx
			// 1E80-1EFF : 128 bytes
			// 1F00-1FFF : 256 bytes
			dataOutw = 16'd0;
		end
	end
end

wire  [15:0] currV_sampleRate	= reg_sampleRate[currVoice];
wire  [15:0] currV_startAddr	= reg_startAddr	[currVoice];
wire  [15:0] currV_repeatAddr	= reg_repeatAddr[currVoice];
wire  [16:0] currV_adpcmPos		= reg_adpcmPos	[currVoice];
wire  [15:0] currV_adpcmCurrAdr	= reg_adpcmCurrAdr[currVoice];
wire  [31:0] currV_adpcmPrev	= reg_adpcmPrev	[currVoice];

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
		voiceCounter		= 5'd0;
		currVoice6Bit		= 6'd0;
	end else begin
		if (isLastCycle) begin
			voiceCounter = 5'd0;
			currVoice6Bit	= currVoice6Bit + 6'd1;
		end else begin
			voiceCounter = voiceCounter + 5'd1; 
		end
	end
end

reg [3:0] currV_shift;
reg [2:0] currV_filter;
wire signed [15:0] sampleOutADPCMRAW;

always @(posedge i_clk)
begin
	if (loadPrev) begin
		currV_shift		= i_dataInRAM[3:0];
		currV_filter	= i_dataInRAM[6:4];
	end
	
	if (reg_SPUIRQEnable && (reg_ramIRQAddr==o_adrRAM[17:2])) begin
		reg_SPUIRQSet = 1'b1;
	end
	if (reg_SPUIRQEnable == 1'b0 /* || (n_rst == 0) */) begin // On Reset, enable will reset the IRQ with 1 cycle latency... No need for n_rst signal.
		// Acknowledge if IRQ was set.
		reg_SPUIRQSet = 1'b0;
	end
	if (loadPrev) begin
		reg_tmpAdpcmPrev = currV_adpcmPrev;
	end
	if (updatePrev) begin
		reg_tmpAdpcmPrev = { reg_tmpAdpcmPrev[15:0], sampleOutADPCMRAW };
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
		reverbCnt = 8'd0;
	end else begin
		reverbCnt = reverbCnt + 8'd1;
	end
end

// 000xx
wire signed [15:0] dAPF1	= reg_reverb[0];
wire signed [15:0] dAPF2	= reg_reverb[1];
wire signed [15:0]  vIIR	= reg_reverb[2];
wire signed [15:0] vCOMB1	= reg_reverb[3];

// 001xx
wire signed [15:0] vCOMB2	= reg_reverb[4];
wire signed [15:0] vCOMB3	= reg_reverb[5];
wire signed [15:0] vCOMB4	= reg_reverb[6];
wire signed [15:0] vWALL	= reg_reverb[7];

// 010xx
wire signed [15:0] vAPF1	= reg_reverb[8];
wire signed [15:0] vAPF2	= reg_reverb[9];
wire signed [15:0] mLSAME	= reg_reverb[10];
wire signed [15:0] mRSAME	= reg_reverb[11];

wire signed [15:0] negvAPF1	= (~vAPF1) + 16'd1;
wire signed [15:0] negvAPF2	= (~vAPF2) + 16'd1;

// 011xx
wire signed [15:0] mLCOMB1	= reg_reverb[12];
wire signed [15:0] mRCOMB1	= reg_reverb[13];
wire signed [15:0] mLCOMB2	= reg_reverb[14];
wire signed [15:0] mRCOMB2	= reg_reverb[15];

// 100xx
wire signed [15:0] dLSAME	= reg_reverb[16];
wire signed [15:0] dRSAME	= reg_reverb[17];
wire signed [15:0] mLDIFF	= reg_reverb[18];
wire signed [15:0] mRDIFF	= reg_reverb[19];

// 101xx
wire signed [15:0] mLCOMB3	= reg_reverb[20];
wire signed [15:0] mRCOMB3	= reg_reverb[21];
wire signed [15:0] mLCOMB4	= reg_reverb[22];
wire signed [15:0] mRCOMB4	= reg_reverb[23];

// 110xx
wire signed [15:0] dLDIFF	= reg_reverb[24];
wire signed [15:0] dRDIFF	= reg_reverb[25];
wire signed [15:0] mLAPF1	= reg_reverb[26];
wire signed [15:0] mRAPF1	= reg_reverb[27];

// 111xx
wire signed [15:0] mLAPF2	= reg_reverb[28];
wire signed [15:0] mRAPF2	= reg_reverb[29];
wire signed [15:0] vLIN		= reg_reverb[30];
wire signed [15:0] vRIN		= reg_reverb[31];

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
	accReverb = clampedAddC;
end

reg [15:0] adrB;

reg [3:0] sideAReg;
reg [4:0] sideBReg;
reg       minus2;
reg [1:0] selB;
reg       accAdd;
reg		  isRight;

parameter 	SA_VWALL	=	4'h0,
			SA_VIIR		=	4'h1,
			SA_ZERO		=	4'h2,
			SA_ONE		=	4'h3,
			SA_COMB1	=	4'h4,
			SA_COMB2	=	4'h5,
			SA_COMB3	=	4'h6,
			SA_COMB4	=	4'h7,
			SA_VAPF1	=	4'h8,
			SA_VAPF2	=	4'h9,
			SA_NVAPF1	=	4'hA,
			SA_NVAPF2	=	4'hB,
			SA_NEG_ONE	=	4'hC,
			SA_VIN		=	4'hD;
			
parameter 	SB_DLSAME	=	5'h0,
			SB_DRSAME	=	5'h1,
			SB_MLSAME	=	5'h2,
			SB_MRSAME	=	5'h3,

			SB_DLDIFF	=	5'h4,
			SB_DRDIFF	=	5'h5,
			SB_MLDIFF	=	5'h6,
			SB_MRDIFF	=	5'h7,

			SB_MLCOMB1	=	5'h8,
			SB_MRCOMB1	=	5'h9,
			SB_MLCOMB2	=	5'hA,
			SB_MRCOMB2	=	5'hB,

			SB_MLCOMB3	=	5'hC,
			SB_MRCOMB3	=	5'hD,
			SB_MLCOMB4	=	5'hE,
			SB_MRCOMB4	=	5'hF,

			SB_MLAPF1_ADPF1 =	5'h10,
			SB_MRAPF1_ADPF1 =	5'h11,
			SB_MLAPF2_ADPF2 =	5'h12,
			SB_MRAPF2_ADPF2 =	5'h13,
			
			SB_MLAPF1 =	5'h14,
			SB_MRAPF1 =	5'h15,
			SB_MLAPF2 =	5'h16,
			SB_MRAPF2 =	5'h17,
			
			SB_FAKEREAD 	  =	5'h18;

parameter 	SB_DxSAME		=	4'h0,
			SB_MxSAME		=	4'h1,
			SB_DxDIFF		=	4'h2,
			SB_MxDIFF		=	4'h3,
			SB_MxCOMB1		=	4'h4,
			SB_MxCOMB2		=	4'h5,
			SB_MxCOMB3		=	4'h6,
			SB_MxCOMB4		=	4'h7,
			SB_MxAPF1_ADPF1 =	4'h8,
			SB_MxAPF2_ADPF2 =	4'h9,
			SB_MxAPF1 		=	4'hA,
			SB_MxAPF2		=	4'hB;
			
parameter	SEL_IN	  = 2'd0,
			SEL_RAM	  = 2'd1,
			SEL_ACC	  = 2'd2;

                   //15->17 bit +   0/-1 Half Word.(-2 byte)
wire [17:0] reverbAdrPreRing = {adrB, 2'd0} + {18{minus2}}; // [Read Memory from Reverb Adr stuff]
reg  [17:0] reverb_CounterWord;

ReverbWrapAdr ReverbWrapAdrInst(
	.i_offsetRegister	(reverbAdrPreRing),	// Word Offset.
	.i_baseAdr			(reg_mBase),		// x8 byte 16 bit reg.
	.i_offsetCounter	(reverb_CounterWord),// Word Offset.
	.o_reverbAdr		(reverbAdr)			// Word output absolute adr.
);

// Value to write to the SPU RAM for reverb data bus.
assign reverbWriteValue	= accReverb;

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

assign SPUDREQ = isDMAXferRD & !readSPU;

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
	SPUMemWRSel			= NO_SPU_READ;	// Default empty reads...
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
		end
		//
		// The interpolator takes 5 CYCLE to output, prefer to maintain channel active for that amount of cycle....
		//
		5'd14:
		begin
			SPUMemWRSel			= FIFO_WRITE; // Allow only ONCE XFer per voice...
			// [BREAK] SPUMemWRSel = isDMAXferRD ? FIFO_RD : FIFO_WRITE; // Allow only ONCE XFer per voice...
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
			readSPU			= (isDMAXferRD & SPUDACK);
			
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
assign readFIFO		= isFIFOHasData & isFIFOWR & (reg_SPUTransferMode != XFER_STOP);

// A.[Write when FIFO data available AND mode is read FIFO]
// B.[Write when mode is not read FIFO but write back     ]
assign writeSPURAM	= readFIFO | (!isFIFOWR & SPUMemWRSel[2]);

wire  KON = reg_kon [currVoice];
wire PMON = reg_pmon[currVoice];
wire  EON = reg_eon [currVoice];

// --------------------------------------------------------------------------------------
//		Stage 0A : ADPCM Adress computation (common : once every 32 cycle)
// --------------------------------------------------------------------------------------
//--------------------------------------------------
//  INPUT
//--------------------------------------------------

wire signed [15:0]  VxPitch		= currV_sampleRate;
reg  signed [15:0]	prevChannelVxOut;
//--------------------------------------------------
/*
Step = VxPitch                  ;range +0000h..+FFFFh (0...705.6 kHz)						s4.12
IF PMON.Bit(x)=1 AND (x>0)      ;pitch modulation enable
	Factor = VxOUTX(x-1)          ;range -8000h..+7FFFh (prev voice amplitude)
	Factor = Factor+8000h         ;range +0000h..+FFFFh (factor = 0.00 .. 1.99)				s1.15 -> -0.99,+0.99
	Step=SignExpand16to32(Step)   ;hardware glitch on VxPitch>7FFFh, make sign
	Step = (Step * Factor) SAR 15 ;range 0..1FFFFh (glitchy if VxPitch>7FFFh -> VxPitch as signed value) 6.26 -> 11
	Step=Step AND 0000FFFFh       ;hardware glitch on VxPitch>7FFFh, kill sign
IF Step>3FFFh then Step=4000h   ;range +0000h..+3FFFh (0.. 176.4kHz)
*/
// Convert S16 to U16 (Add +0x8000)
wire SgnS2U						= prevChannelVxOut[15] ^ 1'b1;
// Select Previous output modulation or standard pitch.
wire 				pitchSel	= PMON   /* & (currVoice != 5'd0)  <--- Done at HW Setup */;
wire signed	[16:0]	pitchMul	= pitchSel 	? { SgnS2U,SgnS2U,prevChannelVxOut[14:0] }	// -0.999,+0.999 pitch
											: { 17'h8000 }; 							// 1.0 positive
// Compute new pitch
wire signed [32:0]  mulPitch	= pitchMul * VxPitch;
wire        [15:0]	tmpRes		= mulPitch[30:15];
// Clamp over 4000.
wire				 GT4000		= tmpRes[14] | tmpRes[15];
wire				nGT4000		= !GT4000;
wire		[13:0]	lowPart		= tmpRes[13:0] & {14{nGT4000}};
//--------------------------------------------------
//  OUTPUT
//--------------------------------------------------
wire  [16:0]	nextPitch	= { 2'b0, GT4000, lowPart };
wire  [16:0] nextADPCMPos	= currV_adpcmPos + nextPitch;
wire         nextNewBlock	= nextADPCMPos[16:14] > 3'd6;
wire		 nextNewLine    = nextADPCMPos[16:14] != currV_adpcmPos[16:14];	// Change of line.

// PB : not well defined arch here... TODO : What in case of START. pure 0.

// --------------------------------------------------------------------------------------
//		Stage 0 : ADPCM Input -> Output		(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire isNullADSR         = (AdsrVol==15'd0);
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
wire		NON							= reg_non [currVoice];
wire signed [15:0] ChannelValue			= NON ? noiseLevel : (validSampleStage2 ? voiceSample : 16'd0); // [TODO ADDED DEBUG WITH VALID SAMPLE. -> REMOVE]
wire  signed [14:0] currV_VolumeL		= reg_volumeL	[currVoice][14:0];
wire  signed [14:0] currV_VolumeR		= reg_volumeR	[currVoice][14:0];

// --------------------------------------------------------------------------------------
//		Stage 3A : Compute ADSR        	(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire  [14:0] AdsrVol			= reg_SPUEnable ? reg_currentAdsrVOL[currVoice] : 15'd0;
wire  [15:0] AdsrLo				= reg_adsrLo	[currVoice];
wire  [15:0] AdsrHi				= reg_adsrHi	[currVoice];
wire   [1:0] AdsrState			= reg_adsrState	[currVoice];
wire  [22:0] AdsrCycleCount		= reg_adsrCycleCount[currVoice];

reg 				EnvExponential;
reg 				EnvDirection;
reg signed [4:0]	EnvShift;
reg signed [3:0]	EnvStep;
reg [15:0]			EnvLevel;
reg [1:0]           computedNextAdsrState;
reg                 cmpLevel;

wire [4:0]  	susLvl = { 1'b0, AdsrLo[3:0] } + { 5'd1 };
wire [15:0]	EnvSusLevel= { susLvl, 11'd0 };

wire [1:0] tstState = changeADSRState ? nextAdsrState : AdsrState;
always @(*) begin
	case (AdsrState)
	// ---- Activated only from KON
	ADSR_ATTACK : computedNextAdsrState = KON ? ADSR_ATTACK : ADSR_DECAY; // A State -> D State if KON cleared, else stay on ATTACK.
	ADSR_DECAY  : computedNextAdsrState = ADSR_SUSTAIN;
	ADSR_SUSTAIN: computedNextAdsrState = ADSR_SUSTAIN;
	// ---- Activated only from KOFF
	ADSR_RELEASE: computedNextAdsrState = ADSR_RELEASE;
	endcase
	
	case (AdsrState)
	ADSR_ATTACK : cmpLevel = 1;
	ADSR_DECAY  : cmpLevel = 1;
	ADSR_SUSTAIN: cmpLevel = 0;
	ADSR_RELEASE: cmpLevel = 0;
	endcase
	
	case (tstState)
	ADSR_ATTACK: // A State
	begin
		EnvExponential	= AdsrLo[15];
		EnvDirection	= 0;						// INCR
		EnvShift		= AdsrLo[14:10];			// 0..+1F
		EnvStep			= { 2'b01, ~AdsrLo[9:8] };	// +7..+4
	end
	ADSR_DECAY: // D State
	begin
		EnvExponential	= 1'b1;						// Exponential
		EnvDirection	= 1;						// DECR
		EnvShift		= { 1'b0, AdsrLo[7:4] };	// 0..+0F
		EnvStep			= 4'b1000;					// -8
	end
	ADSR_SUSTAIN: // S State
	begin
		EnvExponential	= AdsrHi[15];
		EnvDirection	= AdsrHi[14];				// INCR/DECR
		EnvShift		= AdsrHi[12:8];				// 0..+1F
		// +7/+6/+5/+4 if INCREASE
		//	0 00 : 0111
		//  0 01 : 0110
		//  0 10 : 0101
		//  0 11 : 0100
		// -8/-7/-6/-5 if DECREASE
		//	1 00 : 1000 -8
		//  1 01 : 1001 -7
		//  1 10 : 1010 -6
		//  1 11 : 1011 -5
		EnvStep			= { AdsrHi[14] , !AdsrHi[14] , AdsrHi[14] ? AdsrHi[7:6] : ~AdsrHi[7:6] };
	end
	ADSR_RELEASE: // R State	
	begin
		EnvExponential	= AdsrHi[5];
		EnvDirection	= 1;						// DECR
		EnvShift		= AdsrHi[4:0];				// 0..+1F
		EnvStep			= 4'b1000;					// -8
	end
	endcase
end

wire shift2ExpIncr = EnvExponential & !EnvDirection & (AdsrVol > 15'h6000);
wire step2ExpDecr  = EnvExponential & EnvDirection;

wire [22:0] cycleCountStart;
wire signed [14:0] adsrStep;
	
ADSRCycleCountModule ADSRCycleCountInstance
(
	.i_EnvShift				(EnvShift),
	.i_EnvStep				(EnvStep),
	.i_adsrLevel			(AdsrVol),		// 0..+7FFF
	.i_shift2ExpIncr		(shift2ExpIncr),
	.i_step2ExpDecr			(step2ExpDecr),
	.o_CycleCount			(cycleCountStart),
	.o_AdsrStep				(adsrStep)
);

wire [22:0] decAdsrCycle    = AdsrCycleCount + { 23{1'b1} } /* Same as AdsrCycleCount - 1 */;
wire		reachZero		= (AdsrCycleCount == CHANGE_ADSR_AT); // Go to next state when reach 1 or 0 ??? (Take care of KON event setting current voice to 1 or 0 cycle)
wire		tooBigLvl		= (      AdsrVol ==    15'h7FFF) && (AdsrState == ADSR_ATTACK);
wire        tooLowLvl		= ({1'b0,AdsrVol} < EnvSusLevel) && (AdsrState == ADSR_DECAY );
wire		changeADSRState	= validSampleStage2 & reachZero & ((cmpLevel & (tooBigLvl | tooLowLvl)) | (!cmpLevel));

wire [22:0] nextAdsrCycle	= reachZero ? cycleCountStart : decAdsrCycle;

// TODO : On Sustain, should stop adding adsrStep when reachZero
wire [14:0] nextAdsrVol;
wire [16:0] tmpVolStep		= {2'b0, AdsrVol} + {adsrStep[14],adsrStep[14],adsrStep};
clampSPositive #(.INW(17),.OUTW(15)) ClampADSRVolume(.valueIn(tmpVolStep),.valueOut(nextAdsrVol));

wire  [1:0]	nextAdsrState	= computedNextAdsrState;
wire		clearKON		= reachZero & KON & validSampleStage2;

/*
	4. Detect value threshold and change state.
 */

wire signed [15:0] sAdsrVol = {1'b0, AdsrVol};
wire signed [30:0] tmpVxOut = ChannelValue * sAdsrVol;
wire signed [15:0] vxOut	 = tmpVxOut[30:15];	// 1.15 bit precision.

reg signed [15:0] PvxOut;
reg PValidSample;
always @(posedge i_clk) begin
	if (storePrevVxOut) begin
		prevChannelVxOut = vxOut;
	end
	PvxOut			= validSampleStage2 ? vxOut : 16'd0; // [TODO DEBUG LOGIC MUX -> REMOVE]
	PValidSample	= validSampleStage2;
end

// --------------------------------------------------------------------------------------
//		Channel volume / Support Sweep (16 cycle)
// --------------------------------------------------------------------------------------

wire signed [30:0] applyLVol = currV_VolumeL * PvxOut;
wire signed [30:0] applyRVol = currV_VolumeR * PvxOut;

// --------------------------------------------------------------------------------------
//		Stage Accumulate all voices    (768/16/32)
// --------------------------------------------------------------------------------------
reg signed [20:0] sumL,sumR;
reg signed [20:0] sumReverb;
wire signed [15:0] reverbApply = side22Khz ? applyRVol[30:15] : applyLVol[30:15];
always @(posedge i_clk) begin
	if (PValidSample) begin
		sumL = sumL + { {5{applyLVol[30]}},applyLVol[30:15]};
		sumR = sumR + { {5{applyRVol[30]}},applyRVol[30:15]};
		if (EON) begin
			sumReverb = sumReverb + { {5{reverbApply[15]}}, reverbApply };
		end
	end else begin
		if (clearSum) begin
			sumL		= 21'd0;
			sumR		= 21'd0;
			sumReverb	= 21'd0;
		end
	end
end

// Because we scan per channel.
reg  signed [15:0] reg_CDRomInL,reg_CDRomInR;
// Select correct volume based on 22 Khz switch bit.
wire signed [15:0] volume			= side22Khz ? reg_reverbVolRight : reg_reverbVolLeft;
wire signed [31:0] valueReverb      = accReverb * volume; 
wire signed [15:0] valueReverbFinal = reg_ReverbEnable ? valueReverb[30:15] : 16'd0;
reg  signed [15:0] regValueReverbLeft,regValueReverbRight;

always @(posedge i_clk) begin
	if (inputL) begin
		reg_CDRomInL = CDRomInL; 
	end
	if (inputR) begin
		reg_CDRomInR = CDRomInR;
	end

	if (ctrlSendOut) begin
		if (side22Khz) begin
			// Right Side
			regValueReverbRight = valueReverbFinal;
		end else begin
			// Left Side
			regValueReverbLeft  = valueReverbFinal;
		end
	end
end

wire signed [31:0] tmpCDRomL = reg_CDRomInL * reg_CDVolumeL;
wire signed [31:0] tmpCDRomR = reg_CDRomInR * reg_CDVolumeR;
wire signed [15:0] CD_addL   = tmpCDRomL[30:15];
wire signed [15:0] CD_addR   = tmpCDRomR[30:15];

wire signed [15:0] CdSideL	= reg_CDAudioEnabled	? CD_addL : 16'd0;
wire signed [15:0] CdSideR	= reg_CDAudioEnabled	? CD_addR : 16'd0;
// wire signed [15:0] ExtSide = reg_ExtEnabled		? (extInput * extLRVolume) : 16'd0; // Volume R + L

// --------------------------------------------------------------------------------------
//		Reverb Input (1536 / 768 / 16)
// --------------------------------------------------------------------------------------
// Get CD Data post-volume for REVERB : Enabled ? If so, which side ?
wire signed [15:0] cdReverbInput = reg_CDAudioReverbEnabled ? 16'd0 : (side22Khz ? CdSideR : CdSideL);
// Sum CD Reverb and Voice Reverb.
wire signed [20:0] reverbFull	 = sumReverb + {{5{cdReverbInput[15]}},cdReverbInput};
// [Assign clamped value to Reverb INPUT]
clampSRange #(.INW(21),.OUTW(16)) Reverb_Clamp(.valueIn(reverbFull),.valueOut(lineIn));

// --------------------------------------------------------------------------------------
//		Mix
// --------------------------------------------------------------------------------------
// According to spec : impact only MAIN, not CD
wire signed [14:0] volL        = reg_SPUNotMuted ? reg_mainVolLeft [14:0] : 15'd0;
wire signed [14:0] volR        = reg_SPUNotMuted ? reg_mainVolRight[14:0] : 15'd0;
wire signed [35:0] sumPostVolL = sumL * volL;
wire signed [35:0] sumPostVolR = sumR * volR;

// Mix = Accumulate + CdSide + RevertOutput
// 16 bit signed x 5 bit (64 channel max)
wire signed [16:0] CDAndReverbL= CdSideL + regValueReverbLeft ;
wire signed [16:0] CDAndReverbR= CdSideR + regValueReverbRight;
wire signed [20:0] postVolL    = sumPostVolL[34:14] + {{4{CDAndReverbL[16]}} ,CDAndReverbL};
wire signed [20:0] postVolR    = sumPostVolR[34:14] + {{4{CDAndReverbR[16]}} ,CDAndReverbR};

wire signed [15:0] outL,outR;
clampSRange #(.INW(21),.OUTW(16)) Left_Clamp(.valueIn(postVolL),.valueOut(outL));
clampSRange #(.INW(21),.OUTW(16)) RightClamp(.valueIn(postVolR),.valueOut(outR));

assign AOUTL		= outL;
assign AOUTR		= outR;
assign VALIDOUT		= ctrlSendOut;

endmodule
