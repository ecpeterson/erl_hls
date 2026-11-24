# Small synthetic Vivado API fixture. This checks orchestration and identity
# failures, not native API availability, routed geometry or hardware behavior.
# Usage: tclsh test/native/export_routes_tests.tcl FRESH_OUTPUT_DIRECTORY
source [file join [file dirname [info script]] ../../priv/tools/export_routes.tcl]
if {[llength $argv] != 1 || [file exists [lindex $argv 0]]} {error "fresh output directory required"}
set output [lindex $argv 0]
file mkdir $output
set digest [string repeat a 64]
set counters [dict create]
set properties [dict create \
    net [dict create NAME net ROUTE_STATUS ROUTED] \
    q [dict create NAME q DIRECTION OUT] d [dict create NAME d DIRECTION IN] \
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
    if {[lindex $args 0] eq "-of_objects"} {return net}
    if {$args eq "net"} {return net}
    return {}
}
proc get_pins {args} {
    set name [lindex $args 0]
    if {$name in {q d sibling internal}} {return $name}
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
    return [dict get [dict create q bq d bd sibling bd internal bi] [lindex $args end]]
}
proc get_site_pins {args} {
    return [dict get [dict create q sq d sd sibling {sq sd} internal {}] [lindex $args end]]
}
# The real exporter checks SHA256 twice; synthetic orchestration substitutes an
# explicit constant instead of pretending to possess a native checkpoint.
rename ::hls_spacetime_routes::hash ::hls_spacetime_routes::native_hash
proc ::hls_spacetime_routes::hash {path} {return $::digest}
set opened 0
set build [dict create source $digest rtl $digest observation $digest implementation $digest]
set arc [dict create path_id max/0 arc_index 0 report_net net canonical_net net source_pin q target_pin d]
set duplicate [dict replace $arc path_id max/1]
set selection [dict create build $build checkpoint_sha256 $digest report_sha256 $digest selection_sha256 $digest paths [list $arc $duplicate]]
::hls_spacetime_routes::run mock.dcp [file join $output good] $selection
if {$opened != 1 || [dict get $counters net_nodes] != 1} {error "net queried more than once"}
set channel [open [file join $output good routes.json]]
set result [read $channel]
close $channel
foreach expected {{"scope":"static_route_topology"} {"implementation":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"} {"routing_node":"n0","status":"resolved"} {"direction_status":"bidirectional"} {"id":"w2","tile":"tile_b","x":4,"y":7}} {
    if {[string first $expected $result] < 0} {error "missing expected output: $expected"}
}
set used [dict create n0 1 n1 1 n2 1]
foreach {pin status} {missing unavailable internal intrasite sibling ambiguous} {
    set value [::hls_spacetime_routes::attachment $pin net $used]
    if {[string first "\"status\":\"$status\"" $value] < 0} {error "bad attachment disposition: $pin"}
}
if {![catch {::hls_spacetime_routes::attachment q wrong_net $used}]} {error "wrong net accepted"}
set wrong [dict replace $selection checkpoint_sha256 [string repeat b 64]]
if {![catch {::hls_spacetime_routes::run mock.dcp [file join $output wrong] $wrong}]} {error "wrong checkpoint accepted"}
if {[file exists [file join $output wrong complete.json]]} {error "failed export has completion marker"}
set duplicate [dict replace $selection paths [list $arc $arc]]
if {![catch {::hls_spacetime_routes::selection $duplicate}]} {error "duplicate arc identity accepted"}
set missing_implementation [dict replace $selection build [dict remove $build implementation]]
if {![catch {::hls_spacetime_routes::selection $missing_implementation}]} {error "missing implementation accepted"}
puts "route exporter synthetic fixture passed"
