/* Validated by Verilator testBlendUnit.cpp 

 */
module blendUnit(
	input	[7:0]	bg_r,
	input	[7:0]	bg_g,
	input	[7:0]	bg_b,

	input	[7:0]	px_r,
	input	[7:0]	px_g,
	input	[7:0]	px_b,
	
	// input bg_mask,
	// input checkMask,
	
	input			noblend,
	input	[1:0]	mode,
	
	output	[7:0]	rOut,
	output	[7:0]	gOut,
	output	[7:0]	bOut
);
	wire [10:0] npr = {1'b1, ~px_r, 2'b00} + 11'd4;
	wire [10:0] npg = {1'b1, ~px_g, 2'b00} + 11'd4;
	wire [10:0] npb = {1'b1, ~px_b, 2'b00} + 11'd4;
	 
	reg  [8:0] ra,ga,ba;
	reg [10:0] rb,gb,bb;
	
	always @(*)
	begin
		// (0=B/2+F/2, 1=B+F, 2=B-F, 3=B+F/4)
		
		if (mode==2'b00) begin
			// 0.5
			ra = {1'b0, bg_r};
			ga = {1'b0, bg_g};
			ba = {1'b0, bg_b};
		end else begin
			// 1.0
			ra = {bg_r, 1'b0};
			ga = {bg_g, 1'b0};
			ba = {bg_b, 1'b0};
		end
		
		case (mode)
		2'd0: 
		begin
			// 0.5
			rb = {2'b0, px_r, 1'b0};
			gb = {2'b0, px_g, 1'b0};
			bb = {2'b0, px_b, 1'b0};
		end
		2'd1:
		begin
			// 1.0
			rb = {1'b0, px_r, 2'b0};
			gb = {1'b0, px_g, 2'b0};
			bb = {1'b0, px_b, 2'b0};
		end
		2'd2:
		begin
			// -1.0
			rb = npr;
			gb = npg;
			bb = npb;
		end
		2'd3:
		begin
			// 0.25
			rb = {3'd0, px_r};
			gb = {3'd0, px_g};
			bb = {3'd0, px_b};
		end
		endcase
	end
	
	wire [11:0] blend_r = {2'b0,ra,1'b0} + { rb[10],rb };
	wire [11:0] blend_g = {2'b0,ga,1'b0} + { gb[10],gb };
	wire [11:0] blend_b = {2'b0,ba,1'b0} + { bb[10],bb };

	wire [7:0] blend_ro;
	wire [7:0] blend_go;
	wire [7:0] blend_bo;

	clampSPositive #(.INW(10),.OUTW(8)) R_ClmpSPos(.valueIn(blend_r[11:2]),.valueOut(blend_ro));
	clampSPositive #(.INW(10),.OUTW(8)) G_ClmpSPos(.valueIn(blend_g[11:2]),.valueOut(blend_go));
	clampSPositive #(.INW(10),.OUTW(8)) B_ClmpSPos(.valueIn(blend_b[11:2]),.valueOut(blend_bo));

	assign rOut = noblend ? px_r : blend_ro;
	assign gOut = noblend ? px_g : blend_go;
	assign bOut = noblend ? px_b : blend_bo;

endmodule
