# Compile-test pins selected from the Project X-Ray package database.
# Do not program this bitstream until these are checked against the board.
set_property -dict {PACKAGE_PIN L12 IOSTANDARD LVCMOS33} [get_ports clock]
set_property -dict {PACKAGE_PIN E11 IOSTANDARD LVCMOS33} [get_ports activity]
