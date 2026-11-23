# Explicit full-board guard/reset declarations; source after domain_board_constraints.tcl.
# Unknown chains roll back atomically and remain timed in cdc-unresolved.tsv.
# Only fully validated first stages are cut; ordinary state stays timed.
# This combines implemented v4 declarations with the separately measured
# post-route RAMD32/WE association. The combined profile has not itself driven
# a native implementation; it makes no placement or bitstream identity claim.
set board_pending_cuts {}
set board_cdc_errors 0
set board_inventory [open [file join $output cdc-property-chain-inventory.tsv] w]
puts $board_inventory "class\tobject\traw_value_or_sources\tinterpretation"
# Record and require a native ASYNC_REG property that is a true Tcl boolean.
proc board_async_true {cell} {
    global board_inventory
    set raw [get_property ASYNC_REG $cell]
    set code [catch {expr {bool($raw)}} value]
    puts $board_inventory "ASYNC_REG\t$cell\t$raw\t$value"
    flush $board_inventory
    if {![string is boolean -strict $raw] || $code || !$value} {
        error "ASYNC_REG is not a true Tcl boolean on $cell: $raw"
    }
}
set board_cdc_log [open [file join $output cdc-exceptions.tsv] w]
set board_cdc_missing [open [file join $output cdc-unresolved.tsv] w]
puts $board_cdc_log "class\tfrom\tto\tbound_ns"
puts $board_cdc_missing "class\tobject\treason"

# A source declaration names a two-stage destination chain. Only asynchronous
# source startpoints to its first D are cut; same-root arrivals remain timed.
proc board_stage {first second allowed_roots {hard_sources {}} {hard_launch {}}} {
    global board_cdc_log board_cdc_missing board_inventory board_pending_cuts board_cdc_errors
    set pending_start [llength $board_pending_cuts]
    set records {}
    if {[catch {
        set f [board_cell $first]
        set s [board_cell $second]
        foreach cell [list $f $s] {
            board_async_true $cell
        }
        set destination [board_pin "$f/D"]
        set root [board_root [board_ff_clock $f]]
        if {[board_root [board_ff_clock $s]] ne $root} {error "chain changes clock"}
        set second_d [board_pin "$s/D"]
        set drivers [get_pins -leaf -of_objects [get_nets -of_objects $second_d] -filter {DIRECTION == OUT}]
        puts $board_inventory "direct_chain\t$second_d\t[join $drivers ,]\t$root"
        if {[lsort $drivers] ne [list [board_pin "$f/Q"]]} {error "second stage is not driven directly by the declared first Q"}
        set starts [all_fanin -flat -startpoints_only -to $destination]
        puts $board_inventory "first_stage_fanin\t$destination\t[join $starts ,]\t$root"
        flush $board_inventory
        if {[llength $hard_sources]} {
            # Hard status outputs are not valid timing startpoints. The direct
            # driver must be exact. GTX RESETDONE has a separately recorded
            # USRCLK2 timing startpoint; other statuses retain their own fanin.
            set first_drivers [get_pins -leaf -of_objects [get_nets -of_objects $destination] -filter {DIRECTION == OUT}]
            set expected_starts [expr {[llength $hard_launch] ? $hard_launch : $hard_sources}]
            puts $board_inventory "hard_status_direct_drivers\t$destination\t[join $first_drivers ,]\t[join $hard_sources ,]"
            if {[lsort $starts] ne [lsort $expected_starts] || [lsort $first_drivers] ne [lsort $hard_sources]} {
                error "hard status has unapproved timing startpoints or direct drivers"
            }
            foreach launch $hard_launch {
                set launch_clock [board_clock_at $launch]
                set launch_root [board_root $launch_clock]
                set period [get_property PERIOD [get_clocks $launch_clock]]
                puts $board_inventory "hard_status_launch_clock\t$launch\t$launch_clock\t$launch_root:$period"
                if {$launch_root ni $allowed_roots || abs($period-16.0) > 0.0001} {
                    error "GTX done status has wrong directional launch clock"
                }
            }
            lappend board_pending_cuts [list -to $destination]
            lappend records "hard_status_first_stage\t[join $hard_sources ,]\t$destination\t-"
        } else {
            foreach start $starts {
                set owner [board_one [get_cells -quiet -of_objects $start] "owner of $start"]
                if {![string match FD* [get_property REF_NAME $owner]]} {error "foreign source is not a reviewed flip-flop: $start"}
                set source_root [board_root [board_ff_clock $owner]]
                if {$source_root eq $root} {continue}
                if {$source_root ni $allowed_roots} {error "unreviewed source root $source_root ($start)"}
                # UG903 2024.2 False Paths explicitly uses get_cells as -from.
                # A FF cell selects valid launch pins; never pass its Q pin.
                lappend board_pending_cuts [list -from $owner -to $destination]
                lappend records "first_stage\t$owner\t$destination\t-"
            }
        }
    } reason]} {
        puts $board_cdc_missing "first_stage\t$first\t$reason"
        incr board_cdc_errors
        set board_pending_cuts [lrange $board_pending_cuts 0 [expr {$pending_start-1}]]
    } else {
        foreach record $records {puts $board_cdc_log $record}
    }
}

# Board status synchronizers; hard outputs have no fabric launching clock.
foreach {index source launch source_root} {
    0 TXRESETDONE TXUSRCLK2 tx_word
    1 RXRESETDONE RXUSRCLK2 rx_word
} {
    # Both independent done bits have their own matching second-stage bit.
    board_stage [format {done_meta_reg[%d]} $index] [format {done_sync_reg[%d]} $index] [list $source_root] \
        [list [board_pin "$board_gtx/$source"]] [list [board_pin "$board_gtx/$launch"]]
}
foreach {index direction} {0 tx 1 rx} {
    board_stage [format {lock_meta_reg[%d]} $index] [format {lock_sync_reg[%d]} $index] {} \
        [list [board_pin "clocks/$direction/generator/LOCKED"]]
}
board_stage {packets/control/lock_sync_reg[0]} {packets/control/lock_sync_reg[1]} {} \
    [list [board_pin "$board_gtx/CPLLLOCK"]]
# Exact new RTL declarations replace the old mixed-domain health_meta chain.
foreach direction {tx rx} {
    foreach name {ready lost armed} {
        board_stage framing/${direction}_${name}_meta_reg framing/${direction}_${name}_sync_reg [list ${direction}_word]
    }
    foreach name {arm stop} {
        board_stage framing/${direction}_guard/${name}_meta_reg framing/${direction}_guard/${name}_sync_reg {control}
    }
}
board_stage framing/rx_wire_meta_reg framing/rx_wire_sync_reg {rx_word}
foreach direction {tx rx} {
    board_stage packets/loss/${direction}_loss_meta_reg packets/loss/${direction}_loss_sync_reg [list ${direction}_word]
    foreach pair {full_request half_request full_ack half_ack} {
        board_stage [format {packets/%s_watch/%s_reg[0]} $direction $pair] \
            [format {packets/%s_watch/%s_reg[1]} $direction $pair] [list control ${direction}_word]
    }
    foreach chain {req ack} {
        board_stage framing/bridge/${direction}_slot/${chain}_meta_reg \
            framing/bridge/${direction}_slot/${chain}_sync_reg {control tx_word rx_word}
    }
}
# align_registered is TX-clocked in dma_endpoint.v:127, not RX-full-clocked.
board_stage {packets/packets/align_sync_reg[0]} {packets/packets/align_sync_reg[1]} {tx_word}
set board_mac packets/packets/packets/core
foreach index {0 1 3 4 5 6} {
    board_stage $board_mac/xilinxmultiregimpl${index}0_reg \
        $board_mac/xilinxmultiregimpl${index}1_reg {tx_word rx_word}
}

# Only the exact zynq_probe_reset declarations may waive asynchronous assertion
# at their release synchronizer CLR/PRE pins. Ordinary state recovery/removal
# (including loss/health capture) remains visible. Optimized names are recorded.
set reset_instances {reset_sync packets/cr packets/tr packets/rr packets/th packets/rh
    packets/tx_watch/fr packets/tx_watch/hr packets/rx_watch/fr packets/rx_watch/hr
    framing/bridge/hr framing/bridge/tr framing/bridge/rr
    framing/bridge/tx_slot/wr_reset framing/bridge/tx_slot/rd_reset
    framing/bridge/rx_slot/wr_reset framing/bridge/rx_slot/rd_reset
    framing/host_cold
    framing/tx_guard/cold_release framing/tx_guard/active_release framing/tx_guard/run_release
    framing/rx_guard/cold_release framing/rx_guard/active_release framing/rx_guard/run_release
    packets/loss/control_cold packets/loss/tx_cold packets/loss/rx_cold}
foreach instance $reset_instances {
    set pending_start [llength $board_pending_cuts]
    set chain_failed 0
    set records {}
    foreach bit {0 1} {
        set name [format {%s/release_sync_reg[%d]} $instance $bit]
        if {[catch {
            set cell [board_cell $name]
            board_async_true $cell
            set d [board_pin "$cell/D"]
            set drivers [get_pins -leaf -of_objects [get_nets -of_objects $d] -filter {DIRECTION == OUT}]
            puts $board_inventory "reset_D_drivers\t$d\t[join $drivers ,]\t[board_ff_clock $cell]"
            if {$bit == 1 && [lsort $drivers] ne [list [board_pin "$instance/release_sync_reg\[0\]/Q"]]} {
                error "reset release second stage is not driven by its declared first Q"
            }
            set pins [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
            set pin [board_one $pins "asynchronous assertion pin on $name"]
            puts $board_inventory "reset_async_fanin\t$pin\t[join [all_fanin -flat -startpoints_only -to $pin] ,]\tassertion_only"
            lappend board_pending_cuts [list -to $pin]
            lappend records "reset_release_chain\tasync_assertion\t$pin\t-"
        } reason]} {
            puts $board_cdc_missing "reset_release_chain\t$name\t$reason"
            incr board_cdc_errors
            set chain_failed 1
        }
    }
    if {$chain_failed} {
        set board_pending_cuts [lrange $board_pending_cuts 0 [expr {$pending_start-1}]]
    } else {
        foreach record $records {puts $board_cdc_log $record}
    }
}

# Validate all selected synchronizers before removing or adding any exception.
# Unknown chains are atomic: none of their candidate cuts survive. They stay
# timed and block admission, while this diagnostic continuation may still route.
flush $board_inventory
flush $board_cdc_missing
# The caller supplies a freshly synthesized, unconstrained design before this
# profile installs clocks/pads. Source FF cells retain normal launch clocks and
# avoid the pin-startpoint segmentation reported by TIMING-13/42.
set pcs_sources [get_cells -hier -regexp {^packets/packets/packets/core/pcs_lp_abi_ibuffer_reg\[[0-9]+\]$}]
set pcs_targets [get_cells -hier -regexp {^packets/packets/packets/core/xilinxmultiregimpl20_reg\[[0-9]+\]$}]
if {[llength $pcs_sources] != 16 || [llength $pcs_targets] != 16} {error "PCS held bus is not the retained 16-bit pair"}
foreach arguments $board_pending_cuts {set_false_path {*}$arguments}

# Bound only the declared held register bus and its actual foreign-clock sinks.
# The toggle handshake gives at least two destination edges before consumption;
# a one-destination-period datapath/skew bound leaves a full settling interval.
# Associate only reviewed sequential sink pins with their actual port clocks.
proc board_held_clock {sink owner} {
    global board_inventory
    set kind [get_property REF_NAME $owner]
    set pin [get_property REF_PIN_NAME $sink]
    if {[string match FD* $kind]} {
        return [board_ff_clock $owner]
    }
    if {$kind in {RAMS32 RAMD32} && $pin eq "WE"} {
        # Both native role inventories expose RAMS32/RAMD32 WE with one CLK.
        # This association covers write enable only, never an async read port.
        set clock_pin [board_pin "$owner/CLK"]
        set actual_clocks [get_pins -quiet -of_objects $owner -filter {IS_CLOCK == 1}]
        if {[lsort $actual_clocks] ne [list $clock_pin]} {error "$kind WE lacks its unique recorded CLK"}
    } elseif {$kind eq "RAMB18E1" && $pin eq "ENARDEN"} {
        # UG953 2024.2: ENARDEN is port-A/read enable; CLKARDCLK is
        # port-A/read clock. Never substitute this RAM's independent B clock.
        set clock_pin [board_pin "$owner/CLKARDCLK"]
        set actual_clocks [get_pins -quiet -of_objects $owner -filter {IS_CLOCK == 1}]
        if {$clock_pin ni $actual_clocks} {error "RAMB18E1 read-enable clock not present"}
    } else {
        error "unreviewed held-length endpoint association: $kind/$pin"
    }
    set clock [board_clock_at $clock_pin]
    puts $board_inventory "held_port_clock\t$sink\t$clock_pin\t$clock:[board_root $clock]"
    return $clock
}
# Validate every actual sink before bounding the held bus; unknowns stay timed
# and return zero after being recorded. Success installs max delay and bus skew.
proc board_held {expression expected_root limit label {destination_expression {}}} {
    global board_cdc_log board_cdc_missing board_inventory
    if {[catch {
        set cells [get_cells -quiet -hier -regexp $expression]
        if {![llength $cells]} {error "missing held source bus"}
        set sources [get_pins -of_objects $cells -filter {REF_PIN_NAME == Q}]
        if {$destination_expression ne {}} {
            set sinks [get_pins -of_objects [get_cells -quiet -hier -regexp $destination_expression] -filter {REF_PIN_NAME == D}]
        } else {
            set sinks [all_fanout -flat -endpoints_only -from $sources]
        }
        set bounded {}
        foreach sink $sinks {
            set owner [board_one [get_cells -quiet -of_objects $sink] "held sink owner"]
            set clocks [get_pins -quiet -of_objects $owner -filter {IS_CLOCK == 1}]
            puts $board_inventory "held_endpoint\t$sink\t[get_property REF_NAME $owner]\t[join $clocks ,]"
            set clock [board_held_clock $sink $owner]
            if {[board_root $clock] ne $expected_root} {continue}
            lappend bounded $sink
        }
        if {![llength $bounded]} {error "missing held destination bus"}
        set_max_delay -datapath_only $limit -from $cells -to $bounded
        set_bus_skew $limit -from $cells -to $bounded
        puts $board_cdc_log "${label}_sources\t[join $sources ,]\t[llength $bounded]_sinks\t$limit"
        foreach sink $bounded {puts $board_cdc_log "$label\t${label}_sources\t$sink\t$limit"}
    } reason]} {
        puts $board_cdc_missing "$label\t$expression\t$reason"
        flush $board_cdc_missing
        return 0
    }
    return 1
}
if {![board_held {^packets/packets/packets/core/pcs_lp_abi_ibuffer_reg\[[0-9]+\]$} tx_word 8.0 pcs_ability \
    {^packets/packets/packets/core/xilinxmultiregimpl20_reg\[[0-9]+\]$}]} {
    error "PCS held-bus replacement failed; route is prohibited"
}
set tx_length_bounded [board_held {^framing/bridge/tx_slot/length_reg\[[0-9]+\]$} tx_word 8.0 tx_packet_length]
set rx_length_bounded [board_held {^framing/bridge/rx_slot/length_reg\[[0-9]+\]$} control 40.0 rx_packet_length]
close $board_cdc_log
close $board_cdc_missing
close $board_inventory
puts "CDC_REPAIR_APPLIED validated_cuts=[llength $board_pending_cuts] unresolved_chain_rows=$board_cdc_errors PCS_bound_ns=8.0 tx_length_bounded=$tx_length_bounded rx_length_bounded=$rx_length_bounded"
