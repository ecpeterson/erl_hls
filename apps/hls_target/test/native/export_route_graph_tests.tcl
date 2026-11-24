# Local synthetic orchestration: whole canonical population, incremental reuse,
# closed prefixes and rejected identities. No native geometry is established.
# Usage: tclsh test/native/export_route_graph_tests.tcl FRESH_OUTPUT_DIRECTORY
source [file join [file dirname [info script]] ../../priv/tools/export_route_graph.tcl]
if {[llength $argv] != 1 || [file exists [lindex $argv 0]]} {error "fresh output directory required"}
set output [lindex $argv 0]
file mkdir $output
set digest [string repeat a 64]
set counters [dict create]
set properties [dict create \
    net [dict create NAME net ROUTE_STATUS ROUTED TYPE SIGNAL] \
    extra [dict create NAME extra DIRECTION IN] port [dict create NAME port DIRECTION IN] q [dict create NAME q DIRECTION OUT] d [dict create NAME d DIRECTION IN] \
    sibling [dict create NAME sibling DIRECTION IN] internal [dict create NAME internal DIRECTION IN] \
    n0 [dict create NAME n0] n1 [dict create NAME n1] n2 [dict create NAME n2] \
    w0 [dict create NAME w0] w1 [dict create NAME w1] w2 [dict create NAME w2] w3 [dict create NAME w3] \
    p0 [dict create NAME p0 IS_DIRECTIONAL 1] p1 [dict create NAME p1 IS_DIRECTIONAL 0] \
    bq [dict create NAME bq] bd [dict create NAME bd] bi [dict create NAME bi] \
    sq [dict create NAME sq] sd [dict create NAME sd] \
    tile_a [dict create NAME tile_a GRID_POINT_X 3 GRID_POINT_Y 5] \
    tile_b [dict create NAME tile_b GRID_POINT_X 4 GRID_POINT_Y 7]]
proc get_property {key obj} {return [dict get $::properties $obj $key]}
proc set_param {args} {
    if {$args ne {general.maxThreads 2}} {error "unexpected mutation"}
}
proc open_checkpoint {path} {incr ::opened}
proc get_nets {args} {
    if {[lindex $args 0] eq "-segments"} {return [lindex $args end]}
    if {$args eq {-of_objects port}} {return {net net}}
    if {[lindex $args 0] eq "-of_objects"} {return net}
    if {$args eq "net"} {return net}
    return {}
}
proc get_ports {args} {if {$args eq "port"} {return port}; return {}}
proc get_pins {args} {
    dict incr ::counters pin_lookup
    set name [lindex $args 0]
    if {$name in {q d sibling internal extra}} {return $name}
    return {}
}
proc get_nodes {args} {
    if {$args eq {-of_objects net}} {dict incr ::counters net_nodes; return {n0 n1 n2}}
    if {$args eq {-of_objects sq}} {return n0}
    if {$args eq {-of_objects sd}} {return n1}
    if {$args eq {-uphill -of_objects p0} || $args eq {-uphill -of_objects p1}} {return n0}
    if {$args eq {-downhill -of_objects p0}} {return n1}
    if {$args eq {-downhill -of_objects p1}} {return n2}
    error "unexpected get_nodes: $args"
}
proc get_wires {args} {
    return [dict get [dict create n0 {w0 w2} n1 w1 n2 w3] [lindex $args end]]
}
proc get_pips {args} {
    if {$args ne {-of_objects net}} {error "unbounded PIP query"}
    return {p0 p1}
}
proc get_tiles {args} {
    set name [lindex $args end]
    if {$name in {w0 p0}} {return tile_a}
    if {$name in {w1 w2 w3 p1}} {return tile_b}
    error "unexpected tile object: $name"
}
proc get_bel_pins {args} {
    return [dict get [dict create q bq d bd sibling bd internal bi extra bd] [lindex $args end]]
}
proc get_site_pins {args} {
    return [dict get [dict create q sq d sd sibling {sq sd} internal {} extra sd] [lindex $args end]]
}

# A fake checkpoint identity is explicit; actual retained shard bytes use real hashes.
rename ::hls_spacetime_routes::hash ::hls_spacetime_routes::native_hash
proc ::hls_spacetime_routes::hash {path} {
    if {$path eq "mock.dcp"} {return $::digest}
    if {[auto_execok sha256sum] ne ""} {return [lindex [exec sha256sum -- $path] 0]}
    return [lindex [exec shasum -a 256 -- $path] 0]
}
# Read completed scalar fixture text without supplying a JSON parser to Vivado.
proc text {path} {set f [open $path]; set s [read $f]; close $f; return $s}
# File identities describe the exact reused bytes, not native correspondence.
proc reference {path} {
    return [dict create path $path sha256 [::hls_spacetime_routes::hash $path] bytes [file size $path]]
}
# Negative cases must reject and never publish a full completion marker.
proc reject {label script} {
    if {![catch {uplevel 1 $script} reason]} {error "accepted negative case: $label"}
    if {[file exists [file join $::output $label manifest.json]]} {error "failed case published complete manifest: $label"}
    incr ::tests
}
set opened 0
set tests 0
set build [dict create source $digest rtl $digest observation $digest implementation $digest]
set endpoints [list [dict create pin q kind pin direction OUT] [dict create pin d kind pin direction IN] \
    [dict create pin sibling kind pin direction IN] [dict create pin internal kind pin direction IN] \
    [dict create pin port kind port direction IN]]
set net [dict create id net type SIGNAL route_status ROUTED pins $endpoints]
set specification [dict create schema_version 1 build $build checkpoint_sha256 $digest \
    catalogue_sha256 $digest demand_sha256 $digest nets [list $net]]
set none [dict create nets {}]
::hls_spacetime_route_graph::run mock.dcp [file join $output full] $specification $none
if {$opened != 1 || [dict get $counters net_nodes] != 1} {error "geometry not queried exactly once"}
set manifest [text [file join $output full manifest.json]]
foreach expected {{"requested_nets":1} {"requested_endpoints":5} {"new_geometry":1} {"new_endpoints":5} {"complete":true}} {
    if {[string first $expected $manifest] < 0} {error "missing complete population: $expected"}
}
incr tests
set geometry [reference [file join $output full geometry 000001.json]]
set attachments [reference [file join $output full attachments 000001-000001.json]]
dict set attachments pins {q d sibling internal port}
set row [dict create id net geometry $geometry nodes {n0 n1 n2} attachments [list $attachments]]
set reuse [dict create nets [list $row]]
set before $counters
::hls_spacetime_route_graph::run mock.dcp [file join $output reused] $specification $reuse
if {$before ne $counters} {error "completed geometry or endpoint was queried again"}
if {[string first {"new_geometry":0} [text [file join $output reused manifest.json]]] < 0} {error "reuse count absent"}
incr tests
set attach_text [text [dict get $attachments path]]
foreach expected {{"kind":"port"} {"status":"ambiguous"} {"status":"intrasite"} {"top_level_port_site_geometry_not_exported"}} {
    if {[string first $expected $attach_text] < 0} {error "lost attachment disposition: $expected"}
}
incr tests
# Reuse geometry alone and query the missing endpoint set without touching net nodes/PIPs/wires.
set empty_row [dict replace $row attachments {}]
set before_nodes [dict get $counters net_nodes]
::hls_spacetime_route_graph::run mock.dcp [file join $output new_pins] $specification [dict create nets [list $empty_row]]
if {[dict get $counters net_nodes] != $before_nodes} {error "reused geometry queried for missing endpoints"}
incr tests
# Existing endpoints stay untouched when one new endpoint is demanded on reused geometry.
set extended [dict replace $net pins [concat $endpoints [list [dict create pin extra kind pin direction IN]]]]
set before_nodes [dict get $counters net_nodes]
set before_pins [dict get $counters pin_lookup]
::hls_spacetime_route_graph::run mock.dcp [file join $output partial_reuse] [dict replace $specification nets [list $extended]] $reuse
if {[dict get $counters net_nodes] != $before_nodes || [dict get $counters pin_lookup] != $before_pins + 2} {
    error "partial reuse queried completed inputs"
}
set mixed [text [file join $output partial_reuse manifest.json]]
foreach expected {{"requested_endpoints":6} {"new_endpoints":1} {"reused_endpoints":5}} {
    if {[string first $expected $mixed] < 0} {error "partial reuse counts disagree: $expected"}
}
incr tests
# A second net's lookup failure preserves the first closed net and its phase records.
set bad_net [dict replace $net id absent pins {}]
set two [dict replace $specification nets [list $net $bad_net]]
reject failed_tail {::hls_spacetime_route_graph::run mock.dcp [file join $output failed_tail] $two $none}
if {![file exists [file join $output failed_tail nets 000001.json]] ||
    ![file exists [file join $output failed_tail incomplete.json]] ||
    [string first {"kind":"net"} [text [file join $output failed_tail closed-records 000001.jsonl]]] < 0} {
    error "closed prefix was lost"
}
incr tests
set wrong [dict replace $specification checkpoint_sha256 [string repeat b 64]]
reject wrong_checkpoint {::hls_spacetime_route_graph::run mock.dcp [file join $output wrong_checkpoint] $wrong $none}
set missing_implementation [dict replace $specification build [dict remove $build implementation]]
reject missing_implementation {::hls_spacetime_route_graph::run mock.dcp [file join $output missing_implementation] $missing_implementation $none}
reject tiny_budget {::hls_spacetime_route_graph::run mock.dcp [file join $output tiny_budget] $specification $none [dict create records 1]}
reject tiny_file {::hls_spacetime_route_graph::run mock.dcp [file join $output tiny_file] $specification $none [dict create file_bytes 16]}
set duplicate [dict replace $specification nets [list $net $net]]
reject duplicate_net {::hls_spacetime_route_graph::run mock.dcp [file join $output duplicate_net] $duplicate $none}
set invalid_row [dict replace $row geometry [dict replace $geometry sha256 [string repeat b 64]]]
reject stale_reuse {::hls_spacetime_route_graph::run mock.dcp [file join $output stale_reuse] $specification [dict create nets [list $invalid_row]]}
set invalid_row [dict replace $row attachments [list [dict replace $attachments pins {absent}]]]
reject foreign_pin {::hls_spacetime_route_graph::run mock.dcp [file join $output foreign_pin] $specification [dict create nets [list $invalid_row]]}
reject existing_output {::hls_spacetime_route_graph::run mock.dcp [file join $output full] $specification $none}
# The new schema covers populations larger than the selected-path exporter's 1000-net cap.
set many {}
for {set i 0} {$i < 1001} {incr i} {lappend many [dict replace $net id net_$i pins {}]}
set large [dict replace $specification nets $many]
set population [::hls_spacetime_route_graph::demand $large [::hls_spacetime_route_graph::limits {}]]
if {[dict get $population nets] != 1001 || [dict get $population endpoints] != 0 ||
    [array size ::hls_spacetime_route_graph::net_index] != 1001} {error "whole population was truncated"}
incr tests
# Invalid endpoint populations reject before any native checkpoint opens.
set before_opened $opened
set duplicate_pin [dict replace $net pins [concat $endpoints [list [lindex $endpoints 0]]]]
reject duplicate_pin {::hls_spacetime_route_graph::run mock.dcp [file join $output duplicate_pin] \
    [dict replace $specification nets [list $duplicate_pin]] $none}
reject endpoint_cap {::hls_spacetime_route_graph::run mock.dcp [file join $output endpoint_cap] \
    $specification $none [dict create endpoints 4]}
if {$opened != $before_opened} {error "invalid preflight opened a checkpoint"}
# Expiration inside identity validation must be caught before native work.
rename ::hls_spacetime_route_graph::identity ::hls_spacetime_route_graph::original_identity
proc ::hls_spacetime_route_graph::identity {value} {
    set result [original_identity $value]
    set ::hls_spacetime_routes::deadline 0
    return $result
}
reject preflight_deadline {::hls_spacetime_route_graph::run mock.dcp [file join $output preflight_deadline] \
    $specification $none}
rename ::hls_spacetime_route_graph::identity {}
rename ::hls_spacetime_route_graph::original_identity ::hls_spacetime_route_graph::identity
if {$opened != $before_opened ||
    [string first {route export time limit} [text [file join $output preflight_deadline incomplete.json]]] < 0} {
    error "preflight deadline did not retain a failure before native work"
}
set ::hls_spacetime_routes::deadline [expr {[clock milliseconds] + 60000}]
# Closure ledgers rotate before the per-file ceiling; no line is truncated.
set ::hls_spacetime_route_graph::file_limit 512
set ::hls_spacetime_route_graph::byte_limit 65536
set ::hls_spacetime_route_graph::output_bytes 0
set ::hls_spacetime_route_graph::ledger_number 0
set ::hls_spacetime_route_graph::closed_ledgers {}
set rotated [file join $output rotated]
file mkdir $rotated
::hls_spacetime_route_graph::open_ledger $rotated
for {set i 0} {$i < 10} {incr i} {
    ::hls_spacetime_route_graph::publish $rotated [format {%02d.json} $i] {{"fixture":true}} [dict create kind {"fixture"}]
}
::hls_spacetime_route_graph::close_ledger
if {[llength $::hls_spacetime_route_graph::closed_ledgers] < 2} {error "ledger never rotated"}
set lines 0
foreach reference $::hls_spacetime_route_graph::closed_ledgers {
    if {[dict get $reference bytes] > 512} {error "oversized closed ledger"}
    set body [text [dict get $reference path]]
    if {[string index $body end] ne "\n"} {error "truncated ledger line"}
    incr lines [expr {[llength [split $body "\n"]] - 1}]
}
if {$lines != 10} {error "ledger records lost"}
incr tests
puts "route graph synthetic fixtures passed: $tests"
