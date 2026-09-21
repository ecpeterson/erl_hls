# Cut only asynchronous arrival at a declared synchronizer's first stage.
# Preserve timing between stages and between each MMCM's related output clocks.
# Return the primary clock whose generated descendants share a phase relationship.
proc clock_root {clock} {
    while {[get_property IS_GENERATED [get_clocks $clock]]} {
        set clock [get_property MASTER_CLOCK [get_clocks $clock]]
    }
    return $clock
}
set census [open [file join $output cdc-exceptions.tsv] w]
foreach cell [get_cells -hier -filter {ASYNC_REG == TRUE}] {
    set destination [get_pins -quiet $cell/D]
    if {[llength $destination] != 1} {continue}
    set destination_clocks [get_clocks -quiet -of_objects [get_pins $cell/C]]
    if {[llength $destination_clocks] != 1} {error "ambiguous synchronizer clock: $cell"}
    set target_root [clock_root $destination_clocks]
    set crossing 0
    foreach start [all_fanin -flat -startpoints_only -to $destination] {
        foreach source_clock [get_clocks -quiet -of_objects $start] {
            if {[clock_root $source_clock] ne $target_root} {set crossing 1}
        }
    }
    if {$crossing} {
        if {[string match *xilinxmultiregimpl20_reg* $cell]} {
            # BusSynchronizer holds this word while its ping/pong handshake runs.
            # Bound the first data capture to one 125-MHz cycle, including skew.
            set sources [get_cells -hier -regexp {.*pcs_lp_abi_ibuffer_reg\[.*\]}]
            if {![llength $sources]} {error "missing PCS held bus"}
            set_max_delay -datapath_only 8.0 -from $sources -to $destination
            puts $census "held_pcs_bus\t$destination\t8.0"
        } else {
            set_false_path -to $destination
            puts $census "first_stage\t$destination"
        }
    }
    # Async assertion is intentional. Release passes through these two flops;
    # downstream reset recovery/removal remains timed on ordinary registers.
    foreach pin [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}] {
        set_false_path -to $pin
        puts $census "reset_synchronizer\t$pin"
    }
}
if {$profile in {ethernet-loopback ethernet-external}} {
    foreach name {tx_stats rx_stats} {
        set sources [get_cells -hier -regexp "$name/held_reg\\\[.*\\\]"]
        set destinations [get_cells -hier -regexp "$name/sampled_reg\\\[.*\\\]"]
        if {![llength $sources] || ![llength $destinations]} {error "missing snapshot: $name"}
        # Acknowledge traverses two control-clock flops before capture. One
        # control period leaves a full cycle of settling margin for this bus.
        set_max_delay -datapath_only 40.0 -from $sources -to $destinations
        puts $census "snapshot\t$name\t40.0"
    }
}
close $census
