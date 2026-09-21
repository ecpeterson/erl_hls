# Physical clocks for Vivado; native frequency-only constraints are not reused.
if {$profile in {phi micro}} {
    create_clock -name workload -period $workload_period [get_ports clock]
    set_property IOSTANDARD LVCMOS33 [get_ports *]
    # These are compile-harness pins, not a board wiring declaration.
    set_property PACKAGE_PIN Y14 [get_ports clock]
    set_property PACKAGE_PIN V13 [get_ports activity]
    set_output_delay -clock workload 0 [get_ports activity]
} else {
    set period [expr {$profile in {register dma} ? 10.0 : 40.0}]
    create_clock -name control -period $period [get_pins -hier -filter {REF_PIN_NAME == FCLKCLK[0]}]
}
if {$profile in {prbs ethernet-loopback ethernet-external}} {
    foreach {port pad} {ref_p U5 ref_n V5 gt_rx_p W8 gt_rx_n Y8 gt_tx_p W4 gt_tx_n Y4} {
        set_property PACKAGE_PIN $pad [get_ports $port]
    }
    set lane [get_cells -hier -filter {REF_NAME == GTXE2_CHANNEL}]
    set_property LOC GTXE2_CHANNEL_X0Y1 $lane
    create_clock -name reference -period 8.000 [get_ports ref_p]
    # GTX output clocks are timing roots; Vivado has no timing arc through its CPLL.
    # Each MMCM still derives a related full/half pair from its own root.
    create_clock -name tx_word -period 16.000 [get_pins $lane/TXOUTCLK]
    create_clock -name rx_word -period 16.000 [get_pins $lane/RXOUTCLK]
    # Vivado derives both outputs of each MMCM, preserving full/half phase.
}
# Initially leave asynchronous paths visible. The reviewed CDC exceptions and
# held-bus bounds are added only after examining the synthesized crossing census.
