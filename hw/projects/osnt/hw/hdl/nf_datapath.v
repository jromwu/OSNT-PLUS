`timescale 1ns / 1ps
//-
// Copyright (c) 2015 Noa Zilberman
// Copyright (c) 2021 Yuta Tokusashi
// Copyright (c) 2022 Gianni Antichi
// All rights reserved.
//
// This software was developed by Stanford University and the University of Cambridge Computer Laboratory 
// under National Science Foundation under Grant No. CNS-0855268,
// the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
// by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
// as part of the DARPA MRC research programme,
// and by the University of Cambridge Computer Laboratory under EPSRC EARL Project
// EP/P025374/1 alongside support from Xilinx Inc.
//
//  File:
//        nf_datapath.v
//
//  Module:
//        nf_datapath
//
//  Author: Noa Zilberman
//
//  Description:
//        NetFPGA user data path wrapper, wrapping input arbiter, output port lookup and output queues
//
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


module nf_datapath #(
    //Slave AXI parameters
    parameter C_S_AXI_DATA_WIDTH    = 32,          
    parameter C_S_AXI_ADDR_WIDTH    = 32,          
    parameter C_BASEADDR            = 32'h00000000,

    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH  = 512,
    parameter C_S_AXIS_DATA_WIDTH  = 512,
    parameter C_TX_DATA_WIDTH      = 512,
    parameter C_M_AXIS_TUSER_WIDTH = 128,
    parameter C_S_AXIS_TUSER_WIDTH = 128,
    parameter NUM_QUEUES           = 3
) (
    //Datapath clock
    input                                     axis_aclk,
    input                                     axis_resetn,
    //Registers clock
    input                                     axi_aclk,
    input                                     axi_resetn,

    // Slave AXI Ports
    //Extract Metadata
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S0_AXI_AWADDR,
    input                                     S0_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S0_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S0_AXI_WSTRB,
    input                                     S0_AXI_WVALID,
    input                                     S0_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S0_AXI_ARADDR,
    input                                     S0_AXI_ARVALID,
    input                                     S0_AXI_RREADY,
    output                                    S0_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S0_AXI_RDATA,
    output     [1 : 0]                        S0_AXI_RRESP,
    output                                    S0_AXI_RVALID,
    output                                    S0_AXI_WREADY,
    output     [1 :0]                         S0_AXI_BRESP,
    output                                    S0_AXI_BVALID,
    output                                    S0_AXI_AWREADY,
    // NIC OPL
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S1_AXI_AWADDR,
    input                                     S1_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S1_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S1_AXI_WSTRB,
    input                                     S1_AXI_WVALID,
    input                                     S1_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S1_AXI_ARADDR,
    input                                     S1_AXI_ARVALID,
    input                                     S1_AXI_RREADY,
    output                                    S1_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S1_AXI_RDATA,
    output     [1 : 0]                        S1_AXI_RRESP,
    output                                    S1_AXI_RVALID,
    output                                    S1_AXI_WREADY,
    output     [1 :0]                         S1_AXI_BRESP,
    output                                    S1_AXI_BVALID,
    output                                    S1_AXI_AWREADY,
    // PCAP Reply
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S2_AXI_AWADDR,
    input                                     S2_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S2_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S2_AXI_WSTRB,
    input                                     S2_AXI_WVALID,
    input                                     S2_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S2_AXI_ARADDR,
    input                                     S2_AXI_ARVALID,
    input                                     S2_AXI_RREADY,
    output                                    S2_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S2_AXI_RDATA,
    output     [1 : 0]                        S2_AXI_RRESP,
    output                                    S2_AXI_RVALID,
    output                                    S2_AXI_WREADY,
    output     [1 :0]                         S2_AXI_BRESP,
    output                                    S2_AXI_BVALID,
    output                                    S2_AXI_AWREADY,
    // Inter Packet Delay
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S3_AXI_AWADDR,
    input                                     S3_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S3_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S3_AXI_WSTRB,
    input                                     S3_AXI_WVALID,
    input                                     S3_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S3_AXI_ARADDR,
    input                                     S3_AXI_ARVALID,
    input                                     S3_AXI_RREADY,
    output                                    S3_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S3_AXI_RDATA,
    output     [1 : 0]                        S3_AXI_RRESP,
    output                                    S3_AXI_RVALID,
    output                                    S3_AXI_WREADY,
    output     [1 :0]                         S3_AXI_BRESP,
    output                                    S3_AXI_BVALID,
    output                                    S3_AXI_AWREADY,
    // Rate Limiter
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S4_AXI_AWADDR,
    input                                     S4_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S4_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S4_AXI_WSTRB,
    input                                     S4_AXI_WVALID,
    input                                     S4_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S4_AXI_ARADDR,
    input                                     S4_AXI_ARVALID,
    input                                     S4_AXI_RREADY,
    output                                    S4_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S4_AXI_RDATA,
    output     [1 : 0]                        S4_AXI_RRESP,
    output                                    S4_AXI_RVALID,
    output                                    S4_AXI_WREADY,
    output     [1 :0]                         S4_AXI_BRESP,
    output                                    S4_AXI_BVALID,
    output                                    S4_AXI_AWREADY,
    // Input Arbiter
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S5_AXI_AWADDR,
    input                                     S5_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S5_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S5_AXI_WSTRB,
    input                                     S5_AXI_WVALID,
    input                                     S5_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S5_AXI_ARADDR,
    input                                     S5_AXI_ARVALID,
    input                                     S5_AXI_RREADY,
    output                                    S5_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S5_AXI_RDATA,
    output     [1 : 0]                        S5_AXI_RRESP,
    output                                    S5_AXI_RVALID,
    output                                    S5_AXI_WREADY,
    output     [1 :0]                         S5_AXI_BRESP,
    output                                    S5_AXI_BVALID,
    output                                    S5_AXI_AWREADY,
    // Packet Cutter (not yet present)
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S6_AXI_AWADDR,
    input                                     S6_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S6_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S6_AXI_WSTRB,
    input                                     S6_AXI_WVALID,
    input                                     S6_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S6_AXI_ARADDR,
    input                                     S6_AXI_ARVALID,
    input                                     S6_AXI_RREADY,
    output                                    S6_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S6_AXI_RDATA,
    output     [1 : 0]                        S6_AXI_RRESP,
    output                                    S6_AXI_RVALID,
    output                                    S6_AXI_WREADY,
    output     [1 :0]                         S6_AXI_BRESP,
    output                                    S6_AXI_BVALID,
    output                                    S6_AXI_AWREADY,
    // Monitoring OPL (not yet present)
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S7_AXI_AWADDR,
    input                                     S7_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S7_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S7_AXI_WSTRB,
    input                                     S7_AXI_WVALID,
    input                                     S7_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S7_AXI_ARADDR,
    input                                     S7_AXI_ARVALID,
    input                                     S7_AXI_RREADY,
    output                                    S7_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S7_AXI_RDATA,
    output     [1 : 0]                        S7_AXI_RRESP,
    output                                    S7_AXI_RVALID,
    output                                    S7_AXI_WREADY,
    output     [1 :0]                         S7_AXI_BRESP,
    output                                    S7_AXI_BVALID,
    output                                    S7_AXI_AWREADY,
    // Memory mapped BRAM (port 0)
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S8_AXI_AWADDR,
    input                                     S8_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S8_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S8_AXI_WSTRB,
    input                                     S8_AXI_WVALID,
    input                                     S8_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S8_AXI_ARADDR,
    input                                     S8_AXI_ARVALID,
    input                                     S8_AXI_RREADY,
    output                                    S8_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S8_AXI_RDATA,
    output     [1 : 0]                        S8_AXI_RRESP,
    output                                    S8_AXI_RVALID,
    output                                    S8_AXI_WREADY,
    output     [1 :0]                         S8_AXI_BRESP,
    output                                    S8_AXI_BVALID,
    output                                    S8_AXI_AWREADY,
    // Memory mapped BRAM (port 1)
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S9_AXI_AWADDR,
    input                                     S9_AXI_AWVALID,
    input      [C_S_AXI_DATA_WIDTH-1 : 0]     S9_AXI_WDATA,
    input      [C_S_AXI_DATA_WIDTH/8-1 : 0]   S9_AXI_WSTRB,
    input                                     S9_AXI_WVALID,
    input                                     S9_AXI_BREADY,
    input      [C_S_AXI_ADDR_WIDTH-1 : 0]     S9_AXI_ARADDR,
    input                                     S9_AXI_ARVALID,
    input                                     S9_AXI_RREADY,
    output                                    S9_AXI_ARREADY,
    output     [C_S_AXI_DATA_WIDTH-1 : 0]     S9_AXI_RDATA,
    output     [1 : 0]                        S9_AXI_RRESP,
    output                                    S9_AXI_RVALID,
    output                                    S9_AXI_WREADY,
    output     [1 :0]                         S9_AXI_BRESP,
    output                                    S9_AXI_BVALID,
    output                                    S9_AXI_AWREADY,

    // Slave Stream Ports (interface from Rx queues)
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_0_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_0_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_0_tuser,
    input                                     s_axis_0_tvalid,
    output                                    s_axis_0_tready,
    input                                     s_axis_0_tlast,
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_1_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_1_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_1_tuser,
    input                                     s_axis_1_tvalid,
    output                                    s_axis_1_tready,
    input                                     s_axis_1_tlast,
    input [C_TX_DATA_WIDTH-1:0]               s_axis_2_tdata,
    input [((C_TX_DATA_WIDTH/8))-1:0]         s_axis_2_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_2_tuser,
    input                                     s_axis_2_tvalid,
    output                                    s_axis_2_tready,
    input                                     s_axis_2_tlast,


    // Master Stream Ports (interface to TX queues)
    output [C_TX_DATA_WIDTH-1:0]               m_axis_0_tdata,
    output [((C_TX_DATA_WIDTH/8))-1:0]         m_axis_0_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_0_tuser,
    output                                     m_axis_0_tvalid,
    input                                      m_axis_0_tready,
    output                                     m_axis_0_tlast,
    output [C_TX_DATA_WIDTH-1:0]               m_axis_1_tdata,
    output [((C_TX_DATA_WIDTH/8))-1:0]         m_axis_1_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_1_tuser,
    output                                     m_axis_1_tvalid,
    input                                      m_axis_1_tready,
    output                                     m_axis_1_tlast,
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_2_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_2_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_2_tuser,
    output                                     m_axis_2_tvalid,
    input                                      m_axis_2_tready,
    output                                     m_axis_2_tlast

    );
    


    localparam ADDR_WIDTH = 14; //hardcoded. Need to be consistent with osnt_bram module
    localparam DATA_WIDTH = 736;//hardcoded. Need to be consistent with osnt_bram module
    //internal connectivity
  
    // from Extract Metadata to NIC output port lookup
    wire [C_TX_DATA_WIDTH-1:0]               m_axis_meta_tdata;
    wire [((C_TX_DATA_WIDTH/8))-1:0]         m_axis_meta_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_meta_tuser;
    wire                                     m_axis_meta_tvalid;
    wire                                     m_axis_meta_tready;
    wire                                     m_axis_meta_tlast;
    // from NIC output port lookup to PCAP reply 
    wire [C_TX_DATA_WIDTH-1:0]               m_axis_opl_tdata;
    wire [((C_TX_DATA_WIDTH/8))-1:0]         m_axis_opl_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_opl_tuser;
    wire                                     m_axis_opl_tvalid;
    wire                                     m_axis_opl_tready;
    wire                                     m_axis_opl_tlast;
    // PCAP reply <-> BRAM mem port 0
    wire [ADDR_WIDTH-1:0]                    ip2bram_addr0;
    wire [DATA_WIDTH-1:0]                    ip2bram_dout0;
    wire [DATA_WIDTH-1:0]                    ip2bram_din0;
    wire                                     ip2bram_en0;
    wire                                     ip2bram_we0;
    // PCAP reply <-> BRAM mem port 1
    wire [ADDR_WIDTH-1:0]                    ip2bram_addr1;
    wire [DATA_WIDTH-1:0]                    ip2bram_dout1;
    wire [DATA_WIDTH-1:0]                    ip2bram_din1;
    wire                                     ip2bram_en1;
    wire                                     ip2bram_we1;
//   // Memory mapping for BRAM mem port 0
//    wire [ADDR_WIDTH-1:0]                    h2ip_addr0;
//    wire [DATA_WIDTH-1:0]                    h2ip_wrdata0;
//    wire [DATA_WIDTH-1:0]                    h2ip_rddata0;
//    wire                                     h2ip_en0;
//    wire                                     h2ip_we0;    
//   // Memory mapping for BRAM mem port 1
//    wire [ADDR_WIDTH-1:0]                    h2ip_addr1;
//    wire [DATA_WIDTH-1:0]                    h2ip_wrdata1;
//    wire [DATA_WIDTH-1:0]                    h2ip_rddata1;
//    wire                                     h2ip_en1;
//    wire                                     h2ip_we1;  
   // PCAP Reply to Inter Packet Delay
    wire [C_TX_DATA_WIDTH-1:0]               m0_axis_pcap_tdata;
    wire [((C_TX_DATA_WIDTH/8))-1:0]         m0_axis_pcap_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          m0_axis_pcap_tuser;
    wire                                     m0_axis_pcap_tvalid;
    wire                                     m0_axis_pcap_tready;
    wire                                     m0_axis_pcap_tlast;
    wire [C_TX_DATA_WIDTH-1:0]               m1_axis_pcap_tdata;
    wire [((C_TX_DATA_WIDTH/8))-1:0]         m1_axis_pcap_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          m1_axis_pcap_tuser;
    wire                                     m1_axis_pcap_tvalid;
    wire                                     m1_axis_pcap_tready;
    wire                                     m1_axis_pcap_tlast;
   // Inter Packet Delay to Rate Limiter
    wire [C_TX_DATA_WIDTH-1:0]               m0_axis_ipd_tdata;
    wire [((C_TX_DATA_WIDTH/8))-1:0]         m0_axis_ipd_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          m0_axis_ipd_tuser;
    wire                                     m0_axis_ipd_tvalid;
    wire                                     m0_axis_ipd_tready;
    wire                                     m0_axis_ipd_tlast;
    wire [C_TX_DATA_WIDTH-1:0]               m1_axis_ipd_tdata;
    wire [((C_TX_DATA_WIDTH/8))-1:0]         m1_axis_ipd_tkeep;
    wire [C_M_AXIS_TUSER_WIDTH-1:0]          m1_axis_ipd_tuser;
    wire                                     m1_axis_ipd_tvalid;
    wire                                     m1_axis_ipd_tready;
    wire                                     m1_axis_ipd_tlast;

  //----------------------------------------------------------
  // OSNT TX pipeline
  //---------------------------------------------------------
  //Extract Metadata
  osnt_extract_metadata_ip  u_osnt_extract_metadata_0 (
      .axis_aclk(axis_aclk),
      .axis_aresetn(axis_resetn),
      .m_axis_tdata (m_axis_meta_tdata),
      .m_axis_tkeep (m_axis_meta_tkeep),
      .m_axis_tuser (m_axis_meta_tuser),
      .m_axis_tvalid(m_axis_meta_tvalid),
      .m_axis_tready(m_axis_meta_tready),
      .m_axis_tlast (m_axis_meta_tlast),
      .s_axis_tdata (s_axis_2_tdata),
      .s_axis_tkeep (s_axis_2_tkeep),
      .s_axis_tuser (s_axis_2_tuser),
      .s_axis_tvalid(s_axis_2_tvalid),
      .s_axis_tready(s_axis_2_tready),
      .s_axis_tlast (s_axis_2_tlast),
      .s_axi_awaddr(S0_AXI_AWADDR),
      .s_axi_awvalid(S0_AXI_AWVALID),
      .s_axi_wdata(S0_AXI_WDATA),
      .s_axi_wstrb(S0_AXI_WSTRB),
      .s_axi_wvalid(S0_AXI_WVALID),
      .s_axi_bready(S0_AXI_BREADY),
      .s_axi_araddr(S0_AXI_ARADDR),
      .s_axi_arvalid(S0_AXI_ARVALID),
      .s_axi_rready(S0_AXI_RREADY),
      .s_axi_arready(S0_AXI_ARREADY),
      .s_axi_rdata(S0_AXI_RDATA),
      .s_axi_rresp(S0_AXI_RRESP),
      .s_axi_rvalid(S0_AXI_RVALID),
      .s_axi_wready(S0_AXI_WREADY),
      .s_axi_bresp(S0_AXI_BRESP),
      .s_axi_bvalid(S0_AXI_BVALID),
      .s_axi_awready(S0_AXI_AWREADY),
      .s_axi_aclk (axi_aclk),
      .s_axi_aresetn(axi_resetn)
    );
  //NIC Output Port Lookup  
  nic_output_port_lookup_ip  u_nic_output_port_lookup_0  (
      .axis_aclk(axis_aclk),
      .axis_resetn(axis_resetn),
      .m_axis_tdata (m_axis_opl_tdata),
      .m_axis_tkeep (m_axis_opl_tkeep),
      .m_axis_tuser (m_axis_opl_tuser),
      .m_axis_tvalid(m_axis_opl_tvalid),
      .m_axis_tready(m_axis_opl_tready),
      .m_axis_tlast (m_axis_opl_tlast),
      .s_axis_tdata (m_axis_meta_tdata),
      .s_axis_tkeep (m_axis_meta_tkeep),
      .s_axis_tuser (m_axis_meta_tuser),
      .s_axis_tvalid(m_axis_meta_tvalid),
      .s_axis_tready(m_axis_meta_tready),
      .s_axis_tlast (m_axis_meta_tlast),
      .S_AXI_AWADDR(S1_AXI_AWADDR),
      .S_AXI_AWVALID(S1_AXI_AWVALID),
      .S_AXI_WDATA(S1_AXI_WDATA),
      .S_AXI_WSTRB(S1_AXI_WSTRB),
      .S_AXI_WVALID(S1_AXI_WVALID),
      .S_AXI_BREADY(S1_AXI_BREADY),
      .S_AXI_ARADDR(S1_AXI_ARADDR),
      .S_AXI_ARVALID(S1_AXI_ARVALID),
      .S_AXI_RREADY(S1_AXI_RREADY),
      .S_AXI_ARREADY(S1_AXI_ARREADY),
      .S_AXI_RDATA(S1_AXI_RDATA),
      .S_AXI_RRESP(S1_AXI_RRESP),
      .S_AXI_RVALID(S1_AXI_RVALID),
      .S_AXI_WREADY(S1_AXI_WREADY),
      .S_AXI_BRESP(S1_AXI_BRESP),
      .S_AXI_BVALID(S1_AXI_BVALID),
      .S_AXI_AWREADY(S1_AXI_AWREADY),
      .S_AXI_ACLK (axi_aclk),
      .S_AXI_ARESETN(axi_resetn)
    );
  //PCAP Reply  
  osnt_bram_pcap_replay_uengine_ip  u_osnt_bram_pcap_replay_uengine_0  (
      .axis_aclk(axis_aclk),
      .axis_aresetn(axis_resetn),
      .m0_axis_tdata (m0_axis_pcap_tdata),
      .m0_axis_tkeep (m0_axis_pcap_tkeep),
      .m0_axis_tuser (m0_axis_pcap_tuser),
      .m0_axis_tvalid(m0_axis_pcap_tvalid),
      .m0_axis_tready(m0_axis_pcap_tready),
      .m0_axis_tlast (m0_axis_pcap_tlast),
      .m1_axis_tdata (m1_axis_pcap_tdata),
      .m1_axis_tkeep (m1_axis_pcap_tkeep),
      .m1_axis_tuser (m1_axis_pcap_tuser),
      .m1_axis_tvalid(m1_axis_pcap_tvalid),
      .m1_axis_tready(m1_axis_pcap_tready),
      .m1_axis_tlast (m1_axis_pcap_tlast),
      .s_axis_tdata (m_axis_opl_tdata),
      .s_axis_tkeep (m_axis_opl_tkeep),
      .s_axis_tuser (m_axis_opl_tuser),
      .s_axis_tvalid(m_axis_opl_tvalid),
      .s_axis_tready(m_axis_opl_tready),
      .s_axis_tlast (m_axis_opl_tlast),
      .addra0(ip2bram_addr0),
      .ena0(ip2bram_en0),
      .wea0(ip2bram_we0),
      .douta0(ip2bram_dout0),
      .dina0(ip2bram_din0),
      .addra1(ip2bram_addr1),
      .ena1(ip2bram_en1),
      .wea1(ip2bram_we1),
      .douta1(ip2bram_dout1),
      .dina1(ip2bram_dout1),
      .s_axi_awaddr(S2_AXI_AWADDR),
      .s_axi_awvalid(S2_AXI_AWVALID),
      .s_axi_wdata(S2_AXI_WDATA),
      .s_axi_wstrb(S2_AXI_WSTRB),
      .s_axi_wvalid(S2_AXI_WVALID),
      .s_axi_bready(S2_AXI_BREADY),
      .s_axi_araddr(S2_AXI_ARADDR),
      .s_axi_arvalid(S2_AXI_ARVALID),
      .s_axi_rready(S2_AXI_RREADY),
      .s_axi_arready(S2_AXI_ARREADY),
      .s_axi_rdata(S2_AXI_RDATA),
      .s_axi_rresp(S2_AXI_RRESP),
      .s_axi_rvalid(S2_AXI_RVALID),
      .s_axi_wready(S2_AXI_WREADY),
      .s_axi_bresp(S2_AXI_BRESP),
      .s_axi_bvalid(S2_AXI_BVALID),
      .s_axi_awready(S2_AXI_AWREADY),
      .s_axi_aclk (axi_aclk),
      .s_axi_aresetn(axi_resetn)
    );
  //BRAM memory port 0  
  osnt_bram_ip  u_osnt_bram_0  (
//      .bram_clk_a(axi_aclk),
//      .bram_rst_a(axi_resetn),
//      .bram_addr_a(h2ip_addr0),
//      .bram_en_a(h2ip_en0),
//      .bram_we_a(h2ip_we0),      
//      .bram_wrdata_a(h2ip_wrdata0),
//      .bram_rddata_a(h2ip_rddata0),
      .bram_clk(axi_aclk),
      .bram_rst(axi_resetn), 
      .bram_addr(ip2bram_addr0),
      .bram_en(ip2bram_en0),
      .bram_we(ip2bram_we0),            
      .bram_wrdata(ip2bram_dout0),
      .bram_rddata(ip2bram_din0)
    );
//   //BRAM memory port 0 (memory mapping) 
//   axi_bram_ctrl_0 u_axi_bram_ctrl_0 (
//      .s_axi_aclk    (axi_aclk),
//      .s_axi_aresetn (axi_resetn),
//      .s_axi_awaddr  (S8_AXI_AWADDR),
//      .s_axi_awprot  (),
//      .s_axi_awvalid (S8_AXI_AWVALID),
//      .s_axi_awready (S8_AXI_AWREADY),
//      .s_axi_wdata   (S8_AXI_WDATA),
//      .s_axi_wstrb   (S8_AXI_WSTRB),
//      .s_axi_wvalid  (S8_AXI_WVALID),
//      .s_axi_wready  (S8_AXI_WREADY),
//      .s_axi_bresp   (S8_AXI_BRESP),
//      .s_axi_bvalid  (S8_AXI_BVALID),
//      .s_axi_bready  (S8_AXI_BREADY),
//      .s_axi_araddr  (S8_AXI_ARADDR),
//      .s_axi_arprot  (),
//      .s_axi_arvalid (S8_AXI_ARVALID),
//      .s_axi_arready (S8_AXI_ARREADY),
//      .s_axi_rdata   (S8_AXI_RDATA),
//      .s_axi_rresp   (S8_AXI_RRESP),
//      .s_axi_rvalid  (S8_AXI_RVALID),
//      .s_axi_rready  (S8_AXI_RREADY),
//      .bram_rst_a    (axi_resetn),
//      .bram_clk_a    (axi_aclk),
//      .bram_en_a     (h2ip_en0),
//      .bram_we_a     (h2ip_we0),
//      .bram_addr_a   (h2ip_addr0),
//      .bram_wrdata_a (h2ip_wrdata0),
//      .bram_rddata_a (h2ip_rddata0)
//    );
  //BRAM memory port 1  
  osnt_bram_ip  u_osnt_bram_1  (
//      .bram_clk_a(axi_aclk),
//      .bram_rst_a(axi_resetn),
//      .bram_addr_a(h2ip_addr1),
//      .bram_en_a(h2ip_en1),
//      .bram_we_a(h2ip_we1),
//      .bram_wrdata_a(h2ip_wrdata1),
//      .bram_rddata_a(h2ip_rddata1),
      .bram_clk(axi_aclk),
      .bram_rst(axi_resetn),
      .bram_addr(ip2bram_addr1),
      .bram_en(ip2bram_en1),
      .bram_we(ip2bram_we1),
      .bram_wrdata(ip2bram_dout1),
      .bram_rddata(ip2bram_din1)
    );
//   //BRAM memory port 1 (memory mapping) 
//   axi_bram_ctrl_0 u_axi_bram_ctrl_1 (
//      .s_axi_aclk    (axi_aclk),
//      .s_axi_aresetn (axi_resetn),
//      .s_axi_awaddr  (S9_AXI_AWADDR),
//      .s_axi_awprot  (),
//      .s_axi_awvalid (S9_AXI_AWVALID),
//      .s_axi_awready (S9_AXI_AWREADY),
//      .s_axi_wdata   (S9_AXI_WDATA),
//      .s_axi_wstrb   (S9_AXI_WSTRB),
//      .s_axi_wvalid  (S9_AXI_WVALID),
//      .s_axi_wready  (S9_AXI_WREADY),
//      .s_axi_bresp   (S9_AXI_BRESP),
//      .s_axi_bvalid  (S9_AXI_BVALID),
//      .s_axi_bready  (S9_AXI_BREADY),
//      .s_axi_araddr  (S9_AXI_ARADDR),
//      .s_axi_arprot  (),
//      .s_axi_arvalid (S9_AXI_ARVALID),
//      .s_axi_arready (S9_AXI_ARREADY),
//      .s_axi_rdata   (S9_AXI_RDATA),
//      .s_axi_rresp   (S9_AXI_RRESP),
//      .s_axi_rvalid  (S9_AXI_RVALID),
//      .s_axi_rready  (S9_AXI_RREADY),
//      .bram_rst_a    (axi_resetn),
//      .bram_clk_a    (axi_aclk),
//      .bram_en_a     (h2ip_en1),
//      .bram_we_a     (h2ip_we1),
//      .bram_addr_a   (h2ip_addr1),
//      .bram_wrdata_a (h2ip_wrdata1),
//      .bram_rddata_a (h2ip_rddata1)
//    );
  //Inter Packet Delay
  osnt_inter_packet_delay_ip  u_osnt_inter_packet_delay_0  (
      .axis_aclk(axis_aclk),
      .axis_aresetn(axis_resetn),
      .m0_axis_tdata (m0_axis_ipd_tdata),
      .m0_axis_tkeep (m0_axis_ipd_tkeep),
      .m0_axis_tuser (m0_axis_ipd_tuser),
      .m0_axis_tvalid(m0_axis_ipd_tvalid),
      .m0_axis_tready(m0_axis_ipd_tready),
      .m0_axis_tlast (m0_axis_ipd_tlast),
      .m1_axis_tdata (m1_axis_ipd_tdata),
      .m1_axis_tkeep (m1_axis_ipd_tkeep),
      .m1_axis_tuser (m1_axis_ipd_tuser),
      .m1_axis_tvalid(m1_axis_ipd_tvalid),
      .m1_axis_tready(m1_axis_ipd_tready),
      .m1_axis_tlast (m1_axis_ipd_tlast),      
      .s0_axis_tdata (m0_axis_pcap_tdata),
      .s0_axis_tkeep (m0_axis_pcap_tkeep),
      .s0_axis_tuser (m0_axis_pcap_tuser),
      .s0_axis_tvalid(m0_axis_pcap_tvalid),
      .s0_axis_tready(m0_axis_pcap_tready),
      .s0_axis_tlast (m0_axis_pcap_tlast),
      .s1_axis_tdata (m1_axis_pcap_tdata),
      .s1_axis_tkeep (m1_axis_pcap_tkeep),
      .s1_axis_tuser (m1_axis_pcap_tuser),
      .s1_axis_tvalid(m1_axis_pcap_tvalid),
      .s1_axis_tready(m1_axis_pcap_tready),
      .s1_axis_tlast (m1_axis_pcap_tlast),
      .s_axi_awaddr(S3_AXI_AWADDR),
      .s_axi_awvalid(S3_AXI_AWVALID),
      .s_axi_wdata(S3_AXI_WDATA),
      .s_axi_wstrb(S3_AXI_WSTRB),
      .s_axi_wvalid(S3_AXI_WVALID),
      .s_axi_bready(S3_AXI_BREADY),
      .s_axi_araddr(S3_AXI_ARADDR),
      .s_axi_arvalid(S3_AXI_ARVALID),
      .s_axi_rready(S3_AXI_RREADY),
      .s_axi_arready(S3_AXI_ARREADY),
      .s_axi_rdata(S3_AXI_RDATA),
      .s_axi_rresp(S3_AXI_RRESP),
      .s_axi_rvalid(S3_AXI_RVALID),
      .s_axi_wready(S3_AXI_WREADY),
      .s_axi_bresp(S3_AXI_BRESP),
      .s_axi_bvalid(S3_AXI_BVALID),
      .s_axi_awready(S3_AXI_AWREADY),
      .s_axi_aclk (axi_aclk),
      .s_axi_aresetn(axi_resetn)
    );
  //Rate Limiter
  osnt_rate_limiter_ip  u_osnt_rate_limiter_0  (
      .axis_aclk(axis_aclk),
      .axis_aresetn(axis_resetn),
      .m0_axis_tdata (m_axis_0_tdata),
      .m0_axis_tkeep (m_axis_0_tkeep),
      .m0_axis_tuser (m_axis_0_tuser),
      .m0_axis_tvalid(m_axis_0_tvalid),
      .m0_axis_tready(m_axis_0_tready),
      .m0_axis_tlast (m_axis_0_tlast),
      .m1_axis_tdata (m_axis_1_tdata),
      .m1_axis_tkeep (m_axis_1_tkeep),
      .m1_axis_tuser (m_axis_1_tuser),
      .m1_axis_tvalid(m_axis_1_tvalid),
      .m1_axis_tready(m_axis_1_tready),
      .m1_axis_tlast (m_axis_1_tlast),
      .s0_axis_tdata (m0_axis_ipd_tdata),
      .s0_axis_tkeep (m0_axis_ipd_tkeep),
      .s0_axis_tuser (m0_axis_ipd_tuser),
      .s0_axis_tvalid(m0_axis_ipd_tvalid),
      .s0_axis_tready(m0_axis_ipd_tready),
      .s0_axis_tlast (m0_axis_ipd_tlast),
      .s1_axis_tdata (m1_axis_ipd_tdata),
      .s1_axis_tkeep (m1_axis_ipd_tkeep),
      .s1_axis_tuser (m1_axis_ipd_tuser),
      .s1_axis_tvalid(m1_axis_ipd_tvalid),
      .s1_axis_tready(m1_axis_ipd_tready),
      .s1_axis_tlast (m1_axis_ipd_tlast),
      .s_axi_awaddr(S4_AXI_AWADDR),
      .s_axi_awvalid(S4_AXI_AWVALID),
      .s_axi_wdata(S4_AXI_WDATA),
      .s_axi_wstrb(S4_AXI_WSTRB),
      .s_axi_wvalid(S4_AXI_WVALID),
      .s_axi_bready(S4_AXI_BREADY),
      .s_axi_araddr(S4_AXI_ARADDR),
      .s_axi_arvalid(S4_AXI_ARVALID),
      .s_axi_rready(S4_AXI_RREADY),
      .s_axi_arready(S4_AXI_ARREADY),
      .s_axi_rdata(S4_AXI_RDATA),
      .s_axi_rresp(S4_AXI_RRESP),
      .s_axi_rvalid(S4_AXI_RVALID),
      .s_axi_wready(S4_AXI_WREADY),
      .s_axi_bresp(S4_AXI_BRESP),
      .s_axi_bvalid(S4_AXI_BVALID),
      .s_axi_awready(S4_AXI_AWREADY),
      .s_axi_aclk (axi_aclk),
      .s_axi_aresetn(axi_resetn)
    );

  //----------------------------------------------------------
  // OSNT RX pipeline
  //---------------------------------------------------------
  //Input Arbiter
  input_arbiter_ip  input_arbiter_0 (
      .axis_aclk(axis_aclk), 
      .axis_resetn(axis_resetn), 
      .m_axis_tdata (m_axis_2_tdata), 
      .m_axis_tkeep (m_axis_2_tkeep), 
      .m_axis_tuser (m_axis_2_tuser), 
      .m_axis_tvalid(m_axis_2_tvalid), 
      .m_axis_tready(m_axis_2_tready), 
      .m_axis_tlast (m_axis_2_tlast), 
      .s_axis_0_tdata (s_axis_0_tdata), 
      .s_axis_0_tkeep (s_axis_0_tkeep), 
      .s_axis_0_tuser (s_axis_0_tuser), 
      .s_axis_0_tvalid(s_axis_0_tvalid), 
      .s_axis_0_tready(s_axis_0_tready), 
      .s_axis_0_tlast (s_axis_0_tlast), 
      .s_axis_1_tdata (s_axis_1_tdata), 
      .s_axis_1_tkeep (s_axis_1_tkeep), 
      .s_axis_1_tuser (s_axis_1_tuser), 
      .s_axis_1_tvalid(s_axis_1_tvalid), 
      .s_axis_1_tready(s_axis_1_tready), 
      .s_axis_1_tlast (s_axis_1_tlast), 
      .s_axis_2_tdata (), 
      .s_axis_2_tkeep (), 
      .s_axis_2_tuser (), 
      .s_axis_2_tvalid(), 
      .s_axis_2_tready(), 
      .s_axis_2_tlast (), 
      .S_AXI_AWADDR(S5_AXI_AWADDR), 
      .S_AXI_AWVALID(S5_AXI_AWVALID),
      .S_AXI_WDATA(S5_AXI_WDATA),  
      .S_AXI_WSTRB(S5_AXI_WSTRB),  
      .S_AXI_WVALID(S5_AXI_WVALID), 
      .S_AXI_BREADY(S5_AXI_BREADY), 
      .S_AXI_ARADDR(S5_AXI_ARADDR), 
      .S_AXI_ARVALID(S5_AXI_ARVALID),
      .S_AXI_RREADY(S5_AXI_RREADY), 
      .S_AXI_ARREADY(S5_AXI_ARREADY),
      .S_AXI_RDATA(S5_AXI_RDATA),  
      .S_AXI_RRESP(S5_AXI_RRESP),  
      .S_AXI_RVALID(S5_AXI_RVALID), 
      .S_AXI_WREADY(S5_AXI_WREADY), 
      .S_AXI_BRESP(S5_AXI_BRESP),  
      .S_AXI_BVALID(S5_AXI_BVALID), 
      .S_AXI_AWREADY(S5_AXI_AWREADY),
      .S_AXI_ACLK (axi_aclk), 
      .S_AXI_ARESETN(axi_resetn)
    );
    
endmodule
