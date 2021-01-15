/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

#ifndef IF_CDRom_Firmware
#define IF_CDRom_Firmware

typedef unsigned char uint8_t;
typedef unsigned char u8;
typedef unsigned int  u32;
typedef int           s32;
typedef short         s16;
typedef unsigned short u16;

typedef u8			  BOOL;

#define FALSE		(0)
#define TRUE		(1)

#ifdef __cplusplus
extern "C" {
#endif

// ==================================================
//   MAIL BOX TO PSX SIDE
// ==================================================

BOOL	HasNewCommand		();
void	ResetHasNewCommand	();
u8		ReadCommand			();

BOOL	IsFifoParamEmpty	();
u8		ReadValueParam		();
void	RequestParam		(BOOL readOnOff);

u8		GetEnabledINT		();
void	SetINT				(int id);
void	SetIRQ				();

void	SetBusy				();
void	ResetBusy			();

void	WriteResponse		(u8 resp);

u32		ReadHW_TimerDIV8	(); // 33.8 Mhz / 8.

BOOL	ApplyVolumes		();
BOOL	MuteADPCM			();
void	ResetApplyVolumes	(); // Or can autocancel on read ?
u8		GetLLVolume			();
u8		GetLRVolume			();
u8		GetRLVolume			();
u8		GetRRVolume			();

// Note : We will push data at regular pace.
// Audio is always 44.1 Khz and we push 588 sample per sector.
// A FIFO of 1024 or 2048 item should be just perfect and FULL should be never be reached.
// A single OR'ed FULL is ok for both fifo, the read / write will be slightly shifted in time by SPU and INT CPU.
// But we don't care much...
BOOL	IsSPUFifoFULL		();
void	PushSPUFIFOL		(s16 leftAudio);
void	PushSPUFIFOR		(s16 rightAudio);

BOOL	IsOutputDataFULL	();
BOOL	IsOutputDataEMPTY	(); // Probably not needed here but...
void	PushOutputData		(u8 value);

// ==================================================
//   EXT CPU SIDE to INT CPU SIDE
// ==================================================

BOOL	IsOpen				();
BOOL	HasMedia			();

BOOL	HasInputData		();
u8		PopInputData		();

void	RequestSector		(u32 sectorID);

// ==================================================
// Function to run the firmware in sim.
// ==================================================

void	InitPorting				();
void	InitFirmware			();
void	EvaluateFirmware		(u32 clockCount);
void	EvaluateFirmwareEndless	();

// Simulate Outside stuff
void	SetMediaPresent			(BOOL hasMedia);
void	SetOpen					(BOOL openLid );
// TODO : InputData

void	lax_assert			(const char* str);

#ifdef __cplusplus
}
#endif

#endif
