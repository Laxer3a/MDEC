// ----------------------------------------------------------------------------------------------
//   Microcode RAM/ROM
// ----------------------------------------------------------------------------------------------
`include "GTEDefine.hv"

module GTEMicroCode(
	input					i_clk,
	input [8:0]				i_PC,
	
	output gteWriteBack		o_writeBack,
	output gteComputeCtrl	o_ctrl,
	output o_lastInstr
);
	MCodeEntry microCodeROM[511:0];
	initial begin
//		integer i;
//		for (i=0; i < 512; i = i+1) begin
//		microCodeROM[i].ctrlPath = '{ sel1:'{mat:2'd1,selLeft:3'd0/*L11*/,selRight:4'd0,vcompo:2'd0/*VX0*/} , sel2:'{mat:2'd1,selLeft:3'd0/*L12*/,selRight:4'd0,vcompo:2'd0/*VY0*/} , sel3:'{mat:2'd1,selLeft:3'd0/*L13*/,selRight:4'd0,vcompo:2'd0/*VZ0*/} ,  wrTMP1:1'b0 , wrTMP2:1'b0 , wrTMP3:1'b0 };
//		microCodeROM[i].wb       = '{wrVX:3'b000, wrVY:3'b000, wrVZ:3'b000, wrIR:4'b0000, wrMAC:4'b0000, wrOTZ:1'b0, pushX:1'b0, pushY:1'b0, pushZ:1'b0, pushR:1'b0, pushG:1'b0, pushB:1'b0  };
//		end
		`include "MicroCode.inl"
	end
	
	gteComputeCtrl	cmptCtrl;
	gteWriteBack	wb;
	
	assign o_ctrl		= cmptCtrl;
	assign o_writeBack	= wb;
	
	wire [8:0] PCP1 = i_PC + 9'd1;
		
	MCodeEntry currentEntry;
	always @(posedge i_clk) begin
		// DISABLED : ROM
		// if (we) begin
		// 	microCodeROM[addr_in] <= data_in;
		// end
		currentEntry <= microCodeROM[PCP1];
	end
	
	// NOP INSTRUCTION
	gteComputeCtrl NOP_Ctrl = '{	 sel1:'{mat:2'b0,selLeft:3'b0,selRight:4'b0,vcompo:2'b0}
		                          , sel2:'{mat:2'b0,selLeft:3'b0,selRight:4'b0,vcompo:2'b0}
										  , sel3:'{mat:2'b0,selLeft:3'b0,selRight:4'b0,vcompo:2'b0}
										  , addSel:'{useSF:1'b0,id:2'd0,sel:4'd0}
										  , wrTMP1:1'b0
										  , wrTMP2:1'b0
										  , wrTMP3:1'b0
										  , wrDivRes:1'b0
										  , useSFWrite32:1'b0 
										  , assignIRtoTMP:1'b0
										  , negSel:3'b000
										  , selOpInstr:2'd0
										  , selCol0:1'b0
										 };
										  
	gteWriteBack   NOP_Wr   = '{ wrIR:4'b0000, wrMAC:4'b0000, wrOTZ:1'b0, pushX:1'b0, pushY:1'b0, pushZ:1'b0, pushR:1'b0, pushG:1'b0,pushB:1'b0 };
	// System to have ZERO latency even when using BRAM for microcode.
	always @(*)
	begin
		if (i_PC == 9'd0) begin // || startInstrPC
			// Output current PC ROM 0 Cycle latency
			cmptCtrl = NOP_Ctrl;
			wb       = NOP_Wr;
		end else begin
			// Output BRAM value
			cmptCtrl = currentEntry.ctrlPath;
			wb       = currentEntry.wb;
		end
		// Request PC+1 BRAM
	end
	
endmodule
