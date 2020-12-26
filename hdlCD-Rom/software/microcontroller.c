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
BOOL	HasNewCommand		()					{ return gHasNewCommand;		}
void	ResetHasNewCommand	()					{ gHasNewCommand = 0;			}
u8		ReadCommand			()					{ return gCommand;				}

// ===== 1F801802.0  Internal R
u8 gIsFifoParamEmpty;
BOOL	IsFifoParamEmpty	()					{ return gIsFifoParamEmpty;		}
u8		ReadValueParam		()					{ return EXT_ReadParameter();	}
// Real HW pin 1/0 + Transition detection in HW.
void	RequestParam		(BOOL readOnOff)	{ gRequestParam = readOnOff;	}

// ===== 1F801802.0  Internal R
u8 gINTSetBit;
u8 gEnabledInt;
u8		GetEnabledINT		()					{ return gEnabledInt;			}

void	SetINT				(int id) {
	if (gINTSetBit != 0) { lax_assert("WAS NOT ACK !!!"); }
	if (id == 0) { lax_assert("ID ZERO SHIFT TRICK FAIL. (id-1)"); }
	gINTSetBit = 1<<(id-1);
}

void	SetIRQ				()					{ gSetIRQ = 1;					}

void	SetBusy				()					{ gSetBusy = 1;					}

void	ResetBusy			()					{ gSetBusy = 0;					}

void	WriteResponse		(u8 resp)			{ EXT_WriteResponse(resp);		}

BOOL	IsOpen				()					{ return gIsOpen; }

BOOL	HasMedia			()					{ lax_assert("NOT IMPLEMENTED."); return 0; }

u32		ReadHW_TimerDIV8	() {
	// 33.8 Mhz / 8.
	// For now we advance at 100 cycle at 4.225 Mhz => 0.00002366863905325444 sec.
	//												=> 0.02366863905325444    msec
	//												=> 23.66863905325444      microsec
	return 100; 
}

void InitPorting() {
	gSetIRQ			= 0;
	gSetBusy		= 0;
	gResetBusy		= 0;
	gRequestParam	= 0;
	gHasMedia		= 0;
	gIsOpen			= 0;

	gDataWrite		= 0;
	gRequDataWrite	= 0;

	gSMEN			= 0;
	gBFWR			= 0;
	gBFRD			= 0;

	gValueParam		= 0;

	gHasNewCommand	= 0;
	gResetNewCommandFlag= 0;
	gCommand		= 0;

	gIsFifoParamEmpty = 0;
	gINTSetBit		= 0;
	gEnabledInt		= 0;
}
