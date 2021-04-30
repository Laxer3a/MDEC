module spu_counter(
	input			i_clk,
	input			n_rst,
	input			i_onClock,	// Future stuff
	
	output			o_ctrl44Khz,
	output			o_side22Khz,
	output	[4:0] 	o_voiceCounter,
	output	[4:0]	o_currVoice
);

// TODO : 1. i_onClock allows to cumulate offtime (when = 0)
//        2. The counter is spend when transitionning (between reverb and voices ? end of all ?
//			 At a state where no damage/transaction can be done/happens.

// --- Exported ---
reg  [4:0] voiceCounter;

// --- Internal ---
reg  [5:0] currVoice6Bit;
wire isLastCycle = (voiceCounter == 5'd23);
// reg  [9:0] counter768;
// wire [9:0] nextCounter768 = counter768 + 10'd1;
always @(posedge i_clk)
begin
	if (n_rst == 0)
	begin
		voiceCounter		<= 5'd0;
		currVoice6Bit		<= 6'd0;
	end else begin
		if (isLastCycle) begin
			voiceCounter 	<= 5'd0;
			currVoice6Bit	<= currVoice6Bit + 6'd1;
		end else begin
			voiceCounter 	<= voiceCounter + 5'd1; 
		end
	end
end

wire [4:0] currVoice	= currVoice6Bit[4:0];
assign o_ctrl44Khz		= (currVoice == 5'd31) && isLastCycle;
assign o_side22Khz		= currVoice6Bit[5]; 						// Left / Right side for Reverb.
assign o_currVoice		= currVoice;
assign o_voiceCounter	= voiceCounter;

endmodule
