/*	
	TODO : Finish READ of registers and status.
	TODO : Finish the time slicing logic. (decide the whole state machine for the SPU)
			- Reverb start,control
			- Per channel control + request memory including ADPCM.
			- Free timing for uploading CPU data to SPU RAM.
	TODO : Implement FIFO for input data.
	TODO : Implement DATA transfer.
	TODO : Implement ADPCM Decoder.
	TODO : Implement ADPCM Loader.
			- Support kick IRQ when request specific adress block.
			- Support loop of channel.
	TODO : Implement ADSR. (Including KON / KOFF)
	TODO : Implement Volume Sweep.
	TODO : Implement state machine with accumulator for output.
	TODO : Implement Reverb.
	
	// --> Seperate block is better for testing and more concise code.
	TODO : Test ADSR and Noise block using Verilator.
	TODO : Test ADPCM Decoding block using Verilator.
*/

module SPU_tmp(
	input			clk,
	input			n_rst,
	
	// CPU Side
	// CPU can do 32 bit read/write but they are translated into multiple 16 bit access.
	// CPU can do  8 bit read/write but it will receive 16 bit. Write will write 16 bit. (See No$PSX specs)
	input			spuSelect,	// We have only 11 adress bit, so for read and write, we tell the chip is selected.
	input	[10:0]	addr,		// Here Sony spec is probably in HALF-WORD (10 bit), we keep in BYTE for now. (11 bit)
	input			read,
	input			write,
	input	[15:0]	dataIn,
	output	[15:0]	dataOut,
	output			dataOutValid,
	output			spuInterrupt,
	
	// CPU DMA stuff.
	input			srd,
	input			swr0,
	input			spudack,
	output			spudreq,

	// RAM Side
	output	[17:0]	adr,
	output			dataReadRAM,
	output			dataWriteRAM,
	input	[15:0]	dataInRAM,
	output	[15:0]	dataOutRAM,
	
	// From CD-Rom, serial stuff in original HW,
	// 
	input  [15:0]	CDRomInL,
	input  [15:0]	CDRomInR,
	input			inputL,
	input			inputR,
	
	// Audio DAC Out
	output [15:0]	leftOut,
	output [15:0]	rightOut,
	output 			pushToDAC
);

wire internalWrite = write & spuSelect;
wire internalRead  = read  & spuSelect;

// --------------------------------------------------------------------------------------
//		[FRONT END : Register setup]
// --------------------------------------------------------------------------------------
reg [15:0]	reg_volumeL			[23:0];
reg [15:0]	reg_volumeR			[23:0];
reg [15:0]	reg_sampleRate		[23:0];
reg [15:0]	reg_startAddr		[23:0];
reg [15:0]	reg_repeatAddr		[23:0];
reg [23:0]	reg_repeatUserSet;
reg [15:0]	reg_adsrLo			[23:0];
reg [15:0]	reg_adsrHi			[23:0];
reg [15:0]	reg_currentAdsr		[23:0];
reg [15:0]	reg_mainVolLeft;
reg [15:0]	reg_mainVolRight;
reg [15:0]	reg_reverbVolLeft;
reg [15:0]	reg_reverbVolRight;
reg [23:0]	reg_kon;
reg [23:0]	reg_koff;
reg [23:0]	reg_pmon;
reg [23:0]	reg_non;
reg [23:0]	reg_eon;
reg [23:0]	reg_endx;
reg [15:0]	reg_reverb			[31:0];
reg [15:0]	reg_mBase;					// 32 bit ?
reg [15:0]	reg_ramIRQAddr;
reg [15:0]	reg_dataTransferAddr;
reg [15:0]	reg_CDVolume;
reg [15:0]	reg_ExtVolumeL;
reg [15:0]	reg_ExtVolumeR;

reg 		reg_SPUEnable;
reg			reg_SPUMute;
reg	[3:0]	reg_NoiseFrequShift;
reg	[3:0]	reg_NoiseFrequStep;
reg			reg_ReverbEnable;
reg			reg_SPUIRQEnable;
reg	[1:0]	reg_SPUTransferMode;
reg			reg_ExtReverbEnabled;
reg			reg_CDAudioReverbEnabled;
reg			reg_ExtEnabled;
reg			reg_CDAudioEnabled;

//-----
// TODO Data transfer FIFO here...
//-----

	wire launchFIFO;
	wire launchHeaderRead;
	wire readBRAM_AdrPitchCurrSampleCounter;
	
	
	/*
	case STEP0:
	begin
		launchFIFO							<= 0;
		readBRAM_AdrPitchCurrSampleCounter	<= 1;
	end
	case STEP1:
	begin
		
	end
	case STEP2:
	begin
	end
	case STEP3:
	begin
	end
	case STEP4:
	begin
	end
	case STEP5:
	begin
	end
	case STEP6:
	begin
	end
	case STEP7:
	begin
	end
	*/

// -----------------------------------------------------------------
// REGISTER READ / WRITE SECTION
// -----------------------------------------------------------------
reg [3:0] negNoiseStep;
always @(*) begin
	case (dataIn[9:8])
	2'b00: negNoiseStep <= 4'b1100;	// -4
	2'b01: negNoiseStep <= 4'b1011;	// -5
	2'b10: negNoiseStep <= 4'b1010;	// -6
	2'b11: negNoiseStep <= 4'b1001;	// -7
	endcase
end

wire isD8      = (addr[9:8]==2'b01);
wire isD80_DFF = (isD8 && addr[7]);							// Latency 0 : D80~DFF
wire isReverb  = isD80_DFF & addr[6];						// Latency 1 : DC0~DFF
wire isChannel = ((addr[9:8]==2'b00) | (isD8 & !addr[7])); 	// Latency 1 : C00~D7F
wire isReadLatency = isReverb | isChannel;					// Latency 1 because we use BRAM to access registers.

reg [15:0] readVolumeL;
reg [15:0] readVolumeR;
reg [15:0] readSampleRate;
reg [15:0] readStartAddr;
reg [15:0] readAdsrLo;
reg [15:0] readAdsrHi;
reg [15:0] readCurrAdsr;

//----------------- Repeat Address is accessed by BOTH system (CPU & State machine, needed TRUE DOUBLE PORT)
wire [15:0] readRepeatAddr;
wire setRepeatByUser 	= (internalWrite & (!isD80_DFF) & isChannel & (addr[3:2]==2'b00) & (addr[3:1]==3'b111));
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
//---------------------------------------------------------------------------------------------------------------

reg [15:0] readReverb;

always @ (posedge clk)
begin
	if (n_rst == 0)
	begin
		reg_mainVolLeft			<= 16'h0;
		reg_mainVolRight		<= 16'h0;
		reg_reverbVolLeft		<= 16'h0;
		reg_reverbVolRight		<= 16'h0;
		reg_kon					<= 24'h0;
		reg_koff				<= 24'h0;
		reg_pmon				<= 24'h0;
		reg_non					<= 24'h0;
		reg_eon					<= 24'h0;
		reg_mBase				<= 16'h0;
		reg_ramIRQAddr			<= 16'h0;
		reg_dataTransferAddr	<= 16'h0;
		reg_CDVolume			<= 16'h0;
		reg_ExtVolumeL			<= 16'h0;
		reg_ExtVolumeR			<= 16'h0;
		reg_SPUEnable			<= 1'b0;
		reg_SPUMute				<= 1'b0;
		reg_NoiseFrequShift		<= 4'b0;
		reg_NoiseFrequStep		<= 4'b1100;
		reg_ReverbEnable		<= 1'b0;
		reg_SPUIRQEnable		<= 1'b0;
		reg_SPUTransferMode		<= 2'b00;
		reg_ExtReverbEnabled	<= 1'b0;
		reg_CDAudioReverbEnabled<= 1'b0;
		reg_ExtEnabled			<= 1'b0;
		reg_CDAudioEnabled		<= 1'b0;
	end 
	else 
	begin
		if (internalWrite) 
		begin
			if (isD80_DFF) 
			begin	// D80~DFF
				if (addr[6]==0) 
				begin					// D80~DBE
					case (addr[5:1])	
					// [Address IN WORD, not in BYTE LIKE COMMENTS !!! Take care]
					5'h00:	reg_mainVolLeft		<= dataIn;
					5'h01:	reg_mainVolRight	<= dataIn;
					5'h02:	reg_reverbVolLeft	<= dataIn;
					5'h03:	reg_reverbVolRight	<= dataIn;
					5'h04:	reg_kon[15: 0]		<= dataIn;
					5'h05:	reg_kon[23:16]		<= dataIn[7:0];
					5'h06:	reg_koff[15: 0]		<= dataIn;
					5'h07:	reg_koff[23:16]		<= dataIn[7:0];
					5'h08:	reg_pmon[15: 1]		<= dataIn[15:1];
					5'h09:	reg_pmon[23:16]		<= dataIn[7:0];
					5'h0A:	reg_non[15: 0]		<= dataIn;
					5'h0B:	reg_non[23:16]		<= dataIn[7:0];
					5'h0C:	reg_eon[15: 0]		<= dataIn;
					5'h0D:	reg_eon[23:16]		<= dataIn[7:0];
					5'h0E:	;// Do nothing ENDX is READONLY.
					5'h0F:	;// Do nothing ENDX is READONLY.
					5'h10:	;// Do nothing...
					5'h11:	reg_mBase			<= dataIn;
					5'h12:	reg_ramIRQAddr		<= dataIn;
					5'h13:	reg_dataTransferAddr<= dataIn;
					5'h14:	;// TODO FIFO work, not done here, WARNING, PROTECT FOR EDGE TRANSITION : WRITE during multiple cycle will perform multiple WRITE of the same value !!!!
					5'h16:	begin // SPU Control register
							reg_SPUEnable		<= dataIn[15];
							reg_SPUMute			<= dataIn[14];
							reg_NoiseFrequShift	<= dataIn[13:10];
							reg_NoiseFrequStep	<= negNoiseStep; // See logic with dataIn[9:8];
							reg_ReverbEnable	<= dataIn[7];
							reg_SPUIRQEnable	<= dataIn[6];
							reg_SPUTransferMode	<= dataIn[5:4];
							reg_ExtReverbEnabled		<= dataIn[3];
							reg_CDAudioReverbEnabled	<= dataIn[2];
							reg_ExtEnabled		<= dataIn[1];
							reg_CDAudioEnabled	<= dataIn[0];
							end
					5'h17:	;// Read only register.
					5'h18:	reg_CDVolume		<= dataIn;
					5'h19:	reg_ExtVolumeL		<= dataIn;
					5'h1A:	reg_ExtVolumeR		<= dataIn;
					5'h1B:	;/*TODO ???*/
					5'h1C:	;/*TODO ???*/
					default: ;/* Do nothing */
					endcase
				end
				else 
				begin						// DC0~DFF
					reg_reverb[addr[5:1]] <= dataIn;
				end
			end
			else
			begin
				if (isChannel) begin	// C00~D7F
					if (addr[3:2]==2'b00) begin
						// 1F801xx0h - Voice 0..23 Volume Left
						// 1F801xx2h - Voice 0..23 Volume Right
						if (addr[1])
						begin
							reg_volumeR[addr[8:4]] <= dataIn;
						end
						if (!addr[1])
						begin
							reg_volumeL[addr[8:4]] <= dataIn;
						end
					end
					if (addr[3:1]==3'b010) begin
						// 1F801xx4h - Voice 0..23 ADPCM Sample Rate    (R/W) [15:0] (VxPitch)
						reg_sampleRate[addr[8:4]] <= dataIn;
					end
					if (addr[3:1]==3'b011) begin
						// 1F801xx6h - Voice 0..23 ADPCM Start Address
						reg_startAddr[addr[8:4]] <= dataIn;
					end
					if (addr[3:1]==3'b100) begin
						// 1F801xx8h LSB - Voice 0..23 Attack/Decay/Sustain/Release (ADSR) (32bit) [15:0]x2
						reg_adsrLo[addr[8:4]] <= dataIn;
					end
					if (addr[3:1]==3'b101) begin
						// 1F801xx8h (xxA) MSB - Voice 0..23 Attack/Decay/Sustain/Release (ADSR) (32bit) [15:0]x2
						reg_adsrHi[addr[8:4]] <= dataIn;
					end
					
					if (addr[3:1]==3'b110) begin
						// 1F801xxCh - Voice 0..23 Current ADSR volume (R/W) (0..+7FFFh) (or -8000h..+7FFFh on manual write)
						reg_currentAdsr[addr[8:4]] <= dataIn;
					end
				end
			end
		end
		else
		begin // No write.
			// CPU for now has priority when writing a repeat address.
			if (overwriteRepeatAddress) begin
				reg_repeatAddr[currVoice] <= newRepeatAddress;
			end
		
			// Register read...
			readVolumeR 	<= reg_volumeR[addr[8:4]];
			readVolumeL 	<= reg_volumeL[addr[8:4]];
			readSampleRate	<= reg_sampleRate[addr[8:4]];
			readStartAddr	<= reg_startAddr[addr[8:4]];
			readAdsrLo		<= reg_adsrLo[addr[8:4]];
			readAdsrHi		<= reg_adsrHi[addr[8:4]];
			readCurrAdsr	<= reg_currentAdsr[addr[8:4]];
			// DONE BY DPRAM readRepeatAddr	<= reg_repeatAddr[addr[8:4]];
			readReverb		<= reg_reverb[addr[5:1]];
			
			if (resetCurrentKeyOn) begin
				case (currVoice)
				5'd0 : reg_kon[0 ] <= 1'b0;
				5'd1 : reg_kon[1 ] <= 1'b0;
				5'd2 : reg_kon[2 ] <= 1'b0;
				5'd3 : reg_kon[3 ] <= 1'b0;
				5'd4 : reg_kon[4 ] <= 1'b0;
				5'd5 : reg_kon[5 ] <= 1'b0;
				5'd6 : reg_kon[6 ] <= 1'b0;
				5'd7 : reg_kon[7 ] <= 1'b0;
				5'd8 : reg_kon[8 ] <= 1'b0;
				5'd9 : reg_kon[9 ] <= 1'b0;
				5'd10: reg_kon[10] <= 1'b0;
				5'd11: reg_kon[11] <= 1'b0;
				5'd12: reg_kon[12] <= 1'b0;
				5'd13: reg_kon[13] <= 1'b0;
				5'd14: reg_kon[14] <= 1'b0;
				5'd15: reg_kon[15] <= 1'b0;
				5'd16: reg_kon[16] <= 1'b0;
				5'd17: reg_kon[17] <= 1'b0;
				5'd18: reg_kon[18] <= 1'b0;
				5'd19: reg_kon[19] <= 1'b0;
				5'd20: reg_kon[20] <= 1'b0;
				5'd21: reg_kon[21] <= 1'b0;
				5'd22: reg_kon[22] <= 1'b0;
				5'd23: reg_kon[23] <= 1'b0;
				endcase
			end

			if (resetCurrentKeyOff) begin
				case (currVoice)
				5'd0 : reg_koff[0 ] <= 1'b0;
				5'd1 : reg_koff[1 ] <= 1'b0;
				5'd2 : reg_koff[2 ] <= 1'b0;
				5'd3 : reg_koff[3 ] <= 1'b0;
				5'd4 : reg_koff[4 ] <= 1'b0;
				5'd5 : reg_koff[5 ] <= 1'b0;
				5'd6 : reg_koff[6 ] <= 1'b0;
				5'd7 : reg_koff[7 ] <= 1'b0;
				5'd8 : reg_koff[8 ] <= 1'b0;
				5'd9 : reg_koff[9 ] <= 1'b0;
				5'd10: reg_koff[10] <= 1'b0;
				5'd11: reg_koff[11] <= 1'b0;
				5'd12: reg_koff[12] <= 1'b0;
				5'd13: reg_koff[13] <= 1'b0;
				5'd14: reg_koff[14] <= 1'b0;
				5'd15: reg_koff[15] <= 1'b0;
				5'd16: reg_koff[16] <= 1'b0;
				5'd17: reg_koff[17] <= 1'b0;
				5'd18: reg_koff[18] <= 1'b0;
				5'd19: reg_koff[19] <= 1'b0;
				5'd20: reg_koff[20] <= 1'b0;
				5'd21: reg_koff[21] <= 1'b0;
				5'd22: reg_koff[22] <= 1'b0;
				5'd23: reg_koff[23] <= 1'b0;
				endcase
			end
		end // end write
	end // end reset
end // end always block

reg [15:0] dataOutw;

assign dataOut		= dataOutw;

reg internalReadPipe;
always @ (posedge clk) internalReadPipe = internalRead;
assign dataOutValid	= internalReadPipe; // Pipe read. For now everything answer at the NEXT clock, ONCE.

// Read output
always @ (*)
begin
	if (isD80_DFF) begin	// D80~DFF
		if (addr[6]==0) begin					// D80~DBE
			case (addr[5:1])
			5'h00:	dataOutw <= reg_mainVolLeft;
			5'h01:	dataOutw <= reg_mainVolRight;
			5'h02:	dataOutw <= reg_reverbVolLeft;
			5'h03:	dataOutw <= reg_reverbVolRight;
			5'h04:	dataOutw <= reg_kon[15: 0];
			5'h05:	dataOutw <= { 8'd0, reg_kon[23:16] };
			5'h06:	dataOutw <= reg_koff[15: 0];
			5'h07:	dataOutw <= { 8'd0, reg_koff[23:16] };
			5'h08:	dataOutw <= reg_pmon[15: 0];	// Force channel ZERO to have no PMON at WRITE.
			5'h09:	dataOutw <= { 8'd0, reg_pmon[23:16] };
			5'h0A:	dataOutw <= reg_non[15: 0];
			5'h0B:	dataOutw <= { 8'd0, reg_non[23:16] };
			5'h0C:	dataOutw <= reg_eon[15: 0];
			5'h0D:	dataOutw <= { 8'd0, reg_eon[23:16] };
			5'h0E:	dataOutw <= reg_endx[15: 0];
			5'h0F:	dataOutw <= { 8'd0, reg_endx[23:16] };
			5'h10:	dataOutw <= 16'd0;
			5'h11:	dataOutw <= reg_mBase;
			5'h12:	dataOutw <= reg_ramIRQAddr;
			5'h13:	dataOutw <= reg_dataTransferAddr;
			5'h14:	dataOutw <= 16'd0; // Can't read FIFO.
			5'h16:	begin // SPU Control register
					dataOutw <= { 	reg_SPUEnable,
									reg_SPUMute,
									reg_NoiseFrequShift,
									reg_NoiseFrequStep,
									reg_ReverbEnable,
									reg_SPUIRQEnable,
									reg_SPUTransferMode,
									reg_ExtReverbEnabled,
									reg_CDAudioReverbEnabled,
									reg_ExtEnabled,
									reg_CDAudioEnabled
								};
						end
			5'h17:	dataOutw <= 16'd0;
			5'h18:	dataOutw <= reg_CDVolume;
			5'h19:	dataOutw <= reg_ExtVolumeL;
			5'h1A:	dataOutw <= reg_ExtVolumeR;
			5'h1B:	dataOutw <= 16'd0;
			5'h1C:	dataOutw <= 16'd0;
			default: dataOutw <= 16'd0;
			endcase
		end else begin						// DC0~DFF
			dataOutw <= readReverb;
		end
	end else if (isChannel) begin	// C00~D7F
		case (addr[3:2])
		3'b000:dataOutw <= readVolumeL;
		3'b001:dataOutw <= readVolumeR;
		3'b010:dataOutw <= readSampleRate;
		3'b011:dataOutw <= readStartAddr;
		3'b100:dataOutw <= readAdsrLo;
		3'b101:dataOutw <= readAdsrHi;
		3'b110:dataOutw <= readCurrAdsr;
		3'b111:dataOutw <= readRepeatAddr;
		endcase
	end else begin
		dataOutw <= 16'd0;
	end
end

reg [0:15] currV_VolumeL;
reg [0:15] currV_VolumeR;
reg [0:15] currV_sampleRate;
reg [0:15] currV_startAddr;
reg [0:15] currV_adsrLo;
reg [0:15] currV_adsrHi;
reg [0:15] currV_currentAdsr;
wire [0:15] currV_repeatAddr; // DP RAM output.

always @ (posedge clk)
begin
	// Dual Port READ
	currV_VolumeL		<= reg_volumeL		[currVoice];
	currV_VolumeR 		<= reg_volumeR		[currVoice];
	currV_sampleRate	<= reg_sampleRate	[currVoice];
	currV_startAddr		<= reg_startAddr	[currVoice];
	currV_adsrLo		<= reg_adsrLo		[currVoice];
	currV_adsrHi		<= reg_adsrHi		[currVoice];
	currV_currentAdsr	<= reg_currentAdsr	[currVoice];
	// DPRAM Does the job... no need for currV_repeatAddr <= reg_repeatAddr	[currVoice];
end

// -----------------------------------------------------------------
// INTERNAL TIMING & STATE SECTION
// -----------------------------------------------------------------
reg  [9:0] counter768;
reg        counter22Khz;
reg        pipeCounter22Khz;
wire [9:0] nextCounter768 = counter768 + 10'd1;

wire ctrl44Khz = (nextCounter768 == 10'd768);
wire ctrl22Khz = pipeCounter22Khz & !counter22Khz;

always @(posedge clk)
begin
	if (n_rst == 0)
	begin
		counter768			<= 10'd0;
		pipeCounter22Khz	<= 1;
		counter22Khz		<= 0;
		currVoice			<= 5'd0;		
	end else begin
		counter768 <= ctrl44Khz ? 10'd0 : nextCounter768;
		if (ctrl44Khz) begin
			pipeCounter22Khz	= counter22Khz;
			counter22Khz		= !counter22Khz;
		end
		currVoice			<= currVoice + voiceIncrement;
	end
end

// OUTPUT --------------------------------------------
// Set to 1 every first cycle in the loop.
wire is16	= (counter768[3:0] == 4'd0);	// Loop 16 cycles.
wire is32	=  is16 & !counter768[4];		// Loop 32 cycles.
wire is768	= (counter768 == 10'd0);		// Loop 768 cycles.
reg [4:0] currVoice;						// Loop 0..23
//----------------------------------------------------

always @(posedge clk)
begin
	if (n_rst == 0)
	begin
		reg_repeatUserSet <= 24'd0;
	end else begin
		if (setRepeatByUser)
		begin
			// A/ SET FLAG WHEN WRITING CHANNEL REPEAT ADR ===> FLAG 1.
			case (addr[8:4])
			5'd0 : reg_repeatUserSet[ 0] <= 1;
			5'd1 : reg_repeatUserSet[ 1] <= 1;
			5'd2 : reg_repeatUserSet[ 2] <= 1;
			5'd3 : reg_repeatUserSet[ 3] <= 1;
			5'd4 : reg_repeatUserSet[ 4] <= 1;
			5'd5 : reg_repeatUserSet[ 5] <= 1;
			5'd6 : reg_repeatUserSet[ 6] <= 1;
			5'd7 : reg_repeatUserSet[ 7] <= 1;
			5'd8 : reg_repeatUserSet[ 8] <= 1;
			5'd9 : reg_repeatUserSet[ 9] <= 1;
			5'd10: reg_repeatUserSet[10] <= 1;
			5'd11: reg_repeatUserSet[11] <= 1;
			5'd12: reg_repeatUserSet[12] <= 1;
			5'd13: reg_repeatUserSet[13] <= 1;
			5'd14: reg_repeatUserSet[14] <= 1;
			5'd15: reg_repeatUserSet[15] <= 1;
			5'd16: reg_repeatUserSet[16] <= 1;
			5'd17: reg_repeatUserSet[17] <= 1;
			5'd18: reg_repeatUserSet[18] <= 1;
			5'd19: reg_repeatUserSet[19] <= 1;
			5'd20: reg_repeatUserSet[20] <= 1;
			5'd21: reg_repeatUserSet[21] <= 1;
			5'd22: reg_repeatUserSet[22] <= 1;
			5'd23: reg_repeatUserSet[23] <= 1;
			endcase
		end
		
		// Not a ELSE. priority here...
		if (resetRepeatUserFlagByCurrChannel) begin
			case (currVoice)
			5'd0 : reg_repeatUserSet[ 0] <= 0;
			5'd1 : reg_repeatUserSet[ 1] <= 0;
			5'd2 : reg_repeatUserSet[ 2] <= 0;
			5'd3 : reg_repeatUserSet[ 3] <= 0;
			5'd4 : reg_repeatUserSet[ 4] <= 0;
			5'd5 : reg_repeatUserSet[ 5] <= 0;
			5'd6 : reg_repeatUserSet[ 6] <= 0;
			5'd7 : reg_repeatUserSet[ 7] <= 0;
			5'd8 : reg_repeatUserSet[ 8] <= 0;
			5'd9 : reg_repeatUserSet[ 9] <= 0;
			5'd10: reg_repeatUserSet[10] <= 0;
			5'd11: reg_repeatUserSet[11] <= 0;
			5'd12: reg_repeatUserSet[12] <= 0;
			5'd13: reg_repeatUserSet[13] <= 0;
			5'd14: reg_repeatUserSet[14] <= 0;
			5'd15: reg_repeatUserSet[15] <= 0;
			5'd16: reg_repeatUserSet[16] <= 0;
			5'd17: reg_repeatUserSet[17] <= 0;
			5'd18: reg_repeatUserSet[18] <= 0;
			5'd19: reg_repeatUserSet[19] <= 0;
			5'd20: reg_repeatUserSet[20] <= 0;
			5'd21: reg_repeatUserSet[21] <= 0;
			5'd22: reg_repeatUserSet[22] <= 0;
			5'd23: reg_repeatUserSet[23] <= 0;
			endcase
		end
	end
end

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

wire VoiceRepeatUserSet; SelectCh VoiceRepeatSelectCh(.v(reg_repeatUserSet), .ch(currVoice), .o(VoiceRepeatUserSet));

// [Control Signal from the state machine]
wire resetCurrentKeyOn;					// Will reset KeyOn  flag for the current voice.
wire resetCurrentKeyOff;				// Will reset KeyOff flag for the current voice.
wire resetRepeatUserFlagByCurrChannel;	// Will reset the userFlag.
wire voiceIncrement;						// Goto the next voice.
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
	Step = VxPitch                  ;range +0000h..+FFFFh (0...705.6 kHz)						s4.12
	IF PMON.Bit(x)=1 AND (x>0)      ;pitch modulation enable
		Factor = VxOUTX(x-1)          ;range -8000h..+7FFFh (prev voice amplitude)
		Factor = Factor+8000h         ;range +0000h..+FFFFh (factor = 0.00 .. 1.99)				s1.15 -> -0.99,+0.99
		Step=SignExpand16to32(Step)   ;hardware glitch on VxPitch>7FFFh, make sign
		Step = (Step * Factor) SAR 15 ;range 0..1FFFFh (glitchy if VxPitch>7FFFh -> VxPitch as signed value) 6.26 -> 11
		Step=Step AND 0000FFFFh       ;hardware glitch on VxPitch>7FFFh, kill sign
	IF Step>3FFFh then Step=4000h   ;range +0000h..+3FFFh (0.. 176.4kHz)
	Counter = Counter + Step

	SamplePos 			<= Counter[..:12]
	Interpolator		<= Counter[11: 3]
	*/
//--------------------------------------------------
//  INPUT
//--------------------------------------------------
wire PMON; SelectCh PMONSelect(.v(reg_pmon), .ch(currVoice), .o(PMON));	// Select Bit PMON

wire signed [15:0]  VxPitch				= currV_sampleRate;
reg  signed [15:0]	prevChannelVxOut; // TODO
//--------------------------------------------------

// Convert S16 to U16 (Add +0x8000)
wire SgnS2U						= prevChannelVxOut[15] ^ 1;
// Select Previous output modulation or standard pitch.
wire 				pitchSel	= PMON  & (currVoice != 5'd0);
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
wire		[15:0]	currPitch	= { 1'b0, GT4000, lowPart };



//--------------------------------------------------
reg			[16:0]	sampleCounter;	// 5.12 Sample counter in ADPCM block.
wire				load;
wire				rstLow;
wire		[11:0]	lowPos = rstLow ? 12'd0 : sampleCounter[11:0];
always @(posedge clk)
begin
	sampleCounter <= load 	? { 5'd0 , lowPos } 
							: (sampleCounter + { 1'b0 , currPitch } );
end
wire 		[7:0] 	interpolator = sampleCounter[11:3];

// PB : not well defined arch here... TODO : What in case of START. pure 0.

// --------------------------------------------------------------------------------------
//		Stage 0 : ADPCM Input 			(common : once every 32 cycle)
// --------------------------------------------------------------------------------------

// TODO : Adress loading unit.

// TODO : ADPCM decode unit.	

// TODO : Loop point / one shot spec.
wire ENDX; SelectCh ENDXSelect(.v(reg_endx),.ch(currVoice), .o(ENDX));

// TODO : IRQ Load

// --------------------------------------------------------------------------------------
//		Stage 1A : ADPCM Output (once every   32 cycle)
// --------------------------------------------------------------------------------------
/*	idx = 0,1,2,3

	[No$PSX Doc]
	-----------------------------
	((gauss[000h+i] *    new)
	((gauss[100h+i] *    old)
	((gauss[1FFh-i] *  older)
	((gauss[0FFh-i] * oldest)
	-----------------------------
	idx
	0 = NEW			@0xx
	1 = OLD			@1xx
	2 = OLDER		@1FF - xx
	3 = OLDEST		@0FF - xx
*/
wire [1:0] idx;
wire [8:0] romAdr = idx[1] ? {!idx[0], ~interpolator} : { idx[0], interpolator };
wire signed[15:0] ratio;

InterpROM InterpROM_inst(
	.clk		(clk),
	.adr		(romAdr),
	.dataOut	(ratio)
);

// --------------------------------------------------------------------------------------
//	[COMPLETED]	Stage Z  : Noise Output        	(once per audio sample, every 768 cycle)
// --------------------------------------------------------------------------------------
wire [15:0] noiseLevel;
NoiseUnit NoiseUnit_inst(
	.clk			(clk),
	.i_nrst			(n_rst),
	.i_ctrl44Khz	(ctrl44Khz),
	.i_noiseShift	(reg_NoiseFrequShift),
	.i_noiseStep 	(reg_NoiseFrequStep),
	.o_noiseOut  	(noiseLevel)
);

// --------------------------------------------------------------------------------------
//	[COMPLETED]	Stage 2 : Select ADPCM / Noise 	(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire NON; SelectCh NONSelect(.v(reg_non), .ch(currVoice), .o(NON));	// Select Bit NON

wire [15:0] ADPCM_Value = 16'h0;		// Todo!
wire [15:0] ChannelValue = NON ? noiseLevel : ADPCM_Value;

// --------------------------------------------------------------------------------------
//		Stage 3A : Compute ADSR        	(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire [15:0] AdsrLo = currV_adsrLo;
wire [15:0] AdsrHi = currV_adsrHi;

reg [3:0] ADSRState;	// Todo.

reg 				EnvExponential;
reg signed [1:0] 	EnvDirection;
reg signed [4:0]	EnvShift;
reg signed [3:0]	EnvStep;
wire signed [4:0]	SustainLevel = AdsrLo[3:0] + 4'b0001; // 11 bit shift for compare.

wire  KON; SelectCh KONSelect (.v(reg_kon) , .ch(currVoice), .o( KON));
wire KOFF; SelectCh KOFFSelect(.v(reg_koff), .ch(currVoice), .o(KOFF));

always @(*) begin
	case (ADSRState)
	0: // A State
	begin
		EnvExponential	<= AdsrLo[15];
		EnvDirection	<= 2'b01;					// +1 Signed
		EnvShift		<= AdsrLo[14:10];			// 0..+1F
		EnvStep			<= { 2'b01, AdsrLo[9:8] };	// +4..+7
	end
	1: // D State
	begin
		EnvExponential	<= 1'b1;						// Exponential
		EnvDirection	<= 2'b11;					// -1 Signed
		EnvShift		<= { 1'b0, AdsrLo[7:4] };	// 0..+0F
		EnvStep			<= 4'b1000;					// -8
	end
	2: // S State
	begin
		EnvExponential	<= AdsrHi[15];
		EnvDirection	<= { AdsrHi[14], 1'b1 };		// -1,+1
		EnvShift		<= AdsrHi[12:8];				// 0..+1F
		// +7/+6/+5/+4 if INCREASE
		// -8/-7/-6/-5 if DECREASE
		EnvStep			<= { AdsrHi[14] , !AdsrHi[14] , ~AdsrHi[7:6] };
	end
	3: // R State	
	begin
		EnvExponential	<= AdsrHi[5];
		EnvDirection	<= 2'b11;					// -1
		EnvShift		<= AdsrHi[4:0];				// 0..+1F
		EnvStep			<= 4'b1000;					// -8
	end
	default:;
	endcase
end

/*
	VxOut[ch] = ChannelValue * ADSRVol
	
	TODO : Computation of ADSR 
	
	TODO : Use KeyON and KeyOFF
	
*/
	wire [15:0] VxOut;


// --------------------------------------------------------------------------------------
//		Channel volume / Support Sweep (16 cycle)
// --------------------------------------------------------------------------------------
	wire [15:0] channelVolume; // L/R

// --------------------------------------------------------------------------------------
//		Stage Accumulate all voices    (768/16/32)
// --------------------------------------------------------------------------------------

// Because we scan per channel.

/*
	VxOut * channelVolume;

AccumulateL = ...;
AccumulateR = ...;

CdSide  = reg_CDAudioEnabled	? (cdInput  * cdVolume   ) : 16'd0; // 1 volume
ExtSide = reg_ExtEnabled		? (extInput * extLRVolume) : 16'd0; // Volume R + L

// --------------------------------------------------------------------------------------
//		Reverb Input (1536 / 768 / 16)
// --------------------------------------------------------------------------------------

wire EON; EONSelect SelectCh(.v(reg_eon), currVoice, .o(EON));

									,
									,
									,
									

ReverbInput = (reg_CDAudioReverbEnabled		? CdSide    : 0)
            + (VoiceReverbEnable 			? VoiceSide : 0)
            + (reg_ExtReverbEnabled   		? ExtSide   : 0);
            
// TODO Reverb Unit

//
ReverbOutputL;
ReverbOutputR;

// --------------------------------------------------------------------------------------
//		Mix
// --------------------------------------------------------------------------------------
Mix = Accumulate + CdSide + ExtSide + RevertOutput * VolumeReverb

OutputSPU = (reg_SPUMute ? 16'd0 : MasterVolume) * Mix;
*/
endmodule
