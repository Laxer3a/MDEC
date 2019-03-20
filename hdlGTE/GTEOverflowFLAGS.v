module GTEOverflowFLAGS (
	input signed [48:0] v,
	input  sf,		// Use >> 12 bit shift if 1
	input  lm,		// B Check can select if using 0 (lm=1) or -MAX range (lm=0) value.
	
	output AxPos,	// Use  0 bit shift.
	output AxNeg,	// Use  0 bit shift.
	output FPos,	// Use  0 bit shift.
	output FNeg,	// Use  0 bit shift.
	output G,		// Use >> 16 bit shift.
	output H,		// Use >> 12 bit shift.
	
	output B,		// Depend on SF.
	output C,		// Depend on SF+4.
	output D		// Depend on SF.
);
/*
	For a unsigned integer overflow means :
	[0000000000][range] <- No overflow.
	[not zero  ][range] <- Overflow.    = OR all the out of range MSB bit using reduction operator.
	
	For a signed integer overflow means :
	 S = Last bit (sign)
	 |   Other
	 |   |
	[0][0000000][range] Normal value. (positive )  OR all bit -> must be 0 if S=0
	[1][1111111][range] Normal value. (negative ) AND all bit -> must be 1 if S=1
	[0][notzero][range] Out of range. (overflow )
	[1][not_one][range] Out of range. (underflow)
	
	In our case :
	49 bit result from internal 
	4|4444.4444|3333.3333|3322.2222|2222.1111|1111.1100|0000.0000
	8|7654.3210|9876.5432|1098.7654|3210.9876|5432.1098|7654.3210
	
   [S]AAAAAA[---------------------------------------------------] Check overflow bit 43
   [S]FFFFFFFFFFFFFFFFFFFFF[------------------------------------] Check overflow bit 31
   [S]GGGGGGGGGGGGGGGGGGGGGGGGGGG[-----------]XXXXXXXXXXXXXXXXXXX Check overflow bit 10 with >> 16 value. (we do not shift the value, but test higher position)
   [S]GGGGGGGGGGGGGGGGGGGGGGGGGGG[-----------]XXXXXXXXXXXXXXXXXXX Check overflow bit 10 with >> 16 value. (we do not shift the value, but test higher position)
   [S]HHHHHHHHHHHHHHHHHHHHHHHHHHHHH[--------------]XXXXXXXXXXXXXX Check overflow bit 12 with >> 12 value. (we do not shift the value, but test higher position)
	  Note : H is a special case, we also support :
	  00000000000000000000000000001|0000.0000|0000.XXXXXXXXXXXXXX 4096
   SF=0 Shift 0 / SF=1 Shift 12
   [S]BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB[----------------] Check 15 bit SF=0
   [S]BBBBBBBBBBBBBBBBBBBBBBBBBB[----------------]XXXXXXXXXXXXXXX Check 15 bit SF=1
   SF=0 Shift 4 / SF=1 Shift 16
   [S]CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC[--------]XXXX Check  8 bit SF=0
   [S]CCCCCCCCCCCCCCCCCCCCCCCCCCCCC[---------]XXXXXXXXXXXXXXXXXXX Check  8 bit SF=1
   SF=0 Shift 0 / SF=1 Shift 12
   [S]DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD[------------------] Check 16 bit SF=0
   [S]DDDDDDDDDDDDDDDDDDDDDDDD[-------------------]XXXXXXXXXXXXXX Check 16 bit SF=1
 */
 
// ---- Internal stuff ----
// Suppose Signed V[48:0], result is [42:0]
wire vSGN     = v[48];
wire isPos    = !vSGN;
// High   Part AND OR reduction.
wire orRdctA  = |v[47:43];				// 47:43
wire andRdctA = &v[47:43];				// 47:43
// Middle Part AND OR reduction.
wire orRdctF  = |v[42:31];				// 42:31
wire andRdctF = &v[42:31];				// 42:31

// G : Value larger than 10 bits from >> 16 value => same as test bit << 16.  -400..3FF
wire orRdctG  = |v[30: 28];				// 14:10 + 16 -> 30:26 but compute up to 28 here (optimize for others)
wire andRdctG = &v[30: 27];				// 14:10 + 16 -> 30:26 but compute up to 27 here (optimize for others)
wire overG    = (  orRdctA |  orRdctF |  orRdctG | (|v[27:26]) ); // 47:26
wire underG   = ( andRdctA & andRdctF & andRdctG & (&v[28:26]) ); // 47:26
wire GPos     = (isPos) & (  overG);	// 10 Bit positive overflow.  9:0 = 10 bit. ( > 0x*******3FF )
wire GNeg     = ( vSGN) & (!underG);	// 10 Bit negative overflow.  9:0 = 10 bit. ( < 0x******0400 )

// H : Value of 12 bit [11: 0] + 0x1000.
//                   ->[23:12]
//                           23               12 11                0
// Check Pattern = 0....0001_0000_0000_0000_0000_xxxx_xxxx_xxxx_xxxx
//              [Positive][All upper bit 0  ] [1 set]  [ all zeros    ]
wire is4096   = (isPos) &&((!(overG|v[25])) && v[24] && (!(|v[23:12])));
// Is >= 4096 ?
wire HPos     = (isPos)  & ( overG | (|v[25:24]));	// 12 Bit positive overflow.           11: 0 = 12 bit. ( > 0x*******FFF )

wire orRdctD  = overG    | (|v[25:16]);				// 42:16
wire andRdctD = andRdctF & (&v[30:16]);				// 42:16

// Positive overflow ?
wire DPos0    = (isPos) & (orRdctD);				// 16 Bit positive overflow.           15: 0 = 16 bit. ( > 0x******FFFF )
wire DPos12   = (isPos) & (orRdctG);				// 16 Bit positive overflow, shift 12. 27:12 = 16 bit. ( > 0x******FFFF )

wire orB0     = orRdctD | v[15];
wire orB12    = orRdctG | v[27];
wire BPos0    = (isPos) & (orB0 );					// 15 Bit positive overflow.           14: 0 = 15 bit. ( > 0x******7FFF )
wire BPos12   = (isPos) & (orB12);					// 15 Bit positive overflow. shift 12. 26:12 = 15 bit. ( > 0x******7FFF )

wire CPos0    = (isPos) & (orB0  | (|v[14:12]));	//  8 Bit positive overflow.  7:0 but shift 4               [11: 4]  =  8 bit. ( > 0x********FF )
wire CPos12   = (isPos) & (orB12 | (|v[26:24]));	//  8 Bit positive overflow.  7:0 but shift 12 then shift 4 [23:16]  =  8 bit. ( > 0x********FF )

// Negative overflow ?
wire BNeg0    = ( vSGN) & (!(andRdctD & v[15]));	// 15 Bit negative overflow.           14:0 = 15 bit.  ( < 0x******8000 )
wire BNeg12   = ( vSGN) & (!(andRdctG        ));	// 15 Bit negative overflow.           26:12 = 15 bit. ( < 0x******8000 )

// [Result Flag]
// Public output
// --------------------------------------------------------------
// A check only [MAX]
assign AxPos  = (isPos) & ( ( orRdctA                      )); // 43 Bit positive overflow. 42:0 = 43 bit, Sign bit is zero, and there is AT LEAST 1 bit at 1.
// A check only [MIN]
assign AxNeg  = ( vSGN) & (!(andRdctA                      )); // 43 Bit negative overflow. 42:0 = 43 bit, Sign bit is one,  and there is AT LEAST 1 bit at 0.
// F check only [MAX]
assign FPos   = (isPos) & ( ( orRdctA |  orRdctF           )); // 31 Bit positive overflow. 30:0 = 31 bit. ( > 0x**7FFFFFFF )
// F check only [MIN]
assign FNeg   = ( vSGN) & (!(andRdctA & andRdctF           )); // 31 Bit negative overflow. 31:0 = 15 bit. ( < 0x**80000000 )
// G check only [MIN,MAX]
assign G      = ( GPos) | (GNeg);
// H check only [0,MAX+1]
assign H      = ( vSGN) | (HPos && (!is4096))                ; // Check for > 0xFFF but remove 0x1000 case. Check also for > 0.
// lm select [0,MAX] or [MIN,MAX].
// sf select start at bit 0 or 12.
assign B      = ( sf ? BPos12 : BPos0) | ((sf ? BNeg12 : BNeg0) && (!lm)) | (vSGN && (lm));
// C check only [0,MAX]
assign C      = ( sf ? CPos12 : CPos0) | vSGN;
// D check only [0,MAX]
assign D      = ( sf ? DPos12 : DPos0) | vSGN;
// --------------------------------------------------------------
endmodule
