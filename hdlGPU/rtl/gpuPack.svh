/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

package gpuPack;

/*
// ----------------------------- Parsing Stage -----------------------------------
reg signed [10:0] GPU_REG_OFFSETX;
reg signed [10:0] GPU_REG_OFFSETY;
reg         [3:0] GPU_REG_TexBasePageX;
reg               GPU_REG_TexBasePageY;
reg         [1:0] GPU_REG_Transparency; parameter TRANSP_HALF=2'd0, TRANSP_ADD=2'd1, TRANSP_SUB=2'd2, TRANSP_ADDQUARTER=2'd3;
reg         [1:0] GPU_REG_TexFormat;	parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;
reg               GPU_REG_DitherOn;
reg               GPU_REG_DrawDisplayAreaOn;
reg               GPU_REG_TextureDisable;
reg               GPU_REG_TextureXFlip;
reg               GPU_REG_TextureYFlip;
reg         [4:0] GPU_REG_WindowTextureMaskX;
reg         [4:0] GPU_REG_WindowTextureMaskY;
reg         [4:0] GPU_REG_WindowTextureOffsetX;
reg         [4:0] GPU_REG_WindowTextureOffsetY;
reg         [9:0] GPU_REG_DrawAreaX0;
reg         [9:0] GPU_REG_DrawAreaY0;				// 8:0 on old GPU.
reg         [9:0] GPU_REG_DrawAreaX1;
reg         [9:0] GPU_REG_DrawAreaY1;				// 8:0 on old GPU.
reg               GPU_REG_ForcePixel15MaskSet;		// Stencil force to 1.
reg               GPU_REG_CheckMaskBit; 			// Stencil Read/Compare Enabled

reg               GPU_REG_IRQSet;
reg               GPU_REG_DisplayDisabled;
reg               GPU_REG_IsInterlaced;
reg               GPU_REG_BufferRGB888;
reg               GPU_REG_VideoMode;
reg               GPU_REG_VerticalResolution;
reg         [1:0] GPU_REG_HorizResolution;	parameter XRES_256=2'd0, XRES_320=2'd1, XRES_512=2'd2, XRES_640=2'd3;
reg               GPU_REG_HorizResolution368;
reg         [1:0] GPU_REG_DMADirection;		parameter DMADIR_OFF=2'd0, DMADIR_FIFO=2'd1, DMADIR_C2G=2'd2, DMADIR_G2C=2'd3;
reg			[9:0] GPU_REG_DispAreaX;
reg			[8:0] GPU_REG_DispAreaY;
reg			[11:0] GPU_REG_RangeX0;
reg			[11:0] GPU_REG_RangeX1;
reg			[9:0] GPU_REG_RangeY0;
reg			[9:0] GPU_REG_RangeY1;
reg				  GPU_REG_ReverseFlag;
reg					GPU_DisplayEvenOddLinesInterlace;	// TODO
reg					GPU_REG_CurrentInterlaceField;		// TODO


// -2048..+2047
reg signed [11:0] RegX0;
reg signed [11:0] RegY0;
reg  [8:0] RegR0;
reg  [8:0] RegG0;
reg  [8:0] RegB0;
reg  [7:0] RegU0;
reg  [7:0] RegV0;
reg signed [11:0] RegX1;
reg signed [11:0] RegY1;
reg  [8:0] RegR1;
reg  [8:0] RegG1;
reg  [8:0] RegB1;
reg  [7:0] RegU1;
reg  [7:0] RegV1;
reg signed [11:0] RegX2;
reg signed [11:0] RegY2;
reg  [8:0] RegR2;
reg  [8:0] RegG2;
reg  [8:0] RegB2;
reg  [7:0] RegU2;
reg  [7:0] RegV2;
reg [14:0] RegC ;
// [NOT USED FOR NOW : DIRECTLY MODIFY GLOBAL GPU STATE]
// reg  [9:0] RegTx;
reg [10:0] RegSizeW;
reg [ 9:0] RegSizeH;
reg [ 9:0] OriginalRegSizeH;


*/

typedef enum logic[5:0] {
    NOT_WORKING_DEFAULT_STATE	= 6'd0,
    LINE_START					= 6'd1,
    LINE_DRAW					= 6'd2,
    RECT_START					= 6'd3,
    FILL_START					= 6'd4,
    COPY_INIT					= 6'd5,
    TRIANGLE_START				= 6'd6,
    FILL_LINE  					= 6'd7,
    COPYCV_START 				= 6'd8,
    COPYVC_START 				= 6'd9,
	CPY_RS1						= 6'd10,
	CPY_R1						= 6'd11,
	CPY_RS2						= 6'd12,
	CPY_R2						= 6'd13,
	CPY_LWS1					= 6'd14,
	CPY_LW1						= 6'd15,
	CPY_LRS						= 6'd16,
	CPY_LR						= 6'd17,
	CPY_WS2						= 6'd18,
	CPY_W2						= 6'd19,
	CPY_WS3						= 6'd20,
	CPY_W3						= 6'd21,
	START_LINE_TEST_LEFT		= 6'd22,
	START_LINE_TEST_RIGHT		= 6'd23,
	SCAN_LINE					= 6'd24,
	SCAN_LINE_CATCH_END			= 6'd25,
	TMP_2 						= 6'd26,
	TMP_3 						= 6'd27,
	TMP_4 						= 6'd28,
	SETUP_RX					= 6'd29,
	SETUP_RY					= 6'd30,
	SETUP_GX					= 6'd31,
	SETUP_GY					= 6'd32,
	SETUP_BX					= 6'd33,
	SETUP_BY					= 6'd34,
	SETUP_UX					= 6'd35,
	SETUP_UY					= 6'd36,
	SETUP_VX					= 6'd37,
	SETUP_VY					= 6'd38,
	RECT_SCAN_LINE				= 6'd39,
	WAIT_3						= 6'd40,
	WAIT_2						= 6'd41,
	WAIT_1						= 6'd42,
	SELECT_PRIMITIVE			= 6'd43,
	COPYCV_COPY					= 6'd44,
	RECT_READ_MASK				= 6'd45,
	COPYVC_TOCPU				= 6'd46,
	LINE_END					= 6'd47,
	FLUSH_COMPLETE_STATE		= 6'd48,
	COPY_START_LINE				= 6'd49,
	CPY_ENDLINE					= 6'd50
} workState_t;

//parameter
typedef enum logic[2:0] {
    X_TRI_NEXT		= 3'd1,
    X_LINE_START	= 3'd2,
    X_LINE_NEXT		= 3'd3,
    X_TRI_BBLEFT	= 3'd4,
    X_TRI_BBRIGHT	= 3'd5,
    X_ASIS			= 3'd0,
    // 7 free...
    X_CV_START		= 3'd6
} nextX_t;

//parameter
typedef enum logic[2:0] {
    Y_LINE_START	= 3'd1,
    Y_LINE_NEXT		= 3'd2,
    Y_TRI_START		= 3'd3,
    Y_TRI_NEXT		= 3'd4,
    Y_TRI_PREV		= 3'd5,
    Y_CV_ZERO		= 3'd6,
    // 7 free...
    Y_ASIS			= 3'd0
} nextY_t;


parameter EQUMSB = 22; // 11bit signed * 11 bit signed.

parameter	MEM_CMD_PIXEL2VRAM	= 3'b001,
            MEM_CMD_FILL		= 3'b010,
			MEM_CMD_RDBURST		= 3'b011,
			MEM_CMD_WRBURST		= 3'b100,
            // Other command to come later...
            MEM_CMD_NONE		= 3'b000;

parameter   IS_NOT_NEWBLOCK				= 2'b00,
            IS_NEW_BLOCK_IN_PRIMITIVE	= 2'b01,	// The first time we flush a 16 pixel block, there is NO WRITE of the previous block, but LOAD must be done if doing blending.
            IS_OTHER_BLOCK_IN_PRIMITIVE	= 2'b10,	// For other block we simply do WRITE the previous block, or WRITE + LOAD next block BG if doing blending.
            IS_FLUSH_LAST_PIXEL			= 2'b11;

parameter PREC = 11;
parameter PRECM1 = PREC-1;
parameter ZERO_PREC = 20'd0, ONE_PREC = 20'h800;

typedef enum logic[3:0] {
    DEFAULT_STATE		=4'd0,
    LOAD_COMMAND		=4'd1,
    COLOR_LOAD			=4'd2,
    VERTEX_LOAD			=4'd3,
    UV_LOAD				=4'd4,
    WIDTH_HEIGHT_STATE	=4'd5,
    LOAD_XY1			=4'd6,
    LOAD_XY2			=4'd7,
    WAIT_COMMAND_COMPLETE = 4'd8,
    COLOR_LOAD_GARAGE   =4'd9,
    VERTEX_LOAD_GARAGE	=4'd10
} state_t;

parameter TRANSP_HALF=2'd0, TRANSP_ADD=2'd1, TRANSP_SUB=2'd2, TRANSP_ADDQUARTER=2'd3;
parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3;

parameter XRES_256=2'd0, XRES_320=2'd1, XRES_512=2'd2, XRES_640=2'd3;
parameter DMADIR_OFF=2'd0, DMADIR_FIFO=2'd1, DMADIR_C2G=2'd2, DMADIR_G2C=2'd3;

parameter SIZE_VAR	= 2'd0, SIZE_1x1 = 2'd1, SIZE_8x8 = 2'd2, SIZE_16x16 = 2'd3;
parameter NO_ISSUE = 5'd0, ISSUE_TRIANGLE = 5'b00001,ISSUE_RECT = 5'b00010,ISSUE_LINE = 5'b00100,ISSUE_FILL = 5'b01000,ISSUE_COPY = 5'b10000;

typedef struct packed {
    logic       resetVertexCounter;
    logic       increaseVertexCounter;
    logic       loadRGB,loadUV,loadVertices,loadAllRGB;
    logic       storeCommand;
    logic       loadE5Offsets;
    logic       loadTexPageE1;
    logic       loadTexWindowSetting;
    logic       loadDrawAreaTL;
    logic       loadDrawAreaBR;
    logic       loadMaskSetting;
    logic       setIRQ;
    logic       rstTextureCache;
    logic       loadClutPage;
    logic       loadTexPage;
    logic       loadSize;
    logic       loadCoord1,loadCoord2;
    logic       loadRectEdge;
    logic       preCheckCLUT;
    logic [1:0] loadSizeParam;
    logic [4:0] issuePrimitive;
 } issue_t;

endpackage