/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module spu_counter(
	input			i_clk,
	input			n_rst,
	input			i_onClock,			// Enabled to work
	input			i_safeStopState,	// Tells counter that we can freeze the state machine to deflate the disable counter.
	
	output			o_ctrl44Khz,
	output			o_side22Khz,
	output	[4:0] 	o_voiceCounter,
	output	[4:0]	o_currVoice
);

// --- Exported ---
reg  [4:0] voiceCounter;

// --- Internal ---
reg  [5:0] currVoice6Bit;
wire isLastCycle = (voiceCounter == 5'd23);
// reg  [9:0] counter768;
// wire [9:0] nextCounter768 = counter768 + 10'd1;

// Number of cycles added while we do a 768 cycles round in unstoppable states (unsafe).
// Use 1023 cycles max for 768 cycles. (Allows max ~78 Mhz clock for a 33.8 Mhz Clock played)
reg  [9:0]	stopCounter;

wire exitSafeState = i_safeStopState && (stopCounter == 0) && i_onClock;

always @(posedge i_clk)
begin
	if (n_rst == 0)
	begin
		voiceCounter		<= 5'd0;
		currVoice6Bit		<= 6'd0;
		stopCounter			<= 10'd0;
	end else begin
		// Not safe state or first safe stop state.
		if (i_safeStopState && (!exitSafeState)) begin
			// Decrement only on valid clock while 
			stopCounter <= stopCounter + ((!i_onClock) ? 10'd0 : 10'h3FF);
		end else begin
			stopCounter	<= stopCounter + {9'd0, !i_onClock};
			if (isLastCycle) begin
				voiceCounter 	<= 5'd0;
				currVoice6Bit	<= currVoice6Bit + 6'd1;
			end else begin
				voiceCounter 	<= voiceCounter + 5'd1; 
			end
		end
	end
end

wire [4:0] currVoice	= currVoice6Bit[4:0];
assign o_ctrl44Khz		= (currVoice == 5'd31) && isLastCycle;
assign o_side22Khz		= currVoice6Bit[5]; 						// Left / Right side for Reverb.
assign o_currVoice		= currVoice;
assign o_voiceCounter	= voiceCounter;

endmodule
