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

// Assuming that this interface is running at same clock speed as i_clk.
// We don't provide the clock in it, nor reset.
interface Soft_IF;
    //  [PARAMETER FIFO SIGNAL AND DATA READ]
    logic [7:0]         paramFIFO_out;                              // FROM SOFTWARE SIDE
    logic               paramRead;                                  // FROM SOFTWARE SIDE --> Please use 'sig_PARAMFifoNotEmpty'.
    //  [RESPONSE FIFO INSTANCE WRITE]
    logic [7:0]         responseFIFO_in;                                // FROM SOFTWARE SIDE --> Please use 'responseFIFO_full' ?
    logic               responseWrite;                              // FROM SOFTWARE SIDE
    //  [PCM FIFO STATE AND WRITE]
    logic               writeL   ,writeR;                           // FROM SOFTWARE SIDE : Write PCM data
    logic signed [15:0] PCMValueL,PCMValueR;                        //
    logic               PCMFifoFull;
    //  [DATA FIFO STATE AND WRITE]
    logic               write_data;
    logic [15:0]        write_dataValue;
    
    modport SW (
        input   paramFIFO_out,
        output  paramRead,
        
        output  responseFIFO_in,
        output  responseWrite,

        output  writeL,
        output  writeR,
    
        output  PCMValueL,
        output  PCMValueR,

        input   PCMFifoFull,
        
        output  write_data,
        output  write_dataValue
    );

    // Opposite direction for HW.
    modport HW (
        output  paramFIFO_out,
        input   paramRead,
        
        input   responseFIFO_in,
        input   responseWrite,

        input   writeL,
        input   writeR,
    
        input   PCMValueL,
        input   PCMValueR,

        output  PCMFifoFull,
        
        input  write_data,
        input  write_dataValue
    );
endinterface

module CDRom (
    // --------------------------------------------
    // CPU Side
    // --------------------------------------------
    input                   i_clk,
    input                   i_nrst,
    input                   i_CDROM_CS,

    // [TODO] : Interrupt, input ? output ? Schematics show INPUT... Does not make sense.
    output                  i_CDROM_INT,
    
    input                   i_write,
    input                   i_read,
    
    input   [1:0]           i_adr,
    input   [7:0]           i_dataIn,
    output  [7:0]           o_dataOut,

    // --------------------------------------------
    // Interface for module implementing CD Rom (software or hardware)
    // Control the front end.
    // --------------------------------------------
    Soft_IF.HW              swCtrl,
    
    // --------------------------------------------
    // SPU Side
    // --------------------------------------------
    // o_outputX signal is 1 clock, every 768 main cycle
    output  signed [15:0]   o_CDRomOutL,
    output  signed [15:0]   o_CDRomOutR,
    output                  o_outputL,
    output                  o_outputR
);

wire s_rst = !i_nrst;

reg [7:0] vDataOut; assign o_dataOut = vDataOut;

// Current Index
reg [2:0] IndexREG;

// ------------------------------------------------
// Direct Control (Not registers)
// ------------------------------------------------

//  --- WRITE ---
// 1F801801.0 (W)
wire sig_issueCommand  = i_CDROM_CS && i_write && (i_adr==2'd1) && (IndexREG==2'd0);
// 1F801801.1 (W)
wire sig_writeSoundMap = i_CDROM_CS && i_write && (i_adr==2'd1) && (IndexREG==2'd1);

// 1F801802.0 (W)
wire sig_writeParamFIFO= i_CDROM_CS && i_write && (i_adr==2'd2) && (IndexREG==2'd0);

// 1F801803.1 (W) Bit 6
wire sig_resetParamFIFO= s_rst | (i_CDROM_CS && i_write && (i_adr==2'd2) && (IndexREG==2'd1) && i_dataIn[6]);
// 1F801803.3 (W)
wire sig_applyVolChange= i_CDROM_CS && i_write && (i_adr==2'd3) && (IndexREG==2'd3) && i_dataIn[5];

//  --- READ ---
// 1F801801.x (R)
wire sig_readRespFIFO  = i_CDROM_CS && (!i_write) && (i_adr==2'd1);
wire sig_readDataFIFO  = i_CDROM_CS && (!i_write) && (i_adr==2'd2);

// ------------------------------------------------

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

reg       REG_SNDMAP_Stereo;       // Mono/Stereo
reg       REG_SNDMAP_SampleRate;   // 37800/18900
reg       REG_SNDMAP_BitPerSample; // 4/8
reg       REG_SNDMAP_Emphasis;     // ??


// Forward declaration, used for PCM Fifo full flags.
wire PCMFifoFullL,PCMFifoFullR;

// ---------------------------------------------------------------------------------------------------------
//  Logic signal sent back to the platform.
// ---------------------------------------------------------------------------------------------------------
// Return if audio data is full.
assign swCtrl.PCMFifoFull = PCMFifoFullL | PCMFifoFullR;    // FROM SOFTWARE SIDE : Can read the data and check ?

// ---------------------------------------------------------------------------------------------------------
//  [PARAMETER FIFO SIGNAL AND DATA]
// ---------------------------------------------------------------------------------------------------------
wire        sig_PARAMFifoNotEmpty;
wire        sig_PARAMFifoFull;

// ---------------------------------------------------------------------------------------------------------
// TODO : Bit3,4,5 are bound to 5bit counters; ie. the bits become true at specified amount of reads/writes, and thereafter once on every further 32 reads/writes. (No$)
wire sig_CmdParamTransmissionBusy;                          // 1F801800 Bit 7 1:Busy
wire sig_DATAFifoNotEmpty;                                  // 1F801800 Bit 6 0:Empty, 1:Has some data at least. 
wire sig_RESPONSEFifoNotEmpty;                              // 1F801800 Bit 5 0:Empty, 1:Has some data at least. 
wire sig_PARAMFifoNotFull   = !sig_PARAMFifoFull;           // 1F801800 Bit 4 0:Full,  1:Not full.
wire sig_PARAMFifoEmpty     = !sig_PARAMFifoNotEmpty;       // 1F801800 Bit 3 1:Empty, 0:Has some data at least.
wire sig_ADPCMFifoNotEmpty;                                 // 1F801800 Bit 2 0:Empty, 1:Has some data at least.
// ---------------------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------------------
//  [PARAMETER FIFO INSTANCE]
// ---------------------------------------------------------------------------------------------------------
Fifo2 #(.DEPTH_WIDTH(4),.DATA_WIDTH(8))
inParamFIFO (
    // System
    .i_clk          (i_clk),
    .i_rst          (sig_resetParamFIFO),
    .i_ena          (1),
    
    .i_w_data       (i_dataIn),                 // Data In
    .i_w_ena        (sig_writeParamFIFO),       // Write Signal
    
    .o_r_data       (swCtrl.paramFIFO_out),         // Data Out
    .i_r_taken      (swCtrl.paramRead),             // Read signal
    
    .o_w_full       (sig_PARAMFifoFull),
    .o_r_valid      (sig_PARAMFifoNotEmpty),
    .o_level        (/*Unused*/)
);

// ---------------------------------------------------------------------------------------------------------
//  [RESPONSE FIFO INSTANCE]
// ---------------------------------------------------------------------------------------------------------
/* The response Fifo is a 16-byte buffer, most or all responses are less than 16 bytes, after reading the last used byte (or before reading anything when the response is 0-byte long), Bit5 of the Index/Status register becomes zero to indicate that the last byte was received.
When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes, and does then restart at the first response byte (that, without receiving a new response, so it'll always return the same 16 bytes, until a new command/response has been sent/received).
*/
wire [7:0]  responseFIFO_out;
wire        responseFIFO_full;

Fifo2 #(.DEPTH_WIDTH(4),.DATA_WIDTH(8)) // TODO : Spec issues "When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes ???? ==> Can just return 0 when FIFO is empty and read ?"
outResponseFIFO (
    // System
    .i_clk          (i_clk),
    .i_rst          (s_rst),
    .i_ena          (1),
    
    .i_w_data       (swCtrl.responseFIFO_in),   // Data In
    .i_w_ena        (swCtrl.responseWrite),     // Write Signal
    
    .o_r_data       (responseFIFO_out),     // Data Out
    .i_r_taken      (sig_readRespFIFO),     // Read signal
    
    .o_w_full       (responseFIFO_full),
    .o_r_valid      (sig_RESPONSEFifoNotEmpty),
    .o_level        (/*Unused*/)
);

// ---------------------------------------------------------------------------------------------------------
//  [DATA FIFO INSTANCE]
// ---------------------------------------------------------------------------------------------------------

/* 1F801802h.Index0..3 - Data Fifo - 8bit/16bit (R)
After ReadS/ReadN commands have generated INT1, software must set the Want Data bit (1F801803h.Index0.Bit7), then wait until Data Fifo becomes not empty (1F801800h.Bit6), the datablock (disk sector) can be then read from this register.
  0-7  Data 8bit  (one byte), or alternately,
  0-15 Data 16bit (LSB=First byte, MSB=Second byte)
The PSX hardware allows to read 800h-byte or 924h-byte sectors, indexed as [000h..7FFh] or [000h..923h], when trying to read further bytes, then the PSX will repeat the byte at index [800h-8] or [924h-4] as padding value.
Port 1F801802h can be accessed with 8bit or 16bit reads (ie. to read a 2048-byte sector, one can use 2048 load-byte opcodes, or 1024 load halfword opcodes, or, more conventionally, a 512 word DMA transfer; the actual CDROM databus is only 8bits wide, so CPU/DMA are apparently breaking 16bit/32bit reads into multiple 8bit reads from 1F801802h).
*/
wire [7:0] dataFIFOL,dataFIFOM;
wire hasDataL,hasDataM;
reg  currentReadColumn;

wire readSigL = (!currentReadColumn) && sig_readDataFIFO && hasDataL;
wire readSigM = ( currentReadColumn) && sig_readDataFIFO && hasDataM;

Fifo2 #(.DEPTH_WIDTH(4),.DATA_WIDTH(8)) // TODO : Spec issues "When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes ???? ==> Can just return 0 when FIFO is empty and read ?"
outDataFIFOL (
    // System
    .i_clk          (i_clk),
    .i_rst          (s_rst),
    .i_ena          (1),
    
    .i_w_data       (swCtrl.write_dataValue[7:0]),      // Data In
    .i_w_ena        (swCtrl.write_data),        // Write Signal
    
    .o_r_data       (dataFIFOL),                // Data Out
    .i_r_taken      (readSigL),                 // Read signal
    
    .o_w_full       (),
    .o_r_valid      (hasDataL),
    .o_level        (/*Unused*/)
);

Fifo2 #(.DEPTH_WIDTH(4),.DATA_WIDTH(8)) // TODO : Spec issues "When reading further bytes: The buffer is padded with 00h's to the end of the 16-bytes ???? ==> Can just return 0 when FIFO is empty and read ?"
outDataFIFOM (
    // System
    .i_clk          (i_clk),
    .i_rst          (s_rst),
    .i_ena          (1),
    
    .i_w_data       (swCtrl.write_dataValue[15:8]),     // Data In
    .i_w_ena        (swCtrl.write_data),        // Write Signal
    
    .o_r_data       (dataFIFOM),                // Data Out
    .i_r_taken      (readSigM),                 // Read signal
    
    .o_w_full       (),
    .o_r_valid      (hasDataM),
    .o_level        (/*Unused*/)
);

// Select correct data to send back to main bus.
wire [7:0] dataFIFO_Out = (!currentReadColumn) ? dataFIFOL : dataFIFOM; // May read from 2 FIFOs alternating...
// ---------------------------------------------------------------------------------------------------------

// Interrupt enabled flags. + Stored only bits...
reg [4:0] INT_Enabled; reg[2:0] INT_Garbage;

// ---------------------------------------------------------------------------------------------------------
// TODO : 1F801803.0 & 1F801803.1 => Everything to do.

// =========================
// ---- WRITE REGISTERS ----
// =========================
reg [9:0] REG_Counter;
wire sendAudioSound = (REG_Counter == 10'd767);
 
always @(posedge i_clk) begin
    // Set to 0 when reach 768 or reset signal.
    REG_Counter = ((i_nrst == 1'b0) || sendAudioSound) ? 10'd0 : (REG_Counter + 10'd1);
    
    if (i_nrst == 1'b0) begin
        // [TODO : Default value after reset ?]
        REG_SNDMAP_Stereo       = 1'b0;
        REG_SNDMAP_SampleRate   = 1'b0;
        REG_SNDMAP_BitPerSample = 1'b0;
        REG_SNDMAP_Emphasis     = 1'b0;
    
        IndexREG                = 3'd0;

        CD_VOL_LL               = 8'd0;
        CD_VOL_LR               = 8'd0;
        CD_VOL_RL               = 8'd0;
        CD_VOL_RR               = 8'd0;

        CD_VOL_LL_WORK          = 8'd0;
        CD_VOL_LR_WORK          = 8'd0;
        CD_VOL_RL_WORK          = 8'd0;
        CD_VOL_RR_WORK          = 8'd0;

        //
        REG_ADPCM_Muted         = 1'b0;

        REG_SNDMAP_Stereo       = 1'b0;
        REG_SNDMAP_SampleRate   = 1'b0;
        REG_SNDMAP_BitPerSample = 1'b0;
        REG_SNDMAP_Emphasis     = 1'b0;
        currentReadColumn       = 1'b0; // LSB first, switch to 1 if MSB first.
    end else begin
        if (i_CDROM_CS) begin
            if (i_write) begin
                case (i_adr)
                // 1F801800 (W) : Index/Status Register
                2'd0: IndexREG = i_dataIn[2:0];
                // 1F801801.0 (W)   : Nothing to do here, sig_issueCommand is set. (Other circuit)
                // 1F801801.1 (W)   : Nothing to do here, Sound Map Data Out       (Other circuit)
                // 1F801801.2 (W)   : Sound Map Coding Info
                // 1F801801.3 (W)   : Audio Volume for Right-CD-Out to Right-SPU-Input
                2'd1: begin
                    case (IndexREG)
                    2'd0: /* Command is issued, not here        (Other Circuit) */;
                    2'd1: /* Sound Map Audio Out pushed to FIFO (Other Circuit) */;
                    2'd2: begin
                        REG_SNDMAP_Stereo       = i_dataIn[0];
                        REG_SNDMAP_SampleRate   = i_dataIn[2];
                        REG_SNDMAP_BitPerSample = i_dataIn[4];
                        REG_SNDMAP_Emphasis     = i_dataIn[6];
                    end
                    2'd3: CD_VOL_RR = i_dataIn;
                    endcase
                end
                // 1F801802.0 (W)   : Parameter Fifo                                (Other circuit)
                // 1F801802.1 (W)   : Interrupt Enable Register
                // 1F801802.2 (W)   : Audio Volume for Left -CD-Out to Left -SPU-Input
                // 1F801802.3 (W)   : Audio Volume for Right-CD-Out to Left -SPU-Input
                2'd2: begin
                    case (IndexREG)
                    2'd0: /* Parameter FIFO push, not here         */;
                    2'd1: begin
                          INT_Enabled   = i_dataIn[4:0];
                          INT_Garbage   = i_dataIn[7:5];
                          end
                    2'd2: CD_VOL_LL     = i_dataIn;
                    2'd3: CD_VOL_RL     = i_dataIn;
                    endcase
                end
                // 1F801803.0 (W)   : Request Register                              [TODO : Spec not understood yet]
                // 1F801803.1 (W)   : Interrupt Flag Register
                // 1F801803.2 (W)   : Audio Volume for Left-CD-Out to Right-SPU-Input
                // 1F801803.3 (W)   : Audio Volume Apply Change + Mute ADPCM
                2'd3:
                    case (IndexREG)
                    2'd0: /* Request REG */;
                    2'd1: /* Interrupt Flag REG */;
                    2'd2: CD_VOL_LR         = i_dataIn;
                    2'd3: REG_ADPCM_Muted   = i_dataIn[0];
                    endcase
                endcase
            end
        end
    end
    
    if (sig_applyVolChange) begin
        CD_VOL_LL_WORK = CD_VOL_LL;
        CD_VOL_LR_WORK = CD_VOL_LR;
        CD_VOL_RL_WORK = CD_VOL_RL;
        CD_VOL_RR_WORK = CD_VOL_RR;
    end 
end

always @(*) begin

    // =========================
    // ---- READ REGISTERS -----
    // =========================
    case (i_adr)
    2'd0: vDataOut = {  sig_CmdParamTransmissionBusy,
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


// ---------------------------------------------------------------------------------------------------------
//  [AUDIO PCM FIFO]
// ---------------------------------------------------------------------------------------------------------
wire PCMFifoNotEmpty_L,PCMFifoNotEmpty_R;
wire signed [15:0]  pcmL,pcmR;

wire getAudioSoundFIFO_L = sendAudioSound & PCMFifoNotEmpty_L;
wire getAudioSoundFIFO_R = sendAudioSound & PCMFifoNotEmpty_R;


// TODO [Size of BOTH AUDIO FIFO : for now 8192 samples.]
Fifo2 #(.DEPTH_WIDTH(13),.DATA_WIDTH(16))
outPCMFIFO_L (
    // System
    .i_clk          (i_clk),
    .i_rst          (s_rst),
    .i_ena          (1),
    
    .i_w_data       (swCtrl.PCMValueL), // Data In
    .i_w_ena        (swCtrl.writeL),        // Write Signal
    
    .o_r_data       (pcmL),                 // Data Out
    .i_r_taken      (getAudioSoundFIFO_L),  // Read signal
    
    .o_w_full       (PCMFifoFullL),
    .o_r_valid      (PCMFifoNotEmpty_L),
    .o_level        (/*Unused*/)
);

Fifo2 #(.DEPTH_WIDTH(13),.DATA_WIDTH(16))
outPCMFIFO_R (
    // System
    .i_clk          (i_clk),
    .i_rst          (s_rst),
    .i_ena          (1),
    
    .i_w_data       (swCtrl.PCMValueR), // Data In
    .i_w_ena        (swCtrl.writeR),        // Write Signal
    
    .o_r_data       (pcmR),                 // Data Out
    .i_r_taken      (getAudioSoundFIFO_R),  // Read signal
    
    .o_w_full       (PCMFifoFullR),
    .o_r_valid      (PCMFifoNotEmpty_R),
    .o_level        (/*Unused*/)
);

// Audio return ZERO when FIFO has no data... 
// [TODO : Should be LAST value READ FROM FIFO instead to avoid 'CRACK/POP' if HPS does not fill fast enough]
wire signed [15:0] audioL = PCMFifoNotEmpty_L ? pcmL : 16'd0;
wire signed [15:0] audioR = PCMFifoNotEmpty_R ? pcmR : 16'd0;

wire signed [8:0] sCD_VOL_LL_WORK = { 1'b0, CD_VOL_LL_WORK };
wire signed [8:0] sCD_VOL_LR_WORK = { 1'b0, CD_VOL_LR_WORK };
wire signed [8:0] sCD_VOL_RL_WORK = { 1'b0, CD_VOL_RL_WORK };
wire signed [8:0] sCD_VOL_RR_WORK = { 1'b0, CD_VOL_RR_WORK };

wire signed [23:0] LLv = sCD_VOL_LL_WORK * audioL; // Volume 1.0 = 0x80 -> 7 Bit fixed point.
wire signed [23:0] RLv = sCD_VOL_RL_WORK * audioR;
wire signed [23:0] LRv = sCD_VOL_LR_WORK * audioL;
wire signed [23:0] RRv = sCD_VOL_RR_WORK * audioR;

wire signed [17:0] unclampedL = LLv[23:7] + RLv[23:7];  // convert back from fixed point to normal and add.
wire signed [17:0] unclampedR = LRv[23:7] + RRv[23:7];

// [TODO] Clipping

assign  o_outputL   = sendAudioSound;
assign  o_CDRomOutL = unclampedL[15:0];

assign  o_outputR   = sendAudioSound;
assign  o_CDRomOutR = unclampedR[15:0];

// ---------------------------------------------------------------------------------------------------------

endmodule
