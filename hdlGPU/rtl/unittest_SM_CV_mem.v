module unitest_SM_CV_mem(
	input				i_clk,
	input				i_rst,

	//
	// GPU Registers / Stencil Cache / FIFO Side
	//
	input				i_activateCopyCV,
	output				o_CopyInactiveNextCycle,
	output				o_active,

	// Registers
	input				GPU_REG_CheckMaskBit,
	input				GPU_REG_ForcePixel15MaskSet,
	input signed [11:0] RegX0,
	input signed [11:0] RegY0,
	input	[10:0]		RegSizeW,
	input	[9:0]		RegSizeH,
	
	// -----------------------------------
	// [FIFO Side input]
	// -----------------------------------
	output				o_canWriteFIFO,
	input				i_fifowrite,
	input	[31:0]		i_fifoDataIn,

	// -----------------------------------
	// [DDR SIDE]
	// -----------------------------------

    output           	o_command,        // 0 = do nothing, 1 Perform a read or write to memory.
    input            	i_busy,           // Memory busy 1 => can not use.
    output   [1:0]   	o_commandSize,    // 0 = 8 byte, 1 = 32 byte. (Support for write ?)
    
    output           	o_write,          // 0=READ / 1=WRITE 
    output [ 14:0]   	o_adr,            // 1 MB memory splitted into 32768 block of 32 byte.
    output   [2:0]   	o_subadr,         // Block of 8 or 4 byte into a 32 byte block.
    output  [15:0]   	o_writeMask,

	/*
    input  [255:0]   	i_dataIn,
    input            	i_dataInValid,
	*/
    output [255:0]   	o_dataOut
);

wire 			stencilReadSig;
wire [14:0]		stencilReadAdr;
wire  [2:0]		stencilReadPair;
wire  [1:0]		stencilReadSelect;
wire [1:0]		stencilReadValue;

wire  [2:0]		stencilWritePairC;
wire  [1:0]		stencilWriteSelectC;
wire  [1:0]		stencilWriteValueC;
wire 			stencilFullMode;
wire 			stencilWriteSigC;
wire [14:0]		stencilWriteAdrC;

wire 			canReadL;
wire 			canReadM;
wire 			readL;
wire 			readM;
wire [15:0]		fifoDataOutM;
wire [15:0]		fifoDataOutL;

gpu_SM_CopyCV_mem gpu_SM_CopyCV_mem_inst(
	.i_clk							(i_clk						),
	.i_rst							(i_rst						),

	.i_activateCopyCV				(i_activateCopyCV			),
	.o_CopyInactiveNextCycle		(o_CopyInactiveNextCycle	),
	.o_active						(o_active					),

	.GPU_REG_CheckMaskBit			(GPU_REG_CheckMaskBit		),
	.GPU_REG_ForcePixel15MaskSet	(GPU_REG_ForcePixel15MaskSet),
	.RegX0                          (RegX0                     ),
	.RegY0                          (RegY0                     ),
	.RegSizeW                       (RegSizeW                  ),
	.RegSizeH                       (RegSizeH                  ),

	.o_stencilReadSig				(stencilReadSig				),
	.o_stencilReadAdr				(stencilReadAdr				),
	.o_stencilReadPair				(stencilReadPair			),
	.o_stencilReadSelect			(stencilReadSelect			),
	.i_stencilReadValue				(stencilReadValue			),

	.o_stencilWritePairC			(stencilWritePairC			),
	.o_stencilWriteSelectC			(stencilWriteSelectC		),
	.o_stencilWriteValueC			(stencilWriteValueC			),
	.o_stencilFullMode				(stencilFullMode			),
	.o_stencilWriteSigC				(stencilWriteSigC			),
	.o_stencilWriteAdrC				(stencilWriteAdrC			),

	.i_canReadL						(canReadL					),
	.i_canReadM						(canReadM					),
	.o_readL						(readL						),
	.o_readM						(readM						),
	.i_fifoDataOutM					(fifoDataOutM				),
	.i_fifoDataOutL					(fifoDataOutL				),

    .o_command						(o_command					),
    .i_busy							(i_busy						),
    .o_commandSize					(o_commandSize				),

    .o_write						(o_write					),
    .o_adr							(o_adr						),
    .o_subadr						(o_subadr					),
    .o_writeMask					(o_writeMask				),

    // .i_dataIn						(),
    // .i_dataInValid					(),
	
    .o_dataOut						(o_dataOut)
);

StencilCache StencilCache_instance(
	.clk				(i_clk),

	.fullMode			(stencilFullMode),		// Always 0 with CV
	.writeValue16		(), // All Full 16 pixel mode stuff ignored.
	.writeMask16		(), // All Full 16 pixel mode stuff ignored.
	.readValue16		(), // All Full 16 pixel mode stuff ignored.

	.stencilWriteSig	(stencilWriteSigC),
	.stencilWriteAdr	(stencilWriteAdrC),
	.stencilWritePair	(stencilWritePairC),
	.stencilWriteSelect	(stencilWriteSelectC),
	.stencilWriteValue	(stencilWriteValueC),

	.stencilReadSig		(stencilReadSig),
	.stencilReadAdr		(stencilReadAdr),
	.stencilReadPair	(stencilReadPair),
	.stencilReadSelect	(stencilReadSelect),
	.stencilReadValue	(stencilReadValue)
);


wire isFifoEmptyMSB,isFifoEmptyLSB;
wire isFifoFullMSB,isFifoFullLSB;

Fifo
#(
    .DEPTH_WIDTH	(4),
    .DATA_WIDTH		(16)
)
Fifo_instMSB
(
    .clk			(i_clk),
    .rst			(i_rst),

    .wr_data_i		(i_fifoDataIn[31:16]),
    .wr_en_i		(i_fifowrite),

    .rd_data_o		(fifoDataOutM),
    .rd_en_i		(readM),

    .full_o			(isFifoFullMSB),
    .empty_o		(isFifoEmptyMSB)
);

Fifo
#(
    .DEPTH_WIDTH	(4),
    .DATA_WIDTH		(16)
)
Fifo_instLSB
(
    .clk			(i_clk),
    .rst			(i_rst),

    .wr_data_i		(i_fifoDataIn[15:0]),
    .wr_en_i		(i_fifowrite),

    .rd_data_o		(fifoDataOutL),
    .rd_en_i		(readL),

    .full_o			(isFifoFullLSB),
    .empty_o		(isFifoEmptyLSB)
);

assign canReadL 		= !isFifoEmptyLSB;
assign canReadM 		= !isFifoEmptyMSB;
assign o_canWriteFIFO	= !(isFifoFullMSB | isFifoFullMSB);

endmodule
