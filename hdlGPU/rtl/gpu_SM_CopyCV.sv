/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_CopyCV(
	input				i_clk,
	input				i_rst,

	input				i_activateCopyCV,
	output				o_CopyInactiveNextCycle,
	output				o_active,
		
	input				i_RegX0_0,
	input				i_pixelY_0,
	input				i_nextPixelY_0,
	input				i_RegSizeW_0,
	input				i_RegSizeH_0,
	input				i_WidthNot1,
	input				i_endVertical,
	
	input				i_canReadL,
	input				i_canReadM,
	input				i_nextPairIsLineLast,
	input				i_commandFIFOaccept,
	
	output				o_loadNext,
	output	[2:0]		o_selNextX,
	output	[2:0]		o_selNextY,
	output	[2:0]		o_memoryCommand,
	
	output				o_swap,			// FIFO swap
	output				o_stencilReadSig,
	output				o_writeStencil,
	output				o_flush,
	output				o_saveL,
	output				o_saveM,
	output				o_readL,
	output				o_readM
);

typedef enum logic[3:0] {
	COPYCV_WAIT			= 4'd0,
	COPYCV_START		= 4'd1,
	COPYCV_COPY			= 4'd2,
	CPY_RS1				= 4'd3,
	CPY_R1				= 4'd4,
	CPY_RS2				= 4'd5,
	CPY_R2				= 4'd6,
	CPY_LWS1			= 4'd7,
	CPY_LW1				= 4'd8,
	CPY_LRS				= 4'd9,
	CPY_LR				= 4'd10,
	CPY_WS2				= 4'd11,
	CPY_W2				= 4'd12,
	CPY_WS3				= 4'd13,
	CPY_W3				= 4'd14,
	CPY_ENDLINE			= 4'd15
} workState_t;

//----------------------------------------------------	
workState_t nextWorkState,currWorkState;
always @(posedge i_clk)
	if (i_rst)
		currWorkState <= COPYCV_WAIT;
	else
		currWorkState <= nextWorkState;
//----------------------------------------------------	
// Internal Registers
reg	lastPair,swap,regSaveM,regSaveL;

// Control Signals
reg setSwap,resetLastPair,setLastPair,readL,readM,changeSwap,resetLM;

//
// Check the L,M,LM are BOTH VALID.
// Checking EACH FIFO that it has data and we want to read is not enough.
// Need to make sure that the OTHER FIFO we want to read is also able for our OWN READ
// Because we read L, M, LM patterns ! If we allow M or L when we wanted to do LM, that's wrong !!!
// And then we add another check that the memory system can receive the result from the FIFO read.
//
wire nextReadValid = ((readL | readM) & ((readL & i_canReadL) | !readL) & ((readM & i_canReadM) | !readM)) & (!flush) & i_commandFIFOaccept;

reg currReadValid;
always @(posedge i_clk)
begin
	if (i_rst) begin
		lastPair 	<= 0;
		swap		<= 0;
		regSaveL	<= 0;
		regSaveM	<= 0;
		currReadValid <= 0;
	end else begin
		if (setLastPair) begin
			lastPair <= 1;
		end
		if (resetLastPair) begin
			lastPair <= 0;
		end
		if (setSwap) begin
			swap	<= i_RegX0_0;
		end else begin
			swap	<= swap ^ changeSwap;
		end
		if (readL | readM) begin
			regSaveM <= readM;
			regSaveL <= readL;
		end else if (resetLM) begin
			regSaveM <= 0;
			regSaveL <= 0;
		end
		currReadValid <= nextReadValid;
	end
end

// --------------------------------------------------------------------
//	 COPY CPU TO VRAM.
// --------------------------------------------------------------------
// Common
reg [2:0]	memoryCommand;
reg [2:0]	selNextX,selNextY;
reg loadNext,stencilReadSig,writeStencil,flush;
reg tmpResetLastPair;
reg tmpSetLastPair;
reg tmpChangeSwap;

always @(*) begin
	nextWorkState			= currWorkState;

	// Common
	selNextX				= X_ASIS;
	selNextY				= Y_ASIS;
	memoryCommand			= MEM_CMD_NONE;
	loadNext				= 0;
	stencilReadSig			= 0;
	writeStencil			= 0;
	flush					= 0;
	
	setSwap					= 0;
	resetLastPair			= 0;
	setLastPair				= 0;
	readL					= 0;
	readM					= 0;
	changeSwap				= 0;
	resetLM					= 0;

	tmpResetLastPair		= 0;
	tmpSetLastPair			= 0;
	tmpChangeSwap			= 0;
	
	if (currReadValid) begin
		memoryCommand = MEM_CMD_PIXEL2VRAM;
		writeStencil  = 1;
	end
	
	case (currWorkState)
	COPYCV_WAIT:
	begin
		if (i_activateCopyCV) begin
			nextWorkState = COPYCV_START;
		end
	end
	COPYCV_START:
	begin
		selNextX		= X_CV_START;
		selNextY		= Y_CV_ZERO;
		loadNext		= 1;
		setSwap			= 1;
		resetLM			= 1;
		// Reset last pair by default, but if WIDTH == 1 -> different.
		resetLastPair	= !((!i_WidthNot1) | i_nextPairIsLineLast);
		setLastPair		=	(!i_WidthNot1) | i_nextPairIsLineLast;
		// We set first pair read here, flag not need to be set for next state !
		// No Zero Size W/H Test -> IMPOSSIBLE By definition.

		// We always have a full word or not here, check is easy.
		if (i_canReadL & i_canReadM) begin
			// Read ALL DATA 1 item in advance -> Remove FIFO LATENCY /*issue.*/
			readL = 1'b1;
			readM = !i_RegX0_0 & (i_WidthNot1);
			nextWorkState	= COPYCV_COPY;
			stencilReadSig	= 1;
		end
	end
	COPYCV_COPY:
	begin
//		stencilSourceAdr		= 0;
		// TRICKY :
		// -----------------------------
		// At the current pixel X,Y we preload the FIFO for the NEXT X,Y coordinate.
		// So setup of readL/readM are ONE PAIR in advance compare to the scanning...
		// -----------------------------
		stencilReadSig	= 1;
		// Accept to process when :
		// - Can write the memory transaction.
		// - Has next data ready OR it is the LAST memory transaction.

		// [Last pair]
		if (lastPair) begin
			if (i_endVertical) begin
				// PURGE...
				readL		= 1'b0;
				readM		= i_RegSizeW_0 & i_RegSizeH_0; // Pump out unused pixel in FIFO.
				flush		= 1'b1;
			end else begin
				selNextY	= Y_TRI_NEXT;
				if (i_WidthNot1) begin
					// WIDTH != 1, standard case
					/* FIRST SEGMENT PATTERN
						W=0	W=0	W=1	W=1
						X=0	X=1	X=0	X=1
					L=	1	1	1	!currY[0]
					M=	1	0	1	currY[0]
					*/
					case ({i_RegSizeW_0,i_RegX0_0})
					2'b00: begin
						readL = 1'b1; readM = 1'b1;
					end
					2'b01: begin
						readL = 1'b1; readM = 1'b0;
					end
					2'b10: begin
						readL = 1'b1; readM = 1'b1;
					end
					2'b11: begin
						readL = !i_nextPixelY_0; readM = i_nextPixelY_0;
					end
					endcase
					tmpChangeSwap	= i_RegSizeW_0 & i_WidthNot1; // If width=1, do NOT swap.
				end else begin
					// Only 1 pixel WIDTH pattern...
					// Alternate ODD/EVEN lines...
					readL		= !i_nextPixelY_0;
					readM		=  i_nextPixelY_0;
					tmpChangeSwap	= 1'b1;
				end
			end
			selNextX			= X_CV_START;
			tmpResetLastPair	= i_WidthNot1 & (!i_nextPairIsLineLast);
		end else begin
			// [MIDDLE OR FIRST SEGMENT]
			//	  PRELOAD NEXT SEGMENT...
			if (i_nextPairIsLineLast) begin
				/* LAST SEGMENT PATTERN
					W=0	W=0	W=1		W=1
					X=0	X=1	X=0		X=1
				L = 1	0	!Y[0]	1
				M = 1	1	Y[0]	1	*/
				case ({i_RegSizeW_0,i_RegX0_0})
				2'b00: begin
					readL = 1'b1; readM = 1'b1;
				end
				2'b01: begin
					readL = 1'b0; readM = 1'b1;
				end
				2'b10: begin
					// L on first line (even), M on second (odd)
					readL = !i_pixelY_0; readM = i_pixelY_0;
				end
				2'b11: begin
					readL = 1'b1; readM = 1'b1;
				end
				endcase

				tmpSetLastPair	= 1'b1; // TODO : Rename FirstPair into LastPair.
			end else begin
				readL = 1'b1;
				readM = 1'b1;
			end
			selNextX	= X_TRI_NEXT;
		end
		if (nextReadValid | (lastPair & i_endVertical)) begin
			loadNext	  = nextReadValid;
			nextWorkState = lastPair & i_endVertical ? COPYCV_WAIT : COPYCV_COPY;
			changeSwap    = tmpChangeSwap;
			resetLastPair = tmpResetLastPair;
			setLastPair   = tmpSetLastPair;
		end
	end
	default: begin
		// Invalid State
		nextWorkState	= COPYCV_WAIT;
	end
	endcase
end

assign o_active					= (currWorkState != COPYCV_WAIT);
assign o_CopyInactiveNextCycle	= o_active & (nextWorkState == COPYCV_WAIT);

assign o_loadNext				= loadNext;
assign o_selNextX				= selNextX;
assign o_selNextY				= selNextY;
assign o_memoryCommand			= memoryCommand;
assign o_stencilReadSig			= stencilReadSig;
assign o_writeStencil			= writeStencil;
assign o_flush					= flush;

assign o_swap					= swap;
assign o_saveL					= regSaveL;
assign o_saveM					= regSaveM;
assign o_readL					= readL &  nextReadValid; 
assign o_readM					= readM & (nextReadValid | flush); // Allow FIFO read even if no write to command for LAST

endmodule
