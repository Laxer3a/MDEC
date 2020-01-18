/******************************************************************************

 ******************************************************************************/

module Fifo2
#(
	parameter DEPTH_WIDTH	= 5,
	parameter DATA_WIDTH	= 16
)
(
	input 		    i_clk,
	input 		    i_rst,
	input			i_ena,

	input 		    i_w_ena,
	input [DATA_WIDTH-1:0]  i_w_data,

	input 		    i_r_taken,
	output [DATA_WIDTH-1:0] o_r_data,
	
	output [DEPTH_WIDTH:0] o_level,

	output 		    o_w_full,
	output 		    o_r_valid
);
	localparam DW = (DATA_WIDTH  < 1) ? 1 : DATA_WIDTH;
	localparam AW = (DEPTH_WIDTH < 1) ? 1 : DEPTH_WIDTH;
	localparam AWM1 = AW-1;

	wire w_ena,r_ena,r_ena_g;

	reg [AW-1:0] r_addr;
	reg [AW-1:0] w_addr;
	reg [AW  :0] level;
   
	reg full_i,empty_i,valid;

	localparam [AW:0] c_Full		= (2**DEPTH_WIDTH);
	localparam [AW:0] c_Full_m1 	= (2**DEPTH_WIDTH)-1;
	localparam [AW:0] c_Empty_p1	= 1;
	localparam [AW:0] c_Empty		= 0;

	//synthesis translate_off
	initial begin
		if(DEPTH_WIDTH < 1) $display("%m : Warning: DEPTH_WIDTH must be > 0. Setting minimum value (1)");
		if(DATA_WIDTH  < 1) $display("%m : Warning: DATA_WIDTH must be > 0. Setting minimum value (1)");
	end
	//synthesis translate_on


	// ------------------------------------------
	//   FIFO RAM
	// ------------------------------------------
	reg  [AW-1:0]   				pRaddr;
	/* verilator lint_off WIDTH */
	wire [AW-1:0] nextAdr = r_addr + (i_ena & r_ena);
	wire [AW-1:0] nextWAdr= w_addr + (i_ena & w_ena);
	/* verilator lint_on WIDTH */
	
	reg signed [DATA_WIDTH-1:0] 	RAMStorage[(2**DEPTH_WIDTH)-1:0];

	always @ (posedge i_clk)
	begin
		if (i_ena & i_w_ena)
		begin
			RAMStorage[w_addr] = i_w_data;
		end
		
		if (i_rst) begin
		  w_addr  = 0;
		end else begin
			if (i_ena & i_w_ena) begin
				w_addr = nextWAdr;
			end
		end
		pRaddr = nextAdr;
	end
	
	assign o_r_data = RAMStorage[pRaddr];
	// ------------------------------------------
	assign w_ena   = i_w_ena & !(full_i | fullNow);
	assign r_ena   = (i_r_taken | !valid) & (!empty_i);
	assign r_ena_g = i_ena & r_ena;

	// Hack no present originally but else data is shifter of one bloody cycle...
	
	always @(posedge i_clk)
	begin
		if (i_rst) begin
		  valid = 0;
		end else begin
		  if (i_ena) begin
			if (!empty_i) begin
			  valid = 1;
			end else begin
			  if (i_r_taken) begin
				valid = 0;
			  end
			end
		  end
		end
	end
  
	wire fullNow = (level == c_Full_m1);
	always @(posedge i_clk)
	begin
		if (i_rst) begin
		  r_addr  = 0;
		  level   = 0;
		  full_i  = 0;
		  empty_i = 1;
		end else begin
		  if (i_ena) begin
			r_addr = nextAdr;

			case ({w_ena,r_ena})
			2'b10: begin 
				// => offset(0) := '1'; -- +1
				if (level == c_Full_m1 ) begin full_i  = 1; end
				if (level == c_Empty   ) begin empty_i = 0; end
				level = level + { {AW{1'b0}}, 1'b1};
			end
			2'b01: begin
				// => offset    := (others => '1'); -- -1
				if (level == c_Full    ) begin full_i  = 0; end
				if (level == c_Empty_p1) begin empty_i = 1; end
				level = level + { {AW{1'b1}}, 1'b1};
			end
			default: begin
				// Do nothing.
			end
			endcase
		  end
		end
	end

	reg Pvalid;
	always @(posedge i_clk)
	begin
	  Pvalid = valid;
	end
	
	assign o_w_full  = full_i | fullNow;
	assign o_r_valid = Pvalid;
	assign o_level   = level;
endmodule
