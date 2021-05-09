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
	
	input	signed	[20:0]	i_sumLeft,
	input	signed	[20:0]	i_sumRight,
	input	signed	[20:0]	i_sumReverb,
	input					i_ctrlSendOut,
	
	input					i_side22Khz,
	
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

	input   signed [15:0]	i_accReverb,
	output signed   [15:0]  o_lineIn,
	
	// From CD Rom Drive Audio
	input					i_CDRomInL_valid,
	input			[15:0]	i_CDRomInL,
	input					i_CDRomInR_valid,
	input			[15:0]	i_CDRomInR,
	
	output			[15:0]	o_storedCDRomInL,
	output			[15:0]	o_storedCDRomInR,

	// To DAC, final samples.
	output signed	[15:0]	o_AOUTL,
	output signed	[15:0]	o_AOUTR,
	output					o_VALIDOUT
);

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
wire signed [20:0] reverbFull	 = i_sumReverb + {{5{cdReverbInput[15]}},cdReverbInput};
// [Assign clamped value to Reverb INPUT]
clampSRange #(.INW(21),.OUTW(16)) Reverb_Clamp(.valueIn(reverbFull),.valueOut(o_lineIn));

// --------------------------------------------------------------------------------------
//		Mix
// --------------------------------------------------------------------------------------
// According to spec : impact only MAIN, not CD
wire signed [14:0] volL        = i_reg_SPUNotMuted ? i_reg_mainVolLeft [14:0] : 15'd0;
wire signed [14:0] volR        = i_reg_SPUNotMuted ? i_reg_mainVolRight[14:0] : 15'd0;
wire signed [35:0] sumPostVolL = i_sumLeft  * volL;
wire signed [35:0] sumPostVolR = i_sumRight * volR;

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

endmodule
