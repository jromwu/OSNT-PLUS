//
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
// Junior University
// Copyright (c) 2016 University of Cambridge
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
 *        osnt_packet_cutter.v
 *
 *  Author:
 *        Gianni Antichi
 *
 *  Description:
 */

`timescale 1ns/1ps
`include "packet_cutter_cpu_regs_defines.v"

module osnt_packet_cutter
#(
  parameter C_FAMILY              = "virtex7",
  parameter C_S_AXI_DATA_WIDTH    = 32,
  parameter C_S_AXI_ADDR_WIDTH    = 32,
  parameter C_USE_WSTRB           = 0,
  parameter C_DPHASE_TIMEOUT      = 0,
  parameter C_BASEADDR            = 32'h77800000,
  parameter C_HIGHADDR            = 32'h7780FFFF,
  parameter C_S_AXI_ACLK_FREQ_HZ  = 100,
  parameter C_M_AXIS_DATA_WIDTH   = 1024,
  parameter C_S_AXIS_DATA_WIDTH   = 1024,
  parameter C_M_AXIS_TUSER_WIDTH  = 128,
  parameter C_S_AXIS_TUSER_WIDTH  = 128,
  parameter HASH_WIDTH            = 128
)
(
  // Slave AXI Ports
  input                                     S_AXI_ACLK,
  input                                     S_AXI_ARESETN,
  input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_AWADDR,
  input                                     S_AXI_AWVALID,
  input      [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_WDATA,
  input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S_AXI_WSTRB,
  input                                     S_AXI_WVALID,
  input                                     S_AXI_BREADY,
  input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S_AXI_ARADDR,
  input                                     S_AXI_ARVALID,
  input                                     S_AXI_RREADY,
  output                                    S_AXI_ARREADY,
  output     [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_RDATA,
  output     [1 : 0]                        S_AXI_RRESP,
  output                                    S_AXI_RVALID,
  output                                    S_AXI_WREADY,
  output     [1 :0]                         S_AXI_BRESP,
  output                                    S_AXI_BVALID,
  output                                    S_AXI_AWREADY,

  // Master Stream Ports (interface to data path)
  output     [C_M_AXIS_DATA_WIDTH - 1:0]    M_AXIS_TDATA,
  output     [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] M_AXIS_TKEEP,
  output     [C_M_AXIS_TUSER_WIDTH-1:0]     M_AXIS_TUSER,
  output                                    M_AXIS_TVALID,
  input                                     M_AXIS_TREADY,
  output                                    M_AXIS_TLAST,

  // Slave Stream Ports (interface to RX queues)
  input      [C_S_AXIS_DATA_WIDTH - 1:0]    S_AXIS_TDATA,
  input      [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] S_AXIS_TKEEP,
  input      [C_S_AXIS_TUSER_WIDTH-1:0]     S_AXIS_TUSER,
  input                                     S_AXIS_TVALID,
  output                                    S_AXIS_TREADY,
  input                                     S_AXIS_TLAST
);

  localparam NUM_RW_REGS       = 5;
  localparam NUM_RO_REGS       = 2;

  // -- Signals

  wire                                      Bus2IP_Clk;
  wire                                      Bus2IP_Resetn;
  wire [C_S_AXI_ADDR_WIDTH-1:0]             Bus2IP_Addr;
  wire [0:0]                                Bus2IP_CS;
  wire                                      Bus2IP_RNW;
  wire [C_S_AXI_DATA_WIDTH-1:0]             Bus2IP_Data;
  wire [C_S_AXI_DATA_WIDTH/8-1:0]           Bus2IP_BE;
  wire [C_S_AXI_DATA_WIDTH-1:0]             IP2Bus_Data;
  wire                                      IP2Bus_RdAck;
  wire                                      IP2Bus_WrAck;
  wire                                      IP2Bus_Error;

  wire [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0] rw_regs;
  wire [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0] rw_defaults;
  wire [NUM_RO_REGS*C_S_AXI_DATA_WIDTH-1:0] ro_regs;

  wire                                      cut_en;
  wire [C_S_AXI_ADDR_WIDTH-1:0]             cut_words;
  wire [C_S_AXI_ADDR_WIDTH-1:0]             cut_offset;
  wire [C_S_AXI_ADDR_WIDTH-1:0]             cut_bytes;
  wire                                      hash_en;

  reg [C_S_AXI_ADDR_WIDTH-1:0]              s_axis_cnt;
  reg [C_S_AXI_ADDR_WIDTH-1:0]              m_axis_cnt;

  // -- Packet cutter
  packet_cutter #
  (
    .C_M_AXIS_DATA_WIDTH  (C_M_AXIS_DATA_WIDTH),
    .C_S_AXIS_DATA_WIDTH  (C_S_AXIS_DATA_WIDTH),
    .C_M_AXIS_TUSER_WIDTH (C_M_AXIS_TUSER_WIDTH),
    .C_S_AXIS_TUSER_WIDTH (C_S_AXIS_TUSER_WIDTH),
    .C_S_AXI_DATA_WIDTH   (C_S_AXI_DATA_WIDTH),
    .HASH_WIDTH           (HASH_WIDTH)
   ) packet_cutter
  (
    // Global Ports
    .axi_aclk      (S_AXI_ACLK),
    .axi_resetn    (S_AXI_ARESETN),

    // Master Stream Ports (interface to data path)
    .m_axis_tdata  (M_AXIS_TDATA),
    .m_axis_tstrb  (M_AXIS_TKEEP),
    .m_axis_tuser  (M_AXIS_TUSER),
    .m_axis_tvalid (M_AXIS_TVALID), 
    .m_axis_tready (M_AXIS_TREADY),
    .m_axis_tlast  (M_AXIS_TLAST),

    // Slave Stream Ports (interface to RX queues)
    .s_axis_tdata  (S_AXIS_TDATA),
    .s_axis_tstrb  (S_AXIS_TKEEP),
    .s_axis_tuser  (S_AXIS_TUSER),
    .s_axis_tvalid (S_AXIS_TVALID),
    .s_axis_tready (S_AXIS_TREADY),
    .s_axis_tlast  (S_AXIS_TLAST),

    // pkt cut
    .cut_en        (cut_en),
    .cut_words     (cut_words),
    .cut_offset    (cut_offset),
    .cut_bytes     (cut_bytes),
    .hash_en       (hash_en)
  );

   wire [`REG_CTRL_REGS0_BITS] 		       ip2cpu_ctrl_regs0_wire;
   wire [`REG_CTRL_REGS1_BITS] 		       ip2cpu_ctrl_regs1_wire;
   wire [`REG_CTRL_REGS2_BITS] 		       ip2cpu_ctrl_regs2_wire;
   wire [`REG_CTRL_REGS3_BITS] 		       ip2cpu_ctrl_regs3_wire;
   wire [`REG_CTRL_REGS4_BITS] 		       ip2cpu_ctrl_regs4_wire;

   wire [`REG_CTRL_REGS0_BITS] 		       cpu2ip_ctrl_regs0_wire;
   wire [`REG_CTRL_REGS1_BITS] 		       cpu2ip_ctrl_regs1_wire;
   wire [`REG_CTRL_REGS2_BITS] 		       cpu2ip_ctrl_regs2_wire;
   wire [`REG_CTRL_REGS3_BITS] 		       cpu2ip_ctrl_regs3_wire;
   wire [`REG_CTRL_REGS4_BITS] 		       ctrl_regs4_wire;

   wire [`REG_CTRL_REGS3_BITS] 		       return_regs0_wire;
   wire [`REG_CTRL_REGS4_BITS] 		       return_regs1_wire;

   assign cpu2ip_ctrl_regs0_wire = ip2cpu_ctrl_regs0_wire;
   assign cpu2ip_ctrl_regs1_wire = ip2cpu_ctrl_regs1_wire;
   assign cpu2ip_ctrl_regs2_wire = ip2cpu_ctrl_regs2_wire;
   assign cpu2ip_ctrl_regs3_wire = ip2cpu_ctrl_regs3_wire;
   assign cpu2ip_ctrl_regs4_wire = ip2cpu_ctrl_regs4_wire;

   always @(posedge S_AXI_ACLK)
     if (S_AXI_ARESETN) begin
       s_axis_cnt  <= 0;
     end
     else if (cut_en) begin
       s_axis_cnt  <= 0;
     end
     else begin
       s_axis_cnt  <= (S_AXIS_TVALID & S_AXIS_TREADY & S_AXIS_TLAST) ? s_axis_cnt + 1 : s_axis_cnt;
     end

   always @(posedge S_AXI_ACLK)
     if (S_AXI_ARESETN) begin
       m_axis_cnt  <= 0;
     end
     else if (cut_en) begin
       m_axis_cnt  <= 0;
     end
     else begin
       m_axis_cnt  <= (M_AXIS_TVALID & M_AXIS_TREADY & M_AXIS_TLAST) ? m_axis_cnt + 1 : m_axis_cnt;
     end

   // -- Register assignments

   assign ro_regs = {s_axis_cnt, m_axis_cnt};

   assign cut_en       = rw_regs[C_S_AXI_DATA_WIDTH*0];
   assign cut_words    = rw_regs[31+C_S_AXI_DATA_WIDTH*1:C_S_AXI_DATA_WIDTH*1];
   assign cut_offset   = rw_regs[31+C_S_AXI_DATA_WIDTH*2:C_S_AXI_DATA_WIDTH*2];
   assign cut_bytes    = rw_regs[31+C_S_AXI_DATA_WIDTH*3:C_S_AXI_DATA_WIDTH*3];
   assign hash_en      = rw_regs[C_S_AXI_DATA_WIDTH*4:C_S_AXI_DATA_WIDTH*4];

   assign rw_regs[(C_S_AXI_DATA_WIDTH * 1)-1 : C_S_AXI_DATA_WIDTH * 0] = cpu2ip_ctrl_regs0_wire;
   assign rw_regs[(C_S_AXI_DATA_WIDTH * 2)-1 : C_S_AXI_DATA_WIDTH * 1] = cpu2ip_ctrl_regs1_wire;
   assign rw_regs[(C_S_AXI_DATA_WIDTH * 3)-1 : C_S_AXI_DATA_WIDTH * 2] = cpu2ip_ctrl_regs2_wire;
   assign rw_regs[(C_S_AXI_DATA_WIDTH * 4)-1 : C_S_AXI_DATA_WIDTH * 3] = cpu2ip_ctrl_regs3_wire;
   assign rw_regs[(C_S_AXI_DATA_WIDTH * 5)-1 : C_S_AXI_DATA_WIDTH * 4] = cpu2ip_ctrl_regs4_wire;

   assign return_regs0_wire = ro_regs[(C_S_AXI_DATA_WIDTH * 1) - 1 : C_S_AXI_DATA_WIDTH * 0];
   assign return_regs1_wire = ro_regs[(C_S_AXI_DATA_WIDTH * 2) - 1 : C_S_AXI_DATA_WIDTH * 1]; 

   packet_cutter_cpu_regs#
     (
      .C_BASE_ADDRESS(C_BASEADDR),
      .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
      .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
      )
   (
    // General ports
    .clk                    (S_AXI_ACLK),
    .resetn                 (S_AXI_ARESETN),
    // Global Registers
    .cpu_resetn_soft        (),
    .resetn_soft            (),
    .resetn_sync            (),

    // Register ports
    .ip2cpu_ctrl_regs0_reg  (ip2cpu_ctrl_regs0_wire),
    .cpu2ip_ctrl_regs0_reg  (cpu2ip_ctrl_regs0_wire),
    .ip2cpu_ctrl_regs1_reg  (ip2cpu_ctrl_regs1_wire),
    .cpu2ip_ctrl_regs1_reg  (cpu2ip_ctrl_regs1_wire),
    .ip2cpu_ctrl_regs2_reg  (ip2cpu_ctrl_regs2_wire),
    .cpu2ip_ctrl_regs2_reg  (cpu2ip_ctrl_regs2_wire),
    .ip2cpu_ctrl_regs3_reg  (ip2cpu_ctrl_regs3_wire),
    .cpu2ip_ctrl_regs3_reg  (cpu2ip_ctrl_regs3_wire),
    .ip2cpu_ctrl_regs4_reg  (ip2cpu_ctrl_regs4_wire),
    .cpu2ip_ctrl_regs4_reg  (cpu2ip_ctrl_regs4_wire),
    .return_regs0_reg       (return_regs0_wire),
    .return_regs1_reg       (return_regs1_wire),

    // AXI Lite ports
    .S_AXI_ACLK             ( S_AXI_ACLK     ),
    .S_AXI_ARESETN          ( S_AXI_ARESETN  ),
    .S_AXI_AWADDR           ( S_AXI_AWADDR   ),
    .S_AXI_AWVALID          ( S_AXI_AWVALID  ),
    .S_AXI_WDATA            ( S_AXI_WDATA    ),
    .S_AXI_WSTRB            ( S_AXI_WSTRB    ),
    .S_AXI_WVALID           ( S_AXI_WVALID   ),
    .S_AXI_BREADY           ( S_AXI_BREADY   ),
    .S_AXI_ARADDR           ( S_AXI_ARADDR   ),
    .S_AXI_ARVALID          ( S_AXI_ARVALID  ),
    .S_AXI_RREADY           ( S_AXI_RREADY   ),
    .S_AXI_ARREADY          ( S_AXI_ARREADY  ),
    .S_AXI_RDATA            ( S_AXI_RDATA    ),
    .S_AXI_RRESP            ( S_AXI_RRESP    ),
    .S_AXI_RVALID           ( S_AXI_RVALID   ),
    .S_AXI_WREADY           ( S_AXI_WREADY   ),
    .S_AXI_BRESP            ( S_AXI_BRESP    ),
    .S_AXI_BVALID           ( S_AXI_BVALID   ),
    .S_AXI_AWREADY          ( S_AXI_AWREADY  )

    );


endmodule
