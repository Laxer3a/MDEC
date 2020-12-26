#include "externalWorld.h"

// ########################################
//    FROM PSX
// ########################################

/*  ---------------------------------------------------
		[PART DONE IN HW]
	    extern variables are used by CDRom - Firmware
	---------------------------------------------------   */

// HW REGISTER/STORAGE
// ----------------------------------------------------------
u8 gIndex = 0;					// Index Selector for registers.
// ----------------------------------------------------------
// [Mixing Volumes]
// IGNORE THOSE IN SOFTWARE. DONE PROPERLY IN HW ALREADY
u8 mixLtoR;
u8 mixLtoL;
u8 mixRtoL;
u8 mixRtoR;

u8 paramFIFO[16];
u8 paramRDIndex = 0;
u8 paramWRIndex = 0;
u8 isParamFull() { return (((paramWRIndex+1 & 0xF)) == paramRDIndex) ? 1 : 0; }

u8 respFIFO[16];
u8 respRDIndex = 0;
u8 respWRIndex = 0;
u8 isRespEmpty() { return (respWRIndex == respRDIndex) ? 1:0 ; }
u8 isRespFull()  { return (((respWRIndex+1 & 0xF)) == respRDIndex) ? 1 : 0; }

u8 dataFIFO[8192];
u16 dataRDIndex = 0;
u16 dataWRIndex = 0;
u8 isDataEmpty() { return (dataWRIndex == dataRDIndex) ? 1:0 ; }
u8 isDataFull()  { return (((dataWRIndex+1 & 0x1FFF)) == dataRDIndex) ? 1 : 0; }

// ----------------------------------------------------------
extern u8 gCommand;				// Command written
extern u8 gHasNewCommand;		// Flag saying PSX has written the command.

extern u8 gIsFifoParamEmpty;	// Parameter in FIFO
extern u8 gRequestParam;		// Request Signal to read FIFO
extern u8 gValueParam;			// Value read

extern u8 gEnabledInt;			// Enabled Interrupt
extern u8 gINTSetBit;			// Set INT.

extern u8 gDataWrite;			// Data to write to FIFO Data
extern u8 gRequDataWrite;		// Signal Write to FIFO

extern u8 gSMEN;				// Not used yet
extern u8 gBFWR;				// Not used yet
extern u8 gBFRD;				// Not used yet
// ----------------------------------------------------------

void initExternalWorld() {
	gIsFifoParamEmpty	= 1;
	gIndex				= 0;
	paramRDIndex		= 0;
	paramWRIndex		= 0;
}

// TODO : Size of Audio FIFO ???
// One sector decoded ?

u8 updateStatus() {
	// TODO : BIT 2 => AudioFIFO + flag(empty/full) + when playing...
	// TODO : BIT 7

	// No$ : Bit3,4,5 are bound to 5bit counters; ie. the bits become true at specified amount of reads/writes, and thereafter once on every further 32 reads/writes.
	// No$ : The response Fifo is a 16-byte buffer, most or all responses are less than 16 bytes, after reading the last used byte (or before reading anything when the response is 0-byte long), Bit5 of the Index/Status register becomes zero to indicate that the last byte was received.
    //       When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes, and does then restart at the first response byte (that, without receiving a new response, so it'll always return the same 16 bytes, until a new command/response has been sent/received).
	// => 32 byte ? 16 byte ? Ridiculous !

	u8 isParamFULL = isParamFull();

	return 0
	//	 | BIT 2 TODO		 
		 | (gIsFifoParamEmpty << 3)
		 | ((isParamFULL ? /*Reverse !*/0:1)<<4)
		 | ((isRespEmpty() ? /*Reverse !*/0:1)<<5)
		 | ((isDataEmpty() ? /*Reverse !*/0:1)<<6)
	//	 | BIT 7 TODO 
	;
}

void CDROM_Write(int adr, u8 v) {
	switch (adr & 3) {
	case 0:
		WriteStatusRegister(v); return;
	case 1:
		switch (gIndex) {
		case 0: WriteCommand		(v); break;
		case 1: WriteSoundMapDataOut(v); break;
		case 2: WriteSoundCodingInfo(v); break;
		case 3: SetR_CDVolToR		(v); break;
		}
		break;
	case 2:
		switch (gIndex) {
		case 0: WriteParameter		(v); break;
		case 1: WriteINTEnableReg	(v); break;
		case 2: SetL_CDVolToL		(v); break;
		case 3: SetR_CDVolToL		(v); break;
		}
		break;
	case 3:
		switch (gIndex) {
		case 0: WriteRequestReg		(v); break;
		case 1: WriteINTFlagReg		(v); break;
		case 2: SetL_CDVolToR		(v); break;
		case 3: WriteApplyChange	(v); break;
		}
		break;
	}
}

u8   CDROM_Read (int adr) {
	switch (adr & 3) {
	case 0: return ReadStatusRegister	();
	case 1: return ReadResponse			();
	case 2: return ReadData				(); 
	case 3:
		if (gIndex == 0 || gIndex == 2) { return ReadINTEnableReg(); }
		else							{ return ReadINTFlagReg	 (); }
	}
}

// ########################################
// ===== 1F801800    R/W
void WriteStatusRegister(u8 index)	{ gIndex = index & 3;             }
u8   ReadStatusRegister ()			{ return updateStatus() | gIndex; }

// ########################################

// ===== 1F801801.0  W
void WriteCommand		(u8 command_) {
	gCommand		= command_;		// Command Written.
	gHasNewCommand	= 1;			// New command was written.
}

// ===== 1F801801.1  W
void WriteSoundMapDataOut(u8 v) {
	// Data Audio Input path from outside instead of CD-ROM.
	lax_assert("NOT IMPLEMENTED.");
}

// ===== 1F801801.2  W
void WriteSoundCodingInfo(u8 v) {
	/* TODO
		THE XA ADPCM SETUP IS DONE HERE ?
		NOT BY SECTOR FORMAT / HEADER IN XA data ????
	 */ 
	u8 gIsStereo;
	u8 gIs18_9Khz;
	u8 gIs8BitSmp;
	u8 gIsEmphasis;

	gIsStereo  = v & (1<<0);
	gIs18_9Khz = v & (1<<2);
	gIs8BitSmp = v & (1<<4);
	gIsEmphasis= v & (1<<6);

	lax_assert("NOT IMPLEMENTED.");
}

// ===== 1F801801.3  W
void SetR_CDVolToR		(u8 vol) {
	mixRtoR = vol;
}

// ===== 1F801801.x  R
u8   ReadResponse		() {
	u8 v = respFIFO[respRDIndex];
	if (!isRespEmpty()) {
		respRDIndex	= (respRDIndex + 1) & 0xF;
	}

	return v;
}

void EXT_WriteResponse(u8 value) {
	if (!isRespFull()) {
		respFIFO[respWRIndex]	= value;
		respWRIndex				= (respWRIndex + 1) & 0xF;
		// None for now : gIsFifoRespEmpty		= 0;
	}
}

// ########################################

// ===== 1F801802.0  W
void WriteParameter		(u8 param  ) {
	// Done by HW.
	if (!isParamFull()) {
		paramFIFO[paramWRIndex]	= param;
		paramWRIndex			= (paramWRIndex + 1) & 0xF;
		gIsFifoParamEmpty		= 0;
	}
}

u8 EXT_ReadParameter() {
	// Real HW will detect transition req 0->1 to create a flag.
	// CPU will just set a pin 0->1 then 1->0 when completed.
	if (!gIsFifoParamEmpty && gRequestParam) {
		gValueParam		= paramFIFO[paramRDIndex];
		paramRDIndex	= (paramRDIndex + 1) & 0xF;
		gIsFifoParamEmpty=(paramRDIndex == paramWRIndex);
	}

	return gValueParam;
}

// ===== 1F801802.1  W
void WriteINTEnableReg	(u8 param) {
	gEnabledInt = param & 0x1F;
}
// ===== 1F801802.2  W
void SetL_CDVolToL		(u8 vol) {
	mixLtoL = vol;
}
// ===== 1F801802.3  W
void SetR_CDVolToL		(u8 vol) {
	mixRtoL = vol;
}

// ===== 1F801802.x  R
u8   ReadData			() {
// TODO : Want Data bit (1F801803h.Index0.Bit7), then wait until Data Fifo becomes not empty (1F801800h.Bit6), the datablock (disk sector) can be then read from this register.
	// Weird specs from No$. What is this ? We just read 16 bit by having LSB first, whatever that means...

	u8 v = dataFIFO[dataRDIndex];
	if (!isDataEmpty()) {
		dataRDIndex++;
		if (dataRDIndex >= 2352) { dataRDIndex = 0; }
	}

	return v;
}

void EXT_WriteDataFIFO() {
	// Done by HW.
	// Detect transition with 
	if (!isDataFull()) {
		dataFIFO[dataWRIndex]	= gDataWrite;
		gRequDataWrite          = 0;
		dataWRIndex				= (dataWRIndex + 1);
		if (dataWRIndex >= 2352) { dataWRIndex = 0; }
	}
}

// ########################################

// ===== 1F801803.0  W
void WriteRequestReg	(u8 regBit ) {
	gSMEN = (regBit>>5) & 1;
	gBFWR = (regBit>>6) & 1;
	gBFRD = (regBit>>7) & 1;
}

// ===== 1F801803.1  W

void WriteINTFlagReg	(u8 regBit) {
	// ACK to zero, if bit were set...
	gINTSetBit &= (~regBit & 0x1F);
}

// ===== 1F801803.2  W
void SetL_CDVolToR		(u8 vol) {
	mixLtoR = vol;
}

// ===== 1F801803.3  W
void WriteApplyChange	(u8 vol) {
	// Done in HW, ignore here.
}

// ===== 1F801803.0  R
//     + 1F801803.2  R
u8   ReadINTEnableReg   () {
	return gEnabledInt | (7<<5);
}

// ===== 1F801803.1  R
//     + 1F801803.3  R
u8   ReadINTFlagReg		() {
	static const READY_BIT    = 1<<0;
	static const COMPLETE_BIT = 1<<1;
	static const ACK_BIT      = 1<<2;
	static const END_BIT      = 1<<3;
	static const ERROR_BIT    = 1<<4;

    u8 flags = 0;
	switch (gINTSetBit) {
	case 0x01: flags = 1; break; // READY_BIT
	case 0x02: flags = 2; break; // COMPLETE_BIT
	case 0x04: flags = 3; break; // ACK_BIT
	case 0x08: flags = 4; break; // END_BIT
	case 0x10: flags = 5; break; // ERROR_BIT
	default :
		lax_assert("INVALID !!!!");
		break;
	}

	u8 err = (gINTSetBit & ERROR_BIT)>>4;
	u8 end = (gINTSetBit & END_BIT  )>>3;

	return flags | (err<<4) | (end<<3) | (7<<5);
}

#include <stdio.h>
void lax_assert(const char* str) {
	printf(str);
	while (1) {
	}
}
