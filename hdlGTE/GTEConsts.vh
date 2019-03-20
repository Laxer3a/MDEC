// Included file with constant : 
parameter
	// Bit 0 : Fist instruction -> Reset status bit.
	// Bit 1 : Last instruction -> Allow to end state.
	RSTFLG    = 2'b01,
	___FLG    = 2'b00,
	LAST__	  = 2'b10,
	
	// Bit 2 : Override and set to 0 the LM bit.
	USE_LM    = 1'b1,
	RST_LM    = 1'b0,
	// Bit  7:3
	// Bit 12:8
	DATA_VXY0 = 6'd0,
	DATA__VZ0 = 6'd1,
	DATA_VXY1 = 6'd2,
	DATA__VZ1 = 6'd3,
	DATA_VXY2 = 6'd4,
	DATA__VZ2 = 6'd5,
	DATA_RGBC = 6'd6,
	DATA__OTZ = 6'd7,
	DATA__IR0 = 6'd8,
	DATA__IR1 = 6'd9,
	DATA__IR2 = 6'd10,
	DATA__IR3 = 6'd11,
	DATA_SXY0 = 6'd12,
	DATA_SXY1 = 6'd13,
	DATA_SXY2 = 6'd14,
	DATA_SXYP = 6'd15,
	DATA__SZ0 = 6'd16,
	DATA__SZ1 = 6'd17,
	DATA__SZ2 = 6'd18,
	DATA__SZ3 = 6'd19,
	DATACRGB0 = 6'd20,
	DATACRGB1 = 6'd21,
	DATACRGB2 = 6'd22,
	DATA_RES1 = 6'd23,
	DATA_MAC0 = 6'd24,
	DATA_MAC1 = 6'd25,
	DATA_MAC2 = 6'd26,
	DATA_MAC3 = 6'd27,
	
	CTRL_R33_ = 6'd04,
	CTRL_L33_ = 6'd12,
	CTRL_LB3_ = 6'd20,
	CTRL__H__ = 6'd26,
	CTRL_ZSF4 = 6'd30,
	
	DATA_____ = 6'd31,
	CTRL_____ = 6'd31,

	// WRITE
	DAT_WRITE = 1'b1,
	CTR_WRITE = 1'b1,
	____NOWRT = 1'b0,
	
	// Push
	PUSH___SZ = 1'b1,
	PUSH__SPX = 1'b1,
	PUSH__SPY = 1'b1,
	PUSH_CRGB = 1'b1,
	_NO_PSH__ = 1'b0,
	
	F______   = 19'b000_0000_0000_0000_0000,
	FLG_A1 	  = 19'b100_1000_0000_0000_0000,
	FLG_A2 	  = 19'b010_0100_0000_0000_0000,
	FLG_A3 	  = 19'b001_0010_0000_0000_0000,
	FLG_B1	  = 19'b000_0001_0000_0000_0000,
	FLG_B2	  = 19'b000_0000_1000_0000_0000,
	FLG_B3	  = 19'b000_0000_0100_0000_0000,
	
	UNUSED_SYMBOL_END_LIST = 0; // Convenience to add/remove item with the last , issue.
