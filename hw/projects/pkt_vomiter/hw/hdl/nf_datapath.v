`timescale 1ns / 1ps
//-
// Copyright (c) 2015 Noa Zilberman
// Copyright (c) 2021 Yuta Tokusashi
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
    parameter C_M_AXIS_DATA_WIDTH=512,
    parameter C_S_AXIS_DATA_WIDTH=512,
    parameter C_M_AXIS_TUSER_WIDTH=128,
    parameter C_S_AXIS_TUSER_WIDTH=128,
    parameter NUM_QUEUES = 3,

    parameter TIMESTAMP_WIDTH = 64
) (
    //Datapath clock
    input                                     axis_aclk,
    input                                     axis_resetn,
    //Registers clock
    input                                     axi_aclk,
    input                                     axi_resetn,

    // Slave AXI Ports
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
    input [C_S_AXIS_DATA_WIDTH - 1:0]         s_axis_2_tdata,
    input [((C_S_AXIS_DATA_WIDTH / 8)) - 1:0] s_axis_2_tkeep,
    input [C_S_AXIS_TUSER_WIDTH-1:0]          s_axis_2_tuser,
    input                                     s_axis_2_tvalid,
    output                                    s_axis_2_tready,
    input                                     s_axis_2_tlast,


    // Master Stream Ports (interface to TX queues)
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_0_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_0_tkeep,
    output [C_M_AXIS_TUSER_WIDTH-1:0]          m_axis_0_tuser,
    output                                     m_axis_0_tvalid,
    input                                      m_axis_0_tready,
    output                                     m_axis_0_tlast,
    output [C_M_AXIS_DATA_WIDTH - 1:0]         m_axis_1_tdata,
    output [((C_M_AXIS_DATA_WIDTH / 8)) - 1:0] m_axis_1_tkeep,
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
    // localparam DST_PORT_POS = 24;
    // wire [C_S_AXIS_TUSER_WIDTH - 1:0] fifo_in_tuser;
    // assign fifo_in_tuser[DST_PORT_POS-1:0] = s_axis_1_tuser[DST_PORT_POS-1:0];
    // assign fifo_in_tuser[DST_PORT_POS+7:DST_PORT_POS] = 8'h08; // DMA 1 (nf1)
    // assign fifo_in_tuser[C_S_AXIS_TUSER_WIDTH-1:DST_PORT_POS+8] = s_axis_1_tuser[C_S_AXIS_TUSER_WIDTH-1:DST_PORT_POS+8];

    // assign s_axis_1_tready = m_axis_2_tready;
    // assign m_axis_2_tdata = s_axis_1_tdata;
    // assign m_axis_2_tkeep = s_axis_1_tkeep;
    // assign m_axis_2_tuser = fifo_in_tuser;
    // assign m_axis_2_tvalid = s_axis_1_tvalid;
    // assign m_axis_2_tlast = s_axis_1_tlast;
    

    wire [TIMESTAMP_WIDTH-1:0] stamp_counter;

    stamp_counter_ip stamp_counter_0 (
      .ACLK(axis_aclk), 
      .ARESETN(axis_resetn), 
      .STAMP_COUNTER(stamp_counter)
    );

    // TODO: make this a module

    // Pass CMAC 1 RX to DMA but add timestamp
    localparam IN_FIFO_DEPTH = 256;
    localparam TIMESTAMP_POS = 304;
    localparam DST_PORT_POS = 24;

    wire [C_S_AXIS_DATA_WIDTH - 1:0] fifo_in_tdata;
    assign fifo_in_tdata[TIMESTAMP_POS - 1:0] = s_axis_1_tdata[TIMESTAMP_POS - 1:0];
    assign fifo_in_tdata[C_S_AXIS_DATA_WIDTH - 1:TIMESTAMP_POS + TIMESTAMP_WIDTH] = s_axis_1_tdata[C_S_AXIS_DATA_WIDTH - 1:TIMESTAMP_POS + TIMESTAMP_WIDTH];
    genvar i;
    generate for (i = 0; i < TIMESTAMP_WIDTH; i = i + 8) begin : KEEP_GEN
      // flip endianness
      assign fifo_in_tdata[TIMESTAMP_POS + TIMESTAMP_WIDTH - i - 1:TIMESTAMP_POS + TIMESTAMP_WIDTH - i - 8] = stamp_counter[i +: 8];
    end endgenerate;

    wire [C_S_AXIS_TUSER_WIDTH - 1:0] fifo_in_tuser;
    assign fifo_in_tuser[DST_PORT_POS-1:0] = s_axis_1_tuser[DST_PORT_POS-1:0];
    assign fifo_in_tuser[DST_PORT_POS+7:DST_PORT_POS] = 8'h08; // DMA 1 (nf1)
    assign fifo_in_tuser[C_S_AXIS_TUSER_WIDTH-1:DST_PORT_POS+8] = s_axis_1_tuser[C_S_AXIS_TUSER_WIDTH-1:DST_PORT_POS+8];

    assign s_axis_1_tready = m_axis_2_tready;
    assign m_axis_2_tdata = fifo_in_tdata;
    assign m_axis_2_tkeep = s_axis_1_tkeep;
    assign m_axis_2_tuser = fifo_in_tuser;
    assign m_axis_2_tvalid = s_axis_1_tvalid;
    assign m_axis_2_tlast = s_axis_1_tlast;


//////////////////////////////////////////////////////

    // wire [TIMESTAMP_WIDTH:0] stamp_counter;

    // stamp_counter_ip stamp_counter_0 (
    //   .ACLK(axis_aclk), 
    //   .ARESETN(axis_resetn), 
    //   .STAMP_COUNTER(stamp_counter)
    // );

    // // Pass CMAC 1 RX to DMA but add timestamp
    // localparam IN_FIFO_DEPTH = 256;
    // localparam TIMESTAMP_ADDR = 176;
    // localparam DST_PORT_POS = 24;

    // wire [C_S_AXIS_DATA_WIDTH - 1:0] fifo_in_tdata;
    // wire [C_S_AXIS_TUSER_WIDTH - 1:0] fifo_in_tuser;
    // wire [C_S_AXIS_DATA_WIDTH / 8 - 1:0] fifo_in_tkeep;
    // wire fifo_in_tlast, fifo_in_tvalid;

    // wire fifo_empty, fifo_nearly_full, fifo_rden;


    // packet_vomiter_1_ip packet_vomiter_2 (
    //   .axis_aclk(axis_aclk), 
    //   .axis_resetn(axis_resetn), 
    //   .m_axis_tdata (fifo_in_tdata), 
    //   .m_axis_tkeep (fifo_in_tkeep), 
    //   .m_axis_tuser (fifo_in_tuser), 
    //   .m_axis_tvalid(fifo_in_tvalid), 
    //   .m_axis_tready(~fifo_nearly_full), 
    //   .m_axis_tlast (fifo_in_tlast), 
    //   .S_AXI_AWADDR(S2_AXI_AWADDR), 
    //   .S_AXI_AWVALID(S2_AXI_AWVALID),
    //   .S_AXI_WDATA(S2_AXI_WDATA),  
    //   .S_AXI_WSTRB(S2_AXI_WSTRB),  
    //   .S_AXI_WVALID(S2_AXI_WVALID), 
    //   .S_AXI_BREADY(S2_AXI_BREADY), 
    //   .S_AXI_ARADDR(S2_AXI_ARADDR), 
    //   .S_AXI_ARVALID(S2_AXI_ARVALID),
    //   .S_AXI_RREADY(S2_AXI_RREADY), 
    //   .S_AXI_ARREADY(S2_AXI_ARREADY),
    //   .S_AXI_RDATA(S2_AXI_RDATA),  
    //   .S_AXI_RRESP(S2_AXI_RRESP),  
    //   .S_AXI_RVALID(S2_AXI_RVALID), 
    //   .S_AXI_WREADY(S2_AXI_WREADY), 
    //   .S_AXI_BRESP(S2_AXI_BRESP),  
    //   .S_AXI_BVALID(S2_AXI_BVALID), 
    //   .S_AXI_AWREADY(S2_AXI_AWREADY),
    //   .S_AXI_ACLK (axi_aclk), 
    //   .S_AXI_ARESETN(axi_resetn)
    // );
    

    // xpm_fifo_sync #(
    //   .FIFO_MEMORY_TYPE     ("auto"),
    //   .ECC_MODE             ("no_ecc"),
    //   .FIFO_WRITE_DEPTH     (IN_FIFO_DEPTH),
    //   .WRITE_DATA_WIDTH     (1+1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH),
    //   .WR_DATA_COUNT_WIDTH  (1),
    //   .PROG_FULL_THRESH     (IN_FIFO_DEPTH - 12),
    //   .FULL_RESET_VALUE     (0),
    //   .USE_ADV_FEATURES     ("0707"),
    //   .READ_MODE            ("fwft"),
    //   .FIFO_READ_LATENCY    (0),
    //   .READ_DATA_WIDTH      (1+1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH),
    //   .RD_DATA_COUNT_WIDTH  (1),
    //   .PROG_EMPTY_THRESH    (10),
    //   .DOUT_RESET_VALUE     ("0"),
    //   .WAKEUP_TIME          (0)
    // ) u_xpm_fifo_sync (
    //   // Common module ports
    //   .sleep           (),
    //   .rst             (~axis_resetn),
      
    //   // Write Domain ports
    //   .wr_clk          (axis_aclk),
    //   .wr_en           (s_axis_1_tvalid),
    //   .din             ({fifo_in_tvalid, fifo_in_tlast, fifo_in_tuser, fifo_in_tkeep, fifo_in_tdata}),
    //   .full            (),
    //   .prog_full       (fifo_nearly_full),
    //   .wr_data_count   (),
    //   .overflow        (),
    //   .wr_rst_busy     (),
    //   .almost_full     (),
    //   .wr_ack          (),
      
    //   // Read Domain ports
    //   .rd_en           (m_axis_2_tready & ~fifo_empty),
    //   .dout            ({m_axis_2_tvalid, m_axis_2_tlast, m_axis_2_tuser, m_axis_2_tkeep, m_axis_2_tdata}),
    //   .empty           (fifo_empty),
    //   .prog_empty      (),
    //   .rd_data_count   (),
    //   .underflow       (),
    //   .rd_rst_busy     (),
    //   .almost_empty    (),
    //   .data_valid      (),
      
    //   // ECC Related ports
    //   .injectsbiterr   (),
    //   .injectdbiterr   (),
    //   .sbiterr         (),
    //   .dbiterr         () 
    // );
    // // we can stop overflowing the fifo by negating tready, but doing so would impact the timestamp accuracy
    // // what is best is to mark packets when the fifo is nearly full, but let's not bother with that for now 
    // assign s_axis_1_tready = 1;
    // // in this case, we will just drop packets when the fifo is full
    // // assign s_axis_1_tready = 1;
    

    // wire [TIMESTAMP_WIDTH:0] stamp_counter;

    // stamp_counter_ip stamp_counter_0 (
    //   .ACLK(axis_aclk), 
    //   .ARESETN(axis_resetn), 
    //   .STAMP_COUNTER(stamp_counter)
    // );

    // // Pass CMAC 1 RX to DMA but add timestamp
    // localparam IN_FIFO_DEPTH = 256;
    // localparam TIMESTAMP_ADDR = 176;
    // localparam DST_PORT_POS = 24;

    // wire [C_S_AXIS_DATA_WIDTH - 1:0] fifo_in_tdata;
    // assign fifo_in_tdata[TIMESTAMP_ADDR - 1:0] = s_axis_1_tdata[TIMESTAMP_ADDR - 1:0];
    // assign fifo_in_tdata[C_S_AXIS_DATA_WIDTH - 1:TIMESTAMP_ADDR + TIMESTAMP_WIDTH] = s_axis_1_tdata[C_S_AXIS_DATA_WIDTH - 1:TIMESTAMP_ADDR + TIMESTAMP_WIDTH];
    // genvar i;
    // generate for (i = 0; i < TIMESTAMP_WIDTH; i = i + 8) begin : KEEP_GEN
    //   // flip endianness
    //   assign fifo_in_tdata[TIMESTAMP_ADDR + TIMESTAMP_WIDTH - i:TIMESTAMP_ADDR + TIMESTAMP_WIDTH - i - 8] = stamp_counter[i +: 8];
    // end endgenerate;

    // wire [C_S_AXIS_TUSER_WIDTH - 1:0] fifo_in_tuser;
    // assign fifo_in_tuser[DST_PORT_POS-1:0] = s_axis_1_tuser[DST_PORT_POS-1:0];
    // assign fifo_in_tuser[DST_PORT_POS+7:DST_PORT_POS] = 8'h08; // DMA 1 (nf1)
    // assign fifo_in_tuser[C_S_AXIS_TUSER_WIDTH-1:DST_PORT_POS+8] = s_axis_1_tuser[C_S_AXIS_TUSER_WIDTH-1:DST_PORT_POS+8];

    // wire fifo_empty, fifo_nearly_full, fifo_rden;

    // xpm_fifo_sync #(
    //   .FIFO_MEMORY_TYPE     ("auto"),
    //   .ECC_MODE             ("no_ecc"),
    //   .FIFO_WRITE_DEPTH     (IN_FIFO_DEPTH),
    //   .WRITE_DATA_WIDTH     (1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH),
    //   .WR_DATA_COUNT_WIDTH  (1),
    //   .PROG_FULL_THRESH     (IN_FIFO_DEPTH - 12),
    //   .FULL_RESET_VALUE     (0),
    //   .USE_ADV_FEATURES     ("0707"),
    //   .READ_MODE            ("fwft"),
    //   .FIFO_READ_LATENCY    (0),
    //   .READ_DATA_WIDTH      (1+C_M_AXIS_TUSER_WIDTH+(C_M_AXIS_DATA_WIDTH/8)+C_M_AXIS_DATA_WIDTH),
    //   .RD_DATA_COUNT_WIDTH  (1),
    //   .PROG_EMPTY_THRESH    (10),
    //   .DOUT_RESET_VALUE     ("0"),
    //   .WAKEUP_TIME          (0)
    // ) u_xpm_fifo_sync (
    //   // Common module ports
    //   .sleep           (),
    //   .rst             (~axis_resetn),
      
    //   // Write Domain ports
    //   .wr_clk          (axis_aclk),
    //   .wr_en           (s_axis_1_tvalid),
    //   .din             ({s_axis_1_tlast, fifo_in_tuser, s_axis_1_tkeep, fifo_in_tdata}),
    //   .full            (),
    //   .prog_full       (fifo_nearly_full),
    //   .wr_data_count   (),
    //   .overflow        (),
    //   .wr_rst_busy     (),
    //   .almost_full     (),
    //   .wr_ack          (),
      
    //   // Read Domain ports
    //   .rd_en           (fifo_rden),
    //   .dout            ({m_axis_2_tlast, m_axis_2_tuser, m_axis_2_tkeep, m_axis_2_tdata}),
    //   .empty           (fifo_empty),
    //   .prog_empty      (),
    //   .rd_data_count   (),
    //   .underflow       (),
    //   .rd_rst_busy     (),
    //   .almost_empty    (),
    //   .data_valid      (),
      
    //   // ECC Related ports
    //   .injectsbiterr   (),
    //   .injectdbiterr   (),
    //   .sbiterr         (),
    //   .dbiterr         () 
    // );
    // assign fifo_rden = m_axis_2_tready & ~fifo_empty;
    // assign m_axis_2_tvalid = fifo_rden;
    // // we can stop overflowing the fifo by negating tready, but doing so would impact the timestamp accuracy
    // // what is best is to mark packets when the fifo is nearly full, but let's not bother with that for now 
    // // assign s_axis_1_tready = ~fifo_nearly_full;
    // // in this case, we will just drop packets when the fifo is full
    // assign s_axis_1_tready = 1;
    

    // Accept RX from CMAC and DMA but do nothing with them
    assign s_axis_0_tready = 1;
    assign s_axis_2_tready = 1;
    
    packet_vomiter_0_ip packet_vomiter_0 (
      .axis_aclk(axis_aclk), 
      .axis_resetn(axis_resetn), 
      .m_axis_tdata (m_axis_0_tdata), 
      .m_axis_tkeep (m_axis_0_tkeep), 
      .m_axis_tuser (m_axis_0_tuser), 
      .m_axis_tvalid(m_axis_0_tvalid), 
      .m_axis_tready(m_axis_0_tready), 
      .m_axis_tlast (m_axis_0_tlast), 
      .stamp_counter(stamp_counter),
      .S_AXI_AWADDR(S0_AXI_AWADDR), 
      .S_AXI_AWVALID(S0_AXI_AWVALID),
      .S_AXI_WDATA(S0_AXI_WDATA),  
      .S_AXI_WSTRB(S0_AXI_WSTRB),  
      .S_AXI_WVALID(S0_AXI_WVALID), 
      .S_AXI_BREADY(S0_AXI_BREADY), 
      .S_AXI_ARADDR(S0_AXI_ARADDR), 
      .S_AXI_ARVALID(S0_AXI_ARVALID),
      .S_AXI_RREADY(S0_AXI_RREADY), 
      .S_AXI_ARREADY(S0_AXI_ARREADY),
      .S_AXI_RDATA(S0_AXI_RDATA),  
      .S_AXI_RRESP(S0_AXI_RRESP),  
      .S_AXI_RVALID(S0_AXI_RVALID), 
      .S_AXI_WREADY(S0_AXI_WREADY), 
      .S_AXI_BRESP(S0_AXI_BRESP),  
      .S_AXI_BVALID(S0_AXI_BVALID), 
      .S_AXI_AWREADY(S0_AXI_AWREADY),
      .S_AXI_ACLK (axi_aclk), 
      .S_AXI_ARESETN(axi_resetn)
    );

    packet_vomiter_2_ip packet_vomiter_1 (
      .axis_aclk(axis_aclk), 
      .axis_resetn(axis_resetn), 
      .m_axis_tdata (m_axis_1_tdata), 
      .m_axis_tkeep (m_axis_1_tkeep), 
      .m_axis_tuser (m_axis_1_tuser), 
      .m_axis_tvalid(m_axis_1_tvalid), 
      .m_axis_tready(m_axis_1_tready), 
      .m_axis_tlast (m_axis_1_tlast), 
      .stamp_counter(stamp_counter),
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

    // packet_vomiter_1_ip packet_vomiter_2 (
    //   .axis_aclk(axis_aclk), 
    //   .axis_resetn(axis_resetn), 
    //   .m_axis_tdata (m_axis_2_tdata), 
    //   .m_axis_tkeep (m_axis_2_tkeep), 
    //   .m_axis_tuser (m_axis_2_tuser), 
    //   .m_axis_tvalid(m_axis_2_tvalid), 
    //   .m_axis_tready(m_axis_2_tready), 
    //   .m_axis_tlast (m_axis_2_tlast), 
    //   .S_AXI_AWADDR(S2_AXI_AWADDR), 
    //   .S_AXI_AWVALID(S2_AXI_AWVALID),
    //   .S_AXI_WDATA(S2_AXI_WDATA),  
    //   .S_AXI_WSTRB(S2_AXI_WSTRB),  
    //   .S_AXI_WVALID(S2_AXI_WVALID), 
    //   .S_AXI_BREADY(S2_AXI_BREADY), 
    //   .S_AXI_ARADDR(S2_AXI_ARADDR), 
    //   .S_AXI_ARVALID(S2_AXI_ARVALID),
    //   .S_AXI_RREADY(S2_AXI_RREADY), 
    //   .S_AXI_ARREADY(S2_AXI_ARREADY),
    //   .S_AXI_RDATA(S2_AXI_RDATA),  
    //   .S_AXI_RRESP(S2_AXI_RRESP),  
    //   .S_AXI_RVALID(S2_AXI_RVALID), 
    //   .S_AXI_WREADY(S2_AXI_WREADY), 
    //   .S_AXI_BRESP(S2_AXI_BRESP),  
    //   .S_AXI_BVALID(S2_AXI_BVALID), 
    //   .S_AXI_AWREADY(S2_AXI_AWREADY),
    //   .S_AXI_ACLK (axi_aclk), 
    //   .S_AXI_ARESETN(axi_resetn)
    // );
    
endmodule
