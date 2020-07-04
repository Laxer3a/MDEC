module GTEOverflowFLAGS (
	input signed [49:0] v,
	input  sf,		// Use >> 12 bit shift if 1
	input  lm,		// VALUE B : Check can select if using 0 (lm=1) or -MAX range (lm=0) value.
	input  forceSF_BFlag,
	
	output AxPos,	// Use  0 bit shift.
	output AxNeg,	// Use  0 bit shift.
	output FPos,	// Use  0 bit shift.
	output FNeg,	// Use  0 bit shift.
	output G,		// Use >> 16 bit shift.
	output H,		// Use >> 12 bit shift.
	
	output B,		// Depend on SF.
	output C,		// Depend on SF+4.
	output D,		// Depend on SF.
	
	output [31:0]   OutA,
	output [15:0]   OutB,
	output [ 7:0]	OutC,
	output [15:0]   OutD,
	output [10:0]	OutG,
	output [12:0]	OutH
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

   [S]HHHHHHHHHHHHHHHHHHHHHHHHHHHHH[--------------]XXXXXXXXXXXXXX Check overflow bit 12 with >> 12 value FLAGS. (we do not shift the value, but test higher position)
   [S]_____HHHHHHHHHHHHHHHHHHHHHHHH[--------------]XXXXXXXXXXXXXX Check overflow bit 12 with >> 12 value CLAMP. (we do not shift the value, but test higher position)
   
	  Note : H is a special case, we also support :
	  00000000000000000000000000001|0000.0000|0000.XXXXXXXXXXXXXX 4096
   SF=0 Shift 0 / SF=1 Shift 12
   [S]____________________BBBBBBBBBBBBBBBBBBBBB[----------------] Check 15 bit SF=0
   [S]_____BBBBBBBBBBBBBBBBBBBBB[----------------]XXXXXXXXXXXXXXX Check 15 bit SF=1
		ALSO Special mode force SF=1 ONLY FOR FLAG VALUE (forceSF_BFlag = 1) BUT CLAMP only use SF !
		
   SF=0 Shift 4 / SF=1 Shift 16
   [S]____________________CCCCCCCCCCCCCCCCCCCCCCCCC[--------]XXXX Check  8 bit SF=0
   [S]_____CCCCCCCCCCCCCCCCCCCCCCCC[---------]XXXXXXXXXXXXXXXXXXX Check  8 bit SF=1
   SF=0 Shift 0 / SF=1 Shift 12
   [S]_____DDDDDDDDDDDDDDDDDDD[-------------------]XXXXXXXXXXXXXX Check 16 bit SF=1 // SF=0 IS NEVER USED. HARD CODED SF=1.
 */

// ---- Internal stuff ----
// Suppose Signed V[48:0], result is [42:0]
wire vSGN     = v[49];
wire isPos    = !vSGN;
wire bSF      = (sf | forceSF_BFlag);
wire vSGNB    = bSF ? v[43] : v[31]; 
wire isPosB   = !vSGNB;
wire vSGNC    = sf ? v[43] : v[31];
wire isPosC   = !vSGNC;
wire vSGND    = v[43]; // SF=1 always.
wire isPosD   = !vSGND;

// High   Part AND OR reduction.
wire orRdctA  = |v[48:43];				// 48:43
wire andRdctA = &v[48:43];				// 48:43
// Middle Part AND OR reduction.
wire orRdctF  = |v[42:31];				// 42:31
wire andRdctF = &v[42:31];				// 42:31

// G : Value larger than 10 bits from >> 16 value => same as test bit << 16.  -400..3FF
wire orRdctG  = |v[30: 28];				// 14:10 + 16 -> 30:26 but compute up to 28 here (optimize for others)
wire andRdctG = &v[30: 27];				// 14:10 + 16 -> 30:26 but compute up to 27 here (optimize for others)
wire or2726   = |v[27:26];
wire overG    = (  orRdctA |  orRdctF |  orRdctG | or2726); // 47:26
wire underG   = ( andRdctA & andRdctF & andRdctG & (&v[28:26]) ); // 47:26
wire GPos     = (isPos) & (  overG);	// 10 Bit positive overflow.  9:0 = 10 bit. ( > 0x*******3FF )
wire GNeg     = ( vSGN) & (!underG);	// 10 Bit negative overflow.  9:0 = 10 bit. ( < 0x******0400 )

// H : Value of 12 bit [11: 0] + 0x1000.
//                   ->[23:12]
//                           23               12 11                0
// Check Pattern = 0....0001_0000_0000_0000_0000_xxxx_xxxx_xxxx_xxxx
//              [Positive][All upper bit 0  ] [1 set]  [ all zeros    ]
wire isLow4096= v[24] && (!(|v[23:12]));
wire is4096   = (isPos)  && (!(overG|v[25])) && isLow4096;
wire is4096Clp= (isPosD) && (!(orRdctF | orRdctG | or2726 | v[25])) && isLow4096;

// Is >= 4096 ?
wire or2524   = (|v[25:24]);
wire HPosFlg  = (isPos )  & ( overG   | or2524);	// 12 Bit positive overflow.           11: 0 = 12 bit. ( > 0x*******FFF )
wire HPosClp  = (isPosD)  & ( orRdctF | orRdctG | or2726 | or2524);

// Positive overflow ?

// SF=1 always for D
// wire orRdctD  = overG    | (|v[25:16]);			// 42:16
// wire DPos0    = (isPos) & (orRdctD);				// 16 Bit positive overflow.           15: 0 = 16 bit. ( > 0x******FFFF )
wire DPos12   = (isPosD) & (orRdctF | orRdctG);		// [42:31][30:28] : 16 Bit positive overflow, shift 12. 27:12 = 16 bit. ( > 0x******FFFF )

wire orBHi    = (orRdctF | orRdctG | v[27]);
wire orBLo    = ( |v[30:15]               );

wire orB      = (sf ? orBHi 	//42:27
					: orBLo);	//30:15
					
wire orBFlg   = (bSF? orBHi 	//42:27
					: orBLo);	//30:15
					
// Note isPosC here is NOT a bug : same sign bit for B and C.
													// Depend on SF or ForceB flag.
wire BPosFlg  = (isPosB) & (orBFlg);				// 15 Bit positive overflow.           14: 0 = 15 bit. ( > 0x******7FFF )
                                                    // 15 Bit positive overflow. shift 12. 26:12 = 15 bit. ( > 0x******7FFF )
													
													// Depend on SF flag.
wire BPosClp  = (isPosC) & (orB);					// 15 Bit positive overflow.           14: 0 = 15 bit. ( > 0x******7FFF )
													// 15 Bit positive overflow. shift 12. 26:12 = 15 bit. ( > 0x******7FFF )

wire CPos     = (isPosC) & (orB | (sf ? (|v[26:24]) : (|v[14:12])));	//  8 Bit positive overflow.  7:0 but shift 4               [11: 4]  =  8 bit. ( > 0x********FF )
																		//  8 Bit positive overflow.  7:0 but shift 12 then shift 4 [23:16]  =  8 bit. ( > 0x********FF )

// Negative overflow ?
wire andBHi   = (andRdctF | andRdctG );
wire andBLo   = ( &v[30:15]          );
wire andB     = (sf ? andBHi	// 42:27 (Different from orRdctG range xx:28!)
                    : andBLo);
wire andBFlg  = (bSF? andBHi	// 42:27 (Different from orRdctG range xx:28!)
                    : andBLo);
					
									// Depend on SF or ForceB flag.
wire BNegFlg  = (vSGNB) & andBFlg;	// 15 Bit negative overflow.           14:0 = 15 bit.  ( < 0x******8000 )
									// 15 Bit negative overflow.           26:12 = 15 bit. ( < 0x******8000 )

									// Depend on SF flag.
wire BNegClp  = (vSGNC) & andB;		// 15 Bit negative overflow.           14:0 = 15 bit.  ( < 0x******8000 )
									// 15 Bit negative overflow.           26:12 = 15 bit. ( < 0x******8000 )
									
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
assign H      = ( vSGN) | (HPosFlg && (!is4096))                ; // Check for > 0xFFF but remove 0x1000 case. Check also for > 0.
// lm select [0,MAX] or [MIN,MAX].


assign OutA   = sf ? v[43:12] : v[31:0];

// sf select start at bit 0 or 12.
wire   nandBFlg  = (BNegFlg && (!lm)) | (vSGNB && lm);
assign B         = BPosFlg | nandBFlg;

wire   nandBClp  = (BNegClp && (!lm)) | (vSGNC && lm);
assign OutB	     = { (vSGNC & (~lm)) , (((sf ? v[26:12] : v[14:0]) & {15{!nandBClp}}) | {15{BPosClp}}) };

// C [0,MAX]
assign C      = CPos | vSGNC;
assign OutC   = ((sf ? v[23:16] : v[11:4]) & {8{!vSGNC}}) | {8{CPos}};

// D [0,MAX]
// Those comment are for support of variable SF, for now SF=1 always for D value.
// wire   orD    =  (sf ? DPos12 : DPos0);
// assign OutD   = ((sf ? v[27:12] : v[15:0]) & {16{!vSGN}}) | {16{orD}};
assign D      = DPos12 | vSGND;
assign OutD   = (v[27:12] & {16{!vSGND}}) | {16{DPos12}};

// G [MIN,MAX]
assign OutG   = {vSGN,(v[25:16] | {10{GPos}}) & {10{!GNeg}}};

// H [0,MAX+1]
// TODO : Possible optimization ? (avoid multipler with OR/AND stage ?)
assign OutH	  = (HPosClp && (!is4096Clp)) ? 13'h1000 : (v[24:12] & {13{!vSGND}});

// --------------------------------------------------------------
endmodule
