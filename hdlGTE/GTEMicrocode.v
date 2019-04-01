module GTEMicrocode (
	input  [8:0] PC,
	
	input        instr_sf,
	input        instr_lm,
	input  [1:0] instr_cv,
	input  [1:0] instr_vec,
	input  [1:0] instr_mx,

	output gteLastMicroInstruction,
	
	// Special Register Side WRITE
	output gtePshR,
	output gtePshG,
	output gtePshB,
	output gteWrtSZ3,
	output gteWrtSPX,
	output gteWrtSPY,
	output gteWrtShadowIR, // Write into Shadow FIFO.
	output gteCpyShadowIR, // Flush the Shadow to real register.
	output [3:0] gteWrtIR,
	
		// Special Register READ
		output [4:0] gteReadCustomRegA,
		output [4:0] gteReadCustomRegB,
	
	// Flags
	output gteLM,
	output gteResetStatus,
	output gteSF,				// TODO Today
	output gteForceSF_B,		// TODO Today
	output [14:0] gteFlagMask,

		// Register File READ
		output [4:0] gteReadAdrDataA,
		output [4:0] gteReadAdrDataB,
		output [4:0] gteReadAdrCtrlA,
		output [4:0] gteReadAdrCtrlB,
		output       readHighA,			// WARNING : setup 1 cycle LATER after READ.
		output       readHighB,			// WARNING : setup 1 cycle LATER after READ.
		output [1:0] selectColA,
		output [1:0] selectColB,
		
		// Register File WRITE
		output gteWriteToDataFile,
		output [4:0] gteWriteAdrData,
	output gteWriteToCtrlFile,
	output [4:0] gteWriteAdrCtrl,
		
		// Computation Path control...
		output [1:0] select16A,
		output       selAA,
		output [1:0] select32A,
		output       shft12A,
		output       negB_A,
		
		output [1:0] select16B,
		output       selAB,
		output [1:0] select32B,
		output       shft12B,
		output       negB_B
);
// -------------------------------------------------------------------------------------------------------------------------------------
//   Write to CTRL REGISTER FILES
// -------------------------------------------------------------------------------------------------------------------------------------
assign gteWriteToCtrlFile	= 0; 	// Probably forever that way...
assign gteWriteAdrCtrl		= 5'd0;	// Probably forever that way...

// -------------------------------------------------------------------------------------------------------------------------------------
//   Last Instruction, Reset Flags.
// -------------------------------------------------------------------------------------------------------------------------------------
assign gteLastMicroInstruction	= v[0];
assign gteResetStatus			= v[1];

parameter	___FLG = 2'b00,
			LAST__ = 2'b01,
			RSTFLG = 2'b10;
// -------------------------------------------------------------------------------------------------------------------------------------

// -------------------------------------------------------------------------------------------------------------------------------------
//   Write IR register, Write Shadow IR, Flush Shadow IR, Flag Mask, Force reset LM, 
// -------------------------------------------------------------------------------------------------------------------------------------
wire [1:0] ctrlWriteID    		= v[3:2];
wire [3:0] ctrlWriteFlgLm 		= v[7:4];

parameter	NO________	= 4'd0, 
			AB__WMS_LM	= 4'd1, //	AB__WMS_LM	: Write shadowIR            , LM of instruction, Flag Ax/Bx    setup.
			AB__WMF_LM	= 4'd2, //	AB__WMF_LM	: Write IR3 + Flush ShadowIR, LM of instruction, Flag A3/B3    setup.
			AB______L0	= 4'd3, //	AB______L0  :                             LM force 0       , Flag Ax/Bx    setup.
			ABC_WIC_LM	= 4'd4, //	ABC_WIC_LM  : Write IRx                 , LM of instruction, Flag Ax/Bx/Cx setup. Push color x(RGB)
			AB__WI__LM	= 4'd5, //	AB__WI__LM  : Write IRx                 , LM of instruction, Flag Ax/Bx    setup.
			ABC_WMSCLM	= 4'd6, //	ABC_WMSCLM  : Write shadowIR            , LM of instruction, Flag Ax/Bx/Cx setup. Push color x(RGB)
			ABC_WMFCLM	= 4'd7, //	ABC_WMFCLM  : Write IR3 + Flush ShadowIR, LM of instruction, Flag Ax/Bx/Cx setup. Push color x(RGB)
			DF__W_____	= 4'd8; //	DF__W_____  : Write D Clamped to OTZ                       , Flag D/F      setup.
		
reg  flagA,flagC,flagD;
reg  wrIR;
reg  LM_as_is;
reg  pshCol;
always @(ctrlWriteFlgLm) begin
	case (ctrlWriteFlgLm)
	default 
/*NO________*/: begin gteWrtShadowIR = 0; gteCpyShadowIR = 0; LM_as_is = 1; flagA = 0; flagC = 0; flagD = 0; wrIR = 0; pshCol = 0; end
	AB__WMS_LM:	begin gteWrtShadowIR = 1; gteCpyShadowIR = 0; LM_as_is = 1; flagA = 1; flagC = 0; flagD = 0; wrIR = 0; pshCol = 0; end
	AB__WMF_LM: begin gteWrtShadowIR = 0; gteCpyShadowIR = 1; LM_as_is = 1; flagA = 1; flagC = 0; flagD = 0; wrIR = 1; pshCol = 0; end
	AB______L0: begin gteWrtShadowIR = 0; gteCpyShadowIR = 0; LM_as_is = 0; flagA = 1; flagC = 0; flagD = 0; wrIR = 0; pshCol = 0; end
	ABC_WIC_LM: begin gteWrtShadowIR = 0; gteCpyShadowIR = 0; LM_as_is = 1; flagA = 1; flagC = 1; flagD = 0; wrIR = 1; pshCol = 1; end
	AB__WI__LM: begin gteWrtShadowIR = 0; gteCpyShadowIR = 0; LM_as_is = 1; flagA = 1; flagC = 0; flagD = 0; wrIR = 1; pshCol = 0; end
	ABC_WMSCLM: begin gteWrtShadowIR = 1; gteCpyShadowIR = 0; LM_as_is = 1; flagA = 1; flagC = 1; flagD = 0; wrIR = 0; pshCol = 1; end
	ABC_WMFCLM: begin gteWrtShadowIR = 0; gteCpyShadowIR = 1; LM_as_is = 1; flagA = 1; flagC = 1; flagD = 0; wrIR = 1; pshCol = 1; end
	DF__W_____: begin gteWrtShadowIR = 0; gteCpyShadowIR = 0; LM_as_is = 1; flagA = 0; flagC = 0; flagD = 1; wrIR = 0; pshCol = 0; end
	
	endcase
end
// F use same flag as D for now.
wire is0   = (ctrlWriteID==2'b00);
wire is1   = (ctrlWriteID==2'b01);
wire is2   = (ctrlWriteID==2'b10);
wire is3   = (ctrlWriteID==2'b11);

assign gteLM		   = LM_as_is & instr_lm;
assign gteWrtIR	  [ 0] = wrIR  & is0;
assign gteWrtIR	  [ 1] = wrIR  & is1;
assign gteWrtIR	  [ 2] = wrIR  & is2;
assign gteWrtIR	  [ 3] = wrIR  & is3;
// A Flag
assign gteFlagMask[14] = flagA & is1;
assign gteFlagMask[13] = flagA & is2;
assign gteFlagMask[12] = flagA & is3;
// OPTIMIZE : Final optimization B use same flag as A
assign gteFlagMask[11] = flagA & is1;
assign gteFlagMask[10] = flagA & is2;
assign gteFlagMask[ 9] = flagA & is3;

assign gteFlagMask[ 8] = flagC & is1;
assign gteFlagMask[ 7] = flagC & is2;
assign gteFlagMask[ 6] = flagC & is3;
assign gteFlagMask[ 5] = flagD;
assign gteFlagMask[ 4] = flagE;
assign gteFlagMask[ 3] = flagF;
assign gteFlagMask[ 2] = flagG & is1;
assign gteFlagMask[ 1] = flagG & is2;
assign gteFlagMask[ 0] = flagH;
assign gtePshR		   = pshCol & is1;
assign gtePshG		   = pshCol & is2;
assign gtePshB		   = pshCol & is3;

wire   flagF = flagD; // TODO : time will come when not the same as D.
wire   flagE           = 1'b0; // TODO
wire   flagG           = 1'b0; // TODO
wire   flagH           = 1'b0; // TODO
assign gteWrtSZ3	   = 1'b0; // TODO
assign gteWrtSPX       = 1'b0; // TODO
assign gteWrtSPY       = 1'b0; // TODO
// -------------------------------------------------------------------------------------------------------------------------------------

// -------------------------------------------------------------------------------------------------------------------------------------
//   UNIT A & B Control
// -------------------------------------------------------------------------------------------------------------------------------------
wire [3:0]  mode_A    			= v[11: 8]; // TODO
wire [3:0]  mode_B    			= v[15:12]; // TODO

parameter	C32SHF12 = 4'd0,
			R16SHF12 = 4'd1,
			NU8SHF16 = 4'd2,
			NU8SHF4_ = 4'd3,
			A16R16__ = 4'd4,
			R16C16__ = 4'd5,
			R16U8SH4 = 4'd6,
			D16C16_N = 4'd7,
			D16C16__ = 4'd8,
			R16R16__ = 4'd9,
			NO_OP___ = 4'd10;

parameter   C32_     = 2'b00,
			B16_     = 2'b01,
			U816     = 2'b10,
			U8_4     = 2'b11;
			
parameter   MUL0	 = 2'b00,
			MUL1	 = 2'b01,
			M_N1	 = 2'b10,
			MVAL	 = 2'b11;

reg [1:0] select16_A, select16_B, select32_A, select32_B;
reg       selA_A, selA_B, shft12_A, shft12_B, negBr_A,negBr_B;
always @(mode_A) begin
	case (mode_A)
	C32SHF12: begin select16_A = MUL1; selA_A = 1; select32_A = C32_; shft12_A = 1; negBr_A=0; end
	R16SHF12: begin select16_A = MUL1; selA_A = 1; select32_A = B16_; shft12_A = 1; negBr_A=0; end
	NU8SHF16: begin select16_A = MUL1; selA_A = 1; select32_A = U816; shft12_A = 0; negBr_A=0; end
	NU8SHF4_: begin select16_A = MUL1; selA_A = 1; select32_A = U8_4; shft12_A = 0; negBr_A=0; end
	A16R16__: begin select16_A = MVAL; selA_A = 1; select32_A = B16_; shft12_A = 0; negBr_A=0; end
	// TODO : optimize case R16/D16
	R16C16__: begin select16_A = MVAL; selA_A = 0; select32_A = B16_; shft12_A = 0; negBr_A=0; end
	R16U8SH4: begin select16_A = MVAL; selA_A = 0; select32_A = U8_4; shft12_A = 0; negBr_A=0; end
	D16C16_N: begin select16_A = MVAL; selA_A = 0; select32_A = B16_; shft12_A = 0; negBr_A=1; end
	D16C16__: begin select16_A = MVAL; selA_A = 0; select32_A = B16_; shft12_A = 0; negBr_A=0; end
	R16R16__: begin select16_A = MVAL; selA_A = 0; select32_A = B16_; shft12_A = 0; negBr_A=0; end
	default 
/*NO_OP___*/: begin select16_A = MUL0; selA_A = 0; select32_A = U8_4; shft12_A = 0; negBr_A=0; end
	endcase
end
	/*
	C32SHF12	// Right Side
	R16SHF12	// Right Side
	NU8SHF16	// Right Side
	NU8SHF4_	// Right Side
	A16R16__	// A:Left, R :Right
	R16C16__	// R:Left, C :Right
	R16U8SH4	// R:Left, U8:Right
	D16C16_N
	D16C16__	// R:Left, C :Right (Same as R16C16 but higher selector from register vs data)
	R16R16__    // R:Left, R :Right (Same as R16C16 but higher selector from register vs register) IRx*IRx
	NO_OP___
                                                    -i16B  i16B  -U8   U8               
                       iD16    A16                     |    |     |    |                
                        |      |                      +-------+ +-------+               
                      -------------                    \     /   \     /                
                       \0      1 /                      \   /<----\   /<-------- negB   
                        \       /<----- selA             +-+       +-+                  
                         +-----+                       17b|         |9b                 
                            |                             | u8<<16  |                   
                0   +1  -1  |                       i32C  |   +-----+              
                |   |   |   |                         |   |   |     | u8<<4                  
              -----------------                    --------------------                 
              \ 0   1   2   3 /                     \ 0   1   2     3/                  
               \             /<---- Select 16        \              /<---- Select 32    
                +-----------+                         +------------+                    
                     |                                      |       Note : i16B is sign extended.
					 +----------------[ * ]-----------------+                           
					                    |                                               
									[ << 12 ]<--- shft12                                
									    |                                               



			  C32SHF12      NU8SHF16
	Lm_B#( A#((C32 << 12) - ( U8 << 16)      ), 0) // 2 Step
	Lm_B#( A#((C32 << 12) - (R16 << 12)      ), 0) // 2 Step
	Lm_B#( A#((C32 << 12) - (R16 *U8<<4))      , 0) // 2 Step, outside NEG.
	MAC# = A#((U8  << 16) + (R16 * A16)                            ); // 2 Step
	MAC# = A#((U8  << 16) + (R16 * A16)                            ); // 2 Step
	MAC# = A#((R16 << 12) + (R16 * A16)                            ); // 2 Step
	MAC# = A#(              (R16*U8<<4) + (R16 * A16)              ); // 2 Step
	MAC# = A#(              (R16*U8<<4)                            ); // 1 Step
	MAC# = A#(              (C16 * R16) - (C16 * R16)              ); // 2 Step
	MAC# = A#(              (C16 * D16) + (C16 * D16) + (C16 * D16));
	MAC# = A#(              (C16 * D16) + (C16 * D16)              );
	MAC# = A#((C32 << 12) + (C16 * D16) + (C16 * D16) + (C16 * D16));
	MAC# = A#((C32 << 12) + (C16 * R16) + (C16 * R16) + (C16 * R16));
	MAC# = A#((C32 << 12) + (C16 * D16) + (C16 * D16) + (C16 * D16));
	MAC# = A#(              (R16 * R16)                            ); <-- special case, same reg. (IR1/2/3)

	MAC# = A#(gte_shift(MAC#, -m_sf) + (R16 * R16));
     */
		

// -------------------------------------------------------------------------------------------------------------------------------------


			
			
			
// TODO `include "GTEConsts.vh"

/*	TODO 1/4/2019 : Convert enum+2bitID into 
		output gtePshR,
		output gtePshG,
		output gtePshB,
output gteWrtShadowIR, // Write into Shadow FIFO.
output gteCpyShadowIR, // Flush the Shadow to real register.
		output [3:0] gteWrtIR,
		gteFlagMask
		gteLM

// HANDLE WITH OTHER PLACES ? --> REGISTER TARGET.
Write MACx, 		
Write MAC3, 
            
Write MACx, 
Write MACx, 
Write MACx, 		
Write MACx, 		
Write MAC0, 		
		
		
		
*/


	parameter	N = 1'b1,
				L = 1'b0,
				H = 1'b1;
				
	parameter	CT_R22R23 = 6'd0,	// TODO redo values.
				CT____R33 = 6'd1,
				NO_DATA_R = 6'd2,
				CT_R11R12 = 6'd3,
				DATA__IR3 = 6'd4,
				DATA__IR2 = 6'd5,
				DATA__IR1 = 6'd6,
				NO_DATA_C = 6'd7;
	
/*
1. Microcode for write to Register R/G/B/IR0/IR1/IR2/IR3
2. Microcode for computation
3. Microcode for flag setup
4. Microcode for reading registers.

Flag Setup Pattern :

	AB_MI,1 // 
	AB_MS,1 // Shadow IR
	AB_MF,3 // Write to IR3 -> Flush IR
	
	Note correct value is taken (path hardcoded)
	// Pattern A
	A1/B1    -> Write to MAC1 + Write to IR1     + setup flag APos1/ANeg1/B1
	A2/B2    -> Write to MAC2 + Write to IR2     + setup flag APos2/ANeg2/B2
	A3/B3    -> Write to MAC3 + Write to IR3     + setup flag APos3/ANeg3/B3
	// Pattern A'
	A1/B1    -> Write to MAC1 + Write to Shadow IR + setup flag APos1/ANeg1/B1
	A2/B2    -> Write to MAC2 + Write to Shadow IR + setup flag APos2/ANeg2/B2
	A3/B3    -> Write to MAC3 + Write to Shadow IR + setup flag APos3/ANeg3/B3
	// Pattern B
	A3/B3    -> Write to MAC3 + Write to IR3/SZ3 + setup flag APos3/ANeg3/B3 with force flag/D/
	// Pattern C
	F        -> Write to MAC0
	// Pattern D
	A1/B1    -> LM set to 0                      + setup flag APos1/ANeg1/B1
	A2/B2    -> LM set to 0                      + setup flag APos2/ANeg2/B2
	A3/B3    -> LM set to 0                      + setup flag APos3/ANeg3/B3
	// Pattern E
	A1/B1/C1 -> Write to MAC1 + Write to IR1 + PushR + setup flag APos1/ANeg1/B1/C1
	A2/B2/C2 -> Write to MAC2 + Write to IR2 + PushG + setup flag APos2/ANeg2/B2/C2
	A3/B3/C3 -> Write to MAC3 + Write to IR3 + PushB + setup flag APos3/ANeg3/B3/C3 // Code pushed with B
	// Pattern E'
	A1/B1/C1 -> Write to MAC1 + Write to Shadow IR + PushR + setup flag APos1/ANeg1/B1/C1
	A2/B2/C2 -> Write to MAC2 + Write to Shadow IR + PushG + setup flag APos2/ANeg2/B2/C2
	A3/B3/C3 -> Write to MAC3 + Write to IR3 + ShadowFlush + PushB + setup flag APos3/ANeg3/B3/C3 // Code pushed with B
	// 

		// Pattern 4 bit enough. + 2 bit numbering : 01/10/11
*/

// Include Microcode constants.

//  5 5 5 5 5 5 5 5 5 4 4 4 4 4 4 4 4 4 4 4 3 3 3 3 3 3 3 3 3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
//  9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
//      | | | | | | | | | | | | | | | | | | | +-------+ +-------+ | | | | | | +-------+ +-------+ +-------+ +-------+ | | |
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         |         |         |         | | | Reset Status Flag (1=Reset)
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         |         |         |         | | Last Instruction
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         |         |         |         | lm bit override (0=Reset flag,1=lm as is)
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         |         |         |         Read Adress DATA File A
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         |         |         Read Adress DATA File B
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         |         Read Adress CTRL File A
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | |         Read Adress CTRL File B
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | | Write DATA                      
//      | | | | | | | | | | | | | | | | | | |         |         | | | | | Write CTRL                        
//      | | | | | | | | | | | | | | | | | | |         |         | | | | Write SZ Fifo                       
//      | | | | | | | | | | | | | | | | | | |         |         | | | Write SX Fifo                        
//      | | | | | | | | | | | | | | | | | | |         |         | | Write SY Fifo                           
//      | | | | | | | | | | | | | | | | | | |         |         | Write CRGB Fifo                           
//      | | | | | | | | | | | | | | | | | | |         |         Write Adress Data                            
//      | | | | | | | | | | | | | | | | | | |         Write Adress CTRL                                     
//      | 121314151617181921222324252627282930 Update Status Registers Bits with value from flag unit.     
//      sf bit override (                                                                                                    
//                                                                                                          
//                                                                                                          
//                                                                                                          
//                                                                                                          
//                                                                                                          
//                                                                                                          
//                                                                                                          
// MicroCode ROM Table
reg [58:0] v;
always @(PC) begin
	case (PC)
	9'd0  : v = { RSTFLG } ; // 15;  INSTR_RTPS	00
	9'd1  : v = { ___FLG } ; // 15;  INSTR_RTPS	01
	9'd2  : v = { ___FLG } ; // 15;  INSTR_RTPS	02
	9'd3  : v = { ___FLG } ; // 15;  INSTR_RTPS	03
	9'd4  : v = { ___FLG } ; // 15;  INSTR_RTPS	04
	9'd5  : v = { ___FLG } ; // 15;  INSTR_RTPS	05
	9'd6  : v = { ___FLG } ; // 15;  INSTR_RTPS	06
	9'd7  : v = { ___FLG } ; // 15;  INSTR_RTPS	07
	9'd8  : v = { ___FLG } ; // 15;  INSTR_RTPS	08
	9'd9  : v = { ___FLG } ; // 15;  INSTR_RTPS	09
	9'd10 : v = { ___FLG } ; // 15;  INSTR_RTPS	10
	9'd11 : v = { ___FLG } ; // 15;  INSTR_RTPS	11
	9'd12 : v = { ___FLG } ; // 15;  INSTR_RTPS	12
	9'd13 : v = { ___FLG } ; // 15;  INSTR_RTPS	13
	9'd14 : v = { LAST__ } ; // 15;  INSTR_RTPS	14
	//--------------------------------
	9'd15 : v = { RSTFLG } ; //  8;  INSTR_NCLIP 00
	9'd16 : v = { ___FLG } ; //  8;  INSTR_NCLIP 01
	9'd17 : v = { ___FLG } ; //  8;  INSTR_NCLIP 02
	9'd18 : v = { ___FLG } ; //  8;  INSTR_NCLIP 03
	9'd19 : v = { ___FLG } ; //  8;  INSTR_NCLIP 04
	9'd20 : v = { ___FLG } ; //  8;  INSTR_NCLIP 05
	9'd21 : v = { ___FLG } ; //  8;  INSTR_NCLIP 06
	9'd22 : v = { LAST__ } ; //  8;  INSTR_NCLIP 07
	//--------------------------------
	
	9'd23 : v = { NO_OP___,NO_OP___ ,N,N,CT_R22R23,CT____R33, NO_DATA_R,NO_DATA_R, NO________,2'd0, RSTFLG } ; //   INSTR_OP	00 
	9'd24 : v = { D16C16__,D16C16_N ,H,L,CT____R33,CT_R11R12, DATA__IR3,DATA__IR2, AB__WMS_LM,2'd1, ___FLG } ; //   INSTR_OP	01 
	9'd25 : v = { D16C16__,D16C16_N ,L,H,CT_R11R12,CT_R22R23, DATA__IR1,DATA__IR3, AB__WMS_LM,2'd2, ___FLG } ; //   INSTR_OP	02 
	9'd26 : v = { D16C16__,D16C16_N ,H,H,NO_DATA_C,NO_DATA_C, DATA__IR2,DATA__IR1, AB__WMF_LM,2'd3, ___FLG } ; //   INSTR_OP	03 
	9'd27 : v = { NO_OP___,NO_OP___ ,N,N,NO_DATA_C,NO_DATA_C, NO_DATA_R,NO_DATA_R, NO________,2'd0, ___FLG } ; //   INSTR_OP	04 
	9'd28 : v = { NO_OP___,NO_OP___ ,N,N,NO_DATA_C,NO_DATA_C, NO_DATA_R,NO_DATA_R, NO________,2'd0, LAST__ } ; //   INSTR_OP	05 
	//--------------------------------
	9'd29 : v = { NO________,2'd0, RSTFLG } ; //  8;  INSTR_DPCS	00
	9'd30 : v = { AB______L0,2'd1, ___FLG } ; //  8;  INSTR_DPCS	01
	9'd31 : v = { ABC_WIC_LM,2'd1, ___FLG } ; //  8;  INSTR_DPCS	02
	9'd32 : v = { AB______L0,2'd2, ___FLG } ; //  8;  INSTR_DPCS	03
	9'd33 : v = { ABC_WIC_LM,2'd2, ___FLG } ; //  8;  INSTR_DPCS	04
	9'd34 : v = { AB______L0,2'd3, ___FLG } ; //  8;  INSTR_DPCS	05
	9'd35 : v = { ABC_WIC_LM,2'd3, ___FLG } ; //  8;  INSTR_DPCS	06
	9'd36 : v = { NO________,2'd0, LAST__ } ; //  8;  INSTR_DPCS	07
	//------------------------------
	9'd37 : v = { NO________,2'd0, RSTFLG } ; //  8;  INSTR_INTPL 00
	9'd38 : v = { AB______L0,2'd1, ___FLG } ; //  8;  INSTR_INTPL 01
	9'd39 : v = { ABC_WIC_LM,2'd1, ___FLG } ; //  8;  INSTR_INTPL 02
	9'd40 : v = { AB______L0,2'd2, ___FLG } ; //  8;  INSTR_INTPL 03
	9'd41 : v = { ABC_WIC_LM,2'd2, ___FLG } ; //  8;  INSTR_INTPL 04
	9'd42 : v = { AB______L0,2'd3, ___FLG } ; //  8;  INSTR_INTPL 05
	9'd43 : v = { ABC_WIC_LM,2'd3, ___FLG } ; //  8;  INSTR_INTPL 06
	9'd44 : v = { NO________,2'd0, LAST__ } ; //  8;  INSTR_INTPL 07
	//--------------------------------
		// TODO, depend on version with CV
		9'd45 : v = { RSTFLG } ; //  8;  INSTR_MVMVA 00
		9'd46 : v = { ___FLG } ; //  8;  INSTR_MVMVA 01
		9'd47 : v = { ___FLG } ; //  8;  INSTR_MVMVA 02
		9'd48 : v = { ___FLG } ; //  8;  INSTR_MVMVA 03
		9'd49 : v = { ___FLG } ; //  8;  INSTR_MVMVA 04
		9'd50 : v = { ___FLG } ; //  8;  INSTR_MVMVA 05
		9'd51 : v = { ___FLG } ; //  8;  INSTR_MVMVA 06
		9'd52 : v = { LAST__ } ; //  8;  INSTR_MVMVA 07
	//--------------------------------
	9'd53 : v = { NO________,2'd0, RSTFLG } ; // 19;  INSTR_NCDS	00
	9'd54 : v = { NO________,2'd0, ___FLG } ; // 19;  INSTR_NCDS	01
	9'd55 : v = { AB__WI__LM,2'd1, ___FLG } ; // 19;  INSTR_NCDS	02
	9'd56 : v = { NO________,2'd0, ___FLG } ; // 19;  INSTR_NCDS	03
	9'd57 : v = { AB__WI__LM,2'd2, ___FLG } ; // 19;  INSTR_NCDS	04
	9'd58 : v = { NO________,2'd0, ___FLG } ; // 19;  INSTR_NCDS	05
	9'd59 : v = { AB__WI__LM,2'd3, ___FLG } ; // 19;  INSTR_NCDS	06
	9'd60 : v = { NO________,2'd0, ___FLG } ; // 19;  INSTR_NCDS	07
	9'd61 : v = { AB__WMS_LM,2'd1, ___FLG } ; // 19;  INSTR_NCDS	08
	9'd62 : v = { NO________,2'd0, ___FLG } ; // 19;  INSTR_NCDS	09
	9'd63 : v = { AB__WMS_LM,2'd2, ___FLG } ; // 19;  INSTR_NCDS	10
	9'd64 : v = { NO________,2'd0, ___FLG } ; // 19;  INSTR_NCDS	11
	9'd65 : v = { AB__WMF_LM,2'd3, ___FLG } ; // 19;  INSTR_NCDS	12
	9'd66 : v = { AB______L0,2'd1, ___FLG } ; // 19;  INSTR_NCDS	13
	9'd67 : v = { ABC_WIC_LM,2'd1, ___FLG } ; // 19;  INSTR_NCDS	14
	9'd68 : v = { AB______L0,2'd2, ___FLG } ; // 19;  INSTR_NCDS	15
	9'd69 : v = { ABC_WIC_LM,2'd2, ___FLG } ; // 19;  INSTR_NCDS	16
	9'd70 : v = { AB______L0,2'd3, ___FLG } ; // 19;  INSTR_NCDS	17
	9'd71 : v = { ABC_WIC_LM,2'd3, LAST__ } ; // 19;  INSTR_NCDS	18
	//--------------------------------
	9'd72 : v = { NO________,2'd0, RSTFLG } ; // 13;  INSTR_CDP	00
	9'd73 : v = { NO________,2'd0, ___FLG } ; // 13;  INSTR_CDP	01
	9'd74 : v = { AB__WMS_LM,2'd1, ___FLG } ; // 13;  INSTR_CDP	02
	9'd75 : v = { NO________,2'd0, ___FLG } ; // 13;  INSTR_CDP	03
	9'd76 : v = { AB__WMS_LM,2'd2, ___FLG } ; // 13;  INSTR_CDP	04
	9'd77 : v = { NO________,2'd0, ___FLG } ; // 13;  INSTR_CDP	05
	9'd78 : v = { AB__WMF_LM,2'd3, ___FLG } ; // 13;  INSTR_CDP	06
	9'd79 : v = { AB______L0,2'd1, ___FLG } ; // 13;  INSTR_CDP	07
	9'd80 : v = { ABC_WIC_LM,2'd1, ___FLG } ; // 13;  INSTR_CDP	08
	9'd81 : v = { AB______L0,2'd2, ___FLG } ; // 13;  INSTR_CDP	09
	9'd82 : v = { ABC_WIC_LM,2'd2, ___FLG } ; // 13;  INSTR_CDP	10
	9'd83 : v = { AB______L0,2'd3, ___FLG } ; // 13;  INSTR_CDP	11
	9'd84 : v = { ABC_WIC_LM,2'd3, LAST__ } ; // 13;  INSTR_CDP	12
	//--------------------------------
		// TODO
	9'd85 : v = { RSTFLG } ; // 44;  INSTR_NCDT	00
	9'd86 : v = { ___FLG } ; // 44;  INSTR_NCDT	01
	9'd87 : v = { ___FLG } ; // 44;  INSTR_NCDT	02
	9'd88 : v = { ___FLG } ; // 44;  INSTR_NCDT	03
	9'd89 : v = { ___FLG } ; // 44;  INSTR_NCDT	04
	9'd90 : v = { ___FLG } ; // 44;  INSTR_NCDT	05
	9'd91 : v = { ___FLG } ; // 44;  INSTR_NCDT	06
	9'd92 : v = { ___FLG } ; // 44;  INSTR_NCDT	07
	9'd93 : v = { ___FLG } ; // 44;  INSTR_NCDT	08
	9'd94 : v = { ___FLG } ; // 44;  INSTR_NCDT	09
	9'd95 : v = { ___FLG } ; // 44;  INSTR_NCDT	10
	9'd96 : v = { ___FLG } ; // 44;  INSTR_NCDT	11
	9'd97 : v = { ___FLG } ; // 44;  INSTR_NCDT	12
	9'd98 : v = { ___FLG } ; // 44;  INSTR_NCDT	13
	9'd99 : v = { ___FLG } ; // 44;  INSTR_NCDT	14
	9'd100: v = { ___FLG } ; // 44;  INSTR_NCDT	15
	9'd101: v = { ___FLG } ; // 44;  INSTR_NCDT	16
	9'd102: v = { ___FLG } ; // 44;  INSTR_NCDT	17
	9'd103: v = { ___FLG } ; // 44;  INSTR_NCDT	18
	9'd104: v = { ___FLG } ; // 44;  INSTR_NCDT	19
	9'd105: v = { ___FLG } ; // 44;  INSTR_NCDT	20
	9'd106: v = { ___FLG } ; // 44;  INSTR_NCDT	21
	9'd107: v = { ___FLG } ; // 44;  INSTR_NCDT	22
	9'd108: v = { ___FLG } ; // 44;  INSTR_NCDT	23
	9'd109: v = { ___FLG } ; // 44;  INSTR_NCDT	24
	9'd110: v = { ___FLG } ; // 44;  INSTR_NCDT	25
	9'd111: v = { ___FLG } ; // 44;  INSTR_NCDT	26
	9'd112: v = { ___FLG } ; // 44;  INSTR_NCDT	27
	9'd113: v = { ___FLG } ; // 44;  INSTR_NCDT	28
	9'd114: v = { ___FLG } ; // 44;  INSTR_NCDT	29
	9'd115: v = { ___FLG } ; // 44;  INSTR_NCDT	30
	9'd116: v = { ___FLG } ; // 44;  INSTR_NCDT	31
	9'd117: v = { ___FLG } ; // 44;  INSTR_NCDT	32
	9'd118: v = { ___FLG } ; // 44;  INSTR_NCDT	33
	9'd119: v = { ___FLG } ; // 44;  INSTR_NCDT	34
	9'd120: v = { ___FLG } ; // 44;  INSTR_NCDT	35
	9'd121: v = { ___FLG } ; // 44;  INSTR_NCDT	36
	9'd122: v = { ___FLG } ; // 44;  INSTR_NCDT	37
	9'd123: v = { ___FLG } ; // 44;  INSTR_NCDT	38
	9'd124: v = { ___FLG } ; // 44;  INSTR_NCDT	39
	9'd125: v = { ___FLG } ; // 44;  INSTR_NCDT	40
	9'd126: v = { ___FLG } ; // 44;  INSTR_NCDT	41
	9'd127: v = { ___FLG } ; // 44;  INSTR_NCDT	42
	9'd128: v = { LAST__ } ; // 44;  INSTR_NCDT	43
	//--------------------------------
	9'd129: v = { NO________,2'd0, RSTFLG } ; // 17;  INSTR_NCCS	00
	9'd130: v = { NO________,2'd0, ___FLG } ; // 17;  INSTR_NCCS	01
	9'd131: v = { AB__WI__LM,2'd1, ___FLG } ; // 17;  INSTR_NCCS	02
	9'd132: v = { NO________,2'd0, ___FLG } ; // 17;  INSTR_NCCS	03
	9'd133: v = { AB__WI__LM,2'd2, ___FLG } ; // 17;  INSTR_NCCS	04
	9'd134: v = { NO________,2'd0, ___FLG } ; // 17;  INSTR_NCCS	05
	9'd135: v = { AB__WI__LM,2'd3, ___FLG } ; // 17;  INSTR_NCCS	06
	9'd136: v = { NO________,2'd0, ___FLG } ; // 17;  INSTR_NCCS	07
	9'd137: v = { AB__WMS_LM,2'd1, ___FLG } ; // 17;  INSTR_NCCS	08
	9'd138: v = { NO________,2'd0, ___FLG } ; // 17;  INSTR_NCCS	09
	9'd139: v = { AB__WMS_LM,2'd2, ___FLG } ; // 17;  INSTR_NCCS	10
	9'd140: v = { NO________,2'd0, ___FLG } ; // 17;  INSTR_NCCS	11
	9'd141: v = { AB__WMF_LM,2'd3, ___FLG } ; // 17;  INSTR_NCCS	12
	9'd142: v = { ABC_WIC_LM,2'd1, ___FLG } ; // 17;  INSTR_NCCS	13
	9'd143: v = { ABC_WIC_LM,2'd2, ___FLG } ; // 17;  INSTR_NCCS	14
	9'd144: v = { ABC_WIC_LM,2'd3, ___FLG } ; // 17;  INSTR_NCCS	15
	9'd145: v = { NO________,2'd0, LAST__ } ; // 17;  INSTR_NCCS	16
	//--------------------------------
	9'd146: v = { NO________,2'd0, RSTFLG } ; // 11;  INSTR_CC 	00
	9'd147: v = { NO________,2'd0, ___FLG } ; // 11;  INSTR_CC 	01
	9'd148: v = { AB__WMS_LM,2'd1, ___FLG } ; // 11;  INSTR_CC 	02
	9'd149: v = { NO________,2'd0, ___FLG } ; // 11;  INSTR_CC 	03
	9'd150: v = { AB__WMS_LM,2'd2, ___FLG } ; // 11;  INSTR_CC 	04
	9'd151: v = { NO________,2'd0, ___FLG } ; // 11;  INSTR_CC 	05
	9'd152: v = { AB__WMF_LM,2'd3, ___FLG } ; // 11;  INSTR_CC 	06
	9'd153: v = { ABC_WIC_LM,2'd1, ___FLG } ; // 11;  INSTR_CC 	07
	9'd154: v = { ABC_WIC_LM,2'd2, ___FLG } ; // 11;  INSTR_CC 	08
	9'd155: v = { ABC_WIC_LM,2'd3, ___FLG } ; // 11;  INSTR_CC 	09
	9'd156: v = { NO________,2'd0, LAST__ } ; // 11;  INSTR_CC 	10
	//------------------------------
	9'd157: v = { NO________,2'd0, RSTFLG } ; // 14;  INSTR_NCS 	00
	9'd158: v = { NO________,2'd0, ___FLG } ; // 14;  INSTR_NCS 	01
	9'd159: v = { AB__WI__LM,2'd1, ___FLG } ; // 14;  INSTR_NCS 	02
	9'd160: v = { NO________,2'd0, ___FLG } ; // 14;  INSTR_NCS 	03
	9'd161: v = { AB__WI__LM,2'd2, ___FLG } ; // 14;  INSTR_NCS 	04
	9'd162: v = { NO________,2'd0, ___FLG } ; // 14;  INSTR_NCS 	05
	9'd163: v = { AB__WI__LM,2'd3, ___FLG } ; // 14;  INSTR_NCS 	06
	9'd164: v = { NO________,2'd0, ___FLG } ; // 14;  INSTR_NCS 	07
	9'd165: v = { ABC_WMSCLM,2'd1, ___FLG } ; // 14;  INSTR_NCS 	08
	9'd166: v = { NO________,2'd0, ___FLG } ; // 14;  INSTR_NCS 	09
	9'd167: v = { ABC_WMSCLM,2'd2, ___FLG } ; // 14;  INSTR_NCS 	10
	9'd168: v = { NO________,2'd0, ___FLG } ; // 14;  INSTR_NCS 	11
	9'd169: v = { ABC_WMFCLM,2'd3, ___FLG } ; // 14;  INSTR_NCS 	12
	9'd170: v = { NO________,2'd0, LAST__ } ; // 14;  INSTR_NCS 	13
	//------------------------------
	9'd171: v = { NO________,2'd0, RSTFLG } ; // 30;  INSTR_NCT 	00
	// Use 3 multiplier !
	9'd172: v = { AB__WI__LM,2'd1, ___FLG } ; // 30;  INSTR_NCT 	01
	9'd173: v = { AB__WI__LM,2'd2, ___FLG } ; // 30;  INSTR_NCT 	02
	9'd174: v = { AB__WI__LM,2'd3, ___FLG } ; // 30;  INSTR_NCT 	03
	9'd175: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	04
	9'd176: v = { ABC_WMSCLM,2'd1, ___FLG } ; // 30;  INSTR_NCT 	05
	9'd177: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	06
	9'd178: v = { ABC_WMSCLM,2'd2, ___FLG } ; // 30;  INSTR_NCT 	07
	9'd179: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	08
	9'd180: v = { ABC_WMFCLM,2'd3, ___FLG } ; // 30;  INSTR_NCT 	09
	// Vector2
	9'd181: v = { AB__WI__LM,2'd1, ___FLG } ; // 30;  INSTR_NCT 	10
	9'd182: v = { AB__WI__LM,2'd2, ___FLG } ; // 30;  INSTR_NCT 	11
	9'd183: v = { AB__WI__LM,2'd3, ___FLG } ; // 30;  INSTR_NCT 	12
	9'd184: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	13
	9'd185: v = { ABC_WMSCLM,2'd1, ___FLG } ; // 30;  INSTR_NCT 	14
	9'd186: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	15
	9'd187: v = { ABC_WMSCLM,2'd2, ___FLG } ; // 30;  INSTR_NCT 	16
	9'd188: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	17
	9'd189: v = { ABC_WMFCLM,2'd3, ___FLG } ; // 30;  INSTR_NCT 	18
	// Vector3
	9'd190: v = { AB__WI__LM,2'd1, ___FLG } ; // 30;  INSTR_NCT 	19
	9'd191: v = { AB__WI__LM,2'd2, ___FLG } ; // 30;  INSTR_NCT 	20
	9'd192: v = { AB__WI__LM,2'd3, ___FLG } ; // 30;  INSTR_NCT 	21
	9'd193: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	22
	9'd194: v = { ABC_WMSCLM,2'd1, ___FLG } ; // 30;  INSTR_NCT 	23
	9'd195: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	24
	9'd196: v = { ABC_WMSCLM,2'd2, ___FLG } ; // 30;  INSTR_NCT 	25
	9'd197: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	26
	9'd198: v = { ABC_WMFCLM,2'd3, ___FLG } ; // 30;  INSTR_NCT 	27
	9'd199: v = { NO________,2'd0, ___FLG } ; // 30;  INSTR_NCT 	28
	9'd200: v = { NO________,2'd0, LAST__ } ; // 30;  INSTR_NCT 	29
	//------------------------------
	9'd201: v = { NO________,2'd0, RSTFLG } ; //  5;  INSTR_SQR 	00
	9'd202: v = { AB__WI__LM,2'd1, ___FLG } ; //  5;  INSTR_SQR 	01
	9'd203: v = { AB__WI__LM,2'd2, ___FLG } ; //  5;  INSTR_SQR 	02
	9'd204: v = { AB__WI__LM,2'd3, ___FLG } ; //  5;  INSTR_SQR 	03
	9'd205: v = { NO________,2'd0, ___FLG } ; //  5;  INSTR_SQR 	04
	//------------------------------
	9'd206: v = { NO________,2'd0, RSTFLG } ; //  8;  INSTR_DCPL  00
	9'd207: v = { AB______L0,2'd1, ___FLG } ; //  8;  INSTR_DCPL  01
	9'd208: v = { ABC_WIC_LM,2'd1, ___FLG } ; //  8;  INSTR_DCPL  02
	9'd209: v = { AB______L0,2'd2, ___FLG } ; //  8;  INSTR_DCPL  03
	9'd210: v = { ABC_WIC_LM,2'd2, ___FLG } ; //  8;  INSTR_DCPL  04
	9'd211: v = { AB______L0,2'd3, ___FLG } ; //  8;  INSTR_DCPL  05
	9'd212: v = { ABC_WIC_LM,2'd3, ___FLG } ; //  8;  INSTR_DCPL  06
	9'd213: v = { NO________,2'd0, LAST__ } ; //  8;  INSTR_DCPL  07
	//--------------------------------
	// TODO 19 cycle to fit into 17 !
	9'd214: v = { RSTFLG } ; // 17;  INSTR_DPCT  00
	9'd215: v = { ___FLG } ; // 17;  INSTR_DPCT  01
	9'd216: v = { ___FLG } ; // 17;  INSTR_DPCT  02
	9'd217: v = { ___FLG } ; // 17;  INSTR_DPCT  03
	9'd218: v = { ___FLG } ; // 17;  INSTR_DPCT  04
	9'd219: v = { ___FLG } ; // 17;  INSTR_DPCT  05
	9'd220: v = { ___FLG } ; // 17;  INSTR_DPCT  06
	9'd221: v = { ___FLG } ; // 17;  INSTR_DPCT  07
	9'd222: v = { ___FLG } ; // 17;  INSTR_DPCT  08
	9'd223: v = { ___FLG } ; // 17;  INSTR_DPCT  09
	9'd224: v = { ___FLG } ; // 17;  INSTR_DPCT  10
	9'd225: v = { ___FLG } ; // 17;  INSTR_DPCT  11
	9'd226: v = { ___FLG } ; // 17;  INSTR_DPCT  12
	9'd227: v = { ___FLG } ; // 17;  INSTR_DPCT  13
	9'd228: v = { ___FLG } ; // 17;  INSTR_DPCT  14
	9'd229: v = { ___FLG } ; // 17;  INSTR_DPCT  15
	9'd230: v = { LAST__ } ; // 17;  INSTR_DPCT  16
	//--------------------------------
	9'd231: v = { NO________,2'd0,RSTFLG } ; //  5;  INSTR_AVSZ3 00
	9'd232: v = { NO________,2'd0,___FLG } ; //  5;  INSTR_AVSZ3 01
	9'd233: v = { NO________,2'd0,___FLG } ; //  5;  INSTR_AVSZ3 02
	9'd234: v = { DF__W_____,2'd0,___FLG } ; //  5;  INSTR_AVSZ3 03
	9'd235: v = { NO________,2'd0,LAST__ } ; //  5;  INSTR_AVSZ3 04
	//-----------------------------
	9'd236: v = { NO________,2'd0,___FLG } ; //  6;  INSTR_AVSZ4 00
	9'd237: v = { NO________,2'd0,___FLG } ; //  6;  INSTR_AVSZ4 01
	9'd238: v = { NO________,2'd0,___FLG } ; //  6;  INSTR_AVSZ4 02
	9'd239: v = { NO________,2'd0,___FLG } ; //  6;  INSTR_AVSZ4 03
	9'd240: v = { DF__W_____,2'd0,___FLG } ; //  6;  INSTR_AVSZ4 04
	9'd241: v = { NO________,2'd0,LAST__ } ; //  6;  INSTR_AVSZ4 05
	//--------------------------------
	// TODO
	9'd242: v = { RSTFLG } ; // 23;  INSTR_RTPT	00
	9'd243: v = { ___FLG } ; // 23;  INSTR_RTPT	01
	9'd244: v = { ___FLG } ; // 23;  INSTR_RTPT	02
	9'd245: v = { ___FLG } ; // 23;  INSTR_RTPT	03
	9'd246: v = { ___FLG } ; // 23;  INSTR_RTPT	04
	9'd247: v = { ___FLG } ; // 23;  INSTR_RTPT	05
	9'd248: v = { ___FLG } ; // 23;  INSTR_RTPT	06
	9'd249: v = { ___FLG } ; // 23;  INSTR_RTPT	07
	9'd250: v = { ___FLG } ; // 23;  INSTR_RTPT	08
	9'd251: v = { ___FLG } ; // 23;  INSTR_RTPT	09
	9'd252: v = { ___FLG } ; // 23;  INSTR_RTPT	10
	9'd253: v = { ___FLG } ; // 23;  INSTR_RTPT	11
	9'd254: v = { ___FLG } ; // 23;  INSTR_RTPT	12
	9'd255: v = { ___FLG } ; // 23;  INSTR_RTPT	13
	9'd256: v = { ___FLG } ; // 23;  INSTR_RTPT	14
	9'd257: v = { ___FLG } ; // 23;  INSTR_RTPT	15
	9'd258: v = { ___FLG } ; // 23;  INSTR_RTPT	16
	9'd259: v = { ___FLG } ; // 23;  INSTR_RTPT	17
	9'd260: v = { ___FLG } ; // 23;  INSTR_RTPT	18
	9'd261: v = { ___FLG } ; // 23;  INSTR_RTPT	19
	9'd262: v = { ___FLG } ; // 23;  INSTR_RTPT	20
	9'd263: v = { ___FLG } ; // 23;  INSTR_RTPT	21
	9'd264: v = { LAST__ } ; // 23;  INSTR_RTPT	22
	//--------------------------------
	9'd265: v = { ABC_WIC_LM,2'd1,RSTFLG } ; //  5;  INSTR_GPF	00 IRx immediate read.
	9'd266: v = { ABC_WIC_LM,2'd2,___FLG } ; //  5;  INSTR_GPF	01
	9'd267: v = { ABC_WIC_LM,2'd3,___FLG } ; //  5;  INSTR_GPF	02
	9'd268: v = { NO________,2'd0,___FLG } ; //  5;  INSTR_GPF	03
	9'd269: v = { NO________,2'd0,LAST__ } ; //  5;  INSTR_GPF	04
	//-----------------------------
	9'd270: v = { NO________,2'd0,RSTFLG } ; //  5;  INSTR_GPL	00 // Delay for MAC1 read.
	9'd271: v = { ABC_WIC_LM,2'd1,___FLG } ; //  5;  INSTR_GPL	01
	9'd272: v = { ABC_WIC_LM,2'd2,___FLG } ; //  5;  INSTR_GPL	02
	9'd273: v = { ABC_WIC_LM,2'd3,___FLG } ; //  5;  INSTR_GPL	03
	9'd274: v = { NO________,2'd0,LAST__ } ; //  5;  INSTR_GPL	04
	//-----------------------------
	9'd275: v = { NO________,2'd0,RSTFLG } ; // 39;  INSTR_NCCT	00
	// Vector 0
	9'd276: v = { AB__WI__LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	01
	9'd277: v = { AB__WI__LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	02
	9'd278: v = { AB__WI__LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	03
	9'd279: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	04
	9'd280: v = { AB__WI__LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	05
	9'd281: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	06
	9'd282: v = { AB__WI__LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	07
	9'd283: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	08
	9'd284: v = { AB__WI__LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	09
	// Vector 1
	9'd285: v = { ABC_WIC_LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	10
	9'd286: v = { ABC_WIC_LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	11
	9'd287: v = { ABC_WIC_LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	12
	9'd288: v = { AB__WI__LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	13
	9'd289: v = { AB__WI__LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	14
	9'd290: v = { AB__WI__LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	15
	9'd291: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	16
	9'd292: v = { AB__WI__LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	17
	9'd293: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	18
	9'd294: v = { AB__WI__LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	19
	9'd295: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	20
	9'd296: v = { AB__WI__LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	21
	// Vector 2
	9'd297: v = { ABC_WIC_LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	22
	9'd298: v = { ABC_WIC_LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	23
	9'd299: v = { ABC_WIC_LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	24
	9'd300: v = { AB__WI__LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	25
	9'd301: v = { AB__WI__LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	26
	9'd302: v = { AB__WI__LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	27
	9'd303: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	28
	9'd304: v = { AB__WI__LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	29
	9'd305: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	30
	9'd306: v = { AB__WI__LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	31
	9'd307: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	32
	9'd308: v = { AB__WI__LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	33
	9'd309: v = { ABC_WIC_LM,2'd1,___FLG } ; // 39;  INSTR_NCCT	34
	9'd310: v = { ABC_WIC_LM,2'd2,___FLG } ; // 39;  INSTR_NCCT	35
	9'd311: v = { ABC_WIC_LM,2'd3,___FLG } ; // 39;  INSTR_NCCT	36
	9'd312: v = { NO________,2'd0,___FLG } ; // 39;  INSTR_NCCT	37
	9'd313: v = { NO________,2'd0,LAST__ } ; // 39;  INSTR_NCCT	38
	//--------------------------------
	default: v = { NO________,2'd0,LAST__ } ; // 1;
	endcase
end

endmodule
