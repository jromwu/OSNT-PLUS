# version 2.12 14.54

#
# Copyright (c) 2017 University of Cambridge
# Copyright (c) 2017 Jong Hun Han
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

from datetime import datetime
import pickle # update
import os, sys, math, argparse
sys.path.insert(0, "./../lib")
from libaxi import *
from time import gmtime, strftime, sleep
#from monitor import *
#from monitor_cli_lib import *
from generator import *
from generator_cli_lib import *
#from timestamp_capture_cli_lib import *

input_arg = argparse.ArgumentParser()
# Generator flags
input_arg.add_argument("-new", action="store_true", help="new command set (clear old parameters) eg. -new")
input_arg.add_argument("-ifp0", type=str, help="OSNT PLUS generator load packet into port 0. eg. -if0 <pcap file>")
input_arg.add_argument("-ifp1", type=str, help="OSNT PLUS generator load packet into port 1. eg. -if1 <pcap file>")
input_arg.add_argument("-rpn0", type=int, help="OSNT PLUS generator packet replay no. on port 0. eg. -rpn0 <integer number>")
input_arg.add_argument("-rpn1", type=int, help="OSNT PLUS generator packet replay no. on port 1. eg. -rpn1 <integer number>")
input_arg.add_argument("-ipg0", type=int, help="OSNT PLUS generator inter packet gap on port 0. eg. -ipg0 <integer number>")
input_arg.add_argument("-ipg1", type=int, help="OSNT PLUS generator inter packet gap on port 1. eg. -ipg1 <integer number>")
#input_arg.add_argument("-txs0", type=int, help="OSNT PLUS generator tx timestamp position on port 0. eg. -txs0 <integer number>")
#input_arg.add_argument("-txs1", type=int, help="OSNT PLUS generator tx timestamp position on port 1. eg. -txs1 <integer number>")
#input_arg.add_argument("-rxs0", type=int, help="OSNT PLUS generator rx timestamp position on port 0. eg. -rxs0 <integer number>")
#input_arg.add_argument("-rxs1", type=int, help="OSNT PLUS generator rx timestamp position on port 1. eg. -rxs1 <integer number>")
input_arg.add_argument("-run", action="store_true", help="OSNT PLUS generator trigger to run. eg. --run")

# Monitor flags
#input_arg.add_argument("-cs", type=int, help="OSNT PLUS monitor packet cutter size in byte. -cs <integer number>")
#input_arg.add_argument("-ds", action="store_true", help="OSNT PLUS monitor run display stats. -ds")
#input_arg.add_argument("-st", action="store_true", help="OSNT PLUS monitor show stats. -st")
#input_arg.add_argument("-flt", type=str, help="OSNT PLUS monitor load filter file. -flt <filter file name>")
#input_arg.add_argument("-clear", action="store_true", help="OSNT PLUS monitor clear stats and time. -clear")

# Latency measurement flags
#input_arg.add_argument("-lpn", type=int, help="OSNT PLUS latency measurement packet no on one of the nf interfaces. eg. -lpn <integer number>. This number should be the same with the rpn.")
#input_arg.add_argument("-lty0", action="store_true", help="OSNT PLUS latency measurement on port 0. eg. -lty0")
#input_arg.add_argument("-lty1", action="store_true", help="OSNT PLUS latency measurement on port 1. eg. -lty1")
#input_arg.add_argument("-llog", type=str, help="OSNT PLUS latency measurement log file. eg. -lf <file name>")
#input_arg.add_argument("-skt", action="store_true", help="OSNT PLUS generator trigger and latency measurement with python socket. eg. -skt")
#input_arg.add_argument("-rnm", action="store_true", help="OSNT PLUS generator trigger and latency measurement. eg. -rnm")


args = input_arg.parse_args()

# 1. Generator only
# 2. Monitor only
# 3. Latency only
# 4. Generator and Monitor : Gen set - Monitor live display - Gen run
# 5. Generator and Latency : Gen set - Latency - Gen run

## ==============================================

nullstr = "nullstr"

if (args.new):

    # load pcap file
    pickle.dump(nullstr, open("./pickle/pcapfile_0.p", "wb"))
    pickle.dump(nullstr, open("./pickle/pcapfile_1.p", "wb"))
    
    # load pcap file with timestamp
    pickle.dump(nullstr, open("./pickle/pcapfilets_0.p", "wb"))
    pickle.dump(nullstr, open("./pickle/pcapfilets_1.p", "wb"))

    # replay count
    pickle.dump(0, open("./pickle/rpn_0.p", "wb"))
    pickle.dump(0, open("./pickle/rpn_1.p", "wb"))

    # delays
    pickle.dump(0, open("./pickle/delay_0.p", "wb"))
    pickle.dump(0, open("./pickle/delay_1.p", "wb"))

#    # rx timestamp position
#    pickle.dump(nullstr, open("./pickle/rxtsps_0.p", "wb"))
#    pickle.dump(nullstr, open("./pickle/rxtsps_1.p", "wb"))
#
#    # tx timestamp position
#    pickle.dump(nullstr, open("./pickle/txtsps_0.p", "wb"))
#    pickle.dump(nullstr, open("./pickle/txtsps_1.p", "wb"))

    print("  ")
    print("[CLI: Previous Configuration Cleared!]\n")

## ==============================================

if (args.clear):
    set_clear()
    clear()
    sys.exit(1)

# Set no packet for latency measure ment 
#if (args.lpn or args.lpn == 0):
#    lty_pkt_no=args.lpn
#else:
#    lty_pkt_no=0 
#
## Set and chect latency measurement interface. 
#lty_value=[0, 0]
#lty_if=""
#if (args.lty0):
#    print("------> args.lty0 = " + str(args.lty0))
#    lty_value[0]=1
#    lty_if="nf0"
#
#if (args.lty1):
#    lty_value[1]=1
#    lty_if="nf1"
#
#if (sum(lty_value) == 1):
#    if (lty_pkt_no == 0):
#       print("Neet to set the number of packet to be captured.")
#       sys.exit(1)
#    set_clear()
#
#if (sum(lty_value) > 1):
#    print(lty_value)
#    print("\n\nError: Cannot measure two ports on the same terminal!\n")

# Load pcap file
if (args.ifp0):
    pickle.dump(args.ifp0, open("./pickle/pcapfile_0.p", "wb"))

if (args.ifp1):
    pickle.dump(args.ifp1, open("./pickle/pcapfile_1.p", "wb"))

# Load pcap file
if (args.ifpt0):
    pickle.dump(args.ifpt0, open("./pickle/pcapfilets_0.p", "wb"))

if (args.ifpt1):
    pickle.dump(args.ifpt1, open("./pickle/pcapfilets_1.p", "wb"))

# Set packet replay number
if (args.rpn0 or args.rpn0 == 0):
    pickle.dump(args.rpn0, open("./pickle/rpn_0.p", "wb"))

if (args.rpn1 or args.rpn1 == 0):
    pickle.dump(args.rpn1, open("./pickle/rpn_1.p", "wb"))

# Set inter packet gap dealy
if (args.ipg0):
   pickle.dump(args.ipg0, open("./pickle/delay_0.p", "wb"))

if (args.ipg1):
   pickle.dump(args.ipg1, open("./pickle/delay_1.p", "wb"))

# Set TX timestamp position (preparation)
#if (args.txs0):
#    pickle.dump(args.txs0, open("./pickle/txtsps_0.p", "wb"))
#    lty_tx_pos = args.txs0
#
#if (args.txs1):
#    pickle.dump(args.txs1, open("./pickle/txtsps_1.p", "wb"))    
#    lty_tx_pos = args.txs1

# Set RX timestamp position
#if (args.rxs0):
#    pickle.dump(args.rxs0, open("./pickle/rxtsps_0.p", "wb"))  
#    lty_rx_pos = args.rxs0
#
#if (args.rxs1):
#    pickle.dump(args.rxs1, open("./pickle/rxtsps_1.p", "wb")) 
#    lty_rx_pos = args.rxs1

# Load filter for monitor on the host
#if (args.flt):
#    print(' -*-*-*-*-*-*-*-*-*-> [ args.flt ]')
#    load_rule(args.flt)
#
#if (args.llog):
#    log_file = args.llog
#elif (lty_if != ""):
#    log_file = "latency_data.dat"
#    print('Write a file name to store the results. Default <latency_data.dat>\n')
#
#if (lty_if != ""):
#    print("Set the interface ", lty_if)
#    if (args.flt):
#       print(' -*-*-*-*-*-*-*-*-*-> [lty_if != null, args.flt]')        
#       load_rule(args.flt)
#    else:
#       load_rule("./filter.cfg")
#
#    if (args.skt):   
#       timestamp_capture(lty_if, lty_tx_pos, lty_rx_pos, lty_pkt_no, log_file, args.rnm)
#    else:
#       print(" -*-*-*-*-*-*-*-*-*-> timestamp tcpdump function call")
#       timestamp_tcpdump(lty_if, lty_tx_pos, lty_rx_pos, lty_pkt_no, log_file, args.rnm)

# run 
if (args.run):
    # --- print help
    pcaps = {}
    pcaps_ts = {}
    replays = {}
    delays = {}
#    rxtss = {}
#    txtss = {}

    # load generator parameters
    pickle_fname_suffix = ".p"
    # ### load pcap file ###
    pickle_fname_prefix = "./pickle/pcapfile_"
    mypcaps = {}
    change = 0
    for i in range(2):
        pickle_fname_str = pickle_fname_prefix + str(i) + pickle_fname_suffix
        v = pickle.load(open(pickle_fname_str, "rb"))
        if v != nullstr:
            change = 1
            portstr = "ens1f" + str(i)
            mypcaps[portstr] = v
            pcaps[i] = v
        else:
            pcaps[i] = "n/a"                 
    if change == 1:
        set_load_pcap(mypcaps)  
    # ### load pcap file with timestamp ###
    pickle_fname_prefix = "./pickle/pcapfilets_"
    flag_pcapfilets = 0
    mypcaps = {}
    change = 0
    for i in range(2):
        pickle_fname_str = pickle_fname_prefix + str(i) + pickle_fname_suffix
        v = pickle.load(open(pickle_fname_str, "rb"))
        if v != nullstr:
            change = 1
            flag_pcapfilets = 1
            portstr = "ens1f" + str(i)
            mypcaps[portstr] = v
            pcaps_ts[i] = v
        else:
            pcaps_ts[i] = "n/a"        
    if change == 1:
        set_load_pcap_ts(mypcaps)  
    # ### set packet replay number ###
    pickle_fname_prefix = "./pickle/rpn_"
    values = [0, 0]
    for i in range(2):
        pickle_fname_str = pickle_fname_prefix + str(i) + pickle_fname_suffix
        values[i] = pickle.load(open(pickle_fname_str, "rb"))
        #print('copied replay number: ' + str(i) + ' with value: ' + str(values[i]))
        replays[i] = pickle.load(open(pickle_fname_str, "rb"))
    set_replay_cnt(values)
    # ### set inter packet delays ###   
    pickle_fname_prefix = "./pickle/delay_"
    values = [0, 0]
    for i in range(2):
        pickle_fname_str = pickle_fname_prefix + str(i) + pickle_fname_suffix
        values[i] = pickle.load(open(pickle_fname_str, "rb"))
        delays[i] = values[i]
        #print('copied interpacket delay: ' + str(i) + ' with value: ' + str(values[i]))
    if flag_pcapfilets == 1:
        #print('inter packet delay: pcap TS')
        for i in range(2):  
            set_ipg_ts(i, values[i])
    else:
        #print('inter packet delay: normal')
        for i in range(2):  
            set_ipg(i, values[i])

    # ### -> before setting rx and tx timestamp position
    # configure 10g_axi_if's indirect access
#    if_indi_config();

    # ### set rx timestamp position ###
#    pickle_fname_prefix = "./pickle/rxtsps_"
#    values = [0, 0, 0, 0]
#    for i in range(4):
#        pickle_fname_str = pickle_fname_prefix + str(i) + pickle_fname_suffix
#        values[i] = pickle.load(open(pickle_fname_str, "rb"))
#        rxtss[i] = values[i]
#        if values[i] != nullstr:
#            set_rx_ts(i, values[i])
    # ### set tx timestamp position ###
#    pickle_fname_prefix = "./pickle/txtsps_"
#    values = [0, 0, 0, 0]
#    for i in range(4):
#        pickle_fname_str = pickle_fname_prefix + str(i) + pickle_fname_suffix
#        values[i] = pickle.load(open(pickle_fname_str, "rb"))
#        txtss[i] = values[i]
#        if values[i] != nullstr:
#            set_tx_ts(i, values[i])
    # actual run        
    initgcli.pcap_engine.run()
    print("  ")
    print("[CLI: Start packet generator...!]\n")
    
    ################# display run-config ######################
    print(" --------------------------------------------------------------------------------")
    print(" --------- Packet Generator Started With The Following Configuration ------------")
    print(" --------------------------------------------------------------------------------")
    print("                                 ")
    print("       replay,     delay,     rxts,     txts,     pcap or pcap_ts,")
    print("                                 ")
    for i in range(2):
        port_name = " [ens1f"+str(i)+"]"
        pcap_local = pcaps[i]
        pcap_ts_local = pcaps_ts[i]
        if pcap_local == "n/a" and pcap_ts_local == "n/a":
            pcap_print = "     n/a"
        else: 
            if pcap_ts_local == "n/a":
                pcap_print = "(pcap)" + pcap_local
            else:
                if pcap_local == "n/a":
                    pcap_print = "(pcap_TS)" + pcap_ts_local       
                else:
                    pcap_print = "     n/a"
#        if rxtss[i] == "nullstr":
#            rxtss[i] = "- "
#        if txtss[i] == "nullstr":
#            txtss[i] = "-"
        print((port_name+"   "+ str(replays[i])+"           "+str(delays[i])+"         "+str(rxtss[i])+"        "+str(txtss[i])+"      " + pcap_print))
        print("                                 ")
    
    print((datetime.now()))
    print(" --------------------------------------------------------------------------------")

    ###########################################################

# Show the stats in monitor
if (args.st):
    cli_display_stats("show")

if (args.ds):
    run_stats()
