
module gpu_mem_cache
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           gpu_command_i
    ,input  [  1:0]  gpu_size_i
    ,input           gpu_write_i
    ,input  [ 14:0]  gpu_addr_lin_i
    ,input  [  2:0]  gpu_sub_addr_i
    ,input  [ 15:0]  gpu_write_mask_i
    ,input  [255:0]  gpu_data_out_i
    ,input           mem_busy_i
    ,input           mem_data_in_valid_i
    ,input  [255:0]  mem_data_in_i

    // Outputs
    ,output          gpu_busy_o
    ,output          gpu_data_in_valid_o
    ,output [255:0]  gpu_data_in_o
    ,output          mem_command_o
    ,output [  1:0]  mem_size_o
    ,output          mem_write_o
    ,output [ 14:0]  mem_addr_o
    ,output [  2:0]  mem_sub_addr_o
    ,output [ 15:0]  mem_write_mask_o
    ,output [255:0]  mem_data_out_o
);

reg [31:0]  access_addr_q;

// Swizzle here.   (Make swizzle for internal usage)
wire [14:0] gpu_addr_i			= gpu_addr_lin_i;
// Unswizzle here. (Make linear for memory access)
wire [14:0] unswizzle_adr_out	= access_addr_q[14+5:5];

//-----------------------------------------------------------------
// This cache instance is 2 way set associative.
// The total size is 16KB.
// The replacement policy is a limited pseudo random scheme
// (between lines, toggling on line thrashing).
// The cache is a write through cache, with allocate on read.
//-----------------------------------------------------------------
// Number of ways
parameter GPU_CACHE_NUM_WAYS           = 2;

// Number of cache lines
parameter GPU_CACHE_NUM_LINES          = 256;
parameter GPU_CACHE_LINE_ADDR_W        = 8;

// Line size (e.g. 32-bytes)
parameter GPU_CACHE_LINE_SIZE_W        = 5;
parameter GPU_CACHE_LINE_SIZE          = 32;
parameter GPU_CACHE_LINE_WORDS         = 8;

// Request -> tag address mapping
parameter GPU_CACHE_TAG_REQ_LINE_L     = 5;  // GPU_CACHE_LINE_SIZE_W
parameter GPU_CACHE_TAG_REQ_LINE_H     = 12; // GPU_CACHE_LINE_ADDR_W+GPU_CACHE_LINE_SIZE_W-1
parameter GPU_CACHE_TAG_REQ_LINE_W     = 8;  // GPU_CACHE_LINE_ADDR_W
`define GPU_CACHE_TAG_REQ_RNG          GPU_CACHE_TAG_REQ_LINE_H:GPU_CACHE_TAG_REQ_LINE_L

// Tag fields
`define GPU_CACHE_TAG_ADDR_RNG          18:0
parameter GPU_CACHE_TAG_ADDR_BITS       = 19;
parameter GPU_CACHE_TAG_VALID_BIT       = GPU_CACHE_TAG_ADDR_BITS;
parameter GPU_CACHE_TAG_DATA_W          = GPU_CACHE_TAG_VALID_BIT + 1;

// Tag compare bits
parameter GPU_CACHE_TAG_CMP_ADDR_L     = GPU_CACHE_TAG_REQ_LINE_H + 1;
parameter GPU_CACHE_TAG_CMP_ADDR_H     = 32-1;
parameter GPU_CACHE_TAG_CMP_ADDR_W     = GPU_CACHE_TAG_CMP_ADDR_H - GPU_CACHE_TAG_CMP_ADDR_L + 1;
`define   GPU_CACHE_TAG_CMP_ADDR_RNG   31:13

// Address mapping example:
//  31          16 15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
// |--------------|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
//  +--------------------+  +--------------------+ 
//  |  Tag address.      |  |   Line address     | 
//  |                    |  |                    | 
//  |                    |  |                    |
//  |                    |  |                    |- GPU_CACHE_TAG_REQ_LINE_L
//  |                    |  |- GPU_CACHE_TAG_REQ_LINE_H
//  |                    |- GPU_CACHE_TAG_CMP_ADDR_L
//  |- GPU_CACHE_TAG_CMP_ADDR_H

// Full address
wire [31:0]                      gpu_addr_w = {12'b0, gpu_addr_i, gpu_sub_addr_i, 2'b0};

// Tag addressing and match value
wire [GPU_CACHE_TAG_REQ_LINE_W-1:0] req_line_addr_w  = gpu_addr_w[`GPU_CACHE_TAG_REQ_RNG];

// Data addressing
wire [GPU_CACHE_LINE_ADDR_W-1:0] req_data_addr_w = gpu_addr_w[GPU_CACHE_LINE_ADDR_W+5-1:5];

wire gpu_read_w  = gpu_command_i & ~gpu_write_i;
wire gpu_write_w = gpu_command_i &  gpu_write_i;
reg  gpu_accept_r;

localparam GPU_CMDSZ_8_BYTE  = 2'd0;
localparam GPU_CMDSZ_32_BYTE = 2'd1;
localparam GPU_CMDSZ_4_BYTE  = 2'd2;

//-----------------------------------------------------------------
// States
//-----------------------------------------------------------------
localparam STATE_W           = 2;
localparam STATE_FLUSH       = 2'd0;
localparam STATE_LOOKUP      = 2'd1;
localparam STATE_REFILL      = 2'd2;
localparam STATE_RELOOKUP    = 2'd3;

//-----------------------------------------------------------------
// Registers / Wires
//-----------------------------------------------------------------

// States
reg [STATE_W-1:0]           next_state_r;
reg [STATE_W-1:0]           state_q;

reg [0:0]  replace_way_q;

//-----------------------------------------------------------------
// Lookup validation
//-----------------------------------------------------------------
reg access_valid_q;

always @ (posedge clk_i )
if (rst_i)
    access_valid_q <= 1'b0;
else if ((gpu_read_w || gpu_write_w) && gpu_accept_r)
    access_valid_q <= 1'b1;
else
    access_valid_q <= 1'b0;

//-----------------------------------------------------------------
// Flopped request
//-----------------------------------------------------------------
reg [255:0] access_data_q;
reg [15:0]  access_mask_q;
reg         access_wr_q;
reg         access_rd_q;
reg         access_rd_8_q;
reg [1:0]   access_idx_q;

always @ (posedge clk_i )
if (rst_i)
begin
    access_addr_q <= 32'b0;
    access_data_q <= 256'b0;
    access_mask_q <= 16'b0;
    access_wr_q   <= 1'b0;
    access_rd_q   <= 1'b0;
    access_rd_8_q <= 1'b0;
    access_idx_q  <= 2'b0;
end
else if ((gpu_read_w || gpu_write_w) && gpu_accept_r)
begin
    access_addr_q <= gpu_addr_w;
    access_data_q <= gpu_data_out_i;
    access_mask_q <= gpu_write_mask_i;
    access_wr_q   <= gpu_write_w;
    access_rd_q   <= gpu_read_w;
    access_rd_8_q <= (gpu_size_i == GPU_CMDSZ_8_BYTE);
    access_idx_q  <= gpu_sub_addr_i[2:1];
end
else if (gpu_data_in_valid_o || (state_q == STATE_LOOKUP && next_state_r == STATE_LOOKUP))
begin
    access_addr_q <= 32'b0;
    access_data_q <= 256'b0;
    access_mask_q <= 16'b0;
    access_wr_q   <= 1'b0;
    access_rd_q   <= 1'b0;
    access_rd_8_q <= 1'b0;
    access_idx_q  <= 2'b0;
end

wire [GPU_CACHE_TAG_CMP_ADDR_W-1:0] req_addr_tag_cmp_w = access_addr_q[`GPU_CACHE_TAG_CMP_ADDR_RNG];

//-----------------------------------------------------------------
// TAG RAMS
//-----------------------------------------------------------------
reg [GPU_CACHE_TAG_REQ_LINE_W-1:0] tag_addr_r;

// Tag RAM address
always @ *
begin
    tag_addr_r = flush_addr_q;

    // Cache flush
    if (state_q == STATE_FLUSH)
        tag_addr_r = flush_addr_q;
    // Line refill / write
    else if (state_q == STATE_REFILL || state_q == STATE_RELOOKUP)
        tag_addr_r = access_addr_q[`GPU_CACHE_TAG_REQ_RNG];
    // Lookup
    else
        tag_addr_r = req_line_addr_w;
end

// Tag RAM write data
reg [GPU_CACHE_TAG_DATA_W-1:0] tag_data_in_r;
always @ *
begin
    tag_data_in_r = {(GPU_CACHE_TAG_DATA_W){1'b0}};

    // Cache flush
    if (state_q == STATE_FLUSH)
        tag_data_in_r = {(GPU_CACHE_TAG_DATA_W){1'b0}};
    // Line refill
    else if (state_q == STATE_REFILL)
    begin
        tag_data_in_r[GPU_CACHE_TAG_VALID_BIT] = 1'b1;
        tag_data_in_r[`GPU_CACHE_TAG_ADDR_RNG] = access_addr_q[`GPU_CACHE_TAG_CMP_ADDR_RNG];
    end
end

// Tag RAM write enable (way 0)
reg tag0_write_r;
always @ *
begin
    tag0_write_r = 1'b0;

    // Cache flush
    if (state_q == STATE_FLUSH)
        tag0_write_r = 1'b1;
    // Line refill
    else if (state_q == STATE_REFILL)
        tag0_write_r = mem_data_in_valid_i && (replace_way_q == 0);
end

wire [GPU_CACHE_TAG_DATA_W-1:0] tag0_data_out_w;

gpu_mem_cache_tag_ram
u_tag0
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(tag_addr_r),
  .data_i(tag_data_in_r),
  .wr_i(tag0_write_r),
  .data_o(tag0_data_out_w)
);

wire                               tag0_valid_w     = tag0_data_out_w[GPU_CACHE_TAG_VALID_BIT];
wire [GPU_CACHE_TAG_ADDR_BITS-1:0] tag0_addr_bits_w = tag0_data_out_w[`GPU_CACHE_TAG_ADDR_RNG];

// Tag hit?
wire                               tag0_hit_w = tag0_valid_w ? (tag0_addr_bits_w == req_addr_tag_cmp_w) : 1'b0;

// Tag RAM write enable (way 1)
reg tag1_write_r;
always @ *
begin
    tag1_write_r = 1'b0;

    // Cache flush
    if (state_q == STATE_FLUSH)
        tag1_write_r = 1'b1;
    // Line refill
    else if (state_q == STATE_REFILL)
        tag1_write_r = mem_data_in_valid_i && (replace_way_q == 1);
end

wire [GPU_CACHE_TAG_DATA_W-1:0] tag1_data_out_w;

gpu_mem_cache_tag_ram
u_tag1
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(tag_addr_r),
  .data_i(tag_data_in_r),
  .wr_i(tag1_write_r),
  .data_o(tag1_data_out_w)
);

wire                               tag1_valid_w     = tag1_data_out_w[GPU_CACHE_TAG_VALID_BIT];
wire [GPU_CACHE_TAG_ADDR_BITS-1:0] tag1_addr_bits_w = tag1_data_out_w[`GPU_CACHE_TAG_ADDR_RNG];

// Tag hit?
wire                               tag1_hit_w = tag1_valid_w ? (tag1_addr_bits_w == req_addr_tag_cmp_w) : 1'b0;


wire tag_hit_any_w = 1'b0
                   | tag0_hit_w
                   | tag1_hit_w
                    ;

//-----------------------------------------------------------------
// DATA RAMS
//-----------------------------------------------------------------
reg [GPU_CACHE_LINE_ADDR_W-1:0] data_addr_r;

// Data RAM address
always @ *
begin
    data_addr_r = req_data_addr_w;

    // Line refill
    if (state_q == STATE_REFILL)
        data_addr_r = access_addr_q[GPU_CACHE_LINE_ADDR_W+5-1:5];
    // Lookup after refill
    else if (state_q == STATE_RELOOKUP)
        data_addr_r = access_addr_q[GPU_CACHE_LINE_ADDR_W+5-1:5];
    // Possible line update on write
    else if (access_valid_q && access_wr_q)
        data_addr_r = access_addr_q[GPU_CACHE_LINE_ADDR_W+5-1:5];
    // Lookup
    else
        data_addr_r = req_data_addr_w;
end


// Data RAM write enable (way 0)
reg [15:0] data0_write_r;
always @ *
begin
    data0_write_r = 16'b0;

    if (state_q == STATE_LOOKUP)
        data0_write_r = {16{access_wr_q}} & {16{access_valid_q & tag0_hit_w}} & access_mask_q;
    else if (state_q == STATE_REFILL)
        data0_write_r = (mem_data_in_valid_i && replace_way_q == 0) ? 16'hFFFF : 16'h0000;
end

wire [255:0] data0_data_out_w;
wire [255:0] data0_data_in_w = (state_q == STATE_REFILL) ? mem_data_in_i : access_data_q;

wire [31:0]  data0_write_en_w;

assign data0_write_en_w[0+1:0] = {2{data0_write_r[0]}};
assign data0_write_en_w[2+1:2] = {2{data0_write_r[1]}};
assign data0_write_en_w[4+1:4] = {2{data0_write_r[2]}};
assign data0_write_en_w[6+1:6] = {2{data0_write_r[3]}};
assign data0_write_en_w[8+1:8] = {2{data0_write_r[4]}};
assign data0_write_en_w[10+1:10] = {2{data0_write_r[5]}};
assign data0_write_en_w[12+1:12] = {2{data0_write_r[6]}};
assign data0_write_en_w[14+1:14] = {2{data0_write_r[7]}};
assign data0_write_en_w[16+1:16] = {2{data0_write_r[8]}};
assign data0_write_en_w[18+1:18] = {2{data0_write_r[9]}};
assign data0_write_en_w[20+1:20] = {2{data0_write_r[10]}};
assign data0_write_en_w[22+1:22] = {2{data0_write_r[11]}};
assign data0_write_en_w[24+1:24] = {2{data0_write_r[12]}};
assign data0_write_en_w[26+1:26] = {2{data0_write_r[13]}};
assign data0_write_en_w[28+1:28] = {2{data0_write_r[14]}};
assign data0_write_en_w[30+1:30] = {2{data0_write_r[15]}};

gpu_mem_cache_data_ram
u_data0_0
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[31:0]),
  .wr_i(data0_write_en_w[3:0]),
  .data_o(data0_data_out_w[31:0])
);

gpu_mem_cache_data_ram
u_data0_1
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[63:32]),
  .wr_i(data0_write_en_w[7:4]),
  .data_o(data0_data_out_w[63:32])
);

gpu_mem_cache_data_ram
u_data0_2
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[95:64]),
  .wr_i(data0_write_en_w[11:8]),
  .data_o(data0_data_out_w[95:64])
);

gpu_mem_cache_data_ram
u_data0_3
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[127:96]),
  .wr_i(data0_write_en_w[15:12]),
  .data_o(data0_data_out_w[127:96])
);

gpu_mem_cache_data_ram
u_data0_4
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[159:128]),
  .wr_i(data0_write_en_w[19:16]),
  .data_o(data0_data_out_w[159:128])
);

gpu_mem_cache_data_ram
u_data0_5
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[191:160]),
  .wr_i(data0_write_en_w[23:20]),
  .data_o(data0_data_out_w[191:160])
);

gpu_mem_cache_data_ram
u_data0_6
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[223:192]),
  .wr_i(data0_write_en_w[27:24]),
  .data_o(data0_data_out_w[223:192])
);

gpu_mem_cache_data_ram
u_data0_7
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data0_data_in_w[255:224]),
  .wr_i(data0_write_en_w[31:28]),
  .data_o(data0_data_out_w[255:224])
);


// Data RAM write enable (way 1)
reg [15:0] data1_write_r;
always @ *
begin
    data1_write_r = 16'b0;

    if (state_q == STATE_LOOKUP)
        data1_write_r = {16{access_wr_q}} & {16{access_valid_q & tag1_hit_w}} & access_mask_q;
    else if (state_q == STATE_REFILL)
        data1_write_r = (mem_data_in_valid_i && replace_way_q == 1) ? 16'hFFFF : 16'h0000;
end

wire [255:0] data1_data_out_w;
wire [255:0] data1_data_in_w = (state_q == STATE_REFILL) ? mem_data_in_i : access_data_q;

wire [31:0]  data1_write_en_w;

assign data1_write_en_w[0+1:0] = {2{data1_write_r[0]}};
assign data1_write_en_w[2+1:2] = {2{data1_write_r[1]}};
assign data1_write_en_w[4+1:4] = {2{data1_write_r[2]}};
assign data1_write_en_w[6+1:6] = {2{data1_write_r[3]}};
assign data1_write_en_w[8+1:8] = {2{data1_write_r[4]}};
assign data1_write_en_w[10+1:10] = {2{data1_write_r[5]}};
assign data1_write_en_w[12+1:12] = {2{data1_write_r[6]}};
assign data1_write_en_w[14+1:14] = {2{data1_write_r[7]}};
assign data1_write_en_w[16+1:16] = {2{data1_write_r[8]}};
assign data1_write_en_w[18+1:18] = {2{data1_write_r[9]}};
assign data1_write_en_w[20+1:20] = {2{data1_write_r[10]}};
assign data1_write_en_w[22+1:22] = {2{data1_write_r[11]}};
assign data1_write_en_w[24+1:24] = {2{data1_write_r[12]}};
assign data1_write_en_w[26+1:26] = {2{data1_write_r[13]}};
assign data1_write_en_w[28+1:28] = {2{data1_write_r[14]}};
assign data1_write_en_w[30+1:30] = {2{data1_write_r[15]}};

gpu_mem_cache_data_ram
u_data1_0
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[31:0]),
  .wr_i(data1_write_en_w[3:0]),
  .data_o(data1_data_out_w[31:0])
);

gpu_mem_cache_data_ram
u_data1_1
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[63:32]),
  .wr_i(data1_write_en_w[7:4]),
  .data_o(data1_data_out_w[63:32])
);

gpu_mem_cache_data_ram
u_data1_2
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[95:64]),
  .wr_i(data1_write_en_w[11:8]),
  .data_o(data1_data_out_w[95:64])
);

gpu_mem_cache_data_ram
u_data1_3
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[127:96]),
  .wr_i(data1_write_en_w[15:12]),
  .data_o(data1_data_out_w[127:96])
);

gpu_mem_cache_data_ram
u_data1_4
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[159:128]),
  .wr_i(data1_write_en_w[19:16]),
  .data_o(data1_data_out_w[159:128])
);

gpu_mem_cache_data_ram
u_data1_5
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[191:160]),
  .wr_i(data1_write_en_w[23:20]),
  .data_o(data1_data_out_w[191:160])
);

gpu_mem_cache_data_ram
u_data1_6
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[223:192]),
  .wr_i(data1_write_en_w[27:24]),
  .data_o(data1_data_out_w[223:192])
);

gpu_mem_cache_data_ram
u_data1_7
(
  .clk_i(clk_i),
  .rst_i(rst_i),
  .addr_i(data_addr_r),
  .data_i(data1_data_in_w[255:224]),
  .wr_i(data1_write_en_w[31:28]),
  .data_o(data1_data_out_w[255:224])
);


//-----------------------------------------------------------------
// Flush counter
//-----------------------------------------------------------------
reg [GPU_CACHE_TAG_REQ_LINE_W-1:0] flush_addr_q;

always @ (posedge clk_i )
if (rst_i)
    flush_addr_q <= {(GPU_CACHE_TAG_REQ_LINE_W){1'b0}};
else if (state_q == STATE_FLUSH)
    flush_addr_q <= flush_addr_q + 1;
else
    flush_addr_q <= {(GPU_CACHE_TAG_REQ_LINE_W){1'b0}};

//-----------------------------------------------------------------
// Replacement Policy
//----------------------------------------------------------------- 
// Using random replacement policy - this way we cycle through the ways
// when needing to replace a line.
always @ (posedge clk_i )
if (rst_i)
    replace_way_q <= 0;
else if (state_q == STATE_REFILL && mem_data_in_valid_i)
    replace_way_q <= replace_way_q + 1;

//-----------------------------------------------------------------
// Output Result / Ack
//-----------------------------------------------------------------
assign gpu_data_in_valid_o = ((state_q == STATE_LOOKUP && access_rd_q) ? tag_hit_any_w : 1'b0) | mem_data_in_valid_i;

// Data output mux
reg [255:0] data_r;
always @ *
begin
    data_r = data0_data_out_w;

    // Read response to cache miss
    if (mem_data_in_valid_i)
        data_r = mem_data_in_i;
    // Cache access
    else
    begin
        case (1'b1)
        tag0_hit_w: data_r = data0_data_out_w;
        tag1_hit_w: data_r = data1_data_out_w;
        endcase
    end

    // Narrow read (8-byte read)
    if (access_rd_8_q)
    begin
        case (access_idx_q)
        2'd0: data_r = {192'b0, data_r[63:0]};
        2'd1: data_r = {192'b0, data_r[127:64]};
        2'd2: data_r = {192'b0, data_r[191:128]};
        2'd3: data_r = {192'b0, data_r[255:192]};
        endcase
    end
end

assign gpu_data_in_o  = data_r;

//-----------------------------------------------------------------
// Next State Logic
//-----------------------------------------------------------------
always @ *
begin
    next_state_r = state_q;

    case (state_q)
    //-----------------------------------------
    // STATE_FLUSH
    //-----------------------------------------
    STATE_FLUSH :
    begin
        if (flush_addr_q == {(GPU_CACHE_TAG_REQ_LINE_W){1'b1}})
            next_state_r = STATE_LOOKUP;
    end
    //-----------------------------------------
    // STATE_LOOKUP
    //-----------------------------------------
    STATE_LOOKUP :
    begin
        // Tried a lookup but no match found
        if (access_rd_q && !tag_hit_any_w)
            next_state_r = STATE_REFILL;
        // Read or Write
        else if (gpu_read_w || gpu_write_w)
            ;
    end
    //-----------------------------------------
    // STATE_REFILL
    //-----------------------------------------
    STATE_REFILL :
    begin
        // End of refill
        if (mem_data_in_valid_i)
            next_state_r = STATE_RELOOKUP;
    end
    //-----------------------------------------
    // STATE_RELOOKUP
    //-----------------------------------------
    STATE_RELOOKUP :
    begin
        next_state_r = STATE_LOOKUP;
    end
    default:
        ;
    endcase
end

// Update state
always @ (posedge clk_i )
if (rst_i)
    state_q   <= STATE_FLUSH;
else
    state_q   <= next_state_r;

// Pipeline requests of the same type
wire same_request_type_w = (gpu_read_w  == access_rd_q) && 
                           (gpu_write_w == access_wr_q);
wire no_requests_pending_w = (!access_rd_q && !access_wr_q);

wire can_accept_w = same_request_type_w | no_requests_pending_w;

always @ *
begin
    gpu_accept_r = 1'b0;

    if (state_q == STATE_LOOKUP)
    begin
        // Previous request missed
        if (next_state_r == STATE_REFILL)
            gpu_accept_r = 1'b0;
        // Write request - on AXI accept
        else if (gpu_write_w)
            gpu_accept_r = ~mem_busy_i && can_accept_w;
        // Misc (cached read / flush)
        else
            gpu_accept_r = can_accept_w;
    end
end

assign gpu_busy_o = ~gpu_accept_r;

//-----------------------------------------------------------------
// Memory Request
//-----------------------------------------------------------------
reg mem_read_q;

always @ (posedge clk_i )
if (rst_i)
    mem_read_q   <= 1'b0;
else if (mem_command_o && !mem_write_o)
    mem_read_q   <= mem_busy_i;

wire refill_request_w   = (state_q == STATE_LOOKUP && next_state_r == STATE_REFILL);

assign mem_command_o    = (state_q == STATE_LOOKUP && gpu_write_w & can_accept_w) || (refill_request_w || mem_read_q);
assign mem_write_o      = ~(refill_request_w || mem_read_q);
assign mem_addr_o       = (refill_request_w || mem_read_q) ? unswizzle_adr_out : gpu_addr_lin_i;
assign mem_write_mask_o = gpu_write_mask_i;
assign mem_data_out_o   = gpu_data_out_i;
assign mem_size_o       = GPU_CMDSZ_32_BYTE;
assign mem_sub_addr_o   = 3'b0;

//-----------------------------------------------------------------
// Debug
//-----------------------------------------------------------------
`ifdef verilator
reg [79:0] dbg_state;
always @ *
begin
    dbg_state = "-";

    case (state_q)
    STATE_FLUSH    : dbg_state = "FLUSH   ";
    STATE_LOOKUP   : dbg_state = "LOOKUP  ";
    STATE_REFILL   : dbg_state = "REFILL  ";
    STATE_RELOOKUP : dbg_state = "RELOOKUP";
    default:
        ;
    endcase
end
`endif


endmodule
