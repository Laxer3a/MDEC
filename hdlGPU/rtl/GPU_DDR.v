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
	input			i_DIP_ForceInterlaceField,
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
	
//	output	[31:0]	o_mydebugCnt,
//	output	[15:0]	dbg_commmandCount,
	output          o_dbg_canWrite,
	output			o_dbg_error,
	output	[6:0]	o_dbg_busy,
	output [14:0]   o_adrPrefetch,

    // --------------------------------------
	//   CPU Bus
    // --------------------------------------
    input	[1:0]	i_gpuAdrA,
    input			i_gpuSel,
    input			i_write,
    input			i_read,
    input  [31:0]	i_cpuDataIn,
    output [31:0]	o_cpuDataOut,
    output 			o_validDataOut,
	
    // --------------------------------------
	//   Display Controller
    // --------------------------------------
	/*
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
	*/
	// [ULTRA STUFF DISPLAY]
    // GPU -> Display
    output [  9:0]  display_res_x_o,
    output [  8:0]  display_res_y_o,
    output [  9:0]  display_x_o,
    output [  8:0]  display_y_o,
    output          display_interlaced_o,
    output          display_pal_o,
    // Display -> GPU
    input           display_field_i,
    input           display_hblank_i,
    input           display_vblank_i,
	
    // --------------------------------------
	//   GPU Direct 256 bit mem IF
    // --------------------------------------
    output           o_command,        		// 0 = do nothing, 1 Perform a read or write to memory.
    input            i_busy,           		// Memory busy 1 => can not use.
    output   [1:0]   o_commandSize,    		// 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           o_write,          		// 0=READ / 1=WRITE 
    output [ 14:0]   o_adr,            		// 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   o_subadr,         		// Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   o_writeMask,

    input  [255:0]   i_dataIn,
    input            i_dataInValid,
    output [255:0]   o_dataOut
);

//--------------------------------------
// Plumbing between GPU and Memory System
//--------------------------------------
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
	.DIP_ForceInterlaceField(i_DIP_ForceInterlaceField),

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
//	.mydebugCnt		(o_mydebugCnt),
//	.dbg_commmandCount(dbg_commmandCount),
	.dbg_canWrite	(o_dbg_canWrite),
	.dbg_error		(o_dbg_error),
	.dbg_busy		(o_dbg_busy),


	.o_adrPrefetch	(o_adrPrefetch),

    // --------------------------------------
    // Memory Interface
    // --------------------------------------
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
	/*
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
	*/
    .display_res_x_o		(display_res_x_o),
    .display_res_y_o		(display_res_y_o),
    .display_x_o			(display_x_o),
    .display_y_o			(display_y_o),
    .display_interlaced_o	(display_interlaced_o),
    .display_pal_o			(display_pal_o),
    .display_field_i		(display_field_i),
    .display_hblank_i		(display_hblank_i),
    .display_vblank_i		(display_vblank_i),
	
    // --------------------------------------
	//   CPU Bus
    // --------------------------------------
    .gpuAdr			(i_gpuAdrA), 
    .gpuSel			(i_gpuSel),
    .write			(i_write),
    .read			(i_read),
    .cpuDataIn		(i_cpuDataIn),
    .cpuDataOut		(o_cpuDataOut),
    .validDataOut	(o_validDataOut)
);

`ifndef UNDEFINED_VALUE

assign o_command = command;
assign busy		 = i_busy;
assign o_commandSize = commandSize;
    
assign o_write	= memwrite;
assign o_adr    = adr32;
assign o_subadr = subAdr;
assign o_writeMask = mask;

assign dataIn = i_dataIn;
assign dataInValid = i_dataInValid;
assign o_dataOut = dataOut;

`else

gpu_mem_cache bitFatCache (
    // Inputs
    .clk_i					(clk),
    .rst_i					(!i_nrst),
    .gpu_command_i			(command),
    .gpu_size_i				(commandSize),
    .gpu_write_i			(memwrite),
    .gpu_addr_i				(adr32),
    .gpu_sub_addr_i         (subAdr),
    .gpu_write_mask_i       (mask),
    .gpu_data_out_i         (dataOut),
    .gpu_busy_o				(busy),
    .gpu_data_in_valid_o    (dataInValid),
    .gpu_data_in_o          (dataIn),
	

    // Outputs
    .mem_busy_i             (i_busy),
    .mem_data_in_valid_i    (i_dataInValid),
    .mem_data_in_i          (i_dataIn),
    .mem_command_o          (o_command),
    .mem_size_o             (o_commandSize),
    .mem_write_o            (o_write),
    .mem_addr_o             (o_adr),
    .mem_sub_addr_o         (o_subadr),
    .mem_write_mask_o       (o_writeMask),
    .mem_data_out_o         (o_dataOut)
);

`endif

/*
hdlPSXDDR hdlPSXDDR_Instance (
	// Global Connections
	.i_clk			(clk),
	.i_nRst			(i_nrst),
  
	// Client (PSX) Connections
	.i_command		(s_command),			// 0 = do nothing, 1 = read/write operation
	.i_writeElseRead(s_memwrite),			// 0 = read, 1 = write
	.i_commandSize	(s_commandSize),		// 
	.i_targetAddr	(s_adr32),			// 1 MB memory splitted into 32768 block of 32 byte.
	.i_subAddr		(s_subAdr),
	.i_writeMask	(s_mask),
	.i_dataClient	(s_dataOut),
	.o_busyClient	(s_busy),
	.o_dataValidClient(s_dataInValid),	// When 1, PSX makes no request.
	.o_dataClient	(s_dataIn),

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
*/

endmodule
