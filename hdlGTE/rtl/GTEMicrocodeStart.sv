module GTEMicrocodeStart(
	input			IsNop,
	input			isBuggyMVMVA,
	input	[5:0]	Instruction,
	output	[8:0]	StartAddress
);	
	reg [8:0] retAdr;
	
	// isBuggyMVMVA = FALSE : 2 -> Remap 3, else as is.
	// is
	/*	To simulate the buggy MVMVA instruction, we actually use a different instruction opcode.
		Then, we have a conflict between a "NOP" opcode and "BUGGY MVMVA" opcode slot.
		What we do, is re-route one "NOP" opcode to another opcode and free a slot to avoid conflict.
		
		For standard instruction, if Instruction is  2, it becomes 3 else normal.
		For Buggy MVMVA,             Instruction is 18, it becomes 2.
	 */
	wire       remapp3  = (!isBuggyMVMVA) && (Instruction == 6'd2);
	
	// If invalid MVMVA : 18 becomes 2.
	// If             2 :  2 becomes 3 else as is.
	wire [5:0] remapped = { Instruction[5], (Instruction[4] & (!isBuggyMVMVA)), Instruction[3:1] , Instruction[0] | remapp3 };
	always @(remapped) begin
		case (remapped)
		
		// Generated with C++ tool.
		`include "MicroCodeStart.inl"
		
		endcase
	end
	
	assign StartAddress = retAdr;
endmodule
