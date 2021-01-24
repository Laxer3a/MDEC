/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_workDispatch(
	input			i_clk,
	input			i_rst,

	// Current Command type
	input			i_bIsPerVtxCol,
	input			i_bUseTexture,

	// Set when starting new work.
	input	[4:0]	i_issuePrimitive,
	input			i_bIsCopyVVCommand,
	input			i_bIsCopyCVCommand,

	// Message to sub state machines...
	output	[2:0]	o_activateRender,
	output			o_activateCopy,
	
	// When sub complete
	input			i_renderInactiveNextCycle,
	input			i_inactiveCopyCVNextCycle,
	input			i_inactiveCopyVCNextCycle,
	input			i_inactiveCopyVVNextCycle,

	output	[2:0]	o_StencilMode,						// Control for Stencil Cache
	output			o_waitWork							// Assign to setInterCounter,setFirstPixel, assignRectSetup, resetDir, resetEnteredTriangle
);

parameter 	NOT_WORKING_DEFAULT_STATE	= 1'd0,
			WAIT_SUB_STATE_COMPLETE		= 1'd1;

//----------------------------------------------------	
reg nextWorkState,currWorkState;
always @(posedge i_clk)
	if (i_rst)
		currWorkState <= NOT_WORKING_DEFAULT_STATE;
	else
		currWorkState <= nextWorkState;
//----------------------------------------------------	

reg [2:0] setRenderInit;
reg       activateCopy;

reg [2:0] setStencilMode;
reg	[2:0] StencilMode;
always @(posedge i_clk)
    if (setStencilMode!=3'd0)
		StencilMode <= setStencilMode;

always @(*)
begin
	setRenderInit	= RDR_NONE;
	setStencilMode	= 3'd0;
	activateCopy	= 0;
	
	case (currWorkState)
	NOT_WORKING_DEFAULT_STATE:
	begin
		case (/*issue.*/i_issuePrimitive)
		ISSUE_TRIANGLE:
		begin
			nextWorkState			= WAIT_SUB_STATE_COMPLETE;
			setStencilMode			= 3'd1;
			if (i_bIsPerVtxCol) begin
				setRenderInit		= RDR_SETUP_INTERP;
			end else begin
				setRenderInit		= (i_bUseTexture) ? RDR_SETUP_INTERP : RDR_TRIANGLE_START;
			end
		end
		ISSUE_RECT:
		begin
			nextWorkState			= WAIT_SUB_STATE_COMPLETE;
			setStencilMode			= 3'd1;
			setRenderInit			= RDR_WAIT_3;
		end
		ISSUE_LINE:
		begin
			nextWorkState			= WAIT_SUB_STATE_COMPLETE;
			setStencilMode			= 3'd1;
			setRenderInit			= (i_bIsPerVtxCol) ? RDR_SETUP_INTERP : /*(bUseTexture) ? SETUP_UX :*/ RDR_LINE_START;
		end
		ISSUE_FILL:
		begin
			nextWorkState			= WAIT_SUB_STATE_COMPLETE;
			setStencilMode			= 3'd2;
			setRenderInit			= RDR_FILL_START;
		end
		ISSUE_COPY:
		begin
			nextWorkState			= WAIT_SUB_STATE_COMPLETE;
			activateCopy			= 1;
			if (i_bIsCopyVVCommand) begin
				setStencilMode		= 3'd6;
			end else if (i_bIsCopyCVCommand) begin
				setStencilMode		= 3'd3;
			end else begin
				// bIsCopyVCCommandbegin obviously...
				// STENCIL MODE NOT USED (no read, no write), BUT USED TO KNOW DIRECTION FOR CPU READ...
				setStencilMode		= 3'd7;
			end
		end
		default:
			nextWorkState			= NOT_WORKING_DEFAULT_STATE;
		endcase
	end
	WAIT_SUB_STATE_COMPLETE:
	begin
		// If all inactive next cycle, then dispatcher should be inactive next cycle too.
		nextWorkState = (i_renderInactiveNextCycle | i_inactiveCopyCVNextCycle | i_inactiveCopyVCNextCycle | i_inactiveCopyVVNextCycle) 
			? NOT_WORKING_DEFAULT_STATE 
			: WAIT_SUB_STATE_COMPLETE;
	end
	default:
	begin
		nextWorkState = NOT_WORKING_DEFAULT_STATE;
	end
	endcase	
end

// [Shorter and faster]
assign o_activateRender	= setRenderInit;
assign o_activateCopy	= activateCopy;

assign o_StencilMode	= StencilMode;
assign o_waitWork		= (currWorkState == NOT_WORKING_DEFAULT_STATE);

endmodule










