module GTEMicrocodeStart(
	input			IsNop,
	input	[5:0]	Instruction,
	output	[8:0]	StartAddress
);	
	reg [8:0] retAdr;
	always @(Instruction) begin
		case (Instruction)
		
		// Generated with C++ tool.
		`include "MicroCodeStart.inl"
		
		endcase
	end
	
	assign StartAddress = IsNop ? 9'd0 : retAdr;
endmodule
