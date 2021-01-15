/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

#include "if.h"

// ########################################
// CD PSX Interface
// ########################################
/*
Yes, No$ register order is a real shit-show.

---------------------------------------------------------------
1F801800h - Index/Status Register (Bit0-1 R/W) (Bit2-7 Read Only)
---------------------------------------------------------------
1F801801h.Index0 - Command Register          (W)
1F801801h.Index1 - Sound Map Data Out        (W)
1F801801h.Index2 - Sound Map Coding Info     (W)
1F801801h.Index3 - Audio Volume for Right-CD-Out to Right-SPU-Input (W)

1F801801h.X      - Response Fifo             (R)
---------------------------------------------------------------
1F801802h.Index0 - Parameter Fifo            (W)
1F801802h.Index1 - Interrupt Enable Register (W)
1F801802h.Index2 - Audio Volume for Left -CD-Out to Left-SPU-Input (W)
1F801802h.Index3 - Audio Volume for Right-CD-Out to Left-SPU-Input (W)

1F801802h.X      - Data Fifo - 8bit/16bit    (R)
---------------------------------------------------------------
1F801803h.Index0 - Request Register          (W)
1F801803h.Index1 - Interrupt Flag Register   (R/W)
1F801803h.Index2 - Audio Volume for Left-CD-Out to Right-SPU-Input (W)
1F801803h.Index3 - Audio Volume Apply Changes (by writing bit5=1)

1F801803h.Index0 - Interrupt Enable Register (R)
1F801803h.Index2 - Interrupt Enable Register (R) (Mirror)
1F801803h.Index3 - Interrupt Flag Register   (R) (Mirror)
---------------------------------------------------------------
*/
// ########################################
// PSX INTERFACE
#ifdef __cplusplus
extern "C" {
#endif

	void initExternalWorld();
	u8   CDROM_Read (int adr);
	void CDROM_Write(int adr, u8 v);
	void LogUpdateStatus(u8 out);

#ifdef __cplusplus
}
#endif
// ########################################




// ########################################
// INTERNAL SIMULATED HARDWARE
// ########################################
// ===== 1F801800    R/W
void WriteStatusRegister	(u8 index);
u8   ReadStatusRegister		();

// ########################################

// ===== 1F801801.0  W
void WriteCommand			(u8 command);
// ===== 1F801801.1  W
void WriteSoundMapDataOut	(u8 v);
// ===== 1F801801.2  W
void WriteSoundCodingInfo	(u8 v);
// ===== 1F801801.3  W
void SetR_CDVolToR			(u8 vol);

// ===== 1F801801.x  R
u8   ReadResponse			();

// ########################################

// ===== 1F801802.0  W
void WriteParameter			(u8 param  );
// ===== 1F801802.1  W
void WriteINTEnableReg		(u8 param);
// ===== 1F801802.2  W
void SetL_CDVolToL			(u8 vol);
// ===== 1F801802.3	 W
void SetR_CDVolToL			(u8 vol);

// ===== 1F801802.x  R
// TODO : Want Data bit (1F801803h.Index0.Bit7), then wait until Data Fifo becomes not empty (1F801800h.Bit6), the datablock (disk sector) can be then read from this register.
u8   ReadData				();	// Weird specs from No$. What is this garbage ? We just read 16 bit by having LSB first, whatever that means...

// ########################################

// ===== 1F801803.0  W
void WriteRequestReg		(u8 regBit);
// ===== 1F801803.1  W
void WriteINTFlagReg		(u8 regBit);
// ===== 1F801803.2  W
void SetL_CDVolToR			(u8 vol);
// ===== 1F801803.3  W
void WriteApplyChange		(u8 vol);

// ===== 1F801803.0  R
//     + 1F801803.2  R
u8   ReadINTEnableReg		();
// ===== 1F801803.1  R
//     + 1F801803.3  R
u8   ReadINTFlagReg			();
