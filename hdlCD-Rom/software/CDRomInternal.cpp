// CDRomInternal.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <iostream>
#include "externalWorld.h"

void compareRead(u8 adr, u8 resExpect) {
	u8 v = CDROM_Read(adr);
	if (v != resExpect) {
		printf("ERROR\n");
	}
}
int main()
{
	initExternalWorld();

	CDROM_Write(0,0x01);
	CDROM_Write(3,0x1F);
	CDROM_Write(0,0x01);
	CDROM_Write(2,0x1F);

	compareRead(0,0x19);

	CDROM_Write(0,0x01);
	CDROM_Write(3,0x40);
	CDROM_Write(0,0x00);
	CDROM_Write(2,0x20);
	CDROM_Write(1,0x19);

	compareRead(0,0x38);

	CDROM_Write(0,0x01);
	compareRead(3,0xE3);
	compareRead(1,0x94);
	compareRead(1,0x09);
	compareRead(1,0x19);
	compareRead(1,0xC0);


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
