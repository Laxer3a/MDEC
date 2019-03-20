/*
	This unit takes the decoded stream of coefficent with scale and specific setup
	and does the pre IDCT multiplication of the coefficient based on the mode :
	
	Standard Mode :
	- Item 0 : Coef x   1.0 x QuantMatrix[0]    -> Coef x     8 x QuantMatrix[0] / 8
	- Item x : Coef x Scale x QuantMatrix[x]/8  -> Coef x Scale x QuantMatrix[x] / 8 
	
	Full Uncompressed Matrix Mode :
	- Item 0 : Coef x   2.0                     -> Coef x    16 x              1 / 8
	- Item x : Coef x   2.0						-> Coef x    16 x              1 / 8
	
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
	input	[5:0]			i_scale,
	input					i_isDC,
	input	[5:0]			i_index,
	input	[5:0]			i_zagIndex,			// Needed because Quant table is in zigzag order, avoid decode into linear.
	input					i_fullBlockType,
	input	[2:0]			i_blockNum,
	input					i_matrixComplete,

	// Quant Table Loading
	input					i_quantWrt,
	input	[27:0]			i_quantValue,
	input	[3:0]			i_quantAdr,
	input					i_quantTblSelect,
	
	// Write output (2 cycle latency from loading)
	output					o_write,
	output	[5:0]			o_writeIdx,
	output	[2:0]			o_blockNum,
	output	signed [11:0]	o_coefValue,
	output          		o_matrixComplete
);

	// ---- Stage 0 ----
	// 
	// Cycle 0 :	- Drive SRAM Read for quantization block.
	//				- Compute Scale * Coef => Temporary Coef
	//
	wire 		selectTable			= i_blockNum[1] | i_blockNum[2];
	wire [5:0]	quantReadIdx		= i_zagIndex;

	reg			pWrite;
	reg  [5:0]	pIndex;
	reg  [2:0]	pBlk;
	reg			pMatrixComplete;
	reg			pFullBlkType;

	//
	// Save values needed for stage 1 (pipeline to match SRAM latency)
	//
	wire [5:0] scale	= (i_isDC | i_fullBlockType)	? {1'b0,{i_fullBlockType,!i_fullBlockType},3'b000}	// Scale = 8 if fullblockType=0, or 16 if 1 or i_scale.
														: i_scale;
	wire signed [15:0] multF;
	reg  signed [15:0] pMultF;
	
	wire signed [6:0]  signedScale = {1'b0,scale}; // Verilog authorize wire signed a = ua; and generate one more bit, but Verilator is not. And I prefer explicit anyway.
	
	assign multF = i_dataIn * signedScale; // 10x6 bit

	always @(posedge i_clk)
	begin
		pWrite			<= i_dataWrt & i_nrst;
		pIndex			<= i_index;
		pBlk			<= i_blockNum;
		pMatrixComplete	<= i_matrixComplete;
		pFullBlkType	<= i_fullBlockType;
		pMultF          <= multF;
	end

	// ---- Stage 1 ----
	//   Compute :
	//	 Temporary Coef * Quantization Value => Output
	//                  * 1.0 if fullblockType
	//
	wire signed [23:0] outCalc;
	reg  signed [11:0] pOutCalc;
	
	wire signed [ 7:0] quant = pFullBlkType ? 8'd1 : { 1'b0, valueQuant };

	assign outCalc = pMultF * quant; // 16x7 = 23 bit.	// Consider MUL to take 1 cycle, implement accordingly.

	// [23:Sign][22:15 Overflow][14:3 Value][2:0 Not necessary (div 8)]
	// /8 then Signed saturated arithmetic. 12 bit. (-2048..+2047)
	// TODO : Signed div 8 ? --> add sign [23]
	wire isNZero= |outCalc[22:15];
	wire isOne  = &outCalc[22:15];
	wire orSt   = (!outCalc[23]) & (isNZero);					// [+ Value] and has non zero                    -> OR  1
	wire andSt  = ((outCalc[23]) & ( isOne)) | (!outCalc[23]);	// [- Value] and has all one   or positive value -> AND 1 
	wire [11:0] clippedOutCalc = (outCalc[14:3] | {12{orSt}}) & {12{andSt}};
	
	reg       ppWrite;
	reg [5:0] ppIndex;
	reg [2:0] ppBlk;
	reg       ppMatrixComplete;

	always @(posedge i_clk)
	begin
		ppWrite <= pWrite & i_nrst;
		ppIndex <= pIndex;
		ppBlk   <= pBlk;
		ppMatrixComplete <= pMatrixComplete;
		pOutCalc<= clippedOutCalc;
	end

	assign o_write    		= ppWrite & i_nrst;
	assign o_writeIdx 		= ppIndex;
	assign o_blockNum 		= ppBlk;
	// 12 bit : -2048..+2047
	assign o_coefValue		= pOutCalc;
	assign o_matrixComplete = ppMatrixComplete;
	
	// -----------------------------------------
	//   Embedded Quantization Table RAM
	// -----------------------------------------
	reg  [27:0] QuantTbl[31:0];
	// Internal Address buffering
	reg  [4:0] quantAdr_reg;
	wire [4:0] writeAdr = {i_quantTblSelect,i_quantAdr};
	reg  [1:0] pipeQuantReadIdx;
	
	always @ (posedge i_clk)
	begin
		// Write
		if (i_quantWrt)
		begin
			QuantTbl[writeAdr] <= i_quantValue;
		end

		// Read
		quantAdr_reg <= {selectTable,quantReadIdx[5:2]};
		// Read
		pipeQuantReadIdx <= quantReadIdx[1:0];
	end
	
	wire [27:0] fullValueQuant = QuantTbl[quantAdr_reg]; 
	reg  [ 6:0] valueQuant;
	always @ (*)
	begin
		case (pipeQuantReadIdx)
		0       : valueQuant = fullValueQuant[ 6: 0];
		1       : valueQuant = fullValueQuant[13: 7];
		2       : valueQuant = fullValueQuant[20:14];
		default : valueQuant = fullValueQuant[27:21];
		endcase
	end
endmodule
