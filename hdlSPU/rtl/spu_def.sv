/* ----------------------------------------------------------------------------------------------------------------------

PS-FPGA Licenses (DUAL License GPLv2 and commercial license)

This PS-FPGA source code is copyright 2019 Romain PIQUOIS and licensed under the GNU General Public License v2.0, 
 and a commercial licensing option.
If you wish to use the source code from PS-FPGA, email laxer3a [at] hotmail [dot] com for commercial licensing.

See LICENSE file.
---------------------------------------------------------------------------------------------------------------------- */

`ifndef SPU_DEFINITION
`define SPU_DEFINITION

parameter	CHANGE_ADSR_AT = 23'd1;

parameter	VOICEMD				= 2'd1,
			FIFO_MD				= 2'd2,
			REVB_MD				= 2'd3,
			CDROMMD				= 2'd0;
//
//                                   +--------- Write (1) / Read (0)
//                                   |++------  0:CD, 1:Voice, 2:Fifo, 3:Reverb for read or writeback.
//                                   |||
//                                   |||
//                                   |||
parameter	VOICE_RD			= 3'b001,
			FIFO_RD				= 3'b010,
			REVERB_READ			= 3'b011,
			NO_SPU_READ			= 3'b000,
			//---------------------------
			VOICE_WR			= 3'b101,
			FIFO_WRITE			= 3'b110,
			REVERB_WRITE		= 3'b111,
			CD_WR				= 3'b100;


parameter	ADSR_ATTACK			= 2'd0, // May need bit 2 for ADSR_STOPPED ?
			ADSR_DECAY			= 2'd1,
			ADSR_SUSTAIN		= 2'd2,
			ADSR_RELEASE		= 2'd3;


parameter	XFER_STOP   		= 2'd0,
			XFER_MANUAL 		= 2'd1,
			XFER_DMAWR  		= 2'd2,
			XFER_DMARD  		= 2'd3;

// ----------------------------------------------
//   Reverb Computation MUX Selectors
// ----------------------------------------------

// Mux A
parameter 	SA_VWALL	=	4'h0,
			SA_VIIR		=	4'h1,
			SA_ZERO		=	4'h2,
			SA_ONE		=	4'h3,
			SA_COMB1	=	4'h4,
			SA_COMB2	=	4'h5,
			SA_COMB3	=	4'h6,
			SA_COMB4	=	4'h7,
			SA_VAPF1	=	4'h8,
			SA_VAPF2	=	4'h9,
			SA_NVAPF1	=	4'hA,
			SA_NVAPF2	=	4'hB,
			SA_NEG_ONE	=	4'hC,
			SA_VIN		=	4'hD;
			
// Mux B
parameter 	SB_DLSAME	=	5'h0,
			SB_DRSAME	=	5'h1,
			SB_MLSAME	=	5'h2,
			SB_MRSAME	=	5'h3,

			SB_DLDIFF	=	5'h4,
			SB_DRDIFF	=	5'h5,
			SB_MLDIFF	=	5'h6,
			SB_MRDIFF	=	5'h7,

			SB_MLCOMB1	=	5'h8,
			SB_MRCOMB1	=	5'h9,
			SB_MLCOMB2	=	5'hA,
			SB_MRCOMB2	=	5'hB,

			SB_MLCOMB3	=	5'hC,
			SB_MRCOMB3	=	5'hD,
			SB_MLCOMB4	=	5'hE,
			SB_MRCOMB4	=	5'hF,

			SB_MLAPF1_ADPF1 =	5'h10,
			SB_MRAPF1_ADPF1 =	5'h11,
			SB_MLAPF2_ADPF2 =	5'h12,
			SB_MRAPF2_ADPF2 =	5'h13,
			
			SB_MLAPF1 =	5'h14,
			SB_MRAPF1 =	5'h15,
			SB_MLAPF2 =	5'h16,
			SB_MRAPF2 =	5'h17,
			
			SB_FAKEREAD 	  =	5'h18;

parameter 	SB_DxSAME		=	4'h0,
			SB_MxSAME		=	4'h1,
			SB_DxDIFF		=	4'h2,
			SB_MxDIFF		=	4'h3,
			SB_MxCOMB1		=	4'h4,
			SB_MxCOMB2		=	4'h5,
			SB_MxCOMB3		=	4'h6,
			SB_MxCOMB4		=	4'h7,
			SB_MxAPF1_ADPF1 =	4'h8,
			SB_MxAPF2_ADPF2 =	4'h9,
			SB_MxAPF1 		=	4'hA,
			SB_MxAPF2		=	4'hB;

// Mux C
parameter	SEL_IN	  = 2'd0,
			SEL_RAM	  = 2'd1,
			SEL_ACC	  = 2'd2;


`endif // SPU_DEFINITION
