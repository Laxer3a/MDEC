/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module spu_AudioAccumulator(
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
	
	input					i_storePrevVxOut, // TODO : Should be internal, probably equivalent to i_vxOut
	output signed	[15:0]	o_prevVxOut,
	output signed   [15:0]	o_currVxOut,
	output signed	[20:0]	o_sumLeft,
	output signed	[20:0]	o_sumRight,
	output signed	[20:0]	o_sumReverb
);

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

assign o_prevVxOut	= prevChannelVxOut;
assign o_currVxOut	= vxOut;
assign o_sumLeft	= sumL;
assign o_sumRight	= sumR;
assign o_sumReverb	= sumReverb;
endmodule
