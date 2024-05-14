//-
// Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
//                          Junior University
// Copyright (C) 2010, 2011 Adam Covington
// Copyright (C) 2015 Noa Zilberman
// Copyright (C) 2021 Yuta Tokusashi
// All rights reserved.
//
// This software was developed by
// Stanford University and the University of Cambridge Computer Laboratory
// under National Science Foundation under Grant No. CNS-0855268,
// the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
// by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
// as part of the DARPA MRC research programme,
// and by the University of Cambridge Computer Laboratory under EPSRC EARL Project
// EP/P025374/1 alongside support from Xilinx Inc.
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
/*******************************************************************************
 *  File:
 *        input_arbiter.v
 *
 *  Library:
 *        hw/std/cores/input_arbiter
 *
 *  Module:
 *        input_arbiter
 *
 *  Author:
 *        Adam Covington
 *        Modified by Noa Zilberman
 * 		
 *  Description:
 *        Round Robin arbiter (N inputs to 1 output)
 *        Inputs have a parameterizable width
 *
 */

`timescale 1ns/1ns
`include "packet_vomiter_cpu_regs_defines.v"

module packet_vomiter
#(
    // Master AXI Stream Data Width
    parameter C_M_AXIS_DATA_WIDTH=512,
    parameter C_S_AXIS_DATA_WIDTH=512,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128,

    // Port position in tuser
    parameter DST_PORT_POS=24,

    parameter DST_PORT_VALUE=8'h00,
    parameter ETH_ADDR=48'h000000000000,
    
    // AXI Registers Data Width
    parameter C_S_AXI_DATA_WIDTH    = 32,          
    parameter C_S_AXI_ADDR_WIDTH    = 12,          
    parameter C_BASEADDR            = 32'h00000000
 
)
(
    // Part 1: System side signals
    // Global Ports
    input axis_aclk,
    input axis_resetn,

    // Master Stream Ports (interface to data path)
    output [C_M_AXIS_DATA_WIDTH - 1:0] m_axis_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0] m_axis_tuser,
    output m_axis_tvalid,
    input  m_axis_tready,
    output m_axis_tlast,

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
    output                                    S_AXI_AWREADY

);
  wire     [C_M_AXIS_DATA_WIDTH - 1:0] packet_content;
  reg      [C_M_AXIS_TUSER_WIDTH - 1:0] tuser_content;
  reg      [31:0] time_counter;
  reg      [31:0] packet_counter;
  
  reg      [`REG_ID_BITS]    id_reg;
  reg      [`REG_VERSION_BITS]    version_reg;
  wire     [`REG_RESET_BITS]    reset_reg;
  wire     [`REG_ENABLE_BITS]    enable_reg;
  reg      [`REG_PKTIN_BITS]    pktin_reg;
  wire                             pktin_reg_clear;
  reg      [`REG_PKTOUT_BITS]    pktout_reg;
  wire                             pktout_reg_clear;
  reg      [`REG_DEBUG_BITS]    ip2cpu_debug_reg;
  wire     [`REG_DEBUG_BITS]    cpu2ip_debug_reg;

  wire enable = enable_reg[0]; // normal packets are 60 bytes
  wire full_pkt = enable_reg[1]; // 64 bytes
  wire short_pkt = enable_reg[2]; // 56 bytes, does not work

  assign packet_content = {64'h0001020304050607, {(C_M_AXIS_DATA_WIDTH - 256 - 64 - 32 - 32){1'b0}}, 144'h0e0f101112131415161718191a1b1c1d1e1f, 
                            time_counter[7:0], time_counter[15:8], time_counter[23:16], time_counter[31:24],
                            packet_counter[7:0], packet_counter[15:8], packet_counter[23:16], packet_counter[31:24],
                            16'h0d0c, ETH_ADDR, 48'hffffffffffff};
  assign m_axis_tvalid = (m_axis_tready && enable) ? 1 : 0;
  assign m_axis_tlast = (m_axis_tready && enable) ? 1 : 0;
  assign m_axis_tdata = (m_axis_tready && enable) ? packet_content : {C_M_AXIS_DATA_WIDTH{1'b0}};
  assign m_axis_tkeep = (m_axis_tready && enable) ? (full_pkt ? {(C_M_AXIS_DATA_WIDTH / 8){1'b1}} : 
                        (short_pkt ? {8'h00, {(C_M_AXIS_DATA_WIDTH / 8 - 8){1'b1}}} : 
                        {4'b0000, {(C_M_AXIS_DATA_WIDTH / 8 - 4){1'b1}}})) : 
                        {(C_M_AXIS_DATA_WIDTH / 8){1'b0}};
  assign m_axis_tuser = tuser_content;

  always @(*) begin
    if (m_axis_tready && enable) begin
      tuser_content = {C_M_AXIS_TUSER_WIDTH{1'b0}};
      tuser_content[15:0] = full_pkt ? 16'h0040 : (short_pkt ? 16'h0038 : 16'h003c); // packet length
      tuser_content[DST_PORT_POS+7:DST_PORT_POS] = DST_PORT_VALUE;
    end
	end
  // assign m_axis_tuser = full_pkt ? {{(C_M_AXIS_TUSER_WIDTH - 16){1'b0}}, 16'h0040} : (short_pkt ? {{(C_M_AXIS_TUSER_WIDTH - 16){1'b0}}, 16'h0038} : {{(C_M_AXIS_TUSER_WIDTH - 16){1'b0}}, 16'h003c});

  wire clear_counters;
  wire reset_registers;
  wire unused;

  //a counter used to measure time
  always @(posedge axis_aclk)
    if (~resetn_sync | clear_counters) begin
      time_counter <= #1 32'h0;
      packet_counter <= #1 32'h0;
    end
    else begin
      time_counter <= #1 (time_counter==32'hFFFFFFFF) ? 32'h0 : time_counter + 32'h1;
      packet_counter <= #1 (m_axis_tready && enable) ? ((packet_counter==32'hFFFFFFFF) ? 32'h0 : packet_counter + 32'h1) : packet_counter;
    end

  //Registers section
  packet_vomiter_cpu_regs 
  #(
    .C_S_AXI_DATA_WIDTH (C_S_AXI_DATA_WIDTH),
    .C_S_AXI_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH),
    .C_BASE_ADDRESS    (C_BASEADDR)
  ) packet_vomiter_cpu_regs_inst
  (   
    // General ports
     .clk                    (axis_aclk),
     .resetn                 (axis_resetn),
    // AXI Lite ports
     .S_AXI_ACLK             (S_AXI_ACLK),
     .S_AXI_ARESETN          (S_AXI_ARESETN),
     .S_AXI_AWADDR           (S_AXI_AWADDR),
     .S_AXI_AWVALID          (S_AXI_AWVALID),
     .S_AXI_WDATA            (S_AXI_WDATA),
     .S_AXI_WSTRB            (S_AXI_WSTRB),
     .S_AXI_WVALID           (S_AXI_WVALID),
     .S_AXI_BREADY           (S_AXI_BREADY),
     .S_AXI_ARADDR           (S_AXI_ARADDR),
     .S_AXI_ARVALID          (S_AXI_ARVALID),
     .S_AXI_RREADY           (S_AXI_RREADY),
     .S_AXI_ARREADY          (S_AXI_ARREADY),
     .S_AXI_RDATA            (S_AXI_RDATA),
     .S_AXI_RRESP            (S_AXI_RRESP),
     .S_AXI_RVALID           (S_AXI_RVALID),
     .S_AXI_WREADY           (S_AXI_WREADY),
     .S_AXI_BRESP            (S_AXI_BRESP),
     .S_AXI_BVALID           (S_AXI_BVALID),
     .S_AXI_AWREADY          (S_AXI_AWREADY),

    // Register ports
    .id_reg          (id_reg),
    .version_reg          (version_reg),
    .reset_reg          (reset_reg),
    .enable_reg          (enable_reg),
    .pktin_reg          (pktin_reg),
    .pktin_reg_clear    (pktin_reg_clear),
    .pktout_reg          (pktout_reg),
    .pktout_reg_clear    (pktout_reg_clear),
    .ip2cpu_debug_reg          (ip2cpu_debug_reg),
    .cpu2ip_debug_reg          (cpu2ip_debug_reg),
    // Global Registers - user can select if to use
    .cpu_resetn_soft(),//software reset, after cpu module
    .resetn_soft    (),//software reset to cpu module (from central reset management)
    .resetn_sync    (resetn_sync)//synchronized reset, use for better timing
  );

  assign clear_counters = reset_reg[0];
  assign reset_registers = reset_reg[4];

  always @(posedge axis_aclk)
    if (~resetn_sync | reset_registers) begin
      id_reg <= #1    `REG_ID_DEFAULT;
      version_reg <= #1    `REG_VERSION_DEFAULT;
      pktin_reg <= #1    `REG_PKTIN_DEFAULT;
      pktout_reg <= #1    `REG_PKTOUT_DEFAULT;
      ip2cpu_debug_reg <= #1    `REG_DEBUG_DEFAULT;
    end
    else begin
      id_reg <= #1 `REG_ID_DEFAULT;
      version_reg <= #1 `REG_VERSION_DEFAULT;
      // pktin_reg[`REG_PKTIN_WIDTH -2: 0] <= #1  clear_counters | pktin_reg_clear ? 'h0  : pktin_reg[`REG_PKTIN_WIDTH-2:0] + (s_axis_0_tlast && s_axis_0_tvalid && s_axis_0_tready ) + (s_axis_1_tlast && s_axis_1_tvalid && s_axis_1_tready) + (s_axis_2_tlast && s_axis_2_tvalid && s_axis_2_tready);
      //   pktin_reg[`REG_PKTIN_WIDTH-1] <= #1 clear_counters | pktin_reg_clear ? 1'h0 : pktin_reg_clear ? 'h0  : pktin_reg[`REG_PKTIN_WIDTH-2:0] + pktin_reg[`REG_PKTIN_WIDTH-2:0] + (s_axis_0_tlast && s_axis_0_tvalid && s_axis_0_tready ) + (s_axis_1_tlast && s_axis_1_tvalid && s_axis_1_tready) + (s_axis_2_tlast && s_axis_2_tvalid && s_axis_2_tready) > {(`REG_PKTIN_WIDTH-1){1'b1}} ? 1'b1 : pktin_reg[`REG_PKTIN_WIDTH-1];
                                                                 
      // pktout_reg [`REG_PKTOUT_WIDTH-2:0]<= #1  clear_counters | pktout_reg_clear ? 'h0  : pktout_reg [`REG_PKTOUT_WIDTH-2:0] + (m_axis_tvalid && m_axis_tlast && m_axis_tready ) ;
      //   pktout_reg [`REG_PKTOUT_WIDTH-1]<= #1  clear_counters | pktout_reg_clear ? 'h0  : pktout_reg [`REG_PKTOUT_WIDTH-2:0] + (m_axis_tvalid && m_axis_tlast && m_axis_tready) > {(`REG_PKTOUT_WIDTH-1){1'b1}} ?  1'b1 : pktout_reg [`REG_PKTOUT_WIDTH-1];
      ip2cpu_debug_reg <= #1 `REG_DEBUG_DEFAULT+cpu2ip_debug_reg;
    end



endmodule
