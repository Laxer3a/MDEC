// ----------------------------------------------------------------------------------------------
//   Microcode RAM/ROM
// ----------------------------------------------------------------------------------------------
`include "GTEDefine.hv"

module GTEMicroCode(
	input					i_clk,
	input                   isNewInstr,
	input [5:0]				Instruction,
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
	
//	wire [8:0] PCP1 = i_PC + 9'd1;

	MCodeEntry currentEntry;
	always @(* ) begin
		// DISABLED : ROM
		// if (we) begin
		// 	microCodeROM[addr_in] <= data_in;
		// end
		
		/*posedge i_clk*/
		// currentEntry <= microCodeROM[PCP1];
		
		// For now stupid ROM.
		currentEntry = microCodeROM[i_PC];
	end
	
	// NOP INSTRUCTION
	/*
	gteComputeCtrl NOP_Ctrl = '{	 sel1:'{mat:2'b0,selLeft:3'b0,selRight:4'b0,vcompo:2'b0}
		                          , sel2:'{mat:2'b0,selLeft:3'b0,selRight:4'b0,vcompo:2'b0}
										  , sel3:'{mat:2'b0,selLeft:3'b0,selRight:4'b0,vcompo:2'b0}
										  , addSel:'{useSF:1'b0,id:2'd0,sel:4'd0}
										  , wrTMP1:1'b0
										  , wrTMP2:1'b0
										  , wrTMP3:1'b0
										  , storeFull:1'b0
                                , useStoreFull:1'b0
										  , wrDivRes:1'b0
										  , useSFWrite32:1'b0 
										  , assignIRtoTMP:1'b0
										  , negSel:3'b000
										  , selOpInstr:2'd0
										  , selCol0:1'b0
										  , check44Global:1'b0 , check44Local:1'b0 , check32Global:1'b0 , checkOTZ:1'b0 , checkDIV:1'b0 , checkXY:1'b0 , checkIR0:1'b0 
										  , checkIRn:1'b0 , checkColor:1'b0 , isIRnCheckUseLM:1'b0 , lmFalseForIR3Saturation:1'b0 , maskID:2'd0 , X0_or_Y1:1'b0
										 };
	gteWriteBack   NOP_Wr   = '{ wrIR:4'b0000, wrMAC:4'b0000, wrOTZ:1'b0, pushX:1'b0, pushY:1'b0, pushZ:1'b0, pushR:1'b0, pushG:1'b0,pushB:1'b0 };
	wire isNop = (i_PC == 9'd0);
	*/
	
	// System to have ZERO latency for now... all LOGIC.
	
	reg isLastEntry;
	always @(*)
	begin
		// Output BRAM value
		cmptCtrl     = currentEntry.ctrlPath;
		wb           = currentEntry.wb;
		isLastEntry  = currentEntry.lastInstr;
	end
	
	assign o_lastInstr = isLastEntry;
endmodule
