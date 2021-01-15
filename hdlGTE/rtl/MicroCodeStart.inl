/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */
6'h0 : retAdr = 8'd0; // NOP
6'h1 : retAdr = 8'd173; // RTPS
6'h2 : retAdr = 8'd205; // MVMVA_Buggy
6'h6 : retAdr = 8'd228; // NCLIP
6'hc : retAdr = 8'd224; // OP
6'h10 : retAdr = 8'd133; // DPCS
6'h11 : retAdr = 8'd166; // INTPL
6'h12 : retAdr = 8'd201; // MVMVA
6'h13 : retAdr = 8'd2; // NCDS
6'h14 : retAdr = 8'd123; // CDP
6'h16 : retAdr = 8'd15; // NCDT
6'h1b : retAdr = 8'd78; // NCCS
6'h1c : retAdr = 8'd116; // CC
6'h1e : retAdr = 8'd52; // NCS
6'h20 : retAdr = 8'd59; // NCT
6'h28 : retAdr = 8'd220; // SQR
6'h29 : retAdr = 8'd159; // DPCL
6'h2a : retAdr = 8'd140; // DPCT
6'h2d : retAdr = 8'd197; // AVSZ3
6'h2e : retAdr = 8'd199; // AVSZ4
6'h30 : retAdr = 8'd180; // RTPT
6'h3d : retAdr = 8'd216; // GPF
6'h3e : retAdr = 8'd212; // GPL
6'h3f : retAdr = 8'd88; // NCCT
default: retAdr = 8'd0; // UNDEF -> MAP TO NOP
