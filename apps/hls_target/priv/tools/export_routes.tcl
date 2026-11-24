# Read-only routed topology for explicitly selected saved timing-report net arcs.
# Source this file, then call ::hls_spacetime_routes::run in a fresh Vivado process.
# No timing/pathfinder query, implementation command or checkpoint write is used.
# Native API basis: AMD Vivado 2024.2 UG835 get_nodes/get_pips/get_wires,
# get_site_pins/get_bel_pins/get_tiles; UG912 NODE/PIP/TILE properties.
# A node is an electrical union of tile-local wires, not an ordered polyline.
namespace eval ::hls_spacetime_routes {
    variable deadline
    variable row_limit
    variable byte_limit
    variable rows
    variable bytes
    variable tile_cache
    variable escapes [list "\\" "\\\\" "\"" "\\\""]
    for {set i 0} {$i < 32} {incr i} {
        lappend escapes [format %c $i] [format {\u%04x} $i]
    }
}

# JSON fragments are composed only from explicit scalar/array/object encoders.
proc ::hls_spacetime_routes::quote {value} {
    variable escapes
    return "\"[string map $escapes $value]\""
}
proc ::hls_spacetime_routes::array {fragments} {return "\[[join $fragments ,]\]"}
proc ::hls_spacetime_routes::object {fragments} {
    set fields {}
    dict for {key value} $fragments {lappend fields "[quote $key]:$value"}
    return "\{[join $fields ,]\}"
}
proc ::hls_spacetime_routes::strings {values} {
    set fragments {}
    foreach value $values {lappend fragments [quote $value]}
    return [array $fragments]
}

# Native calls may block; the caller also owns a wall-time/process-memory guard.
proc ::hls_spacetime_routes::budget {{increment 0}} {
    variable deadline
    variable row_limit
    variable byte_limit
    variable rows
    variable bytes
    incr rows $increment
    if {[clock milliseconds] > $deadline} {error "route export time limit"}
    if {$rows > $row_limit} {error "route export record limit"}
    if {$bytes > $byte_limit} {error "route export byte limit"}
}

# All published rows count against both the record and UTF-8 byte ceilings.
proc ::hls_spacetime_routes::row {fields} {
    variable bytes
    set json [object $fields]
    incr bytes [string length [encoding convertto utf-8 $json]]
    budget 1
    return $json
}

# Scalar native properties avoid collection/property cardinality ambiguities.
proc ::hls_spacetime_routes::names {objects} {
    set values {}
    foreach obj $objects {lappend values [get_property NAME $obj]}
    return [lsort -unique $values]
}
proc ::hls_spacetime_routes::exact {command name} {
    set found [$command [list $name]]
    if {[llength $found] != 1 || [get_property NAME $found] ne $name} {
        error "nonexact $command lookup: $name"
    }
    return [lindex $found 0]
}
proc ::hls_spacetime_routes::canonical {net} {
    set roots [get_nets -segments -top_net_of_hierarchical_group $net]
    if {[llength $roots] != 1} {error "ambiguous canonical net: $net"}
    return [lindex $roots 0]
}
proc ::hls_spacetime_routes::hash {path} {
    set digest [lindex [exec sha256sum -- $path] 0]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {error "invalid file digest: $path"}
    return $digest
}

# Coordinates come from the native TILE, never a parsed object name or centroid.
proc ::hls_spacetime_routes::tile {obj} {
    variable tile_cache
    set tiles [get_tiles -of_objects $obj]
    if {[llength $tiles] != 1} {error "nonunique tile for native object: $obj"}
    set name [get_property NAME $tiles]
    if {[dict exists $tile_cache $name]} {return [dict get $tile_cache $name]}
    set x [get_property GRID_POINT_X $tiles]
    set y [get_property GRID_POINT_Y $tiles]
    if {![string is integer -strict $x] || ![string is integer -strict $y] || $x < 0 || $y < 0} {
        error "invalid native tile coordinate: $name"
    }
    set position [dict create tile [quote $name] x $x y $y]
    dict set tile_cache $name $position
    return $position
}

# Keep every wire's tile membership without inventing ordering within a node.
proc ::hls_spacetime_routes::node {obj} {
    budget
    set wires {}
    foreach wire [get_wires -of_objects $obj] {
        lappend wires [row [dict merge [dict create id [quote [get_property NAME $wire]]] [tile $wire]]]
    }
    return [row [dict create id [quote [get_property NAME $obj]] wires [array $wires]]]
}

# Only PIPs assigned to the selected net are passed here. Device adjacency is
# intersected with that net's used nodes; bidirectionality is not an orientation.
proc ::hls_spacetime_routes::pip {obj used} {
    budget
    set from [names [get_nodes -uphill -of_objects $obj]]
    set to [names [get_nodes -downhill -of_objects $obj]]
    set direction unavailable
    set a null
    set b null
    if {[llength $from] == 1 && [llength $to] == 1 &&
        [dict exists $used [lindex $from 0]] && [dict exists $used [lindex $to 0]]} {
        set a [quote [lindex $from 0]]
        set b [quote [lindex $to 0]]
        if {![catch {get_property IS_DIRECTIONAL $obj} directional]} {
            if {$directional in {1 true}} {set direction directional}
            if {$directional in {0 false}} {set direction bidirectional}
        }
    }
    return [row [dict merge [dict create id [quote [get_property NAME $obj]] \
        from_node $a to_node $b direction_status [quote $direction]] [tile $obj]]]
}

# Missing pin/site mappings remain explicit. A known pin on the wrong physical
# net is a binding error, not missing evidence. In-site geometry is not implied.
proc ::hls_spacetime_routes::attachment {name net_name used} {
    set base [dict create pin [quote $name] direction null bel_pins {[]} site_pins {[]} routing_node null status [quote unavailable] reason null]
    if {[catch {exact get_pins $name} pin]} {
        dict set base reason [quote "pin lookup: $pin"]
        return [row $base]
    }
    if {[catch {get_property DIRECTION $pin} direction]} {
        dict set base reason [quote "pin direction: $direction"]
        return [row $base]
    }
    dict set base direction [quote $direction]
    set connected {}
    foreach net [get_nets -of_objects $pin] {
        lappend connected [get_property NAME [canonical $net]]
    }
    if {$net_name ni $connected} {error "selected pin/net mismatch: $name / $net_name"}
    if {[catch {get_bel_pins -of_objects $pin} bels]} {
        dict set base reason [quote "BEL pin query: $bels"]
        return [row $base]
    }
    if {[catch {get_site_pins -of_objects $pin} sites]} {
        dict set base reason [quote "site pin query: $sites"]
        return [row $base]
    }
    dict set base bel_pins [strings [names $bels]]
    set mappings {}
    set nodes {}
    set ambiguous 0
    foreach site $sites {
        set candidates [names [get_nodes -of_objects $site]]
        set native_node null
        if {[llength $candidates] == 1 && [dict exists $used [lindex $candidates 0]]} {
            set native_node [quote [lindex $candidates 0]]
            lappend nodes [lindex $candidates 0]
        } else {
            set ambiguous 1
        }
        lappend mappings [row [dict create id [quote [get_property NAME $site]] node $native_node]]
    }
    dict set base site_pins [array $mappings]
    set nodes [lsort -unique $nodes]
    if {[llength $nodes] == 1 && !$ambiguous} {
        dict set base routing_node [quote [lindex $nodes 0]]
        dict set base status [quote resolved]
    } elseif {[llength $sites] == 0 && [llength $bels] > 0} {
        dict set base status [quote intrasite]
    } elseif {[llength $sites] > 0} {
        dict set base status [quote ambiguous]
    }
    return [row $base]
}

# Each selected physical net and selected endpoint is queried once, preserving
# all used fanout branches so a consumer can reject ambiguous branch selection.
proc ::hls_spacetime_routes::net {obj pins} {
    set name [get_property NAME $obj]
    puts "SPACETIME_ROUTE_NET_START $name"
    flush stdout
    set native_nodes [get_nodes -of_objects $obj]
    set used [dict create]
    set nodes {}
    foreach item $native_nodes {
        dict set used [get_property NAME $item] 1
        lappend nodes [node $item]
    }
    set pips {}
    foreach item [get_pips -of_objects $obj] {lappend pips [pip $item $used]}
    set attachments {}
    foreach pin [lsort -unique $pins] {lappend attachments [attachment $pin $name $used]}
    set json [row [dict create id [quote $name] route_status [quote [get_property ROUTE_STATUS $obj]] \
        status [quote complete] nodes [array $nodes] pips [array $pips] \
        pin_attachments [array $attachments] issues {[]}]]
    puts "SPACETIME_ROUTE_NET_COMPLETE $name [llength $nodes] [llength $pips]"
    flush stdout
    return $json
}

# The caller creates SELECTION from hash-bound saved report arcs. No newly
# queried timing path can silently replace a saved path or change its ordinal.
proc ::hls_spacetime_routes::selection {selection} {
    foreach key {checkpoint_sha256 report_sha256 selection_sha256} {
        if {![regexp {^[0-9a-f]{64}$} [dict get $selection $key]]} {error "invalid selection digest: $key"}
    }
    foreach key {source rtl observation implementation} {
        if {![regexp {^[0-9a-f]{64}$} [dict get $selection build $key]]} {error "invalid build digest: $key"}
    }
    set paths [dict get $selection paths]
    if {![llength $paths] || [llength $paths] > 10000} {error "selected arc count limit"}
    set identities [dict create]
    set path_ids [dict create]
    foreach path $paths {
        foreach key {path_id arc_index report_net canonical_net source_pin target_pin} {
            if {![dict exists $path $key] || [dict get $path $key] eq ""} {error "missing selected arc field: $key"}
        }
        set index [dict get $path arc_index]
        if {![string is integer -strict $index] || $index < 0} {error "invalid arc index"}
        set id [list [dict get $path path_id] $index]
        if {[dict exists $identities $id]} {error "duplicate selected arc: $id"}
        dict set identities $id 1
        dict set path_ids [dict get $path path_id] 1
    }
    if {[dict size $path_ids] > 50} {error "selected path count limit"}
    return $paths
}

# OUTPUT must be fresh. Complete routes.json is published only after every net
# and the unchanged checkpoint hash are checked. Failures retain diagnostics.
proc ::hls_spacetime_routes::run {checkpoint output selection {limits {}}} {
    variable deadline
    variable row_limit
    variable byte_limit
    variable rows
    variable bytes
    variable tile_cache
    set ceilings [dict create seconds 600 records 2000000 bytes 268435456 nets 1000]
    dict for {key value} $limits {
        if {![dict exists $ceilings $key] || ![string is integer -strict $value] ||
            $value <= 0 || $value > [dict get $ceilings $key]} {error "invalid route limit: $key"}
        dict set ceilings $key $value
    }
    set paths [selection $selection]
    if {[file exists $output]} {error "route output already exists: $output"}
    set started [clock milliseconds]
    set deadline [expr {$started + 1000 * [dict get $ceilings seconds]}]
    set row_limit [dict get $ceilings records]
    set byte_limit [dict get $ceilings bytes]
    set rows 0
    set bytes 0
    set tile_cache [dict create]
    file mkdir $output
    set channel [open [file join $output routes.json] {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    if {[catch {
        if {[hash $checkpoint] ne [dict get $selection checkpoint_sha256]} {error "checkpoint hash mismatch"}
        set_param general.maxThreads 2
        open_checkpoint $checkpoint
        set nets [dict create]
        set report_cache [dict create]
        set selected {}
        foreach path $paths {
            budget
            set report_name [dict get $path report_net]
            if {![dict exists $report_cache $report_name]} {
                dict set report_cache $report_name [canonical [exact get_nets $report_name]]
            }
            set obj [dict get $report_cache $report_name]
            set name [get_property NAME $obj]
            if {$name ne [dict get $path canonical_net]} {error "canonical net mismatch: $name"}
            dict set nets $name object $obj
            foreach key {source_pin target_pin} {
                dict set nets $name pins [dict get $path $key] 1
            }
            set fields [dict create]
            dict for {key value} $path {
                if {$key eq "arc_index"} {dict set fields $key $value} else {dict set fields $key [quote $value]}
            }
            lappend selected [row $fields]
        }
        if {[dict size $nets] > [dict get $ceilings nets]} {error "selected net count limit"}
        set build [dict create]
        dict for {key value} [dict get $selection build] {dict set build $key [quote $value]}
        set header [dict create schema_version 1 complete true scope [quote static_route_topology] \
            coordinate_unit [quote tile_grid] build [object $build]]
        foreach key {checkpoint_sha256 report_sha256 selection_sha256} {
            dict set header $key [quote [dict get $selection $key]]
        }
        dict set header paths [array $selected]
        set prefix [string range [object $header] 0 end-1]
        puts -nonewline $channel "$prefix,\"nets\":\["
        set separator ""
        dict for {name entry} $nets {
            set value [net [dict get $entry object] [dict keys [dict get $entry pins]]]
            puts -nonewline $channel "$separator$value"
            flush $channel
            set separator ,
            budget
        }
        if {[hash $checkpoint] ne [dict get $selection checkpoint_sha256]} {error "checkpoint changed during export"}
        puts $channel "\]\}"
        close $channel
        set channel ""
        if {[file size [file join $output routes.json]] > $byte_limit} {error "route export byte limit"}
        set done [open [file join $output complete.json] {WRONLY CREAT EXCL}]
        puts $done [object [dict create complete true elapsed_ms [expr {[clock milliseconds]-$started}] \
            records $rows bytes [file size [file join $output routes.json]] \
            routes_sha256 [quote [hash [file join $output routes.json]]]]]
        close $done
    } message options]} {
        if {$channel ne ""} {catch {close $channel}}
        set failed [open [file join $output incomplete.json] {WRONLY CREAT EXCL}]
        puts $failed [object [dict create complete false reason [quote $message] records $rows bytes $bytes]]
        close $failed
        return -options $options $message
    }
    puts "SPACETIME_ROUTE_EXPORT_COMPLETE $output"
}
