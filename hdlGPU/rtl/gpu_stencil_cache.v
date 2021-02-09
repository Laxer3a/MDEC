
module gpu_stencil_cache
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input           stencil_rd_req_i
    ,input  [ 14:0]  stencil_rd_addr_i
    ,input           stencil_wr_req_i
    ,input  [ 14:0]  stencil_wr_addr_i
    ,input  [ 15:0]  stencil_wr_mask_i
    ,input  [ 15:0]  stencil_wr_value_i

    // Outputs
    ,output [ 15:0]  stencil_rd_value_o
);




wire direct_wr_w = stencil_wr_req_i && (stencil_wr_mask_i == 16'hFFFF);
wire delay_wr_w  = stencil_wr_req_i && (stencil_wr_mask_i != 16'hFFFF);

//-----------------------------------------------------------------
// Write Register
//-----------------------------------------------------------------
reg         wr_valid_q;
reg [14:0]  wr_addr_q;
reg [15:0]  wr_mask_q;
reg [15:0]  wr_data_q;

always @ (posedge clk_i )
if (rst_i)
    wr_valid_q <= 1'b0;
else
    wr_valid_q <= delay_wr_w;

always @ (posedge clk_i )
if (rst_i)
    wr_addr_q <= 15'b0;
else
    wr_addr_q <= stencil_wr_addr_i;

always @ (posedge clk_i )
if (rst_i)
    wr_mask_q <= 16'b0;
else
    wr_mask_q <= stencil_wr_mask_i;

always @ (posedge clk_i )
if (rst_i)
    wr_data_q <= 16'b0;
else
    wr_data_q <= stencil_wr_value_i;

//-----------------------------------------------------------------
// Write logic
//-----------------------------------------------------------------
wire [14:0] wr_addr_w = wr_valid_q ? wr_addr_q : stencil_wr_addr_i;
wire        wr_en_w   = direct_wr_w | wr_valid_q;
wire [15:0] wr_prev_data_w;

reg [15:0]  wr_data_r;

always @ *
begin
    wr_data_r = 16'b0;

    // Immediate write - no delay
    if (direct_wr_w)
        wr_data_r = stencil_wr_value_i;
    // Delay write - Read modify write
    else
        wr_data_r = (wr_prev_data_w & ~wr_mask_q) | (wr_data_q & wr_mask_q);
end

wire [14:0] rd_addr_w = stencil_rd_addr_i;
wire [15:0] rd_data_w;

//-----------------------------------------------------------------
// 64-KB Stencil RAM
//-----------------------------------------------------------------
stencil_cache_ram
u_ram
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)

    // Write / read port
    ,.addr0_i(wr_addr_w)
    ,.data0_i(wr_data_r)
    ,.wr0_i(wr_en_w)
    ,.data0_o(wr_prev_data_w)

    // Read port
    ,.addr1_i(rd_addr_w)
    ,.data1_o(rd_data_w)
);

//-----------------------------------------------------------------
// Write -> Read Bypass
//-----------------------------------------------------------------
reg         rd_valid_q;
reg [14:0]  rd_addr_q;

always @ (posedge clk_i )
if (rst_i)
    rd_valid_q <= 1'b0;
else
    rd_valid_q <= stencil_rd_req_i;

always @ (posedge clk_i )
if (rst_i)
    rd_addr_q <= 15'b0;
else
    rd_addr_q <= stencil_rd_addr_i;

reg [15:0]  rd_data_r;

always @ *
begin
    rd_data_r = 16'b0;

    // Read follows write + same address
    if (wr_valid_q && (wr_addr_q == rd_addr_q))
        rd_data_r = (rd_data_w & ~wr_mask_q) | (wr_data_q & wr_mask_q);
    // Normal
    else
        rd_data_r = rd_data_w;
end

assign stencil_rd_value_o = rd_data_r;

endmodule

//-----------------------------------------------------------------
// Dual Port RAM 64KB with write bypass features
//-----------------------------------------------------------------
module stencil_cache_ram
(
     input           clk_i
    ,input           rst_i

    ,input  [ 14:0]  addr0_i
    ,input  [ 15:0]  data0_i
    ,input           wr0_i
    ,output [ 15:0]  data0_o

    ,input  [ 14:0]  addr1_i
    ,output [ 15:0]  data1_o
);

/* verilator lint_off MULTIDRIVEN */
reg [15:0]   ram [32767:0] /*verilator public*/;
/* verilator lint_on MULTIDRIVEN */

reg [15:0] ram_read0_q;
reg [15:0] ram_read1_q;


// Synchronous write
always @ (posedge clk_i)
begin
    if (wr0_i)
        ram[addr0_i] <= data0_i;

    ram_read0_q <= ram[addr0_i];
end

always @ (posedge clk_i)
begin
    ram_read1_q <= ram[addr1_i];
end

reg data0_wr_q;
always @ (posedge clk_i )
if (rst_i)
    data0_wr_q <= 1'b0;
else
    data0_wr_q <= wr0_i;

reg wr_rd_byp_q;
always @ (posedge clk_i )
if (rst_i)
    wr_rd_byp_q <= 1'b0;
else
    wr_rd_byp_q <= wr0_i && (addr0_i == addr1_i);

reg [15:0] data0_bypass_q;

always @ (posedge clk_i)
    data0_bypass_q <= data0_i;

assign data0_o = data0_wr_q  ? data0_bypass_q : ram_read0_q;
assign data1_o = wr_rd_byp_q ? data0_bypass_q : ram_read1_q;


`ifdef verilator
function write; /* verilator public */
input  [31:0]   addr;
input  [15:0]   data;
begin
    ram[addr] = data;
end
endfunction
`endif

`ifdef verilator
function [15:0] read; /* verilator public */
input  [14:0]   addr;
begin
    read = ram[addr];
end
endfunction
`endif

endmodule
