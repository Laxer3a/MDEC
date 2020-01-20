/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
 **************************************************************************************************************************************/
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
module Interpolator(
	input					i_clk,
	// 5 Cycle latency between input and output.
	input					i_go,
	input			[7:0]	i_interpolator,
	input	signed [15:0]	i_sampleOldest,
	input	signed [15:0]	i_sampleOlder,
	input	signed [15:0]	i_sampleOld,
	input	signed [15:0]	i_sampleNew,
	
	output	signed [15:0]	o_sample_c5,
	output					o_validSample
);

reg signed [15:0] rOLDEST;
reg signed [15:0] rOLDER;
reg signed [15:0] rOLD;
reg signed [15:0] rNEW;

reg signed [17:0] acc;
reg         [2:0] regIdx;
always @(posedge i_clk) begin
	if (i_go) begin
		regIdx	= 3'd1;	// Start at 1, stop at 4.
		acc		= 18'd0;
		rNEW	= i_sampleNew;
		rOLD	= i_sampleOld;
		rOLDER	= i_sampleOlder;
		rOLDEST	= i_sampleOldest;
	end else begin
		// Because of latency to InterpROM, when regIdx = 1, data is not there yet...
		// BEFORE regIdx INCREMENT !
		if (regIdx > 1) begin
			acc = acc + { cumulativeSample[15], cumulativeSample[15], cumulativeSample};
		end
	
		// Stuck at 6
		if (regIdx < 7) begin
			regIdx = regIdx + 1;
		end
	end
	Pidx = idx;
end

wire [7:0] interp = i_interpolator;
wire [1:0] idx    = regIdx[1:0];
reg  [1:0] Pidx; // Needed to handle latency of InterpROM.
wire [8:0] romAdr = {idx[0], idx[1] ? ~interp : interp };
wire signed[15:0] ratio;

// 1 Clock Latency (use BRAM to store 8KBit ROM of 512x16 bits)
InterpROM instanceInterpROM(
	.clk		( i_clk),
	.adr		(romAdr),
	.dataOut	( ratio)
);

/*
  out = 0
                      IDX[0]
                      |
                      | 
                      |+---- IDX[1]
                      ||
  out = out + ((gauss[100h+i] * old)    SAR 15)		01
  out = out + ((gauss[0FFh-i] * oldest) SAR 15)		10
  out = out + ((gauss[1FFh-i] * older)  SAR 15)		11
  out = out + ((gauss[000h+i] * new)    SAR 15)		00
*/
reg signed[15:0] src;
always @(*) begin
	case (Pidx)
	2'b00 : src = rNEW;		// Fourth
	2'b01 : src = rOLD;		// First
	2'b10 : src = rOLDEST;	// Second
	2'b11 : src = rOLDER;	// Third
	endcase
end
wire signed[31:0] res				= ratio * src;
wire signed[15:0] cumulativeSample	= res[30:15]; // Division by 2^15 --> Imperfect.
// NO CLAMPING... clampSRange #(.INW(32),.OUTW(16)) clampAudioSample(.valueIn(res),.valueOut(cumulativeSample));

assign o_validSample	= (regIdx == 3'd6);
assign o_sample_c5		= acc[15:0];
endmodule
