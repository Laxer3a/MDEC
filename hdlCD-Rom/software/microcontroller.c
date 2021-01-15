/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

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

u8 gApplyVol;
u8 gMuteADPCM;

u8 mixLtoR;
u8 mixLtoL;
u8 mixRtoL;
u8 mixRtoR;

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

u32		ReadHW_TimerDIV8	() {
	// 33.8 Mhz / 8.
	// For now we advance at 1000 cycle at 4.225 Mhz =>  0.0002366863905325444 sec.
	//												=>   0.2366863905325444    msec
	//												=> 236.6863905325444      microsec
	return 1000; 
}

BOOL	ApplyVolumes		() { return gApplyVol; }
BOOL	MuteADPCM			() { return gMuteADPCM;}
void	ResetApplyVolumes	() { gApplyVol = 0;  }
u8		GetLLVolume			() { return mixLtoL; }
u8		GetLRVolume			() { return mixLtoR; }
u8		GetRLVolume			() { return mixRtoL; }
u8		GetRRVolume			() { return mixRtoR; }

// Note : We will push data at regular pace.
// Audio is always 44.1 Khz and we push 588 sample per sector.
// A FIFO of 1024 or 2048 item should be just perfect and FULL should be never be reached.
// A single OR'ed FULL is ok for both fifo, the read / write will be slightly shifted in time by SPU and INT CPU.
// But we don't care much...
BOOL	IsSPUFifoFULL		() {
	lax_assert("NOT IMPLEMENTED"); return 0; 
}

void	PushSPUFIFOL		(s16 leftAudio) {
	lax_assert("NOT IMPLEMENTED");
}

void	PushSPUFIFOR		(s16 rightAudio) {
	lax_assert("NOT IMPLEMENTED");
}

BOOL	IsOutputDataFULL	() {
	lax_assert("NOT IMPLEMENTED"); return 0; 
}

BOOL	IsOutputDataEMPTY	() {
	lax_assert("NOT IMPLEMENTED"); return 0; 
}

void	PushOutputData		(u8 value) {
	lax_assert("NOT IMPLEMENTED");
}

// ==================================================
//   EXT CPU SIDE to INT CPU SIDE
// ==================================================

BOOL	IsOpen				()					{ return gIsOpen;   }
BOOL	HasMedia			()					{ return gHasMedia; }

BOOL	HasInputData		() { /* lax_assert("NOT IMPLEMENTED"); */ return 0; }
u8		PopInputData		() { lax_assert("NOT IMPLEMENTED"); return 0; }

void	RequestSector		(u32 sectorID) {
	lax_assert("NOT IMPLEMENTED");
}

void	SetMediaPresent			(BOOL hasMedia)	{ gHasMedia = hasMedia; }
void	SetOpen					(BOOL openLid)	{ gIsOpen   = openLid;  }

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

	gINTSetBit		= 0;
	gEnabledInt		= 0;
}
