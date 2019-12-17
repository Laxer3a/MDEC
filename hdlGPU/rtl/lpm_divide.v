// Copyright (C) 2018 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions 
// and other software and tools, and its AMPP partner logic 
// functions, and any output files from any of the foregoing 
// (including device programming or simulation files), and any 
// associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License 
// Subscription Agreement, the Intel Quartus Prime License Agreement,
// the Intel FPGA IP License Agreement, or other applicable license
// agreement, including, without limitation, that your use is for
// the sole purpose of programming logic devices manufactured by
// Intel and sold by Intel or its authorized distributors.  Please
// refer to the applicable agreement for further details.
module lpm_divide (
	quotient,
	remain,
	numer,
	denom,
	clock,
	clken,
`ifdef POST_FIT
	_unassoc_inputs_,
	_unassoc_outputs_,
`endif
	aclr
);

	parameter lpm_type = "lpm_divide";
	parameter lpm_widthn = 1;
	parameter lpm_widthd = 1;
	parameter lpm_nrepresentation = "UNSIGNED";
	parameter lpm_drepresentation = "UNSIGNED";
	parameter lpm_remainderpositive = "TRUE";
	parameter lpm_pipeline = 0;
	parameter lpm_hint = "UNUSED";
	parameter skip_bits = 0;
`ifdef POST_FIT
	parameter _unassoc_inputs_width_ = 1;
	parameter _unassoc_outputs_width_ = 1;
`endif

	input clock;
	input clken;
	input aclr;
	input [lpm_widthn-1:0] numer;
	input [lpm_widthd-1:0] denom;
	// Extra bus for connecting signals unassociated with defined ports
`ifdef POST_FIT
	input [ _unassoc_inputs_width_ - 1 : 0 ] _unassoc_inputs_;
	output [ _unassoc_outputs_width_ - 1 : 0 ] _unassoc_outputs_;
`endif
	output [lpm_widthn-1:0] quotient;
	output [lpm_widthd-1:0] remain;

endmodule
