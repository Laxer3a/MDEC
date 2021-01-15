/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

#include "if.h"

BOOL	HasNewCommand		() {
}

void	ResetHasNewCommand	() {
}

u8		ReadCommand			() {
}

BOOL	IsFifoParamEmpty	() {
	
}

u8		ReadValueParam		() {
}

void	RequestParam		(BOOL readOnOff) {
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
}

