module FileReg (
	input         clk,
	input         read,
	input   [4:0] readAdr,
	output [31:0] outData,
	input         write,
	input   [4:0] writeAdr,
	input  [31:0] inData
);
// Declare the RAM variable
reg [31:0] ram[31:0];
reg [31:0] routData;

always @ (posedge clk)
begin
	if (write) 
	begin
		ram[writeAdr] <= inData;
	end
	routData <= ram[readAdr];
end
assign outData = routData;

endmodule
