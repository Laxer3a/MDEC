/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

// ----------------------------------------------------------------------------------------------
//   Microcode RAM/ROM
// ----------------------------------------------------------------------------------------------
`include "GTEDefine.hv"

module GTEMicroCode(
	input					i_clk,
	input                   isNewInstr,
	input [5:0]				Instruction,
	input [8:0]				i_PC,
	input					i_USEFAST,
	
	output gteWriteBack		o_writeBack,
	output gteComputeCtrl	o_ctrl,
	output o_lastInstr
);
	gteComputeCtrl	cmptCtrl;
	gteWriteBack	wb;

	assign o_ctrl		= cmptCtrl;
	assign o_writeBack	= wb;
	
	MCodeEntry currentEntry;
	MCodeEntry microCodeROM[321:0];
	
	/*
	always @(*) begin
		currentEntry = microCodeROM[i_PC];
	end
	*/
	// [Only 300 entries in BRAM]
	// [Only 206:0] entries in BRAM if FAST ONLY + counter seperate.
	always @(posedge i_clk) begin
		currentEntry <= microCodeROM[i_PC];
	end


	/*
	MCodeEntry microCodeROM[299:0];
	always @(posedge i_clk) begin
		currentEntry <= microCodeROM[i_PC];
	end
	*/
	
	initial begin
		`include "MicroCode.inl"
	end
	
	reg isLastEntrySLOW;
	reg isLastEntryFAST;
	always @(*)
	begin
		// Output BRAM value
		cmptCtrl         = currentEntry.ctrlPath;
		wb               = currentEntry.wb;
		isLastEntrySLOW  = currentEntry.lastInstrSLOW;
		isLastEntryFAST  = currentEntry.lastInstrFAST;
	end
	
	assign o_lastInstr = (!i_USEFAST && isLastEntrySLOW) | (i_USEFAST & isLastEntryFAST);
endmodule
