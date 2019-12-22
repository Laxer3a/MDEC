/*	
	Playstation MDEC YUV -> RGB Hardware conversion.
	Done by Laxer3A
	
	-------------------------------------------------
	Module for YUV->RGB Conversion.
	-------------------------------------------------
	
	YUV2RGB Compute is the module doing the computations.
	and is purely combinatorial.
	
	YUV2RGB Module handle the addressing, timing, pipelining.
	and wrap computations.
 */
module YUV2RGBModule (
	// System
	input					i_clk,
	input					i_nrst,

	// Input
	input					i_wrt,
	input					i_YOnly,
	input 					i_signed,
	
	input			[5:0]	i_writeIdx,
	input	signed 	[7:0]	i_valueY,
	input			[1:0]	i_YBlockNum,

	// Read Cr
	// Read Cb
	// No need for Read Signal, always. Write higher priority, and values ignore when invalid address.
	output 			[5:0]	o_readAdr,
	input	signed 	[7:0]	i_valueCr,
	input	signed 	[7:0]	i_valueCb,
	
	// Output in order value out
	output					o_wPix,
	output  [7:0]			o_pix,
	output	[7:0]			o_r,
	output	[7:0]			o_g,
	output	[7:0]			o_b
);
	/*	--------------------------------------------------------------------------
		  [CYCLE n : Setup Cr/Cb Matrix reading]
		--------------------------------------------------------------------------
		- 1 Cycle Latency when reading Cr/Cb */
	wire [2:0] adrX		= i_writeIdx[2:0];
	wire [1:0] adrXSub	= i_writeIdx[2:1];
	wire [2:0] adrY		= i_writeIdx[5:3];
	wire [1:0] adrYSub	= i_writeIdx[5:4];
	wire       tileX	= i_YBlockNum[0];
	wire       tileY	= i_YBlockNum[1];
	
	// Read address for Cr/Cb 8x8 block.
	assign o_readAdr	= {tileY,adrYSub,tileX,adrXSub};

	wire [7:0] pix  	= i_YOnly	? { 2'b00  , i_writeIdx }
									: {tileY,adrY,tileX,adrX};

	reg					p_YOnly;
	reg					p_signed;
	reg	signed	[7:0]	p_valueY;
	reg					p_Wrt;
	reg			[7:0]	p_WrtIdx;
	
	/*	--------------------------------------------------------------------------
		  [CYCLE n+1 : Computation and output]
		-------------------------------------------------------------------------- */
	always @(posedge i_clk)
	begin
		p_valueY	= i_valueY;
		p_WrtIdx	= pix;
		p_Wrt		= i_wrt;
		//
		p_YOnly		= i_YOnly;		// Could may be afford to do not use registers... But safer to embbed context.
		p_signed	= i_signed;	// Same here
	end

	// ---------------------------------
	// --- Instance Computation Core ---
	// ---------------------------------
	YUV2RGBCompute YUV2RGBCompute_inst (
		.i_YOnly   (p_YOnly   ),
		.i_signed  (p_signed),

		.i_valueY  (p_valueY ),
		.i_valueCr (i_valueCr),
		.i_valueCb (i_valueCb),
		
		.o_r       (o_r),				// output	[7:0]
		.o_g       (o_g),				// output	[7:0]
		.o_b       (o_b)				// output	[7:0]
	);
	assign o_wPix		= p_Wrt;		// output	[7:0]
	assign o_pix		= p_WrtIdx;		// output
endmodule
