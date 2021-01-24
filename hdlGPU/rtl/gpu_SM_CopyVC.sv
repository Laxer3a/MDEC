/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_CopyVC(
	input			clk,
	input			nRst,
	
	input			i_activate,
	output			o_exitSig,
	output			o_active,
	
	
	// Control Scanning [Input]
	input			isWidthNot1,
	input			xb_0,
	input			wb_0,
	
	input			endVertical,
	input			nextPairIsLineLast,
	input			currPairIsLineLast,

	// Control Scanning [Output]
	output	[2:0]	o_nextX,
	output  [2:0]	o_nextY,
	output	[2:0]	o_memoryCommand,
	
	// Memory System
	output			o_read,
	input			i_readACK,
	input  [31:0]	i_readPairValue,

	// FIFO
	input			canNearPush,		// Unused
	input			i_canPush,
	input			i_outFIFO_empty,
	output			o_writeFIFOOut,
	output	[31:0]	o_pairPixelToCPU
);

parameter LEFT = 1'b0,
          CRLF = 1'b1;
		  
parameter	MA = 3'd0,
			MB = 3'd1,
			MC = 3'd2,
			S1 = 3'd3,
			S2 = 3'd4,
			S3 = 3'd5,
			S4 = 3'd6,
			S5 = 3'd7;

parameter	SELA_A = 2'd0,
			SELA_B = 2'd1,
			SELA_D = 2'd2,
			SELA__ = 2'd3;

parameter	SELB_A = 1'd0,
			SELB_B = 1'd1;

parameter	WAIT = 5'd0,
			FIRST = 5'd1,
			
			A1 = 5'd2,
			
			B1 = 5'd3,
			B2 = 5'd4,
			B3 = 5'd5,
			B4 = 5'd6,
			
			C1 = 5'd7,
			C2 = 5'd8,
			C3 = 5'd9,
			
			D1 = 5'd10,
			D2 = 5'd11,
			D3 = 5'd12,
			D4 = 5'd13,
			D5 = 5'd14,
			D6 = 5'd15,
			
			P0 = 5'd16,
			P1 = 5'd17,
			
			T0 = 5'd18,
			T1 = 5'd19,
			FINAL = 5'd20;

	reg [4:0] subState, next;
	
reg [2:0] nextX;
reg [2:0] nextY;
assign o_nextX = nextX;
assign o_nextY = nextY;

wire goNextState;
wire sread;

// Allow to know that ACK happened, even cycles before it could not be handled...
// We can go to the next step when : 
// - FIFO space is available for NEXT command result.
// - That we received data for current command or do not need one. (control is S5)
assign goNextState		= canPushI && (stateDoNotNeedDataForTransition || realReadAck || enterStateMachine);


reg [2:0] ctrl;
reg pReadAck;
// reg readSet;
reg pActivate;
reg reqRead;


// Is this state going to write to FIFO when complete.
// If state is not S1 nor S3 (or that S1 and S3 are the LAST state in the state machine).
wire stateDoNotNeedDataForTransition	= (ctrl == S5);																	// OK
wire nextStateIsEnd						= (next == WAIT);															    // OK
wire currStateIsActive					= (subState != WAIT);															// OK
wire isCurrentStateWriter				= ((ctrl != S1) && (ctrl != S3) && currStateIsActive) || nextStateIsEnd;		// OK

wire enterStateMachine					= (i_activate && !pActivate);

always @(posedge clk) begin
	if (nRst == 0) begin
		subState <= WAIT;
		pActivate<= 0;
		reqRead	 <= 0;
	end else begin
		// READACK WILL ALWAYS BE ACCEPTED, BECAUSE WE ISSUE READ WHEN FIFO IS NOT FULL !
		if (goNextState) begin
			subState <= next;
		end
	end
	
	if (goNextState) begin
		reqRead <= 1;
	end
	if (sread) begin
		reqRead <= 0;
	end
	
	// Allow read at next step then...
	pReadAck  <= goNextState;
	pActivate <= i_activate;
end

reg [1:0] aSelABDX;
reg       wbSel;
reg       bSelAB;

/*
	Mecanism :
	Inside a state, 
	- we wait for a transition to the next state (goNextState).
		1. If we need data
		=> Most of the time, it is READ_ACK (Received data).
		  ( But some state do not require such or the first time we enter from END state to start state )
		=> Some state do not require waiting for a read ACK because they did not issue one when started (S5).
		=> Or transitition must be force the first time (END state -> Start state)
		
		See goNextState.
		
	- When we decide the transition, AT LAST CYCLE OF CURRENT STATE (state change at next cycle, 'goNextState').
		=>	We setup NEXT state COORDINATE 
			Coordinate STAY CONSTANT INSIDE A STATE and are modified AT THE LAST CYCLE FOR THE NEXT.
		=>	We pipeline READ_ACK to decide to launch a read for the first cycle of the next state.
			But it is possible that this is 'missed' because the FIFO is full.
			So we use 'reqRead' flag to support delayed read send.
		
		See 
 */

reg readAckDefer;

wire realReadAck			= readAckDefer | i_readACK;

always @(posedge clk) begin
	if (nRst == 0)
	    readAckDefer <= 1'b0;
	else if (realReadAck & ~canPushI)
	    readAckDefer <= 1'b1;
	else if (canPushI)
	    readAckDefer <= 1'b0;
end


// EXCEPT that we ISSUE READ ONLY IF current command is NOT S5.
wire canPushI				= i_activate && i_canPush;
assign sread				= (canPushI && ((pReadAck || reqRead) && (!stateDoNotNeedDataForTransition)));

always @(*) begin
	aSelABDX	= SELA__;
	wbSel		= 1'd0;
	bSelAB		= 1'dx;
	
	if (goNextState) begin
		// 0:A
		// 1:B
		// 2:D
		// 3:Nothing
		case (ctrl)
		MA : aSelABDX = SELA_A;
		MB : aSelABDX = SELA_D;
		MC : aSelABDX = SELA_D;
		S1 : aSelABDX = SELA_B;
		S2 : aSelABDX = SELA__;
		S3 : aSelABDX = SELA_A;
		S4 : aSelABDX = SELA__;
		/*S5*/ default : aSelABDX = SELA_D;
		endcase
		
		case (ctrl)
		MA : begin bSelAB = SELB_B; wbSel = 1; end
		MB : begin bSelAB = SELB_A; wbSel = 1; end
		MC : begin bSelAB = SELB_B; wbSel = 1; end
		S1 : begin bSelAB = 1'dx;   wbSel = 0; end
		S2 : begin bSelAB = SELB_A; wbSel = 1; end
		S3 : begin bSelAB = 1'dx;   wbSel = 0; end
		S4 : begin bSelAB = SELB_B; wbSel = 1; end
		/*S5*/ default : begin bSelAB = 1'dx;   wbSel = 0; end
		endcase
	end
end

reg nextCoord;

// State change is dependent on current coordinate and READ ACK to authorize state change.
always @(*) begin
	nextCoord = CRLF;
	
	case (subState)
	WAIT: begin
		ctrl		= S5;	// AVOID REQUESTING MEMORY READ.
		// Force loading.
		nextCoord	= CRLF;
		if (i_activate) begin
			next = FIRST;
		end else begin
			next = WAIT;
		end
	end
	FIRST: begin
		ctrl		= S5;	// AVOID REQUESTING MEMORY READ.
		nextCoord	= LEFT;	// IGNORED (no readACK)
		if (isWidthNot1) begin
			// TODO Width = 1 states....
			case ({xb_0,wb_0})
			2'd00: next = A1;
			2'b01: next = B1;
			2'b10: next = C1;
			/*2'b11*/ default: next = D1;
			endcase
		end else begin
			 if (xb_0) begin
				next = T0;
			 end else begin
				next = P0;
			 end
		end
	end
	A1: begin
		ctrl = MA;
		if (currPairIsLineLast) begin
			nextCoord	= CRLF;
			next		= (endVertical) ? FINAL : A1;
		end else begin
			nextCoord	= LEFT;
			next		= A1;
		end
	end
	B1: begin
		ctrl		= MA;
		nextCoord	= LEFT;
		next		= (nextPairIsLineLast) ? B2 : B1;
	end
	B2: begin
		ctrl		= S3;
		nextCoord	= CRLF;
		next		= (endVertical) ? FINAL : B3;
	end
	B3: begin
		ctrl		= S2;
		nextCoord	= LEFT;
		next		= B4;
	end
	B4: begin
		ctrl		= MB;
		if (!currPairIsLineLast) begin
			nextCoord	= LEFT;
			next 		= B4;
		end else begin
			nextCoord	= CRLF;
			next		= (endVertical) ? FINAL : B1;
		end
	end
	C1: begin
		ctrl		= S1;
		nextCoord	= LEFT;
		next		= C2;
	end
	C2: begin
		ctrl		= S2;
		if (currPairIsLineLast) begin
			nextCoord	= CRLF;
			next		= (endVertical) ? FINAL : C1; 
		end else begin
			nextCoord	= LEFT;
			next		= C3;
		end
	end
	C3: begin
		ctrl		= MB;
		if (!currPairIsLineLast) begin
			nextCoord	= LEFT;
			next 		= C3;
		end else begin
			nextCoord	= CRLF;
			next		= (endVertical) ? FINAL : C1;
		end
	end
	D1: begin
		ctrl		= S1;
		nextCoord	= LEFT;
		next		= D2;
	end
	D2: begin
		ctrl		= S2;
		if (endVertical && currPairIsLineLast) begin
			nextCoord	= CRLF;
			next		= D6;
		end else begin
			if (!currPairIsLineLast) begin
				nextCoord	= LEFT;
				next 		= D3;
			end else begin
				nextCoord	= CRLF;
				next		= D4;
			end
		end
	end
	D3: begin
		ctrl		= MB;
		if (!currPairIsLineLast) begin
			nextCoord	= LEFT;
			next		= D3;
		end else begin
			nextCoord	= CRLF;
			next		= endVertical ? D6 : D4;
		end
	end
	D4: begin
		ctrl		= MC;
		nextCoord	= LEFT;
		next		= D5;
	end
	D5: begin
		ctrl		= MA;
		if (!currPairIsLineLast) begin
			nextCoord	= LEFT;
			next		= D5;
		end else begin
			nextCoord	= CRLF;
			next		= endVertical ? FINAL: D1;
		end
	end
	D6: begin
		ctrl		= S5;
		next		= FINAL;
	end
	// ALIGNED
	P0: begin
		ctrl		= S3;
		nextCoord	= CRLF;
		next		= endVertical ? FINAL : P1;
	end
	P1: begin
		ctrl		= S2;
		nextCoord	= CRLF;
		next		= endVertical ? FINAL : P0;
	end
	// UNALIGNED
	T0: begin
		ctrl		= S1;
		nextCoord	= CRLF;
		next		= endVertical ? FINAL : T1;
	end
	T1: begin
		ctrl		= S4;
		nextCoord	= CRLF;
		next		= endVertical ? FINAL : T0;
	end
	FINAL: begin
		ctrl		= S5;	// AVOID REQUESTING MEMORY READ.
		next = (i_outFIFO_empty) ? WAIT : FINAL;
	end
	default: begin
		ctrl		= S5;	// AVOID REQUESTING MEMORY READ.
		next = WAIT;
	end
	endcase
end
	
// Convert signal bool into 6 bit control direction signals.
// Change coordinate ONLY when we receive read ACK.
always @(*) begin
	nextX = X_ASIS;
	nextY = Y_ASIS;
	
	if (goNextState && (!enterStateMachine)) begin
		nextX = nextCoord	?  X_CV_START /*CRLF*/ 
							:  X_TRI_NEXT /*LEFT*/;
		if (nextCoord) begin
			nextY = i_activate ? Y_CV_ZERO : Y_TRI_NEXT; /*CRLF*/
		end // else Y_ASIS      /*LEFT*/;
	end
end

// Allow to push when transition (=receive data or no need to receive data)
// Some state do NOT require to write data (S1 and S3), so we do not write in those case.
// But in some special cases if S1 and S3 are the LAST executing state, we allow them to push the data (with garbage in it)
wire  writeNextCycle		= goNextState && isCurrentStateWriter;

reg pipeToFIFOOut;
reg [31:0] pairPixelToCPU;
reg [15:0] DPixelReg;
always @(posedge clk)
begin
	// A Part
	case (aSelABDX)
	/*SELA_A = */2'd0: pairPixelToCPU[15:0] <= i_readPairValue[15:0];
	/*SELA_B = */2'd1: pairPixelToCPU[15:0] <= i_readPairValue[31:16];
	/*SELA_D = */2'd2: pairPixelToCPU[15:0] <= DPixelReg;
	/*SELA__ = */2'd3: begin /*Nothing*/ end
	endcase
	
	// B Part
	if (wbSel) begin
		pairPixelToCPU[31:16] <= bSelAB ? i_readPairValue[31:16] : i_readPairValue[15:0];
	end
	
	if (i_readACK) begin
		DPixelReg <= i_readPairValue[31:16];
	end
	pipeToFIFOOut <= writeNextCycle;
end

assign o_pairPixelToCPU 	= pairPixelToCPU;
assign o_writeFIFOOut		= pipeToFIFOOut;
assign o_active				= currStateIsActive;
assign o_exitSig			= goNextState && nextStateIsEnd;
assign o_read				= sread;
assign o_memoryCommand		= sread ? MEM_CMD_VRAM2CPU : MEM_CMD_NONE;
	
endmodule
