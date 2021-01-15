/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

//
// FIFO for memory command.
//
module MultiClockDomain(
	input	rdClk,
	input	wrClk,
	input	aclr,
	
	input   [289:0] data,
	input			wrreq,
	output			wrfull,

	input			rdreq,
	output  [289:0] q,
	output			rdempty
);
	//
	// Debug version for simulation...
	//
	fifo_fwft #(.DATA_WIDTH(290), .DEPTH_WIDTH(9))
	fifo_fwftInst
    (	.clk	(wrClk),
		.rst	(aclr),
		.din	(data),
		.wr_en	(wrreq),
		.full	(wrfull),
		
		.dout	(q),
		.rd_en	(rdreq),
		.empty	(rdempty)
	);
endmodule

//
// FIFO for response.
//
module MultiClockDomain2(
	input	rdClk,
	input	wrClk,
	input	aclr,
	
	input   [255:0] data,
	input			wrreq,
	output			wrfull,

	input			rdreq,
	output  [255:0] q,
	output			rdempty
);
	//
	// Debug version for simulation...
	//
	fifo_fwft #(.DATA_WIDTH(256), .DEPTH_WIDTH(2))
	fifo_fwftInst
    (	.clk	(rdClk),
		.rst	(aclr),
		.din	(data),
		.wr_en	(wrreq),
		.full	(wrfull),
		
		.dout	(q),
		.rd_en	(rdreq),
		.empty	(rdempty)
	);
endmodule
