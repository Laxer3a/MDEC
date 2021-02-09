/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`ifndef GPU_DEFINITION
`define GPU_DEFINITION

// USE TWO DIV UNIT IF DEFINED, ELSE ONE
`define DOUBLE_DIVUNIT

// Variable size parameter for rect.
parameter SIZE_VAR	= 2'd0, SIZE_1x1 = 2'd1, SIZE_8x8 = 2'd2, SIZE_16x16 = 2'd3;

// Parser state machine type of primitived emitted to work state machine.
parameter NO_ISSUE = 5'd0, ISSUE_TRIANGLE = 5'b00001,ISSUE_RECT = 5'b00010,ISSUE_LINE = 5'b00100,ISSUE_FILL = 5'b01000,ISSUE_COPY = 5'b10000;

parameter	MEM_CMD_PIXEL2VRAM	= 3'b001,
            MEM_CMD_FILL		= 3'b010,
            MEM_CMD_RDBURST		= 3'b011,
            MEM_CMD_WRBURST		= 3'b100,
			MEM_CMD_VRAM2CPU	= 3'b101,
            // Other command to come later...
            MEM_CMD_NONE		= 3'b000;

//parameter
typedef enum logic[2:0] {
    X_ASIS			= 3'd0,
    X_TRI_NEXT		= 3'd1,
    X_LINE_START	= 3'd2,
    X_LINE_NEXT		= 3'd3,
    X_TRI_BBLEFT	= 3'd4,
    X_TRI_BBRIGHT	= 3'd5,
    // 7 free...
    X_CV_START		= 3'd6
} nextX_t;

//parameter
typedef enum logic[2:0] {
    Y_ASIS			= 3'd0,
    Y_LINE_START	= 3'd1,
    Y_LINE_NEXT		= 3'd2,
    Y_TRI_START		= 3'd3,
    Y_TRI_NEXT		= 3'd4,
    Y_CV_ZERO		= 3'd5
    // 6,7 free...
} nextY_t;

typedef enum logic[1:0] {
	DMA_DirOff		= 2'd0,
	DMA_FIFO		= 2'd1,
	DMA_CPUtoGP0	= 2'd2,
	DMA_GP0toCPU	= 2'd3
} DMADirection;

parameter 	RDR_NONE			= 3'd0,
			RDR_SETUP_INTERP	= 3'd1,
			RDR_TRIANGLE_START	= 3'd2,
			RDR_LINE_START		= 3'd3,
			RDR_FILL_START		= 3'd4,
			RDR_WAIT_3			= 3'd5;

`endif // GPU_DEFINITION
