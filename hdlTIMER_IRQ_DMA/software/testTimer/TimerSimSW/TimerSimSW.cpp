// GPUSimSW.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <stdio.h>
#include <memory.h>

class VTimerModule;
#include "..\..\..\rtl\obj_dir\VTimerModule.h"

// My own scanner to generate VCD file.
#define VCSCANNER_IMPL
#include "VCScanner.h"

extern void registerVerilatedMemberIntoScanner(VTimerModule* mod, VCScanner* pScan);
extern void addEnumIntoScanner(VCScanner* pScan);

typedef unsigned char u8;
typedef unsigned int  u32;
typedef unsigned short u16;

class CommandTimer {

	struct command {
		u8 selTimerReg;
		u8 adrInterruptReg2;
		u8 i_write;
		u8 valueW;
		int timeStamp;
	};
	int currRead  = 0;
	int currWrite = 0;
	int timeToCommand = 0;
	int timeStamp;

	command innerCommands[2000];

private:
	void innerWrite(u8 ID, u8 offset, u16 value, u8 isWrite) {
		innerCommands[currWrite].selTimerReg		= 1;
		innerCommands[currWrite].adrInterruptReg2	= (ID * 4) + offset;
		innerCommands[currWrite].i_write			= isWrite;
		innerCommands[currWrite].valueW				= value;
		innerCommands[currWrite].timeStamp			= timeStamp++;
		currWrite++;
		if (currWrite == 2000) { currWrite = 0; }
	}
public:

	// Bit 0 Synchronization Enable (0=Free Run, 1=Synchronize via Bit1-2)
	static const int FREE_RUN = 0;
//	static const int SYNC_RUN = 1;

	// Bit 1-2   Synchronization Mode   (0-3, see lists below)
	// Timer 0/1
	static const int SYNC_MODE_PAUSE_XBLANK              = (0<<0) | 1;
	static const int SYNC_MODE_RESETCNT_XBLANK           = (1<<1) | 1;
	static const int SYNC_MODE_RESETCNT_XBLANK_PAUSEOUT  = (2<<1) | 1;
	static const int SYNC_MODE_PAUSE_UNTIL_XBLANK        = (3<<1) | 1;
	// Timer 2
	static const int SYNC2_MODE_STOPCNT0				 = 0<<1;
	static const int SYNC2_MODE_STOPCNT3				 = 3<<1; // Same
	static const int SYNC2_MODE_FREERUN1				 = 1<<1;
	static const int SYNC2_MODE_FREERUN2				 = 2<<1; // Same

	// Bit 3
	static const int LOOP_AFTER_TARGET					 = 1<<3;
	static const int LOOP_OVERFLOW						 = 0<<3;

	// Bit 4
	static const int IRQ_ON_EQ_TARGET					 = 1<<4;

	// Bit 5
	static const int IRQ_ON_EQ_FFFF						 = 1<<5;

	// Bit 6
	static const int IRQ_REPEAT							 = 1<<6;

	// Bit 7-8
	// Timer 0/1
	static const int T01_CLK_SRC_SYSTEM0				 = 0<<8;
	static const int T01_CLK_SRC_SYSTEM2				 = 2<<8;
	static const int T01_CLK_EXT1						 = 1<<8;
	static const int T01_CLK_EXT3						 = 3<<8;

	// Timer 2
	static const int T2_CLK_SRC_SYSTEM0					 = 0<<8;
	static const int T2_CLK_SRC_SYSTEM1					 = 1<<8;
	static const int T2_CLK_EXT2						 = 2<<8;
	static const int T2_CLK_EXT3						 = 3<<8;

	// Status.
	static const int REACHED_TARGET						 = 1<<11;
	static const int REACHED_FFFF						 = 1<<12;

	static const int TOGGLE_MODE						 = 1<<7;

	static const int IS_IRQSET							 = 1<<10;

	CommandTimer():currRead(0),currWrite(0),timeToCommand(0),timeStamp(0) {}

	void writeTimerCounter(u8 ID, u16 value) {
		innerWrite(ID,0,value,1);
	}

	void writeTimerSetup  (u8 ID, u16 setup) {
		innerWrite(ID,1,setup,1);
	}

	void writeTimerTarget (u8 ID, u16 target) {
		innerWrite(ID,2,target,1);
	}

	void readTimer(u8 ID, u8 reg) {
		innerWrite(ID,reg,0,0);
	}

	bool exists(int timing) {
		if (timeToCommand > 0) {
			timeToCommand--;
			return false;
		} else {
			if (timing >= innerCommands[currRead].timeStamp) {
				return currWrite != currRead;
			} else {
				return false;
			}
		}
	}

	void write(VTimerModule* pMod) {
		command& com = innerCommands[currRead++];
		pMod->selTimerReg		= com.selTimerReg;
		pMod->adrInterruptReg2	= com.adrInterruptReg2;
		pMod->i_sys_write			= com.i_write;
		pMod->i_sys_valueW			= com.valueW;

		if (currRead == 2000) {
			currRead = 0;
		}
		timeToCommand = 2; // 3 cycle before sending new write...
	}

	void noOp(VTimerModule* pMod) {
		pMod->selTimerReg		= 0;
		pMod->adrInterruptReg2	= 0;
		pMod->i_sys_write		= 0;
		pMod->i_sys_valueW		= 0;
	}

	void operateFrom(int timing) {
		timeStamp = timing;
	}
};

/*
1F801100h+N*10h - Timer 0..2 Current Counter Value (R/W)
	0-15  Current Counter value (incrementing)
	16-31 Garbage

	- This register is automatically incrementing. 
	- It is write-able (allowing to set it to any value). 
	- It gets forcefully reset to 0000h on any write to the Counter Mode register.
	- It gets            reset to 0000h on counter overflow (either when exceeding FFFFh, or when exceeding the selected target value).
		Thus, Range is [0..value]

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
         Timer 0:  0 or 2 = System Clock,  1 or 3 = Dotclock
         Timer 1:  0 or 2 = System Clock,  1 or 3 = Hblank
         Timer 2:  0 or 1 = System Clock,  2 or 3 = System Clock/8
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
*/

void sendCommand(CommandTimer& commands, VTimerModule* mod, int clockDiv2) {
		if (commands.exists(clockDiv2)) {
			commands.write(mod);
		} else {
			commands.noOp(mod);
		}
		mod->eval();
}

int main(int argcount, char** args)
{
	int sFrom = 0;
	int sTo   = 0;
	int sL    = 0;

	CommandTimer commands;

	if (argcount > 3) {
		sscanf(args[1], "%i", &sFrom);
		sscanf(args[2], "%i", &sTo);
		sscanf(args[3], "%i", &sL);
	}

	// ------------------------------------------------------------------
	// [Instance of verilated GPU & custom VCD Generator]
	// ------------------------------------------------------------------
	VTimerModule* mod		= new VTimerModule();
	VCScanner*	pScan = new VCScanner();
				pScan->init(2000);

	registerVerilatedMemberIntoScanner(mod, pScan);
	addEnumIntoScanner(pScan);
	

	int clockCnt  = 0;
	int clockDiv2 = 0;
	pScan->addMemberFullPath( "CYCLE", WIRE, BIN,32,&clockDiv2);

	// AFTER all signal added.
	pScan->addPlugin(new ValueChangeDump_Plugin("timerLog.vcd"));

	// ------------------------------------------------------------------
	// Reset the chip for a few cycles at start...
	// ------------------------------------------------------------------
	mod->i_nRst = 0;
	for (int n=0; n < 10; n++) {
		mod->clk = 0; mod->eval(); pScan->eval(clockCnt); clockCnt++;
		clockDiv2++;
		mod->clk = 1; mod->eval(); pScan->eval(clockCnt); clockCnt++;
	}
	mod->i_nRst = 1;
	for (int n=0; n < 10; n++) {
		mod->clk = 0; mod->eval(); pScan->eval(clockCnt); clockCnt++;
		clockDiv2++;
		mod->clk = 1; mod->eval(); pScan->eval(clockCnt); clockCnt++;
	}

	commands.operateFrom(20);
	commands.readTimer(1,1);
	commands.writeTimerCounter(1,1);
	commands.writeTimerTarget(1,14); // Target is 48.
	commands.writeTimerSetup(1, 
		CommandTimer::IRQ_ON_EQ_TARGET  |
		CommandTimer::IRQ_REPEAT        |
		CommandTimer::LOOP_AFTER_TARGET |
		CommandTimer::TOGGLE_MODE |
		CommandTimer::SYNC_MODE_RESETCNT_XBLANK/* | CommandTimer::FREE_RUN */
	);

	commands.operateFrom(42);
	commands.readTimer(1,1);

	// ------------------------------------------------------------------
	// MAIN LOOP
	// ------------------------------------------------------------------
	int waitCount = 0;

	int stuckState = 0;
	int currentCommandID      =  0;

	bool NoHW = false;

	bool log
#ifdef RELEASE
		= false;
#else
		= true;
#endif

	int didRead = 0;


	while (clockCnt < 1500)
	{

		mod->clk    = 0;
		mod->eval();

		// Generate VCD if needed
		pScan->eval(clockCnt);
		clockCnt++;


		// TODO : Set input with different timing signals....
		// - VL_IN8(hBlankDotClk,0,0);
		// - VL_IN8(vBlankDotClk,0,0);

		clockDiv2++;

		mod->clk    = 1;
		mod->eval();

		// ---------------------------------------------------
		mod->hBlankDotClk = (clockDiv2 / 100) & 1;
		mod->vBlankDotClk = (clockDiv2 / 100) & 1;

		sendCommand(commands, mod, clockDiv2);
		// ---------------------------------------------------

		pScan->eval(clockCnt);
		clockCnt++;
	}

	pScan->shutdown();
}
