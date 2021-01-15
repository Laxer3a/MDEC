/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright © 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */


typedef enum bit[1:0] {
	ACCESS_8BIT			= 2'd0,
	ACCESS_16BIT		= 2'd1,
	ACCESS_32BIT		= 2'd2,
	ACCESS_UNDEF		= 2'd3
} ACCESSWIDTH;

module JOY_IO(
	//--------------------------------------
	// CPU Side
	//--------------------------------------
	input				i_clk,
	input				i_nRst,

	input				i_CS,
	input	ACCESSWIDTH	i_format,
	input	[3:0]		i_addr16BitByte,
	input				i_readSig,
	input				i_writeSig,

	input	[31:0]		i_dataIn,
	output	[31:0]		o_dataOut,
	
	output				o_INT7,

	//--------------------------------------
	// Device side
	//--------------------------------------

	// Joystick 0
	output	[7:0]		emitData0J,
	output				emit0J,
	input	[7:0]		receiveData0J,
	input				receive0J,
	
	// Memcard 0	
	output	[7:0]		emitData0C,
	output				emit0C,
	input	[7:0]		receiveData0C,
	input				receive0C,
	
	// Joystick 1	
	output	[7:0]		emitData1J,
	output				emit1J,
	input	[7:0]		receiveData1J,
	input				receive1J,
	
	// Memcard 1	
	output	[7:0]		emitData1C,
	output				emit1C,
	input	[7:0]		receiveData1C,
	input				receive1C
);

// Detect unsupported register adressing format/mode
reg	BAD_ACCESS;

// 1F80104x as 8 bit forbidden except 1F801040
// 1F801042(16 bit) forbidden
// 1F801046(16 bit) forbidden
// 1F801048(32 bit) forbidden
// 1F80104C(32 bit) forbidden
wire assertBadAccess = i_CS & (
							(i_addr16BitWord == 3'h1) || 
							(i_addr16BitWord == 3'h3) || 
							(((i_addr16BitWord == 3'h4) || (i_addr16BitWord == 3'h6)) && (i_format == ACCESS_32BIT)) || 
							((i_addr16BitByte != 4'd0) && i_format == ACCESS_8BIT));

//----------------------------------------------------------
//
//----------------------------------------------------------
typedef enum bit[1:0] {
	DEVICE_UNSELECTED	= 2'd0,
	DEVICE_CONTROLLER	= 2'd1,
	DEVICE_MEMORYCARD	= 2'd2,
	DEVICE_IMPOSSIBLE	= 2'd3
} DEVICESEL;

/* 1F801040h JOY_TX_DATA (W)
	0-7   Data to be sent
	Writing to this register starts the transfer (if, or as soon as TXEN=1 and (TX Ready Flag 2)JOY_STAT.2=Ready), 
	the written value is sent to the controller or memory card, and, simultaneously, a byte is received 
	(and stored in RX FIFO if JOY_CTRL.1 or JOY_CTRL.2 is set).

	The "TXEN=1" condition is a bit more complex: Writing to SIO_TX_DATA latches the current TXEN value, 
	and the transfer DOES start if the current TXEN value OR the latched TXEN value is set 
	(ie. if TXEN gets cleared after writing to SIO_TX_DATA, then the transfer may STILL start if the old latched TXEN value was set). */	
	
typedef struct packed { // 24 bit
	logic [7:0] RX_DATA0;
	logic [7:0] RX_DATA1;
	logic [7:0] RX_DATA2;
	logic [7:0] RX_DATA3;
} SReceivedData;

/*	1F801044h JOY_STAT (R)
  0     TX Ready Flag 1   (1=Ready/Started)
  1     RX FIFO Not Empty (0=Empty, 1=Not Empty)
  2     TX Ready Flag 2   (1=Ready/Finished)
  3     RX Parity Error   (0=No, 1=Error; Wrong Parity, when enabled)  (sticky)
  4     Unknown (zero)    (unlike SIO, this isn't RX FIFO Overrun flag)
  5     Unknown (zero)    (for SIO this would be RX Bad Stop Bit)
  6     Unknown (zero)    (for SIO this would be RX Input Level AFTER Stop bit)
  7     /ACK Input Level  (0=High, 1=Low)
  8     Unknown (zero)    (for SIO this would be CTS Input Level)
  9     Interrupt Request (0=None, 1=IRQ7) (See JOY_CTRL.Bit4,10-12)   (sticky)	-> RESET BY
  10    Unknown (always zero)
  11-31 Baudrate Timer    (21bit timer, decrementing at 33MHz) */

typedef struct packed {
	logic	TX_READY;
	logic	RX_PENDING;
	logic	TX_FINISHED;
	logic	RX_PARITYERROR;
	// 3 bit pad
	logic	ACK;
	// 1 bit pad
	logic	IRQ;
	// 1 bit pad
	logic	[20:0]	BAUDTIMER;
} SStatus;

/* 1F801048h JOY_MODE (R/W) (usually 000Dh, ie. 8bit, no parity, MUL1)
  0-1   Baudrate Reload Factor (1=MUL1, 2=MUL16, 3=MUL64) (or 0=MUL1, too)
  2-3   Character Length       (0=5bits, 1=6bits, 2=7bits, 3=8bits)
  4     Parity Enable          (0=No, 1=Enable)
  5     Parity Type            (0=Even, 1=Odd) (seems to be vice-versa...?)
  6-7   Unknown (always zero)
  8     CLK Output Polarity    (0=Normal:High=Idle, 1=Inverse:Low=Idle)
  9-15  Unknown (always zero) */
typedef struct packed {
	logic	[1:0]	REG_BAUDRATE_RELOAD_FACT;
	logic 	[1:0]	REG_CHARACTER_LENGTH;
	logic			REG_PARITY_ENABLE;
	logic			REG_PARITY_ODD;
	logic			REG_CLK_OUTPOLARITY;
} SMode;

/* 1F80104Ah JOY_CTRL (R/W) (usually 1003h,3003h,0000h)
  0     TX Enable (TXEN)  (0=Disable, 1=Enable)
  1     /JOYn Output      (0=High, 1=Low/Select) (/JOYn as defined in Bit13)
  2     RX Enable (RXEN)  (0=Normal, when /JOYn=Low, 1=Force Enable Once)
  3     Unknown? (read/write-able) (for SIO, this would be TX Output Level)
  4     Acknowledge       (0=No change, 1=Reset JOY_STAT.Bits 3,9)          (W)
  5     Unknown? (read/write-able) (for SIO, this would be RTS Output Level)
  6     Reset             (0=No change, 1=Reset most JOY_registers to zero) (W)
  7     Not used             (always zero) (unlike SIO, no matter of FACTOR)
  8-9   RX Interrupt Mode    (0..3 = IRQ when RX FIFO contains 1,2,4,8 bytes)
  10    TX Interrupt Enable  (0=Disable, 1=Enable) ;when JOY_STAT.0-or-2 ;Ready
  11    RX Interrupt Enable  (0=Disable, 1=Enable) ;when N bytes in RX FIFO
  12    ACK Interrupt Enable (0=Disable, 1=Enable) ;when JOY_STAT.7  ;/ACK=LOW
  13    Desired Slot Number  (0=/JOY1, 1=/JOY2) (set to LOW when Bit1=1)
  14-15 Not used             (always zero) */
typedef struct packed {
	logic			REG_TX_ENABLE;		// Bit 0
	logic			REG_SELECT;			// Bit 1
	logic			REG_RX_ENABLE;		// Bit 2
	logic			REG_CTRL_BIT3;		// Bit 3
	// logic		REG_ACKNOWLEDGE;	// Bit 4 Write only
	logic			REG_CTRL_BIT5;		// Bit 5
	// logic		REG_RESET;			// Bit 6 Write only
	// 7 : Always 0.
	logic	[1:0]	REG_RX_INT_MODE;	// Bit [9:8]
	logic 			REG_TX_INT_ENABLE;	// Bit 10
	logic 			REG_RX_INT_ENABLE;	// Bit 11
	logic			REG_ACK_INT_ENABLE;	// Bit 12
	logic			REG_ACTIVESLOT_NUM;	// Bit 13
} SCtrl;

/* 1F80104Eh JOY_BAUD (R/W) (usually 0088h, ie. circa 250kHz, when Factor=MUL1)
  0-15  Baudrate Reload value for decrementing Baudrate Timer

	Timer reload occurs when writing to this register, and, automatically when the Baudrate Timer reaches zero. 
	Upon reload, the 16bit Reload value is multiplied by the Baudrate Factor (see 1F801048h.Bit0-1), divided by 2, 
	and then copied to the 21bit Baudrate Timer (1F801044h.Bit11-31). 
	The 21bit timer decreases at 33MHz, and, it ellapses twice per bit (once for CLK=LOW and once for CLK=HIGH).

  BitsPerSecond = (44100Hz*300h) / MIN(((Reload*Factor) AND NOT 1),1)

	The default BAUD value is 0088h (equivalent to 44h cpu cycles), and default factor is MUL1, 
	so CLK pulses are 44h cpu cycles LOW, and 44h cpu cycles HIGH, giving it a transfer rate of circa 250kHz per bit (33MHz divided by 88h cycles).
	Note: The Baudrate Timer is always running; even if there's no transfer in progress.
*/
reg	[15:0]	REG_BAUDRATE_RELOAD;

SReceivedData 	reg_receivedData;
SStatus			reg_status;
SMode			reg_mode;
SCtrl			reg_ctrl;

DEVICESEL		PERIPH_TYPE;

wire [2:0] i_addr16BitWord = i_addr16BitByte[3:1];

// TODO use also this signal to reset state of controllers/card...
wire writeInternal   = i_CS & i_writeSig;
wire writeCtrl       = writeInternal && (i_addr16BitWord == 3'h5);

wire resetPeripheral = writeCtrl     && (!i_dataIn[1]); // incoming control.select
wire resetACK        = writeCtrl     && ( i_dataIn[4]); // input ctrl.acknowledge bit set to 1
wire resetBySetup    = writeCtrl     && ( i_dataIn[6]); // 

//------------------------------------------------------------------------
// CLOCKED PART :
// - CPU Write
// - Internal updates
//------------------------------------------------------------------------

always @(posedge i_clk) begin
	if ((i_nRst == 1'd0) || resetBySetup) begin
		// +4 Status
		reg_status.TX_READY			<= 1'b1; 			// TRUE HERE BY DEFAULT, NEVER SET TO ZERO
		reg_status.RX_PENDING		<= 1'b0;			// TODO
		reg_status.TX_FINISHED		<= 1'b0;			// TODO Set to True after receiving...
		reg_status.RX_PARITYERROR	<= 1'b0;			// UNUSED
		reg_status.ACK				<= 1'b0;			// TODO Set to True (::step)
		reg_status.IRQ				<= 1'b0;			// TODO Set to True (::step), false (resetACK)
		reg_status.BAUDTIMER		<= 21'd0;			// UNUSED ????
		
		// +8 Mode
		reg_mode.REG_BAUDRATE_RELOAD_FACT	<= 2'b0;
		reg_mode.REG_CHARACTER_LENGTH		<= 2'b0;	// UNUSED
		reg_mode.REG_PARITY_ENABLE			<= 1'b0;	// UNUSED
		reg_mode.REG_PARITY_ODD				<= 1'b0;	// UNUSED
		reg_mode.REG_CLK_OUTPOLARITY		<= 1'b0;	// UNUSED
		
		// +10 Ctrl
		reg_ctrl.REG_TX_ENABLE		<= 1'b0;			// UNUSED
		reg_ctrl.REG_SELECT			<= 1'b0;			// DONE
		reg_ctrl.REG_RX_ENABLE		<= 1'b0;			// UNUSED
		reg_ctrl.REG_CTRL_BIT3		<= 1'b0;			// UNUSED [BY SPEC]
		
		reg_ctrl.REG_CTRL_BIT5		<= 1'b0;			// UNUSED [BY SPEC]

		reg_ctrl.REG_RX_INT_MODE	<= 2'b0;			// UNUSED
		reg_ctrl.REG_TX_INT_ENABLE	<= 1'b0;			// TODO Check this flag to trigger interrupt. (::step)
		reg_ctrl.REG_RX_INT_ENABLE	<= 1'b0;			// UNUSED
		reg_ctrl.REG_ACK_INT_ENABLE	<= 1'b0;			// TODO Check this flag (::step)
		reg_ctrl.REG_ACTIVESLOT_NUM	<= 1'b0;			// TODO Use to adress correct output when writing/reading.
		
		// +14
		REG_BAUDRATE_RELOAD			<= 16'd0;			// TODO Use to compute timer.

		// Internals...
		BAD_ACCESS					<= 1'b0;
		PERIPH_TYPE					<= DEVICE_UNSELECTED;
	end else begin
		//
		// CPU WRITE
		// 
		if (writeInternal) begin
			if (i_addr16BitWord == 3'h0 && (!reg_ctrl.REG_SELECT)) begin
				if (i_format == ACCESS_32BIT && (reg_ctrl.REG_TX_ENABLE)) begin
					// 1F801040h JOY_TX_DATA (W)
					case (PERIPH_TYPE)
					default:
					begin
						if (i_dataIn[7:0]==8'd1) begin
							PERIPH_TYPE	<= DEVICE_CONTROLLER;
						end
						if (i_dataIn[7:0]==8'd81) begin
							PERIPH_TYPE	<= DEVICE_MEMORYCARD;
						end
					end
					DEVICE_CONTROLLER:
					begin
						// postByte(controller[control.port]->handle(byte));
						
						// TO CHECK
						/* if (controller[control.port]->getAck()) {
								postAck();
						} else {
								deviceSelected = DeviceSelected::None;
						} */
					end
					DEVICE_MEMORYCARD:
					begin
						// postByte(card[control.port]->handle(byte));

						// TO CHECK
						/* if (card[control.port]->getAck()) {
							postAck();
						} else {
							deviceSelected = DeviceSelected::None;
						} */
					end
					endcase
					
					reg_status.TX_READY		<= 1'b1;
					reg_status.TX_FINISHED	<= 1'b0;
					reg_status.ACK			<= 1'b0;	// Start Emitting...
					
				end
			end

			if (assertBadAccess) begin
				BAD_ACCESS <= 1'b1;
			end
			
			/* 1F801044h JOY_STAT (R)
			if (i_addr16BitWord == 3'h2) begin
				// 1F801044h JOY_STAT (R)
			end
			*/

			if (i_addr16BitWord == 3'h4) begin
				// 1F801048h JOY_MODE (R/W) (usually 000Dh, ie. 8bit, no parity, MUL1)
				reg_mode.REG_BAUDRATE_RELOAD_FACT	<= i_dataIn[1:0];
				reg_mode.REG_CHARACTER_LENGTH		<= i_dataIn[3:2];
				reg_mode.REG_PARITY_ENABLE			<= i_dataIn[4];
				reg_mode.REG_PARITY_ODD				<= i_dataIn[5];
				reg_mode.REG_CLK_OUTPOLARITY		<= i_dataIn[8];
			end

			if (i_addr16BitWord == 3'h5) begin
				// 1F80104Ah JOY_CTRL (R/W) (usually 1003h,3003h,0000h)
				reg_ctrl.REG_TX_ENABLE				<= i_dataIn[0];	
				reg_ctrl.REG_SELECT					<= i_dataIn[1];	
				reg_ctrl.REG_RX_ENABLE				<= i_dataIn[2];
				reg_ctrl.REG_CTRL_BIT3				<= i_dataIn[3];

				reg_ctrl.REG_CTRL_BIT5				<= i_dataIn[5];

				reg_ctrl.REG_RX_INT_MODE			<= i_dataIn[9:8];
				reg_ctrl.REG_TX_INT_ENABLE			<= i_dataIn[10];
				reg_ctrl.REG_RX_INT_ENABLE			<= i_dataIn[11];
				reg_ctrl.REG_ACK_INT_ENABLE			<= i_dataIn[12];
				reg_ctrl.REG_ACTIVESLOT_NUM			<= i_dataIn[13];
			end
			
			if (i_addr16BitWord == 3'h7) begin
				// 1F80104Eh JOY_BAUD (R/W) (usually 0088h, ie. circa 250kHz, when Factor=MUL1)
				REG_BAUDRATE_RELOAD					<= i_dataIn[15:0];
			end
		end

		//
		// CPU WRITE & INTERNAL UPDATE
		//
		if (resetPeripheral) begin
			// Reset Periphal
			PERIPH_TYPE				<= DEVICE_UNSELECTED;
		end
		
		if (resetACK) begin
			reg_status.RX_PARITYERROR	<= 1'b0;
			// reg_status.IRQ			<= ; TODO, NOT SURE...
		end
	end
end

//------------------------------------------------------------------------
// - CPU READs
//------------------------------------------------------------------------
reg	[31:0]	dataOut;
always @(*) begin
	case (i_addr16BitWord)
	// Data Received		1F801040h JOY_RX_DATA (R)
	3'd0: dataOut = { reg_receivedData.RX_DATA3, reg_receivedData.RX_DATA2 , reg_receivedData.RX_DATA1 , reg_receivedData.RX_DATA0 };
	// Status 				1F801044h JOY_STAT (R)
	3'd2: dataOut	= {
						  reg_status.BAUDTIMER
						, 1'b0
						, reg_status.IRQ
						, 1'b0
						
						, reg_status.ACK
						, 3'b0
						
						, reg_status.RX_PARITYERROR
						, reg_status.TX_FINISHED
						, reg_status.RX_PENDING
						, reg_status.TX_READY 
					};
	// 1F801048h JOY_MODE (R/W) (usually 000Dh, ie. 8bit, no parity, MUL1)
	3'd4: dataOut	= {
						 16'd0
						, 7'd0
						, reg_mode.REG_CLK_OUTPOLARITY								  
						
						, 2'd0
						, reg_mode.REG_PARITY_ODD										  
						, reg_mode.REG_PARITY_ENABLE									  
						
						, reg_mode.REG_CHARACTER_LENGTH								  
						, reg_mode.REG_BAUDRATE_RELOAD_FACT							  
					};
	// 1F80104Ah JOY_CTRL (R/W) (usually 1003h,3003h,0000h)
	3'd5: dataOut	= {
						  18'd0
						, reg_ctrl.REG_ACTIVESLOT_NUM
						, reg_ctrl.REG_ACK_INT_ENABLE
						, reg_ctrl.REG_RX_INT_ENABLE
						, reg_ctrl.REG_TX_INT_ENABLE
						, reg_ctrl.REG_RX_INT_MODE	
						, 1'b0
						, 1'b0
						, reg_ctrl.REG_CTRL_BIT5	
						, 1'b0
						, reg_ctrl.REG_CTRL_BIT3
						, reg_ctrl.REG_RX_ENABLE
						, reg_ctrl.REG_SELECT		
						, reg_ctrl.REG_TX_ENABLE	
					};
	3'd7: dataOut	= { 16'd0, REG_BAUDRATE_RELOAD };
	default dataOut = 32'd0;
	endcase
end

reg	[31:0]	pDataOut;
always @(posedge i_clk) begin
	pDataOut <= dataOut;
end

assign	o_dataOut	= pDataOut; // 1 Cycle latency compare to read.

// TODO Timer and update, communicate with ports etc...
// TODO assign	o_INT7		= ;
/*	
	TODO internal counter, send data, etc...
	
	wire [20:0]	nextDecBaudRateTimer = BAUDRATE_TIMER + 21'h1FFFFF; // -1
	always @(posedge i_clk) begin
		if () begin
			??? Load Value
			??? Reset ???
		end else begin
			BAUDRATE_TIMER <= nextDecBaudRateTimer;
		end
	end



	reg ReloadValue;
	always @(*) begin
		case (
	ReloadValue = BaudRateFactor * 
	if (BaudRateTimer == 0 || write) begin
		Timer <= ReloadValue;
	end else begin
	end
*/
endmodule
