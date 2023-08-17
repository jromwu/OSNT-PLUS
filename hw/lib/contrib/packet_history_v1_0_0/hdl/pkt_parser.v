/*******************************************************************************
*
* Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
*                          Junior University
* Copyright (C) 2010, 2011 Muhammad Shahbaz
* Copyright (C) 2015 Gianni Antichi
* Copyright (C) 2021 Yuta Tokusashi
* Copyright (C) 2023 Gianni Antichi
* All rights reserved.
*
* This software was developed by
* Stanford University and the University of Cambridge Computer Laboratory
* under National Science Foundation under Grant No. CNS-0855268,
* the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
* by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
* as part of the DARPA MRC research programme,
* and by the University of Cambridge Computer Laboratory under EPSRC EARL Project
* EP/P025374/1 alongside support from Xilinx Inc.
*
* @NETFPGA_LICENSE_HEADER_START@
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*  http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*
* @NETFPGA_LICENSE_HEADER_END@
*
********************************************************************************/


  module pkt_parser
    #(parameter C_S_AXIS_DATA_WIDTH	   = 512,
      parameter C_S_AXIS_TUSER_WIDTH	= 128,
      parameter TUPLE_WIDTH            = 112
      )
   (// --- Input signals
    input [C_S_AXIS_DATA_WIDTH-1:0]    tdata,
    input                              tvalid,
    input                              tlast,
    input [C_S_AXIS_TUSER_WIDTH-1:0]   tuser,
   
    // --- Output signals
    output reg [TUPLE_WIDTH-1:0]       tuple, 
    output reg                         tuple_valid,

    // --- Misc
    input                              reset,
    input                              clk
   );

   //------------------ Internal Parameter ---------------------------
   //localparam	ETH_ARP	= 16'h0806;	// byte order = Big Endian
   //localparam	ETH_IP 	= 16'h0800;	// byte order = Big Endian
   //localparam  DST_MAC_POS = C_S_AXIS_DATA_WIDTH;
   //localparam  ETHTYPE_POS = C_S_AXIS_DATA_WIDTH - 96; (not used but useful reminder for parsing: taken from the NetFPGA router project)


   localparam  IDLE		   = 1;
   localparam  WAIT_NEXT	= 2;

   localparam  SRC_IP_POS = C_S_AXIS_DATA_WIDTH - 208; // L2 header = 48+48+16; L3 header before IPs is 32+32+32
   localparam  DST_IP_POS = C_S_AXIS_DATA_WIDTH - 240; // SRC_IP_POS + 32
   localparam  SRC_L4_PORT_POS = C_S_AXIS_DATA_WIDTH - 272; // DST_IP_POS + 32
   localparam  DST_L4_PORT_POS = C_S_AXIS_DATA_WIDTH - 288; // SRC_L4_PORT_POS + 16


   //---------------------- Wires/Regs -------------------------------
   reg [TUPLE_WIDTH-1:0]	tuple_next;
   reg                  	tuple_valid_next;

   reg [1:0]            	state, state_next;

   /******************************************************************
    * Get the L3/L4 destination, source and length of the pkt
    *****************************************************************/
   always @(*) begin
      tuple_valid_next = 0;
      tuple_next = tuple;
      state_next = state;

      case(state)

         IDLE: begin
            if(tvalid) begin
               tuple_next = {tdata[SRC_IP_POS-1:SRC_IP_POS-32],tdata[DST_IP_POS-1:DST_IP_POS-32],tdata[SRC_L4_PORT_POS-1:SRC_L4_PORT_POS-16],tdata[DST_L4_PORT_POS-1:DST_L4_PORT_POS-16],tuser[15:0]}; //{src_ip,dst_ip,src_l4_port,dst_l4_port,pkt_length}
               tuple_valid_next = 1;
               if(!tlast)
                  state_next	= WAIT_NEXT;
            end
         end

         WAIT_NEXT: begin
            if(tlast) begin
               state_next = IDLE;
            end
         end

      endcase // case(state)
   end // always @(*)

   always @(posedge clk) begin
      if(reset) begin
         state	      <= IDLE;
         tuple	      <= 0;
         tuple_valid <= 0;
      end
      else begin
         state		   <= state_next;
         tuple	      <= tuple_next;
         tuple_valid <= tuple_valid_next;
      end
   end

endmodule // pkt_parser


