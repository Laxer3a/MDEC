/*
    Technical shortcut for easier implementation of GTE data path :
    The goal is to avoid being 'stuck' with a technical impossibility (due to unseen issues) in term of bandwidth or //ism.
    So I went directly bold with :
    A - 2 File Register banks for DATA and CTRL.
        - At the same time, why not implementing also x2 multiplier unit in //. -> Improve performance and lower risk of not fitting in original time budget.
    B - Support special parallel write back path to IR0/1/2/3 as special register. Can be used at the same time MAC0/1/2/3 is updated (no time waste) 
    C - Use Micro code to control the instructions.
    D - For now, until synthesis and performance check, no pipelining. (more hellish microcode... no thanks)
    
    If somebody comes up with a cleaner design, reducing memory usage, complexity of data path. I am a taker.
    But for now, I just went with a "it's not optimal, but not too much wasteful" kind of design.
        -> Flexible
        -> Easier to fix timing issues.


		
		
*/

module GTEComputePath (
    input [ 1:0]    select16,   // 0:0,1:-1,2:+1,3:data16
    input           selA,
    input [15:0]    iD16,
    input [15:0]    A16,
    
    input [1:0]     select32,   // i32C,i16B,u8Shl16, u8Shl4,
	input           negB,
    input [31:0]    i32C,
    input [15:0]    i16B,
    input [ 7:0]    i8U,
    
    input           shft12,     // IMPORTANT : Authorized only for select16 -1/0/+1, else buggy output 
    
    output [47:0]   out
);
	
	/*
	C32SHF12	// Right Side
	R16SHF12	// Right Side
	NU8SHF16	// Right Side
	NU8SHF4_	// Right Side
	R16SHF12	// Right Side
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
                0   -1  +1  |                       i32C  |   +-----+              
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
    
    reg signed [15:0] aSide;
    always @ (*)
    begin
        // 
        case (select16)
        0       : aSide = 16'd0;
        1       : aSide = 16'hFFFF;
        2       : aSide = 16'd1;
        default : aSide = selA ? A16 : iD16;
		endcase
    end
    
    reg signed [31:0] bSide;
	wire [16:0] negI  = (~{i16B[15],i16B})+(17'b1);
	wire [16:0] rev17 = negB ? negI : {i16B[15], i16B};
	wire [8:0]  negU  = (~{i8U[7],i8U})+(9'b1);
	wire [8:0]  negU8 = negB ? negU : { 1'b0   ,  i8U};
    always @ (*)
    begin
        case (select32)
        0       : bSide = i32C;
        1       : bSide = {{15{rev17[16]}}, rev17};
        2       : bSide = {{ 7{negU8[ 8]}}, negU8, 16'd0  };
        default : bSide = {{19{negU8[ 8]}}, negU8,  4'd0  };
		endcase
    end
    
    wire signed [47:0] mult = aSide * bSide;

    assign out = shft12 ? { mult[35:0],12'b0 } : mult;
endmodule
