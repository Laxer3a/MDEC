`include "GTEDefine.hv"

module GTESelAddPath(
	input gteSelAddCtrl ctrl,
	
	input        i_SF,
	input        isMVMVA,
	input  [1:0] cv,

	input [31:0] TRX,
	input [31:0] TRY,
	input [31:0] TRZ,
	
	input [31:0] RBK,
	input [31:0] GBK,
	input [31:0] BBK,
	
	input [31:0] RFC,
	input [31:0] GFC,
	input [31:0] BFC,
	
	input [31:0] MAC1,
	input [31:0] MAC2,
	input [31:0] MAC3,
	
	input [31:0] OF0,
	input [31:0] OF1,
	input [31:0] DQB,
	
	input [23:0] NCDS_CDP_DPCL_Special,  // R/G/B*Prev.x/y/z (Save cycle to fit in budget)
	
	input [ 7:0] R,
	input [ 7:0] G,
	input [ 7:0] B,

	input [15:0] TMP1,
	input [15:0] TMP2,
	input [15:0] TMP3,
	
	input [15:0] SZ0,
	input [15:0] ZFS4,
	
	// --- Reuse i_IRn
	output [43:0] outstuff
);
	/*
	TRX/Y/Z         << 12		// Vector 0 in case of MVMA
	backGroundColor << 12		// Vector 1 in case of MVMA
	farColor        << 12		// Vector 2 in case of MVMA
	ZERO						// Vector 3 in case of MVMA
	(r/g/b<<4)      << 12		// Vector 4
	MAC1..3         << sf*12	// Vector 5
	SpecialZ0*ZSF4	<< 0		// Vector 6
	TMP1..3			<< 12		// Vector 7
	OF[0/1] | DQB	<< 0		// Vector 8
	
	*/
	wire signed [16:0] mulA = { 1'b0, SZ0 };
	wire signed [15:0] mulB = ZFS4;
	wire signed [32:0] resMul = mulA * mulB; // 
	
	wire vSF = ctrl.useSF & i_SF;
	
	wire [31:0] specialZ0MulZSF4_Hi = {{11{resMul[32]}}, resMul[32:12]};
	wire [11:0] specialZ0MulZSF4_Lo = resMul[11:0];
	wire [31:0] mac_Hi = vSF ? macV  : { {12{macV[31]}}, macV[31:12] };
	wire [11:0] mac_Lo = vSF ? 12'd0 : macV[11:0];		// Perform sign extension...
	
	reg [31:0] trV;
	reg [31:0] bgV;
	reg [31:0] fcV;
	reg [31:0] macV;
	reg [31:0] of;
	reg [ 7:0] colV;
	reg [15:0] shadowIR;
	
	reg [43:0] out;
	wire [3:0] sel = isMVMVA && (ctrl.sel != 4'd3) ? {2'd0,cv} : ctrl.sel; // Microcode can override CV selection to force ZERO.
	
	always @(*) begin
		case (ctrl.id)
		2'd0   : begin trV = TRX; bgV = RBK; fcV = RFC; macV = MAC1; colV = R; shadowIR = TMP1; of = OF0; end
		2'd1   : begin trV = TRY; bgV = GBK; fcV = GFC; macV = MAC2; colV = G; shadowIR = TMP2; of = OF1; end
		default: begin trV = TRZ; bgV = BBK; fcV = BFC; macV = MAC3; colV = B; shadowIR = TMP3; of = DQB; end
		endcase
		
		case (sel)
		4'd0   : out[43:12] = trV;
		4'd1   : out[43:12] = bgV;
		4'd2   : out[43:12] = fcV;
		// 4'd3 is DEFAULT ! (MUST BE ZERO)
		4'd4   : out[43:12] = { 20'd0, colV, 4'd0 };
		4'd5   : out[43:12] = mac_Hi;
		4'd6   : out[43:12] = specialZ0MulZSF4_Hi;
		4'd7   : out[43:12] = { {16{shadowIR[15]}}, shadowIR};
		4'd8   : out[43:12] = {{12{of[31]}}, of[31:12]};
		4'd9   : out[43:12] = {{16{NCDS_CDP_DPCL_Special[23]}}, NCDS_CDP_DPCL_Special[23:8]};
		default: out[43:12] = 32'd0; // ZERO (Vector 3 for MVMA)
		endcase

		case (sel)
		4'd5   : out[11:0] = mac_Lo;
		4'd6   : out[11:0] = specialZ0MulZSF4_Lo;
		4'd8   : out[11:0] = of[11:0];
		4'd9   : out[11:0] = {NCDS_CDP_DPCL_Special[7:0], 4'd0};
		default: out[11:0] = 12'd0;
		endcase
	end
	
	assign outstuff = out;
endmodule
