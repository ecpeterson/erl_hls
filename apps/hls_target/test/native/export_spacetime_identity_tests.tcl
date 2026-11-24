# Synthetic identity preflight for the native physical exporter. No checkpoint
# or vendor API is opened; this checks only the four-component build boundary.
# Usage: tclsh test/native/export_spacetime_identity_tests.tcl FRESH_OUTPUT_PARENT
source [file join [file dirname [info script]] ../../priv/tools/export_spacetime.tcl]
if {[llength $argv] != 1 || [file exists [lindex $argv 0]]} {
    error "fresh output parent required"
}
set output [lindex $argv 0]
set digest [string repeat a 64]
set build [dict create source $digest rtl $digest observation $digest implementation $digest]
set timing [dict create fixture true]

set incomplete [dict remove $build implementation]
if {![catch {
    ::hls_spacetime_export::run mock.dcp [file join $output missing] $incomplete {} $timing
} reason] || $reason ne "missing/invalid registered build digest: implementation"} {
    error "missing implementation was not rejected: $reason"
}
if {[file exists $output]} {error "invalid preflight created output"}

rename ::hls_spacetime_export::checkpoint_hash ::hls_spacetime_export::native_checkpoint_hash
proc ::hls_spacetime_export::checkpoint_hash {path} {return $::digest}
set location [dict create checkpoint_sha $digest build \
    [dict replace $build implementation [string repeat b 64]]]
if {![catch {
    ::hls_spacetime_export::run mock.dcp [file join $output mismatch] $build {} $timing $location
} reason] || $reason ne "location input build mismatch: implementation"} {
    error "implementation mismatch was not rejected: $reason"
}
if {![file exists [file join $output mismatch incomplete.json]] ||
    [file exists [file join $output mismatch manifest.json]]} {
    error "implementation mismatch publication state"
}
puts "spacetime exporter identity fixture passed"
