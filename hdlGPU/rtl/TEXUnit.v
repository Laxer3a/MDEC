module TEXUnit(
	// Register SETUP
	input [3:0] GPU_REG_TexBasePageX,
	input		GPU_REG_TexBasePageY,
	input		GPU_REG_TextureXFlip,
	input		GPU_REG_TextureYFlip,
	input [1:0]	GPU_REG_TexFormat,
	input [4:0]	GPU_REG_WindowTextureMaskX,
	input [4:0]	GPU_REG_WindowTextureMaskY,
	input [4:0]	GPU_REG_WindowTextureOffsetX,
	input [4:0]	GPU_REG_WindowTextureOffsetY,
	
	// Dynamic stuff...
	input [7:0]	coordU_L,
	input [7:0]	coordV_L,
	input [7:0]	coordU_R,
	input [7:0]	coordV_R,
	
	output [18:0]	texelAdress_L,	// HalfWord adress.
	output [18:0]	texelAdress_R	// HalfWord adress.
);

	/*
		0-4    Texture window Mask X   (in 8 pixel steps)
		5-9    Texture window Mask Y   (in 8 pixel steps)
		10-14  Texture window Offset X (in 8 pixel steps)
		15-19  Texture window Offset Y (in 8 pixel steps)
		Mask specifies the bits that are to be manipulated, and Offset contains the new values for these bits, ie. texture X/Y coordinates are adjusted as so:
		Texcoord = (Texcoord AND (NOT (Mask*8))) OR ((Offset AND Mask)*8)
		
		(From Avocado emulator implementation also)
		tex.x = (tex.x & ~(textureWindow.maskX * 8)) | ((textureWindow.offsetX & textureWindow.maskX) * 8);
		tex.y = (tex.y & ~(textureWindow.maskY * 8)) | ((textureWindow.offsetY & textureWindow.maskY) * 8);
	*/
	wire [7:0] flippedU1 = GPU_REG_TextureXFlip ? ~coordU_L : coordU_L;
	wire [7:0] flippedV1 = GPU_REG_TextureYFlip ? ~coordV_L : coordV_L;
	wire [7:0] flippedU2 = GPU_REG_TextureXFlip ? ~coordU_R : coordU_R;
	wire [7:0] flippedV2 = GPU_REG_TextureYFlip ? ~coordV_R : coordV_R;

	wire [7:0] extMaskX  = (~{GPU_REG_WindowTextureMaskX , 3'd0});
	wire [7:0] extMaskY  = (~{GPU_REG_WindowTextureMaskY , 3'd0});

	wire [7:0] extOffMaskX  = {(GPU_REG_WindowTextureOffsetX & GPU_REG_WindowTextureMaskX),3'd0};
	wire [7:0] extOffMaskY  = {(GPU_REG_WindowTextureOffsetY & GPU_REG_WindowTextureMaskY),3'd0};
	
	// Now we have final texture coordinates...
	// Convert into an adress...
	wire [7:0] texCoordU1 = (flippedU1 & extMaskX) | extOffMaskX;
	wire [7:0] texCoordV1 = (flippedV1 & extMaskY) | extOffMaskY;
	wire [7:0] texCoordU2 = (flippedU2 & extMaskX) | extOffMaskX;
	wire [7:0] texCoordV2 = (flippedV2 & extMaskY) | extOffMaskY;
	
/*	Texture address can be computed as is from :
    98765432109876543 210 
    bbbbbbbbbbaaaaaaa|aaa  !!! IN BYTE ADDRESS!!!
    Y        XXXX        <-- Texture Page Base X = 128 byte , Y = 512 KB Jump
+    VVVVVVVV    UUUU|UUU.U in 4  bit (last U is selector for 4 bit, sub byte)
+    VVVVVVVV   UUUUU|UUU   in 8  bit
+    VVVVVVVV  UUUUUU|UU0   in 16 bit 
*/

	// ------------------------------
	// But WARNING : in HALF-WORD !!!!
	// ------------------------------
	wire [9:0] baseT = { GPU_REG_TexBasePageX, 6'd0 };	// [XXXX______] X Position for base.
	
	reg [9:0] adrL,adrR;
	
	parameter PIX_4BIT   =2'd0, PIX_8BIT  =2'd1, PIX_16BIT =2'd2, PIX_RESERVED     =2'd3; // TODO Include instead.	
	always @(*) begin
		case (GPU_REG_TexFormat)							//  [XXXX______]
		PIX_4BIT: adrL = baseT + { 4'd0, texCoordU1[7:2] };	//+ [____UUUUUU]	 4 Bit
		PIX_8BIT: adrL = baseT + { 3'd0, texCoordU1[7:1] };	//+ [___UUUUUUU]	 8 Bit
		default:  adrL = baseT + { 2'd0, texCoordU1[7:0] };	//+ [__UUUUUUUU]	16 Bit
		endcase
	end

	always @(*) begin
		case (GPU_REG_TexFormat)
		PIX_4BIT: adrR = baseT + { 4'd0, texCoordU2[7:2] };
		PIX_8BIT: adrR = baseT + { 3'd0, texCoordU2[7:1] };
		default:  adrR = baseT + { 2'd0, texCoordU2[7:0] };
		endcase
	end

	//  1      8           10
	// [Y][VVVV.VVVV][XX.XXUU.UUUU]  = Pixel coordinate in halfword.
	//
	assign texelAdress_L = {{ GPU_REG_TexBasePageY, texCoordV1 } , adrL };
	assign texelAdress_R = {{ GPU_REG_TexBasePageY, texCoordV2 } , adrR };
endmodule
