# Emit a vendor bitstream for the isolated RAMB36E1 configuration fixture.
# Usage: vivado -mode batch -source build_ramb36_sdp72_reference.tcl -tclargs OUTPUT
set root [file dirname [file normalize [info script]]]
set output [file normalize [lindex $argv 0]]
if {$output eq ""} {error "missing output directory"}
file mkdir $output
create_project -in_memory -part xc7z030sbg485-1
read_verilog [file join $root ramb36_sdp72_reference.v]
synth_design -top ramb36_sdp72_reference -part xc7z030sbg485-1
opt_design
place_design
route_design
write_checkpoint -force [file join $output routed.dcp]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
write_bitstream -force [file join $output candidate.bit]
report_property -all [get_cells memory] -file [file join $output memory-properties.rpt]
puts "BATCH_COMPLETE ramb36-sdp72-reference"
