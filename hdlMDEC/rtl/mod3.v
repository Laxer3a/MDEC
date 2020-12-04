module mod3(
	input [6:0] inV,
	output [1:0] outP,
	output [4:0] divP
);

reg [1:0] outV;
reg [4:0] outD;

always @(*) begin
	case (inV)
	7'd0	: outD = 5'd0;
	7'd1	: outD = 5'd0;
	7'd2	: outD = 5'd0;
	7'd3	: outD = 5'd1;
	7'd4	: outD = 5'd1;
	7'd5	: outD = 5'd1;
	7'd6	: outD = 5'd2;
	7'd7	: outD = 5'd2;
	7'd8	: outD = 5'd2;
	7'd9	: outD = 5'd3;
	7'd10	: outD = 5'd3;
	7'd11	: outD = 5'd3;
	7'd12	: outD = 5'd4;
	7'd13	: outD = 5'd4;
	7'd14	: outD = 5'd4;
	7'd15	: outD = 5'd5;
	7'd16	: outD = 5'd5;
	7'd17	: outD = 5'd5;
	7'd18	: outD = 5'd6;
	7'd19	: outD = 5'd6;
	7'd20	: outD = 5'd6;
	7'd21	: outD = 5'd7;
	7'd22	: outD = 5'd7;
	7'd23	: outD = 5'd7;
	7'd24	: outD = 5'd8;
	7'd25	: outD = 5'd8;
	7'd26	: outD = 5'd8;
	7'd27	: outD = 5'd9;
	7'd28	: outD = 5'd9;
	7'd29	: outD = 5'd9;
	7'd30	: outD = 5'd10;
	7'd31	: outD = 5'd10;
	7'd32	: outD = 5'd10;
	7'd33	: outD = 5'd11;
	7'd34	: outD = 5'd11;
	7'd35	: outD = 5'd11;
	7'd36	: outD = 5'd12;
	7'd37	: outD = 5'd12;
	7'd38	: outD = 5'd12;
	7'd39	: outD = 5'd13;
	7'd40	: outD = 5'd13;
	7'd41	: outD = 5'd13;
	7'd42	: outD = 5'd14;
	7'd43	: outD = 5'd14;
	7'd44	: outD = 5'd14;
	7'd45	: outD = 5'd15;
	7'd46	: outD = 5'd15;
	7'd47	: outD = 5'd15;
	7'd48	: outD = 5'd16;
	7'd49	: outD = 5'd16;
	7'd50	: outD = 5'd16;
	7'd51	: outD = 5'd17;
	7'd52	: outD = 5'd17;
	7'd53	: outD = 5'd17;
	7'd54	: outD = 5'd18;
	7'd55	: outD = 5'd18;
	7'd56	: outD = 5'd18;
	7'd57	: outD = 5'd19;
	7'd58	: outD = 5'd19;
	7'd59	: outD = 5'd19;
	7'd60	: outD = 5'd20;
	7'd61	: outD = 5'd20;
	7'd62	: outD = 5'd20;
	7'd63	: outD = 5'd21;
	7'd64	: outD = 5'd21;
	7'd65	: outD = 5'd21;
	7'd66	: outD = 5'd22;
	7'd67	: outD = 5'd22;
	7'd68	: outD = 5'd22;
	7'd69	: outD = 5'd23;
	7'd70	: outD = 5'd23;
	7'd71	: outD = 5'd23;
	7'd72	: outD = 5'd24;
	7'd73	: outD = 5'd24;
	7'd74	: outD = 5'd24;
	7'd75	: outD = 5'd25;
	7'd76	: outD = 5'd25;
	7'd77	: outD = 5'd25;
	7'd78	: outD = 5'd26;
	7'd79	: outD = 5'd26;
	7'd80	: outD = 5'd26;
	7'd81	: outD = 5'd27;
	7'd82	: outD = 5'd27;
	7'd83	: outD = 5'd27;
	7'd84	: outD = 5'd28;
	7'd85	: outD = 5'd28;
	7'd86	: outD = 5'd28;
	7'd87	: outD = 5'd29;
	7'd88	: outD = 5'd29;
	7'd89	: outD = 5'd29;
	7'd90	: outD = 5'd30;
	7'd91	: outD = 5'd30;
	7'd92	: outD = 5'd30;
	7'd93	: outD = 5'd31;
	7'd94	: outD = 5'd31;
	7'd95	: outD = 5'd31;
	default : outD = 5'dx;
	endcase

	case (inV)
	7'd0	: outV = 2'd0;
	7'd1	: outV = 2'd1;
	7'd2	: outV = 2'd2;
	7'd3	: outV = 2'd0;
	7'd4	: outV = 2'd1;
	7'd5	: outV = 2'd2;
	7'd6	: outV = 2'd0;
	7'd7	: outV = 2'd1;
	7'd8	: outV = 2'd2;
	7'd9	: outV = 2'd0;
	7'd10	: outV = 2'd1;
	7'd11	: outV = 2'd2;
	7'd12	: outV = 2'd0;
	7'd13	: outV = 2'd1;
	7'd14	: outV = 2'd2;
	7'd15	: outV = 2'd0;
	7'd16	: outV = 2'd1;
	7'd17	: outV = 2'd2;
	7'd18	: outV = 2'd0;
	7'd19	: outV = 2'd1;
	7'd20	: outV = 2'd2;
	7'd21	: outV = 2'd0;
	7'd22	: outV = 2'd1;
	7'd23	: outV = 2'd2;
	7'd24	: outV = 2'd0;
	7'd25	: outV = 2'd1;
	7'd26	: outV = 2'd2;
	7'd27	: outV = 2'd0;
	7'd28	: outV = 2'd1;
	7'd29	: outV = 2'd2;
	7'd30	: outV = 2'd0;
	7'd31	: outV = 2'd1;
	7'd32	: outV = 2'd2;
	7'd33	: outV = 2'd0;
	7'd34	: outV = 2'd1;
	7'd35	: outV = 2'd2;
	7'd36	: outV = 2'd0;
	7'd37	: outV = 2'd1;
	7'd38	: outV = 2'd2;
	7'd39	: outV = 2'd0;
	7'd40	: outV = 2'd1;
	7'd41	: outV = 2'd2;
	7'd42	: outV = 2'd0;
	7'd43	: outV = 2'd1;
	7'd44	: outV = 2'd2;
	7'd45	: outV = 2'd0;
	7'd46	: outV = 2'd1;
	7'd47	: outV = 2'd2;
	7'd48	: outV = 2'd0;
	7'd49	: outV = 2'd1;
	7'd50	: outV = 2'd2;
	7'd51	: outV = 2'd0;
	7'd52	: outV = 2'd1;
	7'd53	: outV = 2'd2;
	7'd54	: outV = 2'd0;
	7'd55	: outV = 2'd1;
	7'd56	: outV = 2'd2;
	7'd57	: outV = 2'd0;
	7'd58	: outV = 2'd1;
	7'd59	: outV = 2'd2;
	7'd60	: outV = 2'd0;
	7'd61	: outV = 2'd1;
	7'd62	: outV = 2'd2;
	7'd63	: outV = 2'd0;
	7'd64	: outV = 2'd1;
	7'd65	: outV = 2'd2;
	7'd66	: outV = 2'd0;
	7'd67	: outV = 2'd1;
	7'd68	: outV = 2'd2;
	7'd69	: outV = 2'd0;
	7'd70	: outV = 2'd1;
	7'd71	: outV = 2'd2;
	7'd72	: outV = 2'd0;
	7'd73	: outV = 2'd1;
	7'd74	: outV = 2'd2;
	7'd75	: outV = 2'd0;
	7'd76	: outV = 2'd1;
	7'd77	: outV = 2'd2;
	7'd78	: outV = 2'd0;
	7'd79	: outV = 2'd1;
	7'd80	: outV = 2'd2;
	7'd81	: outV = 2'd0;
	7'd82	: outV = 2'd1;
	7'd83	: outV = 2'd2;
	7'd84	: outV = 2'd0;
	7'd85	: outV = 2'd1;
	7'd86	: outV = 2'd2;
	7'd87	: outV = 2'd0;
	7'd88	: outV = 2'd1;
	7'd89	: outV = 2'd2;
	7'd90	: outV = 2'd0;
	7'd91	: outV = 2'd1;
	7'd92	: outV = 2'd2;
	7'd93	: outV = 2'd0;
	7'd94	: outV = 2'd1;
	7'd95	: outV = 2'd2;
	default : outV = 2'dx;
	endcase
end
assign outP = outV;
assign divP = outD;
endmodule
