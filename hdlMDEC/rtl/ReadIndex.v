module ReadIndex(
	input			i_clk,
	input			i_nrst,
	
	input	[1:0]	format,
	input			isDMARead,
	
	input			i_readNext,
	output			o_reachedLast,
	output	[7:0]	o_readIdx,
	output	[7:0]	o_linearReadIdx
);
	reg [7:0] maxValue;
	reg [2:0] maxLoop;
	reg	[7:0] Index;
	reg [2:0] Loop;
	reg [4:0] LoopCnt;
	
	wire [2:0] nextLoop = Loop  + 3'd1;// i_readNext;
	wire [7:0] nextIndex= Index + 8'd1;// i_readNext;
	
	always @(*)
	begin
		case (format)
		0      : maxValue = 8'd8;   // 4 BIT                  
		1      : maxValue = 8'd16;  // 8 BIT
		2      : maxValue = 8'd192; // 24 BIT
		default: maxValue = 8'd128; // 15 BIT
		endcase
		
		case (format)
		0      : maxLoop  = 3'd0; // 4 BIT (Normal when 0 -> become 0)
		1      : maxLoop  = 3'd0; // 8 BIT (Normal when 0 -> become 0)
		2      : maxLoop  = 3'd6; // 24 BIT
		default: maxLoop  = 3'd4; // 15 BIT
		endcase
		
		if (isDMARead) begin
			case (format)
			3      : o_readIdx = { 1'd0, LoopCnt[4],LoopCnt[0],LoopCnt[3:1],Loop[1:0] };                        	// 15 BIT
			2      : o_readIdx = { 5'd0, Loop[2:0] } + (LoopCnt[0] ? 8'd0 : 8'd48) + (LoopCnt[4] ? 8'd96 : 8'd0);	// 24 BIT
			default: o_readIdx = Index;   // 4 BIT / 8 BIT                  
			endcase
		end else begin
			o_readIdx = Index;
		end
	end

	wire resetLoop = (nextIndex == maxValue);
	
	always @(posedge i_clk)
	begin
		if ((!i_nrst) || (i_readNext & resetLoop)) begin
			Index	<= 8'd0;
			Loop    <= 3'd0;
			LoopCnt	<= 5'd0;
		end else begin
			if (i_readNext) begin
				if (nextLoop == maxLoop) begin
					Loop    <= 3'd0;
					LoopCnt	<= LoopCnt + 5'd1;
				end else begin
					Loop    <= nextLoop;
				end

				Index	<= nextIndex;
			end
		end
	end
	assign o_linearReadIdx	= Index;
	assign o_reachedLast	= resetLoop;
endmodule
