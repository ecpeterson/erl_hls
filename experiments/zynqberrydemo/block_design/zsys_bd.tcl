catch {TE::UTILS::te_msg TE_BD-0 INFO "This block design tcl-file was generate with Trenz Electronic GmbH Board Part:trenz.biz:te0726_10_1c:part0:3.1, FPGA: xc7z010clg225-1 at 2025-10-21T13:35:13."}
catch {TE::UTILS::te_msg TE_BD-1 INFO "This block design tcl-file was modified by TE-Scripts. Modifications are labelled with comment tag  # #TE_MOD# on the Block-Design tcl-file."}

if { ![info exist TE::VERSION_CONTROL] } {
  namespace eval ::TE  {
    set ::TE::VERSION_CONTROL true
  }
}
################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2024.2
set current_vivado_version [version -short ]
if { [string first $scripts_vivado_version $current_vivado_version] == -1 &&  $TE::VERSION_CONTROL } {
   puts ""
   catch {common::send_msg_id "BD_TCL-109" "ERROR" "This script was generated using Vivado < $scripts_vivado_version> and is being run in < $current_vivado_version> of Vivado. Please run the script in Vivado < $scripts_vivado_version> then open the design in Vivado < $current_vivado_version>. Upgrade the design by running "Tools => Report => Report IP Status...", then run write_bd_tcl to create an updated script."}
 return 1
}

################################################################
# This is a generated script based on design: zsys
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2024.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   common::send_gid_msg -ssname BD::TCL -id 2040 -severity "CRITICAL WARNING" "This script was generated using Vivado <$scripts_vivado_version> without IP versions in the create_bd_cell commands, but is now being run in <$current_vivado_version> of Vivado. There may have been changes to the IP between Vivado <$scripts_vivado_version> and <$current_vivado_version>, which could impact the functionality and configuration of the design."

}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source zsys_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# clk_divider, clk_divider, clk_divider

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z010clg225-1
   set_property BOARD_PART trenz.biz:te0726_10_1c:part0:3.1 [current_project]
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name zsys

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
trenz.biz:user:axi_reg32:*\
xilinx.com:ip:processing_system7:*\
xilinx.com:ip:xlconcat:*\
xilinx.com:ip:xlslice:*\
xilinx.com:ip:audio_formatter:*\
trenz.biz:user:axis_to_i2s:*\
xilinx.com:ip:i2s_receiver:*\
trenz.biz:user:i2s_to_pwm:*\
xilinx.com:ip:i2s_transmitter:*\
xilinx.com:ip:xadc_wiz:*\
xilinx.com:ip:xlconstant:*\
xilinx.com:ip:proc_sys_reset:*\
xilinx.com:ip:axi_vdma:*\
xilinx.com:ip:axis_data_fifo:*\
trenz.biz:user:axis_raw_demosaic:*\
trenz.biz:user:axis_raw_unpack:*\
trenz.biz:user:csi2_d_phy_rx:*\
trenz.biz:user:csi_to_axis:*\
trenz.biz:user:Video_IO_2_HDMI_TMDS:*\
trenz.biz:user:axis_fb_conv:*\
xilinx.com:ip:clk_wiz:*\
xilinx.com:ip:v_axi4s_vid_out:*\
xilinx.com:ip:v_tc:*\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
clk_divider\
clk_divider\
clk_divider\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################


# Hierarchical cell: video_out
proc create_hier_cell_video_out { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_video_out() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 CLKWIZ_AXI

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 VDMA_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 VIDEO_OUT_AXI

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 VTC_AXI


  # Create pins
  create_bd_pin -dir I -type clk axi_aclk
  create_bd_pin -dir I -from 0 -to 0 -type rst axi_int_aresetn
  create_bd_pin -dir I -from 0 -to 0 -type rst axi_per_aresetn
  create_bd_pin -dir O hdmi_clk_n
  create_bd_pin -dir O hdmi_clk_p
  create_bd_pin -dir O -from 2 -to 0 hdmi_data_n
  create_bd_pin -dir O -from 2 -to 0 hdmi_data_p
  create_bd_pin -dir I -type clk ref_clk
  create_bd_pin -dir O -type intr tx_dma_int
  create_bd_pin -dir I -type rst ext_reset_in

  # Create instance: Video_IO_2_HDMI_TMDS_0, and set properties
  set Video_IO_2_HDMI_TMDS_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:Video_IO_2_HDMI_TMDS Video_IO_2_HDMI_TMDS_0 ]
  set_property -dict [list \
    CONFIG.C_CLK_SWAP {true} \
    CONFIG.C_D0_SWAP {true} \
    CONFIG.C_INT_CLOCKING {false} \
  ] $Video_IO_2_HDMI_TMDS_0


  # Create instance: axi_mem_intercon, and set properties
  set axi_mem_intercon [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_mem_intercon ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.SYNCHRONIZATION_STAGES {2} \
  ] $axi_mem_intercon


  # Create instance: axi_vdma_0, and set properties
  set axi_vdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma axi_vdma_0 ]
  set_property -dict [list \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_mm2s_genlock_mode {0} \
    CONFIG.c_mm2s_linebuffer_depth {1024} \
    CONFIG.c_mm2s_max_burst_length {16} \
    CONFIG.c_num_fstores {1} \
  ] $axi_vdma_0


  # Create instance: axis_fb_conv_0, and set properties
  set axis_fb_conv_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:axis_fb_conv axis_fb_conv_0 ]

  # Create instance: clk_wiz_1, and set properties
  set clk_wiz_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_1 ]
  set_property -dict [list \
    CONFIG.CLKIN1_JITTER_PS {50.0} \
    CONFIG.CLKOUT1_JITTER {333.287} \
    CONFIG.CLKOUT1_PHASE_ERROR {322.999} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.250} \
    CONFIG.CLKOUT2_JITTER {256.477} \
    CONFIG.CLKOUT2_PHASE_ERROR {322.999} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {371.250} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT3_JITTER {325.031} \
    CONFIG.CLKOUT3_PHASE_ERROR {569.784} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT3_USED {false} \
    CONFIG.CLKOUT4_JITTER {357.108} \
    CONFIG.CLKOUT4_PHASE_ERROR {569.784} \
    CONFIG.CLKOUT4_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.CLKOUT4_USED {false} \
    CONFIG.JITTER_SEL {Min_O_Jitter} \
    CONFIG.MMCM_BANDWIDTH {HIGH} \
    CONFIG.MMCM_CLKFBOUT_MULT_F {37.125} \
    CONFIG.MMCM_CLKIN1_PERIOD {5.000} \
    CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {10.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {2} \
    CONFIG.MMCM_CLKOUT2_DIVIDE {1} \
    CONFIG.MMCM_CLKOUT3_DIVIDE {1} \
    CONFIG.MMCM_DIVCLK_DIVIDE {10} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.USE_DYN_RECONFIG {true} \
  ] $clk_wiz_1


  # Create instance: v_axi4s_vid_out_0, and set properties
  set v_axi4s_vid_out_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out v_axi4s_vid_out_0 ]
  set_property CONFIG.C_HAS_ASYNC_CLK {1} $v_axi4s_vid_out_0


  # Create instance: v_tc_0, and set properties
  set v_tc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc v_tc_0 ]
  set_property -dict [list \
    CONFIG.HAS_AXI4_LITE {true} \
    CONFIG.VIDEO_MODE {720p} \
    CONFIG.enable_detection {false} \
    CONFIG.max_clocks_per_line {4096} \
    CONFIG.max_lines_per_frame {2048} \
  ] $v_tc_0


  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_0 ]

  # Create interface connections
  connect_bd_intf_net -intf_net CLKWIZ_AXI_1 [get_bd_intf_pins CLKWIZ_AXI] [get_bd_intf_pins clk_wiz_1/s_axi_lite]
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins VIDEO_OUT_AXI] [get_bd_intf_pins axi_mem_intercon/M00_AXI]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins VDMA_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins VTC_AXI] [get_bd_intf_pins v_tc_0/ctrl]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXIS_MM2S [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins axis_fb_conv_0/S_AXIS]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXI_MM2S [get_bd_intf_pins axi_mem_intercon/S00_AXI] [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S]
  connect_bd_intf_net -intf_net axis_fb_conv_0_video_out [get_bd_intf_pins axis_fb_conv_0/video_out] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
  connect_bd_intf_net -intf_net v_axi4s_vid_out_0_vid_io_out [get_bd_intf_pins Video_IO_2_HDMI_TMDS_0/vid_io_in] [get_bd_intf_pins v_axi4s_vid_out_0/vid_io_out]
  connect_bd_intf_net -intf_net v_tc_0_vtiming_out [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in] [get_bd_intf_pins v_tc_0/vtiming_out]

  # Create port connections
  connect_bd_net -net ARESETN_2  [get_bd_pins axi_int_aresetn] \
  [get_bd_pins axi_mem_intercon/ARESETN]
  connect_bd_net -net Video_IO_2_HDMI_TMDS_0_hdmi_clk_n  [get_bd_pins Video_IO_2_HDMI_TMDS_0/hdmi_clk_n] \
  [get_bd_pins hdmi_clk_n]
  connect_bd_net -net Video_IO_2_HDMI_TMDS_0_hdmi_clk_p  [get_bd_pins Video_IO_2_HDMI_TMDS_0/hdmi_clk_p] \
  [get_bd_pins hdmi_clk_p]
  connect_bd_net -net Video_IO_2_HDMI_TMDS_0_hdmi_data_n  [get_bd_pins Video_IO_2_HDMI_TMDS_0/hdmi_data_n] \
  [get_bd_pins hdmi_data_n]
  connect_bd_net -net Video_IO_2_HDMI_TMDS_0_hdmi_data_p  [get_bd_pins Video_IO_2_HDMI_TMDS_0/hdmi_data_p] \
  [get_bd_pins hdmi_data_p]
  connect_bd_net -net aclk_1  [get_bd_pins axi_aclk] \
  [get_bd_pins axi_mem_intercon/ACLK] \
  [get_bd_pins axi_mem_intercon/M00_ACLK] \
  [get_bd_pins axi_mem_intercon/S00_ACLK] \
  [get_bd_pins axi_vdma_0/m_axi_mm2s_aclk] \
  [get_bd_pins axi_vdma_0/m_axis_mm2s_aclk] \
  [get_bd_pins axi_vdma_0/s_axi_lite_aclk] \
  [get_bd_pins axis_fb_conv_0/s_axis_aclk] \
  [get_bd_pins clk_wiz_1/s_axi_aclk] \
  [get_bd_pins v_axi4s_vid_out_0/aclk] \
  [get_bd_pins v_tc_0/s_axi_aclk]
  connect_bd_net -net aresetn_1  [get_bd_pins axi_per_aresetn] \
  [get_bd_pins axi_mem_intercon/M00_ARESETN] \
  [get_bd_pins axi_mem_intercon/S00_ARESETN] \
  [get_bd_pins axi_vdma_0/axi_resetn] \
  [get_bd_pins axis_fb_conv_0/s_axis_aresetn] \
  [get_bd_pins clk_wiz_1/s_axi_aresetn] \
  [get_bd_pins v_axi4s_vid_out_0/aresetn] \
  [get_bd_pins v_tc_0/s_axi_aresetn]
  connect_bd_net -net axi_vdma_0_mm2s_introut  [get_bd_pins axi_vdma_0/mm2s_introut] \
  [get_bd_pins tx_dma_int]
  connect_bd_net -net clk_in1_1  [get_bd_pins ref_clk] \
  [get_bd_pins clk_wiz_1/clk_in1]
  connect_bd_net -net clk_wiz_1_clk_out2  [get_bd_pins clk_wiz_1/clk_out2] \
  [get_bd_pins Video_IO_2_HDMI_TMDS_0/video_clk5x_in]
  connect_bd_net -net clk_wiz_1_locked  [get_bd_pins clk_wiz_1/locked] \
  [get_bd_pins Video_IO_2_HDMI_TMDS_0/lock_in] \
  [get_bd_pins proc_sys_reset_0/dcm_locked]
  connect_bd_net -net ext_reset_in_1  [get_bd_pins ext_reset_in] \
  [get_bd_pins proc_sys_reset_0/ext_reset_in]
  connect_bd_net -net proc_sys_reset_0_peripheral_aresetn  [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
  [get_bd_pins v_tc_0/resetn]
  connect_bd_net -net proc_sys_reset_0_peripheral_reset  [get_bd_pins proc_sys_reset_0/peripheral_reset] \
  [get_bd_pins v_axi4s_vid_out_0/vid_io_out_reset]
  connect_bd_net -net v_axi4s_vid_out_0_vtg_ce  [get_bd_pins v_axi4s_vid_out_0/vtg_ce] \
  [get_bd_pins v_tc_0/gen_clken]
  connect_bd_net -net video_clk_in_1  [get_bd_pins clk_wiz_1/clk_out1] \
  [get_bd_pins Video_IO_2_HDMI_TMDS_0/video_clk_in] \
  [get_bd_pins v_axi4s_vid_out_0/vid_io_out_clk] \
  [get_bd_pins v_tc_0/clk] \
  [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: video_in
proc create_hier_cell_video_in { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_video_in() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 VDMA_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 VIDEO_IN_AXI


  # Create pins
  create_bd_pin -dir I -type clk axi_aclk
  create_bd_pin -dir I -from 0 -to 0 -type rst axi_aresetn
  create_bd_pin -dir I -from 0 -to 0 axi_int_aresetn
  create_bd_pin -dir I colors_mode
  create_bd_pin -dir I csi_clk_n
  create_bd_pin -dir I csi_clk_p
  create_bd_pin -dir I -from 0 -to 0 csi_data_lp_n
  create_bd_pin -dir I -from 0 -to 0 csi_data_lp_p
  create_bd_pin -dir I -from 1 -to 0 csi_data_n
  create_bd_pin -dir I -from 1 -to 0 csi_data_p
  create_bd_pin -dir I -from 0 -to 0 enable
  create_bd_pin -dir I -type rst ext_reset_in
  create_bd_pin -dir I processing_clk
  create_bd_pin -dir I ref_clk
  create_bd_pin -dir O rx_dma_int

  # Create instance: axi_interconnect_0, and set properties
  set axi_interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_interconnect_0 ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.SYNCHRONIZATION_STAGES {2} \
  ] $axi_interconnect_0


  # Create instance: axi_vdma_0, and set properties
  set axi_vdma_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma axi_vdma_0 ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm_dre {1} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_num_fstores {1} \
    CONFIG.c_s2mm_genlock_mode {0} \
    CONFIG.c_s2mm_linebuffer_depth {4096} \
    CONFIG.c_s2mm_max_burst_length {32} \
  ] $axi_vdma_0


  # Create instance: axis_data_fifo_0, and set properties
  set axis_data_fifo_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_data_fifo_0 ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {16384} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {2} \
    CONFIG.TUSER_WIDTH {1} \
  ] $axis_data_fifo_0


  # Create instance: axis_data_fifo_3, and set properties
  set axis_data_fifo_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_data_fifo_3 ]

  # Create instance: axis_data_fifo_4, and set properties
  set axis_data_fifo_4 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo axis_data_fifo_4 ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {4096} \
    CONFIG.IS_ACLK_ASYNC {1} \
  ] $axis_data_fifo_4


  # Create instance: axis_raw_demosaic_0, and set properties
  set axis_raw_demosaic_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:axis_raw_demosaic axis_raw_demosaic_0 ]
  set_property -dict [list \
    CONFIG.C_COLOR_POS {2} \
    CONFIG.C_IN_TYPE {1} \
    CONFIG.C_MODE {1} \
  ] $axis_raw_demosaic_0


  # Create instance: axis_raw_unpack_0, and set properties
  set axis_raw_unpack_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:axis_raw_unpack axis_raw_unpack_0 ]
  set_property -dict [list \
    CONFIG.C_IMP_TYPE {1} \
    CONFIG.C_OUT_TYPE {1} \
  ] $axis_raw_unpack_0


  # Create instance: csi2_d_phy_rx_0, and set properties
  set csi2_d_phy_rx_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:csi2_d_phy_rx csi2_d_phy_rx_0 ]
  set_property -dict [list \
    CONFIG.C_ADD_IDELAYCTRL {true} \
    CONFIG.C_CALIB_WAIT {8191} \
    CONFIG.C_NUM_LP_LANES {1} \
    CONFIG.C_RATE_LIMIT {50} \
    CONFIG.C_USE_DELAY {true} \
  ] $csi2_d_phy_rx_0


  # Create instance: csi_to_axis_0, and set properties
  set csi_to_axis_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:csi_to_axis csi_to_axis_0 ]
  set_property CONFIG.C_TIMEOUT {255} $csi_to_axis_0


  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_0 ]

  # Create instance: proc_sys_reset_1, and set properties
  set proc_sys_reset_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_1 ]

  # Create interface connections
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins axis_data_fifo_0/S_AXIS] [get_bd_intf_pins csi_to_axis_0/M_AXIS]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins VDMA_AXI] [get_bd_intf_pins axi_vdma_0/S_AXI_LITE]
  connect_bd_intf_net -intf_net Conn4 [get_bd_intf_pins VIDEO_IN_AXI] [get_bd_intf_pins axi_interconnect_0/M00_AXI]
  connect_bd_intf_net -intf_net axi_vdma_0_M_AXI_S2MM [get_bd_intf_pins axi_interconnect_0/S00_AXI] [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM]
  connect_bd_intf_net -intf_net axis_data_fifo_0_M_AXIS [get_bd_intf_pins axis_data_fifo_0/M_AXIS] [get_bd_intf_pins axis_raw_unpack_0/S_AXIS]
  connect_bd_intf_net -intf_net axis_data_fifo_3_M_AXIS [get_bd_intf_pins axis_data_fifo_3/M_AXIS] [get_bd_intf_pins axis_raw_demosaic_0/S_AXIS]
  connect_bd_intf_net -intf_net axis_data_fifo_4_M_AXIS [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM] [get_bd_intf_pins axis_data_fifo_4/M_AXIS]
  connect_bd_intf_net -intf_net axis_raw_demosaic_0_M_AXIS [get_bd_intf_pins axis_data_fifo_4/S_AXIS] [get_bd_intf_pins axis_raw_demosaic_0/M_AXIS]
  connect_bd_intf_net -intf_net axis_raw_unpack_0_M_AXIS [get_bd_intf_pins axis_data_fifo_3/S_AXIS] [get_bd_intf_pins axis_raw_unpack_0/M_AXIS]
  connect_bd_intf_net -intf_net csi2_d_phy_rx_0_RX_MIPI_PPI [get_bd_intf_pins csi2_d_phy_rx_0/RX_MIPI_PPI] [get_bd_intf_pins csi_to_axis_0/RX_MIPI_PPI]
  connect_bd_intf_net -intf_net csi_to_axis_0_data_err [get_bd_intf_pins csi2_d_phy_rx_0/data_err] [get_bd_intf_pins csi_to_axis_0/data_err]

  # Create port connections
  connect_bd_net -net CSI_AXIS_RSTN  [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
  [get_bd_pins axis_data_fifo_0/s_axis_aresetn] \
  [get_bd_pins csi_to_axis_0/m_axis_aresetn]
  connect_bd_net -net ENABLE_STREAM  [get_bd_pins enable] \
  [get_bd_pins csi_to_axis_0/enable_in]
  connect_bd_net -net axi_int_aresetn_1  [get_bd_pins axi_int_aresetn] \
  [get_bd_pins axi_interconnect_0/ARESETN]
  connect_bd_net -net axi_vdma_0_s2mm_introut  [get_bd_pins axi_vdma_0/s2mm_introut] \
  [get_bd_pins rx_dma_int]
  connect_bd_net -net colors_mode_1  [get_bd_pins colors_mode] \
  [get_bd_pins axis_raw_demosaic_0/colors_mode]
  connect_bd_net -net csi_clk_n_1  [get_bd_pins csi_clk_n] \
  [get_bd_pins csi2_d_phy_rx_0/clk_rxn]
  connect_bd_net -net csi_clk_p_1  [get_bd_pins csi_clk_p] \
  [get_bd_pins csi2_d_phy_rx_0/clk_rxp]
  connect_bd_net -net csi_data_lp_n_1  [get_bd_pins csi_data_lp_n] \
  [get_bd_pins csi2_d_phy_rx_0/data_lp_n]
  connect_bd_net -net csi_data_lp_p_1  [get_bd_pins csi_data_lp_p] \
  [get_bd_pins csi2_d_phy_rx_0/data_lp_p]
  connect_bd_net -net csi_data_n_1  [get_bd_pins csi_data_n] \
  [get_bd_pins csi2_d_phy_rx_0/data_rxn]
  connect_bd_net -net csi_data_p_1  [get_bd_pins csi_data_p] \
  [get_bd_pins csi2_d_phy_rx_0/data_rxp]
  connect_bd_net -net ext_reset_in_1  [get_bd_pins ext_reset_in] \
  [get_bd_pins proc_sys_reset_0/ext_reset_in] \
  [get_bd_pins proc_sys_reset_1/ext_reset_in]
  connect_bd_net -net m_axi_aclk  [get_bd_pins axi_aclk] \
  [get_bd_pins axi_interconnect_0/ACLK] \
  [get_bd_pins axi_interconnect_0/M00_ACLK] \
  [get_bd_pins axi_interconnect_0/S00_ACLK] \
  [get_bd_pins axi_vdma_0/m_axi_s2mm_aclk] \
  [get_bd_pins axi_vdma_0/s_axi_lite_aclk] \
  [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] \
  [get_bd_pins axis_data_fifo_4/m_axis_aclk]
  connect_bd_net -net m_axis_aresetn_1  [get_bd_pins axi_aresetn] \
  [get_bd_pins axi_interconnect_0/M00_ARESETN] \
  [get_bd_pins axi_interconnect_0/S00_ARESETN] \
  [get_bd_pins axi_vdma_0/axi_resetn]
  connect_bd_net -net proc_sys_reset_1_peripheral_aresetn  [get_bd_pins proc_sys_reset_1/peripheral_aresetn] \
  [get_bd_pins axis_data_fifo_3/s_axis_aresetn] \
  [get_bd_pins axis_data_fifo_4/s_axis_aresetn] \
  [get_bd_pins axis_raw_demosaic_0/axis_aresetn] \
  [get_bd_pins axis_raw_unpack_0/axis_aresetn]
  connect_bd_net -net processing_clk_1  [get_bd_pins processing_clk] \
  [get_bd_pins axis_data_fifo_0/m_axis_aclk] \
  [get_bd_pins axis_data_fifo_3/s_axis_aclk] \
  [get_bd_pins axis_data_fifo_4/s_axis_aclk] \
  [get_bd_pins axis_raw_demosaic_0/axis_aclk] \
  [get_bd_pins axis_raw_unpack_0/axis_aclk] \
  [get_bd_pins proc_sys_reset_1/slowest_sync_clk]
  connect_bd_net -net ref_clk_in_1  [get_bd_pins ref_clk] \
  [get_bd_pins csi2_d_phy_rx_0/in_delay_clk]
  connect_bd_net -net s_axis_aclk_1  [get_bd_pins csi2_d_phy_rx_0/rxbyteclkhs] \
  [get_bd_pins axis_data_fifo_0/s_axis_aclk] \
  [get_bd_pins csi_to_axis_0/m_axis_aclk] \
  [get_bd_pins csi_to_axis_0/rxbyteclkhs] \
  [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: resets
proc create_hier_cell_resets { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_resets() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins

  # Create pins
  create_bd_pin -dir I -type clk axi_clk
  create_bd_pin -dir O -from 0 -to 0 -type rst axi_int_aresetn
  create_bd_pin -dir O -from 0 -to 0 -type rst axi_per_aresetn
  create_bd_pin -dir I -type rst ext_reset_in
  create_bd_pin -dir O -from 0 -to 0 -type rst peripheral_reset

  # Create instance: rst_proc_sys7_0_50M, and set properties
  set rst_proc_sys7_0_50M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_proc_sys7_0_50M ]

  # Create port connections
  connect_bd_net -net ext_reset_in_1  [get_bd_pins ext_reset_in] \
  [get_bd_pins rst_proc_sys7_0_50M/ext_reset_in]
  connect_bd_net -net rst_proc_sys7_0_50M_interconnect_aresetn  [get_bd_pins rst_proc_sys7_0_50M/interconnect_aresetn] \
  [get_bd_pins axi_int_aresetn]
  connect_bd_net -net rst_proc_sys7_0_50M_peripheral_aresetn  [get_bd_pins rst_proc_sys7_0_50M/peripheral_aresetn] \
  [get_bd_pins axi_per_aresetn]
  connect_bd_net -net rst_proc_sys7_0_50M_peripheral_reset  [get_bd_pins rst_proc_sys7_0_50M/peripheral_reset] \
  [get_bd_pins peripheral_reset]
  connect_bd_net -net slowest_sync_clk_1  [get_bd_pins axi_clk] \
  [get_bd_pins rst_proc_sys7_0_50M/slowest_sync_clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}

# Hierarchical cell: audio
proc create_hier_cell_audio { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_audio() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M00_AXI

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S00_AXI

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 Vp_Vn


  # Create pins
  create_bd_pin -dir I aud_clk
  create_bd_pin -dir I audio_clk
  create_bd_pin -dir I -type clk axi_aclk
  create_bd_pin -dir I -from 0 -to 0 -type rst axi_resetn
  create_bd_pin -dir O -type intr irq
  create_bd_pin -dir O -type intr irq1
  create_bd_pin -dir O -type intr irq_mm2s
  create_bd_pin -dir O -type intr irq_s2mm
  create_bd_pin -dir O pwm_l_out
  create_bd_pin -dir O pwm_r_out
  create_bd_pin -dir I -type rst ext_reset_in

  # Create instance: audio_formatter_0, and set properties
  set audio_formatter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:audio_formatter audio_formatter_0 ]

  # Create instance: axi_interconnect_0, and set properties
  set axi_interconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_interconnect_0 ]
  set_property -dict [list \
    CONFIG.NUM_MI {3} \
    CONFIG.NUM_SI {1} \
  ] $axi_interconnect_0


  # Create instance: axi_interconnect_1, and set properties
  set axi_interconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect axi_interconnect_1 ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {2} \
  ] $axi_interconnect_1


  # Create instance: axis_to_i2s_0, and set properties
  set axis_to_i2s_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:axis_to_i2s axis_to_i2s_0 ]

  # Create instance: clk_divider_0, and set properties
  set block_name clk_divider
  set block_cell_name clk_divider_0
  if { [catch {set clk_divider_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $clk_divider_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: clk_divider_1, and set properties
  set block_name clk_divider
  set block_cell_name clk_divider_1
  if { [catch {set clk_divider_1 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $clk_divider_1 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: clk_divider_2, and set properties
  set block_name clk_divider
  set block_cell_name clk_divider_2
  if { [catch {set clk_divider_2 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $clk_divider_2 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: i2s_receiver_0, and set properties
  set i2s_receiver_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:i2s_receiver i2s_receiver_0 ]
  set_property -dict [list \
    CONFIG.C_32BIT_LR {1} \
    CONFIG.C_DEPTH {1024} \
    CONFIG.C_DWIDTH {16} \
    CONFIG.C_IS_MASTER {0} \
  ] $i2s_receiver_0


  # Create instance: i2s_to_pwm_0, and set properties
  set i2s_to_pwm_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:i2s_to_pwm i2s_to_pwm_0 ]

  # Create instance: i2s_transmitter_0, and set properties
  set i2s_transmitter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:i2s_transmitter i2s_transmitter_0 ]
  set_property -dict [list \
    CONFIG.C_32BIT_LR {1} \
    CONFIG.C_DEPTH {1024} \
    CONFIG.C_DWIDTH {16} \
    CONFIG.C_IS_MASTER {0} \
  ] $i2s_transmitter_0


  # Create instance: xadc_wiz_0, and set properties
  set xadc_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xadc_wiz xadc_wiz_0 ]
  set_property -dict [list \
    CONFIG.ADC_CONVERSION_RATE {1000} \
    CONFIG.DCLK_FREQUENCY {150} \
    CONFIG.ENABLE_AXI4STREAM {true} \
    CONFIG.ENABLE_RESET {true} \
    CONFIG.ENABLE_VCCDDRO_ALARM {false} \
    CONFIG.ENABLE_VCCPAUX_ALARM {false} \
    CONFIG.ENABLE_VCCPINT_ALARM {false} \
    CONFIG.INTERFACE_SELECTION {None} \
    CONFIG.OT_ALARM {false} \
    CONFIG.SINGLE_CHANNEL_SELECTION {VP_VN} \
    CONFIG.USER_TEMP_ALARM {false} \
    CONFIG.VCCAUX_ALARM {false} \
    CONFIG.VCCINT_ALARM {false} \
  ] $xadc_wiz_0


  # Create instance: xlconstant_0, and set properties
  set xlconstant_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconstant_0 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0x000C} \
    CONFIG.CONST_WIDTH {16} \
  ] $xlconstant_0


  # Create instance: xlconstant_1, and set properties
  set xlconstant_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconstant_1 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0x0004} \
    CONFIG.CONST_WIDTH {16} \
  ] $xlconstant_1


  # Create instance: xlconstant_2, and set properties
  set xlconstant_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant xlconstant_2 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0x0180} \
    CONFIG.CONST_WIDTH {16} \
  ] $xlconstant_2


  # Create instance: proc_sys_reset_0, and set properties
  set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_0 ]

  # Create instance: proc_sys_reset_1, and set properties
  set proc_sys_reset_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_1 ]

  # Create instance: proc_sys_reset_2, and set properties
  set proc_sys_reset_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset proc_sys_reset_2 ]

  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins Vp_Vn] [get_bd_intf_pins xadc_wiz_0/Vp_Vn]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins M00_AXI] [get_bd_intf_pins axi_interconnect_1/M00_AXI]
  connect_bd_intf_net -intf_net S00_AXI_1 [get_bd_intf_pins S00_AXI] [get_bd_intf_pins axi_interconnect_0/S00_AXI]
  connect_bd_intf_net -intf_net S01_AXI_1 [get_bd_intf_pins audio_formatter_0/m_axi_s2mm] [get_bd_intf_pins axi_interconnect_1/S01_AXI]
  connect_bd_intf_net -intf_net audio_formatter_0_m_axi_mm2s [get_bd_intf_pins audio_formatter_0/m_axi_mm2s] [get_bd_intf_pins axi_interconnect_1/S00_AXI]
  connect_bd_intf_net -intf_net audio_formatter_0_m_axis_mm2s [get_bd_intf_pins audio_formatter_0/m_axis_mm2s] [get_bd_intf_pins i2s_transmitter_0/s_axis_aud]
  connect_bd_intf_net -intf_net axi_interconnect_0_M00_AXI [get_bd_intf_pins axi_interconnect_0/M00_AXI] [get_bd_intf_pins i2s_receiver_0/s_axi_ctrl]
  connect_bd_intf_net -intf_net axi_interconnect_0_M01_AXI [get_bd_intf_pins axi_interconnect_0/M01_AXI] [get_bd_intf_pins i2s_transmitter_0/s_axi_ctrl]
  connect_bd_intf_net -intf_net axi_interconnect_0_M02_AXI [get_bd_intf_pins audio_formatter_0/s_axi_lite] [get_bd_intf_pins axi_interconnect_0/M02_AXI]
  connect_bd_intf_net -intf_net i2s_receiver_0_m_axis_aud [get_bd_intf_pins audio_formatter_0/s_axis_s2mm] [get_bd_intf_pins i2s_receiver_0/m_axis_aud]
  connect_bd_intf_net -intf_net xadc_wiz_0_M_AXIS [get_bd_intf_pins axis_to_i2s_0/s_axis] [get_bd_intf_pins xadc_wiz_0/M_AXIS]

  # Create port connections
  connect_bd_net -net audio_clk_1  [get_bd_pins audio_clk] \
  [get_bd_pins audio_formatter_0/aud_mclk] \
  [get_bd_pins clk_divider_0/clk_in] \
  [get_bd_pins clk_divider_2/clk_in] \
  [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
  connect_bd_net -net audio_formatter_0_irq_mm2s  [get_bd_pins audio_formatter_0/irq_mm2s] \
  [get_bd_pins irq_mm2s]
  connect_bd_net -net audio_formatter_0_irq_s2mm  [get_bd_pins audio_formatter_0/irq_s2mm] \
  [get_bd_pins irq_s2mm]
  connect_bd_net -net axis_to_i2s_0_i2s_sdata  [get_bd_pins axis_to_i2s_0/i2s_sdata] \
  [get_bd_pins i2s_receiver_0/sdata_0_in]
  connect_bd_net -net clk_divider_0_clk_out  [get_bd_pins clk_divider_0/clk_out] \
  [get_bd_pins axis_to_i2s_0/i2s_bclk] \
  [get_bd_pins i2s_receiver_0/sclk_in] \
  [get_bd_pins i2s_to_pwm_0/i2s_bclk] \
  [get_bd_pins i2s_transmitter_0/sclk_in]
  connect_bd_net -net clk_divider_1_clk_out  [get_bd_pins clk_divider_1/clk_out] \
  [get_bd_pins i2s_receiver_0/aud_mclk] \
  [get_bd_pins i2s_transmitter_0/aud_mclk] \
  [get_bd_pins proc_sys_reset_1/slowest_sync_clk]
  connect_bd_net -net clk_divider_2_clk_out  [get_bd_pins clk_divider_2/clk_out] \
  [get_bd_pins axis_to_i2s_0/i2s_lrclk] \
  [get_bd_pins i2s_receiver_0/lrclk_in] \
  [get_bd_pins i2s_to_pwm_0/i2s_lrclk] \
  [get_bd_pins i2s_transmitter_0/lrclk_in]
  connect_bd_net -net clk_in_1  [get_bd_pins aud_clk] \
  [get_bd_pins clk_divider_1/clk_in] \
  [get_bd_pins proc_sys_reset_2/slowest_sync_clk]
  connect_bd_net -net ext_reset_in_1  [get_bd_pins ext_reset_in] \
  [get_bd_pins proc_sys_reset_0/ext_reset_in] \
  [get_bd_pins proc_sys_reset_1/ext_reset_in] \
  [get_bd_pins proc_sys_reset_2/ext_reset_in]
  connect_bd_net -net i2s_receiver_0_irq  [get_bd_pins i2s_receiver_0/irq] \
  [get_bd_pins irq1]
  connect_bd_net -net i2s_to_pwm_0_pwm_l_out  [get_bd_pins i2s_to_pwm_0/pwm_l_out] \
  [get_bd_pins pwm_l_out]
  connect_bd_net -net i2s_to_pwm_0_pwm_r_out  [get_bd_pins i2s_to_pwm_0/pwm_r_out] \
  [get_bd_pins pwm_r_out]
  connect_bd_net -net i2s_transmitter_0_irq  [get_bd_pins i2s_transmitter_0/irq] \
  [get_bd_pins irq]
  connect_bd_net -net i2s_transmitter_0_sdata_0_out  [get_bd_pins i2s_transmitter_0/sdata_0_out] \
  [get_bd_pins i2s_to_pwm_0/i2s_sdata]
  connect_bd_net -net m_axis_resetn_1  [get_bd_pins axi_resetn] \
  [get_bd_pins audio_formatter_0/m_axis_mm2s_aresetn] \
  [get_bd_pins audio_formatter_0/s_axi_lite_aresetn] \
  [get_bd_pins audio_formatter_0/s_axis_s2mm_aresetn] \
  [get_bd_pins axi_interconnect_0/ARESETN] \
  [get_bd_pins axi_interconnect_0/M00_ARESETN] \
  [get_bd_pins axi_interconnect_0/M01_ARESETN] \
  [get_bd_pins axi_interconnect_0/M02_ARESETN] \
  [get_bd_pins axi_interconnect_0/S00_ARESETN] \
  [get_bd_pins axi_interconnect_1/ARESETN] \
  [get_bd_pins axi_interconnect_1/M00_ARESETN] \
  [get_bd_pins axi_interconnect_1/S00_ARESETN] \
  [get_bd_pins axi_interconnect_1/S01_ARESETN] \
  [get_bd_pins axis_to_i2s_0/s_axis_aresetn] \
  [get_bd_pins i2s_receiver_0/m_axis_aud_aresetn] \
  [get_bd_pins i2s_receiver_0/s_axi_ctrl_aresetn] \
  [get_bd_pins i2s_transmitter_0/s_axi_ctrl_aresetn] \
  [get_bd_pins i2s_transmitter_0/s_axis_aud_aresetn] \
  [get_bd_pins xadc_wiz_0/m_axis_resetn]
  connect_bd_net -net proc_sys_reset_0_peripheral_aresetn  [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
  [get_bd_pins clk_divider_0/reset] \
  [get_bd_pins clk_divider_2/reset]
  connect_bd_net -net proc_sys_reset_0_peripheral_reset  [get_bd_pins proc_sys_reset_0/peripheral_reset] \
  [get_bd_pins audio_formatter_0/aud_mreset]
  connect_bd_net -net proc_sys_reset_1_peripheral_reset  [get_bd_pins proc_sys_reset_1/peripheral_reset] \
  [get_bd_pins i2s_transmitter_0/aud_mrst] \
  [get_bd_pins i2s_receiver_0/aud_mrst]
  connect_bd_net -net proc_sys_reset_2_peripheral_aresetn  [get_bd_pins proc_sys_reset_2/peripheral_aresetn] \
  [get_bd_pins clk_divider_1/reset]
  connect_bd_net -net s_axis_aclk_1  [get_bd_pins axi_aclk] \
  [get_bd_pins audio_formatter_0/m_axis_mm2s_aclk] \
  [get_bd_pins audio_formatter_0/s_axi_lite_aclk] \
  [get_bd_pins audio_formatter_0/s_axis_s2mm_aclk] \
  [get_bd_pins axi_interconnect_0/ACLK] \
  [get_bd_pins axi_interconnect_0/M00_ACLK] \
  [get_bd_pins axi_interconnect_0/M01_ACLK] \
  [get_bd_pins axi_interconnect_0/M02_ACLK] \
  [get_bd_pins axi_interconnect_0/S00_ACLK] \
  [get_bd_pins axi_interconnect_1/ACLK] \
  [get_bd_pins axi_interconnect_1/M00_ACLK] \
  [get_bd_pins axi_interconnect_1/S00_ACLK] \
  [get_bd_pins axi_interconnect_1/S01_ACLK] \
  [get_bd_pins axis_to_i2s_0/s_axis_aclk] \
  [get_bd_pins i2s_receiver_0/m_axis_aud_aclk] \
  [get_bd_pins i2s_receiver_0/s_axi_ctrl_aclk] \
  [get_bd_pins i2s_to_pwm_0/clk_in] \
  [get_bd_pins i2s_transmitter_0/s_axi_ctrl_aclk] \
  [get_bd_pins i2s_transmitter_0/s_axis_aud_aclk] \
  [get_bd_pins xadc_wiz_0/m_axis_aclk] \
  [get_bd_pins xadc_wiz_0/s_axis_aclk]
  connect_bd_net -net xlconstant_0_dout  [get_bd_pins xlconstant_0/dout] \
  [get_bd_pins clk_divider_0/divider]
  connect_bd_net -net xlconstant_1_dout  [get_bd_pins xlconstant_1/dout] \
  [get_bd_pins clk_divider_1/divider]
  connect_bd_net -net xlconstant_2_dout  [get_bd_pins xlconstant_2/dout] \
  [get_bd_pins clk_divider_2/divider]

  # Restore current instance
  current_bd_instance $oldCurInst
}


# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set GPIO_1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 GPIO_1 ]

  set Vp_Vn [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_analog_io_rtl:1.0 Vp_Vn ]

# #TE_MOD#   set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

# #TE_MOD#   set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]


  # Create ports
  set PWM_L [ create_bd_port -dir O PWM_L ]
  set PWM_R [ create_bd_port -dir O PWM_R ]
  set csi_c_clk_n [ create_bd_port -dir I csi_c_clk_n ]
  set csi_c_clk_p [ create_bd_port -dir I csi_c_clk_p ]
  set csi_d_lp_n [ create_bd_port -dir I -from 0 -to 0 csi_d_lp_n ]
  set csi_d_lp_p [ create_bd_port -dir I -from 0 -to 0 csi_d_lp_p ]
  set csi_d_n [ create_bd_port -dir I -from 1 -to 0 csi_d_n ]
  set csi_d_p [ create_bd_port -dir I -from 1 -to 0 csi_d_p ]
  set hdmi_clk_n [ create_bd_port -dir O hdmi_clk_n ]
  set hdmi_clk_p [ create_bd_port -dir O hdmi_clk_p ]
  set hdmi_data_n [ create_bd_port -dir O -from 2 -to 0 hdmi_data_n ]
  set hdmi_data_p [ create_bd_port -dir O -from 2 -to 0 hdmi_data_p ]

  # Create instance: audio
  create_hier_cell_audio [current_bd_instance .] audio

  # Create instance: axi_reg32_0, and set properties
  set axi_reg32_0 [ create_bd_cell -type ip -vlnv trenz.biz:user:axi_reg32 axi_reg32_0 ]
  set_property -dict [list \
    CONFIG.C_NUM_RO_REG {1} \
    CONFIG.C_NUM_WR_REG {1} \
  ] $axi_reg32_0


  # Create instance: proc_sys7_0_axi_periph, and set properties
  set proc_sys7_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect proc_sys7_0_axi_periph ]
  set_property -dict [list \
    CONFIG.NUM_MI {6} \
    CONFIG.SYNCHRONIZATION_STAGES {2} \
  ] $proc_sys7_0_axi_periph


  # Create instance: processing_system7_0, and set properties
  set processing_system7_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0 ]
# #TE_MOD#_Add next line#
  apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1"}  [get_bd_cells processing_system7_0]
# #TE_MOD#_Add next line#
  set tcl_pr_ext [];if { [catch {set tcl_pr_ext [glob -join -dir ${TE::BOARDDEF_PATH}/preset_extension/ *_preset.tcl]}] } {};foreach preset_ext $tcl_pr_ext { source  $preset_ext};
# #TE_MOD#   set_property -dict [list \
# #TE_MOD#   ] $processing_system7_0

# #TE_MOD#     CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666626} \
# #TE_MOD#     CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
# #TE_MOD#     CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158729} \
# #TE_MOD#     CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {10.000000} \
# #TE_MOD#     CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
# #TE_MOD#     CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {119.999985} \
# #TE_MOD#     CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {16.216213} \
# #TE_MOD#     CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {199.999985} \
# #TE_MOD#     CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {12.244897} \
# #TE_MOD#     CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {199.999985} \
# #TE_MOD#     CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {199.999985} \
# #TE_MOD#     CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {99.999992} \
# #TE_MOD#     CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
# #TE_MOD#     CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
# #TE_MOD#     CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
# #TE_MOD#     CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {99.999992} \
# #TE_MOD#     CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_CLK0_FREQ {119999985} \
# #TE_MOD#     CONFIG.PCW_CLK1_FREQ {16216213} \
# #TE_MOD#     CONFIG.PCW_CLK2_FREQ {199999985} \
# #TE_MOD#     CONFIG.PCW_CLK3_FREQ {12244897} \
# #TE_MOD#     CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.33333} \
# #TE_MOD#     CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} \
# #TE_MOD#     CONFIG.PCW_EN_CLK0_PORT {1} \
# #TE_MOD#     CONFIG.PCW_EN_CLK1_PORT {1} \
# #TE_MOD#     CONFIG.PCW_EN_CLK2_PORT {1} \
# #TE_MOD#     CONFIG.PCW_EN_CLK3_PORT {1} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_CD_SDIO1 {0} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_GPIO {1} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_SDIO1 {0} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_TTC0 {1} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_TTC1 {1} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_WDT {1} \
# #TE_MOD#     CONFIG.PCW_EN_EMIO_WP_SDIO1 {0} \
# #TE_MOD#     CONFIG.PCW_EN_GPIO {1} \
# #TE_MOD#     CONFIG.PCW_EN_I2C1 {1} \
# #TE_MOD#     CONFIG.PCW_EN_QSPI {1} \
# #TE_MOD#     CONFIG.PCW_EN_SDIO1 {1} \
# #TE_MOD#     CONFIG.PCW_EN_TTC0 {1} \
# #TE_MOD#     CONFIG.PCW_EN_TTC1 {1} \
# #TE_MOD#     CONFIG.PCW_EN_UART1 {1} \
# #TE_MOD#     CONFIG.PCW_EN_USB0 {1} \
# #TE_MOD#     CONFIG.PCW_EN_WDT {1} \
# #TE_MOD#     CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
# #TE_MOD#     CONFIG.PCW_FCLK_CLK1_BUF {TRUE} \
# #TE_MOD#     CONFIG.PCW_FCLK_CLK2_BUF {TRUE} \
# #TE_MOD#     CONFIG.PCW_FCLK_CLK3_BUF {TRUE} \
# #TE_MOD#     CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {120} \
# #TE_MOD#     CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {16.384} \
# #TE_MOD#     CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {200} \
# #TE_MOD#     CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {12.228} \
# #TE_MOD#     CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_FPGA_FCLK1_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_FPGA_FCLK2_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_FPGA_FCLK3_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_GPIO_EMIO_GPIO_IO {24} \
# #TE_MOD#     CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {24} \
# #TE_MOD#     CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
# #TE_MOD#     CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_I2C1_GRP_INT_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_I2C1_I2C1_IO {MIO 48 .. 49} \
# #TE_MOD#     CONFIG.PCW_I2C1_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_I2C_PERIPHERAL_FREQMHZ {111.111107} \
# #TE_MOD#     CONFIG.PCW_I2C_RESET_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_IRQ_F2P_INTR {1} \
# #TE_MOD#     CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_0_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_0_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_10_PULLUP {disabled} \
# #TE_MOD#     CONFIG.PCW_MIO_10_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_11_PULLUP {disabled} \
# #TE_MOD#     CONFIG.PCW_MIO_11_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_12_PULLUP {disabled} \
# #TE_MOD#     CONFIG.PCW_MIO_12_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_13_PULLUP {disabled} \
# #TE_MOD#     CONFIG.PCW_MIO_13_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_14_PULLUP {disabled} \
# #TE_MOD#     CONFIG.PCW_MIO_14_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_15_PULLUP {disabled} \
# #TE_MOD#     CONFIG.PCW_MIO_15_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_1_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_1_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_28_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_28_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_29_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_29_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_2_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_30_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_30_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_31_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_31_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_32_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_32_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_33_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_33_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_34_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_34_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_35_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_35_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_36_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_36_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_37_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_37_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_38_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_38_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_39_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_39_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_3_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_48_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_48_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_49_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_49_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_4_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_52_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_52_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_53_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_53_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_5_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_6_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_7_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_8_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_MIO_9_PULLUP {enabled} \
# #TE_MOD#     CONFIG.PCW_MIO_9_SLEW {slow} \
# #TE_MOD#     CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#USB Reset#UART 1#UART 1#SD 1#SD 1#SD 1#SD 1#SD 1#SD 1#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#USB\
# #TE_MOD# 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#I2C 1#I2C 1#Unbonded#Unbonded#GPIO#GPIO} \
# #TE_MOD#     CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#reset#tx#rx#data[0]#cmd#clk#data[1]#data[2]#data[3]#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#data[4]#dir#stp#nxt#data[0]#data[1]#data[2]#data[3]#clk#data[5]#data[6]#data[7]#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#Unbonded#scl#sda#Unbonded#Unbonded#gpio[52]#gpio[53]}\
# #TE_MOD# \
# #TE_MOD#     CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 3.3V} \
# #TE_MOD#     CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_QSPI_GRP_IO1_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
# #TE_MOD#     CONFIG.PCW_QSPI_GRP_SS1_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200} \
# #TE_MOD#     CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
# #TE_MOD#     CONFIG.PCW_SD1_GRP_CD_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_SD1_GRP_CD_IO {0} \
# #TE_MOD#     CONFIG.PCW_SD1_GRP_POW_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_SD1_GRP_WP_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_SD1_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_SD1_SD1_IO {MIO 10 .. 15} \
# #TE_MOD#     CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {100} \
# #TE_MOD#     CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
# #TE_MOD#     CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
# #TE_MOD#     CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {32} \
# #TE_MOD#     CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
# #TE_MOD#     CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_TTC0_TTC0_IO {EMIO} \
# #TE_MOD#     CONFIG.PCW_TTC1_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_TTC1_TTC1_IO {EMIO} \
# #TE_MOD#     CONFIG.PCW_TTC_PERIPHERAL_FREQMHZ {50} \
# #TE_MOD#     CONFIG.PCW_UART1_GRP_FULL_ENABLE {0} \
# #TE_MOD#     CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_UART1_UART1_IO {MIO 8 .. 9} \
# #TE_MOD#     CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
# #TE_MOD#     CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
# #TE_MOD#     CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333252} \
# #TE_MOD#     CONFIG.PCW_UIPARAM_DDR_BL {8} \
# #TE_MOD#     CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)} \
# #TE_MOD#     CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
# #TE_MOD#     CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_USB0_RESET_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_USB0_RESET_IO {MIO 7} \
# #TE_MOD#     CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
# #TE_MOD#     CONFIG.PCW_USB_RESET_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_USB_RESET_SELECT {Share reset pin} \
# #TE_MOD#     CONFIG.PCW_USE_DMA0 {0} \
# #TE_MOD#     CONFIG.PCW_USE_DMA1 {0} \
# #TE_MOD#     CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
# #TE_MOD#     CONFIG.PCW_USE_S_AXI_HP0 {1} \
# #TE_MOD#     CONFIG.PCW_USE_S_AXI_HP1 {1} \
# #TE_MOD#     CONFIG.PCW_USE_S_AXI_HP2 {1} \
# #TE_MOD#     CONFIG.PCW_WDT_PERIPHERAL_ENABLE {1} \
# #TE_MOD#     CONFIG.PCW_WDT_WDT_IO {EMIO} \
# #TE_MOD# #Empty Line

  # Create instance: resets
  create_hier_cell_resets [current_bd_instance .] resets

  # Create instance: video_in
  create_hier_cell_video_in [current_bd_instance .] video_in

  # Create instance: video_out
  create_hier_cell_video_out [current_bd_instance .] video_out

  # Create instance: xlconcat_0, and set properties
  set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat xlconcat_0 ]
  set_property CONFIG.NUM_PORTS {6} $xlconcat_0


  # Create instance: xlslice_0, and set properties
  set xlslice_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice xlslice_0 ]
  set_property -dict [list \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
    CONFIG.DIN_WIDTH {32} \
  ] $xlslice_0


  # Create instance: xlslice_1, and set properties
  set xlslice_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice xlslice_1 ]
  set_property -dict [list \
    CONFIG.DIN_FROM {1} \
    CONFIG.DIN_TO {1} \
    CONFIG.DIN_WIDTH {32} \
    CONFIG.DOUT_WIDTH {1} \
  ] $xlslice_1


  # Create interface connections
  connect_bd_intf_net -intf_net Vp_Vn_1 [get_bd_intf_ports Vp_Vn] [get_bd_intf_pins audio/Vp_Vn]
  connect_bd_intf_net -intf_net audio_M00_AXI [get_bd_intf_pins audio/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP2]
  connect_bd_intf_net -intf_net proc_sys7_0_axi_periph_M00_AXI [get_bd_intf_pins proc_sys7_0_axi_periph/M00_AXI] [get_bd_intf_pins video_out/VDMA_AXI]
  connect_bd_intf_net -intf_net proc_sys7_0_axi_periph_M01_AXI [get_bd_intf_pins proc_sys7_0_axi_periph/M01_AXI] [get_bd_intf_pins video_in/VDMA_AXI]
  connect_bd_intf_net -intf_net proc_sys7_0_axi_periph_M02_AXI [get_bd_intf_pins audio/S00_AXI] [get_bd_intf_pins proc_sys7_0_axi_periph/M02_AXI]
  connect_bd_intf_net -intf_net proc_sys7_0_axi_periph_M03_AXI [get_bd_intf_pins axi_reg32_0/S_AXI] [get_bd_intf_pins proc_sys7_0_axi_periph/M03_AXI]
  connect_bd_intf_net -intf_net proc_sys7_0_axi_periph_M04_AXI [get_bd_intf_pins proc_sys7_0_axi_periph/M04_AXI] [get_bd_intf_pins video_out/VTC_AXI]
  connect_bd_intf_net -intf_net proc_sys7_0_axi_periph_M05_AXI [get_bd_intf_pins proc_sys7_0_axi_periph/M05_AXI] [get_bd_intf_pins video_out/CLKWIZ_AXI]
# #TE_MOD#   connect_bd_intf_net -intf_net processing_system7_0_DDR [get_bd_intf_ports DDR] [get_bd_intf_pins processing_system7_0/DDR]
# #TE_MOD#   connect_bd_intf_net -intf_net processing_system7_0_FIXED_IO [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins processing_system7_0/FIXED_IO]
  connect_bd_intf_net -intf_net processing_system7_0_GPIO_0 [get_bd_intf_ports GPIO_1] [get_bd_intf_pins processing_system7_0/GPIO_0]
  connect_bd_intf_net -intf_net processing_system7_0_M_AXI_GP0 [get_bd_intf_pins proc_sys7_0_axi_periph/S00_AXI] [get_bd_intf_pins processing_system7_0/M_AXI_GP0]
  connect_bd_intf_net -intf_net video_in_M00_AXI [get_bd_intf_pins processing_system7_0/S_AXI_HP1] [get_bd_intf_pins video_in/VIDEO_IN_AXI]
  connect_bd_intf_net -intf_net video_out_M00_AXI [get_bd_intf_pins processing_system7_0/S_AXI_HP0] [get_bd_intf_pins video_out/VIDEO_OUT_AXI]

  # Create port connections
  connect_bd_net -net audio_irq  [get_bd_pins audio/irq] \
  [get_bd_pins xlconcat_0/In2]
  connect_bd_net -net audio_irq1  [get_bd_pins audio/irq1] \
  [get_bd_pins xlconcat_0/In5]
  connect_bd_net -net audio_irq_mm2s  [get_bd_pins audio/irq_mm2s] \
  [get_bd_pins xlconcat_0/In3]
  connect_bd_net -net audio_irq_s2mm  [get_bd_pins audio/irq_s2mm] \
  [get_bd_pins xlconcat_0/In4]
  connect_bd_net -net audio_pwm_l_out  [get_bd_pins audio/pwm_l_out] \
  [get_bd_ports PWM_L]
  connect_bd_net -net audio_pwm_r_out  [get_bd_pins audio/pwm_r_out] \
  [get_bd_ports PWM_R]
  connect_bd_net -net axi_reg32_0_WR0  [get_bd_pins axi_reg32_0/WR0] \
  [get_bd_pins xlslice_0/Din] \
  [get_bd_pins xlslice_1/Din]
  connect_bd_net -net csi_c_clk_n_1  [get_bd_ports csi_c_clk_n] \
  [get_bd_pins video_in/csi_clk_n]
  connect_bd_net -net csi_c_clk_p_1  [get_bd_ports csi_c_clk_p] \
  [get_bd_pins video_in/csi_clk_p]
  connect_bd_net -net csi_d_lp_n_1  [get_bd_ports csi_d_lp_n] \
  [get_bd_pins video_in/csi_data_lp_n]
  connect_bd_net -net csi_d_lp_p_1  [get_bd_ports csi_d_lp_p] \
  [get_bd_pins video_in/csi_data_lp_p]
  connect_bd_net -net csi_d_n_1  [get_bd_ports csi_d_n] \
  [get_bd_pins video_in/csi_data_n]
  connect_bd_net -net csi_d_p_1  [get_bd_ports csi_d_p] \
  [get_bd_pins video_in/csi_data_p]
  connect_bd_net -net processing_system7_0_FCLK_CLK0  [get_bd_pins processing_system7_0/FCLK_CLK0] \
  [get_bd_pins audio/axi_aclk] \
  [get_bd_pins axi_reg32_0/s_axi_aclk] \
  [get_bd_pins proc_sys7_0_axi_periph/ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/M00_ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/M01_ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/M02_ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/M03_ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/M04_ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/M05_ACLK] \
  [get_bd_pins proc_sys7_0_axi_periph/S00_ACLK] \
  [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
  [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK] \
  [get_bd_pins processing_system7_0/S_AXI_HP1_ACLK] \
  [get_bd_pins processing_system7_0/S_AXI_HP2_ACLK] \
  [get_bd_pins resets/axi_clk] \
  [get_bd_pins video_in/axi_aclk] \
  [get_bd_pins video_in/processing_clk] \
  [get_bd_pins video_out/axi_aclk]
  connect_bd_net -net processing_system7_0_FCLK_CLK1  [get_bd_pins processing_system7_0/FCLK_CLK1] \
  [get_bd_pins audio/aud_clk]
  connect_bd_net -net processing_system7_0_FCLK_CLK2  [get_bd_pins processing_system7_0/FCLK_CLK2] \
  [get_bd_pins video_in/ref_clk] \
  [get_bd_pins video_out/ref_clk]
  connect_bd_net -net processing_system7_0_FCLK_CLK3  [get_bd_pins processing_system7_0/FCLK_CLK3] \
  [get_bd_pins audio/audio_clk]
  connect_bd_net -net processing_system7_0_FCLK_RESET0_N  [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
  [get_bd_pins resets/ext_reset_in] \
  [get_bd_pins video_in/ext_reset_in] \
  [get_bd_pins video_out/ext_reset_in] \
  [get_bd_pins audio/ext_reset_in]
  connect_bd_net -net rst_proc_sys7_0_50M_interconnect_aresetn  [get_bd_pins resets/axi_int_aresetn] \
  [get_bd_pins proc_sys7_0_axi_periph/ARESETN] \
  [get_bd_pins video_in/axi_int_aresetn] \
  [get_bd_pins video_out/axi_int_aresetn]
  connect_bd_net -net rst_proc_sys7_0_50M_peripheral_aresetn  [get_bd_pins resets/axi_per_aresetn] \
  [get_bd_pins audio/axi_resetn] \
  [get_bd_pins axi_reg32_0/s_axi_aresetn] \
  [get_bd_pins proc_sys7_0_axi_periph/M00_ARESETN] \
  [get_bd_pins proc_sys7_0_axi_periph/M01_ARESETN] \
  [get_bd_pins proc_sys7_0_axi_periph/M02_ARESETN] \
  [get_bd_pins proc_sys7_0_axi_periph/M03_ARESETN] \
  [get_bd_pins proc_sys7_0_axi_periph/M04_ARESETN] \
  [get_bd_pins proc_sys7_0_axi_periph/M05_ARESETN] \
  [get_bd_pins proc_sys7_0_axi_periph/S00_ARESETN] \
  [get_bd_pins video_in/axi_aresetn] \
  [get_bd_pins video_out/axi_per_aresetn]
  connect_bd_net -net video_in_rx_dma_int  [get_bd_pins video_in/rx_dma_int] \
  [get_bd_pins xlconcat_0/In1]
  connect_bd_net -net video_out_hdmi_clk_n  [get_bd_pins video_out/hdmi_clk_n] \
  [get_bd_ports hdmi_clk_n]
  connect_bd_net -net video_out_hdmi_clk_p  [get_bd_pins video_out/hdmi_clk_p] \
  [get_bd_ports hdmi_clk_p]
  connect_bd_net -net video_out_hdmi_data_n  [get_bd_pins video_out/hdmi_data_n] \
  [get_bd_ports hdmi_data_n]
  connect_bd_net -net video_out_hdmi_data_p  [get_bd_pins video_out/hdmi_data_p] \
  [get_bd_ports hdmi_data_p]
  connect_bd_net -net video_out_mm2s_introut  [get_bd_pins video_out/tx_dma_int] \
  [get_bd_pins xlconcat_0/In0]
  connect_bd_net -net xlconcat_0_dout  [get_bd_pins xlconcat_0/dout] \
  [get_bd_pins processing_system7_0/IRQ_F2P]
  connect_bd_net -net xlslice_0_Dout  [get_bd_pins xlslice_0/Dout] \
  [get_bd_pins video_in/enable]
  connect_bd_net -net xlslice_1_Dout  [get_bd_pins xlslice_1/Dout] \
  [get_bd_pins video_in/colors_mode]

  # Create address segments
  assign_bd_address -offset 0x43C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs audio/audio_formatter_0/s_axi_lite/reg0] -force
  assign_bd_address -offset 0x43C30000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_reg32_0/S_AXI/S_AXI_reg] -force
  assign_bd_address -offset 0x43000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs video_in/axi_vdma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x43010000 -range 0x00010000 -with_name SEG_axi_vdma_0_Reg_1 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs video_out/axi_vdma_0/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x43C40000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs video_out/clk_wiz_1/s_axi_lite/Reg] -force
  assign_bd_address -offset 0x43C10000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs audio/i2s_receiver_0/s_axi_ctrl/Reg] -force
  assign_bd_address -offset 0x43C20000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs audio/i2s_transmitter_0/s_axi_ctrl/Reg] -force
  assign_bd_address -offset 0x43C50000 -range 0x00010000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs video_out/v_tc_0/ctrl/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces audio/audio_formatter_0/m_axi_mm2s] [get_bd_addr_segs processing_system7_0/S_AXI_HP2/HP2_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces audio/audio_formatter_0/m_axi_s2mm] [get_bd_addr_segs processing_system7_0/S_AXI_HP2/HP2_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces video_in/axi_vdma_0/Data_S2MM] [get_bd_addr_segs processing_system7_0/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces video_out/axi_vdma_0/Data_MM2S] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""



