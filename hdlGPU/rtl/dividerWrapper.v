/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */


module dividerWrapper(
	input					clock,
	input signed  [31:0]	numerator,
	input signed  [21:0]	denominator,
	output signed [19:0]	output20
);

//-----------------------------------------------------------------
// [For verilator] Simulate a 6 clock latency pipelined divider unit.
//-----------------------------------------------------------------
`ifdef VERILATOR
    reg signed [31:0] num1,num2,num3,num4,num5;
    reg signed [21:0] den1,den2,den3,den4,den5;

    always @(posedge clock)
    begin
        num5 <= num4; den5 <= den4;
        num4 <= num3; den4 <= den3;
        num3 <= num2; den3 <= den2;
        num2 <= num1; den2 <= den1;
        num1 <= numerator;
        den1 <= denominator;
    end
    wire signed [31:0] divisor   = { {10{den5[21]}} ,den5 };
    wire signed [31:0] resultDiv = num5 / divisor;
    assign output20 = resultDiv[19:0];
`else
//-----------------------------------------------------------------
// Altera
//-----------------------------------------------------------------
`ifdef INTEL_FPGA
    wire signed [21:0] remain_sig;
    wire signed [31:0] quot;
    div6    div6_inst (
        .clock ( clock ),
        .denom ( denominator ),
        .numer ( numerator ),
        .quotient ( quot ),
        .remain ( remain_sig )
    );
    assign output20 = quot[19:0];
`else
    //-----------------------------------------------------------------
    // Xilinx
    //-----------------------------------------------------------------
    wire [31:0] resultDiv;

    // 76543210 76543210 76543210 76543210
    // 00000100 00010000 01000000 10000001
    divider_xil #(
        .Width              (32),
        .Regs               (32'h04104081)
    ) div_inst (
        .clk                (clock),
        .numerator          (numerator),
        .denominator        ({ {10{denominator[21]}} ,denominator }),
        .quotient           (resultDiv)
    );

    assign output20 = resultDiv[19:0];

`endif
`endif
endmodule
