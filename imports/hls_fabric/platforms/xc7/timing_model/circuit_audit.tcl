# Export logical pins and parameters, checking them against the native mapping.
namespace eval xc7_timing {
    variable checker [file join [file dirname [file normalize [info script]]] connectivity.py]

    # Audit a linked or routed design; any changed primitive behavior or net fails.
    proc audit {mapped output {prefix ""}} {
        # Bulk property reads avoid quadratic per-cell metadata overhead on wide probes.
        set cells [get_cells -hier -filter {IS_PRIMITIVE}]
        set pins [get_pins -of_objects $cells]
        array set cell_types {}
        foreach name [get_property NAME $cells] ref [get_property REF_NAME $cells] {
            set cell_types($name) $ref
        }
        array set pin_nets {}
        array set port_nets {}
        set nets [get_nets -hier]
        foreach net $nets netname [get_property NAME $nets] {
            set members [get_pins -quiet -of_objects $net]
            if {[llength $members]} {
                foreach pinname [get_property NAME $members] {set pin_nets($pinname) $netname}
            }
            set members [get_ports -quiet -of_objects $net]
            if {[llength $members]} {
                foreach portname [get_property NAME $members] {set port_nets($portname) $netname}
            }
        }
        set stream [open [file join $output ${prefix}connectivity.tsv] w]
        # Primitive pin names end in /REF_PIN_NAME. Avoid repeated parent-object
        # resolution for every pin; validate every derived parent against the cell map.
        foreach name [get_property NAME $pins] {
            set split [string last / $name]
            if {$split < 0} {error "primitive pin lacks parent: $name"}
            set cell [string range $name 0 [expr {$split - 1}]]
            set pin [string range $name [expr {$split + 1}] end]
            set ref $cell_types($cell)
            set netname ""
            if {[info exists pin_nets($name)]} {set netname $pin_nets($name)}
            puts $stream "$cell\t$ref\t$pin\t$netname"
        }
        foreach name [get_property NAME [get_ports]] {
            set netname ""
            if {[info exists port_nets($name)]} {set netname $port_nets($name)}
            puts $stream "@top\tPORT\t$name\t$netname"
        }
        close $stream
        variable checker
        set parameters [exec env -u PYTHONHOME -u PYTHONPATH /usr/bin/python3 $checker --list-parameters $mapped]
        set stream [open [file join $output ${prefix}parameters.tsv] w]
        foreach ref [lsort -unique [get_property REF_NAME $cells]] {
            set group [filter $cells "REF_NAME == $ref"]
            set properties [list_property [lindex $group 0]]
            set names [get_property NAME $group]
            foreach parameter $parameters {
                if {[lsearch -exact $properties $parameter] >= 0} {
                    foreach name $names value [get_property $parameter $group] {
                        puts $stream "$name\t$parameter\t$value"
                    }
                }
            }
        }
        close $stream
        set audit [exec env -u PYTHONHOME -u PYTHONPATH /usr/bin/python3 $checker $mapped [file join $output ${prefix}connectivity.tsv] [file join $output ${prefix}parameters.tsv]]
        set stream [open [file join $output ${prefix}audit.json] w]
        puts $stream $audit
        close $stream
        return $audit
    }
}
