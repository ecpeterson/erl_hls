# TEF1002-03 JB1 odd/even contacts mate to TE0715-05 JM1 even/odd.
# A_01_N: JB1-35 -> JM1-36 -> B13_L6_P -> U13 (CPLD to SoM).
# A_02_P: JB1-39 -> JM1-40 -> B13_L4_P -> V11 (SoM to CPLD).
# A_02_N: JB1-41 -> JM1-42 -> B13_L4_N -> W11 (SoM to CPLD clock).
# J4 must select 1.8 V VCCIOA, which supplies bank 13; confirm before programming.
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS18} [get_ports rgpio_rx]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports rgpio_tx]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports rgpio_clock]
# Carrier's three-wire I2C bridge: high SDA output means release at the CPLD.
# A_00_P: JB1-36 -> JM1-35 -> B13_L5_P -> U11 (SCL).
# A_00_N: JB1-38 -> JM1-37 -> B13_L5_N -> U12 (SDA release).
# A_01_P: JB1-37 -> JM1-38 -> B13_L6_N -> U14 (aggregate SDA return).
# A_06_N: JB1-49 -> JM1-50 -> B13_L8_P -> AA12 (select bit 0).
# A_07:   JB1-34 -> JM1-33 -> B13_L3_N -> W13 (select bit 1).
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports i2c_scl]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports i2c_sda_release]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS18} [get_ports i2c_sda_in]
set_property -dict {PACKAGE_PIN AA12 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports {i2c_select[0]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 4} [get_ports {i2c_select[1]}]
