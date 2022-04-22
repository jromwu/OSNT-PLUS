//
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
// Junior University
// Copyright (c) 2016 University of Cambridge
// Copyright (c) 2016 Jong Hun Han
// All rights reserved.
//
// This software was developed by University of Cambridge Computer Laboratory
// under the ENDEAVOUR project (grant agreement 644960) as part of
// the European Union's Horizon 2020 research and innovation programme.
//
// @NETFPGA_LICENSE_HEADER_START@
//
// Licensed to NetFPGA Open Systems C.I.C. (NetFPGA) under one or more
// contributor license agreements. See the NOTICE file distributed with this
// work for additional information regarding copyright ownership. NetFPGA
// licenses this file to you under the NetFPGA Hardware-Software License,
// Version 1.0 (the License); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at:
//
// http://www.netfpga-cic.org
//
// Unless required by applicable law or agreed to in writing, Work distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// @NETFPGA_LICENSE_HEADER_END@
/*******************************************************************************
 *  File:
 *        packet_cutter.v
 *
 *  Author:
 *        Gianni Antichi
 *
 *  Description:
 *        Hardwire the hardware interfaces to CPU and vice versa
 */


   module packet_cutter
   #(
       //Master AXI Stream Data Width
          parameter C_M_AXIS_DATA_WIDTH=1024,
          parameter C_S_AXIS_DATA_WIDTH=1024,
          parameter C_M_AXIS_TUSER_WIDTH=128,
          parameter C_S_AXIS_TUSER_WIDTH=128,
          parameter C_S_AXI_DATA_WIDTH=32,
          parameter HASH_WIDTH=128
   )
   (
       // Global Ports
          input axi_aclk,
          input axi_resetn,

       // Master Stream Ports (interface to data path)
          output reg [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_tdata,
          output reg [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tstrb,
          output reg [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_tuser,
          output reg m_axis_tvalid,
          input  m_axis_tready,
          output reg m_axis_tlast,

       // Slave Stream Ports (interface to RX queues)
          input [C_S_AXIS_DATA_WIDTH - 1:0] s_axis_tdata,
          input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_tstrb,
          input [C_S_AXIS_TUSER_WIDTH-1:0] s_axis_tuser,
          input  s_axis_tvalid,
          output s_axis_tready,
          input  s_axis_tlast,
 
       // pkt cut
          input cut_en,
          input [C_S_AXI_DATA_WIDTH-1:0] cut_offset,
          input [C_S_AXI_DATA_WIDTH-1:0] cut_words,
          input [C_S_AXI_DATA_WIDTH-1:0] cut_bytes,
          input hash_en
   );


   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   //--------------------- Internal Parameter-------------------------

   localparam NUM_STATES        = 7;
   localparam WAIT_PKT          = 1;
   localparam IN_PACKET         = 2;
   localparam START_HASH        = 4;
   localparam COMPLETE_PKT      = 8;
   localparam SEND_LAST_WORD    = 16;
   localparam CUT_PACKET        = 32;
   localparam CUT_PACKET_WAIT   = 64;

   localparam MAX_WORDS_PKT     = 2048;
   localparam HASH_BYTES        = (HASH_WIDTH)>>3;
   localparam ALL_VALID         = 32'hffffffff; 

   localparam BYTES_ONE_WORD    = C_M_AXIS_DATA_WIDTH >>3;
   localparam COUNT_BIT_WIDTH   = log2(C_M_AXIS_DATA_WIDTH);
   localparam COUNT_BYTE_WIDTH  = COUNT_BIT_WIDTH-3;

   //---------------------- Wires and regs---------------------------

   reg [C_S_AXI_DATA_WIDTH-1:0]           pkt_cut_count, pkt_cut_count_next;

   reg [C_S_AXI_DATA_WIDTH-1:0]           cut_counter, cut_counter_next;
   reg [C_S_AXI_DATA_WIDTH-1:0]           tstrb_cut,tstrb_cut_next; 

   reg [NUM_STATES-1:0]                   state,state_next;

   wire [C_S_AXIS_TUSER_WIDTH-1:0]        tuser_fifo;
   wire [((C_M_AXIS_DATA_WIDTH/8))-1:0]   tstrb_fifo;
   wire                                   tlast_fifo;
   wire [C_M_AXIS_DATA_WIDTH-1:0]         tdata_fifo;

   reg                                    in_fifo_rd_en;
   wire                                   in_fifo_nearly_full;
   wire                                   in_fifo_empty;

   wire [C_S_AXI_DATA_WIDTH-1:0]          counter;

   reg                                    pkt_short,pkt_short_next;

   wire[C_S_AXIS_DATA_WIDTH-1:0]          first_word_hash;
   wire[C_S_AXIS_DATA_WIDTH-1:0]          last_word_hash;
   wire[C_S_AXIS_DATA_WIDTH-1:0]          one_word_hash;
   wire[C_S_AXIS_DATA_WIDTH-1:0]          final_hash;

   reg[COUNT_BYTE_WIDTH-1:0]              last_word_bytes_free;
   reg[COUNT_BIT_WIDTH-1:0]               pkt_boundaries_bits_free;         

   reg[COUNT_BYTE_WIDTH-1:0]              bytes_free,bytes_free_next;
   reg[COUNT_BIT_WIDTH-1:0]               bits_free,bits_free_next;
   reg[COUNT_BYTE_WIDTH-1:0]              hash_carry_bytes,hash_carry_bytes_next;
   reg[COUNT_BIT_WIDTH-1:0]               hash_carry_bits,hash_carry_bits_next;

   reg [C_S_AXIS_DATA_WIDTH-1:0]          hash;
   reg [C_S_AXIS_DATA_WIDTH-1:0]          hash_next;

   reg [C_S_AXIS_DATA_WIDTH-1:0]          last_word_pkt_temp,last_word_pkt_temp_next;
   wire[C_S_AXIS_DATA_WIDTH-1:0]          last_word_pkt_temp_cleaned;

   wire[15:0]                             len_pkt_cut;
   wire                                   pkt_cuttable;
   wire[15:0]                             pkt_len;

   //------------------------- Modules-------------------------------


   fallthrough_small_fifo
   #(
       .WIDTH(C_M_AXIS_DATA_WIDTH+C_M_AXIS_TUSER_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
       .MAX_DEPTH_BITS(3)
   )
   pkt_fifo
   (   .din ({s_axis_tlast, s_axis_tuser, s_axis_tstrb, s_axis_tdata}),     // Data in
       .wr_en (s_axis_tvalid & ~in_fifo_nearly_full),               // Write enable
       .rd_en (in_fifo_rd_en),       // Read the next word
       .dout ({tlast_fifo, tuser_fifo, tstrb_fifo, tdata_fifo}),
       .full (),
       .prog_full (),
       .nearly_full (in_fifo_nearly_full),
       .empty (in_fifo_empty),
       .reset (~axi_resetn),
       .clk (axi_aclk));

   assign s_axis_tready = !in_fifo_nearly_full;

   assign counter = (cut_en) ? cut_words : MAX_WORDS_PKT;

   assign len_pkt_cut = (hash_en) ? cut_bytes : cut_bytes + HASH_BYTES;
   assign pkt_cuttable = (tuser_fifo[15:0] > len_pkt_cut && len_pkt_cut >= 64);
   assign pkt_len = (cut_en & pkt_cuttable) ? len_pkt_cut : tuser_fifo[15:0];

   assign first_word_hash = (~(({C_S_AXIS_DATA_WIDTH{1'b1}}<<bits_free))&tdata_fifo);
   assign last_word_hash  = (({C_S_AXIS_DATA_WIDTH{1'b1}}<<pkt_boundaries_bits_free)&tdata_fifo);

   assign last_word_pkt_temp_cleaned = (({C_S_AXIS_DATA_WIDTH{1'b1}}<<bits_free)&last_word_pkt_temp);

   assign one_word_hash   = ((~({C_S_AXIS_DATA_WIDTH{1'b1}}<<bits_free))&({C_S_AXIS_DATA_WIDTH{1'b1}}<<pkt_boundaries_bits_free)&tdata_fifo);
   assign final_hash      = {{HASH_WIDTH{1'b0}},hash[HASH_WIDTH-1:0]^hash[(2*HASH_WIDTH)-1:HASH_WIDTH]};
   //assign final_hash      = 128'hdeadbeefaccafeafddddeaeaccffadad; //DEBUG fixed value

   always @(*) begin
      pkt_boundaries_bits_free = 0;
      case(tstrb_fifo)
         128'h80000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd1016;
         128'hc0000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd1008;
         128'he0000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd1000;
         128'hf0000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd992 ;
         128'hf8000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd984 ;
         128'hfc000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd976 ;
         128'hfe000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd968 ;
         128'hff000000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd960 ;
         128'hff800000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd952 ;
         128'hffc00000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd944 ;
         128'hffe00000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd936 ;
         128'hfff00000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd928 ;
         128'hfff80000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd920 ;
         128'hfffc0000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd912 ;
         128'hfffe0000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd904 ;
         128'hffff0000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd896 ;
         128'hffff8000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd888 ;
         128'hffffc000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd880 ;
         128'hffffe000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd872 ;
         128'hfffff000_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd864 ;
         128'hfffff800_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd856 ;
         128'hfffffc00_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd848 ;
         128'hfffffe00_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd840 ;
         128'hffffff00_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd832 ;
         128'hffffff80_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd824 ;
         128'hffffffc0_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd816 ;
         128'hffffffe0_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd808 ;
         128'hfffffff0_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd800 ;
         128'hfffffff8_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd792 ;
         128'hfffffffc_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd784 ;
         128'hfffffffe_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd776 ;
         128'hffffffff_00000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd768 ;
         128'hffffffff_80000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd760 ;
         128'hffffffff_c0000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd752 ;
         128'hffffffff_e0000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd744 ;
         128'hffffffff_f0000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd736 ;
         128'hffffffff_f8000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd728 ;
         128'hffffffff_fc000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd720 ;
         128'hffffffff_fe000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd712 ;
         128'hffffffff_ff000000_00000000_00000000:   pkt_boundaries_bits_free = 10'd704 ;
         128'hffffffff_ff800000_00000000_00000000:   pkt_boundaries_bits_free = 10'd696 ;
         128'hffffffff_ffc00000_00000000_00000000:   pkt_boundaries_bits_free = 10'd688 ;
         128'hffffffff_ffe00000_00000000_00000000:   pkt_boundaries_bits_free = 10'd680 ;
         128'hffffffff_fff00000_00000000_00000000:   pkt_boundaries_bits_free = 10'd672 ;
         128'hffffffff_fff80000_00000000_00000000:   pkt_boundaries_bits_free = 10'd664 ;
         128'hffffffff_fffc0000_00000000_00000000:   pkt_boundaries_bits_free = 10'd656 ;
         128'hffffffff_fffe0000_00000000_00000000:   pkt_boundaries_bits_free = 10'd648 ;
         128'hffffffff_ffff0000_00000000_00000000:   pkt_boundaries_bits_free = 10'd640 ;
         128'hffffffff_ffff8000_00000000_00000000:   pkt_boundaries_bits_free = 10'd632 ;
         128'hffffffff_ffffc000_00000000_00000000:   pkt_boundaries_bits_free = 10'd624 ;
         128'hffffffff_ffffe000_00000000_00000000:   pkt_boundaries_bits_free = 10'd616 ;
         128'hffffffff_fffff000_00000000_00000000:   pkt_boundaries_bits_free = 10'd608 ;
         128'hffffffff_fffff800_00000000_00000000:   pkt_boundaries_bits_free = 10'd600 ;
         128'hffffffff_fffffc00_00000000_00000000:   pkt_boundaries_bits_free = 10'd592 ;
         128'hffffffff_fffffe00_00000000_00000000:   pkt_boundaries_bits_free = 10'd584 ;
         128'hffffffff_ffffff00_00000000_00000000:   pkt_boundaries_bits_free = 10'd576 ;
         128'hffffffff_ffffff80_00000000_00000000:   pkt_boundaries_bits_free = 10'd568 ;
         128'hffffffff_ffffffc0_00000000_00000000:   pkt_boundaries_bits_free = 10'd560 ;
         128'hffffffff_ffffffe0_00000000_00000000:   pkt_boundaries_bits_free = 10'd552 ;
         128'hffffffff_fffffff0_00000000_00000000:   pkt_boundaries_bits_free = 10'd544 ;
         128'hffffffff_fffffff8_00000000_00000000:   pkt_boundaries_bits_free = 10'd536 ;
         128'hffffffff_fffffffc_00000000_00000000:   pkt_boundaries_bits_free = 10'd528 ;
         128'hffffffff_fffffffe_00000000_00000000:   pkt_boundaries_bits_free = 10'd520 ;
         128'hffffffff_ffffffff_00000000_00000000:   pkt_boundaries_bits_free = 10'd512 ;
         128'hffffffff_ffffffff_80000000_00000000:   pkt_boundaries_bits_free = 10'd504 ;
         128'hffffffff_ffffffff_c0000000_00000000:   pkt_boundaries_bits_free = 10'd496 ;
         128'hffffffff_ffffffff_e0000000_00000000:   pkt_boundaries_bits_free = 10'd488 ;
         128'hffffffff_ffffffff_f0000000_00000000:   pkt_boundaries_bits_free = 10'd480 ;
         128'hffffffff_ffffffff_f8000000_00000000:   pkt_boundaries_bits_free = 10'd472 ;
         128'hffffffff_ffffffff_fc000000_00000000:   pkt_boundaries_bits_free = 10'd464 ;
         128'hffffffff_ffffffff_fe000000_00000000:   pkt_boundaries_bits_free = 10'd456 ;
         128'hffffffff_ffffffff_ff000000_00000000:   pkt_boundaries_bits_free = 10'd448 ;
         128'hffffffff_ffffffff_ff800000_00000000:   pkt_boundaries_bits_free = 10'd440 ;
         128'hffffffff_ffffffff_ffc00000_00000000:   pkt_boundaries_bits_free = 10'd432 ;
         128'hffffffff_ffffffff_ffe00000_00000000:   pkt_boundaries_bits_free = 10'd424 ;
         128'hffffffff_ffffffff_fff00000_00000000:   pkt_boundaries_bits_free = 10'd416 ;
         128'hffffffff_ffffffff_fff80000_00000000:   pkt_boundaries_bits_free = 10'd408 ;
         128'hffffffff_ffffffff_fffc0000_00000000:   pkt_boundaries_bits_free = 10'd400 ;
         128'hffffffff_ffffffff_fffe0000_00000000:   pkt_boundaries_bits_free = 10'd392 ;
         128'hffffffff_ffffffff_ffff0000_00000000:   pkt_boundaries_bits_free = 10'd384 ;
         128'hffffffff_ffffffff_ffff8000_00000000:   pkt_boundaries_bits_free = 10'd376 ;
         128'hffffffff_ffffffff_ffffc000_00000000:   pkt_boundaries_bits_free = 10'd368 ;
         128'hffffffff_ffffffff_ffffe000_00000000:   pkt_boundaries_bits_free = 10'd360 ;
         128'hffffffff_ffffffff_fffff000_00000000:   pkt_boundaries_bits_free = 10'd352 ;
         128'hffffffff_ffffffff_fffff800_00000000:   pkt_boundaries_bits_free = 10'd344 ;
         128'hffffffff_ffffffff_fffffc00_00000000:   pkt_boundaries_bits_free = 10'd336 ;
         128'hffffffff_ffffffff_fffffe00_00000000:   pkt_boundaries_bits_free = 10'd328 ;
         128'hffffffff_ffffffff_ffffff00_00000000:   pkt_boundaries_bits_free = 10'd320 ;
         128'hffffffff_ffffffff_ffffff80_00000000:   pkt_boundaries_bits_free = 10'd312 ;
         128'hffffffff_ffffffff_ffffffc0_00000000:   pkt_boundaries_bits_free = 10'd304 ;
         128'hffffffff_ffffffff_ffffffe0_00000000:   pkt_boundaries_bits_free = 10'd296 ;
         128'hffffffff_ffffffff_fffffff0_00000000:   pkt_boundaries_bits_free = 10'd288 ;
         128'hffffffff_ffffffff_fffffff8_00000000:   pkt_boundaries_bits_free = 10'd280 ;
         128'hffffffff_ffffffff_fffffffc_00000000:   pkt_boundaries_bits_free = 10'd272 ;
         128'hffffffff_ffffffff_fffffffe_00000000:   pkt_boundaries_bits_free = 10'd264 ;
         128'hffffffff_ffffffff_ffffffff_00000000:   pkt_boundaries_bits_free = 10'd256;
         128'hffffffff_ffffffff_ffffffff_80000000:   pkt_boundaries_bits_free = 10'd248;
         128'hffffffff_ffffffff_ffffffff_c0000000:   pkt_boundaries_bits_free = 10'd240;
         128'hffffffff_ffffffff_ffffffff_e0000000:   pkt_boundaries_bits_free = 10'd232;
         128'hffffffff_ffffffff_ffffffff_f0000000:   pkt_boundaries_bits_free = 10'd224;
         128'hffffffff_ffffffff_ffffffff_f8000000:   pkt_boundaries_bits_free = 10'd216;
         128'hffffffff_ffffffff_ffffffff_fc000000:   pkt_boundaries_bits_free = 10'd208;
         128'hffffffff_ffffffff_ffffffff_fe000000:   pkt_boundaries_bits_free = 10'd200;
         128'hffffffff_ffffffff_ffffffff_ff000000:   pkt_boundaries_bits_free = 10'd192;
         128'hffffffff_ffffffff_ffffffff_ff800000:   pkt_boundaries_bits_free = 10'd184;
         128'hffffffff_ffffffff_ffffffff_ffc00000:   pkt_boundaries_bits_free = 10'd176;
         128'hffffffff_ffffffff_ffffffff_ffe00000:   pkt_boundaries_bits_free = 10'd168;
         128'hffffffff_ffffffff_ffffffff_fff00000:   pkt_boundaries_bits_free = 10'd160;
         128'hffffffff_ffffffff_ffffffff_fff80000:   pkt_boundaries_bits_free = 10'd152;
         128'hffffffff_ffffffff_ffffffff_fffc0000:   pkt_boundaries_bits_free = 10'd144;
         128'hffffffff_ffffffff_ffffffff_fffe0000:   pkt_boundaries_bits_free = 10'd136;
         128'hffffffff_ffffffff_ffffffff_ffff0000:   pkt_boundaries_bits_free = 10'd128;
         128'hffffffff_ffffffff_ffffffff_ffff8000:   pkt_boundaries_bits_free = 10'd120;
         128'hffffffff_ffffffff_ffffffff_ffffc000:   pkt_boundaries_bits_free = 10'd112;
         128'hffffffff_ffffffff_ffffffff_ffffe000:   pkt_boundaries_bits_free = 10'd104;
         128'hffffffff_ffffffff_ffffffff_fffff000:   pkt_boundaries_bits_free = 10'd96 ;
         128'hffffffff_ffffffff_ffffffff_fffff800:   pkt_boundaries_bits_free = 10'd88 ;
         128'hffffffff_ffffffff_ffffffff_fffffc00:   pkt_boundaries_bits_free = 10'd80 ;
         128'hffffffff_ffffffff_ffffffff_fffffe00:   pkt_boundaries_bits_free = 10'd72 ;
         128'hffffffff_ffffffff_ffffffff_ffffff00:   pkt_boundaries_bits_free = 10'd64 ;
         128'hffffffff_ffffffff_ffffffff_ffffff80:   pkt_boundaries_bits_free = 10'd56 ;
         128'hffffffff_ffffffff_ffffffff_ffffffc0:   pkt_boundaries_bits_free = 10'd48 ;
         128'hffffffff_ffffffff_ffffffff_ffffffe0:   pkt_boundaries_bits_free = 10'd40 ;
         128'hffffffff_ffffffff_ffffffff_fffffff0:   pkt_boundaries_bits_free = 10'd32 ;
         128'hffffffff_ffffffff_ffffffff_fffffff8:   pkt_boundaries_bits_free = 10'd24 ;
         128'hffffffff_ffffffff_ffffffff_fffffffc:   pkt_boundaries_bits_free = 10'd16 ;
         128'hffffffff_ffffffff_ffffffff_fffffffe:   pkt_boundaries_bits_free = 10'd8  ;
         128'hffffffff_ffffffff_ffffffff_ffffffff:   pkt_boundaries_bits_free = 10'd0;
         default      :   pkt_boundaries_bits_free = 10'd0;
      endcase
   end

   always @(*) begin
      last_word_bytes_free = 0;
      case(cut_offset)
         128'h80000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd127;
         128'hc0000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd126;
         128'he0000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd125;
         128'hf0000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd124;
         128'hf8000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd123;
         128'hfc000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd122;
         128'hfe000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd121;
         128'hff000000_00000000_00000000_00000000:   last_word_bytes_free = 7'd120;
         128'hff800000_00000000_00000000_00000000:   last_word_bytes_free = 7'd119;
         128'hffc00000_00000000_00000000_00000000:   last_word_bytes_free = 7'd118;
         128'hffe00000_00000000_00000000_00000000:   last_word_bytes_free = 7'd117;
         128'hfff00000_00000000_00000000_00000000:   last_word_bytes_free = 7'd116;
         128'hfff80000_00000000_00000000_00000000:   last_word_bytes_free = 7'd115;
         128'hfffc0000_00000000_00000000_00000000:   last_word_bytes_free = 7'd114;
         128'hfffe0000_00000000_00000000_00000000:   last_word_bytes_free = 7'd113;
         128'hffff0000_00000000_00000000_00000000:   last_word_bytes_free = 7'd112;
         128'hffff8000_00000000_00000000_00000000:   last_word_bytes_free = 7'd111;
         128'hffffc000_00000000_00000000_00000000:   last_word_bytes_free = 7'd110;
         128'hffffe000_00000000_00000000_00000000:   last_word_bytes_free = 7'd109;
         128'hfffff000_00000000_00000000_00000000:   last_word_bytes_free = 7'd108;
         128'hfffff800_00000000_00000000_00000000:   last_word_bytes_free = 7'd107;
         128'hfffffc00_00000000_00000000_00000000:   last_word_bytes_free = 7'd106;
         128'hfffffe00_00000000_00000000_00000000:   last_word_bytes_free = 7'd105;
         128'hffffff00_00000000_00000000_00000000:   last_word_bytes_free = 7'd104;
         128'hffffff80_00000000_00000000_00000000:   last_word_bytes_free = 7'd103;
         128'hffffffc0_00000000_00000000_00000000:   last_word_bytes_free = 7'd102;
         128'hffffffe0_00000000_00000000_00000000:   last_word_bytes_free = 7'd101;
         128'hfffffff0_00000000_00000000_00000000:   last_word_bytes_free = 7'd100;
         128'hfffffff8_00000000_00000000_00000000:   last_word_bytes_free = 7'd99;
         128'hfffffffc_00000000_00000000_00000000:   last_word_bytes_free = 7'd98;
         128'hfffffffe_00000000_00000000_00000000:   last_word_bytes_free = 7'd97;
         128'hffffffff_00000000_00000000_00000000:   last_word_bytes_free = 7'd96;
         128'hffffffff_80000000_00000000_00000000:   last_word_bytes_free = 7'd95;
         128'hffffffff_c0000000_00000000_00000000:   last_word_bytes_free = 7'd94;
         128'hffffffff_e0000000_00000000_00000000:   last_word_bytes_free = 7'd93;
         128'hffffffff_f0000000_00000000_00000000:   last_word_bytes_free = 7'd92;
         128'hffffffff_f8000000_00000000_00000000:   last_word_bytes_free = 7'd91;
         128'hffffffff_fc000000_00000000_00000000:   last_word_bytes_free = 7'd90;
         128'hffffffff_fe000000_00000000_00000000:   last_word_bytes_free = 7'd89;
         128'hffffffff_ff000000_00000000_00000000:   last_word_bytes_free = 7'd88;
         128'hffffffff_ff800000_00000000_00000000:   last_word_bytes_free = 7'd87;
         128'hffffffff_ffc00000_00000000_00000000:   last_word_bytes_free = 7'd86;
         128'hffffffff_ffe00000_00000000_00000000:   last_word_bytes_free = 7'd85;
         128'hffffffff_fff00000_00000000_00000000:   last_word_bytes_free = 7'd84;
         128'hffffffff_fff80000_00000000_00000000:   last_word_bytes_free = 7'd83;
         128'hffffffff_fffc0000_00000000_00000000:   last_word_bytes_free = 7'd82;
         128'hffffffff_fffe0000_00000000_00000000:   last_word_bytes_free = 7'd81;
         128'hffffffff_ffff0000_00000000_00000000:   last_word_bytes_free = 7'd80;
         128'hffffffff_ffff8000_00000000_00000000:   last_word_bytes_free = 7'd79;
         128'hffffffff_ffffc000_00000000_00000000:   last_word_bytes_free = 7'd78;
         128'hffffffff_ffffe000_00000000_00000000:   last_word_bytes_free = 7'd77;
         128'hffffffff_fffff000_00000000_00000000:   last_word_bytes_free = 7'd76;
         128'hffffffff_fffff800_00000000_00000000:   last_word_bytes_free = 7'd75;
         128'hffffffff_fffffc00_00000000_00000000:   last_word_bytes_free = 7'd74;
         128'hffffffff_fffffe00_00000000_00000000:   last_word_bytes_free = 7'd73;
         128'hffffffff_ffffff00_00000000_00000000:   last_word_bytes_free = 7'd72;
         128'hffffffff_ffffff80_00000000_00000000:   last_word_bytes_free = 7'd71;
         128'hffffffff_ffffffc0_00000000_00000000:   last_word_bytes_free = 7'd70;
         128'hffffffff_ffffffe0_00000000_00000000:   last_word_bytes_free = 7'd69;
         128'hffffffff_fffffff0_00000000_00000000:   last_word_bytes_free = 7'd68;
         128'hffffffff_fffffff8_00000000_00000000:   last_word_bytes_free = 7'd67;
         128'hffffffff_fffffffc_00000000_00000000:   last_word_bytes_free = 7'd66;
         128'hffffffff_fffffffe_00000000_00000000:   last_word_bytes_free = 7'd65;
         128'hffffffff_ffffffff_00000000_00000000:   last_word_bytes_free = 7'd64;
         128'hffffffff_ffffffff_80000000_00000000:   last_word_bytes_free = 7'd63;
         128'hffffffff_ffffffff_c0000000_00000000:   last_word_bytes_free = 7'd62;
         128'hffffffff_ffffffff_e0000000_00000000:   last_word_bytes_free = 7'd61;
         128'hffffffff_ffffffff_f0000000_00000000:   last_word_bytes_free = 7'd60;
         128'hffffffff_ffffffff_f8000000_00000000:   last_word_bytes_free = 7'd59;
         128'hffffffff_ffffffff_fc000000_00000000:   last_word_bytes_free = 7'd58;
         128'hffffffff_ffffffff_fe000000_00000000:   last_word_bytes_free = 7'd57;
         128'hffffffff_ffffffff_ff000000_00000000:   last_word_bytes_free = 7'd56;
         128'hffffffff_ffffffff_ff800000_00000000:   last_word_bytes_free = 7'd55;
         128'hffffffff_ffffffff_ffc00000_00000000:   last_word_bytes_free = 7'd54;
         128'hffffffff_ffffffff_ffe00000_00000000:   last_word_bytes_free = 7'd53;
         128'hffffffff_ffffffff_fff00000_00000000:   last_word_bytes_free = 7'd52;
         128'hffffffff_ffffffff_fff80000_00000000:   last_word_bytes_free = 7'd51;
         128'hffffffff_ffffffff_fffc0000_00000000:   last_word_bytes_free = 7'd50;
         128'hffffffff_ffffffff_fffe0000_00000000:   last_word_bytes_free = 7'd49;
         128'hffffffff_ffffffff_ffff0000_00000000:   last_word_bytes_free = 7'd48;
         128'hffffffff_ffffffff_ffff8000_00000000:   last_word_bytes_free = 7'd47;
         128'hffffffff_ffffffff_ffffc000_00000000:   last_word_bytes_free = 7'd46;
         128'hffffffff_ffffffff_ffffe000_00000000:   last_word_bytes_free = 7'd45;
         128'hffffffff_ffffffff_fffff000_00000000:   last_word_bytes_free = 7'd44;
         128'hffffffff_ffffffff_fffff800_00000000:   last_word_bytes_free = 7'd43;
         128'hffffffff_ffffffff_fffffc00_00000000:   last_word_bytes_free = 7'd42;
         128'hffffffff_ffffffff_fffffe00_00000000:   last_word_bytes_free = 7'd41;
         128'hffffffff_ffffffff_ffffff00_00000000:   last_word_bytes_free = 7'd40;
         128'hffffffff_ffffffff_ffffff80_00000000:   last_word_bytes_free = 7'd39;
         128'hffffffff_ffffffff_ffffffc0_00000000:   last_word_bytes_free = 7'd38;
         128'hffffffff_ffffffff_ffffffe0_00000000:   last_word_bytes_free = 7'd37;
         128'hffffffff_ffffffff_fffffff0_00000000:   last_word_bytes_free = 7'd36;
         128'hffffffff_ffffffff_fffffff8_00000000:   last_word_bytes_free = 7'd35;
         128'hffffffff_ffffffff_fffffffc_00000000:   last_word_bytes_free = 7'd34;
         128'hffffffff_ffffffff_fffffffe_00000000:   last_word_bytes_free = 7'd33;
         128'hffffffff_ffffffff_ffffffff_00000000:   last_word_bytes_free = 7'd32;
         128'hffffffff_ffffffff_ffffffff_80000000:   last_word_bytes_free = 7'd31;
         128'hffffffff_ffffffff_ffffffff_c0000000:   last_word_bytes_free = 7'd30;
         128'hffffffff_ffffffff_ffffffff_e0000000:   last_word_bytes_free = 7'd29;
         128'hffffffff_ffffffff_ffffffff_f0000000:   last_word_bytes_free = 7'd28;
         128'hffffffff_ffffffff_ffffffff_f8000000:   last_word_bytes_free = 7'd27;
         128'hffffffff_ffffffff_ffffffff_fc000000:   last_word_bytes_free = 7'd26;
         128'hffffffff_ffffffff_ffffffff_fe000000:   last_word_bytes_free = 7'd25;
         128'hffffffff_ffffffff_ffffffff_ff000000:   last_word_bytes_free = 7'd24;
         128'hffffffff_ffffffff_ffffffff_ff800000:   last_word_bytes_free = 7'd23;
         128'hffffffff_ffffffff_ffffffff_ffc00000:   last_word_bytes_free = 7'd22;
         128'hffffffff_ffffffff_ffffffff_ffe00000:   last_word_bytes_free = 7'd21;
         128'hffffffff_ffffffff_ffffffff_fff00000:   last_word_bytes_free = 7'd20;
         128'hffffffff_ffffffff_ffffffff_fff80000:   last_word_bytes_free = 7'd19;
         128'hffffffff_ffffffff_ffffffff_fffc0000:   last_word_bytes_free = 7'd18;
         128'hffffffff_ffffffff_ffffffff_fffe0000:   last_word_bytes_free = 7'd17;
         128'hffffffff_ffffffff_ffffffff_ffff0000:   last_word_bytes_free = 7'd16;
         128'hffffffff_ffffffff_ffffffff_ffff8000:   last_word_bytes_free = 7'd15;
         128'hffffffff_ffffffff_ffffffff_ffffc000:   last_word_bytes_free = 7'd14;
         128'hffffffff_ffffffff_ffffffff_ffffe000:   last_word_bytes_free = 7'd13;
         128'hffffffff_ffffffff_ffffffff_fffff000:   last_word_bytes_free = 7'd12;
         128'hffffffff_ffffffff_ffffffff_fffff800:   last_word_bytes_free = 7'd11;
         128'hffffffff_ffffffff_ffffffff_fffffc00:   last_word_bytes_free = 7'd10;
         128'hffffffff_ffffffff_ffffffff_fffffe00:   last_word_bytes_free = 7'd9;
         128'hffffffff_ffffffff_ffffffff_ffffff00:   last_word_bytes_free = 7'd8;
         128'hffffffff_ffffffff_ffffffff_ffffff80:   last_word_bytes_free = 7'd7;
         128'hffffffff_ffffffff_ffffffff_ffffffc0:   last_word_bytes_free = 7'd6;
         128'hffffffff_ffffffff_ffffffff_ffffffe0:   last_word_bytes_free = 7'd5;
         128'hffffffff_ffffffff_ffffffff_fffffff0:   last_word_bytes_free = 7'd4;
         128'hffffffff_ffffffff_ffffffff_fffffff8:   last_word_bytes_free = 7'd3;
         128'hffffffff_ffffffff_ffffffff_fffffffc:   last_word_bytes_free = 7'd2;
         128'hffffffff_ffffffff_ffffffff_fffffffe:   last_word_bytes_free = 7'd1;
         128'hffffffff_ffffffff_ffffffff_ffffffff:   last_word_bytes_free = 7'd0;
         default      :   last_word_bytes_free = 7'd0;
      endcase
   end

   always @(*) begin
      m_axis_tuser = tuser_fifo;
      m_axis_tstrb = tstrb_fifo;
      m_axis_tlast = tlast_fifo;
      m_axis_tdata = tdata_fifo;
      m_axis_tvalid = 0;
      in_fifo_rd_en = 0;
      state_next = WAIT_PKT;
      cut_counter_next = cut_counter;
      pkt_cut_count_next = 1;
      tstrb_cut_next = tstrb_cut;
      bytes_free_next = bytes_free;
      bits_free_next = bits_free;
      hash_carry_bytes_next = hash_carry_bytes;
      hash_carry_bits_next = hash_carry_bits;
      pkt_short_next = pkt_short;
      hash_next = hash;
      last_word_pkt_temp_next = last_word_pkt_temp;
   
      case(state)
         WAIT_PKT: begin
            cut_counter_next = counter;
            tstrb_cut_next = cut_offset;
            if(!in_fifo_empty) begin
               m_axis_tvalid = 1;
               m_axis_tuser[15:0] = pkt_len;
               if(!pkt_cuttable)
                  pkt_short_next = 1;
               else
                  pkt_short_next = 0;
               bytes_free_next = last_word_bytes_free;
               bits_free_next = (last_word_bytes_free<<3);
               if(m_axis_tready) begin
                  in_fifo_rd_en = 1;
                  if (pkt_cuttable && hash_en) begin
                     pkt_cut_count_next = pkt_cut_count + 1;
                     state_next = CUT_PACKET;
                  end
                  else begin
                     state_next = (tlast_fifo) ? WAIT_PKT : IN_PACKET;
                  end
               end
            end
         end

         IN_PACKET: begin
             state_next = IN_PACKET;
            if(!in_fifo_empty) begin
               if(!cut_counter) begin
                  if(tlast_fifo) begin
                     if(pkt_short) begin
                        m_axis_tvalid = 1;
                        if(m_axis_tready) begin
                           in_fifo_rd_en = 1;
                           state_next = WAIT_PKT;
                        end
                     end
                     else begin
                        last_word_pkt_temp_next = tdata_fifo;
                        hash_next = one_word_hash;
                        state_next = COMPLETE_PKT;
                     end
                  end
                  else begin
                     last_word_pkt_temp_next = tdata_fifo;
                     hash_next = first_word_hash;
                     in_fifo_rd_en = 1;
                     state_next = START_HASH;
                  end
               end
               else begin
                  m_axis_tvalid = 1;
                  if(m_axis_tready) begin
                     in_fifo_rd_en = 1;
                     if(tlast_fifo)
                        state_next = WAIT_PKT;
                     else
                        cut_counter_next = cut_counter-1;
                  end
               end
            end
         end

         START_HASH: begin
            state_next = START_HASH;
            if(tlast_fifo) begin 
               hash_next = hash ^ last_word_hash;
               state_next = COMPLETE_PKT;
            end
            else begin
               if(!in_fifo_empty) begin
                  in_fifo_rd_en = 1;
                  hash_next = hash ^ tdata_fifo;
               end
            end
         end

         COMPLETE_PKT: begin
            state_next = COMPLETE_PKT;
            m_axis_tvalid = 1;
            if(m_axis_tready) begin
               in_fifo_rd_en = 1;
               if(bytes_free < HASH_BYTES) begin
                  m_axis_tstrb = ALL_VALID;
                  hash_carry_bytes_next = HASH_BYTES[COUNT_BYTE_WIDTH-1:0] - bytes_free;
                  hash_carry_bits_next = (HASH_BYTES[COUNT_BYTE_WIDTH-1:0] - bytes_free)<<3;
                  m_axis_tlast = 0;
                  m_axis_tdata = (last_word_pkt_temp_cleaned | (final_hash >> (HASH_WIDTH-bits_free)));
                  state_next = SEND_LAST_WORD;
               end
               else begin
                  m_axis_tlast = 1;
                  m_axis_tdata = (last_word_pkt_temp_cleaned | (final_hash << (bits_free-HASH_WIDTH)));
                  m_axis_tstrb = (ALL_VALID<<(bytes_free-HASH_BYTES));
                  state_next = WAIT_PKT;
               end
            end
         end

         SEND_LAST_WORD: begin
            m_axis_tvalid = 1;
               state_next = SEND_LAST_WORD;
            if(m_axis_tready) begin
               m_axis_tlast = 1;
               m_axis_tdata = (final_hash)<<(C_S_AXIS_DATA_WIDTH-hash_carry_bits);
               m_axis_tstrb = (ALL_VALID<<(BYTES_ONE_WORD[COUNT_BYTE_WIDTH-1:0]-hash_carry_bytes));
               state_next = WAIT_PKT;
            end
         end

         CUT_PACKET: begin
            state_next = CUT_PACKET;
            m_axis_tvalid = 1;
            m_axis_tuser = 0;
            if (m_axis_tready && !in_fifo_empty) begin
               in_fifo_rd_en = 1;
               pkt_cut_count_next = pkt_cut_count + 1;
               if ((len_pkt_cut[15:5] + |len_pkt_cut[4:0]) == pkt_cut_count) begin
                  m_axis_tlast = 1;
                  state_next = (tlast_fifo) ? WAIT_PKT : CUT_PACKET_WAIT;
                  case (len_pkt_cut[4:0])
                     5'h00: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffffff;
                     end
                     5'h01: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'h80000000;
                     end
                     5'h02: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hc0000000;
                     end
                     5'h03: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'he0000000;
                     end
                     5'h04: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hf0000000;
                     end
                     5'h05: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hf8000000;
                     end
                     5'h06: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfc00000;
                     end
                     5'h07: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfe000000;
                     end
                     5'h08: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hff000000;
                     end
                     5'h09: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hff800000;
                     end
                     5'h0a: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffc00000;
                     end
                     5'h0b: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffe00000;
                     end
                     5'h0c: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfff00000;
                     end
                     5'h0d: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfff80000;
                     end
                     5'h0e: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffc0000;
                     end
                     5'h0f: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffe0000;
                     end
                     5'h10: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffff0000;
                     end
                     5'h11: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfff8000;
                     end
                     5'h12: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffc000;
                     end
                     5'h13: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffe000;
                     end
                     5'h14: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffff000;
                     end
                     5'h15: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffff800;
                     end
                     5'h16: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffffc00;
                     end
                     5'h17: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffffe00;
                     end
                     5'h18: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffff00;
                     end
                     5'h19: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffff80;
                     end
                     5'h1a: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffffc0;
                     end
                     5'h1b: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hffffffe0;
                     end
                     5'h1c: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffffff0;
                     end
                     5'h1d: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffffff8;
                     end
                     5'h1e: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffffffc;
                     end
                     5'h1f: begin
                        m_axis_tdata = tdata_fifo;
                        m_axis_tstrb = 32'hfffffffe;
                     end
                  endcase
               end
               else begin
                  m_axis_tdata = tdata_fifo;
                  m_axis_tstrb = tstrb_fifo;
                  m_axis_tlast = 0;
                  pkt_cut_count_next = pkt_cut_count + 1;
                  state_next = CUT_PACKET;
               end
            end
            else begin
               pkt_cut_count_next = pkt_cut_count;
               state_next = CUT_PACKET;
            end
         end

      CUT_PACKET_WAIT: begin
         m_axis_tvalid = 0;
         m_axis_tdata = 0;
         m_axis_tstrb = 0;
         m_axis_tuser = 0;
         m_axis_tlast = 0;
         if (!in_fifo_empty) begin
            in_fifo_rd_en = 1;
            state_next = (tlast_fifo) ? WAIT_PKT : CUT_PACKET_WAIT;
         end
         else begin
            state_next = CUT_PACKET_WAIT;
         end
      end

      endcase // case(state)
   end // always @ (*)

   always @(posedge axi_aclk) begin
      if(~axi_resetn) begin
         state       <= WAIT_PKT;
         cut_counter   <= 0;
         pkt_cut_count   <= 0;
         tstrb_cut   <= 0;
         bytes_free    <= 0;
         bits_free    <= 0;
         hash_carry_bytes<= 0;
         hash_carry_bits <= 0;
         hash       <= 0;
         pkt_short       <= 0;
         last_word_pkt_temp<=0;
      end
      else begin
         state <= state_next;

         bytes_free <= bytes_free_next;
         bits_free <= bits_free_next;
         hash_carry_bytes <= hash_carry_bytes_next;
         hash_carry_bits <= hash_carry_bits_next;

         pkt_short    <= pkt_short_next;

         hash <= hash_next;

         cut_counter <= cut_counter_next;
         pkt_cut_count <= pkt_cut_count_next;
         tstrb_cut <= tstrb_cut_next;

         last_word_pkt_temp <= last_word_pkt_temp_next;
      end
   end
   endmodule // output_port_lookup
