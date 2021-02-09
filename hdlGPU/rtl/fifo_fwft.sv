module fifo_fwft
  #(parameter DATA_WIDTH = 0,
    parameter DEPTH_WIDTH = 0)
   (
    input                   clk,
    input                   rst,
    input [DATA_WIDTH-1:0]  din,
    input                   wr_en,
    output                  full,
    output [DATA_WIDTH-1:0] dout,
    input                   rd_en,
    output                  empty);

// wire [DATA_WIDTH-1:0]    fifo_dout;
   wire                     fifo_empty;
   wire                     fifo_rd_en;

   // orig_fifo is just a normal (non-FWFT) synchronous or asynchronous FIFO
   SSCfifo
     #(.DEPTH_WIDTH (DEPTH_WIDTH),
       .DATA_WIDTH  (DATA_WIDTH))
   fifo0
     (
      .clk       (clk),
      .rst       (rst),
      .rd_en_i   (fifo_rd_en),
      .rd_data_o (dout),
      .empty_o   (fifo_empty),
      .wr_en_i   (wr_en),
      .wr_data_i (din),
      .full_o    (full));

	reg dout_valid;
	
   assign fifo_rd_en = !fifo_empty && (!dout_valid || rd_en);
   assign empty = !dout_valid;

   always @(posedge clk)
   begin
      if (rst)
         dout_valid <= 0;
      else
         begin
            if (fifo_rd_en)
               dout_valid <= 1;
            else if (rd_en)
               dout_valid <= 0;
         end 
	end
	/*
   fifo_fwft_adapter
     #(.DATA_WIDTH (DATA_WIDTH))
   fwft_adapter
     (.clk          (clk),
      .rst          (rst),
      .rd_en_i      (rd_en),
      .fifo_empty_i (fifo_empty),
      .fifo_rd_en_o (fifo_rd_en),
      .fifo_dout_i  (fifo_dout),
      .dout_o       (dout),
      .empty_o      (empty));
	*/
	
endmodule
