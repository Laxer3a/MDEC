module RGB2Fifo(
	input	i_clk,
	input	i_nrst,
	
	input			i_wrtPix,
	input	[1:0]	format,
	input			setBit15,
	input   [7:0]	i_pixAdr,
	input	[7:0]	i_r,
	input	[7:0]	i_g,
	input	[7:0]	i_b,
	output			stopFill,

	input			i_readFifo,
	output			o_fifoHasData,
	output	[31:0]	o_dataOut
);
	// TODO C CHECK Can handle RGB or BGR order here. (easiest)
	wire [7:0]  R = i_r;
	wire [7:0]  G = i_g;
	wire [7:0]  B = i_b;
	wire       Cl = setBit15;
	
	reg	[2:0] count;
	reg pWrite;
	always @(posedge i_clk)
	begin
		if (i_nrst == 0) begin
			count  = 3'b000;
			pWrite = 0;
		end else begin
			pWrite = i_wrtPix;
			if (i_wrtPix) begin
				count = count + 3'd1;
			end
		end
	end

	reg [11:0] groupBits;
	
	always @(*)
	begin
		case(format) // (0=4bit, 1=8bit, 2=24bit, 3=15bit)
		// 4 BIT
		2'b00:
			case (count[2:0])
			3'd0: groupBits = 12'b00_00_00000001;
			3'd1: groupBits = 12'b00_00_00000010;
			3'd2: groupBits = 12'b00_00_00000100;
			3'd3: groupBits = 12'b00_00_00001000;
			3'd4: groupBits = 12'b00_00_00010000;
			3'd5: groupBits = 12'b00_00_00100000;
			3'd6: groupBits = 12'b00_00_01000000;
			3'd7: groupBits = 12'b10_00_10000000;
			endcase               
		// 8 BIT                  
		2'b01:                    
			case (count[1:0])
			2'd0: groupBits = 12'b00_00_00000011;
			2'd1: groupBits = 12'b00_00_00001100;
			2'd2: groupBits = 12'b00_00_00110000;
			2'd3: groupBits = 12'b10_00_11000000;
			endcase               
		// 24 BIT                 
		2'b10:                    
			case (count[1:0])
			2'd0: groupBits = 12'b00_00_00111111;
			2'd1: groupBits = 12'b10_01_11000000;
			2'd2: groupBits = 12'b01_10_00000011;
			2'd3: groupBits = 12'b10_00_11111100;
			endcase
		// 15 BIT
		2'b11:
			if (count[0])
				groupBits = 12'b00_00_00001111;
			else
				groupBits = 12'b10_00_11110000;
		endcase
	end

	wire [3:0] v0 = ((count[1:0]==2'd2) && (format==2'd2)) ? B[7:4] : R[7:4]; 

	reg  [3:0] v1;
	reg  [3:0] v2;
	reg  [3:0] v3;
	reg  [3:0] v4;
	reg  [3:0] v5;
	reg  [3:0] v6;
	reg  [3:0] v7;

	wire [3:0] GreyM = R[7:4];
	wire [3:0] GreyL = R[3:0];
	
	always @(*)
	begin
		case (format)
		0: v1 = GreyM;
		1: v1 = GreyL;
		2: v1 = (count[0]==0) ? R[3:0] : B[3:0];
		3: v1 = { R[3],G[7:5] };
		endcase
	end

	always @(*)
	begin
		case (format)
		0: v2 = GreyM;
		1: v2 = GreyM;
		2: v2 = (count[0]==0) ? G[7:4] : R[7:4];
		3: v2 = { G[4:3], B[7:6] };
		endcase
	end

	always @(*)
	begin
		case (format)
		0: v3 = GreyM;
		1: v3 = GreyL;
		2: v3 = (count[0]==0) ? G[3:0] : R[3:0];
		3: v3 = {B[5:3],Cl};
		endcase
	end

	always @(*)
	begin
		case (format)
		0: v4 = GreyM;
		1: v4 = GreyM;
		2: v4 = (count[0]==0) ? B[7:4] : G[7:4];
		3: v4 = R[7:4];
		endcase
	end
	
	always @(*)
	begin
		case (format)
		0: v5 = GreyM;
		1: v5 = GreyL;
		2: v5 = (count[0]==0) ? B[3:0] : G[3:0];
		3: v5 = { R[3],G[7:5] };
		endcase
	end
	
	always @(*)
	begin
		case (format)
		0: v6 = GreyM;
		1: v6 = GreyM;
		2: v6 = (count[1]==0) ? R[7:4] : B[7:4];
		3: v6 = { G[4:3], B[7:6] };
		endcase
	end
	
	always @(*)
	begin
		case (format)
		0: v7 = GreyM;
		1: v7 = GreyL;
		2: v7 = (count[1]==0) ? R[3:0] : B[3:0];
		3: v7 = {B[5:3],Cl};
		endcase
	end
	
	wire [15:0] v8 = { G, B };
	wire [15:0] v9 = { R, G };

	// One cycle later than groupBits[10] and [11] : pipelined.
//	reg pushReg1;
//	reg pushReg0;
	reg [31:0] reg0,reg1;
	
	always @(posedge i_clk)
	begin
		// i_wrtPix <-- no need for it.
		// we just write forever until the correct data arrive and bit state change.
		
//		pushReg1 <= groupBits[10];
//		pushReg0 <= groupBits[11];
		if (groupBits[0])
			reg0[31:28] = v0;
		if (groupBits[1])
			reg0[27:24] = v1;
		if (groupBits[2])
			reg0[23:20] = v2;
		if (groupBits[3])
			reg0[19:16] = v3;
		if (groupBits[4])
			reg0[15:12] = v4;
		if (groupBits[5])
			reg0[11: 8] = v5;
		if (groupBits[6])
			reg0[ 7: 4] = v6;
		if (groupBits[7])
			reg0[ 3: 0] = v7;
			
		if (groupBits[8])
			reg1[31:16] = v8;
		if (groupBits[9])
			reg1[15: 0] = v9;
	end
	
	// In mode 3, write every 2 pixels.
	// In mode 2, write every pixel (except 1st out of 4)
	// In mode 1, write every 4 pixels.
	// In mode 0, write every 8 pixels.
	wire writeFifo	=  ((     count  [0]    && (format==2'd3)) ||
						((count[1:0]!=2'd0) && (format==2'd2)) ||
						((count[1:0]==2'd3) && (format==2'd1)) ||
						((count[2:0]==3'd7) && (format==2'd0))   ) & pWrite;
						
	// Select Reg1 only in format 2, 3rd pixel write.
	// else   Reg0 for ALL other cases.
	wire selectReg  = ((format==2'd2) && (count[1:0]==2'd2));
	wire [31:0] valueWrite = selectReg ? reg1 : reg0;
	
	wire oppRst = !i_nrst;
	wire emptyFifo;
	wire isFifoFull;
	Fifo
	#(
		.DEPTH_WIDTH	(4),
		.DATA_WIDTH		(32)
	)
	Fifo_inst
	(
		.clk			(i_clk ),
		.rst			(oppRst),

		.wr_data_i		(valueWrite),
		.wr_en_i		(writeFifo),

		.rd_data_o		(o_dataOut),
		.rd_en_i		(i_readFifo),

		.full_o			(isFifoFull),	// TODO A : not FULL but FULL-2 item !!! to fix later...
		.empty_o		(emptyFifo)
	);
	// TODO C CHECK can handle byte order here (o_dataOut)
	assign o_fifoHasData	= !emptyFifo;
	assign stopFill			= isFifoFull;
endmodule
