
module gpu_mem_vramvram
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           req_valid_i
    ,input  [ 15:0]  req_src_x_i
    ,input  [ 15:0]  req_src_y_i
    ,input  [ 15:0]  req_dst_x_i
    ,input  [ 15:0]  req_dst_y_i
    ,input  [ 15:0]  req_sizex_i
    ,input  [ 15:0]  req_sizey_i
    ,input           req_set_mask_i
    ,input           req_use_mask_i
    ,input  [ 15:0]  stencil_rd_value_i
    ,input           gpu_busy_i
    ,input           gpu_data_in_valid_i
    ,input  [255:0]  gpu_data_in_i

    // Outputs
    ,output          req_accept_o
    ,output          busy_o
    ,output          done_o
    ,output          stencil_rd_req_o
    ,output [ 14:0]  stencil_rd_addr_o
    ,output          stencil_wr_req_o
    ,output [ 14:0]  stencil_wr_addr_o
    ,output [ 15:0]  stencil_wr_mask_o
    ,output [ 15:0]  stencil_wr_value_o
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

// Move from higher address to lower address - copy left to right (incr)
// Move from lower address to higher address - copy right to left (decr)
wire req_incr_w = (req_src_x_i >= req_dst_x_i);

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

reg  req_incr_q;

always @ (posedge clk_i )
if (rst_i)
    req_incr_q <= 1'b0;
else if (req_accept_o)
    req_incr_q <= req_incr_w;

//-----------------------------------------------------------------
// Read - perform reads from VRAM
//-----------------------------------------------------------------
wire          gpu_rd_command_w;
wire [  1:0]  gpu_rd_size_w;
wire          gpu_rd_write_w;
wire [ 14:0]  gpu_rd_addr_w;
wire [  2:0]  gpu_rd_sub_addr_w;
wire [ 15:0]  gpu_rd_write_mask_w;
wire [255:0]  gpu_rd_data_out_w;
wire          gpu_rd_busy_w;

wire          rd_data_valid_w;
wire [255:0]  rd_data_value_w;
wire [ 15:0]  rd_data_mask_w;
wire [ 3:0]   rd_data_offset_w;
wire          rd_data_end_line_w;
wire          rd_data_final_w;
wire          rd_data_accept_w;

gpu_mem_vram_read
u_read
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.req_valid_i(req_valid_i & req_accept_o)
    ,.req_src_x_i(req_src_x_i)
    ,.req_src_y_i(req_src_y_i)
    ,.req_incr_i(req_incr_w)
    ,.req_sizex_i(req_sizex_i)
    ,.req_sizey_i(req_sizey_i)
    ,.req_accept_o()

    ,.gpu_command_o(gpu_rd_command_w)
    ,.gpu_size_o(gpu_rd_size_w)
    ,.gpu_write_o(gpu_rd_write_w)
    ,.gpu_addr_o(gpu_rd_addr_w)
    ,.gpu_sub_addr_o(gpu_rd_sub_addr_w)
    ,.gpu_write_mask_o(gpu_rd_write_mask_w)
    ,.gpu_data_out_o(gpu_rd_data_out_w)
    ,.gpu_busy_i(gpu_rd_busy_w)
    ,.gpu_data_in_valid_i(gpu_data_in_valid_i)
    ,.gpu_data_in_i(gpu_data_in_i)

    ,.busy_o()

    ,.data_valid_o(rd_data_valid_w)
    ,.data_value_o(rd_data_value_w)
    ,.data_mask_o(rd_data_mask_w)
    ,.data_offset_o(rd_data_offset_w)
    ,.data_end_line_o(rd_data_end_line_w)
    ,.data_final_o(rd_data_final_w)
    ,.data_accept_i(rd_data_accept_w)
);

//-----------------------------------------------------------------
// Unroll incoming line (pixel by pixel)
//-----------------------------------------------------------------
wire [3:0] in_pixel_offset_w;
wire       in_pixel_accept_w;
reg        in_mid_line_q;

always @ (posedge clk_i )
if (rst_i)
    in_mid_line_q <= 1'b0;
else if (rd_data_valid_w && rd_data_accept_w)
    in_mid_line_q <= 1'b0;
else if (rd_data_valid_w && in_pixel_accept_w)
    in_mid_line_q <= 1'b1;

// Offset within the line of the first pixel
reg [3:0] in_pixel_offset_q;

always @ (posedge clk_i )
if (rst_i)
    in_pixel_offset_q <= 4'b0;
else if (in_pixel_accept_w)
    in_pixel_offset_q <= req_incr_q ? (in_pixel_offset_w + 4'd1) : (in_pixel_offset_w - 4'd1);

// Offset within the line of the pixel to extract
assign in_pixel_offset_w  = in_mid_line_q ? in_pixel_offset_q : rd_data_offset_w;

//-----------------------------------------------------------------
// Extract appropriate pixel from the response
//-----------------------------------------------------------------
reg          in_pixel_valid_r;
reg [15:0]   in_pixel_r;
reg          in_line_done_r;

always @ *
begin
    in_pixel_valid_r = rd_data_valid_w;
    in_pixel_r       = 16'b0;
    in_line_done_r   = 1'b0;

    case (in_pixel_offset_w)
    4'd0: in_pixel_r = rd_data_value_w[15:0];
    4'd1: in_pixel_r = rd_data_value_w[31:16];
    4'd2: in_pixel_r = rd_data_value_w[47:32];
    4'd3: in_pixel_r = rd_data_value_w[63:48];
    4'd4: in_pixel_r = rd_data_value_w[79:64];
    4'd5: in_pixel_r = rd_data_value_w[95:80];
    4'd6: in_pixel_r = rd_data_value_w[111:96];
    4'd7: in_pixel_r = rd_data_value_w[127:112];
    4'd8: in_pixel_r = rd_data_value_w[143:128];
    4'd9: in_pixel_r = rd_data_value_w[159:144];
    4'd10: in_pixel_r = rd_data_value_w[175:160];
    4'd11: in_pixel_r = rd_data_value_w[191:176];
    4'd12: in_pixel_r = rd_data_value_w[207:192];
    4'd13: in_pixel_r = rd_data_value_w[223:208];
    4'd14: in_pixel_r = rd_data_value_w[239:224];
    4'd15: in_pixel_r = rd_data_value_w[255:240];
    default: ;
    endcase

    // Forward
    if (req_incr_q)
    begin
        case (in_pixel_offset_w)
        4'd0: in_line_done_r = ~rd_data_mask_w[1];
        4'd1: in_line_done_r = ~rd_data_mask_w[2];
        4'd2: in_line_done_r = ~rd_data_mask_w[3];
        4'd3: in_line_done_r = ~rd_data_mask_w[4];
        4'd4: in_line_done_r = ~rd_data_mask_w[5];
        4'd5: in_line_done_r = ~rd_data_mask_w[6];
        4'd6: in_line_done_r = ~rd_data_mask_w[7];
        4'd7: in_line_done_r = ~rd_data_mask_w[8];
        4'd8: in_line_done_r = ~rd_data_mask_w[9];
        4'd9: in_line_done_r = ~rd_data_mask_w[10];
        4'd10: in_line_done_r = ~rd_data_mask_w[11];
        4'd11: in_line_done_r = ~rd_data_mask_w[12];
        4'd12: in_line_done_r = ~rd_data_mask_w[13];
        4'd13: in_line_done_r = ~rd_data_mask_w[14];
        4'd14: in_line_done_r = ~rd_data_mask_w[15];
        default: in_line_done_r = 1'b1;
        endcase
    end
    // Backward
    else
    begin
        case (in_pixel_offset_w)
        4'd1: in_line_done_r = ~rd_data_mask_w[0];
        4'd2: in_line_done_r = ~rd_data_mask_w[1];
        4'd3: in_line_done_r = ~rd_data_mask_w[2];
        4'd4: in_line_done_r = ~rd_data_mask_w[3];
        4'd5: in_line_done_r = ~rd_data_mask_w[4];
        4'd6: in_line_done_r = ~rd_data_mask_w[5];
        4'd7: in_line_done_r = ~rd_data_mask_w[6];
        4'd8: in_line_done_r = ~rd_data_mask_w[7];
        4'd9: in_line_done_r = ~rd_data_mask_w[8];
        4'd10: in_line_done_r = ~rd_data_mask_w[9];
        4'd11: in_line_done_r = ~rd_data_mask_w[10];
        4'd12: in_line_done_r = ~rd_data_mask_w[11];
        4'd13: in_line_done_r = ~rd_data_mask_w[12];
        4'd14: in_line_done_r = ~rd_data_mask_w[13];
        4'd15: in_line_done_r = ~rd_data_mask_w[14];
        default: in_line_done_r = 1'b1;
        endcase
    end
end

assign rd_data_accept_w = in_pixel_accept_w & in_line_done_r;

//-----------------------------------------------------------------
// Pixel FIFO
//-----------------------------------------------------------------
wire        pixel_ready_w;
wire [15:0] pixel_data_w;
wire        pixel_pop_w;

gpu_mem_fifo
#(
     .WIDTH(16)
    ,.DEPTH(4)
    ,.ADDR_W(2)
)
u_pixel_fifo
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(in_pixel_valid_r)
    ,.data_in_i(in_pixel_r)
    ,.accept_o(in_pixel_accept_w)

    ,.valid_o(pixel_ready_w)
    ,.data_out_o(pixel_data_w)
    ,.pop_i(pixel_pop_w)
);

//-----------------------------------------------------------------
// State machine
//-----------------------------------------------------------------
wire write_space_w;
wire out_line_ready_w;
wire out_line_last_w;

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
        if (write_space_w)
            next_state_r = STATE_FILL;
    end
    STATE_FILL :
    begin
        if (out_line_ready_w)
            next_state_r = STATE_WR_STENCIL;
    end
    STATE_WR_STENCIL:
    begin
        if (out_line_last_w)
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
// Dest address generation
//-----------------------------------------------------------------
wire          valid_w;
wire [31:0]   write_addr_w;
wire [3:0]    offset_w;
wire [15:0]   mask_w;
wire          out_line_accept_w;

gpu_mem_addr_gen
u_dst_addr
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.req_start_i(req_valid_i & req_accept_o)
    ,.req_incr_i(req_incr_w)
    ,.req_x_i(req_dst_x_i)
    ,.req_y_i(req_dst_y_i)
    ,.req_sizex_i(req_sizex_i)
    ,.req_sizey_i(req_sizey_i)

    ,.valid_o(valid_w)
    ,.addr_o(write_addr_w)
    ,.offset_o(offset_w)
    ,.mask_o(mask_w)
    ,.last_line_o()
    ,.last_o(out_line_last_w)
    ,.accept_i(out_line_accept_w)
);

//-----------------------------------------------------------------
// Reroll outcoming line
//-----------------------------------------------------------------
wire [3:0] out_offset_w;
reg        out_mid_q;

always @ (posedge clk_i )
if (rst_i)
    out_mid_q <= 1'b0;
else if (out_line_ready_w && pixel_pop_w && pixel_ready_w)
    out_mid_q <= 1'b0;
else if (pixel_ready_w && pixel_pop_w && pixel_ready_w)
    out_mid_q <= 1'b1;

// Offset within the line of the first pixel
reg [3:0] out_offset_q;

always @ (posedge clk_i )
if (rst_i)
    out_offset_q <= 4'b0;
else if (pixel_pop_w && pixel_ready_w)
    out_offset_q <= req_incr_q ? (out_offset_w + 4'd1) : (out_offset_w - 4'd1);

// Offset within the line of the pixel to extract
assign out_offset_w  = out_mid_q ? out_offset_q : offset_w;

reg out_line_done_r;

always @ *
begin
    out_line_done_r  = 1'b0;

    if (req_incr_q)
    begin
        case (out_offset_w)
        4'd0: out_line_done_r = ~mask_w[1];
        4'd1: out_line_done_r = ~mask_w[2];
        4'd2: out_line_done_r = ~mask_w[3];
        4'd3: out_line_done_r = ~mask_w[4];
        4'd4: out_line_done_r = ~mask_w[5];
        4'd5: out_line_done_r = ~mask_w[6];
        4'd6: out_line_done_r = ~mask_w[7];
        4'd7: out_line_done_r = ~mask_w[8];
        4'd8: out_line_done_r = ~mask_w[9];
        4'd9: out_line_done_r = ~mask_w[10];
        4'd10: out_line_done_r = ~mask_w[11];
        4'd11: out_line_done_r = ~mask_w[12];
        4'd12: out_line_done_r = ~mask_w[13];
        4'd13: out_line_done_r = ~mask_w[14];
        4'd14: out_line_done_r = ~mask_w[15];
        default: out_line_done_r = 1'b1;
        endcase
    end
    else
    begin
        case (out_offset_w)
        4'd1: out_line_done_r = ~mask_w[0];
        4'd2: out_line_done_r = ~mask_w[1];
        4'd3: out_line_done_r = ~mask_w[2];
        4'd4: out_line_done_r = ~mask_w[3];
        4'd5: out_line_done_r = ~mask_w[4];
        4'd6: out_line_done_r = ~mask_w[5];
        4'd7: out_line_done_r = ~mask_w[6];
        4'd8: out_line_done_r = ~mask_w[7];
        4'd9: out_line_done_r = ~mask_w[8];
        4'd10: out_line_done_r = ~mask_w[9];
        4'd11: out_line_done_r = ~mask_w[10];
        4'd12: out_line_done_r = ~mask_w[11];
        4'd13: out_line_done_r = ~mask_w[12];
        4'd14: out_line_done_r = ~mask_w[13];
        4'd15: out_line_done_r = ~mask_w[14];
        default: out_line_done_r = 1'b1;
        endcase
    end
end


// Pop pixel by pixel and build up a burst (line)
assign pixel_pop_w      = (state_q == STATE_FILL);

// End of a line (burst ready to go)
assign out_line_ready_w = pixel_ready_w & out_line_done_r;

//-----------------------------------------------------------------
// Stencil read
//-----------------------------------------------------------------
wire [15:0] stencil_data_w;

assign stencil_rd_req_o  = (state_q == STATE_RD_STENCIL);
assign stencil_rd_addr_o = {write_addr_w[19:11], write_addr_w[10:5]};

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

        case (out_offset_w)
        4'd0: word_data_r[15:0] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd1: word_data_r[31:16] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd2: word_data_r[47:32] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd3: word_data_r[63:48] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd4: word_data_r[79:64] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd5: word_data_r[95:80] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd6: word_data_r[111:96] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd7: word_data_r[127:112] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd8: word_data_r[143:128] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd9: word_data_r[159:144] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd10: word_data_r[175:160] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd11: word_data_r[191:176] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd12: word_data_r[207:192] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd13: word_data_r[223:208] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd14: word_data_r[239:224] = pixel_data_w | {req_set_mask_q, 15'b0};
        4'd15: word_data_r[255:240] = pixel_data_w | {req_set_mask_q, 15'b0};
        default: ;
        endcase

        case (out_offset_w)
        4'd0: word_mask_r[0] = mask_w[0] & ~stencil_data_w[0];
        4'd1: word_mask_r[1] = mask_w[1] & ~stencil_data_w[1];
        4'd2: word_mask_r[2] = mask_w[2] & ~stencil_data_w[2];
        4'd3: word_mask_r[3] = mask_w[3] & ~stencil_data_w[3];
        4'd4: word_mask_r[4] = mask_w[4] & ~stencil_data_w[4];
        4'd5: word_mask_r[5] = mask_w[5] & ~stencil_data_w[5];
        4'd6: word_mask_r[6] = mask_w[6] & ~stencil_data_w[6];
        4'd7: word_mask_r[7] = mask_w[7] & ~stencil_data_w[7];
        4'd8: word_mask_r[8] = mask_w[8] & ~stencil_data_w[8];
        4'd9: word_mask_r[9] = mask_w[9] & ~stencil_data_w[9];
        4'd10: word_mask_r[10] = mask_w[10] & ~stencil_data_w[10];
        4'd11: word_mask_r[11] = mask_w[11] & ~stencil_data_w[11];
        4'd12: word_mask_r[12] = mask_w[12] & ~stencil_data_w[12];
        4'd13: word_mask_r[13] = mask_w[13] & ~stencil_data_w[13];
        4'd14: word_mask_r[14] = mask_w[14] & ~stencil_data_w[14];
        4'd15: word_mask_r[15] = mask_w[15] & ~stencil_data_w[15];
        default: ;
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

assign out_line_accept_w = (state_q == STATE_WR_STENCIL);

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
// Write - perform writes to VRAM
//-----------------------------------------------------------------
wire          gpu_wr_command_w;
wire [ 14:0]  gpu_wr_addr_w;
wire [ 15:0]  gpu_wr_write_mask_w;
wire [255:0]  gpu_wr_data_out_w;
wire          gpu_wr_busy_w;

gpu_mem_fifo
#(
     .WIDTH(256 + 16 + 15)
    ,.DEPTH(2)
    ,.ADDR_W(1)
)
u_mem_req
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    ,.push_i(out_line_accept_w)
    ,.data_in_i({write_addr_w[19:5], word_mask_q, word_data_q})
    ,.accept_o(write_space_w)

    // Outputs
    ,.data_out_o({gpu_wr_addr_w, gpu_wr_write_mask_w, gpu_wr_data_out_w})
    ,.valid_o(gpu_wr_command_w)
    ,.pop_i(~gpu_wr_busy_w)
);

// The priority is for read over write
assign gpu_command_o    = gpu_rd_command_w ? gpu_rd_command_w    : gpu_wr_command_w;
assign gpu_write_o      = gpu_rd_command_w ? gpu_rd_write_w      : 1'b1;
assign gpu_addr_o       = gpu_rd_command_w ? gpu_rd_addr_w       : gpu_wr_addr_w;
assign gpu_write_mask_o = gpu_rd_command_w ? gpu_rd_write_mask_w : gpu_wr_write_mask_w;
assign gpu_data_out_o   = gpu_rd_command_w ? gpu_rd_data_out_w   : gpu_wr_data_out_w;
assign gpu_size_o       = GPU_CMDSZ_32_BYTE;
assign gpu_sub_addr_o   = 3'b0;

assign gpu_rd_busy_w    = gpu_busy_i;
assign gpu_wr_busy_w    = gpu_rd_command_w | gpu_busy_i;


endmodule
