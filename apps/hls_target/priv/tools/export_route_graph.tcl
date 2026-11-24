# Read-only whole-population routed topology. Unlike export_routes.tcl, this
# boundary accepts canonical nets and native endpoints, never sampled paths.
# Reuse indexes are caller-validated projections of hash-bound closed JSON
# records. No synthesis, placement, routing, timing or replay command runs here.
source [file join [file dirname [info script]] export_routes.tcl]

namespace eval ::hls_spacetime_route_graph {
    variable output_bytes
    variable byte_limit
    variable file_limit
    variable ledger
    variable ledger_path
    variable ledger_bytes
    variable ledger_number
    variable closed_ledgers
    variable net_index
    variable endpoint_index
    variable reuse_index
    variable reused_endpoint_index
    variable reference_index
}

# Validate an exact, bounded native identity without interpreting Tcl metacharacters.
proc ::hls_spacetime_route_graph::identity {value} {
    if {$value eq "" || [string length $value] > 4096 || [regexp {[\x00-\x1f\x7f]} $value]} {
        error "invalid route-graph identity"
    }
    return $value
}

# Hash formats are checked independently from trusted native/control authenticity.
proc ::hls_spacetime_route_graph::digest {value} {
    if {![regexp {^[0-9a-f]{64}$} $value]} {error "invalid route-graph digest"}
    return $value
}

# New whole-graph work has its own finite ceilings; these are not display samples.
proc ::hls_spacetime_route_graph::limits {requested} {
    set bounds [dict create seconds 3600 records 8000000 bytes 536870912 \
        file_bytes 16777216 nets 100000 endpoints 1000000]
    dict for {key value} $requested {
        if {![dict exists $bounds $key] || ![string is integer -strict $value] || \
            $value <= 0 || $value > [dict get $bounds $key]} {error "invalid route-graph limit: $key"}
        dict set bounds $key $value
    }
    return $bounds
}

# Every canonical net and endpoint appears once, including constants and clocks.
# Directions/type/route status are the retained catalogue's exact native values.
# Population indexes are arrays, with only scalar counts returned: the retained
# native diagnostic found expensive bookkeeping through large dictionary values.
proc ::hls_spacetime_route_graph::demand {demand limits} {
    variable net_index
    variable endpoint_index
    array unset net_index
    array set net_index {}
    array unset endpoint_index
    array set endpoint_index {}
    ::hls_spacetime_routes::budget
    if {[dict get $demand schema_version] != 1} {error "unsupported route-graph demand"}
    foreach key {checkpoint_sha256 catalogue_sha256 demand_sha256} {digest [dict get $demand $key]}
    foreach key {source rtl observation implementation} {digest [dict get $demand build $key]}
    set nets [dict get $demand nets]
    if {![llength $nets] || [llength $nets] > [dict get $limits nets]} {error "route-graph net limit"}
    set net_count 0
    set endpoint_count 0
    set endpoint_limit [dict get $limits endpoints]
    foreach net $nets {
        ::hls_spacetime_routes::budget
        set id [identity [dict get $net id]]
        if {[info exists net_index($id)]} {error "duplicate canonical net: $id"}
        set net_index($id) 1
        incr net_count
        foreach key {type route_status} {identity [dict get $net $key]}
        foreach endpoint [dict get $net pins] {
            ::hls_spacetime_routes::budget
            set pin [identity [dict get $endpoint pin]]
            if {[info exists endpoint_index($pin)]} {error "duplicate native endpoint: $pin"}
            if {[dict get $endpoint kind] ni {pin port} ||
                [dict get $endpoint direction] ni {IN OUT INOUT}} {error "invalid endpoint kind/direction: $pin"}
            set endpoint_index($pin) $id
            if {[incr endpoint_count] > $endpoint_limit} {error "route-graph endpoint limit"}
        }
        if {$net_count % 1000 == 0} {
            puts "SPACETIME_ROUTE_GRAPH_DEMAND $net_count $endpoint_count"
            flush stdout
        }
    }
    return [dict create nets $net_count endpoints $endpoint_count]
}

# Reuse files are immutable complete records authenticated before any native work.
# The producer must also check that the supplied node/pin indexes equal the JSON
# content; consumers recheck that projection before accepting the assembled graph.
proc ::hls_spacetime_route_graph::reference {reference} {
    set path [dict get $reference path]
    set expected [digest [dict get $reference sha256]]
    set bytes [dict get $reference bytes]
    if {![string is integer -strict $bytes] || $bytes < 0 || $bytes > 16777216 ||
        ![file isfile $path] || [file size $path] != $bytes ||
        [::hls_spacetime_routes::hash $path] ne $expected} {error "invalid reuse file: $path"}
    return [dict create path [file normalize $path] sha256 $expected bytes $bytes]
}

# Reuse never claims a pin absent from the complete demand, and duplicate source
# files are authenticated once. A net's geometry and attachments are independent.
# Indexes stay in arrays; no growing population dictionary crosses a command.
proc ::hls_spacetime_route_graph::reuse {reuse} {
    variable net_index
    variable endpoint_index
    variable reuse_index
    variable reused_endpoint_index
    variable reference_index
    foreach index {reuse_index reused_endpoint_index reference_index} {
        array unset $index
        array set $index {}
    }
    set count 0
    foreach row [dict get $reuse nets] {
        ::hls_spacetime_routes::budget
        set id [dict get $row id]
        if {![info exists net_index($id)] || [info exists reuse_index($id)]} {error "invalid reused net: $id"}
        set references [list [dict get $row geometry]]
        foreach source [dict get $row attachments] {lappend references $source}
        foreach source $references {
            set key [list [dict get $source path] [dict get $source sha256] [dict get $source bytes]]
            if {![info exists reference_index($key)]} {reference $source; set reference_index($key) 1}
        }
        set nodes [dict get $row nodes]
        if {[llength $nodes] != [llength [lsort -unique $nodes]]} {error "duplicate reused node: $id"}
        foreach node $nodes {identity $node}
        set pin_count 0
        foreach source [dict get $row attachments] {
            foreach pin [dict get $source pins] {
                ::hls_spacetime_routes::budget
                if {![info exists endpoint_index($pin)] ||
                    $endpoint_index($pin) ne $id || [info exists reused_endpoint_index($pin)]} {
                    error "invalid reused endpoint: $pin"
                }
                set reused_endpoint_index($pin) 1
                incr pin_count
            }
        }
        dict set row pin_count $pin_count
        set reuse_index($id) $row
        incr count
    }
    return $count
}

# Small metadata uses the same explicit JSON encoders as the measured exporter.
proc ::hls_spacetime_route_graph::reference_json {reference} {
    return [::hls_spacetime_routes::object [dict create \
        path [::hls_spacetime_routes::quote [dict get $reference path]] \
        sha256 [::hls_spacetime_routes::quote [dict get $reference sha256]] \
        bytes [dict get $reference bytes]]]
}

# Closed-ledger shards stay below the same per-file ceiling as geometry. A
# complete line authenticates a closed output record; the final partial line
# of an interrupted shard is excluded by bounded prefix preservation.
proc ::hls_spacetime_route_graph::open_ledger {output} {
    variable ledger
    variable ledger_path
    variable ledger_bytes
    variable ledger_number
    set ledger_path [file join $output closed-records [format {%06d.jsonl} [incr ledger_number]]]
    file mkdir [file dirname $ledger_path]
    set ledger [open $ledger_path {WRONLY CREAT EXCL}]
    fconfigure $ledger -encoding utf-8 -translation lf
    set ledger_bytes 0
}

# A full manifest inventories only ledgers which were actually closed.
proc ::hls_spacetime_route_graph::close_ledger {} {
    variable ledger
    variable ledger_path
    variable closed_ledgers
    if {$ledger eq ""} {return}
    close $ledger
    set ledger ""
    lappend closed_ledgers [dict create path $ledger_path bytes [file size $ledger_path] \
        sha256 [::hls_spacetime_routes::hash $ledger_path]]
}

# Publish one immutable bounded shard. Its hash/size enters the append-only
# closed-record ledger only after the shard is closed; a partial last line is
# never accepted by recovery. Reuse of a completed record requires no requery.
proc ::hls_spacetime_route_graph::publish {output relative json fields} {
    variable output_bytes
    variable byte_limit
    variable file_limit
    variable ledger
    variable ledger_bytes
    ::hls_spacetime_routes::budget
    set bytes [encoding convertto utf-8 "$json\n"]
    set size [string length $bytes]
    set path [file join $output $relative]
    set provisional [dict create path $path sha256 [string repeat 0 64] bytes $size]
    dict set fields file [reference_json $provisional]
    set ledger_size [string length [encoding convertto utf-8 "[::hls_spacetime_routes::object $fields]\n"]]
    if {$size > $file_limit || $ledger_size > $file_limit || $output_bytes + $size + $ledger_size > $byte_limit} {
        error "route-graph output byte limit"
    }
    if {$ledger_bytes > 0 && $ledger_bytes + $ledger_size > min(4194304, $file_limit)} {
        close_ledger
        open_ledger $output
    }
    file mkdir [file dirname $path]
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -translation binary
    puts -nonewline $channel $bytes
    close $channel
    incr output_bytes [expr {$size + $ledger_size}]
    set reference [dict create path $path sha256 [::hls_spacetime_routes::hash $path] bytes $size]
    dict set fields file [reference_json $reference]
    puts $ledger [::hls_spacetime_routes::object $fields]
    flush $ledger
    incr ledger_bytes $ledger_size
    return $reference
}

# The full manifest is the final atomic rename, after its bytes and the closed
# record ledger are closed. Failure before that point leaves only a prefix.
proc ::hls_spacetime_route_graph::complete {output json} {
    variable output_bytes
    variable byte_limit
    variable file_limit
    ::hls_spacetime_routes::budget
    set bytes [encoding convertto utf-8 "$json\n"]
    set size [string length $bytes]
    if {$size > $file_limit || $output_bytes + $size > $byte_limit} {error "route-graph manifest byte limit"}
    set temporary [file join $output manifest.partial]
    set channel [open $temporary {WRONLY CREAT EXCL}]
    fconfigure $channel -translation binary
    puts -nonewline $channel $bytes
    close $channel
    file rename $temporary [file join $output manifest.json]
    incr output_bytes $size
}

# Geometry retains all used fanout branches. A native node's wire set remains
# unordered tile membership; no shortest path, physical length or timing is inferred.
proc ::hls_spacetime_route_graph::geometry {obj} {
    set id [get_property NAME $obj]
    set used [dict create]
    set nodes {}
    foreach node [get_nodes -of_objects $obj] {
        dict set used [get_property NAME $node] 1
        lappend nodes [::hls_spacetime_routes::node $node]
    }
    set pips {}
    foreach pip [get_pips -of_objects $obj] {lappend pips [::hls_spacetime_routes::pip $pip $used]}
    set fields [dict create id [::hls_spacetime_routes::quote $id] \
        route_status [::hls_spacetime_routes::quote [get_property ROUTE_STATUS $obj]] \
        status [::hls_spacetime_routes::quote complete] \
        nodes [::hls_spacetime_routes::array $nodes] pips [::hls_spacetime_routes::array $pips] \
        pin_attachments {[]} issues {[]}]
    return [list [::hls_spacetime_routes::row $fields] [dict keys $used]]
}

# Primitive-pin attachment is the previously qualified native query. Top ports
# have verified net/direction membership but no implied package/site geometry.
proc ::hls_spacetime_route_graph::attachment {endpoint net used} {
    set pin [dict get $endpoint pin]
    if {[dict get $endpoint kind] eq "pin"} {
        set object [::hls_spacetime_routes::exact get_pins $pin]
        if {[get_property DIRECTION $object] ne [dict get $endpoint direction]} {error "pin direction mismatch: $pin"}
        return [::hls_spacetime_routes::attachment $pin $net $used]
    }
    set object [::hls_spacetime_routes::exact get_ports $pin]
    if {[get_property DIRECTION $object] ne [dict get $endpoint direction]} {error "port direction mismatch: $pin"}
    set connected {}
    foreach item [get_nets -of_objects $object] {
        lappend connected [get_property NAME [::hls_spacetime_routes::canonical $item]]
    }
    if {[lsort -unique $connected] ne [list $net]} {error "port/net mismatch: $pin"}
    return [::hls_spacetime_routes::row [dict create pin [::hls_spacetime_routes::quote $pin] \
        kind [::hls_spacetime_routes::quote port] direction [::hls_spacetime_routes::quote [dict get $endpoint direction]] \
        bel_pins {[]} site_pins {[]} routing_node null status [::hls_spacetime_routes::quote unavailable] \
        reason [::hls_spacetime_routes::quote top_level_port_site_geometry_not_exported]]]
}

# Every closed attachment batch can be reused independently after a later guard.
proc ::hls_spacetime_route_graph::attachments {output ordinal batch id rows pins} {
    set payload [::hls_spacetime_routes::object [dict create id [::hls_spacetime_routes::quote $id] \
        pin_attachments [::hls_spacetime_routes::array $rows]]]
    set reference [publish $output [format {attachments/%06d-%06d.json} $ordinal $batch] $payload \
        [dict create kind [::hls_spacetime_routes::quote attachments] net [::hls_spacetime_routes::quote $id] \
            pins [::hls_spacetime_routes::strings $pins]]]
    dict set reference pins $pins
    return $reference
}

# Completed net indexes reference immutable geometry and attachment shards.
proc ::hls_spacetime_route_graph::net_json {entry geometry attachments} {
    set sources {}
    foreach source $attachments {
        lappend sources [::hls_spacetime_routes::object [dict create \
            file [reference_json $source] pins [::hls_spacetime_routes::strings [dict get $source pins]]]]
    }
    set endpoints {}
    foreach pin [dict get $entry pins] {
        set fields [dict create]
        dict for {key value} $pin {dict set fields $key [::hls_spacetime_routes::quote $value]}
        lappend endpoints [::hls_spacetime_routes::object $fields]
    }
    return [::hls_spacetime_routes::object [dict create id [::hls_spacetime_routes::quote [dict get $entry id]] \
        type [::hls_spacetime_routes::quote [dict get $entry type]] \
        route_status [::hls_spacetime_routes::quote [dict get $entry route_status]] \
        complete true geometry [reference_json $geometry] \
        attachments [::hls_spacetime_routes::array $sources] endpoints [::hls_spacetime_routes::array $endpoints]]]
}

# Open the exact saved DCP once, query only absent geometry/endpoints, and retain
# each complete shard. The outer process-group guard covers blocking native calls.
# A full completion manifest is impossible until all requested net indexes close.
proc ::hls_spacetime_route_graph::run {checkpoint output specification reuse_spec {requested {}}} {
    variable output_bytes
    variable byte_limit
    variable file_limit
    variable ledger
    variable ledger_number
    variable closed_ledgers
    variable reuse_index
    variable reused_endpoint_index
    set bounds [limits $requested]
    set started [clock milliseconds]
    set ::hls_spacetime_routes::deadline [expr {$started + 1000 * [dict get $bounds seconds]}]
    set ::hls_spacetime_routes::row_limit [dict get $bounds records]
    set ::hls_spacetime_routes::byte_limit [dict get $bounds bytes]
    set ::hls_spacetime_routes::rows 0
    set ::hls_spacetime_routes::bytes 0
    set ::hls_spacetime_routes::tile_cache [dict create]
    if {[file exists $output]} {error "route-graph output already exists"}
    set output [file normalize $output]
    set output_bytes 0
    set byte_limit [dict get $bounds bytes]
    set file_limit [dict get $bounds file_bytes]
    file mkdir $output
    set ledger_number 0
    set closed_ledgers {}
    set ledger ""
    open_ledger $output
    set completed {}
    set new_geometry 0
    set new_endpoints 0
    set reused_endpoints 0
    if {[catch {
        puts "SPACETIME_ROUTE_GRAPH_PHASE demand_start [clock milliseconds]"
        flush stdout
        set population [demand $specification $bounds]
        set net_count [dict get $population nets]
        set endpoint_count [dict get $population endpoints]
        puts "SPACETIME_ROUTE_GRAPH_PHASE demand_complete [clock milliseconds] $net_count $endpoint_count"
        puts "SPACETIME_ROUTE_GRAPH_PHASE reuse_start [clock milliseconds]"
        flush stdout
        set reused_count [reuse $reuse_spec]
        puts "SPACETIME_ROUTE_GRAPH_PHASE reuse_complete [clock milliseconds] $reused_count"
        flush stdout
        if {[::hls_spacetime_routes::hash $checkpoint] ne [dict get $specification checkpoint_sha256]} {
            error "route-graph checkpoint mismatch"
        }
        set_param general.maxThreads 2
        ::hls_spacetime_routes::budget
        puts "SPACETIME_ROUTE_GRAPH_PHASE checkpoint_start [clock milliseconds]"
        flush stdout
        open_checkpoint $checkpoint
        puts "SPACETIME_ROUTE_GRAPH_PHASE checkpoint_complete [clock milliseconds]"
        flush stdout
        set ordinal 0
        foreach entry [dict get $specification nets] {
            ::hls_spacetime_routes::budget
            incr ordinal
            set id [dict get $entry id]
            set sources {}
            set object ""
            if {[info exists reuse_index($id)]} {
                set prior $reuse_index($id)
                set geometry [dict get $prior geometry]
                set nodes [dict get $prior nodes]
                set sources [dict get $prior attachments]
                incr reused_endpoints [dict get $prior pin_count]
            } else {
                set object [::hls_spacetime_routes::exact get_nets $id]
                if {[get_property NAME [::hls_spacetime_routes::canonical $object]] ne $id} {error "noncanonical net: $id"}
                foreach key {type route_status} property {TYPE ROUTE_STATUS} {
                    if {[get_property $property $object] ne [dict get $entry $key]} {error "native net disposition mismatch: $id / $key"}
                }
                lassign [geometry $object] json nodes
                set geometry [publish $output [format {geometry/%06d.json} $ordinal] $json \
                    [dict create kind [::hls_spacetime_routes::quote geometry] net [::hls_spacetime_routes::quote $id]]]
                incr new_geometry
            }
            set used [dict create]
            foreach node $nodes {dict set used $node 1}
            set rows {}
            set pins {}
            set batch 0
            foreach endpoint [dict get $entry pins] {
                set pin [dict get $endpoint pin]
                if {[info exists reused_endpoint_index($pin)]} {continue}
                ::hls_spacetime_routes::budget
                lappend rows [attachment $endpoint $id $used]
                lappend pins $pin
                incr new_endpoints
                if {[llength $pins] == 128} {
                    lappend sources [attachments $output $ordinal [incr batch] $id $rows $pins]
                    set rows {}; set pins {}
                }
            }
            if {[llength $pins]} {lappend sources [attachments $output $ordinal [incr batch] $id $rows $pins]}
            set index [publish $output [format {nets/%06d.json} $ordinal] [net_json $entry $geometry $sources] \
                [dict create kind [::hls_spacetime_routes::quote net] net [::hls_spacetime_routes::quote $id]]]
            lappend completed [::hls_spacetime_routes::object [dict create id [::hls_spacetime_routes::quote $id] file [reference_json $index]]]
            if {$ordinal == 1 || $ordinal % 100 == 0 || $ordinal == $net_count} {
                puts "SPACETIME_ROUTE_GRAPH_NET_COMPLETE $ordinal $id"
                flush stdout
            }
        }
        if {[::hls_spacetime_routes::hash $checkpoint] ne [dict get $specification checkpoint_sha256]} {
            error "route-graph checkpoint changed"
        }
        # Recheck retained source bytes before accepting the assembled population.
        reuse $reuse_spec
        set build [dict create]
        dict for {key value} [dict get $specification build] {dict set build $key [::hls_spacetime_routes::quote $value]}
        set fields [dict create schema_version 1 complete true scope [::hls_spacetime_routes::quote static_route_graph] \
            coordinate_unit [::hls_spacetime_routes::quote tile_grid] build [::hls_spacetime_routes::object $build] \
            nets [::hls_spacetime_routes::array $completed] \
            requested_nets $net_count \
            requested_endpoints $endpoint_count \
            new_geometry $new_geometry reused_geometry $reused_count \
            new_endpoints $new_endpoints reused_endpoints $reused_endpoints \
            elapsed_ms [expr {[clock milliseconds] - $started}]]
        foreach key {checkpoint_sha256 catalogue_sha256 demand_sha256} {
            dict set fields $key [::hls_spacetime_routes::quote [dict get $specification $key]]
        }
        close_ledger
        set ledger_references {}
        foreach source $closed_ledgers {lappend ledger_references [reference_json $source]}
        dict set fields closed_records [::hls_spacetime_routes::array $ledger_references]
        complete $output [::hls_spacetime_routes::object $fields]
    } message options]} {
        if {$ledger ne ""} {catch {close_ledger}; set ledger ""}
        set channel [open [file join $output incomplete.json] {WRONLY CREAT EXCL}]
        fconfigure $channel -encoding utf-8 -translation lf
        puts $channel [::hls_spacetime_routes::object [dict create complete false \
            reason [::hls_spacetime_routes::quote $message] completed_nets [llength $completed] \
            new_geometry $new_geometry new_endpoints $new_endpoints output_bytes $output_bytes]]
        close $channel
        return -options $options $message
    }
    puts "SPACETIME_ROUTE_GRAPH_COMPLETE $net_count $endpoint_count"
}
