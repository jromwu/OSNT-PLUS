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
 *        osnt_inter_packet_delay.v
 *
 *  Author:
 *        Muhammad Shahbaz
 *
 *  Description:
 */

`timescale 1ns/1ps
`include "inter_packet_delay_cpu_regs_defines.v"

module osnt_inter_packet_delay
#(
  parameter C_S_AXI_DATA_WIDTH    = 32,
  parameter C_S_AXI_ADDR_WIDTH    = 32,
  parameter C_BASEADDR            = 32'hFFFFFFFF,
  parameter C_HIGHADDR            = 32'h00000000,
  parameter C_USE_WSTRB           = 0,
  parameter C_DPHASE_TIMEOUT      = 0,
  parameter C_S_AXI_ACLK_FREQ_HZ  = 100,
  parameter C_M_AXIS_DATA_WIDTH   = 512,
  parameter C_S_AXIS_DATA_WIDTH   = 512,
  parameter C_M_AXIS_TUSER_WIDTH  = 128,
  parameter C_S_AXIS_TUSER_WIDTH  = 128,
  parameter C_TUSER_TIMESTAMP_POS = 32,
  parameter C_NUM_QUEUES          = 2,
  parameter SIM_ONLY              = 0
)
(
  // Clock and Reset

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
  input                                           axis_aclk,
  input                                           axis_aresetn,

  output     [C_M_AXIS_DATA_WIDTH-1:0]            m0_axis_tdata,
  output     [((C_M_AXIS_DATA_WIDTH/8))-1:0]      m0_axis_tkeep,
  output     [C_M_AXIS_TUSER_WIDTH-1:0]           m0_axis_tuser,
  output                                          m0_axis_tvalid,
  input                                           m0_axis_tready,
  output                                          m0_axis_tlast,

  output     [C_M_AXIS_DATA_WIDTH-1:0]            m1_axis_tdata,
  output     [((C_M_AXIS_DATA_WIDTH/8))-1:0]      m1_axis_tkeep,
  output     [C_M_AXIS_TUSER_WIDTH-1:0]           m1_axis_tuser,
  output                                          m1_axis_tvalid,
  input                                           m1_axis_tready,
  output                                          m1_axis_tlast,

  input      [C_S_AXIS_DATA_WIDTH-1:0]            s0_axis_tdata,
  input      [((C_S_AXIS_DATA_WIDTH/8))-1:0]      s0_axis_tkeep,
  input      [C_S_AXIS_TUSER_WIDTH-1:0]           s0_axis_tuser,
  input                                           s0_axis_tvalid,
  output                                          s0_axis_tready,
  input                                           s0_axis_tlast,

  input      [C_S_AXIS_DATA_WIDTH-1:0]            s1_axis_tdata,
  input      [((C_S_AXIS_DATA_WIDTH/8))-1:0]      s1_axis_tkeep,
  input      [C_S_AXIS_TUSER_WIDTH-1:0]           s1_axis_tuser,
  input                                           s1_axis_tvalid,
  output                                          s1_axis_tready,
  input                                           s1_axis_tlast
);

  // -- Internal Parameters
  localparam NUM_RW_REGS = 4*C_NUM_QUEUES;
localparam NUM_WO_REGS = 0;
localparam NUM_RO_REGS = 0;

  // -- Signals

  genvar                                          i;

  wire     [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0]   rw_regs;

  wire                                            sw_rst[0:C_NUM_QUEUES-1];
  wire                                            ipd_en[0:C_NUM_QUEUES-1];
  wire                                            use_reg_val[0:C_NUM_QUEUES-1];
  wire     [C_S_AXI_DATA_WIDTH-1:0]               delay_reg_val[0:C_NUM_QUEUES-1];

  // -- Register assignments

    generate 
      for (i=0; i<C_NUM_QUEUES; i=i+1) begin: _regs
        assign sw_rst[i]        = rw_regs[C_S_AXI_DATA_WIDTH*((i*4)+0)+( 1-1):C_S_AXI_DATA_WIDTH*((i*4)+0)];
        assign ipd_en[i]        = rw_regs[C_S_AXI_DATA_WIDTH*((i*4)+1)+( 1-1):C_S_AXI_DATA_WIDTH*((i*4)+1)];
        assign use_reg_val[i]   = rw_regs[C_S_AXI_DATA_WIDTH*((i*4)+2)+( 1-1):C_S_AXI_DATA_WIDTH*((i*4)+2)];
        assign delay_reg_val[i] = rw_regs[C_S_AXI_DATA_WIDTH*((i*4)+3)+(32-1):C_S_AXI_DATA_WIDTH*((i*4)+3)];
      end
    endgenerate

  // -- Inter Packet Delay
    generate
      if (C_NUM_QUEUES > 0) begin: _ipd_0
      inter_packet_delay #
      (
        .C_M_AXIS_DATA_WIDTH   ( C_M_AXIS_DATA_WIDTH ),
        .C_S_AXIS_DATA_WIDTH   ( C_S_AXIS_DATA_WIDTH ),
        .C_M_AXIS_TUSER_WIDTH  ( C_M_AXIS_TUSER_WIDTH ),
        .C_S_AXIS_TUSER_WIDTH  ( C_S_AXIS_TUSER_WIDTH ),
        .C_S_AXI_DATA_WIDTH    ( C_S_AXI_DATA_WIDTH ),
        .C_TUSER_TIMESTAMP_POS ( C_TUSER_TIMESTAMP_POS )
      )
        _inst
      (
        // Global Ports
        .axi_aclk             ( axis_aclk ),
        .axi_aresetn          ( axis_aresetn ),

        // Master Stream Ports (interface to data path)
        .m_axis_tdata         ( m0_axis_tdata ),
        .m_axis_tstrb         ( m0_axis_tkeep ),
        .m_axis_tuser         ( m0_axis_tuser ),
        .m_axis_tvalid        ( m0_axis_tvalid ),
        .m_axis_tready        ( m0_axis_tready ),
        .m_axis_tlast         ( m0_axis_tlast ),

        // Slave Stream Ports (interface to RX queues)
        .s_axis_tdata         ( s0_axis_tdata ),
        .s_axis_tstrb         ( s0_axis_tkeep ),
        .s_axis_tuser         ( s0_axis_tuser ),
        .s_axis_tvalid        ( s0_axis_tvalid ),
        .s_axis_tready        ( s0_axis_tready ),
        .s_axis_tlast         ( s0_axis_tlast ),

        .sw_rst               ( sw_rst[0] ),
        .ipd_en               ( ipd_en[0] ),
        .use_reg_val          ( use_reg_val[0] ),
        .delay_reg_val        ( delay_reg_val[0] )
      );
      end

      if (C_NUM_QUEUES > 1) begin: _ipd_1
      inter_packet_delay #
      (
        .C_M_AXIS_DATA_WIDTH   ( C_M_AXIS_DATA_WIDTH ),
        .C_S_AXIS_DATA_WIDTH   ( C_S_AXIS_DATA_WIDTH ),
        .C_M_AXIS_TUSER_WIDTH  ( C_M_AXIS_TUSER_WIDTH ),
        .C_S_AXIS_TUSER_WIDTH  ( C_S_AXIS_TUSER_WIDTH ),
        .C_S_AXI_DATA_WIDTH    ( C_S_AXI_DATA_WIDTH ),
        .C_TUSER_TIMESTAMP_POS ( C_TUSER_TIMESTAMP_POS )
      )
        _inst
      (
        // Global Ports
        .axi_aclk             ( axis_aclk ),
        .axi_aresetn          ( axis_aresetn ),

        // Master Stream Ports (interface to data path)
        .m_axis_tdata         ( m1_axis_tdata ),
        .m_axis_tstrb         ( m1_axis_tkeep ),
        .m_axis_tuser         ( m1_axis_tuser ),
        .m_axis_tvalid        ( m1_axis_tvalid ),
        .m_axis_tready        ( m1_axis_tready ),
        .m_axis_tlast         ( m1_axis_tlast ),

        // Slave Stream Ports (interface to RX queues)
        .s_axis_tdata         ( s1_axis_tdata ),
        .s_axis_tstrb         ( s1_axis_tkeep ),
        .s_axis_tuser         ( s1_axis_tuser ),
        .s_axis_tvalid        ( s1_axis_tvalid ),
        .s_axis_tready        ( s1_axis_tready ),
        .s_axis_tlast         ( s1_axis_tlast ),

        .sw_rst               ( sw_rst[1] ),
        .ipd_en               ( ipd_en[1] ),
        .use_reg_val          ( use_reg_val[1] ),
        .delay_reg_val        ( delay_reg_val[1] )
      );
      end
    endgenerate

   // -------------------- CPU Registers -----------------------------

   wire [`REG_CTRL0_BITS] 		     ip2cpu_ctrl0;
   wire [`REG_CTRL0_BITS] 		     cpu2ip_ctrl0;
   wire [`REG_CTRL1_BITS] 		     ip2cpu_ctrl1;
   wire [`REG_CTRL1_BITS] 		     cpu2ip_ctrl1;
   wire [`REG_CTRL2_BITS] 		     ip2cpu_ctrl2;
   wire [`REG_CTRL2_BITS] 		     cpu2ip_ctrl2;
   wire [`REG_CTRL3_BITS] 		     ip2cpu_ctrl3;
   wire [`REG_CTRL3_BITS] 		     cpu2ip_ctrl3;
   wire [`REG_CTRL4_BITS] 		     ip2cpu_ctrl4;
   wire [`REG_CTRL4_BITS] 		     cpu2ip_ctrl4;
   wire [`REG_CTRL5_BITS] 		     ip2cpu_ctrl5;
   wire [`REG_CTRL5_BITS] 		     cpu2ip_ctrl5;
   wire [`REG_CTRL6_BITS] 		     ip2cpu_ctrl6;
   wire [`REG_CTRL6_BITS] 		     cpu2ip_ctrl6;
   wire [`REG_CTRL7_BITS] 		     ip2cpu_ctrl7;
   wire [`REG_CTRL7_BITS] 		     cpu2ip_ctrl7;
   wire [`REG_CTRL8_BITS] 		     ip2cpu_ctrl8;
   wire [`REG_CTRL8_BITS] 		     cpu2ip_ctrl8;
   wire [`REG_CTRL9_BITS] 		     ip2cpu_ctrl9;
   wire [`REG_CTRL9_BITS] 		     cpu2ip_ctrl9;
   wire [`REG_CTRL10_BITS] 		     ip2cpu_ctrl10;
   wire [`REG_CTRL10_BITS] 		     cpu2ip_ctrl10;
   wire [`REG_CTRL11_BITS] 		     ip2cpu_ctrl11;
   wire [`REG_CTRL11_BITS] 		     cpu2ip_ctrl11;
   wire [`REG_CTRL12_BITS] 		     ip2cpu_ctrl12;
   wire [`REG_CTRL12_BITS] 		     cpu2ip_ctrl12;
   wire [`REG_CTRL13_BITS] 		     ip2cpu_ctrl13;
   wire [`REG_CTRL13_BITS] 		     cpu2ip_ctrl13;
   wire [`REG_CTRL14_BITS] 		     ip2cpu_ctrl14;
   wire [`REG_CTRL14_BITS] 		     cpu2ip_ctrl14;
   wire [`REG_CTRL15_BITS] 		     ip2cpu_ctrl15;
   wire [`REG_CTRL15_BITS] 		     cpu2ip_ctrl15;

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
   assign ip2cpu_ctrl14 = cpu2ip_ctrl14;
   assign ip2cpu_ctrl15 = cpu2ip_ctrl15;

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
   assign rw_regs[C_S_AXI_DATA_WIDTH * 15 - 1:C_S_AXI_DATA_WIDTH * 14] = cpu2ip_ctrl14;
   assign rw_regs[C_S_AXI_DATA_WIDTH * 16 - 1:C_S_AXI_DATA_WIDTH * 15] = cpu2ip_ctrl15;

   inter_packet_delay_cpu_regs #
     (
      .C_BASE_ADDRESS(C_BASEADDR),
      .C_S_AXI_DATA_WIDTH(32),
      .C_S_AXI_ADDR_WIDTH(32)
      )
   (
    // General ports
    .clk(s_axi_aclk),
    .resetn(s_axi_aresetn),
    // Global Registers
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
    .ip2cpu_ctrl14_reg(ip2cpu_ctrl14),
    .cpu2ip_ctrl14_reg(cpu2ip_ctrl14),
    .ip2cpu_ctrl15_reg(ip2cpu_ctrl15),
    .cpu2ip_ctrl15_reg(cpu2ip_ctrl15),

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
