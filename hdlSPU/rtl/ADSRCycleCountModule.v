module ADSRCycleCountModule
(
	input   		[4:0]	i_EnvShift,
	input	signed 	[3:0]	i_EnvStep,
	input          [14:0]   i_adsrLevel,		// 0..+7FFF
	input					i_shift2ExpIncr,
	input					i_step2ExpDecr,
	output [22:0]			o_CycleCount,
	output 	signed  [14:0]	o_AdsrStep
);
	
	// --------------------------------------------------
	//	[Step Computation]
	// --------------------------------------------------
	/*
		Step 1:
		AdsrStep = i_EnvStep << [11-ShiftValue](Clamp shift)
		
		11-0  -> 11
		11-31 -> 0
		
		Step 2:
		IF i_step2ExpDecr THEN
			AdsrStep = (AdsrStep*i_adsrLevel)/8000h
			-> 
	 */
	 reg [3:0] sh;
	always @(*) begin
		if (i_EnvShift[4] == 1'b0) begin
			case (i_EnvShift[3:0])
			4'h00: sh = 4'hB;
			4'h01: sh = 4'hA;
			4'h02: sh = 4'h9;
			4'h03: sh = 4'h8;
			4'h04: sh = 4'h7;
			4'h05: sh = 4'h6;
			4'h06: sh = 4'h5;
			4'h07: sh = 4'h4;
			4'h08: sh = 4'h3;
			4'h09: sh = 4'h2;
			4'h0A: sh = 4'h1;
			4'h0B: sh = 4'h0;
			4'h0C: sh = 4'h0;
			4'h0D: sh = 4'h0;
			4'h0E: sh = 4'h0;
			4'h0F: sh = 4'h0;
			endcase
		end else begin
			sh = 4'h0;
		end
	end
	
	// Shift 1
	wire [4:0] st1 = sh[0] ? {i_EnvStep, 1'b0} : {i_EnvStep[3]     ,i_EnvStep};
	// Shift 2
	wire [6:0] st2 = sh[1] ? {st1      , 2'b0} : {{2{i_EnvStep[3]}},      st1};
	// Shift 4
	wire [10:0] st3= sh[2] ? {st2      , 4'b0} : {{4{i_EnvStep[3]}},      st2};
	// Shift 8
	wire [18:0] st4= sh[3] ? {st3      , 8'b0} : {{8{i_EnvStep[3]}},      st3};
	// This will optimize unecessary HW logic in shifter...
	wire signed [14:0] adsrStepBeforeOptDiv = st4[14:0];
	
	// Signe[14:0]x[14:0]/8000 -> >> 15 bit.
	wire signed [15:0] sAdsrLevel = { 1'b0, i_adsrLevel };
	wire signed [29:0] stepE = adsrStepBeforeOptDiv * sAdsrLevel;
	
	// Not a real division, but a SHIFT signed for negative value.
	// wire signed [14:0] resDiv;
	// SDivTrunc #(.INW(30),.OUTW(15)) mySignedDivisionBy32768(.valueIn(stepE),.valueOut(resDiv));

	assign o_AdsrStep = i_step2ExpDecr ? stepE[29:15] : adsrStepBeforeOptDiv;
	
	// --------------------------------------------------
	//	[Env Cycle Count]
	// --------------------------------------------------
	
	// TODO : out = 1 << (i_EnvShift-11) , more optimized VERILOG ?
	reg [20:0] newCycleCount;
	always @(*) begin
	case (i_EnvShift)
	5'h00: newCycleCount = 21'h000001;
	5'h01: newCycleCount = 21'h000001;
	5'h02: newCycleCount = 21'h000001;
	5'h03: newCycleCount = 21'h000001;
	5'h04: newCycleCount = 21'h000001;
	5'h05: newCycleCount = 21'h000001;
	5'h06: newCycleCount = 21'h000001;
	5'h07: newCycleCount = 21'h000001;
	5'h08: newCycleCount = 21'h000001;
	5'h09: newCycleCount = 21'h000001;
	5'h0A: newCycleCount = 21'h000001;
	5'h0B: newCycleCount = 21'h000001;
	5'h0C: newCycleCount = 21'h000002;
	5'h0D: newCycleCount = 21'h000004;
	5'h0E: newCycleCount = 21'h000008;
	5'h0F: newCycleCount = 21'h000010;
	5'h10: newCycleCount = 21'h000020;
	5'h11: newCycleCount = 21'h000040;
	5'h12: newCycleCount = 21'h000080;
	5'h13: newCycleCount = 21'h000100;
	5'h14: newCycleCount = 21'h000200;
	5'h15: newCycleCount = 21'h000400;
	5'h16: newCycleCount = 21'h000800;
	5'h17: newCycleCount = 21'h001000;
	5'h18: newCycleCount = 21'h002000;
	5'h19: newCycleCount = 21'h004000;
	5'h1A: newCycleCount = 21'h008000;
	5'h1B: newCycleCount = 21'h010000;
	5'h1C: newCycleCount = 21'h020000;
	5'h1D: newCycleCount = 21'h040000;
	5'h1E: newCycleCount = 21'h080000;
	5'h1F: newCycleCount = 21'h100000;
	endcase
	end
	
	assign o_CycleCount = i_shift2ExpIncr ? {newCycleCount, 2'b00} : {2'b00, newCycleCount};
	
	/* Version 2 18 LUT also...
	wire [5:0] rShift = i_EnvShift + { 4'b0 , i_shift2ExpIncr, 1'b0 };
	reg [22:0] newCycleCount;
	always @(*) begin
	case (rShift)
	6'h00: newCycleCount = 23'h000001;
	6'h01: newCycleCount = 23'h000001;
	6'h02: newCycleCount = 23'h000001;
	6'h03: newCycleCount = 23'h000001;
	6'h04: newCycleCount = 23'h000001;
	6'h05: newCycleCount = 23'h000001;
	6'h06: newCycleCount = 23'h000001;
	6'h07: newCycleCount = 23'h000001;
	6'h08: newCycleCount = 23'h000001;
	6'h09: newCycleCount = 23'h000001;
	6'h0A: newCycleCount = 23'h000001;
	6'h0B: newCycleCount = 23'h000001;
	6'h0C: newCycleCount = 23'h000002;
	6'h0D: newCycleCount = 23'h000004;
	6'h0E: newCycleCount = 23'h000008;
	6'h0F: newCycleCount = 23'h000010;
	6'h10: newCycleCount = 23'h000020;
	6'h11: newCycleCount = 23'h000040;
	6'h12: newCycleCount = 23'h000080;
	6'h13: newCycleCount = 23'h000100;
	6'h14: newCycleCount = 23'h000200;
	6'h15: newCycleCount = 23'h000400;
	6'h16: newCycleCount = 23'h000800;
	6'h17: newCycleCount = 23'h001000;
	6'h18: newCycleCount = 23'h002000;
	6'h19: newCycleCount = 23'h004000;
	6'h1A: newCycleCount = 23'h008000;
	6'h1B: newCycleCount = 23'h010000;
	6'h1C: newCycleCount = 23'h020000;
	6'h1D: newCycleCount = 23'h040000;
	6'h1E: newCycleCount = 23'h080000;
	6'h1F: newCycleCount = 23'h100000;
	6'h20:   newCycleCount = 23'h200000;
	default: newCycleCount = 23'h400000;
	endcase
	end
	
	assign o_CycleCount = newCycleCount;
	*/
endmodule

