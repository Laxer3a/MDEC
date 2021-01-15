/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

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

parameter	FMT_04BIT		= 2'd0,
			FMT_08BIT		= 2'd1,
			FMT_24BIT		= 2'd2,
			FMT_15BIT		= 2'd3;

	// TODO Endianorder, V01 23 45 67 and v8/v9 reverse.
	// TODO RGB or BGR order here. (easiest, swap r/g/b)
	wire [7:0] R	 = i_r;
	wire [7:0] G	 = i_g;
	wire [7:0] B	 = i_b;
	wire [3:0] GreyM = i_r[7:4];
	wire [3:0] GreyL = i_r[3:0];
	wire       Cl	 = setBit15;
	
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

	reg  [3:0] v0,v1,v2,v3,v4,v5,v6,v7;
	reg  [9:0] groupBits;
	
	always @(*)
	begin
		case (format)
		FMT_04BIT : begin
			v0 = GreyM; // LSB
			v1 = GreyM;
			v2 = GreyM;
			v3 = GreyM;
			v4 = GreyM;
			v5 = GreyM;
			v6 = GreyM;
			v7 = GreyM; // MSB
			
			case (count[2:0])
			//                      V98 76543210
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
		FMT_08BIT : begin
			v0 = GreyL; // LSB
			v1 = GreyM;
			v2 = GreyL;
			v3 = GreyM;
			v4 = GreyL;
			v5 = GreyM;
			v6 = GreyL;
			v7 = GreyM; // MSB

			case (count[1:0])
			//                      V98 76543210
			2'd0   : groupBits = 10'b00_00000011;
			2'd1   : groupBits = 10'b00_00001100;
			2'd2   : groupBits = 10'b00_00110000;
			default: groupBits = 10'b00_11000000;
			endcase               
		end
		FMT_24BIT : begin
			v0 = count[1] ? B[3:0] : R[3:0];	// LSB
			v1 = count[1] ? B[7:4] : R[7:4];
			v2 = count[1] ? R[3:0] : G[3:0];
			v3 = count[1] ? R[7:4] : G[7:4];
			v4 = count[1] ? G[3:0] : B[3:0];
			v5 = count[1] ? G[7:4] : B[7:4];
			v6 = count[1] ? B[3:0] : R[3:0];
			v7 = count[1] ? B[7:4] : R[7:4];	// MSB
		
			case (count[1:0])
			//                      V98 76543210
			2'd0   : groupBits = 10'b00_00111111;
			2'd1   : groupBits = 10'b01_11000000;
			2'd2   : groupBits = 10'b10_00000011;
			default: groupBits = 10'b00_11111100;
			endcase
		end
		// FMT_15BIT
		default: begin
			v0 = { R[6:3]         }; // LSB
			v1 = { G[5:3], R[7]   };
			v2 = { B[4:3], G[7:6] };
			v3 = { Cl    , B[7:5] }; // MSB
			
			v4 = { R[6:3]         }; // LSB
			v5 = { G[5:3], R[7]   };
			v6 = { B[4:3], G[7:6] };
			v7 = { Cl    , B[7:5] }; // MSB
			
			//                        V98 76543210
			groupBits = count[0] ? 10'b00_11110000	// MSB second pixel
			                     : 10'b00_00001111;	// LSB First pixel
		end
		endcase
	end
	
	wire [15:0] v8 = { B , G };
	wire [15:0] v9 = { G , R };

	reg [31:0] reg0,reg1;
	
	always @(posedge i_clk)
	begin
		// we just write forever until the correct data arrive and bit state change.
		if (groupBits[0] & i_wrtPix)
			reg0[ 3: 0] <= v0;
		if (groupBits[1] & i_wrtPix)
			reg0[ 7: 4] <= v1;
		if (groupBits[2] & i_wrtPix)
			reg0[11: 8] <= v2;
		if (groupBits[3] & i_wrtPix)
			reg0[15:12] <= v3;
		if (groupBits[4] & i_wrtPix)
			reg0[19:16] <= v4;
		if (groupBits[5] & i_wrtPix)
			reg0[23:20] <= v5;
		if (groupBits[6] & i_wrtPix)
			reg0[27:24] <= v6;
		if (groupBits[7] & i_wrtPix)
			reg0[31:28] <= v7;
			
		if (groupBits[9] & i_wrtPix)
			reg1[31:16] <= v9;
		if (groupBits[8] & i_wrtPix)
			reg1[15: 0] <= v8;
	end
	
	// In mode 3, write every 2 pixels.
	// In mode 2, write every pixel (except 1st out of 4)
	// In mode 1, write every 4 pixels.
	// In mode 0, write every 8 pixels.
						
	// Select Reg1 only in format 2, 3rd pixel write.
	// else   Reg0 for ALL other cases.
	wire selectReg  = ((format==FMT_24BIT) && (count[1:0]==2'd3));
	
	assign o_dataPacked	= selectReg ? reg1 : reg0;
	assign o_dataValid	=  ((  (!count  [0])    && (format==FMT_15BIT)) ||
							((count[1:0]!=2'd1) && (format==FMT_24BIT)) ||
							((count[1:0]==2'd0) && (format==FMT_08BIT)) ||
							((count[2:0]==3'd0) && (format==FMT_04BIT))   ) & pWrite;	
endmodule
