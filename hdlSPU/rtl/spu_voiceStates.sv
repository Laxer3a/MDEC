/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "spu_def.sv"

module spu_voiceStates (
	input  i_isDMAXferRD,
	input  i_isVoice1,
	input  i_isVoice3,
	input  i_nextNewBlock,
	input  i_nextNewLine,
	input  i_reverbInactive,
	input   [4:0] i_voiceCounter,
	input  [15:0] i_dataInRAM,
	input   [4:0] i_currVoice,

	output o_loadPrev,
	output o_updatePrev,
	output o_check_Kevent,
	output o_storePrevVxOut,
	output o_clearSum,
	output o_setEndX,
	output o_setAsStart,
	output o_zeroIndex,
	output [2:0] o_SPUMemWRSel,
	output o_updateVoiceADPCMAdr,
	output o_updateVoiceADPCMPos,
	output o_updateVoiceADPCMPrev,
	output [1:0] o_adpcmSubSample,
	output o_isNotEndADPCMBlock,
	output o_isRepeatADPCMFlag,
	output o_readSPU,
	output o_kickFifoRead
);

reg [2:0] SPUMemWRSel;

reg loadPrev,updatePrev,check_Kevent,storePrevVxOut,clearSum,setEndX,setAsStart,zeroIndex
   ,updateVoiceADPCMAdr,updateVoiceADPCMPos,updateVoiceADPCMPrev,isNotEndADPCMBlock
   ,isRepeatADPCMFlag,readSPU,kickFifoRead;				
reg [1:0] adpcmSubSample;

always @(*)
begin
	loadPrev			= 0;
	updatePrev			= 0;
	check_Kevent		= 0;
	storePrevVxOut		= 0;
	clearSum			= 0;
	setEndX				= 0;
	setAsStart			= 0;
	zeroIndex			= 0;
	SPUMemWRSel			= NO_SPU_READ;	// Default : NO READ/WRITE SIGNALS
	updateVoiceADPCMAdr	= 0;
	updateVoiceADPCMPos = 0;
	updateVoiceADPCMPrev= 0;
	adpcmSubSample		= 0;
	isNotEndADPCMBlock	= 0;
	isRepeatADPCMFlag	= 0;
	readSPU				= 0;

	// Keep data in the reverb loop by default...
	kickFifoRead		= 0;
	
	if (i_reverbInactive) begin // [Channel 0..23 Timing are VOICES in original SPU]
		case (i_voiceCounter)
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
			clearSum			= (i_currVoice == 5'd0);
		end
		
		5'd13:
		begin
			kickFifoRead		= 1;
		end
		//
		// The interpolator takes 5 CYCLE to output, prefer to maintain channel active for that amount of cycle....
		//
		5'd14:
		begin
			// SPUMemWRSel			= FIFO_WRITE; // Allow only ONCE XFer per voice...
			SPUMemWRSel = i_isDMAXferRD ? FIFO_RD : FIFO_WRITE; // Allow only ONCE XFer per voice...
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
			readSPU			= i_isDMAXferRD;
			
			storePrevVxOut	= 1;
			// -> If NEXT sample is OUTSIDE AND CONTINUE, SAVE sample2/sample3 (previous needed for decoding)
			//       NEXT sample is OUTSIDE AND JUMP, set 0/0.
			// 
			if (i_isVoice1 | i_isVoice3) begin
				SPUMemWRSel			= VOICE_WR;
			end // else use FIFO to purge...

			// --------------------------------
			// ADPCM Line/Block Management
			// --------------------------------
			updateVoiceADPCMAdr = i_nextNewBlock;
			updateVoiceADPCMPos = 1;
			updateVoiceADPCMPrev= i_nextNewLine;	// Store PREV ADPCM when we move to the next 16 bit only.(different line in same ADPCM block or new ADPCM block)
		end
		default:
		begin
			// Do nothing.
		end
		endcase
	end
end

assign o_loadPrev				= loadPrev;
assign o_updatePrev				= updatePrev;
assign o_check_Kevent			= check_Kevent;
assign o_storePrevVxOut			= storePrevVxOut;
assign o_clearSum				= clearSum;
assign o_setEndX				= setEndX;
assign o_setAsStart				= setAsStart;
assign o_zeroIndex				= zeroIndex;
assign o_SPUMemWRSel			= SPUMemWRSel;
assign o_updateVoiceADPCMAdr	= updateVoiceADPCMAdr;
assign o_updateVoiceADPCMPos	= updateVoiceADPCMPos;
assign o_updateVoiceADPCMPrev	= updateVoiceADPCMPrev;
assign o_adpcmSubSample			= adpcmSubSample;
assign o_isNotEndADPCMBlock		= isNotEndADPCMBlock;
assign o_isRepeatADPCMFlag		= isRepeatADPCMFlag;
assign o_readSPU				= readSPU;
assign o_kickFifoRead			= kickFifoRead;

endmodule
