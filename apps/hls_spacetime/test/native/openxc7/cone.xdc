# Compile-only XC7Z030-SBG485 bank 13 pins.
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports clock]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS33} [get_ports enable]
set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports reset]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports activity]
