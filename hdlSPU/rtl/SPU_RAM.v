/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
	Fake ram with :
	- Last memory data kept available for further re-read.
	- Latency of 4 cycles.
 **************************************************************************************************************************************/
module SPU_RAM
(
	input			i_clk,
	input 	[15:0]	i_data,
	input 	[17:0]	i_wordAddr,
	input			i_re,
	input			i_we,
	input	[ 1:0]	i_byteSelect,
	
	output	[15:0]	o_q
);

	// Declare the RAM variable
	reg [7:0] ramL[262143:0];
	reg [7:0] ramM[262143:0];
	
	// Variable to hold the registered read address
	reg [17:0] addr_reg;
	reg [1:0]  readByteSelect_reg;
	
	always @ (posedge i_clk)
	begin
	// Write
		if (i_we)
		begin
			if (i_byteSelect[0]) ramL[i_wordAddr] = i_data[ 7:0];
			if (i_byteSelect[1]) ramM[i_wordAddr] = i_data[15:8];
		end
		
		addr_reg			= i_wordAddr;
		readByteSelect_reg	= i_byteSelect & {i_re,i_re};
	end
	
	// Continuous assignment implies read returns NEW data.
	// This is the natural behavior of the TriMatrix memory
	// blocks in Single Port mode.  
	wire [7:0] low = readByteSelect_reg[0] ? ramL[addr_reg] : cachL;
	wire [7:0] hig = readByteSelect_reg[1] ? ramM[addr_reg] : cachM;
	
	// Keep last data forever...
	reg [7:0] cachL, cachM;
	always @ (posedge i_clk)
	begin
		if (readByteSelect_reg[0]) begin cachL = low; end
		if (readByteSelect_reg[1]) begin cachM = hig; end
	end
	
	assign o_q = { hig , low };
endmodule
