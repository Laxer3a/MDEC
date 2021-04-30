/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "spu_def.v"

module spu_front (
	 input					i_clk
	,input					n_rst
	
	// -------------------------------------------
	//   Bus Side
	// -------------------------------------------
	// CPU Side
	// CPU can do 32 bit read/write but they are translated into multiple 16 bit access.
	// CPU can do  8 bit read/write but it will receive 16 bit. Write will write 16 bit. (See No$PSX specs)
	,input					i_SPUCS
	,input					i_SRD
	,input					i_SWRO
	,input	[ 9:0]			i_addr			// Here Sony spec is probably in HALF-WORD (9 bit), we keep in BYTE for now. (10 bit)
	,input	[15:0]			i_dataIn

	,input	[ 4:0]			i_currVoice
	
	,input	[3:0]			i_negNoiseStep
	,input					i_check_Kevent
	,input					i_clearKON
	,input					i_incrXFerAdr
	,input					i_ctrlSendOut
	,input					i_setAsStart
	,input					i_setEndX
	,input					i_isRepeatADPCMFlag
	,input					i_isNotEndADPCMBlock
	,input					i_updateVoiceADPCMAdr
	,input					i_updateVoiceADPCMPos
	,input					i_updateVoiceADPCMPrev
	,input					i_updateADSRVolReg
	,input					i_updateADSRState
	,input					i_validSampleStage2
	
	,input					i_side22Khz
	
	,input					i_nextNewBlock
	
	,input	[16:0]			i_nextADPCMPos
	,input	[31:0]			i_reg_tmpAdpcmPrev
	,input  [22:0]			i_nextAdsrCycle
	,input	[14:0]			i_nextAdsrVol
	,input	 [1:0]			i_nextAdsrState
	
	// For dataOutw
	,input					i_dataTransferBusy
	,input					i_dataTransferWriteReq
	,input					i_dataTransferReadReq
	,input					i_dataTransferRDReq
	,input					i_reg_SPUIRQSet
	
	
	,output [17:0]			o_reg_dataTransferAddrCurr
	,output  [8:0]			o_regRingBufferIndex
	,output	 [1:0]			o_reg_SPUTransferMode
	
	,output [15:0] 			o_currV_startAddr		
	,output 	 			o_currV_NON		
	,output [15:0] 			o_currV_repeatAddr		
	,output [15:0] 			o_currV_adpcmCurrAdr	
	,output [16:0] 			o_currV_adpcmPos		
	,output [31:0] 			o_currV_adpcmPrev		
	,output 				o_currV_KON	
	,output 				o_currV_PMON	
	,output 				o_currV_EON		
	,output signed [14:0] 	o_currV_VolumeL	
	,output signed [14:0] 	o_currV_VolumeR	
	,output [14:0] 			o_currV_AdsrVol	
	,output [15:0] 			o_currV_AdsrLo	
	,output [15:0] 			o_currV_AdsrHi	
	,output  [1:0] 			o_currV_AdsrState	
	,output [22:0] 			o_currV_AdsrCycleCount
	,output [15:0] 			o_currV_sampleRate

	,output					o_reg_SPUIRQEnable
	,output [15:0]			o_reg_ramIRQAddr
	,output [15:0]			o_reg_mBase
	,output  [17:0] 		o_reverb_CounterWord
	,output					o_reg_ReverbEnable
	,output	[3:0]			o_reg_NoiseFrequShift
	,output	[3:0]			o_reg_NoiseFrequStep
	,output 				o_reg_SPUEnable

	,output					o_reg_SPUNotMuted	
	,output					o_reg_CDAudioEnabled
	,output					o_reg_CDAudioReverbEnabled
	,output signed [15:0]	o_reg_CDVolumeL
	,output signed [15:0]	o_reg_CDVolumeR
	,output signed [15:0]	o_reg_mainVolLeft
	,output signed [15:0]	o_reg_mainVolRight
	,output signed [15:0]	o_reg_reverbVolLeft
	,output signed [15:0]	o_reg_reverbVolRight

	,output signed [15:0]	o_dAPF1 
	,output signed [15:0]	o_dAPF2	
	,output signed [15:0]	o_vIIR	
	,output signed [15:0]	o_vCOMB1

	,output signed [15:0]	o_vCOMB2
	,output signed [15:0]	o_vCOMB3
	,output signed [15:0]	o_vCOMB4
	,output signed [15:0]	o_vWALL	

	,output signed [15:0]	o_vAPF1	
	,output signed [15:0]	o_vAPF2	
	,output signed [15:0]	o_mLSAME
	,output signed [15:0]	o_mRSAME

	,output signed [15:0]	o_mLCOMB1
	,output signed [15:0]	o_mRCOMB1
	,output signed [15:0]	o_mLCOMB2
	,output signed [15:0]	o_mRCOMB2

	,output signed [15:0]	o_dLSAME	
	,output signed [15:0]	o_dRSAME	
	,output signed [15:0]	o_mLDIFF	
	,output signed [15:0]	o_mRDIFF	

	,output signed [15:0]	o_mLCOMB3
	,output signed [15:0]	o_mRCOMB3
	,output signed [15:0]	o_mLCOMB4
	,output signed [15:0]	o_mRCOMB4

	,output signed [15:0]	o_dLDIFF	
	,output signed [15:0]	o_dRDIFF	
	,output signed [15:0]	o_mLAPF1	
	,output signed [15:0]	o_mRAPF1	

	,output signed [15:0]	o_mLAPF2	
	,output signed [15:0]	o_mRAPF2	
	,output signed [15:0]	o_vLIN	
	,output signed [15:0]	o_vRIN	

	,output	[15:0]			o_dataOutw
	
);


// DUPLICATE
wire isD8				= (i_addr[9:8]==2'b01);
wire isD80_DFF			= (isD8 && i_addr[7]);							// Latency 0 : D80~DFF
wire isChannel			= ((i_addr[9:8]==2'b00) | (isD8 & !i_addr[7])); 	// Latency 0 : C00~D7F
wire [4:0] channelAdr	= i_addr[8:4];
wire internalWrite		= i_SWRO & i_SPUCS;

//-----------------------------------------
//
//-----------------------------------------
reg [15:0]	reg_volumeL			[23:0];	// Cn0 Voice Volume Left
reg [15:0]	reg_volumeR			[23:0];	// Cn2 Voice Volume Right
reg [15:0]	reg_sampleRate		[23:0];	// Cn4 VxPitch
reg [15:0]	reg_startAddr		[23:0];	// Cn6 ADPCM Start  Address
reg [14:0]	reg_currentAdsrVOL	[23:0];	// CnC Voice Current ADSR Volume
reg [15:0]	reg_repeatAddr		[23:0];	// CnE ADPCM Repeat Address
reg [15:0]	reg_adsrLo			[23:0];
reg [15:0]	reg_adsrHi			[23:0];

reg [ 1:0]	reg_adsrState		[23:0];

reg [31:0]  reg_adpcmPrev		[23:0];	// [NWRITE]
reg [16:0]	reg_adpcmPos		[23:0];
reg [15:0]  reg_adpcmCurrAdr	[23:0];
reg [22:0]  reg_adsrCycleCount	[23:0];

reg [15:0]	reg_reverb			[31:0];

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
reg [15:0]	reg_mBase;					// 32 bit ?
reg [15:0]	reg_ramIRQAddr;				// DA4 Sound RAM IRQ Address
reg [15:0]	reg_dataTransferAddr;		// DA6 Sound RAM Data Transfer Address
reg [17:0]	reg_dataTransferAddrCurr;

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
reg	[1:0]	reg_SPUTransferMode;		//  DAA.5-4
reg			reg_ExtReverbEnabled;		//  DAA.3
reg			reg_CDAudioReverbEnabled;	//  DAA.2
reg			reg_ExtEnabled;				//  DAA.1
reg			reg_CDAudioEnabled;			//  DAA.0
reg	[15:0]	regSoundRAMDataXFerCtrl;	// DAC Sound RAM Data Transfer Control
									// DAE SPU Status Register (SPUSTAT) (Read only)

reg [23:0]	reg_ignoreLoadRepeatAddress;
reg [23:0]	reg_endx;					// D9C Voice Status (ENDX)
reg [8:0] regRingBufferIndex;
reg  [17:0] reverb_CounterWord;
reg regIsLastADPCMBlk;
reg reg_isRepeatADPCMFlag;
//-----------------------------------------

/* Decide if we loop ADSR cycle counter when reach 0 or 1 ?
	0 = Number of cycle + 1 evaluation !
	1 = Number of cycle exactly.
*/
parameter		CHANGE_ADSR_AT = 23'd1;

always @(posedge i_clk)
begin
	if (n_rst == 0)
	begin
		reg_mainVolLeft				<= 16'h0;
		reg_mainVolRight			<= 16'h0;
		reg_reverbVolLeft			<= 16'h0;
		reg_reverbVolRight			<= 16'h0;
		reg_kon						<= 24'h0;
		reg_koff					<= 24'h0;
		reg_kEvent					<= 24'h0;
		reg_kMode					<= 24'h0;
		reg_pmon					<= 24'h0;
		reg_non						<= 24'h0;
		reg_eon						<= 24'h0;
		reg_mBase					<= 16'h0;
		reg_ramIRQAddr				<= 16'h0;
		reg_dataTransferAddr		<= 16'h0;
		reg_CDVolumeL				<= 16'h0;
		reg_CDVolumeR				<= 16'h0;
		reg_ExtVolumeL				<= 16'h0;
		reg_ExtVolumeR				<= 16'h0;
		reg_SPUEnable				<= 1'b0;
		reg_SPUNotMuted				<= 1'b0;
		reg_NoiseFrequShift			<= 4'b0000;
		reg_NoiseFrequStep			<= 4'b1100;
		reg_NoiseStepStore			<= 2'b00;
		reg_ReverbEnable			<= 1'b0;
		reg_SPUIRQEnable			<= 1'b0;
		reg_SPUTransferMode			<= 2'b00;	// STOP Transfer by default.
		reg_ExtReverbEnabled		<= 1'b0;
		reg_CDAudioReverbEnabled	<= 1'b0;
		reg_ExtEnabled				<= 1'b0;
		reg_CDAudioEnabled			<= 1'b0;
		regSoundRAMDataXFerCtrl		<= 16'h4;
		reg_ignoreLoadRepeatAddress	<= 24'd0;
		reg_endx					<= 24'd0;
		regRingBufferIndex			<= 9'd0;
		reverb_CounterWord			<= 18'd0;
		regIsLastADPCMBlk			<= 1'b0;
		reg_isRepeatADPCMFlag		<= 1'b0;
		reg_dataTransferAddrCurr	<= 18'd0;
	end else begin
		if (internalWrite) begin
			if (isD80_DFF) begin		// D80~DFF
				// 011xxx.xxxx
				if (i_addr[6]==0) begin	// D80~DBF
					// 0110xx.xxxx
					case (i_addr[5:1])	
					// D8x ---------------
					// [Address IN WORD, not in BYTE LIKE COMMENTS !!! Take care]
					5'h00:	reg_mainVolLeft		<= i_dataIn;			// 1F801D80h - 180h
					5'h01:	reg_mainVolRight	<= i_dataIn;			// 1F801D82h - 182h
					5'h02:	reg_reverbVolLeft	<= i_dataIn;			// 1F801D84h - 184h
					5'h03:	reg_reverbVolRight	<= i_dataIn;			// 1F801D86h - 186h
					5'h04:	begin
								reg_kon [15: 0]		<= i_dataIn;		// 1F801D88h - 188h
								if (i_dataIn [0] & (reg_kEvent [ 0]==0)) begin reg_kEvent [0] <= 1; reg_kMode [0] <= 1; end
								if (i_dataIn [1] & (reg_kEvent [ 1]==0)) begin reg_kEvent [1] <= 1; reg_kMode [1] <= 1; end
								if (i_dataIn [2] & (reg_kEvent [ 2]==0)) begin reg_kEvent [2] <= 1; reg_kMode [2] <= 1; end
								if (i_dataIn [3] & (reg_kEvent [ 3]==0)) begin reg_kEvent [3] <= 1; reg_kMode [3] <= 1; end
								if (i_dataIn [4] & (reg_kEvent [ 4]==0)) begin reg_kEvent [4] <= 1; reg_kMode [4] <= 1; end
								if (i_dataIn [5] & (reg_kEvent [ 5]==0)) begin reg_kEvent [5] <= 1; reg_kMode [5] <= 1; end
								if (i_dataIn [6] & (reg_kEvent [ 6]==0)) begin reg_kEvent [6] <= 1; reg_kMode [6] <= 1; end
								if (i_dataIn [7] & (reg_kEvent [ 7]==0)) begin reg_kEvent [7] <= 1; reg_kMode [7] <= 1; end
								if (i_dataIn [8] & (reg_kEvent [ 8]==0)) begin reg_kEvent [8] <= 1; reg_kMode [8] <= 1; end
								if (i_dataIn [9] & (reg_kEvent [ 9]==0)) begin reg_kEvent [9] <= 1; reg_kMode [9] <= 1; end
								if (i_dataIn[10] & (reg_kEvent [10]==0)) begin reg_kEvent[10] <= 1; reg_kMode[10] <= 1; end
								if (i_dataIn[11] & (reg_kEvent [11]==0)) begin reg_kEvent[11] <= 1; reg_kMode[11] <= 1; end
								if (i_dataIn[12] & (reg_kEvent [12]==0)) begin reg_kEvent[12] <= 1; reg_kMode[12] <= 1; end
								if (i_dataIn[13] & (reg_kEvent [13]==0)) begin reg_kEvent[13] <= 1; reg_kMode[13] <= 1; end
								if (i_dataIn[14] & (reg_kEvent [14]==0)) begin reg_kEvent[14] <= 1; reg_kMode[14] <= 1; end
								if (i_dataIn[15] & (reg_kEvent [15]==0)) begin reg_kEvent[15] <= 1; reg_kMode[15] <= 1; end
							end
					5'h05:	begin									// 1F801D8Ah - 18Ah
								reg_kon [23:16]		<= i_dataIn[7:0];
								if (i_dataIn [0] & (reg_kEvent [16]==0)) begin reg_kEvent[16] <= 1; reg_kMode[16] <= 1; end
								if (i_dataIn [1] & (reg_kEvent [17]==0)) begin reg_kEvent[17] <= 1; reg_kMode[17] <= 1; end
								if (i_dataIn [2] & (reg_kEvent [18]==0)) begin reg_kEvent[18] <= 1; reg_kMode[18] <= 1; end
								if (i_dataIn [3] & (reg_kEvent [19]==0)) begin reg_kEvent[19] <= 1; reg_kMode[19] <= 1; end
								if (i_dataIn [4] & (reg_kEvent [20]==0)) begin reg_kEvent[20] <= 1; reg_kMode[20] <= 1; end
								if (i_dataIn [5] & (reg_kEvent [21]==0)) begin reg_kEvent[21] <= 1; reg_kMode[21] <= 1; end
								if (i_dataIn [6] & (reg_kEvent [22]==0)) begin reg_kEvent[22] <= 1; reg_kMode[22] <= 1; end
								if (i_dataIn [7] & (reg_kEvent [23]==0)) begin reg_kEvent[23] <= 1; reg_kMode[23] <= 1; end
							end
					5'h06:	begin									// 1F801D8Ch - 18Ch
								reg_koff[15: 0]		<= i_dataIn;			
								if (i_dataIn [0] & (reg_kEvent [ 0]==0)) begin reg_kEvent [0] <= 1; reg_kMode [0] <= 0; end
								if (i_dataIn [1] & (reg_kEvent [ 1]==0)) begin reg_kEvent [1] <= 1; reg_kMode [1] <= 0; end
								if (i_dataIn [2] & (reg_kEvent [ 2]==0)) begin reg_kEvent [2] <= 1; reg_kMode [2] <= 0; end
								if (i_dataIn [3] & (reg_kEvent [ 3]==0)) begin reg_kEvent [3] <= 1; reg_kMode [3] <= 0; end
								if (i_dataIn [4] & (reg_kEvent [ 4]==0)) begin reg_kEvent [4] <= 1; reg_kMode [4] <= 0; end
								if (i_dataIn [5] & (reg_kEvent [ 5]==0)) begin reg_kEvent [5] <= 1; reg_kMode [5] <= 0; end
								if (i_dataIn [6] & (reg_kEvent [ 6]==0)) begin reg_kEvent [6] <= 1; reg_kMode [6] <= 0; end
								if (i_dataIn [7] & (reg_kEvent [ 7]==0)) begin reg_kEvent [7] <= 1; reg_kMode [7] <= 0; end
								if (i_dataIn [8] & (reg_kEvent [ 8]==0)) begin reg_kEvent [8] <= 1; reg_kMode [8] <= 0; end
								if (i_dataIn [9] & (reg_kEvent [ 9]==0)) begin reg_kEvent [9] <= 1; reg_kMode [9] <= 0; end
								if (i_dataIn[10] & (reg_kEvent [10]==0)) begin reg_kEvent[10] <= 1; reg_kMode[10] <= 0; end
								if (i_dataIn[11] & (reg_kEvent [11]==0)) begin reg_kEvent[11] <= 1; reg_kMode[11] <= 0; end
								if (i_dataIn[12] & (reg_kEvent [12]==0)) begin reg_kEvent[12] <= 1; reg_kMode[12] <= 0; end
								if (i_dataIn[13] & (reg_kEvent [13]==0)) begin reg_kEvent[13] <= 1; reg_kMode[13] <= 0; end
								if (i_dataIn[14] & (reg_kEvent [14]==0)) begin reg_kEvent[14] <= 1; reg_kMode[14] <= 0; end
								if (i_dataIn[15] & (reg_kEvent [15]==0)) begin reg_kEvent[15] <= 1; reg_kMode[15] <= 0; end
							end
					5'h07:	begin									// 1F801D8Eh - 18Eh
								reg_koff[23:16]		<= i_dataIn[7:0];		
								if (i_dataIn [0] & (reg_kEvent [16]==0)) begin reg_kEvent[16] <= 1; reg_kMode[16] <= 0; end
								if (i_dataIn [1] & (reg_kEvent [17]==0)) begin reg_kEvent[17] <= 1; reg_kMode[17] <= 0; end
								if (i_dataIn [2] & (reg_kEvent [18]==0)) begin reg_kEvent[18] <= 1; reg_kMode[18] <= 0; end
								if (i_dataIn [3] & (reg_kEvent [19]==0)) begin reg_kEvent[19] <= 1; reg_kMode[19] <= 0; end
								if (i_dataIn [4] & (reg_kEvent [20]==0)) begin reg_kEvent[20] <= 1; reg_kMode[20] <= 0; end
								if (i_dataIn [5] & (reg_kEvent [21]==0)) begin reg_kEvent[21] <= 1; reg_kMode[21] <= 0; end
								if (i_dataIn [6] & (reg_kEvent [22]==0)) begin reg_kEvent[22] <= 1; reg_kMode[22] <= 0; end
								if (i_dataIn [7] & (reg_kEvent [23]==0)) begin reg_kEvent[23] <= 1; reg_kMode[23] <= 0; end
							end
					// D9x ---------------
					5'h08:	reg_pmon[15: 1]		<= i_dataIn[15:1];		// 1F801D90h - 190h /* By reset also reg_pmon[0] = 1'b0; */
					5'h09:	reg_pmon[23:16]		<= i_dataIn[7:0];		// 1F801D92h - 192h
					5'h0A:	reg_non [15: 0]		<= i_dataIn;			// 1F801D94h - 194h
					5'h0B:	reg_non [23:16]		<= i_dataIn[7:0];		// 1F801D96h - 196h
					5'h0C:	reg_eon [15: 0]		<= i_dataIn;			// 1F801D98h - 198h
					5'h0D:	reg_eon [23:16]		<= i_dataIn[7:0];		// 1F801D9Ah - 19Ah
					// 5'h0E: Do nothing ENDX is READONLY.			// 1F801D9Ch - 19Ch
					// 5'h0F: Do nothing ENDX is READONLY.			// 1F801D9Eh - 19Eh
					// DAx ---------------
					// 5'h10: [1F801DA0] Do nothing... (WEIRD reg)
					5'h11:	begin
								reg_mBase			<= i_dataIn;		// 1F801DA2h - 1A2h
								reverb_CounterWord	<= 18'd0;
							end
					5'h12:	reg_ramIRQAddr		<= i_dataIn;			// 1F801DA4h - 1A4h
					5'h13:	begin									// 1F801DA6h - 1A6h
								// Adress (dataIn) is multiple x8 in byte adress.
								reg_dataTransferAddr	 <= i_dataIn;
								reg_dataTransferAddrCurr <= {i_dataIn, 2'd0}; // x8 in byte -> 4x in half-word.
							end
					5'h14:	begin									// 1F801DA8h - 1A8h
								// FIFO INPUT implemented, just not done here.
							end
					5'h15:	begin // SPU Control register			// 1F801DAAh - 1AAh
							reg_SPUEnable		<= i_dataIn[15];
							reg_SPUNotMuted		<= i_dataIn[14];
							reg_NoiseFrequShift	<= i_dataIn[13:10];
							reg_NoiseFrequStep	<= i_negNoiseStep; // See logic with dataIn[9:8];
							reg_NoiseStepStore	<= i_dataIn[9:8];
							reg_ReverbEnable	<= i_dataIn[7];
							reg_SPUIRQEnable	<= i_dataIn[6];
							reg_SPUTransferMode	<= i_dataIn[5:4];
							reg_ExtReverbEnabled		<= i_dataIn[3];
							reg_CDAudioReverbEnabled	<= i_dataIn[2];
							reg_ExtEnabled		<= i_dataIn[1];
							reg_CDAudioEnabled	<= i_dataIn[0];
							end
					5'h16:	regSoundRAMDataXFerCtrl <= i_dataIn;
					// 5'h17:	SPUSTAT is READ ONLY.
					// DBx ---------------
					5'h18:	reg_CDVolumeL		<= i_dataIn;
					5'h19:	reg_CDVolumeR		<= i_dataIn;
					5'h1A:	reg_ExtVolumeL		<= i_dataIn;
					5'h1B:	reg_ExtVolumeR		<= i_dataIn;
					// 5'h1C: Current Main Volume Left
					// 5'h1D: Current Main Volume Right
					// 5'h1E: 4B/DF
					// 5'h1F: 80/21
					default: ;/* Do nothing */
					endcase
				end else begin	// DC0~DFF
					// 0111xx.xxxx
					reg_reverb[i_addr[5:1]] <= i_dataIn;
				end
			end else begin
				if (isChannel) begin
					// 00xxxx.xxxx
					// 010xxx.xxxx
					case (i_addr[3:1])
					3'b000:	// 1F801xx0h - Voice 0..23 Volume Left
						reg_volumeL[channelAdr]		<= i_dataIn;
					3'b001:	// 1F801xx2h - Voice 0..23 Volume Right
						reg_volumeR[channelAdr]		<= i_dataIn;
					3'b010:	// 1F801xx4h - Voice 0..23 ADPCM Sample Rate    (R/W) [15:0] (VxPitch)
						reg_sampleRate[channelAdr]	<= i_dataIn;
					3'b011:	// 1F801xx6h - Voice 0..23 ADPCM Start Address
						reg_startAddr[channelAdr]	<= i_dataIn;
					3'b100:	// 1F801xx8h LSB - Voice 0..23 Attack/Decay/Sustain/Release (ADSR) (32bit) [15:0]x2
						reg_adsrLo[channelAdr]		<= i_dataIn;
					3'b101: // 1F801xx8h (xxA) MSB - Voice 0..23 Attack/Decay/Sustain/Release (ADSR) (32bit) [15:0]x2
						reg_adsrHi[channelAdr]		<= i_dataIn;
					3'b110: // 1F801xxCh - Voice 0..23 Current ADSR volume (R/W) (0..+7FFFh) (or -8000h..+7FFFh on manual write)
						reg_currentAdsrVOL[channelAdr] <= i_dataIn[14:0];
					default: begin
						reg_ignoreLoadRepeatAddress	[channelAdr] <= 1'b1;
						reg_repeatAddr				[channelAdr] <= i_dataIn;
					end
					endcase
				end // else 1xxxxx.xxxx <--- ELSE
					// Current volume L/R channels. (1F801E00h..1F801E5Fh)
					// 1E60~1FFFF Unknown/Unused
			end
		end // end write

		//
		// [OUTSIDE OF WRITE]
		//
		if (i_check_Kevent) begin
			if (reg_kEvent[i_currVoice]) begin	// KON or KOFF occured to this channel...
				// Force reset counter to accept new 'state'.
				reg_adsrCycleCount[i_currVoice] <= CHANGE_ADSR_AT;
				if (reg_kMode[i_currVoice]) begin // Voice start [TODO : have bit that said voice is stopped and check it : reg_endx ?]
					reg_adsrState	[i_currVoice] <= ADSR_ATTACK;
					reg_endx		[i_currVoice] <= 1'b0;
					reg_currentAdsrVOL[i_currVoice] <= 15'd0;
					reg_adpcmCurrAdr[i_currVoice] <= o_currV_startAddr;
					reg_adpcmPos	[i_currVoice] <= 17'd0;
					reg_adpcmPrev	[i_currVoice] <= 32'd0;
					
					if (reg_ignoreLoadRepeatAddress[i_currVoice] == 1'b0) begin
						reg_repeatAddr[i_currVoice] <= o_currV_startAddr;
					end

					// Optionnal... can't stay for ever... ? What's the point, else everything ends up 1.
					// reg_kon			[currVoice] = 1'b0;
				end else begin
					reg_adsrState	[i_currVoice] <= ADSR_RELEASE;
					reg_koff		[i_currVoice] <= 1'b0;
				end
			end
			reg_kEvent			[i_currVoice] <= 1'b0; // Reset Event.
		end
		
		if (i_clearKON) begin
			reg_kon[i_currVoice] <= 1'b0;
		end
		
		if (i_setAsStart) begin
			reg_repeatAddr	[i_currVoice] <= o_currV_adpcmCurrAdr;
		end
		
		if (i_setEndX) begin
			reg_isRepeatADPCMFlag	<= i_isRepeatADPCMFlag; // Store value for later usage a few cycles later...
			regIsLastADPCMBlk		<= 1'b1;
		end else if (i_isNotEndADPCMBlock) begin
			regIsLastADPCMBlk		<= 1'b0;
		end
		
		if (i_updateVoiceADPCMAdr) begin
			if (regIsLastADPCMBlk && (!o_currV_NON)) begin		// NON checked here : we don't want RELEASE and ENDX to happen in Noise Mode. -> Garbage ADPCM can modify things.
				reg_endx		[i_currVoice] <= 1'b1;
				if ((!reg_isRepeatADPCMFlag)) begin 	// Voice must be in ADPCM mode to use flag.
					reg_adsrState	  [i_currVoice] <= ADSR_RELEASE;
					reg_currentAdsrVOL[i_currVoice] <= 15'd0;
				end
			end
			reg_adpcmCurrAdr[i_currVoice] <= regIsLastADPCMBlk ? o_currV_repeatAddr : {o_currV_adpcmCurrAdr + 16'd2};	// Skip 16 byte for next ADPCM block.
		end
		
		if (i_updateVoiceADPCMPos) begin
			// If next block, point to the correct SAMPLE and SUB sample position.
			// else           point to the correct SAMPLE with INDEX and sub sample position.
			reg_adpcmPos[i_currVoice]		<= { {i_nextNewBlock ? 3'd0 : i_nextADPCMPos[16:14]} , i_nextADPCMPos[13:0] };
		end

		if (i_updateVoiceADPCMPrev) begin
			reg_adpcmPrev[i_currVoice]	<= i_reg_tmpAdpcmPrev;
		end

		if (i_incrXFerAdr) begin
			reg_dataTransferAddrCurr 	<= reg_dataTransferAddrCurr + 18'd1; // One half-word increment.
		end
		
		if (i_ctrlSendOut) begin
			regRingBufferIndex 			<= regRingBufferIndex + 9'd1;
		end
		
		// Updated each time a new sample is issued over the voice.
		if (i_validSampleStage2) begin
			reg_adsrCycleCount[i_currVoice]	<= i_nextAdsrCycle;
		end
		// Updated each time a new sample AND counter reach ZERO.
		if (i_updateADSRVolReg) begin
			reg_currentAdsrVOL[i_currVoice]	<= i_nextAdsrVol;
		end
		if (i_updateADSRState) begin
			reg_adsrState[i_currVoice]		<= i_nextAdsrState;
		end
		if (i_ctrlSendOut & i_side22Khz) begin
			//  if counter == last valid index -> loop to zero.
			if (reverb_CounterWord == {~reg_mBase,2'b11}) begin
				// reverb_CounterWord+1   >= 262144 -  reg_mBase
				// reverb_CounterWord+1-1 >= 262144 -  reg_mBase   -1
				// reverb_CounterWord     >= 262144 + ~reg_mBase+1 -1
				// reverb_CounterWord     >=          ~reg_mBase+1 -1  (262144 out of range 17:0, loop counter, not needed), +1-1 simplify.
				// replace                ==          ~reg_mBase
				reverb_CounterWord <= 18'd0;
			end else begin
				reverb_CounterWord <= reverb_CounterWord + 18'd1;
			end
		end
	end // end reset
end // end always block

reg [15:0] dataOutw;

// Read output
always @ (*)
begin
	if (isD80_DFF) begin			// D80~DFF
		if (i_addr[6]==0) begin		// D80~DBF
			case (i_addr[5:1])
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
									i_dataTransferBusy,
									//  9     Data Transfer DMA Read Request   (0=No, 1=Yes)
									i_dataTransferReadReq,
									//  8     Data Transfer DMA Write Request  (0=No, 1=Yes)
									i_dataTransferWriteReq,
									//  7     Data Transfer DMA Read/Write Request ;seems to be same as SPUCNT.Bit5
									i_dataTransferRDReq,
									//  6     IRQ9 Flag                        (0=No, 1=Interrupt Request)
									i_reg_SPUIRQSet,
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
			dataOutw = reg_reverb[i_addr[5:1]];
		end
	end else if (isChannel) begin	// C00~D7F
		case (i_addr[3:1])
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
		if (i_addr[8:7] == 2'b00) begin
			// Current volume L/R channels. (1F801E00h..1F801E5Fh)
			if (i_addr[6:4] < 3'd6) begin
				// 96 bytes
				if (i_addr[1]) begin
					dataOutw = reg_volumeR[channelAdr];
				end else begin
					dataOutw = reg_volumeL[channelAdr];
				end
			end else begin
				// 32 bytes
				// >= 1F801E60~EFF
				case (i_addr[4:1])			// Hard coded stupid stuff, but never know for backward comp.
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

assign o_currV_startAddr			= reg_startAddr		[i_currVoice];
assign o_currV_NON					= reg_non			[i_currVoice];
assign o_currV_repeatAddr			= reg_repeatAddr	[i_currVoice];
assign o_currV_adpcmCurrAdr			= reg_adpcmCurrAdr	[i_currVoice];
assign o_currV_adpcmPos				= reg_adpcmPos		[i_currVoice];
assign o_currV_adpcmPrev			= reg_adpcmPrev		[i_currVoice];
assign o_currV_KON					= reg_kon 			[i_currVoice];
assign o_currV_PMON					= reg_pmon			[i_currVoice];
assign o_currV_EON					= reg_eon 			[i_currVoice];
assign o_currV_VolumeL				= reg_volumeL		[i_currVoice][14:0];
assign o_currV_VolumeR				= reg_volumeR		[i_currVoice][14:0];
assign o_currV_AdsrVol				= reg_SPUEnable ? reg_currentAdsrVOL[i_currVoice] : 15'd0;
assign o_currV_AdsrLo				= reg_adsrLo		[i_currVoice];
assign o_currV_AdsrHi				= reg_adsrHi		[i_currVoice];
assign o_currV_AdsrState			= reg_adsrState		[i_currVoice];
assign o_currV_AdsrCycleCount		= reg_adsrCycleCount[i_currVoice];
assign o_currV_sampleRate			= reg_sampleRate	[i_currVoice];

assign o_reg_SPUIRQEnable			= reg_SPUIRQEnable;
assign o_reg_ramIRQAddr             = reg_ramIRQAddr;
assign o_reg_mBase                  = reg_mBase;
assign o_reverb_CounterWord         = reverb_CounterWord;
assign o_reg_ReverbEnable           = reg_ReverbEnable;
assign o_reg_NoiseFrequShift        = reg_NoiseFrequShift;
assign o_reg_NoiseFrequStep         = reg_NoiseFrequStep;
assign o_reg_SPUEnable              = reg_SPUEnable;
assign o_reg_SPUNotMuted            = reg_SPUNotMuted;
assign o_reg_CDAudioEnabled         = reg_CDAudioEnabled;
assign o_reg_CDAudioReverbEnabled   = reg_CDAudioReverbEnabled;
assign o_reg_CDVolumeL              = reg_CDVolumeL;
assign o_reg_CDVolumeR              = reg_CDVolumeR;
assign o_reg_mainVolLeft            = reg_mainVolLeft;
assign o_reg_mainVolRight           = reg_mainVolRight;
assign o_reg_reverbVolLeft          = reg_reverbVolLeft;
assign o_reg_reverbVolRight         = reg_reverbVolRight;

assign o_dAPF1						= reg_reverb[0];
assign o_dAPF2						= reg_reverb[1];
assign o_vIIR						= reg_reverb[2];
assign o_vCOMB1						= reg_reverb[3];

assign o_vCOMB2						= reg_reverb[4];
assign o_vCOMB3						= reg_reverb[5];
assign o_vCOMB4						= reg_reverb[6];
assign o_vWALL						= reg_reverb[7];

assign o_vAPF1						= reg_reverb[8];
assign o_vAPF2						= reg_reverb[9];
assign o_mLSAME						= reg_reverb[10];
assign o_mRSAME						= reg_reverb[11];

assign o_mLCOMB1					= reg_reverb[12];
assign o_mRCOMB1					= reg_reverb[13];
assign o_mLCOMB2					= reg_reverb[14];
assign o_mRCOMB2					= reg_reverb[15];

assign o_dLSAME						= reg_reverb[16];
assign o_dRSAME						= reg_reverb[17];
assign o_mLDIFF						= reg_reverb[18];
assign o_mRDIFF						= reg_reverb[19];

assign o_mLCOMB3					= reg_reverb[20];
assign o_mRCOMB3					= reg_reverb[21];
assign o_mLCOMB4					= reg_reverb[22];
assign o_mRCOMB4					= reg_reverb[23];

assign o_dLDIFF						= reg_reverb[24];
assign o_dRDIFF						= reg_reverb[25];
assign o_mLAPF1						= reg_reverb[26];
assign o_mRAPF1						= reg_reverb[27];

assign o_mLAPF2						= reg_reverb[28];
assign o_mRAPF2						= reg_reverb[29];
assign o_vLIN						= reg_reverb[30];
assign o_vRIN						= reg_reverb[31];

assign o_reg_dataTransferAddrCurr	= reg_dataTransferAddrCurr;
assign o_regRingBufferIndex			= regRingBufferIndex;
assign o_reg_SPUTransferMode		= reg_SPUTransferMode;

assign o_dataOutw					= dataOutw;

endmodule
