
module gpu_mem_cpuvram
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           req_valid_i
    ,input  [ 15:0]  req_x_i
    ,input  [ 15:0]  req_y_i
    ,input  [ 15:0]  req_sizex_i
    ,input  [ 15:0]  req_sizey_i
    ,input           req_set_mask_i
    ,input           req_use_mask_i
    ,input           data_valid_l_i
    ,input  [ 15:0]  data_pixel_l_i
    ,input           data_valid_r_i
    ,input  [ 15:0]  data_pixel_r_i
    ,input  [ 15:0]  stencil_rd_value_i
    ,input           gpu_busy_i
    ,input           gpu_data_in_valid_i
    ,input  [255:0]  gpu_data_in_i

    // Outputs
    ,output          req_accept_o
    ,output          data_accept_l_o
    ,output          data_accept_r_o
    ,output          stencil_rd_req_o
    ,output [ 14:0]  stencil_rd_addr_o
    ,output          stencil_wr_req_o
    ,output [ 14:0]  stencil_wr_addr_o
    ,output [ 15:0]  stencil_wr_mask_o
    ,output [ 15:0]  stencil_wr_value_o
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

localparam PIXEL_BURST       = 16'd16;

wire fifo_space_w;

//-----------------------------------------------------------------
// Param stash
//-----------------------------------------------------------------
reg req_use_mask_q;

always @ (posedge clk_i )
if (rst_i)
    req_use_mask_q <= 1'b0;
else if (req_accept_o)
    req_use_mask_q <= req_use_mask_i;

reg req_set_mask_q;

always @ (posedge clk_i )
if (rst_i)
    req_set_mask_q <= 1'b0;
else if (req_accept_o)
    req_set_mask_q <= req_set_mask_i;

//-----------------------------------------------------------------
// FIFO adapter - FIFO allows for 1w 2r (which is really 2w2r here)
//-----------------------------------------------------------------
wire        data_in_valid_w = data_valid_l_i & data_valid_r_i & busy_o;
wire        data_in_accept_w;

wire        pixel_l_valid_w;
wire [15:0] pixel_l_data_w;
wire        pixel_l_pop_w;

wire        pixel_r_valid_w;
wire [15:0] pixel_r_data_w;
wire        pixel_r_pop_w;

gpu_mem_cpuvram_fifo_1w2r
#(
     .WIDTH(16)
    ,.DEPTH(8) 
    ,.ADDR_W(3)
)
u_adapter
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    // Flush trailing pixel at the end of the transfer
    ,.flush_i(~busy_o)

    ,.push_i(data_in_valid_w)
    ,.data_in_i({data_pixel_r_i, data_pixel_l_i})
    ,.accept_o(data_in_accept_w)

    ,.valid0_o(pixel_l_valid_w)
    ,.data_out0_o(pixel_l_data_w)
    ,.pop0_i(pixel_l_pop_w)

    ,.valid1_o(pixel_r_valid_w)
    ,.data_out1_o(pixel_r_data_w)
    ,.pop1_i(pixel_r_pop_w)
);

assign data_accept_l_o = data_in_accept_w & data_valid_r_i & busy_o;
assign data_accept_r_o = data_in_accept_w & data_valid_l_i & busy_o;

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

// Max write size (capped to burst length)
wire [15:0] max_write_x_w    = (avail_x_w > PIXEL_BURST) ? PIXEL_BURST : avail_x_w;

// Pixel within the line (16 pixels per 32-byte line)
wire [15:0] x_word_offset_w = {12'b0, cur_x_q[3:0]};

// Pixels remaining in the line
wire [15:0] x_line_remain_w = PIXEL_BURST - {12'b0, cur_x_q[3:0]};

// Max pixels to process taking into account alignment and remainder
wire [15:0] write_x_w = (x_line_remain_w < 16'd2 || x_word_offset_w > 16'd14 || max_write_x_w < 16'd2) ? 16'd1 : 16'd2;

wire [15:0] next_x_w  = cur_x_q + write_x_w;
wire [15:0] next_y_w  = cur_y_q + 16'd1;

// This is the last write
reg         end_reached_r;
reg         end_of_line_r;

// The last write has been performed
wire        xfer_complete_w;

always @ *
begin
    start_x_r     = start_x_q;
    start_y_r     = start_y_q;
    cur_x_r       = cur_x_q;
    cur_y_r       = cur_y_q;
    end_x_r       = end_x_q;
    end_y_r       = end_y_q;
    end_reached_r = 1'b0;
    end_of_line_r = 1'b0;

    if (req_valid_i && req_accept_o)
    begin
        start_x_r = req_x_i;
        start_y_r = req_y_i;
        cur_x_r   = req_x_i;
        cur_y_r   = req_y_i;
        end_x_r   = req_x_i + req_sizex_i;
        end_y_r   = req_y_i + req_sizey_i;
    end
    else if (pixel_l_pop_w)
    begin
        // Advance
        if (next_x_w >= end_x_r)
        begin
            end_of_line_r = 1'b1;

            if (next_y_w >= end_y_r)
            begin
                cur_y_r       = next_y_w;
                end_reached_r = 1'b1;
            end
            else
            begin
                cur_x_r = start_x_r;
                cur_y_r = next_y_w;
            end
        end
        else
            cur_x_r = cur_x_r + write_x_w;
    end
end

wire flush_line_w = (state_q == STATE_FILL) && (end_of_line_r || (next_x_w[15:4] != cur_x_q[15:4]));

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
localparam STATE_W           = 3;
localparam STATE_IDLE        = 3'd0;
localparam STATE_RD_STENCIL  = 3'd1;
localparam STATE_FILL        = 3'd2;
localparam STATE_WR_STENCIL  = 3'd3;
localparam STATE_DONE        = 3'd4;

reg [STATE_W-1:0] state_q;
reg [STATE_W-1:0] next_state_r;

always @ *
begin
    next_state_r = state_q;

    case (state_q)
    STATE_IDLE :
    begin
        if (req_valid_i && req_accept_o)
            next_state_r = STATE_RD_STENCIL;
    end
    STATE_RD_STENCIL :
    begin
        if (fifo_space_w)
            next_state_r = STATE_FILL;
    end
    STATE_FILL :
    begin
        if (flush_line_w)
            next_state_r = STATE_WR_STENCIL;
    end
    STATE_WR_STENCIL:
    begin
        if (xfer_complete_w)
            next_state_r = STATE_DONE;
        else
            next_state_r = STATE_RD_STENCIL;
    end
    STATE_DONE :
    begin
        // Wait until all writes drained
        if (~gpu_command_o)
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
assign done_o          = state_q == STATE_DONE && (next_state_r == STATE_IDLE);
assign req_accept_o    = state_q == STATE_IDLE;

//-----------------------------------------------------------------
// Stencil read
//-----------------------------------------------------------------
wire [15:0] stencil_data_w;

assign stencil_rd_req_o  = (state_q == STATE_RD_STENCIL);
assign stencil_rd_addr_o = {cur_y_q[8:0], cur_x_q[9:4]};

reg stencil_rd_req_q;

always @ (posedge clk_i )
if (rst_i)
    stencil_rd_req_q <= 1'b0;
else
    stencil_rd_req_q <= stencil_rd_req_o;

reg [15:0] stencil_data_q;

always @ (posedge clk_i )
if (rst_i)
    stencil_data_q <= 16'b0;
else
    stencil_data_q <= stencil_data_w;

// Stencil data: bit=1 -> do not write pixel
assign stencil_data_w = stencil_rd_req_q ? (stencil_rd_value_i & {16{req_use_mask_q}}) : stencil_data_q; 

//-----------------------------------------------------------------
// Line builder
//-----------------------------------------------------------------
reg [255:0] word_data_q;
reg  [15:0] word_mask_q;

reg [255:0] word_data_r;
reg  [15:0] word_mask_r;

wire pixels_ready_w = (write_x_w == 16'd2) ? (pixel_r_valid_w && pixel_l_valid_w) : pixel_l_valid_w;

always @ *
begin
    word_data_r  = 256'b0;
    word_mask_r  = 16'b0;

    if (state_q == STATE_RD_STENCIL)
    begin
        word_data_r  = 256'b0;
        word_mask_r  = 16'b0;
    end
    else if (state_q == STATE_FILL)
    begin
        word_data_r  = word_data_q;
        word_mask_r  = word_mask_q;

        case (cur_x_q[3:0])
        4'd0: word_data_r[31:0] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd1: word_data_r[47:16] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd2: word_data_r[63:32] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd3: word_data_r[79:48] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd4: word_data_r[95:64] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd5: word_data_r[111:80] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd6: word_data_r[127:96] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd7: word_data_r[143:112] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd8: word_data_r[159:128] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd9: word_data_r[175:144] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd10: word_data_r[191:160] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd11: word_data_r[207:176] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd12: word_data_r[223:192] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd13: word_data_r[239:208] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        4'd14: word_data_r[255:224] = {pixel_r_data_w, pixel_l_data_w} | {req_set_mask_q, 15'b0, req_set_mask_q, 15'b0};
        default: word_data_r[255:240] = pixel_l_data_w | {req_set_mask_q, 15'b0};
        endcase

        case (cur_x_q[3:0])
        4'd0: word_mask_r[1:0] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[1:0];
        4'd1: word_mask_r[2:1] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[2:1];
        4'd2: word_mask_r[3:2] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[3:2];
        4'd3: word_mask_r[4:3] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[4:3];
        4'd4: word_mask_r[5:4] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[5:4];
        4'd5: word_mask_r[6:5] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[6:5];
        4'd6: word_mask_r[7:6] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[7:6];
        4'd7: word_mask_r[8:7] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[8:7];
        4'd8: word_mask_r[9:8] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[9:8];
        4'd9: word_mask_r[10:9] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[10:9];
        4'd10: word_mask_r[11:10] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[11:10];
        4'd11: word_mask_r[12:11] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[12:11];
        4'd12: word_mask_r[13:12] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[13:12];
        4'd13: word_mask_r[14:13] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[14:13];
        4'd14: word_mask_r[15:14] = {pixel_r_pop_w, pixel_l_pop_w} & ~stencil_data_w[15:14];
        default: word_mask_r[15] = pixel_l_pop_w & ~stencil_data_w[15];
        endcase
    end
end

always @ (posedge clk_i )
if (rst_i)
    word_data_q <= 256'b0;
else
    word_data_q <= word_data_r;

always @ (posedge clk_i )
if (rst_i)
    word_mask_q <= 16'b0;
else
    word_mask_q <= word_mask_r;

//-----------------------------------------------------------------
// Stencil write
//-----------------------------------------------------------------
reg [14:0] stencil_addr_q;

always @ (posedge clk_i )
if (rst_i)
    stencil_addr_q <= 15'b0;
else if (stencil_rd_req_o)
    stencil_addr_q <= stencil_rd_addr_o;

assign stencil_wr_req_o   = (state_q == STATE_WR_STENCIL);
assign stencil_wr_addr_o  = stencil_addr_q;
assign stencil_wr_mask_o  = word_mask_q;

// Generated
assign stencil_wr_value_o[0] = word_data_q[15];
assign stencil_wr_value_o[1] = word_data_q[31];
assign stencil_wr_value_o[2] = word_data_q[47];
assign stencil_wr_value_o[3] = word_data_q[63];
assign stencil_wr_value_o[4] = word_data_q[79];
assign stencil_wr_value_o[5] = word_data_q[95];
assign stencil_wr_value_o[6] = word_data_q[111];
assign stencil_wr_value_o[7] = word_data_q[127];
assign stencil_wr_value_o[8] = word_data_q[143];
assign stencil_wr_value_o[9] = word_data_q[159];
assign stencil_wr_value_o[10] = word_data_q[175];
assign stencil_wr_value_o[11] = word_data_q[191];
assign stencil_wr_value_o[12] = word_data_q[207];
assign stencil_wr_value_o[13] = word_data_q[223];
assign stencil_wr_value_o[14] = word_data_q[239];
assign stencil_wr_value_o[15] = word_data_q[255];

//-----------------------------------------------------------------
// Pixel pop
//-----------------------------------------------------------------
assign pixel_l_pop_w = (state_q == STATE_FILL) && pixels_ready_w && (write_x_w >= 16'd1);
assign pixel_r_pop_w = (state_q == STATE_FILL) && pixels_ready_w && (write_x_w >= 16'd2);

//-----------------------------------------------------------------
// Memory Request
//-----------------------------------------------------------------
gpu_mem_cpuvram_fifo
#(
     .WIDTH(256 + 16 + 15)
    ,.DEPTH(2)
    ,.ADDR_W(1)
)
u_mem_req
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(flush_line_w)
    ,.data_in_i({mem_addr_w[19:5], word_mask_r, word_data_r})
    ,.accept_o(fifo_space_w)

    // Outputs
    ,.data_out_o({gpu_addr_o, gpu_write_mask_o, gpu_data_out_o})
    ,.valid_o(gpu_command_o)
    ,.pop_i(~gpu_busy_i)
);

assign gpu_write_o      = 1'b1;
assign gpu_size_o       = GPU_CMDSZ_32_BYTE;
assign gpu_sub_addr_o   = 3'b0;


endmodule
