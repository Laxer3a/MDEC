module SelectCh(
	input [23:0] v, 
	input [4:0] ch, 
	output o
);

reg Tmp;
always @ (*)
begin
	case (ch)
	'd0  : Tmp = v[ 0];
	'd1  : Tmp = v[ 1];
	'd2  : Tmp = v[ 2];
	'd3  : Tmp = v[ 3];
	'd4  : Tmp = v[ 4];
	'd5  : Tmp = v[ 5];
	'd6  : Tmp = v[ 6];
	'd7  : Tmp = v[ 7];
	'd8  : Tmp = v[ 8];
	'd9  : Tmp = v[ 9];
	'd10 : Tmp = v[10];
	'd11 : Tmp = v[11];
	'd12 : Tmp = v[12];
	'd13 : Tmp = v[13];
	'd14 : Tmp = v[14];
	'd15 : Tmp = v[15];
	'd16 : Tmp = v[16];
	'd17 : Tmp = v[17];
	'd18 : Tmp = v[18];
	'd19 : Tmp = v[19];
	'd20 : Tmp = v[20];
	'd21 : Tmp = v[21];
	'd22 : Tmp = v[22];
	'd23 : Tmp = v[23];
	default: Tmp = v[23];
	endcase
end
assign o = Tmp;
endmodule
