# --------------------------------------------------------------------
# --   *****************************
# --   *   Trenz Electronic GmbH   *
# --   *   Beendorfer Str. 23      *
# --   *   32609 Hüllhorst         *
# --   *   Germany                 *
# --   *****************************
# --------------------------------------------------------------------
# -- $Author: Hartfiel, John $ Hanemann, Waldemar $
# -- $Email: j.hartfiel@trenz-electronic.de $
# --------------------------------------------------------------------
# -- Links to documentation
# -- Public:https://wiki.trenz-electronic.de/display/PD/Project+Delivery+-+Xilinx+devices
# -- Internal: (currently not visible here)
# -----------------------------------------------------------------------------------------------------------------------------
# -- Change history  :
# ------------------|---------------|---------|---------|----------------------------------------------------------------------
# -- Date           | SCRIPTVER     | Author  |Critical | Description
# ------------------|---------------|---------|---------|----------------------------------------------------------------------
# --                |               |         |         |
# --                |               |         |         |
# ------------------|---------------|---------|---------|----------------------------------------------------------------------
# -- 2024-07-17     |               |WH       |         |- Added Bitfile programming and .ELF file execution via XSDB console
# --                |               |         |         |- in proc jtag_xsdb_datatransfer
# ------------------|---------------|---------|---------|----------------------------------------------------------------------
# -- 2023-05-09     |               |JH       |         |- initial...moved from MT to general scripts
# ------------------|---------------|---------|---------|----------------------------------------------------------------------


namespace eval ::TE {

  namespace eval ::TE::JTAG {
    set AXI_OBJ hw_axi_1
    #todo Waldemar fragen ob die 32bit bei den  extractIntegers zufällig die gleichen sind...ist wahrscheinlich so
    set AXI_SIZE 32
    
    set XSDB_PROC "MicroBlaze*#0"
    set XSDB_RESET true
    
    #set customscript false
    
    #--------------------------------
    #--init_xsdb
    proc init_xsdb {{obj "MicroBlaze*#0"} {reset true}} {
      set ::TE::JTAG::XSDB_PROC  $obj
      set ::TE::JTAG::XSDB_RESET  $reset
    }
    
    #--------------------------------
    #--init_axi
    proc init_axi {{obj hw_axi_1} {size 32}} {
      set ::TE::JTAG::AXI_OBJ  $obj
      set ::TE::JTAG::AXI_SIZE  $size
    }
    #--------------------------------
    #--Text_to_ASCII mache mir aus dem text string, hex werte
    proc Text_to_ASCII {string} {
      binary scan $string H* hex
      set Ascii_Word [regsub -all (..) $hex {\1}]
      return $Ascii_Word
    }

    #--------------------------------
    #--write_data
    proc write_data {address value {length 1}  {quiet false}} {
      set address [string range $address 2 [expr {[string length $address]-1}]]
      if {!$quiet} {
        puts "Write Process START...Addr:$address|Val:$value|Length:$length"
      }
      #todo hier weiter quiet und auch axi objekt!
      create_hw_axi_txn -force wr_tx [get_hw_axis ${::TE::JTAG::AXI_OBJ}] -address $address -data $value -len $length -type write
      run_hw_axi -quiet wr_tx
      
      # remove previously created txn if exist
      if {[llength [get_hw_axi_txns wr_tx* -quiet]] > 0} {
        delete_hw_axi_txn [get_hw_axi_txns wr_tx*]
      }
    }
    #--------------------------------
    #--read_data
    proc read_data {address {length 1} {quiet false}} {
        set address [string range $address 2 [expr {[string length $address]-1}]]
        if {!$quiet} {
          puts "Read Process START...Addr:$address|Length:$length"
        }
        create_hw_axi_txn -quiet -force rd_tx [get_hw_axis ${::TE::JTAG::AXI_OBJ}] -address $address -len $length -size  ${::TE::JTAG::AXI_SIZE} -type read
        run_hw_axi -quiet rd_tx
        set tmp "0x[get_property DATA [get_hw_axi_txn rd_tx]]"
        
        # remove previously created rxn if exist
        if {[llength [get_hw_axi_txns rd_tx* -quiet]] > 0} {
          delete_hw_axi_txn [get_hw_axi_txns rd_tx*]
        }
        return $tmp
    }
    
    
    #--------------------------------
    #--write_filedata_to_fpga hole mir 32 bit werte aus dem lange hex string und schreibe diese direkt in den RAM
    proc write_filedata_to_fpga {address number {bits 32} {quiet false} {calculate_address_only false}} {
      # STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE 
          
      #number always hex string, so remove prefix 0x (-2 elements) from length
      set cnt [expr 8 - fmod(([string length $number]-2),8)]
      if {$cnt == 8} {
          set cnt 0
      }
      if {!$quiet} {
        puts "WriteFileData 32byte length:[expr ([string length $number]-2)/8] "
        puts "WriteFileData add Zeros:$cnt"
      }
      set ext ""
      #add zeros to get multiple of 8
      for {set i 0} {$i < $cnt} {incr i} {
        set ext "0$ext"  
      }
      set number "${number}${ext}"

      set accumulator {}
      #mask to see only first bits
      set mask [expr {(1 << $bits) - 1}]
      while {$number != 0} {
          set value [expr {$number & $mask}]
          #remove first bits
          set number [expr {$number >> $bits}]
          set value [format "%08x" $value]
          # append accumulator $value
          lappend accumulator $value
      }
      # puts "Test|$accumulator"
      # puts "Test|[lreverse $accumulator]"
      set number [lreverse $accumulator]
        
      
      set ext_address $address
      if {!$quiet} {
        puts "WriteFileData Transfer Startaddress:$ext_address"
        puts "WriteFileData 32bit elements:[llength $number]"
        # puts "$number"
      }
      
      set index 0
      set package_cnt 256
      set sendfiles [list]
      foreach element $number {
        set index [expr $index +1]
        #resort bytes because they are swapped on linux after transfer
        set value [string index $element 6][string index $element 7][string index $element 4][string index $element 5][string index $element 2][string index $element 3][string index $element 0][string index $element 1]
        
        lappend sendfiles $value
        #send file each 256 32bit word or when list rest
        if {$index == [llength $number] || [expr fmod($index,$package_cnt)]==0.0} {
          #transfer files
          if {!$calculate_address_only} {
            #TE::JTAG::write_data $ext_address $sendfiles [llength $sendfiles] $quiet
            TE::JTAG::write_data $ext_address $sendfiles [llength $sendfiles] $quiet
          }
          #calculate new addr
          set offset [expr {[llength $sendfiles] * 4}]
          set ext_address [format 0x%x [expr {$ext_address + $offset}]]
          if {!$quiet} {
            puts "Send Data: "
            puts $sendfiles  
            puts "New Address: "
            puts $ext_address   
            puts "Index: "
            puts $index        
          }
          #clean list for next transfer
          set sendfiles [list]
        }
      }
      return $ext_address
    }
      #--------------------------------
    #--create_xsdb_rwr : todo speater mal  write_filedata_to_fpga mit der kombinieren...
    proc create_xsdb_rwr {address number {bits 32} {quiet false} } {
      # STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE  STARTADRESSE 
      #number always hex string, so remove prefix 0x (-2 elements) from length
      set cnt [expr 8 - fmod(([string length $number]-2),8)]
      if {$cnt == 8} {
          set cnt 0
      }

      set ext ""
      #add zeros to get multiple of 8
      for {set i 0} {$i < $cnt} {incr i} {
        set ext "0$ext"  
      }
      set number "${number}${ext}"

      set accumulator {}
      #mask to see only first bits
      set mask [expr {(1 << $bits) - 1}]
      while {$number != 0} {
          set value [expr {$number & $mask}]
          #remove first bits
          set number [expr {$number >> $bits}]
          set value [format "%08x" $value]
          # append accumulator $value
          lappend accumulator $value
      }
      set number [lreverse $accumulator]
        
      
      set ext_address $address

      
      set transfer_list [list]    
      foreach element $number {
        #resort bytes because they are swapped on linux after transfer
        set value [string index $element 6][string index $element 7][string index $element 4][string index $element 5][string index $element 2][string index $element 3][string index $element 0][string index $element 1]
        
        
        set content [list]
        lappend content $ext_address
        lappend content $value
        lappend transfer_list $content
        
        
        #calculate new addr
        set offset [expr {1 * 4}]
        set ext_address [format 0x%x [expr {$ext_address + $offset}]]
      }
      
      return $transfer_list
    }
    
    #--------------------------------
    #--jtag_master_datatransfer
    proc jtag_master_datatransfer {startaddress {filelist [list]} {quiet false} {enableheader true} {offline false}} { 
      set int_addr $startaddress
      set int_data ""
      set filecnt [llength $filelist]
      
      foreach file  $filelist {
        #tcl can't read huge file easly todo read
        set fp [open $file r]
        set int_data [read $fp]
        close $fp 
        
        set fbasename "[file tail $file]"
        set fbasenamelength "[string length $fbasename]"
        set filelength "[string length $int_data]"
        set fileashex 0x[TE::JTAG::Text_to_ASCII $int_data]

        set start_word "0x[::TE::JTAG::Text_to_ASCII #StT][format %08X $fbasenamelength][format %08X $filelength][::TE::JTAG::Text_to_ASCII $fbasename]"
        set end_word "0x[::TE::JTAG::Text_to_ASCII #EnD]"
        if {!$quiet} {
          puts "Write File $file"
          puts "Start $start_word"
          puts "Filename $fbasename"
          puts "End $end_word"
        }
        
        
        set calculate_address_only false 
        if {$offline} {
          set calculate_address_only true 
          if {!$quiet} {
            puts "offline mode"
          }
        } 
        if {$enableheader} {
          set int_addr [write_filedata_to_fpga $int_addr ${start_word} $TE::JTAG::AXI_SIZE $quiet $calculate_address_only]
        }
        set int_addr [write_filedata_to_fpga $int_addr ${fileashex}  $TE::JTAG::AXI_SIZE $quiet $calculate_address_only]
        if {$enableheader} {
          set int_addr [write_filedata_to_fpga $int_addr ${end_word} $TE::JTAG::AXI_SIZE $quiet $calculate_address_only]
        }
      }
    }
    #--------------------------------
    #--jtag_xsdb_datatransfer
    proc jtag_xsdb_datatransfer {startaddress {filelist [list]} {quiet false} {enableheader true} {reset true} {offline false}} { 
    
    
      set customscriptGO false
      set int_addr $startaddress
      set int_data ""
      set filecnt [llength $filelist]
      #list for generating xsdb script
      set transfer_list [list]
      #
      set workfolder ${TE::TMP_PATH}/xsdb/
      if {! [file exists  ${workfolder}] } {
        file mkdir ${workfolder}
      } else {
        if {[catch {file delete -force $workfolder} result]} {TE::UTILS::te_msg TE_MT-??? {CRITICAL WARNING} "Problem with deleting temp folder $result"}
        file mkdir ${workfolder}
      }
      

      # write tcl file for transfer
      set program "${TE::TMP_PATH}/xsdb/program.tcl"
      set fp_w [open  ${program} "w"]
      puts $fp_w  "connect"
      
      
      

      
      #create offsets and add files to tcl
      
      # FOR EACH FILE START
       
      foreach file  $filelist {
        #tcl can't read huge file easly todo read
        #
        # set fp [open $file r]
        # set int_data [read $fp]
        # close $fp 
        
        # wenn das ein bitfile ist dann bitte nicht mit microblaze verbinden
        if {![string match -nocase  "*.bit" $file]} {
        #if uboot is to be started on cpu 
        
        puts $fp_w  "targets -set -filter {name =~ \"${TE::JTAG::XSDB_PROC}\"} -index 0"
        
         # if {$TE::JTAG::XSDB_RESET} {
         # puts $fp_w  "rst -processor"
        #}
        
        }
       
        set fbasename "[file tail $file]"
        set fbasenamelength "[string length $fbasename]"
        # set filelength "[string length $int_data]"
        set filelength [file size $file]
        # set fileashex [TE::JTAG::Text_to_ASCII $int_data]
        #todo xsdb write directly hex to memory for start end end word
        set start_word "[::TE::JTAG::Text_to_ASCII #StT][format %08X $fbasenamelength][format %08X $filelength][::TE::JTAG::Text_to_ASCII $fbasename]"
        set end_word "[::TE::JTAG::Text_to_ASCII #EnD]"
        if {!$quiet} {
          puts "Write File $file"
          puts "Start $start_word"
          puts "Filename $fbasename"
          puts "End $end_word"
        }
        set calculate_address_only true
        if {$enableheader} {
          set transferlist [list]
          set transferlist [create_xsdb_rwr $int_addr 0x${start_word}  $TE::JTAG::AXI_SIZE $quiet ]
          foreach tline  $transferlist {
            #todo check eventuell muss noch der basisoffset entfernt werden, mwr startet glaube bei 0x0...und muss ueber memmap angepasst werden, falls mehr speicher da ist
            set tl_addr [lindex $tline 0]
            
            set tl_data [lindex $tline 1]
            puts $fp_w  "mwr $tl_addr $tl_data"
          }
          set int_addr [write_filedata_to_fpga $int_addr 0x${start_word}  $TE::JTAG::AXI_SIZE $quiet $calculate_address_only]
        }
       
        # WALDI MOD
        
        if {[string match -nocase  "*.tcl" $file]} {
        # Wenn ein custom tcl script ausgeführt werden soll 
        set customscriptGO true
        
     
        # custom external xsdb script 
        set custom_program "$file"
   
        
        } elseif {[string match -nocase  "fsbl.elf" $file]} {
        #if uboot is to be started on cpu 
        
        puts $fp_w  "dow $file"
        puts $fp_w  "con"
        puts $fp_w  "after 5000;"
        puts $fp_w  "stop"
        
        } elseif {[string match -nocase  "*.elf" $file]} {
        #if uboot is to be started on cpu 
        
        puts $fp_w  "dow $file"
        puts $fp_w  "con"
        
        } elseif {[string match -nocase  "*.bit" $file]} {
        
        puts $fp_w  "fpga $file"
        puts $fp_w  "after 11000;"
        
        } else {
        #create new addres
        puts $fp_w  "dow -data $file $int_addr"
        #puts $fp_w  "con"
        }

        

        
        # set int_addr [write_filedata_to_fpga $int_addr 0x${fileashex}  $TE::JTAG::AXI_SIZE $quiet $calculate_address_only]
        #addiert aktuell im worst case 32 bit mehr aber macht ja nix (falls fmod 0 ist)
        set calcoffset [expr int($filelength + [expr 8 - [expr fmod($filelength,8)]])]
        set int_addr [expr $int_addr + $calcoffset]
        
        # puts "Test|$int_addr|$calcoffset|||"
        
        if {$enableheader} {
          set transferlist [list]
          set transferlist [create_xsdb_rwr $int_addr 0x${end_word}  $TE::JTAG::AXI_SIZE $quiet ]
          foreach tline  $transferlist {
            #todo check eventuell muss noch der basisoffset entfernt werden, mwr startet glaube bei 0x0...und muss ueber memmap angepasst werden, falls mehr speicher da ist
            set tl_addr [lindex $tline 0]
            
            set tl_data [lindex $tline 1]
            puts $fp_w  "mwr $tl_addr $tl_data"
          }
          set int_addr [write_filedata_to_fpga $int_addr 0x${end_word}  $TE::JTAG::AXI_SIZE $quiet $calculate_address_only]
        }
        
        
      }
      
      
      # FOR EACH FILE END
      
      #final 
      #if {$TE::JTAG::XSDB_RESET} {
      #  puts $fp_w  "rst -processor"
      #}
      
      puts $fp_w  "disconnect"
      close $fp_w
    
      if {$offline} {
        if {!$quiet} {
          puts "offline mode"
        }
      } else {
        #run 
        set command exec
        lappend command xsdb
        if {$quiet} {
          lappend command "-quiet"
        }
        # wenn ein externes tcl script in xsdb ausgeführt werden soll if {$TE::MT::SIGLENT_ENABLED_SPD3303X}
        if {$customscriptGO} {
          set customscriptGO false
          lappend command  ${custom_program}
        } else {
          lappend command  ${program}
        }
        eval $command
      }
    }
    
    #--------------------------------
    #--value_b32_range: convert hex to binary and return bits
    proc value_b32_range {value from downto} {
     set newvalue [string map {"_" ""} $value ]
     set newvalue [string map {"0x" ""} $newvalue ]
     binary scan [binary format H* $newvalue] B* bits
     return [string range $bits [expr 31 - $from] [expr 31 - $downto] ]
    }
    #--------------------------------
    #--value_h8_range: returns part of the 8char string  
    proc value_h8_range {value from downto} {
     set newvalue [string map {"_" ""} $value ]
     set newvalue [string map {"0x" ""} $newvalue ]
     return [string range $newvalue [expr 7 - $from] [expr 7 - $downto] ]
    }
    #--------------------------------
    #--bin2hex: converts binary string to hex string
    proc bin2hex {bin} {
        set result ""
        set prepend [string repeat 0 [expr (4-[string length $bin]%4)%4]]
        foreach g [regexp -all -inline {[01]{4}} $prepend$bin] {
            foreach {b3 b2 b1 b0} [split $g ""] {
                append result [format %X [expr {$b3*8+$b2*4+$b1*2+$b0}]]
            }
        }
        return $result
    } 
    #--------------------------------
    #--hex2dec: converts hex string to decimal number
    proc hex2dec {largeHex} {
        set newvalue [string map {"_" ""} $largeHex ]
        set newvalue [string map {"0x" ""} $newvalue ]
        set res 0
        foreach hexDigit [split $newvalue {}] {
            set new 0x$hexDigit
            set res [expr {16*$res + $new}]
        }
        return $res
    } 
  }
  # -----------------------------------------------------------------------------------------------------------------------------------------
  puts "INFO:(TE) Load JTAG Script finished"
}