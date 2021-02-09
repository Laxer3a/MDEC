/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_CopyVV_mem(
	input					i_clk,
	input					i_rst,

	// Control signals
	input					i_activateCopyVV,
	output					o_CopyInactiveNextCycle,
	output					o_active,

	// Setup with registers
	input					i_isNegXAxis,	// X1-X0 sign.
	input	signed [11:0]	RegX0,
	input	signed [11:0] 	RegX1,
	input	signed [11:0]	RegY0,
	input	signed [11:0]	RegY1,
	input 		   [10:0]	RegSizeW,
	input		   [ 9:0]	RegSizeH,
	input					GPU_REG_CheckMaskBit,
	input					GPU_REG_ForcePixel15MaskSet,
	
	// Stencil cache.
	input	[15:0]			i_stencilReadValue16,
	output					o_stencilReadSig,
	output					o_stencilWrite,
	output					o_stencilFullMode,
	output	[15:0]			o_stencilWriteValue16,
	output	[15:0]			o_stencilWriteMask16,
	
	// Identical to o_adr
	output  [14:0]			o_stencilReadAdr,
	output  [14:0]			o_stencilWriteAdr,
	
	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    output           		o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input            		i_busy,           // Memory busy 1 => can not use.
    output   [1:0]   		o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           		o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]   		o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   		o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   		o_writeMask,

    input  [255:0]   		i_dataIn,
    input            		i_dataInValid,
    output [255:0]   		o_dataOut
);

wire commandFIFOaccept	= !i_busy;

parameter   WAIT_CMD			= 2'd0,
			READ_VV				= 2'd1,
			WRITE_VV			= 2'd2;

typedef enum logic[3:0] {
	COPY_WAIT			= 4'd0,
	COPY_INIT			= 4'd1,
	COPY_START_LINE		= 4'd2,
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
		currWorkState <= COPY_WAIT;
	else
		currWorkState <= nextWorkState;
//----------------------------------------------------	

// Common
reg [1:0]	memoryCommand;
reg [2:0]	selNextY;
reg loadNext,resetXCounter,stencilReadSig,incrementXCounter;

// Specific
reg resetBank,useDest,clearOtherBank,switchBank,stencilReadSigW,clearBank0,clearBank1;

reg         cpyBank;

// AFTER cpyBank is used !!!!
always @(posedge i_clk)
    if (resetBank || i_rst) begin
        cpyBank <= 1'b0;
    end else begin
        cpyBank <= cpyBank ^ switchBank;
    end

wire	xCopyDirectionIncr = i_isNegXAxis;
wire	writeBankOld = performSwitch & (cpyBank ^ (!xCopyDirectionIncr));

wire storeStencilRead = memoryCommand[0]; // READ_VV
reg [31:0]  maskReadCache;
reg [31:0]  stencilReadCache;

always @(posedge i_clk)
begin
    // BEFORE cpyBank UPDATE !!!
    if (storeStencilRead) begin
        if (cpyBank) begin
            stencilReadCache[31:16] <= i_stencilReadValue16;
            maskReadCache	[31:16] <= maskRead16;
            if (clearOtherBank) begin
                maskReadCache	[15:0] <= 16'd0;
            end
        end else begin
            stencilReadCache[15: 0] <= i_stencilReadValue16;
            maskReadCache	[15: 0] <= maskRead16;
            if (clearOtherBank) begin
                maskReadCache	[31:16] <= 16'd0;
            end
        end
    end

    if (clearBank0) begin // storeStencilRead is always False, no priority issues.
        maskReadCache	[15: 0] <= 16'd0;
    end

    if (clearBank1) begin // storeStencilRead is always False, no priority issues.
        maskReadCache	[31:16] <= 16'd0;
    end
end


reg	 [ 6:0] counterXDst;
reg	 [ 6:0] counterXSrc;
reg signed [11:0] pixelX, pixelY,nextPixelX,nextPixelY;
wire InterlaceRender = 0;
wire renderYOffsetInterlace = 0;
wire signed [11:0] nextLineY = pixelY + { 9'b0 , InterlaceRender , !InterlaceRender };	// +1 for normal mode, +2 for interlaced locked render primitives

wire [10:0] fullSizeSrc			= RegSizeW + { 7'd0, RegX0[3:0] };
wire [10:0] fullSizeDst			= RegSizeW + { 7'd0, RegX1[3:0] };

wire        srcDistExact16Pixel	= !(|fullSizeSrc[3:0]);
wire        dstDistExact16Pixel	= !(|fullSizeDst[3:0]);

wire  [6:0] lengthBlockSrcHM1	= fullSizeSrc[10:4] + {7{srcDistExact16Pixel}};	// If exact 16, retract 1 block. (Add -1)
wire  [6:0] lengthBlockDstHM1	= fullSizeDst[10:4] + {7{dstDistExact16Pixel}};

wire  [6:0] OppAdrXSrc			= lengthBlockSrcHM1 - counterXSrc;
wire  [6:0] OppAdrXDst			= lengthBlockDstHM1 - counterXDst;

wire  [5:0] adrXSrc = xCopyDirectionIncr ? counterXSrc[5:0] : OppAdrXSrc[5:0];
wire  [5:0] adrXDst = xCopyDirectionIncr ? counterXDst[5:0] : OppAdrXDst[5:0];

wire [3:0] rightPos;
wire [15:0] maskRead16;

// wire  [6:0] fullX				= (useDest           ? adrXDst : adrXSrc)          + { 1'b0, useDest ? RegX1[9:4] : RegX0[9:4] };
gpu_masking gpu_masking_inst(
	.RegX0_4bit				(RegX0[3:0]),
	.RegSizeW_4bit			(RegSizeW[3:0]),
	
	.i_adrXSrc				(adrXSrc),
	.i_lengthBlkSrcHM1_6bit	(lengthBlockSrcHM1[5:0]),
	
	.o_rightPos				(rightPos),
	.o_maskRead16			(maskRead16)
);

wire [3:0]  sxe16    		= rightPos + 4'b1111;
wire dblLoadL2R				= RegX1[3:0] < RegX0[3:0];

wire [4:0] tmpidx			= { dblLoadL2R , RegX0[3:0] } + { 1'b1, ~RegX1[3:0] } + 5'd1;
wire [3:0] cpyIdx			= tmpidx[3:0];

wire dblLoadR2L				= sxe16 < cpyIdx;
wire isDoubleLoad			= xCopyDirectionIncr ? dblLoadL2R : dblLoadR2L;
wire isLastSegment  		= (counterXSrc==lengthBlockSrcHM1);
wire isLastSegmentDst		= (counterXDst==lengthBlockDstHM1);
wire  performSwitch			= |cpyIdx; // If ZERO, NO SWITCH !

wire	endVertical			= (nextLineY[9:0] >= RegSizeH);

wire isLongLine				= RegSizeW[9] | RegSizeW[10]; // At least >= 512
wire allowNextRead			= (!isLastSegment) | isLongLine;

always @(*)
begin
    case (selNextY)
        Y_TRI_NEXT:		nextPixelY	= nextLineY;
        Y_CV_ZERO:		nextPixelY	= { 11'd0, renderYOffsetInterlace };
        default:		nextPixelY	= pixelY;
    endcase
end

always @(posedge i_clk)
begin
    if (loadNext) begin
        pixelY <= nextPixelY;
    end
end

always @(posedge i_clk)
begin
    counterXSrc <= (resetXCounter) ? 7'd0 : counterXSrc + { 6'd0 ,incrementXCounter & (!useDest) };
    counterXDst <= (resetXCounter) ? 7'd0 : counterXDst + { 6'd0 ,incrementXCounter &   useDest  };
end

wire [5:0]		scrSrcX = adrXSrc[5:0] + RegX0[9:4];
wire [5:0] 		scrDstX = adrXDst[5:0] + RegX1[9:4];
wire [9:0]		scrY	= pixelY[9:0]  + RegY0[9:0];
wire [8:0]      scrDstY	= pixelY[8:0]  + RegY1[8:0];

// --------------------------------------------------------------------
//	 COPY VRAM STATE MACHINE
// --------------------------------------------------------------------
always @(*)
begin
	nextWorkState			= currWorkState;

	// Common
	selNextY				= Y_ASIS;
	memoryCommand			= WAIT_CMD;
	loadNext				= 0;
	resetXCounter			= 0;
	stencilReadSig			= 0;
	incrementXCounter		= 0;

	// Specific
	resetBank				= 0;
	useDest					= 0;
	clearOtherBank			= 0;
	switchBank				= 0;
	stencilReadSigW			= 0;
	clearBank0				= 0;
	clearBank1				= 0;

	case (currWorkState)
	COPY_WAIT:
	begin
		if (i_activateCopyVV) begin
			nextWorkState = COPY_INIT;
		end
	end
	COPY_INIT:
	begin
		nextWorkState		= COPY_START_LINE;
		selNextY = Y_CV_ZERO; loadNext = 1;
	end
	COPY_START_LINE:
	begin
		// [CPY_START] : Beginning of a line.
		// Copy never have 'empty surfaces'

		// Do start current line...
		nextWorkState		= CPY_RS1;
		resetBank			= 1;
		resetXCounter		= 1; // No load loadNext here.

		// TODO resetStencilTmp		= 1;
	end
	CPY_RS1: // Read Stencil.
	begin
		stencilReadSig	= 1; // Adr setup auto.
		if (commandFIFOaccept) begin
			nextWorkState = CPY_R1;
		// else nextWorkState stay the same
		end
	end
	CPY_R1:
	begin
		// Here we know that commandFIFOaccept is 1 (Previous state)
		// Store (Stencil & Mask) in temporary here
		incrementXCounter	= 1; useDest = 0; // Increment Source.
		// TODO storeStencilTmp		= 1;
		// TODO switchBank			= 1;
		clearOtherBank		= 1;
		memoryCommand		= READ_VV;

		if (allowNextRead) begin
			if (isDoubleLoad) begin
				nextWorkState	= CPY_RS2;
			end else begin
				nextWorkState	= CPY_LWS1;
			end
		end else begin
			nextWorkState		= CPY_WS2;
		end

		if (isDoubleLoad) begin
			if (allowNextRead) begin
				switchBank		= performSwitch;
			end else begin
				switchBank		= !performSwitch;
			end
		end else begin
			switchBank		= performSwitch;
		end

		//-------------------
		/* OLD BUGGY CODE
		if (allowNextRead) begin
			if (isDoubleLoad) begin
				switchBank		= performSwitch;
				nextWorkState	= CPY_RS2;
			end else begin
				// If PerformSwitch = 1 => Double bank switch -> No Switch !
				// If PerformSwitch = 0 => Single bank switch -> 1	Switch !
				switchBank		= !performSwitch;
				nextWorkState	= CPY_LWS1;
			end
		end else begin
			switchBank			= performSwitch;
			nextWorkState		= CPY_WS2;
		end
		*/
	end
	CPY_RS2:
	begin
		stencilReadSig	= 1; // Adr setup auto.
		if (commandFIFOaccept) begin
			nextWorkState = CPY_R2;
		// else nextWorkState stay the same
		end
	end
	CPY_R2:
	begin
		incrementXCounter	= 1; useDest = 0; // Increment Source.
		// TODO storeStencilTmp		= 1;
		memoryCommand		= READ_VV;
		switchBank			= performSwitch;

		if (allowNextRead) begin
			nextWorkState	= CPY_LWS1;
		end else begin
			nextWorkState	= CPY_WS2;
		end
	end
	CPY_LWS1:
	begin
		stencilReadSigW		= 1;

		if (commandFIFOaccept) begin
			nextWorkState	= CPY_LW1;
		// else nextWorkState stay the same
		end
	end
	CPY_LW1:
	begin
		incrementXCounter	= 1; useDest = 1;
		memoryCommand		= WRITE_VV;
		nextWorkState		= CPY_LRS;
	end
	CPY_LRS:
	begin
		stencilReadSig	= 1; // Adr setup auto.
		if (commandFIFOaccept) begin
			nextWorkState	= CPY_LR;
		// else nextWorkState stay the same
		end
	end
	CPY_LR:
	begin
		incrementXCounter	= 1; useDest = 0; // Increment Source.

		memoryCommand		= READ_VV;
		switchBank			= performSwitch;

		if (!isLastSegment/* = allowNextRead, do NOT check isLongLine ! */) begin
			nextWorkState	= CPY_LWS1;
		end else begin
			nextWorkState	= CPY_WS2;
		end
	end
	CPY_WS2:
	begin
		stencilReadSigW		= 1;

		if (commandFIFOaccept) begin
			nextWorkState	= CPY_W2;
		// else nextWorkState stay the same
		end
	end
	CPY_W2:
	begin
		// Here : at this cycle we receive value from stencil READ.
		// And do now a STENCIL WRITE.
		incrementXCounter	= 1; useDest = 1;
		memoryCommand		= WRITE_VV;

		clearBank0			= !cpyBank;
		clearBank1			= cpyBank;
		switchBank			= performSwitch;

		if (!isLastSegmentDst) begin
			nextWorkState	= CPY_WS3;
		end else begin
			nextWorkState	= CPY_ENDLINE;
		end
	end
	CPY_WS3:
	begin
		stencilReadSigW		= 1;

		if (commandFIFOaccept) begin
			nextWorkState	= CPY_W3;
		// else nextWorkState stay the same
		end
	end
	CPY_W3:
	begin
		memoryCommand		= WRITE_VV;
		nextWorkState		= CPY_ENDLINE;
	end
	CPY_ENDLINE:
	begin
		selNextY			= Y_TRI_NEXT; loadNext = 1;

		if (endVertical) begin
			// End of copy primitive...
			nextWorkState	= COPY_WAIT;
		end else begin
			nextWorkState	= COPY_START_LINE;
		end
	end
	endcase
end

reg			waitRead;
reg [15:0]	storageMask;
reg [31:0]	maskBank;
reg [511:0] vvReadCache;
reg         bankID;
wire [15:0] cmdMask 					= i_stencilReadValue16;
wire		hasCommand					= (memoryCommand != WAIT_CMD);
wire		sendCommandToMemory			= (!i_busy && hasCommand && (!waitRead));
wire		sendCommandToMemoryNOBUSY	=            (hasCommand && (!waitRead));
wire		resetWait					= (waitRead && i_dataInValid);

reg loadVVBank;

always @(posedge i_clk) begin
	if (i_rst) begin
		waitRead	<= 0;
		loadVVBank	<= 0;
		bankID		<= 0;
	end else begin
		if (waitRead && resetWait) begin
			loadVVBank	<= 0;
		end

		// Send command and is READ COMMAND. (OVERRIDE RESET)
		if (sendCommandToMemory & (memoryCommand == READ_VV)) begin
			waitRead <= 1;
		end else begin
			if (waitRead && resetWait) begin
				waitRead <= 0;
			end
		end

		// [Read BURST Command ONLY]
		if (sendCommandToMemory & (memoryCommand == READ_VV)) begin
			// Bank ID used only in READ (when result comes back)
			bankID		<= cpyBank;
			loadVVBank	<= 1;
			if (cpyBank) begin
				maskBank[31:16]	<= maskRead16;	// Pixel Select Mask
				if (clearOtherBank) begin	// Clear other bank ?
					maskBank[15:0] <= 16'd0;
				end
			end else begin
				maskBank[15:0] 	<= maskRead16;	// Pixel Select Mask
				if (clearOtherBank) begin	// Clear other bank ?
					maskBank[31:16] <= 16'd0;
				end
			end
		end
		
		// Mask Bank will clear for the NEXT READ/WRITE sequence.
		if (sendCommandToMemory & (memoryCommand == WRITE_VV)) begin
			if (clearBank0) begin
				maskBank[15: 0] <= 16'd0;
			end
			if (clearBank1) begin
				maskBank[31:16] <= 16'd0;
			end
		end
	end
end

always @(posedge i_clk) begin
	if (waitRead && loadVVBank && i_dataInValid) begin
		if (bankID) begin
			vvReadCache[511:256] <= i_dataIn;
		end else begin
			vvReadCache[255:  0] <= i_dataIn;
		end
	end
end

wire [4:0] rotationAmount	= {writeBankOld,cpyIdx};
wire [255:0] storage;
ROL512 ROL512_inst(
	.inp		(vvReadCache),
	.rot		(rotationAmount),
	.out		(storage)
);

reg [31:0] tmpMsk;
always @(*) begin
	// 1st step
	tmpMsk = rotationAmount[4] ? { maskBank[15:0] , maskBank[31:16] } : maskBank;
	// 2nd step
	case (rotationAmount[3:0])
	4'h0: storageMask = tmpMsk[15: 0];
	4'h1: storageMask = tmpMsk[16: 1];
	4'h2: storageMask = tmpMsk[17: 2];
	4'h3: storageMask = tmpMsk[18: 3];
	4'h4: storageMask = tmpMsk[19: 4];
	4'h5: storageMask = tmpMsk[20: 5];
	4'h6: storageMask = tmpMsk[21: 6];
	4'h7: storageMask = tmpMsk[22: 7];
	4'h8: storageMask = tmpMsk[23: 8];
	4'h9: storageMask = tmpMsk[24: 9];
	4'hA: storageMask = tmpMsk[25:10];
	4'hB: storageMask = tmpMsk[26:11];
	4'hC: storageMask = tmpMsk[27:12];
	4'hD: storageMask = tmpMsk[28:13];
	4'hE: storageMask = tmpMsk[29:14];
	4'hF: storageMask = tmpMsk[30:15];
	endcase
end

wire [255:0] currVVPixelWFinal		= { 
	GPU_REG_ForcePixel15MaskSet | storage[255], storage[254:240],
	GPU_REG_ForcePixel15MaskSet | storage[239], storage[238:224],
	GPU_REG_ForcePixel15MaskSet | storage[223], storage[222:208],
	GPU_REG_ForcePixel15MaskSet | storage[207], storage[206:192],
	
	GPU_REG_ForcePixel15MaskSet | storage[191], storage[190:176],
	GPU_REG_ForcePixel15MaskSet | storage[175], storage[174:160],
	GPU_REG_ForcePixel15MaskSet | storage[159], storage[158:144],
	GPU_REG_ForcePixel15MaskSet | storage[143], storage[142:128],

	GPU_REG_ForcePixel15MaskSet | storage[127], storage[126:112],
	GPU_REG_ForcePixel15MaskSet | storage[111], storage[110: 96],
	GPU_REG_ForcePixel15MaskSet | storage[ 95], storage[ 94: 80],
	GPU_REG_ForcePixel15MaskSet | storage[ 79], storage[ 78: 64],

	GPU_REG_ForcePixel15MaskSet | storage[ 63], storage[ 62: 48],
	GPU_REG_ForcePixel15MaskSet | storage[ 47], storage[ 46: 32],
	GPU_REG_ForcePixel15MaskSet | storage[ 31], storage[ 30: 16],
	GPU_REG_ForcePixel15MaskSet | storage[ 15], storage[ 14:  0]
};

wire [15:0] currVVPixelWFinalSel= ({16{!GPU_REG_CheckMaskBit}} | (~cmdMask /*Here is it a stencil, not a mask*/)) & storageMask; // Write all pixels if GPU_REG_CheckMaskBit=0, else write Pixel when Stencil IS 0.

reg  [15:0] stencilReadRemapped;
reg  [15:0] maskReadRemapped;
// Mask and [Full_selection_if_GPU_DRAW_ALWAYS or inverse_stencilRead_At_target]

always @(*)
begin
    // TODO : Replace with Logarithm shift stage. ( << 1, << 2, << 4, << 8, << 16 )
    case ({writeBankOld,cpyIdx})
    5'h00: begin stencilReadRemapped =  stencilReadCache[15: 0];                         maskReadRemapped =  maskReadCache[15: 0];                         end
    5'h01: begin stencilReadRemapped =  stencilReadCache[16: 1];                         maskReadRemapped =  maskReadCache[16: 1];                         end
    5'h02: begin stencilReadRemapped =  stencilReadCache[17: 2];                         maskReadRemapped =  maskReadCache[17: 2];                         end
    5'h03: begin stencilReadRemapped =  stencilReadCache[18: 3];                         maskReadRemapped =  maskReadCache[18: 3];                         end
    5'h04: begin stencilReadRemapped =  stencilReadCache[19: 4];                         maskReadRemapped =  maskReadCache[19: 4];                         end
    5'h05: begin stencilReadRemapped =  stencilReadCache[20: 5];                         maskReadRemapped =  maskReadCache[20: 5];                         end
    5'h06: begin stencilReadRemapped =  stencilReadCache[21: 6];                         maskReadRemapped =  maskReadCache[21: 6];                         end
    5'h07: begin stencilReadRemapped =  stencilReadCache[22: 7];                         maskReadRemapped =  maskReadCache[22: 7];                         end
    5'h08: begin stencilReadRemapped =  stencilReadCache[23: 8];                         maskReadRemapped =  maskReadCache[23: 8];                         end
    5'h09: begin stencilReadRemapped =  stencilReadCache[24: 9];                         maskReadRemapped =  maskReadCache[24: 9];                         end
    5'h0A: begin stencilReadRemapped =  stencilReadCache[25:10];                         maskReadRemapped =  maskReadCache[25:10];                         end
    5'h0B: begin stencilReadRemapped =  stencilReadCache[26:11];                         maskReadRemapped =  maskReadCache[26:11];                         end
    5'h0C: begin stencilReadRemapped =  stencilReadCache[27:12];                         maskReadRemapped =  maskReadCache[27:12];                         end
    5'h0D: begin stencilReadRemapped =  stencilReadCache[28:13];                         maskReadRemapped =  maskReadCache[28:13];                         end
    5'h0E: begin stencilReadRemapped =  stencilReadCache[29:14];                         maskReadRemapped =  maskReadCache[29:14];                         end
    5'h0F: begin stencilReadRemapped =  stencilReadCache[30:15];                         maskReadRemapped =  maskReadCache[30:15];                         end
    5'h10: begin stencilReadRemapped =  stencilReadCache[31:16];                         maskReadRemapped =  maskReadCache[31:16];                         end
    5'h11: begin stencilReadRemapped = {stencilReadCache   [0],stencilReadCache[31:17]}; maskReadRemapped = {maskReadCache   [0],maskReadCache[31:17]}; end
    5'h12: begin stencilReadRemapped = {stencilReadCache[ 1:0],stencilReadCache[31:18]}; maskReadRemapped = {maskReadCache[ 1:0],maskReadCache[31:18]}; end
    5'h13: begin stencilReadRemapped = {stencilReadCache[ 2:0],stencilReadCache[31:19]}; maskReadRemapped = {maskReadCache[ 2:0],maskReadCache[31:19]}; end
    5'h14: begin stencilReadRemapped = {stencilReadCache[ 3:0],stencilReadCache[31:20]}; maskReadRemapped = {maskReadCache[ 3:0],maskReadCache[31:20]}; end
    5'h15: begin stencilReadRemapped = {stencilReadCache[ 4:0],stencilReadCache[31:21]}; maskReadRemapped = {maskReadCache[ 4:0],maskReadCache[31:21]}; end
    5'h16: begin stencilReadRemapped = {stencilReadCache[ 5:0],stencilReadCache[31:22]}; maskReadRemapped = {maskReadCache[ 5:0],maskReadCache[31:22]}; end
    5'h17: begin stencilReadRemapped = {stencilReadCache[ 6:0],stencilReadCache[31:23]}; maskReadRemapped = {maskReadCache[ 6:0],maskReadCache[31:23]}; end
    5'h18: begin stencilReadRemapped = {stencilReadCache[ 7:0],stencilReadCache[31:24]}; maskReadRemapped = {maskReadCache[ 7:0],maskReadCache[31:24]}; end
    5'h19: begin stencilReadRemapped = {stencilReadCache[ 8:0],stencilReadCache[31:25]}; maskReadRemapped = {maskReadCache[ 8:0],maskReadCache[31:25]}; end
    5'h1A: begin stencilReadRemapped = {stencilReadCache[ 9:0],stencilReadCache[31:26]}; maskReadRemapped = {maskReadCache[ 9:0],maskReadCache[31:26]}; end
    5'h1B: begin stencilReadRemapped = {stencilReadCache[10:0],stencilReadCache[31:27]}; maskReadRemapped = {maskReadCache[10:0],maskReadCache[31:27]}; end
    5'h1C: begin stencilReadRemapped = {stencilReadCache[11:0],stencilReadCache[31:28]}; maskReadRemapped = {maskReadCache[11:0],maskReadCache[31:28]}; end
    5'h1D: begin stencilReadRemapped = {stencilReadCache[12:0],stencilReadCache[31:29]}; maskReadRemapped = {maskReadCache[12:0],maskReadCache[31:29]}; end
    5'h1E: begin stencilReadRemapped = {stencilReadCache[13:0],stencilReadCache[31:30]}; maskReadRemapped = {maskReadCache[13:0],maskReadCache[31:30]}; end
    5'h1F: begin stencilReadRemapped = {stencilReadCache[14:0],stencilReadCache   [31]}; maskReadRemapped = {maskReadCache[14:0],maskReadCache   [31]}; end
    endcase
end

// Mutually exclusive
wire   writeCommand				= memoryCommand[1]; // WRITE_VV
wire   readCommand				= memoryCommand[0]; // READ_VV

assign o_command				= writeCommand | readCommand;
assign o_commandSize			= 2'd1; // 32 Byte
assign o_write					= writeCommand & sendCommandToMemoryNOBUSY;
assign o_adr					= writeCommand ? {scrDstY[8:0],scrDstX} : {scrY[8:0], scrSrcX};// 1 MB memory splitted into 32768 block of 32 byte.
assign o_subadr					= 3'd0;

assign o_dataOut				= currVVPixelWFinal;
assign o_writeMask				= currVVPixelWFinalSel;

assign o_stencilFullMode		= 1;
assign o_stencilWriteValue16	= stencilReadRemapped |  {16{GPU_REG_ForcePixel15MaskSet}};
assign o_stencilWriteMask16		= maskReadRemapped    & ({16{!GPU_REG_CheckMaskBit}} | (~i_stencilReadValue16));
assign o_stencilReadSig			= stencilReadSig | stencilReadSigW;
assign o_stencilWrite			= writeCommand;
assign o_stencilWriteAdr		= o_adr;
// Use DEST ADR for a STENCIL READ TOO !
assign o_stencilReadAdr			= stencilReadSigW ? {scrDstY[8:0],scrDstX} : {scrY[8:0],scrSrcX};

assign o_active					= (currWorkState != COPY_WAIT);
assign o_CopyInactiveNextCycle	= o_active & (nextWorkState == COPY_WAIT);

endmodule

module ROL512(
	input  [511:0]		inp,
	input	   [4:0]    rot,
	output [255:0]		out
);

	// wire [511:0] a = inp;
	wire [511:0] a = rot[4] ? { inp[255:0] , inp[511:256] } : inp;

	reg [255:0] br;
	always @(*)
	begin
		/*
		case (rot)
		5'd0 : br = a[255: 0];
		5'd1 : br = a[271:16];
		5'd2 : br = a[287:32];
		5'd3 : br = a[303:48];
		5'd4 : br = a[319:64];
		5'd5 : br = a[335:80];
		5'd6 : br = a[351:96];
		5'd7 : br = a[367:112];
		5'd8 : br = a[383:128];
		5'd9 : br = a[399:144];
		5'd10: br = a[415:160];
		5'd11: br = a[431:176];
		5'd12: br = a[447:192];
		5'd13: br = a[463:208];
		5'd14: br = a[479:224];
		5'd15: br = a[495:240];
		5'd16: br = a[511:256];
		5'd17: br = { a[ 15:0], a[511:272] };
		5'd18: br = { a[ 31:0], a[511:288] };
		5'd19: br = { a[ 47:0], a[511:304] };
		5'd20: br = { a[ 63:0], a[511:320] };
		5'd21: br = { a[ 79:0], a[511:336] };
		5'd22: br = { a[ 95:0], a[511:352] };
		5'd23: br = { a[111:0], a[511:368] };
		5'd24: br = { a[127:0], a[511:384] };
		5'd25: br = { a[143:0], a[511:400] };
		5'd26: br = { a[159:0], a[511:416] };
		5'd27: br = { a[175:0], a[511:432] };
		5'd28: br = { a[191:0], a[511:448] };
		5'd29: br = { a[207:0], a[511:464] };
		5'd30: br = { a[223:0], a[511:480] };
		5'd31: br = { a[239:0], a[511:496] };
		endcase
		*/
		case (rot[3:0])
		4'd0 : br = a[255: 0];
		4'd1 : br = a[271:16];
		4'd2 : br = a[287:32];
		4'd3 : br = a[303:48];
		4'd4 : br = a[319:64];
		4'd5 : br = a[335:80];
		4'd6 : br = a[351:96];
		4'd7 : br = a[367:112];
		4'd8 : br = a[383:128];
		4'd9 : br = a[399:144];
		4'd10: br = a[415:160];
		4'd11: br = a[431:176];
		4'd12: br = a[447:192];
		4'd13: br = a[463:208];
		4'd14: br = a[479:224];
		4'd15: br = a[495:240];
		endcase
	end

	assign out = br;

endmodule
