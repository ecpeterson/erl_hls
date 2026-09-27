# Compare named native endpoints on a preserved Vivado routed checkpoint.
# Usage: vivado -mode batch -source probe_paths.tcl -tclargs CHECKPOINT QUERIES.tsv OUTPUT
set checkpoint [file normalize [lindex $argv 0]]
set queries [file normalize [lindex $argv 1]]
set output [file normalize [lindex $argv 2]]
file mkdir $output
set_param general.maxThreads 2
open_checkpoint $checkpoint
set cells [get_cells -hier -filter {IS_PRIMITIVE}]
set lookup [dict create]
foreach cell $cells name [get_property NAME $cells] {
    dict set lookup [string map [list "\\\\" "\\"] $name] $cell
}
set stream [open $queries r]
set records [split [string trim [read $stream]] "\n"]
close $stream
set summary [open [file join $output status.tsv] w]
foreach record $records {
    lassign [split $record "\t"] label start_cell start_port end_cell end_port
    if {![regexp {^[a-z0-9_-]+$} $label]} {error "invalid query label"}
    if {![dict exists $lookup $start_cell] || ![dict exists $lookup $end_cell]} {
        puts $summary "$label\tmissing_cell"
        continue
    }
    set starts [get_pins -of_objects [dict get $lookup $start_cell] -filter "REF_PIN_NAME == $start_port"]
    set ends [get_pins -of_objects [dict get $lookup $end_cell] -filter "REF_PIN_NAME == $end_port"]
    if {[llength $starts] != 1 || [llength $ends] != 1} {
        puts $summary "$label\tmissing_pin"
        continue
    }
    set path [get_timing_paths -quiet -from $starts -to $ends -delay_type max -max_paths 1]
    if {[llength $path] != 1} {
        puts $summary "$label\tno_path"
        continue
    }
    report_timing -from $starts -to $ends -delay_type max -max_paths 1 \
        -path_type full_clock_expanded -file [file join $output $label-path.rpt]
    set stream [open [file join $output $label-properties.rpt] w]
    puts $stream [report_property -all -return_string $path]
    close $stream
    puts $summary "$label\tcomplete"
}
close $summary
puts "PATH_QUERIES_COMPLETE"
