# Full source-domain TE0715 shell clocks/pads; loaded by domain_board_profile.tcl.
# Native constraints retain independent GTX roots and related MMCM descendants.
# This file supplies exact selectors for the explicit full-board CDC/check files.
# Require one native object; ambiguous or missing identity is an error.
proc board_one {objects label} {
    if {[llength $objects] != 1} {error "$label: expected one object, found [llength $objects]"}
    return [lindex $objects 0]
}
# Resolve an exact cell name without treating brackets as wildcard syntax.
proc board_cell {name} {
    return [board_one [get_cells -quiet -hier -filter [format {NAME == "%s"} $name]] $name]
}
# Resolve an exact pin name without treating brackets as wildcard syntax.
proc board_pin {name} {
    return [board_one [get_pins -quiet -hier -filter [format {NAME == "%s"} $name]] $name]
}
# Find the primary ancestor, rejecting malformed generated-clock cycles.
proc board_root {clock} {
    set visited {}
    while {[get_property IS_GENERATED [get_clocks $clock]]} {
        if {$clock in $visited} {error "clock ancestry loop: $clock"}
        lappend visited $clock
        set clock [board_one [get_clocks [get_property MASTER_CLOCK [get_clocks $clock]]] "master of $clock"]
    }
    return $clock
}
# Require exactly one actual clock at the selected native pin.
proc board_clock_at {pin} {
    return [board_one [get_clocks -quiet -of_objects $pin] "clock at $pin"]
}
# Return the clock at a declared flip-flop C pin.
proc board_ff_clock {cell} {
    return [board_clock_at [board_pin "$cell/C"]]
}

set board_ps [board_one [get_cells -hier -filter {REF_NAME == PS7}] PS7]
set board_gtx [board_one [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL}] GTXE2_CHANNEL]
foreach {port pad} {ref_p U5 ref_n V5 gt_rx_p W8 gt_rx_n Y8 gt_tx_p W4 gt_tx_n Y4} {
    set_property PACKAGE_PIN $pad [board_one [get_ports -quiet $port] $port]
}
set_property LOC GTXE2_CHANNEL_X0Y1 $board_gtx
foreach {direction site} {tx MMCME2_ADV_X1Y2 rx MMCME2_ADV_X1Y3} {
    set cell [board_cell clocks/$direction/generator]
    if {[get_property REF_NAME $cell] ni {MMCME2_BASE MMCME2_ADV}} {
        error "unexpected clock primitive: $cell"
    }
    set_property LOC $site $cell
}

# PS7's boot configuration must actually supply 25 MHz; XDC does not program it.
create_clock -name control -period 40.000 [board_pin "$board_ps/FCLKCLK\[0\]"]
create_clock -name reference -period 8.000 [board_one [get_ports ref_p] ref_p]
# CPLL has no modeled propagation arc. These independent OUTCLK roots are NOT
# generated from reference or from each other. Do not group their descendants.
create_clock -name tx_word -period 16.000 [board_pin "$board_gtx/TXOUTCLK"]
create_clock -name rx_word -period 16.000 [board_pin "$board_gtx/RXOUTCLK"]
# Vivado must derive CLKOUT0=8 ns and CLKOUT1=16 ns through each MMCM. Defining
# replacement primary clocks on these outputs would lose gearbox relationships.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
