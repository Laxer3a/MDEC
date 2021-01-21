/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`include "gpu_def.sv"

module gpu_parser(
	input				i_clk,
	input				i_rstGPU,
	
	input	[7:0]		i_command,
	output				o_waitingNewCommand,

	// Runtime parameter from instruction
	input				i_bIgnoreColor,

	//================================================
	// Transaction management
	//================================================
	// GPU BUSY WORKING, Do not accept work.
	input				i_gpuBusy,	// Busy doing primitives. (!canIssueWork)
	// Request GPU TO become busy and do work.
	output  [4:0]		o_issuePrimitive,

	// Request data to parse
	input				i_isFifoNotEmpty32,
	output				o_readFIFO,
	// Valid data from previous request
	input				i_dataValid,		// i_dataValid IS o_readFIFO pipelined (FIFO = 1 CYCLE LATENCY) THAT'S SPECS (outside is just pipelining o_readFIFO)
	input				i_bIsTerminator,	// Used when i_dataValid (Word analyzed to find STOP pattern)
	
	//================================================
	// Control signals
	//================================================
	// To Vertex Register loading
	//------------------------------------------------
		
	output	[1:0]		o_vertexID,
	output				o_loadVertices,			// Load Coordinate from input
	output				o_loadUV,				// Load Texture coordinate from input
	output				o_loadRGB,				// Load Color from input
	output				o_loadAllRGB,			// If i_loadRGB = 1 => force ALL VERTEX TO SAME COLOR.
	output				o_loadCoord1,			// Load Top-Left     Coordinate (Fill, Copy commands)
	output				o_loadCoord2,			// Load Bottom-Right Coordinate (Fill, Copy commands)
	output				o_loadSize,				// Load WIDTH/HEIGHT for rectangle primitive.
	output	[1:0]		o_loadSizeParam,		// Parameter for 	i_loadSizeParam
	output				o_loadRectEdge,			// Compute the vertices while loading from SIZE.
	output				o_isVertexLoadState,	// Parameter for i_loadRectEdge

	// To GPU Register loading
	//------------------------------------------------
	output				o_rstTextureCache,
	output				o_storeCommand,
	output				o_loadE5Offsets,
	output				o_loadTexPageE1,
	output				o_loadTexWindowSetting,
	output				o_loadDrawAreaTL,
	output				o_loadDrawAreaBR,
	output				o_loadMaskSetting,
	output				o_setIRQ,
	output				o_loadClutPage,
	output				o_loadTexPage
);

//------------------------------------------------
// States
//------------------------------------------------
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

state_t currState,nextLogicalState;
state_t nextState;

always @(posedge i_clk)
begin
    if (i_rstGPU) begin
        currState 		<= DEFAULT_STATE;
    end else begin
        currState		<= nextState;
    end
end

//------------------------------------------------
// State machine output control signals.
//------------------------------------------------
reg rstTextureCache;
reg storeCommand;
reg loadRGB,loadUV,loadVertices,loadAllRGB;
reg loadE5Offsets;
reg loadTexPageE1;
reg loadTexWindowSetting;
reg loadDrawAreaTL;
reg loadDrawAreaBR;
reg loadMaskSetting;
reg setIRQ;
reg nextCondUseFIFO;
reg loadClutPage;
reg loadTexPage;
reg loadSize;
reg loadCoord1,loadCoord2;
reg loadRectEdge;
reg [1:0] loadSizeParam;
reg [4:0] issuePrimitive;
//------------------------------------------------

//------------------------------------------------
// Alias to old logic
//------------------------------------------------
wire canIssueWork  = !i_gpuBusy;
wire FifoDataValid = i_dataValid;

//------------------------------------------------
//  Command Decoder
//------------------------------------------------
wire bIsBase0x,bIsBase01,bIsBase1F,bIsPolyCommand,bIsRectCommand,bIsLineCommand,bIsMultiLine,bIsCopyVVCommand,
	 bIsCopyCommand,bIsFillCommand,bIsRenderAttrib,bIsNop,bUseTextureParser,bIs4PointPoly,bIsPerVtxCol;
	 
gpu_commandDecoder gpu_commandDecoder_instance(
	.i_command				(i_command),
	.o_bIsBase0x			(bIsBase0x),
	.o_bIsBase01			(bIsBase01),
	.o_bIsBase02			(),
	.o_bIsBase1F			(bIsBase1F),
	.o_bIsPolyCommand		(bIsPolyCommand),
	.o_bIsRectCommand		(bIsRectCommand),
	.o_bIsLineCommand		(bIsLineCommand),
	.o_bIsMultiLine			(bIsMultiLine),
	.o_bIsForECommand		(),
	.o_bIsCopyVVCommand		(bIsCopyVVCommand),
	.o_bIsCopyCVCommand		(),
	.o_bIsCopyVCCommand		(),
	.o_bIsCopyCommand		(bIsCopyCommand),
	.o_bIsFillCommand		(bIsFillCommand),
	.o_bIsRenderAttrib		(bIsRenderAttrib),
	.o_bIsNop				(bIsNop),
	.o_bIsPolyOrRect		(),
	.o_bUseTextureParser	(bUseTextureParser),
	.o_bSemiTransp			(),
	.o_bOpaque				(),
	.o_bIs4PointPoly		(bIs4PointPoly),
	.o_bIsPerVtxCol         (bIsPerVtxCol)
);

wire bIsMultiLineTerminator = (bIsLineCommand & bIsMultiLine & i_bIsTerminator);

// -------------------------------------------------------------------
//   Vertex Counter Management
// -------------------------------------------------------------------
// Vertex Management.
reg	[1:0]	vertexCnt;
reg			isFirstVertex;				// MULTILINE SUPPORT !
// Control signal from state machine.	
reg resetVertexCounter;
reg increaseVertexCounter;

always @(posedge i_clk)
begin
	if (resetVertexCounter /* | rstGPU | rstCmd : Done by STATE RESET. */) begin
		vertexCnt		<= 2'b00;
		isFirstVertex	<= 1;
	end else begin
		vertexCnt 		<= vertexCnt + increaseVertexCounter;
		if (increaseVertexCounter) begin
			isFirstVertex	<= 0;
		end
	end
end
wire   isV0,isV1,isV2;
assign isV0 = ((!bIsLineCommand) &((vertexCnt == 2'd0) | (vertexCnt == 2'd3))) | (bIsLineCommand & !vertexCnt[0]); // Vertex 4 primitive load in zero for second triangle.
assign isV1 = ((!bIsLineCommand) & (vertexCnt == 2'd1)                       ) | (bIsLineCommand &  vertexCnt[0]);
assign isV2 =  (!bIsLineCommand) & (vertexCnt == 2'd2);

reg [1:0] vertexID;
always @(*)
	case ({isV2,isV1,isV0})
	3'b001  : vertexID = 2'd0;
	3'b010  : vertexID = 2'd1;
	3'b100  : vertexID = 2'd2;
	default	: vertexID = 2'd3; // INVALID VERTEX. None selected
	endcase

wire isSecondVertex		= (vertexCnt == 2'd1);
wire canEmitTriangle	= (vertexCnt >= 2'd2);	// 2 or 3 for any tri or quad primitive. intermediate or final.
wire isPolyFinalVertex	= ((bIs4PointPoly & (vertexCnt == 2'd3)) | (!bIs4PointPoly & (vertexCnt == 2'd2)));
wire bNotFirstVert		= !isFirstVertex;		// Can NOT use counter == 0. Won't work in MULTILINE. (0/1/2/0/1/2/....)

//------------------------------------------------
// States Transition Logic
//------------------------------------------------
always @(*)
begin
    // Read FIFO when fifo is NOT empty or that we can decode the next item in the FIFO.
    // TODO : Assume that FIFO always output the same value as the last read, even if read signal is FALSE ! Simplify state machine a LOT.

    // NOT SUPPORTED WELL --->>>> issue = 0/*'{default:1'b0}*/;
    storeCommand  			= 0;
    loadRGB         		= 0;
    loadAllRGB      		= 0;
    setIRQ					= 0;
    rstTextureCache			= 0;
    loadE5Offsets		    = 0;
    loadTexPageE1		    = 0;
    loadTexWindowSetting  	= 0;
    loadDrawAreaTL			= 0;
    loadDrawAreaBR			= 0;
    loadMaskSetting			= 0;
    resetVertexCounter		= 0;
    increaseVertexCounter	= 0;
    loadUV					= 0;
    loadVertices			= 0;
    loadClutPage			= 0;
    loadTexPage				= 0;
    loadSize				= 0;
    loadCoord1				= 0;
    loadCoord2				= 0;
    loadRectEdge			= 0;
    loadSizeParam			= 2'd0;
    issuePrimitive			= 5'd0;

    nextCondUseFIFO			= 0;
    nextLogicalState		= DEFAULT_STATE;

    case (currState)
    DEFAULT_STATE:
    begin
        /*issue.*/resetVertexCounter = 1;
        nextCondUseFIFO			= 1;
        nextLogicalState		= LOAD_COMMAND; // Need FIFO
    end
    // Step 0A
    LOAD_COMMAND:				// Here we do NOT check data validity : if we arrive in this state, we know the data is available from the FIFO, and GPU accepts commands.
    begin
        /*issue.*/storeCommand  	= 1;
        /*issue.*/loadRGB           = 1; // Work for all command, just ignored.
        /*issue.*/loadAllRGB        = (i_bIgnoreColor) ? 1'b1 : (!bIsPerVtxCol);
        /*issue.*/setIRQ			= bIsBase0x & bIsBase1F;
        /*issue.*/rstTextureCache	= bIsBase0x & bIsBase01;
        /*issue.*/loadClutPage		= bIsBase0x & bIsBase01; // Reset CLUT adr, using rstTextureCache for MSB -> Invalid adr.

         // TODO : Can optimize later by using LOAD_COMMAND instead and loop...
         // For now any command reading is MINIMUM EVERY 2 CYCLES.
        // E1~E6
        if (bIsRenderAttrib) begin
            nextLogicalState	= DEFAULT_STATE;
            nextCondUseFIFO		= 0;

            /*issue.*/loadE5Offsets		    = (i_command[2:0] == 3'd5);
            /*issue.*/loadTexPageE1		    = (i_command[2:0] == 3'd1);
            /*issue.*/loadTexWindowSetting  = (i_command[2:0] == 3'd2);
            /*issue.*/loadDrawAreaTL		= (i_command[2:0] == 3'd3);
            /*issue.*/loadDrawAreaBR		= (i_command[2:0] == 3'd4);
            /*issue.*/loadMaskSetting		= (i_command[2:0] == 3'd6);
        end else begin
            // [02/8x~9X/Ax~Bx/Cx~Dx]
            if (bIsCopyCommand | bIsFillCommand) begin
                nextLogicalState	= LOAD_XY1;
                nextCondUseFIFO		= 1;
            end else begin
                 // Case E0/E7/E8~EF
                 // Case 00/03~1E/01 Handled.
                if (bIsNop | bIsBase0x) begin
                    nextLogicalState	= DEFAULT_STATE;
                    nextCondUseFIFO		= 0;
                end else begin
                // 2x/3x/4x/5x/6x/7x
                    nextLogicalState	= VERTEX_LOAD;
                    nextCondUseFIFO		= 1;
                end
            end
        end
    end
    LOAD_XY1:
    begin
        /*issue.*/loadCoord1 = 1; /*issue.*/loadCoord2	= 0;
        // bIsCopyVVCommand		Top Left Corner   (YyyyXxxxh) then WIDTH_HEIGHT_STATE
        // bIsCopyCVCommand		Source Coord      (YyyyXxxxh) then LOAD_X2
        // bIsCopyVCCommand		Destination Coord (YyyyXxxxh) then WIDTH_HEIGHT_STATE
        // bIsFillCommand		Top Left Corner   (YyyyXxxxh) then WIDTH_HEIGHT_STATE
        nextCondUseFIFO			= 1;
        nextLogicalState		= bIsCopyVVCommand ? LOAD_XY2 :  WIDTH_HEIGHT_STATE;
    end
    LOAD_XY2:
    begin
        /*issue.*/loadCoord1 = 0; /*issue.*/loadCoord2	= 1;
        nextCondUseFIFO			= 1;
        nextLogicalState		= WIDTH_HEIGHT_STATE;
    end
    // Step 0B
    COLOR_LOAD:
    begin
        //
        /*issue.*/loadRGB           = canIssueWork; // Reach the COLOR_LOAD state while a primitive is rendering... Forbid to LOAD COLOR.
        // Special case to test TERMINATOR (comes instead of COLOR value !!!)
        nextCondUseFIFO			= !(bIsLineCommand & bIsMultiLine & i_bIsTerminator);
        nextLogicalState		=  (bIsLineCommand & bIsMultiLine & i_bIsTerminator) ? DEFAULT_STATE : VERTEX_LOAD;
    end
    COLOR_LOAD_GARAGE:
    begin
        // Special case to test TERMINATOR (comes instead of COLOR value !!!)
        nextCondUseFIFO			= canIssueWork;
        nextLogicalState		= canIssueWork ? COLOR_LOAD : COLOR_LOAD_GARAGE;
    end
    VERTEX_LOAD_GARAGE:
    begin
        // Special case to test TERMINATOR (comes instead of COLOR value !!!)
        nextCondUseFIFO			= canIssueWork;
        nextLogicalState		= canIssueWork ? VERTEX_LOAD : VERTEX_LOAD_GARAGE;
    end
    // Step 1
    VERTEX_LOAD:
    begin
        if (bIsRectCommand) begin
            // Command original 27-28 Rect Size   (0=Var, 1=1x1, 2=8x8, 3=16x16) (Rectangle only)
            if (i_command[4:3]==2'd0) begin
                nextCondUseFIFO		= 1;
                nextLogicalState	= (bUseTextureParser) ? UV_LOAD : WIDTH_HEIGHT_STATE;
            end else begin
                if (bUseTextureParser) begin
                    nextCondUseFIFO		= 1;
                    nextLogicalState	= UV_LOAD;
                end else begin
                    nextCondUseFIFO		= 0;
                    /*issue.*/loadSize  = 1; /*issue.*/loadSizeParam = i_command[4:3];
                    nextLogicalState	= WAIT_COMMAND_COMPLETE;
                    /*issue.*/issuePrimitive		= ISSUE_RECT;
                end
            end
        end else begin
            if (bUseTextureParser) begin
                // Condition with 'FifoDataValid' necessary :
                // => If not done, state machine skip the 4th vertex loading to load directly 4th texture without loading the coordinates. (fifo not valid as we waited for primitive to complete)
                nextCondUseFIFO		= 1;
                nextLogicalState	= UV_LOAD;
            end else begin
                // End command if it is a terminator line or 2 vertex line only
                // Or a 4 point polygon or 3 point polygon.

                // MUST check 'canIssueWork' because the following test check ONLY THE VERTEX COUNTERS related.
                // and when entering the first emitted primitive, counter increments and VALIDATE the state change
                // WHILE the command is still working... So we miss emitting the SECOND TRIANGLE OR MULTILINES remaining.
                if ( canIssueWork & FifoDataValid &
                            ((bIsLineCommand & ((bIsMultiLine & i_bIsTerminator)|(!bIsMultiLine & isSecondVertex)))	// Polyline with FINAL VERTEX or Line with second vertex.
                            |(bIsPolyCommand & isPolyFinalVertex))
                    ) begin
                    nextCondUseFIFO		= 0;	// Instead of FIFO state, it uses
                    nextLogicalState	= WAIT_COMMAND_COMPLETE;  // For now, no optimization of the state machine, FIFO data or not : DEFAULT_STATE.
                    if (bIsPolyCommand) begin // Sure Polygon command
                        // Issue a triangle primitive.
                        /*issue.*/issuePrimitive	= ISSUE_TRIANGLE;
                    end else begin
                        // Line/Polyline
                        // If 5xxx5xxx do not issue a LINE.
                        /*issue.*/issuePrimitive	= (bIsMultiLine & i_bIsTerminator) ? NO_ISSUE : ISSUE_LINE;
                    end
                end else begin
                    // No need to check for canIssueWork because we emit the FIRST TRIANGLE in this case, so we know that the canIssueWork = 1.

                    // Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
                    // Can not issue if data is not valid.
                    if (canIssueWork) begin
                        if (FifoDataValid & bIsPolyCommand & canEmitTriangle) begin
                            /*issue.*/issuePrimitive		= ISSUE_TRIANGLE;
                        end else begin
                            if (FifoDataValid & bIsLineCommand & bIsMultiLine & bNotFirstVert) begin // Remain the case of intermediate line ONLY (single 2 vertex line handled in upper logic)
                                /*issue.*/issuePrimitive	= ISSUE_LINE;
                            end
                        end
                    end

                    //
                    // The logic of this state machine is that when we reach the current state it is a VALID state.
                    // The problem we fix here is that multiple primitive command (Quad, Multiline) emit a rendering command and we reach the NEXT command parameter and executed it.
                    // As a result, next vertex/color can override the primitive we are just trying to draw...
                    // [This logic is also in the UV_LOAD]
                    //
                    nextCondUseFIFO		= (/*issue.*/issuePrimitive == NO_ISSUE); //	TODO ??? OLD COMMENT Fix, proposed multiline support ((issuePrimitive == NO_ISSUE) | !bIsLineCommand); // 1 before line, !bIsLineCommand is a hack. Because...
                    if (/*issue.*/issuePrimitive != NO_ISSUE) begin
                        nextLogicalState	= bIsPerVtxCol ? COLOR_LOAD_GARAGE : VERTEX_LOAD_GARAGE; // Next Vertex or stay current vertex until loaded.
                    end else begin
                        nextLogicalState	= bIsPerVtxCol ? COLOR_LOAD        : VERTEX_LOAD; // Next Vertex or stay current vertex until loaded.
                    end
                end
            end
        end

        //
        // TRICKY DETAIL : When emitting multiple primitive, load the next vertex ONLY WHEN THE EMITTED COMMAND IS COMPLETED.
        //                 So we check (issuePrimitive == NO_ISSUE) when requesting next vertex.
		
		// WE INCREMENT COUNTER ONLY WHEN WE ARE SURE IT IS THE LAST CYCLE OF STATE.
		// TRICK : VERTEX LOAD STAYS ON THE SAME STATE WHEN NEW DATA ARRIVES.
        /*issue.*/increaseVertexCounter	= FifoDataValid & (!bUseTextureParser);	// go to next vertex if do not need UVs, don't care if invalid vertex... cause no issues. PUSH NEW VERTEX ONLY IF NOT BUSY RENDERING.
        /*issue.*/loadVertices			= FifoDataValid & (!bIsMultiLineTerminator); // Check if not TERMINATOR + line + multiline, else vertices are valid.
        /*issue.*/loadRectEdge			= FifoDataValid & bIsRectCommand;	// Force to load, dont care, override by UV if set with UV or SIZE if variable.
    end
    UV_LOAD:
    begin
        //

		// WE INCREMENT COUNTER ONLY WHEN WE ARE SURE IT IS THE LAST CYCLE OF STATE.
        /*issue.*/increaseVertexCounter	= FifoDataValid & canIssueWork & (!bIsRectCommand);	// Increase vertex counter only when in POLY MODE (LINE never reach here, RECT is the only other)
        /*issue.*/loadUV				= FifoDataValid & canIssueWork;
        /*issue.*/loadClutPage			= FifoDataValid & isV0 & (!isPolyFinalVertex); // First entry is Clut info, avoid reset when quad.
        /*issue.*/loadTexPage			= FifoDataValid & isV1; // second entry is TexPage.
        /*issue.*/loadRectEdge			= FifoDataValid & bIsRectCommand;

        // do not issue primitive if Rectangle or 1st/2nd vertex UV.

        if (bIsRectCommand) begin
            // 27-28 Rect Size   (0=Var, 1=1x1, 2=8x8, 3=16x16) (Rectangle only)
            /*issue.*/loadSizeParam		= i_command[4:3]; // Optimization, same as commented version.
            /*issue.*/issuePrimitive	= (i_command[4:3]!=2'd0) ? ISSUE_RECT : NO_ISSUE;
            if (i_command[4:3]==2'd0) begin
                nextCondUseFIFO		= 1;
                nextLogicalState	= WIDTH_HEIGHT_STATE;
            end else begin
                /*issue.*/loadSize			= 1; // loadSizeParam	<= command[4:3];
                nextCondUseFIFO		= 0;
                nextLogicalState	= WAIT_COMMAND_COMPLETE;
            end
        end else begin
            // Same here : MUST CHECK 'FifoDataValid' to force reading the values in another cycle...
            // Can not issue if data is not valid.
            if (FifoDataValid & bIsPolyCommand & canEmitTriangle & canIssueWork) begin
                /*issue.*/issuePrimitive	= ISSUE_TRIANGLE;
            end

            if (/*isPolyFinalVertex*/increaseVertexCounter && isPolyFinalVertex) begin // Is it the final vertex of the command ? (3rd / 4th depending on command)
                // Allow to complete UV LOAD of last vertex and go to COMPLETE
                // only if we can push the triangle and that the incoming FIFO data is valid.
                nextCondUseFIFO		= !(canIssueWork & FifoDataValid);	// Instead of FIFO state, it uses
				nextLogicalState	= (canIssueWork & FifoDataValid) ? WAIT_COMMAND_COMPLETE : UV_LOAD; // For now, no optimization of the state machine, FIFO data or not : DEFAULT_STATE.
            end else begin
                //
                // The logic of this state machine is that when we reach the current state it is a VALID state.
                // The problem we fix here is that multiple primitive command (Quad, Multiline) emit a rendering command and we reach the NEXT command parameter and executed it.
                // As a result, next vertex/color can override the primitive we are just trying to draw...
                // [This logic is also in the UV_LOAD]
                //
                nextCondUseFIFO		= (/*issue.*/issuePrimitive == NO_ISSUE); //	TODO ??? OLD COMMENT Fix, proposed multiline support ((issuePrimitive == NO_ISSUE) | !bIsLineCommand); // 1 before line, !bIsLineCommand is a hack. Because...
                if (/*issue.*/issuePrimitive != NO_ISSUE) begin
                    nextLogicalState	= bIsPerVtxCol ? COLOR_LOAD_GARAGE : VERTEX_LOAD_GARAGE; // Next Vertex or stay current vertex until loaded.
                end else begin
                    nextLogicalState	= bIsPerVtxCol ? COLOR_LOAD : VERTEX_LOAD; // Next Vertex or stay current vertex until loaded.
                end
            end
        end
    end
    WIDTH_HEIGHT_STATE:
    begin
        // No$PSX Doc says that two triangles are not generated.
        // We can use 4 lines equation instead of 3.
        // Visually difference can't be made. And pixel pipeline is nearly the same.
        // TODO ?; // Loop to generate 4 vertices... Add w/h to Vertex and UV.
        /*issue.*/loadSize			= 1; /*issue.*/loadSizeParam = SIZE_VAR;

        /*issue.*/loadRectEdge		= bIsRectCommand;

        /*issue.*/issuePrimitive	= bIsCopyCommand ? ISSUE_COPY : (bIsRectCommand ? ISSUE_RECT : ISSUE_FILL);
        nextCondUseFIFO			= 0;
        nextLogicalState		= WAIT_COMMAND_COMPLETE;
    end
    WAIT_COMMAND_COMPLETE:
    begin
        // (bIsCopyCommand | bIsFillCommand)
        nextCondUseFIFO			= 0;
        nextLogicalState		=  canIssueWork ? DEFAULT_STATE : WAIT_COMMAND_COMPLETE;
    end
    default :; // null
    endcase
end

// WE Read from the FIFO when FIFO has data, but also when the GPU is not busy rendering, else we stop loading commands...
// By blocking the state machine, we also block all the controls more easily. (Vertex loading, command issue, etc...)

// TODO [OPTIMIZE] 'canIssueWork' can be probably remove in upper logic except WAIT_COMMAND_COMPLETE : state machine should always PARSE the primitive when we can ISSUE WORK.
//        We loose a bit of performance (cycle to parse the primitive between 1 to 12 cycle)
//        But anyway we can NOT PARSE WHILE RENDERING PRIMITIVE BECAUSE IT WILL MODIFY THE REGISTERS.
//        So a full optimized system parsing the next command while rendering the first one is a lot more difficult anyway.
//
wire canReadFIFO			= i_isFifoNotEmpty32 & canIssueWork;
wire authorizeNextState     = ((!nextCondUseFIFO) | o_readFIFO);
// GENERATE WARNING : assign nextState			= authorizeNextState ? nextLogicalState : currState;
always @(*) begin nextState = authorizeNextState ? nextLogicalState : currState; end

assign o_issuePrimitive		= canIssueWork ? /*issue.*/issuePrimitive : NO_ISSUE;
assign o_readFIFO			= (nextCondUseFIFO & canReadFIFO);
assign o_vertexID 			= vertexID;

// Vertex Register Side Load Signal
assign o_loadVertices		= loadVertices;
assign o_loadUV				= loadUV;
assign o_loadRGB			= loadRGB; 
assign o_loadAllRGB			= loadAllRGB;
assign o_loadCoord1			= loadCoord1;
assign o_loadCoord2			= loadCoord2;

assign o_loadSize			= loadSize;
assign o_loadSizeParam		= loadSizeParam;

assign o_loadRectEdge		= loadRectEdge;
assign o_isVertexLoadState	= (currState == VERTEX_LOAD);

// GPU Register Side Load Signal
assign o_rstTextureCache		= rstTextureCache;
assign o_storeCommand			= storeCommand;
assign o_loadE5Offsets			= loadE5Offsets;
assign o_loadTexPageE1			= loadTexPageE1;
assign o_loadTexWindowSetting	= loadTexWindowSetting;
assign o_loadDrawAreaTL			= loadDrawAreaTL;
assign o_loadDrawAreaBR			= loadDrawAreaBR;
assign o_loadMaskSetting		= loadMaskSetting;
assign o_setIRQ					= setIRQ;
assign o_loadClutPage			= loadClutPage;
assign o_loadTexPage			= loadTexPage;

endmodule
