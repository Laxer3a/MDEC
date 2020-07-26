/*
	---------------------------------------------
		Playstation GTE Fast Unsigned Division
	---------------------------------------------

	Here is the specification according to No$PSX Documentation.
	----------------------------------------------------------

	GTE Division Inaccuracy (for RTPS/RTPT commands)
	Basically, the GTE division does (attempt to) work as so (using 33bit maths):
		n = (((H*20000h/SZ3)+1)/2)
	alternatively, below would give (almost) the same result (using 32bit maths):
		n = ((H*10000h+SZ3/2)/SZ3)
	in both cases, the result is saturated about as so:
		if n>1FFFFh or division_by_zero then n=1FFFFh, FLAG.Bit17=1, FLAG.Bit31=1
  
	"However, the real GTE hardware is using a fast, but less accurate division mechanism (based on Unsigned Newton-Raphson (UNR) algorithm):

	if (H < SZ3*2) then                            ;check if overflow
		z = count_leading_zeroes(SZ3)                ;z=0..0Fh (for 16bit SZ3)
		n = (H SHL z)                                ;n=0..7FFF8000h
		d = (SZ3 SHL z)                              ;d=8000h..FFFFh
		u = unr_table[(d-7FC0h) SHR 7] + 101h        ;u=200h..101h
		d = ((2000080h - (d * u)) SHR 8)             ;d=10000h..0FF01h
		d = ((0000080h + (d * u)) SHR 8)             ;d=20000h..10000h
		n = min(1FFFFh, (((n*d) + 8000h) SHR 16))    ;n=0..1FFFFh
	else n = 1FFFFh, FLAG.Bit17=1, FLAG.Bit31=1    ;n=1FFFFh plus overflow flag "

	the GTE's unr_table[000h..100h] consists of following values:

	  FFh,FDh,FBh,F9h,F7h,F5h,F3h,F1h,EFh,EEh,ECh,EAh,E8h,E6h,E4h,E3h ;\
	  E1h,DFh,DDh,DCh,DAh,D8h,D6h,D5h,D3h,D1h,D0h,CEh,CDh,CBh,C9h,C8h ; 00h..3Fh
	  C6h,C5h,C3h,C1h,C0h,BEh,BDh,BBh,BAh,B8h,B7h,B5h,B4h,B2h,B1h,B0h ;
	  AEh,ADh,ABh,AAh,A9h,A7h,A6h,A4h,A3h,A2h,A0h,9Fh,9Eh,9Ch,9Bh,9Ah ;/
	  99h,97h,96h,95h,94h,92h,91h,90h,8Fh,8Dh,8Ch,8Bh,8Ah,89h,87h,86h ;\
	  85h,84h,83h,82h,81h,7Fh,7Eh,7Dh,7Ch,7Bh,7Ah,79h,78h,77h,75h,74h ; 40h..7Fh
	  73h,72h,71h,70h,6Fh,6Eh,6Dh,6Ch,6Bh,6Ah,69h,68h,67h,66h,65h,64h ;
	  63h,62h,61h,60h,5Fh,5Eh,5Dh,5Dh,5Ch,5Bh,5Ah,59h,58h,57h,56h,55h ;/
	  54h,53h,53h,52h,51h,50h,4Fh,4Eh,4Dh,4Dh,4Ch,4Bh,4Ah,49h,48h,48h ;\
	  47h,46h,45h,44h,43h,43h,42h,41h,40h,3Fh,3Fh,3Eh,3Dh,3Ch,3Ch,3Bh ; 80h..BFh
	  3Ah,39h,39h,38h,37h,36h,36h,35h,34h,33h,33h,32h,31h,31h,30h,2Fh ;
	  2Eh,2Eh,2Dh,2Ch,2Ch,2Bh,2Ah,2Ah,29h,28h,28h,27h,26h,26h,25h,24h ;/
	  24h,23h,22h,22h,21h,20h,20h,1Fh,1Eh,1Eh,1Dh,1Dh,1Ch,1Bh,1Bh,1Ah ;\
	  19h,19h,18h,18h,17h,16h,16h,15h,15h,14h,14h,13h,12h,12h,11h,11h ; C0h..FFh
	  10h,0Fh,0Fh,0Eh,0Eh,0Dh,0Dh,0Ch,0Ch,0Bh,0Ah,0Ah,09h,09h,08h,08h ;
	  07h,07h,06h,06h,05h,05h,04h,04h,03h,03h,02h,02h,01h,01h,00h,00h ;/
	  00h    ;<-- one extra table entry (for "(d-7FC0h)/80h"=100h)    ;-100h

	Above can be generated as "unr_table[i]=min(0,(40000h/(i+100h)+1)/2-101h)".
	Some special cases: NNNNh/0001h uses a big multiplier (d=20000h), in practice, this can occur only for 0000h/0001h and 0001h/0001h (due to the H<SZ3*2 overflow check).
	The min(1FFFFh) limit is needed for cases like FE3Fh/7F20h, F015h/780Bh, etc. (these do produce UNR result 20000h, and are saturated to 1FFFFh, but without setting overflow FLAG bits).

	From Reddit, an interesting anecdote worth pasting here :
	----------------------------------------------------------
	"Anecdote time: This information cost someone his job! Back in the day, the main technical support mechanism for PSX devs was private newsgroups (remember them!) 
	running on a Sony news server. It was common to use the same app (e.g. Outlook Express) to both send emails and read newsgroups, and if you weren't careful 
	you could send a mail to both an email address and a newsgroup at the same time. That's what happened here!

	Someone else had discovered a quirk of the RTPS opcode and documented his findings, and then this guy had leaked the information to an emulator developer, 
	passing it off as his own research, and then accidentally copying it to the Sony newsgroup, for all the devs and Sony support team to see. 
	News servers had to be configured to handle 'delete requests', and this one wasn't, so the post was there for all to see, publicly shaming the leaker (who would've been under NDA) 
	and presumably quickly leading to his company losing their PSX development licence, and naturally his dismissal. 
	Amusingly I think what riled some people most was not that he was leaking confidential technical details, but that he was passing someone else's research off as his own! 
	Funny times. But I guess we ought to consider him a hero now, as this information would have been long lost otherwise!"
	
	---------------------------------------------
	Hardware will do the bit 31 outside from bit 17. So we output only the overflow bit.
	- Possible implementation / optimization : Use 2x Multiplier instead of Logarithmic Shifter.
	- For now, all combinatorial. Depending on specs, will probably pipeline some stages.
*/

module GTEFastDiv(
	input			i_clk,
	input [15:0]	h,			// Dividend
	input [15:0]	z3,			// Divisor
	output[16:0]	divRes,		// Result
	output          overflow	// Overflow bit
);

	//-----------------------------------------------
	//  Count 'h' Leading zero computation
	//-----------------------------------------------
	// Probably a bit smaller than a 16 bit priority encoder.
	// Faster too.
	reg [1:0] countT3,countT2,countT1,countT0;
	
	always @ (z3)
	casez(z3[15:12]) // Number of leading zero for [15:12]
		4'b0001: countT3 = 2'b11; 
		4'b001?: countT3 = 2'b10;
		4'b01??: countT3 = 2'b01;
		4'b1???: countT3 = 2'b00;
		default: countT3 = 2'b00;
	endcase
	wire anyOneT3 = |z3[15:12];
	

	always @ (z3)
	casez(z3[11:8]) // Number of leading zero for [11: 8]
		4'b0001: countT2 = 2'b11;
		4'b001?: countT2 = 2'b10;
		4'b01??: countT2 = 2'b01;
		4'b1???: countT2 = 2'b00;
		default: countT2 = 2'b00;
	endcase
	wire anyOneT2 = |z3[11:8];

	always @ (z3)
	casez(z3[7:4]) // Number of leading zero for [ 7: 4]
		4'b0001: countT1 = 2'b11;
		4'b001?: countT1 = 2'b10;
		4'b01??: countT1 = 2'b01;
		4'b1???: countT1 = 2'b00;
		default: countT1 = 2'b00;
	endcase
	wire anyOneT1 = |z3[7:4];

	always @ (z3)
	casez(z3[3:0]) // Number of leading zero for [ 3: 0]
		4'b0001: countT0 = 2'b11;
		4'b001?: countT0 = 2'b10;
		4'b01??: countT0 = 2'b01;
		4'b1???: countT0 = 2'b00;
		default: countT0 = 2'b00;
	endcase
	// NEVER USED : wire anyOneT0 = |z3[3:0];

	// Gather all leading zero generated in parallel and generate final value.
	reg [3:0] shiftAmount;
	always @ (*)
	begin
		if (anyOneT3)
			shiftAmount = { 2'b00 ,countT3 };
		else
		begin
			if (anyOneT2)
				shiftAmount = { 2'b01, countT2 };
			else
			begin
				if (anyOneT1)
					shiftAmount = { 2'b10, countT1 };
				else
					shiftAmount = { 2'b11, countT0 };
			end
		end
	end
	
	// ---------------------------------------------
	//   Z - 16 Bit Barrel Shifter (Could use a multiplier too)
	// ---------------------------------------------
	wire [15:0] b0	= shiftAmount[3] ? { z3[ 7:0], 8'd0 } : z3[15:0];	// 8 Bit Left Shift
	wire [15:0] b1	= shiftAmount[2] ? { b0[11:0], 4'd0 } : b0[15:0];	// 4 Bit Left Shift
	wire [15:0] b2	= shiftAmount[1] ? { b1[13:0], 2'd0 } : b1[15:0];	// 2 Bit Left Shift
	wire [15:0] b3	= shiftAmount[0] ? { b2[14:0], 1'd0 } : b2[15:0];	// 1 Bit Left Shift
	wire [15:0] d   = b3;	// [8000..FFFF]
	
	// ---------------------------------------------
	//   H - 16 to 31 Bit extending Barrel Shifter (Could use a multiplier too)
	// ---------------------------------------------
	wire [23:0] h0	= shiftAmount[3] ? {  h, 8'd0 } : { 8'd0, h  };	// 8 Bit Left Shift
	wire [27:0] h1	= shiftAmount[2] ? { h0, 4'd0 } : { 4'd0, h0 };	// 4 Bit Left Shift
	wire [29:0] h2	= shiftAmount[1] ? { h1, 2'd0 } : { 2'd0, h1 };	// 2 Bit Left Shift
	wire [30:0] h3	= shiftAmount[0] ? { h2, 1'd0 } : { 1'd0, h2 };	// 1 Bit Left Shift
	wire [30:0] n   = h3;	// [0..7FFF8000]

	// ---------------------------------------
	// Overflow is :
	// Condition     =  !(Z3*2 >  H   )
	// Equivalent to =>  (Z3*2 <= H   )
	// Equivalent to =>  (   H >= Z3*2)
	// ---------------------------------------
	wire ovf = ( { 1'b0,h } >= { z3,1'b0 } );
	
	// ---------------------------------------------
	// unr_table[(d-7FC0h) SHR 7] + 101h
	// ---------------------------------------------
	wire [15:0] ladr = d - 16'h7FC0; // [0x8000~0xFFFF] - 0x7FC0

	reg [15:0] pd;
	reg [30:0] pn;
	reg p_ovf;
	always @(posedge i_clk)
	begin
		pd <= d;
		pn <= n;
		p_ovf <= ovf;
	end
	
	// Declare the ROM variable
	reg [9:0] ram[511:0];
	reg [9:0] routData;

	// Replace LUT + ADDER RESULT INCLUDED !
	initial begin
		ram[0] = 10'd512; ram[1] = 10'd510; ram[2] = 10'd508; ram[3] = 10'd506; ram[4] = 10'd504; ram[5] = 10'd502; ram[6] = 10'd500; ram[7] = 10'd498;
		ram[8] = 10'd496; ram[9] = 10'd495; ram[10] = 10'd493; ram[11] = 10'd491; ram[12] = 10'd489; ram[13] = 10'd487; ram[14] = 10'd485; ram[15] = 10'd484;
		ram[16] = 10'd482; ram[17] = 10'd480; ram[18] = 10'd478; ram[19] = 10'd477; ram[20] = 10'd475; ram[21] = 10'd473; ram[22] = 10'd471; ram[23] = 10'd470;
		ram[24] = 10'd468; ram[25] = 10'd466; ram[26] = 10'd465; ram[27] = 10'd463; ram[28] = 10'd462; ram[29] = 10'd460; ram[30] = 10'd458; ram[31] = 10'd457;
		ram[32] = 10'd455; ram[33] = 10'd454; ram[34] = 10'd452; ram[35] = 10'd450; ram[36] = 10'd449; ram[37] = 10'd447; ram[38] = 10'd446; ram[39] = 10'd444;
		ram[40] = 10'd443; ram[41] = 10'd441; ram[42] = 10'd440; ram[43] = 10'd438; ram[44] = 10'd437; ram[45] = 10'd435; ram[46] = 10'd434; ram[47] = 10'd433;
		ram[48] = 10'd431; ram[49] = 10'd430; ram[50] = 10'd428; ram[51] = 10'd427; ram[52] = 10'd426; ram[53] = 10'd424; ram[54] = 10'd423; ram[55] = 10'd421;
		ram[56] = 10'd420; ram[57] = 10'd419; ram[58] = 10'd417; ram[59] = 10'd416; ram[60] = 10'd415; ram[61] = 10'd413; ram[62] = 10'd412; ram[63] = 10'd411;
		ram[64] = 10'd410; ram[65] = 10'd408; ram[66] = 10'd407; ram[67] = 10'd406; ram[68] = 10'd405; ram[69] = 10'd403; ram[70] = 10'd402; ram[71] = 10'd401;
		ram[72] = 10'd400; ram[73] = 10'd398; ram[74] = 10'd397; ram[75] = 10'd396; ram[76] = 10'd395; ram[77] = 10'd394; ram[78] = 10'd392; ram[79] = 10'd391;
		ram[80] = 10'd390; ram[81] = 10'd389; ram[82] = 10'd388; ram[83] = 10'd387; ram[84] = 10'd386; ram[85] = 10'd384; ram[86] = 10'd383; ram[87] = 10'd382;
		ram[88] = 10'd381; ram[89] = 10'd380; ram[90] = 10'd379; ram[91] = 10'd378; ram[92] = 10'd377; ram[93] = 10'd376; ram[94] = 10'd374; ram[95] = 10'd373;
		ram[96] = 10'd372; ram[97] = 10'd371; ram[98] = 10'd370; ram[99] = 10'd369; ram[100] = 10'd368; ram[101] = 10'd367; ram[102] = 10'd366; ram[103] = 10'd365;
		ram[104] = 10'd364; ram[105] = 10'd363; ram[106] = 10'd362; ram[107] = 10'd361; ram[108] = 10'd360; ram[109] = 10'd359; ram[110] = 10'd358; ram[111] = 10'd357;
		ram[112] = 10'd356; ram[113] = 10'd355; ram[114] = 10'd354; ram[115] = 10'd353; ram[116] = 10'd352; ram[117] = 10'd351; ram[118] = 10'd350; ram[119] = 10'd350;
		ram[120] = 10'd349; ram[121] = 10'd348; ram[122] = 10'd347; ram[123] = 10'd346; ram[124] = 10'd345; ram[125] = 10'd344; ram[126] = 10'd343; ram[127] = 10'd342;
		ram[128] = 10'd341; ram[129] = 10'd340; ram[130] = 10'd340; ram[131] = 10'd339; ram[132] = 10'd338; ram[133] = 10'd337; ram[134] = 10'd336; ram[135] = 10'd335;
		ram[136] = 10'd334; ram[137] = 10'd334; ram[138] = 10'd333; ram[139] = 10'd332; ram[140] = 10'd331; ram[141] = 10'd330; ram[142] = 10'd329; ram[143] = 10'd329;
		ram[144] = 10'd328; ram[145] = 10'd327; ram[146] = 10'd326; ram[147] = 10'd325; ram[148] = 10'd324; ram[149] = 10'd324; ram[150] = 10'd323; ram[151] = 10'd322;
		ram[152] = 10'd321; ram[153] = 10'd320; ram[154] = 10'd320; ram[155] = 10'd319; ram[156] = 10'd318; ram[157] = 10'd317; ram[158] = 10'd317; ram[159] = 10'd316;
		ram[160] = 10'd315; ram[161] = 10'd314; ram[162] = 10'd314; ram[163] = 10'd313; ram[164] = 10'd312; ram[165] = 10'd311; ram[166] = 10'd311; ram[167] = 10'd310;
		ram[168] = 10'd309; ram[169] = 10'd308; ram[170] = 10'd308; ram[171] = 10'd307; ram[172] = 10'd306; ram[173] = 10'd306; ram[174] = 10'd305; ram[175] = 10'd304;
		ram[176] = 10'd303; ram[177] = 10'd303; ram[178] = 10'd302; ram[179] = 10'd301; ram[180] = 10'd301; ram[181] = 10'd300; ram[182] = 10'd299; ram[183] = 10'd299;
		ram[184] = 10'd298; ram[185] = 10'd297; ram[186] = 10'd297; ram[187] = 10'd296; ram[188] = 10'd295; ram[189] = 10'd295; ram[190] = 10'd294; ram[191] = 10'd293;
		ram[192] = 10'd293; ram[193] = 10'd292; ram[194] = 10'd291; ram[195] = 10'd291; ram[196] = 10'd290; ram[197] = 10'd289; ram[198] = 10'd289; ram[199] = 10'd288;
		ram[200] = 10'd287; ram[201] = 10'd287; ram[202] = 10'd286; ram[203] = 10'd286; ram[204] = 10'd285; ram[205] = 10'd284; ram[206] = 10'd284; ram[207] = 10'd283;
		ram[208] = 10'd282; ram[209] = 10'd282; ram[210] = 10'd281; ram[211] = 10'd281; ram[212] = 10'd280; ram[213] = 10'd279; ram[214] = 10'd279; ram[215] = 10'd278;
		ram[216] = 10'd278; ram[217] = 10'd277; ram[218] = 10'd277; ram[219] = 10'd276; ram[220] = 10'd275; ram[221] = 10'd275; ram[222] = 10'd274; ram[223] = 10'd274;
		ram[224] = 10'd273; ram[225] = 10'd272; ram[226] = 10'd272; ram[227] = 10'd271; ram[228] = 10'd271; ram[229] = 10'd270; ram[230] = 10'd270; ram[231] = 10'd269;
		ram[232] = 10'd269; ram[233] = 10'd268; ram[234] = 10'd267; ram[235] = 10'd267; ram[236] = 10'd266; ram[237] = 10'd266; ram[238] = 10'd265; ram[239] = 10'd265;
		ram[240] = 10'd264; ram[241] = 10'd264; ram[242] = 10'd263; ram[243] = 10'd263; ram[244] = 10'd262; ram[245] = 10'd262; ram[246] = 10'd261; ram[247] = 10'd261;
		ram[248] = 10'd260; ram[249] = 10'd260; ram[250] = 10'd259; ram[251] = 10'd259; ram[252] = 10'd258; ram[253] = 10'd258; ram[254] = 10'd257; ram[255] = 10'd257;
		ram[256] = 10'd257;ram[257] = 10'd257;ram[258] = 10'd257;ram[259] = 10'd257;ram[260] = 10'd257;ram[261] = 10'd257;ram[262] = 10'd257;ram[263] = 10'd257;
		ram[264] = 10'd257;ram[265] = 10'd257;ram[266] = 10'd257;ram[267] = 10'd257;ram[268] = 10'd257;ram[269] = 10'd257;ram[270] = 10'd257;ram[271] = 10'd257;
		ram[272] = 10'd257;ram[273] = 10'd257;ram[274] = 10'd257;ram[275] = 10'd257;ram[276] = 10'd257;ram[277] = 10'd257;ram[278] = 10'd257;ram[279] = 10'd257;
		ram[280] = 10'd257;ram[281] = 10'd257;ram[282] = 10'd257;ram[283] = 10'd257;ram[284] = 10'd257;ram[285] = 10'd257;ram[286] = 10'd257;ram[287] = 10'd257;
		ram[288] = 10'd257;ram[289] = 10'd257;ram[290] = 10'd257;ram[291] = 10'd257;ram[292] = 10'd257;ram[293] = 10'd257;ram[294] = 10'd257;ram[295] = 10'd257;
		ram[296] = 10'd257;ram[297] = 10'd257;ram[298] = 10'd257;ram[299] = 10'd257;ram[300] = 10'd257;ram[301] = 10'd257;ram[302] = 10'd257;ram[303] = 10'd257;
		ram[304] = 10'd257;ram[305] = 10'd257;ram[306] = 10'd257;ram[307] = 10'd257;ram[308] = 10'd257;ram[309] = 10'd257;ram[310] = 10'd257;ram[311] = 10'd257;
		ram[312] = 10'd257;ram[313] = 10'd257;ram[314] = 10'd257;ram[315] = 10'd257;ram[316] = 10'd257;ram[317] = 10'd257;ram[318] = 10'd257;ram[319] = 10'd257;
		ram[320] = 10'd257;ram[321] = 10'd257;ram[322] = 10'd257;ram[323] = 10'd257;ram[324] = 10'd257;ram[325] = 10'd257;ram[326] = 10'd257;ram[327] = 10'd257;
		ram[328] = 10'd257;ram[329] = 10'd257;ram[330] = 10'd257;ram[331] = 10'd257;ram[332] = 10'd257;ram[333] = 10'd257;ram[334] = 10'd257;ram[335] = 10'd257;
		ram[336] = 10'd257;ram[337] = 10'd257;ram[338] = 10'd257;ram[339] = 10'd257;ram[340] = 10'd257;ram[341] = 10'd257;ram[342] = 10'd257;ram[343] = 10'd257;
		ram[344] = 10'd257;ram[345] = 10'd257;ram[346] = 10'd257;ram[347] = 10'd257;ram[348] = 10'd257;ram[349] = 10'd257;ram[350] = 10'd257;ram[351] = 10'd257;
		ram[352] = 10'd257;ram[353] = 10'd257;ram[354] = 10'd257;ram[355] = 10'd257;ram[356] = 10'd257;ram[357] = 10'd257;ram[358] = 10'd257;ram[359] = 10'd257;
		ram[360] = 10'd257;ram[361] = 10'd257;ram[362] = 10'd257;ram[363] = 10'd257;ram[364] = 10'd257;ram[365] = 10'd257;ram[366] = 10'd257;ram[367] = 10'd257;
		ram[368] = 10'd257;ram[369] = 10'd257;ram[370] = 10'd257;ram[371] = 10'd257;ram[372] = 10'd257;ram[373] = 10'd257;ram[374] = 10'd257;ram[375] = 10'd257;
		ram[376] = 10'd257;ram[377] = 10'd257;ram[378] = 10'd257;ram[379] = 10'd257;ram[380] = 10'd257;ram[381] = 10'd257;ram[382] = 10'd257;ram[383] = 10'd257;
		ram[384] = 10'd257;ram[385] = 10'd257;ram[386] = 10'd257;ram[387] = 10'd257;ram[388] = 10'd257;ram[389] = 10'd257;ram[390] = 10'd257;ram[391] = 10'd257;
		ram[392] = 10'd257;ram[393] = 10'd257;ram[394] = 10'd257;ram[395] = 10'd257;ram[396] = 10'd257;ram[397] = 10'd257;ram[398] = 10'd257;ram[399] = 10'd257;
		ram[400] = 10'd257;ram[401] = 10'd257;ram[402] = 10'd257;ram[403] = 10'd257;ram[404] = 10'd257;ram[405] = 10'd257;ram[406] = 10'd257;ram[407] = 10'd257;
		ram[408] = 10'd257;ram[409] = 10'd257;ram[410] = 10'd257;ram[411] = 10'd257;ram[412] = 10'd257;ram[413] = 10'd257;ram[414] = 10'd257;ram[415] = 10'd257;
		ram[416] = 10'd257;ram[417] = 10'd257;ram[418] = 10'd257;ram[419] = 10'd257;ram[420] = 10'd257;ram[421] = 10'd257;ram[422] = 10'd257;ram[423] = 10'd257;
		ram[424] = 10'd257;ram[425] = 10'd257;ram[426] = 10'd257;ram[427] = 10'd257;ram[428] = 10'd257;ram[429] = 10'd257;ram[430] = 10'd257;ram[431] = 10'd257;
		ram[432] = 10'd257;ram[433] = 10'd257;ram[434] = 10'd257;ram[435] = 10'd257;ram[436] = 10'd257;ram[437] = 10'd257;ram[438] = 10'd257;ram[439] = 10'd257;
		ram[440] = 10'd257;ram[441] = 10'd257;ram[442] = 10'd257;ram[443] = 10'd257;ram[444] = 10'd257;ram[445] = 10'd257;ram[446] = 10'd257;ram[447] = 10'd257;
		ram[448] = 10'd257;ram[449] = 10'd257;ram[450] = 10'd257;ram[451] = 10'd257;ram[452] = 10'd257;ram[453] = 10'd257;ram[454] = 10'd257;ram[455] = 10'd257;
		ram[456] = 10'd257;ram[457] = 10'd257;ram[458] = 10'd257;ram[459] = 10'd257;ram[460] = 10'd257;ram[461] = 10'd257;ram[462] = 10'd257;ram[463] = 10'd257;
		ram[464] = 10'd257;ram[465] = 10'd257;ram[466] = 10'd257;ram[467] = 10'd257;ram[468] = 10'd257;ram[469] = 10'd257;ram[470] = 10'd257;ram[471] = 10'd257;
		ram[472] = 10'd257;ram[473] = 10'd257;ram[474] = 10'd257;ram[475] = 10'd257;ram[476] = 10'd257;ram[477] = 10'd257;ram[478] = 10'd257;ram[479] = 10'd257;
		ram[480] = 10'd257;ram[481] = 10'd257;ram[482] = 10'd257;ram[483] = 10'd257;ram[484] = 10'd257;ram[485] = 10'd257;ram[486] = 10'd257;ram[487] = 10'd257;
		ram[488] = 10'd257;ram[489] = 10'd257;ram[490] = 10'd257;ram[491] = 10'd257;ram[492] = 10'd257;ram[493] = 10'd257;ram[494] = 10'd257;ram[495] = 10'd257;
		ram[496] = 10'd257;ram[497] = 10'd257;ram[498] = 10'd257;ram[499] = 10'd257;ram[500] = 10'd257;ram[501] = 10'd257;ram[502] = 10'd257;ram[503] = 10'd257;
		ram[504] = 10'd257;ram[505] = 10'd257;ram[506] = 10'd257;ram[507] = 10'd257;ram[508] = 10'd257;ram[509] = 10'd257;ram[510] = 10'd257;ram[511] = 10'd257;
	end

	always @ (posedge i_clk)
	begin
		routData <= ram[ladr[15:7]];
	end

	/*
	reg [7:0] lookup; // PUT HERE BECAUSE MODELSIM DID NOT LIKE AFTER !!!!
	always @(*)
	begin
		case (ladr[14:7])
		'd0   : lookup = 8'hff;  'd1  : lookup = 8'hfd; 'd2   : lookup = 8'hfb;  'd3  : lookup = 8'hf9;  'd4  : lookup = 8'hf7;  'd5  : lookup = 8'hf5;  'd6  : lookup = 8'hf3;  'd7  : lookup = 8'hf1;
		'd8   : lookup = 8'hef;  'd9  : lookup = 8'hee; 'd10  : lookup = 8'hec;  'd11 : lookup = 8'hea;  'd12 : lookup = 8'he8;  'd13 : lookup = 8'he6;  'd14 : lookup = 8'he4;  'd15 : lookup = 8'he3;
		'd16  : lookup = 8'he1;	 'd17 : lookup = 8'hdf;	'd18  : lookup = 8'hdd;	 'd19 : lookup = 8'hdc;  'd20 : lookup = 8'hda;  'd21 : lookup = 8'hd8;  'd22 : lookup = 8'hd6;  'd23 : lookup = 8'hd5;
		'd24  : lookup = 8'hd3;	 'd25 : lookup = 8'hd1;	'd26  : lookup = 8'hd0;	 'd27 : lookup = 8'hce;  'd28 : lookup = 8'hcd;  'd29 : lookup = 8'hcb;  'd30 : lookup = 8'hc9;  'd31 : lookup = 8'hc8;
		'd32  : lookup = 8'hc6;	 'd33 : lookup = 8'hc5;	'd34  : lookup = 8'hc3;	 'd35 : lookup = 8'hc1;  'd36 : lookup = 8'hc0;  'd37 : lookup = 8'hbe;  'd38 : lookup = 8'hbd;  'd39 : lookup = 8'hbb;
		'd40  : lookup = 8'hba;	 'd41 : lookup = 8'hb8;	'd42  : lookup = 8'hb7;	 'd43 : lookup = 8'hb5;  'd44 : lookup = 8'hb4;  'd45 : lookup = 8'hb2;  'd46 : lookup = 8'hb1;  'd47 : lookup = 8'hb0;
		'd48  : lookup = 8'hae;	 'd49 : lookup = 8'had;	'd50  : lookup = 8'hab;	 'd51 : lookup = 8'haa;  'd52 : lookup = 8'ha9;  'd53 : lookup = 8'ha7;  'd54 : lookup = 8'ha6;  'd55 : lookup = 8'ha4;
		'd56  : lookup = 8'ha3;	 'd57 : lookup = 8'ha2;	'd58  : lookup = 8'ha0;	 'd59 : lookup = 8'h9f;  'd60 : lookup = 8'h9e;  'd61 : lookup = 8'h9c;  'd62 : lookup = 8'h9b;  'd63 : lookup = 8'h9a;
		'd64  : lookup = 8'h99;	 'd65 : lookup = 8'h97;	'd66  : lookup = 8'h96;	 'd67 : lookup = 8'h95;  'd68 : lookup = 8'h94;  'd69 : lookup = 8'h92;  'd70 : lookup = 8'h91;  'd71 : lookup = 8'h90;
		'd72  : lookup = 8'h8f;	 'd73 : lookup = 8'h8d;	'd74  : lookup = 8'h8c;	 'd75 : lookup = 8'h8b;  'd76 : lookup = 8'h8a;  'd77 : lookup = 8'h89;  'd78 : lookup = 8'h87;  'd79 : lookup = 8'h86;
		'd80  : lookup = 8'h85;	 'd81 : lookup = 8'h84;	'd82  : lookup = 8'h83;	 'd83 : lookup = 8'h82;  'd84 : lookup = 8'h81;  'd85 : lookup = 8'h7f;  'd86 : lookup = 8'h7e;  'd87 : lookup = 8'h7d;
		'd88  : lookup = 8'h7c;	 'd89 : lookup = 8'h7b;	'd90  : lookup = 8'h7a;	 'd91 : lookup = 8'h79;  'd92 : lookup = 8'h78;  'd93 : lookup = 8'h77;  'd94 : lookup = 8'h75;  'd95 : lookup = 8'h74;
		'd96  : lookup = 8'h73;	 'd97 : lookup = 8'h72;	'd98  : lookup = 8'h71;	 'd99 : lookup = 8'h70; 'd100 : lookup = 8'h6f; 'd101 : lookup = 8'h6e; 'd102 : lookup = 8'h6d; 'd103 : lookup = 8'h6c;
		'd104 : lookup = 8'h6b; 'd105 : lookup = 8'h6a; 'd106 : lookup = 8'h69; 'd107 : lookup = 8'h68; 'd108 : lookup = 8'h67; 'd109 : lookup = 8'h66; 'd110 : lookup = 8'h65; 'd111 : lookup = 8'h64;
		'd112 : lookup = 8'h63; 'd113 : lookup = 8'h62; 'd114 : lookup = 8'h61; 'd115 : lookup = 8'h60; 'd116 : lookup = 8'h5f; 'd117 : lookup = 8'h5e; 'd118 : lookup = 8'h5d; 'd119 : lookup = 8'h5d;
		'd120 : lookup = 8'h5c; 'd121 : lookup = 8'h5b; 'd122 : lookup = 8'h5a; 'd123 : lookup = 8'h59; 'd124 : lookup = 8'h58; 'd125 : lookup = 8'h57; 'd126 : lookup = 8'h56; 'd127 : lookup = 8'h55;
		'd128 : lookup = 8'h54; 'd129 : lookup = 8'h53; 'd130 : lookup = 8'h53; 'd131 : lookup = 8'h52; 'd132 : lookup = 8'h51; 'd133 : lookup = 8'h50; 'd134 : lookup = 8'h4f; 'd135 : lookup = 8'h4e;
		'd136 : lookup = 8'h4d; 'd137 : lookup = 8'h4d; 'd138 : lookup = 8'h4c; 'd139 : lookup = 8'h4b; 'd140 : lookup = 8'h4a; 'd141 : lookup = 8'h49; 'd142 : lookup = 8'h48; 'd143 : lookup = 8'h48;
		'd144 : lookup = 8'h47; 'd145 : lookup = 8'h46; 'd146 : lookup = 8'h45; 'd147 : lookup = 8'h44; 'd148 : lookup = 8'h43; 'd149 : lookup = 8'h43; 'd150 : lookup = 8'h42; 'd151 : lookup = 8'h41;
		'd152 : lookup = 8'h40; 'd153 : lookup = 8'h3f; 'd154 : lookup = 8'h3f; 'd155 : lookup = 8'h3e; 'd156 : lookup = 8'h3d; 'd157 : lookup = 8'h3c; 'd158 : lookup = 8'h3c; 'd159 : lookup = 8'h3b;
		'd160 : lookup = 8'h3a; 'd161 : lookup = 8'h39; 'd162 : lookup = 8'h39; 'd163 : lookup = 8'h38; 'd164 : lookup = 8'h37; 'd165 : lookup = 8'h36; 'd166 : lookup = 8'h36; 'd167 : lookup = 8'h35;
		'd168 : lookup = 8'h34; 'd169 : lookup = 8'h33; 'd170 : lookup = 8'h33; 'd171 : lookup = 8'h32; 'd172 : lookup = 8'h31; 'd173 : lookup = 8'h31; 'd174 : lookup = 8'h30; 'd175 : lookup = 8'h2f;
		'd176 : lookup = 8'h2e; 'd177 : lookup = 8'h2e; 'd178 : lookup = 8'h2d; 'd179 : lookup = 8'h2c; 'd180 : lookup = 8'h2c; 'd181 : lookup = 8'h2b; 'd182 : lookup = 8'h2a; 'd183 : lookup = 8'h2a;
		'd184 : lookup = 8'h29; 'd185 : lookup = 8'h28; 'd186 : lookup = 8'h28; 'd187 : lookup = 8'h27; 'd188 : lookup = 8'h26; 'd189 : lookup = 8'h26; 'd190 : lookup = 8'h25; 'd191 : lookup = 8'h24;
		'd192 : lookup = 8'h24; 'd193 : lookup = 8'h23; 'd194 : lookup = 8'h22; 'd195 : lookup = 8'h22; 'd196 : lookup = 8'h21; 'd197 : lookup = 8'h20; 'd198 : lookup = 8'h20; 'd199 : lookup = 8'h1f;
		'd200 : lookup = 8'h1e; 'd201 : lookup = 8'h1e; 'd202 : lookup = 8'h1d; 'd203 : lookup = 8'h1d; 'd204 : lookup = 8'h1c; 'd205 : lookup = 8'h1b; 'd206 : lookup = 8'h1b; 'd207 : lookup = 8'h1a;
		'd208 : lookup = 8'h19; 'd209 : lookup = 8'h19; 'd210 : lookup = 8'h18; 'd211 : lookup = 8'h18; 'd212 : lookup = 8'h17; 'd213 : lookup = 8'h16; 'd214 : lookup = 8'h16; 'd215 : lookup = 8'h15;
		'd216 : lookup = 8'h15; 'd217 : lookup = 8'h14; 'd218 : lookup = 8'h14; 'd219 : lookup = 8'h13; 'd220 : lookup = 8'h12; 'd221 : lookup = 8'h12; 'd222 : lookup = 8'h11; 'd223 : lookup = 8'h11;
		'd224 : lookup = 8'h10; 'd225 : lookup = 8'h0f; 'd226 : lookup = 8'h0f; 'd227 : lookup = 8'h0e; 'd228 : lookup = 8'h0e; 'd229 : lookup = 8'h0d; 'd230 : lookup = 8'h0d; 'd231 : lookup = 8'h0c;
		'd232 : lookup = 8'h0c; 'd233 : lookup = 8'h0b; 'd234 : lookup = 8'h0a; 'd235 : lookup = 8'h0a; 'd236 : lookup = 8'h09; 'd237 : lookup = 8'h09; 'd238 : lookup = 8'h08; 'd239 : lookup = 8'h08;
		'd240 : lookup = 8'h07;	'd241 : lookup = 8'h07;	'd242 : lookup = 8'h06;	'd243 : lookup = 8'h06;	'd244 : lookup = 8'h05;	'd245 : lookup = 8'h05;	'd246 : lookup = 8'h04;	'd247 : lookup = 8'h04;
		'd248 : lookup = 8'h03;	'd249 : lookup = 8'h03;	'd250 : lookup = 8'h02;	'd251 : lookup = 8'h02;	'd252 : lookup = 8'h01;	'd253 : lookup = 8'h01;	'd254 : lookup = 8'h00;	'd255 : lookup = 8'h00;
		default: lookup = 8'h00;
	endcase
	end
	wire [7:0] uLUT  = ladr[15] ? 8'h00 : lookup;
	wire [9:0] u     = {2'b00,uLUT} + 10'h101;				// Output = [0x101..0x200] (need 10 bit because of 0x200 !)
	*/

	// ---------------------------------------------
	//   Stage 2
	// ---------------------------------------------
	// d = ((0x2000080 - (d * u)) >> 8); d=10000h..0FF01h
	wire [25:0] mdu1 = (pd*routData);				// .16x.10 = .26	Output [808000..0x1FFFE00]
	wire [25:0] dmdu1= 26'h2000080 - mdu1;			// Fix 25 Bit :     Output [ 0x280..0x17F8080]
	wire [16:0] d2 = dmdu1[24:8];					// Shr 8.			Output [   0x2..0x17F80  ]
	
	// ---------------------------------------------
	//   Stage 3
	// ---------------------------------------------
	// d = ((0x0000080 + (d * u)) >> 8); d=20000h..10000h
	wire [26:0] mdu2 = (d2*routData);				// .17x.10 = .27	Output [ 0x202..0x2FF0000] (but 26 bit should be enough)
	wire [19:0] dmdu2=  mdu2[26:7] + 1'b1; 			// Same as adding 0x80 then shift 7, less HW.
	wire [18:0] d3   = dmdu2[19:1];					// Then shift 1 again.
	
	reg [18:0] pd3;
	reg [30:0] ppn;
	reg pp_ovf;
	always @ (posedge i_clk)
	begin
		pd3 <= d3;
		ppn <= pn;
		pp_ovf <= p_ovf;
	end

	// ---------------------------------------------
	//   Stage 4
	// ---------------------------------------------
	// n = min(0x1FFFF, (((n*d) + 0x8000) >> 16)); // n=0..1FFFFh
	wire [49:0] mnd = ppn*pd3; 					// .31 x .19
	wire [34:0] shfm= mnd[49:15] + 1'b1;		// Remove 15 bit add 1 = same as add 0x8000 then shift 15.
	wire [33:0] shcp= shfm[34:1];

	wire 		isOver		= (|shcp[33:17]) | pp_ovf;		// Same as >= 0x20000, optimized comparison OR overflow bit set from comparison test.
	wire [16:0] outStage4	=   shcp[16: 0]  | {17{isOver}};// Saturated arithmetic, if over 0x2000 -> then all 0x1FFFF, else value.
	
	// + setup bit17 and bit 31:
	// 17   Divide overflow. RTPS/RTPT division result saturated to max=1FFFFh
	// 31	Error Flag (Bit30..23, and 18..13 ORed together) (Read only)
	// if n>1FFFFh or division_by_zero then n=1FFFFh, FLAG.Bit17=1, FLAG.Bit31=1

	// ---------------------------------------------
	//   Output
	// ---------------------------------------------
	assign divRes	= outStage4;
	assign overflow	= pp_ovf;
endmodule
