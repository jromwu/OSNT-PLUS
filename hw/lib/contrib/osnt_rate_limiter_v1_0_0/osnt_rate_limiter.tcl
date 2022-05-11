#
# Copyright (c) 2016 University of Cambridge
# Copyright (c) 2016 Jong Hun Han
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


# Set variables.
set design              osnt_rate_limiter
set top                 osnt_rate_limiter
set ip_version          1.0
set ip_version_display  v1_0
set proj_dir            ./ip_proj

# Call common setting for ips
source ../osnt_lib/osnt_ip_set_common.tcl

#####################################
# Project Settings
#####################################
create_project -name ${design} -force -dir "./${proj_dir}" -part ${device} -ip
set_property source_mgmt_mode All [current_project]
set_property top ${top} [current_fileset]
set_property ip_repo_paths $::env(NFPLUS_FOLDER)/hw/lib/  [current_fileset]
update_ip_catalog

# IP build.
read_verilog "./hdl/verilog/osnt_rate_limiter.v"
read_verilog "./hdl/verilog/rate_limiter_simple.v"
read_verilog "./hdl/verilog/rate_limiter_cpu_regs.v"

update_compile_order -fileset sources_1

ipx::package_project

# Call common properties of ips
source ../osnt_lib/osnt_ip_property_common.tcl

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

ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s_axi -of_objects [ipx::current_core]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces m0_axis -of_objects [ipx::current_core]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces m1_axis -of_objects [ipx::current_core]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces m2_axis -of_objects [ipx::current_core]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s0_axis -of_objects [ipx::current_core]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s1_axis -of_objects [ipx::current_core]]
ipx::add_bus_parameter FREQ_HZ [ipx::get_bus_interfaces s2_axis -of_objects [ipx::current_core]]

ipx::infer_user_parameters [ipx::current_core]
ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]

close_project
exit

