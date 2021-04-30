module spu_ADPCMnextAdr(
	 input          [16:0]	i_currV_adpcmPos
	,input	signed [15:0]	i_currV_sampleRate
	,input  signed [15:0]	i_prevChannelVxOut
	,input					i_currPMON
	
	,output			[16:0]	o_nextADPCMPos
	,output					o_nextNewBlock
	,output					o_nextNewLine
);

// --------------------------------------------------------------------------------------
//		Stage 0A : ADPCM Adress computation (common : once every 32 cycle)
// --------------------------------------------------------------------------------------
//--------------------------------------------------
//  INPUT
//--------------------------------------------------

wire signed [15:0]  VxPitch		= i_currV_sampleRate;
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
wire SgnS2U						= i_prevChannelVxOut[15] ^ 1'b1;
// Select Previous output modulation or standard pitch.
wire 				pitchSel	= i_currPMON   /* & (currVoice != 5'd0)  <--- Done at HW Setup */;
wire signed	[16:0]	pitchMul	= pitchSel 	? { SgnS2U,SgnS2U,i_prevChannelVxOut[14:0] }	// -0.999,+0.999 pitch
											: { 17'h8000 }; 							// 1.0 positive
// Compute new pitch
wire signed [32:0]  mulPitch	= pitchMul * VxPitch;
wire        [15:0]	tmpRes		= mulPitch[30:15];
// Clamp over 4000.
wire				 GT4000		= tmpRes[14] | tmpRes[15];
wire				nGT4000		= !GT4000;
wire		[13:0]	lowPart		= tmpRes[13:0] & {14{nGT4000}};

// PB : not well defined arch here... TODO : What in case of START. pure 0.

//--------------------------------------------------
//  OUTPUT
//--------------------------------------------------
wire  [16:0]	nextPitch	= { 2'b0, GT4000, lowPart };
assign 		o_nextADPCMPos	= i_currV_adpcmPos + nextPitch;
assign		o_nextNewBlock	= o_nextADPCMPos[16:14] > 3'd6;
assign		o_nextNewLine   = o_nextADPCMPos[16:14] != i_currV_adpcmPos[16:14];	// Change of line.

endmodule
