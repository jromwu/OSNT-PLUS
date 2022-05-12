//
// Copyright (c) 2016 University of Cambridge
// Copyright (c) 2016 Jong Hun Han
// Copyright (c) 2022 Gianni Antichi
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
//

`timescale 1ns/1ps

module osnt_bram 
#(
	parameter	ADDR_WIDTH		= 16,
	parameter	DATA_WIDTH		= 736 //32 bit aligned. (TDATA=512 + TUSER=128 + TKEEP=64 + TVALID=1 + TLAST=1: tot = 706)
)
(
   input    	[ADDR_WIDTH-1:0]	bram_addr,
   input                         	bram_clk,
   input    	[DATA_WIDTH-1:0]     	bram_wrdata,
   output reg	[DATA_WIDTH-1:0]     	bram_rddata,
   input                         	bram_en,
   input                         	bram_rst,
   input   				bram_we
);

(* ram_style = "ultra" *) reg   [DATA_WIDTH-1:0]    bootmem[0:(2**ADDR_WIDTH)-1];

integer i;

always @(posedge bram_clk) begin
   if (bram_rst) begin
   	for (i=0; i<2**ADDR_WIDTH; i=i+1)
	     bootmem[i] <= {DATA_WIDTH{1'b0}};
   end     
   else if (bram_en) begin
   	bram_rddata  <= bootmem[bram_addr];
      		if (bram_we) 
      			bootmem[bram_addr] <= bram_wrdata;
   end
end

endmodule
