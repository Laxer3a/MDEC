/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
 **************************************************************************************************************************************/
/*
XA-ADPCM Header Bytes

  0-3   Shift  (0..12) (0=Loudest) (13..15=Reserved/Same as 9)   OK
  4-5   Filter (0..3) (only four filters, unlike SPU-ADPCM which has five)
   or
  4-6   Filter (0..4) SPU-ADPCM
  6-7   Unused (should be 0)
---------------------------  
    auto shift = buffer[0] & 0x0f;	// OK
    if (shift > 9) shift = 9;
	
	// 
    auto filter = (buffer[0] & 0x70) >> 4;  // 0x40 for xa adpcm

    assert(filter <= 4);
    if (filter > 4) filter = 4;  // TODO: Not sure, check behaviour on real HW
  
*/

module ADPCMDecoder(
	input			[3:0]	i_Shift,
	input			[2:0]	i_Filter,
	
	input 			[15:0]	inputRAW,
	input signed	[ 1:0]	samplePosition,

	input signed	[15:0]	i_PrevSample0,
	input signed    [15:0]  i_PrevSample1,
	output signed   [15:0]	o_sample
);

/*
Sample Block
[ Header 16 bit  ]
[ A 8 B ][ C 8 D ]	4
[ A 8 B ][ C 8 D ]	4
[ A 8 B ][ C 8 D ]	4
[ A 8 B ][ C 8 D ]	4
[ A 8 B ][ C 8 D ]	4
[ A 8 B ][ C 8 D ]	4
[ A 8 B ][ C 8 D ]	4	= 28 sample per block.
*/

// Shift Between 0..9
wire [3:0] shift  = (i_Shift  < 4'd13) ? i_Shift  : 4'd9;
wire [2:0] filter = (i_Filter < 3'd5 ) ? i_Filter : 3'd4;
reg signed [7:0] filterPos;
reg signed [7:0] filterNeg;

always @(*) begin
	case (filter)
	default	: begin filterPos = 8'd0;   filterNeg =   8'd0; end
	3'd0	: begin filterPos = 8'd0;   filterNeg =   8'd0; end
	3'd1 	: begin filterPos = 8'd60;  filterNeg =   8'd0; end
	3'd2 	: begin filterPos = 8'd115; filterNeg = -8'd52; end
	3'd3 	: begin filterPos = 8'd98;  filterNeg = -8'd55; end
	3'd4 	: begin filterPos = 8'd122; filterNeg = -8'd60; end
	endcase
end

reg [3:0] nibble;
always @(*) begin
	case (samplePosition)
	2'd0	: nibble = inputRAW[ 3: 0];
	2'd1 	: nibble = inputRAW[ 7: 4];
	2'd2 	: nibble = inputRAW[11: 8];
	2'd3 	: nibble = inputRAW[15:12];
	endcase
end

// 12 Shift nibble >>
//  2 stage shifter. (smaller FIRST, circuit smaller and faster)
reg [6:0] firstStageNibble; // 3:0 -> 6:0
wire sgn = nibble[3];

always @(*) begin
	case (shift[1:0])
	2'd3	: firstStageNibble = { {3{sgn}}  , nibble        };
	2'd2 	: firstStageNibble = { {2{sgn}}  , nibble , 1'b0 };
	2'd1 	: firstStageNibble = { sgn       , nibble , 2'd0 };
	2'd0 	: firstStageNibble = { nibble    ,          3'd0 };
	endcase
end

reg signed [15:0] baseSample;
always @(*) begin
	case (shift[3:2])	// 0/4/8/12
	// From 0..11 Work fine
	2'd0 	: baseSample = {            firstStageNibble, 9'd0 };
	2'd1 	: baseSample = { { 4{sgn}}, firstStageNibble, 5'd0 };
	2'd2 	: baseSample = { { 8{sgn}}, firstStageNibble, 1'd0 };
	2'd3	: baseSample = { {12{sgn}},                 nibble };
	endcase
end

// (prevSample[0] * filterPos + prevSample[1] * filterNeg + 32) / 64
wire signed [23:0] p0 = i_PrevSample0 * filterPos;
wire signed [23:0] p1 = i_PrevSample1 * filterNeg;
wire signed [23:0] t  = p0 + p1 + 24'b0000_0000_0000_0000_0010_0000;	// +64, we don't worry about overflow to 25 bit because can't happen (filterPos/filterNeg)

wire signed [17:0] div64;
SDivTrunc #(.INW(24),.OUTW(18)) mySignedDivisionBy64(.valueIn(t),.valueOut(div64));

// Addition in 19 bit to handle overflow.
wire signed [18:0] addBase     = {div64[17],div64} + {{3{baseSample[15]}},baseSample};

// Output clamped sample.
clampSRange #(.INW(19),.OUTW(16)) myClampSRange(.valueIn(addBase),.valueOut(o_sample));

endmodule
