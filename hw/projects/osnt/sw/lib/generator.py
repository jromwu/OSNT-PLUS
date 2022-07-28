#
# Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
# Junior University
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
#  Author:
#        Yilong Geng
#
#  Description:
#        Code to operate the OSNT Generator

import os, sys, binascii
from libaxi import *
from time import sleep
from scapy import *
from scapy.all import *
from math import ceil
from subprocess import Popen, PIPE

#TO ADJUST BASED ON HW:
DATAPATH_FREQUENCY = 250000000

PCAP_ENGINE_BASE_ADDR = "0x12000"

INTER_PKT_DELAY_BASE_ADDR = {"ens1f0" : "0x13000",
                             "ens1f1" : "0x13030"}

RATE_LIMITER_BASE_ADDR = {"ens1f0" : "0x14000",
                          "ens1f1" : "0x14024"}

DELAY_HEADER_EXTRACTOR_BASE_ADDR = "0x10000"


TS_SIGNATURE = '\xde\xad\xbe\xef\x00\x00\x00\x00'

class DelayField(LongField):

    def __init__(self, name, default):
        LongField.__init__(self, name, default)

    def i2m(self, pkt, x):
        x = '{0:016x}'.format(x)
        x = x.decode('hex')
        x = x[::-1]
        x = x + ('00'*(32-8)).decode('hex')
        return x

    def m2i(self, pkt, x):
        x = x[:8]
        x = x[::-1]
        x = x.encode('hex')
        return int(x, 16)

    def addfield(self, pkt, s, val):
        return s+self.i2m(pkt, val)

    def getfield(self, pkt, s):
        return s[32:], self.m2i(pkt, s[:32])

class DelayHeader(Packet):
    fields_desc = [
          DelayField("delay", 0)
          ]

class OSNTDelayHeaderExtractor:

    def __init__(self):
        self.module_base_addr = DELAY_HEADER_EXTRACTOR_BASE_ADDR

        self.reset_reg_offset = "0x0"
        self.enable_reg_offset = "0x4"

        self.enable = False
        self.reset = False

        self.get_enable()
        self.get_reset()

    def get_status(self):
        return 'OSNTDelayHeaderExtractor: Enable: '+str(self.enable)+' Reset: '+str(self.reset)

    def get_reset(self):
        value = rdaxi(self.reg_addr(self.reset_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.reset = False
        else:
            self.reset = True

    #Reset the module. reset is boolean.
    def set_reset(self, reset):
        if(reset):
            value = 1
        else:
            value = 0

        wraxi(self.reg_addr(self.reset_reg_offset), hex(value))
        self.get_reset()

    def get_enable(self):
        value = rdaxi(self.reg_addr(self.enable_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.enable = False
        else:
            self.enable = True

    def set_enable(self, enable):
        if enable:
            value = 1
        else:
            value = 0
        wraxi(self.reg_addr(self.enable_reg_offset), hex(value))
        self.get_enable()

    def reg_addr(self, offset):
        return add_hex(self.module_base_addr, offset)

class OSNTGeneratorPcapEngine:

    def __init__(self):

        self.reset_reg_offset = "0x0"
        self.begin_replay_reg_offset = "0x4" # simultaneously triggers 2 tx to generate
        self.replay_cnt_reg_offsets = ["0x0C", "0x10"]

        # use axi.get_base_addr for better extensibility
        self.module_base_addr = PCAP_ENGINE_BASE_ADDR

        self.reset = False
        self.begin_replay = False
        self.replay_cnt = [0, 0]
        
        self.get_reset()
        self.get_begin_replay()
        self.get_replay_cnt()
        
    def get_reset(self):
        value = rdaxi(self.reg_addr(self.reset_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.reset = False
        else:
            self.reset = True

    #Reset the module. reset is boolean.
    def set_reset(self, reset):

        if(reset):
            value = 1
        else:
            value = 0

        wraxi(self.reg_addr(self.reset_reg_offset), hex(value))
        self.get_reset()

    def clear(self):
        # reset
        self.set_reset(True)

        self.begin_replay = False
        self.replay_cnt = [0, 0]

        self.set_begin_replay()
        self.set_replay_cnt()

        self.set_reset(False)

    def load_pcap_only(self, pcaps):
        # reset
        self.set_reset(True)
        sleep(0.1)
        # load packets
        for iface in pcaps:
            pkt = rdpcap(pcaps[iface])
            sendp(pkt, iface=iface, verbose=False)

            sleep(1)
            if iface == 'ens1f0':
                print(iface)
                wraxi("0x1202C", 0x1)
                wraxi("0x1202C", 0x0)
            if iface == 'ens1f1':
                print(iface)
                wraxi("0x12030", 0x1)
                wraxi("0x12030", 0x0)


    def load_pcap(self, pcaps):
        # reset
        self.set_reset(True)

        # read packets in
        pkts = {}
        pkt_time = {}
        self.begin_replay = False
        self.set_begin_replay()
        self.set_reset(False)

        pkts_loaded = {}
        for i in range(2):
            iface = 'ens1f'+str(i)
            if ('ens1f'+str(i)) in pcaps:
                self.begin_replay = True
                pkts.update({'ens1f'+str(i): rdpcap(pcaps['ens1f'+str(i)])})
                pkts_loaded[iface] = 0
                for pkt in pkts['ens1f'+str(i)]:
                    pkts_loaded[iface] = pkts_loaded[iface] + 1

                pkt_time['ens1f'+str(i)] = [pkt.time for pkt in pkts['ens1f'+str(i)]]

        average_pkt_len = {}
        average_word_cnt = {}

        for iface in pkts:
            average_pkt_len[iface] = 0
            average_word_cnt[iface] = 0
            s = conf.L2socket(iface = iface)
            for i in range(min(len(pkts[iface]), pkts_loaded[iface])):
                pkt = pkts[iface][i]
                average_pkt_len[iface] = average_pkt_len[iface] + len(pkt)
                average_word_cnt[iface] = average_word_cnt[iface] + ceil(len(pkt)/64.0)
                s.send(pkt)

            average_pkt_len[iface] = float(average_pkt_len[iface])/len(pkts[iface])
            average_word_cnt[iface] = float(average_word_cnt[iface])/len(pkts[iface])
        
            sleep(1)
            if iface == 'ens1f0':
                wraxi("0x1202C", 0x1)
                sleep(0.5)
                wraxi("0x1202C", 0x0)
            if iface == 'ens1f1':
                wraxi("0x12030", 0x1)
                sleep(0.5)
                wraxi("0x12030", 0x0)

        return {'average_pkt_len':average_pkt_len, 'average_word_cnt':average_word_cnt, 'pkts_loaded':pkts_loaded}

    def load_pcap_ts(self, pcaps):
       # reset
        self.set_reset(True)

        # read packets in
        pkts = {}
        pkt_time = {}
        self.begin_replay = False

        self.set_begin_replay()

        self.set_reset(False)

        pkts_loaded = {}
        for i in range(2):
            iface = 'ens1f'+str(i)
            if ('ens1f'+str(i)) in pcaps:
                self.begin_replay = True
                pkts.update({'ens1f'+str(i): rdpcap(pcaps['ens1f'+str(i)])})
                pkts_loaded[iface] = 0
                for pkt in pkts['ens1f'+str(i)]:
                    pkts_loaded[iface] = pkts_loaded[iface] + 1

                pkt_time['ens1f'+str(i)] = [pkt.time for pkt in pkts['ens1f'+str(i)]]

        average_pkt_len = {}
        average_word_cnt = {}
        pkt_time_diff = {} 

        for i in range(2):
            iface = 'ens1f'+str(i)
            if ('ens1f'+str(i)) in pkt_time:
                temp_pkt_time_0 = pkt_time[iface]
                temp_pkt_time_1 = list(range(len(pkt_time[iface]))) 
                for pkt_no in range(len(pkt_time[iface])):
                    if (pkt_no != 0):
                        temp_pkt_time_1[pkt_no] = float(temp_pkt_time_0[pkt_no]) - float(temp_pkt_time_0[pkt_no-1])

                temp_pkt_time_1[0]=1
                pkt_time_diff[iface]=[int(10**9*ts_value/4.00) for ts_value in temp_pkt_time_1]

        for iface in pkts:
            average_pkt_len[iface] = 0
            average_word_cnt[iface] = 0
            s = conf.L2socket(iface = iface)
            for i in range(min(len(pkts[iface]), pkts_loaded[iface])):
                pkt = pkts[iface][i]
                average_pkt_len[iface] = average_pkt_len[iface] + len(pkt)
                average_word_cnt[iface] = average_word_cnt[iface] + ceil(len(pkt)/64.0)
                
                pkt_stamp= "{0:0{1}x}".format(pkt_time_diff[iface][i],16)
                ts_pkt_out = TS_SIGNATURE+binascii.unhexlify(pkt_stamp)
                s.send(Raw(str(ts_pkt_out)))
                test_pkt_out_2 = Raw(str(pkt))
                s.send(test_pkt_out_2)

            average_pkt_len[iface] = float(average_pkt_len[iface])/len(pkts[iface])
            average_word_cnt[iface] = float(average_word_cnt[iface])/len(pkts[iface])

            sleep(1)
            if iface == 'ens1f0':
                wraxi("0x1202C", 0x1)
                sleep(0.5)
                wraxi("0x1202C", 0x0)
            if iface == 'ens1f1':
                wraxi("0x12030", 0x1)
                sleep(0.5)
                wraxi("0x12030", 0x0)

        return {'average_pkt_len':average_pkt_len, 'average_word_cnt':average_word_cnt, 'pkts_loaded':pkts_loaded}

    def run(self):
        begin_replay = self.begin_replay
        self.begin_replay = False
        self.set_begin_replay()

    def stop_replay(self):
        begin_replay = self.begin_replay
        self.begin_replay = False
        self.set_begin_replay()
        self.begin_replay = begin_replay

    def get_replay_cnt(self):
        for i in range(2):
            replay_cnt = rdaxi(self.reg_addr(self.replay_cnt_reg_offsets[i]))
            self.replay_cnt[i] = int(replay_cnt, 16)

    #replay_cnt is an integer
    def set_replay_cnt(self):
        for i in range(2):
            wraxi(self.reg_addr(self.replay_cnt_reg_offsets[i]), hex(self.replay_cnt[i]))
        self.get_replay_cnt()

    def get_begin_replay(self):
        value = rdaxi(self.reg_addr(self.begin_replay_reg_offset)) # use 0x4 to trigger all ports
        value = int(value,16)
        if value == 0:
            self.begin_replay = False
        else:
            self.begin_replay = True          

    def set_begin_replay(self):
        value = 1
        wraxi(self.reg_addr(self.begin_replay_reg_offset), hex(value))
        sleep(0.1)
        value = 0
        wraxi(self.reg_addr(self.begin_replay_reg_offset), hex(value)) # deassert        

    def reg_addr(self, offset):
        return add_hex(self.module_base_addr, offset)

class OSNTRateLimiter:

    def __init__(self, iface):
        self.iface = iface
        self.module_base_addr = RATE_LIMITER_BASE_ADDR[iface]
        self.rate_reg_offset = "0x8"
        self.reset_reg_offset = "0x0"
        self.enable_reg_offset = "0x4"

        self.rate = 0
        self.enable = False
        self.reset = False

        self.get_rate()
        self.get_enable()
        self.get_reset()

    # rate is stored as an integer value
    def get_rate(self):
        rate = rdaxi(self.reg_addr(self.rate_reg_offset))
        self.rate = int(rate, 16)

    def to_string(self, average_pkt_len, average_word_cnt):
        #average_pkt_len + 4 -> 4 is 4B FCS
        rate = float(1)/((1<<self.rate)+1)*(average_pkt_len + 4)*8*DATAPATH_FREQUENCY/average_word_cnt
        #average_pkt_len*8+32 -> 32 is 4B FCS
        #average_pkt_len*8+32+96+64 -> 32b is FCS, 96b is IFG and 64b is Preamble
        rate_max = float(100000000000)*(average_pkt_len*8+32)/(average_pkt_len*8+32+96+64)
        rate = float(min(rate_max, rate))
        percentage = float(rate)/rate_max*100
        percentage = '{0:.4f}'.format(percentage)+'%'
        if rate >= 1000000000:
            rate = rate/1000000000
            return '{0:.2f}'.format(rate)+'Gbps '+percentage
        elif rate >= 1000000:
            rate = rate/1000000
            return '{0:.2f}'.format(rate)+'Mbps '+percentage
        elif rate >= 1000:
            rate = rate/1000
            return '{0:.2f}'.format(rate)+'Kbps '+percentage
        else:
            return '{0:.2f}'.format(rate)+'bps '+percentage

    # rate is an interger value
    def set_rate(self, rate):
        wraxi(self.reg_addr(self.rate_reg_offset), hex(rate))
        self.get_rate()

    def get_enable(self):
        value = rdaxi(self.reg_addr(self.enable_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.enable = False
        else:
            self.enable = True

    def set_enable(self, enable):
        if enable:
            value = 1
        else:
            value = 0
        wraxi(self.reg_addr(self.enable_reg_offset), hex(value))
        self.get_enable()

    def get_reset(self):
        value = rdaxi(self.reg_addr(self.reset_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.reset = False;
        else:
            self.reset = True;

    def set_reset(self, reset):
        if reset:
            value = 1
        else:
            value = 0
        wraxi(self.reg_addr(self.reset_reg_offset), hex(value))
        self.get_reset()
        self.set_rate(0)
        self.set_enable(False)

    def reg_addr(self, offset):
        return add_hex(self.module_base_addr, offset)

    def print_status(self):
        print('iface: '+self.iface+' rate: '+str(self.rate)+' enable: '+str(self.enable)+' reset: '+str(self.reset))

class OSNTDelay:

    def __init__(self, iface):
        self.iface = iface
        self.module_base_addr = INTER_PKT_DELAY_BASE_ADDR[iface]
        self.delay_reg_offset = "0xc"
        self.reset_reg_offset = "0x0"
        self.enable_reg_offset = "0x4"
        self.use_reg_reg_offset = "0x8"

        self.enable = False
        self.use_reg = False
        # The internal delay_length is in ticks (integer)
        self.delay = 0
        self.reset = False

        self.get_enable()
        self.get_use_reg()
        self.get_delay()
        self.get_reset()

    def get_enable(self):
        value = rdaxi(self.reg_addr(self.enable_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.enable = False;
        else:
            self.enable = True;

    def set_enable(self, enable):
        if enable:
            value = 1
        else:
            value = 0
        wraxi(self.reg_addr(self.enable_reg_offset), hex(value))
        self.get_enable()

    def get_use_reg(self):
        value = rdaxi(self.reg_addr(self.use_reg_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.use_reg = False;
        else:
            self.use_reg = True;

    def set_use_reg(self, use_reg):
        if use_reg:
            value = 1
        else:
            value = 0
        wraxi(self.reg_addr(self.use_reg_reg_offset), hex(value))
        self.get_use_reg()

    # delay is stored as an integer value
    def get_delay(self):
        delay = rdaxi(self.reg_addr(self.delay_reg_offset))
        self.delay = int(delay, 16)

    def to_string(self):
        return '{:,}'.format(int(self.delay*1000000000/DATAPATH_FREQUENCY))+'ns'

    # delay is an interger value
    def set_delay(self, delay):
        wraxi(self.reg_addr(self.delay_reg_offset), hex(delay*DATAPATH_FREQUENCY//1000000000))
        self.get_delay()

    def get_reset(self):
        value = rdaxi(self.reg_addr(self.reset_reg_offset))
        value = int(value, 16)
        if value == 0:
            self.reset = False;
        else:
            self.reset = True;

    def set_reset(self, reset):
        if reset:
            value = 1
        else:
            value = 0
        wraxi(self.reg_addr(self.reset_reg_offset), hex(value))
        self.get_reset()
        self.set_enable(False)
        self.set_delay(0)
        self.set_use_reg(False)

    def reg_addr(self, offset):
        return add_hex(self.module_base_addr, offset)

    def print_status(self):
        print('iface: '+self.iface+' delay: '+str(self.delay)+' enable: '+str(self.enable)+' reset: '+str(self.reset)+' use_reg: '+str(self.use_reg))



if __name__=="__main__":
    print("begin")
    rateLimiters = {}
    delays = {}
    poissonEngines = {}
    pcaps = {}
    
    pcaps = {'ens1f0' : 'ens1f0.cap'#,
             #'ens1f1' : 'ens1f1.cap',
             #'ens1f2' : 'ens1f2.cap',
             #'ens1f3' : 'ens1f3.cap'
            }
    # instantiate pcap engine
    pcap_engine = OSNTGeneratorPcapEngine()
    #sleep(1)
    #pcap_engine.replay_cnt = [1, 2, 3, 4]
    #pcap_engine.load_pcap(pcaps)
