/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/*
1F801100h+N*10h - Timer 0..2 Current Counter Value (R/W)
	0-15  Current Counter value (incrementing)
	16-31 Garbage

	- This register is automatically incrementing. 
	- It is write-able (allowing to set it to any value). 
	- It gets forcefully reset to 0000h on any write to the Counter Mode register.
	- It gets            reset to 0000h on counter overflow (either when exceeding FFFFh, or when exceeding the selected sys_target value).
		Thus, Range is [0..value]
*/
/*
1F801104h+N*10h - Timer 0..2 Counter Mode (R/W)

OK0     Synchronization Enable (0=Free Run, 1=Synchronize via Bit1-2)
OK1-2   Synchronization Mode   (0-3, see lists below)
  
		TYPE 1 COUNTER (Timer 0 / 1)
         Synchronization Modes for Counter 0 (HBlank) / 1 (VBLank) :
           0 = Pause counter during *Blank(s)
           1 = Reset counter to 0000h at *Blank(s)
           2 = Reset counter to 0000h at *Blank(s) and pause outside of *Blank
           3 = Pause until *Blank occurs once, then switch to Free Run
		TYPE 2 COUNTER (Timer 2)
         Synchronization Modes for Counter 2:
           0 or 3 = Stop counter at current value (forever)
           1 or 2 = Free Run (same as when Synchronization Disabled)
		   
OK3     Reset counter to 0000h  (0=After Counter=FFFFh, 1=After Counter=Target)
OK4     IRQ when Counter=Target (0=Disable, 1=Enable)
OK5     IRQ when Counter=FFFFh  (0=Disable, 1=Enable)
OK6     IRQ Once/Repeat Mode    (0=One-shot, 1=Repeatedly)

OK8-9   Clock Source (0-3, see list below)
         Timer 0:  0 or 2 = System Clock,  1 or 3 = Dotclock         (Sync HBlank)
         Timer 1:  0 or 2 = System Clock,  1 or 3 = Hblank           (Sync VBlank)
         Timer 2:  0 or 1 = System Clock,  2 or 3 = System Clock/8   (No Sync)
OK11    Reached Target Value    (0=No, 1=Yes) (Reset after Reading)        (R)
OK12    Reached FFFFh Value     (0=No, 1=Yes) (Reset after Reading)        (R)
  13-15 Unknown (seems to be always zero)
  16-31 Garbage (next opcode)

In one-shot mode, the IRQ is pulsed/toggled only once 
(one-shot mode doesn't stop the counter, it just suppresses any further IRQs 
until a new write to the Mode register occurs; 
if both IRQ conditions are enabled in Bit4-5, then one-shot mode triggers only one of those conditions; 
whichever occurs first).

  7     IRQ Pulse/Toggle Mode   (0=Short Bit10=0 Pulse, 1=Toggle Bit10 on/off)
  10    Interrupt Request       (0=Yes, 1=No) (Set after Writing)    (W=1) (R)
			TODO : (Set after Writing)  + Reset default value
			
Normally, Pulse mode should be used (Bit10 is permanently set, except for a few clock cycles when an IRQ occurs). 
In Toggle mode, Bit10 is set after writing to the Mode register, 
and becomes inverted on each IRQ (in one-shot mode, it remains zero after the IRQ) 
(in repeat mode it inverts Bit10 on each IRQ, so IRQ4/5/6 are triggered only each 2nd time, 
ie. when Bit10 changes from 1 to 0).

*/

// Timer [0,1,2]
module TimerUnit
#(	parameter TYPE = 1
)
(
	input			sysClk,
	input			i_nRst,
	
	input			pixClk,
	input			i_secondSrc,	// Div8 (Timer 2), HBlank (Timer 1)
	input			i_xBL,			// VBL, HBL, ...
	
	input			i_sys_CSTimer,
	input			i_sys_write,
	input	[1:0]	i_sys_regID,
	input	[15:0]	i_sys_valueW,
	output	[15:0]	o_sys_valueR,
	output			i_xxx_irqTimer
);
	reg [15:0]		xxx_counter;
	reg [15:0]		sys_target;
	
	// Status Register
	reg				sys_freeRun;		// Bit 0
	reg  [1:0]		sys_mode;			// Bit 1-2
	reg				sys_resetType;		// Bit 3
	
	reg 			IrqWhenTarget;
	reg				IrqWhenFull;
	reg				IrqRepeat;
	reg				IrqFlip;
	reg  [1:0]		srcClockSel;
	reg				reachedTarget;
	reg				reachedFull;


	// ======================================================
	// Transition from 0->1 for signal xBL
	// Transition from 0->1 for signal i_secondSrc
	reg  transitionXBL,
	     transitionSecondSrc;									// NOT USED BY TIMER 0
	always @(posedge sysClk) begin
		transitionXBL       = i_xBL;
		transitionSecondSrc = i_secondSrc;						// NOT USED BY TIMER 0
	end
	// ------------------------------------------------------
	wire xBLTrans       = i_xBL       & !transitionXBL;
	wire secondClkTrans = i_secondSrc & !transitionSecondSrc;	// NOT USED BY TIMER 0
	// ======================================================
	
	// Check Counter conditions for reset to 0.
	wire isFull 	 = (xxx_counter == 16'hFFFF);
	wire isTarget	 = (xxx_counter == sys_target);
	
	reg incr;
	reg reset;
	
	// SPECIAL CONDITION : In sys_mode 3 for type 1 -> Switch to freeRun to xBL transition to 1.
	wire setFreeRun  = (TYPE != 2)  && (sys_mode == 2'd3) && xBLTrans;
	
	// Depending on clock type, source clock selection is different.
	wire useExtClock = ((TYPE != 2) && (srcClockSel[0]))  // 0 or 2 = System Clock,  1 or 3 = Hblank           (Sync VBlank)
	                || ((TYPE == 2) && (srcClockSel[1])); // 0 or 1 = System Clock,  2 or 3 = System Clock/8   (No Sync)

	// Increment select system clock or transition on second input.
//if TIMER0
//	wire freeRunIncr = 1'b1;	// We change the clock only.
//else
	wire freeRunIncr = (!useExtClock) | (useExtClock & secondClkTrans);	// 	TODO
//end
	
	// Reset logic for Register bit [3]
	wire resetBase	 = (sys_resetType & isTarget) | (!sys_resetType & isFull);
	
	always @(*)
	begin
		if (sys_freeRun) begin
			incr	= freeRunIncr;
			reset	= resetBase;
		end else begin
			if (TYPE != 2) begin
				case (sys_mode)
				2'd0: begin
					incr	= freeRunIncr & (!i_xBL); // run when xBlank == 0, pause when xBlank = 1.
					reset	= resetBase;
				end
				2'd1: begin
					incr	= freeRunIncr; 			// run always
					reset	= resetBase | xBLTrans;
				end
				2'd2: begin
					incr	= freeRunIncr & i_xBL; 	// run when xBlank == 1.
					reset	= resetBase | xBLTrans;
				end
				2'd3: begin
					incr	= setFreeRun;			// Pause until xBlank == 1. Allow to increment right away.
					reset	= resetBase;
				end
				endcase
			end
			if (TYPE == 2) begin
				reset	= resetBase;
				if (sys_mode[0]^sys_mode[1]) begin	
					// 01 / 10 (1,2)
					incr	= 1'b0;
				end else begin
					// 00 / 11 (0,3)
					incr	= freeRunIncr;
				end
			end
		end
	end
	
	// ------------------------------------------------------------------------
	wire basePulse	= ((IrqWhenTarget & isTarget) | (IrqWhenFull & isFull));
	reg fired;
	// If IRQ condition met -> Fire.
	// If already fired, do authorize repeat ?
	// If not     fired, always true.
	wire setIRQ		= ((!fired & !IrqRepeat) | IrqRepeat) & basePulse;
	reg  prevIRQ;
	always @(posedge sysClk)
	begin
		prevIRQ = setIRQ;
	end
	// ------------------------------------------------------------------------
	wire transitionIRQ = (!prevIRQ) && setIRQ;
	// ------------------------------------------------------------------------
	reg  outIRQ;
	
	always @(posedge sysClk)
	begin
		if (i_nRst == 1'b0) begin
			outIRQ = 1'b1;
		end else begin
			if (i_sys_CSTimer & i_sys_write & (i_sys_regID==2'd1)) begin
				outIRQ = 1'b1; // Set to one.
			end
		
			if (transitionIRQ) begin
				// Flag occurs
				if (IrqFlip) begin
					outIRQ = !outIRQ;
				end else begin
					outIRQ = 1'b0; // Set to zero, IRQ active
				end
			end else begin
				if (!IrqFlip) begin
					outIRQ = 1'b1; // Set to one again, IRQ inactive.
				end
			end
		end
	end

	// Trick : ourIRQ register is modified at the NEXT CYCLE
	// But IRQ Signals and readable register state are modified to be readable within the same cycle as things occurs
	// So :
	// If Flip  Mode : Flag for transition set, return the already inversed state, else current state.
	// If Pulse Mode : If no transition occurs -> return current state, else force to 0.
	//
	// Without this logic => formula is simply : exportIRQ = outIRQ
	// [THOSE ARE ONLY FOR VALUES VISIBLE TO USER, NOTHING INTERNAL TO THE TIMER ITSELF]
//	wire    exportIRQ = IrqFlip       ? (transitionIRQ ? (!outIRQ) : outIRQ) : (transitionIRQ ? 1'b0 : outIRQ);
	// Equivalent : if transition, return next value, else current value.
	wire    exportIRQ = transitionIRQ ? (IrqFlip ? (!outIRQ) :1'b0 ) : outIRQ; // Equivalent.
	assign	i_xxx_irqTimer = !exportIRQ;
	
	always @(posedge sysClk)
	begin
		if (i_nRst == 1'b0) begin
			xxx_counter		= 16'd0;
		end else begin
			// Perform xxx_counter reset to ZERO when next valid increment arrive.
			if (reset) begin
				xxx_counter = 16'd0;
			end else begin
				xxx_counter = xxx_counter + { 15'd0, incr };
			end
		end
	end
	
	// ----------------------------------------------------------
	//   [CPU WRIDE SIDE]
	// ----------------------------------------------------------
	always @(posedge sysClk)
	begin
		if (i_nRst == 1'b0) begin
			sys_target			= 16'd0;
			sys_freeRun			= 1'b1;
			sys_mode			= 2'd0;
			sys_resetType		= 1'b0;
			IrqWhenTarget		= 1'b0;
			IrqWhenFull			= 1'b0;
			IrqRepeat			= 1'b0;
			IrqFlip				= 1'b0;
			srcClockSel			= 2'd0;
			reachedTarget		= 1'b0;
			reachedFull			= 1'b0;
			fired				= 1'b0;
		end else begin
			// reached flag can be overridden by CPU READ or WRITE.
			if (isTarget) begin
				reachedTarget	= 1'b1;
			end
			if (isFull) begin
				reachedFull		= 1'b1;
			end
		
			if (i_sys_CSTimer) begin
				if (i_sys_write) begin
					case (i_sys_regID)
					default:
					begin
							// Do nothing...
					end
					2'd0:	// Value 0
					begin
						xxx_counter			= i_sys_valueW;
					end
					2'd1:	// Setup 0
					begin
						sys_freeRun			= !i_sys_valueW[0];
						sys_mode			= i_sys_valueW[2:1];
						sys_resetType		= i_sys_valueW[3];
						IrqWhenTarget		= i_sys_valueW[4];
						IrqWhenFull			= i_sys_valueW[5];
						IrqRepeat			= i_sys_valueW[6];
						IrqFlip				= i_sys_valueW[7];
						srcClockSel			= i_sys_valueW[9:8];
// Validated by test.
//						reachedTarget		= 1'b0;
//						reachedFull			= 1'b0;
						fired				= 1'b0;
					end
					2'd2:	// Target
					begin
						sys_target	= i_sys_valueW;
					end
					endcase
				end else begin
					if (i_sys_regID == 2'd1) begin
						reachedTarget = 1'b0;
						reachedFull   = 1'b0;
					end
				end
			end
			
			if (setFreeRun) begin
				sys_freeRun = 1'b1;
			end
			
			if (basePulse) begin
				fired = 1'b1;
			end
		end
	end

	// ----------------------------------------------------------
	//   [CPU READ SIDE]
	// ----------------------------------------------------------
	wire [15:0] modeR = { 3'b000,reachedFull,reachedTarget,exportIRQ,srcClockSel,IrqFlip,IrqRepeat,IrqWhenFull,IrqWhenTarget,sys_resetType, sys_mode,sys_freeRun };
	assign o_sys_valueR = (i_sys_regID == 2'd1) ? modeR : ((i_sys_regID == 2'd2) ? sys_target : xxx_counter);
	// ----------------------------------------------------------
endmodule

module TimerModule (
	input			clk,
	input			i_nRst,
	
	input			isPAL,				// May not be used depending on implementation.
	input			pixClk,
	
	input			selTimerReg,
	input	[3:0]	adrInterruptReg2, // Bit [5:2] of CPU ADR
	input			i_sys_write,
	input	[15:0]	i_sys_valueW,
	output	[15:0]	o_sys_valueR,
	
	input			hBlankDotClk,
	input			vBlankDotClk,
	
	output			irqTimer0,
	output			irqTimer1,
	output			irqTimer2
);

	wire hBlankSysClk,vBlankSysClk;
	// TODO Convert signal HBlank and VBlank from Pixel clock to System clock domain.
	assign hBlankSysClk = hBlankDotClk;
	assign vBlankSysClk = vBlankDotClk;
		
	wire [1:0] timerID = adrInterruptReg2[3:2];
	wire [1:0] i_sys_regID   = adrInterruptReg2[1:0];
	
	// ===========================================
	// ---- Divide clock by 8 thingy ----
	reg [2:0] div8Clk;
	always @(posedge clk)
	begin
		div8Clk = div8Clk + 3'b001;
	end	
	// --- Output:flag every 8 cycles ---
	wire isDiv8 = (div8Clk == 3'd0);
	
	// ===========================================
	
	// Select adr timer
	wire CS_Timer0 = selTimerReg && (timerID == 2'd0);
	wire CS_Timer1 = selTimerReg && (timerID == 2'd1);
	wire CS_Timer2 = selTimerReg && (timerID == 2'd2);
	
	// ===========================================
	// Read Handling to bus
	//
	// Cycle 0 get value
	wire [15:0] outValue0, outValue1, outValue2;
	reg  [15:0] outV;
	reg  [15:0] outReg;
	always @(*) begin
		case (timerID)
		2'd0    : outV = outValue0;
		2'd1    : outV = outValue1;
		default : outV = outValue2;
		endcase
	end
	// 1 Cycle latency between read and data out.
	always @(posedge clk) begin
		outReg = outV;
	end
	// Assign value out
	assign o_sys_valueR = outReg;
	// -----------------------------------------------
	
	TimerUnit #(.TYPE(0)) timer0(
		.sysClk			(clk),
		.pixClk			(pixClk),
		.i_nRst			(i_nRst),
		
		.i_secondSrc	(/*Not used*/),
		.i_xBL			(vBlankDotClk),
		
		.i_sys_CSTimer		(CS_Timer0),
		.i_sys_write		(i_sys_write),
		.i_sys_regID			(i_sys_regID),
		.i_sys_valueW			(i_sys_valueW),
		.o_sys_valueR			(outValue0),
		.i_xxx_irqTimer		(irqTimer0)
	);
	
	TimerUnit #(.TYPE(1)) timer1(
		.sysClk			(clk),
		.pixClk			(/*Not used*/),
		.i_nRst			(i_nRst),
		
		.i_secondSrc	(hBlankSysClk),
		.i_xBL			(vBlankDotClk),
		
		.i_sys_CSTimer		(CS_Timer1),
		.i_sys_write		(i_sys_write),
		.i_sys_regID			(i_sys_regID),
		.i_sys_valueW			(i_sys_valueW),
		.o_sys_valueR			(outValue1),
		.i_xxx_irqTimer		(irqTimer1)
	);
	
	TimerUnit #(.TYPE(2)) timer2(
		.sysClk			(clk),
		.pixClk			(/*Not used*/),
		.i_nRst			(i_nRst),
		
		.i_secondSrc	(isDiv8),
		.i_xBL			(/*Unused by type 2*/),
		
		.i_sys_CSTimer		(CS_Timer2),
		.i_sys_write		(i_sys_write),
		.i_sys_regID			(adrInterruptReg2[1:0]),
		.i_sys_valueW			(i_sys_valueW),
		.o_sys_valueR			(outValue2),
		.i_xxx_irqTimer		(irqTimer2)
	);
	
	// ----------------------------------------------------------
	//   [PAL/NTSC DOT CLOCK SIM] + HBlank transition.
	// ----------------------------------------------------------
	/*
	reg  [10:0] divCounter;
	reg  prevHBlank;
	wire moreThan = (divCounter > (isPAL ? 11'd7 : 11'd745));
	reg  [1:0] stepDOT;
	always @(posedge clk)
	begin
		// Detect transition
		prevHBlank = hBlankDotClk;
		
		// Reverse Bresenham for DOT clock simulation.
		// For each valid increment compute next step
		if (i_nRst == 1'b0) begin
			divCounter = 11'd0;
		end else begin
			if (incr0) begin
				if (isPAL) begin
					divCounter	= divCounter + (moreThan ? 11'b1_11111_11101 : 11'd4   ); // -3  ,+4
				end else begin
					divCounter	= divCounter + (moreThan ? 11'b1_01000_10111 : 11'd436 ); // -745,+436
				end
				stepDOT		= moreThan ? 2'b10 : 2'b01;
			end
		end
	end
	*/
	// ----------------------------------------------------------
endmodule
