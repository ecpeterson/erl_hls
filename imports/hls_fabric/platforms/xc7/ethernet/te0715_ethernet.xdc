# Exact native pad polarity; external profile inverts both serial directions.
set_property PACKAGE_PIN U5 [get_ports ref_p]
set_property PACKAGE_PIN V5 [get_ports ref_n]
set_property PACKAGE_PIN W8 [get_ports gt_rx_p]
set_property PACKAGE_PIN Y8 [get_ports gt_rx_n]
set_property PACKAGE_PIN W4 [get_ports gt_tx_p]
set_property PACKAGE_PIN Y4 [get_ports gt_tx_n]
# Match the MMCM sites in the hardware-working Vivado external-Ethernet image.
# Native bottom-site placement routed successfully but neither MMCM locked.
set_property BEL MMCME2_ADV_X1Y2/MMCME2_ADV [get_cells clocks.tx.generator]
set_property BEL MMCME2_ADV_X1Y3/MMCME2_ADV [get_cells clocks.rx.generator]
create_clock -period 8.000 [get_ports ref_p]
create_clock -period 40.000 [get_nets clock]
# Native backend supports frequency constraints, not generated-clock relations.
# These are partial timing targets, NOT a constraint signoff for gearbox/CDC.
# Full/half clocks of each direction derive from one MMCM; never false-path them.
create_clock -period 8.000 [get_nets tx_clock]
create_clock -period 16.000 [get_nets tx_half_clock]
create_clock -period 8.000 [get_nets rx_clock]
create_clock -period 16.000 [get_nets rx_half_clock]
