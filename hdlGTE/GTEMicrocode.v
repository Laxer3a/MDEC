module GTEMicroCode(
	input  [ 8:0] PC,
	output [ 1:0] microCode
);

// Include Microcode constants.
`include "GTEConsts.vh"

// MicroCode ROM Table
reg [1:0] v;
always @(PC) begin
	case (PC)
	/*  INSTR_RTPS	00*/ 9'd0  : v = { RSTFLG } ; // 15;
	/*  INSTR_RTPS	01*/ 9'd1  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	02*/ 9'd2  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	03*/ 9'd3  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	04*/ 9'd4  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	05*/ 9'd5  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	06*/ 9'd6  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	07*/ 9'd7  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	08*/ 9'd8  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	09*/ 9'd9  : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	10*/ 9'd10 : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	11*/ 9'd11 : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	12*/ 9'd12 : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	13*/ 9'd13 : v = { ___FLG } ; // 15;
	/*  INSTR_RTPS	14*/ 9'd14 : v = { LAST__ } ; // 15;
	//--------------------------------
	/*  INSTR_NCLIP 00*/ 9'd15 : v = { RSTFLG } ; //  8;
	/*  INSTR_NCLIP 01*/ 9'd16 : v = { ___FLG } ; //  8;
	/*  INSTR_NCLIP 02*/ 9'd17 : v = { ___FLG } ; //  8;
	/*  INSTR_NCLIP 03*/ 9'd18 : v = { ___FLG } ; //  8;
	/*  INSTR_NCLIP 04*/ 9'd19 : v = { ___FLG } ; //  8;
	/*  INSTR_NCLIP 05*/ 9'd20 : v = { ___FLG } ; //  8;
	/*  INSTR_NCLIP 06*/ 9'd21 : v = { ___FLG } ; //  8;
	/*  INSTR_NCLIP 07*/ 9'd22 : v = { LAST__ } ; //  8;
	//--------------------------------
	/*  INSTR_OP	00*/ 9'd23 : v = { RSTFLG } ; //  6;
	/*  INSTR_OP	01*/ 9'd24 : v = { ___FLG } ; //  6;
	/*  INSTR_OP	02*/ 9'd25 : v = { ___FLG } ; //  6;
	/*  INSTR_OP	03*/ 9'd26 : v = { ___FLG } ; //  6;
	/*  INSTR_OP	04*/ 9'd27 : v = { ___FLG } ; //  6;
	/*  INSTR_OP	05*/ 9'd28 : v = { LAST__ } ; //  6;
	//--------------------------------
	/*  INSTR_DPCS	00*/ 9'd29 : v = { RSTFLG } ; //  8;
	/*  INSTR_DPCS	01*/ 9'd30 : v = { ___FLG } ; //  8;
	/*  INSTR_DPCS	02*/ 9'd31 : v = { ___FLG } ; //  8;
	/*  INSTR_DPCS	03*/ 9'd32 : v = { ___FLG } ; //  8;
	/*  INSTR_DPCS	04*/ 9'd33 : v = { ___FLG } ; //  8;
	/*  INSTR_DPCS	05*/ 9'd34 : v = { ___FLG } ; //  8;
	/*  INSTR_DPCS	06*/ 9'd35 : v = { ___FLG } ; //  8;
	/*  INSTR_DPCS	07*/ 9'd36 : v = { LAST__ } ; //  8;
	//--------------------------------
	/*  INSTR_INTPL 00*/ 9'd37 : v = { RSTFLG } ; //  8;
	/*  INSTR_INTPL 01*/ 9'd38 : v = { ___FLG } ; //  8;
	/*  INSTR_INTPL 02*/ 9'd39 : v = { ___FLG } ; //  8;
	/*  INSTR_INTPL 03*/ 9'd40 : v = { ___FLG } ; //  8;
	/*  INSTR_INTPL 04*/ 9'd41 : v = { ___FLG } ; //  8;
	/*  INSTR_INTPL 05*/ 9'd42 : v = { ___FLG } ; //  8;
	/*  INSTR_INTPL 06*/ 9'd43 : v = { ___FLG } ; //  8;
	/*  INSTR_INTPL 07*/ 9'd44 : v = { LAST__ } ; //  8;
	//--------------------------------
	/*  INSTR_MVMVA 00*/ 9'd45 : v = { RSTFLG } ; //  8;
	/*  INSTR_MVMVA 01*/ 9'd46 : v = { ___FLG } ; //  8;
	/*  INSTR_MVMVA 02*/ 9'd47 : v = { ___FLG } ; //  8;
	/*  INSTR_MVMVA 03*/ 9'd48 : v = { ___FLG } ; //  8;
	/*  INSTR_MVMVA 04*/ 9'd49 : v = { ___FLG } ; //  8;
	/*  INSTR_MVMVA 05*/ 9'd50 : v = { ___FLG } ; //  8;
	/*  INSTR_MVMVA 06*/ 9'd51 : v = { ___FLG } ; //  8;
	/*  INSTR_MVMVA 07*/ 9'd52 : v = { LAST__ } ; //  8;
	//--------------------------------
	/*  INSTR_NCDS	00*/ 9'd53 : v = { RSTFLG } ; // 19;
	/*  INSTR_NCDS	01*/ 9'd54 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	02*/ 9'd55 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	03*/ 9'd56 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	04*/ 9'd57 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	05*/ 9'd58 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	06*/ 9'd59 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	07*/ 9'd60 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	08*/ 9'd61 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	09*/ 9'd62 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	10*/ 9'd63 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	11*/ 9'd64 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	12*/ 9'd65 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	13*/ 9'd66 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	14*/ 9'd67 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	15*/ 9'd68 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	16*/ 9'd69 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	17*/ 9'd70 : v = { ___FLG } ; // 19;
	/*  INSTR_NCDS	18*/ 9'd71 : v = { LAST__ } ; // 19;
	//--------------------------------
	/*  INSTR_CDP	00*/ 9'd72 : v = { RSTFLG } ; // 13;
	/*  INSTR_CDP	01*/ 9'd73 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	02*/ 9'd74 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	03*/ 9'd75 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	04*/ 9'd76 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	05*/ 9'd77 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	06*/ 9'd78 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	07*/ 9'd79 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	08*/ 9'd80 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	09*/ 9'd81 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	10*/ 9'd82 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	11*/ 9'd83 : v = { ___FLG } ; // 13;
	/*  INSTR_CDP	12*/ 9'd84 : v = { LAST__ } ; // 13;
	//--------------------------------
	/*  INSTR_NCDT	00*/ 9'd85 : v = { RSTFLG } ; // 44;
	/*  INSTR_NCDT	01*/ 9'd86 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	02*/ 9'd87 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	03*/ 9'd88 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	04*/ 9'd89 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	05*/ 9'd90 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	06*/ 9'd91 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	07*/ 9'd92 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	08*/ 9'd93 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	09*/ 9'd94 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	10*/ 9'd95 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	11*/ 9'd96 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	12*/ 9'd97 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	13*/ 9'd98 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	14*/ 9'd99 : v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	15*/ 9'd100: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	16*/ 9'd101: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	17*/ 9'd102: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	18*/ 9'd103: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	19*/ 9'd104: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	20*/ 9'd105: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	21*/ 9'd106: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	22*/ 9'd107: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	23*/ 9'd108: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	24*/ 9'd109: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	25*/ 9'd110: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	26*/ 9'd111: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	27*/ 9'd112: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	28*/ 9'd113: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	29*/ 9'd114: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	30*/ 9'd115: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	31*/ 9'd116: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	32*/ 9'd117: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	33*/ 9'd118: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	34*/ 9'd119: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	35*/ 9'd120: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	36*/ 9'd121: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	37*/ 9'd122: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	38*/ 9'd123: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	39*/ 9'd124: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	40*/ 9'd125: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	41*/ 9'd126: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	42*/ 9'd127: v = { ___FLG } ; // 44;
	/*  INSTR_NCDT	43*/ 9'd128: v = { LAST__ } ; // 44;
	//--------------------------------
	/*  INSTR_NCCS	00*/ 9'd129: v = { RSTFLG } ; // 17;
	/*  INSTR_NCCS	01*/ 9'd130: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	02*/ 9'd131: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	03*/ 9'd132: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	04*/ 9'd133: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	05*/ 9'd134: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	06*/ 9'd135: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	07*/ 9'd136: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	08*/ 9'd137: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	09*/ 9'd138: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	10*/ 9'd139: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	11*/ 9'd140: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	12*/ 9'd141: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	13*/ 9'd142: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	14*/ 9'd143: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	15*/ 9'd144: v = { ___FLG } ; // 17;
	/*  INSTR_NCCS	16*/ 9'd145: v = { LAST__ } ; // 17;
	//--------------------------------
	/*  INSTR_CC 	00*/ 9'd146: v = { RSTFLG } ; // 11;
	/*  INSTR_CC 	01*/ 9'd147: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	02*/ 9'd148: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	03*/ 9'd149: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	04*/ 9'd150: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	05*/ 9'd151: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	06*/ 9'd152: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	07*/ 9'd153: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	08*/ 9'd154: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	09*/ 9'd155: v = { ___FLG } ; // 11;
	/*  INSTR_CC 	10*/ 9'd156: v = { LAST__ } ; // 11;
	//--------------------------------
	/*  INSTR_NCS 	00*/ 9'd157: v = { RSTFLG } ; // 14;
	/*  INSTR_NCS 	01*/ 9'd158: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	02*/ 9'd159: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	03*/ 9'd160: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	04*/ 9'd161: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	05*/ 9'd162: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	06*/ 9'd163: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	07*/ 9'd164: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	08*/ 9'd165: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	09*/ 9'd166: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	10*/ 9'd167: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	11*/ 9'd168: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	12*/ 9'd169: v = { ___FLG } ; // 14;
	/*  INSTR_NCS 	13*/ 9'd170: v = { LAST__ } ; // 14;
	//--------------------------------
	/*  INSTR_NCT 	00*/ 9'd171: v = { RSTFLG } ; // 30;
	/*  INSTR_NCT 	01*/ 9'd172: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	02*/ 9'd173: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	03*/ 9'd174: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	04*/ 9'd175: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	05*/ 9'd176: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	06*/ 9'd177: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	07*/ 9'd178: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	08*/ 9'd179: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	09*/ 9'd180: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	10*/ 9'd181: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	11*/ 9'd182: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	12*/ 9'd183: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	13*/ 9'd184: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	14*/ 9'd185: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	15*/ 9'd186: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	16*/ 9'd187: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	17*/ 9'd188: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	18*/ 9'd189: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	19*/ 9'd190: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	20*/ 9'd191: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	21*/ 9'd192: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	22*/ 9'd193: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	23*/ 9'd194: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	24*/ 9'd195: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	25*/ 9'd196: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	26*/ 9'd197: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	27*/ 9'd198: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	28*/ 9'd199: v = { ___FLG } ; // 30;
	/*  INSTR_NCT 	29*/ 9'd200: v = { LAST__ } ; // 30;
	//--------------------------------
	/*  INSTR_SQR 	00*/ 9'd201: v = { RSTFLG } ; //  5;
	/*  INSTR_SQR 	01*/ 9'd202: v = { ___FLG } ; //  5;
	/*  INSTR_SQR 	02*/ 9'd203: v = { ___FLG } ; //  5;
	/*  INSTR_SQR 	03*/ 9'd204: v = { ___FLG } ; //  5;
	/*  INSTR_SQR 	04*/ 9'd205: v = { ___FLG } ; //  5;
	//--------------------------------
	/*  INSTR_DCPL  00*/ 9'd206: v = { RSTFLG } ; //  8;
	/*  INSTR_DCPL  01*/ 9'd207: v = { ___FLG } ; //  8;
	/*  INSTR_DCPL  02*/ 9'd208: v = { ___FLG } ; //  8;
	/*  INSTR_DCPL  03*/ 9'd209: v = { ___FLG } ; //  8;
	/*  INSTR_DCPL  04*/ 9'd210: v = { ___FLG } ; //  8;
	/*  INSTR_DCPL  05*/ 9'd211: v = { ___FLG } ; //  8;
	/*  INSTR_DCPL  06*/ 9'd212: v = { ___FLG } ; //  8;
	/*  INSTR_DCPL  07*/ 9'd213: v = { LAST__ } ; //  8;
	//--------------------------------
	/*  INSTR_DPCT  00*/ 9'd214: v = { RSTFLG } ; // 17;
	/*  INSTR_DPCT  01*/ 9'd215: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  02*/ 9'd216: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  03*/ 9'd217: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  04*/ 9'd218: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  05*/ 9'd219: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  06*/ 9'd220: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  07*/ 9'd221: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  08*/ 9'd222: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  09*/ 9'd223: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  10*/ 9'd224: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  11*/ 9'd225: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  12*/ 9'd226: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  13*/ 9'd227: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  14*/ 9'd228: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  15*/ 9'd229: v = { ___FLG } ; // 17;
	/*  INSTR_DPCT  16*/ 9'd230: v = { LAST__ } ; // 17;
	//--------------------------------
	/*  INSTR_AVSZ3 00*/ 9'd231: v = { RSTFLG } ; //  5;
	/*  INSTR_AVSZ3 01*/ 9'd232: v = { ___FLG } ; //  5;
	/*  INSTR_AVSZ3 02*/ 9'd233: v = { ___FLG } ; //  5;
	/*  INSTR_AVSZ3 03*/ 9'd234: v = { ___FLG } ; //  5;
	/*  INSTR_AVSZ3 04*/ 9'd235: v = { ___FLG } ; //  5;
	/*  INSTR_AVSZ4 00*/ 9'd236: v = { ___FLG } ; //  6;
	/*  INSTR_AVSZ4 01*/ 9'd237: v = { ___FLG } ; //  6;
	/*  INSTR_AVSZ4 02*/ 9'd238: v = { ___FLG } ; //  6;
	/*  INSTR_AVSZ4 03*/ 9'd239: v = { ___FLG } ; //  6;
	/*  INSTR_AVSZ4 04*/ 9'd240: v = { ___FLG } ; //  6;
	/*  INSTR_AVSZ4 05*/ 9'd241: v = { LAST__ } ; //  6;
	//--------------------------------
	/*  INSTR_RTPT	00*/ 9'd242: v = { RSTFLG } ; // 23;
	/*  INSTR_RTPT	01*/ 9'd243: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	02*/ 9'd244: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	03*/ 9'd245: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	04*/ 9'd246: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	05*/ 9'd247: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	06*/ 9'd248: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	07*/ 9'd249: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	08*/ 9'd250: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	09*/ 9'd251: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	10*/ 9'd252: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	11*/ 9'd253: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	12*/ 9'd254: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	13*/ 9'd255: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	14*/ 9'd256: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	15*/ 9'd257: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	16*/ 9'd258: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	17*/ 9'd259: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	18*/ 9'd260: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	19*/ 9'd261: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	20*/ 9'd262: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	21*/ 9'd263: v = { ___FLG } ; // 23;
	/*  INSTR_RTPT	22*/ 9'd264: v = { LAST__ } ; // 23;
	//--------------------------------
	/*  INSTR_GPF	00*/ 9'd265: v = { RSTFLG } ; //  5;
	/*  INSTR_GPF	01*/ 9'd266: v = { ___FLG } ; //  5;
	/*  INSTR_GPF	02*/ 9'd267: v = { ___FLG } ; //  5;
	/*  INSTR_GPF	03*/ 9'd268: v = { ___FLG } ; //  5;
	/*  INSTR_GPF	04*/ 9'd269: v = { LAST__ } ; //  5;
	//--------------------------------
	/*  INSTR_GPL	00*/ 9'd270: v = { RSTFLG } ; //  5;
	/*  INSTR_GPL	01*/ 9'd271: v = { ___FLG } ; //  5;
	/*  INSTR_GPL	02*/ 9'd272: v = { ___FLG } ; //  5;
	/*  INSTR_GPL	03*/ 9'd273: v = { ___FLG } ; //  5;
	/*  INSTR_GPL	04*/ 9'd274: v = { LAST__ } ; //  5;
	//--------------------------------
	/*  INSTR_NCCT	00*/ 9'd275: v = { RSTFLG } ; // 39;
	/*  INSTR_NCCT	01*/ 9'd276: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	02*/ 9'd277: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	03*/ 9'd278: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	04*/ 9'd279: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	05*/ 9'd280: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	06*/ 9'd281: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	07*/ 9'd282: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	08*/ 9'd283: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	09*/ 9'd284: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	10*/ 9'd285: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	11*/ 9'd286: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	12*/ 9'd287: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	13*/ 9'd288: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	14*/ 9'd289: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	15*/ 9'd290: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	16*/ 9'd291: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	17*/ 9'd292: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	18*/ 9'd293: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	19*/ 9'd294: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	20*/ 9'd295: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	21*/ 9'd296: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	22*/ 9'd297: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	23*/ 9'd298: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	24*/ 9'd299: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	25*/ 9'd300: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	26*/ 9'd301: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	27*/ 9'd302: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	28*/ 9'd303: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	29*/ 9'd304: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	30*/ 9'd305: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	31*/ 9'd306: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	32*/ 9'd307: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	33*/ 9'd308: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	34*/ 9'd309: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	35*/ 9'd310: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	36*/ 9'd311: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	37*/ 9'd312: v = { ___FLG } ; // 39;
	/*  INSTR_NCCT	38*/ 9'd313: v = { LAST__ } ; // 39;
	//--------------------------------
	/*  INSTR_DEF   00*/default: v = { LAST__ } ; // 1;
	endcase
end
assign microCode = v;

endmodule
