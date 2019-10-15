module StencilCache(
	input			clk,
	input	[14:0]	addrWord,	// [19:0] : 1 MByte, [18:0] : 0.5 MegaHWord
								// Work by 16 HWord (pixels) => [14:0] 32k x 16 pixel block (32 byte => 16 bit cache)
	input	[15:0]	writeBitSelect,
	input	[15:0]	writeBitValue,
	
	output	[15:0]	StencilOut
);
	reg RAMCache00[(2**15)-1:0];
	reg RAMCache01[(2**15)-1:0];
	reg RAMCache02[(2**15)-1:0];
	reg RAMCache03[(2**15)-1:0];
	reg RAMCache04[(2**15)-1:0];
	reg RAMCache05[(2**15)-1:0];
	reg RAMCache06[(2**15)-1:0];
	reg RAMCache07[(2**15)-1:0];
	reg RAMCache08[(2**15)-1:0];
	reg RAMCache09[(2**15)-1:0];
	reg RAMCache10[(2**15)-1:0];
	reg RAMCache11[(2**15)-1:0];
	reg RAMCache12[(2**15)-1:0];
	reg RAMCache13[(2**15)-1:0];
	reg RAMCache14[(2**15)-1:0];
	reg RAMCache15[(2**15)-1:0];
	reg [14:0] pAddrWord;
	always @ (posedge clk)
	begin
		if (writeBitSelect[0])
		begin RAMCache00[addrWord] <= writeBitValue[0]; end
		if (writeBitSelect[1])
		begin RAMCache01[addrWord] <= writeBitValue[1]; end
		if (writeBitSelect[2])
		begin RAMCache02[addrWord] <= writeBitValue[2]; end
		if (writeBitSelect[3])
		begin RAMCache03[addrWord] <= writeBitValue[3]; end
		if (writeBitSelect[4])
		begin RAMCache04[addrWord] <= writeBitValue[4]; end
		if (writeBitSelect[5])
		begin RAMCache05[addrWord] <= writeBitValue[5]; end
		if (writeBitSelect[6])
		begin RAMCache06[addrWord] <= writeBitValue[6]; end
		if (writeBitSelect[7])
		begin RAMCache07[addrWord] <= writeBitValue[7]; end
		if (writeBitSelect[8])
		begin RAMCache08[addrWord] <= writeBitValue[8]; end
		if (writeBitSelect[9])
		begin RAMCache09[addrWord] <= writeBitValue[9]; end
		if (writeBitSelect[10])
		begin RAMCache10[addrWord] <= writeBitValue[10]; end
		if (writeBitSelect[11])
		begin RAMCache11[addrWord] <= writeBitValue[11]; end
		if (writeBitSelect[12])
		begin RAMCache12[addrWord] <= writeBitValue[12]; end
		if (writeBitSelect[13])
		begin RAMCache13[addrWord] <= writeBitValue[13]; end
		if (writeBitSelect[14])
		begin RAMCache14[addrWord] <= writeBitValue[14]; end
		if (writeBitSelect[15])
		begin RAMCache15[addrWord] <= writeBitValue[15]; end
		
		pAddrWord <= addrWord;
	end
	
	assign StencilOut[0]  = RAMCache00[pAddrWord];
	assign StencilOut[1]  = RAMCache01[pAddrWord];
	assign StencilOut[2]  = RAMCache02[pAddrWord];
	assign StencilOut[3]  = RAMCache03[pAddrWord];
	assign StencilOut[4]  = RAMCache04[pAddrWord];
	assign StencilOut[5]  = RAMCache05[pAddrWord];
	assign StencilOut[6]  = RAMCache06[pAddrWord];
	assign StencilOut[7]  = RAMCache07[pAddrWord];
	assign StencilOut[8]  = RAMCache08[pAddrWord];
	assign StencilOut[9]  = RAMCache09[pAddrWord];
	assign StencilOut[10] = RAMCache10[pAddrWord];
	assign StencilOut[11] = RAMCache11[pAddrWord];
	assign StencilOut[12] = RAMCache12[pAddrWord];
	assign StencilOut[13] = RAMCache13[pAddrWord];
	assign StencilOut[14] = RAMCache14[pAddrWord];
	assign StencilOut[15] = RAMCache15[pAddrWord];
endmodule
