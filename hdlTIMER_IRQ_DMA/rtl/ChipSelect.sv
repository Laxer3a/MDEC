/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */


typedef struct packed {
	logic	RAMHIZ;		// Bit 13
	logic	RAM;		// Bit 12
	logic	MemCtrl1;	// Bit 11
	logic	PeriphIO;	// Bit 10
	logic   MemCtrl2;	// Bit 9
	logic   INTCtrl;	// Bit 8
	logic	DMACtrl;	// Bit 7
	logic	TimerCtrl;	// Bit 6
	logic	CDRomCtrl;	// Bit 5
	logic	GPUCtrl;	// Bit 4
	logic	MDECCtrl;	// Bit 3
	logic	SPUCtrl;	// Bit 2
	logic	ExpReg2;	// Bit 1
	logic	BIOS_CS;	// Bit 0
} SChipCS;


module ChipSelect(
	input	[30:0]	 	i_address,
	input	[ 2:0]		REG_RAM_SIZE,		// 0:1MB..7:8MB RAM Size Configuration, independant from REAL CHIP SIZE ! (Perform mirroring, HiZ)
	input   [ 1:0]      PhysicalRAMSize,	// 0:2MB, 1:4MB, 2:6MB, 3:8MB => For MiSTer or other platform to select the amount of DDR memory allocated to the CPU RAM.
	
	input	 [4:0]		i_wdwExp1,
	input	 [4:0]		i_wdwExp2,
	input	 [4:0]		i_wdwExp3,
	input	 [4:0]		i_wdwBIOS,
	input	 [4:0]		i_wdwCDRM,
	input	 [4:0]		i_wdwSPU ,
	
	output  [22:0]		o_ramAddr,			// Allow up to 8 MB. Addr is mirrored, clipped matching specs on input setup.
	
	// Chip Select, include checking KSeg already.
	output  SChipCS 	o_csPins,
	output				o_openBus,
	output				o_busError
);

/*
Fixed
  00000000h 80000000h A0000000h  2048K  Main RAM (first 64K reserved for BIOS)
  1F800000h 9F800000h    --      1K     Scratchpad (D-Cache used as Fast RAM)
  1F801000h 9F801000h BF801000h  8K     I/O Ports
  
Windowed
  1F000000h 9F000000h BF000000h  8192K  Expansion Region 1 (ROM/RAM)
  1F802000h 9F802000h BF802000h  8K     Expansion Region 2 (I/O Ports)
  1FA00000h 9FA00000h BFA00000h  2048K  Expansion Region 3 (SRAM BIOS region for DTL cards)
  1FC00000h 9FC00000h BFC00000h  512K   BIOS ROM (Kernel) (4096K max)
  1F801800h 9F801800h BF801800h         CD-ROM
  1F801C00h 9F801C00h BF801C00h         SPU

  --BIT POSITION--------------------------
  332 2 2222 2222 1111 1111 1100 0000 0000
  109 8 7654 3210 9876 5432 1098 7654 3210
  ----------------------------------------
  MMM x_xxxx xxxx_xxxx xxxx_xxxx xxxx_xxxx
  MMM 1_1111 0vvv_vvvv vvvv_vvvv vvvv_vvvv Expansion Region 1 (v = 8192 KB)
  MMM 1_1111 1000_0000 0010_*vvv vvvv_vvvv Expansion Region 2 (v =    8 KB)
  MMM 1_1111 110v_vvvv vvvv_vvvv vvvv_vvvv Expansion Region 3 (v = 2048 KB)
  MMM 1_1111 1110_0vvv vvvv_vvvv vvvv_vvvv               BIOS (v =  512 KB)
  MMM 1_1111 1000_0000 0001_1000 0000_00vv              CDROM (v =    4  B)
  MMM 1_1111 1000_0000 0001_11vv vvvv_vvvv               BIOS (v =    1 KB)
*/

// If CPU is KUSEG   => Send [30:29] as is
// If CPU is KSEG2   => Send [30:29] != 00 (any value ok)
// If CPU is KSEG1/0 => Send [30:29] = 00
wire validIOs = (i_address[30:29] == 2'b00);

reg [2:0] mskAddr;
reg [2:0] mskRAMSizeSetup;
reg       unlocked;
always @(*) begin
	case (PhysicalRAMSize)
	2'd0   : mskAddr = 3'b001; // 2MB
	2'd1   : mskAddr = 3'b011; // 4MB
	2'd2   : mskAddr = 3'b101; // 6MB
	default: mskAddr = 3'b111; // 8MB
	endcase
	
	case (REG_RAM_SIZE)
	3'd0   : mskRAMSizeSetup = 3'b000;
	3'd1   : mskRAMSizeSetup = 3'b011;
	3'd2   : mskRAMSizeSetup = 3'b000;
	3'd3   : mskRAMSizeSetup = 3'b011;
	3'd4   : mskRAMSizeSetup = 3'b001;
	3'd5   : mskRAMSizeSetup = 3'b111;
	3'd6   : mskRAMSizeSetup = 3'b001;
	default: mskRAMSizeSetup = 3'b111;
	endcase
	
	case (REG_RAM_SIZE)
	3'd0   : unlocked = (i_address[22:20] == 3'b000);		// High 7 MB => LOCKED.
	3'd1   : unlocked = i_address[22]; 						// High 4 MB => LOCKED.
	3'd2   : unlocked = (i_address[22:21] == 2'b00 );		// High 6 MB => LOCKED.
	3'd3   : unlocked = i_address[22]; 						// High 4 MB => LOCKED.
	3'd4   : unlocked = (i_address[22:21] == 2'b00 );		// High 6 MB => LOCKED.
	3'd5   : unlocked = 1'b1;								// No lock for 8 MB.
	3'd6   : unlocked = i_address[22]; 						// High 4 MB => LOCKED.
	default: unlocked = 1'b1;								// No lock for 8 MB.
	endcase
end

wire        ChipsB  		= validIOs & (i_address[28:14] == 15'b1_1111_1000_0000_00);
wire        Chips			= ChipsB & (i_address[13:12]==2'b01); // 1F801 block.
wire        Chips2			= ChipsB & (i_address[13:12]==2'b10); // 1F802 block.
wire        M0      		= (i_address[11: 8] == 4'd0);
wire        M1      		= (i_address[11: 8] == 4'd1);
wire        M8      		= (i_address[11: 8] == 4'd8);
wire        MCDEF   		= (i_address[11:10] == 2'd3);

// [22:20][19:0] : 1MB
/*	  0 = 1MB Memory (+ 7MB Locked)
//    000  xxxx    0
	  1 = 4MB Memory (+ 4MB Locked)
//    0xx  xxxx    1
	  2 = 1MB Memory + 1MB HighZ + 6MB Locked
//    00z  xxxx    2
	  3 = 4MB Memory + 4MB HighZ
//    zxx  xxxx    3
	  4 = 2MB Memory + 6MB Locked                 ;<--- would be correct for PSX
//    00x  xxxx    4
	  5 = 8MB Memory                              ;<--- default by BIOS init
//    xxx  xxxx    5
	  6 = 2MB Memory + 2MB HighZ + 4MB Locked     ;<-- HighZ = Second /RAS
//    0zx  xxxx    6
	  7 = 8MB Memory 
//    xxx  xxxx    7 */
wire internalHiZ			= (i_address[20] & (REG_RAM_SIZE == 3'd2)) 
                            | (i_address[22] & (REG_RAM_SIZE == 3'd3))
                            | (i_address[21] & (REG_RAM_SIZE == 3'd6))							
							;

assign o_ramAddr			= { i_address[22:20] & (mskAddr & mskRAMSizeSetup), i_address[19:0] };
	 
wire   isMemory             = unlocked & validIOs & (i_address[28:23] == 6'b0_0000_0);
assign o_csPins.RAMHIZ		= isMemory & internalHiZ;
assign o_csPins.RAM			= isMemory & !internalHiZ; // [20:0 = 2MB RAM] => Then 2MB Mirrored to 8MB
assign o_csPins.MemCtrl1	= Chips & M0 &((i_address[7:6]==2'b00  ) || (i_address[7:2]==6'b100000));	// 1F8010 _00-1F | 20 -> 24~3F : Exception.
assign o_csPins.PeriphIO	= Chips & M0 & (i_address[7:5]==3'b010 ); // bit 4 = JOY vs SIO
assign o_csPins.MemCtrl2	= Chips & M0 & (i_address[7:2]==6'b011000); 								// 1F8010 _60    Only -> 64~6F : Exception
assign o_csPins.INTCtrl		= Chips & M0 & (i_address[7:3]==5'b01110);									// 1F8010 _70-74 Only -> 78~7F : Exception
assign o_csPins.DMACtrl		= Chips & M0 &  i_address[7]; 												// 1xxx 1F8010 _80~FF
assign o_csPins.TimerCtrl	= Chips & M1 & (i_address[7:6]==2'b00  );									// 1F8011 _00~3F (3X not used but valid),Reject 14x~1Fx
assign o_csPins.CDRomCtrl	= Chips & M8 & (i_address[7:2]==6'd0);										// 1F80180_0~4h, else exception.
assign o_csPins.GPUCtrl		= Chips & M8 & (i_address[7:4]==4'd1) & (i_address[3]==1'b0);				// 1F80181_0~4h, else exception.
assign o_csPins.MDECCtrl	= Chips & M8 & (i_address[7:4]==4'd2) & (i_address[3]==1'b0);				// 1F80182_0~4h, else exception.
assign o_csPins.SPUCtrl		= Chips & MCDEF;
assign o_csPins.BIOS_CS		= validIOs   & (i_address[29:22] == 8'b01_1111_11);	// 512 KB Bios => Then mirrored 4096 KB.
assign o_csPins.ExpReg2  	= Chips2;
// TODO : Expansion Region2 detail, Expansion Region 3

// Error if all pin not set.
assign o_busError			= !(o_csPins.RAMHIZ		
                              | o_csPins.RAM			
                              | o_csPins.MemCtrl1	
                              | o_csPins.PeriphIO	
                              | o_csPins.MemCtrl2	
                              | o_csPins.INTCtrl		
                              | o_csPins.DMACtrl		
                              | o_csPins.TimerCtrl	
                              | o_csPins.CDRomCtrl	
                              | o_csPins.GPUCtrl		
                              | o_csPins.MDECCtrl	
                              | o_csPins.SPUCtrl		
                              | o_csPins.BIOS_CS		
                              | o_csPins.ExpReg2);

endmodule
