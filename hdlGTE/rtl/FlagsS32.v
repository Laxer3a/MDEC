module FlagsS32(
	input [44:0] v,
	output       isOverflow,
	output       isUnderflow
);
	wire hasZeros     = !(&v[43:31]);
	wire hasOne       = |v[43:31];
	assign isOverflow = (!v[44]) && hasOne  ; // Positive number but too big.
	assign isUnderflow=   v[44]  && hasZeros; // Negative number but too big.
endmodule

module FlagClipOTZ(
	input i_overflowS32,
	input i_underflowS32,
	input [20:0] v,
	
	output isUnderOrOverflow,
	output [15:0] clampOut,			// Unsigned 0..FFFF
	
	output isUnderOrOverflowIR0,
	output [15:0] clampOutIR0		// Unsigned 0..1000
);
	wire hasOne      = |v[19:16];		// [31:
	reg isOver;
	reg isUnder;
	
//	wire hasOneIR0   = hasOne | (|v[15:12]);		// [31:
//	wire isNot1000   = (v != 21'h1000); 
	
//	reg isOver_IR0;
	
	always @(*) begin
		if (i_overflowS32) begin
			isOver	   = 1'b1;
//			isOver_IR0 = 1'b1;
			isUnder    = 1'b0;
		end else begin
			if (i_underflowS32) begin
				isOver	   = 1'b0;
//				isOver_IR0 = 1'b0;
				isUnder    = 1'b1;
			end else begin
				isUnder    = v[20]; 								// Negative number.
				isOver     = (!v[20]) & hasOne;						// Positive number but too big.
//				isOver_IR0 = ((!v[20]) & hasOneIR0) & isNot1000;	// Range 0xFFFF~0x0FFF
			end
		end
	end
	
	wire [15:0] andS = {16{(!isUnder) /* & isNot1000*/}};
	
	assign isUnderOrOverflow    = isOver     | isUnder;
//	assign isUnderOrOverflowIR0 = isOver_IR0 | isUnder;
	assign clampOut             = (v[15:0] & andS) | {16{isOver}};
	
	//
	reg [15:0] outIR0;
	reg        outUnderOver;
	wire isGEQ4096 = (v > 21'd4096) && (!v[20]); // Verilog is stupid, and does not compare using signed operator even using signed type... Sigh...
	always @(*) begin
		if (i_overflowS32 || isGEQ4096) begin
			outUnderOver = 1;
			outIR0 = 16'd4096;
		end else begin
			if (v[20]) begin
				outUnderOver = 1;
				outIR0 = 16'd0;
			end else begin
				outUnderOver = 0;
				outIR0 = { 3'd0, v[12:0] };
			end
		end
	end
	assign isUnderOrOverflowIR0 = outUnderOver;
	assign clampOutIR0          = outIR0; // { 3'd0, v[12] & (!isNot1000), (v[11:0] & andS[11:0]) | {12{isOver_IR0}}};
endmodule

module FlagClipXY(
	input [16:0] v,
	input        i_overflowS32 ,
	input        i_underflowS32,
	
	output        isUnderOrOverflow,
	output [15:0] clampOut			// -400..+3FF
);
	wire hasOne      = |v[15:10];
	wire hasZero     = !(&v[15:10]);
	reg  isOver;
	reg  isOver_IR0;
	reg  isUnder;

	always @(*) begin
		if (i_overflowS32) begin
			isOver     = 1'b1;
			isUnder    = 1'b0;
		end else begin
			if (i_underflowS32) begin
				isOver     = 1'b0;
				isUnder    = 1'b1;
			end else begin
				isUnder    =  v[16]   & hasZero; 					// Negative number but too big.
				isOver     = (!v[16]) & hasOne;						// Positive number but too big.
			end
		end
	end

	assign isUnderOrOverflow    = isOver     | isUnder;
	wire [9:0] andS             = {10{!isUnder}};
	assign clampOut             = { {6{v[16]}}, (v[9:0] & andS) | {10{isOver}} };
	
endmodule

module FlagClipIRnColor(
	input [44:0]  i_v44,
	input         i_sf,
	input         i_LM,					// isIRCheckUseLM in tool.
	input         i_useFixedSFLM,
	
	output        o_OU_IRn,
	output        o_OU_Color,
	
	output [15:0] clampOut,
	output [ 7:0] clampOutCol
);
	wire [31:0] postSF_v = i_sf ? i_v44[43:12] : i_v44[31: 0];

	// [44: 0] -> (31: 0) -> [15: 0]
	// [44:12] -> (43:12) -> [27:12] 
	wire hasZerosSF   = !(&postSF_v[30:15]);
	wire hasOneSF     = |postSF_v[30:15];
	
	// === Standard Case ===
	wire isUnder_v    = postSF_v[31]&(hasZerosSF);
	wire isUnder_vPos = postSF_v[31]; // Negative number ?
	// Detect +7FFF overflow. 
	wire isOver_v     = (!postSF_v[31])&(hasOneSF);

	// === Always Case ===
	wire hasZerosA    = !(&i_v44[42:27]);
	wire hasOneA      = |i_v44[42:27];
	// Detect v>>12 -8000 overflow. 
	wire isUnderA_v   = i_v44[43]&(hasZerosA);
	// Detect v>>12 +7FFF overflow. 
	wire isOverA_v    = (!i_v44[43])&(hasOneA);

	/*
		// 1.
		setMac<3>(value);
		-------------------------
		if (sf) { value >>= 12; }
		mac[i] = value;             <==== SAME, DONE OUTSIDE
		+
		ir [i] = clip(value (64 bit, not post 32 bit write), 0x7fff, lm ? 0 : -0x8000, saturatedBits);   // CLIP AND FLAG SAME.
	
		// 2. RTP calculates IR3 saturation flag as if lm bit was always false AND SF flag = 1.
		setMac<3>(value);
		-------------------------
		if (sf) { value >>= 12; }
		mac[i] = value;             <==== SAME, DONE OUTSIDE
		+
		VALUE OUT = ir[3] = clip(mac[i] <=== USE SF, 0x7fff, lm ? 0 : -0x8000, 0 ); // NO FLAG, VALUE OUT
		FLAGS OUT = clip(result.z >> 12 <=== USE FIXED SF, 0x7fff, -0x8000, Flag::IR3_SATURATED);
	 */
	 
	// Fed up to think too much and waste brain power when I am tired...
	// Went to full retard, hope optimizer will clean that shit...
	wire [15:0] clampSR16;
	wire [14:0] clampSP15;
	wire  [7:0] clampCol;
	clampSRange    #(.INW(32),.OUTW(16)) myClampSRange   (.valueIn(postSF_v),.valueOut(clampSR16));
	clampSPositive #(.INW(32),.OUTW(15)) myClampSPositive(.valueIn(postSF_v),.valueOut(clampSP15));
	wire  isNegClamp;
	wire  isPosClamp;
	clampSPositiveFlg #(.INW(28),.OUTW( 8)) myClampSPosCol(.valueIn(postSF_v[31:4]),.valueOut(clampCol),.negClamp(isNegClamp),.posClamp(isPosClamp));

	
	wire [15:0] clamp16 = i_LM ? { 1'b0, clampSP15 } : clampSR16;
	assign clampOut    = clamp16;
	assign clampOutCol = clampCol; // 0..255 clamping

	// Flag use different path...
	assign o_OU_IRn   = i_useFixedSFLM ? (isUnderA_v | isOverA_v) : ((i_LM ? isUnder_vPos : isUnder_v) | isOver_v);

	assign o_OU_Color = isNegClamp | isPosClamp;
	
endmodule
