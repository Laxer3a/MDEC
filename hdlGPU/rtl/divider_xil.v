/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS (Laxer3a) and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a@hotmail.com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

// signed divider
module divider_xil
#(  parameter Width = 32,
    parameter [Width-1:0] Regs  = 0 )
(
    input               clk,
    input  [Width-1:0]  numerator,    // dividend
    input  [Width-1:0]  denominator,  // divisor
    output [Width-1:0]  quotient
);

    localparam L = Width;

    reg [Width-1:0] p_m[L:0]; // dividend
    reg [Width-1:0] p_n[L:0]; // diviser
    reg [Width-1:0] p_q[L:0]; // quotient
    reg [Width-1:0] p_r[L:0]; // remainder


    localparam [L-1:0] reg_stage = Regs; // calc one day

    always @* begin
        p_m[L] = numerator[Width-1]   ? 0 - numerator   : numerator;
        p_n[L] = denominator[Width-1] ? 0 - denominator : denominator;
        p_q[L] = 0;
        p_r[L] = 0;
    end

    wire invert_in_w = (numerator[Width-1] != denominator[Width-1]);

    reg [4:0] invert_q;

    always @ (posedge clk)
        invert_q <= {invert_in_w, invert_q[4:1]};

    wire invert_out_w = invert_q[0];

    generate
        genvar i;
        for (i=L-1; i >= 0; i=i-1) begin : gen_div
            wire [Width-1:0] sum  = (p_r[i+1] << 1) + p_m[i+1][Width-1];
            wire [Width  :0] diff = sum - p_n[i+1];

            wire [Width-1:0] n_m =  p_m[i+1] << 1;
            wire [Width-1:0] n_n =  p_n[i+1];
            wire [Width-1:0] n_q = (p_q[i+1] << 1) + !diff[Width];
            wire [Width-1:0] n_r = diff[Width] ? sum : diff[Width-1:0];

            if (reg_stage[i]) begin : gen_ff
                always @ ( posedge clk) begin
                    p_m[i] <= n_m;
                    p_n[i] <= n_n;
                    p_q[i] <= n_q;
                    p_r[i] <= n_r;
                end
            end else begin : gen_comb
                always @* begin
                    p_m[i] = n_m;
                    p_n[i] = n_n;
                    p_q[i] = n_q;
                    p_r[i] = n_r;
                end
            end
        end
    endgenerate

    assign quotient = invert_out_w ? (-p_q[0]) : p_q[0];


endmodule
