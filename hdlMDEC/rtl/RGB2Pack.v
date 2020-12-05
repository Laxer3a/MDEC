module RGB2Pack(
	input	i_clk,
	input	i_nrst,
	
	input			i_wrtPix,
	input	[1:0]	format,
	input			setBit15,
	input	[7:0]	i_r,
	input	[7:0]	i_g,
	input	[7:0]	i_b,

	output			o_dataValid,
	output	[31:0]	o_dataPacked
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
		if (!i_nrst) begin
			count  <= 3'b000;
			pWrite <= 0;
		end else begin
			pWrite <= i_wrtPix;
			if (i_wrtPix) begin
				count <= count + 3'd1;
			end
		end
	end

	reg  [3:0] v1;
	reg  [3:0] v2;
	reg  [3:0] v3;
	reg  [3:0] v4;
	reg  [3:0] v5;
	reg  [3:0] v6;
	reg  [3:0] v7;
	reg  [9:0] groupBits;

	wire [3:0] GreyM = R[7:4];
	wire [3:0] GreyL = R[3:0];
	
	wire [3:0] v0 = ((count[1:0]==2'd2) && (format==2'd2)) ? B[7:4] : R[7:4]; 
	always @(*)
	begin
		case (format)
		// 4 BIT
		0      : begin
			v1 = GreyM;
			v2 = GreyM;
			v3 = GreyM;
			v4 = GreyM;
			v5 = GreyM;
			v6 = GreyM;
			v7 = GreyM;
			
			case (count[2:0])
			3'd0   : groupBits = 10'b00_00000001;
			3'd1   : groupBits = 10'b00_00000010;
			3'd2   : groupBits = 10'b00_00000100;
			3'd3   : groupBits = 10'b00_00001000;
			3'd4   : groupBits = 10'b00_00010000;
			3'd5   : groupBits = 10'b00_00100000;
			3'd6   : groupBits = 10'b00_01000000;
			default: groupBits = 10'b00_10000000;
			endcase               
		end
		// 8 BIT                  
		1      : begin
			v1 = GreyL;
			v2 = GreyM;
			v3 = GreyL;
			v4 = GreyM;
			v5 = GreyL;
			v6 = GreyM;
			v7 = GreyL;

			case (count[1:0])
			2'd0   : groupBits = 10'b00_00000011;
			2'd1   : groupBits = 10'b00_00001100;
			2'd2   : groupBits = 10'b00_00110000;
			default: groupBits = 10'b00_11000000;
			endcase               
		end
		// 24 BIT                 
		2      : begin
			v1 = (count[0]==0) ? R[3:0] : B[3:0];
			v2 = (count[0]==0) ? G[7:4] : R[7:4];
			v3 = (count[0]==0) ? G[3:0] : R[3:0];
			v4 = (count[0]==0) ? B[7:4] : G[7:4];
			v5 = (count[0]==0) ? B[3:0] : G[3:0];
			v6 = (count[1]==0) ? R[7:4] : B[7:4];
			v7 = (count[1]==0) ? R[3:0] : B[3:0];
			case (count[1:0])
			2'd0   : groupBits = 10'b00_00111111;
			2'd1   : groupBits = 10'b01_11000000;
			2'd2   : groupBits = 10'b10_00000011;
			default: groupBits = 10'b00_11111100;
			endcase
		end
		// 15 BIT
		default: begin
			v1 = { R[3]  , G[7:5] };
			v2 = { G[4:3], B[7:6] };
			v3 = { B[5:3], Cl};
			v4 =   R[7:4];
			v5 = { R[3]  , G[7:5] };
			v6 = { G[4:3], B[7:6] };
			v7 = { B[5:3], Cl};
			groupBits = count[0] ? 10'b00_00001111 
			                     : 10'b00_11110000;
		end
		endcase
	end
	
	wire [15:0] v8 = { G, B };
	wire [15:0] v9 = { R, G };

	reg [31:0] reg0,reg1;
	
	always @(posedge i_clk)
	begin
		// we just write forever until the correct data arrive and bit state change.
		if (groupBits[0])
			reg0[31:28] <= v0;
		if (groupBits[1])
			reg0[27:24] <= v1;
		if (groupBits[2])
			reg0[23:20] <= v2;
		if (groupBits[3])
			reg0[19:16] <= v3;
		if (groupBits[4])
			reg0[15:12] <= v4;
		if (groupBits[5])
			reg0[11: 8] <= v5;
		if (groupBits[6])
			reg0[ 7: 4] <= v6;
		if (groupBits[7])
			reg0[ 3: 0] <= v7;
			
		if (groupBits[8])
			reg1[31:16] <= v8;
		if (groupBits[9])
			reg1[15: 0] <= v9;
	end
	
	// In mode 3, write every 2 pixels.
	// In mode 2, write every pixel (except 1st out of 4)
	// In mode 1, write every 4 pixels.
	// In mode 0, write every 8 pixels.
						
	// Select Reg1 only in format 2, 3rd pixel write.
	// else   Reg0 for ALL other cases.
	wire selectReg  = ((format==2'd2) && (count[1:0]==2'd2));
	
	assign o_dataPacked	= selectReg ? reg1 : reg0;
	assign o_dataValid	=  ((     count  [0]    && (format==2'd3)) ||
							((count[1:0]!=2'd0) && (format==2'd2)) ||
							((count[1:0]==2'd3) && (format==2'd1)) ||
							((count[2:0]==3'd7) && (format==2'd0))   ) & pWrite;	
endmodule
