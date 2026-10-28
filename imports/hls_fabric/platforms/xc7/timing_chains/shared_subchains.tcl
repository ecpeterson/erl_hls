# Export a near-critical endpoint census and bounded alternative paths from a routed checkpoint.
# Usage: vivado -mode batch -source shared_subchains.tcl -tclargs CHECKPOINT OUTPUT [BAND_NS] [PATH_LIMIT] [ALTERNATIVES] [ALTERNATIVE_LIMIT]
# Reporting only: no constraint changes, synthesis, placement or routing.
if {[llength $argv] < 2} {error "checkpoint and output are required"}
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set band [expr {[llength $argv] > 2 ? [lindex $argv 2] : 1.0}]
set limit [expr {[llength $argv] > 3 ? [lindex $argv 3] : 50000}]
set alternatives [expr {[llength $argv] > 4 ? [lindex $argv 4] : 4}]
if {![string is double -strict $band] || $band <= 0} {error "band must be positive"}
set alternative_limit [expr {[llength $argv] > 5 ? [lindex $argv 5] : 2000}]
foreach value [list $limit $alternatives $alternative_limit] {
    if {![string is integer -strict $value] || $value < 1} {error "counts must be positive integers"}
}
set_param general.maxThreads 8
open_checkpoint $checkpoint
set worst [lindex [get_timing_paths -setup -max_paths 1 -no_report_unconstrained] 0]
if {$worst eq ""} {error "no constrained setup paths"}
set clock [get_property STARTPOINT_CLOCK $worst]
if {$clock ne [get_property ENDPOINT_CLOCK $worst]} {error "cross-clock worst path is unsupported"}
set requirement [get_property REQUIREMENT $worst]
set slack [get_property SLACK $worst]
set threshold [expr {$slack + $band}]
file mkdir $output
set endpoint_paths [get_timing_paths -setup -group [get_property GROUP $worst] -max_paths $limit -nworst 1 -no_report_unconstrained -slack_lesser_than $threshold]
set endpoint_count [llength $endpoint_paths]
report_timing -of_objects $endpoint_paths -file [file join $output endpoints.rpt]
set paths [get_timing_paths -setup -group [get_property GROUP $worst] -max_paths $alternative_limit -nworst $alternatives -no_report_unconstrained -slack_lesser_than $threshold]
set path_count [llength $paths]
report_timing -of_objects $paths -file [file join $output alternatives.rpt]
# Escape user paths and tool strings without depending on a Tcl JSON package.
proc json_string {value} {
    return "\"[string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $value]\""
}
set stream [open [file join $output extraction.json] w]
puts $stream "{\"schema\":1,\"checkpoint\":[json_string $checkpoint],\"tool\":[json_string [version -short]],\"clock\":[json_string $clock],\"requirement_ns\":$requirement,\"worst_slack_ns\":$slack,\"band_ns\":$band,\"limit\":$limit,\"alternative_limit\":$alternative_limit,\"alternatives_per_endpoint\":$alternatives,\"endpoint_paths\":$endpoint_count,\"alternative_paths\":$path_count,\"threads\":[get_param general.maxThreads]}"
close $stream
puts "SUBCHAINS_EXTRACTED endpoints=$endpoint_count alternatives=$path_count limit=$limit"
exit
