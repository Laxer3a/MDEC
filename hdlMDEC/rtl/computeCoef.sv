`include "MDEC_Cte.sv"

/*
	This unit takes the decoded stream of coefficent with scale and specific setup
	and does the pre IDCT multiplication of the coefficient based on the mode :
	
	Standard Mode :
	- Item 0 : Coef x   1.0 x QuantMatrix[0]    -> Coef x     8 x QuantMatrix[0] / 8
	- Item x : Coef x Scale x QuantMatrix[x]/8  -> Coef x Scale x QuantMatrix[x] / 8 
	
	Full Uncompressed Matrix Mode :
	- Item 0 : Coef x   2.0                     -> Coef x    16 x              1 / 8
	- Item x : Coef x   2.0						-> Coef x    16 x              1 / 8
	
	No$PSX specs says that +4 is added BEFORE DIVISION by 8.
	
	[Coef : 10 Bit]x[Scale : 6 Bit]x[Quantization : 7 Bit] = [22:0] BIT / 8 = BIT[19:0]
	
	And pass pipelined the important information such as :
	- HiRes (4/8/16/24 bit output for YUV->RGB Conversion unit)
	- Block Number
	- Of course strict necessary information for storage in IDCT.
 */
 
module computeCoef (
	input					i_clk,
	input					i_nrst,

	// Loading Side
	input					i_dataWrt,
	input	signed[9:0]		i_dataIn,
	input	[15:0]			i_debug,
	input	[5:0]			i_scale,
	input					i_isDC,
	input	[5:0]			i_index,			// Linear or Zagzig order.
	input	[5:0]			i_linearIndex,		// Needed because Quant table is read in linear order, avoid i_index.
	input					i_fullBlockType,
	input	MDEC_BLCK		i_blockNum,
	input					i_matrixComplete,

	// IDCT Busy side
	input					i_freezePipe,

	// Quant Table Loading
	input					i_quantWrt,
	input	[27:0]			i_quantValue,
	input	[3:0]			i_quantAdr,
	input					i_quantTblSelect,	// 1:Luma Table, 0:Chroma Table
	
//	output	[23:0]			debug,
	
	// Write output (1 cycle latency from loading)
	output					o_write,
	output	[5:0]			o_writeIdx,
	output	MDEC_BLCK		o_blockNum,
	output	signed [11:0]	o_coefValue,
	output          		o_matrixComplete
);
	// ----- Data Pipelining Management ----------------------------------
	//
	// IDCT can suddenly decide to be full and STOP the FIFO from feeding.
	// But in this case, we may have valid data in flight due to a 1 cycle
	// pipeline (which we can NOT avoid because of the Quantization table read).
	// So we handle the freezing and unfreezing of the pipeline.
	//
	// Transition over time : {pipedfreezePipe,freezePipe} => [00] [01] [11] [10] 
	// ----
	//
	// Values over time (output of reg for register):
	//     Input    Reg1    Reg2 (Backup)                                    Reg1W   Reg2W  StoreQuantV
	// 00    C       B B'    A" 			Output B (Acceptd by IDCT)        1       X       1                    Use Reg
	// 01    D       C C'    B"				Output C (Refused by IDCT)        1       1       1                    Dont care -> Use Reg
	// 11    X       D D'    C"				Output D (Refused by IDCT)        0       0		  1                    Dont care -> Use Reg
	// 11    X       D X'    C"				Output D (Refused by IDCT)        0       0		  0                    Dont care -> Use Reg
	// 11    X       D X'    C"				Output D (Refused by IDCT)        0       0		  0                    Dont care -> Use Reg
	// 10    X       D X'	 C"				Output C (Acceptd by IDCT)        0       1		  0                    Use Reg2
	// 00    E       D X'    #"				Output D (Acceptd by IDCT)        1       X  	  0                    Use Reg
	// 00    F       E E'    
	//
	//		transition	00	01	11	11	10	00	
	//		Input		A	B	X	X	C	D	
	//		Output		X	A	Z	X	B	C	
	
	// x' are value from the Quantization Table read.
	// x" are value stored using x' and x values if we do not handle 
	//
	// We notice thate there is a discrepancy if we just pipeline the values, but
	// do not manager the output of the table.
	//
	// => Store the Quant Table result on pipe(True when 01 transition)
	// => Use stored result (TRUE) on 10 transition (non piped !)
	//
	// -------------------------------------------------------------------

	// -------------------------------------------------------------------
	//   Embedded Quantization Table RAM
	// -------------------------------------------------------------------
	// INPUT : [We read continuously from the Quant table]
	//
	//    Read from computeCoef
	//    ----------------------
	//             storeQuantVal
	//             selectTable
	//       [5:0] quantReadIdx
	//
	//    Setup from outside
	//    ----------------------
	//				i_quantWrt,
	//		[27:0]	i_quantValue,
	//		[ 3:0]	i_quantAdr,
	//				i_quantTblSelect,
	//
	// OUTPUT
	reg  [6:0] valueQuant;
	// -------------------------------------------------------------------
	// Internal stuff
	reg  [27:0] QuantTbl[31:0];
	reg   [4:0] quantAdr_reg;
	wire  [4:0] writeAdr = {i_quantTblSelect,i_quantAdr};
	reg   [1:0] pipeQuantReadIdx;

	// [Quantization Table READ/WRITE]
	always @ (posedge i_clk)
	begin
		// Write
		if (i_quantWrt)
		begin
			QuantTbl[writeAdr] = i_quantValue;
		end

		// Read
		quantAdr_reg 		= {selectTable,quantReadIdx[5:2]};
		// Read
		pipeQuantReadIdx	= quantReadIdx[1:0];
	end
	wire [27:0] fullValueQuant = QuantTbl[quantAdr_reg]; 

	// [Select the correct 7 bit from 28 bit record]
	always @ (*)	
	begin
		case (pipeQuantReadIdx)
		0       : valueQuant = fullValueQuant[ 6: 0];
		1       : valueQuant = fullValueQuant[13: 7];
		2       : valueQuant = fullValueQuant[20:14];
		default : valueQuant = fullValueQuant[27:21];
		endcase
	end
	// -------------------------------------------------------------------
	
	
	// -------------------------------------------------------------------
	//   Stage 0 : Compute data (1st multiplication) while we request
	//             the quantization factor
	// -------------------------------------------------------------------
	// 
	// Cycle 0 :	- Drive SRAM Read for quantization block.
	//				- Compute Scale * Coef => Temporary Coef
	//
	wire 			selectTable			= (!i_blockNum[2] | i_blockNum[1]);	// 1=Luma, 0=Chroma
	wire [5:0]		quantReadIdx		= i_linearIndex;

	reg				pWrite;
	reg  [5:0]		pIndex;
	MDEC_BLCK		pBlk;
	reg				pMatrixComplete;
	reg				pFullBlkType;

	//
	// Save values needed for stage 1 (pipeline to match SRAM latency)
	//
	wire signed [16:0]	multF;
	reg  signed [15:0]	pMultF;
	reg  [15:0]			pDebug;
	
	wire signed [6:0]  signedScale = {1'b0,i_scale}; // Verilog authorize wire signed a = ua; and generate one more bit, but Verilator is not. And I prefer explicit anyway.
	
	assign multF = i_dataIn * signedScale; // 10x7 -> 17 bit, but range is from [-512*63..511*63] (-32256,32193)

	always @(posedge i_clk)
	begin
		if (!i_freezePipe) begin
			pWrite			= i_dataWrt;			// Already done in streamInput ( & i_nrst )
			pIndex			= i_index;
			pBlk			= i_blockNum;
			pMatrixComplete	= i_matrixComplete;	// Already done in streamInput ( & i_nrst );
			pFullBlkType	= i_fullBlockType;
			pMultF          = multF[15:0];
			pDebug			= i_debug;
		end
	end
	
	// -------------------------------------------------------------------
	//   Stage 1 : Compute data (2nd multiplication) with the arrived
	//             the quantization factor
	// -------------------------------------------------------------------
	//   Compute :
	//	 Temporary Coef * Quantization Value => Output
	//                  * 1.0 if fullblockType
	//
	wire signed [23:0] outCalc;
	reg  signed [11:0] pOutCalc;
	wire signed [ 7:0] quant= pFullBlkType  ? 8'd1 : { 1'b0, valueQuant };

	// Spec says in No$PSX => (signed10bit(n AND 3FFh)*qt[k]*q_scale+4)/8
	
	//--------------------------------------------------------------------------------------------
	// First we do qt[k]*(q_scale*value)
	assign outCalc			= (pMultF * quant); // 16x8 = 24 bit.	// Consider MUL to take 1 cycle, implement accordingly.

	roundDiv8AndClamp inst_roundDiv8AndClamp(
		.valueIn	(outCalc),
		.valueOut	(roundedOddTowardZeroExceptMinus1)
	);
	
	wire [11:0] roundedOddTowardZeroExceptMinus1;
	wire [11:0] outSelCalc 	= roundedOddTowardZeroExceptMinus1;

//  NOT HANDLED ANYMORE... for now.
//	wire   cancelOutput     =  & (!i_freezePipe);
	wire   outWriteSignal   = pWrite & i_nrst;
	assign o_write    		= outWriteSignal;
	assign o_matrixComplete = pMatrixComplete & i_nrst;
	assign o_writeIdx 		= pIndex;
	assign o_blockNum 		= pBlk;
	// 12 bit : -2048..+2047
	assign o_coefValue		= outWriteSignal ? outSelCalc : 12'd999; // TODO DEBUG, TO REMOVE.
endmodule
