#ifndef GPUCommandGen_h
#define GPUCommandGen_h

struct VertexCmdGen {
	int x;
	int y;
};

typedef unsigned char u8;
typedef unsigned int  u32;
typedef unsigned short u16;
typedef unsigned long long int u64;

struct Color {
	u8  r;
	u8  g;
	u8  b;

};

struct TextureCoord {
	u8  u;
	u8  v;
};

struct DrawModeSetup {
	enum Transparency {
		BLEND50      = 0,
		ADDITIVE     = 1,
		SUBSTRACTIVE = 2,
		ADD25        = 3,
	};
	
	enum TextureFormat {
		TEX4BIT		= 0,
		TEX8BIT		= 1,
		TEX16BIT	= 2,
		// Reserved.
	};
	
	DrawModeSetup() {
		textureXBase		= 0;
		textureYBase 		= 0;
		semiTranspMode 		= 0;
		textureFormat  		= TEX16BIT;
		performDither		= 0;
		drawToDisplayArea	= 0;
		textureDisable		= 0;
		texXFlip			= 0;
		texYFlip			= 0;
	}
	
	u8 textureXBase			: 4;
	u8 textureYBase 		: 1;
	u8 semiTranspMode 		: 2;
	u8 textureFormat  		: 2;
	u8 performDither		: 1;
	u8 drawToDisplayArea	: 1;
	u8 textureDisable		: 1;
	u8 texXFlip				: 1;
	u8 texYFlip				: 1;
};

struct Rect {
	Rect(int x0_, int y0_, int x1_, int y1_):x0(x0_),y0(y0_),x1(x1_),y1(y1_) {}
	int x0;
	int y0;
	int x1;
	int y1;
};

class GPUCommandGen {
public:
	GPUCommandGen(bool forceRamWrite);
	~GPUCommandGen();
	
	// (2)
	// MonoChrome    			Triangle/Quad(1)
	// Gouraud       			Triangle/Quad
	// Tex + Gouraud			Triangle/Quad
	// Tex Only					Triangle/Quad
	// MonoChrome + Tex			Triangle/Quad
	//   (3)
	// + Opaque / SemiTransp
	//
	// Rectangle
	// ---------------
	// Monochrome
	// Textured
	// Textured + Monochrome
	// + Opaque / SemiTransp
	
	// Line
	// ---------------
	// Monochrome
	// Shaded
	//
	// Opaque / SemiTransp
	// Polyline/SingleLine
	
	/*
		VRAM Stuff too
		ClearCache()
		InterruptRequest()
	 */
	void setDrawMode		(DrawModeSetup& setup);
	void setTextureWindow	(u8 maskX, u8 maskY, u8 offsetX, u8 offsetY);
	void setDrawArea		(Rect& rectangle);
	void setDrawOffset		(int x, int y);
	void setStencil			(bool forceWriteTo1, bool checkIfBit15Zero);
	
	void setWhiteColor		();
	void setSingleColor		(u8 r, u8 g, u8 b);
	void setSemiTransp		(bool semiTransparent = true);
	void setMultiColor		(Color* arrayColors);				// NULL = desactivate.
	void setMultiTexture	(TextureCoord* arrayTextureCoords, DrawModeSetup& setup, u8 clutX64, int clutY512);


	void createTriangle		();
	void createQuad			();
	void createRectangle	(VertexCmdGen& v, unsigned int width, unsigned int height);
	void createLine			(int count);
	
	void setVertices		(VertexCmdGen* arrayVertice);

	bool writeGP1			(u32 word);

	inline void setTime		(u64 val) { currStamp = val; }

	bool writeRaw			(u32 word, bool head, u8 gp1);
	bool writeRaw			(u32 word);
	void resetBuffer		() { readCounter = 0; writeCounter = 0; diff = 0; }

	bool stillHasCommand	();
	bool isCommandStart		();

	u8	 isGP1				();

	u32	 getRawCommand		();
	u64* getRawTiming		(u32& size) {
		size = writeCounter - readCounter;
		return &timeStamps[readCounter];
	}

	u32* getRawCommands		(u32& size) {
		size = writeCounter - readCounter;
		return &commands[readCounter];
	}
	u8* getGP1Args			() {
		return &commandGP1[readCounter];
	}

private:
	void genParams			(int cnt, bool NOTEX);
	static const int SIZE_ARRAY = 10000000;
	
	u64*			timeStamps;
	u32*			commands;	// 2 MB Enough, in case we transfer textures...
	bool*			commandsHead;
	u8*				commandGP1;
	u64				currStamp;
	u32				readCounter;
	u32				writeCounter;
	int				diff;
	Color  			colorsV		[1];

	bool			noColor; // true
	u32				baseColor;
	u32				singleColorFlag,colorFlag,semiFlag,textureFlag,clutFlag,pageFlag;
	Color*			srcColors;
	TextureCoord*	srcTexture;
	VertexCmdGen*	srcVertex;
};

GPUCommandGen* getCommandGen();

#endif // GPUCommandGen_h
