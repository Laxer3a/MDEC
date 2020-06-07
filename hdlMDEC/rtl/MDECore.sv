`include "MDEC_Cte.sv"

// Note : bitSetupDepth has no need to move along the pipeline
//        => Command to MDEC can not change in between. Format belong to the command itself, not register setup. Atomic guarantee. Smaller hardware logic.

module MDECore (
	// System
	input			clk,
	input			i_nrst,

	// Setup
	input MDEC_TPIX	i_bitSetupDepth, // [Bit 1..0 = (0=4bit, 1=8bit, 2=24bit, 3=15bit)
	input MDEC_SIGN	i_bitSigned,
	
	// RLE Stream
	input			i_dataWrite,
	input [15:0]	i_dataIn,
	output			o_endMatrix,
	output			o_allowLoad,
//	input			writeCoefOutToREG,
//	input			selectREGtoIDCT,
	
	// Loading of COS Table (Linear, no zigzag)
	input			i_cosWrite,
	input	[ 4:0]	i_cosIndex,
	input	[25:0]	i_cosVal,
	
	// Loading of quant Matrix
	input			i_quantWrt,
	input	[27:0]	i_quantValue,
	input	 [3:0]	i_quantAdr,
	input			i_quantTblSelect,

	input			i_stopFillY,
	output MDEC_BLCK o_idctBlockNum,
	
	output			o_stillIDCT,
	
	output			o_pixelOut,
	output  [7:0]   o_pixelAddress,		// 16x16 or 8x8 [yyyyxxxx] or [0yyy0xxx]
	output  [7:0]	o_rComp,
	output  [7:0]	o_gComp,
	output  [7:0]	o_bComp
);
	wire isPass1;

	// Instance Stream Decoder
	wire YOnly = !i_bitSetupDepth[1];
	wire busyIDCT;
	
	assign o_stillIDCT	= busyIDCT;

	// ---------------- Directly to state machine and FIFO pusher -------
	wire	canLoadMatrix;	// From IDCT direct to FIFO state machine.
//	wire	stopPipeLine			= canLoadMatrix | ((isPass1==1) & (blockComplete_b));
	assign	o_allowLoad				= canLoadMatrix;
	wire	freezeStreamAndCompute	= !canLoadMatrix;
	// ------------------------------------------------------------------
	
	wire bDataWrite = i_dataWrite;
	
	streamInput streamInput_inst(
		.clk				(clk),
		.i_nrst				(i_nrst),
		.bDataWrite			(bDataWrite),			// Never write if pipeline is frozen.
		.i_dataIn			(i_dataIn),
		
		.i_YOnly			(YOnly),
		.o_dataWrt			(dataWrt_b),
		.o_dataOut			(dataOut_b),
		.o_scale			(scale_b),
		.o_isDC				(isDC_b),
		.o_index			(index_b),				// Direct Access order for storage.
		.o_linearIndex		(linearIndex_b),		// 
		.o_fullBlockType	(fullBlockType_b),
		.o_blockNum			(blockNum_b),			// Need to propagate info with data, easier for control logic.
		.o_blockComplete	(blockComplete_b)
	);
	
	assign o_endMatrix = blockComplete_b;
	
	wire 			dataWrt_b;
	wire [9:0]		dataOut_b;
	wire [5:0]		scale_b;
	wire			isDC_b;
	wire [5:0]		index_b;			
	wire [5:0]		linearIndex_b;		
	wire			fullBlockType_b;
	wire [2:0]	blockNum_b;		
	wire			blockComplete_b;

	// Instance Coef Multiplier
	computeCoef ComputeCoef_inst (
		.i_clk				(clk),
		.i_nrst				(i_nrst),

		.i_dataWrt			(dataWrt_b),
		.i_dataIn			(dataOut_b),
		.i_debug			(i_dataIn),

		.i_scale			(scale_b),
		.i_isDC				(isDC_b),
		.i_index			(index_b),
		.i_linearIndex		(linearIndex_b),			// Needed because Quant table is in linear order.
		.i_fullBlockType	(fullBlockType_b),
		.i_blockNum			(blockNum_b),
		.i_matrixComplete	(blockComplete_b),
		
		.i_freezePipe		(freezeStreamAndCompute),

		// Quant Table Loading
		.i_quantWrt			(i_quantWrt),
		.i_quantValue		(i_quantValue),
		.i_quantAdr			(i_quantAdr),
		.i_quantTblSelect	(i_quantTblSelect),
		
		// Write output (1 cycle latency from loading)
		.o_write			(write_c),
		.o_writeIdx			(writeIdx_c),
		.o_blockNum			(blockNum_c),
		.o_coefValue		(coefValue_c),
		.o_matrixComplete	(matrixComplete_c)
	);

	wire			write_c;
	wire [5:0]		writeIdx_c;
	wire [2:0]	blockNum_c, writeValueBlock;
	wire [11:0]		coefValue_c;
	wire			matrixComplete_c;

	/*
	reg			REGwrite_c;
	reg [5:0]	REGwriteIdx_c;
	reg [2:0]	REGblockNum_c;
	reg [11:0]	REGcoefValue_c;
	reg			REGmatrixComplete_c;
	
	always @ (posedge clk)
	begin
		if (writeCoefOutToREG)
		begin
			REGwrite_c			<= write_c;
			REGwriteIdx_c		<= writeIdx_c;
			REGblockNum_c		<= blockNum_c;
			REGcoefValue_c		<= coefValue_c;
			REGmatrixComplete_c	<= matrixComplete_c;
		end
	end
	*/

	wire			write_c2			= /* selectREGtoIDCT ? REGwrite_c			: */ write_c;
	wire [5:0]		writeIdx_c2			= /* selectREGtoIDCT ? REGwriteIdx_c		: */ writeIdx_c;
	wire [2:0]	blockNum_c2			= /* selectREGtoIDCT ? REGblockNum_c		: */ blockNum_c;
	wire [11:0]		coefValue_c2		= /* selectREGtoIDCT ? REGcoefValue_c		: */ coefValue_c;
	wire			matrixComplete_c2	= /* selectREGtoIDCT ? REGmatrixComplete_c	: */ matrixComplete_c;
	
	IDCT IDCTinstance (
		// System
		.clk				(clk),
		.i_nrst				(i_nrst),
		// Coefficient input
		.i_write			(write_c2),
		.i_writeIdx			(writeIdx_c2),
		.i_blockNum			(blockNum_c2),
		.i_coefValue		(coefValue_c2),
		.i_matrixComplete	(matrixComplete_c2),
		.o_canLoadMatrix	(canLoadMatrix),

		// Loading of COS Table (Linear, no zigzag)
		.i_cosWrite			(i_cosWrite),
		.i_cosIndex			(i_cosIndex),
		.i_cosVal			(i_cosVal),
		
		// Output in order value out
		.i_pauseIDCT_YBlock	(pauseIDCTYBlock),		// If signal = 1, IDCT pause everthing... Signal sent only for Y blocks. (FIFO RGB full)
		.o_value			(value_d),
		.o_writeValue		(writeValue_d),
		.o_blockNum			(writeValueBlock),
		.o_busyIDCT			(busyIDCT),
		.o_writeIndex		(writeIndex_d)
	);

	wire		isYOnlyBlock	= (writeValueBlock == BLK_Y_ /* is 7*/);
	wire		isYBlock  		= isYOnlyBlock | (!writeValueBlock[2] /* range 0..3 */);
	// [FIFO Out force IDCT to stop pushing Y values because it is near full]
	wire		pauseIDCTYBlock = isYBlock & i_stopFillY;
	
	wire	 [7:0]	value_d;
	wire 			writeValue_d;
	wire	 [5:0]	writeIndex_d;

	// --------------------------------------------------
	// Select Cr,Cb write or direct input to YUV
	// --------------------------------------------------
	wire writeY  = writeValue_d && isYBlock;
	wire writeCr = writeValue_d && !isYBlock && (!writeValueBlock[0]);	// When not Y, and blocknumber = 0
	wire writeCb = writeValue_d && !isYBlock && ( writeValueBlock[0]);	// When not Y, and blocknumber = 1
	
	// 000 : Y0
	// 001 : Y1
	// 010 : Y2
	// 011 : Y3
	// 100 : Cr
	// 101 : Cb
	// 111 : Y3 (Y Only mode)
	assign o_idctBlockNum = writeValueBlock;
	
	// --------------------------------------------------
	//  Cr / Cb Memory : 8x8
	// --------------------------------------------------
	// Public Shared (declared already)
	wire		 [5:0]	readAdrCrCbTable;
	//
	// Public READ Value
	wire		 [7:0]	readCrValue;
	wire		 [7:0]	readCbValue;
	// Public WRITE VALUE
	reg signed	 [7:0]	CrTable[63:0];
	reg signed	 [7:0]	CbTable[63:0];
	reg			 [5:0]	readAdrCrCbTable_reg;
	
	always @ (posedge clk)
	begin
		if (writeCr)
		begin
			CrTable[writeIndex_d] = value_d;
		end
		if (writeCb)
		begin
			CbTable[writeIndex_d] = value_d;
		end
		readAdrCrCbTable_reg = readAdrCrCbTable;
	end
	assign readCrValue = CrTable[readAdrCrCbTable_reg];
	assign readCbValue = CbTable[readAdrCrCbTable_reg];
	//--------------------------------------------------------
	
	YUV2RGBModule YUV2RGBInstance (
		// System
		.i_clk				(clk),
		.i_nrst				(i_nrst),
		.i_wrt				(writeY),	// Write to YUV2RGB only the Luminance.
		.i_YOnly			(isYOnlyBlock),
		.i_signed			(i_bitSigned),
		
		.i_writeIdx			(writeIndex_d),
		.i_valueY			(value_d),
		.i_YBlockNum		(writeValueBlock[1:0]), // 0..3 is Y block range.

		// Read Cr
		// Read Cb
		// No need for Read Signal, always. Write higher priority, and values ignore when invalid address.
		.o_readAdr			(readAdrCrCbTable),
		.i_valueCr			(readCrValue),
		.i_valueCb			(readCbValue),
		
		// Output in order value out
		.o_wPix				(o_pixelOut),
		.o_pix				(o_pixelAddress),
		.o_r				(o_rComp),
		.o_g				(o_gComp),
		.o_b				(o_bComp)
	);
	
	
endmodule
