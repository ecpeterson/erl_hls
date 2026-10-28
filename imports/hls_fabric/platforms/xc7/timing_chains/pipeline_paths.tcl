# Report the same endpoint classes before/after routing, including new registers.
# Usage: vivado -mode batch -source pipeline_paths.tcl -tclargs CHECKPOINT OUTPUT
# An unplaced checkpoint uses estimated interconnect, not routed delay.
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
file mkdir $output
set_param general.maxThreads 2
open_checkpoint $checkpoint
report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded -file [file join $output paths.rpt]
set ff [get_cells -hier -filter {REF_NAME =~ FD*}]
set ram [get_cells -hier -filter {REF_NAME =~ RAMB*}]
set groups [dict create \
    register_control [get_pins -of_objects $ff -filter {REF_PIN_NAME == CE || REF_PIN_NAME == R || REF_PIN_NAME == S}] \
    ram_read [get_pins -of_objects $ram -filter {REF_PIN_NAME =~ ADDRARDADDR* || REF_PIN_NAME == ENARDEN}] \
    ram_write [get_pins -of_objects $ram -filter {REF_PIN_NAME =~ ADDRBWRADDR* || REF_PIN_NAME =~ WEBWE*}]]
set summary [open [file join $output coverage.tsv] w]
puts $summary "group\tpins\tstatus"
dict for {name pins} $groups {
    if {![llength $pins]} {error "missing endpoint class: $name"}
    set paths [get_timing_paths -quiet -to $pins -delay_type max -max_paths 1]
    if {![llength $paths]} {error "untimed endpoint class: $name"}
    report_timing -to $pins -delay_type max -max_paths 20 -path_type full_clock_expanded -file [file join $output paths-$name.rpt]
    puts $summary "$name\t[llength $pins]\ttimed"
}
set ram_paths [get_timing_paths -quiet -from $ram -delay_type max -max_paths 1]
if {![llength $ram_paths]} {error "untimed RAM launch class"}
report_timing -from $ram -delay_type max -max_paths 20 -path_type full_clock_expanded -file [file join $output paths-ram_response.rpt]
puts $summary "ram_response\t[llength $ram]\ttimed"
close $summary
puts "PIPELINE_PATHS_COMPLETE"
