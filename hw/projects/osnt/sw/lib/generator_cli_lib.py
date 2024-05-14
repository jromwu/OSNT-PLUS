#
# Copyright (c) 2016-2017 University of Cambridge
# Copyright (c) 2016-2017 Jong Hun Han
# Copyright (c) 2022 Gianni Antichi
# All rights reserved.
#
# This software was developed by University of Cambridge Computer Laboratory
# under the ENDEAVOUR project (grant agreement 644960) as part of
# the European Union's Horizon 2020 research and innovation programme.
#
# @NETFPGA_LICENSE_HEADER_START@
#
# Licensed to NetFPGA Open Systems C.I.C. (NetFPGA) under one or more
# contributor license agreements. See the NOTICE file distributed with this
# work for additional information regarding copyright ownership. NetFPGA
# licenses this file to you under the NetFPGA Hardware-Software License,
# Version 1.0 (the License); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at:
#
# http://www.netfpga-cic.org
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# @NETFPGA_LICENSE_HEADER_END@
################################################################################

import os, argparse, datetime, subprocess
from libaxi import *
from generator import *

#TARGET_BASE_ADDR = "0x79000000" # TO UPDATE (10g_axi_if)

#following: check if needed.
#TIMESTAMP_TBL_OFFSET_ADDRESS = "0x14"
#TIMESTAMP_TBL_OFFSET_WRDATA = "0x04"
#TIMESTAMP_TBL_OFFSET_RDDATA = "0x08"
#TIMESTAMP_TBL_OFFSET_CMD = "0x0C"
#TIMESTAMP_TBL_OFFSET_CONFIG = "0x10"
#TIMESTAMP_TBL_ACCESS_CONFIG = "0x00010130"
#TIMESTAMP_TBL_ACCESS_CMD_WRITE = "0x00000001"
#TIMESTAMP_TBL_ACCESS_CMD_READ = "0x00000011"
#INDI_ACC_STAT_MASK = "0x00000100"
#INDI_ACC_TRIG_MASK = "0x00000001"

class InitGCli:
    def __init__(self):
        self.average_pkt_len = {'nf0':1500, 'nf1':1500}
        #check 47.
        self.average_word_cnt = {'nf0':47, 'nf1':47}
        self.pkts_loaded = {'nf0':0, 'nf1':0}
        self.pcaps = {}
        self.rate_limiters = [None]*2
        self.delays = [None]*2
        #rx position is static, tx does not yet exist
        #rx_pos_addr = ["0x1050", "0x3050", "0x5050", "0x7050"]
        #tx_pos_addr = ["0x1054", "0x3054", "0x5054", "0x7054"]
    
        #self.rx_pos_wr = [None]*2
        #self.tx_pos_wr = [None]*2
        #for i in range(2):
        #    self.rx_pos_wr[i] = rx_pos_addr[i]
        #    self.tx_pos_wr[i] = tx_pos_addr[i] 
        
        for i in range(2):
            iface = 'nf' + str(i)
            self.rate_limiters[i] = OSNTRateLimiter(iface)
            self.delays[i] = OSNTDelay(iface)
    
        self.pcap_engine = OSNTGeneratorPcapEngine()
        self.delay_header_extractor = OSNTDelayHeaderExtractor()
    
        self.delay_header_extractor.set_reset(False)
        self.delay_header_extractor.set_enable(False)

def clear():
    initgcli.pcap_engine.clear()
    print("Cleared pcap replay. Stop ...")

#def if_indi_write(wraddr, wrdata):
#    # give indirect address
#    wraxi(add_hex(TARGET_BASE_ADDR, TIMESTAMP_TBL_OFFSET_ADDRESS), wraddr) # addr @ coloumn
#    # give indirect data
#    wraxi(add_hex(TARGET_BASE_ADDR, TIMESTAMP_TBL_OFFSET_WRDATA), wrdata) # content of word
#    # give indirect command to write
#    wraxi(add_hex(TARGET_BASE_ADDR, TIMESTAMP_TBL_OFFSET_CMD), TIMESTAMP_TBL_ACCESS_CMD_WRITE)
#    # pull transaction status
#    feedback_hexstring = rdaxi(add_hex(TARGET_BASE_ADDR, TIMESTAMP_TBL_OFFSET_CMD))
#    trig = hex(int(feedback_hexstring,16) & int(INDI_ACC_TRIG_MASK,16))
#    while int(trig,16) == int(INDI_ACC_TRIG_MASK,16): # trigger not deasserted, means transaction still in progress
#        feedback_hexstring = rdaxi(add_hex(TARGET_BASE_ADDR, TIMESTAMP_TBL_OFFSET_CMD))
#        trig = hex(int(feedback_hexstring, 16) & int(INDI_ACC_TRIG_MASK, 16))
#    stat = hex(int(feedback_hexstring,16) & int(INDI_ACC_STAT_MASK,16)) 
#    if int(stat,16) == int(INDI_ACC_STAT_MASK,16): # if status bit asserted, means transaction failed
#        print("[!!!] INDIRECT WRITE FAILED...")
#        print(" ")
#    return 0
#
#def if_indi_config():
#    wraxi(add_hex(TARGET_BASE_ADDR, TIMESTAMP_TBL_OFFSET_CONFIG), TIMESTAMP_TBL_ACCESS_CONFIG) # config

def set_load_pcap(mypcaps):
    print("  ")
    print("[CLI: Loading Pcap File..]")    
    for key, value in list(mypcaps.items()):
        print((key, value))
    initgcli.pcaps = mypcaps
    result = initgcli.pcap_engine.load_pcap(initgcli.pcaps)
    print(result)

def set_load_pcap_ts(mypcaps):
    print("  ")
    print("[CLI: Loading Pcap File with Timestamp..]")    
    for key, value in list(mypcaps.items()):
        print((key, value))
    initgcli.pcaps = mypcaps
    result = initgcli.pcap_engine.load_pcap_ts(initgcli.pcaps)
    print(result)

def set_load_pcap_only(pcap_file):
    print("  ")
    print("[CLI: Loading Pcap File only..]")   
    for key, value in list(mypcaps.items()):
        print((key, value))
    result = initgcli.pcap_engine.load_pcap_only(initgcli.pcaps)
    print(result)

#def set_tx_ts(interface, value):
#   print("  ")
#   print("[CLI: Tx Timestamp position setting.. " + "nf" + str(interface) + ", "+ str(value) +"]")     
#   if_indi_write(initgcli.tx_pos_wr[interface], hex(value))
#
#   
#def set_rx_ts(interface, value):
#   print("  ")
#   print("[CLI: Rx Timestamp position setting.. " + "nf" + str(interface) + ", "+ str(value) +"]")     
#   if_indi_write(initgcli.rx_pos_wr[interface], hex(value))

def set_ipg(interface, value):
   print("  ")
   print("[CLI: Inter Packet Gap delay setting... " + "nf" + str(interface) + ", "+ str(value) +"]")     
   initgcli.delays[interface].set_delay(value)
   initgcli.delays[interface].set_enable(True)
   initgcli.delays[interface].set_use_reg(True)

def set_ipg_ts(interface, value):
   print("  ")
   print("[CLI: Inter Packet Gap delay setting with Timestamp... " + "nf" + str(interface) + ", "+ str(value) +"]")     
   initgcli.delays[interface].set_delay(value)
   initgcli.delays[interface].set_enable(True)
   initgcli.delays[interface].set_use_reg(False)

def set_replay_cnt(values):
    print("  ")
    print("[CLI: Packet Replay counter setting ...]")    
    for i in range(2):
        print("(nf" + str(i) +", "+ str(values[i]) +")")
    initgcli.pcap_engine.set_replay_cnt(values)

initgcli = InitGCli()
