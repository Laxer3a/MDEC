module IRQModule (
	input			clk,
	input			nRst,
	input			selInterruptReg,
	input			adrInterruptReg2,	// +0/+4.
	input			write,
	input	[15:0]	valueW,
	output	[15:0]	valueR,
	
	input			IRQ0_GPU_VBL,
	input			IRQ1_GPU_COMMAND,
	input			IRQ2_CDROM,
	input			IRQ3_DMA,
	input			IRQ4_TIMER0,
	input			IRQ5_TIMER1,
	input			IRQ6_TIMER2,
	input			IRQ7_CTRLLER_MEMCARD,
	input			IRQ8_SIO,
	input			IRQ9_SPU,
	input			IRQ10_CONTROLLER_LIGHTPEN, // PIO too ?
	
	output			cop0r13_bit10
);
	// --------------------------------------------
	// Read Side, always return the value.
	// --------------------------------------------
	assign valueR = { 5'd0 , adrInterruptReg2 ? mask : state };

	// --------------------------------------------
	// Detection of Edge Transition and valid flag for update.
	// --------------------------------------------
	
	wire GPU_VBL_CrossDomain;
	SigXDomain sigVBLXClockDomain(
		.clkOut	(clk),
		.in		(IRQ0_GPU_VBL),
		.out	(GPU_VBL_CrossDomain)
	);
	
	reg [10:0] prevIRQIn;
	wire [10:0] currIRQIn = {	
						IRQ10_CONTROLLER_LIGHTPEN,		// Bit 10
						IRQ9_SPU,						// ...
						IRQ8_SIO,
						IRQ7_CTRLLER_MEMCARD,
						IRQ6_TIMER2,
						IRQ5_TIMER1,
						IRQ4_TIMER0,
						IRQ3_DMA,						// ...
						IRQ2_CDROM,						// Bit 2
						IRQ1_GPU_COMMAND,				// Bit 1
						GPU_VBL_CrossDomain				// Bit 0
					};
	always @(posedge clk)
	begin
		prevIRQIn = currIRQIn;
	end
	wire [10:0] setIRQ;
	// Edge trigger, upfront and Enabled => Update flag is TRUE.
	assign setIRQ[0 ] = (prevIRQIn[ 0] != currIRQIn[ 0]	) & currIRQIn[ 0] & mask[ 0];
	assign setIRQ[1 ] = (prevIRQIn[ 1] != currIRQIn[ 1]	) & currIRQIn[ 1] & mask[ 1];
	assign setIRQ[2 ] = (prevIRQIn[ 2] != currIRQIn[ 2]	) & currIRQIn[ 2] & mask[ 2];
	assign setIRQ[3 ] = (prevIRQIn[ 3] != currIRQIn[ 3]	) & currIRQIn[ 3] & mask[ 3];
	assign setIRQ[4 ] = (prevIRQIn[ 4] != currIRQIn[ 4]	) & currIRQIn[ 4] & mask[ 4];
	assign setIRQ[5 ] = (prevIRQIn[ 5] != currIRQIn[ 5]	) &	currIRQIn[ 5] & mask[ 5];
	assign setIRQ[6 ] = (prevIRQIn[ 6] != currIRQIn[ 6]	) & currIRQIn[ 6] & mask[ 6];
	assign setIRQ[7 ] = (prevIRQIn[ 7] != currIRQIn[ 7]	) & currIRQIn[ 7] & mask[ 7];
	assign setIRQ[8 ] = (prevIRQIn[ 8] != currIRQIn[ 8]	) & currIRQIn[ 8] & mask[ 8];
	assign setIRQ[9 ] = (prevIRQIn[ 9] != currIRQIn[ 9]	) & currIRQIn[ 9] & mask[ 9];
	assign setIRQ[10] = (prevIRQIn[10] != currIRQIn[10]	) & currIRQIn[10] & mask[10];
	
	// --------------------------------------------
	// Write Side and update.
	// --------------------------------------------
	reg [10:0] mask;
	reg [10:0] state;
	always @(posedge clk)
	begin
		if (nRst == 1'b0) begin
			mask 	= 11'b111_1111_1111;
			state	= 11'b000_0000_0000;
		end else begin
			// What if CPU update flag at the SAME cycle as incoming IRQ ?
			// For now we give priority to the IRQ to override.
			if (write & selInterruptReg) begin
				if (adrInterruptReg2) begin
					mask = valueW[10:0];
				end else begin
					state = state & valueW[10:0]; // ACK WRITE
				end
			end
			
			// Priority to external IRQ hardware over CPU state setup.
			if (setIRQ[0 ])	begin state[ 0] = 1'b1; end
			if (setIRQ[1 ])	begin state[ 1] = 1'b1; end
			if (setIRQ[2 ])	begin state[ 2] = 1'b1; end
			if (setIRQ[3 ])	begin state[ 3] = 1'b1; end
			if (setIRQ[4 ])	begin state[ 4] = 1'b1; end
			if (setIRQ[5 ])	begin state[ 5] = 1'b1; end
			if (setIRQ[6 ])	begin state[ 6] = 1'b1; end
			if (setIRQ[7 ])	begin state[ 7] = 1'b1; end
			if (setIRQ[8 ])	begin state[ 8] = 1'b1; end
			if (setIRQ[9 ])	begin state[ 9] = 1'b1; end
			if (setIRQ[10])	begin state[10] = 1'b1; end
		end
	end
	
	// Send only FLAG to the CPU => Warns of NEW IRQ only.
	assign cop0r13_bit10 = |setIRQ;
endmodule
