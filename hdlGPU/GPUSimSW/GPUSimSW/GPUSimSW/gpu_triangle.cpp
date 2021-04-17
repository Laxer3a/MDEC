#include "gpu_ref.h"
#include <stdio.h>
#include <assert.h>
#include <string.h>
#include <Windows.h>

int triangleCounter = 0;

int globalCycleCount = 0;

#define CHECK_AGAINSTREF		(1)
#define DEBUG_TRIANGLE			(0)

#if 0
void PrimitiveSetup::SetupFurtherDir(int dir) {
	h[0]    = (((f   < 0) & (dir>0)) | ((f    > 0) & (dir<0)));
	h[1]    = (((b   < 0) & (dir>0)) | ((b    > 0) & (dir<0)));
	h[2]    = (((d   > 0) & (dir>0)) | ((d    < 0) & (dir<0))); // -d => Condition IS INVERSED FOR .d !!!!
}
#endif

void PrimitiveSetup::SetupFurtherBool(int dir, int* w) {
	// DET never equal to zero.
	// DIR never equal to zero.
	// W >= 0 can be used.

	// Remain indecision toward f,b,d 
	further[0] = ((w[0] <  0) & (((f   < 0) && (dir >= 0)) || ((f   >=0) && (dir < 0))) & (DET <  0))
			   | ((w[0] >= 0) & (((f   >=0) && (dir >= 0)) || ((f   < 0) && (dir < 0))) & (DET >= 0));
	further[1] = ((w[1] <  0) & (((b   < 0) && (dir >= 0)) || ((b   >=0) && (dir < 0))) & (DET <  0))
			   | ((w[1] >= 0) & (((b   >=0) && (dir >= 0)) || ((b   < 0) && (dir < 0))) & (DET >= 0));
	// Reverse d conditions. (-d)
	further[2] = ((w[2] <  0) & (((d   >=0) && (dir >= 0)) || ((d   < 0) && (dir < 0))) & (DET <  0))
			   | ((w[2] >= 0) & (((d   < 0) && (dir >= 0)) || ((d   >=0) && (dir < 0))) & (DET >= 0));
/*	OLD BUGGY EQUATIONS
	further[0] = ((w[0] <  0) &   h[0]  & (DET < 0))
			   | ((w[0] >= 0) & (!h[0]) & (DET > 0));
	further[1] = ((w[1] <  0) &   h[1]  & (DET < 0))
			   | ((w[1] >= 0) & (!h[1]) & (DET > 0));
	further[2] = ((w[2] <  0) &   h[2]  & (DET < 0))
			   | ((w[2] >= 0) & (!h[2]) & (DET > 0));
*/
}

#include <math.h>

int GPURdrCtx::RenderTriangle(Vertex* pVertex, u8 id0, u8 id1, u8 id2) {
	// Brute force reference ignored for now.
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

/*
	this->drAreaX0_10	= 0;
	this->drAreaX1_10	= 80;
	this->drAreaY0_9	= 0;
	this->drAreaY1_9	= 40;
*/

	float a = 0;
	float b = 30*(3.14159f/180);

//	while (true) {
		/*
		ppVertex[0]->x = 40;
		ppVertex[0]->y = 0;

		ppVertex[1]->x = 0;
		ppVertex[1]->y = 40;

		ppVertex[2]->x = 80;
		ppVertex[2]->y = 38;
		*/
#if 0
		a += 0.001f;

		ppVertex[0]->x = 128 + cos(a) * 60;
		ppVertex[0]->y = 128 + sin(b) * 60;

		ppVertex[1]->x = 128 + cos(a+3.159-b)*60;
		ppVertex[1]->y = 128 + sin(a+3.159-b)*60;

		ppVertex[2]->x = 128 + cos(a+3.159+b)*60;
		ppVertex[2]->y = 128 + sin(a+3.159+b)*60;
#endif

		for (int n=0; n < 3; n++) {
			int x = ppVertex[n]->x;
			int y = ppVertex[n]->y;
			if (x>=0 && x<=1023 && y>=0 && y<=511) {
				this->swBuffer[x + (y * 1024)] = 0x0;
			}
		}

		if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
			// Skip primitive.
			return 0;
		}

	#if CHECK_AGAINSTREF
		static u16 TESTCOLOR = 0;
		TESTCOLOR &= 0x0FFF;
		TESTCOLOR++;
		if (TESTCOLOR == 0) {
			TESTCOLOR = 1;
		}
		TESTCOLOR |= 0xF000;
	#endif

		isLine = false;

		int pixelCounter = 0;
	#if 1
		Interpolator interp;
		bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
		int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
		int offsetY      = this->interlaced ? 2 : 1;
		Vertex p;
		PrimitiveSetup& s = primitiveSetup;

		for (p.y = s.minTriDAY0 + startOffset; p.y <= s.maxTriDAY1; p.y += offsetY) {
			for (p.x = s.minTriDAX0; p.x <= s.maxTriDAX1; p.x++) {
				bool insideTriangle = primitiveSetup.perPixelTriangle(p.x,p.y,ppVertex);

				if (insideTriangle) {
//					printf("Tri:%i,%i\n",p.x,p.y);
	//				this->swBuffer[p.x     + (p.y * 1024)] = TESTCOLOR;
					this->swBuffer[p.x     + (p.y * 1024)] = 0xFF00;
					pixelCounter++;
//				} else {
//					this->swBuffer[p.x     + (p.y * 1024)] = 0x0;
				}
	#if 0
				// If p is on or inside all edges, render pixel.
				if (primitiveSetup.perPixelTriangle(p.x,p.y,ppVertex)) {
	#if CHECK_AGAINSTREF
					this->swBuffer[p.x     + (p.y * 1024)] = TESTCOLOR;
	#else
	//				primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
	//				this->pixelPipeline(p.x,p.y,interp);
	#endif
					// RENDERING IS DONE BY NS function !!! Here is just reference pixel counter.
				}
	#endif
			}
		}
	#endif

		int PSFurther = RenderTriangleFurtherPair(pVertex, id0, id1, id2);
		if (pixelCounter != PSFurther) {
			static int failure = 0;
			printf("SCANMISMATCH 2 !!!! %i => %i,%i,%i,%i,%i,%i\n",triangleCounter,
				ppVertex[0]->x, ppVertex[0]->y,
				ppVertex[1]->x, ppVertex[1]->y,
				ppVertex[2]->x, ppVertex[2]->y
			); // while (true) {}

			failure++;
			if (failure > 100) {
				while (1) {
					Sleep(1000);
				}
			}
		}
		performRefresh(0,0);
//	}

//	int NSCount = RenderTriangleNS    (pVertex,id0,id1,id2,TESTCOLOR);
//	int NSCount = RenderTriangleNSPair(pVertex,id0,id1,id2,TESTCOLOR);
//	int NSCount = RenderTriangleGPU(pVertex,id0,id1,id2);
#if 1
	if ((triangleCounter++ & 0x7F) == 0) {
	}

//	return pixelCounter;
#endif
	return 0;
}

int GPURdrCtx::RenderTriangleFurther(Vertex* pVertex, u8 id0, u8 id1, u8 id2) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

//	triangleCounter++;
	if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
		// Skip primitive.
		return 0;
	}

	isLine = false;

	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TESTLEFT,
		TESTRIGHT,
		SEARCH_OUT,
		SNAKE,
		CLIP_CASE,
		EXIT,
	};

	enum XSel {
		BBOX_LEFT,
		BBOX_RIGHT,
		NEXT_PIXELX,
		AS_IS_X
	};

	enum YSel {
		BBOX_TOP,
		AS_IS_Y,
		NEXT_PIXELY,
	};

	ScanState	state		= TESTLEFT;
	ScanState   prevState	= TESTLEFT;
	XSel		selX		= BBOX_LEFT;
	YSel        selY		= BBOX_TOP;

	int		dir				= 1;
	bool	savedFurther	= false;

#if 0
	p.y = primitiveSetup.minTriDAY0 + startOffset;
	p.x = primitiveSetup.minTriDAX0;
	// Pair Work.
	//	p.x = (primitiveSetup.minTriDAX0>>1)<<1;

	while (p.y <= primitiveSetup.maxTriDAY1) {
		for (p.x = primitiveSetup.minTriDAX0; p.x <= primitiveSetup.maxTriDAX1; p.x++) {
			// Evaluate Line Equations
			int w0[3];
			primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);

			primitiveSetup.SetupFurtherBool(dir,w0);

			int zoneCode[2];
			zoneCode[0] = 0;
			if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
			if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
			if (w0[2] >= 0)					{ zoneCode[0] |= 4; }
			if (!primitiveSetup.DETPOS)		{
				zoneCode[0] = ~zoneCode[0] & 7; 
			}
			bool insideTriangle	= (zoneCode[0] == 0); // || (zoneCode[1] == 0);
			bool furtherF		= primitiveSetup.further[0] | primitiveSetup.further[1] | primitiveSetup.further[2];

			int offset = p.x + p.y * 1024;
			if ((p.x >=0 && p.x <= 1023) && (p.y >= 0) && (p.y <= 511)) {
				this->swBuffer[offset] = (furtherF ? 0x0FF0 : 0) | (insideTriangle ? 0x001F : 0);
			}
		}
		p.y++;
	}
	
	performRefresh(0,0);
	if (primitiveSetup.special) {
		printf("HYEAH");
	}
	return 0;
#endif

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	p.x = primitiveSetup.minTriDAX0;

	while (p.y <= primitiveSetup.maxTriDAY1) {
		int offset = p.x + p.y * 1024;

		// Evaluate Line Equations
		int w0[3];
		primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);

//		primitiveSetup.SetupFurtherDir();
		primitiveSetup.SetupFurtherBool(dir,w0); // DIR REG OUTPUT, NOT NEXT DIR !!! NO PB.

		// --- Zone Code ---
		int zoneCode[2];
		zoneCode[0] = 0;

		bool outSideLeft0  = p.x     < primitiveSetup.minTriDAX0;
		bool outSideRight0 = p.x     > primitiveSetup.maxTriDAX1;

		if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
		if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
		if (w0[2] >= 0)					{ zoneCode[0] |= 4; }

		if (!primitiveSetup.DETPOS)		{
			zoneCode[0] = ~zoneCode[0] & 7; 
		}

#if 0
		int w1[3];
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);
		zoneCode[1] = 0;
		bool outSideLeft1  = (p.x+1) < primitiveSetup.minTriDAX0;
		bool outSideRight1 = (p.x+1) > primitiveSetup.maxTriDAX1;
		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }
		if (!primitiveSetup.DETPOS)		{
			zoneCode[1] = ~zoneCode[1] & 7; 
		}
#endif

		if (p.x >= 0 && p.y >= 0 && p.x <= 1023 && p.y <= 511) {
			this->swBuffer[offset  ] = 0x0FF0;
		}

		// -----------------------------------------------------------------------------------------------
		bool insideTriangle	= (zoneCode[0] == 0); // || (zoneCode[1] == 0);

		// TODO : Add left/right clipping here.
		bool further		= primitiveSetup.further[0] | primitiveSetup.further[1] | primitiveSetup.further[2] | (outSideLeft0 | outSideRight0);

		bool storeFurther   = false;

//		printf("F:%i,%i\n",p.x,p.y);

		switch (state) {
		case TESTLEFT:
			storeFurther = true;
			if (insideTriangle) {
				state	= SNAKE;
				selX	= AS_IS_X;
				selY	= AS_IS_Y;
			} else {
				state	= TESTRIGHT;
				selX	= BBOX_RIGHT;
				selY	= AS_IS_Y;
			}
			break;
		case TESTRIGHT:
			if ((further == savedFurther) && (!insideTriangle)) {
				// Same side
				state	= TESTLEFT;
				selX	= BBOX_LEFT;
				selY	= NEXT_PIXELY;
			} else {
				state	= SNAKE;
				selX	= insideTriangle ? AS_IS_X : NEXT_PIXELX; // Save 1 cycle.
				selY	= AS_IS_Y;
				dir		= -dir;
			}
			break;
		case SNAKE:
			if ((insideTriangle || (!further)) && (!(outSideLeft0 | outSideRight0))) {
				if (insideTriangle) {
					this->swBuffer[offset  ] = 0x00FF;
					pixelCounter++;
//					printf("-->HIT\n");
				}
				selX	= NEXT_PIXELX;
				selY	= AS_IS_Y;
			} else {
				if (outSideLeft0 | outSideRight0) {
					// Continue scanning next line, switch of direction.
					dir     = -dir;
					selX	= NEXT_PIXELX;
					selY	= NEXT_PIXELY;
				} else {
					// Generic reach outside of triangle...
					// Further and outside of triangle.
					// => Do not change direction
					// Go next line
					selX	= AS_IS_X;
					selY	= NEXT_PIXELY;
					state	= SEARCH_OUT;
				}
			}
			break;
		case SEARCH_OUT:
			selX	= NEXT_PIXELX;
			selY	= AS_IS_Y;
			if ((insideTriangle || (!further)) && (!(outSideLeft0|outSideRight0))) {
				state	= SEARCH_OUT;
			} else {
				dir		= -dir;
				state	= SNAKE;
			}
			break;
		}

		if (storeFurther) {
			savedFurther = further;
		}

		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0);   break;
		case BBOX_RIGHT		: p.x =  (primitiveSetup.maxTriDAX1);   break;
		case NEXT_PIXELX	: p.x += dir; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}

		switch (selY) {
		case BBOX_TOP		: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case NEXT_PIXELY	: p.y += offsetY; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}

//		performRefresh(0,0);

	}

	return pixelCounter;
}

int GPURdrCtx::RenderTriangleFurtherPair(Vertex* pVertex, u8 id0, u8 id1, u8 id2) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

//	triangleCounter++;
	if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
		// Skip primitive.
		return 0;
	}

	isLine = false;

	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TESTLEFT,
		TESTRIGHT,
		SEARCH_OUT,
		SNAKE,
		CLIP_CASE,
		EXIT,
	};

	enum XSel {
		X_TRI_BBLEFT,
		X_TRI_BBRIGHT,
		X_TRI_NEXT,
		X_ASIS
	};

	enum YSel {
		Y_TRI_START,
		Y_ASIS,
		Y_TRI_NEXT,
	};

	ScanState	state		= TESTLEFT;
	ScanState   prevState	= TESTLEFT;
	XSel		selX		= X_TRI_BBLEFT;
	YSel        selY		= Y_TRI_START;

	int		dir				= 2;
	bool	savedFurther	= false;

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	// p.x = primitiveSetup.minTriDAX0;
	p.x = (primitiveSetup.minTriDAX0>>1)<<1; // Pair mode

	while (p.y <= primitiveSetup.maxTriDAY1) {
		int offset = p.x + p.y * 1024;

		// Evaluate Line Equations
		int w0[3];
		int w1[3];
		primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);

//		primitiveSetup.SetupFurtherDir();
		primitiveSetup.SetupFurtherBool(dir,w0);	// Only on the left pixel.

		// --- Zone Code ---
		int zoneCode[2];
		zoneCode[0] = 0;
		zoneCode[1] = 0;

		bool outSideLeft0  = p.x     < primitiveSetup.minTriDAX0;
		bool outSideRight0 = p.x     > primitiveSetup.maxTriDAX1;
		bool outSideLeft1  =(p.x+1)  < primitiveSetup.minTriDAX0;
		bool outSideRight1 =(p.x+1)  > primitiveSetup.maxTriDAX1;

		// No need in verilog
		if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
		if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
		if (w0[2] >= 0)					{ zoneCode[0] |= 4; }

		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }
		// ----

		if (!primitiveSetup.DETPOS)		{
			zoneCode[0] = ~zoneCode[0] & 7; 
			zoneCode[1] = ~zoneCode[1] & 7; 
		}

#if 0
		int w1[3];
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);
		zoneCode[1] = 0;
		bool outSideLeft1  = (p.x+1) < primitiveSetup.minTriDAX0;
		bool outSideRight1 = (p.x+1) > primitiveSetup.maxTriDAX1;
		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }
		if (!primitiveSetup.DETPOS)		{
			zoneCode[1] = ~zoneCode[1] & 7; 
		}
#endif

		if (p.x >= 0 && p.y >= 0 && p.x <= 1023 && p.y <= 511) {
			this->swBuffer[offset  ] = 0x0FF0;
			this->swBuffer[offset+1] = 0x0FF0;
		}

		// -----------------------------------------------------------------------------------------------
		bool insideTriangle	= (zoneCode[0] == 0) || (zoneCode[1] == 0);
		bool outSideLeft    =  outSideLeft0 &  outSideLeft1;
		bool outSideRight   = outSideRight0 & outSideRight1;

		// TODO : Add left/right clipping here.
		bool further		= primitiveSetup.further[0] | primitiveSetup.further[1] | primitiveSetup.further[2] | (outSideLeft | outSideRight);

		bool storeFurther   = false;


		switch (state) {
		case TESTLEFT:
			storeFurther = true;
			if (insideTriangle) {
				state	= SNAKE;
				selX	= X_ASIS;
				selY	= Y_ASIS;
			} else {
				state	= TESTRIGHT;
				selX	= X_TRI_BBRIGHT;
				selY	= Y_ASIS;
			}
			break;
		case TESTRIGHT:
			if ((further == savedFurther) && (!insideTriangle)) {
				// Same side
				state	= TESTLEFT;
				selX	= X_TRI_BBLEFT;
				selY	= Y_TRI_NEXT;
			} else {
				state	= SNAKE;
				selX	= insideTriangle ? X_ASIS : X_TRI_NEXT; // Save 1 cycle.
				selY	= Y_ASIS;
				dir		= -2;
			}
			break;
		case SNAKE:
			if ((insideTriangle || (!further)) && (!(outSideLeft | outSideRight))) {
				if (zoneCode[0] == 0 && (!(outSideLeft0 | outSideRight0))) {
					this->swBuffer[offset  ] = 0x00FF;
//					printf("F:%i,%i\n",p.x,p.y);
					pixelCounter++;
				}
				if (zoneCode[1] == 0 && (!(outSideLeft1 | outSideRight1))) {
					this->swBuffer[offset+1] = 0x00FF;
//					printf("F:%i,%i\n",p.x+1,p.y);
					pixelCounter++;
				}
				selX	= X_TRI_NEXT;
				selY	= Y_ASIS;
			} else {
				if (outSideLeft | outSideRight) {
					// Continue scanning next line, switch of direction.
					dir     = -dir;
					selX	= X_TRI_NEXT;
					selY	= Y_TRI_NEXT;
				} else {
					// Generic reach outside of triangle...
					// Further and outside of triangle.
					// => Do not change direction
					// Go next line
					selX	= X_ASIS;
					selY	= Y_TRI_NEXT;
					state	= SEARCH_OUT;
				}
			}
			break;
		case SEARCH_OUT:
			selX	= X_TRI_NEXT;
			selY	= Y_ASIS;
			if ((insideTriangle || (!further)) && (!(outSideLeft|outSideRight))) {
				state	= SEARCH_OUT;
			} else {
				dir		= -dir;
				state	= SNAKE;
			}
			break;
		}

		if (storeFurther) {
			savedFurther = further;
		}

		switch (selX) {
		case X_TRI_BBLEFT	: p.x =  ((primitiveSetup.minTriDAX0)>>1)<<1;   break;
		case X_TRI_BBRIGHT	: p.x =  ((primitiveSetup.maxTriDAX1)>>1)<<1;   break;
		case X_TRI_NEXT		: p.x += dir; break;
		case X_ASIS			: /* Do nothing*/ break;
		}

		switch (selY) {
		case Y_TRI_START	: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case Y_TRI_NEXT		: p.y += offsetY; break;
		case Y_ASIS			: /* Do nothing*/ break;
		}

//		performRefresh(0,0);

	}

	return pixelCounter;
}
// SINGLE PIXEL VERSION
int GPURdrCtx::RenderTriangleNS(Vertex* pVertex, u8 id0, u8 id1, u8 id2, int refColor) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

//	triangleCounter++;
	if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
		// Skip primitive.
		return 0;
	}

	isLine = false;

	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TESTLEFT,
		TESTRIGHT,
		SEARCH_OUT,
		SNAKE,
		CLIP_CASE,
		EXIT,
	};

	enum XSel {
		BBOX_LEFT,
		BBOX_RIGHT,
		NEXT_PIXELX,
		AS_IS_X
	};

	enum YSel {
		BBOX_TOP,
		AS_IS_Y,
		NEXT_PIXELY,
	};

	ScanState	state		= TESTLEFT;
	ScanState   prevState	= TESTLEFT;
	XSel		selX		= BBOX_LEFT;
	YSel        selY		= BBOX_TOP;

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	// Pair Work.
//	p.x = (primitiveSetup.minTriDAX0>>1)<<1;
	p.x = primitiveSetup.minTriDAX0;

	int		saveZoneCode	= 0;
	int		dir				= 1;
	bool	foundFirst	= false;
	bool	wasInside   = false;
	bool	wasVertical = false;

	bool    first       = true;
	bool	loop		= false;
	int		found		= 0;

	u16 fColor = 0x00FF;

	while (p.y <= primitiveSetup.maxTriDAY1) {
		bool renderDebug = false;

		// Evaluate Line Equations
		int w0[3];
		int w1[3];
		primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);

		// --- Zone Code ---
		int zoneCode[2];
		zoneCode[0] = 0;
		zoneCode[1] = 0;

		bool outSideLeft0  = p.x     < primitiveSetup.minTriDAX0;
		bool outSideRight0 = p.x     > primitiveSetup.maxTriDAX1;
//		bool outSideLeft1  = (p.x+1) < primitiveSetup.minTriDAX0;
//		bool outSideRight1 = (p.x+1) > primitiveSetup.maxTriDAX1;

		if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
		if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
		if (w0[2] >= 0)					{ zoneCode[0] |= 4; }

//		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
//		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
//		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }

		// Make sure we are always '111' as inside the triangle (reverse code)
		if (!primitiveSetup.DETPOS)		{
			zoneCode[0] = ~zoneCode[0] & 7; 
//			zoneCode[1] = ~zoneCode[1] & 7; 
		}

		// Add another new code :-)
//		if (outSideLeft0 ) { zoneCode[0] |= 8;  }
//		if (outSideRight0) { zoneCode[0] |= 16; }
	/*
		if (outSideLeft1 ) { zoneCode[1] |= 8;  }
		if (outSideRight1) { zoneCode[1] |= 16; }
	*/
		// -----------------------------------------------------------------------------------------------
		bool insideTriangle = (zoneCode[0] == 0); // || (zoneCode[1] == 0);

		// 		
		int  transition = ((~zoneCode[0]) & 7) | saveZoneCode;

//		bool inOut			= ((transitionCode!=0) && (prevZoneCode==0));
//		bool outIn			= ((transitionCode!=0) && (zoneCode    ==0));
		
		int differentSide = 0;
		int differentOut  = 0;
		// -----------------------------------------------------------------------------------------------

		bool saveCode = false;
		bool reverseCode = false;

		/*
		if (((zoneCode & 7) == 3) || ((zoneCode & 7) == 5) || ((zoneCode & 7) == 6)) {
			printf("FORBIDDEN CODE\n");
		}
		*/

		// Horizontal scan :
		// - Out->In
		//		Noice, change nothing, continue to scan...
		// -  In->Out
		//		Go down one line, switch to end search scan.
		// - Out->Out (no change zone)
		//		
		// -  In->In
		//		Noice, change nothing, continue to scan...
		// - Out->Out (Change zone)
		//		Go down one line, s

		int offset = p.x + p.y * 1024;
		if ((p.x >=0 && p.x <= 1023) && (p.y >= 0) && (p.y <= 511)) {
			this->swBuffer[offset] = 0x0FF0;
		}
		// PAIR STUFF : outsideLeft and outsideRight are BOTH PIXEL OUT LEFT or RIGHT => outSideLeft = outSideLeft0 & outSideLeft1, same for outsideRight.
		//				insideTriangle = insideTriangleLeft | insideTriangleRight
		//				zoneCode       = (dir > 0) ? zoneCode[1] : zoneCode[0]
		//					PB : dir with TESTLEFT right. Should be -1 at LEFT, +1 at RIGHT

		prevState = state;
#if DEBUG_TRIANGLE
		printf("NS:%i,%i Code:%i Dir:%i State: ",p.x,p.y,zoneCode[0],dir);
#endif
		switch (state) {
		// Scanout
		// Scanin
		case TESTLEFT:
#if DEBUG_TRIANGLE
			printf("TEST LEFT\n");
#endif
			if (insideTriangle && (!loop)) {
				state = SNAKE;
				selX  = AS_IS_X;	
				selY  = AS_IS_Y;
				loop  = true;		// loop = false set when selY != AS_IS_Y; !!!
			} else {
				saveCode = true;
				state = TESTRIGHT;
				selX  = BBOX_RIGHT;
				selY  = AS_IS_Y;				
				dir   = -1;
			}
			break;
		case TESTRIGHT:
#if DEBUG_TRIANGLE
			printf("TEST RIGHT\n");
#endif
			if (otherSide(zoneCode[0],saveZoneCode) && (!loop)) { // Enter a different region makes a bit goes to ZERO.
				// Scan back 
				state = SNAKE;
				saveCode = true;
				first   = false;
				selX  = AS_IS_X;
				selY  = AS_IS_Y;
				loop  = true;		// loop = false set when selY != AS_IS_Y; !!!
			} else {
				// Same side
				state= TESTLEFT;
				selY = NEXT_PIXELY;
				selX = BBOX_LEFT;
				dir  = 1;
				first = true;
			}
			break;
		case SNAKE:
#if DEBUG_TRIANGLE
			printf("SNAKE\n");
#endif
			saveCode = true;

			if (insideTriangle && (!(outSideLeft0 || outSideRight0))) {
//				printf("%i,%i\n",p.x,p.y);
//				if (this->swBuffer[offset] == refColor) {
				this->swBuffer[offset] = 0x00FF;
//				}
#if 0
				primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
				this->pixelPipeline(p.x,p.y,interp);
#endif
				pixelCounter++;
				found   = 1;
				selX	= NEXT_PIXELX;
				selY	= AS_IS_Y;
			} else {
				this->swBuffer[offset] = 0xFFF0;
				if (outSideLeft0 | outSideRight0) {
#if 0
					selX	= NEXT_PIXELX;
					selY	= NEXT_PIXELY;
					state   = CLIP_CASE;
					dir     = outSideRight0 ? -1 : 1;
#else
					if (found) {
						selX	= NEXT_PIXELX;
						selY	= NEXT_PIXELY;
						state   = CLIP_CASE;
						dir     = outSideRight0 ? -1 : 1;
					} else {
						selY	= AS_IS_Y;
						selX	= BBOX_LEFT;
						state   = TESTLEFT;
						first   = true;
						dir     = 1;
					}
#endif
				} else {
					if (first || otherSide(zoneCode[0],saveZoneCode)) {
						first   = false;
						state   = SEARCH_OUT;
						found   = 0;
						selX	= AS_IS_X;
						selY	= NEXT_PIXELY;
					} else {
						selX	= NEXT_PIXELX;
						selY	= AS_IS_Y;
					}
				}
			}
			break;
		case CLIP_CASE:
#if DEBUG_TRIANGLE
			printf("CLIP_CASE\n");
#endif
			if (!insideTriangle) {
				first    = false;
			}
			saveCode    = !insideTriangle;
			reverseCode = insideTriangle;
			state       = insideTriangle ? SNAKE : TESTLEFT;
			first		= !insideTriangle;
			dir         = insideTriangle ? dir : 1;
			selX	    = insideTriangle ? AS_IS_X : BBOX_LEFT;
			selY	    = AS_IS_Y;
			break;
		case SEARCH_OUT:
#if DEBUG_TRIANGLE
			printf("SEARCH_OUT\n");
#endif
			// - We scan until we exit the triangle on the left or right, turn around and render the whole line
			// - Need to handle the case where clipping is better the exit left or right too.
			//
			renderDebug = true;
			selY	= AS_IS_Y;
			if ((!insideTriangle) || (outSideLeft0 || outSideRight0)) { // Force to scan and render...
				state	= SNAKE;
				found   = 0;

				if (outSideLeft0) {
					selX	= BBOX_LEFT;
					dir		= 1;
				} else {
					if (outSideRight0) {
						selX	= BBOX_RIGHT;
						dir		= -1;
					} else {
						selX	= AS_IS_X;
						saveCode = otherSide(zoneCode[0],saveZoneCode);
#if 0
						if (found) {
							dir = -dir;
						} else {
							dir = otherSide(zoneCode[0],saveZoneCode) ? dir : -dir;
						}
#else
						// ORIGINAL VERSION 1:
						dir = otherSide(zoneCode[0],saveZoneCode) ? dir : -dir;
#endif
					}
				}
			} else {
				found   = 1;
				selX	= NEXT_PIXELX;
			}
			break;
		}

#if 0
		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0>>1)<<1;   break;
		case BBOX_RIGHT		: p.x = ((primitiveSetup.maxTriDAX1>>1)<<1)+1;break;
		case NEXT_PIXELX	: p.x += dir*2; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}
#else
		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0);   break;
		case BBOX_RIGHT		: p.x =  (primitiveSetup.maxTriDAX1);   break;
		case NEXT_PIXELX	: p.x += dir; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}
#endif

		switch (selY) {
		case BBOX_TOP		: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case NEXT_PIXELY	: p.y += offsetY; loop = false; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}


		// if (selY == NEXT_PIXELY) {
		// }

		// Copy
		if (saveCode) {
			saveZoneCode = zoneCode[0] & 0x7;
		}
		if (reverseCode) {
			saveZoneCode = ~saveZoneCode & 0x7;
		}
//		if (selY == NEXT_PIXELY) {

		static int cnt = 0;
		globalCycleCount++;
		if ((++cnt & 0x3F) == 0) {
			performRefresh(0,0);
		}
	}

outLoop:
#if DEBUG_TRIANGLE
	performRefresh(0,0);
#endif

	return pixelCounter;
}

int GPURdrCtx::RenderTriangleNSPair(Vertex* pVertex, u8 id0, u8 id1, u8 id2, int refColor) {
	Vertex* ppVertex[3];
	ppVertex[0] = &pVertex[id0];
	ppVertex[1] = &pVertex[id1];
	ppVertex[2] = &pVertex[id2];

//	triangleCounter++;
	if (!primitiveSetup.Setup(*this,ppVertex,false /*NOT A LINE*/)) {
		// Skip primitive.
		return 0;
	}

	isLine = false;

	Interpolator interp;
	bool isOddStart	 = primitiveSetup.minTriDAY0 & 1;
	int startOffset  = (this->interlaced && (isOddStart ^ this->currentInterlaceFrameOdd)) ? 1 : 0;
	int offsetY      = this->interlaced ? 2 : 1;
	int pixelCounter = 0;
	Vertex p;

	enum ScanState {
		TESTLEFT,
		TESTRIGHT,
		SEARCH_OUT,
		SNAKE,
		CLIP_CASE,
		EXIT,
	};

	enum XSel {
		BBOX_LEFT,
		BBOX_RIGHT,
		NEXT_PIXELX,
		AS_IS_X
	};

	enum YSel {
		BBOX_TOP,
		AS_IS_Y,
		NEXT_PIXELY,
	};

	ScanState	state		= TESTLEFT;
	ScanState   prevState	= TESTLEFT;
	XSel		selX		= BBOX_LEFT;
	YSel        selY		= BBOX_TOP;

	p.y = primitiveSetup.minTriDAY0 + startOffset;
	// Pair Work.
	p.x = (primitiveSetup.minTriDAX0>>1)<<1;
//	p.x = primitiveSetup.minTriDAX0;

	int		saveZoneCode	= 0;
	int		dir				= 2;
	bool	foundFirst	= false;
	bool	wasInside   = false;
	bool	wasVertical = false;

	bool    first       = true;
	bool	loop		= false;
	int		found		= 0;

	u16 fColor = 0x00FF;

	bool further[3];// = primitiveSetup.f;
	// b    pour X axis, nega pour Y axis, L1
	// negd pour X axis, c    pour Y axis, L2

	while (p.y <= primitiveSetup.maxTriDAY1) {
		bool renderDebug = false;

		// Evaluate Line Equations
		int w0[3];
		int w1[3];
		primitiveSetup.LineEqu(p.x  , p.y,ppVertex, w0);
		primitiveSetup.LineEqu(p.x+1, p.y,ppVertex, w1);

		// --- Zone Code ---
		int zoneCode[2];
		zoneCode[0] = 0;
		zoneCode[1] = 0;

		bool outSideLeft0  = p.x     < primitiveSetup.minTriDAX0;
		bool outSideRight0 = p.x     > primitiveSetup.maxTriDAX1;
		bool outSideLeft1  = (p.x+1) < primitiveSetup.minTriDAX0;
		bool outSideRight1 = (p.x+1) > primitiveSetup.maxTriDAX1;

		bool outSideLeft   = outSideLeft0  && outSideLeft1;
		bool outSideRight  = outSideRight0 && outSideRight1;

		if (w0[0] >= 0)					{ zoneCode[0] |= 1; } 
		if (w0[1] >= 0)					{ zoneCode[0] |= 2; }
		if (w0[2] >= 0)					{ zoneCode[0] |= 4; }

		if (w1[0] >= 0)					{ zoneCode[1] |= 1; } 
		if (w1[1] >= 0)					{ zoneCode[1] |= 2; }
		if (w1[2] >= 0)					{ zoneCode[1] |= 4; }

		further[0] = ((w0[0] <  0) & (primitiveSetup.f   < 0) & (primitiveSetup.DET < 0))
                   | ((w0[0] >= 0) & (primitiveSetup.f  >= 0) & (primitiveSetup.DET > 0));
		further[1] = ((w0[1] <  0) & (primitiveSetup.b   < 0) & (primitiveSetup.DET < 0))
                   | ((w0[1] >= 0) & (primitiveSetup.b  >= 0) & (primitiveSetup.DET > 0));
		// -d => Condition IS INVERSED FOR .d !!!!
		further[2] = ((w0[2] <  0) & (primitiveSetup.d >= 0 /*See Comment !*/) & (primitiveSetup.DET < 0))
                   | ((w0[2] >= 0) & (primitiveSetup.d  < 0 /*See Comment !*/) & (primitiveSetup.DET > 0));

		// Make sure we are always '111' as inside the triangle (reverse code)
		if (!primitiveSetup.DETPOS)		{
			zoneCode[0] = ~zoneCode[0] & 7; 
			zoneCode[1] = ~zoneCode[1] & 7; 
		}

		// -----------------------------------------------------------------------------------------------
		bool insideTriangle = (zoneCode[0] == 0) || (zoneCode[1] == 0);
		int  currCode       = zoneCode[0] | zoneCode[1];
		// -----------------------------------------------------------------------------------------------

		bool saveCode    = false;
		bool reverseCode = false;

		/*
		if (((zoneCode & 7) == 3) || ((zoneCode & 7) == 5) || ((zoneCode & 7) == 6)) {
			printf("FORBIDDEN CODE\n");
		}
		*/

		// Horizontal scan :
		// - Out->In
		//		Noice, change nothing, continue to scan...
		// -  In->Out
		//		Go down one line, switch to end search scan.
		// - Out->Out (no change zone)
		//		
		// -  In->In
		//		Noice, change nothing, continue to scan...
		// - Out->Out (Change zone)
		//		Go down one line, s

		if ((p.x >=0 && p.x <= 1023) && (p.y >= 0) && (p.y <= 511)) {
			this->swBuffer[p.x     + p.y * 1024] = 0x0FF0;
			this->swBuffer[(p.x+1) + p.y * 1024] = 0x0FF0;
		}
		// PAIR STUFF : outsideLeft and outsideRight are BOTH PIXEL OUT LEFT or RIGHT => outSideLeft = outSideLeft0 & outSideLeft1, same for outsideRight.
		//				insideTriangle = insideTriangleLeft | insideTriangleRight
		//				zoneCode       = (dir > 0) ? zoneCode[1] : zoneCode[0]
		//					PB : dir with TESTLEFT right. Should be -1 at LEFT, +1 at RIGHT

		prevState = state;
#if DEBUG_TRIANGLE
		printf("NS:%i,%i Code:%i Dir:%i State: ",p.x,p.y,currCode,dir);
#endif
		switch (state) {
		// Scanout
		// Scanin
		case TESTLEFT:
#if DEBUG_TRIANGLE
			printf("TEST LEFT\n");
#endif
			if (insideTriangle && (!loop)) {
				state = SNAKE;
				selX  = AS_IS_X;	
				selY  = AS_IS_Y;
				loop  = true;		// loop = false set when selY != AS_IS_Y; !!!
			} else {
				saveCode = true;
				state = TESTRIGHT;
				selX  = BBOX_RIGHT;
				selY  = AS_IS_Y;				
				dir   = -2;
			}
			break;
		case TESTRIGHT:
#if DEBUG_TRIANGLE
			printf("TEST RIGHT\n");
#endif
			if (insideTriangle || (otherSide(currCode,saveZoneCode) && (!loop))) { // Enter a different region makes a bit goes to ZERO.
				// Scan back 
				state = SNAKE;
				saveCode = true;
				first   = false;
				selX  = AS_IS_X;
				selY  = AS_IS_Y;
				loop  = true;		// loop = false set when selY != AS_IS_Y; !!!
			} else {
				// Same side
				state= TESTLEFT;
				selY = NEXT_PIXELY;
				selX = BBOX_LEFT;
				dir  = 2;
				first = true;
			}
			break;
		case SNAKE:
		{
#if DEBUG_TRIANGLE
			printf("SNAKE\n");
#endif
			saveCode = true;
			int offset = p.x + p.y * 1024;

			if (insideTriangle && (!(outSideLeft || outSideRight))) {
//				printf("%i,%i\n",p.x,p.y);
//				if (this->swBuffer[offset] == refColor) {
				if (zoneCode[0] == 0 && (!(outSideLeft0|outSideRight0))) {
					this->swBuffer[offset  ] = 0xF00F;
					pixelCounter++;
				}

				if (zoneCode[1] == 0 && (!(outSideLeft1|outSideRight1))) {
					this->swBuffer[offset+1] = 0xF00F;
					pixelCounter++;
				}
#if 0
				primitiveSetup.perPixelInterp(p.x,p.y,ppVertex,interp);
				this->pixelPipeline(p.x,p.y,interp);
#endif
				found   = 1;
				selX	= NEXT_PIXELX;
				selY	= AS_IS_Y;
			} else {
				this->swBuffer[offset  ] = 0xFFF0;
				this->swBuffer[offset+1] = 0xFFF0;
				if (outSideLeft | outSideRight) {
					if (found) {
						selX	= NEXT_PIXELX;
						selY	= NEXT_PIXELY;
						state   = CLIP_CASE;
						dir     = outSideRight ? -2 : 2;
					} else {
						selY	= AS_IS_Y;
						selX	= BBOX_LEFT;
						state   = TESTLEFT;
						first   = true;
						dir     = 2;
					}
				} else {
					if (first || otherSide(currCode,saveZoneCode)) {
						first   = false;
						state   = SEARCH_OUT;
						found   = 0;
						selX	= AS_IS_X;
						selY	= NEXT_PIXELY;
					} else {
						selX	= NEXT_PIXELX;
						selY	= AS_IS_Y;
					}
				}
			}
		}
			break;
		case CLIP_CASE:
#if DEBUG_TRIANGLE
			printf("CLIP_CASE\n");
#endif
			if (!insideTriangle) {
				first    = false;
			}
			saveCode    = !insideTriangle;
			reverseCode = insideTriangle;
			state       = insideTriangle ? SNAKE : TESTLEFT;
			first		= !insideTriangle;
			dir         = insideTriangle ? dir : 2;
			selX	    = insideTriangle ? AS_IS_X : BBOX_LEFT;
			selY	    = AS_IS_Y;
			break;
		case SEARCH_OUT:
#if DEBUG_TRIANGLE
			printf("SEARCH_OUT\n");
#endif
			// - We scan until we exit the triangle on the left or right, turn around and render the whole line
			// - Need to handle the case where clipping is better the exit left or right too.
			//
			renderDebug = true;
			selY	= AS_IS_Y;
			if ((!insideTriangle) || (outSideLeft || outSideRight)) { // Force to scan and render...
				state	= SNAKE;
				found   = 0;

				if (outSideLeft) {
					selX	= BBOX_LEFT;
					dir		= 2;
				} else {
					if (outSideRight) {
						selX	= BBOX_RIGHT;
						dir		= -2;
					} else {
						selX	= AS_IS_X;
						saveCode = otherSide(currCode,saveZoneCode);
						// ORIGINAL VERSION 1:
						dir     = otherSide(currCode,saveZoneCode) ? dir : -dir;
					}
				}
			} else {
				found   = 1;
				selX	= NEXT_PIXELX;
			}
			break;
		}

		switch (selX) {
		case BBOX_LEFT		: p.x =  (primitiveSetup.minTriDAX0>>1)<<1;   break;
		case BBOX_RIGHT		: p.x =  (primitiveSetup.maxTriDAX1>>1)<<1;   break;
		case NEXT_PIXELX	: p.x += dir; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}

		switch (selY) {
		case BBOX_TOP		: p.y = primitiveSetup.minTriDAY0 + startOffset; break;
		case NEXT_PIXELY	: p.y += offsetY; loop = false; break;
		case AS_IS_X		: /* Do nothing*/ break;
		}

		// Copy
		if (saveCode) {
			saveZoneCode = currCode & 0x7;
		}
		if (reverseCode) {
			saveZoneCode = ~saveZoneCode & 0x7;
		}
//		if (selY == NEXT_PIXELY) {

		static int cnt = 0;
		globalCycleCount++;
//		if ((++cnt & 0x01) == 0) {
			performRefresh(0,0);
//		}
	}

outLoop:
#if DEBUG_TRIANGLE
	performRefresh(0,0);
#endif

	return pixelCounter;
}

void printTotalTimeCycle() {
	printf("Total Cycle Triangle : %i\n",globalCycleCount);
}

/*
bool otherSide(int codeA, int codeB) {
	if ((codeA == 7) || (codeB == 7) || (codeA == 0)) {
		//printf("IMPOSSILBE"); // while (1) {};
		return true;
	}

	if (codeB == 0) {
		return true;
	}

	switch (codeA) {
	//
	// [EASY CASES]
	//
	case 1:
		switch (codeB) {
		case 1: return false;
		case 2: return true;
		case 3: return true;
		case 4: return true;
		case 5: return true;
		case 6: return true;
		}
		break;
	case 2:
		switch (codeB) {
		case 1: return true;
		case 2: return false;
		case 3: return true;
		case 4: return true;
		case 5: return true;
		case 6: return true;
		}
		break;
	case 4:
		switch (codeB) {
		case 1: return true;
		case 2: return true;
		case 3: return true;
		case 4: return false;
		case 5: return true;	// Enter Zone 1
		case 6: return true;	// Enter Zone 2
		}
		break;
	case 3:
		switch (codeB) {
		case 1: return true;
		case 2: return true;
		case 3: return false;
		case 4: return true;
		case 5: return true;
		case 6: return true;
		}
		break;
	case 5:
		switch (codeB) {
		case 1: return true;
		case 2: return true;
		case 3: return true;
		case 4: return true;
		case 5: return false;
		case 6: return true;
		}
		break;
	case 6:
		switch (codeB) {
		case 1: return true;
		case 2: return true;
		case 3: return true;
		case 4: return true;
		case 5: return true;
		case 6: return false;
		}
		break;
	}
}
*/

bool otherSide(int codeA, int codeB) {
	if ((codeA == 7) || (codeB == 7) || (codeA == 0)) {
		//printf("IMPOSSILBE"); // while (1) {};
		return true;
	}

	if (codeB == 0) {
		return true;
	}

	switch (codeA) {
	//
	// [EASY CASES]
	//
	case 1:
		switch (codeB) {
		case 1: return false;
		case 2: return true;
		case 3: return false;
		case 4: return true;
		case 5: return false;
		case 6: return true;
		}
		break;
	case 2:
		switch (codeB) {
		case 1: return true;
		case 2: return false;
		case 3: return false;
		case 4: return true;
		case 5: return true;
		case 6: return false;
		}
		break;
	case 4:
		switch (codeB) {
		case 1: return true;
		case 2: return true;
		case 3: return true;
		case 4: return false;
		case 5: return false;	// Enter Zone 1
		case 6: return false;	// Enter Zone 2
		}
		break;
	case 3:
		switch (codeB) {
		case 1: return false;
		case 2: return false;
		case 3: return false;
		case 4: return true;
		case 5: return true;
		case 6: return true;
		}
		break;
	case 5:
		switch (codeB) {
		case 1: return false;
		case 2: return true;
		case 3: return true;
		case 4: return false;
		case 5: return false;
		case 6: return true;
		}
		break;
	case 6:
		switch (codeB) {
		case 1: return true;
		case 2: return false;
		case 3: return true;
		case 4: return false;
		case 5: return true;
		case 6: return false;
		}
		break;
	}
}
