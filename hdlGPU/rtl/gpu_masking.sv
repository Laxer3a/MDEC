module gpu_masking(
	input	[3:0]	RegX0_4bit,
	input	[3:0]	RegSizeW_4bit,
	
	input	[5:0]	i_adrXSrc,
	input	[5:0]	i_lengthBlkSrcHM1_6bit,	// lengthBlockSrcHM1[5:0]
	
	output	[3:0]	o_rightPos,
	output	[15:0]	o_maskRead16
);

reg  [15:0] maskLeft,maskRight;
always @(*)
begin
	case (RegX0_4bit)
	4'h0: maskLeft = 16'b1111_1111_1111_1111; // Pixel order is ->, While bit are MSB <- LSB.
	4'h1: maskLeft = 16'b1111_1111_1111_1110;
	4'h2: maskLeft = 16'b1111_1111_1111_1100;
	4'h3: maskLeft = 16'b1111_1111_1111_1000;
	4'h4: maskLeft = 16'b1111_1111_1111_0000;
	4'h5: maskLeft = 16'b1111_1111_1110_0000;
	4'h6: maskLeft = 16'b1111_1111_1100_0000;
	4'h7: maskLeft = 16'b1111_1111_1000_0000;
	4'h8: maskLeft = 16'b1111_1111_0000_0000;
	4'h9: maskLeft = 16'b1111_1110_0000_0000;
	4'hA: maskLeft = 16'b1111_1100_0000_0000;
	4'hB: maskLeft = 16'b1111_1000_0000_0000;
	4'hC: maskLeft = 16'b1111_0000_0000_0000;
	4'hD: maskLeft = 16'b1110_0000_0000_0000;
	4'hE: maskLeft = 16'b1100_0000_0000_0000;
	default: maskLeft = 16'b1000_0000_0000_0000;
	endcase
    
	case (o_rightPos)
	// Special case : lastSegment is actually the PREVIOUS segment. Empty segment never occurs because of computation.
	// The END (EXCLUDED) pixel from the segment is the beginning of a new chunk that will be never loaded.
	// See computation of 'lengthBlockSrcHM1'
	4'h0: maskRight = 16'b1111_1111_1111_1111; // Pixel order is ->, While bit are MSB <- LSB.
	// Normal cases...
	4'h1: maskRight = 16'b0000_0000_0000_0001;
	4'h2: maskRight = 16'b0000_0000_0000_0011;
	4'h3: maskRight = 16'b0000_0000_0000_0111;
	4'h4: maskRight = 16'b0000_0000_0000_1111;
	4'h5: maskRight = 16'b0000_0000_0001_1111;
	4'h6: maskRight = 16'b0000_0000_0011_1111;
	4'h7: maskRight = 16'b0000_0000_0111_1111;
	4'h8: maskRight = 16'b0000_0000_1111_1111;
	4'h9: maskRight = 16'b0000_0001_1111_1111;
	4'hA: maskRight = 16'b0000_0011_1111_1111;
	4'hB: maskRight = 16'b0000_0111_1111_1111;
	4'hC: maskRight = 16'b0000_1111_1111_1111;
	4'hD: maskRight = 16'b0001_1111_1111_1111;
	4'hE: maskRight = 16'b0011_1111_1111_1111;
	default: maskRight = 16'b0111_1111_1111_1111;
	endcase
end


wire isFirstSegmentMask		= (i_adrXSrc == 6'd0);
wire isLastSegmentMask 		= (i_adrXSrc == i_lengthBlkSrcHM1_6bit);

wire [15:0] maskSegmentRead	= (isFirstSegmentMask ? maskLeft  : 16'hFFFF)
                            & (isLastSegmentMask  ? maskRight : 16'hFFFF);

// ------------------------------------------------------
assign o_rightPos			= RegX0_4bit + RegSizeW_4bit;
assign o_maskRead16			= maskSegmentRead;
// ------------------------------------------------------
endmodule
