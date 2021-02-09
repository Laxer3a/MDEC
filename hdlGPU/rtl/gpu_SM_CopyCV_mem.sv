/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_CopyCV_mem(
	input				i_clk,
	input				i_rst,

	//
	// GPU Registers / Stencil Cache / FIFO Side
	//
	input				i_activateCopyCV,
	output				o_CopyInactiveNextCycle,
	output				o_active,

	// Registers
	input				GPU_REG_CheckMaskBit,
	input				GPU_REG_ForcePixel15MaskSet,
	input signed [11:0] RegX0,
	input signed [11:0] RegY0,
	input	[10:0]		RegSizeW,
	input	[9:0]		RegSizeH,
	
	// Stencil [Read]
	output				o_stencilReadSig,
	output 	[14:0]		o_stencilReadAdr,
	output	 [2:0]		o_stencilReadPair,
	output	 [1:0]		o_stencilReadSelect,
	input	[1:0]		i_stencilReadValue,
	// Stencil [Write]
	output	 [2:0]		o_stencilWritePairC,
	output	 [1:0]		o_stencilWriteSelectC,
	output	 [1:0]		o_stencilWriteValueC,
	output				o_stencilFullMode,
	output				o_stencilWriteSigC,
	output	[14:0]		o_stencilWriteAdrC,

	// FIFO
	input				i_canReadL,
	input				i_canReadM,
	output				o_readL,
	output				o_readM,
	input	[15:0]		i_fifoDataOutM,
	input	[15:0]		i_fifoDataOutL,

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    output           	o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input            	i_busy,           // Memory busy 1 => can not use.
    output   [1:0]   	o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           	o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]   	o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   	o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   	o_writeMask,

	/*
    input  [255:0]   	i_dataIn,
    input            	i_dataInValid,
	*/
    output [255:0]   	o_dataOut
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

wire		WidthNot1	= |RegSizeW[10:1];

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

reg signed [11:0] pixelX, pixelY,nextPixelX,nextPixelY;

wire dir						= 0;
wire renderYOffsetInterlace 	= 0;
wire InterlaceRender			= 0;
wire signed [11:0] nextLineY	= pixelY + { 9'b0 , InterlaceRender , !InterlaceRender };	// +1 for normal mode, +2 for interlaced locked render primitives
wire endVertical				= (nextLineY[9:0] >= RegSizeH);
wire [11:0]	XE					= { RegX0 } + { 1'b0, RegSizeW } + {{11{1'b1}}, RegX0[0] ^ RegSizeW[0]};
wire nextPairIsLineLast			= (nextPixelX == XE);

always @(posedge i_clk)
begin
    if (loadNext) begin
        pixelX <= nextPixelX;
        pixelY <= nextPixelY;
    end
end

wire  [9:0]		scrY	=     pixelY[9:0] + RegY0[9:0];
wire  [9:0]  nextScrY	= nextPixelY[9:0] + RegY0[9:0]; // simply scrY +1 ????

    // CPU 2 VRAM : [16,16,2,15,...]

//
// Check the L,M,LM are BOTH VALID.
// Checking EACH FIFO that it has data and we want to read is not enough.
// Need to make sure that the OTHER FIFO we want to read is also able for our OWN READ
// Because we read L, M, LM patterns ! If we allow M or L when we wanted to do LM, that's wrong !!!
// And then we add another check that the memory system can receive the result from the FIFO read.
//
wire nextReadValid = ((readL | readM) & ((readL & i_canReadL) | !readL) & ((readM & i_canReadM) | !readM)) & (!flush) & (!i_busy);

wire [15:0] LPixel = swap ? i_fifoDataOutM : i_fifoDataOutL;
wire [15:0] RPixel = swap ? i_fifoDataOutL : i_fifoDataOutM;
wire validL        = swap ? regSaveM : regSaveL;
wire validR        = swap ? regSaveL : regSaveM;
wire cmd1ValidL	= (validL & !GPU_REG_CheckMaskBit) | (validL & (!i_stencilReadValue[0]));
wire cmd1ValidR	= (validR & !GPU_REG_CheckMaskBit) | (validR & (!i_stencilReadValue[1]));
wire WRPixelL15 = LPixel[15] | GPU_REG_ForcePixel15MaskSet; // No sticky bit from source.
wire WRPixelR15 = RPixel[15] | GPU_REG_ForcePixel15MaskSet; // No sticky bit from source.


reg [ 15:0] writtenPixelMask;
reg [255:0] writtenPixelBuffer;

always @(posedge i_clk)
begin
	if (i_rst | resetMaskBank | (!o_active)) begin
		writtenPixelMask <= 16'd00;
	end else if (currReadValid) begin
		case (pixelX[3:1])
		3'd0: begin
			writtenPixelMask[ 0] <= cmd1ValidL;
			writtenPixelMask[ 1] <= cmd1ValidR;
			writtenPixelBuffer[ 15:  0] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[ 31: 16] <= { WRPixelR15, RPixel[14:0] };
		end
		3'd1: begin
			writtenPixelMask[ 2] <= cmd1ValidL;
			writtenPixelMask[ 3] <= cmd1ValidR;
			writtenPixelBuffer[ 47: 32] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[ 63: 48] <= { WRPixelR15, RPixel[14:0] };
		end
		3'd2: begin
			writtenPixelMask[ 4] <= cmd1ValidL;
			writtenPixelMask[ 5] <= cmd1ValidR;
			writtenPixelBuffer[ 79: 64] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[ 95: 80] <= { WRPixelR15, RPixel[14:0] };
		end
		3'd3: begin
			writtenPixelMask[ 6] <= cmd1ValidL;
			writtenPixelMask[ 7] <= cmd1ValidR;
			writtenPixelBuffer[111: 96] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[127:112] <= { WRPixelR15, RPixel[14:0] };
		end
		3'd4: begin
			writtenPixelMask[ 8] <= cmd1ValidL;
			writtenPixelMask[ 9] <= cmd1ValidR;
			writtenPixelBuffer[143:128] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[159:144] <= { WRPixelR15, RPixel[14:0] };
		end
		3'd5: begin
			writtenPixelMask[10] <= cmd1ValidL;
			writtenPixelMask[11] <= cmd1ValidR;
			writtenPixelBuffer[175:160] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[191:176] <= { WRPixelR15, RPixel[14:0] };
		end
		3'd6: begin
			writtenPixelMask[12] <= cmd1ValidL;
			writtenPixelMask[13] <= cmd1ValidR;
			writtenPixelBuffer[207:192] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[223:208] <= { WRPixelR15, RPixel[14:0] };
		end
		default  : begin
			writtenPixelMask[14] <= cmd1ValidL;
			writtenPixelMask[15] <= cmd1ValidR;
			writtenPixelBuffer[239:224] <= { WRPixelL15, LPixel[14:0] };
			writtenPixelBuffer[255:240] <= { WRPixelR15, RPixel[14:0] };
		end
		endcase
	end
end

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
			swap	<= RegX0[0];
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

reg [2:0]	selNextX,selNextY;
always @(*)
begin
    case (selNextX)
        X_TRI_NEXT:		nextPixelX	= pixelX + { {10{dir}}, 2'b10 };	// -2,0,+2
        X_CV_START:		nextPixelX	= { 2'b0, RegX0[9:1], 1'b0 };
        default:		nextPixelX	= pixelX;
    endcase

    case (selNextY)
        Y_TRI_NEXT:		nextPixelY	= nextLineY;
        Y_CV_ZERO:		nextPixelY	= { 11'd0, renderYOffsetInterlace };
        default:		nextPixelY	= pixelY;
    endcase
end


// --------------------------------------------------------------------
//	 COPY CPU TO VRAM.
// --------------------------------------------------------------------
// Common
reg loadNext,stencilReadSig,flush;
reg tmpResetLastPair;
reg tmpSetLastPair;
reg tmpChangeSwap;

always @(*) begin
	nextWorkState			= currWorkState;

	// Common
	selNextX				= X_ASIS;
	selNextY				= Y_ASIS;
	loadNext				= 0;
	stencilReadSig			= 0;
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
		resetLastPair	= !((!WidthNot1) | nextPairIsLineLast);
		setLastPair		=	(!WidthNot1) | nextPairIsLineLast;
		// We set first pair read here, flag not need to be set for next state !
		// No Zero Size W/H Test -> IMPOSSIBLE By definition.

		// We always have a full word or not here, check is easy.
		if (i_canReadL & i_canReadM) begin
			// Read ALL DATA 1 item in advance -> Remove FIFO LATENCY /*issue.*/
			readL = 1'b1;
			readM = !RegX0[0] & (WidthNot1);
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
			if (endVertical) begin
				// PURGE...
				readL		= 1'b0;
				readM		= RegSizeW[0] & RegSizeH[0]; // Pump out unused pixel in FIFO.
				flush		= 1'b1;
			end else begin
				selNextY	= Y_TRI_NEXT;
				if (WidthNot1) begin
					// WIDTH != 1, standard case
					/* FIRST SEGMENT PATTERN
						W=0	W=0	W=1	W=1
						X=0	X=1	X=0	X=1
					L=	1	1	1	!currY[0]
					M=	1	0	1	currY[0]
					*/
					case ({RegSizeW[0],RegX0[0]})
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
						readL = !nextPixelY[0]; readM = nextPixelY[0];
					end
					endcase
					tmpChangeSwap	= RegSizeW[0] & WidthNot1; // If width=1, do NOT swap.
				end else begin
					// Only 1 pixel WIDTH pattern...
					// Alternate ODD/EVEN lines...
					readL		= !nextPixelY[0];
					readM		=  nextPixelY[0];
					tmpChangeSwap	= 1'b1;
				end
			end
			selNextX			= X_CV_START;
			tmpResetLastPair	= WidthNot1 & (!nextPairIsLineLast);
		end else begin
			// [MIDDLE OR FIRST SEGMENT]
			//	  PRELOAD NEXT SEGMENT...
			if (nextPairIsLineLast) begin
				/* LAST SEGMENT PATTERN
					W=0	W=0	W=1		W=1
					X=0	X=1	X=0		X=1
				L = 1	0	!Y[0]	1
				M = 1	1	Y[0]	1	*/
				case ({RegSizeW[0],RegX0[0]})
				2'b00: begin
					readL = 1'b1; readM = 1'b1;
				end
				2'b01: begin
					readL = 1'b0; readM = 1'b1;
				end
				2'b10: begin
					// L on first line (even), M on second (odd)
					readL = !pixelY[0]; readM = pixelY[0];
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
		if (nextReadValid | (lastPair & endVertical)) begin
			loadNext	  = nextReadValid;
			nextWorkState = lastPair & endVertical ? COPYCV_WAIT : COPYCV_COPY;
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

wire [14:0] nextAdr				= { nextScrY[8:0], nextPixelX[9:4] };
wire [14:0] currAdr				= {     scrY[8:0],     pixelX[9:4] };

wire        newBlock			= nextAdr != currAdr;
wire		resetMaskBank		= newBlock & o_command;

assign o_readL					= readL &  nextReadValid; 
assign o_readM					= readM & (nextReadValid | flush); 		// Allow FIFO read even if no write to command for LAST

assign o_stencilReadAdr			= nextAdr;	// Other modes.
assign o_stencilReadPair		= { nextPixelX[3:1] };
assign o_stencilReadSelect		= 2'b11;
assign o_stencilReadSig			= stencilReadSig;

assign o_stencilWritePairC		= pixelX[3:1];
assign o_stencilWriteSelectC	= { cmd1ValidR , cmd1ValidL };
assign o_stencilWriteValueC		= { WRPixelR15 , WRPixelL15 };
assign o_stencilFullMode		= 0;
assign o_stencilWriteSigC		= currReadValid;
assign o_stencilWriteAdrC		= currAdr;

// Send Burst command only on transition from one block to another or when last write occured.
assign o_command				= currReadValid & (newBlock | (lastPair & endVertical));			// Assume that i_busy at cycle 0 is also at cycle 1.
assign o_commandSize			= 2'd1; // 32 byte.
assign o_write					= o_command;
assign o_adr					= currAdr;
assign o_subadr					= 3'd0;
assign o_dataOut				= writtenPixelBuffer;
assign o_writeMask				= writtenPixelMask;

endmodule
