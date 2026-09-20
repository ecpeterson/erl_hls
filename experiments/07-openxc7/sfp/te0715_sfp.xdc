# TEF1002-03 JB1 odd/even contacts mate to TE0715-05 JM1 even/odd.
# A_01_N: JB1-35 -> JM1-36 -> B13_L6_P -> U13 (CPLD to SoM).
# A_02_P: JB1-39 -> JM1-40 -> B13_L4_P -> V11 (SoM to CPLD).
# A_02_N: JB1-41 -> JM1-42 -> B13_L4_N -> W11 (SoM to CPLD clock).
# J4 must select 1.8 V VCCIOA, which supplies bank 13; confirm before programming.
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS18} [get_ports rgpio_rx]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports rgpio_tx]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports rgpio_clock]
