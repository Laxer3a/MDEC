// testChipSelect.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <stdio.h>
#include <string.h>

/*		TODO LIST :
		- MVMVA Microcode
		- MVMVA Buggy Microcode
		- HW : NClip special path to add.
		- NClip new addition support.

		- HW : Special path for DPCT/DPCS (Go from 18 to 15 cycles and fit budget)

		- Special path support in tool.
		- Flags support.

		- Proper 16 bit write back selection.

		- HW : Support temporary expression evaluation flags.
		- Tool support for temporary expression flags.
*/

struct SELUNIT {
public:
	static const int NA = 0;
	SELUNIT():availableRegCountL(0) {}

	void Register		(int instructionID) {
		this->instructionID = instructionID;
		setInstruction(NULL,"ZERO"); // Result by default.
	}

	void setInstruction	(const char* nameLeft, const char* nameRight) {
		setup[instructionID].left  = FindLeft (nameLeft,false);
		setup[instructionID].right = FindRight(nameRight,false);
		// printf("L:%i, R:%i @%i (%s,%s)\n",setup[instructionID].left,setup[instructionID].right,instructionID, availableRegL[setup[instructionID].left].name,availableRegR[setup[instructionID].right].name);
	}

	// Program the unit.
	void assignLeft		(const char* name, int indexSel, const char* portName) {
		int idx = FindLeft(name,true);
		if (idx == -1) {
			availableRegL[availableRegCountL].name    = name;
			availableRegL[availableRegCountL].selLeft = indexSel;
			availableRegL[availableRegCountL].matSel  = NA;
			availableRegL[availableRegCountL].portName= portName; 
			availableRegCountL++;
			if (availableRegCountL >= 64) {
				printf("ERROR\n");
			}
		} else {
			printf("ERROR\n");
		}
	}

	void assignLeftMat	(const char* name, int itemSel, int matID, const char* portName) {
		int idx = FindLeft(name,true);
		if (idx == -1) {
			availableRegL[availableRegCountL].name    = name;
			availableRegL[availableRegCountL].portName= portName; 
			availableRegL[availableRegCountL].selLeft = itemSel;
			availableRegL[availableRegCountL].matSel  = matID;
			availableRegCountL++;
			if (availableRegCountL >= 64) {
				printf("ERROR\n");
			}
		} else {
			printf("ERROR\n");
		}
	}

	void assignRightVec	(const char* name, int vecSel,int indexSel, const char* portName) {
		int idx = FindRight(name,true);
		if (idx == -1) {
			availableRegR[availableRegCountR].name    = name;
			availableRegR[availableRegCountR].selRight= indexSel;
			availableRegR[availableRegCountR].vecSel  = vecSel;
			availableRegR[availableRegCountR].portName= portName;
			if (portName) {
				lastExportR = availableRegCountR;
			}
			availableRegCountR++;
			if (availableRegCountR >= 64) {
				printf("ERROR\n");
			}
		} else {
			printf("ERROR\n");
		}
	}

	void assignRight    (const char* name, int indexSel, const char* portName, bool isSpecialInternal = false) {
		int idx = FindRight(name,true);
		if (idx == -1) {
			availableRegR[availableRegCountR].name    = name;
			availableRegR[availableRegCountR].selRight= indexSel;
			availableRegR[availableRegCountR].vecSel  = NA;
			availableRegR[availableRegCountR].portName= portName;
			availableRegR[availableRegCountR].isSpecialLocal = isSpecialInternal;
			if (portName) {
				lastExportR = availableRegCountR;
			}
			availableRegCountR++;
			if (availableRegCountR >= 64) {
				printf("ERROR\n");
			}
		} else {
			printf("ERROR\n");
		}
	}

	bool isLastExport(int rightIndex) { return rightIndex == lastExportR; } // To remove last comma in verilog export.
private:

	int FindLeft(const char* name, bool noError) {
		if (name) {
			for (int n=0; n < availableRegCountL; n++) {
				if (strcmp(name,availableRegL[n].name)==0) {
					return n;
				}
			}

			if (!noError) {
				printf("ERROR FindLeft\n");
			}
		} // NULL name return N/A -> -1
		return noError ? -1 : 0;
	}

	int FindRight(const char* name, bool noError) {
		for (int n=0; n < availableRegCountR; n++) {
			if (strcmp(name,availableRegR[n].name)==0) {
				return n;
			}
		}

		if (!noError) {
			printf("ERROR FindRight\n");
		}
		return noError ? -1 : 0;
	}

public:
	struct fullLeftEntry {
		const char* name;
		int  selLeft;
		bool useMat1() { return selLeft == 0x0; }
		bool useMat2() { return selLeft == 0x1; }
		bool useMat3() { return selLeft == 0x2; }
		bool useCol () { return selLeft == 0x4; } 
		int matSel;
		const char* portName;
	};

	struct fullRightEntry {
		const char* name;
		int  selRight;
		bool isVec() { return selRight == 0x0; }
		bool isCol() { return selRight == 0x7; }
		int  vecSel;
		bool isSpecialLocal;
		const char* portName;
	};

	struct instructionEntry {
		int left;
		int right;
	};

	fullLeftEntry availableRegL[64];
	int availableRegCountL;
	fullRightEntry availableRegR[64];
	int availableRegCountR;

	instructionEntry setup[1500];
	int instructionID;

	int lastExportR;
};

struct MASKUNIT {
	struct MaskingSetup {
		// MAC 1..3
		bool s44CheckGlobal;
		bool s44CheckLocal;
		bool colorCheck;
		bool IRCheck;
		bool isIRCheckUseLM;
		bool lmFalseForIR3Saturation;

		// MAC 0
		bool s32Check;
		bool otzCheck;
		bool s11Check;
		bool u4096Check;
		bool checkDivOverflow;

		// Will Drive all : COLOR, IRx, MACx
		int  id;
		int  X0_or_Y1; // Push X/Y 1 bit.
	};

	MASKUNIT():instructionCount(0),currInstr(0) {}

	void Reset(int nextInstructionID) {
		currInstr = nextInstructionID;
		MaskingSetup& rSet = instructions[currInstr];
		rSet.s44CheckGlobal = false;
		rSet.s44CheckLocal  = false;
		rSet.colorCheck = false;
		rSet.IRCheck    = false;
		rSet.isIRCheckUseLM = false;
		rSet.lmFalseForIR3Saturation = false;

		rSet.s32Check       = false;
		rSet.otzCheck       = false;
		rSet.s11Check       = false; // XY
		rSet.u4096Check     = false; // IR0
		rSet.checkDivOverflow = false;

		// N/A but prefer avoid noise in Microcode.
		rSet.id       = 0;
		rSet.X0_or_Y1 = 0;
	}

	MaskingSetup* Set() {
		return &instructions[currInstr];
	}

	void EndInstruction() {
		// Do nothing.
	}
	MaskingSetup instructions[1500];
private:
	int currInstr;
	int instructionCount;
};

struct SELADD {
	SELADD():entryCount(0) {}

	void generateMainDataPath();

	void Register		(int instructionID) {
		this->instructionID = instructionID;
		setup[instructionID] = Find("ZERO",true);
	}

	void setSpecial_ZOZSF4Mul() {
		setup[instructionID] = Find("Z0xZSF4",true);
	}

	void setZero() {
		setup[instructionID] = Find("ZERO",true);
	}

	void set(const char* name) {
		setup[instructionID] = Find(name,true);
	}

	int Find(const char* name, bool checkErr) {
		for (int n=0; n < entryCount; n++) {
			if (strcmp(entries[n].name,name)==0) {
				return n;
			}
		}

		if (checkErr) {
			printf("ERROR\n");
		}
		return -1;
	}

	void Register(const char* name, int ID, int subID, bool useSFShift) {
		if (Find(name,false)==-1) {
			entries[entryCount].name = name;
			entries[entryCount].id   = ID;
			entries[entryCount].subID= subID;
			entries[entryCount].useSFShift= useSFShift;
			entryCount++;
		} else {
			printf("ERROR\n");
		}
	}

	struct Entry {
		const char* name;
		int         id;
		int			subID;
		bool		useSFShift;
	};

	int entryCount;
	Entry entries[50];

	int instructionID;
	int setup[1500];
};

struct WRITEBACK {
	void reset(int nextInstructionID) {
		instructionID = nextInstructionID;
		setup[instructionID].Reset();
	}

	// Can cumulate multiple write back in same cycle.
	void write(const char* dst, int index1to3) { // Mac0, Mac1..3, IR1..3, etc...
		Entry& rE = setup[instructionID];

		// FIRST, BEFORE 'IR' !!!!
		if (strncmp(dst,"IR2TMP",6)==0) { rE.copyIRtoTemp = true; return; }

		if (strncmp(dst,"TMP",3)==0) { rE.wrTMP[index1to3] = true; return; }
		if (strncmp(dst,"IR",2)==0) {
			rE.wrIR[index1to3] = true; return; 
		}
		if (strncmp(dst,"MAC",3)==0) {
			if (index1to3 >= 1) {
				rE.useSFWrite32 = true;
			} // else false for MAC0
			rE.wrMAC[index1to3] = true; return;
		}
		if (strncmp(dst,"COL",2)==0) {
			switch (index1to3) {
			case 1: rE.pushR = true; break;
			case 2: rE.pushG = true; break;
			case 3: rE.pushB = true; break;
			default: printf("ERROR\n"); break;
			}
			return;
		}
		if (strncmp(dst,"PUSH",4)==0) {
			switch (index1to3) {
			case 1: rE.pushX = true; break;
			case 2: rE.pushY = true; break;
			case 3: rE.pushZ = true; break;
			default: printf("ERROR\n"); break;
			}
			return;
		}
		if (strncmp(dst,"OTZ",3)==0) { rE.wrOTZ = true; return; }
		if (strcmp(dst,"DIVRES")==0) { rE.wrDIVRES= true; return; }
		if (strcmp(dst,"STORERES")==0) { rE.storeFull = true; return; }

		printf("ERROR WRITE NOT FOUND %s\n",dst);
	}

	void useStoreRes() {
		Entry& rE = setup[instructionID];
		rE.useStoreFull = true;
	}

	void EndInstruction() {
		// Do nothing, write done in write() calls directly.
	}

	struct Entry {
		void Reset() {
			for (int n=0; n < 3; n++) {
				wrTMP[n] = false;
			}

			for (int n=0; n < 4; n++) {
				wrIR [n] = false;
				wrMAC[n] = false;
			}
		
			wrOTZ = false;
			pushR = false; pushG = false; pushB = false;
			pushX = false; pushY = false; pushZ = false;
			useSFWrite32 = false;
			copyIRtoTemp = false;
			wrDIVRES = false;
			storeFull = false;
			useStoreFull = false;
		}

		bool wrIR[4];   // TODO : I guess I could switch to SINGLE BIT (write) + ID stored in MASK
		bool wrMAC[4];  // TODO : Same here (save 6 bit total here)
		bool wrOTZ;
	
		bool pushR; // TODO : I guess could remove the checkFlags colorCheck by or-ing those (remove 1 bit width from LUT)
		bool pushG;
		bool pushB;

		bool pushX; // TODO : same here I guess.
		bool pushY;
		bool pushZ;

		bool wrTMP[3];
		bool useSFWrite32;
		bool wrDIVRES;

		bool copyIRtoTemp;

		bool storeFull;
		bool useStoreFull;
	};

	int instructionID;
	Entry setup[1500];
};

struct GLOBALPATHCTRL {
	void reset(int nextInstructionID) {
		instructionID = nextInstructionID;
		useNegSel1[instructionID] = false;
		useNegSel2[instructionID] = false;
		useNegSel3[instructionID] = false;
		selCol0   [instructionID] = false;
		lastInstructionFAST[instructionID] = false;
		lastInstructionSLOW[instructionID] = false;
		selOpInstr[instructionID] = 0;
	}

	void negSelOutput(int index) {
		if (index == 1) { useNegSel1[instructionID] = true; return; }
		if (index == 2) { useNegSel2[instructionID] = true; return; }
		if (index == 3) { useNegSel3[instructionID] = true; return; }
	}

	void useCol0() {
		selCol0[instructionID] = true; 
	}

	void setOPInstrCycle(int n1to3) {
		selOpInstr[instructionID] = n1to3;
	}

	void setLastInstructionFast() {
		lastInstructionFAST[instructionID] = true;
	}

	void setLastInstructionSlow() {
		lastInstructionSLOW[instructionID] = true;
	}

	int instructionID;
	bool useNegSel1[1500];
	bool useNegSel2[1500];
	bool useNegSel3[1500];
	bool selCol0   [1500];
	bool lastInstructionFAST[1500];
	bool lastInstructionSLOW[1500];
	int  selOpInstr[1500];
};

// All Hardware Unit.
SELUNIT   sel[3];
SELADD    selAdd;
MASKUNIT  mask;
WRITEBACK writeBack;
GLOBALPATHCTRL globalPath;

void registerInstructions();
void generateMicroCode(const char* fileName);
void generatorStartTableMicroCode(const char* fileName);

void HWDesignSetup() {
	// ===========================================
	// Sel0 : Mat 0
	sel[0].assignLeftMat("R11",0,0,"MAT0_C0");
	sel[0].assignLeftMat("R21",1,0,"MAT1_C0");
	sel[0].assignLeftMat("R31",2,0,"MAT2_C0");
	// Sel1 : Mat 1
	sel[0].assignLeftMat("L11",0,1,"MAT0_C1");
	sel[0].assignLeftMat("L21",1,1,"MAT1_C1");
	sel[0].assignLeftMat("L31",2,1,"MAT2_C1");
	// Sel2 : Mat 0
	sel[0].assignLeftMat("LR1",0,2,"MAT0_C2");
	sel[0].assignLeftMat("LG1",1,2,"MAT1_C2");
	sel[0].assignLeftMat("LB1",2,2,"MAT2_C2");
	// Sel3 : Color
	sel[0].assignLeft   ("CRGB.r",3,"color"  );
	// Sel4 : IRn
	sel[0].assignLeft   ("IR1"  ,4,"IRn"    );
	// Sel5 : SZ
	sel[0].assignLeft   ("SZ1"  ,5,"SZ"     );
	// Sel6 : DQA
	sel[0].assignLeft	 ("DQA"  ,6, "DQA"); // ONLY IN SEL1.
	// Sel8 : SX0
	sel[0].assignLeft   ("SX0"  ,8,"SX"     );
	// -------------------------------------------
	// Sel0 : Vec
	sel[0].assignRightVec("VX0",0,0,"V0c");
	sel[0].assignRightVec("VX1",1,0,"V1c");
	sel[0].assignRightVec("VX2",2,0,"V2c");
	sel[0].assignRightVec("HS3Z",3,0,"HS3Z");

	sel[0].assignRightVec("DYNVEC0" ,0,0,NULL);
	sel[0].assignRightVec("DYNVEC1" ,1,0,NULL);

	sel[0].assignRight   ("TMP1" ,1,"tmpReg",true/*SPECIAL INTERNAL COMPUTE PATH REG*/);
	// [1..4,6] Common to all.
	sel[0].assignRight   ("IR1"  ,5, NULL); // Already port reused.
	sel[0].assignRight	 ("CRGB.r",7,NULL);
	sel[0].assignRight	 ("SY1", 8,NULL);
	sel[0].assignRight	 ("SY2", 9,NULL);
	// ===========================================

	// ===========================================
	// Sel0 : Mat 0
	sel[1].assignLeftMat("R12",0,0,"MAT0_C0");
	sel[1].assignLeftMat("R22",1,0,"MAT1_C0");
	sel[1].assignLeftMat("R32",2,0,"MAT2_C0");
	// Sel1 : Mat 1
	sel[1].assignLeftMat("L12",0,1,"MAT0_C1");
	sel[1].assignLeftMat("L22",1,1,"MAT1_C1");
	sel[1].assignLeftMat("L32",2,1,"MAT2_C1");
	// Sel2 : Mat 0
	sel[1].assignLeftMat("LR2",0,2,"MAT0_C2");
	sel[1].assignLeftMat("LG2",1,2,"MAT1_C2");
	sel[1].assignLeftMat("LB2",2,2,"MAT2_C2");
	// Sel3 : Color
	sel[1].assignLeft   ("CRGB.g",    3,"color"  );
	// Sel4 : IRn
	sel[1].assignLeft   ("IR2",  4,"IRn"    );
	// Sel5 : SZ
	sel[1].assignLeft   ("SZ2",  5,"SZ"     );
	// Sel8 : SX1
	sel[1].assignLeft   ("SX1"  ,8,"SX"     );
	// -------------------------------------------
	// Sel0 : Vec
	sel[1].assignRightVec("VY0",0,0,"V0c");
	sel[1].assignRightVec("VY1",1,0,"V1c");
	sel[1].assignRightVec("VY2",2,0,"V2c");
	sel[1].assignRightVec("HS3Z",3,0,"HS3Z");
	// [1..4,6] Common to all.
	sel[1].assignRightVec("DYNVEC0" ,0,0,NULL);
	sel[1].assignRightVec("DYNVEC1" ,1,0,NULL);
	sel[1].assignRight   ("TMP2" ,1,"tmpReg",true/*SPECIAL INTERNAL COMPUTE PATH REG*/);

	sel[1].assignRight   ("IR2"  ,5, NULL); // Already port reused.

	sel[1].assignRight	 ("CRGB.g",7,NULL);
	sel[1].assignRight	 ("SY2", 8,NULL);
	sel[1].assignRight	 ("SY0", 9,NULL);
	// ===========================================

	// ===========================================
	// Sel0 : Mat 0
	sel[2].assignLeftMat("R13",0,0,"MAT0_C0");
	sel[2].assignLeftMat("R23",1,0,"MAT1_C0");
	sel[2].assignLeftMat("R33",2,0,"MAT2_C0");
	// Sel1 : Mat 1
	sel[2].assignLeftMat("L13",0,1,"MAT0_C1");
	sel[2].assignLeftMat("L23",1,1,"MAT1_C1");
	sel[2].assignLeftMat("L33",2,1,"MAT2_C1");
	// Sel2 : Mat 0
	sel[2].assignLeftMat("LR3",0,2,"MAT0_C2");
	sel[2].assignLeftMat("LG3",1,2,"MAT1_C2");
	sel[2].assignLeftMat("LB3",2,2,"MAT2_C2");
	// Sel3 : Color
	sel[2].assignLeft   ("CRGB.b", 3,"color"  );
	// Sel4 : IRn
	sel[2].assignLeft   ("IR3",  4,"IRn"    );
	// Sel5 : SZ
	sel[2].assignLeft   ("SZ3",  5,"SZ"     );
	// Sel8 : SX2
	sel[2].assignLeft   ("SX2"  ,8,"SX"     );
	// -------------------------------------------
	// Sel0 : Vec
	sel[2].assignRightVec("VZ0",0,0,"V0c");
	sel[2].assignRightVec("VZ1",1,0,"V1c");
	sel[2].assignRightVec("VZ2",2,0,"V2c");

	sel[2].assignRightVec("DYNVEC0" ,0,0,NULL);
	sel[2].assignRightVec("DYNVEC1" ,1,0,NULL);

	sel[2].assignRight   ("TMP3" ,1,"tmpReg",true/*SPECIAL INTERNAL COMPUTE PATH REG*/);
	// [1..4,6] Common to all.
	sel[2].assignRight   ("IR3"  ,5, NULL); // Already port reused.
	sel[2].assignRight	 ("CRGB.b",7,NULL);
	sel[2].assignRight	 ("SY0", 8,NULL);
	sel[2].assignRight	 ("SY1", 9,NULL);
	// ===========================================

	// Sel[1] / Sel[2] Have ZERO for index 6. Dont register anything for now.

	// For ALL UNIT THE SAME.
	for (int n=0; n < 3; n++) {
		// Sel7 : 4096
		sel[n].assignLeft("4096", 7, NULL);

		// Right setup
		sel[n].assignRight   ("ZSF3"   ,2,"Z3");
		sel[n].assignRight   ("ZSF4"   ,3,"Z4");
		sel[n].assignRight   ("ZERO" ,4,NULL);
		sel[n].assignRight   ("IR0"  ,6,"IR0");
	}

	// MACn,IRn lm=0
	static const int NO_LM  = 0;
	static const int USE_LM = 3;
	static const int USE_LMCLIP = 1; // IR3 value clipping is using LM bit, but : 1/ flag compute ignore [mac[3] and SF], but choose raw input>>12. 2/ Act as LM=0.
	static const int NA     = -1;

	// ===========================================

	selAdd.Register("TRX", 0, 0, false);
	selAdd.Register("TRY", 0, 1, false);
	selAdd.Register("TRZ", 0, 2, false);
	selAdd.Register("???", 0, 3, false);

	selAdd.Register("RBK", 1, 0, false);
	selAdd.Register("GBK", 1, 1, false);
	selAdd.Register("BBK", 1, 2, false);
	selAdd.Register("???", 1, 3, false);

	selAdd.Register("RFC", 2, 0, false);
	selAdd.Register("GFC", 2, 1, false);
	selAdd.Register("BFC", 2, 2, false);
	selAdd.Register("???", 2, 3, false);

	// Valid for MVMA MUX
	selAdd.Register("ZERO", 3, 0, false);
	selAdd.Register("???", 3, 1, false);
	selAdd.Register("???", 3, 2, false);
	selAdd.Register("???", 3, 3, false);

	selAdd.Register("CRGB.r", 4, 0, false); // (R<<4)   <<12 (false)
	selAdd.Register("CRGB.g", 4, 1, false); // (R<<4)   <<12 (false)
	selAdd.Register("CRGB.b", 4, 2, false); // (R<<4)   <<12 (false)

	selAdd.Register("MAC1", 5, 0, true); // Use SF (GPL)
	selAdd.Register("MAC2", 5, 1, true);
	selAdd.Register("MAC3", 5, 2, true);

	// Do I Remap to "???" sections ? 
	selAdd.Register("Z0xZSF4", 6, 0, false); // NO SHIFT << 12 !!!

	// SHADOW REGISTER OF IRx
	selAdd.Register("TMP1", 7, 0, false); //    <<12 (false)
	selAdd.Register("TMP2", 7, 1, false); //    <<12 (false)
	selAdd.Register("TMP3", 7, 2, false); //    <<12 (false)
	// ===========================================

	// OFX/OFY/DQB
	selAdd.Register("OFX", 8, 0, false); //    <<0 (false)
	selAdd.Register("OFY", 8, 1, false); //    <<0 (false)
	selAdd.Register("DQB", 8, 2, false); //    <<0 (false)

	// R/G/B x IRx SHADOW
	selAdd.Register("R_mul_ShadowIR1", 9, 0, false); //    <<0 (false)
	selAdd.Register("G_mul_ShadowIR2", 9, 1, false); //    <<0 (false)
	selAdd.Register("B_mul_ShadowIR3", 9, 2, false); //    <<0 (false)

	/*
	mask.Record("MACIR1", 0, (1<<24) | (1<<30) | (1<<27), NO_LM); // TODO : Proper values for mask setup. MAC:44 bit signed overflow, IR: <0.. >=+2^15
	mask.Record("MACIR2", 1, (1<<23) | (1<<29) | (1<<26), NO_LM);
	mask.Record("MACIR3", 2, (1<<22) | (1<<28) | (1<<25), NO_LM);
	// MACn,IRn use lm
	mask.Record("MACIR1_LM", 0, (1<<24) | (1<<30) | (1<<27), USE_LM); // TODO : Proper values for mask setup. MAC:44 bit signed overflow, IR: <-2^15..>=+2^15
	mask.Record("MACIR2_LM", 1, (1<<23) | (1<<29) | (1<<26), USE_LM);
	mask.Record("MACIR3_LM", 2, (1<<22) | (1<<28) | (1<<25), USE_LM);
	mask.Record("MACIR3_LMC", 2, (1<<22) | (1<<28) | (1<<25), USE_LMCLIP); // MAC3 work as intended, IR3 value clipping is using LM bit, but : 1/ flag compute ignore [mac[3] and SF], but choose raw input>>12. 2/ Act as LM=0.

	//
	mask.Record("R"       , 7,(1<<21),NA); // TODO : Proper value, < 0 ... >= 2^8 bit range
	mask.Record("G"       , 8,(1<<20),NA);
	mask.Record("B"       , 9,(1<<19),NA);

	mask.Record("OTZ_SAT" ,10, 1<<18, NA); // SZ3_OTZ_SATURATED = setOtz (avz3/avz4) or pushScreenZ (rtps/rtpt)

	mask.Record("DIVIDE_OVF", 11, 1<<17, NA);

	// TODO : multiplyMatrixByVector setup mask for EACH MULTIPLIER IN THE SUM... #define O(i, value)

	mask.Record("MAC0"    ,12,(1<<16) | (1<<15), NA); // Bit16,TODO : proper value, <-2^31 >=2^31
	mask.Record("SX_OVF"  ,13,1<<14, NA); // D1  < -2^10 >= 2^10
	mask.Record("SY_OVF"  ,14,1<<13, NA); // D2  < -2^10 >= 2^10
	mask.Record("IR0_SAT" ,15,1<<12, NA); // E, rtpt (last index), <0 >=2^12 
	*/

}

int instructionID = 0;
bool bEndInstruction = true;

struct INSTRTbl {
	const char* name;
	int StartPC;
	int instrCode;
	int officialCount;
	int realCount;
};

INSTRTbl Opcode[64];
bool initOpcode = false;
int  lastOpcode;

void Start(const char* name, int opcode, int PSXClockCycle, int ownClockCycleEstimate) {
	if (!initOpcode) {
		initOpcode = true;
		for (int n=0; n < 63; n++) {
			Opcode[n].name    = NULL;
			Opcode[n].StartPC = 0;
			Opcode[n].instrCode = -1;
		}
	}
	lastOpcode = opcode;
	Opcode[opcode].name = name;
	Opcode[opcode].StartPC = instructionID;
	Opcode[opcode].instrCode = opcode;
	Opcode[opcode].officialCount = PSXClockCycle;
	Opcode[opcode].realCount = ownClockCycleEstimate;
}

void registerNext();

void endInstruction(bool final = true) {
	if (bEndInstruction) {
		bEndInstruction = false;

		mask.EndInstruction();
		writeBack.EndInstruction();
	}
	if (final) {
		static int counterOfOp = 1;

		int start = Opcode[lastOpcode].StartPC;
		int end   = instructionID; // POINT TO NEXT INSTRUCTION SLOT. So mark END excluded.
		int length = (end - start);
		int lengthOfficial = Opcode[lastOpcode].officialCount;
		printf("[%i] Opcode %i %s EXEC TIME : %i (Official : %i)\n",counterOfOp , lastOpcode, Opcode[lastOpcode].name, length, lengthOfficial);
		counterOfOp++;

		globalPath.setLastInstructionFast();	// POINT TO LAST MICROCODE !!!!

		if (length < lengthOfficial) {
			for (int n=length; n < lengthOfficial; n++) {
				registerNext(); // Warning recursive call...
			}
			globalPath.setLastInstructionSlow();	// POINT TO LAST MICROCODE !!!!
		} else {
			globalPath.setLastInstructionSlow();	// POINT TO LAST MICROCODE !!!!
		}
	}
}

void registerNext() {
	endInstruction(false);
	// Reset flag of end instruction.
	bEndInstruction = true;

	sel[0].Register(instructionID);
	sel[1].Register(instructionID);
	sel[2].Register(instructionID);
	selAdd.Register(instructionID);

	globalPath.reset(instructionID);

	mask.Reset(instructionID);
	writeBack.reset(instructionID);

	instructionID++;
}

void format(char* dst, const char* format, int i) {
	sprintf(dst,format,i);
}

void formatS(char* dst, const char* format, const char* param) {
	sprintf(dst,format,param);
}
void multiplyMatrixByVector_LightByVertexPart(int i, int v) {

	// FIRST, SETUP HW.
	registerNext();

	char Lx1[10];    format(Lx1,"L%i1",i);
	char Lx2[10];    format(Lx2,"L%i2",i);
	char Lx3[10];    format(Lx3,"L%i3",i);

	// ---- Step 0
	char VXn [10];   format(VXn, "VX%i", v);
	char VYn [10];   format(VYn, "VY%i", v);
	char VZn [10];   format(VZn, "VZ%i", v);

	sel[0].setInstruction(Lx1,VXn);
	sel[1].setInstruction(Lx2,VYn);
	sel[2].setInstruction(Lx3,VZn);
	selAdd.setZero();

	MASKUNIT::MaskingSetup* msk = mask.Set();
		msk->id = i;
		msk->IRCheck = true;
		msk->s44CheckGlobal = true; // MAC1..3
		msk->s44CheckLocal  = true; // O( macro
		msk->isIRCheckUseLM = true;

	writeBack.write("MAC", i);
	writeBack.write("IR",i);
	writeBack.write("TMP",i);
}

/*
void multiplyMatrixByVector_LightByVertexPart(int i, int v) {

	// FIRST, SETUP HW.
	registerNext();

	char Lx1[10];    format(Lx1,"L%i1",i);
	char Lx2[10];    format(Lx2,"L%i2",i);
	char Lx3[10];    format(Lx3,"L%i3",i);

	// ---- Step 0
	char VXn [10];   format(VXn, "VX%i", v);
	char VYn [10];   format(VYn, "VY%i", v);
	char VZn [10];   format(VZn, "VZ%i", v);

	sel[0].setInstruction(Lx1,VXn);
	sel[1].setInstruction(Lx2,VYn);
	sel[2].setInstruction(Lx3,VZn);
	selAdd.setZero();

	MASKUNIT::MaskingSetup& msk = mask.Set();
		msk.id = i;
		msk.IRCheck = true;
		msk.s32CheckGlobal = true; // MAC1..3
		msk.s32CheckLocal  = true; // O( macro
		msk.isIRCheckUseLM = true;

	writeBack.write("MAC", i);
	writeBack.write("IR",i);
	writeBack.write("TMP",i);
}
*/

void multiplyMatrixByVector_ColorByIRPart(int v, bool pushColor) {

	// FIRST, SETUP HW.
	registerNext();

	// Feed back issue when RIGHT SIDE IS [IR VECTOR], force always.
	if (v == 1) {
		writeBack.write("IR2TMP",0);	// 1 CYCLE TO COPY IR TO SHADOW REG
	}

	// ---- Step 0
	const char* maskCol;
	const char* cte;
	switch (v) {
	case 1: maskCol="R"; cte = "RBK"; break;
	case 2: maskCol="G"; cte = "GBK"; break;
	case 3: maskCol="B"; cte = "BBK"; break;
	default: maskCol=NULL; cte = NULL; printf("ERROR"); break;
	}

	char Lx1 [10];   formatS(Lx1, "L%s1", maskCol);
	char Lx2 [10];   formatS(Lx2, "L%s2", maskCol);
	char Lx3 [10];   formatS(Lx3, "L%s3", maskCol);

	// IR Vector using Shadow IR.
	sel[0].setInstruction(Lx1,(v == 1) ? "IR1" : "TMP1");
	sel[1].setInstruction(Lx2,(v == 1) ? "IR2" : "TMP2");
	sel[2].setInstruction(Lx3,(v == 1) ? "IR3" : "TMP3");
	selAdd.set(cte);

	MASKUNIT::MaskingSetup* msk = mask.Set();
		msk->id = v;
		msk->IRCheck = true;
		msk->s44CheckGlobal = true; // MAC1..3
		msk->s44CheckLocal  = true; // O( macro
		msk->isIRCheckUseLM = true;

	writeBack.write("MAC", v);
	writeBack.write("IR",v);
	if (pushColor) {
		writeBack.write("COL",v);
		msk->colorCheck = true;
	}
}

void multiplyMatrixByVector_LightByVertex(int vertex) {
	// multiplyMatrixByVector for Lx123 x VXi :
	// Store tmp, mac and IR updated with LM, temporary flag set.
	multiplyMatrixByVector_LightByVertexPart(1, vertex);
	multiplyMatrixByVector_LightByVertexPart(2, vertex);
	multiplyMatrixByVector_LightByVertexPart(3, vertex);
}

void multiplyMatrixByVector_ColorByIR(bool pushColor) {
	// multiplyMatrixByVector(colorMatrix, toVector(ir), backgroundColor);
	multiplyMatrixByVector_ColorByIRPart(1, pushColor);
	multiplyMatrixByVector_ColorByIRPart(2, pushColor);
	multiplyMatrixByVector_ColorByIRPart(3, pushColor);
}

// DONE
void patternB() {
	/*
    multiplyVectors(Vector<int16_t>(R, G, B), toVector(ir)); // Use LM
    pushColor();
	*/
	for (int v=1; v<=3; v++) {
		registerNext();

		const char* col = "4096";
		switch (v) {
		case 1: col = "CRGB.r"; break;
		case 2: col = "CRGB.g"; break;
		case 3: col = "CRGB.b"; break;
		default: col = NULL; printf("ERROR"); break;
		}

		if (v == 1) { sel[0].setInstruction(col,"IR1"); } else { sel[0].setInstruction(NULL,"ZERO"); }
		if (v == 2) { sel[1].setInstruction(col,"IR2"); } else { sel[1].setInstruction(NULL,"ZERO"); }
		if (v == 3) { sel[2].setInstruction(col,"IR3"); } else { sel[2].setInstruction(NULL,"ZERO"); }
		selAdd.setZero();

		writeBack.write("MAC", v);
		writeBack.write("IR",v);
		writeBack.write("COL",v);

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = v;
			msk->IRCheck = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = true;
			msk->colorCheck     = true;
	}
}

// DONE TRICK : First entry is NOT USING PREVIR but IR1 !!! Still work for ALL CASES.
// TRUE : setMacAndIr<x>(((int64_t)farColor.r << 12) - (color.x * prevIr.x),false); + Write Shadow IR first
// FALSE: setMacAndIr<x>(((int64_t)farColor.x << 12) - (prevIr.x << 12    ),false); + Write Shadow IR first
void vecFarCol_IRx(bool useColor) {
	for (int v=1; v<=3; v++) {
		registerNext();
		if (v == 1) {
			writeBack.write("IR2TMP",0);	// 1 CYCLE TO COPY IR TO SHADOW REG
		}

		const char* cte     = NULL;
		switch (v) {
		case 1: cte = "RFC"; break;
		case 2: cte = "GFC"; break;
		case 3: cte = "BFC"; break;
		default: cte = NULL; printf("ERROR"); break;
		}
		
		const char* col_Or_4096 = "4096";
		if (useColor) {
			switch (v) {
			case 1: col_Or_4096 = "CRGB.r"; break;
			case 2: col_Or_4096 = "CRGB.g"; break;
			case 3: col_Or_4096 = "CRGB.b"; break;
			default: col_Or_4096 = NULL; printf("ERROR"); break;
			}
		}

		if (v == 1) { sel[0].setInstruction(col_Or_4096,"IR1" ); } else { sel[0].setInstruction(NULL,"ZERO"); }
		if (v == 2) { sel[1].setInstruction(col_Or_4096,"TMP2"); } else { sel[1].setInstruction(NULL,"ZERO"); }
		if (v == 3) { sel[2].setInstruction(col_Or_4096,"TMP3"); } else { sel[2].setInstruction(NULL,"ZERO"); }
		selAdd.set(cte);

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = v;
			msk->IRCheck = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = false; // NO LM !!!!

		writeBack.write("MAC", v);
		writeBack.write("IR",v);
		globalPath.negSelOutput(v);
	}
} 

// DONE
void patternC(bool useRGBFifo) {
	/*
	int16_t r = (useRGBFifo ? rgb[0].read(0) : rgbc.read(0)) << 4;
	int16_t g = (useRGBFifo ? rgb[0].read(1) : rgbc.read(1)) << 4;
	int16_t b = (useRGBFifo ? rgb[0].read(2) : rgbc.read(2)) << 4;

	setMacAndIr<1>(((int64_t)farColor.r << 12) - (r << 12),false);
	setMacAndIr<2>(((int64_t)farColor.g << 12) - (g << 12),false);
	setMacAndIr<3>(((int64_t)farColor.b << 12) - (b << 12),false);
	*/
	for (int v=1; v<=3; v++) {
		registerNext();

		if (useRGBFifo) {
			globalPath.useCol0();
		}

		const char* cte     = NULL;
		switch (v) {
		case 1: cte = "RFC"; break;
		case 2: cte = "GFC"; break;
		case 3: cte = "BFC"; break;
		default: cte = NULL; printf("ERROR"); break;
		}
		
		const char* col = NULL;
		switch (v) {
		case 1: col = "CRGB.r"; break;
		case 2: col = "CRGB.g"; break;
		case 3: col = "CRGB.b"; break;
		default: col = NULL; printf("ERROR"); break;
		}

		if (v == 1) { sel[0].setInstruction("4096",col); } else { sel[0].setInstruction(NULL,"ZERO"); }
		if (v == 2) { sel[1].setInstruction("4096",col); } else { sel[1].setInstruction(NULL,"ZERO"); }
		if (v == 3) { sel[2].setInstruction("4096",col); } else { sel[2].setInstruction(NULL,"ZERO"); }
		selAdd.set(cte);

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = v;
			msk->IRCheck = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = false; // NO LM !!!!

		writeBack.write("MAC", v);
		writeBack.write("IR",v);
		globalPath.negSelOutput(v);
	}
}

// DONE
void patternD() {
	/*
		setMacAndIr<1>(R * prevIr.x + ir[0] * ir[1], lm);
		setMacAndIr<2>(G * prevIr.y + ir[0] * ir[2], lm);
		setMacAndIr<3>(B * prevIr.z + ir[0] * ir[3], lm);
		pushColor();
	*/
	for (int v=1; v<=3; v++) {
		registerNext();

		const char* cte     = NULL;
		switch (v) {
		case 1: cte = "R_mul_ShadowIR1"; break;
		case 2: cte = "G_mul_ShadowIR2"; break;
		case 3: cte = "B_mul_ShadowIR3"; break;
		default: cte = NULL; printf("ERROR"); break;
		}
		
		if (v == 1) { sel[0].setInstruction("IR1","IR0"); } else { sel[0].setInstruction(NULL,"ZERO"); }
		if (v == 2) { sel[1].setInstruction("IR2","IR0"); } else { sel[1].setInstruction(NULL,"ZERO"); }
		if (v == 3) { sel[2].setInstruction("IR3","IR0"); } else { sel[2].setInstruction(NULL,"ZERO"); }
		selAdd.set(cte);

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id             = v;
			msk->IRCheck        = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = true;
			msk->colorCheck     = true;

		writeBack.write("MAC",v);
		writeBack.write("IR" ,v);
		writeBack.write("COL",v);
	}
}

// DONE
void patternA() {
	/*
    auto prevIr = toVector(ir);
    {
		setMacAndIr<1>(((int64_t)farColor.r << 12) - (R * ir[1]), false); // setMacAndIr<x>(((int64_t)farColor.r << 12) - (color.x * prevIr.x),false); + Write Shadow IR first
		setMacAndIr<2>(((int64_t)farColor.g << 12) - (G * ir[2]), false);
		setMacAndIr<3>(((int64_t)farColor.b << 12) - (B * ir[3]), false);
	*/ // IR[x] and TMPx same usage OK.
	vecFarCol_IRx(true);

	/*
		setMacAndIr<1>((R * prevIr.x) + ir[0] * ir[1], lm);
		setMacAndIr<2>((G * prevIr.y) + ir[0] * ir[2], lm);
		setMacAndIr<3>((B * prevIr.z) + ir[0] * ir[3], lm);
		pushColor();
	*/
	patternD();
}

// DONE
void patternE(bool useColor, bool useCol0) {
	/*  int16_t r = (useRGB0 ? rgb[0].read(0) : rgbc.read(0)) << 4;
		int16_t g = (useRGB0 ? rgb[0].read(1) : rgbc.read(1)) << 4;
		int16_t b = (useRGB0 ? rgb[0].read(2) : rgbc.read(2)) << 4;
		multiplyVectors(Vector<int16_t>(ir[0]), toVector(ir), Vector<int16_t>(r, g, b));	// USE COLOR
		   or
		multiplyVectors(Vector<int16_t>(ir[0]), toVector(ir), prevIr);						// USE SHADOW IR
		
		pushColor(); */
	for (int v=1; v<=3; v++) {
		registerNext();

		if (useColor && useCol0) { globalPath.useCol0(); }

		const char* cte     = NULL;
		const char* maskCol = NULL;
		switch (v) {
		case 1: cte = useColor ? "CRGB.r" : "TMP1"; maskCol = "R"; break;
		case 2: cte = useColor ? "CRGB.g" : "TMP2"; maskCol = "G"; break;
		case 3: cte = useColor ? "CRGB.b" : "TMP3"; maskCol = "B"; break;
		default: cte = NULL; printf("ERROR"); break;
		}

		if (v == 1) { sel[0].setInstruction("IR1","IR0"); } else { sel[0].setInstruction(NULL,"ZERO"); }
		if (v == 2) { sel[1].setInstruction("IR2","IR0"); } else { sel[1].setInstruction(NULL,"ZERO"); }
		if (v == 3) { sel[2].setInstruction("IR3","IR0"); } else { sel[2].setInstruction(NULL,"ZERO"); }
		selAdd.set(cte);

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = v;
			msk->IRCheck        = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = true;
			msk->colorCheck     = true;

		writeBack.write("MAC", v);
		writeBack.write("IR",v);
		writeBack.write("COL",v);
	}
}

// ------------------------------------------------------------------------------
//   Instructions
// ------------------------------------------------------------------------------

void nop() {
	Start("NOP",0x00,1,1);
	registerNext();
	endInstruction();
}

// DONE PASS AMIDOG
void ncds(int n) {
	multiplyMatrixByVector_LightByVertex(n);
	multiplyMatrixByVector_ColorByIR    (false);
	patternA();
}

// 1 DONE 19 CYCLES PASS AMIDOG
void ncds() {
	Start("NCDS",0x13,19,12);
	ncds(0);
	endInstruction();
}

// 2 DONE NCDT 44 CYCLES PASS AMIDOG
void ncdt() {
	Start("NCDT",0x16,44,36);
	ncds(0);
	ncds(1);
	ncds(2);
	endInstruction();
}

// DONE PASS AMIDOG
void ncs(int n) {
	multiplyMatrixByVector_LightByVertex(n);
	multiplyMatrixByVector_ColorByIR    (true);
}

// 3 DONE NCS 14 CYCLES PASS AMIDOG
void ncs() {
	Start("NCS",0x1E,14,6);
	ncs(0);
	endInstruction();
}

// 4 DONE NCT 30 CYCLES PASS AMIDOG
void nct() {
	Start("NCT",0x20,30,18);
	ncs(0);
	ncs(1);
	ncs(2);
	endInstruction();
}

// DONE PASS AMIDOG
void nccs(int n) {
	multiplyMatrixByVector_LightByVertex(n);
	multiplyMatrixByVector_ColorByIR    (false);
	patternB();
}

// 5 DONE 17 CYCLES PASS AMIDOG
void nccs() {
	Start("NCCS",0x1B,17,9);
	nccs(0);
	endInstruction();
}

// 6 DONE NCCT 39 CYCLES PASS AMIDOG
void ncct() {
	Start("NCCT",0x3F,39,27);
	nccs(0);
	nccs(1);
	nccs(2);
	endInstruction();
}

// 7 DONE CC 11 CYCLES PASS AMIDOG
void cc() {
	Start("CC",0x1C,11,6);
	multiplyMatrixByVector_ColorByIR    (false);
	patternB();
	endInstruction();
}

// 8 DONE CDP 13 CYCLES PASS AMIDOG
void cdp() { 
	Start("CDP",0x14,13,9);
	multiplyMatrixByVector_ColorByIR    (false);
	patternA();
	endInstruction();
}

// DONE DPCS PASS AMIDOG
void dpcs(bool useRGBFifo) {
/*
	int16_t r = (useRGB0 ? rgb[0].read(0) : rgbc.read(0)) << 4;
    int16_t g = (useRGB0 ? rgb[0].read(1) : rgbc.read(1)) << 4;
    int16_t b = (useRGB0 ? rgb[0].read(2) : rgbc.read(2)) << 4;

    setMacAndIr<1>(((int64_t)farColor.r << 12) - (r << 12),false);
    setMacAndIr<2>(((int64_t)farColor.g << 12) - (g << 12),false);
    setMacAndIr<3>(((int64_t)farColor.b << 12) - (b << 12),false);
*/
	patternC(useRGBFifo);
	/*  multiplyVectors(Vector<int16_t>(ir[0]), toVector(ir), Vector<int16_t>(r, g, b));
		pushColor(); */
	patternE(true,useRGBFifo);
}

// 9 DPCS DONE 8 CYCLES (done in 6) PASS AMIDOG
void dpcs() {
	Start("DPCS",0x10,8,6);
	dpcs(false);
	endInstruction();
}

// 10 DONE DPCT 17 CYCLES !!!! (3*6 = 18 !) PASS AMIDOG
void dpct() {
	Start("DPCT",0x2A,17,18);
	dpcs(true);
	dpcs(true);
	dpcs(true);
	endInstruction();
}

// 11 DONE DPCL 8 CYCLES (Done in 6) PASS AMIDOG
void dpcl() {
	Start("DPCL",0x29,8,6);
	/*
    auto prevIr = toVector(ir);

    setMacAndIr<1>(((int64_t)farColor.r << 12) - (R * prevIr.x));
    setMacAndIr<2>(((int64_t)farColor.g << 12) - (G * prevIr.y));
    setMacAndIr<3>(((int64_t)farColor.b << 12) - (B * prevIr.z));

    setMacAndIr<1>(R * prevIr.x + ir[0] * ir[1], lm);
    setMacAndIr<2>(G * prevIr.y + ir[0] * ir[2], lm);
    setMacAndIr<3>(B * prevIr.z + ir[0] * ir[3], lm);
    pushColor();

    setMacAndIr<1>(((int64_t)farColor.r << 12) - (R * prevIr.x),false);
    setMacAndIr<2>(((int64_t)farColor.g << 12) - (G * prevIr.y),false);
    setMacAndIr<3>(((int64_t)farColor.b << 12) - (B * prevIr.z),false);
	*/
	patternA();
	/* SAME as PatternA()
	vecFarCol_IRx(true);
	patternD();
	*/
	endInstruction();
}

// 12 DONE INTPL 8 CYCLES (done in 6) PASS AMIDOG
void intpl() {
	Start("INTPL",0x11,8,6);
	/*
		auto prevIr = toVector(ir); + Write Shadow IR
		setMacAndIr<x>(((int64_t)farColor.x << 12) - (prevIr.x << 12),false); 
		setMacAndIr<2>(((int64_t)farColor.g << 12) - (prevIr.y << 12),false);
		setMacAndIr<3>(((int64_t)farColor.b << 12) - (prevIr.z << 12),false);
	*/
	vecFarCol_IRx(false);

	/*
		multiplyVectors(Vector<int16_t>(ir[0]), toVector(ir), prevIr);
		pushColor();
	*/
	patternE(false,false);

	endInstruction();
}

// DONE RTPS PASS AMIDOG 6 Cycle Stand alone, 5+5+6 RTPT
void rtps(int idx, bool setMAC0) {

	/*	Vector<int64_t> result;

		#define O(i, value) checkMacOverflowAndExtend<i>(value)

		result.x = O(1, O(1, O(1, ((int64_t)tr.x << 12) + m[0][0] * v.x) + m[0][1] * v.y) + m[0][2] * v.z);
		result.y = O(2, O(2, O(2, ((int64_t)tr.y << 12) + m[1][0] * v.x) + m[1][1] * v.y) + m[1][2] * v.z);
		result.z = O(3, O(3, O(3, ((int64_t)tr.z << 12) + m[2][0] * v.x) + m[2][1] * v.y) + m[2][2] * v.z);

		#undef O

		setMacAndIr<1>(result.x, lm);
		setMacAndIr<2>(result.y, lm);
		setMac<3>     (result.z);      // mac[3] = result.z >> (sf*12);

		// RTP calculates IR3 saturation flag as if lm bit was always false
		// NORMAL : ir[i] = clip(value, 0x7fff, lm ? 0 : -0x8000, saturatedBits);
		clip(result.z >> 12, 0x7fff, -0x8000, Flag::IR3_SATURATED); <-- Need a control flag for FLAG RANGE CHECK.

		// But calculation itself respects lm bit <-- OVER FLOW VALUE IS USING STANDARD LM BITS.
		ir[3] = clip(mac[3], 0x7fff, lm ? 0 : -0x8000);

		return result.z;
	*/
    // int64_t macTmp3 = multiplyMatrixByVectorRTP(rotation, v[n], translation);
	for (int n=3; n >= 1; n--) {
		// FIRST, SETUP HW.
		registerNext();


		// ---- Step 0
		const char* cte;
		switch (n) {
		case 1: cte = "TRX"; break;
		case 2: cte = "TRY"; break;
		case 3: cte = "TRZ"; break;
		default: cte = NULL; printf("ERROR"); break;
		}

		char Rx1 [10];   format(Rx1, "R%i1", n);
		char Rx2 [10];   format(Rx2, "R%i2", n);
		char Rx3 [10];   format(Rx3, "R%i3", n);
		char Vx  [10];   format(Vx,  "VX%i", idx);
		char Vy  [10];   format(Vy,  "VY%i", idx);
		char Vz  [10];   format(Vz,  "VZ%i", idx);

		sel[0].setInstruction(Rx1,Vx);
		sel[1].setInstruction(Rx2,Vy);
		sel[2].setInstruction(Rx3,Vz);
		selAdd.set(cte);

		// Special Z Bit path :
		// pushScreenZ((int32_t)(macTmp3 >> 12));
		// int64_t h_s3z = divideUNR(h, s[3].z); // SAME CLOCK
		// STORE VALUE AT THIS CLOCK (3rd instruction) ---> H_S3Z Register internal
		// --------------------------------------------------------------------------------------

		MASKUNIT::MaskingSetup* msk = mask.Set();
		msk->id = n;
		msk->isIRCheckUseLM = true;

		if (n != 3) {
			msk->IRCheck = true;
			msk->s44CheckGlobal = true;
			// O( ... temporary flag for each unit)
			msk->s44CheckLocal  = true;
		} else {
			msk->s44CheckGlobal = true;
			// O( ... temporary flag for each unit)
			msk->s44CheckLocal  = true;
			// TODO : clip(z, 0xffff, 0x0000, Flag::SZ3_OTZ_SATURATED); (PushZ)
			// TODO : +
					// RTP calculates IR3 saturation flag as if lm bit was always false
					// clip(result.z >> 12, 0x7fff, -0x8000, Flag::IR3_SATURATED);
			msk->lmFalseForIR3Saturation = true;


					// But calculation itself respects lm bit
					// ir[3] = clip(mac[3], 0x7fff, lm ? 0 : -0x8000, 0 /*NO FLAG*/);
			msk->IRCheck = true;

			writeBack.write("PUSH",3);
			// Mark Flag when pushing Z too.
			msk->otzCheck = true; // VALUE>>12 0..FFFF
		}
		if (n == 1) {
			// Result of division with 2 cycle latency.
			writeBack.write("DIVRES",-1);
		}

		writeBack.write("MAC", n);
		writeBack.write("IR" , n);

	}

	for (int n=0; n < 2; n++) {
		// FIRST, SETUP HW.
		registerNext();

	/*
		//      2. H_S3Z input in SelMuxUnit1 and SelMuxUnit2
		//      3. OF[0]/OF[1] input in SelAdd

		SX2 = Lm_G1(F((s64) OFX + ((s64) IR1 * h_over_sz3) * (Config.Widescreen ? 0.75 : 1)) >> 16);

		int32_t x = setMac<0>((int64_t)(h_s3z * ir[1] * ratio) + of[0]) >> 16;
		int32_t y = setMac<0>(h_s3z * ir[2] + of[1]) >> 16;
		pushScreenXY(x, y);
	*/

		// ---- Step 0
		sel[0].setInstruction(NULL,"ZERO");
		sel[1].setInstruction(NULL,"ZERO");
		
		// Override
		sel[n].setInstruction( n ? "IR2" : "IR1","HS3Z");
		sel[2].setInstruction(NULL,"ZERO");
		selAdd.set( n ? "OFY" : "OFX");

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = 0;                // For MAC0
			msk->s32Check       = true; // MAC0 too.
			msk->X0_or_Y1       = n;
			msk->s11Check       = true;

			// Output of DIV unit gives overflow bit at this cycle.
			if (n==0) {
				msk->checkDivOverflow = true;
			}

		writeBack.write("PUSH",n+1);
		writeBack.write("MAC",0);
	}

	if (setMAC0) {
		// int64_t mac0 = setMac<0>(h_s3z * dqa + dqb);
		// ir[0] = clip(mac0 >> 12, 0x1000, 0x0000, Flag::IR0_SATURATED);
		registerNext();
		sel[0].setInstruction("DQA","HS3Z");
		sel[1].setInstruction(NULL,"ZERO");
		sel[2].setInstruction(NULL,"ZERO");
		selAdd.set("DQB");

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = 0;                // For MAC0
			msk->s32Check       = true; // MAC0 too.
			msk->u4096Check     = true;

		writeBack.write("MAC",0);
		writeBack.write("IR0",0);
	}
}

// 13 DONE RTPS 14 Cycle (probably done 6)
void rtps() {
	Start("RTPS",0x01,14 /*Sony's doc, No$=15*/,6);
	rtps(0,true);
	endInstruction();
}

// 14 DONE RTPT 22 Cycles (probably done 16)
void rtpt() {
	Start("RTPT",0x30,22 /*Sony's doc, No$=23*/,16);
	rtps(0,false);
	rtps(1,false);
	rtps(2,true );
	endInstruction();
}

// PASS AMIDOG
void avsz3(bool asAVSZ4) { 
	registerNext();

	const char* ZSFx = asAVSZ4 ? "ZSF4" : "ZSF3";
	sel[0].setInstruction("SZ1",ZSFx);
	sel[1].setInstruction("SZ2",ZSFx);
	sel[2].setInstruction("SZ3",ZSFx);

	if (!asAVSZ4) {
		selAdd.setZero();
	} else {
		selAdd.setSpecial_ZOZSF4Mul();
	}

	MASKUNIT::MaskingSetup* msk = mask.Set();
		msk->id = 0;
		msk->s32Check       = true; // MAC0 too.
		msk->otzCheck       = true; // VALUE>>12 0..FFFF

	writeBack.write("MAC",0); // Automatically override SF = 0
	writeBack.write("OTZ",0);
}

// 15 DONE AVSZ3 5 CYCLES (1 CYCLE) PASS AMIDOG
void avsz3() {
	Start("AVSZ3",0x2D,5,1);
	avsz3(false);
	endInstruction();
}

// 16 DONE AVSZ4 6 CYCLES (1 CYCLE) PASS AMIDOG
void avsz4() { // DONE
	Start("AVSZ4",0x2E,6,1);
	avsz3(true);
	endInstruction();
}

// 17 TODO MVMVA 8 CYCLES (3 or 6)
void mvmva_core(int selMode, bool forceLMZero, bool doWriteBack) {
	// Feed back issue when RIGHT SIDE IS [IR VECTOR], force always.
	for (int v=1; v <= 3; v++) {
		// FIRST, SETUP HW.
		registerNext();

		// Only ONCE FOR THE FIRST BLOCK.
		if (v == 1 && (selMode != 2)) {
			writeBack.write("IR2TMP",0);	// 1 CYCLE TO COPY IR TO SHADOW REG, EVEN IF IR is not used as input, no pb.
		}

		// ---- Step 0
		const char* cte;
		const char* U1 = NULL;
		const char* U2 = NULL;
		const char* U3 = NULL;

		switch (v) {
		case 1: U1 = "R11"; U2 = "R12"; U3 = "R13"; cte = "RBK"; break; // U1 and cte are overridden by MVMVA internal to select correct MATRIX and VECTOR SOURCE.
		case 2: U1 = "R21"; U2 = "R22"; U3 = "R23"; cte = "GBK"; break;
		case 3: U1 = "R31"; U2 = "R32"; U3 = "R33"; cte = "BBK"; break;
		default: cte = NULL; printf("ERROR"); break;
		}

		// Trick :
		// - MVMVA instruction select source vector.
		// - TRICK IS HERE : Re-Use internal source vector to select between IR or TMPIR if IR is used, else no impact
		//   -> IR Vector using Shadow IR.
		switch (selMode) {
		case 0:
			sel[0].setInstruction(U1, (v==1) ? "DYNVEC0" : "DYNVEC1");
			sel[1].setInstruction(U2, (v==1) ? "DYNVEC0" : "DYNVEC1");
			sel[2].setInstruction(U3, (v==1) ? "DYNVEC0" : "DYNVEC1");
			selAdd.set(cte);
			break;
		case 1:
			sel[0].setInstruction(U1, (v==1) ? "DYNVEC0" : "DYNVEC1");
			sel[1].setInstruction(NULL, "ZERO");
			sel[2].setInstruction(NULL, "ZERO");
			selAdd.set(cte);
			break;
		case 2:
			sel[0].setInstruction(NULL, "ZERO");
			sel[1].setInstruction(U2, "DYNVEC1");
			sel[2].setInstruction(U3, "DYNVEC1");
			selAdd.setZero();
			break;
		}

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = v;
			msk->IRCheck        = true;
			msk->s44CheckGlobal = true; // MAC1..3
			msk->s44CheckLocal  = true; // O( macro
			msk->isIRCheckUseLM = !forceLMZero;

		if (doWriteBack) {
			writeBack.write("MAC", v);
			writeBack.write("IR",v);
		} else {
			// No write back ! BUT NEED SF !
			writeBack.setup[writeBack.instructionID].useSFWrite32 = true;
		}
	}
}

void mvmva() {
	Start("MVMVA",0x12,8,3);
	mvmva_core(0,false,true);
	endInstruction();
}

void mvmvaBuggy() {
	Start("MVMVA_Buggy",0x2,8,6);
	mvmva_core(1,true,false);
	mvmva_core(2,false,true);
	endInstruction();
}

// 18 DONE GPL PASS AMIDOG
void gpl(bool as_gpf) {
	/*
    setMacAndIr<1>(((int64_t)mac[1] << (sf * 12)) + ir[0] * ir[1], lm);
    setMacAndIr<2>(((int64_t)mac[2] << (sf * 12)) + ir[0] * ir[2], lm);
    setMacAndIr<3>(((int64_t)mac[3] << (sf * 12)) + ir[0] * ir[3], lm);
    pushColor();
	*/
	// FIRST, SETUP HW.
	for (int n=1; n <= 3; n++) {
		registerNext();

		const char* macSel;
		switch (n) {
		case 1:
			sel[0].setInstruction("IR1","IR0");
			sel[1].setInstruction(NULL,"ZERO");
			sel[2].setInstruction(NULL,"ZERO");
			macSel  = "MAC1";
			break;
		case 2:
			sel[0].setInstruction(NULL,"ZERO");
			sel[1].setInstruction("IR2","IR0");
			sel[2].setInstruction(NULL,"ZERO");
			macSel  = "MAC2";
			break;
		case 3:
			sel[0].setInstruction(NULL,"ZERO");
			sel[1].setInstruction(NULL,"ZERO");
			sel[2].setInstruction("IR3","IR0");
			macSel  = "MAC3";
			break;
		default:
			macSel  = NULL;
			printf("ERROR");
			break;
		}
		if (as_gpf) {
			// GPF does not add MACx
			selAdd.setZero();
		} else {
			selAdd.set(macSel);
		}

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = n;
			msk->IRCheck = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = true;
			msk->colorCheck     = true;

		writeBack.write("MAC",n);
		writeBack.write("IR" ,n);
		writeBack.write("COL",n);
	}
}

// 5 CYCLE (done 3) PASS AMIDOG
void gpl() {
	Start("GPL",0x3E, 5, 3);
	gpl(false);
	endInstruction();
}

// 19 DONE GPF 5 CYCLE (done 3) PASS AMIDOG
void gpf() {
	Start("GPF",0x3D, 5, 3);
	gpl(true);
	endInstruction();
}

// 20 DONE SQR 5 CYCLE (done 3) PASS AMIDOG
void sqr() {
	Start("SQR",0x28, 5, 3);

	// FIRST, SETUP HW.
	for (int n=1; n <= 3; n++) {
		registerNext();

		switch (n) {
		case 1:
			sel[0].setInstruction("IR1","IR1");
			sel[1].setInstruction(NULL,"ZERO");
			sel[2].setInstruction(NULL,"ZERO");
			break;
		case 2:
			sel[0].setInstruction(NULL,"ZERO");
			sel[1].setInstruction("IR2","IR2");
			sel[2].setInstruction(NULL,"ZERO");
			break;
		case 3:
			sel[0].setInstruction(NULL,"ZERO");
			sel[1].setInstruction(NULL,"ZERO");
			sel[2].setInstruction("IR3","IR3");
			break;
		}
		selAdd.setZero();

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = n;
			msk->IRCheck = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = true;

		writeBack.write("MAC", n);
		writeBack.write("IR",n);
	}

	endInstruction();
}

// 21 DONE OP 6 CYCLE (done 3) PASS AMIDOG
void op() {
	Start("OP",0x0C,6,3);

	/*
		// CAN'T USE setMacAndIr Macro because of the dependance between IR as BOTH INPUT *and* OUTPUT !!!
		==> COPY TO SHADOW, START WITH IR3 / IR2
		==> USE IR0 as input and set the special flag.
			globalPath.negSelOutput(3,1,2);
			Use Normal standard MacIRLM stuff.
		setMac<1>(rotation[1][1] * ir[3] - rotation[2][2] * ir[2]);  // Sel2(TMP3) - Sel3(TMP2) except 
		setMac<2>(rotation[2][2] * ir[1] - rotation[0][0] * ir[3]);  // Sel3(TMP1) - Sel1(TMP3)
		setMac<3>(rotation[0][0] * ir[2] - rotation[1][1] * ir[1]);  // Sel1(TMP2) - Sel2(TMP1)
		setIr <1>(mac[1], lm);
		setIr <2>(mac[2], lm);
		setIr <3>(mac[3], lm);

		HARDWARE USE SHADOW REGISTERS to avoid the issue. (Does NOT use the shadow reg for first cycle)
		After that IRx can be modified freely.
	*/
	for (int n=1; n <=3; n++) {
		registerNext();
		if (n==1) {
			writeBack.write("IR2TMP",0); // Copy to shadow registers.
		}
		globalPath.setOPInstrCycle(n);

		switch (n) {
		case 1:
			sel[0].setInstruction(NULL,"ZERO");
			sel[1].setInstruction("R22","IR0"); /*IRO=IR3*/
			sel[2].setInstruction("R33","IR0"); /*IRO=IR2*/
			globalPath.negSelOutput(3);
			break;
		case 2:
			sel[0].setInstruction("R11","IR0"); /*IRO=IR3*/
			sel[1].setInstruction(NULL,"ZERO");
			sel[2].setInstruction("R33","IR0"); /*IRO=IR1*/
			globalPath.negSelOutput(1);
			break;
		case 3:
			sel[0].setInstruction("R11","IR0"); /*IRO=IR2*/
			sel[1].setInstruction("R22","IR0"); /*IRO=IR1*/
			sel[2].setInstruction(NULL,"ZERO");
			globalPath.negSelOutput(2);
			break;
		}

		MASKUNIT::MaskingSetup* msk = mask.Set();
			msk->id = n;
			msk->IRCheck = true;
			msk->s44CheckGlobal = true; // MAC1..3
			// NO : STAY FALSE msk.s44CheckLocal
			msk->isIRCheckUseLM = true;

		writeBack.write("MAC", n);
		writeBack.write("IR" , n);

		selAdd.setZero();
	}
	endInstruction();

}

// 22 DONE NCLIP 8 CYCLES PASS AMIDOG
void nclip() {
	Start("NCLIP",0x06,8,2);

	// Cycle 0 (SECOND PART OF THE EQUATION !!!)
	registerNext();
	sel[0].setInstruction("SX0","SY2");
	sel[1].setInstruction("SX1","SY0");
	sel[2].setInstruction("SX2","SY1");
	selAdd.setZero();
	writeBack.write("STORERES",0);

	// Cycle 1 (FIRST PART OF EQUATION AND ADD NEGATIVE RESULT)
	registerNext();
	sel[0].setInstruction("SX0","SY1");
	sel[1].setInstruction("SX1","SY2");
	sel[2].setInstruction("SX2","SY0");
	selAdd.setZero();
	writeBack.useStoreRes();

	MASKUNIT::MaskingSetup* msk = mask.Set();
		msk->id = 0;
		msk->s32Check = true;

	writeBack.write("MAC", 0); // SF force to 0 handled.
	
	endInstruction();
}

void genTblDiv() {
		static const unsigned char unr_table[257] = {
			0xFF,0xFD,0xFB,0xF9,0xF7,0xF5,0xF3,0xF1,0xEF,0xEE,0xEC,0xEA,0xE8,0xE6,0xE4,0xE3, //-
			0xE1,0xDF,0xDD,0xDC,0xDA,0xD8,0xD6,0xD5,0xD3,0xD1,0xD0,0xCE,0xCD,0xCB,0xC9,0xC8, // 00h..3Fh
			0xC6,0xC5,0xC3,0xC1,0xC0,0xBE,0xBD,0xBB,0xBA,0xB8,0xB7,0xB5,0xB4,0xB2,0xB1,0xB0, //
			0xAE,0xAD,0xAB,0xAA,0xA9,0xA7,0xA6,0xA4,0xA3,0xA2,0xA0,0x9F,0x9E,0x9C,0x9B,0x9A, ///

			0x99,0x97,0x96,0x95,0x94,0x92,0x91,0x90,0x8F,0x8D,0x8C,0x8B,0x8A,0x89,0x87,0x86, //-
			0x85,0x84,0x83,0x82,0x81,0x7F,0x7E,0x7D,0x7C,0x7B,0x7A,0x79,0x78,0x77,0x75,0x74, // 40h..7Fh
			0x73,0x72,0x71,0x70,0x6F,0x6E,0x6D,0x6C,0x6B,0x6A,0x69,0x68,0x67,0x66,0x65,0x64, //
			0x63,0x62,0x61,0x60,0x5F,0x5E,0x5D,0x5D,0x5C,0x5B,0x5A,0x59,0x58,0x57,0x56,0x55, ///

			0x54,0x53,0x53,0x52,0x51,0x50,0x4F,0x4E,0x4D,0x4D,0x4C,0x4B,0x4A,0x49,0x48,0x48, //-
			0x47,0x46,0x45,0x44,0x43,0x43,0x42,0x41,0x40,0x3F,0x3F,0x3E,0x3D,0x3C,0x3C,0x3B, // 80h..BFh
			0x3A,0x39,0x39,0x38,0x37,0x36,0x36,0x35,0x34,0x33,0x33,0x32,0x31,0x31,0x30,0x2F, //
			0x2E,0x2E,0x2D,0x2C,0x2C,0x2B,0x2A,0x2A,0x29,0x28,0x28,0x27,0x26,0x26,0x25,0x24, ///

			0x24,0x23,0x22,0x22,0x21,0x20,0x20,0x1F,0x1E,0x1E,0x1D,0x1D,0x1C,0x1B,0x1B,0x1A, //-
			0x19,0x19,0x18,0x18,0x17,0x16,0x16,0x15,0x15,0x14,0x14,0x13,0x12,0x12,0x11,0x11, // C0h..FFh
			0x10,0x0F,0x0F,0x0E,0x0E,0x0D,0x0D,0x0C,0x0C,0x0B,0x0A,0x0A,0x09,0x09,0x08,0x08, //
			0x07,0x07,0x06,0x06,0x05,0x05,0x04,0x04,0x03,0x03,0x02,0x02,0x01,0x01,0x00,0x00, ///
		}; //    ;<-- one extra table entry (for "(d-7FC0h)/80h"=100h)    ;-100h

	int idx = 0;
	for (int n=0; n < 32; n++) {
		for (int x=0; x < 8; x++) {
			printf("ram[%i] = 10'd%i; ",idx, (unr_table[idx] + 0x101));
			idx++;
		}
		printf("\n");
	}
	for (int n=0; n < 32; n++) {
		for (int x=0; x < 8; x++) {
			printf("ram[%i] = 10'd%i;", idx, (int)0x101);
			idx++;
		}
		printf("\n");
	}
}

#define pr(a) printf(a);printf("\n");

void registerInstructions() {
	// 0 NOP
	nop();
	// 1 TODO NCDS
	ncds();
	// 2 DONE NCDT
	ncdt();
	// 3 DONE NCS
	ncs();
	// 4 DONE NCT
	nct();
	// 5 TODO CAN NCCS
	nccs();
	// 6 DONE NCCT
	ncct();
	// 7 TODO CAN CC
	cc();
	// 8 TODO CDP
	cdp();
	// 9 TODO DPCS
	dpcs();
	// 10 DONE DPCT
	dpct();
	// 11 TODO DPCL
	dpcl();
	// 12 TODO INTPL
	intpl();
	// 13 TODO RTPS
	rtps();
	// 14 TODO RTPT
	rtpt();
	// 15 DONE AVSZ3
	avsz3(); 
	// 16 DONE AVSZ4
	avsz4();
	// 17 TODO MVMVA
	mvmva();
	// 17 TODO MVMVA BUGGY
	mvmvaBuggy();
	// 18 DONE GPL
	gpl();
	// 19 DONE GPF
	gpf();
	// 20 DONE SQR
	sqr();
	// 21 TODO OP
	op();
	// 22 TODO NCLIP
	nclip();
	
	generatorStartTableMicroCode("../rtl/MicroCodeStart.inl");
}

#define pro		fprintf
#define proln	fprintf(fout,"\n");

void generateMicroCode(const char* fileName) {

	FILE* fout = fopen(fileName,"wb");

	// TODO : Handle the -1 don't care stuff...

	for (int n=0; n < instructionID; n++) {

		// TODO : Export in comment the Instruction name and cycle count.

		pro(fout,"microCodeROM[%i].ctrlPath = '{ ",n);

		for (int unit=1; unit <=3; unit++) {
			SELUNIT& selU = sel[unit-1];
			int l = selU.setup[n].left;
			int r = selU.setup[n].right;
			
			pro(fout,"sel%i:'{mat:2'd%i,selLeft:4'd%i/*%s*/,selRight:4'd%i,vcompo:2'd%i/*%s*/}"
				,unit
				,selU.availableRegL[l].matSel
				,selU.availableRegL[l].selLeft
				,selU.availableRegL[l].name
				,selU.availableRegR[r].selRight
				,selU.availableRegR[r].vecSel
				,selU.availableRegR[r].name
			);

			pro(fout," , ");
		}

		int def = selAdd.setup[n];

		pro(fout," addSel:'{useSF:1'b%i,id:2'd%i,sel:4'd%i} , ",
			selAdd.entries[def].useSFShift ? 1:0,
			selAdd.entries[def].subID,
			selAdd.entries[def].id
		);

		WRITEBACK::Entry& wre = writeBack.setup[n];

		// Write back stuff a bit in ctrlPath...
		pro(fout," wrTMP1:1'b%i", wre.wrTMP[0] ? 1:0);
		pro(fout," , wrTMP2:1'b%i", wre.wrTMP[1] ? 1:0);
		pro(fout," , wrTMP3:1'b%i", wre.wrTMP[2] ? 1:0);
		pro(fout," , storeFull:1'b%i", wre.storeFull ? 1:0);
		pro(fout," , useStoreFull:1'b%i", wre.useStoreFull ? 1:0);

		pro(fout," , useSFWrite32:1'b%i", wre.useSFWrite32 ? 1:0);
		pro(fout," , assignIRtoTMP:1'b%i",wre.copyIRtoTemp ? 1:0);
		pro(fout," , wrDivRes:1'b%i",wre.wrDIVRES ? 1:0);
		pro(fout," , negSel:3'b%i%i%i", 
			globalPath.useNegSel3[n] ? 1:0,
			globalPath.useNegSel2[n] ? 1:0,
			globalPath.useNegSel1[n] ? 1:0
		);
		pro(fout," , selOpInstr:2'd%i", globalPath.selOpInstr[n]);
		pro(fout," , selCol0:1'b%i",globalPath.selCol0[n] ? 1:0);

		MASKUNIT::MaskingSetup& msk = mask.instructions[n];
		
		pro(fout," , check44Global:1'b%i",msk.s44CheckGlobal ? 1:0);
		pro(fout," , check44Local:1'b%i",msk.s44CheckLocal ? 1:0);
		pro(fout," , check32Global:1'b%i",msk.s32Check ? 1:0);
		pro(fout," , checkOTZ:1'b%i",msk.otzCheck ? 1:0);
		pro(fout," , checkDIV:1'b%i",msk.checkDivOverflow ? 1:0);
		pro(fout," , checkXY:1'b%i",msk.s11Check ? 1:0);
		pro(fout," , checkIR0:1'b%i",msk.u4096Check ? 1:0);
		pro(fout," , checkIRn:1'b%i",msk.IRCheck ? 1:0);
		pro(fout," , checkColor:1'b%i",msk.colorCheck ? 1:0);
		pro(fout," , isIRnCheckUseLM:1'b%i",msk.isIRCheckUseLM ? 1:0);
		pro(fout," , lmFalseForIR3Saturation:1'b%i",msk.lmFalseForIR3Saturation ? 1:0);
		pro(fout," , maskID:2'd%i",msk.id);
		pro(fout," , X0_or_Y1:1'b%i",msk.X0_or_Y1 ? 1:0);

		pro(fout," };");
		/*
		// [TODO] Flag Masking
		// [TODO] Handling of flag lm
		*/
		proln;

		pro(fout,"microCodeROM[%i].wb = '{", n);
		// 4 bit
		pro(fout,"wrIR:4'b"); for (int i=3; i >= 0; i--) { pro(fout,"%i" , wre.wrIR[i] ? 1 : 0); } pro(fout,", ");
		pro(fout,"wrMAC:4'b"); for (int i=3; i >= 0; i--) { pro(fout,"%i" , wre.wrMAC[i] ? 1 : 0); } pro(fout,", ");

		// TODO : have macro YES _NO instead for binary alone ?

		pro(fout,"wrOTZ:1'b%i, ", wre.wrOTZ ? 1:0);

		pro(fout,"pushX:1'b%i, ", wre.pushX ? 1:0); pro(fout,"pushY:1'b%i, ", wre.pushY ? 1:0); pro(fout,"pushZ:1'b%i, ", wre.pushZ ? 1:0);
		pro(fout,"pushR:1'b%i, ", wre.pushR ? 1:0); pro(fout,"pushG:1'b%i, ", wre.pushG ? 1:0); 
		
		pro(fout,"pushB:1'b%i ", wre.pushB ? 1:0); // WARNING : NO COMMA !!!

		pro(fout," };"); proln;
		pro(fout,"microCodeROM[%i].lastInstrFAST = 1'b%i;\n",n,globalPath.lastInstructionFAST[n] ? 1:0);
		pro(fout,"microCodeROM[%i].lastInstrSLOW = 1'b%i;\n",n,globalPath.lastInstructionSLOW[n] ? 1:0);
	}

	fclose(fout);
}

void generatorStartTableMicroCode(const char* fileName) {
// INSTRTbl Opcode[64];
// int OpcodeCount = 0;
	FILE* fout = fopen(fileName,"wb");

	for (int n=0; n < 64; n++) {
		if (Opcode[n].name) {
			fprintf(fout,"6'h%x : retAdr = 9'd%i; // %s\n",n,Opcode[n].StartPC,Opcode[n].name);
		}
	}
	fprintf(fout,"default: retAdr = 9'd0; // UNDEF -> MAP TO NOP\n");

	fclose(fout);
}

class VGTEEngine;
#include "../rtl/obj_dir/VGTEEngine.h"

#define VCSCANNER_IMPL
#include "VCScanner.h"

#define MODULE mod
#define SCAN   pScan

#undef VL_IN
#undef VL_OUT
#undef VL_SIG
#undef VL_SIGA
#undef VL_IN8
#undef VL_OUT8
#undef VL_SIG8
#undef VL_IN16
#undef VL_OUT16
#undef VL_SIG16
#undef VL_IN64
#undef VL_OUT64
#undef VL_SIG64
#undef VL_SIGW

#define VL_IN(NAME,size,s2)			SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIGA(NAME,size,s2,cnt)	SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_IN8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG8(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_IN16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG16(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_IN64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_OUT64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIG64(NAME,size,s2)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME );
#define VL_SIGW(NAME,size,s2,storageSize,depth)		SCAN->addMemberFullPath( VCScanner_PatchName(#NAME), WIRE, BIN,size+1,& MODULE ->## NAME,depth, (((u8*)& MODULE ->## NAME[1]) - ((u8*)& MODULE ->## NAME[0])));

void registerVerilatedMemberIntoScanner(VGTEEngine* mod, VCScanner* pScan) {
    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    // Begin mtask footprint  all: 
    VL_IN8(i_clk,0,0);
    VL_IN8(i_nRst,0,0);
    VL_IN8(i_regID,5,0);
    VL_IN8(i_WritReg,0,0);
    VL_IN8(i_DIP_USEFASTGTE,0,0);
    VL_IN8(i_DIP_FIXWIDE,0,0);
    VL_IN8(i_run,0,0);
    VL_OUT8(o_executing,0,0);
    VL_IN(i_dataIn,31,0);
    VL_OUT(o_dataOut,31,0);
    VL_IN(i_Instruction,24,0);
    
    // LOCAL SIGNALS
    // Internals; generally not touched by application code
    // Begin mtask footprint  all: 
    VL_SIG8(GTEEngine__DOT__i_clk,0,0);
    VL_SIG8(GTEEngine__DOT__i_nRst,0,0);
    VL_SIG8(GTEEngine__DOT__i_regID,5,0);
    VL_SIG8(GTEEngine__DOT__i_WritReg,0,0);
    VL_SIG8(GTEEngine__DOT__i_DIP_USEFASTGTE,0,0);
    VL_SIG8(GTEEngine__DOT__i_DIP_FIXWIDE,0,0);
    VL_SIG8(GTEEngine__DOT__i_run,0,0);
    VL_SIG8(GTEEngine__DOT__o_executing,0,0);
    VL_SIG8(GTEEngine__DOT__isMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__isMVMVAWire,0,0);
    VL_SIG8(GTEEngine__DOT__isBuggyMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__gteLastMicroInstruction,0,0);
    VL_SIG8(GTEEngine__DOT__loadInstr,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__i_clk,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__i_nRst,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__i_loadInstr,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__i_regID,5,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__i_WritReg,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__FLAG_31,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accCRGB0,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accCRGB1,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accCRGB2,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accCRGB,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__cpuWrtCRGB,3,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSXY0,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSXY1,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSXY2,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSXYP,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSZ0,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSZ1,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSZ2,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__accSZP,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__cpuWrtSXY,3,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__cpuWrtSZ,3,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__wrtFSPX,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__wrtFSPY,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__wrtFSPZ,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__wrIRGB,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__cntLeadInput,5,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__pRegID,5,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__R5,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__G5,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__B5,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__result,5,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__oneLead,5,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__zeroLead,5,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__countT3,2,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__countT2,2,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__countT1,2,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__countT0,2,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__anyOneT3,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__anyOneT2,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__anyOneT1,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__anyOneT0,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__o,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__unsignedUPositive,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__myClampUPositive__DOT__valueIn,7,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__myClampUPositive__DOT__valueOut,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__myClampUPositive__DOT__isNZero,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__myClampUPositive__DOT__orStage,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__o,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__unsignedUPositive,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__myClampUPositive__DOT__valueIn,7,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__myClampUPositive__DOT__valueOut,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__myClampUPositive__DOT__isNZero,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__myClampUPositive__DOT__orStage,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__o,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__unsignedUPositive,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__myClampUPositive__DOT__valueIn,7,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__myClampUPositive__DOT__valueOut,4,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__myClampUPositive__DOT__isNZero,0,0);
    VL_SIG8(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__myClampUPositive__DOT__orStage,4,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__i_clk,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__i_nRst,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__i_DIP_FIXWIDE,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__colR,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__colG,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__colB,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__divOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isOverflowS44,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isUnderflowS44,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isOverflowS32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isUnderflowS32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isUO_OTZ,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isUO_IR0,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__isXY_UOFlow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__colorPostClip,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__ou_IRn,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__ou_Color,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__useLM,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__useSFWrite32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__overFlow44,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__underFlow44,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag30,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag29,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag28,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag27,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag26,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag25,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag24,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag23,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag22,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag21,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag20,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag19,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag18,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag17,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag16,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag15,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag14,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag13,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__writeFlag12,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__isMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__vec,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__mx,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__color,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__mat,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__vcompo,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__selLeft,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__selRight,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__isMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__vec,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__mx,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__color,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__mat,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__vcompo,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__selLeft,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__selRight,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__isMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__vec,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__mx,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__color,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__mat,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__vcompo,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__selLeft,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__selRight,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__ctrl,6,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__i_SF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__isMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__cv,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__R,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__G,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__B,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__vSF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__colV,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__sel,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__i_clk,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__overflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__countT3,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__countT2,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__countT1,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__countT0,1,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__anyOneT3,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__anyOneT2,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__anyOneT1,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__shiftAmount,3,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__ovf,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__p_ovf,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__pp_ovf,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__isOver,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local1__DOT__isOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local1__DOT__isUnderflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local2__DOT__isOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local2__DOT__isUnderflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local3__DOT__isOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local3__DOT__isUnderflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Global__DOT__isOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Global__DOT__isUnderflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS32Global__DOT__isOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS32Global__DOT__isUnderflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS32Global__DOT__hasZeros,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS32Global__DOT__hasOne,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__i_overflowS32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__i_underflowS32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__isUnderOrOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__isUnderOrOverflowIR0,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__hasOne,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__isOver,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__isUnder,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__outUnderOver,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__isGEQ4096,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__i_overflowS32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__i_underflowS32,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__isUnderOrOverflow,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__hasOne,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__hasZero,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__isOver,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__isOver_IR0,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__isUnder,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__i_sf,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__i_LM,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__i_useFixedSFLM,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__o_OU_IRn,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__o_OU_Color,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__clampOutCol,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__hasZerosSF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__hasOneSF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isUnder_v,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isUnder_vPos,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isOver_v,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__hasZerosA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__hasOneA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isUnderA_v,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isOverA_v,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__clampCol,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isNegClamp,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__isPosClamp,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__overF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__isOne,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__sgn,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__andV,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__orV,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPositive__DOT__isPos,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPositive__DOT__overF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__valueOut,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__negClamp,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__posClamp,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__isPos,0,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__andStage,7,0);
    VL_SIG8(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__overF,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__i_clk,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__isNewInstr,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__Instruction,5,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__i_USEFAST,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__o_lastInstr,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__isLastEntrySLOW,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicroCode_inst__DOT__isLastEntryFAST,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__IsNop,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__isBuggyMVMVA,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__Instruction,5,0);
    VL_SIG8(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__remapp3,0,0);
    VL_SIG8(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__remapped,5,0);
    VL_SIG16(GTEEngine__DOT__writeBack,14,0);
    VL_SIG16(GTEEngine__DOT__ctrl,8,0);
    VL_SIG16(GTEEngine__DOT__PC,8,0);
    VL_SIG16(GTEEngine__DOT__vPC,8,0);
    VL_SIG16(GTEEngine__DOT__startMicroCodeAdr,8,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__i_wb,14,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SX0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SX1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SX2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SY0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SY1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SY2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SZ0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SZ1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SZ2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__SZ3,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__IR0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__IR1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__IR2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__IR3,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__OTZ,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R11,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R12,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R13,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R21,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R22,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R23,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R31,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R32,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R33,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L11,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L12,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L13,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L21,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L22,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L23,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L31,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L32,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__L33,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LR1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LR2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LR3,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LG1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LG2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LG3,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LB1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LB2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__LB3,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__H,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__DQA,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__ZSF3,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__ZSF4,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VX0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VY0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VZ0,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VX1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VY1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VZ1,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VX2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VY2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__VZ2,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__dataPathSY,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__dataPathSX,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__dataPathSZ,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__R16,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__G16,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__B16,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstR__DOT__i,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstG__DOT__i,15,0);
    VL_SIG16(GTEEngine__DOT__GTERegs_inst__DOT__M16TO5InstB__DOT__i,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__i_wb,14,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__i_instrParam,8,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__TMP1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__TMP2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__TMP3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selIR0_1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selIR0_2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selIR0_3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__minusR,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__colSide,8,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__PrevSide,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__otzValue,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__IR0Value,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__xyValue,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__IRnPostClip,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__ctrl,11,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__IRn,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT0_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT0_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT0_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT1_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT1_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT1_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT2_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT2_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT2_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT3_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT3_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__MAT3_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__SZ,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__DQA,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__SX,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__Z3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__Z4,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__IR0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__tmpReg,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__V0c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__V1c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__V2c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__SYA,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__SYB,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__mc1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__mc2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__mc3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__ctrl,11,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__IRn,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT0_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT0_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT0_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT1_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT1_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT1_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT2_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT2_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT2_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT3_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT3_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__MAT3_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__SZ,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__DQA,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__SX,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__Z3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__Z4,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__IR0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__tmpReg,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__V0c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__V1c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__V2c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__SYA,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__SYB,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__mc1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__mc2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__mc3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__ctrl,11,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__IRn,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT0_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT0_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT0_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT1_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT1_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT1_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT2_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT2_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT2_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT3_C0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT3_C1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__MAT3_C2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__SZ,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__DQA,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__SX,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__Z3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__Z4,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__IR0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__tmpReg,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__V0c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__V1c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__V2c,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__SYA,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__SYB,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__mc1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__mc2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__mc3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__TMP1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__TMP2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__TMP3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__SZ0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__ZFS4,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__mulB,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__specialZ0MulZSF4_Lo,11,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__mac_Lo,11,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__shadowIR,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__h,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__z3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__b0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__b1,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__b2,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__b3,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__d,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__ladr,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__pd,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__routData,9,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__clampOut,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__clampOutIR0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__andS,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__outIR0,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__clampOut,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__andS,9,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__clampOut,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__clampSR16,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__clampSP15,14,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__clamp16,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__valueOut,15,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__orStage,14,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__andStage,14,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPositive__DOT__valueOut,14,0);
    VL_SIG16(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPositive__DOT__andStage,14,0);
    VL_SIG16(GTEEngine__DOT__GTEMicroCode_inst__DOT__i_PC,8,0);
    VL_SIG16(GTEEngine__DOT__GTEMicroCode_inst__DOT__o_writeBack,14,0);
    VL_SIG16(GTEEngine__DOT__GTEMicroCode_inst__DOT__wb,14,0);
    VL_SIG16(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__StartAddress,8,0);
    VL_SIG16(GTEEngine__DOT__GTEMicrocodeStart_inst__DOT__retAdr,8,0);
    VL_SIG(GTEEngine__DOT__i_dataIn,31,0);
    VL_SIG(GTEEngine__DOT__o_dataOut,31,0);
    VL_SIG(GTEEngine__DOT__i_Instruction,24,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__i_dataIn,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__o_dataOut,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__CRGB0,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__CRGB1,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__CRGB2,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__MAC0,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__MAC1,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__MAC2,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__MAC3,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__CRGB,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__TRX,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__TRY,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__TRZ,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__RBK,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__GBK,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__BBK,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__RFC,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__GFC,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__BFC,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__RES1,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__OFX,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__OFY,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__DQB,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__REG_lzcs,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__FLAGS,18,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__vOut,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__value,31,0);
    VL_SIG(GTEEngine__DOT__GTERegs_inst__DOT__instLeadCount__DOT__valueI,30,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__divRes,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__specialRGBMulTMP,23,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__valWriteBack32,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__HS3Z,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__vComp,17,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__leftSide,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__rightSide,17,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__HS3Z,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__vComp,17,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__leftSide,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__rightSide,17,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__HS3Z,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__vComp,17,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__leftSide,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__rightSide,17,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__TRX,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__TRY,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__TRZ,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__RBK,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__GBK,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__BBK,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__RFC,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__GFC,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__BFC,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__MAC1,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__MAC2,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__MAC3,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__OF0,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__OF1,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__DQB,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__NCDS_CDP_DPCL_Special,23,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__mulA,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__specialZ0MulZSF4_Hi,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__mac_Hi,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__trV,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__bgV,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__fcV,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__macV,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__of,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__divRes,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__h0,23,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__h1,27,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__h2,29,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__h3,30,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__n,30,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__pn,30,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__mdu1,25,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__dmdu1,25,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__d2,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__mdu2,26,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__dmdu2,19,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__d3,18,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__pd3,18,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__ppn,30,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__outStage4,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipOTZ_inst__DOT__v,20,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipXY_inst__DOT__v,16,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__postSF_v,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSRange__DOT__valueIn,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPositive__DOT__valueIn,31,0);
    VL_SIG(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__myClampSPosCol__DOT__valueIn,27,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outAddSel,43,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outSel1,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outSel2,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outSel3,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outSel1P,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outSel2P,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__outSel3P,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__part1Sum,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__part1SumPostExt,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__part2Sum,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__tempSumREG,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__part2SumPostExt,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__finalSumBeforeExt,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__finalSum,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__outstuff,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit1__DOT__result,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__outstuff,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit2__DOT__result,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__outstuff,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__SelMuxUnit3__DOT__result,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__outstuff,43,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__resMul,32,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__selAddInst__DOT__out,43,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__mnd,49,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__shfm,34,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__GTEFastDiv_Inst__DOT__shcp,33,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local1__DOT__v,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local2__DOT__v,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Local3__DOT__v,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS44Global__DOT__v,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagS32Global__DOT__v,44,0);
    VL_SIG64(GTEEngine__DOT__GTEComputePath_inst__DOT__FlagClipIRnColor_Inst__DOT__i_v44,44,0);
}

int main()
{

#if 0
	//
	// GENERATE MICROCODE
	//
	HWDesignSetup();
	registerInstructions();
	generateMicroCode("..\\rtl\\MicroCode.inl");
#else
	//
	// RUN SIM
	//
	// ------------------------------------------------------------------
	// [Instance of verilated GPU & custom VCD Generator]
	// ------------------------------------------------------------------
	VGTEEngine* mod = new VGTEEngine();
	VCScanner*	pScan = new VCScanner();
				pScan->init(1500,false);

	bool useScan = true;
	int clockCnt = 0;
	int clockCycle = 0;
	if (useScan) {
		registerVerilatedMemberIntoScanner(mod,pScan);
		// BEFORE PLUGIN !
		pScan->addMemberFullPath("CLOCKNUMBER", WIRE, BIN, 32, &clockCycle, -1, 0);

		pScan->addPlugin(new ValueChangeDump_Plugin("gteTiming.vcd"));
	}

	mod->i_nRst = 0;
	for (int n=0; n < 5; n++) {
		mod->i_clk = 0; mod->eval();
		if (useScan) { pScan->eval(clockCnt); }
		clockCnt++;
		mod->i_clk = 1; mod->eval();
		clockCycle++;
		if (useScan) { pScan->eval(clockCnt); }
		clockCnt++;
	}
	mod->i_nRst = 1;
	mod->i_clk = 0; mod->eval();
	if (useScan) { pScan->eval(clockCnt); }
	clockCnt++;

	while (clockCnt < 200) {
		mod->i_clk    = 1;
		clockCycle++;
		mod->eval();
		
		mod->i_WritReg		= 0;
		mod->i_run			= 0;
		mod->i_Instruction	= 0x00;
		mod->i_regID		= 0;

		switch (clockCycle) {
		case 7:
			// Send instruction
			mod->i_run			= 1;
			mod->i_Instruction	= 0x01; //  RTPS 15 Official;
			break;
		case 26:
			// Send instruction
			mod->i_run			= 1;
			mod->i_Instruction	= 0x01; //  RTPS 15 Official;
			break;
		case 33:
			/*
		case 34:
		case 35:
		case 36:
		*/
			if (mod->o_executing == 0) {
				mod->i_run			= 1;
				mod->i_Instruction	= 0x00; //  NOP
			}
			break;
		case 34:
			mod->i_WritReg	= 1;
			mod->i_dataIn	= 0xDEADBEEF;
			mod->i_regID	= 3;
			break;
		case 36:
			mod->i_regID	= 3;
			break;
		case 24:
			mod->i_DIP_USEFASTGTE = 1;
			break;
		}
		// In case we changed inputs...
		mod->eval();

		if (useScan) {
			pScan->eval(clockCnt);
			clockCnt++;
		}


		mod->i_clk = 0;
		mod->eval();
		if (useScan) {
			pScan->eval(clockCnt);
			clockCnt++;
		}
	}

	delete mod;
	pScan->shutdown();
#endif
}
