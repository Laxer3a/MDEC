#include "genericSPU.h"
#include "spu.h"

struct SWSPU : public IGenericSPU {
	SWSPU() {}

	// Get pointer to the generic SPU RAM content.
	virtual	uint16_t*	getRAM		();

	virtual void		setCycle	(int c0to767);
	
	// CPU Read / Writes to registers
	virtual	void		write16		(uint32_t addr, uint16_t data);
	virtual	void		write32		(uint32_t addr, uint32_t data);
	virtual	uint16_t	read16		(uint32_t addr);
	virtual	uint32_t	read32		(uint32_t addr);

	virtual	bool		isIRQSet	();

	// We push audio input from CD, if CD is not active push 0.
	virtual	void		update		(int16_t cdAudioInLeft, int16_t cdAudioRight, int16_t& leftAudioOut, int16_t& rightAudioOut);

	// FIFOs
	virtual bool		canDMAWrite	();
	virtual bool		canDMARead	();
	virtual void		DMAWrite	(uint32_t data);
	virtual uint32_t	DMARead		();
	
	spu::SPU	swSPUReadWrite;
	spu::SPU	swSPU;
	spu::CDRom	cdRom;
	int			time;

	spu::FIFO	outDMAFIFO;
	spu::FIFO	inDMAFIFO;

	struct WriteRec {
		int			cycle;
		uint32_t	value;
		uint32_t	addr;
	};
	WriteRec writeRecords[768*2];
	int writeRecordCount;
};

SWSPU theSWSPU;

IGenericSPU*	getSWModel() { return &theSWSPU; }

// Get pointer to the generic SPU RAM content.
uint16_t*	SWSPU::getRAM		() {
	return (uint16_t*)(swSPU.ram.data());
}

void SWSPU::setCycle(int c0to767) {
	time = c0to767;
}

// CPU Read / Writes to registers
void	SWSPU::write16		(uint32_t addr, uint16_t data) {
	swSPUReadWrite.write(addr  , data      & 0xFF);
	swSPUReadWrite.write(addr+1,(data >> 8)& 0xFF);

	writeRecords[writeRecordCount].cycle = time;
	writeRecords[writeRecordCount].addr  = addr;
	writeRecords[writeRecordCount].value = data;
	writeRecordCount++;		
}

void	SWSPU::write32		(uint32_t addr, uint32_t data) {
	write16(addr  ,       data & 0xFFFF);
	write16(addr+2, (data>>16) & 0xFFFF);
}

uint16_t SWSPU::read16		(uint32_t addr) {
	return swSPUReadWrite.read(addr) | (swSPU.read(addr+1)<<8);
}

uint32_t SWSPU::read32		(uint32_t addr) {
	return read16(addr) | (read16(addr+2)<<16);
}

bool	SWSPU::isIRQSet		() {
	return swSPU.status.irqFlag ? true : false;
}

// We push audio input from CD, if CD is not active push 0.
void	SWSPU::update		(int16_t cdAudioInLeft, int16_t cdAudioRight, int16_t& leftAudioOut, int16_t& rightAudioOut) {
	cdRom.pushLeft	(cdAudioInLeft);
	cdRom.pushRight	(cdAudioRight);

	Sample l,r;
	swSPU.step(&cdRom,l,r);
	leftAudioOut  = l.value;
	rightAudioOut = r.value;

	time				= 0;
	writeRecordCount	= 0;
}

// FIFOs
bool	SWSPU::canDMAWrite	() {
	return !inDMAFIFO.isFull();
}

bool	SWSPU::canDMARead	() {
	return !outDMAFIFO.isEmpty();
}

void	SWSPU::DMAWrite(uint32_t data) {
	inDMAFIFO.push(data);
}

uint32_t SWSPU::DMARead		() {
	return outDMAFIFO.pop();
}
