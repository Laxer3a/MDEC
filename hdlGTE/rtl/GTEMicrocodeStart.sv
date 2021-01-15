/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module GTEMicrocodeStart(
	input			isBuggyMVMVA,
	input	[5:0]	Instruction,
	output	[7:0]	StartAddress
	,output  [5:0]   officialCycleCount
);	
	reg [7:0] retAdr;
	reg [5:0] retCount;
	
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
		
		case (remapped)
		// Generated with C++ tool.
		`include "MicroCodeTiming.inl"
		endcase
	end
	
	assign StartAddress			= retAdr;
	assign officialCycleCount	= retCount;
endmodule
