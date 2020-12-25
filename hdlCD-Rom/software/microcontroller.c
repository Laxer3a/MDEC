#include "if.h"

// -----------------------------------------
// Microcontroller IOs
// -----------------------------------------

u8 gSetIRQ;

u8 gSetBusy;
u8 gResetBusy;
u8 gRequestParam;
u8 gHasMedia;
u8 gIsOpen;

u8 gDataWrite;
u8 gRequDataWrite;

u8 gSMEN;				// Not used yet
u8 gBFWR;				// Not used yet
u8 gBFRD;				// Not used yet

// u8
u8 gValueParam;



// ===== 1F801801.0  W (HARDWARE)
u8 gHasNewCommand;
u8 gResetNewCommandFlag;
u8 gCommand;
BOOL	HasNewCommand		() { return gHasNewCommand;		}
void	ResetHasNewCommand	() { gHasNewCommand = 0;		}
u8		ReadCommand			() { return gCommand;			}

// ===== 1F801802.0  Internal R
u8 gIsFifoParamEmpty;
BOOL	IsFifoParamEmpty	() { return gIsFifoParamEmpty;	}
u8		ReadValueParam		() { return EXT_ReadParameter(); }
// Real HW pin 1/0 + Transition detection in HW.
void	RequestParam		(BOOL readOnOff) { }

// ===== 1F801802.0  Internal R
u8 gINTSetBit;
u8 gEnabledInt;
u8		GetEnabledINT		() { return gEnabledInt; }

void	SetINT				(int id) {
	if (gINTSetBit != 0) { lax_assert("WAS NOT ACK !!!"); }
	gINTSetBit = 1<<id;
}

void	SetIRQ				() {
	gSetIRQ = 1;
}

void	SetBusy				() {
}

void	ResetBusy			() {
}

void	WriteResponse		(u8 resp) {
}

BOOL	IsOpen				() {
}

BOOL	HasMedia			() {
}

u32		ReadHW_TimerDIV8	() {
	// 33.8 Mhz / 8.
	return 0;
}


