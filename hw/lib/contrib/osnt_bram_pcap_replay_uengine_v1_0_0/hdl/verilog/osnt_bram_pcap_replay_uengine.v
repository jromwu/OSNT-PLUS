//
// Copyright (c) 2016-2017 University of Cambridge
// Copyright (c) 2016-2017 Jong Hun Han
// Copyright (c) 2022 Gianni Antichi
// All rights reserved.
//
// This software was developed by University of Cambridge Computer Laboratory
// under the ENDEAVOUR project (grant agreement 644960) as part of
// the European Union's Horizon 2020 research and innovation programme.
//
// @NETFPGA_LICENSE_HEADER_START@
//
// Licensed to NetFPGA Open Systems C.I.C. (NetFPGA) under one or more // contributor license agreements. See the NOTICE file distributed with this
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


`timescale 1ns/1ps
`include "bram_pcap_replay_uengine_cpu_regs_defines.v"
module osnt_bram_pcap_replay_uengine
#(
  parameter C_S_AXI_DATA_WIDTH   = 32,
  parameter C_S_AXI_ADDR_WIDTH   = 12,
  parameter C_BASEADDR           = 32'h00000000,
//   parameter C_BASEADDR           = 32'hFFFFFFFF,
//   parameter C_HIGHADDR           = 32'h00000000,
  parameter C_USE_WSTRB          = 0,
  parameter C_DPHASE_TIMEOUT     = 0,
  parameter C_S_AXI_ACLK_FREQ_HZ = 100,
  parameter C_M_AXIS_DATA_WIDTH  = 512,
  parameter C_S_AXIS_DATA_WIDTH  = 512,
  parameter C_M_AXIS_TUSER_WIDTH = 128,
  parameter C_S_AXIS_TUSER_WIDTH = 128,
  parameter SRC_PORT_POS         = 16,
  parameter QDR_ADDR_WIDTH       = 12,
  parameter REPLAY_COUNT_WIDTH   = 32,
  parameter NUM_QUEUES           = 2,
  parameter SIM_ONLY             = 0,
  parameter MEM_DEPTH            = 11 
)
(
  // Slave AXI Ports
  input                                           s_axi_aclk,
  input                                           s_axi_aresetn,
  input      [C_S_AXI_ADDR_WIDTH-1:0]             s_axi_awaddr,
  input                                           s_axi_awvalid,
  input      [C_S_AXI_DATA_WIDTH-1:0]             s_axi_wdata,
  input      [C_S_AXI_DATA_WIDTH/8-1:0]           s_axi_wstrb,
  input                                           s_axi_wvalid,
  input                                           s_axi_bready,
  input      [C_S_AXI_ADDR_WIDTH-1:0]             s_axi_araddr,
  input                                           s_axi_arvalid,
  input                                           s_axi_rready,
  output                                          s_axi_arready,
  output     [C_S_AXI_DATA_WIDTH-1:0]             s_axi_rdata,
  output     [1:0]                                s_axi_rresp,
  output                                          s_axi_rvalid,
  output                                          s_axi_wready,
  output     [1:0]                                s_axi_bresp,
  output                                          s_axi_bvalid,
  output                                          s_axi_awready,

  // Master Stream Ports (interface to data path)
  input                                                 axis_aclk,
  input                                                 axis_aresetn,

  output   reg   [C_M_AXIS_DATA_WIDTH-1:0]              m0_axis_tdata,
  output   reg   [((C_M_AXIS_DATA_WIDTH/8))-1:0]        m0_axis_tkeep,
  output   reg   [C_M_AXIS_TUSER_WIDTH-1:0]             m0_axis_tuser,
  output   reg                                          m0_axis_tvalid,
  input                                                 m0_axis_tready,
  output   reg                                          m0_axis_tlast,

  output   reg   [C_M_AXIS_DATA_WIDTH-1:0]              m1_axis_tdata,
  output   reg   [((C_M_AXIS_DATA_WIDTH/8))-1:0]        m1_axis_tkeep,
  output   reg   [C_M_AXIS_TUSER_WIDTH-1:0]             m1_axis_tuser,
  output   reg                                          m1_axis_tvalid,
  input                                                 m1_axis_tready,
  output   reg                                          m1_axis_tlast,

  // Slave Stream Ports (interface to RX queues)
  input          [C_S_AXIS_DATA_WIDTH-1:0]              s_axis_tdata,
  input          [((C_S_AXIS_DATA_WIDTH/8))-1:0]        s_axis_tkeep,
  input          [C_S_AXIS_TUSER_WIDTH-1:0]             s_axis_tuser,
  input                                                 s_axis_tvalid,
  output                                                s_axis_tready,
  input                                                 s_axis_tlast,

//  output                                              clka0,
  output         [MEM_DEPTH-1:0]                        addra0,
  output                                                ena0,
  output                                                wea0,
  output         [(C_S_AXI_DATA_WIDTH*23)-1:0]          douta0, // this width has to be consistent with osnt_bram module
  input          [(C_S_AXI_DATA_WIDTH*23)-1:0]          dina0, // this width has to be consistent with osnt_bram module

//  output                                              clka1,
  output         [MEM_DEPTH-1:0]                        addra1,
  output                                                ena1,
  output                                                wea1,
  output         [(C_S_AXI_DATA_WIDTH*23)-1:0]          douta1, // this width has to be consistent with osnt_bram module
  input          [(C_S_AXI_DATA_WIDTH*23)-1:0]          dina1, // this width has to be consistent with osnt_bram module

  output                                                replay_start_out,
  input                                                 replay_start_in
);

integer j;

function integer log2;
   input integer number;
   begin
      log2=0;
      while(2**log2<number) begin
         log2=log2+1;
      end
   end
endfunction//log2

// tvalid, tlast, tuser, tkeep, tdata
localparam MEM_NILL_BIT_NO = (C_S_AXI_DATA_WIDTH*23) - (1 + 1 + C_S_AXIS_TUSER_WIDTH + (C_S_AXIS_DATA_WIDTH/8) + C_S_AXIS_DATA_WIDTH);
localparam MEM_TLAST_POS = C_S_AXIS_TUSER_WIDTH + (C_S_AXIS_DATA_WIDTH/8) + C_S_AXIS_DATA_WIDTH;
localparam MEM_TVALID_POS = 1 + C_S_AXIS_TUSER_WIDTH + (C_S_AXIS_DATA_WIDTH/8) + C_S_AXIS_DATA_WIDTH;

`define  WR_IDLE  0

`define  M0_IDLE  0
`define  M0_SEND  1
`define  M0_CNT   2

`define  M1_IDLE  0
`define  M1_SEND  1
`define  M1_CNT   2

wire  w_replay_trigger;

reg   [3:0] m0_st_current, m0_st_next;
reg   [3:0] m1_st_current, m1_st_next;

// ------------ Internal Params --------
localparam  MAX_PKT_SIZE      = 2000; // In bytes
localparam  IN_FIFO_DEPTH_BIT = log2(MAX_PKT_SIZE/(C_M_AXIS_DATA_WIDTH / 8));
localparam  IN_FIFO_DEPTH = 64;
localparam  DEBUG_PAYLOAD_POS = 112; // After 48 + 48 ethernet src dst, and 16 bit type 

// -- Internal Parameters
localparam NUM_RW_REGS = 14;
localparam NUM_WO_REGS = 0;
localparam NUM_RO_REGS = 0;

// -- Signals
wire  [NUM_RW_REGS*C_S_AXI_DATA_WIDTH:0]           rw_regs;

//REG0 software reset	(0x0000)
//REG1 start replay q0	(0x0004)
//REG2 start replay q1  (0x0008)
//REG3 replay count q0	(0x000c)
//REG4 replay count q1	(0x0010)
//REG5 addr_low q0	(0x0014) note: not used at the moment
//REG6 addr_high q0	(0x0018) note: not used at the moment
//REG7 addr_low q1	(0x001c) note: not used at the moment
//REG8 addr_high q1	(0x0020) note: not used at the moment
//REG9 enable q0	(0x0024) note: not used at the moment
//REG10 enable q1	(0x0028) note: not used at the moment
//REG11 wr_done q0	(0x002c)
//REG12 wr_done q1	(0x0030)
//REG13 conf_path	(0x0034) note: removed.

wire                            sw_rst;

wire  [QDR_ADDR_WIDTH-1:0]      q0_addr_low;  // not used
wire  [QDR_ADDR_WIDTH-1:0]      q0_addr_high; // not used
wire  [QDR_ADDR_WIDTH-1:0]      q1_addr_low;  // not used
wire  [QDR_ADDR_WIDTH-1:0]      q1_addr_high; // not used

wire                            q0_enable; // not used
wire                            q1_enable; // not used

wire                            q0_wr_done;
wire                            q1_wr_done;
                                                  
wire  [REPLAY_COUNT_WIDTH-1:0]  q0_replay_count;
wire  [REPLAY_COUNT_WIDTH-1:0]  q1_replay_count;

reg   [REPLAY_COUNT_WIDTH-1:0]  q0_count, q0_count_next;
reg   [REPLAY_COUNT_WIDTH-1:0]  q1_count, q1_count_next;
                                                 
wire                            q0_start_replay;
wire                            q1_start_replay;

//wire  [C_S_AXI_DATA_WIDTH-1:0]  conf_path;

// ------------- Regs/ wires -----------

localparam  PCAP_DATA_WIDTH = 1 + C_M_AXIS_TUSER_WIDTH + (C_M_AXIS_DATA_WIDTH/8) + C_M_AXIS_DATA_WIDTH;

reg                                	r_wr_clear;
reg   [MEM_DEPTH-1:0]             	r_mem_wr_addr[0:NUM_QUEUES-1];
reg   [(C_S_AXI_DATA_WIDTH*23)-1:0] 	r_mem_wr_data[0:NUM_QUEUES-1];
reg   [NUM_QUEUES-1:0]              	r_mem_wren;
reg   [3:0]                         	r_mem_wr_sel; //not used

reg   [MEM_DEPTH-1:0]             	tmp0_addr, tmp0_addr_next;
reg   [(C_S_AXI_DATA_WIDTH*23)-1:0] 	tmp0_data;
reg   [NUM_QUEUES-1:0]              	tmp0_we;

reg   [MEM_DEPTH-1:0]             	tmp1_addr, tmp1_addr_next;
reg   [(C_S_AXI_DATA_WIDTH*23)-1:0] 	tmp1_data;
reg   [NUM_QUEUES-1:0]              	tmp1_we;

reg                                 	r_rd_clear;
reg   [MEM_DEPTH-1:0]             	r_mem_rd_addr[0:NUM_QUEUES-1], r_mem_rd_addr_next[0:NUM_QUEUES-1];
reg   [(C_S_AXI_DATA_WIDTH*23)-1:0] 	r_mem_rd_data[0:NUM_QUEUES-1];
reg   [NUM_QUEUES-1:0]              	r_mem_rden;
reg   [3:0]                         	r_mem_rd_sel; //not used

reg   [NUM_QUEUES-1:0]  		fifo_rden;
wire  [NUM_QUEUES-1:0]  		fifo_empty;
wire  [NUM_QUEUES-1:0]  		fifo_nearly_full;
reg   [NUM_QUEUES-1:0]  		r_fifo_nearly_full;
wire  [C_M_AXIS_DATA_WIDTH-1:0]        	fifo_in_tdata[0:NUM_QUEUES-1];
wire  [(C_M_AXIS_DATA_WIDTH/8)-1:0]    	fifo_in_tkeep[0:NUM_QUEUES-1];
wire  [C_M_AXIS_TUSER_WIDTH-1:0]       	fifo_in_tuser[0:NUM_QUEUES-1];
wire  [NUM_QUEUES-1:0]                 	fifo_in_tlast;
wire  [NUM_QUEUES-1:0]                 	fifo_in_tvalid;

wire  [C_M_AXIS_DATA_WIDTH-1:0]        	fifo_out_tdata[0:NUM_QUEUES-1];
wire  [(C_M_AXIS_DATA_WIDTH/8)-1:0]    	fifo_out_tkeep[0:NUM_QUEUES-1];
wire  [C_M_AXIS_TUSER_WIDTH-1:0]       	fifo_out_tuser[0:NUM_QUEUES-1];
wire  [NUM_QUEUES-1:0]                 	fifo_out_tlast;

wire  [7:0] tuser_src_port = s_axis_tuser[16+:8];

wire  [C_S_AXIS_DATA_WIDTH-1:0]        	pre_axis_tdata;
wire  [((C_S_AXIS_DATA_WIDTH/8))-1:0]  	pre_axis_tkeep;
wire  [C_S_AXIS_TUSER_WIDTH-1:0]       	pre_axis_tuser;
wire                                   	pre_axis_tvalid;
wire                                   	pre_axis_tready;
wire                                   	pre_axis_tlast;

wire [`REG_CTRL0_BITS]	ip2cpu_ctrl0;
wire [`REG_CTRL0_BITS]	cpu2ip_ctrl0;
wire [`REG_CTRL1_BITS] 	ip2cpu_ctrl1;
wire [`REG_CTRL1_BITS]	cpu2ip_ctrl1;
wire [`REG_CTRL2_BITS]	ip2cpu_ctrl2;
wire [`REG_CTRL2_BITS] 	cpu2ip_ctrl2;
wire [`REG_CTRL3_BITS]	ip2cpu_ctrl3;
wire [`REG_CTRL3_BITS]	cpu2ip_ctrl3;
wire [`REG_CTRL4_BITS] 	ip2cpu_ctrl4;
wire [`REG_CTRL4_BITS] 	cpu2ip_ctrl4;
wire [`REG_CTRL5_BITS] 	ip2cpu_ctrl5;
wire [`REG_CTRL5_BITS] 	cpu2ip_ctrl5;
wire [`REG_CTRL6_BITS] 	ip2cpu_ctrl6;
wire [`REG_CTRL6_BITS]	cpu2ip_ctrl6;
wire [`REG_CTRL7_BITS] 	ip2cpu_ctrl7;
wire [`REG_CTRL7_BITS] 	cpu2ip_ctrl7;
wire [`REG_CTRL8_BITS] 	ip2cpu_ctrl8;
wire [`REG_CTRL8_BITS] 	cpu2ip_ctrl8;
wire [`REG_CTRL9_BITS] 	ip2cpu_ctrl9;
wire [`REG_CTRL9_BITS] 	cpu2ip_ctrl9;
wire [`REG_CTRL10_BITS] ip2cpu_ctrl10;
wire [`REG_CTRL10_BITS]	cpu2ip_ctrl10;
wire [`REG_CTRL11_BITS] ip2cpu_ctrl11;
wire [`REG_CTRL11_BITS]	cpu2ip_ctrl11;
wire [`REG_CTRL12_BITS]	ip2cpu_ctrl12;
wire [`REG_CTRL12_BITS] cpu2ip_ctrl12;
wire [`REG_CTRL13_BITS]	ip2cpu_ctrl13;
wire [`REG_CTRL13_BITS] cpu2ip_ctrl13;

// reg      [31:0] time_counter;
// always @(posedge axis_aclk)
//     if (~axis_aresetn | sw_rst) begin
//       time_counter <= #1 32'h0;
//     end
//     else begin
//       time_counter <= #1 (time_counter==32'hFFFFFFFF) ? 32'h0 : time_counter + 32'h1;
//     end

assign pre_axis_tready = 1;

reg   [MEM_DEPTH-1:0]             	tmp0_last_addr, tmp0_last_addr_next, tmp1_last_addr, tmp1_last_addr_next;

`define  ST0_WR_IDLE    0
`define  ST0_WR         1
`define  ST0_WR_DONE    2

reg   [3:0] st0_wr_current, st0_wr_next;
always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      tmp0_addr      <= 1;
      st0_wr_current <= 0;
      tmp0_last_addr <= 1;
   end
   else if (sw_rst) begin
      tmp0_addr      <= 1;
      st0_wr_current <= 0;
      tmp0_last_addr <= 1;
   end
   else begin
      tmp0_addr      <= tmp0_addr_next;
      st0_wr_current <= st0_wr_next;
      tmp0_last_addr <= (tmp0_last_addr_next != 1) ? tmp0_last_addr_next : tmp0_last_addr;
   end

always @(*) begin
   tmp0_addr_next    = 1;
   tmp0_we           = 0;
   tmp0_data         = 0;
   st0_wr_next       = 0;
   tmp0_last_addr_next = 1;
   case (st0_wr_current)
      `ST0_WR_IDLE : begin
         tmp0_addr_next    = (pre_axis_tvalid && (tuser_src_port == 8'h02)) ? tmp0_addr + 1 : 1;
         tmp0_we           = (pre_axis_tvalid && (tuser_src_port == 8'h02)) ? 1 : 0;
         tmp0_data         = (pre_axis_tvalid && (tuser_src_port == 8'h02)) ? {{MEM_NILL_BIT_NO{1'b0}}, 1'b1, pre_axis_tlast, pre_axis_tuser, pre_axis_tkeep, pre_axis_tdata} : 0;
         st0_wr_next       = (pre_axis_tvalid && (tuser_src_port == 8'h02)) ? `ST0_WR : `ST0_WR_IDLE;
         tmp0_last_addr_next = 1;
      end
      `ST0_WR : begin
         if (sw_rst) begin
            tmp0_addr_next    = 1;
            tmp0_we           = 1;
            tmp0_data         = 0;
            st0_wr_next       = `ST0_WR_IDLE;
            tmp0_last_addr_next = 1;
         end
         else if (q0_wr_done) begin
            tmp0_addr_next    = tmp0_addr + 1;
            tmp0_we           = 1;
            tmp0_data         = {{(MEM_NILL_BIT_NO-1){1'b0}}, 1'b1, 2'b0, {(C_S_AXIS_TUSER_WIDTH+(C_S_AXIS_DATA_WIDTH/8)+C_S_AXIS_DATA_WIDTH){1'b0}}};
            st0_wr_next       = `ST0_WR_DONE;
            tmp0_last_addr_next = tmp0_addr; 
         end
         else if (pre_axis_tvalid) begin
            tmp0_addr_next    = tmp0_addr + 1;
            tmp0_we           = 1;
            tmp0_data         = {{MEM_NILL_BIT_NO{1'b0}}, 1'b1, pre_axis_tlast, pre_axis_tuser, pre_axis_tkeep, pre_axis_tdata};
            st0_wr_next       = `ST0_WR;
            tmp0_last_addr_next = 1;
         end
         else begin
            tmp0_addr_next    = tmp0_addr;
            tmp0_we           = 0;
            tmp0_data         = 0;
            st0_wr_next       = `ST0_WR;
            tmp0_last_addr_next = 1;
         end
      end
      `ST0_WR_DONE : begin
         tmp0_addr_next    = 1;
         tmp0_we           = 1;
         tmp0_data         = 0;
         st0_wr_next       = `ST0_WR_IDLE;
         tmp0_last_addr_next = 1;
      end
   endcase
   // tmp0_data[DEBUG_PAYLOAD_POS+:64] = {tmp0_last_addr_next[7:0], tmp0_last_addr_next[10:8], 5'b0, st0_wr_current, st0_wr_next, tmp0_addr_next[7:0], tmp0_addr[3:0], 1'b0, tmp0_addr_next[10:8], 1'b0, tmp0_addr[10:4]};
end



`define  ST1_WR_IDLE    0
`define  ST1_WR         1
`define  ST1_WR_DONE    2

reg   [3:0] st1_wr_current, st1_wr_next;
always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      tmp1_addr      <= 1;
      st1_wr_current <= 0;
      tmp1_last_addr <= 1;
   end
   else if (sw_rst) begin
      tmp1_addr      <= 1;
      st1_wr_current <= 0;
      tmp1_last_addr <= 1;
   end
   else begin
      tmp1_addr      <= tmp1_addr_next;
      st1_wr_current <= st1_wr_next;
      tmp1_last_addr <= (tmp1_last_addr_next != 1) ? tmp1_last_addr_next : tmp1_last_addr;
   end

always @(*) begin
   tmp1_addr_next    = 1;
   tmp1_we           = 0;
   tmp1_data         = 0;
   st1_wr_next       = 0;
   tmp1_last_addr_next = 1;
   case (st1_wr_current)
      `ST1_WR_IDLE : begin
         tmp1_addr_next    = (pre_axis_tvalid && (tuser_src_port == 8'h08)) ? tmp1_addr + 1 : 1;
         tmp1_we           = (pre_axis_tvalid && (tuser_src_port == 8'h08)) ? 1 : 0;
         tmp1_data         = (pre_axis_tvalid && (tuser_src_port == 8'h08)) ? {{MEM_NILL_BIT_NO{1'b0}}, 1'b1, pre_axis_tlast, pre_axis_tuser, pre_axis_tkeep, pre_axis_tdata} : 0;
         st1_wr_next       = (pre_axis_tvalid && (tuser_src_port == 8'h08)) ? `ST1_WR : `ST1_WR_IDLE;
         tmp1_last_addr_next = 1;
      end
      `ST1_WR : begin
         if (sw_rst) begin
            tmp1_addr_next    = 1;
            tmp1_we           = 1;
            tmp1_data         = 0;
            st1_wr_next       = `ST1_WR_IDLE;
            tmp1_last_addr_next = 1;
         end
         else if (q1_wr_done) begin
            tmp1_addr_next    = tmp1_addr + 1;
            tmp1_we           = 1;
            tmp1_data         = {{(MEM_NILL_BIT_NO-1){1'b0}}, 1'b1, 2'b0, {(C_S_AXIS_TUSER_WIDTH+(C_S_AXIS_DATA_WIDTH/8)+C_S_AXIS_DATA_WIDTH){1'b0}}};
            st1_wr_next       = `ST1_WR_DONE;
            tmp1_last_addr_next = tmp1_addr; 
         end
         else if (pre_axis_tvalid) begin
            tmp1_addr_next    = tmp1_addr + 1;
            tmp1_we           = 1;
            tmp1_data         = {{MEM_NILL_BIT_NO{1'b0}}, 1'b1, pre_axis_tlast, pre_axis_tuser, pre_axis_tkeep, pre_axis_tdata};
            st1_wr_next       = `ST1_WR;
            tmp1_last_addr_next = 1; 
         end
         else begin
            tmp1_addr_next    = tmp1_addr;
            tmp1_we           = 0;
            tmp1_data         = 0;
            st1_wr_next       = `ST1_WR;
            tmp1_last_addr_next = 1;
         end
      end
      `ST1_WR_DONE : begin
         tmp1_addr_next    = 1;
         tmp1_we           = 1;
         tmp1_data         = 0;
         st1_wr_next       = `ST1_WR_IDLE;
         tmp1_last_addr_next = 1;
      end
   endcase
   // tmp1_data[DEBUG_PAYLOAD_POS+:64] = {time_counter, st1_wr_current, st1_wr_next, tmp1_addr_next[7:0], tmp1_addr[3:0], 1'b0, tmp1_addr_next[10:8], 1'b0, tmp1_addr[10:4]};
end

always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      for (j=0; j<NUM_QUEUES; j=j+1) begin
         r_mem_wr_addr[j]  <= 0;
         r_mem_wren[j]     <= 0;
         r_mem_wr_data[j]  <= 0;
      end
   end
   else begin
      r_mem_wr_addr[0]  <= tmp0_addr;
      r_mem_wren[0]     <= tmp0_we;
      r_mem_wr_data[0]  <= tmp0_data;
      r_mem_wr_addr[1]  <= tmp1_addr;
      r_mem_wren[1]     <= tmp1_we;
      r_mem_wr_data[1]  <= tmp1_data;
   end

//assign clka0 = axis_aclk;
//assign clka1 = axis_aclk;

assign addra0 = (r_mem_wren[0]) ? {r_mem_wr_addr[0]} : {r_mem_rd_addr[0]};
assign addra1 = (r_mem_wren[1]) ? {r_mem_wr_addr[1]} : {r_mem_rd_addr[1]};

assign ena0 = r_mem_wren[0] | r_mem_rden[0];
assign ena1 = r_mem_wren[1] | r_mem_rden[1];

assign wea0 = r_mem_wren[0];
assign wea1 = r_mem_wren[1];

assign douta0 = r_mem_wr_data[0];
assign douta1 = r_mem_wr_data[1];


reg   r_q0_start_replay, r_q1_start_replay;
always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      r_q0_start_replay    <= 0;
      r_q1_start_replay    <= 0;
   end
   else begin
      r_q0_start_replay    <= q0_start_replay;
      r_q1_start_replay    <= q1_start_replay;
   end

wire  w_q0_start = q0_start_replay & ~r_q0_start_replay;
wire  w_q1_start = q1_start_replay & ~r_q1_start_replay;


// reg   [4:0]    replay_counter;
// always @(posedge axis_aclk)
//    if (~axis_aresetn) begin
//       replay_counter    <= 0;
//    end
//    else if (w_q0_start) begin
//       replay_counter    <= replay_counter + 1;
//    end
//    else if (replay_counter > 0) begin
//       replay_counter    <= replay_counter + 1;
//    end

// assign replay_start_out = |replay_counter;

reg   r_replay_in_0, r_replay_in_1;
always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      r_replay_in_0  <= 0;
      r_replay_in_1  <= 0;
   end
   else begin
      r_replay_in_0  <= replay_start_in;
      r_replay_in_1  <= r_replay_in_0;
   end

assign w_replay_trigger = r_replay_in_0 & ~r_replay_in_1;


`define  ST0_RD_IDLE    0
`define  ST0_RD         1

reg   [3:0]    st0_rd_current, st0_rd_next;

always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      r_mem_rd_addr[0]  <= 1;
      q0_count          <= 0;
      st0_rd_current    <= 0;
   end
   else if (sw_rst) begin
      r_mem_rd_addr[0]  <= 1;
      q0_count          <= 0;
      st0_rd_current    <= 0;
   end
   else begin
      r_mem_rd_addr[0]  <= r_mem_rd_addr_next[0];
      q0_count          <= q0_count_next;
      st0_rd_current    <= st0_rd_next;
   end

always @(*) begin
   r_mem_rd_addr_next[0]   = 1;
   r_mem_rden[0]           = 0;
   q0_count_next           = 0;
   st0_rd_next             = `ST0_RD_IDLE;
   if (st0_rd_current == `ST0_RD_IDLE && (!w_q0_start || (q0_replay_count == 0))) begin
      // idle
      r_mem_rd_addr_next[0]   = 1;
      r_mem_rden[0]           = 0;
      q0_count_next           = 0;
      st0_rd_next             = `ST0_RD_IDLE;
   end 
   else begin
      if (sw_rst) begin
         r_mem_rd_addr_next[0]   = 1;
         r_mem_rden[0]           = 0;
         q0_count_next           = 0;
         st0_rd_next             = `ST0_RD_IDLE;
      end 
      else if (fifo_nearly_full[0]) begin
         // fifo nearly full, pause
         r_mem_rd_addr_next[0]   = r_mem_rd_addr[0];
         r_mem_rden[0]           = 0;
         q0_count_next           = q0_count;
         st0_rd_next             = `ST0_RD;
      end
      else if (dina0[MEM_TVALID_POS+1] || (r_mem_rd_addr[0] + 1 == tmp0_last_addr)) begin
         // Reached the end of pcap
         if ((q0_count + 1) < q0_replay_count) begin
            // go back to start and keep reading
            r_mem_rd_addr_next[0]   = 1;
            r_mem_rden[0]           = 1;
            q0_count_next           = q0_count + 1;
            st0_rd_next             = `ST0_RD;
         end
         else begin
            // finished replay, read the last word and stop
            r_mem_rd_addr_next[0]   = 1;
            r_mem_rden[0]           = 1;
            q0_count_next           = 0;
            st0_rd_next             = `ST0_RD_IDLE;
         end
      end 
      else begin
         // keep reading, still in pcap
         r_mem_rd_addr_next[0]   = r_mem_rd_addr[0] + 1;
         r_mem_rden[0]           = 1;
         q0_count_next           = q0_count;
         st0_rd_next             = `ST0_RD;
      end
   end
end

// reg   r_rden0;
// always @(posedge axis_aclk)
//    if (~axis_aresetn) begin
//       r_rden0                 <= 0;
//       r_fifo_nearly_full[0]   <= 0;
//    end
//    else begin
//       r_rden0                 <= r_mem_rden[0];
//       r_fifo_nearly_full[0]   <= fifo_nearly_full[0];
//    end

// wire  w_fifo_nearly_full0 = ~fifo_nearly_full[0] & r_fifo_nearly_full[0];



`define  ST1_RD_IDLE    0
`define  ST1_RD         1

reg   [3:0]    st1_rd_current, st1_rd_next;

always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      r_mem_rd_addr[1]  <= 1;
      q1_count          <= 0;
      st1_rd_current    <= 0;
   end
   else if (sw_rst) begin
      r_mem_rd_addr[1]  <= 1;
      q1_count          <= 0;
      st1_rd_current    <= 0;
   end
   else begin
      r_mem_rd_addr[1]  <= r_mem_rd_addr_next[1];
      q1_count          <= q1_count_next;
      st1_rd_current    <= st1_rd_next;
   end

always @(*) begin
   r_mem_rd_addr_next[1]   = 1;
   r_mem_rden[1]           = 0;
   q1_count_next           = 0;
   st1_rd_next             = `ST1_RD_IDLE;
   if (st1_rd_current == `ST1_RD_IDLE && (!w_q1_start || (q1_replay_count == 0))) begin
      // idle
      r_mem_rd_addr_next[1]   = 1;
      r_mem_rden[1]           = 0;
      q1_count_next           = 0;
      st1_rd_next             = `ST1_RD_IDLE;
   end 
   else begin
      if (sw_rst) begin
         r_mem_rd_addr_next[1]   = 1;
         r_mem_rden[1]           = 0;
         q1_count_next           = 0;
         st1_rd_next             = `ST1_RD_IDLE;
      end 
      else if (fifo_nearly_full[1]) begin
         // fifo nearly full, pause
         r_mem_rd_addr_next[1]   = r_mem_rd_addr[1];
         r_mem_rden[1]           = 0;
         q1_count_next           = q1_count;
         st1_rd_next             = `ST1_RD;
      end
      else if (dina1[MEM_TVALID_POS+1] || (r_mem_rd_addr[1] + 1 == tmp1_last_addr)) begin
         // Reached the end of pcap
         if ((q1_count + 1) < q1_replay_count) begin
            // go back to start and keep reading
            r_mem_rd_addr_next[1]   = 1;
            r_mem_rden[1]           = 1;
            q1_count_next           = q1_count + 1;
            st1_rd_next             = `ST1_RD;
         end
         else begin
            // finished replay, read the last word and stop
            r_mem_rd_addr_next[1]   = 1;
            r_mem_rden[1]           = 1;
            q1_count_next           = 0;
            st1_rd_next             = `ST1_RD_IDLE;
         end
      end 
      else begin
         // keep reading, still in pcap
         r_mem_rd_addr_next[1]   = r_mem_rd_addr[1] + 1;
         r_mem_rden[1]           = 1;
         q1_count_next           = q1_count;
         st1_rd_next             = `ST1_RD;
      end
   end
end

// reg   r_rden1;
// always @(posedge axis_aclk)
//    if (~axis_aresetn) begin
//       r_rden1                 <= 0;
//       r_fifo_nearly_full[1]   <= 0;
//    end
//    else begin
//       r_rden1                 <= r_mem_rden[1];
//       r_fifo_nearly_full[1]   <= fifo_nearly_full[1];
//    end

// wire  w_fifo_nearly_full1 = ~fifo_nearly_full[1] & r_fifo_nearly_full[1];

// // bypass mode state machine
// `define     ST_DIR_IDLE       0
// `define     ST_DIR_WR         1

reg   [C_M_AXIS_DATA_WIDTH-1:0]        fifo_dir_tdata[0:NUM_QUEUES-1];
reg   [(C_M_AXIS_DATA_WIDTH/8)-1:0]    fifo_dir_tkeep[0:NUM_QUEUES-1];
reg   [C_M_AXIS_TUSER_WIDTH-1:0]       fifo_dir_tuser[0:NUM_QUEUES-1];
reg   [NUM_QUEUES-1:0]                 fifo_dir_tlast;
reg   [NUM_QUEUES-1:0]                 fifo_dir_tvalid;

reg   [3:0]    st_dir_current[0:NUM_QUEUES-1], st_dir_next[0:NUM_QUEUES-1];

wire  [7:0]    src_port[0:NUM_QUEUES-1], dst_port[0:NUM_QUEUES-1];

assign src_port[0] = 8'h02;
assign src_port[1] = 8'h08;

assign dst_port[0] = 8'h01;
assign dst_port[1] = 8'h04;

//generate
//   genvar k;
//      for (k=0; k<NUM_QUEUES; k=k+1) begin
//         always @(*) begin
//            fifo_dir_tdata[k]    = 0;
//            fifo_dir_tkeep[k]    = 0;
//            fifo_dir_tuser[k]    = 0;
//            fifo_dir_tlast[k]    = 0;
//            fifo_dir_tvalid[k]   = 0;
//            st_dir_next[k]        = `ST_DIR_IDLE;
//            case(st_dir_current[k])
//               `ST_DIR_IDLE : begin
//                  fifo_dir_tdata[k]    = s_axis_tdata;
//                  fifo_dir_tkeep[k]    = s_axis_tkeep;
//                  fifo_dir_tuser[k]    = {s_axis_tuser[32+:96],dst_port[0],s_axis_tuser[0+:24]};
//                  fifo_dir_tlast[k]    = s_axis_tlast;
//                  fifo_dir_tvalid[k]   = (s_axis_tvalid && (tuser_src_port == src_port[k]) && conf_path[k]) ? 1 : 0;
//                  st_dir_next[k]       = (s_axis_tvalid && (tuser_src_port == src_port[k]) && conf_path[k]) ? `ST_DIR_WR : `ST_DIR_IDLE;
//               end
//               `ST_DIR_WR : begin
//                  fifo_dir_tdata[k]    = s_axis_tdata;
//                  fifo_dir_tkeep[k]    = s_axis_tkeep;
//                  fifo_dir_tuser[k]    = s_axis_tuser;
//                  fifo_dir_tlast[k]    = s_axis_tlast;
//                  fifo_dir_tvalid[k]   = s_axis_tvalid;
//                  st_dir_next[k]       = (s_axis_tvalid & s_axis_tlast) ? `ST_DIR_IDLE : `ST_DIR_WR;
//               end
//            endcase
//         end
//      end
//endgenerate


// assign fifo_in_tdata[0]  = dina0[0+:C_M_AXIS_DATA_WIDTH];
// assign fifo_in_tdata[0]  = ((r_rden0 && r_mem_rden[0]) || w_fifo_nearly_full0) ? {dina0[(C_M_AXIS_DATA_WIDTH - 1):(DEBUG_PAYLOAD_POS+208)], tmp0_last_addr[7:0], tmp0_last_addr[10:8], 5'h0, time_counter[7:0], time_counter[15:8], time_counter[23:16], time_counter[31:24], q0_count_next[7:0], q0_count_next[15:8], q0_count_next[23:16], q0_count_next[31:24], q0_count[7:0], q0_count[15:8], q0_count[23:16], q0_count[31:24], st0_rd_current, st0_rd_next, r_mem_rd_addr_next[0][7:0], r_mem_rd_addr[0][3:0], 1'b0, r_mem_rd_addr_next[0][10:8], 1'b0, r_mem_rd_addr[0][10:4], dina0[0+:(DEBUG_PAYLOAD_POS+64)]} : 0;
// assign fifo_in_tkeep[0]  = ((r_rden0 && r_mem_rden[0]) || w_fifo_nearly_full0) ? dina0[C_M_AXIS_DATA_WIDTH+:(C_M_AXIS_DATA_WIDTH/8)] : 0;
// assign fifo_in_tuser[0]  = ((r_rden0 && r_mem_rden[0]) || w_fifo_nearly_full0) ? dina0[(C_M_AXIS_DATA_WIDTH+(C_M_AXIS_DATA_WIDTH/8))+:C_M_AXIS_TUSER_WIDTH] : 0;
// assign fifo_in_tlast[0]  = ((r_rden0 && r_mem_rden[0]) || w_fifo_nearly_full0) ? dina0[MEM_TLAST_POS] : 0;
// assign fifo_in_tvalid[0] = ((r_rden0 && r_mem_rden[0]) || w_fifo_nearly_full0) ? dina0[MEM_TVALID_POS] : 0;

// pipeline to fix timing
reg [C_M_AXIS_DATA_WIDTH-1:0] fifo_in_tdata_0_r, fifo_in_tdata_1_r;  
reg [(C_M_AXIS_DATA_WIDTH/8)-1:0] fifo_in_tkeep_0_r, fifo_in_tkeep_1_r;  
reg [C_M_AXIS_TUSER_WIDTH-1:0]  fifo_in_tuser_0_r, fifo_in_tuser_1_r;  
reg fifo_in_tlast_0_r, fifo_in_tlast_1_r;
reg fifo_in_tvalid_0_r, fifo_in_tvalid_1_r;

always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      fifo_in_tdata_0_r <= 0;
      fifo_in_tkeep_0_r <= 0;
      fifo_in_tuser_0_r <= 0;
      fifo_in_tlast_0_r <= 0;
      fifo_in_tvalid_0_r <= 0;
   end
   else begin
      fifo_in_tdata_0_r  <= dina0[0+:C_M_AXIS_DATA_WIDTH];
      // fifo_in_tdata_0_r  <= {dina0[(C_M_AXIS_DATA_WIDTH - 1):(DEBUG_PAYLOAD_POS+208)], tmp0_last_addr[7:0], tmp0_last_addr[10:8], 5'h0, time_counter[7:0], time_counter[15:8], time_counter[23:16], time_counter[31:24], q0_count_next[7:0], q0_count_next[15:8], q0_count_next[23:16], q0_count_next[31:24], q0_count[7:0], q0_count[15:8], q0_count[23:16], q0_count[31:24], st0_rd_current, st0_rd_next, r_mem_rd_addr_next[0][7:0], r_mem_rd_addr[0][3:0], 1'b0, r_mem_rd_addr_next[0][10:8], 1'b0, r_mem_rd_addr[0][10:4], dina0[0+:(DEBUG_PAYLOAD_POS+64)]};
      fifo_in_tkeep_0_r  <= dina0[C_M_AXIS_DATA_WIDTH+:(C_M_AXIS_DATA_WIDTH/8)];
      fifo_in_tuser_0_r  <= dina0[(C_M_AXIS_DATA_WIDTH+(C_M_AXIS_DATA_WIDTH/8))+:C_M_AXIS_TUSER_WIDTH];
      fifo_in_tlast_0_r  <= dina0[MEM_TLAST_POS];
      fifo_in_tvalid_0_r <= dina0[MEM_TVALID_POS];
   end

assign fifo_in_tdata[0]  = fifo_in_tdata_0_r; 
assign fifo_in_tkeep[0]  = fifo_in_tkeep_0_r; 
assign fifo_in_tuser[0]  = fifo_in_tuser_0_r; 
assign fifo_in_tlast[0]  = fifo_in_tlast_0_r; 
assign fifo_in_tvalid[0] = fifo_in_tvalid_0_r;

always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      fifo_in_tdata_1_r <= 0;
      fifo_in_tkeep_1_r <= 0;
      fifo_in_tuser_1_r <= 0;
      fifo_in_tlast_1_r <= 0;
      fifo_in_tvalid_1_r <= 0;
   end
   else begin
      fifo_in_tdata_1_r  <= dina1[0+:C_M_AXIS_DATA_WIDTH];
      fifo_in_tkeep_1_r  <= dina1[C_M_AXIS_DATA_WIDTH+:(C_M_AXIS_DATA_WIDTH/8)];
      fifo_in_tuser_1_r  <= dina1[(C_M_AXIS_DATA_WIDTH+(C_M_AXIS_DATA_WIDTH/8))+:C_M_AXIS_TUSER_WIDTH];
      fifo_in_tlast_1_r  <= dina1[MEM_TLAST_POS];
      fifo_in_tvalid_1_r <= dina1[MEM_TVALID_POS];
   end

assign fifo_in_tdata[1]  = fifo_in_tdata_1_r; 
assign fifo_in_tkeep[1]  = fifo_in_tkeep_1_r; 
assign fifo_in_tuser[1]  = fifo_in_tuser_1_r; 
assign fifo_in_tlast[1]  = fifo_in_tlast_1_r; 
assign fifo_in_tvalid[1] = fifo_in_tvalid_1_r;

// assign fifo_in_tdata[1]  = ((r_rden1 && r_mem_rden[1]) || w_fifo_nearly_full1) ? {dina1[(C_M_AXIS_DATA_WIDTH - 1):(DEBUG_PAYLOAD_POS+192 + 48)], q0_replay_count, 3'h0, fifo_nearly_full[0], fifo_in_tvalid[0], fifo_rden[0], fifo_empty[0], m0_axis_tready, m0_st_next, m0_st_current, time_counter[7:0], time_counter[15:8], time_counter[23:16], time_counter[31:24], q1_count_next[7:0], q1_count_next[15:8], q1_count_next[23:16], q1_count_next[31:24], q1_count[7:0], q1_count[15:8], q1_count[23:16], q1_count[31:24], st1_rd_current, st1_rd_next, r_mem_rd_addr_next[1][7:0], r_mem_rd_addr[1][3:0], 1'b0, r_mem_rd_addr_next[1][10:8], 1'b0, r_mem_rd_addr[1][10:4], dina1[0+:(DEBUG_PAYLOAD_POS+64)]} : 0;


generate
   genvar i;
      for(i=0; i<NUM_QUEUES; i=i+1) begin: pcap_fifos
         fallthrough_small_fifo
         #(
            .WIDTH            (  1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH               ),
            .MAX_DEPTH_BITS   (  IN_FIFO_DEPTH_BIT                                                                ),
            .PROG_FULL_THRESHOLD (2**IN_FIFO_DEPTH_BIT - 10) // use prog_full to detect nearly full early (because several cycles delay in previous pipeline)
         )
         pcap_fifo
         (
            //Outputs
            .dout             (  {fifo_out_tlast[i], fifo_out_tuser[i], fifo_out_tkeep[i], fifo_out_tdata[i]}     ),
            .full             (                                                                                   ),
            .nearly_full      (                                                                                   ),
            .prog_full        (  fifo_nearly_full[i]                                                              ),
            .empty            (  fifo_empty[i]                                                                    ),
            //Inputs
            .din              (  {fifo_in_tlast[i], fifo_in_tuser[i], fifo_in_tkeep[i], fifo_in_tdata[i]}         ),
            .wr_en            (  fifo_in_tvalid[i]                                                                ),
            .rd_en            (  fifo_rden[i]                                                                     ),
            .reset            (  ~axis_aresetn                                                                     ),
            .clk              (  axis_aclk                                                                        )
         );
         // xpm_fifo_sync #(
         //    .FIFO_MEMORY_TYPE     ("auto"),
         //    .ECC_MODE             ("no_ecc"),
         //    .FIFO_WRITE_DEPTH     (IN_FIFO_DEPTH),
         //    .WRITE_DATA_WIDTH     (1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH),
         //    .WR_DATA_COUNT_WIDTH  (1),
         //    .PROG_FULL_THRESH     (IN_FIFO_DEPTH - 12),
         //    .FULL_RESET_VALUE     (0),
         //    .USE_ADV_FEATURES     ("0707"),
         //    .READ_MODE            ("fwft"),
         //    .FIFO_READ_LATENCY    (0),
         //    // .FIFO_READ_LATENCY    (1),
         //    .READ_DATA_WIDTH      (1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH),
         //    .RD_DATA_COUNT_WIDTH  (1),
         //    .PROG_EMPTY_THRESH    (10),
         //    .DOUT_RESET_VALUE     ("0"),
         //    .WAKEUP_TIME          (0)
         // ) u_xpm_fifo_sync (
         //    // Common module ports
         //    .sleep           (),
         //    .rst             (~axis_aresetn),
            
         //    // Write Domain ports
         //    .wr_clk          (axis_aclk),
         //    .wr_en           (fifo_in_tvalid[i]),
         //    .din             ({fifo_in_tlast[i], fifo_in_tuser[i], fifo_in_tkeep[i], fifo_in_tdata[i]}),
         //    .full            (),
         //    .prog_full       (fifo_nearly_full[i]),
         //    // .prog_full       (),
         //    .wr_data_count   (),
         //    .overflow        (),
         //    .wr_rst_busy     (),
         //    .almost_full     (),
         //    // .almost_full     (almost_full),
         //    .wr_ack          (),
            
         //    // Read Domain ports
         //    .rd_en           (fifo_rden[i]),
         //    .dout            ({fifo_out_tlast[i], fifo_out_tuser[i], fifo_out_tkeep[i], fifo_out_tdata[i]}),
         //    .empty           (fifo_empty[i]),
         //    .prog_empty      (),
         //    .rd_data_count   (),
         //    .underflow       (),
         //    .rd_rst_busy     (),
         //    .almost_empty    (),
         //    .data_valid      (),
            
         //    // ECC Related ports
         //    .injectsbiterr   (),
         //    .injectdbiterr   (),
         //    .sbiterr         (),
         //    .dbiterr         () 
         // );
      end
endgenerate


always @(posedge axis_aclk)
   if (~axis_aresetn) begin
      m0_st_current  <= 0;
      m1_st_current  <= 0;
   end
   else begin
      m0_st_current  <= m0_st_next;
      m1_st_current  <= m1_st_next;
   end

// always @(*) begin
//    m0_axis_tdata        = 0;
//    m0_axis_tkeep        = 0;
//    m0_axis_tuser        = 0;
//    m0_axis_tlast        = 0;
//    m0_axis_tvalid       = 0;
//    fifo_rden[0]         = 0;
//    m0_st_next           = `M0_IDLE;
//    case (m0_st_current)
//       `M0_IDLE : begin
//          m0_axis_tdata        = 0;
//          m0_axis_tkeep        = 0;
//          m0_axis_tuser        = 0;
//          m0_axis_tlast        = 0;
//          m0_axis_tvalid       = 0;
//          fifo_rden[0]         = 0;
//          m0_st_next           = (m0_axis_tready & ~fifo_empty[0] & (q0_replay_count != 0)) ? `M0_SEND : `M0_IDLE;
//       end
//       `M0_SEND : begin
//          m0_axis_tdata        = fifo_out_tdata[0];
//          m0_axis_tkeep        = fifo_out_tkeep[0];
//          m0_axis_tuser        = {fifo_out_tuser[0][127:32],16'h0102,16'h0};
//          m0_axis_tlast        = fifo_out_tlast[0];
//          m0_axis_tvalid       = ~fifo_empty[0];
//          fifo_rden[0]         = (m0_axis_tready & ~fifo_empty[0]);
//          m0_st_next           = (m0_axis_tready & ~fifo_empty[0]) ? `M0_SEND : `M0_IDLE;
//       end
//    endcase
// end

// reg   [C_M_AXIS_DATA_WIDTH-1:0]              m0_axis_tdata_next;
// reg   [((C_M_AXIS_DATA_WIDTH/8))-1:0]        m0_axis_tkeep_next;
// reg   [C_M_AXIS_TUSER_WIDTH-1:0]             m0_axis_tuser_next;
// reg                                          m0_axis_tvalid_next;
// reg                                          m0_axis_tlast_next;

// reg   [C_M_AXIS_DATA_WIDTH-1:0]              m1_axis_tdata_next;
// reg   [((C_M_AXIS_DATA_WIDTH/8))-1:0]        m1_axis_tkeep_next;
// reg   [C_M_AXIS_TUSER_WIDTH-1:0]             m1_axis_tuser_next;
// reg                                          m1_axis_tvalid_next;
// reg                                          m1_axis_tlast_next;

// reg   [NUM_QUEUES-1:0]  		fifo_rden_next;
  
// always @(*) begin
//    m0_axis_tdata_next = fifo_out_tdata[0];
//    m0_axis_tkeep_next = fifo_out_tkeep[0];
//    m0_axis_tuser_next = {fifo_out_tuser[0][127:32],16'h0102,16'h0};
//    m0_axis_tvalid_next = ~fifo_empty[0] & m0_axis_tready;
//    m0_axis_tlast_next = fifo_out_tlast[0]; 
//    fifo_rden_next[0] = m0_axis_tready & ~fifo_empty[0] & (q0_replay_count != 0);
// end


always @(*) begin
   m0_axis_tdata = fifo_out_tdata[0];
   m0_axis_tkeep = fifo_out_tkeep[0];
   m0_axis_tuser = {fifo_out_tuser[0][127:32],16'h0102,16'h0};
   m0_axis_tvalid = ~fifo_empty[0] & m0_axis_tready;
   m0_axis_tlast = fifo_out_tlast[0]; 
   fifo_rden[0] = m0_axis_tready & ~fifo_empty[0] & (q0_replay_count != 0);
end


// always @(*) begin
//    m1_axis_tdata = fifo_out_tdata[1];
//    m1_axis_tkeep = fifo_out_tkeep[1];
//    m1_axis_tuser = {fifo_out_tuser[1][127:32],16'h0408,16'h0};
//    m1_axis_tvalid = ~fifo_empty[1] & m1_axis_tready;
//    m1_axis_tlast = fifo_out_tlast[1]; 
//    fifo_rden[1] = m1_axis_tready & ~fifo_empty[1] & (q1_replay_count != 0);
// end

always @(*) begin
   m1_axis_tdata        = 0;
   m1_axis_tkeep        = 0;
   m1_axis_tuser        = 0;
   m1_axis_tlast        = 0;
   m1_axis_tvalid       = 0;
   fifo_rden[1]         = 0;
   m1_st_next           = `M1_IDLE;
   case (m1_st_current)
      `M1_IDLE : begin
         m1_axis_tdata        = 0;
         m1_axis_tkeep        = 0;
         m1_axis_tuser        = 0;
         m1_axis_tlast        = 0;
         m1_axis_tvalid       = 0;
         fifo_rden[1]         = 0;
         m1_st_next           = (m1_axis_tready & ~fifo_empty[1] & (q1_replay_count != 0)) ? `M1_SEND : `M1_IDLE;
      end
      `M1_SEND : begin
         m1_axis_tdata        = fifo_out_tdata[1];
         m1_axis_tkeep        = fifo_out_tkeep[1];
         m1_axis_tuser        = {fifo_out_tuser[1][127:32],16'h0408,16'h0};
         m1_axis_tlast        = fifo_out_tlast[1];
         m1_axis_tvalid       = ~fifo_empty[1];
         fifo_rden[1]         = (m1_axis_tready & ~fifo_empty[1]);
         m1_st_next           = (m1_axis_tready & ~fifo_empty[1]) ? `M1_SEND : `M1_IDLE;
      end
   endcase
end


pre_pcap_bram_store
#(
   .C_M_AXIS_DATA_WIDTH    (  C_M_AXIS_DATA_WIDTH     ),
   .C_S_AXIS_DATA_WIDTH    (  C_S_AXIS_DATA_WIDTH     ),
   .C_M_AXIS_TUSER_WIDTH   (  C_M_AXIS_TUSER_WIDTH    ),
   .C_S_AXIS_TUSER_WIDTH   (  C_S_AXIS_TUSER_WIDTH    )
)
pre_pcap_bram_store
(
   .axis_aclk              (  axis_aclk               ),
   .axis_aresetn           (  axis_aresetn            ),

   //Master Stream Ports to external memory for pcap storing
   .m_axis_tdata           (  pre_axis_tdata          ),
   .m_axis_tkeep           (  pre_axis_tkeep          ),
   .m_axis_tuser           (  pre_axis_tuser          ),
   .m_axis_tvalid          (  pre_axis_tvalid         ),
   .m_axis_tready          (  pre_axis_tready         ),
   .m_axis_tlast           (  pre_axis_tlast          ),

   //Slave Stream Ports from host over DMA 
   .s_axis_tdata           (  s_axis_tdata            ),
   .s_axis_tkeep           (  s_axis_tkeep            ),
   .s_axis_tuser           (  s_axis_tuser            ),
   .s_axis_tvalid          (  s_axis_tvalid           ),
   .s_axis_tready          (  s_axis_tready           ),
   .s_axis_tlast           (  s_axis_tlast            )
);

// -- Register assignments
assign sw_rst           = rw_regs[(C_S_AXI_DATA_WIDTH*0)+1-1:(C_S_AXI_DATA_WIDTH*0)]; //0x0000

assign q0_start_replay  = rw_regs[(C_S_AXI_DATA_WIDTH*1)+1-1:(C_S_AXI_DATA_WIDTH*1)]; //0x0004
assign q1_start_replay  = q0_start_replay; //0x0008

assign q0_replay_count  = rw_regs[(C_S_AXI_DATA_WIDTH*3)+REPLAY_COUNT_WIDTH-1:(C_S_AXI_DATA_WIDTH*3)]; //0x000c
assign q1_replay_count  = rw_regs[(C_S_AXI_DATA_WIDTH*4)+REPLAY_COUNT_WIDTH-1:(C_S_AXI_DATA_WIDTH*4)]; //0x0010

assign q0_wr_done       = rw_regs[(C_S_AXI_DATA_WIDTH*11)+1-1:(C_S_AXI_DATA_WIDTH*11)]; //0x002c
assign q1_wr_done       = rw_regs[(C_S_AXI_DATA_WIDTH*12)+1-1:(C_S_AXI_DATA_WIDTH*12)]; //0x0030

// 0x0 : default, 0x1: path 0, 0x2: path 1, 0x4: path 2, 0x8: path 3.
//assign conf_path        = rw_regs[(C_S_AXI_DATA_WIDTH*13)+32-1:(C_S_AXI_DATA_WIDTH*13)]; //0x0034

// ------------- CPU Register -----------

assign ip2cpu_ctrl0 = cpu2ip_ctrl0;
assign ip2cpu_ctrl1 = cpu2ip_ctrl1;
assign ip2cpu_ctrl2 = cpu2ip_ctrl2;
assign ip2cpu_ctrl3 = cpu2ip_ctrl3;
assign ip2cpu_ctrl4 = cpu2ip_ctrl4;
assign ip2cpu_ctrl5 = cpu2ip_ctrl5;
assign ip2cpu_ctrl6 = cpu2ip_ctrl6;
assign ip2cpu_ctrl7 = cpu2ip_ctrl7;
assign ip2cpu_ctrl8 = cpu2ip_ctrl8;
assign ip2cpu_ctrl9 = cpu2ip_ctrl9;
assign ip2cpu_ctrl10 = cpu2ip_ctrl10;
assign ip2cpu_ctrl11 = cpu2ip_ctrl11;
assign ip2cpu_ctrl12 = cpu2ip_ctrl12;
assign ip2cpu_ctrl13 = cpu2ip_ctrl13;

assign rw_regs[C_S_AXI_DATA_WIDTH * 1 - 1:C_S_AXI_DATA_WIDTH * 0] = cpu2ip_ctrl0;
assign rw_regs[C_S_AXI_DATA_WIDTH * 2 - 1:C_S_AXI_DATA_WIDTH * 1] = cpu2ip_ctrl1;
assign rw_regs[C_S_AXI_DATA_WIDTH * 3 - 1:C_S_AXI_DATA_WIDTH * 2] = cpu2ip_ctrl2;
assign rw_regs[C_S_AXI_DATA_WIDTH * 4 - 1:C_S_AXI_DATA_WIDTH * 3] = cpu2ip_ctrl3;
assign rw_regs[C_S_AXI_DATA_WIDTH * 5 - 1:C_S_AXI_DATA_WIDTH * 4] = cpu2ip_ctrl4;
assign rw_regs[C_S_AXI_DATA_WIDTH * 6 - 1:C_S_AXI_DATA_WIDTH * 5] = cpu2ip_ctrl5;
assign rw_regs[C_S_AXI_DATA_WIDTH * 7 - 1:C_S_AXI_DATA_WIDTH * 6] = cpu2ip_ctrl6;
assign rw_regs[C_S_AXI_DATA_WIDTH * 8 - 1:C_S_AXI_DATA_WIDTH * 7] = cpu2ip_ctrl7;
assign rw_regs[C_S_AXI_DATA_WIDTH * 9 - 1:C_S_AXI_DATA_WIDTH * 8] = cpu2ip_ctrl8;
assign rw_regs[C_S_AXI_DATA_WIDTH * 10 - 1:C_S_AXI_DATA_WIDTH * 9] = cpu2ip_ctrl9;
assign rw_regs[C_S_AXI_DATA_WIDTH * 11 - 1:C_S_AXI_DATA_WIDTH * 10] = cpu2ip_ctrl10;
assign rw_regs[C_S_AXI_DATA_WIDTH * 12 - 1:C_S_AXI_DATA_WIDTH * 11] = cpu2ip_ctrl11;
assign rw_regs[C_S_AXI_DATA_WIDTH * 13 - 1:C_S_AXI_DATA_WIDTH * 12] = cpu2ip_ctrl12;
assign rw_regs[C_S_AXI_DATA_WIDTH * 14 - 1:C_S_AXI_DATA_WIDTH * 13] = cpu2ip_ctrl13;

bram_pcap_replay_uengine_cpu_regs
#(
    .C_BASE_ADDRESS(C_BASEADDR),
    .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
    .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
)
bram_pcap_replay_uengine_cpu_regs
(
    // General ports
    .clk(s_axi_aclk),
    .resetn(axis_aresetn),//(s_axi_aresetn),
    // Global Registersoutput reg [`REG_CTRL25_BITS]    
    .cpu_resetn_soft(),
    .resetn_soft(),
    .resetn_sync(),

    // Register ports
    .ip2cpu_ctrl0_reg(ip2cpu_ctrl0),
    .cpu2ip_ctrl0_reg(cpu2ip_ctrl0),
    .ip2cpu_ctrl1_reg(ip2cpu_ctrl1),
    .cpu2ip_ctrl1_reg(cpu2ip_ctrl1),
    .ip2cpu_ctrl2_reg(ip2cpu_ctrl2),
    .cpu2ip_ctrl2_reg(cpu2ip_ctrl2),
    .ip2cpu_ctrl3_reg(ip2cpu_ctrl3),
    .cpu2ip_ctrl3_reg(cpu2ip_ctrl3),
    .ip2cpu_ctrl4_reg(ip2cpu_ctrl4),
    .cpu2ip_ctrl4_reg(cpu2ip_ctrl4),
    .ip2cpu_ctrl5_reg(ip2cpu_ctrl5),
    .cpu2ip_ctrl5_reg(cpu2ip_ctrl5),
    .ip2cpu_ctrl6_reg(ip2cpu_ctrl6),
    .cpu2ip_ctrl6_reg(cpu2ip_ctrl6),
    .ip2cpu_ctrl7_reg(ip2cpu_ctrl7),
    .cpu2ip_ctrl7_reg(cpu2ip_ctrl7),
    .ip2cpu_ctrl8_reg(ip2cpu_ctrl8),
    .cpu2ip_ctrl8_reg(cpu2ip_ctrl8),
    .ip2cpu_ctrl9_reg(ip2cpu_ctrl9),
    .cpu2ip_ctrl9_reg(cpu2ip_ctrl9),
    .ip2cpu_ctrl10_reg(ip2cpu_ctrl10),
    .cpu2ip_ctrl10_reg(cpu2ip_ctrl10),
    .ip2cpu_ctrl11_reg(ip2cpu_ctrl11),
    .cpu2ip_ctrl11_reg(cpu2ip_ctrl11),
    .ip2cpu_ctrl12_reg(ip2cpu_ctrl12),
    .cpu2ip_ctrl12_reg(cpu2ip_ctrl12),
    .ip2cpu_ctrl13_reg(ip2cpu_ctrl13),
    .cpu2ip_ctrl13_reg(cpu2ip_ctrl13),
   
    // AXI Lite ports
    .S_AXI_ACLK(s_axi_aclk),
    .S_AXI_ARESETN(s_axi_aresetn),
    .S_AXI_AWADDR(s_axi_awaddr),
    .S_AXI_AWVALID(s_axi_awvalid),
    .S_AXI_WDATA(s_axi_wdata),
    .S_AXI_WSTRB(s_axi_wstrb),
    .S_AXI_WVALID(s_axi_wvalid),
    .S_AXI_BREADY(s_axi_bready),
    .S_AXI_ARADDR(s_axi_araddr),
    .S_AXI_ARVALID(s_axi_arvalid),
    .S_AXI_RREADY(s_axi_rready),
    .S_AXI_ARREADY(s_axi_arready),
    .S_AXI_RDATA(s_axi_rdata),
    .S_AXI_RRESP(s_axi_rresp),
    .S_AXI_RVALID(s_axi_rvalid),
    .S_AXI_WREADY(s_axi_wready),
    .S_AXI_BRESP(s_axi_bresp),
    .S_AXI_BVALID(s_axi_bvalid),
    .S_AXI_AWREADY(s_axi_awready)
);

endmodule
