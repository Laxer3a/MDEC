/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

/*
 * Handles all CD-ROM registers and functions.
 */
#include "if.h"


// -----------------------------------------
// Forward declaration Debug API
// -----------------------------------------
void CDRomLogCommand(u8 command);
void CDRecordRespLog(u8 responseToWrite);
void CDRomLogResponse();

// -----------------------------------------
// Forward declaration ADPCM
// -----------------------------------------
void initDecoderADPCM	();
void DecodeSectorXA		(u8* sectorData);

// DIP Switch
u8 SYS_DISC = 0x1 /*NTSC-A*/;
// SYS_DISC = 0x5 /*PAL   */;
// SYS_DISC = 0x9 /*NTSC-J*/;

// GLOBAL VARIABLE SPACE.
u8 gParam[16];
u8 gParamCnt;
u16 gLatencyResetBusy;

// -------------------------------------------------------------
//   Drive Physical simulation
// -------------------------------------------------------------

#include "disc.h"

struct Disc discInternal;

static inline u32 ToUint(u24* pComp) { return (pComp->d[0]) || (pComp->d[1]<<8) || (pComp->d[2]<<16); }

// -------------------------------------------------------------
//   Drive Physical simulation
// -------------------------------------------------------------

enum {
	// Possible target
	DRIVE_STATE_STOPPED	= 0,
	DRIVE_STATE_SEEK    = 1,
	DRIVE_STATE_READ    = 2,
	DRIVE_STATE_PAUSE   = 3,
		// Internal transitionnal states.
		DRIVE_STATE_INTERNAL= 4, // Usefull constant
			DRIVE_STATE_SPINDOWN= 4,
			DRIVE_STATE_DETECTMEDIA = 5,
			DRIVE_STATE_SPINUP  = 6,
//			DRIVE_STATE_READTOC	= 7,
			DRIVE_STATE_SEEKTOC = 8,
};

enum {
	// WARNING : NEVER STORE IN SSR STATUS !!!!
	// SPIKE during result sent to PSX, use | to send it.
	HAS_ERROR		= 0x01,

	IS_MOTOR_ON		= 0x02,
	SEEK_ERROR		= 0x04,
	ID_ERROR		= 0x08,
	SHELL_OPEN		= 0x10,
	READING			= 0x20,
	SEEKING			= 0x40,
	PLAYING_CDDA	= 0x80
};
u8 ssrStatus; // CD Rom Controller Status.

#define BASECLOCK		(33800000)

#define TOTIMER(s)		((u32)(s*(BASECLOCK>>3)))

typedef struct DriveSimulator_ {
	// Timing simulation in ms ? microsec ? sysclk ?
	// PB : 32 bit counter loop must be handled.
	u32 currCycle;

	// HW Counter related internal timers.
	s32 transitionTime;
	s32 newSectorTime;

	u32 currTrackStartIncluded;
	u32 currTrackEndExcluded;

	u32 currSector;

	u8 knownTOC;
	u8 lastOpen;
	u8 currState;
	u8 lastState;
	u8 targetState;

	u8 doubleSpeed;
//	u8 reqSector;		// Number of sector to 

	u8  currTrackType;

//	u32 targetSector;

} DriveSimulator;

DriveSimulator gDriveSim;

void DRV_SetTargetState		(u8 drv_state) {
	// Stop, Seek, Read, Pause (all other are intermediate states)
	if (drv_state >= DRIVE_STATE_INTERNAL) {
		lax_assert("Forbidden state target");
	}

	gDriveSim.targetState = drv_state;
}

u8   DRV_NextState			(u8 drv_state, u8 target) {
	u8 out = drv_state;

	switch (target) {
	case DRIVE_STATE_STOPPED:
	case DRIVE_STATE_PAUSE:
	case DRIVE_STATE_READ:
	case DRIVE_STATE_SEEK:
		break;
	default:
		lax_assert("UNAUTORIZED TARGET");
	}

	// Generic code to go toward stopping the drive if not stopped.
	// If working       -> SPIN DOWN.
	// If spinning down -> STOP.
	if (target == DRIVE_STATE_STOPPED && (drv_state!=target)) {
		out = (drv_state == DRIVE_STATE_SPINDOWN) ? DRIVE_STATE_STOPPED
			                                      : DRIVE_STATE_SPINDOWN;
	} else {
		switch (drv_state) {
		case DRIVE_STATE_STOPPED: out = DRIVE_STATE_DETECTMEDIA;  break;
		case DRIVE_STATE_DETECTMEDIA: out = DRIVE_STATE_SPINUP; break;
		case DRIVE_STATE_SPINUP : out = DRIVE_STATE_SEEKTOC; break;
		case DRIVE_STATE_SEEKTOC: out = DRIVE_STATE_PAUSE; break;

		case DRIVE_STATE_PAUSE:
		case DRIVE_STATE_SEEK:
		case DRIVE_STATE_READ:
			// Read, Seek, Pause can switch from each other ?
			// Can switch to themselves ? (No
			out = target;
			break;
		}
	}

	return out;
}

void DRV_Reset				() {
	gDriveSim.currCycle	  = 0;
	gDriveSim.currState   = gDriveSim.lastState = DRIVE_STATE_STOPPED;
	gDriveSim.doubleSpeed = 0;
	gDriveSim.currSector  = 0;

	gDriveSim.currTrackStartIncluded	= -1;
	gDriveSim.currTrackEndExcluded		= -1;
	gDriveSim.currTrackType				= 0;

	gDriveSim.transitionTime = 0;
	gDriveSim.newSectorTime  = 0;
	gDriveSim.lastOpen		= 0xFF; // UNDEFINED to be sure we check value change.
	gDriveSim.knownTOC		= FALSE;
}

/*	- Will use a sysclk / 8 timer.
	- Problem : not a multiple of 75 per second.
	- Result in : 56333 cycle per sector, instead of 56333.33333
	- Loose 25  cycle / second => 0.999994 precision. (at x1 speed)
	- Loose 100 cycle / second => 0.999976 precision. (at x2 speed)

	Note : a CD is 630000 sector max. At complete linear reading, would end up with a desync of 1.89 sector at x2 speed.
	I don't think I should worry about that.
*/
u8   DRV_Update				(u32 deltaTdiv8) {
	u8  work     = 0;
	u32 oldTimer = gDriveSim.currCycle;
	u32 newTimer = oldTimer + deltaTdiv8;
	if (newTimer < oldTimer) {
		// Overflow ! => oldTimer was HUGE.
		// Compute the distance that was necessary from last to overflow, then add to new.
		newTimer = (~oldTimer) + newTimer;
	}

	// TODO : Handle state machine
	//   if state change...
	s32 transitionTime = gDriveSim.transitionTime;
	u8  oldState       = gDriveSim.currState;
	u8  requestTOC     = 0;

	gDriveSim.lastState= oldState;

	u8 currOpen = IsOpen();
	if (gDriveSim.lastOpen != currOpen) {
		gDriveSim.lastOpen = currOpen;
		if (currOpen) {
			// Close -> Open
			DRV_SetTargetState(DRIVE_STATE_STOPPED);
			ssrStatus |= SHELL_OPEN;
			gDriveSim.knownTOC= FALSE;
		} else {
			gDriveSim.currState = DRIVE_STATE_STOPPED;
			// Open  -> Close
			if (HasMedia()) {
				DRV_SetTargetState(DRIVE_STATE_PAUSE);
			}
			ssrStatus &= ~SHELL_OPEN;
		}
	}

	if (TRUE) {
		s32 newTransition = transitionTime-deltaTdiv8;
		u8  completed     = (newTransition <= 0); // Or [new target when current==lastTarget.]
		transitionTime	  = newTransition;

		switch (gDriveSim.targetState) {
		case DRIVE_STATE_STOPPED:
			switch (gDriveSim.currState) {
			// --------------------------------------
			case DRIVE_STATE_STOPPED:
				// Do nothing.
				ssrStatus &= ~IS_MOTOR_ON;
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINDOWN:
				if (completed) { gDriveSim.currState = DRIVE_STATE_STOPPED; }
				break;
			// --------------------------------------
			default:
				// Any state will spin down.
				if (completed) {
					gDriveSim.currState  = DRIVE_STATE_SPINDOWN;
					transitionTime      += TOTIMER(0.342);
				}
				break;
			}
			// --------------------------------------
			break;

		case DRIVE_STATE_PAUSE:
			switch (gDriveSim.currState) {
			// --------------------------------------
			case DRIVE_STATE_STOPPED:
				if (completed) {
					if (gDriveSim.knownTOC) {
						// If we already know the TOC (Lid stay closed)
						// 
						gDriveSim.currState  = DRIVE_STATE_SPINUP;
						ssrStatus           |= IS_MOTOR_ON;
						transitionTime      += TOTIMER(1.816);
					} else {
						gDriveSim.currState  = DRIVE_STATE_DETECTMEDIA;
						transitionTime      += TOTIMER(1.287);
					}
				}
				break;
			// --------------------------------------
			case DRIVE_STATE_DETECTMEDIA:
				// MEDIA DETECTION TAKES 1.287 Second
				if (completed) {
					gDriveSim.currState  = DRIVE_STATE_SPINUP;
					ssrStatus           |= IS_MOTOR_ON;
					transitionTime      += TOTIMER(5.853);
				}
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINUP:
				if (completed) {
					gDriveSim.currState  = DRIVE_STATE_SEEKTOC;
					requestTOC			 = 4;
					ssrStatus           |= SEEKING;
					transitionTime      += TOTIMER(0.412);
				}
				break;
			// --------------------------------------
			case DRIVE_STATE_SEEKTOC: // Include TOC READ TIME.
				if (completed) {
					ssrStatus &= ~SEEKING;
					gDriveSim.currState  = DRIVE_STATE_PAUSE;
				}
				break;
			// --------------------------------------
			case DRIVE_STATE_READ:
				// PAUSE->READ : No problem
				if (completed) {
					ssrStatus &= ~READING;
					gDriveSim.currState = DRIVE_STATE_PAUSE;
				}
				break;
			// --------------------------------------
			case DRIVE_STATE_SEEK:
				if (completed) {
					ssrStatus &= ~SEEKING;
					gDriveSim.currState = DRIVE_STATE_PAUSE;
				}
				break;
			case DRIVE_STATE_PAUSE:
				// Do nothing, self state.
				break;
			default:
				lax_assert("UNIMPLEMENTED, FORGOT TRANSITION ?");
				break;
			}
			break;

		case DRIVE_STATE_READ:
			switch (gDriveSim.currState) {
			case DRIVE_STATE_PAUSE:
				if (completed) {
					ssrStatus |= READING;
					gDriveSim.currState = DRIVE_STATE_READ;
				}
				break;
			case DRIVE_STATE_SEEK:
				if (completed) {
					ssrStatus &= ~SEEKING;
					ssrStatus |= READING;
					gDriveSim.currState = DRIVE_STATE_READ;
				}
				break;
			case DRIVE_STATE_READ:
				// Do nothing, self state.
				break;
			default:
				lax_assert("UNIMPLEMENTED, FORGOT TRANSITION ?");
				break;
			}
			break;
		case DRIVE_STATE_SEEK:
			switch (gDriveSim.currState) {
			case DRIVE_STATE_PAUSE:
				if (completed) {
					ssrStatus |= SEEKING;
					gDriveSim.currState = DRIVE_STATE_SEEK;
				}
				break;
			case DRIVE_STATE_READ:
				if (completed) {
					ssrStatus &= ~READING;
					ssrStatus |= SEEKING;
					gDriveSim.currState = DRIVE_STATE_SEEK;
				}
				break;
			case DRIVE_STATE_SEEK:
				// Do nothing, self state.
				break;
			default:
				lax_assert("UNIMPLEMENTED, FORGOT TRANSITION ?");
				break;
			}
			break;
		}

		if (gDriveSim.targetState == gDriveSim.currState) {
			transitionTime      = 0; // Completed target
		} else {
			// TODO transition time
		}

		gDriveSim.transitionTime = transitionTime;
	}

	// State change announced to loop.
	{
		u8 stateChange = (gDriveSim.currState != oldState);
		if (stateChange) {
			printf("@%i => State Change : %i->%i (STATUS:%02X)\n",newTimer,oldState,gDriveSim.currState, ssrStatus);
		}
		work |= stateChange ? 2 : 0;
	}

	//
	// Fetching sectors... (Not TOC)
	//
	if (gDriveSim.currState == DRIVE_STATE_READ) {
		s32 newSectorTime = gDriveSim.newSectorTime;
		if (newSectorTime <= 0) {
			newSectorTime += gDriveSim.doubleSpeed ? 28166 : 56333; // 1/75th of a second approx. (1 sector)
			work |= 1; // Fetching sector.
		}
		newSectorTime -= deltaTdiv8;
		gDriveSim.newSectorTime = newSectorTime;
	}

	gDriveSim.currCycle = newTimer;

	return work | requestTOC;
}

// TODO Macro later.
void DRV_SetSpeedMode		(u8 speed)			{ gDriveSim.doubleSpeed = speed-1; } // Works only for x1 / x2.
u8   DRV_GetCurrentState	()					{ return gDriveSim.currState;  }
u8   DRV_StateChanged		()					{ return gDriveSim.currState != gDriveSim.lastState; }
u32  DRV_GetCurrentSector	()					{ return gDriveSim.currSector; }

// PB : what if Spinup/Spindown ? (Neither reading/playing)

u8 isSeeking() { return (DRV_GetCurrentState() == DRIVE_STATE_SEEK); }
u8 isReading() { return (DRV_GetCurrentState() == DRIVE_STATE_READ); }
u8 isPlaying() { return (DRV_GetCurrentState() == DRIVE_STATE_READ) /* TODO : && PLAYING_CDDA */; }

// -------------------------------------------------------------


enum {
	ERROR_REASON_NOT_READY						= 0x80,
	ERROR_CODE_INVALID_COMMAND					= 0x40,
	ERROR_REASON_INCORRECT_NUMBER_OF_PARAMETERS = 0x20,
	ERROR_REASON_INVALID_ARGUMENT				= 0x10,
};

enum {
	EPlayMode_Normal		= 0,
	EPlayMode_FastForward	= 1,
	EPlayMode_Rewind		= 2
};

enum {
	DRV_CDDA		= 0x01,
	DRV_AUTOPAUSE	= 0x02,
	DRV_REPORT		= 0x04,
	DRV_XAFILTER	= 0x08,
	DRV_IGNORE		= 0x10,
	DRV_SECTORSIZE	= 0x20,
	DRV_XAADPCM		= 0x40,
	DRV_SPEED		= 0x80,
};

u8 gDriveMode;
u8 gSectorSkip; u16 gSectorLength; u16 gSectorTransfered;
u8 gFilterFile;
u8 gFilterChannel;
u8 audio_mute;

u8 maxTrackCount = 0;
u8 GetMaxTrackCount() {
	// TODO load value of maxTrackCount.
	lax_assert("UNIMPLEMENTED MAX TRACK COUNT");
	return maxTrackCount;
}

// PSX SIDE PIN, ADR PIN ???
// Later replace with IO pin reading.
// --- Input

typedef void (*sequenceF)(int);

enum {
	EVENT_TYPE_DELAY = 0,
	EVENT_TYPE_STATE = 1,
	EVENT_ITEMFREE   = 0xFF
};
typedef struct _launchItem {
	sequenceF	functionToCallBack;	// 
	u32			trigger;			// Delay Mode = 
	u8			type;				// 0=Delay, 1=Event, ... , 0xFF=Cancelled
	u8			parameter;			// Sequence number.
} LaunchItem;

LaunchItem gLaunchList[8];
u8 gLaunchListActive;

void ParseQueue(u32 deltaT) {
	if (gLaunchListActive) {
		LaunchItem* p  = gLaunchList;
		LaunchItem* pE = p + (gLaunchListActive-1);
		while (p <= pE) {
			switch (p->type) {
			case EVENT_TYPE_DELAY:
				{
					u32 newTime = p->trigger - deltaT;

					if (newTime > p->trigger) { // newTime overflowed. negative value.
						p->functionToCallBack(p->parameter);
						p->type = EVENT_ITEMFREE;
					}
				}
				break;
			case EVENT_TYPE_STATE:
				lax_assert("UNIMPLEMENTED");
				if (FALSE) {
					p->functionToCallBack(p->parameter);
					p->type = EVENT_ITEMFREE;
				}
				break;
			case EVENT_ITEMFREE:
				// If last element is inactive, reduce the list size.
				if (p == pE) { gLaunchListActive--; }
				break;
			}
		}
	}
}

void Launch(int delay, sequenceF fct, int param) {
	lax_assert("ERROR. DEPRECATED, SWITCH TO NEW STUFF");
}

void LaunchTimer(int delay, sequenceF fct, int param) {
	// [Effort to make the code smaller, readability probably suffers.

	LaunchItem* p  =     gLaunchList;
	LaunchItem* pE = p + gLaunchListActive;
	// 1st find a free element.
	while (p < pE) {
		// Free slot
		if (p->type == EVENT_ITEMFREE) {
			goto registerEntry;
		}
		p++;
	}

	if (gLaunchListActive < 8) {
		// Allocate new element.
		p = &gLaunchList[gLaunchListActive++];
	} else {
		lax_assert("ERROR. LAUNCH LIST FULL.");
		return;
	}

registerEntry:
	p->functionToCallBack	= fct;
	p->parameter			= param;
	p->type					= 0;
	p->trigger				= delay;
}

BOOL CanReadMedia() { return (!IsOpen()) && (HasMedia());}
BOOL IsAudioDisc () { lax_assert("UNIMPLEMENTED"); return 0; }

void FifoResponse(u8 responseToWrite) {
	CDRecordRespLog(responseToWrite);
	WriteResponse(responseToWrite);
}

// To make code more compact if possible.
void FifoResponseStatus() {
	FifoResponse(ssrStatus);
}

void FifoResponseStatusOrBit(u8 additionBit) {
	FifoResponse(ssrStatus | additionBit);
}

u8 BCDtoBinary(u8 bcd) {
	int hi = ((bcd >> 4) & 0xf);
	int lo = (bcd & 0xf);
    return (hi*10) + lo;
}

int div10(int n) {
	if ((n < 0) || (n>=100)) { lax_assert("UNVERIFIED RANGE"); }

	// Verified for 0..99 range out of div10.
	int div10p = (n * 6553)>>16;
	// if (div75p != div75) {
	int count = div10p * 10;
	int rem   = n - count;
	if (rem >= 10)  { div10p++; }
	return div10p;
}

// ==> u8[] Table 0..99 ?
u8 toBCD(u8 value) {
	int d10 = div10(value);		// / 10
	int m10 = value - (d10*10);	// % 10
	return (d10 << 4) | m10;
}

int div75(int n) {
	if ((n < 0) || (n>=450000)) { lax_assert("UNVERIFIED RANGE"); }

	// Verified for 0..449999 range from CD-Rom
	int div75p = (n * 3496)>>18;
	int count = div75p * 75;
	int rem   = n - count;
	if (rem < 0)   { div75p--; }
	if (rem < -75) { div75p--; }
	return div75p;
}

int div60(int n) {
	if ((n < 0) || (n>=6001)) { lax_assert("UNVERIFIED RANGE"); }

	// Verified for 0..6000 range out of div75.
	int div60p = (n * 1092)>>16;
	int count  = div60p * 60;
	int rem    = n - count;
	if (rem >= 60)  { div60p++; }
	return div60p;
}

void fromLBA(int lba, u8* min, u8* sec, u8* frame) {
	if((lba < 0) || (lba >= 450000) /*100 * 60 * 75*/)	{
		*min = 0xFF; *sec = 0xFF; *frame = 0xFF;
	} else {
		int tmpDiv75   = div75(lba);
		int tmpDiv75_60= (tmpDiv75 / 60);

		*min		= tmpDiv75_60;				/* % 100 NOT NEEDED !!!! GARANTEE 0..99 by IF*/
		*sec		= tmpDiv75-(*min*60);		/*tmpDiv75 % 60 <- Avoid another division*/
		*frame		= lba - (tmpDiv75 * 75);	/*lba % 75 <- Again avoid division*/
	}
}

int toLBA(u8 min, u8 sec, u8 frame) { return frame + ((sec + (min*60)) * 75); }

// TODO : CDRom RemoveMedia from DuckStation.

void commandTest				();
void commandInvalid				(u8 errorCode);
void commandGetStatus			();
void commandSetLocation			(int sequ);
void commandPlay				();
void commandReadWithRetry		(BOOL is1Bcommand);
void commandStop				(int sequ);
void commandPause				(int sequ);
void commandInitialize			(int sequ);
void commandMute				();
void commandUnmute				();
void commandSetFilter			();
void commandSetMode				();
void commandGetLocationPlaying	();
void commandSetSession			(int sequ);
void commandGetFirstAndLastTrackNumbers();
void commandGetTrackStart		();
void commandSeek				(BOOL isCDDA);
void commandTestControllerDate	();
void commandGetID				(int sequ);
void commandUnimplemented		(u8 operation, u8 suboperation);
void commandUnimplementedNoSub	(u8 operation);
void commandReadTOC				();
void commandVideoCD				();

u8   ValidateParamSize			(u8 command) {
	int expectParam = 0;
	/*
	{"Sync",       0}, {"Getstat",   0}, {"Setloc", 3}, {"Play",     0}, {"Forward", 0}, {"Backward",0},
	{"ReadN",      0}, {"MotorOn",   0}, {"Stop",   0}, {"Pause",    0}, {"Reset",   0}, {"Mute",    0},
	{"Demute",     0}, {"Setfilter", 2}, {"Setmode",1}, {"Getparam", 0}, {"GetlocL", 0}, {"GetlocP", 0},
	{"SetSession", 1}, {"GetTN",     0}, {"GetTD",  1}, {"SeekL",    0}, {"SeekP",   0}, {"SetClock",0},
	{"GetClock",   0}, {"Test",      1}, {"GetID",  0}, {"ReadS",    0}, {"Init",    0}, {"GetQ",    2},
	{"ReadTOC",    0}, {"VideoCD",   6}, {"Unknown", 0}, {"Unknown", 0},  {"Unknown", 0}, {"Unknown", 0},
	*/
	switch (command) {
	case 2:  expectParam = 3; break;

	case 13:
	case 14:
	case 18:
	case 20:
	case 24: expectParam = 1; break;

	case 31: expectParam = 6; break;

	default: expectParam = 0; break;
	}

	if ((gParamCnt < expectParam) || ((command != 0x3) /*PLAY*/ && (gParamCnt > expectParam))) {
		commandInvalid(ERROR_REASON_INCORRECT_NUMBER_OF_PARAMETERS);
		return 0;
	} else {
		return 1;
	}
}

void IRQCompletePoll() {
	u8 mask = GetEnabledINT();
	SetINT(2);
	if (mask & (1<<1)) { // INT2 -> Bit 1
		SetIRQ();
	}
}

void IRQAckPoll() {
	u8 mask = GetEnabledINT();
	SetINT(3);
	if (mask & (1<<2)) { // INT3 -> Bit 2
		SetIRQ();
	}
}

void IRQErrorPoll() {
	u8 mask = GetEnabledINT();
	SetINT(5);
	if (mask & (1<<4)) { // INT5 -> Bit 4
		SetIRQ();
	}
}

void respStatus_IRQAckPoll_CDDAPlayMode(u8 playmode) {
	if (/*TODO (gDrivePhysicalState != PLAYING) ||*/ !CanReadMedia()) {
		commandInvalid(ERROR_REASON_NOT_READY);
		return;
	}

#if 0
	cdda.playMode = playmode;
#endif


	FifoResponseStatus();
	IRQAckPoll();
}

//0x00
void commandInvalid(u8 errCode) {
	FifoResponse(ssrStatus | 0x1 /*STAT_ERROR BIT*/);	// Source DuckStation <= m_secondary_status.bits | stat_bits (STAT_ERROR (=0x01) here).
														// Source PCSXR
														// Source Avocado
	FifoResponse(errCode);
	IRQErrorPoll();
}

//0x01
void commandGetStatus() {
	FifoResponseStatus();
	IRQAckPoll();
}

/*
	- For each command, simulate l'etat actuel du drive.
	  Et prendre le timing pour simuler.

	- Quand je recois une nouvelle commande, RESET response FIFO.
		- Quand on fait ACK, certaine commande rajoute des reponses en plus.


	LBA => 

*/

RequestSectorFirm() {
	
}

//0x02
void commandSetLocation(int sequ) {

	if (sequ == 0) {
		u8 minute = BCDtoBinary(gParam[0]);
		u8 second = BCDtoBinary(gParam[1]);
		u8 frame  = BCDtoBinary(gParam[2]);

		// Probably AFTER error check.
		ssrStatus &= ~READING; // Not reading.

		RequestSectorFirm(toLBA(minute, second, frame));
		LaunchTimer(TOTIMER(0.2),commandSetLocation,1);
	}


	if (sequ == 1) {
		FifoResponseStatus();
		IRQAckPoll();
	}
}

//0x03
void commandPlay() {
	u8 trackID = 0;

	if (!CanReadMedia()) {
		commandInvalid(ERROR_REASON_NOT_READY);
		return;
	}

	if (gParamCnt) {
		trackID = gParam[0]; 
#if 0
		// TODO Get Track from track ID
		// TODO Get Index(1) from Track
		// drive.lba.current = index->lba;
#endif
	} else {
#if 0
		drive.lba.current = drive.lba.request;
#endif
	}

	ssrStatus |= (READING | PLAYING_CDDA);

#if 0
	counter.report = 33868800 / 75;
#endif
	respStatus_IRQAckPoll_CDDAPlayMode(EPlayMode_Normal);
}

//0x06
void commandReadWithRetry(BOOL is1BCommand) {
	if (!CanReadMedia()) {
		commandInvalid(ERROR_REASON_NOT_READY);
	} else {
		// Logic DuckStation
		/*
			SendACKAndStat();	<=== Do not set the READING FLAG !!!
			if ((!m_setloc_pending || m_setloc_position.ToLBA() == GetNextSectorToBeRead()) &&
				(isReading() || (isSeeking() && m_read_after_seek))) {
				Log_DevPrintf("Ignoring read command with no/same setloc, already reading/reading after seek");
			} else {
				if (IsSeeking())
					UpdatePositionWhileSeeking();
				BeginReading();
			}
		*/

		// Logic based on Tesseract
	#if 0
		drive.seeking = 2 << drive.mode.speed;
		drive.lba.current = drive.lba.request;
	#endif

		ssrStatus |= READING;
		FifoResponseStatus();
		IRQAckPoll();
	}
}

//0x07
void commandMotorOn(int sequ) {
	// Issuing [0x07] MotorOn
	// [0.2  s] < CD IRQ=3, status=0x10 
	// [1.816s] < CD IRQ=2, status=0x12 
	if(sequ == 0) {
		if (ssrStatus & IS_MOTOR_ON) {
			// Motor already on.
			commandInvalid(ERROR_REASON_INCORRECT_NUMBER_OF_PARAMETERS /*0x20 USED AS INVALID PARAMETER COMMAND => MOTOR ALREADY ON.*/);
		} else {
			DRV_SetTargetState(DRIVE_STATE_PAUSE);
			Launch(TOTIMER(0.2), commandMotorOn, 1);
		}
	}

	if (sequ == 1) {
		FifoResponseStatus();
		IRQAckPoll();
	}

	if (sequ == 2) {
		lax_assert("RETURN WHEN MOTOR WENT ON !!!! ");
		// ssrStatus |= IS_MOTOR_ON;
		FifoResponseStatus();
		IRQCompletePoll();
	}
}

//0x08
void commandStop(int sequ) {
	if(sequ == 0) {
		Launch(50000, commandStop, 1);
		FifoResponseStatus();
		IRQAckPoll();
	}
	if (sequ == 1) {
		ssrStatus &= ~PLAYING_CDDA;
		FifoResponseStatus();
		IRQCompletePoll();
	}
}

//0x09
void commandPause(int sequ) {
	if(sequ == 0) {
		if (isSeeking()) {
			// Can't pause during seeking.
			commandInvalid(ERROR_REASON_NOT_READY);
		} else {
			Launch(1000000, commandPause,1);
			ssrStatus &= ~READING;
			FifoResponseStatus();
			IRQAckPoll();
		}
	}

	if(sequ == 1) {
		FifoResponseStatus();
		IRQCompletePoll();
	}
}

//0x0a
void commandInitialize(int sequ) {
	if (sequ == 0) {
		Launch(475000,commandInitialize,1);
#if 0
		drive.mode.cdda       = 0;
		drive.mode.autoPause  = 0;
		drive.mode.report     = 0;
		drive.mode.xaFilter   = 0;
		drive.mode.ignore     = 0;
		drive.mode.sectorSize = 0;
		drive.mode.xaADPCM    = 0;
		drive.mode.speed      = 0;
#endif
		ssrStatus &= ~(READING | SEEKING);
		ssrStatus |= IS_MOTOR_ON;
		FifoResponseStatus();
		IRQAckPoll();
	}

	if (sequ == 1) {
		FifoResponseStatus();
		IRQCompletePoll();
	}
}

//0x0b
void commandMute() {
	audio_mute = 1;

	FifoResponseStatus();
	IRQAckPoll();
}

//0x0c
void commandUnmute() {
	audio_mute = 0;

	FifoResponseStatus();
	IRQAckPoll();
}

//0x0d
void commandSetFilter() {
	gFilterFile			= gParam[0];
	gFilterChannel		= gParam[1];
	FifoResponseStatus();
	IRQAckPoll();
}

//0x0e
void commandSetMode() {
	gDriveMode = gParam[0];
	switch ((gDriveMode>>4) & 3) {
	case 1: gSectorSkip = 0x0C; gSectorLength = 2340; break;
	case 3: gSectorSkip = 0x18; gSectorLength = 2048; break;
	default:gSectorSkip = 0x18; gSectorLength = 2328; break;
	}
	
	FifoResponseStatus();
	IRQAckPoll();
}

//0x0f
void commandGetParam() {
	lax_assert("TODO IMPLEMENT");
/* TODO

	[DuckStation]
    Log_DebugPrintf("CDROM Getparam command");

    m_response_fifo.Push(m_secondary_status.bits);
    m_response_fifo.Push(m_mode.bits);
    m_response_fifo.Push(0);
    m_response_fifo.Push(m_xa_filter_file_number);
    m_response_fifo.Push(m_xa_filter_channel_number);
    SetInterrupt(Interrupt::ACK);
*/
}

//0x10 : To implement, LibCrypt.
/*
 */
void commandGetLocationL() {
	lax_assert("TODO IMPLEMENT");
	/* DuckStation
      if (!m_last_sector_header_valid)
      {
        Log_DevPrintf("CDROM GetlocL command - header invalid, status 0x%02X", m_secondary_status.bits);
        SendErrorResponse(STAT_ERROR, ERROR_REASON_NOT_READY);
      } else {
        Log_DebugPrintf("CDROM GetlocL command - [%02X:%02X:%02X]", m_last_sector_header.minute,m_last_sector_header.second, m_last_sector_header.frame);
        m_response_fifo.PushRange(reinterpret_cast<const u8*>(&m_last_sector_header   ), sizeof(m_last_sector_header   ));
        m_response_fifo.PushRange(reinterpret_cast<const u8*>(&m_last_sector_subheader), sizeof(m_last_sector_subheader));
        SetInterrupt(Interrupt::ACK);
      }
	*/
}

//0x11
void commandGetLocationPlaying() {
  u8 lbaTrackID = 0;
  u8 lbaIndexID = 0;
  u8 relativeMM = 0xFF,relativeSS = 0xFF,relativeFF = 0xFF; // INVALID SETUP
  u8 absoluteMM = 0xFF,absoluteSS = 0xFF,absoluteFF = 0xFF;

	if (!CanReadMedia()) {
		commandInvalid(ERROR_REASON_NOT_READY);
		return;
	}
#if 0
	int lba = drive.lba.current;
	int lbaTrack = 0;
	if(auto trackID = session.inTrack(lba)) {
		lbaTrackID = *trackID;
		if(auto track = session.track(*trackID)) {
			if(auto indexID = track->inIndex(lba)) {
				lbaIndexID = *indexID;
			}
			if(auto index = track->index(1)) {
				lbaTrack = index->lba;
			}
		}
	}
	auto [relativeMinute, relativeSecond, relativeFrame] = CD::MSF::fromLBA(lba - lbaTrack);
	auto [absoluteMinute, absoluteSecond, absoluteFrame] = CD::MSF::fromLBA(lba);

#endif
	FifoResponse(lbaTrackID);
	FifoResponse(lbaIndexID);
	FifoResponse(toBCD(relativeMM));
	FifoResponse(toBCD(relativeSS));
	FifoResponse(toBCD(relativeFF));
	FifoResponse(toBCD(absoluteMM));
	FifoResponse(toBCD(absoluteSS));
	FifoResponse(toBCD(absoluteFF));
	IRQAckPoll();
}

u8 gSession = 0;
//0x12
void commandSetSession(int sequ) {
	if(sequ == 0) {
		if (!CanReadMedia() || isReading() || isPlaying()) {
			commandInvalid(ERROR_REASON_NOT_READY);
		} else if (gSession == 0) {
			commandInvalid(ERROR_REASON_INVALID_ARGUMENT);
		} else {
			Launch(50000,commandSetSession,1);

			gSession = gParam[0];
			if (gSession != 1) {
				lax_assert("Disc::commandSetSession(): session != 1");
			}

			ssrStatus |= SEEKING;

			FifoResponseStatus();
			IRQAckPoll();
		}
	}

	if (sequ == 1) {
		ssrStatus &= ~SEEKING;
		FifoResponseStatus();
		IRQCompletePoll();
	}
}

//0x13
void commandGetFirstAndLastTrackNumbers() {

	if (CanReadMedia()) { // DuckStation
		FifoResponseStatus();
		FifoResponse(toBCD(0 /* TODO Tesseract : session.firstTrack*/)); // Duckstation code : m_reader.GetMedia()->GetFirstTrackNumber()
		FifoResponse(toBCD(0 /*      Tesseract : session.lastTrack */)); //                    m_reader.GetMedia()->GetLastTrackNumber()
		IRQAckPoll();
	} else {
		commandInvalid(ERROR_REASON_NOT_READY);
	}
}

//0x14
void commandGetTrackStart() {
	u8 minute = 0xFF, second = 0xFF; // Invalid setup.
	u8 trackID = gParam[0];

	if (CanReadMedia()) {
		if (trackID > GetMaxTrackCount()) {
			commandInvalid(ERROR_REASON_INVALID_ARGUMENT);
		} else {
			if (!trackID) {
		//		lba = session.leadOut.lba;
			} else {
				// auto track = session.track(trackID)) <--- What if INVALID TRACK ?
				// if(auto index = track->index(1)) { <-- Invalid index ?
				//	lba = index->lba;
				// }
			}
		#if 0

		  auto [minute, second, frame] = CD::MSF::fromLBA(150 + lba);
		#endif
			FifoResponseStatus();
			FifoResponse(toBCD(minute));
			FifoResponse(toBCD(second));
			IRQAckPoll();
		}
	} else {
		commandInvalid(ERROR_REASON_NOT_READY);
	}
}

//0x15 / 0x16
void commandSeek(BOOL isCDDA) {
	/* duckstation
      const bool logical = (m_command == Command::SeekL);
      Log_DebugPrintf("CDROM %s command", logical ? "SeekL" : "SeekP");
      if (IsSeeking())
        UpdatePositionWhileSeeking(); */

	if (CanReadMedia) {
	#if 0
		drive.lba.current = drive.lba.request;
	#endif
		if (isCDDA) {
			ssrStatus &= ~PLAYING_CDDA;
		}

		FifoResponseStatus();
		IRQCompletePoll();
	} else {
		commandInvalid(ERROR_REASON_NOT_READY);
	}
}

//Used in 0x19, direct call for 0x20
void commandTestControllerDate() {
	FifoResponse(0x95);
	FifoResponse(0x05);
	FifoResponse(0x16);
	FifoResponse(0xc1);

	IRQAckPoll();
}

//0x19
void commandTest() {
	u8 operation    = 0x19;
	u8 suboperation = gParam[0];

	switch(suboperation) {
	case 0x20:	commandTestControllerDate	();							break;
	default:	commandUnimplemented		(operation, suboperation);	break;
	}
}

//0x1a
void commandGetID(int sequ) {
	if(sequ == 0) {
		Launch(50000, commandGetID, 1);
		FifoResponseStatus();
		IRQAckPoll();
	}

	if(sequ == 1) {
		u8 specialCase = 0;

		if (ssrStatus & SHELL_OPEN) {
			// Drive Open
			FifoResponse(0x11);
			FifoResponse(0x80);

			
			lax_assert("UNIMPLEMENTED GetID");
#if 0
			IRQCompletePoll ?
			IRQErrorPoll    ?
			postInterrupt(5); // Avocado
#endif
			return;
		} else if (!HasMedia()) {
			// No Disc
			specialCase = 0x40;
		} else if (IsAudioDisc()) {
			// Audio CD
			specialCase = 0x90;
		}

		if(specialCase) {
			// audio or no disc.
			ssrStatus |= ID_ERROR;

			FifoResponseStatus();
			FifoResponse(specialCase);
			FifoResponse(0x00);
			FifoResponse(0x00);
			FifoResponse(0x00);
			FifoResponse(0x00);
			FifoResponse(0x00);
			FifoResponse(0x00);

			IRQErrorPoll();
		} else {
			// Game Disc
			ssrStatus &= ~ID_ERROR;
			FifoResponseStatus();
			FifoResponse(0x00);
			FifoResponse(0x20);
			FifoResponse(0x00);
			FifoResponse('S');
			FifoResponse('C');
			FifoResponse('E');
			// // 0x45 E, 0x41 A, 0x49 I
			FifoResponse(0x40 | SYS_DISC); /* <--- region() == "NTSC-J" / I
				                                "NTSC-U" / A
												"PAL"	 / E */

			IRQCompletePoll();
		}
	}
}

//0x1b, Calls => commandReadWithRetry(true);

//TODO 0x1E
void commandReadTOC() {
	if (CanReadMedia()) {
		lax_assert("UNIMPLEMENTED ReadTOC.");
		/*	DuckStation

			SendACKAndStat();
			m_drive_state = DriveState::ReadingTOC;
			m_drive_event->Schedule(System::GetTicksPerSecond() / 2); // half a second
		*/		
	} else {
		commandInvalid(ERROR_REASON_NOT_READY);
	}
}

void commandUnimplemented(u8 operation, u8 suboperation) {
	lax_assert("UNIMPLEMENTED commandUnimplemented error.");
}

void commandUnimplementedNoSub	(u8 operation) {
	lax_assert("UNIMPLEMENTED commandUnimplemented no sub error.");
}

void commandVideoCD				() {
	lax_assert("UNIMPLEMENTED commandUnimplemented no sub error.");
}

// ----------------------------------------------------------------------------------------------
//   ADPCM Decoding Logic
// ----------------------------------------------------------------------------------------------

u16 PCMbuffL[256];
u16 PCMbuffR[256];
u8  PCMLCnt;
u8  PCMRCnt;

void Ouput44100Hz(u8 isRight, s16 sample) {
	if (isRight) {
		PCMbuffR[PCMRCnt++] = sample;
		if (PCMRCnt >= 256) { lax_assert("REACH END OF PCM BUFFER"); }
	} else {
		PCMbuffL[PCMLCnt++] = sample;
		if (PCMLCnt >= 256) { lax_assert("REACH END OF PCM BUFFER"); }
	}
}

int ringbufL		[0x20];  // Ring buffer.
int ringbufR		[0x20];  // Ring buffer.
s32 previousSamples	[4];

/*	Sector is 2352 byte.
	PCM  :       4 byte per sample @ 44.1 Khz (L/R 16 bit)
	ADPCM:128 x 28 block
*/
u8	last128Byte		[128];
u8  idx128 = 0;
u8  receiveHeader	= 1;
u8  ADPCMblockCount	= 0;
BOOL ADPCM_is18_9Khz = 0;
BOOL ADPCM_isStero   = 0;
BOOL ADPCM_is8Bit    = 0;

u8  sectorType;

enum {
	TOC_DATA_TYPE		= 0,
	PCM_SECTOR_TYPE		= 1,
	DATA_SECTOR_TYPE	= 2,
	ADPCM_SECTOR_TYPE	= 3,
};

u8 LLVol;
u8 LRVol;
u8 RRVol;
u8 RLVol;

// Forward declaration.
void decodeBlock(u8* sectorData, BOOL is18_9Khz, BOOL isStereo, BOOL is8bit, int address);

u8 fetchBytes(u8 amount) {
	// Fetch 16 byte at once.
	u8 base = idx128 & 0x7F;
	u8* p = &last128Byte[base];	// Mod 128
	u8* pE= p + amount;
	while (p<pE) { *p++ = PopInputData(); }
	idx128 += amount;
	return base;
}

u8 gIgnoreSector;

// TODO : Attempt delivery -> update gIgnoreSector
void TransferToData(u8 amount, u8 base, u8* pPCM) {
	// Skip logic is active only during the first 128 bytes...
	// And we do transfer data.
	// => Skippable parts.
	if (amount && (base < gSectorSkip) && (gSectorTransfered < 128)) {
		int skipLocal = gSectorSkip - base;
		if (skipLocal > amount) { skipLocal = amount; }
		amount -= skipLocal;
		pPCM   += skipLocal;
	}
	
	for (int n=0; n < amount; n++) {
		if (gSectorTransfered < gSectorLength) {
			gSectorTransfered++;

			// Not performance optimized, but makes code smaller (test byte by byte if sector can be sent to user)
			if ((!gIgnoreSector) && !IsOutputDataFULL()) { 
				PushOutputData(*pPCM++);					
			} else {
				lax_assert("DATA FIFO OVERFLOW");
			}
		}
	}
}

// Flag to know we started parsing a new sector...
u8 gGetNewSector;

void sendDataOrPCM() {
	if (HasInputData()) {

		PCMLCnt = 0;
		PCMRCnt = 0;

		/*	Audio

			  000h 930h Audio Data (2352 bytes) (LeftLsb,LeftMsb,RightLsb,RightMsb)

			Mode0 (Empty)

			  000h 0Ch  Sync
			  00Ch 4    Header (Minute,Second,Sector,Mode=00h)
			  010h 920h Zerofilled

			Mode1 (Original CDROM)

			  000h 0Ch  Sync
			  --------------------
			  00Ch 4    Header (Minute,Second,Sector,Mode=01h)
			  010h 800h Data (2048 bytes)
			  810h 4    EDC (checksum accross [000h..80Fh])
			  814h 8    Zerofilled
			  81Ch 114h ECC (error correction codes)

			Mode2/Form1 (CD-XA)

			  000h 0Ch  Sync
			  ---------------------------------------------------------------
			  00Ch 4    Header (Minute,Second,Sector,Mode=02h)
			  010h 4    Sub-Header (File, Channel, Submode AND DFh, Codinginfo)
			  014h 4    Copy of Sub-Header
			  018h 800h Data (2048 bytes)
			  818h 4    EDC (checksum accross [010h..817h])
			  81Ch 114h ECC (error correction codes)

			Mode2/Form2 (CD-XA)

			  000h 0Ch  Sync
			  00Ch 4    Header (Minute,Second,Sector,Mode=02h)
			  010h 4    Sub-Header (File, Channel, Submode OR 20h, Codinginfo)
			  014h 4    Copy of Sub-Header
			  018h 914h Data (2324 bytes)
			  92Ch 4    EDC (checksum accross [010h..92Bh]) (or 00000000h if no EDC)

			  010h 4    Sub-Header (File, Channel, Submode OR 20h , Codinginfo)
			  010h 4    Sub-Header (File, Channel, Submode AND DFh, Codinginfo)
			----------------------------------------------------------------------------------
			  
			1st Subheader byte - File Number (FN)
			  0-7 File Number    (00h..FFh) (for Audio/Video Interleave, see below)

			2nd Subheader byte - Channel Number (CN)
			  0-4 Channel Number (00h..1Fh) (for Audio/Video Interleave, see below)
			  5-7 Should be always zero


			3rd Subheader byte - Submode (SM)
			  0   End of Record (EOR) (all Volume Descriptors, and all sectors with EOF)
			  1   Video     ;\Sector Type (usually ONE of these bits should be set)
			  2   Audio     ; Note: PSX .STR files are declared as Data (not as Video)
			  3   Data      ;/
			  4   Trigger           (for application use)
			  5   Form2             (0=Form1/800h-byte data, 1=Form2, 914h-byte data)
			  6   Real Time (RT)
			  7   End of File (EOF) (or end of Directory/PathTable/VolumeTerminator)

			The EOR bit is set in all Volume Descriptor sectors, the last sector (ie. the Volume Descriptor Terminator) additionally has the EOF bit set. Moreover, EOR and EOF are set in the last sector of each Path Table, and last sector of each Directory, and last sector of each File.

			4th Subheader byte - Codinginfo (CI)
			When used for Data sectors:

			  0-7 Reserved (00h)

			When used for XA-ADPCM audio sectors:

			  0-1 Mono/Stereo     (0=Mono, 1=Stereo, 2-3=Reserved)
			  2-2 Sample Rate     (0=37800Hz, 1=18900Hz, 2-3=Reserved)
			  4-5 Bits per Sample (0=Normal/4bit, 1=8bit, 2-3=Reserved)
			  6   Emphasis        (0=Normal/Off, 1=Emphasis)
			  7   Reserved        (0)
			  
		 */


		/*
			TODO : MAKE SURE TRANSFER OF PREVIOUS SECTOR IS COMPLETED BEFORE STARTING A NEW ONE HERE !!!!
			Normaly CPU will transfer/decode fast enough for 1/150 sec ?
		*/

		switch (sectorType) {
		case TOC_DATA_TYPE:
			{
				// trust compiler that we have both the same CPU on each SIDE !
				// and same disc.h for definition !!!
				u8* p  = (u8*)&discInternal;
				// Size of 'struct Disc'
				u8* pE = p + sizeof(struct Disc);

				while (p < pE) { *p++ = PopInputData(); }
			}
			break;
		case DATA_SECTOR_TYPE:
			{
				// Send 8 byte TO DATA FIFO OUT
				u8  base = fetchBytes(8);
				u8* pPCM = last128Byte;
				
				if (gGetNewSector) {
					gGetNewSector	  = 0;
					gSectorTransfered = 0;
					gIgnoreSector     = 0;
				}
				
				if (base < 8) {
					// Keep buffering, do nothing...
				} else {
					u8 amount;
					if (base == 8) {
						// Byte 0..15 loaded.
						
						// From No$ Docs :
						// try_deliver_as_adpcm_sector:
						//	reject if CD-DA AUDIO format			<-- Done by track filtering.
						//	reject if sector isn't MODE2 format
						u8 deliverADPCM = (last128Byte[15] == 0x02);
						//	reject if adpcm_disabled(setmode.6)
						u8 adpcmEnabled = gDriveMode & DRV_XAADPCM;
						
						//=> deliver: send sector to xa-adpcm decoder when passing above cases
						if (deliverADPCM && adpcmEnabled) {
							// We continue to load things into the buffer...
							// Next will be [16..23] with ADPCM type.
							// WARNING : WE MAY BE REVERT TO DATA_SECTOR IF REJECTED...
							amount     = 0;
							sectorType = ADPCM_SECTOR_TYPE;
						} else {
							// Transfer as DATA
							amount = 16;
						}
					} else {
						amount = 8;
						pPCM  += base;
					}

					TransferToData(amount, base, pPCM);
				}
			}
			break;
		case PCM_SECTOR_TYPE:
			{
				if (gDriveMode & DRV_CDDA) {
					// Send 8 byte TO PCM OUT
					u8* pPCM = &last128Byte[fetchBytes(8)];	// Mod 128
					// Read 8 byte, send to SPU.
					for (int n=0; n < 2; n++) {
						Ouput44100Hz(FALSE, pPCM[0] | (pPCM[1]<<8));
						Ouput44100Hz(TRUE , pPCM[2] | (pPCM[3]<<8));
						pPCM += 4;
					}
				} else {
					// [TODO]
				}
			}
			break;
		case ADPCM_SECTOR_TYPE:
			{
				u8 base = fetchBytes(8);
				if (receiveHeader) {
					if (base == 16) {
						//	reject if submode isn't audio+realtime (bit2 and bit6 must be both set)
						u8 subModeOK    = (last128Byte[16] & ((1<<6) | (1<<2))) == ((1<<6)|(1<<2));
						
						//	reject if filter_enabled(setmode.3) AND selected file/channel doesn't match
						u8 filterOK     = (!(gDriveMode & DRV_XAFILTER)) || ((gFilterFile == last128Byte[16]) && (gFilterChannel == last128Byte[17]));
						
						if (filterOK && subModeOK) {
							receiveHeader	= 0;
							ADPCMblockCount	= 0;
							idx128			= 0; // Next start at zero.

							u8 codingInfo  	= last128Byte[19];

							ADPCM_isStero   = codingInfo      & 1;
							ADPCM_is18_9Khz = (codingInfo>>2) & 1;
							ADPCM_is8Bit    = (codingInfo>>4) & 1;
						} else {
							gIgnoreSector   = (gDriveMode & DRV_XAFILTER) && subModeOK;
							
							// Roll back to standard DATA SECTOR, NOT AN ADPCM.
							sectorType = DATA_SECTOR_TYPE;
							// Process the first 24 bytes we have already received...
							TransferToData(24, 0, last128Byte);
						}
					}
				} else {
					// Full ADPCM block of 128 byte !!!
					if (base == 112) {
						// 128 byte -> 
						decodeBlock(last128Byte, ADPCM_is18_9Khz, ADPCM_isStero, ADPCM_is8Bit, 0);
						ADPCMblockCount++;
						if (ADPCMblockCount == 28) {
							ADPCMblockCount = 0;
							receiveHeader   = 1;
						}
					}
				}
			}
			break;
		}

		if (PCMLCnt) {
			if (PCMLCnt != PCMRCnt) { lax_assert("MIX DOES NOT MATCH"); }

			// Update internal volume.
			if (ApplyVolumes()) {
				ResetApplyVolumes();
				LLVol = GetLLVolume();
				LRVol = GetLRVolume();
				RLVol = GetRLVolume();
				RRVol = GetRRVolume();
			}

			// Mixing
			{
				u8 LL,LR,RL,RR;
				if (audio_mute || ((sectorType == ADPCM_SECTOR_TYPE) && MuteADPCM())) {
					LL = LR = RL = RR = 0;
				} else {
					LL = LLVol;
					LR = LRVol;
					RL = RLVol;
					RR = RRVol;
				}

				if (!IsSPUFifoFULL()) {
					for (int n=0; n < PCMLCnt; n++) {
						int sampleL = PCMbuffL[n];
						int sampleR = PCMbuffR[n];

						int outL    = ((sampleL * LLVol) + (sampleR * RLVol)) >> 7;
						int outR    = ((sampleL * LRVol) + (sampleR * RRVol)) >> 7;

						// Clipping, no bit trick/optimization.
						if (outL < -32768) { outL = -32768; }
						if (outR < -32768) { outR = -32768; }
						if (outL >  32767) { outL =  32767; }
						if (outR >  32767) { outR =  32767; }

						PushSPUFIFOL(outL);
						PushSPUFIFOR(outR);
					}
				} else {
					lax_assert("FULL SPU FIFOs.");
				}
			}
		}
	} else {
	/*
		TODO
		if (timeTorequest) {
			disableTimeToRequest();
			RequestSector();
		}
	*/
	}
}

void initDecoderADPCM() {
	for (int n=0; n < 0x20;		n++) { ringbufL       [n]= ringbufR       [n]= 0; }
	for (int n=0; n < 0x4;		n++) { previousSamples[n]= 0; }
}

s16 ZigZagInterpolate(int p, int* ringbuf, const s16* TableX) {
	int sum=0;
    for (int i=1; i < 30; i++) {
		int v = (ringbuf[(p-i) & 0x1F]*TableX[i]);
		// Avoid using / 0x8000 -> slow.
		sum += ((v<=-1) && (v>=-32767)) ? 0 : v >> 15;	// div / 0x8000
	}

	     if (sum < -0x8000) { sum = 0x8000; }
	else if (sum >  0x7FFF) { sum = 0x7FFF; }

	return sum;
}

void OutputXA(u8 isRight, u8 is18_9Khz, s16 sample) {
	static int sixstepL = 6;
	static int pL       = 0;
	static int sixstepR = 6;
	static int pR       = 0;
	
	int countTotal     = 1 + is18_9Khz; // 1 or 2
	
	static const s16 Table1[] = {
		0, // NEVER USED : INDEX 0
		0,
		0,
		0,
		0,
		0,
		-0x0002,
		+0x000A,
		-0x0022,
		+0x0041,
		-0x0054,
		+0x0034,
		+0x0009,
		-0x010A,
		+0x0400,
		-0x0A78,
		+0x234C,
		+0x6794,
		-0x1780,
		+0x0BCD,
		-0x0623,
		+0x0350,
		-0x016D,
		+0x006B,
		+0x000A,
		-0x0010,
		+0x0011,
		-0x0008,
		+0x0003,
		-0x0001,
	};
	
	static const s16 Table2[] = {
		0, // NEVER USED : INDEX 0
		0,
		0,
		0,
		-0x0002,
		0,
		+0x0003,
		-0x0013,
		+0x003C,
		-0x004B,
		+0x00A2,
		-0x00E3,
		+0x0132,
		-0x0043,
		-0x0267,
		+0x0C9D,
		+0x74BB,
		-0x11B4,
		+0x09B8,
		-0x05BF,
		+0x0372,
		-0x01A8,
		+0x00A6,
		-0x001B,
		+0x0005,
		+0x0006,
		-0x0008,
		+0x0003,
		-0x0001,
		0,
	};

	static const s16 Table3[] = {
		0, // NEVER USED : INDEX 0
		0,
		0,
		-0x0001,
		+0x0003,
		-0x0002,
		-0x0005,
		+0x001F,
		-0x004A,
		+0x00B3,
		-0x0192,
		+0x02B1,
		-0x039E,
		+0x04F8,
		-0x05A6,
		+0x7939,
		-0x05A6,
		+0x04F8,
		-0x039E,
		+0x02B1,
		-0x0192,
		+0x00B3,
		-0x004A,
		+0x001F,
		-0x0005,
		-0x0002,
		+0x0003,
		-0x0001,
		0,
		0,
	};
	
	static const s16 Table4[] = {
		0, // NEVER USED : INDEX 0
		0,
		-0x0001,
		+0x0003,
		-0x0008,
		+0x0006,
		+0x0005,
		-0x001B,
		+0x00A6,
		-0x01A8,
		+0x0372,
		-0x05BF,
		+0x09B8,
		-0x11B4,
		+0x74BB,
		+0x0C9D,
		-0x0267,
		-0x0043,
		+0x0132,
		-0x00E3,
		+0x00A2,
		-0x004B,
		+0x003C,
		-0x0013,
		+0x0003,
		0,
		-0x0002,
		0,
		0,
		0,
	};
	
	static const s16 Table5[] = {
		0, // NEVER USED : INDEX 0
		-0x0001,
		+0x0003,
		-0x0008,
		+0x0011,
		-0x0010,
		+0x000A,
		+0x006B,
		-0x016D,
		+0x0350,
		-0x0623,
		+0x0BCD,
		-0x1780,
		+0x6794,
		+0x234C,
		-0x0A78,
		+0x0400,
		-0x010A,
		+0x0009,
		+0x0034,
		-0x0054,
		+0x0041,
		-0x0022,
		+0x000A,
		-0x0001,
		0,
		+0x0001,
		0,
		0,
		0,
	};
	
	static const s16 Table6[] = {
		0, // NEVER USED : INDEX 0
		+0x0002,
		-0x0008,
		+0x0010,
		-0x0023,
		+0x002B,
		+0x001A,
		-0x00EB,
		+0x027B,
		-0x0548,
		+0x0AFA,
		-0x16FA,
		+0x53E0,
		+0x3C07,
		-0x1249,
		+0x080E,
		-0x0347,
		+0x015B,
		-0x0044,
		-0x0017,
		+0x0046,
		-0x0023,
		+0x0011,
		-0x0005,
		0,
		0,
		0,
		0,
		0,
		0,
	};

	static const s16 Table7[] = {
		0, // NEVER USED : INDEX 0
		-0x0005,
		+0x0011,
		-0x0023,
		+0x0046,
		-0x0017,
		-0x0044,
		+0x015B,
		-0x0347,
		+0x080E,
		-0x1249,
		+0x3C07,
		+0x53E0,
		-0x16FA,
		+0x0AFA,
		-0x0548,
		+0x027B,
		-0x00EB,
		+0x001A,
		+0x002B,
		-0x0023,
		+0x0010,
		-0x0008,
		+0x0002,
		0,
		0,
		0,
		0,
		0,
		0,
	};
	
	// Export sample twice if 18.9 Khz...

	int* ringbuf = isRight ? ringbufR : ringbufL;
	int  p       = isRight ? pR       : pL;
	int  sixstep = isRight ? sixstepR : sixstepL;

	for (int count=0; count < countTotal; count++) {

		ringbuf[p & 0x1F] = sample; p++; sixstep--;

		if (sixstep==0) {
			sixstep = 6;
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table1));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table2));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table3));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table4));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table5));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table6));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,ringbuf,Table7));
		}
	}
}

void decodeBlock(u8* sectorData, BOOL is18_9Khz, BOOL isStereo, BOOL is8bit, int address) {
	static const s32 filterPositive[] = {0, 60, 115, 98};
	static const s32 filterNegative[] = {0, 0, -52, -55};
	static const u32 WordsPerBlock    = 28;
	             u32 Blocks           = is8bit ? 4 : 8;

	for(u32 block = 0; block < Blocks; block++) {
		 u8 isRight  = (block & 1);
		 u8 header   = sectorData[address + 4 + block];
		 u8 shift    = (header & 0x0f) > 12 ? 9 : (header & 0x0f);
		 u8 filter   = (header & 0x30) >> 4;
		s32 positive = filterPositive[filter];
		s32 negative = filterNegative[filter];
		/* USE GLOBAL ARRAY FOR BLOCK DECODING.
		int index    = isStereo	? ((block >> 1) * (WordsPerBlock << 1) + isRight)
								: (block * WordsPerBlock);
		 */
		u32 dataPtr  = address + 16;
		u8* secDataP = &sectorData[dataPtr];
		u8* secDataPE= &secDataP[WordsPerBlock];
		
		while (secDataP < secDataPE) {
			u32 data		 = (secDataP[0] << 0) | (secDataP[1] << 8) | (secDataP[2] << 16) | (secDataP[3] << 24);
			u32 nibble		 = is8bit	? ((data >> (block << 3)) & 0xff)
										: ((data >> (block << 2)) & 0x0f);
			s16 sample		 = (s16)(nibble << 12) >> shift;

			s32* previous    = isStereo ? &previousSamples[isRight * 2] : &previousSamples[0];
			s32  tmp         = (s32)sample + ((previous[0] * positive) + (previous[1] * negative) + 32);
			s32 interpolated = ((tmp<0) && (tmp>=-63)) ? 0 : (tmp>>3); // Equiv to signed / 64;
			s32 outSample    = interpolated;

			// clamp to s16 range
				 if (outSample < -0x8000) { outSample = 0x8000; }
			else if (outSample >  0x7FFF) { outSample = 0x7FFF; }

			previous[1]      = previous[0];
			previous[0]      = interpolated;

			if (isStereo) {
				OutputXA	(isRight, is18_9Khz, outSample);
			} else {
				OutputXA	(      0, is18_9Khz, outSample);
				OutputXA	(      1, is18_9Khz, outSample);
			}
			secDataP		+= 4;
		}
	}
}

void decodeADPCM(BOOL is18_9Khz, BOOL isStereo, BOOL is8bit, u8* sectorData) {
	// One sector is 18x128 Bytes.
	const u32 Blocks			= 18;
	const u32 BlockSize			= 128;
	const u32 WordsPerBlock		= 28;
	const u32 SamplesPerBlock	= WordsPerBlock << (is8bit ? 2 : 3);

	
	for(unsigned int block = 0; block < Blocks; block++) {
		// Push to FIFO is done inside...
		decodeBlock(sectorData, is18_9Khz, isStereo, is8bit, 24 + block * BlockSize);
	}
}

void DecodeSectorXA(u8* sectorData) {
	u8 subMode     = sectorData[18];
	// uint1 endOfRecord = subMode.bit(0);
	// uint1 video       = subMode.bit(1);
	// uint1 audio       = subMode.bit(2);
	// uint1 data        = subMode.bit(3);
	// uint1 trigger     = subMode.bit(4);
	// uint1 form2       = subMode.bit(5);
	// uint1 realTime    = subMode.bit(6);
	// uint1 endOfFile   = subMode.bit(7);

	u8 codingInfo  = sectorData[19];
	u8 stereo      = codingInfo      & 1;
	u8 halfSpeed   = (codingInfo>>2) & 1;
	u8 is8Bit      = (codingInfo>>4) & 1;
	// uint1 emphasis    = codingInfo.bit(6);

	decodeADPCM(halfSpeed,stereo,is8Bit, sectorData);
	// monaural = !stereo;
}

u8 internalBusy;
void SetBusyFirm	() { internalBusy = TRUE;  }
void ResetBusyFirm	() { internalBusy = FALSE; }
u8   GetBusyFirm    () { return internalBusy;  }

u8 ResolveSectorType(u32 sectorID) {
	if ((sectorID < gDriveSim.currTrackStartIncluded) || (sectorID >= gDriveSim.currTrackEndExcluded)) {
		// Reset
		gDriveSim.currTrackEndExcluded   = 0;

		struct Track* pT = NULL;
		if (discInternal.trackCount) {
			u8  found = 0;
			u32 start;
			for (int n=1; n <= discInternal.trackCount; n++) {
				pT = &discInternal.tracks[n];
				start = ToUint(&pT->indices[0]);
				if (sectorID >= start) {
					found = 1;
					gDriveSim.currTrackType          = pT->trackType; // 0:Undef, 1:AUDIO
					gDriveSim.currTrackStartIncluded = start;
				} else {
					gDriveSim.currTrackEndExcluded   = start;
					return gDriveSim.currTrackType;
				}
			}
			gDriveSim.currTrackEndExcluded = ToUint(&pT->size) + start;
			if (!found) {
				lax_assert("[SECTOR NOT FOUND IN TOC]");
			}
		} else {
			lax_assert("[NO TRACKS]");
		}
	}
	return gDriveSim.currTrackType/* TODO =>  | IsADPCM ? 1:0  DATA->ADPCM type */;
}

void EvaluateFirmware(u32 clockCount) {
	if (gLatencyResetBusy > 0) {
		gLatencyResetBusy--;
		if (gLatencyResetBusy == 0) {
			ResetBusy();
		}
	}

	u8 opDrv = DRV_Update(clockCount);
	if (opDrv) { // Not
		// Something changed... State / Sector reading / etc...
		if (opDrv & 1) {
			// TODO : ADPCM vs DATA detection...
			sectorType = ResolveSectorType(gDriveSim.currSector);
			gGetNewSector = 1;
			RequestSector(gDriveSim.currSector);

			// TODO : Should work... Execpt that Command ASKING WHERE WE ARE SHOULD RETURN currSector-1.
			//        As we time-out and request only here. I guess the -1 thing should be perfectly fine.
			gDriveSim.currSector++; // ID goes to next.
		}

		if (opDrv & 4) {
			sectorType = TOC_DATA_TYPE;
			RequestSector(0);
		}

		//        0x2 State change
	}

	sendDataOrPCM();

	if (HasNewCommand()) {
		u8 command;
		ResetHasNewCommand();
		gParamCnt = 0;
		command	 = ReadCommand();

		// Pump the parameters locally.
		while (!IsFifoParamEmpty()) {
			// Signal to read from FIFO.
			RequestParam(1);							// TODO : HW Detect transition to pop a SINGLE ITEM, (FIFO READ , NO FTFW !)
			// Read value
			gParam[gParamCnt++] = ReadValueParam();
			RequestParam(0);							// Can be before Read for HW, but software check for flag.
		}

		CDRomLogCommand(command);
		
		gLatencyResetBusy = 1;

		if (ValidateParamSize(command)) {
			switch(command) {
			case 0x00: commandInvalid(ERROR_CODE_INVALID_COMMAND); break;
			case 0x01: commandGetStatus();						break;
			case 0x02: commandSetLocation(0);					break;
			case 0x03: commandPlay();							break;
			case 0x04: respStatus_IRQAckPoll_CDDAPlayMode(EPlayMode_FastForward); /* commandFastForward(); */	break;
			case 0x05: respStatus_IRQAckPoll_CDDAPlayMode(EPlayMode_Rewind     ); /* commandRewind();		 */ break;
			case 0x06: commandReadWithRetry	(FALSE);			break;
			case 0x07: commandMotorOn		(0);				break;
			case 0x08: commandStop			(0);				break;
			case 0x09: commandPause			(0);				break;
			case 0x0a: commandInitialize	(0);				break;
			case 0x0b: commandMute();							break;
			case 0x0c: commandUnmute();							break;
			case 0x0d: commandSetFilter();						break;
			case 0x0e: commandSetMode();						break;
			case 0x0f: commandGetParam();						break;
			case 0x10: commandGetLocationL();					break;
			case 0x11: commandGetLocationPlaying();				break;
			case 0x12: commandSetSession	(0);				break;
			case 0x13: commandGetFirstAndLastTrackNumbers();	break;
			case 0x14: commandGetTrackStart();					break;
			case 0x15: commandSeek(FALSE);						break;
			case 0x16: commandSeek(TRUE);						break;
			case 0x17: commandInvalid(ERROR_CODE_INVALID_COMMAND);		break;  //SetClock
			case 0x18: commandInvalid(ERROR_CODE_INVALID_COMMAND);		break;  //GetClock
			case 0x19: commandTest();							break;
			case 0x1a: commandGetID			(0);				break;
			case 0x1b: commandReadWithRetry(TRUE);				break;
			// 1c Unimplemented.
			// 1d Unimplemented.
			case 0x1e: commandReadTOC();						break;
			case 0x1f: commandVideoCD();						break;
			default: 
				if (command >= 0x20 && command <= 0xFF) {
					commandInvalid(ERROR_CODE_INVALID_COMMAND);
				} else {
					commandUnimplementedNoSub(command);
				}
				break;
			}
		} else {
			commandInvalid(ERROR_REASON_INCORRECT_NUMBER_OF_PARAMETERS);
		}

		CDRomLogResponse();
	}
}

void InitFirmware() {
	initDecoderADPCM();
	DRV_Reset();
	// ADPCM parser.
	idx128			= 0;
	receiveHeader	= 1;
	ADPCMblockCount	= 0;

	LLVol			= 0x80;
	LRVol			= 0;
	RLVol			= 0;
	RRVol			= 0x80;

	audio_mute		= 0;

	gLatencyResetBusy = 0;

	gDriveMode		= 0;
	gSectorSkip		= 0x18; 
	gSectorLength	= 2328;

	/* Not needed.
	ADPCM_is18_9Khz = 0;
	ADPCM_isStero   = 0;
	ADPCM_is8Bit    = 0;
	*/
}

void EvaluateFirmwareEndless() {
	InitFirmware();

	// Infinite loop...
	while (TRUE) {
		EvaluateFirmware(ReadHW_TimerDIV8());
	}
}

#define DEBUG_DRIVE

#ifdef DEBUG_DRIVE

u8 gResponseLogCnt;
u8 gResponseLog[32];

#include <stdio.h>
void CDRomDebug() {
	printf("-----------------------------------------------------\n");
	printf("LID      : %s\n", IsOpen()   ? "OPEN" : "CLOSE");
	printf("HasMedia : %s\n", HasMedia() ? "YES"  : "NO"   );
	// IRQ
	// INT Line State
	// Track, Sector, Drive State, Drive Target
}

void CDRomLogCommand(u8 command) {
	const char* commandName = "[UNDEFINED COMMAND]";
	switch(command) {
	case 0x00: commandName = "commandInvalid";					break;
	case 0x01: commandName = "commandGetStatus";				break;
	case 0x02: commandName = "commandSetLocation";				break;
	case 0x03: commandName = "commandPlay";						break;
	case 0x04: commandName = "commrespStatus_IRQAckPoll_CDDAPlayMode(EPlayMode_FastForward)"; break;
	case 0x05: commandName = "commrespStatus_IRQAckPoll_CDDAPlayMode(EPlayMode_Rewind     )"; break;
	case 0x06: commandName = "commandReadWithRetry(FALSE)";		break;
	case 0x07: commandName = "commandMotorOn";					break;
	case 0x08: commandName = "commandStop";						break;
	case 0x09: commandName = "commandPause";					break;
	case 0x0a: commandName = "commandInitialize";				break;
	case 0x0b: commandName = "commandMute";						break;
	case 0x0c: commandName = "commandUnmute";					break;
	case 0x0d: commandName = "commandSetFilter";				break;
	case 0x0e: commandName = "commandSetMode";					break;
	case 0x0f: commandName = "commandGetParam";					break;
	case 0x10: commandName = "commandGetLocationL";				break;
	case 0x11: commandName = "commandGetLocationPlaying";		break;
	case 0x12: commandName = "commandSetSession";				break;
	case 0x13: commandName = "commandGetFirstAndLastTrackNumbers";	break;
	case 0x14: commandName = "commandGetTrackStart";			break;
	case 0x15: commandName = "commandSeek";						break;
	case 0x16: commandName = "commandSeek";						break;
	case 0x17: commandName = "commandInvalid(SetClock)";		break;  //
	case 0x18: commandName = "commandInvalid(GetClock)";		break;  //GetClock
	case 0x19: commandName = "commandTest";						break;
	case 0x1a: commandName = "commandGetID";					break;
	case 0x1b: commandName = "commandReadWithRetry(TRUE)";		break;
	case 0x1e: commandName = "commandReadTOC";					break;
	case 0x1f: commandName = "commandVideoCD";					break;
	default: 
		break;
	}
	printf("Command [%02x] %s (",command,commandName);
	for (int n=0; n < gParamCnt; n++) {
		if (n != 0) { printf(","); }
		printf("%02x",gParam[n]);
	}
	printf(")\n");

	gResponseLogCnt = 0;
}


void CDRecordRespLog(u8 responseToWrite) {
	gResponseLog[gResponseLogCnt++] = responseToWrite;
}

void CDRomLogResponse() {
	printf( "--> (");
	for (int n=0; n < gResponseLogCnt; n++) {
		if (n != 0) { printf(","); }
		printf("%02x",gResponseLog[n]);
	}
	printf( ")\n");
}
#else

void CDRomLogCommand(u8 command)         {}
void CDRecordRespLog(u8 responseToWrite) {}
void CDRomLogResponse()                  {}
void CDRomDebug() {}

#endif
