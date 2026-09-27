# Retain cell placement and net routes for offline comparison with native results.
# Usage: vivado -mode batch -source export_physical.tcl -tclargs CHECKPOINT OUTPUT
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
file mkdir $output
set_param general.maxThreads 2
open_checkpoint $checkpoint
set cells [get_cells -hier -filter {IS_PRIMITIVE}]
set stream [open [file join $output cells.tsv] w]
puts $stream "cell\tprimitive\tsite\tbel"
foreach name [get_property NAME $cells] ref [get_property REF_NAME $cells] \
        loc [get_property LOC $cells] bel [get_property BEL $cells] {
    puts $stream "$name\t$ref\t$loc\t$bel"
}
close $stream
set nets [get_nets -hier]
set stream [open [file join $output routes.tsv] w]
puts $stream "net\troute"
foreach name [get_property NAME $nets] route [get_property ROUTE $nets] {
    puts $stream "$name\t[string map [list \n { } \t { }] $route]"
}
close $stream
puts "PHYSICAL_EXPORT_COMPLETE"
