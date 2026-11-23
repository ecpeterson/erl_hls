# Retain the installed Wizard's supported parameters before choosing a profile.
set root [file dirname [file normalize [info script]]]
set stage [file join $root results wizard]
file mkdir $stage
create_project -force wizard [file join $stage project] -part xc7z030sbg485-1
create_ip -name gtwizard -vendor xilinx.com -library ip -version 3.6 -module_name reference_gt
report_property -all [get_ips reference_gt] -file [file join $stage properties.rpt]
set fp [open [file join $stage configuration.tsv] w]
foreach property [lsort [list_property [get_ips reference_gt]]] {
    if {[string match CONFIG.* $property]} {
        puts $fp "$property\t[get_property $property [get_ips reference_gt]]"
    }
}
close $fp
# Match the board lane's rate/width on the Wizard's first channel in this quad.
# Basic mode uses the shared rate/reference controls; per-channel copies are read-only.
set_property -dict [list CONFIG.gt0_val true CONFIG.gt1_val false \
    CONFIG.identical_val_tx_line_rate 1.250 CONFIG.identical_val_rx_line_rate 1.250 \
    CONFIG.identical_val_tx_reference_clock 125.000 CONFIG.identical_val_rx_reference_clock 125.000 \
    CONFIG.gt0_val_tx_data_width 20 CONFIG.gt0_val_rx_data_width 20 \
    CONFIG.gt0_val_encoding None CONFIG.gt0_val_txbuf_en true CONFIG.gt0_val_rxbuf_en true \
    CONFIG.gt0_val_rxusrclk RXOUTCLK CONFIG.gt0_val_drp_clock 25] [get_ips reference_gt]
foreach key {tx_line_rate rx_line_rate} {
    if {[get_property CONFIG.gt0_val_$key [get_ips reference_gt]] != 1.25} {
        error "Wizard rejected the requested $key"
    }
}
generate_target all [get_ips reference_gt]
report_property -all [get_ips reference_gt] -file [file join $stage configured.rpt]
open_example_project -force -dir [file join $stage example] [get_ips reference_gt]
