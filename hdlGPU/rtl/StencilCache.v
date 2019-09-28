module StencilCache(
	input			clk,
	input	[17:0]	addrWord,
	input			oddStencil,
	input			evenStencil,
	input			writeOdd,
	input			writeEven,
	
	output			oddStencilOut,
	output			evenStencilOut
);
	reg RAMCacheOdd [(2**17)-1:0];
	reg RAMCacheEven[(2**17)-1:0];
	reg [17:0] pAddrWord;
	always @ (posedge clk)
	begin
		if (writeOdd)
		begin RAMCacheOdd [addrWord] <= oddStencil; end
		if (writeEven)
		begin RAMCacheEven[addrWord] <= evenStencil; end
		
		pAddrWord <= addrWord;
	end
	
	assign oddStencilOut  = RAMCacheOdd [pAddrWord];
	assign evenStencilOut = RAMCacheEven[pAddrWord];
endmodule
