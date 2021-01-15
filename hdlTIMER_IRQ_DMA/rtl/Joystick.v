/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module Joystick (
	//--------------------------------------
	// CPU Side
	//--------------------------------------
	input				i_clk,
	input				i_nRst,

	// 
	output	[7:0]		emitData1C,
	output				emit1C,
	input	[7:0]		receiveData1C,
	input				receive1C,
	
	//--------------------------------------
	// Joystick side
	//--------------------------------------
	input	[13:0]		joystick
);
	// [TODO Joystick mapping]
	wire joy_SELECT	= !joystick[ 0];
	wire joy_START	= !joystick[ 1];
	wire joy_UP 	= !joystick[ 2];
	wire joy_RIGHT	= !joystick[ 3];
	wire joy_DOWN	= !joystick[ 4];
	wire joy_LEFT	= !joystick[ 5];
	wire joy_L2		= !joystick[ 6];
	wire joy_R2		= !joystick[ 7];
	wire joy_L1		= !joystick[ 8];
	wire joy_R1		= !joystick[ 9];
	wire joy_TRIAN	= !joystick[10];
	wire joy_ROUND	= !joystick[11];
	wire joy_XBTN	= !joystick[12];
	wire joy_SQUARE	= !joystick[13];

	typedef enum bit[2:0] {
		START	= 3'h0,
		GETx42	= 3'h1,
		RETx5A	= 3'h2,
		BTNBYTE0= 3'h3,
		BTNBYTE1= 3'h4
	} JSTATE;
	
	JSTATE		joyState;
	reg [7:0]	outValue,regOutValue;
	wire       	outValueValid = receive1C; // Same thing, different name
	
	wire transitionSTART_GETx42  = (receiveData1C == 8'h01);
	wire transitionGETx42_RETx5A = (receiveData1C == 8'h42);
	
	always @(posedge i_clk) begin
	
		if (i_nRst == 1'b0) begin
			joyState <= START;
		end else begin
			// State machine transition when we receive a byte.
			if (receive1C) begin
				case (joyState)
				START: begin
					if (transitionSTART_GETx42) begin
						joyState <= GETx42;
					end
				end
				GETx42: begin
					if (transitionGETx42_RETx5A) begin
						joyState <= RETx5A;
					end else begin
						joyState <= START;
					end
				end
				RETx5A: begin
					joyState <= BTNBYTE0;
				end
				BTNBYTE0: begin
					joyState <= BTNBYTE1;
				end
				BTNBYTE1: begin
					joyState <= START;
				end
				default: begin
					joyState <= START;
				end
				endcase
			end

			// Store value for answering timer complete.
			if (outValueValid) begin
				regOutValue <= outValue;
			end
		end
	end
	
										// TODO : Implement timer to restart each time 'receive1C' is true.
	assign emitData1C	= outValue; 	// TODO : use regOutValue with timer internally... for delay.
	assign emit1C		= receive1C;	// TODO : Use internal timer reach end instead.
	
	always @(*) begin
		outValue = 8'hFF;
		case (joyState)
		GETx42: begin
			if (receive1C & transitionGETx42_RETx5A) begin
				outValue = 8'h41;
			end
		end
		RETx5A: begin
			if (receive1C) begin
				outValue = 8'h5A;
			end
		end
		BTNBYTE0: begin
			if (receive1C) begin
				outValue = {
					joy_LEFT,
					joy_DOWN,
					joy_RIGHT,
					joy_UP,
					joy_START,
					1'b0,
					1'b0,
					joy_SELECT
				};
			end
		end
		BTNBYTE1: begin
			if (receive1C) begin
				outValue = {
					joy_SQUARE,
					joy_XBTN,
					joy_ROUND,
					joy_TRIAN,
					joy_R1,
					joy_L1,
					joy_R2,
					joy_L2
				};
			end
		end
		default: begin
		end
		endcase
	end
endmodule
