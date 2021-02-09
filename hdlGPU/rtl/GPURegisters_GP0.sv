/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

module GPURegisters_GP0 (
	input					i_clk,
	
	input					rstGPU,

	//-------------------------------
	//  From Parser
	//-------------------------------
	input					loadE5Offsets,
	input					loadTexPageE1,
	input					loadTexPage,
	input					loadTexWindowSetting,
	input					loadDrawAreaTL,
	input					loadDrawAreaBR,
	input					loadMaskSetting,
	input		[31:0]		fifoDataOut,
	
	//-------------------------------
	//  GP0 Registers
	//-------------------------------
	output signed [10:0] 	o_GPU_REG_OFFSETX,
	output signed [10:0] 	o_GPU_REG_OFFSETY,
	output         [3:0] 	o_GPU_REG_TexBasePageX,
	output               	o_GPU_REG_TexBasePageY,
	output         [1:0] 	o_GPU_REG_Transparency,
	output         [1:0] 	o_GPU_REG_TexFormat,
	output               	o_GPU_REG_DitherOn,
	output               	o_GPU_REG_DrawDisplayAreaOn,
	output               	o_GPU_REG_TextureDisable,
	output               	o_GPU_REG_TextureXFlip,
	output               	o_GPU_REG_TextureYFlip,
	output         [4:0] 	o_GPU_REG_WindowTextureMaskX,
	output         [4:0] 	o_GPU_REG_WindowTextureMaskY,
	output         [4:0] 	o_GPU_REG_WindowTextureOffsetX,
	output         [4:0] 	o_GPU_REG_WindowTextureOffsetY,
	output         [9:0] 	o_GPU_REG_DrawAreaX0,
	output         [9:0] 	o_GPU_REG_DrawAreaY0,
	output         [9:0] 	o_GPU_REG_DrawAreaX1,
	output         [9:0] 	o_GPU_REG_DrawAreaY1,
	output               	o_GPU_REG_ForcePixel15MaskSet,
	output               	o_GPU_REG_CheckMaskBit
);

// ----------------------------- Command Based Register ---------------
reg signed [10:0] 	GPU_REG_OFFSETX;
reg signed [10:0] 	GPU_REG_OFFSETY;
reg         [3:0] 	GPU_REG_TexBasePageX;
reg               	GPU_REG_TexBasePageY;
reg         [1:0] 	GPU_REG_Transparency;
reg         [1:0] 	GPU_REG_TexFormat;
reg               	GPU_REG_DitherOn;
reg               	GPU_REG_DrawDisplayAreaOn;
reg               	GPU_REG_TextureDisable;
reg               	GPU_REG_TextureXFlip;
reg               	GPU_REG_TextureYFlip;
reg         [4:0] 	GPU_REG_WindowTextureMaskX;
reg         [4:0] 	GPU_REG_WindowTextureMaskY;
reg         [4:0] 	GPU_REG_WindowTextureOffsetX;
reg         [4:0] 	GPU_REG_WindowTextureOffsetY;
reg         [9:0] 	GPU_REG_DrawAreaX0;
reg         [9:0] 	GPU_REG_DrawAreaY0;				// 8:0 on old GPU.
reg         [9:0] 	GPU_REG_DrawAreaX1;
reg         [9:0] 	GPU_REG_DrawAreaY1;				// 8:0 on old GPU.
reg               	GPU_REG_ForcePixel15MaskSet;		// Stencil force to 1.
reg               	GPU_REG_CheckMaskBit; 			// Stencil Read/Compare Enabled

always @(posedge i_clk)
begin
	// -------------------------------------------
	// Command through FIFO
	// -------------------------------------------
    if (rstGPU) begin
        GPU_REG_OFFSETX				<= 11'd0;
        GPU_REG_OFFSETY				<= 11'd0;
        GPU_REG_TexBasePageX		<= 4'd0;
        GPU_REG_TexBasePageY		<= 1'b0;
        GPU_REG_Transparency		<= 2'd0;
        GPU_REG_TexFormat			<= 2'd0; //
        GPU_REG_DitherOn			<= 1'd0; //
        GPU_REG_DrawDisplayAreaOn	<= 1'b0; // Default by GP1(00h) definition.
        GPU_REG_TextureDisable		<= 1'b0;
        GPU_REG_TextureXFlip		<= 1'b0;
        GPU_REG_TextureYFlip		<= 1'b0;
        GPU_REG_WindowTextureMaskX	<= 5'd0;
        GPU_REG_WindowTextureMaskY	<= 5'd0;
        GPU_REG_WindowTextureOffsetX<= 5'd0;
        GPU_REG_WindowTextureOffsetY<= 5'd0;
        GPU_REG_DrawAreaX0			<= 10'd0;
        GPU_REG_DrawAreaY0			<= 10'd0; // 8:0 on old GPU.
        GPU_REG_DrawAreaX1			<= 10'd1023;	//
        GPU_REG_DrawAreaY1			<= 10'd511;		//
        GPU_REG_ForcePixel15MaskSet <= 0;
        GPU_REG_CheckMaskBit		<= 0;
    end else begin
        if (/*issue.*/loadE5Offsets) begin
            GPU_REG_OFFSETX <= fifoDataOut[10: 0];
            GPU_REG_OFFSETY <= fifoDataOut[21:11];
        end
        if (/*issue.*/loadTexPageE1 || /*issue.*/loadTexPage) begin
            GPU_REG_TexBasePageX 	<= /*issue.*/loadTexPage ? fifoDataOut[19:16] : fifoDataOut[3:0];
            GPU_REG_TexBasePageY 	<= /*issue.*/loadTexPage ? fifoDataOut[20]    : fifoDataOut[4];
            GPU_REG_Transparency 	<= /*issue.*/loadTexPage ? fifoDataOut[22:21] : fifoDataOut[6:5];
            GPU_REG_TexFormat    	<= /*issue.*/loadTexPage ? fifoDataOut[24:23] : fifoDataOut[8:7];
            GPU_REG_TextureDisable	<= /*issue.*/loadTexPage ? fifoDataOut[27]    : fifoDataOut[11];
        end
        if (/*issue.*/loadTexPageE1) begin // Texture Attribute only changed by E1 Command.
            GPU_REG_DitherOn     <= fifoDataOut[9];
            GPU_REG_DrawDisplayAreaOn <= fifoDataOut[10];
            GPU_REG_TextureXFlip <= fifoDataOut[12];
            GPU_REG_TextureYFlip <= fifoDataOut[13];
        end
        if (/*issue.*/loadTexWindowSetting) begin
            GPU_REG_WindowTextureMaskX   <= fifoDataOut[4:0];
            GPU_REG_WindowTextureMaskY   <= fifoDataOut[9:5];
            GPU_REG_WindowTextureOffsetX <= fifoDataOut[14:10];
            GPU_REG_WindowTextureOffsetY <= fifoDataOut[19:15];
        end

        if (/*issue.*/loadDrawAreaTL) begin
            GPU_REG_DrawAreaX0 <= fifoDataOut[ 9: 0];
            GPU_REG_DrawAreaY0 <= { 1'b0, fifoDataOut[18:10] }; // 19:10 on NEW GPU.
        end
        if (/*issue.*/loadDrawAreaBR) begin
            GPU_REG_DrawAreaX1 <= fifoDataOut[ 9: 0];
            GPU_REG_DrawAreaY1 <= { 1'b0, fifoDataOut[18:10] }; // 19:0 on NEW GPU.
        end
        if (/*issue.*/loadMaskSetting) begin
            GPU_REG_ForcePixel15MaskSet <= fifoDataOut[0];
            GPU_REG_CheckMaskBit		<= fifoDataOut[1];
        end
	end
end

assign o_GPU_REG_OFFSETX					= GPU_REG_OFFSETX;
assign o_GPU_REG_OFFSETY					= GPU_REG_OFFSETY;
assign o_GPU_REG_TexBasePageX				= GPU_REG_TexBasePageX;
assign o_GPU_REG_TexBasePageY				= GPU_REG_TexBasePageY;
assign o_GPU_REG_Transparency				= GPU_REG_Transparency;
assign o_GPU_REG_TexFormat					= GPU_REG_TexFormat;
assign o_GPU_REG_DitherOn					= GPU_REG_DitherOn;
assign o_GPU_REG_DrawDisplayAreaOn			= GPU_REG_DrawDisplayAreaOn;
assign o_GPU_REG_TextureDisable				= GPU_REG_TextureDisable;
assign o_GPU_REG_TextureXFlip				= GPU_REG_TextureXFlip;
assign o_GPU_REG_TextureYFlip				= GPU_REG_TextureYFlip;
assign o_GPU_REG_WindowTextureMaskX			= GPU_REG_WindowTextureMaskX;
assign o_GPU_REG_WindowTextureMaskY			= GPU_REG_WindowTextureMaskY;
assign o_GPU_REG_WindowTextureOffsetX		= GPU_REG_WindowTextureOffsetX;
assign o_GPU_REG_WindowTextureOffsetY		= GPU_REG_WindowTextureOffsetY;
assign o_GPU_REG_DrawAreaX0					= GPU_REG_DrawAreaX0;
assign o_GPU_REG_DrawAreaY0					= GPU_REG_DrawAreaY0;			
assign o_GPU_REG_DrawAreaX1					= GPU_REG_DrawAreaX1;
assign o_GPU_REG_DrawAreaY1					= GPU_REG_DrawAreaY1;			
assign o_GPU_REG_ForcePixel15MaskSet		= GPU_REG_ForcePixel15MaskSet;
assign o_GPU_REG_CheckMaskBit				= GPU_REG_CheckMaskBit; 		

endmodule
