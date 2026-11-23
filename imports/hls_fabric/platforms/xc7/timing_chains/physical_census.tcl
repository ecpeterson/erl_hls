# Read-only ownership evidence from a routed checkpoint. Python 3.10+ is required.
# Usage: vivado -mode batch -source physical_census.tcl -tclargs DCP FRESH_OUTPUT [BAND_NS] [ENDPOINT_LIMIT]
if {$argc < 2 || $argc > 4} {error "expected checkpoint output ?band? ?endpoint_limit?"}
set checkpoint [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set band [expr {$argc > 2 ? [lindex $argv 2] : 1.0}]
set limit [expr {$argc > 3 ? [lindex $argv 3] : 50000}]
if {![string is double -strict $band] || $band <= 0 || ![string is integer -strict $limit] || $limit <= 0} {error "positive band and endpoint limit required"}
if {[file exists $output]} {error "output must be fresh"}
file mkdir $output

# Write escaped JSON scalar values, including host paths and tool versions.
proc json_string {value} {
    return "\"[string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $value]\""
}
# TSV avoids quoting ambiguity by rejecting names that cannot be represented.
proc row {stream fields} {
    foreach field $fields {
        if {[regexp {[\t\r\n]} $field]} {error "unrepresentable TSV field"}
    }
    puts $stream [join $fields \t]
}
set_param general.maxThreads 8
set started [clock seconds]
open_checkpoint $checkpoint
set worst [lindex [get_timing_paths -setup -max_paths 1 -no_report_unconstrained] 0]
if {[get_property STARTPOINT_CLOCK $worst] ne [get_property ENDPOINT_CLOCK $worst]} {error "cross-clock worst path"}
set group [get_property GROUP $worst]
set threshold [expr {[get_property SLACK $worst] + $band}]
set paths [get_timing_paths -setup -group $group -max_paths $limit -nworst 1 -no_report_unconstrained -slack_lesser_than $threshold]
report_timing -of_objects $paths -file $output/endpoints.rpt
report_utilization -hierarchical -file $output/utilization.rpt
report_utilization -file $output/capacity.rpt
# Native congestion evidence remains separate from geometric bounding boxes.
set congestion_status ok
if {[catch {report_design_analysis -congestion -file $output/congestion.rpt} message]} {
    set congestion_status $message
}
set helper [file join [file dirname [info script]] physical_census.py]
set python [expr {[info exists ::env(HLS_REPORT_PYTHON)] ? $::env(HLS_REPORT_PYTHON) : "python3"}]
# Vivado sets PYTHONHOME for its bundled runtime; ignore that for the selected interpreter.
exec $python -E $helper select $output/endpoints.rpt $output/selection.json
set input [open $output/selection.txt r]
set selected [split [string trim [read $input]] \n]
close $input
# Include the highest global signal fanouts, even when not near-critical.
set high {}
foreach net [get_nets -hier -filter {TYPE == SIGNAL && FLAT_PIN_COUNT >= 128}] {
    lappend high [list [get_property FLAT_PIN_COUNT $net] [get_property NAME $net]]
}
foreach pair [lrange [lsort -integer -decreasing -index 0 $high] 0 127] {lappend selected [lindex $pair 1]}
set selected [lsort -unique $selected]

# Index each used site's common tile grid once; unlike SLICE/RAMB X/Y, these
# coordinates share a coordinate system. They are not distances in micrometres.
set cells [get_cells -hier -filter {IS_PRIMITIVE}]
set names [get_property NAME $cells]
set refs [get_property REF_NAME $cells]
set locs [get_property LOC $cells]
set bels [get_property BEL $cells]
set locations [dict create]
foreach loc [lsort -unique $locs] {
    if {$loc eq ""} {continue}
    set site [get_sites $loc]
    set tile [get_tiles -of_objects $site]
    dict set locations $loc [list [get_property GRID_POINT_X $tile] [get_property GRID_POINT_Y $tile] [get_property CLOCK_REGION $site]]
}
set stream [open $output/cells.tsv w]
row $stream {name ref site bel x y clock_region}
foreach name $names ref $refs loc $locs bel $bels {
    set position [list "" "" ""]
    if {$loc ne ""} {set position [dict get $locations $loc]}
    row $stream [concat [list $name $ref $loc $bel] $position]
}
close $stream
set nets_stream [open $output/nets.tsv w]
set pins_stream [open $output/pins.tsv w]
row $nets_stream {name canonical status flat_pin_count type}
set exported [dict create]
row $pins_stream {net pin cell direction}
set missing 0
foreach name $selected {
    # Vivado accepts exact vector-bit names; require equality to reject wildcard matches.
    set net [get_nets -quiet $name]
    if {[llength $net] != 1 || [get_property NAME $net] ne $name} {
        row $nets_stream [list $name $name missing "" ""]
        incr missing
        continue
    }
    # Different hierarchy aliases can reach the same global reset tree. Export
    # leaf pins once per physical net while retaining every timing alias.
    set root_net [get_nets -segments -top_net_of_hierarchical_group $name]
    if {[llength $root_net] != 1} {error "ambiguous physical net for $name"}
    set canonical [get_property NAME $root_net]
    row $nets_stream [list $name $canonical [get_property ROUTE_STATUS $net] [get_property FLAT_PIN_COUNT $net] [get_property TYPE $net]]
    if {[dict exists $exported $canonical]} {continue}
    dict set exported $canonical 1
    foreach pin [get_pins -leaf -of_objects $root_net] {
        row $pins_stream [list $canonical [get_property NAME $pin] [get_property NAME [get_cells -of_objects $pin]] [get_property DIRECTION $pin]]
    }
}
close $nets_stream
close $pins_stream
set hash [lindex [exec sha256sum $checkpoint] 0]
set stream [open $output/extraction.json w]
puts $stream "\{\"schema\":1,\"checkpoint\":[json_string $checkpoint],\"checkpoint_sha256\":[json_string $hash],\"tool\":[json_string [version -short]],\"part\":[json_string [get_property PART [current_design]]],\"band_ns\":$band,\"endpoint_limit\":$limit,\"endpoint_count\":[llength $paths],\"endpoint_cap_reached\":[expr {[llength $paths] >= $limit ? {true} : {false}}],\"selected_nets\":[llength $selected],\"missing_nets\":$missing,\"congestion_status\":[json_string $congestion_status],\"seconds\":[expr {[clock seconds] - $started}]\}"
close $stream
puts "PHYSICAL_CENSUS_COMPLETE $output"
