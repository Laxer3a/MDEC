/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module gpu_commandDecoder(
	input	[7:0]	i_command,
	
	output			o_bIsBase0x,
	output			o_bIsBase01,
	output			o_bIsBase02,
	output			o_bIsBase1F,
	output			o_bIsPolyCommand,
	output			o_bIsRectCommand,
	output			o_bIsLineCommand,
	output			o_bIsMultiLine,
	output			o_bIsForECommand,
	output			o_bIsCopyVVCommand,
	output			o_bIsCopyCVCommand,
	output			o_bIsCopyVCCommand,
	output			o_bIsCopyCommand,
	output			o_bIsFillCommand,
	output			o_bIsRenderAttrib,
	output			o_bIsNop,
	output			o_bIsPolyOrRect,
	output			o_bUseTextureParser,
	output			o_bSemiTransp,
	output			o_bOpaque,
	output			o_bIs4PointPoly,
	output			o_bIsPerVtxCol,
	output			o_bIgnoreColor
);
	// [Command Type]
	assign o_bIsBase0x				= (i_command[7:5]==3'b000);
	assign o_bIsBase01				= (i_command[4:0]==5'd1  );
	assign o_bIsBase02				= (i_command[4:0]==5'd2  );
	assign o_bIsBase1F				= (i_command[4:0]==5'd31 );

	assign o_bIsPolyCommand			= (i_command[7:5]==3'b001);
	assign o_bIsRectCommand			= (i_command[7:5]==3'b011);
	assign o_bIsLineCommand			= (i_command[7:5]==3'b010);
	assign o_bIsMultiLine   		= i_command[3] & o_bIsLineCommand;
	assign o_bIsForECommand			= (i_command[7:5]==3'b111);
	assign o_bIsCopyVVCommand		= (i_command[7:5]==3'b100);
	assign o_bIsCopyCVCommand		= (i_command[7:5]==3'b101);
	assign o_bIsCopyVCCommand		= (i_command[7:5]==3'b110);
	assign o_bIsCopyCommand			= o_bIsCopyVVCommand | o_bIsCopyCVCommand | o_bIsCopyVCCommand;
	assign o_bIsFillCommand			= o_bIsBase0x & o_bIsBase02;


	// [All attribute of i_commands]
	assign o_bIsRenderAttrib		= (o_bIsForECommand & (!i_command[4]) & (!i_command[3])) & (i_command[2:0]!=3'b000) & (i_command[2:0]!=3'b111); // E*, range 0..7 -> Select E1..E6 Only
	assign o_bIsNop         		= (o_bIsBase0x      & (!(o_bIsBase01 | o_bIsBase02 | o_bIsBase1F)))	// Reject 01,02,1F
									| (o_bIsForECommand & (!o_bIsRenderAttrib));				// Reject E1~E6
	assign o_bIsPolyOrRect  		= (o_bIsPolyCommand | o_bIsRectCommand);

	// Line are not textured
	assign o_bUseTextureParser      = o_bIsPolyOrRect & i_command[2];
	assign o_bSemiTransp    		= i_command[1];
	assign o_bOpaque        		= !o_bSemiTransp;
	assign o_bIs4PointPoly  		= i_command[3] & o_bIsPolyCommand;
	assign o_bIsPerVtxCol   		= (o_bIsPolyCommand | o_bIsLineCommand) & i_command[4];
	
	// 
	assign o_bIgnoreColor			= o_bUseTextureParser & i_command[0];

endmodule
