/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_setupunit(
	input						i_clk,

	input						i_bIsLineCommand,

	// --------------------------
	// Vertex registers
	// --------------------------
	input signed [11:0] 		RegX0,
	input signed [11:0] 		RegY0,
	input signed [11:0] 		RegX1,
	input signed [11:0] 		RegY1,
	input signed [11:0] 		RegX2,
	input signed [11:0] 		RegY2,

	input         [8:0] 		RegR0,
	input         [8:0] 		RegG0,
	input         [8:0] 		RegB0,
	input         [7:0] 		RegU0,
	input         [7:0] 		RegV0,
	input         [8:0] 		RegR1,
	input         [8:0] 		RegG1,
	input         [8:0] 		RegB1,
	input         [7:0] 		RegU1,
	input         [7:0] 		RegV1,
	input         [8:0] 		RegR2,
	input         [8:0] 		RegG2,
	input         [8:0] 		RegB2,
	input         [7:0] 		RegU2,
	input         [7:0] 		RegV2,

	// --------------------------
	// GPU registers
	// --------------------------
	input         [9:0]			GPU_REG_DrawAreaX0,
	input         [9:0]			GPU_REG_DrawAreaY0,
	input         [9:0]			GPU_REG_DrawAreaX1,
	input         [9:0]			GPU_REG_DrawAreaY1,

	// --------------------------
	// State machine Control signal when setup
	// --------------------------
	input [4:0]					i_interpolationCounter,
	input						i_assignRectSetup,
	
	// --------------------------
	// Runtime parameters
	// --------------------------
	input signed [11:0]			i_pixelX,
	input signed [11:0]			i_pixelY,
	
	input						i_scanDirectionR2L, // 0=L2R, 1=R2L
	
	// ------------------------------------------
	// Line runtime logic control
	input						i_memorizeLineEqu,
	input						i_lineStart,
	input						i_loadNext,
	// Next Pixel for line algorithm
	output signed [11:0]		o_nextLineX,
	output signed [11:0]		o_nextLineY,
	
	
	// ------------------------------------------
	// Feedback for rendering state machine (rasterization)
	output						o_isNULLDET,
	output						o_isNegXAxis,
	output						o_isValidPixelL,
	output						o_isValidPixelR,
	output						o_earlyTriangleReject,
	output						o_edgeDidNOTSwitchLeftRightBB,
	output						o_reachEdgeTriScan,
	
	output						o_isValidHorizontalTriBbox,
	output						o_isRightPLXmaxTri,
	output						o_isInsideBBoxTriRectL,
	output						o_isInsideBBoxTriRectR,
	output						o_isBottomInsideBBox,
	output						o_isLineInsideDrawArea,
	output						o_isLineLeftPix,
	output						o_isLineRightPix,
	output						o_isNegPreB,

	// ------------------------------------------
	// Triangle BB for scanner
	output signed [11:0]		o_minTriDAX0,
	output signed [11:0]		o_maxTriDAX1,
	output signed [11:0]		o_minTriDAY0,
	
	// ------------------------------------------
	// Output RGBUV per pixel (Left / Right pipeline)
	output	signed [8:0] 		o_pixRL,
	output	signed [8:0] 		o_pixGL,
	output	signed [8:0] 		o_pixBL,
	output	signed [7:0] 		o_pixUL,
	output	signed [7:0] 		o_pixVL,

	output	signed [8:0] 		o_pixRR,
	output	signed [8:0] 		o_pixGR,
	output	signed [8:0] 		o_pixBR,
	output	signed [7:0] 		o_pixUR,
	output	signed [7:0] 		o_pixVR
);
	parameter EQUMSB		= 22; // 11bit signed * 11 bit signed.

	// Alias
	wire signed [11:0] pixelX = i_pixelX;
	wire signed [11:0] pixelY = i_pixelY;

	// ---------------------------------------------------------------------------------------------------------------------
	//  [ Setup Stage ]
	// ---------------------------------------------------------------------------------------------------------------------

	// Range -2047..+2047 (2048 NOT VALID FOR NOW)
	// TO CHECK HW : If we use -1024 offset and -1024 vertex, do we get 0 coordinate ?
	// [SETUP] Do assign value at loading directly.
	wire signed [11:0] nRegX0	= -RegX0;
	wire signed [11:0] nRegY0	= -RegY0;
	wire signed [11:0] nRegX1	= -RegX1;
	wire signed [11:0] nRegY1	= -RegY1;
	wire signed [11:0] nRegX2	= -RegX2;
	wire signed [11:0] nRegY2	= -RegY2;

	// (-2047)+(-2047)..2047+2047 = -4095..+4095
	wire signed [12:0]	preA13 	= RegX2 + nRegX0; // X2-X0
	wire signed [12:0]	preB13 	= RegY2 + nRegY0; // Y2-Y0
	wire signed [12:0]	c13		= RegX1 + nRegX0; // X1-X0
	wire signed [12:0]	negc13	= RegX0 + nRegX1; // X0-X1 (-c)
	wire signed [12:0]	d13		= RegY1 + nRegY0; // Y1-Y0
	wire signed [12:0]  negd13  = RegY0 + nRegY1; // Y0-Y1 (-d)
	wire signed [12:0]	e13		= RegX2 + nRegX1; // X2-X1
	wire signed [12:0]	f13		= RegY1 + nRegY2; // Y1-Y2

	// Permitted RANGE : -511..+511 for Y, -1023..+1023 for X.
	//
	wire signed [11:0]	preA	= preA13[11:0];
	wire signed [11:0]	preB 	= preB13[11:0];
	wire signed [11:0]	c		= c13	[11:0];
	wire signed [11:0]	negc	= negc13[11:0];
	wire signed [11:0]	d		= d13	[11:0];
	wire signed [11:0]  negd  	= negd13[11:0];
	wire signed [11:0]	e		= e13	[11:0];
	wire signed [11:0]	f		= f13	[11:0];

	// For all coordinate testing.
	wire signed [11:0]  extDAX0 = { 2'd0 , GPU_REG_DrawAreaX0 };
	wire signed [11:0]  extDAY0 = { 2'd0 , GPU_REG_DrawAreaY0 };
	wire signed [11:0]  extDAX1 = { 2'd0 , GPU_REG_DrawAreaX1 };
	wire signed [11:0]  extDAY1 = { 2'd0 , GPU_REG_DrawAreaY1 };

	wire signed [11:0]  LPixelX = { pixelX[11:1], 1'b0 };
	wire signed [11:0]  RPixelX = { pixelX[11:1], 1'b1 };

	// TODO optimize code for clarity (remove assign)
	wire				isRightPLXmaxTri;
	wire 				isLineRightPix;
	wire				isLineLeftPix;
	wire				isLineInsideDrawArea;
	wire				isInsideBBoxTriRectL;
	wire				isInsideBBoxTriRectR;

	// Test Current Pixel Pair against [Drawing Area]
	// [NEEDED FOR LINES] : Line are scanned independantly from draw area.
	wire				isTopInside 		= pixelY  >= extDAY0;
	wire				isBottomInside		= pixelY   < extDAY1;
	wire				isTopInsideBBox		= pixelY  >= minTriDAY0; // PIXEL IS EXCLUSIVE
	wire				isBottomInsideBBox	= pixelY  <= maxTriDAY1; // PIXEL IS INCLUSIVE

	wire				isLeftPLXInside	= LPixelX >= extDAX0;
	wire				isLeftPRXInside	= RPixelX >= extDAX0;
	wire				isRightPLXInside= LPixelX <= extDAX1; // PIXEL IS INCLUSIVE
	wire				isRightPRXInside= RPixelX <= extDAX1; // PIXEL IS INCLUSIVE
	// [NEEDED FOR TRIANGLE AND RECTANGLE] : Intersection of draw area AND bounding box.
	wire				isLeftPLXminTri = LPixelX >= minTriDAX0;
	wire				isLeftPRXminTri = RPixelX >= minTriDAX0;
	assign				isRightPLXmaxTri= LPixelX <= maxTriDAX1; // PIXEL IS INCLUSIVE
	wire				isRightPRXmaxTri= RPixelX <= maxTriDAX1; // PIXEL IS INCLUSIVE

	wire				isValidHorizontal			= isTopInside     & isBottomInside;
	wire				isValidHorizontalTriBbox	= isTopInsideBBox & isBottomInsideBBox;

	// Test Current Pixel For Line primitive : Check vertically against the DRAW AREA and select the pixel in the PAIR (odd/even) that match the result of the pixel we want to test.
	assign				isLineRightPix			= ( pixelX[0] & isLeftPRXInside & isRightPRXInside);
	assign				isLineLeftPix			= (!pixelX[0] & isLeftPLXInside & isRightPLXInside);
	assign				isLineInsideDrawArea	= isValidHorizontal & (isLineRightPix | isLineLeftPix);
	// Is Inside Triangle & Box rendering (Draw Area Inter. BBox)
	assign				isInsideBBoxTriRectL	= isValidHorizontalTriBbox & isLeftPLXminTri & isRightPLXmaxTri;
	assign				isInsideBBoxTriRectR	= isValidHorizontalTriBbox & isLeftPRXminTri & isRightPRXmaxTri;

	// --- For Triangle ---
	// Bounding box triangle.
	// Vertex0/Vertex1 Box
	wire signed [11:0]	minX0X1 = isNegXAxis   ? RegX1 : RegX0;
	wire signed [11:0]	maxX0X1 = isNegXAxis   ? RegX0 : RegX1;
	wire signed [11:0]	minY0Y1 = isNegYAxis   ? RegY1 : RegY0;
	wire signed [11:0]	maxY0Y1 = isNegYAxis   ? RegY0 : RegY1;
	// Vertex0/1/2 Box
	wire signed [11:0]	minXTri;
	wire signed [11:0]	maxXTri;
	assign				minXTri = RegX2 < minX0X1 ? RegX2 : minX0X1;
	wire signed [11:0]	minYTri = RegY2 < minY0Y1 ? RegY2 : minY0Y1;
	assign				maxXTri = RegX2 > maxX0X1 ? RegX2 : maxX0X1;
	wire signed [11:0]	maxYTri = RegY2 > maxY0Y1 ? RegY2 : maxY0Y1;

	// Primitive Size
	wire invalidX2X0   = !((preA13[12:10]==  3'b000) | (preA13[12:10]==  3'b111));
	wire invalidX1X0   = !((   c13[12:10]==  3'b000) | (   c13[12:10]==  3'b111));
	wire invalidY2Y0   = !((preB13[12: 9]== 4'b0000) | (preB13[12: 9]== 4'b1111));
	wire invalidY1Y0   = !((   d13[12: 9]== 4'b0000) | (   d13[12: 9]== 4'b1111));
	wire rejectTriSize = invalidX1X0 | invalidX2X0 | invalidY1Y0 | invalidY2Y0; // 1023 pixel in --> direction, 1024 pixel in <-- direction, 511 pixel in V direction, -512 pixel in ^ direction.
	// Bounding box vs Draw Area.

	// [Setup]
	wire				earlyTriRejectLeft   = maxXTri  < extDAX0;
	wire				earlyTriRejectTop    = maxYTri  < extDAY0;
	wire				earlyTriRejectRight  = minXTri  > extDAX1; // PIXEL IS INCLUSIVE, so reject must test AFTER last pixel in X DRAW AREA.
	wire				earlyTriRejectBottom = minYTri  > extDAY1; // PIXEL IS INCLUSIVE, so reject must test AFTER last pixel in Y DRAW AREA.
	/* PERFORMANCE OPTIMIZATION
	wire				earlyLineReject      = invalidX1X0 | invalidY1Y0; // | earlyLineRejectLeft | earlyLineRejectTop | earlyLineRejectRight | earlyLineRejectBottom;
	wire				earlyLineRejectLeft  = maxX0X1  < extDAX0;
	wire				earlyLineRejectTop   = maxY0Y1  < extDAY0;
	wire				earlyLineRejectRight = minX0X1 >= extDAX1;
	wire				earlyLineRejectBottom= minY0Y1 >= extDAY1;
	*/

	// Thanks to earlyTriangleReject, we know the box are intersecting.
	// We know that Box is properly oriented (Min < Max), we assume that DrawArea X0 < X1 too.
	// [Setup]
	wire signed [11:0]	minTriDAX0 = minXTri  < extDAX0 ? extDAX0 : minXTri;
	wire signed [11:0]	maxTriDAX1 = maxXTri >= extDAX1 ? extDAX1 : maxXTri;
	wire signed [11:0]	minTriDAY0 = minYTri  < extDAY0 ? extDAY0 : minYTri;
	wire signed [11:0]	maxTriDAY1 = maxYTri >= extDAY1 ? extDAY1 : maxYTri;

	// =================================================================
	// --- For Lines
	// =================================================================
	
	//------------------------------------------------------------------
	// [Setup] Line
	//------------------------------------------------------------------
	wire				isNegXAxis = c[11];
	wire				isNegYAxis = d[11];
	wire        [11:0]  absXAxis   = isNegXAxis ? negc : c;
	wire        [11:0]  absYAxis   = isNegYAxis ? negd : d;
	wire                swapAxis   = absYAxis > absXAxis;
	wire signed [11:0]  aDX2       = swapAxis ? absYAxis : absXAxis;
	wire signed [11:0]  aDY2       = swapAxis ? absXAxis : absYAxis;
	wire        [13:0]  initialD   = { 1'b0 ,aDY2, !swapAxis };

	//------------------------------------------------------------------
	// Runtime Lines
	//------------------------------------------------------------------
	wire signed [13:0]  compD      = { 2'b0 , aDX2 };
	wire                changeDir  = DLine > compD;
	wire        [12:0]  incrDOff   = (~{ aDX2, 1'b0 }) + 13'd1; // -2 * aDX2
	wire        [13:0]  incrD      = { 1'b0, aDY2, 1'b0 } + (changeDir ? { incrDOff[12] , incrDOff } : 14'd0);
	wire                incXOK     = (changeDir &  (swapAxis)) | (!swapAxis);
	wire                incYOK     = (changeDir & (!swapAxis)) |   swapAxis;
	wire signed  [1:0]  stepX      = { isNegXAxis & incXOK, incXOK }; // -1/+1 when needed, or 0.
	wire signed  [1:0]  stepY      = { isNegYAxis & incYOK, incYOK }; // -1/+1 when needed, or 0.
	wire signed [11:0]  incrX      = { {10{stepX[1]}}, stepX };
	wire signed [11:0]  incrY      = { {10{stepY[1]}}, stepY };
	wire signed [13:0]  nextD      = DLine + incrD;
	
	reg  signed [13:0]  DLine;
	always @(posedge i_clk)
		if (i_lineStart /* currWorkState == LINE_START */) begin
			DLine <= initialD;
		end else begin
			if (i_loadNext) begin
				DLine <= nextD;
			end
		end

	wire tstRightEqu0 = maxTriDAX1[0] ? w0R[EQUMSB] : w0L[EQUMSB];
	wire tstRightEqu1 = maxTriDAX1[0] ? w1R[EQUMSB] : w1L[EQUMSB];
	wire tstRightEqu2 = maxTriDAX1[0] ? w2R[EQUMSB] : w2L[EQUMSB];

	// ----
	// [Setup] AT Register Loading.
	wire signed [11:0]	a		= i_bIsLineCommand ?    d : preA;
	wire signed [11:0]	b		= i_bIsLineCommand ? negc : preB;
	wire signed [11:0]	negb	= -b;
	wire signed [11:0]	nega	= -a;

	reg signed [11:0]	ra,rd,rnegb,rnegc;
	
	// Pipeline to do a,d,b,negc...
	wire signed [21:0]	/*P*/ DET1	= a * d;
	wire signed [21:0]	/*P*/ DET2	= b * negc;		// -b*c -> b*negc
	reg  signed [21:0]	/*P*/ rDET1,rDET2,rDET;

	// PIPELINE THAT SIDE OF THE DIVIDER INPUT.
	always @(posedge i_clk) begin
		ra		<= a;
		rd		<= d;
		rnegb	<= negb;
		rnegc	<= negc;
		
		// Warning order
		rDET	<= rDET1 + rDET2;
		
		rDET1	<= DET1;
		rDET2	<= DET2;
	end
	
	reg signed [11:0]	mulFA,mulFB;
	reg  signed [9:0]	v0C,v1C,v2C;

	// ------------------------------------------------------------------
	// 1st Step : Pipeline Compo/Vect from state machine, isolate.
	// ------------------------------------------------------------------
	reg [2:0] compoID; // Normally = i_compoID
	reg       vectID;
	reg		  part;
	always @(posedge i_clk) begin
		compoID 	<= i_interpolationCounter[4:2];
		vectID		<= i_interpolationCounter[1];
`ifndef DOUBLE_DIVUNIT
		part		<= i_interpolationCounter[0];
`endif
	end

//	wire [2:0] compoID = i_interpolationCounter[4:2];
//	wire       vectID  = i_interpolationCounter[1];

	reg [2:0] compoID2,compoID3,compoID4,compoID5,compoID6,compoID7;
	reg       vecID2,vecID3,vecID4,vecID5,vecID6,vecID7;
`ifndef DOUBLE_DIVUNIT
	reg		  part2,part3,part4,part5,part6,part7;
`endif
	always @(posedge i_clk)
	begin
		compoID7 <= compoID6;
		compoID6 <= compoID5;
		compoID5 <= compoID4;
		compoID4 <= compoID3;
		compoID3 <= compoID2;
		compoID2 <= compoID;

		vecID7   <= vecID6;
		vecID6   <= vecID5;
		vecID5   <= vecID4;
		vecID4   <= vecID3;
		vecID3   <= vecID2;
		vecID2   <= vectID;
		
`ifndef DOUBLE_DIVUNIT
		part7	 <= part6;
		part6	 <= part5;
		part5	 <= part4;
		part4	 <= part3;
		part3	 <= part2;
		part2	 <= part;
`endif
	end

	always @(*)
	begin
		case (compoID)
		default:	begin v0C = { 1'b0, RegR0 }; v1C = { 1'b0, RegR1 }; v2C = { 1'b0, RegR2 }; end
		3'd2:		begin v0C = { 1'b0, RegG0 }; v1C = { 1'b0, RegG1 }; v2C = { 1'b0, RegG2 }; end
		3'd3:		begin v0C = { 1'b0, RegB0 }; v1C = { 1'b0, RegB1 }; v2C = { 1'b0, RegB2 }; end
		3'd4:		begin v0C = { 2'b0, RegU0 }; v1C = { 2'b0, RegU1 }; v2C = { 2'b0, RegU2 }; end
		3'd5:		begin v0C = { 2'b0, RegV0 }; v1C = { 2'b0, RegV1 }; v2C = { 2'b0, RegV2 }; end
		endcase

		if (vectID) begin
			mulFA = rnegc;	mulFB = ra;
		end else begin
			mulFA = rd;   	mulFB = rnegb;
		end
	end
	wire signed [10:0]  negv0c  = -{1'b0,v0C};
	wire signed [10:0]	C20i	= i_bIsLineCommand ? 11'd0 : ({ 1'b0 ,v2C } + negv0c);
	wire signed [10:0]	C10i	=  { 1'b0 ,v1C } + negv0c; // -512..+511

	// TODO : Use i_interpolationCounter[1] and mux inputDivA / inputDivB
	wire signed [20:0] inputDivA	= mulFA * C20i; // -2048..+2047 x -512..+511 = Signed 21 bit.
	wire signed [20:0] inputDivB	= mulFB * C10i;

	parameter PREC				= 12;
	wire [PREC+8:0] ZERO_PREC	= 0;
	wire [PREC+8:0] ONE_PREC	= 20'h1 << PREC;
	wire [PREC+8:0] HALF_PREC	= ONE_PREC >> 1;
	
`ifdef DOUBLE_DIVUNIT
	// Signed 21 bit << 11 bit => 32 bit signed value.
	wire signed [31:0] inputDivAShftPre= { 11'b0, inputDivA } << PREC; // PREC'd0
`else
	wire signed [31:0] inputDivAShftPre= { 11'b0, i_interpolationCounter[0] ? inputDivB : inputDivA } << PREC; // PREC'd0
`endif

	reg signed [31:0] inputDivAShft;
	always @(posedge i_clk)
		inputDivAShft <= inputDivAShftPre;
		
	wire signed [PREC+8:0] outputA;
	wire signed [PREC+8:0] outputB;	
	dividerWrapper #(.OUTSIZE(PREC+9)) instDivisorA(
		.clock			( i_clk ),
		.numerator		( inputDivAShft),
		.denominator	( rDET ),
		.outputV		( outputA )
	);

`ifdef DOUBLE_DIVUNIT
	wire signed [31:0] inputDivBShftPre= { 11'b0, inputDivB } << PREC;

	reg signed [31:0] inputDivBShft;
	always @(posedge i_clk)
		inputDivBShft <= inputDivBShftPre;
	
	dividerWrapper #(.OUTSIZE(PREC+9)) instDivisorB(
		.clock			( i_clk ),
		.numerator 		( inputDivBShft ),
		.denominator 	( rDET ),
		.outputV 		( outputB )
	);

	// 11 bit prec + 9 bit = 20 bit.
	wire signed [PREC+8:0] perPixelComponentIncrement = outputA + outputB;
`else
	reg signed [PREC+8:0] RegOutputA;
	always @(posedge i_clk) begin
		RegOutputA <= outputA;
	end

	// 11 bit prec + 9 bit = 20 bit.
	wire signed [PREC+8:0] perPixelComponentIncrement = RegOutputA + outputA;
`endif


	// ---------------------------------------------------------------------------------------------------------------------
	//  [ Interpolator Storage Stage ]
	// ---------------------------------------------------------------------------------------------------------------------

	reg signed [PREC+8:0] RSX,RSY,GSX,GSY,BSX,BSY,USX,USY,VSX,VSY; // 1..10 Write, 0:Do nothing.

	wire /*reg*/ [3:0]	assignDivResult = { compoID7, vecID7 }; // 1..A, 0 none
	always @(posedge i_clk) begin
`ifndef DOUBLE_DIVUNIT
		if (part7) begin
`endif
			if (assignDivResult == 4'd2) begin RSX <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd3) begin RSY <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd4) begin GSX <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd5) begin GSY <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd6) begin BSX <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd7) begin BSY <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd8) begin USX <= perPixelComponentIncrement; end
			if (assignDivResult == 4'd9) begin USY <= perPixelComponentIncrement; end
			if (assignDivResult == 4'hA) begin VSX <= perPixelComponentIncrement; end
			if (assignDivResult == 4'hB) begin VSY <= perPixelComponentIncrement; end
`ifndef DOUBLE_DIVUNIT
		end
`endif

		// Assign rasterization parameter for RECT mode.
		if (i_assignRectSetup) begin
			RSX <= ZERO_PREC;
			RSY <= ZERO_PREC;
			GSX <= ZERO_PREC;
			GSY <= ZERO_PREC;
			BSX <= ZERO_PREC;
			BSY <= ZERO_PREC;
			USX <= ONE_PREC;
			USY <= ZERO_PREC;
			VSX <= ZERO_PREC;
			VSY <= ONE_PREC;
		end
	end

	// EQUMSB=22
	// D12(e   ,f)-> isTopLeft(D12) -> f    < 0 || (   f == 0) & e    < 0
	// D20(nega,b)-> isTopLeft(D20) -> b    < 0 || (   b == 0) & nega < 0
	// D01(c,negd)-> isTopLeft(D01) -> negd < 0 || (negd == 0) & c    < 0
	wire isTopLeftD12 					=    f[11] | ((   f == 12'd0) &    e[11]);
	wire isTopLeftD01 					= negd[11] | ((negd == 12'd0) &    c[11]);
	wire isTopLeftD20 					=    b[11] | ((   b == 12'd0) & nega[11]);

	wire signed [EQUMSB:0] bias0		= {23{isTopLeftD12}}; // -1 if true, 0 if false.
	wire signed [EQUMSB:0] bias1		= {23{isTopLeftD20}};
	wire signed [EQUMSB:0] bias2		= {23{isTopLeftD01}};
	
	// ---------------------------------------------------------------------------------------------------------------------
	//  [ Interpolator Compute Stage ]
	// ---------------------------------------------------------------------------------------------------------------------

	wire signed [11:0] distXV0 			= pixelX + nRegX0;
	wire signed [11:0] distYV0 			= pixelY + nRegY0;
	wire signed [11:0] distXV1 			= pixelX + nRegX1;
	wire signed [11:0] distYV1 			= pixelY + nRegY1;
	wire signed [11:0] distXV2 			= pixelX + nRegX2;
	wire signed [11:0] distYV2 			= pixelY + nRegY2;

	wire signed [EQUMSB:0] w0L,w1L,w2L,w0R,w1R,w2R;

	assign w0L							= (   e*distYV1) + (   f*distXV1) + bias0;
	assign w1L							= (nega*distYV2) + (   b*distXV2) + bias1;
	assign w2L							= (   c*distYV0) + (negd*distXV0) + bias2;

	assign w0R							= w0L + { {11{f[11]}}, f};
	assign w1R							= w1L + { {11{b[11]}}, b};
	assign w2R							= w2L + { {11{negd[11]}}, negd};

	reg memW0,memW1,memW2;
	always @(posedge i_clk)
		if (i_memorizeLineEqu) begin
			// Backup the edge result for FIST PIXEL INSIDE BBOX.
			memW0 <= minTriDAX0[0] ? w0R[EQUMSB] : w0L[EQUMSB];
			memW1 <= minTriDAX0[0] ? w1R[EQUMSB] : w1L[EQUMSB];
			memW2 <= minTriDAX0[0] ? w2R[EQUMSB] : w2L[EQUMSB];
		end
	/*
		[Original Implementation in Avocado, based on the famous Ryg article about rasterization.]
		if ((w0L | w1L | w2L) > 0) {    but Avocado always garantee CCW oriented polygon.

		First, we can notice that the condition does not seems accurate :
		By 'oring' we allow one or two line equation >= 0 if another is > 0.

		HW implementation of >= 0 is a LOT easier.
		Did not change a simple pixel on basic triangle I tested.

		For opposite orientation, I use the opposite < 0.
	 */
	wire isCCWInsideL 					= !(w0L[EQUMSB] | w1L[EQUMSB] | w2L[EQUMSB]); // Same as : (w0 >= 0) && (w1 >= 0) && (w2 >= 0)
	wire isCWInsideL  					=  (w0L[EQUMSB] & w1L[EQUMSB] & w2L[EQUMSB]); // Same as : (w0 <  0) && (w1  < 0) && (w2  < 0)
	wire isCCWInsideR 					= !(w0R[EQUMSB] | w1R[EQUMSB] | w2R[EQUMSB]);
	wire isCWInsideR  					=  (w0R[EQUMSB] & w1R[EQUMSB] & w2R[EQUMSB]);

	//
	// [Component Interpolation Out]
	//
	wire signed [PREC+8:0] roundComp 	= HALF_PREC; // PRECM1'd0
	wire signed [PREC+8:0] offR 		= (distXV0*RSX) + (distYV0*RSY) + roundComp;
	wire signed [PREC+8:0] offG 		= (distXV0*GSX) + (distYV0*GSY) + roundComp;
	wire signed [PREC+8:0] offB 		= (distXV0*BSX) + (distYV0*BSY) + roundComp;
	wire signed [PREC+8:0] offU 		= (distXV0*USX) + (distYV0*USY) + roundComp;
	wire signed [PREC+8:0] offV 		= (distXV0*VSX) + (distYV0*VSY) + roundComp;

	wire signed [PREC+8:0] offRR 		= offR + RSX;
	wire signed [PREC+8:0] offGR 		= offG + GSX;
	wire signed [PREC+8:0] offBR 		= offB + BSX;
	wire signed [PREC+8:0] offUR 		= offU + USX;
	wire signed [PREC+8:0] offVR 		= offV + VSX;
	
	assign o_pixRL 						= RegR0 + offR[PREC+8:PREC]; // TODO Here ?
	assign o_pixGL 						= RegG0 + offG[PREC+8:PREC];
	assign o_pixBL 						= RegB0 + offB[PREC+8:PREC];
	assign o_pixUL 						= RegU0 + offU[PREC+7:PREC];
	assign o_pixVL 						= RegV0 + offV[PREC+7:PREC];

	assign o_pixRR 						= RegR0 + offRR[PREC+8:PREC];
	assign o_pixGR 						= RegG0 + offGR[PREC+8:PREC];
	assign o_pixBR 						= RegB0 + offBR[PREC+8:PREC];
	assign o_pixUR 						= RegU0 + offUR[PREC+7:PREC];
	assign o_pixVR 						= RegV0 + offVR[PREC+7:PREC];

	assign o_isNULLDET					= (/*P*/rDET == 22'd0);
	assign o_isNegXAxis					= isNegXAxis;
	assign o_isValidPixelL				= (isCCWInsideL | isCWInsideL) & isInsideBBoxTriRectL;
	assign o_isValidPixelR				= (isCCWInsideR | isCWInsideR) & isInsideBBoxTriRectR;
	assign o_earlyTriangleReject		= earlyTriRejectLeft | earlyTriRejectRight | earlyTriRejectTop | earlyTriRejectBottom | rejectTriSize;

	// Check that TRIANGLE EDGE did not SWITCH between the LEFT and RIGHT side of the bounding box.
	assign o_edgeDidNOTSwitchLeftRightBB = (memW0 == tstRightEqu0) && (memW1 == tstRightEqu1) && (memW2 == tstRightEqu2);
	
	assign o_isValidHorizontalTriBbox	= isValidHorizontalTriBbox;
	assign o_isRightPLXmaxTri			= isRightPLXmaxTri;
	assign o_isInsideBBoxTriRectL		= isInsideBBoxTriRectL;
	assign o_isInsideBBoxTriRectR		= isInsideBBoxTriRectR;
	assign o_isBottomInsideBBox			= isBottomInsideBBox;
	
	assign o_isLineInsideDrawArea		= isLineInsideDrawArea;
	assign o_isLineLeftPix				= isLineLeftPix;
	assign o_isLineRightPix				= isLineRightPix;
	assign o_isNegPreB					= preB[11];
	
	assign o_nextLineX					= pixelX + incrX;
	assign o_nextLineY					= pixelY + incrY;	
	
	assign o_minTriDAX0 				= minTriDAX0;
	assign o_maxTriDAX1 				= maxTriDAX1;
	assign o_minTriDAY0 				= minTriDAY0;
	assign o_reachEdgeTriScan			= (((pixelX > maxXTri) & !i_scanDirectionR2L) || ((pixelX < minXTri) & i_scanDirectionR2L));

endmodule
