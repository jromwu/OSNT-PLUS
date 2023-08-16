//-
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
//                          Junior University
// Copyright (C) 2010, 2011 Muhammad Shahbaz
// Copyright (C) 2015 Gianni Antichi, Noa Zilberman, Salvator Galea
// All rights reserved.
//
// This software was developed by
// Stanford University and the University of Cambridge Computer Laboratory
// under National Science Foundation under Grant No. CNS-0855268,
// the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
// by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
// as part of the DARPA MRC research programme.
//
// @NETFPGA_LICENSE_HEADER_START@
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// @NETFPGA_LICENSE_HEADER_END@
//

module packet_history
#(
   // -- Master AXI Stream Data Width
   parameter C_M_AXIS_DATA_WIDTH	   = 512,
   parameter C_S_AXIS_DATA_WIDTH	   = 512,
   parameter C_M_AXIS_TUSER_WIDTH	= 128,
   parameter C_S_AXIS_TUSER_WIDTH	= 128
   
)
(
   // -- Global Ports
   input                                      axis_aclk,
   input                                      axis_resetn,

   // -- Master Stream Ports (interface to data path)
   output reg [C_M_AXIS_DATA_WIDTH - 1:0]          m_axis_tdata,
   output reg [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0]  m_axis_tkeep,
   output reg [C_M_AXIS_TUSER_WIDTH-1:0]           m_axis_tuser,
   output reg                                      m_axis_tvalid,
   input                                           m_axis_tready,
   output reg                                      m_axis_tlast,

   // -- Slave Stream Ports (interface to RX queues)
   input [C_S_AXIS_DATA_WIDTH - 1:0]          s_axis_tdata,
   input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0]  s_axis_tkeep,
   input [C_S_AXIS_TUSER_WIDTH-1:0]           s_axis_tuser,
   input                                      s_axis_tvalid,
   output                                     s_axis_tready,
   input                                      s_axis_tlast
   
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

  localparam NUM_QUEUES          = 8;
  localparam NUM_QUEUES_WIDTH    = log2(NUM_QUEUES);
  localparam NUM_CORES_HISTORY   = 16;
  localparam NUM_CORES_BITS      = log2(NUM_CORES_HISTORY);
  localparam TUPLE_WIDTH         = 112; // 32 (SRC_IP) + 32 (DST_IP) + 16 (SRC_L4_PORT) + 16 (DST_L4_PORT) + 16 (PKT_LENGTH) 

  localparam SRC_PORT_POS        = 16;
  localparam DST_PORT_POS        = 24;

  localparam NUM_STATES          = 5;
  localparam FIRST_BATCH         = 1;
  localparam SECOND_BATCH        = 2;
  localparam THIRD_BATCH         = 4;
  localparam FOURTH_BATCH        = 8;
  localparam SEND_PACKET         = 16;

  integer	i; // mem initialization

  // -- Signals
  wire [TUPLE_WIDTH-1:0]   tuple;
  wire                     tuple_valid;
  reg [NUM_STATES-1:0]     state,state_next;

  // packet fifo signals
  wire                              in_fifo_nearly_full;     
  reg                               in_fifo_rd_en;
  wire                              in_fifo_empty;
  wire [C_M_AXIS_DATA_WIDTH-1:0]    in_fifo_tdata;
  wire [C_M_AXIS_TUSER_WIDTH-1:0]   in_fifo_tuser;
  wire [C_M_AXIS_DATA_WIDTH/8-1:0]  in_fifo_tkeep;
  wire                              in_fifo_tlast;    

  // tuple fifo signals
  wire                     tuple_fifo_nearly_full;
  reg                      tuple_fifo_rd_en;
  wire                     tuple_fifo_empty;
  wire [TUPLE_WIDTH-1:0]   tuple_fifo_out;

  // variables related to the internal memory
  reg [TUPLE_WIDTH-1:0]    mem_history[NUM_CORES_BITS-1:0];
  reg [NUM_CORES_BITS-1:0] ptr_pos, ptr_pos_next;
  reg wr_mem_en, wr_mem_en_next;

   /* The size of this fifo has to be large enough to fit the previous modules' headers
    * and the ethernet header */
   xpm_fifo_sync #(
      .FIFO_MEMORY_TYPE     ("auto"),
      .ECC_MODE             ("no_ecc"),
      .FIFO_WRITE_DEPTH     (16),
      .WRITE_DATA_WIDTH     (C_M_AXIS_DATA_WIDTH+C_M_AXIS_TUSER_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
      .WR_DATA_COUNT_WIDTH  (1),
      //.PROG_FULL_THRESH     (PROG_FULL_THRESH),
      .FULL_RESET_VALUE     (0),
      .USE_ADV_FEATURES     ("0707"),
      .READ_MODE            ("fwft"),
      .FIFO_READ_LATENCY    (1),
      .READ_DATA_WIDTH      (C_M_AXIS_DATA_WIDTH+C_M_AXIS_TUSER_WIDTH+C_M_AXIS_DATA_WIDTH/8+1),
      .RD_DATA_COUNT_WIDTH  (1),
      .PROG_EMPTY_THRESH    (10),
      .DOUT_RESET_VALUE     ("0"),
      .WAKEUP_TIME          (0)
   ) input_fifo (
      // Common module ports
      .sleep           (),
      .rst             (~axis_resetn),

      // Write Domain ports
      .wr_clk          (axis_aclk),
      .wr_en           (s_axis_tvalid & s_axis_tready),
      .din             ({s_axis_tlast, s_axis_tuser, s_axis_tkeep, s_axis_tdata}),
      .full            (),
      .prog_full       (in_fifo_nearly_full),
      .wr_data_count   (),
      .overflow        (),
      .wr_rst_busy     (),
      .almost_full     (),
      .wr_ack          (),

      // Read Domain ports
      .rd_en           (in_fifo_rd_en),
      .dout            ({in_fifo_tlast, in_fifo_tuser, in_fifo_tkeep, in_fifo_tdata}),
      .empty           (in_fifo_empty),
      .prog_empty      (),
      .rd_data_count   (),
      .underflow       (),
      .rd_rst_busy     (),
      .almost_empty    (),
      .data_valid      (),

      // ECC Related ports
      .injectsbiterr   (),
      .injectdbiterr   (),
      .sbiterr         (),
      .dbiterr         () 
   );

   /* The size of this fifo has to be large enough to fit the previous modules' headers
    * and the ethernet header */
   xpm_fifo_sync #(
      .FIFO_MEMORY_TYPE     ("auto"),
      .ECC_MODE             ("no_ecc"),
      .FIFO_WRITE_DEPTH     (16),
      .WRITE_DATA_WIDTH     (TUPLE_WIDTH),
      .WR_DATA_COUNT_WIDTH  (1),
      //.PROG_FULL_THRESH     (PROG_FULL_THRESH),
      .FULL_RESET_VALUE     (0),
      .USE_ADV_FEATURES     ("0707"),
      .READ_MODE            ("fwft"),
      .FIFO_READ_LATENCY    (1),
      .READ_DATA_WIDTH      (TUPLE_WIDTH),
      .RD_DATA_COUNT_WIDTH  (1),
      .PROG_EMPTY_THRESH    (10),
      .DOUT_RESET_VALUE     ("0"),
      .WAKEUP_TIME          (0)
   ) tuple_fifo (
      // Common module ports
      .sleep           (),
      .rst             (~axis_resetn),

      // Write Domain ports
      .wr_clk          (axis_aclk),
      .wr_en           (tuple_valid),
      .din             (tuple),
      .full            (),
      .prog_full       (tuple_fifo_nearly_full),
      .wr_data_count   (),
      .overflow        (),
      .wr_rst_busy     (),
      .almost_full     (),
      .wr_ack          (),

      // Read Domain ports
      .rd_en           (tuple_fifo_rd_en),
      .dout            (tuple_fifo_out),
      .empty           (tuple_fifo_empty),
      .prog_empty      (),
      .rd_data_count   (),
      .underflow       (),
      .rd_rst_busy     (),
      .almost_empty    (),
      .data_valid      (),

      // ECC Related ports
      .injectsbiterr   (),
      .injectdbiterr   (),
      .sbiterr         (),
      .dbiterr         () 
   );

   pkt_parser
     #(.C_S_AXIS_DATA_WIDTH (C_S_AXIS_DATA_WIDTH),
       .C_M_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),
       .TUPLE_WIDTH (TUPLE_WIDTH)
       ) pkt_parser
       ( 

      // --- Input
      .tdata         (s_axis_tdata),
      .tvalid        (s_axis_tvalid),
      .tlast         (s_axis_tlast),
      .tuser         (s_axis_tuser),

      // --- Output
      .tuple         (tuple),
      .tuple_valid   (tuple_valid),

      // --- Misc
      // --- Input
      .reset         (~axis_resetn),
      .clk           (axis_aclk)
    );


   always @(*) begin 
      ptr_pos_next = ptr_pos;

      m_axis_tlast = in_fifo_tlast;
      m_axis_tuser = in_fifo_tuser;
      m_axis_tkeep = in_fifo_tkeep; // to set full word length 128{4'hf};
      m_axis_tdata = in_fifo_tdata;
      m_axis_tvalid = 0;

      wr_mem_en_next = 1'b0;

      tuple_fifo_rd_en = 0;
      in_fifo_rd_en = 0;
      
      case(state)

         FIRST_BATCH: begin
            if(!tuple_fifo_empty) begin 
               if(m_axis_tready) begin
                  if(in_fifo_tuser[SRC_PORT_POS])
                     m_axis_tuser[DST_PORT_POS+2] = 1'b1;
                  else if(in_fifo_tuser[SRC_PORT_POS+2])
                      m_axis_tuser[DST_PORT_POS] = 1'b1;
                  m_axis_tvalid = 1;
                  m_axis_tlast = 0;
                  m_axis_tkeep = 64'b1;
                  m_axis_tdata = {mem_history[0],mem_history[1],mem_history[2],mem_history[3],ptr_pos,60'b0};
                  wr_mem_en_next = 1;
                  state_next = SECOND_BATCH;
               end
            end
         end

         SECOND_BATCH: begin
            if(m_axis_tready) begin
               m_axis_tvalid = 1;
               m_axis_tlast = 0;
               m_axis_tkeep = 64'b1;
               m_axis_tdata = {mem_history[4],mem_history[5],mem_history[6],mem_history[7],64'b0};
               tuple_fifo_rd_en = 1;
               ptr_pos_next = ptr_pos + 1;
               state_next = THIRD_BATCH;
            end   
         end

         THIRD_BATCH: begin
            if(m_axis_tready) begin
               m_axis_tvalid = 1;
               m_axis_tlast = 0;
               m_axis_tkeep = 64'b1;
               m_axis_tdata = {mem_history[8],mem_history[9],mem_history[10],mem_history[11],64'b0};
               state_next = FOURTH_BATCH;
            end   
         end

         FOURTH_BATCH: begin
            if(m_axis_tready) begin
               m_axis_tvalid = 1;
               m_axis_tlast = 0;
               m_axis_tkeep = 64'b1;
               m_axis_tdata = {mem_history[12],mem_history[13],mem_history[14],mem_history[15],64'b0};
               state_next = SEND_PACKET;
            end   
         end

         SEND_PACKET: begin
            if(!in_fifo_empty) begin
               if(m_axis_tready) begin
                  m_axis_tvalid = 1;
                  in_fifo_rd_en = 1;
                  if(in_fifo_tlast)
                     state_next = FIRST_BATCH;
               end
            end   
         end
      endcase
   end                     

   always @(posedge clk) begin
      if(reset) begin
         state	      <= IDLE;
         ptr_pos     <= 0;
         wr_mem_en   <= 0;
         for(i=0;i<NUM_CORES_HISTORY;i=i+1)
            mem_history[i] <= 112'b0;
      end
      else begin
         state		<= state_next;
         ptr_pos  <= ptr_pos_next;
         wr_mem_en<= wr_mem_en_next;
         if (wr_mem_en)
            mem_history[ptr_pos] <= tuple;
      end
   end


   
endmodule // packet_history

