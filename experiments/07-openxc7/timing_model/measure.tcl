# Time a Yosys-mapped probe without resynthesizing or changing its logic.
# Usage: vivado -mode batch -source measure.tcl -tclargs INPUT.edf OUTPUT [PERIOD_NS]
set input [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set period [expr {[llength $argv] > 2 ? [lindex $argv 2] : 5.0}]
file mkdir $output
set_param general.maxThreads 2
create_project -in_memory -part xc7z030sbg485-1
file copy -force $input [file join $output probe_top.edf]
read_edif [file join $output probe_top.edf]
link_design -top probe_top -part xc7z030sbg485-1 -mode out_of_context
create_clock -period $period [get_ports clock]
set_property HD.CLK_SRC [lindex [get_sites -filter {SITE_TYPE == BUFGCTRL}] 0] [get_ports clock]
# External I/O is deliberately outside the measurement: every measured path is FF-to-FF.
set inputs [get_ports -quiet -filter {DIRECTION == IN && NAME != clock}]
if {[llength $inputs]} {set_false_path -from $inputs}
set_false_path -to [get_ports -filter {DIRECTION == OUT}]
set_property DONT_TOUCH true [get_cells -hier -filter {IS_PRIMITIVE}]
set stream [open [file join $output connectivity.tsv] w]
foreach cell [get_cells -hier -filter {IS_PRIMITIVE}] {
    foreach pin [get_pins -of_objects $cell] {
        set nets [get_nets -quiet -of_objects $pin]
        set netname ""
        if {[llength $nets]} {set netname [get_property NAME $nets]}
        puts $stream "[get_property NAME $cell]\t[get_property REF_NAME $cell]\t[get_property REF_PIN_NAME $pin]\t$netname"
    }
}
foreach port [get_ports] {
    set nets [get_nets -quiet -of_objects $port]
    set netname ""
    if {[llength $nets]} {set netname [get_property NAME $nets]}
    puts $stream "@top\tPORT\t[get_property NAME $port]\t$netname"
}
close $stream
set checker [file join [file dirname [file normalize [info script]]] connectivity.py]
set mapped [file join [file dirname $input] mapped.json]
set parameters [exec env -u PYTHONHOME -u PYTHONPATH /usr/bin/python3 $checker --list-parameters $mapped]
set stream [open [file join $output parameters.tsv] w]
foreach cell [get_cells -hier -filter {IS_PRIMITIVE}] {
    set properties [list_property $cell]
    foreach parameter $parameters {
        if {[lsearch -exact $properties $parameter] >= 0} {
            puts $stream "[get_property NAME $cell]\t$parameter\t[get_property $parameter $cell]"
        }
    }
}
close $stream
set audit [exec env -u PYTHONHOME -u PYTHONPATH /usr/bin/python3 $checker $mapped [file join $output connectivity.tsv] [file join $output parameters.tsv]]
set stream [open [file join $output audit.json] w]
puts $stream $audit
close $stream
puts $audit
write_checkpoint -force [file join $output linked.dcp]
report_utilization -file [file join $output linked-utilization.rpt]
place_design
route_design
write_checkpoint -force [file join $output routed.dcp]
write_sdf -force [file join $output routed.sdf]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output timing.rpt]
report_timing -delay_type max -max_paths 20 -path_type full_clock_expanded -file [file join $output paths.rpt]
report_route_status -file [file join $output route.rpt]
check_timing -verbose -file [file join $output coverage.rpt]
set path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {$path eq ""} {error "no internal timed path"}
set stream [open [file join $output path-properties.rpt] w]
puts $stream [report_property -all -return_string $path]
close $stream
set stream [open [file join $output version.txt] w]
puts $stream [version]
close $stream
puts "CHARACTERIZATION_COMPLETE"
