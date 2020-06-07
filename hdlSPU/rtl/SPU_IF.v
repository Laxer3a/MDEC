module SPU_IF(
	 input			i_clk
	,input			n_rst
	
	// CPU Side
	// CPU can do 32 bit read/write but they are translated into multiple 16 bit access.
	// CPU can do  8 bit read/write but it will receive 16 bit. Write will write 16 bit. (See No$PSX specs)
	,input			SPUCS	// We have only 11 adress bit, so for read and write, we tell the chip is selected.
	
	// No ACK/REQ on CPU SIDE
	,input			SRD
	,input			SWRO
	,input	[ 9:0]	addr			// Here Sony spec is probably in HALF-WORD (9 bit), we keep in BYTE for now. (10 bit)
	,input	[15:0]	dataIn
	,output	[15:0]	dataOut
	,output			dataOutValid	// Always 1 cycle after SRD.
	,output			SPUINT
	
	// CPU DMA stuff.
	,input			SPUDACK
	,output			SPUDREQ

	/* Use when SDRAM will be available
	// RAM Side
	,output	[17:0]	o_adrRAM
	,output			o_dataReadRAM
	,output			o_dataWriteRAM
	,input	[15:0]	i_dataInRAM
	,output	[15:0]	o_dataOutRAM
	*/
	
	// From CD-Rom, serial stuff in original HW,
	// 
	,input  signed [15:0]	CDRomInL
	,input  signed [15:0]	CDRomInR
	,input			inputL
	,input			inputR
	
	// Audio DAC Out
	,output [15:0]	AOUTL
	,output [15:0]	AOUTR
	,output 		VALIDOUT
);

// ----------------------------------------------
// Connection & Memory if we are using [INTERNAL RAM]
// ----------------------------------------------

wire	[17:0]	o_adrRAM;
wire			o_dataReadRAM;
wire			o_dataWriteRAM;
wire	[15:0]	i_dataInRAM;
wire	[15:0]	o_dataOutRAM;

wire	[1:0]	SPURAMByteSel = 2'b11;
SPU_RAM SPU_RAM_FPGAInternal
(
	.i_clk			(i_clk),
	.i_re			(o_dataReadRAM),
	.i_we			(o_dataWriteRAM),
	.i_wordAddr		(o_adrRAM),
	.i_data			(o_dataOutRAM),
	.i_byteSelect	(SPURAMByteSel),
	
	.o_q			(i_dataInRAM)
);

// ----------------------------------------------
//   SPU Core
// ----------------------------------------------

SPU	SPU_instance(
	.i_clk			(i_clk),
	.n_rst			(n_rst),
	
	.SPUCS			(SPUCS),
	
	// No ACK/REQ on CPU SIDE
	.SRD			(SRD),
	.SWRO			(SWRO),
	.addr			(addr),
	.dataIn			(dataIn),
	.dataOut		(dataOut),
	.dataOutValid	(dataOutValid),
	.SPUINT			(SPUINT),
	
	// CPU DMA stuff.
	.SPUDREQ		(SPUDREQ),
	.SPUDACK		(SPUDACK),

	.o_adrRAM		(o_adrRAM),
	.o_dataReadRAM	(o_dataReadRAM),
	.o_dataWriteRAM	(o_dataWriteRAM),
	.i_dataInRAM	(i_dataInRAM),
	.o_dataOutRAM	(o_dataOutRAM),

	.CDRomInL		 (CDRomInL),
	.CDRomInR        (CDRomInR),
	.inputL          (inputL),
	.inputR          (inputR),

	.AOUTL           (AOUTL),
	.AOUTR           (AOUTR),
	.VALIDOUT        (VALIDOUT)
);

endmodule
