class VSPU_IF; // Help 

#include "../../../rtl/obj_dir/VSPU_IF.h"
#include "VCScanner.h"

#define MODULE mod
#define SCAN   pScan

// ----------
// TRICK WITH MACRO TO REGISTER THE MEMBERS OF THE VERILATED INSTANCE INTO MY VCD SCANNER...
// ----------

#undef VL_IN
#undef VL_OUT
#undef VL_SIG
#undef VL_SIGA
#undef VL_IN8
#undef VL_OUT8
#undef VL_SIG8
#undef VL_IN16
#undef VL_OUT16
#undef VL_SIG16
#undef VL_IN64
#undef VL_OUT64
#undef VL_SIG64
#undef VL_SIGW

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
#define VL_SIGW(NAME,size,s2,storageSize,depth)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME,depth, (((u8*)& MODULE ->## NAME[1]) - ((u8*)& MODULE ->## NAME[0])));

void registerVerilatedMemberIntoScanner(VSPU_IF* mod, VCScanner* pScan) {
    VL_IN8(i_clk,0,0);
    VL_IN8(n_rst,0,0);
    VL_IN8(SPUCS,0,0);
    VL_IN8(SRD,0,0);
    VL_IN8(SWRO,0,0);
    VL_OUT8(dataOutValid,0,0);
    VL_OUT8(SPUINT,0,0);
    VL_IN8(SPUDACK,0,0);
    VL_OUT8(SPUDREQ,0,0);
    VL_IN8(inputL,0,0);
    VL_IN8(inputR,0,0);
    VL_OUT8(VALIDOUT,0,0);
    VL_IN16(addr,9,0);
    VL_IN16(dataIn,15,0);
    VL_OUT16(dataOut,15,0);
    VL_IN16(CDRomInL,15,0);
    VL_IN16(CDRomInR,15,0);
    VL_OUT16(AOUTL,15,0);
    VL_OUT16(AOUTR,15,0);
    
    // LOCAL SIGNALS
    // Internals; generally not touched by application code
    // Begin mtask footprint  all: 
    VL_SIG8(SPU_IF__DOT__i_clk,0,0);
    VL_SIG8(SPU_IF__DOT__n_rst,0,0);
    VL_SIG8(SPU_IF__DOT__SPUCS,0,0);
    VL_SIG8(SPU_IF__DOT__SRD,0,0);
    VL_SIG8(SPU_IF__DOT__SWRO,0,0);
    VL_SIG8(SPU_IF__DOT__dataOutValid,0,0);
    VL_SIG8(SPU_IF__DOT__SPUINT,0,0);
    VL_SIG8(SPU_IF__DOT__SPUDACK,0,0);
    VL_SIG8(SPU_IF__DOT__SPUDREQ,0,0);
    VL_SIG8(SPU_IF__DOT__inputL,0,0);
    VL_SIG8(SPU_IF__DOT__inputR,0,0);
    VL_SIG8(SPU_IF__DOT__VALIDOUT,0,0);
    VL_SIG8(SPU_IF__DOT__o_dataReadRAM,0,0);
    VL_SIG8(SPU_IF__DOT__o_dataWriteRAM,0,0);
    VL_SIG8(SPU_IF__DOT__SPURAMByteSel,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__i_clk,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__i_re,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__i_we,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__i_byteSelect,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__readByteSelect_reg,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__readByteSelect_reg1,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__readByteSelect_reg2,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_RAM_FPGAInternal__DOT__readByteSelect_reg3,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__i_clk,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__n_rst,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SPUCS,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SRD,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SWRO,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__dataOutValid,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SPUINT,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SPUDREQ,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SPUDACK,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__o_dataReadRAM,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__o_dataWriteRAM,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__inputL,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__inputR,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__VALIDOUT,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__SPUMemWRSel,2,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__writeSPURAM,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__readFIFO,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isFIFOFull,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__emptyFifo,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isFIFOHasData,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__fifo_level,5,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__internalWrite,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__internalRead,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__reg_SPUEnable,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__reg_SPUNotMuted,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__reg_NoiseFrequShift,3,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__reg_NoiseFrequStep,3,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__negNoiseStep,3,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isD8,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isD80_DFF,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isChannel,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__channelAdr,4,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isDMAXferWR,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isDMAXferRD,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__dataTransferBusy,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__dataTransferReadReq,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__dataTransferWriteReq,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__dataTransferRDReq,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__writeFIFO,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__updateVoiceADPCMAdr,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__updateADSRState,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__updateADSRVolReg,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__clearKON,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__nextAdsrState,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__internalReadPipe,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__incrXFerAdr,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_KON,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_PMON,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_EON,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_NON,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_AdsrState,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currVoice6Bit,5,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currVoice,4,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__voiceCounter,4,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isLastCycle,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__ctrl44Khz,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__side22Khz,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_shift,3,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__currV_filter,2,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__voiceIncrement,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__decodeSample,2,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__updatePrev,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__loadPrev,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__adpcmSubSample,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__check_Kevent,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__zeroIndex,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__idxBuff,3,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__setEndX,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__setAsStart,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isRepeatADPCMFlag,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isNotEndADPCMBlock,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__storePrevVxOut,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__ctrlSendOut,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__clearSum,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__readSPU,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__updateVoiceADPCMPos,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__updateVoiceADPCMPrev,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isVoice1,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isVoice3,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__reverbCnt,7,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__sideAReg,3,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__sideBReg,4,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__minus2,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__selB,1,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__accAdd,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isRight,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isFIFOWR,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__kickFifoRead,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__pipeReadFIFO,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__nextNewBlock,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__nextNewLine,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__isNullADSR,0,0);
    VL_SIG8(SPU_IF__DOT__SPU_instance__DOT__newSampleReady,0,0);
}

