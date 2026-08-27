# Compile-test pins selected from the Project X-Ray package database.
# Do not program this bitstream until these are checked against the board.
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS33} [get_ports clock]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports counter_msb]
