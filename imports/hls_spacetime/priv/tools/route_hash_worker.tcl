# Optional hash transport only. Native geometry and endpoint helpers are unchanged.
# Source after export_routes.tcl; the driver explicitly owns worker start/close.
namespace eval ::hls_spacetime_routes {
    variable hash_channel ""
    variable hash_request 0
}

# COMMAND is a trusted argument list, not a shell program. The worker inherits
# the guarded process group; failed startup is exposed on the first request.
proc ::hls_spacetime_routes::start_hash_worker {command} {
    variable hash_channel
    variable hash_request
    if {$hash_channel ne "" || [llength $command] == 0} {error "hash worker already active or empty command"}
    # Forward startup failures immediately; close errors may be caught by cleanup.
    set channel [open [concat [linsert $command 0 |] {2>@ stderr}] r+]
    fconfigure $channel -encoding ascii -translation lf -buffering line
    set hash_channel $channel
    set hash_request 0
}

# Closing the bidirectional pipe delivers EOF and waits for its child's status.
# A failed close is an export failure; the outer guard owns a blocked child.
proc ::hls_spacetime_routes::stop_hash_worker {} {
    variable hash_channel
    if {$hash_channel eq ""} {return}
    set channel $hash_channel
    set hash_channel ""
    close $channel
}

# The fallback has exactly the existing per-file hash behavior. A started worker
# returns each digest only after rereading the actual file; errors never fall back.
proc ::hls_spacetime_routes::hash {path} {
    variable hash_channel
    variable hash_request
    if {$hash_channel eq ""} {
        set digest [lindex [exec sha256sum -- $path] 0]
    } else {
        set bytes [encoding convertto utf-8 $path]
        if {[file pathtype $path] ne "absolute" || [string length $bytes] > 4096 ||
            [regexp {[\x00-\x1f\x7f]} $path]} {error "invalid hash worker path"}
        binary scan $bytes H* encoded
        set request [incr hash_request]
        puts $hash_channel "$request\t$encoded"
        flush $hash_channel
        if {[gets $hash_channel response] < 0 || [string length $response] > 86} {
            error "hash worker closed without a valid response"
        }
        set fields [split $response "\t"]
        if {[llength $fields] != 2 || [lindex $fields 0] ne "$request"} {
            error "invalid hash worker response identity"
        }
        set digest [lindex $fields 1]
    }
    if {![regexp {^[0-9a-f]{64}$} $digest]} {error "invalid file digest: $path"}
    return $digest
}
