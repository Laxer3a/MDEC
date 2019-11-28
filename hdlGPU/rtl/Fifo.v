/******************************************************************************
 This Source Code Form is subject to the terms of the
 Open Hardware Description License, v. 1.0. If a copy
 of the OHDL was not distributed with this file, You
 can obtain one at http://juliusbaxter.net/ohdl/ohdl.txt

 Description: Store buffer
 Currently a simple single clock FIFO, but with the ambition to
 have combining and reordering capabilities in the future.

 Copyright (C) 2013 Stefan Kristiansson <stefan.kristiansson@saunalahti.fi>

 ******************************************************************************/

module Fifo
  #(
    parameter DEPTH_WIDTH	= 5,
    parameter DATA_WIDTH	= 16
    )
   (
    input 		    clk,
    input 		    rst,

    input [DATA_WIDTH-1:0]  wr_data_i,
    input 		    wr_en_i,

    output [DATA_WIDTH-1:0] rd_data_o,
    input 		    rd_en_i,

    output 		    full_o,
    output 		    empty_o
    );

   localparam DW = (DATA_WIDTH  < 1) ? 1 : DATA_WIDTH;
   localparam AW = (DEPTH_WIDTH < 1) ? 1 : DEPTH_WIDTH;

   //synthesis translate_off
   initial begin
      if(DEPTH_WIDTH < 1) $display("%m : Warning: DEPTH_WIDTH must be > 0. Setting minimum value (1)");
      if(DATA_WIDTH < 1) $display("%m : Warning: DATA_WIDTH must be > 0. Setting minimum value (1)");
   end
   //synthesis translate_on

   reg [AW:0] write_pointer;
   reg [AW:0] read_pointer;

   wire 	       empty_int		= (write_pointer[AW]     == read_pointer[AW]    );
   wire 	       full_or_empty	= (write_pointer[AW-1:0] == read_pointer[AW-1:0]);
   
   assign full_o  = full_or_empty & !empty_int;
   assign empty_o = full_or_empty & empty_int;
   
   always @(posedge clk) begin
      if (wr_en_i)
	write_pointer <= write_pointer + 1'd1;

      if (rd_en_i)
	read_pointer <= read_pointer + 1'd1;

      if (rst) begin
	 read_pointer  <= 0;
	 write_pointer <= 0;
      end
   end

	// ------------------------------------------
	//   FIFO RAM
	// ------------------------------------------
	wire [AW-1:0]					raddr = read_pointer[AW-1:0];
	reg  [AW-1:0]   				pRaddr;
	reg signed [DATA_WIDTH-1:0] 	RAMStorage[(2**DEPTH_WIDTH)-1:0];
	reg  [DATA_WIDTH-1:0]			outputCache;

	always @ (posedge clk)
	begin
		if (wr_en_i)
		begin
			RAMStorage[write_pointer[AW-1:0]] <= wr_data_i;
		end
		pRaddr <= raddr;
	end
	
	reg pRd_en_i;
	always @ (posedge clk)
	begin
		pRd_en_i <= rd_en_i;
	end
	
	wire [DATA_WIDTH-1:0] straight_rd_data_o = RAMStorage[pRaddr];
	
	assign rd_data_o = pRd_en_i ? straight_rd_data_o : outputCache;
	always @(posedge clk)
	begin
		if (pRd_en_i) begin
			outputCache <= straight_rd_data_o;
		end
	end
	// ------------------------------------------
endmodule
