# Call after domain_board_profile.tcl, then again after routing.
# A successful check means clock binding only, never automatic board admission.
proc board_check_clocks {phase output} {
    global board_ps board_gtx
    set file [open [file join $output "$phase-clock-bindings.tsv"] w]
    puts $file "pin\tclock\troot\tperiod_ns"
    set rows [list \
        [list "$board_ps/FCLKCLK\[0\]" control 40.0] \
        [list "$board_gtx/TXOUTCLK" tx_word 16.0] \
        [list "$board_gtx/RXOUTCLK" rx_word 16.0] \
        [list clocks/tx/generator/CLKOUT0 tx_word 8.0] \
        [list clocks/tx/generator/CLKOUT1 tx_word 16.0] \
        [list clocks/rx/generator/CLKOUT0 rx_word 8.0] \
        [list clocks/rx/generator/CLKOUT1 rx_word 16.0] \
        [list "$board_gtx/TXUSRCLK" tx_word 16.0] \
        [list "$board_gtx/TXUSRCLK2" tx_word 16.0] \
        [list "$board_gtx/RXUSRCLK" rx_word 16.0] \
        [list "$board_gtx/RXUSRCLK2" rx_word 16.0] \
        [list "$board_ps/MAXIGP0ACLK" control 40.0]]
    foreach row $rows {
        lassign $row name expected_root expected_period
        set clock [board_clock_at [board_pin $name]]
        set root [board_root $clock]
        set period [get_property PERIOD [get_clocks $clock]]
        puts $file "$name\t$clock\t$root\t$period"
        if {$root ne $expected_root || abs($period-$expected_period) > 0.0001} {
            close $file
            error "wrong clock at $name: $clock root=$root period=$period"
        }
        if {[string match clocks/*/generator/CLKOUT* $name] && ![get_property IS_GENERATED [get_clocks $clock]]} {
            close $file
            error "MMCM output lost generated-clock relationship: $name"
        }
    }
    set ref [board_clock_at [board_one [get_ports ref_p] ref_p]]
    if {[board_root $ref] ne "reference" || abs([get_property PERIOD $ref]-8.0) > 0.0001} {
        close $file
        error "wrong reference clock"
    }
    foreach {name expected} [list $board_gtx GTXE2_CHANNEL_X0Y1 \
        clocks/tx/generator MMCME2_ADV_X1Y2 clocks/rx/generator MMCME2_ADV_X1Y3] {
        set cell [board_cell $name]
        set loc [get_property LOC $cell]
        if {$loc ne $expected} {close $file; error "wrong primitive location: $name $loc"}
        puts $file "location\t$name\t$loc\t-"
    }
    close $file
    report_exceptions -file [file join $output "$phase-exceptions.rpt"]
    if {$phase ne "routed"} {report_methodology -file [file join $output "$phase-methodology.rpt"]}
}
