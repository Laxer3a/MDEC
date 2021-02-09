module gpu_SM_CopyVC_mem(
    input                    i_clk,
    input                    i_rst,
    
    input                    i_activate,
    output                    o_exitSig,    // End at next cycle
    output                    o_active,
    
    input    signed [11:0]    RegX0,
    input    signed [11:0]    RegY0,
    input            [10:0]    RegSizeW,
    input           [ 9:0]    RegSizeH,

    // FIFO
    input                    i_canPush,
    input                    i_outFIFO_empty,
    output                    o_writeFIFOOut,
    output    [31:0]            o_pairPixelToCPU,
    
    // -----------------------------------
    // [DDR SIDE]
    // -----------------------------------

    output                   o_command,        
    input                    i_busy,           
    output   [1:0]           o_commandSize,    
    
    output                   o_write,           
    output [ 14:0]           o_adr,            
    output   [2:0]           o_subadr,         
    output  [15:0]           o_writeMask,

    input  [255:0]           i_dataIn,
    input                    i_dataInValid,
    output [255:0]           o_dataOut
);

gpu_mem_vramcpu gpu_mem_vramcpu_inst
(
    // Inputs
    .clk_i					(i_clk),
    .rst_i                  (i_rst),
    .req_valid_i            (i_activate),
    .req_x_i                ({{4{RegX0[11]}}, RegX0}),
    .req_y_i                ({{4{RegY0[11]}}, RegY0}),
    .req_sizex_i            ({5'b0, RegSizeW}),
    .req_sizey_i            ({6'b0, RegSizeH}),

    .data_accept_i          (i_canPush),
    
	.gpu_busy_i             (i_busy),
    .gpu_data_in_valid_i    (i_dataInValid),
    .gpu_data_in_i          (i_dataIn),

    // Outputs
    .req_accept_o			(),
    .data_valid_o           (o_writeFIFOOut),
    .data_pair_o            (o_pairPixelToCPU),
	
    .busy_o                 (o_active),
    .done_o                 (o_exitSig),
    
	.gpu_command_o          (o_command),
    .gpu_size_o             (o_commandSize),
    .gpu_write_o            (o_write),
    .gpu_addr_o             (o_adr),
    .gpu_sub_addr_o         (o_subadr),
    .gpu_write_mask_o       (o_writeMask),
    .gpu_data_out_o         (o_dataOut)
	
);

endmodule
