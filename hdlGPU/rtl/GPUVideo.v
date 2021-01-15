/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module GPUVideo(
	/*	NTSC video clock = 53.693175 MHz
		PAL video clock  = 53.203425 MHz	 */
	input			i_gpuPixClk,
	input			i_nRst,
	
	input			i_PAL,	// If false -> NTSC
	input			i_IsInterlace,
	input			GPU_REG_HorizResolution368,
	input	[1:0]	GPU_REG_HorizResolution,
	
	input	[11:0]	GPU_REG_RangeX0,
	input	[11:0]	GPU_REG_RangeX1,
	input	[9:0]	GPU_REG_RangeY0,
	input	[9:0]	GPU_REG_RangeY1,

	output			o_dotClockFlag,
	output			o_dotEnableFlag,

	output			o_hbl,
	output			o_vbl,
	
	output			o_hSync,
	output			o_vSync,
	
	output			currentInterlaceField,
	output			currentLineOddEven,
	output  [9:0]	widthDisplay
);

/*
  263 scanlines per field for NTSC non-interlaced
  262.5 scanlines per field for NTSC interlaced

  314 scanlines per field for PAL non-interlaced
  312.5 scanlines per field for PAL interlaced
*/
wire [9:0] scanlineCount = i_PAL ? 10'd314 : 10'd263;
									// TODO Support Interlace.

reg [3:0] dotClockDiv;
reg [3:0] dotLastDiv;
reg [9:0] horizRes;
reg  [3:0] gpuPixClkCount;
reg  [3:0] gpuPixEnableCount;
reg REG_CurrentInterlaceField;
reg [11:0]	VidXCounter;
reg [11:0]  PureVidX;
reg [9:0]	VidYCounter;

wire [3:0] nextgpuPixClkCount    = gpuPixClkCount    + 4'd1;

wire [3:0] nextgpuPixEnableCount = gpuPixEnableCount + 4'd1;

wire [11:0] nextVidXCounter = VidXCounter + { 8'd0 , dotClockDiv };
wire goNextLine;
wire goNextFrame = VidYCounter == scanlineCount;

// wire DisplayHSync        = (PureVidX >= 12'd0); <--- Always TRUE
wire DisplayNoHSync			= (PureVidX >= 12'd268); // 53,693,175 Hz * 0.000,005 Sec = 268.465875 => 5uSec dip of HSync, for now same in NTSC and PAL.
wire VideoStarted           = (PureVidX >= 12'd488);
wire DisplayStarted         = (VidXCounter >= GPU_REG_RangeX0);
wire DisplayEnded           = (VidXCounter >= GPU_REG_RangeX1);
wire DisplayStartedY		= (VidYCounter >= GPU_REG_RangeY0);
wire DisplayEndedY			= (VidYCounter >= GPU_REG_RangeY1);
//---------------------------------------------------------------------------------------------------

wire hbl = DisplayEnded | (!VideoStarted);
wire vbl = DisplayEndedY| (!DisplayStartedY);

wire dotClockFlag  = (nextgpuPixClkCount    == dotClockDiv);			// USED BY TIMER0
wire dotEnableFlag = ((nextgpuPixEnableCount == dotClockDiv) && !hbl);

always @(*) begin
	if (GPU_REG_HorizResolution368) begin
		dotClockDiv /*368*/ = 4'd7;
		dotLastDiv			= 4'd6;
		horizRes			= 10'd368;
	end else begin
		case (GPU_REG_HorizResolution)
		2'd0 /*256*/: begin dotClockDiv = 4'd10;	dotLastDiv = 4'd9; horizRes = 10'd256; end
		2'd1 /*320*/: begin dotClockDiv = 4'd8;		dotLastDiv = 4'd7; horizRes = 10'd320; end
		2'd2 /*512*/: begin dotClockDiv = 4'd5;		dotLastDiv = 4'd4; horizRes = 10'd512; end
		2'd3 /*640*/: begin dotClockDiv = 4'd4;		dotLastDiv = 4'd3; horizRes = 10'd640; end
		endcase
	end
end

always @(posedge i_gpuPixClk) begin
	gpuPixClkCount    <= dotClockFlag ? 4'd0 :    nextgpuPixClkCount;

	if (goNextLine || hbl) begin
		gpuPixEnableCount <= dotLastDiv;
	end else begin
		gpuPixEnableCount <= dotEnableFlag ? 4'd0 : nextgpuPixEnableCount;
	end
end

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

/*	https://wiki.neogeodev.org/index.php?title=Display_timing
	Corrected from and added on from mvstech.txt (by Charles MacDonald).

	There are 264 scanlines per frame:

		8 scanlines vertical sync pulse
		16 scanlines top border (active in PAL, blanked in NTSC)
		224 scanlines active display
		16 scanlines bottom border (active in PAL, blanked in NTSC) 

	HERE THE PSX DOC SAYS 263 and not 264 but that's ok I kind of guess...
	[==> So I will put 0..7 as Vertical Sync Pulse.]
*/
// wire DisplayVSync           = (VidYCounter >= 10'd0);	<-- Always TRUE
wire DisplayNoVSync			= (VidYCounter >= 10'd8);

// Reset counter @ xcounter next HSYNC
assign goNextLine			= (PureVidX    ==  (i_PAL  ? {                 12'd3406 }		// PAL
                                                       : { 11'd1706, VidYCounter[0] }));	// NTSC : 3412 on ODD line, 3413 on EVEN LINE.
													   

assign widthDisplay			= horizRes;								// TODO : Abstract value, not real...
assign currentInterlaceField= REG_CurrentInterlaceField;

/* TODO : Timer0 can use the dotclock as input, however, the Timer0 input "ignores" the fractional portions (in most cases, 
   the values are rounded down, ie. with 340.6 dots/line, the timer increments only 340 times/line; the only value that is rounded up is 425.75 dots/line) \
   (for example, due to the rounding, the timer isn't running exactly twice as fast in 512pix/PAL mode than in 256pix/PAL mode). 
   The dotclock signal is generated even during horizontal/vertical blanking/retrace. */
assign o_dotClockFlag		= dotClockFlag;
assign o_dotEnableFlag		= (!hbl && !vbl) && DisplayStarted && dotEnableFlag;
assign currentLineOddEven	= VidYCounter[0];
assign o_hbl				= hbl;
assign o_vbl				= vbl;
assign o_hSync				= !(/*DisplayHSync Always true, start from 0 & */ (!DisplayNoHSync));	// NEGATIVE LOGIC
assign o_vSync				= !(/*DisplayVSync <--- ALWAYS TRUE          & */ (!DisplayNoVSync));	// NEGATIVE LOGIC

endmodule
