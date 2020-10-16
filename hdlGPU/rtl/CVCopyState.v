module CVCopyState(
	input			clk,
	input			nRst,
	
	input			active,
	input			isWidthNot1,
	input			xb_0,
	input			wb_0,
	
	input			canPush,
	input			endVertical,
	input			nextPairIsLineLast,
	input			currPairIsLineLast,
	input			readACK,
	
	output	[2:0]	o_nextX,
	output  [2:0]	o_nextY,
	output			read,
	output			exitSig,
	output	[1:0]	o_aSelABDX,
	output			o_bSelAB,
	output			o_pushNextCycle,
	output			o_wbSel
);

parameter	X_TRI_NEXT		= 3'd1,
			X_ASIS			= 3'd0,
			X_CV_START		= 3'd6;

parameter	Y_CV_ZERO		= 3'd6,
			Y_TRI_NEXT		= 3'd4,
			Y_ASIS			= 3'd0;

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

parameter	END = 5'd0,
			
			A1 = 5'd1,
			
			B1 = 5'd2,
			B2 = 5'd3,
			B3 = 5'd4,
			B4 = 5'd5,
			
			C1 = 5'd6,
			C2 = 5'd7,
			C3 = 5'd8,
			
			D1 = 5'd9,
			D2 = 5'd10,
			D3 = 5'd11,
			D4 = 5'd12,
			D5 = 5'd13,
			D6 = 5'd14,
			
			P0 = 5'd15,
			P1 = 5'd16,
			
			T0 = 5'd17,
			T1 = 5'd18;

	reg [4:0] subState, next;
	
reg [2:0] nextX;
reg [2:0] nextY;
assign o_nextX = nextX;
assign o_nextY = nextY;

wire goNextStep;
wire sread;

wire nextStateIsEnd	= (next     == END);
wire currStateIsEnd	= (subState == END);
assign exitSig		= goNextStep && nextStateIsEnd;

reg pReadAck;
// reg readSet;
reg pActive;
reg reqRead;

always @(posedge clk) begin
	if (nRst == 0) begin
		subState = END;
//		readSet  = 1'b0;
		pActive  = 1'b0;
		reqRead	 = 1'b0;
	end else begin
		// READACK WILL ALWAYS BE ACCEPTED, BECAUSE WE ISSUE READ WHEN FIFO IS NOT FULL !
		if (goNextStep) begin
			subState = next;
		end
	end
	
	if (goNextStep) begin
		reqRead = 1;
	end
	if (sread) begin
		reqRead = 0;
	end
	
	// Allow read at next step then...
	pReadAck = goNextStep;
	pActive  = active;

/*
	if (readACK) begin
		readSet = 1'b1;
	end
	if (goNextStep) begin
		readSet = 1'b0;
	end
*/
end

reg [2:0] ctrl;
reg [1:0] aSelABDX;
reg       wbSel;
reg       bSelAB;

/*
	Mecanism :
	Inside a state, 
	- we wait for a transition to the next state (goNextStep).
		1. If we need data
		=> Most of the time, it is READ_ACK (Received data).
		  ( But some state do not require such or the first time we enter from END state to start state )
		=> Some state do not require waiting for a read ACK because they did not issue one when started (S5).
		=> Or transitition must be force the first time (END state -> Start state)
		
		See goNextStep.
		
	- When we decide the transition, AT LAST CYCLE OF CURRENT STATE (state change at next cycle, 'goNextStep').
		=>	We setup NEXT state COORDINATE 
			Coordinate STAY CONSTANT INSIDE A STATE and are modified AT THE LAST CYCLE FOR THE NEXT.
		=>	We pipeline READ_ACK to decide to launch a read for the first cycle of the next state.
			But it is possible that this is 'missed' because the FIFO is full.
			So we use 'reqRead' flag to support delayed read send.
		
		See 
 */

wire canPushI				= active && canPush;
wire flagStart				= (active && !pActive);

// Is this state going to write to FIFO when complete.
// If state is not S1 nor S3 (or that S1 and S3 are the LAST state in the state machine).
wire isCurrentStateWriter	= ((ctrl != S1) && (ctrl != S3) && (!currStateIsEnd)) || nextStateIsEnd;

// Allow to know that ACK happened, even cycles before it could not be handled...
// We can go to the next step when : 
// - FIFO space is available for NEXT command result.
// - That we received data for current command or do not need one. (control is S5)
assign goNextStep				= (canPushI /* || (active && (!isCurrentStateWriter)) */) && ((ctrl == S5) || readACK || flagStart);

// Allow to push when transition (=receive data or no need to receive data)
// Some state do NOT require to write data (S1 and S3), so we do not write in those case.
// But in some special cases if S1 and S3 are the LAST executing state, we allow them to push the data (with garbage in it)
wire pushNextCycle			= goNextStep && isCurrentStateWriter;
assign o_pushNextCycle      = pushNextCycle;

// EXCEPT that we ISSUE READ ONLY IF current command is NOT S5.
assign sread				= (canPushI && ((pReadAck || reqRead) && (ctrl != S5)));
assign read					= sread;

assign o_aSelABDX = aSelABDX;
assign o_wbSel    = wbSel;
assign o_bSelAB   = bSelAB;
always @(*) begin
	aSelABDX	= SELA__;
	wbSel		= 1'd0;
	bSelAB		= 1'dx;
	
	if (goNextStep) begin
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
	nextCoord = 1'dx;
	
	case (subState)
	A1: begin
		ctrl = MA;
		if (currPairIsLineLast) begin
			nextCoord	= CRLF;
			next		= (endVertical) ? END : A1;
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
		next		= (endVertical) ? END : B3;
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
			next		= (endVertical) ? END : B1;
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
			next		= (endVertical) ? END : C1; 
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
			next		= (endVertical) ? END : C1;
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
			next		= endVertical ? END: D1;
		end
	end
	D6: begin
		ctrl		= S5;
		next		= END;
	end
	// ALIGNED
	P0: begin
		ctrl		= S3;
		nextCoord	= CRLF;
		next		= endVertical ? END : P1;
	end
	P1: begin
		ctrl		= S2;
		nextCoord	= CRLF;
		next		= endVertical ? END : P0;
	end
	// UNALIGNED
	T0: begin
		ctrl		= S1;
		nextCoord	= CRLF;
		next		= endVertical ? END : T1;
	end
	T1: begin
		ctrl		= S4;
		nextCoord	= CRLF;
		next		= endVertical ? END : T0;
	end
	default: begin
		ctrl		= S5;	// AVOID REQUESTING MEMORY READ.
		nextCoord	= LEFT;	// IGNORED (no readACK)
		if (active) begin
			if (isWidthNot1) begin
				// TODO Width = 1 states....
				case ({xb_0,wb_0})
				2'd00: next = A1;
				2'b01: next = B1;
				2'b10: next = C1;
				2'b11: next = D1;
				endcase
			end else begin
				 if (xb_0) begin
					next = T0;
				 end else begin
					next = P0;
				 end
			end
		end else begin
			next = END;
		end
	end
	endcase
end
	
// Convert signal bool into 6 bit control direction signals.
// Change coordinate ONLY when we receive read ACK.
always @(*) begin
	nextX = X_ASIS;
	nextY = Y_ASIS;
	
	if (goNextStep && (!flagStart)) begin
		nextX = nextCoord	?  X_CV_START /*CRLF*/ 
							:  X_TRI_NEXT /*LEFT*/;
		if (nextCoord) begin
			nextY = Y_TRI_NEXT; /*CRLF*/
		end // else Y_ASIS      /*LEFT*/;
	end
end
	
endmodule
