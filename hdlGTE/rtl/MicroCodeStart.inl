/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */
6'h0 : retAdr = 9'd0; // NOP
6'h1 : retAdr = 9'd219; // RTPS
6'h2 : retAdr = 9'd269; // MVMVA_Buggy
6'h6 : retAdr = 9'd293; // NCLIP
6'hc : retAdr = 9'd288; // OP
6'h10 : retAdr = 9'd180; // DPCS
6'h11 : retAdr = 9'd212; // INTPL
6'h12 : retAdr = 9'd262; // MVMVA
6'h13 : retAdr = 9'd1; // NCDS
6'h14 : retAdr = 9'd168; // CDP
6'h16 : retAdr = 9'd19; // NCDT
6'h1b : retAdr = 9'd104; // NCCS
6'h1c : retAdr = 9'd158; // CC
6'h1e : retAdr = 9'd62; // NCS
6'h20 : retAdr = 9'd75; // NCT
6'h28 : retAdr = 9'd284; // SQR
6'h29 : retAdr = 9'd205; // DPCL
6'h2a : retAdr = 9'd187; // DPCT
6'h2d : retAdr = 9'd253; // AVSZ3
6'h2e : retAdr = 9'd257; // AVSZ4
6'h30 : retAdr = 9'd232; // RTPT
6'h3d : retAdr = 9'd280; // GPF
6'h3e : retAdr = 9'd276; // GPL
6'h3f : retAdr = 9'd120; // NCCT
default: retAdr = 9'd0; // UNDEF -> MAP TO NOP
