
module gpu_mem_vram_read
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           req_valid_i
    ,input  [ 15:0]  req_src_x_i
    ,input  [ 15:0]  req_src_y_i
    ,input           req_incr_i
    ,input  [ 15:0]  req_sizex_i
    ,input  [ 15:0]  req_sizey_i
    ,input           gpu_busy_i
    ,input           gpu_data_in_valid_i
    ,input  [255:0]  gpu_data_in_i
    ,input           data_accept_i

    // Outputs
    ,output          req_accept_o
    ,output          busy_o
    ,output          gpu_command_o
    ,output [  1:0]  gpu_size_o
    ,output          gpu_write_o
    ,output [ 14:0]  gpu_addr_o
    ,output [  2:0]  gpu_sub_addr_o
    ,output [ 15:0]  gpu_write_mask_o
    ,output [255:0]  gpu_data_out_o
    ,output          data_valid_o
    ,output [255:0]  data_value_o
    ,output [ 15:0]  data_mask_o
    ,output [ 3:0]   data_offset_o
    ,output          data_end_line_o
    ,output          data_final_o
);


localparam GPU_CMDSZ_8_BYTE  = 2'd0;
localparam GPU_CMDSZ_32_BYTE = 2'd1;
localparam GPU_CMDSZ_4_BYTE  = 2'd2;

localparam RESP_BUF_DEPTH    = 2;
localparam RESP_BUF_DEPTH_W  = 1;

wire req_complete_w;
wire resp_empty_w;
wire resp_valid_w;
wire resp_pop_w;

//-----------------------------------------------------------------
// State machine
//-----------------------------------------------------------------
localparam STATE_W           = 2;
localparam STATE_IDLE        = 2'd0;
localparam STATE_READ        = 2'd1;
localparam STATE_DONE        = 2'd2;

reg [STATE_W-1:0] state_q;
reg [STATE_W-1:0] next_state_r;

always @ *
begin
    next_state_r = state_q;

    case (state_q)
    STATE_IDLE :
    begin
        if (req_valid_i && req_accept_o)
            next_state_r = STATE_READ;
    end
    STATE_READ :
    begin
        if (req_complete_w)
            next_state_r = STATE_DONE;
    end
    STATE_DONE :
    begin
        // Wait until FIFOs are fully empty
        if (resp_empty_w && !data_valid_o)
            next_state_r = STATE_IDLE;
    end
    default :
       ;
    endcase
end

// Update state
always @ (posedge clk_i )
if (rst_i)
    state_q <= STATE_IDLE;
else
    state_q <= next_state_r;

assign busy_o          = state_q != STATE_IDLE;
assign req_accept_o    = state_q == STATE_IDLE;

//-----------------------------------------------------------------
// Read FIFO space tracking
// NOTE: Track how full the FIFO *will* be, not how full it is now..
//-----------------------------------------------------------------
reg [RESP_BUF_DEPTH_W:0] allocated_r;
reg [RESP_BUF_DEPTH_W:0] allocated_q;

always @ *
begin
    allocated_r = allocated_q;

    if (data_valid_o && data_accept_i)
        allocated_r = allocated_r - 1;

    if (gpu_command_o && !gpu_busy_i)
        allocated_r = allocated_r + 1;
end

always @ (posedge clk_i )
if (rst_i)
    allocated_q <= {(RESP_BUF_DEPTH_W+1){1'b0}};
else
    allocated_q <= allocated_r;

wire fifo_space_w = |(RESP_BUF_DEPTH - allocated_q);

assign resp_empty_w = (allocated_q == {(RESP_BUF_DEPTH_W+1){1'b0}});

//-----------------------------------------------------------------
// Source address generation
//-----------------------------------------------------------------
wire          valid_w;
wire [31:0]   addr_w;
wire [3:0]    offset_w;
wire [15:0]   mask_w;
wire          last_line_w;
wire          last_w;
wire          accept_w;

gpu_mem_addr_gen
u_src_addr
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.req_start_i(req_valid_i & req_accept_o)
    ,.req_incr_i(req_incr_i)
    ,.req_x_i(req_src_x_i)
    ,.req_y_i(req_src_y_i)
    ,.req_sizex_i(req_sizex_i)
    ,.req_sizey_i(req_sizey_i)

    ,.valid_o(valid_w)
    ,.addr_o(addr_w)
    ,.offset_o(offset_w)
    ,.mask_o(mask_w)
    ,.last_line_o(last_line_w)
    ,.last_o(last_w)
    ,.accept_i(accept_w)
);

assign req_complete_w = valid_w & last_w & accept_w;
assign accept_w       = fifo_space_w & ~gpu_busy_i;

//-----------------------------------------------------------------
// Memory Request
//-----------------------------------------------------------------
assign gpu_command_o    = valid_w & fifo_space_w;
assign gpu_write_o      = 1'b0;
assign gpu_size_o       = GPU_CMDSZ_32_BYTE;
assign gpu_addr_o       = addr_w[19:5];
assign gpu_sub_addr_o   = 3'b0;
assign gpu_data_out_o   = 256'b0;
assign gpu_write_mask_o = 16'b0;

//-----------------------------------------------------------------
// Request details (offset, byte masks, end of line details)
//-----------------------------------------------------------------
gpu_mem_fifo
#(
     .WIDTH(16+4+1+1)
    ,.DEPTH(RESP_BUF_DEPTH)
    ,.ADDR_W(RESP_BUF_DEPTH_W)
)
u_request_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(valid_w & accept_w)
    ,.data_in_i({last_w, last_line_w, offset_w, mask_w})
    ,.accept_o()

    ,.valid_o()
    ,.data_out_o({data_final_o, data_end_line_o, data_offset_o, data_mask_o})
    ,.pop_i(data_valid_o & data_accept_i)
);

//-----------------------------------------------------------------
// Response buffer
//-----------------------------------------------------------------
gpu_mem_fifo
#(
     .WIDTH(256)
    ,.DEPTH(RESP_BUF_DEPTH)
    ,.ADDR_W(RESP_BUF_DEPTH_W)
)
u_response_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(gpu_data_in_valid_i && busy_o)
    ,.data_in_i(gpu_data_in_i)
    ,.accept_o()

    ,.valid_o(resp_valid_w)
    ,.data_out_o(data_value_o)
    ,.pop_i(data_valid_o & data_accept_i)
);

assign data_valid_o = resp_valid_w;
assign resp_pop_w = data_valid_o & data_accept_i;

endmodule
