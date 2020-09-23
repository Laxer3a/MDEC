
#include "..\..\..\rtl\obj_dir\VTimerModule.h"

class VTimerModule;

#include "VCScanner.h"

#define MODULE mod
#define SCAN   pScan

// ----------
// TRICK WITH MACRO TO REGISTER THE MEMBERS OF THE VERILATED INSTANCE INTO MY VCD SCANNER...
// ----------

#define VL_IN(NAME,size,s2)			SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIGA(NAME,size,s2,cnt)	SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_IN8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_IN16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_IN64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );

#define VL_INW(NAME,size,s2,storageSize)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME);
#define VL_OUTW(NAME,size,s2,storageSize)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME);
#define VL_SIGW(NAME,size,s2,storageSize)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME);

void addEnumIntoScanner(VCScanner* pScan) {
	return;

}

void registerVerilatedMemberIntoScanner(VTimerModule* mod, VCScanner* pScan) {
    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    // Begin mtask footprint  all: 
    VL_IN8(clk,0,0);
    VL_IN8(i_nRst,0,0);
    VL_IN8(isPAL,0,0);
    VL_IN8(pixClk,0,0);
    VL_IN8(selTimerReg,0,0);
    VL_IN8(adrInterruptReg2,3,0);
    VL_IN8(i_sys_write,0,0);
    VL_IN8(hBlankDotClk,0,0);
    VL_IN8(vBlankDotClk,0,0);
    VL_OUT8(irqTimer0,0,0);
    VL_OUT8(irqTimer1,0,0);
    VL_OUT8(irqTimer2,0,0);
    VL_IN16(i_sys_valueW,15,0);
    VL_OUT16(o_sys_valueR,15,0);
    
    // LOCAL SIGNALS
    // Internals; generally not touched by application code
    // Begin mtask footprint  all: 
    VL_SIG8(TimerModule__DOT__clk,0,0);
    VL_SIG8(TimerModule__DOT__i_nRst,0,0);
    VL_SIG8(TimerModule__DOT__isPAL,0,0);
    VL_SIG8(TimerModule__DOT__pixClk,0,0);
    VL_SIG8(TimerModule__DOT__selTimerReg,0,0);
    VL_SIG8(TimerModule__DOT__adrInterruptReg2,3,0);
    VL_SIG8(TimerModule__DOT__i_sys_write,0,0);
    VL_SIG8(TimerModule__DOT__hBlankDotClk,0,0);
    VL_SIG8(TimerModule__DOT__vBlankDotClk,0,0);
    VL_SIG8(TimerModule__DOT__irqTimer0,0,0);
    VL_SIG8(TimerModule__DOT__irqTimer1,0,0);
    VL_SIG8(TimerModule__DOT__irqTimer2,0,0);
    VL_SIG8(TimerModule__DOT__hBlankSysClk,0,0);
    VL_SIG8(TimerModule__DOT__vBlankSysClk,0,0);
    VL_SIG8(TimerModule__DOT__timerID,1,0);
    VL_SIG8(TimerModule__DOT__i_sys_regID,1,0);
    VL_SIG8(TimerModule__DOT__div8Clk,2,0);
    VL_SIG8(TimerModule__DOT__isDiv8,0,0);
    VL_SIG8(TimerModule__DOT__CS_Timer0,0,0);
    VL_SIG8(TimerModule__DOT__CS_Timer1,0,0);
    VL_SIG8(TimerModule__DOT__CS_Timer2,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__sysClk,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_nRst,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__pixClk,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_secondSrc,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_xBL,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_sys_CSTimer,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_sys_write,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_sys_regID,1,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__i_xxx_irqTimer,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__sys_freeRun,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__sys_mode,1,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__sys_resetType,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__IrqWhenTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__IrqWhenFull,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__IrqRepeat,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__IrqFlip,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__srcClockSel,1,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__reachedTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__reachedFull,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__transitionXBL,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__transitionSecondSrc,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__xBLTrans,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__secondClkTrans,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__isFull,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__isTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__incr,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__reset,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__setFreeRun,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__useExtClock,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__freeRunIncr,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__resetBase,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__basePulse,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__fired,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__setIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__prevIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__transitionIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__outIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer0__DOT__exportIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__sysClk,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_nRst,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__pixClk,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_secondSrc,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_xBL,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_sys_CSTimer,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_sys_write,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_sys_regID,1,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__i_xxx_irqTimer,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__sys_freeRun,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__sys_mode,1,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__sys_resetType,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__IrqWhenTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__IrqWhenFull,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__IrqRepeat,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__IrqFlip,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__srcClockSel,1,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__reachedTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__reachedFull,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__transitionXBL,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__transitionSecondSrc,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__xBLTrans,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__secondClkTrans,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__isFull,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__isTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__incr,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__reset,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__setFreeRun,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__useExtClock,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__freeRunIncr,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__resetBase,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__basePulse,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__fired,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__setIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__prevIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__transitionIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__outIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer1__DOT__exportIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__sysClk,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_nRst,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__pixClk,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_secondSrc,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_xBL,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_sys_CSTimer,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_sys_write,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_sys_regID,1,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__i_xxx_irqTimer,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__sys_freeRun,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__sys_mode,1,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__sys_resetType,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__IrqWhenTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__IrqWhenFull,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__IrqRepeat,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__IrqFlip,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__srcClockSel,1,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__reachedTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__reachedFull,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__transitionXBL,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__transitionSecondSrc,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__xBLTrans,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__secondClkTrans,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__isFull,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__isTarget,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__incr,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__reset,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__setFreeRun,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__useExtClock,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__freeRunIncr,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__resetBase,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__basePulse,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__fired,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__setIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__prevIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__transitionIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__outIRQ,0,0);
    VL_SIG8(TimerModule__DOT__timer2__DOT__exportIRQ,0,0);
    VL_SIG16(TimerModule__DOT__i_sys_valueW,15,0);
    VL_SIG16(TimerModule__DOT__o_sys_valueR,15,0);
    VL_SIG16(TimerModule__DOT__outValue0,15,0);
    VL_SIG16(TimerModule__DOT__outValue1,15,0);
    VL_SIG16(TimerModule__DOT__outValue2,15,0);
    VL_SIG16(TimerModule__DOT__outV,15,0);
    VL_SIG16(TimerModule__DOT__outReg,15,0);
    VL_SIG16(TimerModule__DOT__timer0__DOT__i_sys_valueW,15,0);
    VL_SIG16(TimerModule__DOT__timer0__DOT__o_sys_valueR,15,0);
    VL_SIG16(TimerModule__DOT__timer0__DOT__xxx_counter,15,0);
    VL_SIG16(TimerModule__DOT__timer0__DOT__sys_target,15,0);
    VL_SIG16(TimerModule__DOT__timer0__DOT__modeR,15,0);
    VL_SIG16(TimerModule__DOT__timer1__DOT__i_sys_valueW,15,0);
    VL_SIG16(TimerModule__DOT__timer1__DOT__o_sys_valueR,15,0);
    VL_SIG16(TimerModule__DOT__timer1__DOT__xxx_counter,15,0);
    VL_SIG16(TimerModule__DOT__timer1__DOT__sys_target,15,0);
    VL_SIG16(TimerModule__DOT__timer1__DOT__modeR,15,0);
    VL_SIG16(TimerModule__DOT__timer2__DOT__i_sys_valueW,15,0);
    VL_SIG16(TimerModule__DOT__timer2__DOT__o_sys_valueR,15,0);
    VL_SIG16(TimerModule__DOT__timer2__DOT__xxx_counter,15,0);
    VL_SIG16(TimerModule__DOT__timer2__DOT__sys_target,15,0);
    VL_SIG16(TimerModule__DOT__timer2__DOT__modeR,15,0);
}
