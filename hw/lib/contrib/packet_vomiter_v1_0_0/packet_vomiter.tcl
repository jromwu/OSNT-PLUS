#
# Copyright (c) 2015 Noa Zilberman
# Modified by Salvator Galea
# All rights reserved.
#
# This software was developed by
# Stanford University and the University of Cambridge Computer Laboratory
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

# Vivado Launch Script
#### Change design settings here #######
set design packet_vomiter 
set top packet_vomiter
set device $::env(DEVICE)
set proj_dir ./ip_proj
set ip_version 1.0
set lib_name NetFPGA
#####################################
# Project Settings
#####################################
create_project -name ${design} -force -dir "./${proj_dir}" -part ${device} -ip
set_property source_mgmt_mode All [current_project]  
set_property top ${top} [current_fileset]
set_property ip_repo_paths $::env(NFPLUS_FOLDER)/hw/lib/  [current_fileset]
puts "Creating Packet Vomiter IP"
#####################################
# Project Structure & IP Build
#####################################
read_verilog "./hdl/packet_vomiter_cpu_regs_defines.v"
read_verilog "./hdl/packet_vomiter_cpu_regs.v"
read_verilog "./hdl/packet_vomiter.v"
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
ipx::package_project

set_property name ${design} [ipx::current_core]
set_property library ${lib_name} [ipx::current_core]
set_property vendor_display_name {NetFPGA} [ipx::current_core]
set_property company_url {http://www.netfpga.org} [ipx::current_core]
set_property vendor {NetFPGA} [ipx::current_core]
set_property supported_families {{virtexuplus} {Production} {virtexuplushbm} {Production}} [ipx::current_core]
set_property taxonomy {{/NetFPGA/Generic}} [ipx::current_core]
set_property version ${ip_version} [ipx::current_core]
set_property display_name ${design} [ipx::current_core]
set_property description ${design} [ipx::current_core]

update_ip_catalog -rebuild 
ipx::add_subcore NetFPGA:NetFPGA:fallthrough_small_fifo:1.0 [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_subcore NetFPGA:NetFPGA:fallthrough_small_fifo:1.0 [ipx::get_file_groups xilinx_anylanguagebehavioralsimulation -of_objects [ipx::current_core]]
ipx::infer_user_parameters [ipx::current_core]

ipx::add_user_parameter {C_M_AXIS_DATA_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_M_AXIS_DATA_WIDTH]
set_property display_name {C_M_AXIS_DATA_WIDTH} [ipx::get_user_parameters C_M_AXIS_DATA_WIDTH]
set_property value {512} [ipx::get_user_parameters C_M_AXIS_DATA_WIDTH]
set_property value_format {long} [ipx::get_user_parameters C_M_AXIS_DATA_WIDTH]

ipx::add_user_parameter {C_S_AXIS_DATA_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_S_AXIS_DATA_WIDTH]
set_property display_name {C_S_AXIS_DATA_WIDTH} [ipx::get_user_parameters C_S_AXIS_DATA_WIDTH]
set_property value {512} [ipx::get_user_parameters C_S_AXIS_DATA_WIDTH]
set_property value_format {long} [ipx::get_user_parameters C_S_AXIS_DATA_WIDTH]

ipx::add_user_parameter {C_M_AXIS_TUSER_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_M_AXIS_TUSER_WIDTH]
set_property display_name {C_M_AXIS_TUSER_WIDTH} [ipx::get_user_parameters C_M_AXIS_TUSER_WIDTH]
set_property value {128} [ipx::get_user_parameters C_M_AXIS_TUSER_WIDTH]
set_property value_format {long} [ipx::get_user_parameters C_M_AXIS_TUSER_WIDTH]

ipx::add_user_parameter {C_S_AXIS_TUSER_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_S_AXIS_TUSER_WIDTH]
set_property display_name {C_S_AXIS_TUSER_WIDTH} [ipx::get_user_parameters C_S_AXIS_TUSER_WIDTH]
set_property value {128} [ipx::get_user_parameters C_S_AXIS_TUSER_WIDTH]
set_property value_format {long} [ipx::get_user_parameters C_S_AXIS_TUSER_WIDTH]

ipx::add_user_parameter {C_S_AXI_DATA_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_S_AXI_DATA_WIDTH]
set_property display_name {C_S_AXI_DATA_WIDTH} [ipx::get_user_parameters C_S_AXI_DATA_WIDTH]
set_property value {32} [ipx::get_user_parameters C_S_AXI_DATA_WIDTH]
set_property value_format {long} [ipx::get_user_parameters C_S_AXI_DATA_WIDTH]

ipx::add_user_parameter {C_S_AXI_ADDR_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_S_AXI_ADDR_WIDTH]
set_property display_name {C_S_AXI_ADDR_WIDTH} [ipx::get_user_parameters C_S_AXI_ADDR_WIDTH]
set_property value {32} [ipx::get_user_parameters C_S_AXI_ADDR_WIDTH]
set_property value_format {long} [ipx::get_user_parameters C_S_AXI_ADDR_WIDTH]

ipx::add_user_parameter {C_BASEADDR} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters C_BASEADDR]
set_property display_name {C_BASEADDR} [ipx::get_user_parameters C_BASEADDR]
set_property value {0x00000000} [ipx::get_user_parameters C_BASEADDR]
set_property value_format {bitstring} [ipx::get_user_parameters C_BASEADDR]

ipx::add_user_parameter {DST_PORT_VALUE} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters DST_PORT_VALUE]
set_property display_name {DST_PORT_VALUE} [ipx::get_user_parameters DST_PORT_VALUE]
set_property value {0x00} [ipx::get_user_parameters DST_PORT_VALUE]
set_property value_format {bitstring} [ipx::get_user_parameters DST_PORT_VALUE]

ipx::add_user_parameter {SRC_PORT_VALUE} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters SRC_PORT_VALUE]
set_property display_name {SRC_PORT_VALUE} [ipx::get_user_parameters SRC_PORT_VALUE]
set_property value {0x00} [ipx::get_user_parameters SRC_PORT_VALUE]
set_property value_format {bitstring} [ipx::get_user_parameters SRC_PORT_VALUE]

ipx::add_user_parameter {ETH_ADDR} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters ETH_ADDR]
set_property display_name {ETH_ADDR} [ipx::get_user_parameters ETH_ADDR]
set_property value {0x000000000000} [ipx::get_user_parameters ETH_ADDR]
set_property value_format {bitstring} [ipx::get_user_parameters ETH_ADDR]

ipx::add_user_parameter {TIMESTAMP_POS} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters TIMESTAMP_POS]
set_property display_name {TIMESTAMP_POS} [ipx::get_user_parameters TIMESTAMP_POS]
set_property value {240} [ipx::get_user_parameters TIMESTAMP_POS]
set_property value_format {long} [ipx::get_user_parameters TIMESTAMP_POS]

ipx::add_user_parameter {TIMESTAMP_WIDTH} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameters TIMESTAMP_WIDTH]
set_property display_name {TIMESTAMP_WIDTH} [ipx::get_user_parameters TIMESTAMP_WIDTH]
set_property value {64} [ipx::get_user_parameters TIMESTAMP_WIDTH]
set_property value_format {long} [ipx::get_user_parameters TIMESTAMP_WIDTH]

ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces m_axis -of_objects [ipx::current_core]]
# ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s_axis_0 -of_objects [ipx::current_core]]
# ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s_axis_1 -of_objects [ipx::current_core]]
# ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s_axis_2 -of_objects [ipx::current_core]]

ipx::infer_user_parameters [ipx::current_core]

ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]
update_ip_catalog
close_project

