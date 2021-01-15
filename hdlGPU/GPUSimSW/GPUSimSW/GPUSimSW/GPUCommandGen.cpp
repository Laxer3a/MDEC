#include "GPUCommandGen.h"

GPUCommandGen::GPUCommandGen():readCounter(0),writeCounter(0)
{
	commandsHead	= new bool[10000000];
	commandGP1      = new u8  [10000000];
	commands        = new u32 [10000000];
	diff			= 0;
	colorsV[0].r	= 0; colorsV[0].g = 0; colorsV[0].b = 0;
	noColor			= true;
	baseColor		= 0;
	singleColorFlag	= 0;
	colorFlag		= 0;
	semiFlag		= 0;
	textureFlag		= 0;
	srcColors		= 0;
	srcTexture		= 0;
	srcVertex		= 0;
	clutFlag		= 0;
	pageFlag		= 0;
}

bool GPUCommandGen::writeRaw			(u32 word, bool isCommand, u8 isGP1) {
	if (diff >= 0) {
		commandsHead[writeCounter  ] = isCommand;
		commandGP1  [writeCounter  ] = isGP1;
		commands    [writeCounter++] = word;
		diff++;
		if (writeCounter == SIZE_ARRAY) { writeCounter = 0; }
		return true;
	} else {
		// More read than write...
		return false;
	}
}

bool GPUCommandGen::writeRaw			(u32 word) {
	return writeRaw(word,false,0);
}

bool GPUCommandGen::writeGP1			(u32 word) {
	return writeRaw(word,true,1);
}

bool GPUCommandGen::stillHasCommand	() {
	return (diff > 0);
}

bool GPUCommandGen::isCommandStart() {
	return commandsHead[readCounter];
}

u32	 GPUCommandGen::getRawCommand() {
	if (diff > 0) {
		u32 res = commands[readCounter++];
		if (readCounter == SIZE_ARRAY) { readCounter = 0; }
		diff--;
		return res;
	} else {
		return 0xFFFFFFFF;
	}
}

u8	GPUCommandGen::isGP1() {
	if (diff > 0) {
		return commandGP1[readCounter];
	} else {
		return 0;
	}
}

void GPUCommandGen::setDrawMode		(DrawModeSetup& setup) {
	writeRaw(
		 (0xE1<<24)
		|((setup.textureXBase   & 0xF)<<0)
		|((setup.textureYBase   & 0x1)<<4)
		|((setup.semiTranspMode & 0x3)<<5)
		|((setup.textureFormat  & 0x3)<<7)
		|((setup.performDither  & 0x1)<<9)
		|((setup.drawToDisplayArea & 0x1)<<10)
		|((setup.textureDisable  & 0x1)<<11)
		|((setup.texXFlip  & 0x1)<<12)
		|((setup.texYFlip  & 0x1)<<13)
	);
}

void GPUCommandGen::setTextureWindow	(u8 maskX, u8 maskY, u8 offsetX, u8 offsetY) {
	writeRaw(
		 (0xE2<<24)
		|((maskX   & 0x1F)<<0)
		|((maskY   & 0x1F)<<5)
		|((offsetX & 0x1F)<<10)
		|((offsetY & 0x1F)<<15)
	);
}

void GPUCommandGen::setDrawArea		(Rect& rectangle) {
	writeRaw(
		 (0xE3<<24)
		|((rectangle.x0 & 0x3FF)<<0)
		|((rectangle.y0 & 0x1FF)<<10)
	);
	writeRaw(
		 (0xE4<<24)
		|((rectangle.x1 & 0x3FF)<<0)
		|((rectangle.y1 & 0x1FF)<<10)
	);
}

void GPUCommandGen::setDrawOffset	(int x, int y) {
	writeRaw(
		 (0xE5<<24)
		|((x & 0x7FF)<<0)
		|((y & 0x3FF)<<11)
	);
}

void GPUCommandGen::setStencil		(bool forceWriteTo1, bool checkIfBit15Zero) {
	writeRaw(
		 (0xE6<<24)
		|(forceWriteTo1    ? 1 : 0)
		|(checkIfBit15Zero ? 2 : 0)
	);
}

void GPUCommandGen::setWhiteColor	() {
	noColor			= true;
	singleColorFlag = 0;
}


void GPUCommandGen::setSingleColor	(u8 r, u8 g, u8 b) {
	noColor = false;
	colorsV[0].r = r;
	colorsV[0].g = g;
	colorsV[0].b = b;
	baseColor = (colorsV[0].r<<0) | (colorsV[0].g<<8) | (colorsV[0].b<<16);
	singleColorFlag = 1<<24;
}

void GPUCommandGen::setMultiColor	(Color* arrayColors) {
	noColor		= false;
	srcColors	= arrayColors;
	if (arrayColors) {
		baseColor = (arrayColors[0].r<<0) | (arrayColors[0].g<<8) | (arrayColors[0].b<<16);
	} else {
		baseColor = (colorsV[0].r<<0) | (colorsV[0].g<<8) | (colorsV[0].b<<16);
	}
	colorFlag	= arrayColors ? (1<<28): 0;	// Gouraud, Flat
}

void GPUCommandGen::setSemiTransp	(bool semiTransparent) {
	semiFlag = semiTransparent ? (1<<25): 0;
}

void GPUCommandGen::setMultiTexture	(TextureCoord* arrayTextureCoords, DrawModeSetup& setup, u8 clutX64, int clutY512) {
	textureFlag = arrayTextureCoords ? 1<<26 : 0;
	srcTexture  = arrayTextureCoords;

	pageFlag	=	 ((setup.textureXBase   & 0xF)<<16)
					|((setup.textureYBase   & 0x1)<<20)
					|((setup.semiTranspMode & 0x3)<<21)
					|((setup.textureFormat  & 0x3)<<23)
					//	 ((setup.performDither  & 0x1)<<9)
					//  |((setup.drawToDisplayArea & 0x1)<<10)
					|((setup.textureDisable  & 0x1)<<27)
					//	|((setup.texXFlip  & 0x1)<<12)
					//	|((setup.texYFlip  & 0x1)<<13)
					;

	clutFlag	= ((clutY512 & 0x1FF) << (6+16)) | ((clutX64 & 0x3F) << 16);
}

void GPUCommandGen::setVertices		(Vertex* arrayVertice) {
	srcVertex = arrayVertice;
}

void GPUCommandGen::genParams(int cnt, bool NOTEX) {
	for (int n=0; n < cnt; n++) {
		if (colorFlag & (n!=0)) {
			writeRaw(srcColors[n].r | (srcColors[n].g<<8)| (srcColors[n].b<<16));
		}
		
		// vertex
		writeRaw((srcVertex[n].x & 0x7FF) | ((srcVertex[n].y & 0x7FF)<<16) );
		
		if (textureFlag & (NOTEX==false)) {
			switch (cnt) {
			case 0: // CLUT + X/Y
				writeRaw(srcTexture[n].u | (srcTexture[n].v<<8) | clutFlag);
				break;
			case 1: // Page + X/Y
				writeRaw(srcTexture[n].u | (srcTexture[n].v<<8) | pageFlag);
				break;
			default: // XY
				writeRaw(srcTexture[n].u | (srcTexture[n].v<<8));
				break;
			}
		}
	}
}

void GPUCommandGen::createTriangle	() {
	writeRaw(
		singleColorFlag | colorFlag | semiFlag | textureFlag | (1<<29) /*Polygon*/ |
		baseColor
	);
	genParams(3, false);
}

void GPUCommandGen::createQuad		() {
	writeRaw(
		singleColorFlag | colorFlag | semiFlag | textureFlag | (1<<27)/*Quad*/ | (1<<29) /*Polygon*/ |
		baseColor
	);
	genParams(4, false);
}

void GPUCommandGen::createRectangle	(Vertex& v, unsigned int width, unsigned int height) {
	int  size = 0;
	if (width == 1 && height == 1)		{ size = 1; }
	if (width == 8 && height == 8) 		{ size = 2; }
	if (width == 16 && height == 16)	{ size = 3; }

	writeRaw(
		/*singleColorFlag |*/ colorFlag | semiFlag | textureFlag | (size<<27) | (3<<29) /*Rectangle*/ | baseColor
	);
	
	writeRaw((v.x & 0x7FF) | ((v.y & 0x7FF)<<16) );

	if (textureFlag) {
		writeRaw(srcTexture[0].u | (srcTexture[0].v<<8) | clutFlag);
	}

	if (size == 0) {
		writeRaw((width & 0x3FF) | ((height & 0x1FF)<<16));
	}
}

void GPUCommandGen::createLine		(int count) {
	bool isPoly = count > 2;
	writeRaw(
		colorFlag | semiFlag | (isPoly ? (1<<27) : 0)/*Line/Polyline*/ | (2<<29) /*Line*/ | baseColor
	);
	genParams(count, true);
	if (isPoly) {
		writeRaw(0x55555555);
	}
}
