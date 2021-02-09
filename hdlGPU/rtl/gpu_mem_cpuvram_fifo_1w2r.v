
module gpu_mem_cpuvram_fifo_1w2r
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter WIDTH            = 16
    ,parameter DEPTH            = 4
    ,parameter ADDR_W           = 2
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input                  clk_i
    ,input                  rst_i
    ,input                  push_i
    ,input  [(WIDTH*2)-1:0] data_in_i
    ,input                  pop0_i
    ,input                  pop1_i
    ,input                  flush_i

    // Outputs
    ,output                 accept_o
    ,output                 valid0_o
    ,output [WIDTH-1:0]     data_out0_o
    ,output                 valid1_o
    ,output [WIDTH-1:0]     data_out1_o
);

//-----------------------------------------------------------------
// Local Params
//-----------------------------------------------------------------
localparam COUNT_W  = ADDR_W + 1;

//-----------------------------------------------------------------
// Registers
//-----------------------------------------------------------------
reg [WIDTH-1:0]    ram_q[DEPTH-1:0];
reg [ADDR_W-1:0]   rd_ptr_q;
reg [ADDR_W-1:0]   wr_ptr_q;
reg [COUNT_W-1:0]  count_q;

//-----------------------------------------------------------------
// Count
//-----------------------------------------------------------------
reg [COUNT_W-1:0]  count_r;

always @ *
begin
    count_r = count_q;

    if (push_i && accept_o)
        count_r = count_r + 2;

    if ((valid1_o && pop1_i) && (valid0_o && pop0_i))
        count_r = count_r - 2;
    else if (valid0_o && pop0_i)
        count_r = count_r - 1;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    count_q <= {(COUNT_W) {1'b0}};
else if (flush_i)
    count_q <= {(COUNT_W) {1'b0}};
else
    count_q <= count_r;

//-----------------------------------------------------------------
// Storage
//-----------------------------------------------------------------
wire [ADDR_W-1:0] wr_plus0_w = wr_ptr_q + 0;
wire [ADDR_W-1:0] wr_plus1_w = wr_ptr_q + 1;

always @ (posedge clk_i)
begin
    if (push_i && accept_o)
    begin
        ram_q[wr_plus0_w] <= data_in_i[15:0];
        ram_q[wr_plus1_w] <= data_in_i[31:16];
    end
end

//-----------------------------------------------------------------
// Write pointer
//-----------------------------------------------------------------
reg [ADDR_W-1:0] wr_ptr_r;

always @ *
begin
    wr_ptr_r = wr_ptr_q;

    if (push_i && accept_o)
        wr_ptr_r = wr_ptr_r + 2;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    wr_ptr_q <= {(ADDR_W) {1'b0}};
else if (flush_i)
    wr_ptr_q <= {(ADDR_W) {1'b0}};
else
    wr_ptr_q <= wr_ptr_r;

//-----------------------------------------------------------------
// Read pointer
//-----------------------------------------------------------------
wire [ADDR_W-1:0] rd_plus0_w = rd_ptr_q + 0;
wire [ADDR_W-1:0] rd_plus1_w = rd_ptr_q + 1;
wire [ADDR_W-1:0] rd_plus2_w = rd_ptr_q + 2;

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
    rd_ptr_q <= {(ADDR_W) {1'b0}};
else if (flush_i)
    rd_ptr_q <= {(ADDR_W) {1'b0}};
else if ((pop1_i & valid1_o) && (pop0_i & valid0_o))
    rd_ptr_q <= rd_plus2_w;
else if (pop0_i & valid0_o)
    rd_ptr_q <= rd_plus1_w;

//-----------------------------------------------------------------
// Combinatorial
//-----------------------------------------------------------------
/* verilator lint_off WIDTH */
assign valid0_o      = (count_q >= 1);
assign valid1_o      = (count_q >= 2);
assign accept_o      = (count_q <= (DEPTH - 2));
/* verilator lint_on WIDTH */

assign data_out0_o   = ram_q[rd_plus0_w];
assign data_out1_o   = ram_q[rd_plus1_w];


endmodule
