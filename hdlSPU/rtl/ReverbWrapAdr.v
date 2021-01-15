/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module ReverbWrapAdr(
	 input [17:0]	i_offsetRegister	// Word Offset. (include -1)
	,input [15:0]	i_baseAdr
	,input [17:0]	i_offsetCounter
	,output [17:0]	o_reverbAdr
);
	wire [18:0] addressWord  = i_offsetRegister + i_offsetCounter;	// 18+18 bit = 19 bit
	wire [19:0] addressWord2 = addressWord + {1'b0,i_baseAdr,2'd0};	// 19+19 bit = 20 bit

	wire overflowAdr = (addressWord2[19:18] != 2'd0);

	// if (addressWord2 >= 262144) { addressWord2 -= (262144 - {i_baseAdr,2'd0}); }
	// ........................... { addressWord2  = addressWord2 - 262144 + {i_baseAdr,2'd0} }
	// ........................... { addressWord2  = addressWord2[17:0]    + {i_baseAdr,2'd0} }

	wire [17:0] rollAdr = addressWord2[17:0] + { i_baseAdr, 2'd0 };

	// If part.
	assign o_reverbAdr  = overflowAdr ? rollAdr : addressWord2[17:0];
endmodule
