/*
	CD Rom Implementation concept :
	- Set some registers.
	- FIFO In : Parameters, Sound Map.
	- FIFO Out: Response, Data, (Audio for SPU?)

	Audio FIFO Size : 2x needed pace ?
	44,100 Hz × 16 bits/sample × 2 channels × 2,048 / 2,352 / 8 = 153.6 kB/s = 150 KiB/s.
	
	Each sector is 2048 byte x 2 channel = 4096 byte of Audio data per read.
	Double that : 8192 bytes Of FIFO for audio data. 46 ms of audio data.
	About 3 frames...
	
	- Handle some interrupt. (Kick, ack)
	- Send audio to SPU on a regular basis. (44.1 Khz)
*/


module CDRom (

	// HPS Side, real file system stuff here....
	// TODO Use struct and abstract platform here.
	
	// CPU Side
	input					i_clk,
	input					i_nrst,
	input					i_CDROM_CS,
	
	input					i_write,
	
	input	[1:0]			i_adr,
	input	[7:0]			i_dataIn,
	output	[7:0]			o_dataOut,

	// SPU Side
	// o_outputX signal is 1 clock, every 768 main cycle
	// Can be done in software inside, no problem.
	output  signed [15:0]	o_CDRomOutL,
	output  signed [15:0]	o_CDRomOutR,
	output					o_outputL,
	output					o_outputR		
);

reg [7:0] vDataOut; assign o_dataOut = vDataOut;

// Current Index
reg [2:0] IndexREG;

// Audio volume for left/right input to left/right output, 0x80 is 100%.
reg [7:0] CD_VOL_LL;
reg [7:0] CD_VOL_LR;
reg [7:0] CD_VOL_RL;
reg [7:0] CD_VOL_RR;

// Value used for mixing computation
reg [7:0] CD_VOL_LL_WORK;
reg [7:0] CD_VOL_LR_WORK;
reg [7:0] CD_VOL_RL_WORK;
reg [7:0] CD_VOL_RR_WORK;

//
reg       REG_ADPCM_Muted;

reg		  REG_SNDMAP_Stereo;       // Mono/Stereo
reg		  REG_SNDMAP_SampleRate;   // 37800/18900
reg       REG_SNDMAP_BitPerSample; // 4/8
reg       REG_SNDMAP_Emphasis;     // ??



//
// in : Command FIFO in
// out: 

// Response FIFO
/* The response Fifo is a 16-byte buffer, most or all responses are less than 16 bytes, after reading the last used byte (or before reading anything when the response is 0-byte long), Bit5 of the Index/Status register becomes zero to indicate that the last byte was received.
When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes, and does then restart at the first response byte (that, without receiving a new response, so it'll always return the same 16 bytes, until a new command/response has been sent/received).
*/
wire [7:0]	responseFIFO_out;

// [TODO : Put a FIFO here]

/* 1F801802h.Index0..3 - Data Fifo - 8bit/16bit (R)
After ReadS/ReadN commands have generated INT1, software must set the Want Data bit (1F801803h.Index0.Bit7), then wait until Data Fifo becomes not empty (1F801800h.Bit6), the datablock (disk sector) can be then read from this register.
  0-7  Data 8bit  (one byte), or alternately,
  0-15 Data 16bit (LSB=First byte, MSB=Second byte)
The PSX hardware allows to read 800h-byte or 924h-byte sectors, indexed as [000h..7FFh] or [000h..923h], when trying to read further bytes, then the PSX will repeat the byte at index [800h-8] or [924h-4] as padding value.
Port 1F801802h can be accessed with 8bit or 16bit reads (ie. to read a 2048-byte sector, one can use 2048 load-byte opcodes, or 1024 load halfword opcodes, or, more conventionally, a 512 word DMA transfer; the actual CDROM databus is only 8bits wide, so CPU/DMA are apparently breaking 16bit/32bit reads into multiple 8bit reads from 1F801802h).
*/
wire [7:0] dataFIFO_Out; // May read from 2 FIFOs alternating...

// [TODO : Put a FIFO here. Actually 2 x 8 bit FIFO. CD-Rom may write 16 bit, splitted into two fifos. Read will alternate and pump... Then => sig_DATAFifoNotEmpty = !(Fifo1.Empty && Fifo2.Empty) ]

// Interrupt enabled flags. + Stored only bits...
reg [4:0] INT_Enabled; reg[2:0] INT_Garbage;

// ------------------------------------------------
// Direct Control (Not registers)
// ------------------------------------------------

// 1F801801.0 (W)
wire sig_issueCommand  = i_CDROM_CS && i_write && (i_adr==2'd1) && (IndexREG==2'd0);
// 1F801801.1 (W)
wire sig_writeSoundMap = i_CDROM_CS && i_write && (i_adr==2'd1) && (IndexREG==2'd1);

// 1F801802.0 (W)
wire sig_writeParamFIO = i_CDROM_CS && i_write && (i_adr==2'd2) && (IndexREG==2'd0);

// 1F801803.1 (W) Bit 6
wire sig_resetParamFIFO= i_CDROM_CS && i_write && (i_adr==2'd2) && (IndexREG==2'd1) && i_dataIn[6];
// 1F801803.3 (W)
wire sig_applyVolChange= i_CDROM_CS && i_write && (i_adr==2'd3) && (IndexREG==2'd3) && i_dataIn[5];

// ---------------------------------------------------------------------------------------------------------
// TODO : Bit3,4,5 are bound to 5bit counters; ie. the bits become true at specified amount of reads/writes, and thereafter once on every further 32 reads/writes. (No$)
wire sig_CmdParamTransmissionBusy;	// 1F801800 Bit 7 1:Busy
wire sig_DATAFifoNotEmpty;			// 1F801800 Bit 6 0:Empty, 1:Has some data at least. 
wire sig_RESPONSEFifoNotEmpty;		// 1F801800 Bit 5 0:Empty, 1:Has some data at least. 
wire sig_PARAMFifoNotFull;			// 1F801800 Bit 4 0:Full,  1:Not full.
wire sig_PARAMFifoEmpty;			// 1F801800 Bit 3 1:Empty, 0:Has some data at least.
wire sig_ADPCMFifoNotEmpty;			// 1F801800 Bit 2 0:Empty, 1:Has some data at least.
// ---------------------------------------------------------------------------------------------------------

// TODO : 1F801803.0 & 1F801803.1 => Everything to do.

// =========================
// ---- WRITE REGISTERS ----
// =========================
always @(posedge i_clk) begin
	if (i_nrst == 1'b0) begin
		// [TODO : Default value after reset ?]
		REG_SNDMAP_Stereo		= 1'b0;
		REG_SNDMAP_SampleRate	= 1'b0;
		REG_SNDMAP_BitPerSample = 1'b0;
		REG_SNDMAP_Emphasis		= 1'b0;
	
		IndexREG				= 3'd0;

		CD_VOL_LL				= 8'd0;
		CD_VOL_LR				= 8'd0;
		CD_VOL_RL				= 8'd0;
		CD_VOL_RR				= 8'd0;

		CD_VOL_LL_WORK			= 8'd0;
		CD_VOL_LR_WORK			= 8'd0;
		CD_VOL_RL_WORK			= 8'd0;
		CD_VOL_RR_WORK			= 8'd0;

		//
		REG_ADPCM_Muted			= 1'b0;

		REG_SNDMAP_Stereo		= 1'b0;
		REG_SNDMAP_SampleRate	= 1'b0;
		REG_SNDMAP_BitPerSample	= 1'b0;
		REG_SNDMAP_Emphasis		= 1'b0;
	end else begin
		if (i_CDROM_CS) begin
			if (i_write) begin
				case (i_adr)
				// 1F801800	(W)	: Index/Status Register
				2'd0: IndexREG = i_dataIn[2:0];
				// 1F801801.0 (W)	: Nothing to do here, sig_issueCommand is set. (Other circuit)
				// 1F801801.1 (W)	: Nothing to do here, Sound Map Data Out       (Other circuit)
				// 1F801801.2 (W)	: Sound Map Coding Info
				// 1F801801.3 (W)	: Audio Volume for Right-CD-Out to Right-SPU-Input
				2'd1: begin
					case (IndexREG)
					2'd0: /* Command is issued, not here        (Other Circuit) */;
					2'd1: /* Sound Map Audio Out pushed to FIFO (Other Circuit) */;
					2'd2: begin
						REG_SNDMAP_Stereo		= i_dataIn[0];
						REG_SNDMAP_SampleRate	= i_dataIn[2];
						REG_SNDMAP_BitPerSample = i_dataIn[4];
						REG_SNDMAP_Emphasis		= i_dataIn[6];
					end
					2'd3: CD_VOL_RR = i_dataIn;
					endcase
				end
				// 1F801802.0 (W)	: Parameter Fifo								(Other circuit)
				// 1F801802.1 (W)	: Interrupt Enable Register
				// 1F801802.2 (W)	: Sound Map Coding Info
				// 1F801802.3 (W)	: Audio Volume for Right-CD-Out to Right-SPU-Input
				2'd2: begin
					case (IndexREG)
					2'd0: /* Parameter FIFO push, not here         */;
					2'd1: begin
						  INT_Enabled	= i_dataIn[4:0];
						  INT_Garbage	= i_dataIn[7:5];
						  end
					2'd2: CD_VOL_LL		= i_dataIn;
					2'd3: CD_VOL_RL		= i_dataIn;
					endcase
				end
				// 1F801803.0 (W)	: Request Register 								[TODO : Spec not understood yet]
				// 1F801803.1 (W)	: Interrupt Enable Register
				// 1F801803.2 (W)	: Sound Map Coding Info
				// 1F801803.3 (W)	: Audio Volume for Right-CD-Out to Right-SPU-Input
				2'd3:
					case (IndexREG)
					2'd0: /* Request REG */;
					2'd1: /* Interrupt Flag REG */;
					2'd2: CD_VOL_LR			= i_dataIn;
					2'd3: REG_ADPCM_Muted	= i_dataIn[0];
					endcase
				endcase
			end else begin
			// =========================
			// ---- READ REGISTERS -----
			// =========================
				case (i_adr)
				2'd0: vDataOut = { 	sig_CmdParamTransmissionBusy,
									sig_DATAFifoNotEmpty,
									sig_RESPONSEFifoNotEmpty,
									sig_PARAMFifoNotFull,
									sig_PARAMFifoEmpty,
									sig_ADPCMFifoNotEmpty, 
									IndexREG 
								 };
									
				2'd1: vDataOut = responseFIFO_out; // Index0,2,3 are mirrors.
				2'd2: vDataOut = dataFIFO_Out;
				2'd3: if (IndexREG[0]) begin
						// Index 1,3
						vDataOut = { 8'd0 /*For now, not implemented */ };
						/* TODO Don't understand specs... read to do...
							  0-2   Read: Response Received   Write: 7=Acknowledge   ;INT1..INT7
							  3     Read: Unknown (usually 0) Write: 1=Acknowledge   ;INT8  ;XXX CLRBFEMPT
							  4     Read: Command Start       Write: 1=Acknowledge   ;INT10h;XXX CLRBFWRDY
							  5     Read: Always 1 ;XXX "_"   Write: 1=Unknown              ;XXX SMADPCLR
							  6     Read: Always 1 ;XXX "_"   Write: 1=Reset Parameter Fifo ;XXX CLRPRM
							  7     Read: Always 1 ;XXX "_"   Write: 1=Unknown              ;XXX CHPRST
						*/ 
					  end else begin
						// Index 0,2
						vDataOut = { INT_Garbage , INT_Enabled }; // (read: usually all bits set.)
					  end
				endcase
				
			end
		end
		
		if (sig_applyVolChange) begin
			CD_VOL_LL_WORK = CD_VOL_LL;
			CD_VOL_LR_WORK = CD_VOL_LR;
			CD_VOL_RL_WORK = CD_VOL_RL;
			CD_VOL_RR_WORK = CD_VOL_RR;
		end	
	end
end

endmodule
