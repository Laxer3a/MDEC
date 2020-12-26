// CDRomInternal.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <iostream>
#include "externalWorld.h"

void compareRead(u8 adr, u8 resExpect) {
	u8 v = CDROM_Read(adr);
	if (v != resExpect) {
		printf("ERROR Got:%x Expect:%x\n", v,resExpect);
	}
}

int main()
{
	initExternalWorld	(); // Registers/FIFO simulation of HW
	InitPorting			(); // Fake signals, Closed drive default.
	InitFirmware		();	// Firmware internal variables.

	CDROM_Write(0, 0x01);
	CDROM_Write(3, 0x1f);
	//CDROM:W INTF: 0x1f
	CDROM_Write(0, 0x01);
	CDROM_Write(2, 0x1f);
	//CDROM:W INTE: 0x1f
	compareRead(0, 0x19);
	//CDROM:R STATUS: 0x19
	CDROM_Write(0, 0x01);
	CDROM_Write(3, 0x40);
	//CDROM:W INTF: 0x40
	CDROM_Write(0, 0x00);
	CDROM_Write(2, 0x20);
	CDROM_Write(1, 0x19);
	//CDROM: cmdTest(0x20) -> (0x94, 0x09, 0x19, 0xc0)
	compareRead(0, 0x38);

	EvaluateFirmware();

	//CDROM:R STATUS: 0x38
	CDROM_Write(0, 0x01);
	compareRead(3, 0xe3);
	//CDROM:R INTF: 0xe3
	compareRead(1, 0x95);
	//CDROM:R RESPONSE: 0x94
	compareRead(1, 0x05);
	//CDROM:R RESPONSE: 0x09
	compareRead(1, 0x16);
	//CDROM:R RESPONSE: 0x19
	compareRead(1, 0xc1);
	//CDROM:R RESPONSE: 0xc0

	CDROM_Write(0, 0x01);
	CDROM_Write(3, 0x07);
	//CDROM:W INTF: 0x07
	CDROM_Write(0, 0x00);
	compareRead(0, 0x18);
	//CDROM:R STATUS: 0x18
	CDROM_Write(0, 0x01);
	compareRead(3, 0xe0);
	//CDROM:R INTF: 0xe0
	CDROM_Write(0, 0x01);
	CDROM_Write(3, 0x07);
	//CDROM:W INTF: 0x07
	CDROM_Write(0, 0x00);
//	System Controller ROM Version 94/09/19 c0
	CDROM_Write(0, 0x01);
	CDROM_Write(3, 0x40);
	//CDROM:W INTF: 0x40
	CDROM_Write(0, 0x00);
	CDROM_Write(1, 0x01);
////	CDROM: cmdGetstat -> 0x02

	EvaluateFirmware();


    std::cout << "Hello World!\n";
}

// Run program: Ctrl + F5 or Debug > Start Without Debugging menu
// Debug program: F5 or Debug > Start Debugging menu

// Tips for Getting Started: 
//   1. Use the Solution Explorer window to add/manage files
//   2. Use the Team Explorer window to connect to source control
//   3. Use the Output window to see build output and other messages
//   4. Use the Error List window to view errors
//   5. Go to Project > Add New Item to create new code files, or Project > Add Existing Item to add existing code files to the project
//   6. In the future, to open this project again, go to File > Open > Project and select the .sln file
