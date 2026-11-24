# Read-only Vivado checkpoint census for the spacetime importer. Source this file,
# then call ::hls_spacetime_export::run in a fresh Vivado process. No implementation,
# preservation attributes, timing exceptions or placement changes are performed.
# Native API references: AMD UG835 get_nets/get_pins/get_net_delays/get_timing_paths;
# UG912 TIMING_PATH. Net-delay values are picoseconds; path values are nanoseconds.
# https://docs.amd.com/r/2024.2-English/ug835-vivado-tcl-commands/get_net_delays
# https://docs.amd.com/r/en-US/ug912-vivado-properties/TIMING_PATH
# https://docs.amd.com/r/2023.2-English/ug894-vivado-tcl-scripting/Accessing-Design-Objects
namespace eval ::hls_spacetime_export {
    variable state
    variable deadline_ms
    variable record_limit
    variable byte_limit
    variable records
    variable bytes
    variable cell_index
    variable placement_index
    variable alias_index
    variable canonical_index
    # Tcl's string map performs one nonrecursive C-level pass over each value.
    variable json_escapes [list "\\" "\\\\" "\"" "\\\""]
    for {set code 0} {$code < 32} {incr code} {
        lappend json_escapes [format %c $code] [format {\u%04x} $code]
    }
}

# Escape only the four TSV metacharacters; readers must reject unknown escapes.
proc ::hls_spacetime_export::field {value} {
    return [string map [list \\ \\\\ \t \\t \n \\n \r \\r] $value]
}

# JSON metadata is scalar-only except for explicitly assembled object fragments.
proc ::hls_spacetime_export::quote {value} {
    variable json_escapes
    return "\"[string map $json_escapes $value]\""
}

# A caller may tighten registered ceilings, never enlarge them implicitly.
proc ::hls_spacetime_export::limits {requested} {
    set ceiling [dict create seconds 600 records 2000000 bytes 268435456 max_paths 50]
    dict for {key value} $requested {
        if {![dict exists $ceiling $key] || ![string is integer -strict $value] ||
            $value <= 0 || $value > [dict get $ceiling $key]} {
            error "invalid export limit: $key=$value"
        }
        dict set ceiling $key $value
    }
    if {[dict get $ceiling bytes] < 131072} {error "export byte limit too small"}
    return $ceiling
}

# The outer process guard covers time spent inside a blocking native query.
proc ::hls_spacetime_export::budget {} {
    variable deadline_ms
    variable record_limit
    variable byte_limit
    variable records
    variable bytes
    if {[clock milliseconds] > $deadline_ms} {
        error "export time limit"
    }
    if {$records > $record_limit} {error "export record limit"}
    # Reserve bounded metadata space before writing any table or native report.
    if {$bytes > $byte_limit - 65536} {error "export byte limit"}
}

# Flush coarse phase markers so terminal logs separate native queries from encoding.
proc ::hls_spacetime_export::stage_start {name} {
    set now [clock milliseconds]
    puts "SPACETIME_EXPORT_STAGE_START $name $now"
    flush stdout
    return $now
}

# Close complete tables before publishing a bounded, independently durable stage marker.
# A phase marker never substitutes for the final complete catalogue manifest.
proc ::hls_spacetime_export::stage_finish {name started {completed_tables {}}} {
    variable state
    foreach table $completed_tables {close_table $table}
    flush_tables
    set now [clock milliseconds]
    set tables {}
    dict for {table entry} [dict get $state tables] {
        set complete [expr {[dict exists $entry channel] ? "false" : "true"}]
        lappend tables "[quote $table]:\{\"rows\":[dict get $entry rows],\"bytes\":[dict get $entry bytes],\"complete\":$complete\}"
    }
    set reports {}
    dict for {report bytes} [dict get $state reports] {lappend reports "[quote $report]:$bytes"}
    set text "\{\"phase\":[quote $name],\"complete\":true,\"elapsed_ms\":[expr {$now-$started}],\"tables\":\{[join $tables ,]\},\"reports\":\{[join $reports ,]\}\}"
    set bytes [string length [encoding convertto utf-8 "$text\n"]]
    if {[dict get $state metadata_bytes]+$bytes > 32768} {error "phase metadata byte limit"}
    set channel [open [file join [dict get $state output] "phase-$name.json"] {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel $text
    close $channel
    dict incr state metadata_bytes $bytes
    puts "SPACETIME_EXPORT_STAGE_COMPLETE $name $now [expr {$now - $started}]"
    flush stdout
}

# Periodic counters separate a slow native population from buffered output.
proc ::hls_spacetime_export::progress {name count started} {
    variable records
    variable bytes
    if {$count % 256 != 0} {return}
    flush_tables
    puts "SPACETIME_EXPORT_PROGRESS $name $count [expr {[clock milliseconds]-$started}] $records $bytes"
    flush stdout
}

# Preserve a complete buffered prefix at every phase boundary and progress marker.
proc ::hls_spacetime_export::flush_tables {} {
    variable state
    dict for {name entry} [dict get $state tables] {
        if {[dict exists $entry channel]} {flush [dict get $entry channel]}
    }
}

# Open a fresh LF/UTF-8 table with one mandatory, uncounted header row.
proc ::hls_spacetime_export::table {name columns} {
    variable state
    set path [file join [dict get $state output] $name]
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    dict set state tables $name [dict create channel $channel rows 0 bytes 0]
    line $name $columns 0
}

# Count every data row and byte before committing it to an output channel.
proc ::hls_spacetime_export::line {name values {count 1}} {
    variable state
    variable records
    variable bytes
    set fields {}
    foreach value $values {lappend fields [field $value]}
    set text "[join $fields \t]\n"
    set encoded_bytes [string length [encoding convertto utf-8 $text]]
    if {$encoded_bytes > 1048576} {error "export line limit: $name"}
    incr records $count
    incr bytes $encoded_bytes
    set entry [dict get $state tables $name]
    dict incr entry rows $count
    dict incr entry bytes $encoded_bytes
    dict set state tables $name $entry
    budget
    puts -nonewline [dict get $entry channel] $text
}

# Properties are native strings, including empty values and parameter INIT bodies.
proc ::hls_spacetime_export::properties {table prefix object} {
    foreach property [lsort [list_property $object]] {
        line $table [concat $prefix [list $property [get_property $property $object]]]
    }
}

# A compact row retains every property string without repeating object names per property.
proc ::hls_spacetime_export::property_row {table prefix values counter} {
    variable state
    set fields {}
    dict for {key value} $values {lappend fields "[quote $key]:[quote $value]"}
    dict incr state $counter [dict size $values]
    line $table [concat $prefix [list "\{[join $fields ,]\}"]]
}

# Batch only the fixed common string columns, never configurable/boolean properties.
# Exact cardinality and NAME checks protect the native object correspondence.
proc ::hls_spacetime_export::common_columns {keys objects} {
    if {$keys ni {{NAME REF_NAME LOC BEL} {NAME PARENT_CELL REF_PIN_NAME DIRECTION}}} {
        error "unsupported common property columns"
    }
    set count [llength $objects]
    set columns [dict create]
    foreach key $keys {
        budget
        if {$count == 0} {set values {}} \
        elseif {$count == 1} {set values [list [get_property $key [lindex $objects 0]]]} \
        else {set values [get_property $key $objects]}
        if {[llength $values] != $count} {error "common property cardinality: $key"}
        dict set columns $key $values
    }
    foreach object $objects name [dict get $columns NAME] {
        if {$object ne $name} {error "common property identity/order: $object"}
    }
    return $columns
}

# Read every declared property on this instance, preserving its exact native string.
# Native scalar and bulk values disagreed for IS_BEL_FIXED; never coerce or group them.
proc ::hls_spacetime_export::property_values {object} {
    variable state
    set values [dict create]
    foreach key [lsort [list_property $object]] {
        budget
        set value [get_property $key $object]
        dict set values $key $value
        if {$key eq "HD.ISOLATED" && $value eq "" && ![dict exists $state unavailable_properties $key]} {
            issue property_support $key "Unsupported for this OOC checkpoint; empty native values are unavailable metadata, not configured false"
            dict set state unavailable_properties $key 1
        }
    }
    return $values
}

# Record missing optional timing as an issue; it is never substituted by zero.
proc ::hls_spacetime_export::issue {stage object reason} {
    line issues.tsv [list $stage $object $reason]
}

# A site's immutable coordinates are shared by every cell placed at that site.
proc ::hls_spacetime_export::placement {site bel} {
    variable placement_index
    # Partial placement is not a coordinate; raw LOC/BEL remain native properties.
    if {$site eq "" || $bel eq ""} {return [list "" "" "" "" "" "" unplaced]}
    if {[info exists placement_index($site)]} {
        return [concat [list $site $bel] $placement_index($site) [list placed]]
    }
    set sites [get_sites $site]
    if {[llength $sites] != 1} {error "ambiguous cell site: $site"}
    set tiles [get_tiles -of_objects $sites]
    if {[llength $tiles] != 1} {error "ambiguous site tile: $site"}
    set x [get_property GRID_POINT_X $tiles]
    set y [get_property GRID_POINT_Y $tiles]
    if {![string is integer -strict $x] || ![string is integer -strict $y] || $x < 0 || $y < 0} {
        error "invalid tile coordinates: $site"
    }
    set position [list [get_property NAME $tiles] $x $y [get_property CLOCK_REGION $sites]]
    set placement_index($site) $position
    return [concat [list $site $bel] $position [list placed]]
}

# Export every primitive or black-box leaf, then stream its complete instance configuration.
proc ::hls_spacetime_export::cells {{locations {}}} {
    variable state
    variable cell_index
    set started [stage_start cell_locations]
    set objects [get_cells -hier -include_replicated_objects -filter {IS_PRIMITIVE || IS_BLACKBOX} *]
    set count 0
    if {$locations eq ""} {
        table cells.tsv {name ref site bel tile x y clock_region placement}
        set common [common_columns {NAME REF_NAME LOC BEL} $objects]
        foreach cell $objects name [dict get $common NAME] ref [dict get $common REF_NAME] \
                site [dict get $common LOC] bel [dict get $common BEL] {
            budget
            if {[info exists cell_index($name)]} {error "duplicate primitive: $name"}
            set where [placement $site $bel]
            set cell_index($name) [list $ref $site $bel [lindex $where end]]
            line cells.tsv [concat [list $name $ref] $where]
            if {[lindex $where end] eq "unplaced"} {dict incr state unplaced_cells}
            incr count
            progress cell_locations $count $started
        }
    } else {
        reuse_locations $locations
        set count [llength $objects]
        if {$count != [array size cell_index]} {error "reused cell population mismatch"}
    }
    stage_finish cell_locations $started {cells.tsv}
    set started [stage_start cell_properties]
    set count 0
    array set seen_properties {}
    foreach cell $objects {
        set native [property_values $cell]
        if {![dict exists $native NAME] || ![info exists cell_index([dict get $native NAME])]} {
            error "cell property identity missing from catalogue: $cell"
        }
        set name [dict get $native NAME]
        if {[info exists seen_properties($name)]} {error "duplicate scalar cell identity: $name"}
        set seen_properties($name) 1
        foreach key {REF_NAME LOC BEL} expected [lrange $cell_index($name) 0 2] {
            if {$key ne "REF_NAME" && [lindex $cell_index($name) 3] eq "unplaced"} {continue}
            if {![dict exists $native $key] || [dict get $native $key] ne $expected} {
                error "scalar/common cell property mismatch: $name $key"
            }
        }
        if {[lindex $cell_index($name) 3] eq "unplaced" &&
            ([dict get $native LOC] ne "" && [dict get $native BEL] ne "")} {
            error "scalar/reused unplaced cell mismatch: $name"
        }
        property_row cell-properties.tsv [list $name] $native cell_property_pairs
        incr count
        progress cell_properties $count $started
    }
    if {$count != [array size cell_index]} {error "incomplete scalar cell population"}
    stage_finish cell_properties $started {cell-properties.tsv}
}

# Ordinary names take a constant-overhead path. Escaped fields use the exact
# four-character producer grammar and a nonrecursive C-level replacement pass.
proc ::hls_spacetime_export::unfield {text} {
    if {[string first "\\" $text] < 0} {return $text}
    if {![regexp {^(?:[^\\]|\\[\\tnr])*$} $text]} {error "invalid retained TSV escape"}
    return [string map [list "\\\\" "\\" "\\t" "\t" "\\n" "\n" "\\r" "\r"] $text]
}

# Reuse only a complete table whose registered phase/hash/checkpoint/build binding
# was verified. Scalar native properties later check every identity/type/placement.
proc ::hls_spacetime_export::reuse_locations {inputs} {
    variable state
    variable cell_index
    variable records
    variable bytes
    foreach key {path sha256 phase_path phase_sha256 rows bytes} {
        if {![dict exists $inputs $key]} {error "missing location input: $key"}
    }
    set source [dict get $inputs path]
    set phase [dict get $inputs phase_path]
    foreach {path expected} [list $source [dict get $inputs sha256] $phase [dict get $inputs phase_sha256]] {
        if {![regexp {^[0-9a-f]{64}$} $expected] || ![file isfile $path] ||
            [checkpoint_hash $path] ne $expected} {error "location input digest mismatch: $path"}
    }
    set expected_rows [dict get $inputs rows]
    set expected_bytes [dict get $inputs bytes]
    if {![string is integer -strict $expected_rows] || $expected_rows <= 0 ||
        ![string is integer -strict $expected_bytes] || $expected_bytes <= 0 ||
        [file size $source] != $expected_bytes || [file size $phase] > 32768} {
        error "invalid location input bounds"
    }
    set channel [open $phase r]
    set marker [read $channel]
    close $channel
    set table_marker "\"cells.tsv\":\{\"rows\":$expected_rows,\"bytes\":$expected_bytes,\"complete\":true\}"
    if {[string first {"phase":"cell_locations","complete":true,} $marker] < 0 ||
        [string first $table_marker $marker] < 0} {error "location phase/table binding mismatch"}
    incr records $expected_rows
    incr bytes $expected_bytes
    budget
    set destination [file join [dict get $state output] cells.tsv]
    file copy -- $source $destination
    if {[checkpoint_hash $destination] ne [dict get $inputs sha256]} {error "copied location digest mismatch"}
    dict set state tables cells.tsv [dict create rows $expected_rows bytes $expected_bytes]
    set channel [open $destination r]
    fconfigure $channel -encoding utf-8 -translation lf
    if {[gets $channel] ne "name\tref\tsite\tbel\ttile\tx\ty\tclock_region\tplacement"} {
        close $channel
        error "location input header"
    }
    set count 0
    while {[gets $channel text] >= 0} {
        budget
        set row {}
        foreach item [split $text \t] {lappend row [unfield $item]}
        if {[llength $row] != 9} {error "location input row width"}
        lassign $row name ref site bel tile x y region disposition
        if {$name eq "" || $ref eq "" || [info exists cell_index($name)]} {error "location input identity"}
        if {$disposition eq "placed"} {
            if {$site eq "" || $bel eq "" || $tile eq "" || ![string is integer -strict $x] ||
                ![string is integer -strict $y] || $x < 0 || $y < 0} {error "location input coordinates"}
        } elseif {$disposition eq "unplaced" && $site eq "" && $bel eq "" && $tile eq "" &&
                  $x eq "" && $y eq "" && $region eq ""} {
            dict incr state unplaced_cells
        } else {error "location input disposition"}
        set cell_index($name) [list $ref $site $bel $disposition]
        incr count
    }
    close $channel
    if {$count != $expected_rows} {error "location input row count"}
}

# Resolve one hierarchy segment to its canonical top-level physical net.
proc ::hls_spacetime_export::canonical_net {net} {
    set roots [get_nets -segments -top_net_of_hierarchical_group $net]
    if {[llength $roots] != 1} {error "ambiguous canonical net: $net"}
    return [lindex $roots 0]
}

# Preserve all hierarchy aliases, then visit each complete physical net once.
proc ::hls_spacetime_export::canonical_nets {} {
    variable alias_index
    variable canonical_index
    set started [stage_start net_aliases]
    set count 0
    foreach net [get_nets -hier] {
        budget
        set root_object [canonical_net $net]
        set name [get_property NAME $net]
        set root [get_property NAME $root_object]
        line aliases.tsv [list $name $root]
        set canonical_index($root) $root_object
        set alias_index($name) $root
        incr count
        progress net_aliases $count $started
    }
    stage_finish net_aliases $started {aliases.tsv}
}

# The same net owns all leaf pins and top ports, including control/constant nets.
proc ::hls_spacetime_export::connectivity {name object} {
    variable cell_index
    set pins [get_pins -leaf -of_objects $object]
    set columns [common_columns {NAME PARENT_CELL REF_PIN_NAME DIRECTION} $pins]
    foreach pin $pins actual [dict get $columns NAME] cell [dict get $columns PARENT_CELL] \
            ref [dict get $columns REF_PIN_NAME] direction [dict get $columns DIRECTION] {
        if {![info exists cell_index($cell)]} {error "pin outside leaf catalogue: $pin"}
        line pins.tsv [list $name $actual $cell $ref $direction]
    }
    foreach port [get_ports -of_objects $object] {
        line ports.tsv [list $name [get_property NAME $port] [get_property DIRECTION $port]]
    }
}

# Query only preregistered reference nets; native strings retain the default intra-site-inclusive basis.
proc ::hls_spacetime_export::net_timing {name object} {
    variable state
    variable alias_index
    if {[catch {get_net_delays -of_objects $object} delays]} {
        dict incr state timing_query_errors
        issue net_delays $name $delays
        return error
    }
    if {[llength $delays] == 0} {return empty}
    array set identities {}
    foreach delay $delays {
        set native [property_values $delay]
        set id $delay
        if {[dict exists $native NAME]} {set id [dict get $native NAME]}
        if {[info exists identities($id)]} {error "duplicate native delay identity: $name $id"}
        set identities($id) 1
        if {![dict exists $native NET] || ![info exists alias_index([dict get $native NET])] ||
            $alias_index([dict get $native NET]) ne $name} {
            error "native delay NET mismatch: $name $id"
        }
        set values {}
        foreach property {FAST_MIN FAST_MAX SLOW_MIN SLOW_MAX} {
            if {![dict exists $native $property]} {error "missing native delay property: $name $id $property"}
            set value [dict get $native $property]
            if {$value ne "" && ![string is double -strict $value]} {error "invalid native delay: $name $id $property"}
            lappend values $value
        }
        line net-delays.tsv [concat [list $name $id] $values]
        property_row delay-properties.tsv [list $name $id] $native delay_property_pairs
        dict incr state net_delay_objects
    }
    return available
}

# Finalize complete connectivity before querying timing; missing timing never hides topology.
proc ::hls_spacetime_export::nets {} {
    variable state
    variable canonical_index
    variable alias_index
    canonical_nets
    set started [stage_start net_connectivity]
    set count 0
    foreach name [array names canonical_index] {
        set object $canonical_index($name)
        budget
        connectivity $name $object
        incr count
        progress net_connectivity $count $started
    }
    stage_finish net_connectivity $started {pins.tsv ports.tsv}
    set sampled [dict create]
    foreach requested [dict get $state sample_nets] {
        if {![info exists alias_index($requested)]} {error "sample net absent: $requested"}
        set name $alias_index($requested)
        if {[dict exists $sampled $name]} {error "sample nets share canonical identity: $name"}
        dict set sampled $name 1
    }
    issue timing_population SDF "Full STA timing is supplied by the two exact-checkpoint SDF sidecars; per-net queries are limited to the explicitly sampled reference nets"
    set started [stage_start net_delays]
    set count 0
    foreach name [array names canonical_index] {
        set object $canonical_index($name)
        budget
        set timing not_queried
        if {[dict exists $sampled $name]} {set timing [net_timing $name $object]}
        line nets.tsv [list $name [get_property ROUTE_STATUS $object] [get_property TYPE $object] [get_property FLAT_PIN_COUNT $object] $timing]
        incr count
        progress net_delays $count $started
    }
    stage_finish net_delays $started {nets.tsv net-delays.tsv delay-properties.tsv}
}

# Keep path membership and complete reports; membership alone is not a sensitized arc.
proc ::hls_spacetime_export::paths {} {
    variable state
    variable cell_index
    variable bytes
    foreach mode {max min} {
        set started [stage_start timing_$mode]
        set paths [get_timing_paths -delay_type $mode -max_paths [dict get $state limits max_paths] -nworst 1 -no_report_unconstrained]
        set index 0
        foreach path $paths {
            set id "$mode/$index"
            incr index
            set values [list $id $mode]
            foreach property {STARTPOINT_PIN ENDPOINT_PIN STARTPOINT_CLOCK ENDPOINT_CLOCK SLACK DATAPATH_DELAY REQUIREMENT LOGIC_LEVELS} {
                lappend values [get_property $property $path]
            }
            line paths.tsv $values
            properties path-properties.tsv [list $id] $path
            foreach cell [get_cells -of_objects $path] {
                set name [get_property NAME $cell]
                if {[info exists cell_index($name)]} {
                    line path-members.tsv [list $id cell $name]
                } elseif {[get_property IS_PRIMITIVE $cell] || [get_property IS_BLACKBOX $cell]} {
                    error "path primitive outside leaf catalogue: $name"
                } else {
                    issue path_cell $name "Nonprimitive hierarchy member of $id; retained in full report"
                }
            }
            set path_nets [dict create]
            foreach net [get_nets -of_objects $path] {
                dict set path_nets [get_property NAME [canonical_net $net]] 1
            }
            foreach name [dict keys $path_nets] {line path-members.tsv [list $id net $name]}
            foreach pin [get_pins -of_objects $path] {line path-members.tsv [list $id pin [get_property NAME $pin]]}
        }
        set report "timing-$mode.rpt"
        set filename [file join [dict get $state output] $report]
        if {[llength $paths]} {
            report_timing -of_objects $paths -path_type full_clock_expanded -input_pins -file $filename
        } else {
            set channel [open $filename {WRONLY CREAT EXCL}]
            puts $channel "No constrained timing paths returned for $mode."
            close $channel
        }
        set size [file size $filename]
        dict set state reports $report $size
        incr bytes $size
        budget
        if {$mode eq "min"} {
            stage_finish timing_$mode $started {paths.tsv path-properties.tsv path-members.tsv}
        } else {
            stage_finish timing_$mode $started
        }
    }
}

# A completed table closes once, with a measured on-disk byte count.
proc ::hls_spacetime_export::close_table {name} {
    variable state
    set entry [dict get $state tables $name]
    if {![dict exists $entry channel]} {return}
    close [dict get $entry channel]
    dict unset entry channel
    dict set state tables $name $entry
    set bytes [file size [file join [dict get $state output] $name]]
    if {$bytes != [dict get $entry bytes]} {error "encoded byte mismatch: $name"}
}

# Close remaining handles; already-finalized phase tables keep their completion state.
proc ::hls_spacetime_export::close_tables {} {
    variable state
    foreach name [dict keys [dict get $state tables]] {close_table $name}
}

# Hash the bytes on disk both before opening and after reading the checkpoint.
proc ::hls_spacetime_export::checkpoint_hash {checkpoint} {
    set hash [lindex [exec sha256sum -- $checkpoint] 0]
    if {![regexp {^[0-9a-f]{64}$} $hash]} {error "invalid checkpoint digest"}
    return $hash
}

# Files come from one verified whole-design STA SDF capture of the exact checkpoint.
proc ::hls_spacetime_export::timing_inputs {checkpoint_sha inputs} {
    variable state
    variable bytes
    if {![dict exists $inputs checkpoint_sha] || [dict get $inputs checkpoint_sha] ne $checkpoint_sha ||
        ![dict exists $inputs mode] || [dict get $inputs mode] ne "sta"} {
        error "SDF input checkpoint/mode mismatch"
    }
    if {![dict exists $inputs sample_nets] || [llength [dict get $inputs sample_nets]] > 9} {
        error "SDF reference-net sample ceiling"
    }
    dict set state sample_nets [dict get $inputs sample_nets]
    set started [stage_start timing_inputs]
    foreach corner {fast slow} {
        if {![dict exists $inputs $corner path] || ![dict exists $inputs $corner sha256]} {
            error "missing SDF input: $corner"
        }
        set source [dict get $inputs $corner path]
        set expected [dict get $inputs $corner sha256]
        if {![regexp {^[0-9a-f]{64}$} $expected] || ![file isfile $source]} {error "invalid SDF input: $corner"}
        if {[checkpoint_hash $source] ne $expected} {error "SDF input digest mismatch: $corner"}
        set size [file size $source]
        if {$size <= 0} {error "empty SDF input: $corner"}
        incr bytes $size
        budget
        set name "timing-$corner.sdf"
        set destination [file join [dict get $state output] $name]
        if {[file exists $destination]} {error "SDF output already exists: $corner"}
        file copy -- $source $destination
        if {[file size $destination] != $size || [checkpoint_hash $destination] ne $expected} {
            error "copied SDF identity mismatch: $corner"
        }
        dict set state sdf $corner [dict create file $name bytes $size sha256 $expected mode sta process_corner $corner]
    }
    stage_finish timing_inputs $started
}

# Build IDs are supplied by the registered run; the checkpoint hash is measured here.
proc ::hls_spacetime_export::manifest {checkpoint build} {
    variable state
    variable records
    variable bytes
    set hash [checkpoint_hash $checkpoint]
    if {$hash ne [dict get $state checkpoint_sha]} {error "checkpoint changed during export"}
    set build_fields {}
    dict for {key value} $build {lappend build_fields "[quote $key]:[quote $value]"}
    set tables {}
    dict for {name entry} [dict get $state tables] {
        lappend tables "[quote $name]:\{\"rows\":[dict get $entry rows],\"bytes\":[dict get $entry bytes]\}"
    }
    set reports {}
    dict for {name size} [dict get $state reports] {lappend reports "[quote $name]:\{\"bytes\":$size\}"}
    set sdf {}
    dict for {corner entry} [dict get $state sdf] {
        set fields {}
        foreach key {file sha256 mode process_corner} {lappend fields "[quote $key]:[quote [dict get $entry $key]]"}
        lappend fields "\"bytes\":[dict get $entry bytes]"
        lappend sdf "[quote $corner]:\{[join $fields ,]\}"
    }
    set limits {}
    dict for {key value} [dict get $state limits] {lappend limits "[quote $key]:$value"}
    set counts {}
    foreach {label table} {cells cells.tsv nets nets.tsv pins pins.tsv ports ports.tsv} {
        lappend counts "[quote $label]:[dict get $state tables $table rows]"
    }
    foreach key {unplaced_cells net_delay_objects timing_query_errors cell_property_pairs delay_property_pairs} {
        lappend counts "[quote $key]:[dict get $state $key]"
    }
    set sampled_nets {}
    foreach name [dict get $state sample_nets] {lappend sampled_nets [quote $name]}
    set result "\{\"format\":\"spacetime_physical_export\",\"schema\":1,\"complete\":true,\"net_delay_basis\":\"including_intrasite\",\"net_delay_scope\":\"sampled\",\"sampled_nets\":\[[join $sampled_nets ,]\],\"sdf\":\{[join $sdf ,]\},\"build\":\{[join $build_fields ,]\},\"checkpoint\":\{\"sha256\":[quote $hash],\"file\":[quote $checkpoint]\},\"tool\":[quote [version -short]],\"part\":[quote [get_property PART [current_design]]],\"tables\":\{[join $tables ,]\},\"reports\":\{[join $reports ,]\},\"limits\":\{[join $limits ,]\},\"records\":$records,\"bytes\":$bytes,\"counts\":\{[join $counts ,]\},\"seconds\":[expr {([clock milliseconds]-[dict get $state started])/1000.0}]\}"
    if {[string bytelength $result] > 32767} {error "manifest byte limit"}
    set channel [open [file join [dict get $state output] manifest.json] {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel $result
    close $channel
}

# Open the exact checkpoint and export once; failed prefixes never receive a complete manifest.
proc ::hls_spacetime_export::run {checkpoint output build {requested_limits {}} {timing_inputs {}} {location_inputs {}}} {
    variable state
    variable deadline_ms
    variable record_limit
    variable byte_limit
    variable records
    variable bytes
    variable cell_index
    variable placement_index
    variable alias_index
    variable canonical_index
    foreach key {source rtl observation implementation} {
        if {![dict exists $build $key] || ![regexp {^[0-9a-f]{64}$} [dict get $build $key]]} {
            error "missing/invalid registered build digest: $key"
        }
    }
    if {$timing_inputs eq ""} {error "verified whole-design SDF inputs required"}
    if {[file exists $output]} {error "export output already exists: $output"}
    set checked_limits [limits $requested_limits]
    file mkdir $output
    set state [dict create output $output limits $checked_limits started [clock milliseconds] metadata_bytes 0 tables {} reports {} sdf {} sample_nets {} unavailable_properties {} unplaced_cells 0 net_delay_objects 0 timing_query_errors 0 cell_property_pairs 0 delay_property_pairs 0]
    set deadline_ms [expr {[dict get $state started]+1000*[dict get $checked_limits seconds]}]
    set record_limit [dict get $checked_limits records]
    set byte_limit [dict get $checked_limits bytes]
    set records 0
    set bytes 0
    foreach index {cell_index placement_index alias_index canonical_index} {
        array unset $index
        array set $index {}
    }
    if {[catch {
        dict set state checkpoint_sha [checkpoint_hash $checkpoint]
        if {$location_inputs ne ""} {
            if {![dict exists $location_inputs checkpoint_sha] ||
                [dict get $location_inputs checkpoint_sha] ne [dict get $state checkpoint_sha] ||
                ![dict exists $location_inputs build]} {error "location input checkpoint/build binding"}
            foreach key {source rtl observation implementation} {
                if {![dict exists $location_inputs build $key] ||
                    [dict get $location_inputs build $key] ne [dict get $build $key]} {
                    error "location input build mismatch: $key"
                }
            }
        }
        timing_inputs [dict get $state checkpoint_sha] $timing_inputs
        set_param general.maxThreads 2
        set started [stage_start checkpoint_open]
        open_checkpoint $checkpoint
        stage_finish checkpoint_open $started
        table cell-properties.tsv {cell properties}
        table nets.tsv {name route_status type flat_pin_count timing_status}
        table aliases.tsv {name canonical}
        table pins.tsv {net pin cell ref_pin direction}
        table ports.tsv {net port direction}
        table net-delays.tsv {net delay fast_min_ps fast_max_ps slow_min_ps slow_max_ps}
        table delay-properties.tsv {net delay properties}
        table paths.tsv {id delay_type startpoint endpoint start_clock end_clock slack_ns datapath_ns requirement_ns logic_levels}
        table path-properties.tsv {path property value}
        table path-members.tsv {path kind name}
        table issues.tsv {stage object reason}
        cells $location_inputs
        nets
        paths
        close_tables
        budget
        manifest $checkpoint $build
    } message options]} {
        catch {close_tables}
        set channel [open [file join $output incomplete.json] {WRONLY CREAT EXCL}]
        fconfigure $channel -encoding utf-8 -translation lf
        puts $channel "\{\"complete\":false,\"reason\":[quote $message],\"records\":$records,\"bytes\":$bytes\}"
        close $channel
        return -options $options $message
    }
    puts "SPACETIME_PHYSICAL_EXPORT_COMPLETE $output"
}
