module GPU_DDR
(
    input			clk,
    input			i_nrst,

    // --------------------------------------
    // DIP Switches to control
	input			i_DIP_AllowDither,
	input			i_DIP_ForceDither,
    // --------------------------------------

    output			o_IRQRequest,

	output			o_DMA_REQ,
	input			i_DMA_ACK,
	
	output	[31:0]	o_mydebugCnt,
	output          o_dbg_canWrite,

    // --------------------------------------
	//   CPU Bus
    // --------------------------------------
    input			i_gpuAdrA2, // Called A2 because multiple of 4
    input			i_gpuSel,
    input			i_write,
    input			i_read,
    input  [31:0]	i_cpuDataIn,
    output [31:0]	o_cpuDataOut,
    output 			o_validDataOut,
	
    // --------------------------------------
	//   Avalon MM DDR Bus
    // --------------------------------------
	output [16:0]	o_targetAddr,
	output [ 2:0]	o_burstLength,
	input			i_busyMem,				// Wait Request (Busy = 1, Wait = 1 same meaning)
	output			o_writeEnableMem,		//
	output			o_readEnableMem,		//
	output [63:0]	o_dataMem,
	output [7:0]	o_byteEnableMem,
	input			i_dataValidMem,
	input  [63:0]	i_dataMem
);

//--------------------------------------
// Plumbing between GPU and Memory System
//--------------------------------------
wire clkBus = clk;
wire busy,memwrite,command,dataInValid;
wire [1:0]   commandSize;
wire [14:0]  adr32;
wire [2:0]   subAdr;
wire [15:0]  mask;
wire [255:0] dataIn,dataOut;

gpu	gpu_inst(
    .clk			(clk),
	.i_nrst			(i_nrst),

	.DIP_AllowDither(i_DIP_AllowDither),
	.DIP_ForceDither(i_DIP_ForceDither),

	.IRQRequest		(o_IRQRequest),

	.DMA_REQ		(o_DMA_REQ),
	.DMA_ACK		(i_DMA_ACK),

    // Video output...
	.mydebugCnt		(o_mydebugCnt),
	.dbg_canWrite	(o_dbg_canWrite),

    // --------------------------------------
    // Memory Interface
    // --------------------------------------
	.clkBus			(clkBus),
    .o_command		(command),        // 0 = do nothing, 1 Perform a read or write to memory.
    .i_busy			(busy),           // Memory busy 1 => can not use.
    .o_commandSize	(commandSize),    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    .o_write		(memwrite),
    .o_adr			(adr32),            // 1 MB memory splitted into 32768 block of 32 byte.
    .o_subadr		(subAdr),         // Block of 8 or 4 byte into a 32 byte block.
    .o_writeMask	(mask),

    .i_dataIn		(dataIn),
	.i_dataInValid	(dataInValid),
	.o_dataOut		(dataOut),
	
    // --------------------------------------
	//   CPU Bus
    // --------------------------------------
    .gpuAdrA2		(i_gpuAdrA2), //), // Called A2 because multiple of 4
    .gpuSel			(i_gpuSel),
    .write			(i_write),
    .read			(i_read),
    .cpuDataIn		(i_cpuDataIn),
    .cpuDataOut		(o_cpuDataOut),
    .validDataOut	(o_validDataOut)
);

hdlPSXDDR hdlPSXDDR_Instance (
	// Global Connections
	.i_clk			(clkBus),
	.i_nRst			(i_nrst),
  
	// Client (PSX) Connections
	.i_command		(command),			// 0 = do nothing, 1 = read/write operation
	.i_writeElseRead(memwrite),			// 0 = read, 1 = write
	.i_commandSize	(commandSize),		// 
	.i_targetAddr	(adr32),			// 1 MB memory splitted into 32768 block of 32 byte.
	.i_subAddr		(subAdr),
	.i_writeMask	(mask),
	.i_dataClient	(dataOut),
	.o_busyClient	(busy),
	.o_dataValidClient(dataInValid),	// When 1, PSX makes no request.
	.o_dataClient	(dataIn),

	// DDR (Memory) Connections
	.o_targetAddr	(o_targetAddr	),
	.o_burstLength	(o_burstLength	),
	.i_busyMem		(i_busyMem		),
	.o_writeEnableMem(o_writeEnableMem),
	.o_readEnableMem(o_readEnableMem),
	.o_dataMem		(o_dataMem		),
	.o_byteEnableMem(o_byteEnableMem),
	.i_dataValidMem	(i_dataValidMem	),
	.i_dataMem		(i_dataMem		)
);

endmodule
