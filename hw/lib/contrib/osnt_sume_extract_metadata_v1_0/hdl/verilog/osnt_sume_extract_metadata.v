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
 *        osnt_extract_metadata.v
 *
 *  Author:
 *        Muhammad Shahbaz
 *
 *  Description:
 */


`timescale 1ns/1ps
`include "extract_metadata_cpu_regs_defines.v"
`include "extract_metadata_cpu_regs.v"
module osnt_sume_extract_metadata
  #(
    parameter C_S_AXI_DATA_WIDTH   = 32,
    parameter C_S_AXI_ADDR_WIDTH   = 32,
    parameter C_BASEADDR           = 32'hFFFFFFFF,
    parameter C_HIGHADDR           = 32'h00000000,
    parameter C_USE_WSTRB          = 0,
    parameter C_DPHASE_TIMEOUT     = 0,
    parameter C_S_AXI_ACLK_FREQ_HZ = 100,
    parameter C_M_AXIS_DATA_WIDTH  = 256,
    parameter C_S_AXIS_DATA_WIDTH  = 256,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter C_TUSER_TIMESTAMP_POS = 32,
    parameter SIM_ONLY             = 0
    )
   (
    // Slave AXI Ports
    input 				   s_axi_aclk,
    input 				   s_axi_aresetn,
    input [C_S_AXI_ADDR_WIDTH-1:0] 	   s_axi_awaddr,
    input 				   s_axi_awvalid,
    input [C_S_AXI_DATA_WIDTH-1:0] 	   s_axi_wdata,
    input [C_S_AXI_DATA_WIDTH/8-1:0] 	   s_axi_wstrb,
    input 				   s_axi_wvalid,
    input 				   s_axi_bready,
    input [C_S_AXI_ADDR_WIDTH-1:0] 	   s_axi_araddr,
    input 				   s_axi_arvalid,
    input 				   s_axi_rready,
    output 				   s_axi_arready,
    output [C_S_AXI_DATA_WIDTH-1:0] 	   s_axi_rdata,
    output [1:0] 			   s_axi_rresp,
    output 				   s_axi_rvalid,
    output 				   s_axi_wready,
    output [1:0] 			   s_axi_bresp,
    output 				   s_axi_bvalid,
    output 				   s_axi_awready,

    // Master Stream Ports (interface to data path)
    input 				   axis_aclk,
    input 				   axis_aresetn,

    output [C_M_AXIS_DATA_WIDTH-1:0] 	   m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH/8))-1:0] m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] 	   m_axis_tuser,
    output 				   m_axis_tvalid,
    input 				   m_axis_tready,
    output 				   m_axis_tlast,
   
    // Slave Stream Ports (interface to RX queues)
    input [C_S_AXIS_DATA_WIDTH-1:0] 	   s_axis_tdata,
    input [((C_S_AXIS_DATA_WIDTH/8))-1:0]  s_axis_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0] 	   s_axis_tuser,
    input 				   s_axis_tvalid,
    output 				   s_axis_tready,
    input 				   s_axis_tlast
    );

   // -- Internal Parameters
   localparam NUM_RW_REGS = 2;
   localparam NUM_WO_REGS = 0;
   localparam NUM_RO_REGS = 0;

   // -- Signals
   wire [NUM_RW_REGS*C_S_AXI_DATA_WIDTH-1:0] rw_regs;

   wire 				     sw_rst;
   wire 				     em_enable;
   
   // --------------------------------------------------------
   wire [`REG_CTRL0_BITS] 		     ip2cpu_ctrl0;
   wire [`REG_CTRL0_BITS] 		     cpu2ip_ctrl0;
   wire [`REG_CTRL1_BITS] 		     ip2cpu_ctrl1;
   wire [`REG_CTRL1_BITS] 		     cpu2ip_ctrl1;

   assign ip2cpu_ctrl0 = cpu2ip_ctrl0;
   assign ip2cpu_ctrl1 = cpu2ip_ctrl1;

   assign rw_regs[(C_S_AXI_DATA_WIDTH*1)-1:(C_S_AXI_DATA_WIDTH*0)] = cpu2ip_ctrl0;
   assign rw_regs[(C_S_AXI_DATA_WIDTH*2)-1:(C_S_AXI_DATA_WIDTH*1)] = cpu2ip_ctrl1;  

   extract_metadata_cpu_regs #
     (
      .C_BASE_ADDRESS(C_BASEADDR),
      .C_S_AXI_DATA_WIDTH(32),
      .C_S_AXI_ADDR_WIDTH(32)
      )extract_metadata_cpu_regs
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

   // -- Register assignments

   assign sw_rst         = rw_regs[C_S_AXI_DATA_WIDTH*0:C_S_AXI_DATA_WIDTH*0];
   assign em_enable      = rw_regs[C_S_AXI_DATA_WIDTH*1:C_S_AXI_DATA_WIDTH*1];

   // -- Extract Metadata
   extract_metadata #
     (
      .C_M_AXIS_DATA_WIDTH   ( C_M_AXIS_DATA_WIDTH ),
      .C_S_AXIS_DATA_WIDTH   ( C_S_AXIS_DATA_WIDTH ),
      .C_M_AXIS_TUSER_WIDTH  ( C_M_AXIS_TUSER_WIDTH ),
      .C_S_AXIS_TUSER_WIDTH  ( C_S_AXIS_TUSER_WIDTH ),
      .C_S_AXI_DATA_WIDTH    ( C_S_AXI_DATA_WIDTH ),
      .C_TUSER_TIMESTAMP_POS ( C_TUSER_TIMESTAMP_POS ),
      .SIM_ONLY							 ( SIM_ONLY )
      
      )
   extract_metadata_inst
     (
      // Global Ports
      .axi_aclk             ( axis_aclk ),
      .axi_aresetn          ( axis_aresetn ),

      // Master Stream Ports (interface to data path)
      .m_axis_tdata       	( m_axis_tdata ),
      .m_axis_tstrb       	( m_axis_tkeep ),
      .m_axis_tuser       	( m_axis_tuser ),
      .m_axis_tvalid      	( m_axis_tvalid ),
      .m_axis_tready      	( m_axis_tready ),
      .m_axis_tlast       	( m_axis_tlast ),

      // Slave Stream Ports (interface to RX queues)
      .s_axis_tdata         ( s_axis_tdata ),
      .s_axis_tstrb         ( s_axis_tkeep ),
      .s_axis_tuser         ( s_axis_tuser ),
      .s_axis_tvalid        ( s_axis_tvalid ),
      .s_axis_tready        ( s_axis_tready ),
      .s_axis_tlast         ( s_axis_tlast ),

      // Misc
      .em_enable						( em_enable ),
      
      .sw_rst               ( sw_rst )
      );

endmodule
