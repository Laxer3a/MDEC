/*
	--------------------------------------------------------------------------------------------------------------------
	
	Feature :
	----------------------------------------------------------
	Classes to analyze value changes over time when doing HW Simulation.
	
	Architecture :
	----------------------------------------------------------
	- VCScanner = Main class performing the scan.
		- Assign a plugin.
		- Create a list of data(members) to check by the scanner at each evaluation.
		- Call evaluation function to check the changes.
		
		The scanner registers part of the memory, and can check any content change.
		For now the limitation is :
		- Nested type are not supported.
		- Arrays are not supported.
		- Max length is 64 bit for now.
		
	- VCPlugin  = Class instance able to do work on data change events.
		- Anybody can include their own plugin.
		- Provide ValueChangeDump_Plugin class by default to generate standard VCD file for software like GTKWave.
		

	Library Usage:
	----------------------------------------------------------
	// in multiple places where you are using the header or your own implementation...
	#include <VCScanner.h>
	
	
	// In the file where you want the implementation of VCScanner embedded.
	#define VCSCANNER_IMPL
	#include <VCScanner.h>
	
	
	TODO : Complete doc with example code
	--------------------------------------------------------------------------------------------------------------------
 */
#ifndef _VCSCANNER_H
#define _VCSCANNER_H

// TODO : FIX DATE OUTPUT
// TODO : Support MEMORY TYPE
// TODO : Complete support for hierarchy type.
// Please use VCSCANNER_IMPL before #include "VCScanner.h"
//

// Needed for FILE type.
#include <stdio.h>
// strdup, strlen, strcmp
#include <string.h>

enum VCFORMAT {
	HEXA,
	UINTVC,
	SINT,
	BIN,
	NON_APPLICABLE,
};

enum VCTYPE {
	REG		= 1,
	WIRE	= 2,
	MODULE	= 3, // Not full support yet...
};

typedef unsigned long long	u64;
typedef unsigned int		u32;
typedef unsigned short		u16;
typedef unsigned char		 u8;
typedef int                 s32;
typedef short				s16;

class  VCPlugin;
class  VCScanner;
struct VCMember;

class VCScanner {
	// TODO : have a plugin interface that is called back on changes.
	//        Allow to use directly memory and avoid internal stream on other tool.
public:
	VCScanner	()
	:members(NULL),alloc(NULL),endAlloc(NULL),lastParent(NULL),plugin(NULL),lastTime(-1) {}
	~VCScanner	() { shutdown(); delete[] members; }

	bool init		(int maxmemberCount);
	void shutdown	();

	bool addMember				(const char* name, VCTYPE typeMember, VCFORMAT formatMember, int width, void* memoryLocation, int depth = -1, int strideDepth = 0);
	bool addMemberFullPath		(const char* name, VCTYPE typeMember, VCFORMAT formatMember, int width, void* memoryLocation, int depth = -1, int strideDepth = 0);
	VCMember*	findMemberFullPath(const char* name);
	
	bool pushOwner	(const char* name);
	void popOwner	();

	bool addPlugin	(VCPlugin* plugin);

	void eval		(int timeUnit);

	VCMember*	getTopMember	() { return members; }
protected:
	VCMember*	findParent(const char* name,const char** returnName, bool includeLastAsModule);

	void		eval			(VCMember* item, int timeUnit);
	VCMember*	members;
	VCMember*	alloc;
	VCMember*	endAlloc;
	VCMember*	lastParent;
//	VCMember*	lastItem;
	VCPlugin*	plugin;
	int			lastTime;
	bool		firstValueChange;
};

struct EnumArray {
	int			value;
	const char*	outputString;
};

struct VCMember {
	friend class VCScanner;
public:
	const char*	name;
	const char* fullName;
	VCFORMAT	format;
	VCTYPE		type;
	int			sizeBit;

	VCMember*	findLastChild();


	inline
	VCMember*	getParent	() { return parent; }
	inline
	VCMember*	getChild	() { return child;  }
	inline
	VCMember*	getLastChild() { return lastChild;  }
	inline
	VCMember*	getNext		() { return next;   }
	inline
	VCMember*	getPrev		() { return prev;   }

	inline
	void*		getNewValue	() { return currValuePointer; }

	inline
	void		assignEnum(EnumArray* arraySorted, int lengthArray) {
		sortedArrayEnum = arraySorted;
		sortedArraySize = lengthArray;
	}

	inline
	EnumArray*	getEnum() {
		return sortedArrayEnum;
	}

private:
	VCMember*	next;
	VCMember*	prev;
	VCMember*	parent;
	VCMember*	child;
	VCMember*	lastChild;

	bool        compareOldNew() {
		return memcmp(currValuePointer, oldValuePointer, sizeByte); 
	}
	void		writeToOld	();

	void*		currValuePointer;
	void*		oldValuePointer;
	void*		pluginTag;

	EnumArray*	sortedArrayEnum;
	int			sortedArraySize;

	u64			storeTmp[32];
	u16			sizeByte;
	s16			stride;
	s32			depth;
};

class VCPlugin {
	friend class VCScanner;
public:
	virtual void onStart		(VCScanner* def) = 0;
	virtual void onEnd			() = 0;
	virtual void onTimeChange	(bool hasValueChange, u32 time) = 0;
	virtual	void onValueChange	(VCMember* member, int optIndex = -1) = 0;
private:
	VCPlugin*	next;
};

class ValueChangeDump_Plugin : public VCPlugin {
public:
	ValueChangeDump_Plugin	(const char* fileName);
	~ValueChangeDump_Plugin	();

	void closeFile();
	
	void ParseTree(VCMember* member, bool onCreate_TOrDestroy_F, int depth);

	virtual void onStart		(VCScanner* def);
	virtual void onEnd			();
	virtual void onTimeChange	(bool hasValueChange, u32 time);
	virtual	void onValueChange	(VCMember* member, int optIndex = -1);

	FILE* out;
};

const char* VCScanner_PatchName(const char* originalName);

#define ADD_WIRE(f,p,NAME,s1,s2)	f->addMember( VCScanner_PatchName(#NAME), WIRE, BIN,1,& p ->## NAME );
#define ADD_WIREV(f,p,NAME,size,s2)	f->addMember( VCScanner_PatchName(#NAME), WIRE, BIN,(size+1),& p ->## NAME );

#ifdef VCSCANNER_IMPL

void VCAssert(bool cond, const char* msg) {
	if (!cond) {
		printf("Assert : %s\n", msg);
		printf("(Execute Infinite loop)\n");
		while (1) {
		
		}
	}
}

bool VCScanner::init(int maxmemberCount) {
	if (members == NULL) {
		members = new VCMember[maxmemberCount];
		alloc   = members + 1;
		members[0].child = NULL;
		members[0].lastChild= NULL;
		members[0].name  = "[root]";
		members[0].next  = NULL;
		members[0].prev  = NULL;
		members[0].parent= NULL;
		members[0].type  = MODULE;

		endAlloc= &alloc[maxmemberCount];
	}
	return (members != NULL);
}

void dumpRec(VCMember* list, VCMember* parent, int depth) {
	for (int n=0; n < depth ; n++) {
		printf("  ");
	}

	if (list->type == MODULE) {
		printf("[%s]\n",list->name);
	} else {
		printf("%s\n",list->name);
	}

	VCMember* pC = list->getChild();
	while (pC) {
		dumpRec(pC,list,depth+1);
		pC = pC->getNext();
	}

	if (list->getParent() == NULL) {
		VCMember* pC = list->getNext();
		while (pC) {
			for (int n=0; n < depth ; n++) {
				printf("  ");
			}
			printf("%s(root)\n",pC->name);
			pC = pC->getNext();
		}
	}
}

bool VCScanner::pushOwner	(const char* name) {
	/*
		add child of type module
		lastParent = ...
	 */
	if (lastParent == NULL) {
		lastParent = &members[0];
	}

	// Check if any child already having the same name...
	VCMember* pCList = lastParent->child;
	while (pCList) {
		if (strcmp(pCList->name, name) == 0) {
			lastParent = pCList;
			return pCList;
		}
		pCList = pCList->next;
	}

	bool ok = (alloc < endAlloc);
	if (ok) {
		alloc->name		= strdup(name);
		alloc->fullName = alloc->name;
		alloc->child	= NULL;
		alloc->lastChild= NULL;
		alloc->prev		= NULL;
		alloc->next		= NULL;
		alloc->parent	= lastParent;

		if (lastParent == NULL) {
			lastParent = &members[0];
		} 

		alloc->prev = lastParent->lastChild;
		if (alloc->prev) {
			alloc->prev->next = alloc;
		}
		if (lastParent->child == NULL) {
			lastParent->child = alloc;
		} 
		lastParent->lastChild = alloc;

		lastParent = alloc;

		alloc->sizeBit	= 0;
		alloc->sizeByte	= 0;
		alloc->depth    = -1;

		alloc->format	= NON_APPLICABLE;
		alloc->type		= MODULE;

		alloc->pluginTag= NULL;

		alloc->currValuePointer	= NULL;
		alloc->oldValuePointer	= NULL;
		alloc++;

		return true;
	}

	// printf("---------------------------------\n");
	// dumpRec(this->members, NULL, 0);
	return false;
}

void VCScanner::popOwner	() {
	if (lastParent) {
		lastParent = lastParent->parent;
	}
}

u32 closestPow2(u32 v) {
	v--;
	v |= v >> 1;
	v |= v >> 2;
	v |= v >> 4;
	v |= v >> 8;
	v |= v >> 16;
	v++;
	return v;
}

const char* VCScanner_PatchName(const char* originalName) {
	char* res;
	char* dst = res = strdup(originalName);
	while (*dst) {
		if (strncmp(originalName, "__DOT__",7) != 0) {
			*dst++ = *originalName++;
		} else {
			*dst++ = '.';
			originalName += 7;
		}
	}
	*dst++ = 0;

	return res;
}

VCMember* VCScanner::findParent(const char* name, const char** returnName, bool includeLastAsModule) {
	char tmpBuff[512];
	const char* currName = name;

	*returnName = currName;

	while (*currName != 0) {
		char* wrB = tmpBuff;

		// Split
		while (*currName != 0 && *currName !='.') {
			*wrB++ = *currName++;
		}

		if (*currName == '.' || includeLastAsModule) {
			*wrB++ = 0;
			if (*currName == '.') {
				currName++;
			}
			*returnName = currName;
			pushOwner(tmpBuff);
		}
	}
	return lastParent;
}

bool VCScanner::addMemberFullPath(const char* name, VCTYPE typeMember, VCFORMAT formatMember, int width, void* memoryLocation, int depth, int strideDepth) {
	lastParent = NULL;
	return addMember(name, typeMember, formatMember, width, memoryLocation, depth, strideDepth);
}

VCMember* VCScanner::findMemberFullPath(const char* name) {
	VCMember* parse = &members[0];
	char buffer[2000]; // tmp work.
	int lenChunk = 0;
	const char* parseN = name;

	while ((parseN[lenChunk] != '.') && (parseN[lenChunk] != 0)) { lenChunk++; }

	parse = parse->getChild();

again:
	while (parse && ((strncmp(parse->name,parseN,lenChunk) != 0) || (strlen(parse->name)!=lenChunk))) {
		parse = parse->getNext();
	}

	if (parse == NULL) {
		return NULL; // Not found
	} else {
		if (parseN[lenChunk] == 0) {
			return parse;
		} else {
			parse = parse->getChild();
			parseN += lenChunk+1; // next chunk;
			lenChunk = 0;
			while ((parseN[lenChunk] != '.') && (parseN[lenChunk] != 0)) { lenChunk++; }

			goto again;
		}
	}
}


bool VCScanner::addMember	(const char* name, VCTYPE typeMember, VCFORMAT formatMember, int width, void* memoryLocation, int depth, int strideDepth) {
	bool ok = (alloc < endAlloc);
	if (ok) {
		// BEFORE BECAUSE IT WILL ALLOCATE TOO.
		const char* resultName;
		VCMember* parent = findParent(name, &resultName, depth > 0);
		if (parent == NULL) {
			parent = &members[0];
		}
		// Single entry for non array stuff...
		bool isArray = depth >= 0;

		if (depth <= 0) { depth = 1; }

		char tmpBuffer[256];
		char tmpBuffer2[2048];

		for (int n=0; n < depth; n++) {
			if (isArray) {
				sprintf(tmpBuffer,"%s_%i",parent->name,n);
				sprintf(tmpBuffer2,"%s_%i",name,n);
			}
			alloc->name		= isArray ? strdup(tmpBuffer) : resultName;
			alloc->fullName	= isArray ? strdup(tmpBuffer2) : name;
		
			alloc->child	= NULL;
			alloc->lastChild = NULL;

			alloc->prev		= NULL;
			alloc->next		= NULL;
			
			alloc->assignEnum(NULL,0);

			alloc->parent	= parent;

			if (parent) {
				alloc->prev = parent->lastChild;
				if (parent->lastChild) {
					parent->lastChild->next = alloc;
				}
				if (parent->child == NULL) {
					parent->child = alloc;
				}
				parent->lastChild = alloc;
			}

			VCAssert(width <= (64*32), "BIGGER THAN 64*32 BIT NOT SUPPORTED"); // Not yet supported.

			alloc->sizeBit	= width;
			int byteSize = (width + 7) >> 3;
			alloc->sizeByte	= ((byteSize + 3)>>2)<<2; // rounded to 32 bit block.
			alloc->depth    = depth;

			alloc->format	= formatMember;
			alloc->type		= typeMember;

			alloc->pluginTag= NULL;

			alloc->currValuePointer	= ((u8*)memoryLocation) + (strideDepth * n);
			alloc->oldValuePointer	= alloc->storeTmp;

			alloc++;

//			printf("---------------------------------\n");
//			dumpRec(this->members, NULL, 0);
		}
	}
	return ok;
}

bool VCScanner::addPlugin	(VCPlugin* plugin_) {
	plugin_->next = plugin;
	plugin = plugin_;
	if (plugin) { plugin->onStart(this); }
	return true;
}

void VCScanner::shutdown	() {
	if (plugin) { plugin->onEnd(); }
	plugin = NULL;
}

VCMember*	VCMember::findLastChild() {
	VCMember* pC = this->getLastChild();
	return pC;
}

/*
u64			VCMember::read(void* ptr) {
	switch (sizeByte) {
	case 1:	return *((u8*)ptr);
	case 2: return *((u16*)ptr);
	case 4: return *((u32*)ptr);
	case 8: return *((u64*)ptr);
	}
	return -1LL;
}
*/

void		VCMember::writeToOld() {
	memcpy(oldValuePointer,this->currValuePointer,sizeByte);
	/*
	switch (sizeByte) {
	case 1:	*((u8*)oldValuePointer)  = (u8)v;
	case 2: *((u16*)oldValuePointer) = (u16)v;
	case 4: *((u32*)oldValuePointer) = (u32)v;
	case 8: *((u64*)oldValuePointer) = v;
	}
	*/
}

void VCScanner::eval		(int timeUnit) {
	if (lastTime != timeUnit) {
		lastTime = timeUnit;
		firstValueChange = true;
		if (plugin) { plugin->onTimeChange(false, timeUnit); }
		eval(members, timeUnit);
	}
}

void VCScanner::eval		(VCMember* item, int timeUnit) {
	VCMember* sp = item;

	while (sp) {
		if (sp->type == MODULE) {
			eval(sp->child, timeUnit);
		} else {
			if (sp->compareOldNew()) {
				if (firstValueChange) {
					firstValueChange = false;
					plugin->onTimeChange(true,timeUnit);
				}
				plugin->onValueChange(sp);
				sp->writeToOld();
			}
		}
		sp = sp->next;
	}
}

ValueChangeDump_Plugin::ValueChangeDump_Plugin(const char* fileName) {
	out = fopen(fileName,"wb");
}

ValueChangeDump_Plugin::~ValueChangeDump_Plugin	() {
	if (out) {
		fclose(out);
		out = NULL;
	}
}

const char* getVCDSym(VCMember* member) {
	return member->fullName;
}

// TODO move into scheme...
void ValueChangeDump_Plugin::ParseTree(VCMember* member,bool onCreate_TOrDestroy_F, int depth) {
	while (member) {
		if (onCreate_TOrDestroy_F) {
			// On Create
			switch (member->type) {
			case MODULE:
			{
				if (strcmp(member->name,"[root]")!=0) {
					for (int n=0; n < depth; n++) { fprintf(out,"\t"); }
					fprintf(out,"$scope module %s $end\n",member->name);
				}
				ParseTree(member->getChild(),onCreate_TOrDestroy_F, depth + 1);
				if (strcmp(member->name,"[root]")!=0) {
					for (int n=0; n < depth; n++) { fprintf(out,"\t"); }
					fprintf(out,"$upscope $end\n");
				}
			}
			break;
			case WIRE:
			case REG:
			{
				const char* typeStr = ((member->type == WIRE) ? "wire" : "reg");
				for (int n=0; n < depth; n++) { fprintf(out,"\t"); }
				if (member->sizeBit == 1) {
					fprintf(out,"$var %s %i %s %s $end\n", typeStr, member->sizeBit, getVCDSym(member), member->name);
				} else {
					fprintf(out,"$var %s %i %s %s [%i:0] $end\n", typeStr, member->sizeBit, getVCDSym(member), member->name, member->sizeBit-1);
				}
				if (member->getEnum()) {
					fprintf(out,"$var real 0 %s_enum %s_enum $end\n", getVCDSym(member), member->name);
				}
			}
			break;
			}
		} else {
			// On Destroy
		}

		member = member->getNext();
	}
}

/*virtual*/ void ValueChangeDump_Plugin::onStart		(VCScanner* def) {
	fprintf(out,"$date\n");
	fprintf(out,"\tSun Sep 08 02:57:45 2019\n"); // TODO FIX DATE
	fprintf(out,"$end\n");
	fprintf(out,"$version\n");
	fprintf(out,"\tLaxer3A VCD\n");
	fprintf(out,"$end\n");
	fprintf(out,"$timescale\n");
	fprintf(out,"\t1 ns\n");
	fprintf(out,"$end\n");

	ParseTree(def->getTopMember(), true, 0);
}

/*virtual*/ void ValueChangeDump_Plugin::onEnd			() {
	if (out) {
		fclose(out);
		out = NULL;
	}
}

/*virtual*/ void ValueChangeDump_Plugin::onTimeChange	(bool hasValueChange, u32 time) {
	if (hasValueChange) {
		fprintf(out,"#%i\n",time);
	}
}

const char* ToBin(char* input, void* pVal, u32 bitCount) {
	u32* pVal32 = (u32*)pVal;
	char* out = input;
	u32 b32Cnt = ((bitCount+31) >> 5);

	u32 currBitCnt = bitCount;

	if (bitCount > 32) {
		int sizeCnt = bitCount % 32;
		if (sizeCnt == 0) { sizeCnt = 32; }

		for (int m=0; m < b32Cnt; m++) {
			u32 v = pVal32[(b32Cnt-1) - m];
			for (int n=sizeCnt-1; n >= 0; n--) { *input++ = (v & ((1LL)<<n)) ? '1' : '0'; }
			currBitCnt -= sizeCnt;
			sizeCnt     = 32;
		}
	} else {
		u32 v;
		switch ((bitCount+7)>>3) {
		case 1:
		case 0: v = *((u8*)pVal); break;
		case 2: v = *((u16*)pVal); break;
		case 3: 
		case 4: v = *((u32*)pVal); break;
		default: v = -1; break;
		}

		int sizeCnt = currBitCnt;
		for (int n=sizeCnt-1; n >= 0; n--) {
			*input++ = (v & ((1LL)<<n)) ? '1' : '0';
		}
	}
	*input = 0;
	return out;
}

/*virtual*/	void ValueChangeDump_Plugin::onValueChange	(VCMember* member, int optIndex) {
	char buffer[20000];

	if (member->sizeBit == 1) {
		fprintf(out,"%i%s\n", (int)(*((u8*)member->getNewValue())) ,getVCDSym(member));
	} else {
		fprintf(out,"b%s %s\n", ToBin(buffer,member->getNewValue(),member->sizeBit) ,getVCDSym(member));
		EnumArray* pEnum = member->getEnum();
		if (pEnum) {
			fprintf(out,"s%s %s_enum\n", pEnum[(int)(*((u8*)member->getNewValue()))].outputString ,getVCDSym(member));
		}
	}
}

#endif	// End implementation
#endif	// End Header
