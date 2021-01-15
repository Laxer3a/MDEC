/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module GPU_DDR
(
    input			clk,
    input			i_nrst,

    // --------------------------------------
    // DIP Switches to control
	input			i_DIP_AllowDither,
	input			i_DIP_ForceDither,
	input			i_DIP_Allow480i,
    // --------------------------------------

    output			o_IRQRequest,

	// WRITE/UPLOAD : Outside->GPU
	// - GPU Request data on REQ
	// - Data valid on ACK.
	// GPU->Outside
	// - Data valid on REQ.
	// - DMA Validate the value and requires the next one. with ACK.
	//
	// NOTE : DMA Controller MUST ignore REQ pin and NOT ISSUE ACK when not active.
	output          gpu_m2p_dreq_i,
	input           gpu_m2p_valid_o,
	input [ 31:0]   gpu_m2p_data_o,
	output          gpu_m2p_accept_i,

	output           gpu_p2m_dreq_i,
	output           gpu_p2m_valid_i,
	output  [ 31:0]  gpu_p2m_data_i,
	input            gpu_p2m_accept_o,
	
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
	//   Display Controller
    // --------------------------------------
	input			i_gpuPixClk,
	output			o_HBlank,
	output			o_VBlank,
	output			o_HSync,
	output			o_VSync,
	output			o_DotClk,
	output			o_DotEnable,
	output [9:0]	o_HorizRes,
	output [8:0]	o_VerticalRes,
	output [9:0]	o_DisplayBaseX,
	output [8:0]	o_DisplayBaseY,
	output			o_IsInterlace,
	output			o_CurrentField,
	
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
	.DIP_Allow480i	(i_DIP_Allow480i),

	.IRQRequest		(o_IRQRequest),

	.gpu_m2p_dreq_i		(gpu_m2p_dreq_i),
	.gpu_m2p_valid_o	(gpu_m2p_valid_o),
	.gpu_m2p_data_o		(gpu_m2p_data_o),
	.gpu_m2p_accept_i	(gpu_m2p_accept_i),
                         
	.gpu_p2m_dreq_i		(gpu_p2m_dreq_i),
	.gpu_p2m_valid_i	(gpu_p2m_valid_i),
	.gpu_p2m_data_i		(gpu_p2m_data_i),
	.gpu_p2m_accept_o	(gpu_p2m_accept_o),

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
	//   Display Controller
    // --------------------------------------
	.i_gpuPixClk	(i_gpuPixClk),
	.o_HBlank		(o_HBlank),
	.o_VBlank		(o_VBlank),
	.o_HSync		(o_HSync),
	.o_VSync		(o_VSync),
	.o_DotClk		(o_DotClk),
	.o_DotEnable	(o_DotEnable),
	.o_HorizRes		(o_HorizRes),
	.o_VerticalRes	(o_VerticalRes),
	.o_DisplayBaseX	(o_DisplayBaseX),
	.o_DisplayBaseY	(o_DisplayBaseY),
	.o_IsInterlace	(o_IsInterlace),
	.o_CurrentField	(o_CurrentField),
	
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
