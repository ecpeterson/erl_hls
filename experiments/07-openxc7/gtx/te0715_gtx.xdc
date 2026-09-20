# Native FPGA polarity: TE0715-05 module schematic sheets 13/15. The carrier
# reverses both SFP pairs; external operation will need RX/TXPOLARITY=1.
set_property PACKAGE_PIN U5 [get_ports ref_p]
set_property PACKAGE_PIN V5 [get_ports ref_n]
set_property PACKAGE_PIN W8 [get_ports gt_rx_p]
set_property PACKAGE_PIN Y8 [get_ports gt_rx_n]
set_property PACKAGE_PIN W4 [get_ports gt_tx_p]
set_property PACKAGE_PIN Y4 [get_ports gt_tx_n]
# Clocks are physically distinct; nextpnr does not fully time GTX/PS boundaries.
create_clock -period 8.000 [get_ports ref_p]
create_clock -period 40.000 [get_nets clock]
create_clock -period 16.000 [get_nets tx_clock]
create_clock -period 16.000 [get_nets rx_clock]
