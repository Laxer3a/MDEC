module MemCard (
	//--------------------------------------
	// PSX Side
	//--------------------------------------
	input				i_clk,
	input				i_nRst,

	output	[7:0]		emitData1C,
	output				emit1C,
	input	[7:0]		receiveData1C,
	input				receive1C,			// MUST NEVER HAVE TWO CONSECUTIVE READ SIGNAL
	
	//--------------------------------------
	// Host platform Side
	//--------------------------------------
	input	[16:0]		i_adr,
	input				i_write,
	output				o_canAcceptReadWrite,	// MUST BE USED WITH THE SAME CYCLE AS i_adr / i_write ! (DO NOT : read then cycle+1 do operation !!!)
	
	input	[7:0]		i_loadData,
	output	[7:0]		o_saveData
);
	typedef struct packed {
		// 2 bit padding
		logic error;
		logic fresh;
		logic unknown;
		// 3 bit padding
	} MFlags;

	MFlags flags;

	typedef enum bit[4:0] {
		START		 = 5'd0,
		WAITCOMMAND  = 5'd1,
		READ2        = 5'd2,
		READ3        = 5'd3,
		READ4        = 5'd4,
		READ5        = 5'd5,
		READ6        = 5'd6,
		READ7        = 5'd7,
		READ8        = 5'd8,
		READ9        = 5'd9,
		READGENERIC  = 5'd10,
		READ138      = 5'd11,
		READ139      = 5'd12,

		WRITE2       = 5'd13,
		WRITE3       = 5'd14,
		WRITE4       = 5'd15,
		WRITE5       = 5'd16,
		WRITEGENERIC = 5'd17,
		WRITE134     = 5'd18,
		WRITE135     = 5'd19,
		WRITE136     = 5'd20,
		WRITE137     = 5'd21,
		UNDEFINED    = 5'd22
	} MSTATE;

	MSTATE cardState;

	typedef enum bit[7:0] {
		GOOD		 = 8'h47, 	// 'G'
		BACCHECKSUM  = 8'h4E,	// 'N'
		BADSECTOR    = 8'hFF
	} MWRITESTATUS;
	
	reg  [9:0]		cardAddr;
	reg  [7:0]		cardCHKSUM;
	MWRITESTATUS	cardStatus;
	reg				cardInserted;
	reg				cardDirty;
	
	reg  [7:0]		outValue,regOutValue;
	
	// State machine write decided by state machine and user data.
	wire			internalWrite= (cardState == WRITEGENERIC) && receive1C;
	wire			internalRead = (cardState == READGENERIC ) && receive1C;

	reg				pipeInternalRead;
	always @ (posedge i_clk) begin
		pipeInternalRead <= internalRead;
	end
	assign			o_canAcceptReadWrite = !receive1C;
	
	// ------------------------------------------------------
	// Memory Card
	// ------------------------------------------------------
	// Accept to give the host access to the content of the Memory Card. PSX HAS PRIORITY !!!
	wire [16:0] workAdr = receive1C ? {cardAddr, index} : i_adr;
	wire  [7:0] workData= receive1C ? receiveData1C     : i_loadData;
	// ------------------------------------------------------
	reg [7:0] MemCard[131071:0];
	reg  [16:0] addr_reg;
	always @ (posedge i_clk)
	begin
		// Write
		if (i_write || internalWrite) begin
			MemCard[workAdr] = workData;
		end
		addr_reg			= workAdr;
	end
	wire [7:0] valueRead    = MemCard[addr_reg];
	// ------------------------------------------------------
	assign o_saveData = valueRead;

	reg [6:0]	index;
	wire		notLastIndex = (index < 7'd127);

	always @(posedge i_clk) begin
		if (i_nRst == 1'b0) begin
			cardState     <= START;
			flags.error	  <=  1'b0;
			flags.fresh   <=  1'b1;
			flags.unknown <=  1'b1;
			cardStatus	  <=  GOOD;
			cardCHKSUM	  <=  8'd0;
			cardInserted  <=  1'b1;
			cardDirty	  <=  1'b0;
			cardAddr	  <= 10'd0;
			index     	  <=  7'h0;
		end else begin
			// State machine transition when we receive a byte.
			if (receive1C) begin
				case (cardState)
				//
				// Start
				//
				START: begin
					if (receiveData1C == 8'h81) begin
						cardState <= WAITCOMMAND;
					end
				end
				WAITCOMMAND: begin
					if (receiveData1C == 8'h52 /*'R'*/) begin
						cardState <= READ2;
					end else begin
						if (receiveData1C == 8'h57 /*'W'*/) begin
							cardState <= WRITE2;
						end else begin
							if (receiveData1C == 8'h53 /*'S'*/) begin
								cardState <= UNDEFINED;
							end else begin
								cardState <= START;
							end
						end
					end
					flags.error	<= 1'b0;
				end
				//
				// Read
				//
				READ2: begin // ID1
					cardState <= READ3;
				end
				READ3: begin // ID2
					cardState <= READ4;
				end       
				READ4: begin // MSB ADR
					cardState     <= READ5;
					cardAddr[9:8] <= receiveData1C[1:0];
				end       
				READ5: begin // LSB ADR
					cardState	  <= READ6;
					cardAddr[7:0] <= receiveData1C[7:0];
				end
				READ6: begin
					cardState <= READ7;
				end       
				READ7: begin 
					cardState <= READ8;
				end       
				READ8: begin 
					cardState <= READ9;
				end       
				READ9: begin 
					cardState <= READGENERIC;
					index     <= 7'h0;
				end
				READGENERIC: begin
					if (notLastIndex) begin
						index     <= index + 7'h1;
					end else begin
						cardState <= READ138;
					end
				end 
				READ138: begin 
					cardState <= READ139;
				end     
				READ139: begin 
					cardState <= START;
				end     
				// Write
				WRITE2: begin
					cardState <= WRITE3;
				end      
				WRITE3: begin 
					cardState 	<= WRITE4;
					cardStatus	<= GOOD; 					// Avocado was doing GOOD then overwrite BADSECTOR in the same state, here we know the path, can modify it BEFORE.
				end
				WRITE4: begin 
					cardCHKSUM	<= receiveData1C;
					cardAddr[9:8] <= receiveData1C[1:0];
					if (receiveData1C[7:2] != 6'd0) begin 	// Avocado was doing that post concat in WRITE5. Easier here.
						flags.error	<= 1'b1;
						cardStatus	<= BADSECTOR;
					end
					cardState <= WRITE5;
				end
				WRITE5: begin 
					cardCHKSUM	<= cardCHKSUM ^ receiveData1C;
					cardAddr[7:0] <= receiveData1C[7:0];
					cardState <= WRITE5;
					index     <= 7'h0;
				end      
				WRITEGENERIC: begin 
					cardCHKSUM	<= cardCHKSUM ^ receiveData1C;
					if (notLastIndex) begin
						index     <= index + 7'h1;
					end else begin
						cardState <= WRITE134;
					end
				end
				WRITE134: begin 
					if (cardCHKSUM != receiveData1C) begin
						flags.error	<= 1'b1;
						cardStatus	<= BACCHECKSUM;
					end
					cardState <= WRITE135;
				end    
				WRITE135: begin 
					cardState <= WRITE136;
				end    
				WRITE136: begin 
					cardState <= WRITE137;
				end    
				WRITE137: begin 
					cardDirty	<= 1'b1;
					flags.fresh	<= 1'b0;
					// TODO dirty ROLE ? (Not in protocol)
					// TODO flag.fresh ---> Talk to Jakub about his fresh flag that goes to zero ONCE and the unknown always at 1. (never touched but sent !)
				end
				default: begin // UNDEFINED too
					cardState <= START;
				end
				endcase
			end

			// === Store value for answering timer complete ===
			// Store READ result with one cycle delay.
			// Store other result when received a byte from PSX and NOT IN READ mode.
			if (pipeInternalRead | ((!internalRead) & receive1C)) begin
				regOutValue <= cardInserted ? outValue : 8'hFF;
			end
		end
	end

	always @(*) begin
		case (cardState)
		WAITCOMMAND: 	outValue = { 3'd0, flags.unknown, flags.fresh, flags.error, 2'd0};
		READ2: 			outValue = 8'h5A;
		READ3:    		outValue = 8'h5D;
		READ4:    		outValue = 8'h00;
		READ5: 			outValue = 8'h00;
		READ6:    		outValue = 8'h5C;
		READ7:    		outValue = 8'h5D;
		READ8:    		outValue = { 6'd0 , cardAddr[9:8] };
		READ9:    		outValue = cardAddr[7:0];
		READGENERIC: 	outValue = valueRead;
		READ138: 		outValue = pipeInternalRead ? valueRead : cardCHKSUM;	// For READGENERIC on last byte (delay one cycle) when we have already transitionned to state READ138.
		READ139: 		outValue = 8'h47 /* 'G' */;

		WRITE2:  		outValue = 8'h5A;
		WRITE3:  		outValue = 8'h5D;
		WRITE4:  		outValue = 8'h00;
		WRITE5:  		outValue = 8'h00;
		WRITEGENERIC:	outValue = 8'h00;
		WRITE134:		outValue = 8'h00;
		WRITE135:		outValue = 8'h5C;
		WRITE136:		outValue = 8'h5D;
		WRITE137:		outValue = cardStatus;
		
		default: 		outValue = 8'hFF; // Include UNDEFINED
		endcase
	end

	assign emitData1C	= regOutValue;
	assign emit1C		= 1'b1; // TODO some timer.

endmodule
