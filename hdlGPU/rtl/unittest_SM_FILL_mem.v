module unittest_SM_FILL_mem(
	input					i_clk,
	input					i_rst,
	
	// Setup
	input					i_InterlaceRender,
	input					GPU_REG_CurrentInterlaceField,
	input			[ 7:0]	RegR0,
	input			[ 7:0]	RegG0,
	input			[ 7:0]	RegB0,
	input	signed  [11:0]	RegX0,
	input	signed  [11:0]	RegY0,
	input			[10:0]	RegSizeW,
	input			[ 9:0]	RegSizeH,

	// State machine control
	input					i_activateFILL,
	output					o_FILLInactiveNextCycle,

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

// Dont perform read.
//    input  [255:0]   		i_dataIn,
//    input            		i_dataInValid,

    output [255:0]   		o_dataOut
);

wire					stencilWriteSig;
wire					stencilReadSig;
wire					stencilFullMode;
wire			[15:0]	stencilWriteValue16;
wire			[15:0]	stencilWriteMask16;
wire			[14:0]	stencilWriteAdr;

StencilCache StencilCache_instance(
	.clk				(i_clk),

	.fullMode			(stencilFullMode),	// Always 1 with FILL
	.writeValue16		(stencilWriteValue16),
	.writeMask16		(stencilWriteMask16),
	.readValue16		(), // Read Ignored

	.stencilWriteSig	(stencilWriteSig),
	.stencilWriteAdr	(stencilWriteAdr),
	.stencilWritePair	(), // Pair stuff ignored
	.stencilWriteSelect	(), // Pair stuff ignored
	.stencilWriteValue	(), // Pair stuff ignored

	.stencilReadSig		(stencilReadSig),	// Always 0 with FILL, NO READ
	.stencilReadAdr		(), // Pair stuff ignored
	.stencilReadPair	(), // Pair stuff ignored
	.stencilReadSelect	(), // Pair stuff ignored
	.stencilReadValue	()	// Pair stuff ignored
);

gpu_SM_FILL_mem gpu_SM_FILL_mem_instance(
	.i_clk							(i_clk							),
	.i_rst							(i_rst							),

	.i_InterlaceRender				(i_InterlaceRender				),
	.GPU_REG_CurrentInterlaceField	(GPU_REG_CurrentInterlaceField	),
	.RegR0							(RegR0							),
	.RegG0							(RegG0							),
	.RegB0							(RegB0							),
	.RegX0							(RegX0							),
	.RegY0							(RegY0							),
	.RegSizeW						(RegSizeW						),
	.RegSizeH						(RegSizeH						),

	.i_activateFILL					(i_activateFILL					),
	.o_FILLInactiveNextCycle		(o_FILLInactiveNextCycle		),

	.o_stencilWriteSig				(stencilWriteSig				),
	.o_stencilReadSig				(stencilReadSig					),
	.o_stencilFullMode				(stencilFullMode				),
	.o_stencilWriteValue16			(stencilWriteValue16			),
	.o_stencilWriteMask16			(stencilWriteMask16				),
	.o_stencilWriteAdr				(stencilWriteAdr				),

    .o_command						(o_command						),
    .i_busy							(i_busy							),
    .o_commandSize					(o_commandSize					),

    .o_write						(o_write						),         
    .o_adr							(o_adr							),         
    .o_subadr						(o_subadr						),         
    .o_writeMask					(o_writeMask					),
    .o_dataOut                      (o_dataOut                     )
);

endmodule
