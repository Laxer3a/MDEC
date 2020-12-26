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

BOOL	IsOpen				();
BOOL	HasMedia			();

u32		ReadHW_TimerDIV8	(); // 33.8 Mhz / 8.


//
// Run the firmware.
//
void	InitFirmware			();
void	EvaluateFirmware		();
void	EvaluateFirmwareEndless	();


void	lax_assert			(const char* str);

#ifdef __cplusplus
}
#endif

#endif
