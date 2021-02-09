module unittest_SM_VV_mem(
	input					i_clk,
	input					i_rst,

	// Control signals
	input					i_activateCopyVV,
	output					o_CopyInactiveNextCycle,
	output					o_active,

	// Setup with registers
	input	signed [11:0]	RegX0,
	input	signed [11:0] 	RegX1,
	input	signed [11:0]	RegY0,
	input	signed [11:0]	RegY1,
	input 		   [10:0]	RegSizeW,
	input		   [ 9:0]	RegSizeH,
	input					GPU_REG_CheckMaskBit,
	input					GPU_REG_ForcePixel15MaskSet,
	
	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    output           		o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input            		i_busy,           // Memory busy 1 => can not use.
    output   [1:0]   		o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           		o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]   		o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   		o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   		o_writeMask,

    input  [255:0]   		i_dataIn,
    input            		i_dataInValid,
    output [255:0]   		o_dataOut
);

wire signed [11:0] xAxis = RegX1 - RegX0;
wire isNegXAxis = xAxis[11];

wire	[14:0]	stencilReadAdr;
wire	[14:0]	stencilWriteAdr;

wire	[15:0]	stencilReadValue16;
wire			stencilReadSig;
wire			stencilWriteSig;

wire			stencilFullMode;
wire	[15:0]	stencilWriteValue16;
wire	[15:0]	stencilWriteMask16;
	
StencilCache StencilCache_instance(
	.clk				(i_clk),

	.fullMode			(stencilFullMode),	// Always 1 with FILL
	.writeValue16		(stencilWriteValue16),
	.writeMask16		(stencilWriteMask16),
	.readValue16		(stencilReadValue16),

	.stencilWriteSig	(stencilWriteSig),
	.stencilWriteAdr	(stencilWriteAdr),	// Same as o_adr
	.stencilWritePair	(), // Pair stuff ignored
	.stencilWriteSelect	(), // Pair stuff ignored
	.stencilWriteValue	(), // Pair stuff ignored

	.stencilReadSig		(stencilReadSig),
	.stencilReadAdr		(stencilReadAdr),	// Same as o_adr
	.stencilReadPair	(), // Pair stuff ignored
	.stencilReadSelect	(), // Pair stuff ignored
	.stencilReadValue	()	// Pair stuff ignored
);

gpu_SM_CopyVV_mem gpu_SM_CopyVV_mem_instance(
	.i_clk							(i_clk						),
	.i_rst							(i_rst						),

	.i_activateCopyVV				(i_activateCopyVV			),
	.o_CopyInactiveNextCycle		(o_CopyInactiveNextCycle	),
	.o_active						(o_active					),

	.i_isNegXAxis					(isNegXAxis					),
	.RegX0							(RegX0						),
	.RegX1							(RegX1						),
	.RegY0							(RegY0						),
	.RegY1							(RegY1						),
	.RegSizeW						(RegSizeW					),
	.RegSizeH						(RegSizeH					),
	.GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit		),
	.GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet),

	.i_stencilReadValue16			(stencilReadValue16	),
	.o_stencilReadSig				(stencilReadSig		),
	.o_stencilWrite					(stencilWriteSig	),
	.o_stencilFullMode				(stencilFullMode	),
	.o_stencilWriteValue16			(stencilWriteValue16),
	.o_stencilWriteMask16			(stencilWriteMask16	),

	// Those two are identical to o_adr
	.o_stencilReadAdr				(stencilReadAdr		),
	.o_stencilWriteAdr				(stencilWriteAdr	),
	
    .o_command						(o_command					),
    .i_busy							(i_busy						),
    .o_commandSize					(o_commandSize				),

    .o_write						(o_write					),
    .o_adr							(o_adr						),
    .o_subadr						(o_subadr					),
    .o_writeMask					(o_writeMask				),

    .i_dataIn						(i_dataIn					),
    .i_dataInValid					(i_dataInValid				),
    .o_dataOut						(o_dataOut					)
);

endmodule
