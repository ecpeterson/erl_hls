# --------------------------------------------------------------------
# --   *****************************
# --   *   Trenz Electronic GmbH   *
# --   *   Beendorfer Str. 23      *
# --   *   32609 Hüllhorst         *
# --   *   Germany                 *
# --   *****************************
# --------------------------------------------------------------------
# -- $Initial Author: Hartfiel, John $
# -- $Email: j.hartfiel@trenz-electronic.de $
# --------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------------
# -- Change history  :
# ------------------|---------|---------|----------------------------------------------------------------------
# -- Date           | Author  |Critical | Description
# ------------------|---------|---------|----------------------------------------------------------------------
# --                |         |         |
# --                |         |         |
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/12/02     |JH       |         |- vitis unified WIP (copy of current vitis script which is used on vitis classic)
# ------------------|---------|---------|----------------------------------------------------------------------
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/08/16     |JH       |         |- bugfix domain creation (for 23.1)
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/08/15     |JH       |         |- translate_processorname linux update, platform_domains,  create_linux_source currently deactivated(device depended changes needed)
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/08/14     |JH       |         |- sync 22.2 and 23.1
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/08/10     |MK       |         |- versal bugfix
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/07/24     |JH       |         |- new table history style
# --                |         |         |- bugfix default domain name
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/05/30     |JH       |         |- bugfix get_domain_name,
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/05/27     |JH       |         |- start rework get_domain_name, add translate_processorname
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/05/27     |JH       |         | - - start add versal support to check_system_type, platform_domains,platform_create,app_create
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/01     |JH       |         | - modified app_list, app_build, app_delete, app_clean which use app list from vitis
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/03/02     |JH       |         |- modfy platform_domains --> read compiler flags before set, renamed zynqmp_fsbl and zynqmp_pmufw to fsbl and pmufw,
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2020/01/11     |JH       |         | - add app_list, mod app_create
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2020/01/06     |JH       |         | - renamed platform lists to domain lists, rework, add new bsp csv option
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2020/05/06     |JH       |         | - platform_domains --> extra symbols for FSBL, PMUS possible
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2020/05/06     |JH       |         | - platform_domains,get_domain_name,bsp_modify --> workaround in case domain name is larger than 20 char --> make problem only on 841 at the moment.
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2020/04/01     |JH       |         | - compile fsbl_app
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2020/01/14     |JH       |         | - add possibility of linux domain and  copy files from prebuilts to the workspace (currently more beta)
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2019/12/16     |JH       |         | - microblaze support, bugfixes, multiple domains on platfrom csv
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2019/12/06     |JH       |         | - zynq support
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2019/12/01     |JH       |         | - initial release with zynqMP support
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2019/12/11     |JH       |         |- add Zynq support
# ------------------|---------|---------|----------------------------------------------------------------------

# ------------------------------------------
# -- $Date:  | $Author: Hartfiel, John
# -- 
# ------------------------------------------
# -- $Date:  | $Author: Hartfiel, John
# -- 
# ------------------------------------------
# -- $Date:  | $Author: Hartfiel, John
# -- 
# ------------------------------------------
# -- $Date: 0000/00/00  | $Author:
# -- - 
# --------------------------------------------------------------------
# --------------------------------------------------------------------
# syntx see ug1400-vitis-embedded.pdf
# --------------------------------------------------------------------
namespace eval ::TE {
  namespace eval VITIS_U {
    set GEN_ISSUES [list]
    set CSV_ISSUES [list]
    set SW_APPLIST ""
    set SCRIPT_PATH ../../scripts
    set LIB_PATH ../../sw_lib
    set ID UNKOWN
    set SERIESNAME UNKOWN
    set WORKSPACE_SDK_PATH ../../workspace/sdk
    #will be set with platform_create
    set SYSTEM zynqMP
    # set SYSTEM zynq
    # set SYSTEM microblaze
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # TE HSI variablen declaration
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # finished TE HSI variablen declaration
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # hsi hw functions
    # -----------------------------------------------------------------------------------------------------------------------------------------
    proc create_linux_source { domainname } { 
      if {$TE::VITIS_U::SYSTEM eq "zynq"} {
        puts "Warning: (TE) Create Linux sources currently not implemented for $TE::VITIS_U::SYSTEM"
      } elseif {$TE::VITIS_U::SYSTEM eq "zynqMP"} {
        puts "Warning: (TE) Create Linux sources currently not implemented for $TE::VITIS_U::SYSTEM"
      } elseif {$TE::VITIS_U::SYSTEM eq "versal"} {
        puts "Warning: (TE) Create Linux sources currently not implemented for $TE::VITIS_U::SYSTEM"
      } elseif {$TE::VITIS_U::SYSTEM eq "microblaze"} {
        puts "Warning: (TE) Create Linux sources currently not implemented for $TE::VITIS_U::SYSTEM"
      } else {
        puts "Error:(TE) linux file ${TE::PRODID} failed: unknown system type $TE::VITIS_U::SYSTEM"
      }
    }
    
    
    proc set_workspace {} { 
      setws ${TE::WORKSPACE_SDK_PATH}
      repo -set ${TE::LIB_PATH}
      repo -scan
    }
    proc check_system_type {{name NA}} {
      if {[string match "NA" $name]} {
        foreach sw_platlist_line $TE::SDEF::SW_DOMLIST {
          if {[catch {
            if { [lindex $sw_platlist_line ${TE::SDEF::D_ID}] ne "id" } {
              set d_proc [lindex $sw_platlist_line ${TE::SDEF::D_PROC}]
              #todo list of possible systems
              if {[string match "a9*" $d_proc]} {
                set TE::VITIS_U::SYSTEM zynq  
              } elseif {[string match "a53*" $d_proc]} {
                set TE::VITIS_U::SYSTEM zynqMP  
              } elseif {[string match "a72*" $d_proc] || [string match "pmc*" $d_proc] || [string match "psm*" $d_proc]} {
                set TE::VITIS_U::SYSTEM versal  
              } elseif {[string match "microblaze*" $d_proc]} {
                set TE::VITIS_U::SYSTEM microblaze  
              } else {
                 puts "Error:(TE) platform ${TE::PRODID}  (TE::VITIVS::check_system_type check):system type failed: unknown processor type $d_proc"
              }
            }
          } result]} {
            puts  "Error:(TE) Script (TE::VITIS_U::check_system_type) failed at $sw_platlist_line with: $result."
            lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::check_system_type) failed at $sw_platlist_line"
          }
        }
      } else {
        set TE::VITIS_U::SYSTEM $name  
      }
    
    }
    proc translate_processorname { proc_name} {   
      set d_proc $proc_name
      # if {[string match "a9-*" $proc_name]} { 
        # set name "ps7_cortex[string map {"-" "_"} $proc_name]"
      # } elseif {[string match "a53-*" $proc_name]} {
        # set name "psu_cortex[string map {"-" "_"} $proc_name]"
      # } elseif {[string match "a72-*" $proc_name]} {
        # set name "versal_cips_0_pspmc_0_psv_cortex[string map {"-" "_"} $proc_name]"
      # } elseif {[string match "pmc-*" $proc_name]} {
        # set name "versal_cips_0_pspmc_0_psv_[string map {"-" "_"} $proc_name]"
      # } elseif {[string match "psm-*" $proc_name]} {
        # set name "versal_cips_0_pspmc_0_psv_[string map {"-" "_"} $proc_name]"
      # } else {
         # #use as it is --> for microblaze for example 
      # }
      if {[string match "a9-*" $d_proc]} { 
        set d_proc "ps7_cortex[string map {"-" "_"} $d_proc]"
      } elseif {[string match "a9" $d_proc]} {
        #for linux domain
        set d_proc "ps7_cortex${d_proc}"
      } elseif {[string match "a53-*" $d_proc]} {
        set d_proc "psu_cortex[string map {"-" "_"} $d_proc]"
      } elseif {[string match "a53" $d_proc]} {
        #for linux domain
        set d_proc "psu_cortex${d_proc}"
      } elseif {[string match "a72-*" $d_proc]} {
        set d_proc "versal_cips_0_pspmc_0_psv_cortex[string map {"-" "_"} $d_proc]"
      } elseif {[string match "a72" $d_proc]} {
        #for linux domain
        set d_proc "psv_cortex${d_proc}"
      } elseif {[string match "pmc-*" $d_proc]} {
        set d_proc "versal_cips_0_pspmc_0_psv_[string map {"-" "_"} $d_proc]"
      } elseif {[string match "pmc" $d_proc]} {
        set d_proc "versal_cips_0_pspmc_0_psv_${d_proc}"
      } elseif {[string match "psm-*" $d_proc]} {
        set d_proc "versal_cips_0_pspmc_0_psv_[string map {"-" "_"} $d_proc]"
      } elseif {[string match "psm" $d_proc]} {
        set d_proc "versal_cips_0_pspmc_0_psv_${d_proc}"
      } else {
         #use as it is --> for microblaze for example 
      }      
      
      return $d_proc
    }
    
    proc platform_create {} {    
      #create platform project
     
      foreach sw_platlist_line $TE::SDEF::SW_DOMLIST {
        if {[catch {
          # if { [lindex $sw_platlist_line ${TE::SDEF::D_ID}] ne "id" } {}
          #generate platform only one time, use domains to generate additional domains
          if { [lindex $sw_platlist_line ${TE::SDEF::D_ID}] eq "0" } {
            set d_os [lindex $sw_platlist_line ${TE::SDEF::D_OS}]
            set d_proc [TE::VITIS_U::translate_processorname [lindex $sw_platlist_line ${TE::SDEF::D_PROC}]]
            
            # set d_proc [lindex $sw_platlist_line ${TE::SDEF::D_PROC}]
            # if {[string match "a9-*" $d_proc]} { 
              # set d_proc "ps7_cortex[string map {"-" "_"} $d_proc]"
            # } elseif {[string match "a53-*" $d_proc]} {
              # set d_proc "psu_cortex[string map {"-" "_"} $d_proc]"
            # } elseif {[string match "a72-*" $d_proc]} {
              # set d_proc "versal_cips_0_pspmc_0_psv_cortex[string map {"-" "_"} $d_proc]"
            # } elseif {[string match "pmc-*" $d_proc]} {
              # set d_proc "versal_cips_0_pspmc_0_psv_[string map {"-" "_"} $d_proc]"
            # } elseif {[string match "psm-*" $d_proc]} {
              # set d_proc "versal_cips_0_pspmc_0_psv_[string map {"-" "_"} $d_proc]"
            # } else {
               # #use as it is --> for microblaze for example 
            # }
            set xsafiles [glob -join -dir ${TE::WORKSPACE_SDK_PATH} *.xsa]
            set xsafile [lindex $xsafiles 0]
            
            platform create -name ${TE::PRODID} -hw ${xsafile} -proc $d_proc -os $d_os -out ${TE::WORKSPACE_SDK_PATH}
            platform write
            platform read ${TE::WORKSPACE_SDK_PATH}/${TE::PRODID}/platform.spr

          }
        } result]} {
          puts  "Error:(TE)  Script (TE::VITIS_U::platform_create) with platform ${TE::PRODID} failed at $sw_platlist_line with: $result."
          lappend TE::VITIS_U::CSV_ISSUES "Error:(TE)  Script (TE::VITIS_U::platform_create) with platform ${TE::PRODID} failed at $sw_platlist_line"
        }
      }
    }

    proc platform_domains {} {
      if {[catch {
        #predefined for zynqMP
        # --> add or remove:  todo 
        # platform config -remove-boot-bsp
        # platform write
        # platform config -create-boot-bsp
        if {[catch {set xsafiles [glob -join -dir ${TE::WORKSPACE_SDK_PATH}/${TE::PRODID}/hw/ *.xsa]} ]} {
          puts "Error:(TE) platform ${TE::PRODID} failed: .xsa does not exist in ${TE::WORKSPACE_SDK_PATH}/${TE::PRODID}/hw/."
        }
        set xsafile [lindex $xsafiles 0]
        
        
        platform active ${TE::PRODID}
        
        if {$TE::VITIS_U::SYSTEM eq "zynq"} {
          domain active {zynq_fsbl}
          ::scw::get_hw_path
          ::scw::regenerate_psinit ${xsafile}
          ::scw::get_mss_path
          #extra compiler flags for fsbl
          foreach sw_applist_line $TE::SDEF::SW_APPLIST {
            if {[catch {
              if { [lindex $sw_applist_line ${TE::SDEF::ID}] ne "id" } {
                if { [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "FSBL"} {
                  if { [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ne "NA" } { 
                    set tmp [split [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ","]
                    set c_flags "[platform config -extra-compiler-flags fsbl]"
                    foreach symb $tmp {
                      set c_flags "$c_flags -D$symb"
                    }
                    platform fsbl -extra-compiler-flags  ${c_flags}
                    # puts "Test|$c_flags|||"
                    # platform write
                    # platform fsbl -extra-linker-flags {}
                  }
                }
              }
            } result]} {
            puts "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_applist_line with: $result."
            lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_applist_line"
            }
          }
          domain active {standalone_domain}
          ::scw::get_hw_path
          ::scw::regenerate_psinit ${xsafile}
          ::scw::get_mss_path
        } elseif {$TE::VITIS_U::SYSTEM eq "zynqMP"} {
          domain active {zynqmp_fsbl}
          ::scw::get_hw_path
          ::scw::regenerate_psinit ${xsafile}
          ::scw::get_mss_path
          #extra compiler flags for fsbl
          foreach sw_applist_line $TE::SDEF::SW_APPLIST {
            if {[catch {
              if { [lindex $sw_applist_line ${TE::SDEF::ID}] ne "id" } {
                if { [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "FSBL"} {
                  if { [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ne "NA" } { 
                    set tmp [split [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ","]
                    set c_flags "[platform config -extra-compiler-flags fsbl]"
                    foreach symb $tmp {
                      set c_flags "$c_flags -D$symb"
                    }
                    # platform zynqmp_fsbl -extra-compiler-flags  ${c_flags}
                    platform fsbl -extra-compiler-flags  ${c_flags}
                    # puts "Test|$c_flags|||"
                    platform write
                    # platform zynqmp_fsbl -extra-linker-flags {}
                  }
                }
              }
            } result]} {
            puts "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_applist_line with: $result."
            lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_applist_line"
            }
          }
          domain active {zynqmp_pmufw}
          ::scw::get_hw_path
          ::scw::regenerate_psinit ${xsafile}
          ::scw::get_mss_path
          #extra compiler flags for fsbl
          foreach sw_applist_line $TE::SDEF::SW_APPLIST {
            if {[catch {
              if { [lindex $sw_applist_line ${TE::SDEF::ID}] ne "id" } {
                if { [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "PMU"} {
                  if { [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ne "NA" } { 
                    set tmp [split [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ","]
										set c_flags "[platform config -extra-compiler-flags pmufw]"
                    foreach symb $tmp {
                      set c_flags "$c_flags -D$symb"
                    }
                    platform pmufw -extra-compiler-flags ${c_flags}
                    # platform zynqmp_pmufw -extra-compiler-flags ${c_flags}
                    # puts "Test|$c_flags|||"
                    platform write
                    # platform zynqmp_pmufw -extra-linker-flags {}
                  }
                }
              }
            } result]} {
            puts "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_applist_line with: $result."
            lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_applist_line"
            }
          }
          domain active {standalone_domain}
          ::scw::get_hw_path
          ::scw::regenerate_psinit ${xsafile}
          ::scw::get_mss_path
        } elseif {$TE::VITIS_U::SYSTEM eq "versal"} {
        #looks there is no default domain...
          # domain active {standalone_domain}
          # ::scw::get_hw_path
          # ::scw::regenerate_psinit ${xsafile}
          # ::scw::get_mss_path
        } elseif {$TE::VITIS_U::SYSTEM eq "microblaze"} {
          domain active {standalone_domain}
          ::scw::get_hw_path
          ::scw::regenerate_psinit ${xsafile}
          ::scw::get_mss_path
        } else {
          puts "Error:(TE) platform ${TE::PRODID} failed: unknown system type $TE::VITIS_U::SYSTEM"
        }
        foreach sw_platlist_line $TE::SDEF::SW_DOMLIST {
          if {[catch {
            #ignore first standalone domain which is used on platform generation
            if { [lindex $sw_platlist_line ${TE::SDEF::D_NAME}] ne "NA" && [lindex $sw_platlist_line ${TE::SDEF::D_ID}] ne "id"} {
              set d_list_name [lindex $sw_platlist_line ${TE::SDEF::D_NAME}]
              set d_os [lindex $sw_platlist_line ${TE::SDEF::D_OS}]
              set d_proc [TE::VITIS_U::translate_processorname [lindex $sw_platlist_line ${TE::SDEF::D_PROC}]]

              if {[catch {set xsafiles [glob -join -dir ${TE::WORKSPACE_SDK_PATH} *.xsa]} ]} {
                puts "Error:(TE) platform ${TE::PRODID} failed: .xsa does not exist in ${TE::WORKSPACE_SDK_PATH}."
              }
              set xsafile [lindex $xsafiles 0]
              
              set d_name "${d_list_name}_${d_os}_domain"
              #start workaround
              #shorter name --> workaround for 841, in case name is larger that 20 char, I don't know what's the different to 712 excepted FPGA type, which should be no matter
              if {[string length $d_name] > 20 && $d_os ne "flash_fsbl"} {
                if {[string match "standalone" $d_os]} {
                  set d_name "${d_list_name}_stal_domain"
                } else {
                  puts "Critical Warning (TE): In case of problems contact Trenz support..."
                }
              }
              #end workaround
              set dp_name  "${d_list_name} ${d_os} on ${d_proc}"
              # set dpd_name "${d_name} ${d_os} on ${d_proc}"
              set d_desc "$dp_name"
              
              #special domain for separate fsbl for flash generation
              if {$d_os eq "flash_fsbl"} {
               set d_name "${d_os}"
               set dp_name "${d_os} on ${d_proc}"
               set d_os standalone
               set d_desc "Flash FSBL Application BSP for flash Programming"
              }
              
              # puts "TE_Test------|$d_name|$d_os|$d_proc||$dp_name|$d_name||||||"
              domain create -name $d_name -os $d_os -proc $d_proc -display-name $dp_name -desc $d_desc
              #not longer supported with 23.x  only one default(maybe make variable in the future)              -runtime {cpp}
              
              platform write
              if {[string match "linux" $d_os]} {
                # generate source files
                TE::VITIS_U::create_linux_source $d_name
                #set standalone as default active
                domain active {standalone_domain}
              } else {
                ::scw::get_hw_path
                ::scw::regenerate_psinit ${xsafile}
                ::scw::get_mss_path
              }
            }
          } result]} {
          puts "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_platlist_line with: $result."
          lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_domains) failed at $sw_platlist_line"
          }
        }
        
      } result]} { puts "Error:(TE) platform ${TE::PRODID} failed: $result."}
    }
    
    proc get_domain_name {proc_name os_name} {
      set vd_name "NA"
      
      # if { $os_name eq "zynq_fsbl" || $os_name eq "zynqmp_fsbl" || $os_name eq "zynqmp_pmufw" || $os_name eq "flash_fsbl"} { 
        # #auto generated domains which did not need domain table in csv --> todo test if changable
        # set vd_name "$os_name"
      # } else {
        # set vd_name "${os_name}_domain"
        
        # if {[string length $vd_name] > 20 } {
          # if {[string match "*_standalone*" $os_name]} {
            # set tmp [expr [string first  "_standalone" $os_name] - 1]
            # set vd_name "[string range $os_name 0 $tmp]_stal_domain"
          # } else {
            # puts "Critical Waring (TE): Domain Name is to long. In case of problems contact Trenz support..."
          # }
        # }
      # }
      if { $os_name eq "zynq_fsbl" || $os_name eq "zynqmp_fsbl" || $os_name eq "zynqmp_pmufw" || $os_name eq "flash_fsbl"} { 
        #auto generated domains which did not need domain table in csv --> todo test if changable
        set vd_name "$os_name"
      } else {
        set dlist [split [domain list] "\n"] 
        foreach dom $dlist {
          
         set tmp_pr [TE::VITIS_U::translate_processorname $proc_name]
            # puts "TE_TEST4 |$dom | $tmp_pr"
          if {[string match "*$tmp_pr*" $dom] && [string match "*$os_name*" $dom] && ![string match "*zynq_fsbl*" $dom]  && ![string match "*zynqmp_fsbl*" $dom]  && ![string match "*zynqmp_pmufw*" $dom]  && ![string match "*flash_fsbl*" $dom]} {
            set tmp [split $dom " "] 
            set vd_name [lindex $tmp 0]
            # puts "TE_TEST3 |$vd_name|$proc_name|$tmp_pr |$os_name"
            set vd_name "[string map {"*" ""} $vd_name]"
            # puts "TE_TEST4 |$vd_name|$proc_name|$tmp_pr |$os_name"
            
            
          }
        }
      }
      
      return $vd_name
    }
    
    proc bsp_modify {} {
      foreach sw_bsplist_line $TE::SDEF::SW_BSPLIST {
        if {[catch {
          if { [lindex $sw_bsplist_line ${TE::SDEF::B_ID}] ne "id" } {
            set b_name [lindex $sw_bsplist_line ${TE::SDEF::B_NAME}]
            set b_os [lindex $sw_bsplist_line ${TE::SDEF::B_OS}]
            set d_name "NA"
            if { $b_os eq "zynq_fsbl" || $b_os eq "zynqmp_fsbl" || $b_os eq "zynqmp_pmufw"|| $b_os eq "flash_fsbl"} { 
            #todo test if it can be modified these are auto generated domains from xilinx
            #flash fsbl is special stand alone domain for separate fsbl generation
               set d_name "${b_os}"
            } elseif { $b_name ne "NA" } { 
              set d_name "${b_name}_${b_os}_domain"
              #start workaround
              #shorter name --> workaround for 841, in case name is larger that 20 char, I don't know what's the different to 712 excepted FPGA type, which should be no matter
              if {[string length $d_name] > 20 } {
                if {[string match "standalone" $b_os]} {
                  set d_name "${b_name}_stal_domain"
                } else {
                  puts "Critical Warning (TE): In case of problems contact Trenz support..."
                }
              }
              #end workaround
            } else {
              # default standalone domain
              set d_name "${b_os}_domain"
            }
            # puts "Test:$d_name"
            platform active ${TE::PRODID}
            domain active $d_name
            
            if { [lindex $sw_bsplist_line ${TE::SDEF::B_UART}] ne "NA" } { 
              bsp config stdin [lindex $sw_bsplist_line ${TE::SDEF::B_UART}]
              bsp config stdout [lindex $sw_bsplist_line ${TE::SDEF::B_UART}]
            }
            if { [lindex $sw_bsplist_line ${TE::SDEF::B_LIBS}] ne "NA" } { 
              set tmp [split [lindex $sw_bsplist_line ${TE::SDEF::B_LIBS}] ","]
              foreach xlib $tmp {
                bsp setlib $xlib
              }
            } 
            if { [lindex $sw_bsplist_line ${TE::SDEF::B_CONFIG}] ne "NA" } { 
              set tmp [split [lindex $sw_bsplist_line ${TE::SDEF::B_CONFIG}] ","]
              foreach config $tmp {
                set tmp2 [split [lindex $sw_bsplist_line ${TE::SDEF::B_CONFIG}] "="]
                bsp config [lindex $tmp2 0] [lindex $tmp2 1]
              }
            }          
            bsp regenerate
          }
        } result]} {
        puts "Error:(TE) Script (TE::VITIS_U::bsp_modify) failed at $sw_bsplist_line with: $result."
        lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::bsp_modify) failed at $sw_bsplist_line"
        }
      }
    }
    
    proc platform_generate {} {
       #use this to add platform to SDK directly --> it will not opened on but platfrom generation step can be skipped --> directly add app
       platform generate
       
       importprojects ${TE::WORKSPACE_SDK_PATH}/${TE::PRODID}
    }
    
    proc app_create {{name *}} {
      
      foreach sw_applist_line $TE::SDEF::SW_APPLIST {
        if {[catch {
          if { [lindex $sw_applist_line ${TE::SDEF::ID}] ne "id" } {
             
            if { [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "0" || [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "3" || [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "FSBL_APP"} {
              set app_name [lindex $sw_applist_line ${TE::SDEF::APPNAME}]
              set app_template [lindex $sw_applist_line ${TE::SDEF::TEMPLATE_NAME}]
              set app_os [lindex $sw_applist_line ${TE::SDEF::OSNAME}]
              platform active ${TE::PRODID}
              set app_proc [lindex $sw_applist_line ${TE::SDEF::DESTINATION_CPU}]
              set  domainname [get_domain_name $app_proc $app_os]
              # puts "TE_TEST8 |$domainname|$app_os|"
              
              # if { $domainname eq "NA" } {
                # #fallback
                # set domainname  "${app_os}_domain"
              # }
              if {$app_os eq "flash_fsbl" || [string match "*_standalone*" $app_os]} {
               set app_os standalone
              }
              domain active $domainname
              set app_proc [TE::VITIS_U::translate_processorname $app_proc]
              # if {[string match "a9-*" $app_proc]} { 
                # set app_proc "ps7_cortex[string map {"-" "_"} $app_proc]"
              # } elseif {[string match "a53-*" $app_proc]} {
                # set app_proc "psu_cortex[string map {"-" "_"} $app_proc]"
              # } elseif {[string match "a72-*" $app_proc]} {
                # set app_proc "psu_cortex[string map {"-" "_"} $app_proc]"
              # } elseif {[string match "pmc-*" $app_proc]} {
                # set app_proc "psu_[string map {"-" "_"} $app_proc]"
              # } elseif {[string match "psm-*" $app_proc]} {
                # set app_proc "psu_[string map {"-" "_"} $app_proc]"
              # } else {
                 # #use as it is --> for microblaze for example 
              # }
              if {[string match $name $app_name]} {
                # puts "TE_TEST |---------------------------------------------------"
                # puts "TE_TEST |${app_name}|${TE::PRODID}|${app_proc}|${app_os}|${app_template}|--------------------------|[lindex $sw_applist_line ${TE::SDEF::CSYMB}]|[lindex $sw_applist_line ${TE::SDEF::BUILD}]| "
                # puts "TE_TEST2 |[domain list]|"
               
                app create -name  ${app_name} -platform ${TE::PRODID} -proc ${app_proc} -os ${app_os} -template ${app_template}
                
                if { [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ne "NA" } { 
                  set tmp [split [lindex $sw_applist_line ${TE::SDEF::CSYMB}] ","]
                  # set c_flags ""
                  foreach symb $tmp {
                     # set c_flags "$c_flags -D$symb"
                    app config -name ${app_name} define-compiler-symbols $symb 
                  }
                }               
                if { [lindex $sw_applist_line ${TE::SDEF::BUILD}] ne "NA" } { 
                  app config -name  ${app_name} build-config [lindex $sw_applist_line ${TE::SDEF::BUILD}]
                } 
              } 

        
            }
          }
        } result]} {
        puts "Error:(TE) Script (TE::VITIS_U::app_create) failed at $sw_applist_line with: $result."
        lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::app_create) failed at $sw_applist_line"
        }
      }
    }    
    
    proc repo_list {} {
    
      repo -apps
     
    }
    proc app_list {} {
      set tmplist [app list]
      set tmplist [split $tmplist "\n"]

      puts "------------------------------"
      puts "CSV app list:"
      puts "------------------------------"
      puts "Template_Name Processor OS App_Name Availble"
      foreach sw_applist_line $TE::SDEF::SW_APPLIST {
        if {[catch {
          if { [lindex $sw_applist_line ${TE::SDEF::ID}] ne "id" } {
             
            if { [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "0" || [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "3" || [lindex $sw_applist_line ${TE::SDEF::STEPS}] eq "FSBL_APP"} {
              set app_name [lindex $sw_applist_line ${TE::SDEF::APPNAME}]
              set app_template [lindex $sw_applist_line ${TE::SDEF::TEMPLATE_NAME}]
              set app_os [lindex $sw_applist_line ${TE::SDEF::OSNAME}]
              set app_proc [lindex $sw_applist_line ${TE::SDEF::DESTINATION_CPU}]
              set app_vitis "No"
              foreach element $tmplist {
                if {![string match "*==*" $element] && ! [string match "*NAME*" $element]  && ! [string match "" $element]} {
                  set tmpname [lindex [split $element " "] 1];
                  if {[string match $app_name $tmpname]} {
                    set app_vitis "yes"
                  }
                }
              }
              
              puts "-------------"
              puts "$app_template   $app_proc   $app_os   $app_name $app_vitis"
            }
          }
        } result]} {
        puts "Error:(TE) Script (TE::VITIS_U::app_list) failed at $sw_applist_line with: $result."
        lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::app_list) failed at $sw_applist_line"
        }
      }
    }
     
    proc app_build {{name *}} {
      set tmplist [app list]
      set tmplist [split $tmplist "\n"]
      set index 0
      foreach element $tmplist {
        if {[catch {
          if {![string match "*==*" $element] && ! [string match "*NAME*" $element]  && ! [string match "" $element]} {
            set tmpname [lindex [split $element " "] 1];
            if {[string match $name $tmpname]} {
              app build $tmpname
              puts "build $tmpname "
            } else {
              puts "skip $tmpname"
            }
          } else {
            puts "Debug: (TE) $element"
          }
        } result]} {
          puts "Error:(TE) Script (TE::VITIS_U::app_build) failed at $element with: $result."
          lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::app_build) failed at $element "
        }
        incr index
      }
    }
    
    proc app_delete {{name *}} {
      set tmplist [app list]
      set tmplist [split $tmplist "\n"]
      set index 0
      foreach element $tmplist {
        if {[catch {
          if {![string match "*==*" $element] && ! [string match "*NAME*" $element]  && ! [string match "" $element]} {
            set tmpname [lindex [split $element " "] 1];
            if {[string match $name $tmpname]} {
              app remove $element
              puts "remove $tmpname "
            } else {
              puts "skip $tmpname"
            }
          } else {
            puts "$element"
          }
        } result]} {
          puts "Error:(TE) Script (TE::VITIS_U::app_delete) failed  at $element with: $result."
          lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::app_delete) failed failed at $element "
        }
        incr index
      }
    }   
    proc app_clean {{name *}} {
      set tmplist [app list]
      set tmplist [split $tmplist "\n"]
      set index 0
      foreach element $tmplist {
        if {[catch {
          if {![string match "*==*" $element] && ! [string match "*NAME*" $element]  && ! [string match "" $element]} {
            set tmpname [lindex [split $element " "] 1];
            if {[string match $name $tmpname]} {
              app clean $tmpname
              puts "clean -name $tmpname "
            } else {
              puts "skip $tmpname"
            }
          } else {
            puts "Debug: (TE) $element"
          }
        } result]} {
          puts "Error:(TE) Script (TE::VITIS_U::app_clean) failed failed at $element with: $result."
          lappend TE::VITIS_U::CSV_ISSUES "Error:(TE) Script (TE::VITIS_U::app_clean) failed failed at $element"
        }
        incr index
      }
    }
    
    proc open_workspace_gui {} { 
        set tmplist [list]

        lappend tmplist "-lp" ${TE::LIB_PATH}
        set command exec
        lappend command vitis
        lappend command -workspace ${TE::WORKSPACE_SDK_PATH}
        lappend command {*}$tmplist
        if { [catch {eval $command} result ]  } {
          puts "Error:(TE) ScriptCommand results from vitis \"$command\": $result \n"
        } else {
          puts "INFO:(TE) ScriptCommand results from vitis \"$command\": $result \n"
        }
    }
    #--------------------------------
    #--run_all:
    proc ex_rescan {} { 
      #this is a workaround -->  platform create failes with xsct started manually but works with vivado and scripts directly.
       puts "Info:(TE) Set  system type..."
      if {[catch {TE::VITIS_U::check_system_type} result]} { puts "Error:(TE) Script (TE::VITIS_U::check_system_type) failed: $result."}
       puts "Info:(TE) Create workspace..."
      if {[catch {TE::VITIS_U::set_workspace} result]} { puts "Error:(TE) Script (TE::VITIS_U::set_workspace) failed: $result."}
      puts "Info:(TE) Read platform..."
      platform read ${TE::WORKSPACE_SDK_PATH}/${TE::PRODID}/platform.spr
      platform active ${TE::PRODID}
      
    }
    
    
    
   #--------------------------------
    #--run_all:
    proc run_all {{deep 3}} {      
      puts "Info:(TE) Set  system type..."
      if {[catch {TE::VITIS_U::check_system_type} result]} { 
        puts "Error:(TE) Script (TE::VITIS_U::check_system_type) failed: $result"
        lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::check_system_type) failed."
      }
      puts "Info:(TE) Create workspace..."
      if {[catch {TE::VITIS_U::set_workspace} result]} { 
        puts "Error:(TE) Script (TE::VITIS_U::set_workspace) failed: $result"
        lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::set_workspace) failed."
      }
      if {$deep > 1} {
        puts "Info:(TE) Create platform..."
        if {[catch {TE::VITIS_U::platform_create} result]} { 
          puts "Error:(TE) Script (TE::VITIS_U::platform_create) failed: $result"
          lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_create) failed."
        }
        # after  1000
         puts "Info:(TE) Create platform domains..."
        if {[catch {TE::VITIS_U::platform_domains} result]} { 
          puts "Error:(TE) Script (TE::VITIS_U::platform_domains) failed: $result"
          lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_domains) failed."
        }
        # after  1000
         puts "Info:(TE) Modify BSP..."
        if {[catch {TE::VITIS_U::bsp_modify} result]} { 
          puts "Error:(TE) Script (TE::VITIS_U::bsp_modify) failed: $result"
          lappend TE::VITIS_U::GEN_ISSUES  "Error:(TE) Script (TE::VITIS_U::bsp_modify) failed."
        }
        # after  1000
         puts "Info:(TE) Generate platform..."
        if {[catch {TE::VITIS_U::platform_generate} result]} { 
          puts "Error:(TE) Script (TE::VITIS_U::platform_generate) failed: $result"
          lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::platform_generate) failed."
        }
      }
      if {$deep > 2} {
        # after  1000
        puts "Info:(TE) Create Apps..."
        if {[catch {TE::VITIS_U::app_create} result]} { 
          puts "Error:(TE) Script (TE::VITIS_U::app_create) failed: $result"
          lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::app_create) failed."
        }
        if {$TE::IS_VSYS} {
          puts "Info:(TE) Workaround Clean Apps disabled for Versal..."
          # WORKAROUND: disable for versal, needed on 22.x and 23.1
        }  else {
          puts "Info:(TE) Clean Apps..."
          if {[catch {TE::VITIS_U::app_clean} result]} { 
            puts "Error:(TE) Script (TE::VITIS_U::app_clean) failed: $result"
            lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::app_clean) failed."
          }
        }
        puts "Info:(TE) Build Apps..."
        if {[catch {TE::VITIS_U::app_build} result]} { 
          puts "Error:(TE) Script (TE::VITIS_U::app_build) failed: $result"
          lappend TE::VITIS_U::GEN_ISSUES "Error:(TE) Script (TE::VITIS_U::app_build) failed."
        }
      }
      # after  1000
      puts "Info:(TE) finished..."
      #--> done via vivado otherwise it can be happens some conflict with file lock of previous tasks
      # if {[catch {open_workspace_gui} result]} { puts "Error:(TE) Script (TE::VITIS_U::open_workspace_gui) failed: $result."}
    }
    
    #--------------------------------
    #--return_option: 
    proc help {} {
      puts "source ../../scripts/script_vitis.tcl   --> rescan scripts and configs "
      puts "TE::VITIS_U::ex_rescan                    --> rescan platform "
      puts "TE::VITIS_U::platform_domains             --> create domains(some are predefined)"
      puts "TE::VITIS_U::bsp_modify                   --> modify bsp from csv"
      puts "TE::VITIS_U::platform_generate            --> generate platform"
      puts "TE::VITIS_U::app_create <arg>             --> create apps from csv, optional defined app only"
      puts "TE::VITIS_U::app_clean <arg>              --> clean  all apps or optional defined app"
      puts "TE::VITIS_U::app_build <arg>              --> build  all apps or optional defined app"
      puts "TE::VITIS_U::app_delete  <arg>            --> delete  all apps or optional defined app"
      puts "TE::VITIS_U::repo_list                    --> show all apps from xilinx repo"
      puts "TE::VITIS_U::app_list                     --> show all apps from  TE csv file"
      puts "TE::VITIS_U::open_workspace_gui           --> open Vitis"
      puts "--------"
      puts "repo -apps                              --> show available app templates"
    }
    
    #--------------------------------
    #--return_option: 
    proc return_option {option argc argv} {
      if { $argc <= [expr $option + 1]} { 
        return -code error "Error:(TE) Read parameter failed"
      } else {  
        puts "Info:(TE) Parameter Option Value: [lindex $argv [expr $option + 1]]"
        return [lindex $argv [expr $option + 1]]
      }
    }  
    #--------------------------------
    #--hsi_main: 
    proc vitis_main {} {
      global argc
      global argv
      set tmp_argc 0
      set tmp_argv 0
      if {$argc >= 1 } {
        set tmp_argv [lindex $argv 0]
        set tmp_argc [llength $tmp_argv]
      }
      
      set tmp_argv [split $tmp_argv "*"]
      set tmp_argc [llength $tmp_argv]
      
      set vivrun false
      set platform_only false
      set worspace_only false
      set id_tmp "UNKOWN"
     
      
      for {set option 0} {$option < $tmp_argc} {incr option} {
        puts "Info:(TE) Parameter Index: $option"
        puts "Info:(TE) Parameter Option: [lindex $tmp_argv $option]"
        switch [lindex $tmp_argv $option] {
          "--id"	            { set id_tmp [return_option $option $tmp_argc $tmp_argv];incr option;  }       
          "--platform_only"		    { set platform_only true }
          "--worspace_only"		    { set worspace_only true }
          "--vivrun"		      { set vivrun true }
          default             { puts "" }
        }
      }
       source ${TE::VITIS_U::SCRIPT_PATH}/script_te_utils.tcl
       source ${TE::VITIS_U::SCRIPT_PATH}/script_external.tcl
       source ${TE::VITIS_U::SCRIPT_PATH}/script_settings.tcl
       set tmppath [pwd]
       cd ../../
       if {[catch {TE::INIT::init_pathvar} result]} {  puts "Error:(TE) Script Initialization...$result";  return -code error}
       cd $tmppath
      if {[catch {TE::INIT::init_boardlist} result]} {  puts "Error:(TE) Script Initialization...$result";return -code error}
      if {[catch {TE::INIT::init_app_list} result]} { puts "Error:(TE) Script Initialization...$result"; return -code error} 
      
      # todo add option to recover product id from platform project
       set prod_id [TE::UTILS::read_board_select] 
       if { $id_tmp ne "UNKOWN" } {
         TE::INIT::init_board  [TE::BDEF::find_id $id_tmp] $TE::BDEF::ID
       } elseif {![string match "NA" $prod_id] == 1} {
         TE::INIT::init_board $prod_id $TE::BDEF::PRODID
       } else {
         puts "INFO:(TE) Script (TE::VITIS_U::vitis_main) use part name from environment with PARTNUMBER=$::env(PARTNUMBER)."
         TE::INIT::init_board  [TE::BDEF::find_id $::env(PARTNUMBER)] $TE::BDEF::ID
       }
      
      puts "INFO: (TE): ${TE::WORKSPACE_SDK_PATH} is used as workspace"
      puts "INFO: (TE): See also UG1400-Vitis Embedded Software Development"
      TE::VITIS_U::check_system_type
      if {$vivrun==true} {
        if {$worspace_only==true} {
          TE::VITIS_U::run_all 1
        } elseif {$platform_only==true} {
          TE::VITIS_U::run_all 2
        } else {
          TE::VITIS_U::run_all 3
        }

        puts "--------------------------------------------------"
        puts "--------------------------------------------------"
        if {[llength $TE::VITIS_U::GEN_ISSUES]> 0 } {
          puts "Error:(TE) VITIS general issue summary:"
          puts "---------------------"
          foreach issue $TE::VITIS_U::GEN_ISSUES {
            puts "$issue"
          }
           
        } else {
          puts "INFO:(TE) Script VITIS general generation passed ([llength $TE::VITIS_U::GEN_ISSUES])"
        }
        puts "--------------------------------------------------"
        if {[llength $TE::VITIS_U::CSV_ISSUES]> 0 } {
          puts "Error:(TE) CSV issue summary:"
          puts "---------------------"
          foreach issue $TE::VITIS_U::CSV_ISSUES {
            puts "$issue"
          }
           
        } else {
          puts "INFO:(TE) Script CSV generation passed ([llength $TE::VITIS_U::CSV_ISSUES])"
        }
        puts "--------------------------------------------------"
        
        if {[llength $TE::VITIS_U::CSV_ISSUES]> 0 || [llength $TE::VITIS_U::GEN_ISSUES]> 0} { 
          puts "TE_MESSAGE_FAILED"
          # return -code error
        } else {
          puts "TE_MESSAGE_PASSED"
        }
      } else {
        TE::VITIS_U::help
      }

    }
    if {[catch {vitis_main} result]} {
      puts "TE_MESSAGE_FAILED"
      puts "Error:(TE) Script (TE::VITIS_U::vitis_main) failed: $result"
      return -code error
    } 
  
  # -----------------------------------------------------------------------------------------------------------------------------------------
  }
 puts "Info: Load VITIS Unified scripts finished" 
 return ok
}
