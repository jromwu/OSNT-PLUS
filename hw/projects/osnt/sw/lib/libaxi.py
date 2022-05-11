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
#
#  NetFPGA-10G http://www.netfpga.org
#
#  Author:
#        Yilong Geng
#
#  Description:
#        Helper functions for monitor.py and generator.py
#
#
#  Copyright notice:
#        Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
#                                 Junior University
#
#  Licence:
#        This file is part of the NetFPGA 10G development base package.
#
#        This file is free code: you can redistribute it and/or modify it under
#        the terms of the GNU Lesser General Public License version 2.1 as
#        published by the Free Software Foundation.
#
#        This package is distributed in the hope that it will be useful, but
#        WITHOUT ANY WARRANTY; without even the implied warranty of
#        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#        Lesser General Public License for more details.
#
#        You should have received a copy of the GNU Lesser General Public
#        License along with the NetFPGA source package.  If not, see
#        http://www.gnu.org/licenses/.
#
#

import os, binascii, time, subprocess
from fcntl import *
from struct import *
from binascii import hexlify

def rdaxi(addr):
    value=subprocess.getoutput('./axilib -i ens1f0 -a ' +str(addr))
    read_data = int(value, 16);
    value = hex(read_data & int("0xffffffff", 16))
    
    content = "read from "+str(addr)+" got "+str(value)+" \r\n"
    f=open("axitrack.txt", "a")
    f.write(content)
    f.close()

    return value

def wraxi(addr, value):
    os.system("./axilib -i ens1f0 -a "+str(addr)+" -w "+str(value))
    content = "write to "+str(addr)+" with "+str(value)+" \r\n"
    f=open("axitrack.txt", "a")
    f.write(content)
    f.close()

def add_hex(hex1, hex2):
    return hex(int(hex1, 16) + int(hex2, 16))

def hex2ip(hex1):
    hex1 = hex(int(hex1, 16) & int("0xffffffff", 16))
    ip = ""
    for i in range(4):
        ip = ip + '.' + str((int(hex1, 16)>>((3-i)*8)) & int("0xff", 16))
    ip = ip[1:]
    return ip

def ip2hex(ip):
    hex1 = 0
    for tok in ip.split('.'):
        hex1 = (hex1 << 8) + int(tok)
    return hex(hex1 & int("0xffffffff", 16))

# get one bit of value, both int
def get_bit(value, bit):
    return ((value & (2**bit)) >> bit)

def set_bit(value, bit):
    return (value | (2**bit))

def clear_bit(value, bit):
    return (value & (int("0xffffffff", 16) - 2**bit))
