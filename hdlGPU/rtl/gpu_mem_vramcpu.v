
module gpu_mem_vramcpu
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           req_valid_i
    ,input  [ 15:0]  req_x_i
    ,input  [ 15:0]  req_y_i
    ,input  [ 15:0]  req_sizex_i
    ,input  [ 15:0]  req_sizey_i
    ,input           data_accept_i
    ,input           gpu_busy_i
    ,input           gpu_data_in_valid_i
    ,input  [255:0]  gpu_data_in_i

    // Outputs
    ,output          req_accept_o
    ,output          data_valid_o
    ,output [ 31:0]  data_pair_o
    ,output          busy_o
    ,output          done_o
    ,output          gpu_command_o
    ,output [  1:0]  gpu_size_o
    ,output          gpu_write_o
    ,output [ 14:0]  gpu_addr_o
    ,output [  2:0]  gpu_sub_addr_o
    ,output [ 15:0]  gpu_write_mask_o
    ,output [255:0]  gpu_data_out_o
);



localparam GPU_CMDSZ_8_BYTE  = 2'd0;
localparam GPU_CMDSZ_32_BYTE = 2'd1;
localparam GPU_CMDSZ_4_BYTE  = 2'd2;

localparam PIXEL_BURST       = 16;

localparam RESP_BUF_DEPTH    = 4;
localparam RESP_BUF_DEPTH_W  = 2;

wire resp_valid_w;
wire resp_pop_w;

//-----------------------------------------------------------------
// FIFO space tracking
// NOTE: Track how full the FIFO *will* be, not how full it is now..
//-----------------------------------------------------------------
reg [RESP_BUF_DEPTH_W:0] allocated_r;
reg [RESP_BUF_DEPTH_W:0] allocated_q;

always @ *
begin
    allocated_r = allocated_q;

    if (resp_valid_w && resp_pop_w)
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

//-----------------------------------------------------------------
// Dimensions
//-----------------------------------------------------------------
reg [15:0] start_x_q;
reg [15:0] start_y_q;
reg [15:0] cur_x_q;
reg [15:0] cur_y_q;
reg [15:0] end_x_q;
reg [15:0] end_y_q;

reg [15:0] start_x_r;
reg [15:0] start_y_r;
reg [15:0] cur_x_r;
reg [15:0] cur_y_r;
reg [15:0] end_x_r;
reg [15:0] end_y_r;

// Number of pixels until the edge of the square
wire [15:0] avail_x_w = end_x_q - cur_x_q;

// Max read size (capped to burst length)
wire [15:0] max_read_x_w    = (avail_x_w > PIXEL_BURST) ? PIXEL_BURST : avail_x_w;

// Pixel within the line (16 pixels per 32-byte line)
wire [15:0] x_word_offset_w = {12'b0, cur_x_q[3:0]};

// Pixels remaining in the line
wire [15:0] x_line_remain_w = PIXEL_BURST - {12'b0, cur_x_q[3:0]};

// Pixels to fetch taking into account alignment and remainder
wire [15:0] fetch_x_w = (x_line_remain_w > max_read_x_w) ? max_read_x_w : x_line_remain_w;

wire [15:0] next_x_w  = cur_x_q + fetch_x_w;
wire [15:0] next_y_w  = cur_y_q + 16'd1;

// This is the last read
reg         end_of_read_r;

// The last read has been performed
wire        xfer_complete_w;

always @ *
begin
    start_x_r     = start_x_q;
    start_y_r     = start_y_q;
    cur_x_r       = cur_x_q;
    cur_y_r       = cur_y_q;
    end_x_r       = end_x_q;
    end_y_r       = end_y_q;
    end_of_read_r = 1'b0;

    if (req_valid_i && req_accept_o)
    begin
        start_x_r = req_x_i;
        start_y_r = req_y_i;
        cur_x_r   = req_x_i;
        cur_y_r   = req_y_i;
        end_x_r   = req_x_i + req_sizex_i;
        end_y_r   = req_y_i + req_sizey_i;
    end
    else if (state_q == STATE_READ && ~gpu_busy_i)
    begin
        // Advance
        if (next_x_w >= end_x_r)
        begin    
            if (next_y_w >= end_y_r)
            begin
                cur_y_r       = next_y_w;
                end_of_read_r = 1'b1;
            end
            else
            begin
                cur_x_r = start_x_r;
                cur_y_r = next_y_w;
            end
        end
        else
            cur_x_r = cur_x_r + fetch_x_w;
    end
end

// All reads from memory have completed
assign xfer_complete_w = (next_x_w >= end_x_q) && (next_y_w > end_y_q);

always @ (posedge clk_i )
if (rst_i)
    start_x_q <= 16'b0;
else
    start_x_q <= start_x_r;

always @ (posedge clk_i )
if (rst_i)
    start_y_q <= 16'b0;
else
    start_y_q <= start_y_r;

always @ (posedge clk_i )
if (rst_i)
    cur_x_q <= 16'b0;
else
    cur_x_q <= cur_x_r;

always @ (posedge clk_i )
if (rst_i)
    cur_y_q <= 16'b0;
else
    cur_y_q <= cur_y_r;

always @ (posedge clk_i )
if (rst_i)
    end_x_q <= 16'b0;
else
    end_x_q <= end_x_r;

always @ (posedge clk_i )
if (rst_i)
    end_y_q <= 16'b0;
else
    end_y_q <= end_y_r;


wire [31:0] mem_addr_w  = {12'b0, cur_y_q[8:0], cur_x_q[9:0], 1'b0};

//-----------------------------------------------------------------
// State machine
//-----------------------------------------------------------------
localparam STATE_W           = 2;
localparam STATE_IDLE        = 2'd0;
localparam STATE_READ        = 2'd1;
localparam STATE_READ_WAIT   = 2'd2;
localparam STATE_DONE        = 2'd3;

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
        if (gpu_command_o && ~gpu_busy_i)
            next_state_r = STATE_READ_WAIT;
    end
    STATE_READ_WAIT :
    begin
        if (fifo_space_w)
        begin
            if (!xfer_complete_w)
                next_state_r = STATE_READ;
            else
                next_state_r = STATE_DONE;
        end
    end
    STATE_DONE :
    begin
        // Wait until FIFOs are fully empty
        if (allocated_q == {(RESP_BUF_DEPTH_W+1){1'b0}} && !data_valid_o)
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
assign done_o          = state_q == STATE_DONE;
assign req_accept_o    = state_q == STATE_IDLE;

//-----------------------------------------------------------------
// Memory Request
//-----------------------------------------------------------------
assign gpu_command_o    = (state_q == STATE_READ);
assign gpu_write_o      = 1'b0;
assign gpu_size_o       = GPU_CMDSZ_32_BYTE;
assign gpu_addr_o       = mem_addr_w[19:5];
assign gpu_sub_addr_o   = 3'b0;
assign gpu_data_out_o   = 256'b0;
assign gpu_write_mask_o = 16'b0;

//-----------------------------------------------------------------
// Response details (where to read from, how much data)
//-----------------------------------------------------------------
// Offset within the line of the first pixel
wire [3:0] resp_offset_w;

// Number of pixels in the response line
wire [4:0] resp_pixels_w;

// Is this the last read of the transfer
wire       resp_end_w;

wire       fifo_pop_w;
wire       pixels_pop_w  = fifo_pop_w & resp_valid_w;
wire       line_final_w;

// Last pixel from line consumed
assign     resp_pop_w = pixels_pop_w & line_final_w;

gpu_mem_fifo
#(
     .WIDTH(4+5+1)
    ,.DEPTH(RESP_BUF_DEPTH)
    ,.ADDR_W(RESP_BUF_DEPTH_W)
)
u_request_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(gpu_command_o && ~gpu_busy_i)
    ,.data_in_i({end_of_read_r, fetch_x_w[4:0], x_word_offset_w[3:0]})
    ,.accept_o()

    ,.valid_o()
    ,.data_out_o({resp_end_w, resp_pixels_w, resp_offset_w})
    ,.pop_i(resp_pop_w)
);

//-----------------------------------------------------------------
// Unroll line to pairs of pixels
//-----------------------------------------------------------------
wire       avail_one_w;
wire       avail_two_w;
wire [3:0] line_offset_w;
wire [4:0] line_pixels_w;

reg mid_line_q;

always @ (posedge clk_i )
if (rst_i)
    mid_line_q <= 1'b0;
else if (line_final_w && pixels_pop_w)
    mid_line_q <= 1'b0;
else if (pixels_pop_w)
    mid_line_q <= 1'b1;

// Offset within the line of the first pixel
reg [3:0] resp_offset_q;
reg [3:0] resp_offset_r;

always @ *
begin
    resp_offset_r = resp_offset_q;

    if (pixels_pop_w)
    begin
        if (avail_two_w)
            resp_offset_r = line_offset_w + 4'd2;
        else
            resp_offset_r = line_offset_w + 4'd1;
    end
end

always @ (posedge clk_i )
if (rst_i)
    resp_offset_q <= 4'b0;
else
    resp_offset_q <= resp_offset_r;

// Number of pixels in the response line
reg [4:0] resp_pixels_q;
reg [4:0] resp_pixels_r;

always @ *
begin
    resp_pixels_r = resp_pixels_q;

    if (pixels_pop_w)
    begin
        if (avail_two_w)
            resp_pixels_r = line_pixels_w - 5'd2;
        else
            resp_pixels_r = line_pixels_w - 5'd1;
    end
end

always @ (posedge clk_i )
if (rst_i)
    resp_pixels_q <= 5'b0;
else
    resp_pixels_q <= resp_pixels_r;

// Offset within the line of the first pixel
assign line_offset_w  = mid_line_q ? resp_offset_q : resp_offset_w;

// Number of pixels in the response line
assign line_pixels_w  = mid_line_q ? resp_pixels_q : resp_pixels_w;

// End of data on this line
assign line_final_w   = (line_pixels_w <= 5'd2);

// How many pixels are available on this line
assign avail_one_w    = (line_pixels_w >= 5'd1);
assign avail_two_w    = (line_pixels_w >= 5'd2);

//-----------------------------------------------------------------
// Response buffer
//-----------------------------------------------------------------
wire [255:0] fifo_data_w;

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
    ,.data_out_o(fifo_data_w)
    ,.pop_i(resp_pop_w)
);

//-----------------------------------------------------------------
// Select appropriate data lanes from response
//-----------------------------------------------------------------
reg          lane0_valid_r;
reg [15:0]   lane0_r;
reg          lane1_valid_r;
reg [15:0]   lane1_r;

always @ *
begin
    lane0_valid_r = 1'b0;
    lane0_r       = 16'b0;
    lane1_valid_r = 1'b0;
    lane1_r       = 16'b0;

    lane0_valid_r = resp_valid_w;
    lane1_valid_r = resp_valid_w && (line_pixels_w > 5'd1);

    case (line_offset_w)
    4'd0: lane0_r = fifo_data_w[15:0];
    4'd1: lane0_r = fifo_data_w[31:16];
    4'd2: lane0_r = fifo_data_w[47:32];
    4'd3: lane0_r = fifo_data_w[63:48];
    4'd4: lane0_r = fifo_data_w[79:64];
    4'd5: lane0_r = fifo_data_w[95:80];
    4'd6: lane0_r = fifo_data_w[111:96];
    4'd7: lane0_r = fifo_data_w[127:112];
    4'd8: lane0_r = fifo_data_w[143:128];
    4'd9: lane0_r = fifo_data_w[159:144];
    4'd10: lane0_r = fifo_data_w[175:160];
    4'd11: lane0_r = fifo_data_w[191:176];
    4'd12: lane0_r = fifo_data_w[207:192];
    4'd13: lane0_r = fifo_data_w[223:208];
    4'd14: lane0_r = fifo_data_w[239:224];
    4'd15: lane0_r = fifo_data_w[255:240];
    default: ;
    endcase

    case (line_offset_w + 4'd1)
    4'd0: lane1_r = fifo_data_w[15:0];
    4'd1: lane1_r = fifo_data_w[31:16];
    4'd2: lane1_r = fifo_data_w[47:32];
    4'd3: lane1_r = fifo_data_w[63:48];
    4'd4: lane1_r = fifo_data_w[79:64];
    4'd5: lane1_r = fifo_data_w[95:80];
    4'd6: lane1_r = fifo_data_w[111:96];
    4'd7: lane1_r = fifo_data_w[127:112];
    4'd8: lane1_r = fifo_data_w[143:128];
    4'd9: lane1_r = fifo_data_w[159:144];
    4'd10: lane1_r = fifo_data_w[175:160];
    4'd11: lane1_r = fifo_data_w[191:176];
    4'd12: lane1_r = fifo_data_w[207:192];
    4'd13: lane1_r = fifo_data_w[223:208];
    4'd14: lane1_r = fifo_data_w[239:224];
    4'd15: lane1_r = fifo_data_w[255:240];
    default: ;
    endcase
end

//-----------------------------------------------------------------
// Output realignment FIFO
//-----------------------------------------------------------------
gpu_mem_vramcpu_fifo_2w1r
#(
     .WIDTH(16)
    ,.DEPTH(8)
    ,.ADDR_W(3)
)
u_out_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push0_i(lane0_valid_r)
    ,.data_in0_i(lane0_r)
    ,.push1_i(lane1_valid_r)
    ,.data_in1_i(lane1_r)
    ,.final_i(resp_end_w & line_final_w)
    ,.accept0_o(fifo_pop_w)
    ,.accept1_o()

    ,.valid_o(data_valid_o)
    ,.data_out_o(data_pair_o)
    ,.pop_i(data_accept_i)
);


endmodule
