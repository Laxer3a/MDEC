//-----------------------------------------------------
// Design Name : ram_sp_sr_sw
// File Name   : ram_sp_sr_sw.v
// Function    : Synchronous read write RAM 
// Coder       : Deepak Kumar Tala
//-----------------------------------------------------
module ram_sp_sr_sw (
	input clk,
	input [13:0] addressIn,
	input [13:0] addressOut,	
	input  dataIn,
   output dataOut,
	input  cs,
	input  we
); 

//--------------Internal variables---------------- 
reg data_outR;
reg mem [0:16383];

//--------------Code Starts Here------------------ 
assign dataOut = data_outR; 

// Memory Write Block 
// Write Operation : When we = 1, cs = 1
always @ (posedge clk)
begin : MEM_WRITE
   if ( we & cs) begin
       mem[addressIn] <= dataIn;
   end
end

// Memory Read Block 
// Read Operation : When we = 0, oe = 1, cs = 1
always @ (posedge clk)
begin : MEM_READ
  if (!we & cs) begin
    data_outR <= mem[addressOut];
  end
end

endmodule // End of Module ram_sp_sr_sw
