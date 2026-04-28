# --------------------------------------------------------------------
# --   *****************************
# --   *   Trenz Electronic GmbH   *
# --   *   Beendorfer Str. 23      *
# --   *   32609 Hüllhorst         *
# --   *   Germany                 *
# --   *****************************
# --------------------------------------------------------------------
# -- $Author: Hartfiel, John $
# -- $Email: j.hartfiel@trenz-electronic.de $
# --------------------------------------------------------------------
# -----------------------------------------------------------------------------------------------------------------------------
# -- Change history  :
# ------------------|---------|---------|----------------------------------------------------------------------
# -- Date           | Author  |Critical | Description
# ------------------|---------|---------|----------------------------------------------------------------------
# --                |         |         |
# --                |         |         |
# --                |         |         |
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2025/01/27     |JH       |         |-add template_git_verification to run_plx and plx_clear with remove option
# --                |         |         |-remove obsolete git_patch
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2024/12/16     |JH       |         |-2024.2 update: add xsa file to project creation(plx_run and plx_config)
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/12/05     |JH       |         |-add versal to plx_config create project
# --                |         |         |-bugfix modify_config
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/09/04     |JH       |         |-bugfix plx_clear plx_run
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/08/16     |JH       |         |-bugfix plx_config
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/08/15     |JH       |         |-add  TE::TE_GUI_DISABLED to all exec (only for external automation processes which are not started  inside vivado)
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/07/25     |JH       |         |-bugfix plx_run and plx_clear works again with vivado
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2023/07/24     |JH       |         |-bugfix print source tcl  
# --                |         |         |-new style history table
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2022/11/16     |MK       |         |- - peatlinux: copy fsbls to prebuilt
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2022/10/20     |MK       |         |- refactored store/restore_env to be only called when under vivado
# --                |         |         |- plx_run takes .xsa from prebuilt now per default 
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2022/02/02     |JH       |         |- plx_clear remove hs_err*log
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2022/01/20     |JH       |         |- remove plx_bootsrc from default ran and add options to usrcommands.tcl 
# --                |         |         |- add modify_config to plx_clear, plx_run, plx_config, plx_uboot, plx_kernel,plx_rootfs, plx_app
# --                |         |         |- modify modify_config with local sstate as enviroment variable
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2022/01/11     |JH       |         |-add modify_config
# --                |         |         |- add modify_config to plx_clear
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/06     |JH       |         |-   plx_kernel, plx_uboot remove  clean up
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/17     |JH       |         |-   moved plx_console as terminal to external
# --                |         |         |-   add try catch for extern runnings
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/14     |JH       |         |-   add msg log number
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/06     |JH       |         |- plx_kernel, plx_uboot remove devtool option for 21.2
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/02     |JH       |         |- plx_run, plx_device_tree
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/12/01     |JH       |         |- add uboot.dtb for prebuilt export in plx_run
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/11/26     |JH       |         |- remove python variables on plx_run
# --                |         |         |-  add notes
# ------------------|---------|---------|----------------------------------------------------------------------
# -- 2021/07/07     |JH       |         |- moved plx from external to own tcl
# ------------------|---------|---------|----------------------------------------------------------------------


namespace eval ::TE {
  namespace eval PLX {
  
    variable t_PYTHONHOME
    variable t_LD_LIBRARY_PATH
    variable t_PYTHONPATH
    variable t_PYTHON
    
    # Utility Functions to store and restore env which is necessary under vivado
    proc store_env {} {
      # only do this if we are within vivado, otherwise not needed
      set cmdname create_bd_cell 
      if {$cmdname in [info commands $cmdname]} {
        set TE::PLX::t_PYTHONHOME $::env(PYTHONHOME)
        set TE::PLX::t_LD_LIBRARY_PATH $::env(LD_LIBRARY_PATH)
        set TE::PLX::t_PYTHONPATH $::env(PYTHONPATH)
        set TE::PLX::t_PYTHON $::env(PYTHON)
        unset ::env(PYTHONHOME) 
        unset ::env(LD_LIBRARY_PATH) 
        unset ::env(PYTHONPATH)
        unset ::env(PYTHON)
      }
    }
    proc restore_env {} {
       set cmdname create_bd_cell 
       if {$cmdname in [info commands $cmdname]} {
         set ::env(PYTHONHOME) $TE::PLX::t_PYTHONHOME
         set ::env(LD_LIBRARY_PATH) $TE::PLX::t_LD_LIBRARY_PATH
         set ::env(PYTHONPATH) $TE::PLX::t_PYTHONPATH
         set ::env(PYTHON) $TE::PLX::t_PYTHON
       }
    }
    
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # petalinux functions
    # -----------------------------------------------------------------------------------------------------------------------------------------
    #--------------------------------
    #--plx_config:
    proc plx_config {{refresh false}} {
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
			# create project if missing
			if {![file exists ${TE::PETALINUX_PATH}] } {
				set ospath [file normalize ${TE::PETALINUX_PATH}/..]
				file mkdir ${ospath}
				cd ${ospath}
        store_env
         
        if { [catch {
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            lappend command petalinux-create 
            lappend command --type project
            lappend command --name $prjname
            if {$TE::IS_ZUSYS} {
              lappend command --template zynqMP
            } elseif {$TE::IS_ZSYS} {
              lappend command --template zynq
            } elseif {$TE::IS_MSYS} {
              lappend command --template microblaze
            } elseif {$TE::IS_VSYS} {
              lappend command --template versal
            } else {
              restore_env
              return -code error "unkown system"
            }
          } else {
            lappend command xterm
            if {$TE::IS_ZUSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --name $prjname --template zynqMP "
            } elseif {$TE::IS_ZSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --name $prjname --template zynq "
            } elseif {$TE::IS_MSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --name $prjname --template microblaze "
            } elseif {$TE::IS_VSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --name $prjname --template versal "
            } else {
              restore_env
              return -code error "unkown system"
            }
          }
          set result [eval $command]

          TE::UTILS::te_msg TE_PLX-0 INFO "Command results from petalinux \"$command\": \n \
              $result \n \
            ------" 
        } result ]  } {
          restore_env
          cd ${cur_path}
          return -code error $result
        }
        
        restore_env
			}
			cd ${TE::PETALINUX_PATH}
      #---- change to local sstate if possible
      modify_config 0 
      #----
			set xsafile  [list]
			if { [catch {set xsafile [glob -join -dir ${TE::PETALINUX_PATH}/ *.xsa]}] || $refresh} {
				#copy xsa
				TE::UTILS::generate_workspace_petalinux 
        
        store_env 
        
        if { [catch {
          # load xsa and start config
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            lappend command petalinux-config
            lappend command --get-hw-description=${TE::PB_FILENAME}.xsa
          } else {
            # lappend command gnome-terminal
            lappend command xterm
            lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config --get-hw-description=${TE::PB_FILENAME}.xsa "
          }
          set result [eval $command]
          TE::UTILS::te_msg TE_PLX-1 INFO "Command results from petalinux \"$command\": \n \
              $result \n \
            ------" 
        } result ]  } {
          restore_env
          cd ${cur_path}
          return -code error $result
        }
        restore_env
			} else {
        store_env
        if { [catch {       
          # start config
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            lappend command petalinux-config
          } else {
            # lappend command gnome-terminal
            # lappend command -- unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config
            lappend command xterm
            lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config "
          }
          set result [eval $command]
          TE::UTILS::te_msg TE_PLX-2 INFO "Command results from petalinux \"$command\": \n \
              $result \n \
            ------" 
        } result ]  } {
          restore_env
          cd ${cur_path}
          return -code error $result
        }
        restore_env
			}
			cd $cur_path 
		}
    #--------------------------------
    #--plx_uboot: 
    proc plx_uboot {} {
      #---- change to local sstate if possible
      modify_config 0 
      #----
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
			cd ${TE::PETALINUX_PATH}
      
      store_env
      if { [catch {       
        # start uboot config
        set command exec
        if {$TE::TE_GUI_DISABLED} {
          lappend command  >&@stdout
          lappend command petalinux-config 
          lappend command -c u-boot
        } else {
          lappend command xterm
          lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config -c u-boot"
          # lappend command gnome-terminal
          # lappend command -e "petalinux-config -c u-boot"
        }
        set result [eval $command]
        TE::UTILS::te_msg TE_PLX-3 INFO "Command results from petalinux \"$command\": \n \
            $result \n \
          ------" 
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }
				
      restore_env
			cd $cur_path 
		}
    #--------------------------------
    #--plx_kernel: 
    proc plx_kernel {} {
      #---- change to local sstate if possible
      modify_config 0 
      #----
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
			cd ${TE::PETALINUX_PATH}
      store_env
      if { [catch {       
        # start kernel config
        set command exec
        if {$TE::TE_GUI_DISABLED} {
          lappend command  >&@stdout
          lappend command petalinux-config 
          lappend command -c kernel
        } else {
          lappend command xterm
          lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config -c kernel"
          # lappend command gnome-terminal
          # lappend command -e "petalinux-config -c kernel"
        }
        set result [eval $command]
        TE::UTILS::te_msg TE_PLX-5 INFO "Command results from petalinux \"$command\": \n \
            $result \n \
          ------" 
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }

      restore_env
			cd $cur_path 
		}
    #--------------------------------
    #--plx_rootfs: 
    proc plx_rootfs {} {
      #---- change to local sstate if possible
      modify_config 0 
      #----
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
			cd ${TE::PETALINUX_PATH}
      store_env
      if { [catch {       
        # # start rootfs config 
        set command exec
        if {$TE::TE_GUI_DISABLED} {
          lappend command  >&@stdout
          lappend command petalinux-config
          lappend command -c rootfs
        } else {
          lappend command xterm
          lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config -c rootfs"
        }
        set result [eval $command]
        TE::UTILS::te_msg TE_PLX-7 INFO "Command results from petalinux \"$command\": \n \
            $result \n \
          ------" 
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }
      restore_env
			cd $cur_path 
		}
    #--------------------------------
    #--plx_device_tree: 
    proc plx_device_tree { {sel "system"}} {
    #--sel "system", "u-boot", "both"
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
			cd ${TE::PETALINUX_PATH}
      store_env
      if { [catch {       
        if {[string match -nocase $TE::TE_EDITOR ""] } {
          #start device tree editor
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            if {[string match -nocase $sel "u-boot"]} {
              lappend command gvim ${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/uboot-device-tree/files/system-user.dtsi
            } else {
              lappend command gvim ${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi
            }
          } else {
            lappend command xterm

            if {[string match -nocase $sel "u-boot"]} {
              lappend command -e "gvim ${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/uboot-device-tree/files/system-user.dtsi"
            } else {
              lappend command -e "gvim ${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi"
            }
          }
          set result [eval $command]
          TE::UTILS::te_msg TE_PLX-8 INFO "Command results from petalinux \"$command\": \n \
              $result \n \
            ------" 
        } else {
          if {[string match -nocase $sel "u-boot"]} {
            TE::EXT::editor "${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/uboot-device-tree/files/system-user.dtsi"
          } else {
            TE::EXT::editor "${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi"
          }
          
        }
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }
      if {[string match -nocase $sel "both"]} {  
        [catch {file copy -force  ${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/device-tree/files/system-user.dtsi ${TE::PETALINUX_PATH}/project-spec/meta-user/recipes-bsp/uboot-device-tree/files/system-user.dtsi}]

      }
        
      restore_env
			cd $cur_path 
		}
    #--------------------------------
    #--plx_app: 
    proc plx_app { appname } {
      
      #---- change to local sstate if possible
      modify_config 0 
      #----
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
			cd ${TE::PETALINUX_PATH}
      store_env
      if { [catch {       
        #create empty app
        set command exec
        if {$TE::TE_GUI_DISABLED} {
          lappend command  >&@stdout
          lappend command  petalinux-create
          lappend command  -t apps
          lappend command  -n ${appname}
          lappend command  --enable
        } else {
          lappend command xterm
          # lappend command gnome-terminal
          lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create -t apps -n ${appname} --enable"
        }
        set result [eval $command]
        TE::UTILS::te_msg TE_PLX-9 INFO "Command results from petalinux \"$command\": \n \
            $result \n \
          ------" 
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }
      #maybe copy app from template svn?
      restore_env
			cd $cur_path 
		}
    #--------------------------------
    #--plx_bootsrc: 
    proc plx_bootsrc { {type def} {imageub_addr 0x10000000} {imageub_flash_addr 0x200000} {imageub_flash_size 0xD90000}} {
      puts "todo template script version testen --> parameter mit in die settings aufnehmen und parameter aus dem sw csv uebergeben und das hier bei run ausfuehren" 
			#type= default --> create files without changes
			#type= ign --> do not create bootscr files on prebuilt folder
			#type= all others --> create bootscr files with parameters

      set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
      set posfolder ${TE::PREBUILT_OS_PATH}/petalinux/${TE::DDR_SIZE}/
			file mkdir ${posfolder}
			cd ${posfolder}
      
      if {[file exists ${TE::SCRIPT_PATH}/boot.script_template] && ![string match -nocase "ign" $type]} { 
        set fp_r [open ${TE::SCRIPT_PATH}/boot.script_template "r"]
        set file_data [read $fp_r]
        close $fp_r
        
        set tmp_date "[ clock format [clock seconds] -format "%Y_%m_%d %H_%M_%S"]"
        if {[string match -nocase $type "def"] } {
          TE::UTILS::te_msg TE_PLX-10 INFO "Use default Boot Source file ( ${posfolder}/boot.script ) without modification \n \
          ------" 
        } 
        set e1str "echo \[TE_BOOT-00\] Boot Source Script File creation date:  $tmp_date;"
        set e2str "echo \[TE_BOOT-00\] Automatically generated Trenz Electronic Boot Source file with setup $type;"
        set data [split $file_data "\n"]
        set data [linsert $data[set data {}] 0 "################"]
        set data [linsert $data[set data {}] 0 "$e1str"]
        set data [linsert $data[set data {}] 0 "$e2str"]
        set data [linsert $data[set data {}] 0 "################"]
        set data [linsert $data[set data {}] 0 ""]
        set line_index -1
        set mod_count 0
        foreach line $data {
          incr line_index
          #comment lines on tcl file, modified lines are ignored
          if {[string match "imageub_addr=*" $line] && ! [string match -nocase "def" $type]} {
            set data [lreplace $data[set data {}] $line_index $line_index "imageub_addr=$imageub_addr"]
            incr mod_count
          }
          if {[string match "imageub_flash_addr=*" $line]&& ! [string match -nocase "def" $type]} {
            set data [lreplace $data[set data {}] $line_index $line_index "imageub_flash_addr=$imageub_flash_addr"]
            incr mod_count
          }
          if {[string match "imageub_flash_size=*" $line]&& ! [string match -nocase "def" $type]} {
            set data [lreplace $data[set data {}] $line_index $line_index "imageub_flash_size=$imageub_flash_size"]
            incr mod_count
          }
        }
          
        
        
        if {[file exists ${posfolder}/boot.script]} { 
          TE::UTILS::te_msg TE_PLX-11 INFO "Existing Boot script file ( ${posfolder}/boot.script ) will be overwrite with new one \n \
          ------" 
        }
        set fp_w [open ${posfolder}/boot.script "w"]
        foreach line $data {
          puts $fp_w $line
        }
        close $fp_w
        store_env
        if { [catch {       
          #start 
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            lappend command mkimage
            lappend command -c none
            lappend command -A arm
            lappend command -T script
            lappend command -d boot.script
            lappend command boot.scr
          } else {
            #todo JH:ware das ohne gui...mal schauen(falls keiner meckert hat's gepasst so)
            #todo microblaze...
            lappend command xterm
            lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;mkimage -c none -A arm -T script -d boot.script boot.scr"
            #lappend command gnome-terminal
          }
          
          set result ""
          if { [catch {set result [eval $command]}] } {
            TE::UTILS::te_msg TE_PLX-12 {CRITICAL WARNING} "Install mkimage with: \n \
              sudo apt-get update \n \
              sudo apt install u-boot-tools \n \
            ------" 
          }
          
          TE::UTILS::te_msg TE_PLX-13 INFO "Command results from mkimage \"$command\": \n \
              $result \n \
            ------" 
        } result ]  } {
          restore_env
          cd ${cur_path}
          return -code error $result
        }
        restore_env
        # delete timestamp on script file to see if customer has reused it        
        set fp_r [open ${posfolder}/boot.script "r"]
        set file_data [read $fp_r]
        close $fp_r 
        set data [split $file_data "\n"]
        set fp_w [open ${posfolder}/boot.script "w"]
        foreach line $data {
          if {[string match "*Boot Source Script File creation date:*" $line]} {
            puts $fp_w "echo \[TE_BOOT-00\] Boot Source Script File creation date: customer template version"
          } else {
            puts $fp_w $line
          }
        }
         close $fp_w
          
      } else {
        TE::UTILS::te_msg TE_PLX-14 WARNING "Boot source file generation skipped, customer must create correct file \n \
				------" 
      }
			cd $cur_path 
		}
    #--------------------------------
    #--plx_run: 
    proc plx_run {{refresh false} {copy_fsbl false} {copy_bootscr false}} {
			set cur_path [pwd]
			set prjname [file tail ${TE::PETALINUX_PATH}]
      # check for clean template
      template_git_verification
      
      # store python environments
      store_env
      
			# create project if missing
			if {![file exists ${TE::PETALINUX_PATH}] } {
				set ospath [file normalize ${TE::PETALINUX_PATH}/..]
				file mkdir ${ospath}
				cd ${ospath}
        if { [catch {       
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            lappend command petalinux-create 
            lappend command --type project
            lappend command --name $prjname
            if {$TE::IS_ZUSYS} {
              lappend command --template zynqMP
            } elseif {$TE::IS_ZSYS} {
              lappend command --template zynq
            } elseif {$TE::IS_MSYS} {
              lappend command --template microblaze
            } elseif {$TE::IS_VSYS} {
              lappend command --template versal
            } else {
              restore_env
              return -code error "unkown system"
            }
          } else {
            lappend command xterm
            if {$TE::IS_ZUSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --template zynqMP "
            } elseif {$TE::IS_ZSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --template zynq "
            } elseif {$TE::IS_MSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --template microblaze "
            } elseif {$TE::IS_VSYS} {
              lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-create --type project --template versal "
            } else {
              restore_env
              return -code error "unkown system"
            }
          }
          set result [eval $command]
          TE::UTILS::te_msg TE_PLX-28 INFO "Command results from petalinux \"$command\": \n \
              $result \n \
            ------" 
            
        } result ]  } {
          restore_env
          cd ${cur_path}
          return -code error $result
        }
			}
			cd ${TE::PETALINUX_PATH}
			
      modify_config 0  
      
			set xsafile  [list]
			if { [catch {set xsafile [glob -join -dir ${TE::PETALINUX_PATH}/ *.xsa]}] || $refresh} {
				#copy xsa
				TE::UTILS::generate_workspace_petalinux $TE::SHORTDIR 
				# load xsa
        if { [catch {       
          set command exec
          if {$TE::TE_GUI_DISABLED} {
            lappend command  >&@stdout
            lappend command petalinux-config 
            lappend command --get-hw-description=${TE::PB_FILENAME}.xsa 
            lappend command --silentconfig
          } else {
            lappend command xterm
            lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-config --get-hw-description=${TE::PB_FILENAME}.xsa --silentconfig"
          }
          set result [eval $command]
          TE::UTILS::te_msg TE_PLX-15 INFO "Command results from petalinux \"$command\": \n \
              $result \n \
            ------" 
        } result ]  } {
          restore_env
          cd ${cur_path}
          return -code error $result
        }
			} 
			# build project
      if { [catch {       
        set command exec
        if {$TE::TE_GUI_DISABLED} {
          lappend command  >&@stdout
          lappend command petalinux-build 
        } else {
          lappend command xterm
          lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-build"
        }
        set result [eval $command]
        TE::UTILS::te_msg TE_PLX-16 INFO "Command results from petalinux \"$command\": \n \
            $result \n \
          ------" 
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }
        
      restore_env
      
			#todo copy files to prebuilt(todo selection)
			set posfolder ${TE::PREBUILT_OS_PATH}/petalinux/${TE::DDR_SIZE}/
			file mkdir ${posfolder}
			
			# [catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/boot.scr ${posfolder}}]
			#
      puts "todo finaly use separate function for prebuilt export"      
			catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/image.ub     ${posfolder}}
			catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/u-boot.elf   ${posfolder}}
			catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/bl31.elf     ${posfolder}}
			catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/u-boot.dtb   ${posfolder}}
			catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/system.dtb   ${posfolder}}
			catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/dtbos        ${posfolder}}

      if {$copy_fsbl} {
        if {$TE::IS_ZSYS} {
          catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/zynq_fsbl.elf   ${posfolder}}
        } elseif {$TE::IS_ZUSYS} {
          catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/zynqmp_fsbl.elf   ${posfolder}}
        }
      }

      if {$copy_bootscr} {
          catch {file copy -force  ${TE::PETALINUX_PATH}/images/linux/boot.scr   ${posfolder}}
      }
			
			cd $cur_path
      #create Trenz boot.src file:
     
      # TE::PLX::plx_bootsrc
    }  
    #--------------------------------
    #--plx_clear: 
    proc plx_clear {} {
			set cur_path [pwd]
			cd ${TE::PETALINUX_PATH}
      if { [catch {       
        set command exec
        if {$TE::TE_GUI_DISABLED} {
          lappend command  >&@stdout
          lappend command petalinux-build 
          lappend command -x mrproper
          lappend command -f
        } else {
          lappend command xterm
          lappend command -e "unset PYTHONHOME; unset PYTHONPATH; unset PYTHON ;petalinux-build  -x mrproper -f"
        }
        set result [eval $command]
        TE::UTILS::te_msg TE_PLX-17 INFO "Command results from petalinux \"$command\": \n \
            $result \n \
          ------" 
      } result ]  } {
        restore_env
        cd ${cur_path}
        return -code error $result
      }
			template_git_verification true	
      
      # ----
      #modify config back to default network sstate
     # modify_config 1
      
			cd $cur_path 
    }  
    #--------------------------------
    #--modify_config:
    proc modify_config {{stage 1}} {
      #todo pfade als umgebungsvariablen als alternative
      set vivado_version  ${::env(VIVADO_VERSION)}
      set sstate_url $TE::PLX_SSTATE_CACHE_AARCH64
      set download_url $TE::PLX_SSTATE_CACHE_DOWNLOAD
      set system "aarch64"
      if {$TE::IS_ZUSYS} {
        set system "aarch64"
        set sstate_url $TE::PLX_SSTATE_CACHE_AARCH64
      } elseif {$TE::IS_ZSYS} {
        set system "arm"
        set sstate_url $TE::PLX_SSTATE_CACHE_ARM
      } elseif {$TE::IS_MSYS} {
        set system "mb-full"
        set sstate_url $TE::PLX_SSTATE_CACHE_MB_FULL
      }
      
      set file_name "${TE::PETALINUX_PATH}/project-spec/configs/config"
      if {[file exists ${file_name}]} {
        set fp_r [open ${file_name} "r"]
        set file_data [read $fp_r]
        close $fp_r
        set data [split $file_data "\n"]
        # modify
        set line_index -1
        set mod_count 0
        set temodifications [list]
        set date "[ clock format [clock seconds] -format "%Y_%m_%d %H_%M_%S"]"
        lappend  temodifications "# List of TE script modifications from $date:"
        
        if {$stage == 0 } {
          set data_new [list]
          #modification before building
          #delete old modification list
          
          set start_remove 0
          set line_check_startremove "# List of TE script modifications*"
          set line_check_endremove "# End of modification List*"
          foreach line $data {
            if {[string match $line_check_startremove $line]} {
               set start_remove 1
              TE::UTILS::te_msg TE_PLX-23 INFO "Start cleaning config"
            }
            if {$start_remove == 0} {
              lappend data_new $line
            }
            if {[string match $line_check_endremove $line]} {
               set start_remove 0
              TE::UTILS::te_msg TE_PLX-24 INFO "Finish cleaning config"
            }
            
          }
          #replace reduced list
          set data $data_new
          #add sstate and download if folder exists
          #remove local sstate in case its set
          set line_check_SSTATE_LOCAL "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=*"
          #remove local downloads in case its set
          set line_check_downloads "CONFIG_PRE_MIRROR_URL=*"
          foreach line $data {
            incr line_index
            if {[string match $line_check_SSTATE_LOCAL $line]} {
              if {[file exists $sstate_url]} {
                set line_check_SSTATE_LOCAL "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=\"${sstate_url}\"" 
                if {![string match $line_check_SSTATE_LOCAL $line]} {
                  set data [lreplace $data[set data {}] $line_index $line_index "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=\"${sstate_url}\""]
                  incr mod_count
                  lappend  temodifications "#    Replace default sstate Mirror URL $line with $sstate_url"
                  TE::UTILS::te_msg TE_PLX-25 INFO "Replace default sstate Mirror URL $line with $sstate_url "
                }
              }
            }
            if {[string match $line_check_downloads $line]} { 
              if {[file exists $download_url]} {
                set line_check_downloads "CONFIG_PRE_MIRROR_URL=\"file://${download_url}\"" 
                if {![string match $line_check_downloads $line]} {
                  set data [lreplace $data[set data {}] $line_index $line_index "CONFIG_PRE_MIRROR_URL=\"file://${download_url}\""]
                  incr mod_count
                  lappend  temodifications "#    Replace default download mirror path $line with $download_url"
                  TE::UTILS::te_msg TE_PLX-26 INFO "Replace default download mirror path $line with $download_url"
                }
              }
            }
          }
          
        } else {
          #modification after building
          # remove memory setting to reload memory with xsa import
          # bugfix for petalinux to reload memory. todo check from time to time if it's still needed
          set line_check_ddrmod "CONFIG_SUBSYSTEM_MEMORY_*"
          #remove local sstate in case its set
          set line_check_SSTATE_LOCAL "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=*"
          #remove local downloads in case its set
          set line_check_downloads "CONFIG_PRE_MIRROR_URL=*"
          foreach line $data {
            incr line_index
            if {[string match $line_check_ddrmod $line]} {
              set data [lreplace $data[set data {}] $line_index $line_index "# $line"]
              incr mod_count
              lappend  temodifications "#    Removed line $line"
            }
            if {[string match $line_check_SSTATE_LOCAL $line]} {
              set line_check_SSTATE_LOCAL "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=\"\"*"
              if {![string match $line_check_SSTATE_LOCAL $line]} {
                set data [lreplace $data[set data {}] $line_index $line_index "CONFIG_YOCTO_LOCAL_SSTATE_FEEDS_URL=\"\""]
                incr mod_count
                lappend  temodifications "#    Replace local sstate Mirror URL $line with default"
                TE::UTILS::te_msg TE_PLX-26 INFO "Replace local sstate Mirror URL $download_url with default"
              }
            }
            if {[string match $line_check_downloads $line]} {
              set line_check_downloads "CONFIG_PRE_MIRROR_URL=*file*" 
              if {[string match $line_check_downloads $line]} {
                set data [lreplace $data[set data {}] $line_index $line_index "CONFIG_PRE_MIRROR_URL=\"http://petalinux.xilinx.com/sswreleases/rel-v\$\{PETALINUX_MAJOR_VER\}/downloads\""]
                incr mod_count
                lappend  temodifications "#    Replace local download mirror path $line with default"
                TE::UTILS::te_msg TE_PLX-27 INFO "Replace local download mirror path $download_url with default"
              }
            }
          }
        }
        
        TE::UTILS::te_msg TE_PLX-18 INFO "$mod_count lines was modified in \"$file_name\": \n \
        ------" 
        lappend  temodifications "# End of modification List from $date with $mod_count modified lines."
        set fp_w [open ${file_name} "w"]
        #save modifications list
        foreach line $temodifications {
          puts $fp_w $line
        }
        #save config
        foreach line $data {
          puts $fp_w $line
        }
        close $fp_w
      } else {
        TE::UTILS::te_msg TE_PLX-19 WARNING "File  is missing: \"$file_name\": \n \
          ------" 
      }
        

    
    }
    
    #--------------------------------
    #--template_git_verification:
    #-- - check if all generated files are removed from GIT petalinux folder before running
    #-- - see also:https://wiki.trenz-electronic.de/display/PD/PetaLinux+TE-Template
    proc template_git_verification {{delete false}} {
      #2024.2 template
      set collect_errors [list]
      #check files and folder
      set checklist [list]
    
      lappend checklist "${TE::PETALINUX_PATH}/components/"
      lappend checklist "${TE::PETALINUX_PATH}/images/"
      lappend checklist "${TE::PETALINUX_PATH}/build/"
      lappend checklist "${TE::PETALINUX_PATH}/project-spec/hw-description/"
      #get all non hidden files from configs folder (easier than list all)
      set checklist [concat $checklist  [glob -join -dir ${TE::PETALINUX_PATH}/project-spec/configs/ *]]
      #exclude config and rootfsconfig file
      set idx [lsearch $checklist "*/config"]
      if {$idx !=-1} {
        set checklist [lreplace $checklist $idx $idx]
      }
      set idx [lsearch $checklist "*/rootfs_config"]
      if {$idx !=-1} {
        set checklist [lreplace $checklist $idx $idx]
      }
      #add hidden folder which are not included in glob search
      lappend checklist "${TE::PETALINUX_PATH}/project-spec/configs/.Xil"
      lappend checklist "${TE::PETALINUX_PATH}/project-spec/configs/.statistics"
      #xsa file
      lappend checklist "${TE::PETALINUX_PATH}/${TE::PB_FILENAME}.xsa"
      
      #check folder/files
      foreach element $checklist {
        if {[file exists $element]} {
          if {$delete} {
            puts "Delete: $element"
            file delete -force $element
          } else {
            lappend collect_errors "GIT not clean, please remove: '$element'"
          }
        }
      }
      # check if memory size is commented  to reload ddr sice from xsa import
      set file_name "${TE::PETALINUX_PATH}/project-spec/configs/config"
      if {[file exists ${file_name}]} {
        set fp_r [open ${file_name} "r"]
        set file_data [read $fp_r]
        close $fp_r
        set data [split $file_data "\n"]
        
        set lidx [lsearch -all $data "CONFIG_SUBSYSTEM_MEMORY_*"]
        foreach idx $lidx {
          set old_value  [lindex $data $idx]
          if {$delete} {
            puts "Comment out line [expr $idx+1]: '$old_value' in $file_name"
            set data [lreplace $data[set data {}] $idx $idx "# $old_value"]
          } else {
            lappend collect_errors "GIT not clean, please  comment out line [expr $idx+1]: '$old_value' in $file_name"
          }
        }
        
        
        #overwrite config only if delete is enabled
        if {$delete} {
          puts "Save Memory modification"
          set fp_w [open ${file_name} "w"]
          foreach line $data {
            puts $fp_w $line
          }
          close $fp_w
        } 
      }
      
      if {[llength $collect_errors] != 0} {
        return -code error "[join $collect_errors \n]"
      }
      
    }
    
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # finished plx functions
    # -----------------------------------------------------------------------------------------------------------------------------------------
    # -----------------------------------------------------------------------------------------------------------------------------------------
  }
  puts "INFO:(TE) Load Petalinux script finished"
}
