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
wire [1:0] idx;
wire [8:0] romAdr = idx[1] ? {!idx[0], ~interp} : { idx[0], interp };
wire signed[15:0] ratio;

instanceInterpROM InterpROM(
	.clk	(i_clk),
	.adr	(romAdr),
	.data	(ratio)
);
