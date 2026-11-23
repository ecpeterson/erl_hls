# Package-valid COMPILE-ONLY pins, not a board pinout. Do not program this image.
# AMD: Y14 = IO_L12P_T1_MRCC_13; V13 = IO_L1P_T0_13 (HR bank 13).
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports clock]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports activity]
