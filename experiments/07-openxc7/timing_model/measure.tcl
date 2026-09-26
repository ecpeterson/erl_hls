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
# Standalone operators have an unbuffered OOC clock; application harnesses
# already contain their global buffer and must use that real clock network.
if {[llength [get_cells -hier -filter {REF_NAME == BUFG || REF_NAME == BUFGCTRL}]] == 0} {
    set_property HD.CLK_SRC [lindex [get_sites -filter {SITE_TYPE == BUFGCTRL}] 0] [get_ports clock]
}
# External I/O is deliberately outside the measurement: every measured path is FF-to-FF.
set inputs [get_ports -quiet -filter {DIRECTION == IN && NAME != clock}]
if {[llength $inputs]} {set_false_path -from $inputs}
set_false_path -to [get_ports -filter {DIRECTION == OUT}]
set_property DONT_TOUCH true [get_cells -hier -filter {IS_PRIMITIVE}]
set_property DONT_TOUCH true [get_nets -hier]
source [file join [file dirname [file normalize [info script]]] circuit_audit.tcl]
set mapped [file join [file dirname $input] mapped.json]
puts [xc7_timing::audit $mapped $output]
write_checkpoint -force [file join $output linked.dcp]
report_utilization -file [file join $output linked-utilization.rpt]
place_design -no_psip -no_bufg_opt
route_design
puts [xc7_timing::audit $mapped $output "routed-"]
write_checkpoint -force [file join $output routed.dcp]
write_sdf -force [file join $output routed.sdf]
# Primitive internal clock limits are distinct from external setup/hold arcs.
set hard [get_cells -quiet -hier -filter {REF_NAME =~ RAMB* || REF_NAME == DSP48E1 || REF_NAME =~ SRL*}]
if {[llength $hard]} {
    report_pulse_width -cells $hard -limit 10000 -file [file join $output hard-clock-constraints.rpt]
}
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
