/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_SM_FILL_mem(
	input					i_clk,
	input					i_rst,
	
	// Setup
	input					i_InterlaceRender,
	input					GPU_REG_CurrentInterlaceField,
	input			[ 7:0]	RegR0,
	input			[ 7:0]	RegG0,
	input			[ 7:0]	RegB0,
	input	signed  [11:0]	RegX0,
	input	signed  [11:0]	RegY0,
	input			[10:0]	RegSizeW,
	input			[ 9:0]	RegSizeH,

	// State machine control
	input					i_activateFILL,
	output					o_FILLInactiveNextCycle,
	output					o_active,

	// Stencil Write
	output					o_stencilWriteSig,
	output					o_stencilReadSig,
	output					o_stencilFullMode,
	output			[15:0]	o_stencilWriteValue16,
	output			[15:0]	o_stencilWriteMask16,
	output			[14:0]	o_stencilWriteAdr,

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

// Dont perform read.
//    input  [255:0]   		i_dataIn,
//    input            		i_dataInValid,

    output [255:0]   		o_dataOut
);

wire i_urgentExit = 0;
wire fifo_space_w;

typedef enum logic[1:0] {
	RENDER_WAIT					= 2'd0,
	FILL_START					= 2'd1,
	FILL_LINE  					= 2'd2,
	FILL_WAIT_COMPLETE			= 2'd3
} workState_t;

//----------------------------------------------------	
workState_t nextWorkState,currWorkState;
always @(posedge i_clk)
	if (i_rst || i_urgentExit)
		currWorkState <= RENDER_WAIT;
	else
		currWorkState <= nextWorkState;
//----------------------------------------------------	

reg loadNext, resetXCounter,writeStencil,incrementXCounter;	
reg signed [11:0] pixelY,nextPixelY;
reg	 [ 6:0] counterXSrc;

reg [2:0]	selNextY;
reg memoryWrite;

wire signed [11:0] nextLineY    = pixelY + { 9'b0 , i_InterlaceRender , !i_InterlaceRender };	// +1 for normal mode, +2 for interlaced locked render primitives
wire renderYOffsetInterlace		= (i_InterlaceRender ? (RegY0[0] ^ GPU_REG_CurrentInterlaceField) : 1'b0);

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
	if (i_rst) begin
		pixelY <= 12'd0;
	end else begin
		if (loadNext) begin
			pixelY <= nextPixelY;
		end
	end
end

always @(posedge i_clk)
begin
    counterXSrc <= (resetXCounter || i_rst) ? 7'd0 : counterXSrc + { 6'd0 ,incrementXCounter };
end

wire [10:0] fullSizeSrc			= RegSizeW + { 7'd0, RegX0[3:0] };
wire emptySurface				= (RegSizeH == 10'd0) | (RegSizeW == 11'd0);
wire        srcDistExact16Pixel	= !(|fullSizeSrc[3:0]);
wire  [6:0] lengthBlockSrcHM1	= fullSizeSrc[10:4] + {7{srcDistExact16Pixel}};	// If exact 16, retract 1 block. (Add -1)
wire isLastSegment  			= (counterXSrc==lengthBlockSrcHM1);
wire		endVertical			= (nextLineY[9:0] >= RegSizeH);
wire  [9:0]	scrY				= pixelY[9:0] + RegY0[9:0];
wire  [5:0] adrXSrc				= /*xCopyDirectionIncr ? */counterXSrc[5:0]/* : OppAdrXSrc[5:0]*/;
wire [5:0] scrSrcX				= adrXSrc[5:0] + RegX0[9:4];

always @(*)
begin
	nextWorkState				= currWorkState;
	loadNext					= 0;
	resetXCounter				= 0;
	writeStencil				= 0;
	incrementXCounter			= 0;
	selNextY					= Y_ASIS;
	memoryWrite					= 0;
	
    case (currWorkState)
	RENDER_WAIT:
	begin
		if (i_activateFILL) begin
			nextWorkState = FILL_START;
		end
	end
	// --------------------------------------------------------------------
	//	 FILL VRAM STATE MACHINE
	// --------------------------------------------------------------------
	FILL_START:	// Actually FILL LINE START.
	begin
		if (emptySurface) begin
			nextWorkState = RENDER_WAIT;
		end else begin
			// Next Cycle H=H-1, and we can parse from H-1 to 0 for each line...
			// Reset X Counter. + Now we fill from H-1 to ZERO... force decrement here.
			loadNext		= 1;
			selNextY		= Y_CV_ZERO;
			resetXCounter	= 1;
			nextWorkState	= FILL_LINE;
		end
	end
	FILL_LINE:
	begin
		// Forced to decrement at each step in X
		// [FILL COMMAND : [16 Bit 0BGR][16 bit empty][Adr 15 bit][4 bit empty][010]
		if (fifo_space_w) begin // else it will wait...
			memoryWrite			= 1;
			writeStencil		= 1;
			if (isLastSegment) begin
				loadNext	  = 1;
				selNextY	  = Y_TRI_NEXT;
				resetXCounter = 1;
				nextWorkState = (endVertical) ? FILL_WAIT_COMPLETE : FILL_LINE;
			end else begin
				incrementXCounter	= 1;// SRC COUNTER
			end
		end
	end
	FILL_WAIT_COMPLETE:
	begin
		// Output FIFO drained
		if (!o_command)
		begin
			nextWorkState = RENDER_WAIT;
		end
	end
	default: begin
		nextWorkState = RENDER_WAIT;
	end
	endcase
end

assign o_active					= (currWorkState != RENDER_WAIT);

assign o_stencilWriteSig		= writeStencil;
assign o_stencilReadSig			= 0;
assign o_stencilFullMode		= 1;
assign o_stencilWriteValue16	= 16'h0000;
assign o_stencilWriteMask16		= 16'hFFFF;
assign o_stencilWriteAdr		= o_adr;

assign o_FILLInactiveNextCycle	= o_active && (nextWorkState == RENDER_WAIT);

//-----------------------------------------------------------------
// Memory Request
//-----------------------------------------------------------------
wire [4:0] out_r_w;
wire [4:0] out_g_w;
wire [4:0] out_b_w;

gpu_mem_fifo
#(
     .WIDTH(15 + 15)
    ,.DEPTH(2)
    ,.ADDR_W(1)
)
u_mem_req
(
     .clk_i(i_clk)
    ,.rst_i(i_rst)

    ,.push_i(memoryWrite)
    ,.data_in_i({ scrY[8:0], scrSrcX, RegB0[7:3],RegG0[7:3],RegR0[7:3]})
    ,.accept_o(fifo_space_w)

    // Outputs
    ,.data_out_o({o_adr, out_b_w, out_g_w, out_r_w})
    ,.valid_o(o_command)
    ,.pop_i(~i_busy)
);

assign o_commandSize			= 2'd1;	// 1 = 32 byte.
assign o_write					= 1'b1;
assign o_writeMask				= 16'hFFFF;
assign o_subadr					= 3'd0;
assign o_dataOut                = {16{ 1'b0,out_b_w,out_g_w,out_r_w}};

endmodule

