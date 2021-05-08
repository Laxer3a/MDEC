/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module spu_AudioMixer(
	input					i_clk,
	input					i_rst,
	
	input					i_side22Khz,
	// Mixing this channel to the output
	input	signed [15:0]	i_ChannelValue,
	input					i_vxOutValid,

	input  		   [14:0]	i_AdsrVol,
	input					i_currV_EON,
	input	signed [14:0]	i_currV_VolumeL,
	input	signed [14:0]	i_currV_VolumeR,

	input					i_ctrlSendOut,	// When mixing the last sample -> Send out to the audio DAC.
	input					i_clearSum,
	
	
	// Register from outside
	input					i_reg_SPUNotMuted,
	input					i_reg_CDAudioEnabled,
	input					i_reg_CDAudioReverbEnabled,
	input	signed	[15:0]	i_reg_CDVolumeL,
	input	signed	[15:0]	i_reg_CDVolumeR,
	input	signed  [15:0]	i_reg_mainVolLeft,
	input	signed  [15:0]	i_reg_mainVolRight,
	input   signed  [15:0]  i_reg_reverbVolLeft,
	input   signed  [15:0]  i_reg_reverbVolRight,
	input					i_reg_ReverbEnable,

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
	input					i_CDRomInL_valid,
	input			[15:0]	i_CDRomInL,
	input					i_CDRomInR_valid,
	input			[15:0]	i_CDRomInR,
	
	output			[15:0]	o_storedCDRomInL,
	output			[15:0]	o_storedCDRomInR,


	// Final mix for reverb write back
	input   signed [15:0]	i_accReverb,
	// [TODO] Add signal here I guess ?
	output signed   [15:0]  o_lineIn,
	
	// To DAC, final samples.
	output signed	[15:0]	o_AOUTL,
	output signed	[15:0]	o_AOUTR,
	output					o_VALIDOUT,
	
	input					i_storePrevVxOut, // TODO : Should be internal, probably equivalent to i_vxOut
	output signed	[15:0]	o_prevVxOut,
	output signed   [15:0]	o_currVxOut
);

/*
// --- Volume Registers in Mixer ---
reg [15:0]	reg_volumeL			[23:0];	// Cn0 Voice Volume Left
reg [15:0]	reg_volumeR			[23:0];	// Cn2 Voice Volume Right

// Write to register from front-end
always @(posedge i_clk) begin
	if (i_writeLVolume) begin
		reg_volumeL[i_channelAdr] <= i_writeValue;
	end
	if (i_writeRVolume) begin
		reg_volumeR[i_channelAdr] <= i_writeValue;
	end
end

// Read registers from front-end
assign o_readValue = i_readLVolume ? reg_volumeL[i_channelAdr] : reg_volumeR[i_channelAdr];
// ----------------------------------
*/
/*
wire  EON = i_reg_eon[i_currVoice];
wire  signed [14:0] currV_VolumeL		= reg_volumeL	[i_currVoice][14:0];
wire  signed [14:0] currV_VolumeR		= reg_volumeR	[i_currVoice][14:0];
*/

wire signed [15:0] sAdsrVol = {1'b0, i_AdsrVol};
wire signed [30:0] tmpVxOut = i_ChannelValue * sAdsrVol;
wire signed [15:0] vxOut	 = tmpVxOut[30:15];	// 1.15 bit precision.

reg signed [15:0] prevChannelVxOut;
reg signed [15:0] PvxOut;
reg PValidSample;
always @(posedge i_clk) begin
	if (i_rst) begin
		PValidSample		<= 0;
		prevChannelVxOut	<= 16'd0;
		PvxOut				<= 16'd0;
	end else begin
		if (i_storePrevVxOut) begin
			prevChannelVxOut <= vxOut;
		end
		PvxOut			<= i_vxOutValid ? vxOut : 16'd0; // [TODO DEBUG LOGIC MUX -> REMOVE]
		PValidSample	<= i_vxOutValid;
	end
end
assign o_prevVxOut = prevChannelVxOut;

// --------------------------------------------------------------------------------------
//		Channel volume / Support Sweep (16 cycle)
// --------------------------------------------------------------------------------------

wire signed [30:0] applyLVol = i_currV_VolumeL * PvxOut;
wire signed [30:0] applyRVol = i_currV_VolumeR * PvxOut;

// --------------------------------------------------------------------------------------
//		Stage Accumulate all voices    (768/16/32)
// --------------------------------------------------------------------------------------
reg signed [20:0] sumL,sumR;
reg signed [20:0] sumReverb;
wire signed [15:0] reverbApply = i_side22Khz ? applyRVol[30:15] : applyLVol[30:15];
always @(posedge i_clk) begin
	if (PValidSample) begin
		sumL <= sumL + { {5{applyLVol[30]}},applyLVol[30:15]};
		sumR <= sumR + { {5{applyRVol[30]}},applyRVol[30:15]};
		if (i_currV_EON) begin
			sumReverb <= sumReverb + { {5{reverbApply[15]}}, reverbApply };
		end
	end else begin
		if (i_clearSum || i_rst) begin
			sumL		<= 21'd0;
			sumR		<= 21'd0;
			sumReverb	<= 21'd0;
		end
	end
end

// Because we scan per channel.
reg  signed [15:0] reg_CDRomInL,reg_CDRomInR;
// Select correct volume based on 22 Khz switch bit.
wire signed [15:0] volume			= i_side22Khz ? i_reg_reverbVolRight : i_reg_reverbVolLeft;
wire signed [31:0] valueReverb      = i_accReverb * volume; 
wire signed [15:0] valueReverbFinal = i_reg_ReverbEnable ? valueReverb[30:15] : 16'd0;
reg  signed [15:0] regValueReverbLeft,regValueReverbRight;

always @(posedge i_clk) begin
	if (i_rst) begin
		reg_CDRomInL 		<= 16'd0; 
		reg_CDRomInR		<= 16'd0; 
		regValueReverbLeft	<= 16'd0;
		regValueReverbRight	<= 16'd0;
	end else begin
		if (i_CDRomInL_valid) begin
			reg_CDRomInL <= i_CDRomInL; 
		end
		if (i_CDRomInR_valid) begin
			reg_CDRomInR <= i_CDRomInR;
		end

		if (i_ctrlSendOut) begin
			if (i_side22Khz) begin
				// Right Side
				regValueReverbRight <= valueReverbFinal;
			end else begin
				// Left Side
				regValueReverbLeft  <= valueReverbFinal;
			end
		end
	end
end

wire signed [31:0] tmpCDRomL = reg_CDRomInL * i_reg_CDVolumeL;
wire signed [31:0] tmpCDRomR = reg_CDRomInR * i_reg_CDVolumeR;
wire signed [15:0] CD_addL   = tmpCDRomL[30:15];
wire signed [15:0] CD_addR   = tmpCDRomR[30:15];

wire signed [15:0] CdSideL	= i_reg_CDAudioEnabled	? CD_addL : 16'd0;
wire signed [15:0] CdSideR	= i_reg_CDAudioEnabled	? CD_addR : 16'd0;
// wire signed [15:0] ExtSide = reg_ExtEnabled		? (extInput * extLRVolume) : 16'd0; // Volume R + L

// --------------------------------------------------------------------------------------
//		Reverb Input (1536 / 768 / 16)
// --------------------------------------------------------------------------------------
// Get CD Data post-volume for REVERB : Enabled ? If so, which side ?
wire signed [15:0] cdReverbInput = i_reg_CDAudioReverbEnabled ? 16'd0 : (i_side22Khz ? CdSideR : CdSideL);
// Sum CD Reverb and Voice Reverb.
wire signed [20:0] reverbFull	 = sumReverb + {{5{cdReverbInput[15]}},cdReverbInput};
// [Assign clamped value to Reverb INPUT]
clampSRange #(.INW(21),.OUTW(16)) Reverb_Clamp(.valueIn(reverbFull),.valueOut(o_lineIn));

// --------------------------------------------------------------------------------------
//		Mix
// --------------------------------------------------------------------------------------
// According to spec : impact only MAIN, not CD
wire signed [14:0] volL        = i_reg_SPUNotMuted ? i_reg_mainVolLeft [14:0] : 15'd0;
wire signed [14:0] volR        = i_reg_SPUNotMuted ? i_reg_mainVolRight[14:0] : 15'd0;
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

assign o_AOUTL		= outL;
assign o_AOUTR		= outR;
assign o_VALIDOUT	= i_ctrlSendOut;
assign o_storedCDRomInL	= reg_CDRomInL;
assign o_storedCDRomInR	= reg_CDRomInR;
assign o_currVxOut	= vxOut;

endmodule
