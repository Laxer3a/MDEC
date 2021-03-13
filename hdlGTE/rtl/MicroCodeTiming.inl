/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright (C) 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */
6'h1 : retCount = 6'd13; // RTPS
6'h2 : retCount = 6'd7; // MVMVA_Buggy
6'h6 : retCount = 6'd7; // NCLIP
6'hc : retCount = 6'd5; // OP
6'h10 : retCount = 6'd7; // DPCS
6'h11 : retCount = 6'd7; // INTPL
6'h12 : retCount = 6'd7; // MVMVA
6'h13 : retCount = 6'd18; // NCDS
6'h14 : retCount = 6'd12; // CDP
6'h16 : retCount = 6'd43; // NCDT
6'h1b : retCount = 6'd16; // NCCS
6'h1c : retCount = 6'd10; // CC
6'h1e : retCount = 6'd13; // NCS
6'h20 : retCount = 6'd29; // NCT
6'h28 : retCount = 6'd4; // SQR
6'h29 : retCount = 6'd7; // DPCL
6'h2a : retCount = 6'd18; // DPCT
6'h2d : retCount = 6'd4; // AVSZ3
6'h2e : retCount = 6'd5; // AVSZ4
6'h30 : retCount = 6'd21; // RTPT
6'h3d : retCount = 6'd4; // GPF
6'h3e : retCount = 6'd4; // GPL
6'h3f : retCount = 6'd38; // NCCT
default: retCount = 6'd0; // UNDEF -> MAP TO NOP
