# PSX Reimplementation in FPGA
Attempt to do a verilog Implementation of chips in the Playstation 1 (PSX)

As of now the following chips are being remade :
- MDEC (Block decompression for full motion video)
  * TODO Remaining : Validation of pixel packing in FIFO, validation of FIFOs under backpressure.
- GPU  (Graphic processor, doing all the rendering and display (seperated modules))
  * TODO Remaining : Display side support (rendering is done, but scanning buffer for display is not)
  * TODO Remaining : Some more tests ? For now some warnings request checking.
- SPU  (Audio chip)
  * TODO Remaining : CPU Read from SPU.
  * TODO Remaining : Command to read SPU RAM content from CPU/DMA.
- GTE  (Internal extension of the instruction set of the CPU to do 3D computations)
  * DONE. Only a single instruction takes ONE more cycle than original specs.

All the modules worked in simulation using verilator but GPU and GTE only have been fully validated / tested.
Those 4 systems are working, but MDEC and SPU are not ready for integration fully. 
(Be prepared to look at the waves and fix protocols)

All the test software, dev software is as-is.
I used Visual C++ to run the thing, all the path are probably hard coded to my computer in solution files.
So you have been warned.
