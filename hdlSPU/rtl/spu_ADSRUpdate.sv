/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "spu_def.sv"

module spu_ADSRUpdate (
	input					i_validSampleStage2,

	input					i_reg_SPUEnable,
	input					i_curr_KON,
	input	[14:0]			i_curr_AdsrVOL,
	input	[15:0]			i_curr_AdsrLo,
	input	[15:0]			i_curr_AdsrHi,
	input	[1:0]			i_curr_AdsrState,
	input	[22:0]			i_curr_AdsrCycleCount,
	
	output					o_updateADSRVolReg,
	output					o_updateADSRState,
	output					o_clearKON,
	output			[1:0]	o_nextAdsrState,
	output	signed [14:0]	o_nextAdsrVol,
	output 		   [22:0]	o_nextAdsrCycle
);

// --------------------------------------------------------------------------------------
//		Stage 3A : Compute ADSR        	(common : once every 32 cycle)
// --------------------------------------------------------------------------------------
wire  [14:0] AdsrVol			= i_reg_SPUEnable ? i_curr_AdsrVOL : 15'd0;
// wire  [15:0] curr_AdsrLo		= reg_adsrLo	[currVoice];
// wire  [15:0] curr_AdsrHi		= reg_adsrHi	[currVoice];
// wire   [1:0] curr_AdsrState	= reg_adsrState	[currVoice];
// wire  [22:0] AdsrCycleCount		= reg_adsrCycleCount[currVoice];

reg 				EnvExponential;
reg 				EnvDirection;
reg signed [4:0]	EnvShift;
reg signed [3:0]	EnvStep;
reg [1:0]           computedNextAdsrState;
reg                 cmpLevel;

wire [4:0]  	susLvl = { 1'b0, i_curr_AdsrLo[3:0] } + { 5'd1 };
wire [15:0]	EnvSusLevel= { susLvl, 11'd0 };

wire updateADSRState;
wire [1:0] tstState = updateADSRState ? computedNextAdsrState : i_curr_AdsrState;
always @(*) begin
	case (i_curr_AdsrState)
	// ---- Activated only from KON
	ADSR_ATTACK : computedNextAdsrState = i_curr_KON ? ADSR_ATTACK : ADSR_DECAY; // A State -> D State if KON cleared, else stay on ATTACK.
	ADSR_DECAY  : computedNextAdsrState = ADSR_SUSTAIN;
	ADSR_SUSTAIN: computedNextAdsrState = ADSR_SUSTAIN;
	// ---- Activated only from KOFF
	ADSR_RELEASE: computedNextAdsrState = ADSR_RELEASE;
	endcase
	
	case (i_curr_AdsrState)
	ADSR_ATTACK : cmpLevel = 1;
	ADSR_DECAY  : cmpLevel = 1;
	ADSR_SUSTAIN: cmpLevel = 0;
	ADSR_RELEASE: cmpLevel = 0;
	endcase
	
	case (tstState)
	ADSR_ATTACK: // A State
	begin
		EnvExponential	= i_curr_AdsrLo[15];
		EnvDirection	= 0;								// INCR
		EnvShift		= i_curr_AdsrLo[14:10];				// 0..+1F
		EnvStep			= { 2'b01, ~i_curr_AdsrLo[9:8] };	// +7..+4
	end
	ADSR_DECAY: // D State
	begin
		EnvExponential	= 1'b1;								// Exponential
		EnvDirection	= 1;								// DECR
		EnvShift		= { 1'b0, i_curr_AdsrLo[7:4] };		// 0..+0F
		EnvStep			= 4'b1000;							// -8
	end
	ADSR_SUSTAIN: // S State
	begin
		EnvExponential	= i_curr_AdsrHi[15];
		EnvDirection	= i_curr_AdsrHi[14];				// INCR/DECR
		EnvShift		= i_curr_AdsrHi[12:8];				// 0..+1F
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
		EnvStep			= { i_curr_AdsrHi[14] , !i_curr_AdsrHi[14] , i_curr_AdsrHi[14] ? i_curr_AdsrHi[7:6] : ~i_curr_AdsrHi[7:6] };
	end
	ADSR_RELEASE: // R State	
	begin
		EnvExponential	= i_curr_AdsrHi[5];
		EnvDirection	= 1;						// DECR
		EnvShift		= i_curr_AdsrHi[4:0];		// 0..+1F
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

wire [22:0] decAdsrCycle    = i_curr_AdsrCycleCount + { 23{1'b1} } /* Same as AdsrCycleCount - 1 */;
wire		reachZero		= (i_curr_AdsrCycleCount == CHANGE_ADSR_AT); // Go to next state when reach 1 or 0 ??? (Take care of KON event setting current voice to 1 or 0 cycle)
wire		tooBigLvl		= (      AdsrVol ==    15'h7FFF) && (i_curr_AdsrState == ADSR_ATTACK);
wire        tooLowLvl		= ({1'b0,AdsrVol} < EnvSusLevel) && (i_curr_AdsrState == ADSR_DECAY );
wire [22:0] nextAdsrCycle	= reachZero ? cycleCountStart : decAdsrCycle;

// TODO : On Sustain, should stop adding adsrStep when reachZero
wire [14:0] nextAdsrVol;
wire [16:0] tmpVolStep		= {2'b0, AdsrVol} + {adsrStep[14],adsrStep[14],adsrStep};
clampSPositive #(.INW(17),.OUTW(15)) ClampADSRVolume(.valueIn(tmpVolStep),.valueOut(nextAdsrVol));

assign o_nextAdsrState		= computedNextAdsrState;
assign o_nextAdsrVol		= nextAdsrVol;
assign o_nextAdsrCycle		= nextAdsrCycle;
assign o_updateADSRVolReg	= i_validSampleStage2 & reachZero;
assign updateADSRState      = o_updateADSRVolReg & ((cmpLevel & (tooBigLvl | tooLowLvl)) | (!cmpLevel));
assign o_updateADSRState	= updateADSRState;
assign o_clearKON			= o_updateADSRVolReg & i_curr_KON;

endmodule
