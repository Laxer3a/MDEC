#include "genericSPU.h"
#include "spu.h"

struct SWSPU : public IGenericSPU {
	// Get pointer to the generic SPU RAM content.
	virtual	uint16_t*	getRAM		();
	
	// CPU Read / Writes to registers
	virtual	void		write16		(uint32_t addr, uint16_t data);
	virtual	void		write32		(uint32_t addr, uint32_t data);
	virtual	uint16_t	read16		(uint32_t addr);
	virtual	uint32_t	read32		(uint32_t addr);

	virtual	bool		isIRQSet	();

	// We push audio input from CD, if CD is not active push 0.
	virtual	void		update		(uint16_t cdAudioInLeft, uint16_t cdAudioRight, uint16_t& leftAudioOut, uint16_t& rightAudioOut);

	// FIFOs
	virtual bool		canDMAWrite	();
	virtual bool		canDMARead	();
	virtual void		DMAWrite	(uint32_t data);
	virtual uint32_t	DMARead		();
	
	spu::SPU swSPU;
};

SWSPU theSWSPU;

IGenericSPU*	getSWModel() { return &theSWSPU; }

// Get pointer to the generic SPU RAM content.
uint16_t*	SWSPU::getRAM		() {
	return (uint16_t*)theSWSPU.swSPU.ram.data;
}

// CPU Read / Writes to registers
void	SWSPU::write16		(uint32_t addr, uint16_t data) {
	theSWSPU.swSPU.write(addr  , data      & 0xFF);
	theSWSPU.swSPU.write(addr+1,(data >> 8)& 0xFF);
}

void	SWSPU::write32		(uint32_t addr, uint32_t data) {
	theSWSPU.swSPU.write(addr  , data       & 0xFF);
	theSWSPU.swSPU.write(addr+1,(data >>  8)& 0xFF);
	theSWSPU.swSPU.write(addr+2,(data >> 16)& 0xFF);
	theSWSPU.swSPU.write(addr+3,(data >> 24)& 0xFF);
}

uint16_t SWSPU::read16		(uint32_t addr) {
	return theSWSPU.swSPU.read(addr) | (theSWSPU.swSPU.read(addr+1)<<8);
}

uint32_t SWSPU::read32		(uint32_t addr) {
	return read16(addr) | (read16(addr+2)<<16);
}

bool	SWSPU::isIRQSet		() {
}

// We push audio input from CD, if CD is not active push 0.
void	SWSPU::update		(uint16_t cdAudioInLeft, uint16_t cdAudioRight, uint16_t& leftAudioOut, uint16_t& rightAudioOut) {
}

// FIFOs
bool	SWSPU::canDMAWrite	() {
	return false;
}

bool	SWSPU::canDMARead	() {
	return false;
}

void	SWSPU::DMAWrite		(uint32_t data) {
}


uint32_t SWSPU::DMARead		() {
	return 0;
}
