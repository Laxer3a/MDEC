/*
 * Handles all CD-ROM registers and functions.
 */
#include "if.h"

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


// -------------------------------------------------------------
//   Drive Physical simulation
// -------------------------------------------------------------

enum {
	DRIVE_STATE_STOPPED	= 1,	// MOTOR DOWN
	DRIVE_STATE_SPINDOWN= 2,	// MOTOR DOWN

	DRIVE_STATE_SPINUP  = 3,	// All motor up
	DRIVE_STATE_SEEK    = 4,
	DRIVE_STATE_READ    = 5,
	DRIVE_STATE_PAUSE   = 6,
};


typedef struct DriveSimulator_ {
	// Timing simulation in ms ? microsec ? sysclk ?
	// PB : 32 bit counter loop must be handled.
	u32 currCycle;

	u8 currState;
	u8 lastState;
	u8 targetState;

	u8 doubleSpeed;
	u8 reqSector;		// Number of sector to 

	u32 currSector;
	u32 targetSector;

	// HW Counter related internal timers.
	s32 transitionTime;
	s32 newSectorTime;
} DriveSimulator;

DriveSimulator gDriveSim;

void DRV_SetTargetState		(u8 drv_state) {
	// Stop, Seek, Read, Pause (all other are intermediate states)
	if ((drv_state == DRIVE_STATE_SPINUP) || (drv_state == DRIVE_STATE_SPINDOWN)) {
		lax_assert("Forbidden state target");
	}
}

void DRV_Reset				() {
	gDriveSim.currCycle	  = 0;
	gDriveSim.currState   = gDriveSim.lastState = DRIVE_STATE_STOPPED;
	gDriveSim.doubleSpeed = 0;
	gDriveSim.reqSector   = 0;
	gDriveSim.currSector  = 0;
	gDriveSim.targetSector= 0;
	gDriveSim.transitionTime = 0;
	gDriveSim.newSectorTime  = 0;
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
	gDriveSim.lastState= oldState;

	if (transitionTime != 0) {
		s32 newTransition = transitionTime-deltaTdiv8;
		u8  completed     = (newTransition <= 0);
		transitionTime	  = newTransition;

		switch (gDriveSim.targetState) {
		case DRIVE_STATE_STOPPED:
			switch (gDriveSim.currState) {
			// --------------------------------------
			case DRIVE_STATE_STOPPED:
				// Do nothing.
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINDOWN:
				if (completed) { gDriveSim.currState = DRIVE_STATE_STOPPED; }
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINUP:
			case DRIVE_STATE_SEEK:
			case DRIVE_STATE_PAUSE:
			case DRIVE_STATE_READ:
				gDriveSim.currState  = DRIVE_STATE_SPINDOWN;
				transitionTime      += ((gDriveSim.doubleSpeed ? 50700000 : 33800000)*2 / 8); // 2 seconds to slow down at 1x, 3 sec at 2x.
				break;
			}
			// --------------------------------------
			break;

		// TRANSITION STATE, THEY ARE NOT POSSIBLE AS TARGETS.
		// case DRIVE_STATE_SPINDOWN:
		// case DRIVE_STATE_SPINUP:

		case DRIVE_STATE_SEEK:
			switch (gDriveSim.currState) {
			// --------------------------------------
			case DRIVE_STATE_STOPPED:
				// => SPINUP
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINDOWN:
				// => SPINUP
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINUP:
				// => SEEK
				break;
			// --------------------------------------
			case DRIVE_STATE_SEEK:
				// => Another SEEK ? Cancel current one ?
				break;
			// --------------------------------------
			case DRIVE_STATE_PAUSE:
			case DRIVE_STATE_READ:
				// => SEEK
				break;
			}
			// --------------------------------------
			break;
		case DRIVE_STATE_PAUSE:
			switch (gDriveSim.currState) {
			// --------------------------------------
			case DRIVE_STATE_STOPPED:
				// => SPINUP
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINDOWN:
				// => SPINUP
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINUP:
				// => SEEK
				break;
			// --------------------------------------
			case DRIVE_STATE_SEEK:
				// => PAUSE (reached sector ?)
				break;
			// --------------------------------------
			case DRIVE_STATE_PAUSE:
				// Do nothing.
				break;
			case DRIVE_STATE_READ:
				// => PAUSE
				break;
			}
			// --------------------------------------
			break;
		case DRIVE_STATE_READ:
			switch (gDriveSim.currState) {
			// --------------------------------------
			case DRIVE_STATE_STOPPED:
				// => SPINUP
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINDOWN:
				// => SPINUP
				break;
			// --------------------------------------
			case DRIVE_STATE_SPINUP:
				// => SEEK
				break;
			// --------------------------------------
			case DRIVE_STATE_SEEK:
				// => READ (reached sector ?)
				break;
			// --------------------------------------
			case DRIVE_STATE_PAUSE:
				// => READ
				break;
			case DRIVE_STATE_READ:
				// Do nothing.
				break;
			}
			// --------------------------------------
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
	work |= (gDriveSim.currState != oldState) ? 2 : 0;

	//
	// Fetching sectors...
	//
	if (gDriveSim.currState == DRIVE_STATE_READ) {
		s32 newSectorTime = gDriveSim.newSectorTime;
		newSectorTime -= deltaTdiv8;
		if (newSectorTime <= 0) {
			newSectorTime += gDriveSim.doubleSpeed ? 28166 : 56333; // 1/75th of a second approx. (1 sector)
			gDriveSim.currSector++;
			gDriveSim.reqSector++;
			work |= 1; // Fetching sector.
		}
	}

	gDriveSim.currCycle = newTimer;

	return work;
}

// TODO Macro later.
u8   DRV_ReadNextSector		()					{ return gDriveSim.reqSector;  } // Number of sector to fetch
void DRV_SetTargetSector	(u32 targetSector)	{ gDriveSim.targetSector = targetSector; }
void DRV_SetSpeedMode		(u8 speed)			{ gDriveSim.doubleSpeed = speed-1; } // Works only for x1 / x2.
u8   DRV_GetCurrentState	()					{ return gDriveSim.currState;  }
u8   DRV_StateChanged		()					{ return gDriveSim.currState != gDriveSim.lastState; }
u32  DRV_GetCurrentSector	()					{ return gDriveSim.currSector; }

// PB : what if Spinup/Spindown ? (Neither reading/playing)
u8 isSeeking() {
	return (DRV_GetCurrentState() == DRIVE_STATE_SEEK);
}

u8 isReading() {
	return (DRV_GetCurrentState() == DRIVE_STATE_READ);
}

u8 isPlaying() {
	return (DRV_GetCurrentState() == DRIVE_STATE_READ) /* TODO : && PLAYING_CDDA */;
}


// -------------------------------------------------------------


enum {
	ERROR_REASON_NOT_READY						= 0x80,
	ERROR_CODE_INVALID_COMMAND					= 0x40,
	ERROR_REASON_INCORRECT_NUMBER_OF_PARAMETERS = 0x20,
	ERROR_REASON_INVALID_ARGUMENT				= 0x10,
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

u8 gDriveState;

u8 maxTrackCount; // TODO

// PSX SIDE PIN, ADR PIN ???
// Later replace with IO pin reading.
// --- Input

typedef void (*sequenceF)(int);

void Launch(int delay, sequenceF fct, int param) {
	// TODO Register call back function when we reach a certain state or delay... (Param may change)
}

u8 CanReadMedia() { return IsOpen() || (!HasMedia());}

void FifoResponse(u8 responseToWrite) {
	WriteResponse(responseToWrite);
}

u8 checkParam(u8 paramCount) {
	// TODO Send response when wrong number of parameters.

	return (paramCount != gParamCnt); // True if not valid.
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

// TODO : CDRom RemoveMedia from DuckStation.

void commandTest				();
void commandInvalid				(u8 errorCode);
void commandGetStatus			();
void commandSetLocation			();
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

	if (gParamCnt < expectParam) {
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
	FifoResponse(0x10 | 0x1 /*STAT_ERROR BIT*/);	// Source DuckStation <= m_secondary_status.bits | stat_bits (STAT_ERROR (=0x01) here).
													// Source PCSXR
													// Source Avocado
	FifoResponse(errCode);
	IRQErrorPoll();
}

//0x01
void commandGetStatus() {
	if (checkParam(0)) { return; }

	FifoResponseStatus();
	if (CanReadMedia()) { // DuckStation
		ssrStatus &= ~SHELL_OPEN; // Shell Close;
	}
	IRQAckPoll();
}

/*
	- For each command, simulate l'etat actuel du drive.
	  Et prendre le timing pour simuler.

	- Quand je recois une nouvelle commande, RESET response FIFO.
		- Quand on fait ACK, certaine commande rajoute des reponses en plus.


	LBA => 

*/

//0x02
void commandSetLocation() {

	u8 minute = BCDtoBinary(gParam[0]);
	u8 second = BCDtoBinary(gParam[1]);
	u8 frame  = BCDtoBinary(gParam[2]);

	if (checkParam(3)) { return; }

	// Probably AFTER error check.
	ssrStatus &= ~READING; // Not reading.
#if 0
	drive.lba.request = CD::MSF(minute, second, frame).toLBA();
#endif

	FifoResponseStatus();
	IRQAckPoll();
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
	counter.report = 33'868'800 / 75;
#endif
	respStatus_IRQAckPoll_CDDAPlayMode(EPlayMode_Normal);
}

//0x06
void commandReadWithRetry(BOOL is1BCommand) {
	if (!CanReadMedia) {
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
	if(sequ == 0) {
		if (ssrStatus & IS_MOTOR_ON) {
			// Motor already on.
			commandInvalid(ERROR_REASON_INCORRECT_NUMBER_OF_PARAMETERS /*0x20 USED AS INVALID PARAMETER COMMAND => MOTOR ALREADY ON.*/);
		} else {
			Launch(50'000, commandMotorOn, 1);
			FifoResponseStatus();
			IRQAckPoll();
		}
	}
	if (sequ == 1) {
		ssrStatus |= IS_MOTOR_ON;
		FifoResponseStatus();
		IRQCompletePoll();
	}
}

//0x08
void commandStop(int sequ) {
	if(sequ == 0) {
		Launch(50'000, commandStop, 1);
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
			Launch(1'000'000, commandPause,1);
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
		Launch(475'000,commandInitialize,1);
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
#if 0
	audio.mute = 1;
#endif

	FifoResponseStatus();
	IRQAckPoll();
}

//0x0c
void commandUnmute() {
#if 0
	audio.mute = 0;
#endif
	FifoResponseStatus();
	IRQAckPoll();
}

//0x0d
void commandSetFilter() {
#if 0
	cdxa.filter.file	= fifo.parameter.read(0);
	cdxa.filter.channel = fifo.parameter.read(0);
#endif
	FifoResponseStatus();
	IRQAckPoll();
}

//0x0e
void commandSetMode() {
	if (checkParam(1)) { return; }

	gDriveState = gParam[0];
	FifoResponseStatus();
	IRQAckPoll();
}

//0x0f
void commandGetParam() {
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
	// TODO
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
			Launch(50'000,commandSetSession,1);

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

	if (checkParam(1)) { return; }

	if (CanReadMedia()) {
		if (trackID > maxTrackCount) {
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

	if (checkParam(1)) { return; }

	switch(suboperation) {
	case 0x20:	commandTestControllerDate	();							break;
	default:	commandUnimplemented		(operation, suboperation);	break;
	}
}

//0x1a
void commandGetID(int sequ) {
	if(sequ == 0) {
		Launch(50'000, commandGetID, 1);
		FifoResponseStatus();
		IRQAckPoll();
	}

	if(sequ == 1) {
		u8 specialCase = 0;

		if (gDriveState & SHELL_OPEN) {
			// Drive Open
			FifoResponse(0x11);
			FifoResponse(0x80);
#if 0
			IRQCompletePoll ?
			IRQErrorPoll    ?
			postInterrupt(5); // Avocado
#endif
			return;
		} else if ( FALSE /*trackCount == 0 TODO */) {
			// No Disc
			specialCase = 0x40;
		} else if ( FALSE /* isAudioDisc() TODO */ ) {
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
	// TODO
}

void commandUnimplementedNoSub	(u8 operation) {
	// TODO
}

void commandVideoCD				() {
	// TODO
}

// ----------------------------------------------------------------------------------------------
//   ADPCM Decoding Logic
// ----------------------------------------------------------------------------------------------

void Ouput44100Hz(u8 isRight, s16 sample) {
	// TODO
}

s16 gOutput			[28<<8]; // Thats a LOT for STACK !!!
int ringbuf			[0x20];  // Ring buffer.
s32 previousSamples	[4];

void initDecoderADPCM() {
	for (int n=0; n < 0x20;		n++) { ringbuf        [n]= 0; }
	for (int n=0; n < 0x4;		n++) { previousSamples[n]= 0; }
	for (int n=0; n < (28<<8);	n++) { gOutput		  [n]= 0; }
}

s16 ZigZagInterpolate(int p, const s16* TableX) {
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
	static int sixstep = 6;
	static int p       = 0;
	
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

	for (int count=0; count < countTotal; count++) {
		ringbuf[p & 0x1F] = sample; p++; sixstep--;
		
		if (sixstep==0) {
			sixstep = 6;
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table1));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table2));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table3));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table4));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table5));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table6));
			Ouput44100Hz(isRight, ZigZagInterpolate(p,Table7));
		}
	}
}

void decodeBlock(u8* sectorData, BOOL is18_9Khz, BOOL isStereo, BOOL is8bit, s16* output, int address) {
	static const s32 filterPositive[] = {0, 60, 115, 98};
	static const s32 filterNegative[] = {0, 0, -52, -55};
	static const u32 WordsPerBlock    = 28;
	             u32 Blocks           = is8bit ? 4 : 8;

	for(int block = 0; block < Blocks; block++) {
		 u8 isRight  = (block & 1);
		 u8 header   = sectorData[address + 4 + block];
		 u8 shift    = (header & 0x0f) > 12 ? 9 : (header & 0x0f);
		 u8 filter   = (header & 0x30) >> 4;
		s32 positive = filterPositive[filter];
		s32 negative = filterNegative[filter];
		int index    = isStereo	? ((block >> 1) * (WordsPerBlock << 1) + isRight)
								: (block * WordsPerBlock);

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

			output[index]    = (s16)outSample;

			if (isStereo) {
				index		+= 2;
				OutputXA	(isRight, is18_9Khz, outSample);
			} else {
				index		+= 1;
				OutputXA	(      0, is18_9Khz, outSample);
				OutputXA	(      1, is18_9Khz, outSample);
			}
			secDataP		+= 4;
		}
	}
}

void decodeADPCM(BOOL is18_9Khz, BOOL isStereo, BOOL is8bit, u8* sectorData) {
	const u32 Blocks			= 18;
	const u32 BlockSize			= 128;
	const u32 WordsPerBlock		= 28;
	const u32 SamplesPerBlock	= WordsPerBlock << (is8bit ? 2 : 3);

	
	for(unsigned int block = 0; block < Blocks; block++) {
		// Push to FIFO is done inside...
		decodeBlock(sectorData, is18_9Khz, isStereo, is8bit, gOutput, 24 + block * BlockSize);
		/*
		for(auto sample : output) {
		  if(!samples.full()) samples.write(sample);
		}*/
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

void EvaluateFirmware() {

	if (DRV_Update(ReadHW_TimerDIV8())) {
		// Something changed... State / Sector reading / etc...
	}

	// TODO : Decompressed ADPCM etc...

	if (HasNewCommand()) {
		u8 command;
		SetBusy();
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

		if (ValidateParamSize(command)) {
			switch(command) {
			case 0x00: commandInvalid(ERROR_CODE_INVALID_COMMAND); break;
			case 0x01: commandGetStatus();						break;
			case 0x02: commandSetLocation();					break;
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
	} else {
		ResetBusy();
	}
}

void InitFirmware() {
	initDecoderADPCM();
	DRV_Reset();
}

void EvaluateFirmwareEndless() {
	InitFirmware();

	// Infinite loop...
	while (TRUE) {
		EvaluateFirmware();
	}
}
