/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
 **************************************************************************************************************************************/
/*	READ / WRITE Special Behavior :
	- Overwrite of current voice MAIN VOLUME ignored.
	- Write of 1F801DBCh is not supported (UNKNOWN REGISTER), Read is FAKE hardcoded value.
	- Write of 1F801DA0h is not supported (UNKNOWN REGISTER), Read is FAKE hardcoded value.
	- 1F801E60h R/W Not supported.
	----- Unmet in games ----
	TODO : No CPU READ FIFO Support for now.
	TODO : Implement Sweep.	(Per channel, Per Main)
	-------------------------
	TODO : Implement ADPCM Loader.
			- Support loop of channel.
			- Support Packet flags.
	TODO : Implement ADSR. (Including KON / KOFF)
	TODO : Finish the time slicing logic. (decide the whole state machine for the SPU)
			- Reverb.
	TODO : Implement Reverb.
*/

module SPU(
	 input			i_clk
	,input			n_rst
	
	// CPU Side
	// CPU can do 32 bit read/write but they are translated into multiple 16 bit access.
	// CPU can do  8 bit read/write but it will receive 16 bit. Write will write 16 bit. (See No$PSX specs)
	,input			SPUCS	// We have only 11 adress bit, so for read and write, we tell the chip is selected.
	,input			SPUDREQ
	,input			SPUDACK
	,input			SRD
	,input			SWRO
	,input	[ 9:0]	addr		// Here Sony spec is probably in HALF-WORD (9 bit), we keep in BYTE for now. (10 bit)
	,input	[15:0]	dataIn
	,output	[15:0]	dataOut
	,output			dataOutValid
	,output			SPUINT
	
	// CPU DMA stuff.
	,input			srd
	,input			swr0
	,input			spudack
	,output			spudreq

	/*
	// RAM Side
	,output	[17:0]	o_adrRAM
	,output			o_dataReadRAM
	,output			o_dataWriteRAM
	,input	[15:0]	i_dataInRAM
	,output	[15:0]	o_dataOutRAM
	*/
	
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
begin debugCnt = (n_rst == 0) ? 24'd0 : debugCnt + 1; end

/* Decide if we loop ADSR cycle counter when reach 0 or 1 ?
	0 = Number of cycle + 1 evaluation !
	1 = Number of cycle exactly.
*/
parameter		CHANGE_ADSR_AT = 23'd1;

wire			o_dataReadRAM;
wire			o_dataWriteRAM;
wire	[15:0]	i_dataInRAM; 

reg		[15:0]	o_dataOutRAM;
reg      [1:0]	SPUMemWRSel;
reg 	[17:0]	o_adrRAM;

parameter	FIFO_WRITE			= 2'b00,
			VOICE_WR			= 2'b01,
			CDLeft_WR			= 2'b10,
			CDRight_WR			= 2'b11;

reg [8:0] regRingBufferIndex;

always @(*) begin 
	if (o_dataWriteRAM) begin
		// Write Section
		case (SPUMemWRSel)
		FIFO_WRITE:	o_adrRAM = reg_dataTransferAddrCurr;
		VOICE_WR  : o_adrRAM = {8'd1,isVoice3,regRingBufferIndex};
		CDLeft_WR : o_adrRAM = {9'd0         ,regRingBufferIndex};
		CDRight_WR: o_adrRAM = {9'd1         ,regRingBufferIndex};
		endcase
	end else begin
		// [TODO Reverb, CPU Read, ADPCM Read distinct]
		o_adrRAM = adrRAM; // READ Section...
	end
end

always @(*) begin 
	case (SPUMemWRSel)
	FIFO_WRITE:	o_dataOutRAM = fifoDataOut;
	VOICE_WR  : o_dataOutRAM = vxOut;
	CDLeft_WR : o_dataOutRAM = reg_CDRomInL;
	CDRight_WR: o_dataOutRAM = reg_CDRomInR;
	endcase
end

wire	[1:0]	o_SPURAMByteSel = 2'b11;
wire readFIFO;
wire isFIFOEmpty;
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

wire writeSPURAM;
assign o_dataReadRAM	= dataReadRAM;
assign o_dataWriteRAM	= writeSPURAM;

assign isFIFOEmpty = !fifo_r_valid;

SPU_RAM SPU_RAM_FPGAInternal
(
	.i_clk			(i_clk),
	.i_re			(o_dataReadRAM),
	.i_we			(o_dataWriteRAM),
	.i_wordAddr		(o_adrRAM),
	.i_data			(o_dataOutRAM),
	.i_byteSelect	(o_SPURAMByteSel),
	
	.o_q			(i_dataInRAM)
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
reg [23:0]	reg_repeatUserSet;
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

reg [23:0]	reg_activeChannels;

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
reg			reg_SPUMute;				//  DAA.14
reg	[3:0]	reg_NoiseFrequShift;		//  DAA.13-10
reg	[3:0]	reg_NoiseFrequStep;			//  DAA.9-8 -> Modified at setup.
reg [1:0]	reg_NoiseStepStore;
reg			reg_ReverbEnable;			//  DAA.7
reg			reg_SPUIRQEnable;			//  DAA.6

parameter	XFER_STOP   = 2'd0,
			XFER_MANUAL = 2'd1,
			XFER_DMAWR  = 2'd2,
			XFER_DMARD  = 2'd3; // [TODO : Not supported]
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

/*
reg [15:0] readVolumeL;
reg [15:0] readVolumeR;
reg [15:0] readSampleRate;
reg [15:0] readStartAddr;
reg [15:0] readAdsrLo;
reg [15:0] readAdsrHi;
reg [15:0] readCurrAdsr;
*/

//----------------- Repeat Address is accessed by BOTH system (CPU & State machine, needed TRUE DOUBLE PORT)
/*
wire [15:0] readRepeatAddr;
wire setRepeatByUser 	= (internalWrite & (!isD80_DFF) & isChannel & (addr[3:2]==2'b00) & (addr[3:1]==3'b111));
*/
/*
DPRam #(.DW(16),.AW(5)) RepeatAddressDPRam (
	.clk		(clk),
	
	.data_a		(dataIn),
	.data_b		(newRepeatAddress),
	.addr_a		(addr[8:4]),
	.addr_b		(currVoice),
	.we_a		(setRepeatByUser),
	.we_b		(overwriteRepeatAddress),
	.q_a		(readRepeatAddr),
	.q_b		(currV_repeatAddr)
);
*/
//---------------------------------------------------------------------------------------------------------------

reg [15:0] readReverb;

// Detect write transition
wire isDMAXfer = (reg_SPUTransferMode == XFER_DMAWR);
wire isCPUXFer = (reg_SPUTransferMode == XFER_MANUAL);
wire dataTransferBusy		= (reg_SPUTransferMode != XFER_STOP) & fifo_r_valid;	// [TODO : works only for write , not read]
wire dataTransferReadReq 	= reg_SPUTransferMode[1] & reg_SPUTransferMode[0];
wire dataTransferWriteReq	= reg_SPUTransferMode[1] & (!reg_SPUTransferMode[0]);
wire dataTransferRDReq		= reg_SPUTransferMode[1];

// [Write to FIFO only on transition from internalwrite from 0->1 but allow BURST with DMA transfer] 
//  --> PROTECTED FOR EDGE TRANSITION : WRITE during multiple cycle else would perform multiple WRITE of the same value !!!!
wire writeFIFO = internalWrite & (!PInternalWrite | isDMAXfer) & isD80_DFF & (!addr[6]) & (addr[5:1] == 5'h14);
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
		reg_SPUMute					= 1'b0;
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
		reg_repeatUserSet			= 24'd0;
		reg_activeChannels			= 24'd0;
		reg_endx					= 24'd0;
		regRingBufferIndex			= 9'd0;
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
								if (dataIn [0]) begin reg_kEvent [0] = 1; reg_kMode [0] = 1; end
								if (dataIn [1]) begin reg_kEvent [1] = 1; reg_kMode [1] = 1; end
								if (dataIn [2]) begin reg_kEvent [2] = 1; reg_kMode [2] = 1; end
								if (dataIn [3]) begin reg_kEvent [3] = 1; reg_kMode [3] = 1; end
								if (dataIn [4]) begin reg_kEvent [4] = 1; reg_kMode [4] = 1; end
								if (dataIn [5]) begin reg_kEvent [5] = 1; reg_kMode [5] = 1; end
								if (dataIn [6]) begin reg_kEvent [6] = 1; reg_kMode [6] = 1; end
								if (dataIn [7]) begin reg_kEvent [7] = 1; reg_kMode [7] = 1; end
								if (dataIn [8]) begin reg_kEvent [8] = 1; reg_kMode [8] = 1; end
								if (dataIn [9]) begin reg_kEvent [9] = 1; reg_kMode [9] = 1; end
								if (dataIn[10]) begin reg_kEvent[10] = 1; reg_kMode[10] = 1; end
								if (dataIn[11]) begin reg_kEvent[11] = 1; reg_kMode[11] = 1; end
								if (dataIn[12]) begin reg_kEvent[12] = 1; reg_kMode[12] = 1; end
								if (dataIn[13]) begin reg_kEvent[13] = 1; reg_kMode[13] = 1; end
								if (dataIn[14]) begin reg_kEvent[14] = 1; reg_kMode[14] = 1; end
								if (dataIn[15]) begin reg_kEvent[15] = 1; reg_kMode[15] = 1; end
							end
					5'h05:	begin									// 1F801D8Ah - 18Ah
								reg_kon [23:16]		= dataIn[7:0];
								if (dataIn [0]) begin reg_kEvent[16] = 1; reg_kMode[16] = 1; end
								if (dataIn [1]) begin reg_kEvent[17] = 1; reg_kMode[17] = 1; end
								if (dataIn [2]) begin reg_kEvent[18] = 1; reg_kMode[18] = 1; end
								if (dataIn [3]) begin reg_kEvent[19] = 1; reg_kMode[19] = 1; end
								if (dataIn [4]) begin reg_kEvent[20] = 1; reg_kMode[20] = 1; end
								if (dataIn [5]) begin reg_kEvent[21] = 1; reg_kMode[21] = 1; end
								if (dataIn [6]) begin reg_kEvent[22] = 1; reg_kMode[22] = 1; end
								if (dataIn [7]) begin reg_kEvent[23] = 1; reg_kMode[23] = 1; end
							end
					5'h06:	begin									// 1F801D8Ch - 18Ch
								reg_koff[15: 0]		= dataIn;			
								if (dataIn [0]) begin reg_kEvent [0] = 1; reg_kMode [0] = 0; end
								if (dataIn [1]) begin reg_kEvent [1] = 1; reg_kMode [1] = 0; end
								if (dataIn [2]) begin reg_kEvent [2] = 1; reg_kMode [2] = 0; end
								if (dataIn [3]) begin reg_kEvent [3] = 1; reg_kMode [3] = 0; end
								if (dataIn [4]) begin reg_kEvent [4] = 1; reg_kMode [4] = 0; end
								if (dataIn [5]) begin reg_kEvent [5] = 1; reg_kMode [5] = 0; end
								if (dataIn [6]) begin reg_kEvent [6] = 1; reg_kMode [6] = 0; end
								if (dataIn [7]) begin reg_kEvent [7] = 1; reg_kMode [7] = 0; end
								if (dataIn [8]) begin reg_kEvent [8] = 1; reg_kMode [8] = 0; end
								if (dataIn [9]) begin reg_kEvent [9] = 1; reg_kMode [9] = 0; end
								if (dataIn[10]) begin reg_kEvent[10] = 1; reg_kMode[10] = 0; end
								if (dataIn[11]) begin reg_kEvent[11] = 1; reg_kMode[11] = 0; end
								if (dataIn[12]) begin reg_kEvent[12] = 1; reg_kMode[12] = 0; end
								if (dataIn[13]) begin reg_kEvent[13] = 1; reg_kMode[13] = 0; end
								if (dataIn[14]) begin reg_kEvent[14] = 1; reg_kMode[14] = 0; end
								if (dataIn[15]) begin reg_kEvent[15] = 1; reg_kMode[15] = 0; end
							end
					5'h07:	begin									// 1F801D8Eh - 18Eh
								reg_koff[23:16]		= dataIn[7:0];		
								if (dataIn [0]) begin reg_kEvent[16] = 1; reg_kMode[16] = 0; end
								if (dataIn [1]) begin reg_kEvent[17] = 1; reg_kMode[17] = 0; end
								if (dataIn [2]) begin reg_kEvent[18] = 1; reg_kMode[18] = 0; end
								if (dataIn [3]) begin reg_kEvent[19] = 1; reg_kMode[19] = 0; end
								if (dataIn [4]) begin reg_kEvent[20] = 1; reg_kMode[20] = 0; end
								if (dataIn [5]) begin reg_kEvent[21] = 1; reg_kMode[21] = 0; end
								if (dataIn [6]) begin reg_kEvent[22] = 1; reg_kMode[22] = 0; end
								if (dataIn [7]) begin reg_kEvent[23] = 1; reg_kMode[23] = 0; end
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
					5'h11:	reg_mBase			= dataIn;			// 1F801DA2h - 1A2h
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
							reg_SPUMute			= dataIn[14];
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
						reg_repeatAddr[channelAdr] = dataIn;
					end
				end // else 1xxxxx.xxxx <--- ELSE
					// Current volume L/R channels. (1F801E00h..1F801E5Fh)
					// 1E60~1FFFF Unknown/Unused
			end
		end else begin 
			// --------------------------
			// No write.
			// --------------------------
			
			// CPU for now has priority when writing a repeat address.
			if (overwriteRepeatAddress) begin
				reg_repeatAddr[currVoice] = newRepeatAddress;
			end

			readReverb		= reg_reverb[addr[5:1]];
		end // end write

		//
		// [OUTSIDE OF WRITE]
		//
		if (check_Kevent) begin
			if (reg_kEvent[currVoice]) begin	// KON or KOFF occured to this channel...
				if (reg_kMode[currVoice]) begin // Voice start [TODO : have bit that said voice is stopped and check it : reg_endx ?]
					reg_currentAdsrVOL[currVoice] = 15'd0;
					reg_adpcmCurrAdr[currVoice] = currV_startAddr;
					reg_adsrState	[currVoice] = ADSR_ATTACK;
					reg_adpcmPos	[currVoice] = 17'd0;
					reg_endx		[currVoice] = 1'b0;
					reg_adpcmPrev	[currVoice] = 32'd0;
					reg_adsrCycleCount[currVoice] = CHANGE_ADSR_AT; 
					/*	[TODO : Part from Avocado not done...]
						if (!ignoreLoadRepeatAddress) {
							repeatAddress._reg = startAddress._reg;
							ignoreLoadRepeatAddress = false;
						}

						loadRepeatAddress = false;
					 */

					// Optionnal... can't stay for ever... ? What's the point, else everything ends up 1.
					// reg_kon			[currVoice] = 1'b0;
				end else begin
					reg_adsrState	[currVoice] = ADSR_RELEASE;
					reg_koff		[currVoice] = 1'b0;
				end
			end
			reg_kEvent			[currVoice] = 1'b0; // Reset Event.
			reg_activeChannels	[currVoice] = 1'b1;
		end
		
		if (clearKON) begin
			reg_kon[currVoice] = 1'b0;
		end
		
		if (setEndX) begin
			reg_endx		[currVoice] = 1'b1;
		end
		
		if (updateVoiceADPCMAdr) begin
			reg_adpcmCurrAdr[currVoice] = currV_adpcmCurrAdr + 16'd2;	// Skip 16 byte for next ADPCM block.
		end
		
		if (updateVoiceADPCMPos) begin
			// If next block, point to the correct SAMPLE and SUB sample position.
			// else           point to the correct SAMPLE with INDEX and sub sample position.
			reg_adpcmPos[currVoice]		= { {nextNewBlock ? 3'd0 : nextADPCMPos[16:14]} , nextADPCMPos[13:0] };
		end

		if (updateVoiceADPCMPrev) begin
			reg_adpcmPrev[currVoice]	= reg_tmpAdpcmPrev;
		end

		if (setRepeatByUser) begin
			// A/ SET FLAG WHEN WRITING CHANNEL REPEAT ADR ===> FLAG 1.
			reg_repeatUserSet[channelAdr] = 1'b1;
		end
		// Not a ELSE. priority here...
		if (resetRepeatUserFlagByCurrChannel) begin
			reg_repeatUserSet[currVoice] = 1'b0;
		end
		
		if (incrXFerAdr) begin
			reg_dataTransferAddrCurr = reg_dataTransferAddrCurr + 1; // One half-word increment.
		end
		
		if (ctrlSendOut) begin
			regRingBufferIndex = regRingBufferIndex + 1;
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
	end // end reset
end // end always block

reg [15:0] dataOutw;
wire setRepeatByUser; // [NWRITE]

assign dataOut		= dataOutw;	// [TODO : for now we answer within the same cycle using combinatorial logic]

reg internalReadPipe;
reg incrXFerAdr;
always @ (posedge i_clk) 
begin
	internalReadPipe	= internalRead;
	incrXFerAdr			= readFIFO;
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
			5'h14:	dataOutw = 16'd0; 						// 1F801DA8h [TODO] Can't read FIFO for now.
			5'h15:	begin 									// 1F801DAAh SPU Control register
					dataOutw = { 	reg_SPUEnable,
									reg_SPUMute,
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
			dataOutw = readReverb;
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
// [NREAD] wire  [15:0] currV_repeatAddr	= reg_repeatAddr[currVoice];
// [NREAD] wire         currV_koff			= reg_koff		[currVoice];
wire		 currV_kon			= reg_kon		[currVoice];
wire  [16:0] currV_adpcmPos		= reg_adpcmPos	[currVoice];
wire  [15:0] currV_adpcmCurrAdr	= reg_adpcmCurrAdr[currVoice];
wire  [31:0] currV_adpcmPrev	= reg_adpcmPrev	[currVoice];
wire		 currV_activeChannel= reg_activeChannels[currVoice];

// -----------------------------------------------------------------
// INTERNAL TIMING & STATE SECTION
// -----------------------------------------------------------------
reg  [9:0] counter768;
reg        counter22Khz;
reg        pipeCounter22Khz;
wire [9:0] nextCounter768 = counter768 + 10'd1;

wire ctrl44Khz = (nextCounter768 == 10'd768);
wire ctrl22Khz = pipeCounter22Khz & !counter22Khz;

always @(posedge i_clk)
begin
	if (n_rst == 0)
	begin
		counter768			= 10'd0;
		pipeCounter22Khz	= 1;
		counter22Khz		= 0;
	end else begin
		counter768			= ctrl44Khz ? 10'd0 : nextCounter768;
		if (ctrl44Khz) begin
			pipeCounter22Khz	= counter22Khz;
			counter22Khz		= !counter22Khz;
		end
	end
end


reg [4:0] voiceInternalCnt;
always @(posedge i_clk)
begin
	if (ctrl44Khz || (n_rst==0)) begin
		// Reset all counter and state machine...
		currVoice			= 5'd0;		
		voiceInternalCnt	= 5'd0;
	end else begin
		// Counter reset to 0 for each new voice...
		if (voiceIncrement) begin
			voiceInternalCnt	= 5'd0;
		end else begin
			voiceInternalCnt  = voiceInternalCnt + 5'd1;
		end
		// Increment Channel
		currVoice			= currVoice + { 4'd0, voiceIncrement };
	end
end

wire noMoreVoice = (currVoice == 5'd25);

reg readHeader; 	// [NWRITE]
reg PReadHeader;	// [NWRITE]
reg [3:0] currV_shift;
reg [2:0] currV_filter;
wire signed [15:0] sampleOutADPCMRAW;

always @(posedge i_clk)
begin
	if (loadPrev) begin
		currV_shift		= i_dataInRAM[3:0];
		currV_filter	= i_dataInRAM[6:4];
		// [TODO Flags ADPCM Loop / Start]
	end
	
	if (reg_SPUIRQEnable && (reg_ramIRQAddr==o_adrRAM[17:2])) begin
		reg_SPUIRQSet = 1'b1;
	end
	if (reg_SPUIRQEnable == 1'b0) begin
		reg_SPUIRQSet = 1'b0; // Acknowledge if IRQ was set.
	end
	if (loadPrev) begin
		reg_tmpAdpcmPrev = currV_adpcmPrev;
	end
	if (updatePrev) begin
		reg_tmpAdpcmPrev = { reg_tmpAdpcmPrev[15:0], sampleOutADPCMRAW };
	end
	PReadHeader = readHeader;
end

// TODO : Write back Ch1/3,
// TODO : Write register output into last for Feedback.
// TODO : FIFO Read/Write...
reg voiceIncrement;						// Goto the next voice.
reg [2:0] decodeSample;
reg updatePrev, loadPrev;
reg [1:0] adpcmSubSample;
reg check_Kevent;

reg zeroIndex;
wire  [3:0] idxBuff			= zeroIndex ? 4'd0 : { 1'b0, currV_adpcmPos[16:14]} + 4'd1; // Change from Base 0 index to Base 1 index in adr.
wire [17:0] adrRAM			= { currV_adpcmCurrAdr, 2'd0 } + {13'd0,idxBuff[3:0]};
reg  setEndX, setAsStart; // ADPCM internal block FLAG : Start/End flags.
reg  storePrevVxOut;
reg	ctrlSendOut;
reg	clearSum;
reg dataReadRAM;
reg updateVoiceADPCMPos;
reg updateVoiceADPCMPrev;
wire isLastVoice	= (currVoice == 5'd23);
wire isVoice1		= (currVoice == 5'd1);
wire isVoice3		= (currVoice == 5'd3);

always @(*)
begin
	dataReadRAM			= 0;
	voiceIncrement		= 0;
	loadPrev			= 0;
	updatePrev			= 0;
	check_Kevent		= 0;
	storePrevVxOut		= 0;
	clearSum			= 0;
	ctrlSendOut			= 0;
	setEndX				= 0;
	setAsStart			= 0;
	zeroIndex			= 0;
	SPUMemWRSel			= FIFO_WRITE;	// Default to empty FIFO when possible...
	updateVoiceADPCMAdr	= 0;
	updateVoiceADPCMPos = 0;
	updateVoiceADPCMPrev= 0;
	adpcmSubSample		= 0;

	case (voiceInternalCnt)
	5'd0:
	begin
		// Cycle 0 : currVoice register output updated.
		check_Kevent		= 1;
	end
	5'd1:
	begin
		// If check_Kevent --> Here, updated currV_adpcmCurrAdr
		dataReadRAM = 1;
		zeroIndex	= 1;
		
		// Need to preload header to setup Status stuff...
		// Upgrade address counter if needed.
		/*
		// Cycle 1 : Reading of BRAM storing currVoice data available.
		if (currV_activeChannel || currV_kon) begin
		end */ /* else begin BUGGY, NEVER USE FOR NOW.
			// [CAN : Timing broken for 44.1 Khz generation if we do...
			// Early break... Can be removed if we want regular memory access patterns.
			// But need to take care of using koff to mux the volume to ZERO.
			voiceIncrement = !noMoreVoice;
		end */
	end
	5'd2:
	begin
		// Here Header info is loaded and processed if necessary.
		loadPrev	= 1;
		setEndX		= i_dataInRAM[ 8]; // 1
		setAsStart	= i_dataInRAM[10]; // 4
		// [TODO] : setEndX set EDX but repeatAdress save/load with bit 1 and 4 not handled yet...
		dataReadRAM	= 1;	// Sample 0
		// Load correct Sample block based on current sample position and base block adress.
	end
	
	// [TODO : Read for sample 0/1/2/3 could be reduced to a single read using temp register if needed]
	5'd3:
	begin
		// For each sample 0..3 ( currV_adpcmPos[13:12] )
		// Check if we match currV_adpcmPos[13:12]
		// -> Push sample to gaussian interpolator.
		// At sample 3
		dataReadRAM	= 1;	// Sample 1
		updatePrev	= 1;
		adpcmSubSample	= 0;
	end
	5'd4:
	begin
		dataReadRAM	= 1;	// Sample 2
		updatePrev	= 1;
		adpcmSubSample	= 1;
	end
	5'd5:
	begin
		dataReadRAM	= 1;	// Sample 3
		updatePrev	= 1;
		adpcmSubSample	= 2;
	end
	5'd6:
	begin
		updatePrev		= 1;
		adpcmSubSample	= 3;
		// Before the first sample of the first channel is sent, we reset the accumulators.
		// We put it here, but it can be moved around if needed,
		// it must just take in account the last sample of channel 23 pipeline latency and start of channel 0 when looping.
		clearSum		= (currVoice == 5'd0);
	end
	
	5'd7:
	begin
	end
	//
	// The interpolator takes 5 CYCLE to output, prefer to maintain channel active for that amount of cycle....
	//
	5'd8:
	begin
	end
	5'd9:
	begin
	end
	5'd10:
	begin
	end
	5'd11:
		// Do nothing on memory side for now...
	begin
	end
	5'd12:
	begin
		storePrevVxOut = 1;
		// -> If NEXT sample is OUTSIDE AND CONTINUE, SAVE sample2/sample3 (previous needed for decoding)
		//       NEXT sample is OUTSIDE AND JUMP, set 0/0.
		// 
		if (isVoice1 | isVoice3) begin
			SPUMemWRSel			= VOICE_WR;
		end // else use FIFO to purge...

		// --------------------------------
		// ADPCM Line/Block Management
		// --------------------------------
		updateVoiceADPCMAdr = nextNewBlock; // [TODO, just +1 for now]
		if (nextNewBlock) begin
			// [TODO] New Block.
			// FOR NOW => Continue linear.
			// -> Jump to another block ?
			// 1/ nextADPCMPos[16:14] = 0, anyway -> Write back into reg_adpcmPos.
			// 2/ reg_adpcmCurrAdr += 2 or reg_adpcmCurrAdr = loopPoint. 
			// Save reg_tmpAdpcmPrev
		end /* else begin
			// Continue inside same block...
		end */
		updateVoiceADPCMPos = 1;
		updateVoiceADPCMPrev= nextNewLine;	// Store PREV ADPCM when we move to the next 16 bit only.(different line in same ADPCM block or new ADPCM block)
	end
	5'd30:
	begin
		if (isLastVoice) begin
			SPUMemWRSel			= CDLeft_WR;
		end
	end
	5'd31:
	begin
		ctrlSendOut = isLastVoice;
		if (isLastVoice) begin
			SPUMemWRSel			= CDRight_WR;
		end
		voiceIncrement = 1;
	end
	default:
	begin
		// Do nothing.
	end
	endcase
end

// Allow transfer from FIFO any cycle where RAM not busy...
assign readFIFO		= isFIFOHasData & (SPUMemWRSel==FIFO_WRITE) & (reg_SPUTransferMode != XFER_STOP) & (!dataReadRAM);
assign writeSPURAM	= (readFIFO | ((SPUMemWRSel[0] | SPUMemWRSel[1]) & (!dataReadRAM)));

// OUTPUT --------------------------------------------
// Set to 1 every first cycle in the loop.
// wire is16	= (counter768[3:0] == 4'd0);	// Loop 16 cycles.
// wire is32	=  is16 & !counter768[4];		// Loop 32 cycles.
// wire is768	= (counter768 == 10'd0);		// Loop 768 cycles.
reg [4:0] currVoice;						// Loop 0..23
//----------------------------------------------------

wire ENDX = reg_endx[currVoice];
wire  KON = reg_kon [currVoice];
wire KOFF = reg_koff[currVoice];
wire PMON = reg_pmon[currVoice];
wire VoiceRepeatUserSet = reg_repeatUserSet[currVoice];

// --------------------------------------------------------------------------------------
//		Stage 0A : ADPCM Adress computation (common : once every 32 cycle)
// --------------------------------------------------------------------------------------
//	if (restartFlag /*First time, restart, whatever...*/ | )
//		fetchAdr <= currV_startAddr;
//	else
	
/// TODO : logic for reg [23:0]	reg_endx;

// overrideRepeatWithStart <= 0;
// nextState				<= currState;
// requestChannelInfo		<= 0;

// [Control Signal from the state machine]
wire resetRepeatUserFlagByCurrChannel;	// Will reset the userFlag.
wire overwriteRepeatAddress;			// Write the register file containing RepeatAddress.
wire [15:0] newRepeatAddress;

/*
	nextAdr = loadAdr + 8;
	loopAdr = ? currV_repeatAddr : ;
	loadAdr = isKeyOnOnce ? currV_startAddr : ( nextAdr : loopAdr);
*/
/*
	- End of block / Start.
	- KOn
	- KOff
	- Block Flag

	
	
	
	If (whenNoMoreSample)
		If (KeyOn)
			CurrAddr = StartAddress
			if (!VoiceRepeatUserSet)
				RepeatAddress = StartAddress	// PROBLEM : Interfere with CPU write at the same timing to RepeatAddress fileregisters. For now give priority to the CPU !
			end
		else
			CurrAddr = NextAddress
			
		ResetKeyOn for the channel anyway.
	Decode Sample.

 */
/*

ADPCM FLAGS :
// -------------------------------------------------------------------------
   No$PSX 
   Name      Renamed Convertion
     Start - SetLoopPointHere (0x4)
       End - (1) JumpToLoopPointWhenComplete else (0) continue to next block (0x1)
    Repeat - (1) DontTouchADSR_Or_ (0) KickR_ADSR. (0 is Active only when END=1)   (0x2)


OnReset
// -------------------------------------------------------------------------
	ENDX = 0;
	

KeyOn (play)
// -------------------------------------------------------------------------
	CurrentAdr <= StartAddress.
	Start ADSR state from A.
	if (noUserRepeatSet) {
		RepeatAddress = StartAddress;
	}
	noUserRepeatSet = true
	ENDX            = 0


KeyOff (stop)
// -------------------------------------------------------------------------
	// No change on ADPCM.
	Kick ADSR into R.

When writing to RepeatAddress[n]
// -------------------------------------------------------------------------
	noUserRepeatSet[n] = FALSE;
	END FLAG
	ENDX = 1



// -------------------------------------------------------------------------




// -------------------------------------------------------------------------



*/
	// Read Header condition :
	// - Previous block is full (decode complete) and we want to read the next sample (not the same block anymore)
	// - First time we play (can trick by making it look like condition 1/)
	//
	// Adress reading is : 
	// - Start adress if a new block.
	// - Current += 16 (8) for next block.
	// - Load RepeatAddress.
	//
	/*
	if (isFirstBlock | isBlockEnded) {
		// Load Header
		flags_setLoopPoint 		<= data[10];	// 0x0400
		flags_nextPacketFinal	<= data [8];	// 0x0100
		flags_repeatWhenEnd		<= data [9];
	}
	*/
	
	// ADPCMStartAddress	(16 bit, as 8 byte step)
	// ADPCMRepeatAddress	(16 bit, as 8 byte step)
	// VxPitch				(write 16, clamped to 0x4000 when used without pitch modulation)
	//									u3.12
	// PMon[ch]				(Pitch Modulation Enable)
	// VxOUT[ch-1]
	/*
	Counter = Counter + Step

	SamplePos 			<= Counter[..:12]
	Interpolator		<= Counter[11: 3]
	*/
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
wire SgnS2U						= prevChannelVxOut[15] ^ 1;
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

wire newSampleReady		= (adpcmSubSample == currV_adpcmPos[13:12]) & updatePrev;	// Only when state machine output SAMPLE from SPU RAM and valid ADPCM out.
wire launchInterpolator = (adpcmSubSample == 2'd3) & updatePrev;					// Interpolator must run when no more write done.
wire signed [15:0] sampleOutADPCM   = (AdsrVol!=15'd0) ? sampleOutADPCMRAW : 16'd0; 			// To avoid buffer noise.

ADPCMDecoder ADPCMDecoderUnit(
	.i_Shift		(currV_shift),
	.i_Filter		(currV_filter),
	
	.inputRAW		(i_dataInRAM),
	.samplePosition	(adpcmSubSample),

	.i_PrevSample0	(reg_tmpAdpcmPrev[15: 0]),
	.i_PrevSample1	(reg_tmpAdpcmPrev[31:16]),
	.o_sample		(sampleOutADPCMRAW)
);

// TODO : Loop point / one shot spec.

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
wire signed [15:0] ChannelValue			= NON ? noiseLevel : voiceSample;
wire  signed [14:0] currV_VolumeL		= reg_volumeL	[currVoice][14:0];
wire  signed [14:0] currV_VolumeR		= reg_volumeR	[currVoice][14:0];

// --------------------------------------------------------------------------------------
//		Stage 3A : Compute ADSR        	(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire  [14:0] AdsrVol			= reg_currentAdsrVOL[currVoice];
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

// TODO : Check volume computation bit range.
wire signed [15:0] sAdsrVol = {1'b0, AdsrVol};
wire [30:0] tmpVxOut = ChannelValue * sAdsrVol;
wire [15:0] vxOut	 = tmpVxOut[29:14];	// 1.15 bit precision.
/*
	VxOut[ch] = ChannelValue * ADSRVol
	TODO : Use KeyON and KeyOFF
	
*/
reg [15:0] PvxOut;
reg PValidSample;
always @(posedge i_clk) begin
	if (storePrevVxOut) begin
		prevChannelVxOut = vxOut;
	end
	PvxOut			= vxOut;
	PValidSample	= validSampleStage2;
end

// TODO : Current Channel Volume Register is currV_VolumeL * outADSRVolume

// --------------------------------------------------------------------------------------
//		Channel volume / Support Sweep (16 cycle)
// --------------------------------------------------------------------------------------

wire [30:0] applyLVol = currV_VolumeL * PvxOut;
wire [30:0] applyRVol = currV_VolumeR * PvxOut;

// --------------------------------------------------------------------------------------
//		Stage Accumulate all voices    (768/16/32)
// --------------------------------------------------------------------------------------
reg [20:0] sumL,sumR;
always @(posedge i_clk) begin
	if (PValidSample) begin
		sumL = sumL + { {5{applyLVol[30]}},applyLVol[29:14]};
		sumR = sumR + { {5{applyRVol[30]}},applyRVol[29:14]};
	end else begin
		if (clearSum) begin
			sumL = 21'd0;
			sumR = 21'd0;
		end
	end
end


// Because we scan per channel.
reg  signed [15:0] reg_CDRomInL,reg_CDRomInR;
wire signed [31:0] tmpCDRomL = reg_CDRomInL * reg_CDVolumeL;
wire signed [31:0] tmpCDRomR = reg_CDRomInR * reg_CDVolumeR;
wire signed [15:0] CD_addL   = tmpCDRomL[30:15];
wire signed [15:0] CD_addR   = tmpCDRomR[30:15];

always @(posedge i_clk) begin
	if (inputL) begin
		reg_CDRomInL = CDRomInL; 
	end
	if (inputR) begin
		reg_CDRomInR = CDRomInR;
	end
end

wire signed [15:0] CdSideL	= reg_CDAudioEnabled	? CD_addL : 16'd0;
wire signed [15:0] CdSideR	= reg_CDAudioEnabled	? CD_addR : 16'd0;
// wire signed [15:0] ExtSide = reg_ExtEnabled		? (extInput * extLRVolume) : 16'd0; // Volume R + L

/*
// --------------------------------------------------------------------------------------
//		Reverb Input (1536 / 768 / 16)
// --------------------------------------------------------------------------------------
wire EON; EONSelect SelectCh(.v(reg_eon), currVoice, .o(EON));
ReverbInput = (reg_CDAudioReverbEnabled		? CdSide    : 0)
            + (VoiceReverbEnable 			? VoiceSide : 0)
            + (reg_ExtReverbEnabled   		? ExtSide   : 0);
// TODO Reverb Unit
*/
wire signed [15:0] ReverbL	= 16'd0 /* TODO use reg_reverbVolLeft  */;
wire signed [15:0] ReverbR	= 16'd0 /* TODO use reg_reverbVolRight */;

// --------------------------------------------------------------------------------------
//		Mix
// --------------------------------------------------------------------------------------
// According to spec : impact only MAIN, not CD
wire signed [14:0] volL        = reg_SPUMute ? 15'd0 : reg_mainVolLeft [14:0];
wire signed [14:0] volR        = reg_SPUMute ? 15'd0 : reg_mainVolRight[14:0];
// [TODO] Add Reverb into sumL for correct support (mute reverb too)
wire signed [35:0] sumPostVolL = sumL * volL;
wire signed [35:0] sumPostVolR = sumR * volR;

// Mix = Accumulate + CdSide // TODO : + RevertOutput * VolumeReverb OPTION: +ExtSide
wire signed [21:0] postVolL    = sumPostVolL[35:14] + {{6{CdSideL[15]}} ,CdSideL};
wire signed [21:0] postVolR    = sumPostVolL[35:14] + {{6{CdSideR[15]}} ,CdSideR};

wire signed [15:0] outL,outR;
clampSRange #(.INW(22),.OUTW(16)) Left_Clamp(.valueIn(postVolL),.valueOut(outL));
clampSRange #(.INW(22),.OUTW(16)) RightClamp(.valueIn(postVolR),.valueOut(outR));

assign AOUTL		= outL;
assign AOUTR		= outR;
assign VALIDOUT		= ctrlSendOut;

endmodule
