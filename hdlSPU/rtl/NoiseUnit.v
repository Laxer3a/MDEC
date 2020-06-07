/***************************************************************************************************************************************
	Verilog code done by Laxer3A v1.0
 **************************************************************************************************************************************/
module NoiseUnit(
	input			clk,
	input			i_nrst,
	input 			i_ctrl44Khz,
	input	[3:0]	i_noiseShift,
	input   [3:0]	i_noiseStep,
	
	output [15:0] 	o_noiseOut
);

// reg  [1:0] noiseStep; -> M4To7

reg [18:0] noiseTimer;
reg [15:0] noiseLevel;

wire parityBit			= noiseLevel[15] ^ noiseLevel[12] ^ noiseLevel[11] ^ noiseLevel[10] ^ 1;

wire [18:0] M4to7		= { {15{i_noiseStep[3]}} , i_noiseStep };	// In register !!! done at write time.
wire [18:0] inputTimer	= noiseTimer + M4to7;

// OPTIMIZE : this can be put into a register to fasten the logic.
reg [15:0] shiftedNoiseAdd;
always @(*)
begin
	case (i_noiseShift)
	default:shiftedNoiseAdd= 16'b10_0000_0000_0000_00;
	4'd0 : shiftedNoiseAdd = 16'b10_0000_0000_0000_00; 
	4'd1 : shiftedNoiseAdd = 16'b01_0000_0000_0000_00; 
	4'd2 : shiftedNoiseAdd = 16'b00_1000_0000_0000_00; 
	4'd3 : shiftedNoiseAdd = 16'b00_0100_0000_0000_00; 
	4'd4 : shiftedNoiseAdd = 16'b00_0010_0000_0000_00; 
	4'd5 : shiftedNoiseAdd = 16'b00_0001_0000_0000_00; 
	4'd6 : shiftedNoiseAdd = 16'b00_0000_1000_0000_00; 
	4'd7 : shiftedNoiseAdd = 16'b00_0000_0100_0000_00; 
	4'd8 : shiftedNoiseAdd = 16'b00_0000_0010_0000_00; 
	4'd9 : shiftedNoiseAdd = 16'b00_0000_0001_0000_00; 
	4'd10: shiftedNoiseAdd = 16'b00_0000_0000_1000_00; 
	4'd11: shiftedNoiseAdd = 16'b00_0000_0000_0100_00; 
	4'd12: shiftedNoiseAdd = 16'b00_0000_0000_0010_00; 
	4'd13: shiftedNoiseAdd = 16'b00_0000_0000_0001_00; 
	4'd14: shiftedNoiseAdd = 16'b00_0000_0000_0000_10; 
	4'd15: shiftedNoiseAdd = 16'b00_0000_0000_0000_01; 
	endcase
end

wire [18:0] offset  = { 1'b0,shiftedNoiseAdd,2'b0 };
wire [18:0] secondT = inputTimer + offset;
wire [18:0] thirdT  = inputTimer + {shiftedNoiseAdd,3'b0 };
wire [18:0] finalT  = secondT[18]    ? thirdT : secondT;
wire [18:0] writeT  = inputTimer[18] ? finalT : inputTimer;

// NoiseLevel = NoiseLevel*2 + ParityBit
wire [15:0] Noise_Value = { noiseLevel[14:0] , parityBit};

always @(posedge clk)
begin
	if (i_nrst == 0) begin
		noiseTimer = 19'd0;
		noiseLevel = 16'd0;
	end 
	else
	if (i_ctrl44Khz) begin
		noiseTimer = writeT;
		noiseLevel = Noise_Value;
	end
end

assign o_noiseOut = Noise_Value;

endmodule
