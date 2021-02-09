
module gpu_mem_vramcpu_fifo_2w1r
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter WIDTH            = 16
    ,parameter DEPTH            = 8
    ,parameter ADDR_W           = 3
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Inputs
     input                   clk_i
    ,input                   rst_i
    ,input                   push0_i
    ,input  [WIDTH-1:0]      data_in0_i
    ,input                   push1_i
    ,input  [WIDTH-1:0]      data_in1_i
    ,input                   final_i
    ,input                   pop_i

    // Outputs
    ,output                  accept0_o
    ,output                  accept1_o
    ,output                  valid_o
    ,output [(WIDTH*2)-1:0]  data_out_o
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

// Detect when the end of the stream occurs and there is an odd number of entries
wire odd_w = final_i && accept0_o && 
             ((wr_ptr_q[0]  & (push0_i && push1_i)) ||
             (~wr_ptr_q[0] & (push0_i && ~push1_i)));

//-----------------------------------------------------------------
// Count
//-----------------------------------------------------------------
reg [COUNT_W-1:0]  count_r;

always @ *
begin
    count_r = count_q;

    if ((push0_i && accept0_o) && (push1_i && accept1_o))
        count_r = count_r + 2;
    else if ((push0_i && accept0_o) || (push1_i && accept1_o))
        count_r = count_r + 1;

    if (odd_w)
        count_r = count_r + 1;

    if (valid_o && pop_i)
        count_r = count_r - 2;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
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
    if ((push0_i && accept0_o) && (push1_i && accept1_o))
    begin
        ram_q[wr_plus0_w] <= data_in0_i;
        ram_q[wr_plus1_w] <= data_in1_i;
    end
    else if (push0_i && accept0_o)
        ram_q[wr_plus0_w] <= data_in0_i;
    else if (push1_i && accept1_o)
        ram_q[wr_plus0_w] <= data_in1_i;
end

//-----------------------------------------------------------------
// Write pointer
//-----------------------------------------------------------------
reg [ADDR_W-1:0] wr_ptr_r;

always @ *
begin
    wr_ptr_r = wr_ptr_q;

    if ((push0_i && accept0_o) && (push1_i && accept1_o))
        wr_ptr_r = wr_ptr_r + 2;
    else if ((push0_i && accept0_o) || (push1_i && accept1_o))
        wr_ptr_r = wr_ptr_r + 1;

    if (odd_w)
        wr_ptr_r = wr_ptr_r + 1;
end

always @ (posedge clk_i or posedge rst_i)
if (rst_i)
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
else if (pop_i & valid_o)
    rd_ptr_q <= rd_plus2_w;

//-----------------------------------------------------------------
// Combinatorial
//-----------------------------------------------------------------
/* verilator lint_off WIDTH */
assign valid_o       = (count_q >= 2);
assign accept0_o     = (count_q <= (DEPTH - 2));
assign accept1_o     = (count_q <= (DEPTH - 2));
/* verilator lint_on WIDTH */

assign data_out_o    = {ram_q[rd_plus1_w], ram_q[rd_plus0_w]};


endmodule
