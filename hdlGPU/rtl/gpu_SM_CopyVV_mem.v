module gpu_SM_CopyVV_mem
(
    input               i_clk,
    input               i_rst,

    //
    // GPU Registers / Stencil Cache / FIFO Side
    //
    input               i_activate,
    output              o_CopyInactiveNextCycle,
    output              o_active,

    // Registers
    input               GPU_REG_CheckMaskBit,
    input               GPU_REG_ForcePixel15MaskSet,
    input signed [11:0] RegX0,
    input signed [11:0] RegY0,
    input signed [11:0] RegX1,
    input signed [11:0] RegY1,    
    input   [10:0]      RegSizeW,
    input   [9:0]       RegSizeH,
    
    // Stencil [Read]
    output              o_stencilReadSig,
    output  [14:0]      o_stencilReadAdr,
    input   [15:0]      i_stencilReadValue16,
    // Stencil [Write]
    output   [15:0]     o_stencilWriteMask16,
    output   [15:0]     o_stencilWriteValue16,
    output              o_stencilFullMode,
    output              o_stencilWriteSig,
    output  [14:0]      o_stencilWriteAdr,

    // -----------------------------------
    // [DDR SIDE]
    // -----------------------------------

    output              o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input               i_busy,           // Memory busy 1 => can not use.
    output   [1:0]      o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output              o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]      o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]      o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]      o_writeMask,

    input  [255:0]      i_dataIn,
    input               i_dataInValid,    
    output [255:0]      o_dataOut
);

// Delay acivate so that all signals are valid in the same cycle
reg  activate_q;
wire busy_w;

always @ (posedge i_clk)
if (i_rst)
    activate_q <= 1'b0;
else
    activate_q <= i_activate;

gpu_mem_vramvram
u_core
(
     .clk_i(i_clk)
    ,.rst_i(i_rst)

    ,.req_valid_i(activate_q)
    ,.req_src_x_i({{4{RegX0[11]}}, RegX0})
    ,.req_src_y_i({{4{RegY0[11]}}, RegY0})
    ,.req_dst_x_i({{4{RegX1[11]}}, RegX1})
    ,.req_dst_y_i({{4{RegY1[11]}}, RegY1})
    ,.req_sizex_i({5'b0, RegSizeW})
    ,.req_sizey_i({6'b0, RegSizeH})
    ,.req_set_mask_i(GPU_REG_ForcePixel15MaskSet)
    ,.req_use_mask_i(GPU_REG_CheckMaskBit)
    ,.req_accept_o()

    ,.busy_o(busy_w)
    ,.done_o(o_CopyInactiveNextCycle)

    ,.stencil_rd_req_o(o_stencilReadSig)
    ,.stencil_rd_addr_o(o_stencilReadAdr)
    ,.stencil_rd_value_i(i_stencilReadValue16)

    ,.stencil_wr_req_o(o_stencilWriteSig)
    ,.stencil_wr_addr_o(o_stencilWriteAdr)
    ,.stencil_wr_mask_o(o_stencilWriteMask16)
    ,.stencil_wr_value_o(o_stencilWriteValue16)

    ,.gpu_command_o(o_command)
    ,.gpu_size_o(o_commandSize)
    ,.gpu_write_o(o_write)
    ,.gpu_addr_o(o_adr)
    ,.gpu_sub_addr_o(o_subadr)
    ,.gpu_write_mask_o(o_writeMask)
    ,.gpu_data_out_o(o_dataOut)
    ,.gpu_busy_i(i_busy)
    ,.gpu_data_in_valid_i(i_dataInValid)
    ,.gpu_data_in_i(i_dataIn)    
);

assign o_active = busy_w | activate_q;

assign o_stencilFullMode = 1'b1;

endmodule