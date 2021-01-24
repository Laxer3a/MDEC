/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_CopyVV(
	input				i_clk,
	input				i_rst,

	input				i_activateCopyVV,
	output				o_CopyInactiveNextCycle,
	output				o_active,
	
	input				i_commandFIFOaccept,
	input				i_allowNextRead,
	input				i_isDoubleLoad,
	input				i_performSwitch,
	input				i_isLastSegment,
	input				i_isLastSegmentDst,
	input				i_endVertical,
	input	[15:0]		i_stencilReadValue16,
	input	[15:0]		i_maskSegmentRead,
	
	output				o_loadNext,
	output	[2:0]		o_selNextX,
	output	[2:0]		o_selNextY,
	output				o_resetXCounter,
	output				o_incrementXCounter,
	output	[2:0]		o_memoryCommand,
	output				o_stencilReadSig,
	output				o_writeStencil,
	
	output				o_cpyBank,
	output				o_useDest,
	output				o_clearOtherBank,
	output				o_stencilReadSigW,
	output				o_clearBank0,
	output				o_clearBank1,
	
	output [31:0]		o_maskReadCache,
	output [31:0]		o_stencilReadCache
);

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
reg [2:0]	memoryCommand;
reg [2:0]	selNextY;
reg loadNext,resetXCounter,stencilReadSig,incrementXCounter,writeStencil;

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


wire storeStencilRead = (memoryCommand == MEM_CMD_RDBURST);
reg [31:0]  maskReadCache;
reg [31:0]  stencilReadCache;

always @(posedge i_clk)
begin
    // BEFORE cpyBank UPDATE !!!
    if (storeStencilRead) begin
        if (cpyBank) begin
            stencilReadCache[31:16] <= i_stencilReadValue16;
            maskReadCache	[31:16] <= i_maskSegmentRead;
            if (clearOtherBank) begin
                maskReadCache	[15:0] <= 16'd0;
            end
        end else begin
            stencilReadCache[15: 0] <= i_stencilReadValue16;
            maskReadCache	[15: 0] <= i_maskSegmentRead;
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



// --------------------------------------------------------------------
//	 COPY VRAM STATE MACHINE
// --------------------------------------------------------------------
always @(*)
begin
	nextWorkState			= currWorkState;

	// Common
	selNextY				= Y_ASIS;
	memoryCommand			= MEM_CMD_NONE;
	loadNext				= 0;
	resetXCounter			= 0;
	stencilReadSig			= 0;
	incrementXCounter		= 0;
	writeStencil			= 0;

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
		if (i_commandFIFOaccept) begin
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
		memoryCommand		= MEM_CMD_RDBURST;

		if (i_allowNextRead) begin
			if (i_isDoubleLoad) begin
				nextWorkState	= CPY_RS2;
			end else begin
				nextWorkState	= CPY_LWS1;
			end
		end else begin
			nextWorkState		= CPY_WS2;
		end

		if (i_isDoubleLoad) begin
			if (i_allowNextRead) begin
				switchBank		= i_performSwitch;
			end else begin
				switchBank		= !i_performSwitch;
			end
		end else begin
			switchBank		= i_performSwitch;
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
		if (i_commandFIFOaccept) begin
			nextWorkState = CPY_R2;
		// else nextWorkState stay the same
		end
	end
	CPY_R2:
	begin
		incrementXCounter	= 1; useDest = 0; // Increment Source.
		// TODO storeStencilTmp		= 1;
		memoryCommand		= MEM_CMD_RDBURST;
		switchBank			= i_performSwitch;

		if (i_allowNextRead) begin
			nextWorkState	= CPY_LWS1;
		end else begin
			nextWorkState	= CPY_WS2;
		end
	end
	CPY_LWS1:
	begin
		stencilReadSigW		= 1;

		if (i_commandFIFOaccept) begin
			nextWorkState	= CPY_LW1;
		// else nextWorkState stay the same
		end
	end
	CPY_LW1:
	begin
		incrementXCounter	= 1; useDest = 1;
		memoryCommand		= MEM_CMD_WRBURST;
		writeStencil		= 1;
		nextWorkState		= CPY_LRS;
	end
	CPY_LRS:
	begin
		stencilReadSig	= 1; // Adr setup auto.
		if (i_commandFIFOaccept) begin
			nextWorkState	= CPY_LR;
		// else nextWorkState stay the same
		end
	end
	CPY_LR:
	begin
		incrementXCounter	= 1; useDest = 0; // Increment Source.

		memoryCommand		= MEM_CMD_RDBURST;
		switchBank			= i_performSwitch;

		if (!i_isLastSegment/* = allowNextRead, do NOT check isLongLine ! */) begin
			nextWorkState	= CPY_LWS1;
		end else begin
			nextWorkState	= CPY_WS2;
		end
	end
	CPY_WS2:
	begin
		stencilReadSigW		= 1;

		if (i_commandFIFOaccept) begin
			nextWorkState	= CPY_W2;
		// else nextWorkState stay the same
		end
	end
	CPY_W2:
	begin
		// Here : at this cycle we receive value from stencil READ.
		// And do now a STENCIL WRITE.
		incrementXCounter	= 1; useDest = 1;
		memoryCommand		= MEM_CMD_WRBURST;
		writeStencil		= 1;

		clearBank0			= !cpyBank;
		clearBank1			= cpyBank;
		switchBank			= i_performSwitch;

		if (!i_isLastSegmentDst) begin
			nextWorkState	= CPY_WS3;
		end else begin
			nextWorkState	= CPY_ENDLINE;
		end
	end
	CPY_WS3:
	begin
		stencilReadSigW		= 1;

		if (i_commandFIFOaccept) begin
			nextWorkState	= CPY_W3;
		// else nextWorkState stay the same
		end
	end
	CPY_W3:
	begin
		memoryCommand		= MEM_CMD_WRBURST;
		writeStencil		= 1;
		nextWorkState		= CPY_ENDLINE;
	end
	CPY_ENDLINE:
	begin
		selNextY			= Y_TRI_NEXT; loadNext = 1;

		if (i_endVertical) begin
			// End of copy primitive...
			nextWorkState	= COPY_WAIT;
		end else begin
			nextWorkState	= COPY_START_LINE;
		end
	end
	endcase
end

assign o_loadNext				= loadNext;
assign o_selNextX				= X_ASIS; // Unused
assign o_selNextY				= selNextY;
assign o_resetXCounter			= resetXCounter;
assign o_incrementXCounter		= incrementXCounter;
assign o_memoryCommand			= memoryCommand;
assign o_stencilReadSig			= stencilReadSig;
assign o_writeStencil			= writeStencil;

assign o_useDest				= useDest;
assign o_cpyBank				= cpyBank;
assign o_clearOtherBank			= clearOtherBank;
assign o_stencilReadSigW		= stencilReadSigW;
assign o_clearBank0				= clearBank0;
assign o_clearBank1				= clearBank1;
assign o_active					= (currWorkState != COPY_WAIT);
assign o_CopyInactiveNextCycle	= o_active & (nextWorkState == COPY_WAIT);

assign o_maskReadCache			= maskReadCache;
assign o_stencilReadCache		= stencilReadCache;

endmodule
