module GPUVideo(
	input			i_gpuPixClk,
	input			i_nRst,
	
	input			i_PAL,	// If false -> PAL
	input			i_IsInterlace,
	input			GPU_REG_HorizResolution368,
	input	[1:0]	GPU_REG_HorizResolution,
	
	input	[11:0]	GPU_REG_RangeX0,
	input	[11:0]	GPU_REG_RangeX1,
	input	[9:0]	GPU_REG_RangeY0,
	input	[9:0]	GPU_REG_RangeY1,

	output			o_dotClockFlag,

	output			o_hbl,
	output			o_vbl,
	
	output			currentInterlaceField,
	output			currentLineOddEven,
	output  [9:0]	widthDisplay,
	output	[8:0]	heightDisplay
);

/*
  263 scanlines per field for NTSC non-interlaced
  262.5 scanlines per field for NTSC interlaced

  314 scanlines per field for PAL non-interlaced
  312.5 scanlines per field for PAL interlaced
*/
wire [9:0] scanlineCount = i_PAL ? 10'd314 : 10'd263;
									// TODO Support Interlace.

wire dotClockFlag;
reg [3:0] dotClockDiv;
reg [9:0] horizRes;
always @(*) begin
	if (GPU_REG_HorizResolution368) begin
		dotClockDiv /*368*/ = 4'd7;
		horizRes			= 10'd368;
	end else begin
		case (GPU_REG_HorizResolution)
		2'd0 /*256*/: begin dotClockDiv = 4'd10;	horizRes = 10'd256; end
		2'd1 /*320*/: begin dotClockDiv = 4'd8;		horizRes = 10'd320; end
		2'd2 /*512*/: begin dotClockDiv = 4'd5;		horizRes = 10'd512; end
		2'd3 /*640*/: begin dotClockDiv = 4'd4;		horizRes = 10'd640; end
		endcase
	end
end

reg  [3:0] gpuPixClkCount;
wire [3:0] nextgpuPixClkCount = gpuPixClkCount + 4'd1;
assign dotClockFlag = (nextgpuPixClkCount == dotClockDiv);			// USED BY TIMER0
always @(posedge i_gpuPixClk) begin
	gpuPixClkCount <= dotClockFlag ? 4'd0 : nextgpuPixClkCount;
end

reg [11:0]	VidXCounter;
reg [11:0]  PureVidX;

reg [9:0]	VidYCounter;
wire [11:0] nextVidXCounter = VidXCounter + { 8'd0 , dotClockDiv };
wire goNextLine;
wire goNextFrame = VidYCounter == scanlineCount;
reg REG_CurrentInterlaceField;

always @(posedge i_gpuPixClk) begin // In GPU CLOCK ANYWAY
	if (goNextLine) begin
		VidXCounter		<= 12'd0;
		PureVidX		<= 12'd0;
	end else begin
		VidXCounter 	<= dotClockFlag ? nextVidXCounter : VidXCounter;
		PureVidX		<= PureVidX + { 12'd1 };
	end
	VidYCounter					<= goNextFrame ? 10'd0                      : VidYCounter + { 9'd0, goNextLine };
	REG_CurrentInterlaceField	<= goNextFrame ? !REG_CurrentInterlaceField : REG_CurrentInterlaceField;
end

wire DisplayHSync           = (PureVidX    == 12'd0);
wire VideoStarted           = (PureVidX    == 12'd488);
wire DisplayStarted         = (VidXCounter >= GPU_REG_RangeX0);
wire DisplayEnded           = (VidXCounter >= GPU_REG_RangeX1);
wire VideoEnded             = (PureVidX    == 12'd3312);
// Reset counter @ xcounter next HSYNC
assign goNextLine			= (PureVidX    ==  (i_PAL  ? {                 12'd3406 }		// PAL
                                                       : { 11'd1076, VidYCounter[0] }));	// NTSC : 3412 on ODD line, 3413 on EVEN LINE.
													   
wire DisplayStartedY		= (VidYCounter >= GPU_REG_RangeY0);
wire DisplayEndedY			= (VidYCounter >= GPU_REG_RangeY1);
//---------------------------------------------------------------------------------------------------

assign widthDisplay			= horizRes;								// TODO : Abstract value, not real...
assign currentInterlaceField= REG_CurrentInterlaceField;
assign o_dotClockFlag		= dotClockFlag;
assign currentLineOddEven	= VidYCounter[0];
assign o_hbl				= DisplayEnded | (!VideoStarted);
assign o_vbl				= DisplayEndedY| (!DisplayStartedY); 	// TODO Check VBL
																	// TODO HSync, VSync too : WARNING => just need a spike according to CRTs.

endmodule
