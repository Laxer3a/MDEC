/*
	PS1 GPU Memory is 1MB => 1024x1024 Byte => 20 bit adress bus.
	
	Future possible optimization :
	- Larger 128 Bit Entry.
	- Swizzling
	- 2Way Cache / 4Way / 8way Cache
	
	- Use 512 Bit Active BRAM on posedge, read cache on negedge. => Work at same freq, allow 
 */

module directCacheDoublePort(
	input			clk,
	input			i_nrst,
	input			clearCache,
	
	// [Can spy all write on the bus and maintain cache integrity]
	input			textureFormatTrueColor,
	input			write,
//	input			update,		// If update 32 bit.
	input	[16:0]	adressIn,
	input	[63:0]	dataIn,		// Upper module responsability to make 64 bit atomic write.
	
	input			requLookupA,
	input	[18:0]	adressLookA,
	output	[15:0]	dataOutA,
	output			isHitA,
	output			isMissA,

	input			requLookupB,
	input	[18:0]	adressLookB,
	output	[15:0]	dataOutB,
	output			isHitB,
	output			isMissB
);
	// LINEAR MAPPING :
	// ccccPPPPPbbbbbLLL aaa <-- One line width for block in  16 bpp. (32 pixel   , 64 byte per line)
	// cccPPPPPPbbbbbbLL aaa <-- One line width for block in 8/4 bpp. (32/64 pixel, 32 byte per line)
	// wire [19:0] swizzleAddr = adressIn; // Straight
	
	// SWIZZLED MAPPING : remapped to IN THE cache as : (no need to swizzle outside, cache can implement it internally and just output 16 bit for an address read)
	// --------------------------
	// ccccbbbbb|PPPPPLLL aaa <-- One line width for block in  16 bpp. (32 pixel   , 64 byte per line)
	// cccbbbbbb|PPPPPPLL aaa <-- One line width for block in 8/4 bpp. (32/64 pixel, 32 byte per line)

//	wire [19:0] swizzleAddr = textureFormatTrueColor 	? { adressIn[19:16],adressIn[10:6],adressIn[15:11],adressIn[5:0]}  // 4,5,5,6
//														: { adressIn[19:17],adressIn[10:5],adressIn[16:11],adressIn[4:0]}; // 5,6,6,5
	wire [16:0] swizzleAddr = textureFormatTrueColor 	? { adressIn[16:13],adressIn[7:3],adressIn[12:8],adressIn[2:0]}  // 4,5,5,3
														: { adressIn[16:14],adressIn[7:2],adressIn[13:8],adressIn[1:0]}; // 5,6,6,2

	wire [16:0] swizzleLookA= textureFormatTrueColor 	? { adressLookA[18:15],adressLookA[9:5],adressLookA[14:10],adressLookA[4:2]}  // 4,5,5,3
														: { adressLookA[18:16],adressLookA[9:4],adressLookA[15:10],adressLookA[3:2]}; // 5,6,6,2
	wire [16:0] swizzleLookB= textureFormatTrueColor 	? { adressLookB[18:15],adressLookB[9:5],adressLookB[14:10],adressLookB[4:2]}  // 4,5,5,3
														: { adressLookB[18:16],adressLookB[9:4],adressLookB[15:10],adressLookB[3:2]}; // 5,6,6,2
														
//	parameter WT = 11; 	// 4KB Version
//	parameter NE = 511;

	// ------------- 4 KB Version ----------
	// [20:12][11:3][2:0]		512 Entries x 8 Byte (4x2) = 4 KB.
	//   9 bit 9bit  3bit
	// ------------- 2 KB Version ----------
	// [20:11][10:3][2:0]		256 Entries x 8 Byte (4x2) = 2 KB.
	//  10 bit 8bit  3bit
	reg [71:0] RAMStorage[255:0];			// 72/71 + 512 vs 256 entries.
	reg [255:0] Active;						// 512 vs 256 active bit.
	reg [7:0] pRaddrA,pRaddrB;			// 9 or 8 bit address

	reg [2:1] pIndexA,pIndexB;
	
	always @ (posedge clk)
	begin
		if (write)
		begin
			RAMStorage[swizzleAddr[7:0]]	<= { swizzleAddr[7:0], dataIn[63: 0] };
//			D0A								<= { swizzleAddr[7:0], dataIn[63: 0] };		// DID CAUSE INFERENCE ISSUE, NOT ENABLING RAM BLOCK
//			D0B								<= { swizzleAddr[7:0], dataIn[63: 0] };
//		end else begin
//			D0A								<= RAMStorage[adressLookA[10:2]];
//			D0B								<= RAMStorage[adressLookB[10:2]];
		end
		
		pRaddrA	<= swizzleLookA[7:0];
		pRaddrB	<= swizzleLookB[7:0];
	end
//	reg  [71:0]	D0A;
//	reg  [WS:0]	D0B;

	wire  [71:0]	D0A = RAMStorage[pRaddrA];
	wire  [71:0]	D0B = RAMStorage[pRaddrB];

	wire       lookActiveA	= Active[pRaddrA];
	wire       lookActiveB	= Active[pRaddrB];
	reg 	   pRequLookupA;
	reg 	   pRequLookupB;
	wire [7:0] lookTagA	= D0A[71:64];
	wire [7:0] lookTagB	= D0B[71:64];

	// Return HIT when NOT looking up for data...
	wire hitA       = ((lookTagA == pRaddrA) & pLookActiveA);
	wire hitB		= ((lookTagB == pRaddrB) & pLookActiveB);
	assign isHitA	=   hitA  & pRequLookupA;
	assign isHitB	=   hitB  & pRequLookupB;
	wire spikeMissA = ((!hitA) & pRequLookupA);
	wire spikeMissB = ((!hitB) & pRequLookupB);
	assign isMissA	= spikeMissA | (stickyMissA & !hitA);	// Note : Sticky BIT does not RETURN 1 when isHit is generated.
	assign isMissB	= spikeMissB | (stickyMissB & !hitB);

	reg pLookActiveA;
	reg pLookActiveB;
	reg stickyMissA, stickyMissB;
	always @ (posedge clk)
	begin
		pRequLookupA = requLookupA;
		pRequLookupB = requLookupB;
		pLookActiveA = lookActiveA;
		pLookActiveB = lookActiveB;
		
		if (isHitA) begin
			stickyMissA = 0;
		end else begin
			if (isMissA) begin
				stickyMissA = 1;
			end
		end
		if (isHitB) begin
			stickyMissB = 0;
		end else begin
			if (isMissB) begin
				stickyMissB = 1;
			end
		end
	end
	
	reg [15:0] dOutA;
	always @(*) begin
	case (pIndexA)
	2'd0 : dOutA = D0A[15: 0];
	2'd1 : dOutA = D0A[31:16];
	2'd2 : dOutA = D0A[47:32];
	2'd3 : dOutA = D0A[63:48];
	endcase
	end
	assign dataOutA	= dOutA;
	
	reg [15:0] dOutB;
	always @(*) begin
	case (pIndexB)
	2'd0 : dOutB = D0B[15: 0];
	2'd1 : dOutB = D0B[31:16];
	2'd2 : dOutB = D0B[47:32];
	2'd3 : dOutB = D0B[63:48];
	endcase
	end
	assign dataOutB	= dOutB;
	
	always @ (posedge clk)
	begin
		if ((i_nrst == 0) | clearCache) begin
			Active[  0] <= 1'b0;
			Active[  1] <= 1'b0;
			Active[  2] <= 1'b0;
			Active[  3] <= 1'b0;
			Active[  4] <= 1'b0;
			Active[  5] <= 1'b0;
			Active[  6] <= 1'b0;
			Active[  7] <= 1'b0;
			Active[  8] <= 1'b0;
			Active[  9] <= 1'b0;
			Active[ 10] <= 1'b0;
			Active[ 11] <= 1'b0;
			Active[ 12] <= 1'b0;
			Active[ 13] <= 1'b0;
			Active[ 14] <= 1'b0;
			Active[ 15] <= 1'b0;
			Active[ 16] <= 1'b0;
			Active[ 17] <= 1'b0;
			Active[ 18] <= 1'b0;
			Active[ 19] <= 1'b0;
			Active[ 20] <= 1'b0;
			Active[ 21] <= 1'b0;
			Active[ 22] <= 1'b0;
			Active[ 23] <= 1'b0;
			Active[ 24] <= 1'b0;
			Active[ 25] <= 1'b0;
			Active[ 26] <= 1'b0;
			Active[ 27] <= 1'b0;
			Active[ 28] <= 1'b0;
			Active[ 29] <= 1'b0;
			Active[ 30] <= 1'b0;
			Active[ 31] <= 1'b0;
			Active[ 32] <= 1'b0;
			Active[ 33] <= 1'b0;
			Active[ 34] <= 1'b0;
			Active[ 35] <= 1'b0;
			Active[ 36] <= 1'b0;
			Active[ 37] <= 1'b0;
			Active[ 38] <= 1'b0;
			Active[ 39] <= 1'b0;
			Active[ 40] <= 1'b0;
			Active[ 41] <= 1'b0;
			Active[ 42] <= 1'b0;
			Active[ 43] <= 1'b0;
			Active[ 44] <= 1'b0;
			Active[ 45] <= 1'b0;
			Active[ 46] <= 1'b0;
			Active[ 47] <= 1'b0;
			Active[ 48] <= 1'b0;
			Active[ 49] <= 1'b0;
			Active[ 50] <= 1'b0;
			Active[ 51] <= 1'b0;
			Active[ 52] <= 1'b0;
			Active[ 53] <= 1'b0;
			Active[ 54] <= 1'b0;
			Active[ 55] <= 1'b0;
			Active[ 56] <= 1'b0;
			Active[ 57] <= 1'b0;
			Active[ 58] <= 1'b0;
			Active[ 59] <= 1'b0;
			Active[ 60] <= 1'b0;
			Active[ 61] <= 1'b0;
			Active[ 62] <= 1'b0;
			Active[ 63] <= 1'b0;
			Active[ 64] <= 1'b0;
			Active[ 65] <= 1'b0;
			Active[ 66] <= 1'b0;
			Active[ 67] <= 1'b0;
			Active[ 68] <= 1'b0;
			Active[ 69] <= 1'b0;
			Active[ 70] <= 1'b0;
			Active[ 71] <= 1'b0;
			Active[ 72] <= 1'b0;
			Active[ 73] <= 1'b0;
			Active[ 74] <= 1'b0;
			Active[ 75] <= 1'b0;
			Active[ 76] <= 1'b0;
			Active[ 77] <= 1'b0;
			Active[ 78] <= 1'b0;
			Active[ 79] <= 1'b0;
			Active[ 80] <= 1'b0;
			Active[ 81] <= 1'b0;
			Active[ 82] <= 1'b0;
			Active[ 83] <= 1'b0;
			Active[ 84] <= 1'b0;
			Active[ 85] <= 1'b0;
			Active[ 86] <= 1'b0;
			Active[ 87] <= 1'b0;
			Active[ 88] <= 1'b0;
			Active[ 89] <= 1'b0;
			Active[ 90] <= 1'b0;
			Active[ 91] <= 1'b0;
			Active[ 92] <= 1'b0;
			Active[ 93] <= 1'b0;
			Active[ 94] <= 1'b0;
			Active[ 95] <= 1'b0;
			Active[ 96] <= 1'b0;
			Active[ 97] <= 1'b0;
			Active[ 98] <= 1'b0;
			Active[ 99] <= 1'b0;
			Active[100] <= 1'b0;
			Active[101] <= 1'b0;
			Active[102] <= 1'b0;
			Active[103] <= 1'b0;
			Active[104] <= 1'b0;
			Active[105] <= 1'b0;
			Active[106] <= 1'b0;
			Active[107] <= 1'b0;
			Active[108] <= 1'b0;
			Active[109] <= 1'b0;
			Active[110] <= 1'b0;
			Active[111] <= 1'b0;
			Active[112] <= 1'b0;
			Active[113] <= 1'b0;
			Active[114] <= 1'b0;
			Active[115] <= 1'b0;
			Active[116] <= 1'b0;
			Active[117] <= 1'b0;
			Active[118] <= 1'b0;
			Active[119] <= 1'b0;
			Active[120] <= 1'b0;
			Active[121] <= 1'b0;
			Active[122] <= 1'b0;
			Active[123] <= 1'b0;
			Active[124] <= 1'b0;
			Active[125] <= 1'b0;
			Active[126] <= 1'b0;
			Active[127] <= 1'b0;
			Active[128] <= 1'b0;
			Active[129] <= 1'b0;
			Active[130] <= 1'b0;
			Active[131] <= 1'b0;
			Active[132] <= 1'b0;
			Active[133] <= 1'b0;
			Active[134] <= 1'b0;
			Active[135] <= 1'b0;
			Active[136] <= 1'b0;
			Active[137] <= 1'b0;
			Active[138] <= 1'b0;
			Active[139] <= 1'b0;
			Active[140] <= 1'b0;
			Active[141] <= 1'b0;
			Active[142] <= 1'b0;
			Active[143] <= 1'b0;
			Active[144] <= 1'b0;
			Active[145] <= 1'b0;
			Active[146] <= 1'b0;
			Active[147] <= 1'b0;
			Active[148] <= 1'b0;
			Active[149] <= 1'b0;
			Active[150] <= 1'b0;
			Active[151] <= 1'b0;
			Active[152] <= 1'b0;
			Active[153] <= 1'b0;
			Active[154] <= 1'b0;
			Active[155] <= 1'b0;
			Active[156] <= 1'b0;
			Active[157] <= 1'b0;
			Active[158] <= 1'b0;
			Active[159] <= 1'b0;
			Active[160] <= 1'b0;
			Active[161] <= 1'b0;
			Active[162] <= 1'b0;
			Active[163] <= 1'b0;
			Active[164] <= 1'b0;
			Active[165] <= 1'b0;
			Active[166] <= 1'b0;
			Active[167] <= 1'b0;
			Active[168] <= 1'b0;
			Active[169] <= 1'b0;
			Active[170] <= 1'b0;
			Active[171] <= 1'b0;
			Active[172] <= 1'b0;
			Active[173] <= 1'b0;
			Active[174] <= 1'b0;
			Active[175] <= 1'b0;
			Active[176] <= 1'b0;
			Active[177] <= 1'b0;
			Active[178] <= 1'b0;
			Active[179] <= 1'b0;
			Active[180] <= 1'b0;
			Active[181] <= 1'b0;
			Active[182] <= 1'b0;
			Active[183] <= 1'b0;
			Active[184] <= 1'b0;
			Active[185] <= 1'b0;
			Active[186] <= 1'b0;
			Active[187] <= 1'b0;
			Active[188] <= 1'b0;
			Active[189] <= 1'b0;
			Active[190] <= 1'b0;
			Active[191] <= 1'b0;
			Active[192] <= 1'b0;
			Active[193] <= 1'b0;
			Active[194] <= 1'b0;
			Active[195] <= 1'b0;
			Active[196] <= 1'b0;
			Active[197] <= 1'b0;
			Active[198] <= 1'b0;
			Active[199] <= 1'b0;
			Active[200] <= 1'b0;
			Active[201] <= 1'b0;
			Active[202] <= 1'b0;
			Active[203] <= 1'b0;
			Active[204] <= 1'b0;
			Active[205] <= 1'b0;
			Active[206] <= 1'b0;
			Active[207] <= 1'b0;
			Active[208] <= 1'b0;
			Active[209] <= 1'b0;
			Active[210] <= 1'b0;
			Active[211] <= 1'b0;
			Active[212] <= 1'b0;
			Active[213] <= 1'b0;
			Active[214] <= 1'b0;
			Active[215] <= 1'b0;
			Active[216] <= 1'b0;
			Active[217] <= 1'b0;
			Active[218] <= 1'b0;
			Active[219] <= 1'b0;
			Active[220] <= 1'b0;
			Active[221] <= 1'b0;
			Active[222] <= 1'b0;
			Active[223] <= 1'b0;
			Active[224] <= 1'b0;
			Active[225] <= 1'b0;
			Active[226] <= 1'b0;
			Active[227] <= 1'b0;
			Active[228] <= 1'b0;
			Active[229] <= 1'b0;
			Active[230] <= 1'b0;
			Active[231] <= 1'b0;
			Active[232] <= 1'b0;
			Active[233] <= 1'b0;
			Active[234] <= 1'b0;
			Active[235] <= 1'b0;
			Active[236] <= 1'b0;
			Active[237] <= 1'b0;
			Active[238] <= 1'b0;
			Active[239] <= 1'b0;
			Active[240] <= 1'b0;
			Active[241] <= 1'b0;
			Active[242] <= 1'b0;
			Active[243] <= 1'b0;
			Active[244] <= 1'b0;
			Active[245] <= 1'b0;
			Active[246] <= 1'b0;
			Active[247] <= 1'b0;
			Active[248] <= 1'b0;
			Active[249] <= 1'b0;
			Active[250] <= 1'b0;
			Active[251] <= 1'b0;
			Active[252] <= 1'b0;
			Active[253] <= 1'b0;
			Active[254] <= 1'b0;
			Active[255] <= 1'b0;
		/* 4 KB Version
			Active[256] <= 1'b0;
			Active[257] <= 1'b0;
			Active[258] <= 1'b0;
			Active[259] <= 1'b0;
			Active[260] <= 1'b0;
			Active[261] <= 1'b0;
			Active[262] <= 1'b0;
			Active[263] <= 1'b0;
			Active[264] <= 1'b0;
			Active[265] <= 1'b0;
			Active[266] <= 1'b0;
			Active[267] <= 1'b0;
			Active[268] <= 1'b0;
			Active[269] <= 1'b0;
			Active[270] <= 1'b0;
			Active[271] <= 1'b0;
			Active[272] <= 1'b0;
			Active[273] <= 1'b0;
			Active[274] <= 1'b0;
			Active[275] <= 1'b0;
			Active[276] <= 1'b0;
			Active[277] <= 1'b0;
			Active[278] <= 1'b0;
			Active[279] <= 1'b0;
			Active[280] <= 1'b0;
			Active[281] <= 1'b0;
			Active[282] <= 1'b0;
			Active[283] <= 1'b0;
			Active[284] <= 1'b0;
			Active[285] <= 1'b0;
			Active[286] <= 1'b0;
			Active[287] <= 1'b0;
			Active[288] <= 1'b0;
			Active[289] <= 1'b0;
			Active[290] <= 1'b0;
			Active[291] <= 1'b0;
			Active[292] <= 1'b0;
			Active[293] <= 1'b0;
			Active[294] <= 1'b0;
			Active[295] <= 1'b0;
			Active[296] <= 1'b0;
			Active[297] <= 1'b0;
			Active[298] <= 1'b0;
			Active[299] <= 1'b0;
			Active[300] <= 1'b0;
			Active[301] <= 1'b0;
			Active[302] <= 1'b0;
			Active[303] <= 1'b0;
			Active[304] <= 1'b0;
			Active[305] <= 1'b0;
			Active[306] <= 1'b0;
			Active[307] <= 1'b0;
			Active[308] <= 1'b0;
			Active[309] <= 1'b0;
			Active[310] <= 1'b0;
			Active[311] <= 1'b0;
			Active[312] <= 1'b0;
			Active[313] <= 1'b0;
			Active[314] <= 1'b0;
			Active[315] <= 1'b0;
			Active[316] <= 1'b0;
			Active[317] <= 1'b0;
			Active[318] <= 1'b0;
			Active[319] <= 1'b0;
			Active[320] <= 1'b0;
			Active[321] <= 1'b0;
			Active[322] <= 1'b0;
			Active[323] <= 1'b0;
			Active[324] <= 1'b0;
			Active[325] <= 1'b0;
			Active[326] <= 1'b0;
			Active[327] <= 1'b0;
			Active[328] <= 1'b0;
			Active[329] <= 1'b0;
			Active[330] <= 1'b0;
			Active[331] <= 1'b0;
			Active[332] <= 1'b0;
			Active[333] <= 1'b0;
			Active[334] <= 1'b0;
			Active[335] <= 1'b0;
			Active[336] <= 1'b0;
			Active[337] <= 1'b0;
			Active[338] <= 1'b0;
			Active[339] <= 1'b0;
			Active[340] <= 1'b0;
			Active[341] <= 1'b0;
			Active[342] <= 1'b0;
			Active[343] <= 1'b0;
			Active[344] <= 1'b0;
			Active[345] <= 1'b0;
			Active[346] <= 1'b0;
			Active[347] <= 1'b0;
			Active[348] <= 1'b0;
			Active[349] <= 1'b0;
			Active[350] <= 1'b0;
			Active[351] <= 1'b0;
			Active[352] <= 1'b0;
			Active[353] <= 1'b0;
			Active[354] <= 1'b0;
			Active[355] <= 1'b0;
			Active[356] <= 1'b0;
			Active[357] <= 1'b0;
			Active[358] <= 1'b0;
			Active[359] <= 1'b0;
			Active[360] <= 1'b0;
			Active[361] <= 1'b0;
			Active[362] <= 1'b0;
			Active[363] <= 1'b0;
			Active[364] <= 1'b0;
			Active[365] <= 1'b0;
			Active[366] <= 1'b0;
			Active[367] <= 1'b0;
			Active[368] <= 1'b0;
			Active[369] <= 1'b0;
			Active[370] <= 1'b0;
			Active[371] <= 1'b0;
			Active[372] <= 1'b0;
			Active[373] <= 1'b0;
			Active[374] <= 1'b0;
			Active[375] <= 1'b0;
			Active[376] <= 1'b0;
			Active[377] <= 1'b0;
			Active[378] <= 1'b0;
			Active[379] <= 1'b0;
			Active[380] <= 1'b0;
			Active[381] <= 1'b0;
			Active[382] <= 1'b0;
			Active[383] <= 1'b0;
			Active[384] <= 1'b0;
			Active[385] <= 1'b0;
			Active[386] <= 1'b0;
			Active[387] <= 1'b0;
			Active[388] <= 1'b0;
			Active[389] <= 1'b0;
			Active[390] <= 1'b0;
			Active[391] <= 1'b0;
			Active[392] <= 1'b0;
			Active[393] <= 1'b0;
			Active[394] <= 1'b0;
			Active[395] <= 1'b0;
			Active[396] <= 1'b0;
			Active[397] <= 1'b0;
			Active[398] <= 1'b0;
			Active[399] <= 1'b0;
			Active[400] <= 1'b0;
			Active[401] <= 1'b0;
			Active[402] <= 1'b0;
			Active[403] <= 1'b0;
			Active[404] <= 1'b0;
			Active[405] <= 1'b0;
			Active[406] <= 1'b0;
			Active[407] <= 1'b0;
			Active[408] <= 1'b0;
			Active[409] <= 1'b0;
			Active[410] <= 1'b0;
			Active[411] <= 1'b0;
			Active[412] <= 1'b0;
			Active[413] <= 1'b0;
			Active[414] <= 1'b0;
			Active[415] <= 1'b0;
			Active[416] <= 1'b0;
			Active[417] <= 1'b0;
			Active[418] <= 1'b0;
			Active[419] <= 1'b0;
			Active[420] <= 1'b0;
			Active[421] <= 1'b0;
			Active[422] <= 1'b0;
			Active[423] <= 1'b0;
			Active[424] <= 1'b0;
			Active[425] <= 1'b0;
			Active[426] <= 1'b0;
			Active[427] <= 1'b0;
			Active[428] <= 1'b0;
			Active[429] <= 1'b0;
			Active[430] <= 1'b0;
			Active[431] <= 1'b0;
			Active[432] <= 1'b0;
			Active[433] <= 1'b0;
			Active[434] <= 1'b0;
			Active[435] <= 1'b0;
			Active[436] <= 1'b0;
			Active[437] <= 1'b0;
			Active[438] <= 1'b0;
			Active[439] <= 1'b0;
			Active[440] <= 1'b0;
			Active[441] <= 1'b0;
			Active[442] <= 1'b0;
			Active[443] <= 1'b0;
			Active[444] <= 1'b0;
			Active[445] <= 1'b0;
			Active[446] <= 1'b0;
			Active[447] <= 1'b0;
			Active[448] <= 1'b0;
			Active[449] <= 1'b0;
			Active[450] <= 1'b0;
			Active[451] <= 1'b0;
			Active[452] <= 1'b0;
			Active[453] <= 1'b0;
			Active[454] <= 1'b0;
			Active[455] <= 1'b0;
			Active[456] <= 1'b0;
			Active[457] <= 1'b0;
			Active[458] <= 1'b0;
			Active[459] <= 1'b0;
			Active[460] <= 1'b0;
			Active[461] <= 1'b0;
			Active[462] <= 1'b0;
			Active[463] <= 1'b0;
			Active[464] <= 1'b0;
			Active[465] <= 1'b0;
			Active[466] <= 1'b0;
			Active[467] <= 1'b0;
			Active[468] <= 1'b0;
			Active[469] <= 1'b0;
			Active[470] <= 1'b0;
			Active[471] <= 1'b0;
			Active[472] <= 1'b0;
			Active[473] <= 1'b0;
			Active[474] <= 1'b0;
			Active[475] <= 1'b0;
			Active[476] <= 1'b0;
			Active[477] <= 1'b0;
			Active[478] <= 1'b0;
			Active[479] <= 1'b0;
			Active[480] <= 1'b0;
			Active[481] <= 1'b0;
			Active[482] <= 1'b0;
			Active[483] <= 1'b0;
			Active[484] <= 1'b0;
			Active[485] <= 1'b0;
			Active[486] <= 1'b0;
			Active[487] <= 1'b0;
			Active[488] <= 1'b0;
			Active[489] <= 1'b0;
			Active[490] <= 1'b0;
			Active[491] <= 1'b0;
			Active[492] <= 1'b0;
			Active[493] <= 1'b0;
			Active[494] <= 1'b0;
			Active[495] <= 1'b0;
			Active[496] <= 1'b0;
			Active[497] <= 1'b0;
			Active[498] <= 1'b0;
			Active[499] <= 1'b0;
			Active[500] <= 1'b0;
			Active[501] <= 1'b0;
			Active[502] <= 1'b0;
			Active[503] <= 1'b0;
			Active[504] <= 1'b0;
			Active[505] <= 1'b0;
			Active[506] <= 1'b0;
			Active[507] <= 1'b0;
			Active[508] <= 1'b0;
			Active[509] <= 1'b0;
			Active[510] <= 1'b0;
			Active[511] <= 1'b0;
		*/
		end else begin
			if (write) begin
				case (swizzleAddr[7:0])
				8'd0   : Active[  0] <= 1'b1;
				8'd1   : Active[  1] <= 1'b1;
				8'd2   : Active[  2] <= 1'b1;
				8'd3   : Active[  3] <= 1'b1;
				8'd4   : Active[  4] <= 1'b1;
				8'd5   : Active[  5] <= 1'b1;
				8'd6   : Active[  6] <= 1'b1;
				8'd7   : Active[  7] <= 1'b1;
				8'd8   : Active[  8] <= 1'b1;
				8'd9   : Active[  9] <= 1'b1;
				8'd10  : Active[ 10] <= 1'b1;
				8'd11  : Active[ 11] <= 1'b1;
				8'd12  : Active[ 12] <= 1'b1;
				8'd13  : Active[ 13] <= 1'b1;
				8'd14  : Active[ 14] <= 1'b1;
				8'd15  : Active[ 15] <= 1'b1;
				8'd16  : Active[ 16] <= 1'b1;
				8'd17  : Active[ 17] <= 1'b1;
				8'd18  : Active[ 18] <= 1'b1;
				8'd19  : Active[ 19] <= 1'b1;
				8'd20  : Active[ 20] <= 1'b1;
				8'd21  : Active[ 21] <= 1'b1;
				8'd22  : Active[ 22] <= 1'b1;
				8'd23  : Active[ 23] <= 1'b1;
				8'd24  : Active[ 24] <= 1'b1;
				8'd25  : Active[ 25] <= 1'b1;
				8'd26  : Active[ 26] <= 1'b1;
				8'd27  : Active[ 27] <= 1'b1;
				8'd28  : Active[ 28] <= 1'b1;
				8'd29  : Active[ 29] <= 1'b1;
				8'd30  : Active[ 30] <= 1'b1;
				8'd31  : Active[ 31] <= 1'b1;
				8'd32  : Active[ 32] <= 1'b1;
				8'd33  : Active[ 33] <= 1'b1;
				8'd34  : Active[ 34] <= 1'b1;
				8'd35  : Active[ 35] <= 1'b1;
				8'd36  : Active[ 36] <= 1'b1;
				8'd37  : Active[ 37] <= 1'b1;
				8'd38  : Active[ 38] <= 1'b1;
				8'd39  : Active[ 39] <= 1'b1;
				8'd40  : Active[ 40] <= 1'b1;
				8'd41  : Active[ 41] <= 1'b1;
				8'd42  : Active[ 42] <= 1'b1;
				8'd43  : Active[ 43] <= 1'b1;
				8'd44  : Active[ 44] <= 1'b1;
				8'd45  : Active[ 45] <= 1'b1;
				8'd46  : Active[ 46] <= 1'b1;
				8'd47  : Active[ 47] <= 1'b1;
				8'd48  : Active[ 48] <= 1'b1;
				8'd49  : Active[ 49] <= 1'b1;
				8'd50  : Active[ 50] <= 1'b1;
				8'd51  : Active[ 51] <= 1'b1;
				8'd52  : Active[ 52] <= 1'b1;
				8'd53  : Active[ 53] <= 1'b1;
				8'd54  : Active[ 54] <= 1'b1;
				8'd55  : Active[ 55] <= 1'b1;
				8'd56  : Active[ 56] <= 1'b1;
				8'd57  : Active[ 57] <= 1'b1;
				8'd58  : Active[ 58] <= 1'b1;
				8'd59  : Active[ 59] <= 1'b1;
				8'd60  : Active[ 60] <= 1'b1;
				8'd61  : Active[ 61] <= 1'b1;
				8'd62  : Active[ 62] <= 1'b1;
				8'd63  : Active[ 63] <= 1'b1;
				8'd64  : Active[ 64] <= 1'b1;
				8'd65  : Active[ 65] <= 1'b1;
				8'd66  : Active[ 66] <= 1'b1;
				8'd67  : Active[ 67] <= 1'b1;
				8'd68  : Active[ 68] <= 1'b1;
				8'd69  : Active[ 69] <= 1'b1;
				8'd70  : Active[ 70] <= 1'b1;
				8'd71  : Active[ 71] <= 1'b1;
				8'd72  : Active[ 72] <= 1'b1;
				8'd73  : Active[ 73] <= 1'b1;
				8'd74  : Active[ 74] <= 1'b1;
				8'd75  : Active[ 75] <= 1'b1;
				8'd76  : Active[ 76] <= 1'b1;
				8'd77  : Active[ 77] <= 1'b1;
				8'd78  : Active[ 78] <= 1'b1;
				8'd79  : Active[ 79] <= 1'b1;
				8'd80  : Active[ 80] <= 1'b1;
				8'd81  : Active[ 81] <= 1'b1;
				8'd82  : Active[ 82] <= 1'b1;
				8'd83  : Active[ 83] <= 1'b1;
				8'd84  : Active[ 84] <= 1'b1;
				8'd85  : Active[ 85] <= 1'b1;
				8'd86  : Active[ 86] <= 1'b1;
				8'd87  : Active[ 87] <= 1'b1;
				8'd88  : Active[ 88] <= 1'b1;
				8'd89  : Active[ 89] <= 1'b1;
				8'd90  : Active[ 90] <= 1'b1;
				8'd91  : Active[ 91] <= 1'b1;
				8'd92  : Active[ 92] <= 1'b1;
				8'd93  : Active[ 93] <= 1'b1;
				8'd94  : Active[ 94] <= 1'b1;
				8'd95  : Active[ 95] <= 1'b1;
				8'd96  : Active[ 96] <= 1'b1;
				8'd97  : Active[ 97] <= 1'b1;
				8'd98  : Active[ 98] <= 1'b1;
				8'd99  : Active[ 99] <= 1'b1;
				8'd100 : Active[100] <= 1'b1;
				8'd101 : Active[101] <= 1'b1;
				8'd102 : Active[102] <= 1'b1;
				8'd103 : Active[103] <= 1'b1;
				8'd104 : Active[104] <= 1'b1;
				8'd105 : Active[105] <= 1'b1;
				8'd106 : Active[106] <= 1'b1;
				8'd107 : Active[107] <= 1'b1;
				8'd108 : Active[108] <= 1'b1;
				8'd109 : Active[109] <= 1'b1;
				8'd110 : Active[110] <= 1'b1;
				8'd111 : Active[111] <= 1'b1;
				8'd112 : Active[112] <= 1'b1;
				8'd113 : Active[113] <= 1'b1;
				8'd114 : Active[114] <= 1'b1;
				8'd115 : Active[115] <= 1'b1;
				8'd116 : Active[116] <= 1'b1;
				8'd117 : Active[117] <= 1'b1;
				8'd118 : Active[118] <= 1'b1;
				8'd119 : Active[119] <= 1'b1;
				8'd120 : Active[120] <= 1'b1;
				8'd121 : Active[121] <= 1'b1;
				8'd122 : Active[122] <= 1'b1;
				8'd123 : Active[123] <= 1'b1;
				8'd124 : Active[124] <= 1'b1;
				8'd125 : Active[125] <= 1'b1;
				8'd126 : Active[126] <= 1'b1;
				8'd127 : Active[127] <= 1'b1;
				8'd128 : Active[128] <= 1'b1;
				8'd129 : Active[129] <= 1'b1;
				8'd130 : Active[130] <= 1'b1;
				8'd131 : Active[131] <= 1'b1;
				8'd132 : Active[132] <= 1'b1;
				8'd133 : Active[133] <= 1'b1;
				8'd134 : Active[134] <= 1'b1;
				8'd135 : Active[135] <= 1'b1;
				8'd136 : Active[136] <= 1'b1;
				8'd137 : Active[137] <= 1'b1;
				8'd138 : Active[138] <= 1'b1;
				8'd139 : Active[139] <= 1'b1;
				8'd140 : Active[140] <= 1'b1;
				8'd141 : Active[141] <= 1'b1;
				8'd142 : Active[142] <= 1'b1;
				8'd143 : Active[143] <= 1'b1;
				8'd144 : Active[144] <= 1'b1;
				8'd145 : Active[145] <= 1'b1;
				8'd146 : Active[146] <= 1'b1;
				8'd147 : Active[147] <= 1'b1;
				8'd148 : Active[148] <= 1'b1;
				8'd149 : Active[149] <= 1'b1;
				8'd150 : Active[150] <= 1'b1;
				8'd151 : Active[151] <= 1'b1;
				8'd152 : Active[152] <= 1'b1;
				8'd153 : Active[153] <= 1'b1;
				8'd154 : Active[154] <= 1'b1;
				8'd155 : Active[155] <= 1'b1;
				8'd156 : Active[156] <= 1'b1;
				8'd157 : Active[157] <= 1'b1;
				8'd158 : Active[158] <= 1'b1;
				8'd159 : Active[159] <= 1'b1;
				8'd160 : Active[160] <= 1'b1;
				8'd161 : Active[161] <= 1'b1;
				8'd162 : Active[162] <= 1'b1;
				8'd163 : Active[163] <= 1'b1;
				8'd164 : Active[164] <= 1'b1;
				8'd165 : Active[165] <= 1'b1;
				8'd166 : Active[166] <= 1'b1;
				8'd167 : Active[167] <= 1'b1;
				8'd168 : Active[168] <= 1'b1;
				8'd169 : Active[169] <= 1'b1;
				8'd170 : Active[170] <= 1'b1;
				8'd171 : Active[171] <= 1'b1;
				8'd172 : Active[172] <= 1'b1;
				8'd173 : Active[173] <= 1'b1;
				8'd174 : Active[174] <= 1'b1;
				8'd175 : Active[175] <= 1'b1;
				8'd176 : Active[176] <= 1'b1;
				8'd177 : Active[177] <= 1'b1;
				8'd178 : Active[178] <= 1'b1;
				8'd179 : Active[179] <= 1'b1;
				8'd180 : Active[180] <= 1'b1;
				8'd181 : Active[181] <= 1'b1;
				8'd182 : Active[182] <= 1'b1;
				8'd183 : Active[183] <= 1'b1;
				8'd184 : Active[184] <= 1'b1;
				8'd185 : Active[185] <= 1'b1;
				8'd186 : Active[186] <= 1'b1;
				8'd187 : Active[187] <= 1'b1;
				8'd188 : Active[188] <= 1'b1;
				8'd189 : Active[189] <= 1'b1;
				8'd190 : Active[190] <= 1'b1;
				8'd191 : Active[191] <= 1'b1;
				8'd192 : Active[192] <= 1'b1;
				8'd193 : Active[193] <= 1'b1;
				8'd194 : Active[194] <= 1'b1;
				8'd195 : Active[195] <= 1'b1;
				8'd196 : Active[196] <= 1'b1;
				8'd197 : Active[197] <= 1'b1;
				8'd198 : Active[198] <= 1'b1;
				8'd199 : Active[199] <= 1'b1;
				8'd200 : Active[200] <= 1'b1;
				8'd201 : Active[201] <= 1'b1;
				8'd202 : Active[202] <= 1'b1;
				8'd203 : Active[203] <= 1'b1;
				8'd204 : Active[204] <= 1'b1;
				8'd205 : Active[205] <= 1'b1;
				8'd206 : Active[206] <= 1'b1;
				8'd207 : Active[207] <= 1'b1;
				8'd208 : Active[208] <= 1'b1;
				8'd209 : Active[209] <= 1'b1;
				8'd210 : Active[210] <= 1'b1;
				8'd211 : Active[211] <= 1'b1;
				8'd212 : Active[212] <= 1'b1;
				8'd213 : Active[213] <= 1'b1;
				8'd214 : Active[214] <= 1'b1;
				8'd215 : Active[215] <= 1'b1;
				8'd216 : Active[216] <= 1'b1;
				8'd217 : Active[217] <= 1'b1;
				8'd218 : Active[218] <= 1'b1;
				8'd219 : Active[219] <= 1'b1;
				8'd220 : Active[220] <= 1'b1;
				8'd221 : Active[221] <= 1'b1;
				8'd222 : Active[222] <= 1'b1;
				8'd223 : Active[223] <= 1'b1;
				8'd224 : Active[224] <= 1'b1;
				8'd225 : Active[225] <= 1'b1;
				8'd226 : Active[226] <= 1'b1;
				8'd227 : Active[227] <= 1'b1;
				8'd228 : Active[228] <= 1'b1;
				8'd229 : Active[229] <= 1'b1;
				8'd230 : Active[230] <= 1'b1;
				8'd231 : Active[231] <= 1'b1;
				8'd232 : Active[232] <= 1'b1;
				8'd233 : Active[233] <= 1'b1;
				8'd234 : Active[234] <= 1'b1;
				8'd235 : Active[235] <= 1'b1;
				8'd236 : Active[236] <= 1'b1;
				8'd237 : Active[237] <= 1'b1;
				8'd238 : Active[238] <= 1'b1;
				8'd239 : Active[239] <= 1'b1;
				8'd240 : Active[240] <= 1'b1;
				8'd241 : Active[241] <= 1'b1;
				8'd242 : Active[242] <= 1'b1;
				8'd243 : Active[243] <= 1'b1;
				8'd244 : Active[244] <= 1'b1;
				8'd245 : Active[245] <= 1'b1;
				8'd246 : Active[246] <= 1'b1;
				8'd247 : Active[247] <= 1'b1;
				8'd248 : Active[248] <= 1'b1;
				8'd249 : Active[249] <= 1'b1;
				8'd250 : Active[250] <= 1'b1;
				8'd251 : Active[251] <= 1'b1;
				8'd252 : Active[252] <= 1'b1;
				8'd253 : Active[253] <= 1'b1;
				8'd254 : Active[254] <= 1'b1;
				8'd255 : Active[255] <= 1'b1;
			/* 4 KB Version
				9'd256 : Active[256] <= 1'b1;
				9'd257 : Active[257] <= 1'b1;
				9'd258 : Active[258] <= 1'b1;
				9'd259 : Active[259] <= 1'b1;
				9'd260 : Active[260] <= 1'b1;
				9'd261 : Active[261] <= 1'b1;
				9'd262 : Active[262] <= 1'b1;
				9'd263 : Active[263] <= 1'b1;
				9'd264 : Active[264] <= 1'b1;
				9'd265 : Active[265] <= 1'b1;
				9'd266 : Active[266] <= 1'b1;
				9'd267 : Active[267] <= 1'b1;
				9'd268 : Active[268] <= 1'b1;
				9'd269 : Active[269] <= 1'b1;
				9'd270 : Active[270] <= 1'b1;
				9'd271 : Active[271] <= 1'b1;
				9'd272 : Active[272] <= 1'b1;
				9'd273 : Active[273] <= 1'b1;
				9'd274 : Active[274] <= 1'b1;
				9'd275 : Active[275] <= 1'b1;
				9'd276 : Active[276] <= 1'b1;
				9'd277 : Active[277] <= 1'b1;
				9'd278 : Active[278] <= 1'b1;
				9'd279 : Active[279] <= 1'b1;
				9'd280 : Active[280] <= 1'b1;
				9'd281 : Active[281] <= 1'b1;
				9'd282 : Active[282] <= 1'b1;
				9'd283 : Active[283] <= 1'b1;
				9'd284 : Active[284] <= 1'b1;
				9'd285 : Active[285] <= 1'b1;
				9'd286 : Active[286] <= 1'b1;
				9'd287 : Active[287] <= 1'b1;
				9'd288 : Active[288] <= 1'b1;
				9'd289 : Active[289] <= 1'b1;
				9'd290 : Active[290] <= 1'b1;
				9'd291 : Active[291] <= 1'b1;
				9'd292 : Active[292] <= 1'b1;
				9'd293 : Active[293] <= 1'b1;
				9'd294 : Active[294] <= 1'b1;
				9'd295 : Active[295] <= 1'b1;
				9'd296 : Active[296] <= 1'b1;
				9'd297 : Active[297] <= 1'b1;
				9'd298 : Active[298] <= 1'b1;
				9'd299 : Active[299] <= 1'b1;
				9'd300 : Active[300] <= 1'b1;
				9'd301 : Active[301] <= 1'b1;
				9'd302 : Active[302] <= 1'b1;
				9'd303 : Active[303] <= 1'b1;
				9'd304 : Active[304] <= 1'b1;
				9'd305 : Active[305] <= 1'b1;
				9'd306 : Active[306] <= 1'b1;
				9'd307 : Active[307] <= 1'b1;
				9'd308 : Active[308] <= 1'b1;
				9'd309 : Active[309] <= 1'b1;
				9'd310 : Active[310] <= 1'b1;
				9'd311 : Active[311] <= 1'b1;
				9'd312 : Active[312] <= 1'b1;
				9'd313 : Active[313] <= 1'b1;
				9'd314 : Active[314] <= 1'b1;
				9'd315 : Active[315] <= 1'b1;
				9'd316 : Active[316] <= 1'b1;
				9'd317 : Active[317] <= 1'b1;
				9'd318 : Active[318] <= 1'b1;
				9'd319 : Active[319] <= 1'b1;
				9'd320 : Active[320] <= 1'b1;
				9'd321 : Active[321] <= 1'b1;
				9'd322 : Active[322] <= 1'b1;
				9'd323 : Active[323] <= 1'b1;
				9'd324 : Active[324] <= 1'b1;
				9'd325 : Active[325] <= 1'b1;
				9'd326 : Active[326] <= 1'b1;
				9'd327 : Active[327] <= 1'b1;
				9'd328 : Active[328] <= 1'b1;
				9'd329 : Active[329] <= 1'b1;
				9'd330 : Active[330] <= 1'b1;
				9'd331 : Active[331] <= 1'b1;
				9'd332 : Active[332] <= 1'b1;
				9'd333 : Active[333] <= 1'b1;
				9'd334 : Active[334] <= 1'b1;
				9'd335 : Active[335] <= 1'b1;
				9'd336 : Active[336] <= 1'b1;
				9'd337 : Active[337] <= 1'b1;
				9'd338 : Active[338] <= 1'b1;
				9'd339 : Active[339] <= 1'b1;
				9'd340 : Active[340] <= 1'b1;
				9'd341 : Active[341] <= 1'b1;
				9'd342 : Active[342] <= 1'b1;
				9'd343 : Active[343] <= 1'b1;
				9'd344 : Active[344] <= 1'b1;
				9'd345 : Active[345] <= 1'b1;
				9'd346 : Active[346] <= 1'b1;
				9'd347 : Active[347] <= 1'b1;
				9'd348 : Active[348] <= 1'b1;
				9'd349 : Active[349] <= 1'b1;
				9'd350 : Active[350] <= 1'b1;
				9'd351 : Active[351] <= 1'b1;
				9'd352 : Active[352] <= 1'b1;
				9'd353 : Active[353] <= 1'b1;
				9'd354 : Active[354] <= 1'b1;
				9'd355 : Active[355] <= 1'b1;
				9'd356 : Active[356] <= 1'b1;
				9'd357 : Active[357] <= 1'b1;
				9'd358 : Active[358] <= 1'b1;
				9'd359 : Active[359] <= 1'b1;
				9'd360 : Active[360] <= 1'b1;
				9'd361 : Active[361] <= 1'b1;
				9'd362 : Active[362] <= 1'b1;
				9'd363 : Active[363] <= 1'b1;
				9'd364 : Active[364] <= 1'b1;
				9'd365 : Active[365] <= 1'b1;
				9'd366 : Active[366] <= 1'b1;
				9'd367 : Active[367] <= 1'b1;
				9'd368 : Active[368] <= 1'b1;
				9'd369 : Active[369] <= 1'b1;
				9'd370 : Active[370] <= 1'b1;
				9'd371 : Active[371] <= 1'b1;
				9'd372 : Active[372] <= 1'b1;
				9'd373 : Active[373] <= 1'b1;
				9'd374 : Active[374] <= 1'b1;
				9'd375 : Active[375] <= 1'b1;
				9'd376 : Active[376] <= 1'b1;
				9'd377 : Active[377] <= 1'b1;
				9'd378 : Active[378] <= 1'b1;
				9'd379 : Active[379] <= 1'b1;
				9'd380 : Active[380] <= 1'b1;
				9'd381 : Active[381] <= 1'b1;
				9'd382 : Active[382] <= 1'b1;
				9'd383 : Active[383] <= 1'b1;
				9'd384 : Active[384] <= 1'b1;
				9'd385 : Active[385] <= 1'b1;
				9'd386 : Active[386] <= 1'b1;
				9'd387 : Active[387] <= 1'b1;
				9'd388 : Active[388] <= 1'b1;
				9'd389 : Active[389] <= 1'b1;
				9'd390 : Active[390] <= 1'b1;
				9'd391 : Active[391] <= 1'b1;
				9'd392 : Active[392] <= 1'b1;
				9'd393 : Active[393] <= 1'b1;
				9'd394 : Active[394] <= 1'b1;
				9'd395 : Active[395] <= 1'b1;
				9'd396 : Active[396] <= 1'b1;
				9'd397 : Active[397] <= 1'b1;
				9'd398 : Active[398] <= 1'b1;
				9'd399 : Active[399] <= 1'b1;
				9'd400 : Active[400] <= 1'b1;
				9'd401 : Active[401] <= 1'b1;
				9'd402 : Active[402] <= 1'b1;
				9'd403 : Active[403] <= 1'b1;
				9'd404 : Active[404] <= 1'b1;
				9'd405 : Active[405] <= 1'b1;
				9'd406 : Active[406] <= 1'b1;
				9'd407 : Active[407] <= 1'b1;
				9'd408 : Active[408] <= 1'b1;
				9'd409 : Active[409] <= 1'b1;
				9'd410 : Active[410] <= 1'b1;
				9'd411 : Active[411] <= 1'b1;
				9'd412 : Active[412] <= 1'b1;
				9'd413 : Active[413] <= 1'b1;
				9'd414 : Active[414] <= 1'b1;
				9'd415 : Active[415] <= 1'b1;
				9'd416 : Active[416] <= 1'b1;
				9'd417 : Active[417] <= 1'b1;
				9'd418 : Active[418] <= 1'b1;
				9'd419 : Active[419] <= 1'b1;
				9'd420 : Active[420] <= 1'b1;
				9'd421 : Active[421] <= 1'b1;
				9'd422 : Active[422] <= 1'b1;
				9'd423 : Active[423] <= 1'b1;
				9'd424 : Active[424] <= 1'b1;
				9'd425 : Active[425] <= 1'b1;
				9'd426 : Active[426] <= 1'b1;
				9'd427 : Active[427] <= 1'b1;
				9'd428 : Active[428] <= 1'b1;
				9'd429 : Active[429] <= 1'b1;
				9'd430 : Active[430] <= 1'b1;
				9'd431 : Active[431] <= 1'b1;
				9'd432 : Active[432] <= 1'b1;
				9'd433 : Active[433] <= 1'b1;
				9'd434 : Active[434] <= 1'b1;
				9'd435 : Active[435] <= 1'b1;
				9'd436 : Active[436] <= 1'b1;
				9'd437 : Active[437] <= 1'b1;
				9'd438 : Active[438] <= 1'b1;
				9'd439 : Active[439] <= 1'b1;
				9'd440 : Active[440] <= 1'b1;
				9'd441 : Active[441] <= 1'b1;
				9'd442 : Active[442] <= 1'b1;
				9'd443 : Active[443] <= 1'b1;
				9'd444 : Active[444] <= 1'b1;
				9'd445 : Active[445] <= 1'b1;
				9'd446 : Active[446] <= 1'b1;
				9'd447 : Active[447] <= 1'b1;
				9'd448 : Active[448] <= 1'b1;
				9'd449 : Active[449] <= 1'b1;
				9'd450 : Active[450] <= 1'b1;
				9'd451 : Active[451] <= 1'b1;
				9'd452 : Active[452] <= 1'b1;
				9'd453 : Active[453] <= 1'b1;
				9'd454 : Active[454] <= 1'b1;
				9'd455 : Active[455] <= 1'b1;
				9'd456 : Active[456] <= 1'b1;
				9'd457 : Active[457] <= 1'b1;
				9'd458 : Active[458] <= 1'b1;
				9'd459 : Active[459] <= 1'b1;
				9'd460 : Active[460] <= 1'b1;
				9'd461 : Active[461] <= 1'b1;
				9'd462 : Active[462] <= 1'b1;
				9'd463 : Active[463] <= 1'b1;
				9'd464 : Active[464] <= 1'b1;
				9'd465 : Active[465] <= 1'b1;
				9'd466 : Active[466] <= 1'b1;
				9'd467 : Active[467] <= 1'b1;
				9'd468 : Active[468] <= 1'b1;
				9'd469 : Active[469] <= 1'b1;
				9'd470 : Active[470] <= 1'b1;
				9'd471 : Active[471] <= 1'b1;
				9'd472 : Active[472] <= 1'b1;
				9'd473 : Active[473] <= 1'b1;
				9'd474 : Active[474] <= 1'b1;
				9'd475 : Active[475] <= 1'b1;
				9'd476 : Active[476] <= 1'b1;
				9'd477 : Active[477] <= 1'b1;
				9'd478 : Active[478] <= 1'b1;
				9'd479 : Active[479] <= 1'b1;
				9'd480 : Active[480] <= 1'b1;
				9'd481 : Active[481] <= 1'b1;
				9'd482 : Active[482] <= 1'b1;
				9'd483 : Active[483] <= 1'b1;
				9'd484 : Active[484] <= 1'b1;
				9'd485 : Active[485] <= 1'b1;
				9'd486 : Active[486] <= 1'b1;
				9'd487 : Active[487] <= 1'b1;
				9'd488 : Active[488] <= 1'b1;
				9'd489 : Active[489] <= 1'b1;
				9'd490 : Active[490] <= 1'b1;
				9'd491 : Active[491] <= 1'b1;
				9'd492 : Active[492] <= 1'b1;
				9'd493 : Active[493] <= 1'b1;
				9'd494 : Active[494] <= 1'b1;
				9'd495 : Active[495] <= 1'b1;
				9'd496 : Active[496] <= 1'b1;
				9'd497 : Active[497] <= 1'b1;
				9'd498 : Active[498] <= 1'b1;
				9'd499 : Active[499] <= 1'b1;
				9'd500 : Active[500] <= 1'b1;
				9'd501 : Active[501] <= 1'b1;
				9'd502 : Active[502] <= 1'b1;
				9'd503 : Active[503] <= 1'b1;
				9'd504 : Active[504] <= 1'b1;
				9'd505 : Active[505] <= 1'b1;
				9'd506 : Active[506] <= 1'b1;
				9'd507 : Active[507] <= 1'b1;
				9'd508 : Active[508] <= 1'b1;
				9'd509 : Active[509] <= 1'b1;
				9'd510 : Active[510] <= 1'b1;
				9'd511 : Active[511] <= 1'b1;
			*/
				endcase
			end // End write
		end

		pIndexA	<= adressLookA[1:0];
		pIndexB	<= adressLookB[1:0];
	end
endmodule
