#
# Copyright (c) 2015 Noa Zilberman
# Copyright (c) 2021 Yuta Tokusashi
# All rights reserved.
#
# This software was developed by Stanford University and the University of Cambridge Computer Laboratory
# under National Science Foundation under Grant No. CNS-0855268,
# the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
# by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"),
# as part of the DARPA MRC research programme,
# and by the University of Cambridge Computer Laboratory under EPSRC EARL Project
# EP/P025374/1 alongside support from Xilinx Inc.
#
# @NETFPGA_LICENSE_HEADER_START@
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# @NETFPGA_LICENSE_HEADER_END@
#

#######################
# Segments Assignment #
#######################
#M00
set M00_BASEADDR 0x00010000
set M00_HIGHADDR 0x00010FFF
set M00_SIZEADDR 0x1000

#M01
set M01_BASEADDR 0x00020000
set M01_HIGHADDR 0x00020FFF
set M01_SIZEADDR 0x1000

#M02
set M02_BASEADDR 0x00030000
set M02_HIGHADDR 0x00030FFF
set M02_SIZEADDR 0x1000

#M03
set M03_BASEADDR 0x00040000
set M03_HIGHADDR 0x00040FFF
set M03_SIZEADDR 0x1000

#M04
set M04_BASEADDR 0x00050000
set M04_HIGHADDR 0x00050FFF
set M04_SIZEADDR 0x1000

#M05
set M05_BASEADDR 0x00060000
set M05_HIGHADDR 0x00060FFF
set M05_SIZEADDR 0x1000

#M06
set M06_BASEADDR 0x00070000
set M06_HIGHADDR 0x00070FFF
set M06_SIZEADDR 0x1000

#M07
set M07_BASEADDR 0x00080000
set M07_HIGHADDR 0x00080FFF
set M07_SIZEADDR 0x1000

#M08
set M08_BASEADDR 0x00090000
set M08_HIGHADDR 0x00090FFF
set M08_SIZEADDR 0x1000

#M09
set M09_BASEADDR 0x000A0000
set M09_HIGHADDR 0x000A0FFF
set M09_SIZEADDR 0x1000

#######################
# IP_ASSIGNMENT       #
#######################
# Note that physical connectivity must match this mapping
##IDENTIFIER base address and size #set IDENTIFIER_BASEADDR $M00_BASEADDR
#set IDENTIFIER_HIGHADDR $M00_HIGHADDR
#set IDENTIFIER_SIZEADDR $M00_SIZEADDR

#INPUT ARBITER base address and size
set INPUT_ARBITER_BASEADDR $M00_BASEADDR
set INPUT_ARBITER_HIGHADDR $M00_HIGHADDR
set INPUT_ARBITER_SIZEADDR $M00_SIZEADDR

#OUTPUT_QUEUES base address and size
set OUTPUT_QUEUES_BASEADDR $M02_BASEADDR
set OUTPUT_QUEUES_HIGHADDR $M02_HIGHADDR
set OUTPUT_QUEUES_SIZEADDR $M02_SIZEADDR

#OUPUT_PORT_LOOKUP base address and size
set OUTPUT_PORT_LOOKUP_BASEADDR $M01_BASEADDR
set OUTPUT_PORT_LOOKUP_HIGHADDR $M01_HIGHADDR
set OUTPUT_PORT_LOOKUP_SIZEADDR $M01_SIZEADDR

#PKT_CUTTER base address and size
set PKT_CUTTER_BASEADDR $M03_BASEADDR
set PKT_CUTTER_HIGHADDR $M03_HIGHADDR
set PKT_CUTTER_SIZEADDR $M03_SIZEADDR

#EXTRACT_METADATA base address and size
set EXTRACT_METADATA_BASEADDR $M04_BASEADDR
set EXTRACT_METADATA_HIGHADDR $M04_HIGHADDR
set EXTRACT_METADATA_SIZEADDR $M04_SIZEADDR

#PCAP_REPLAY base address and size
set PCAP_REPLAY_BASEADDR $M05_BASEADDR
set PCAP_REPLAY_HIGHADDR $M05_HIGHADDR
set PCAP_REPLAY_SIZEADDR $M05_SIZEADDR

#INTER_PACKET_DELAY_0 base address and size
set INTER_PACKET_DELAY_0_BASEADDR $M06_BASEADDR
set INTER_PACKET_DELAY_0_HIGHADDR $M06_HIGHADDR
set INTER_PACKET_DELAY_0_SIZEADDR $M06_SIZEADDR

#RATE_LIMITER_0 base address and size
set RATE_LIMITER_0_BASEADDR $M07_BASEADDR
set RATE_LIMITER_0_HIGHADDR $M07_HIGHADDR
set RATE_LIMITER_0_SIZEADDR $M07_SIZEADDR
