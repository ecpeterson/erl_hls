# Opt-in full-board constraint profile for te0715_domain_link_top on TE0715.
# Required: an unconstrained synthesized xc7z030sbg485-1 design and an existing
# artifact directory in $output. Do not source on a previously constrained DCP.
# Usage after full-board synth_design (ROLE is supplied by the caller):
#   source /path/to/domain_board_profile.tcl
#   board_check_clocks synthesis $output
# After routing, call board_check_clocks routed $output as well.
# The caller owns RTL closure, implementation settings, guards and admission.
# Unknown CDC entries remain timed and block admission, not diagnostic reporting;
# inspect cdc-unresolved.tsv and tx_length_bounded/rx_length_bounded explicitly.
# This profile never runs implementation, emits a bitstream or programs a board.
# Existing probe/OOC profiles and their default behavior remain independent.
#
# Evidence boundary: the accepted campaign implemented the frozen v4 clocks/CDC
# declarations, then added RAMD32/WE TX bounds to the saved routed checkpoint.
# This source profile combines those measured declarations but has not driven a
# fresh native implementation. A future build need not reproduce placement or
# bitstream bytes and must perform its own complete constraint/timing review.
if {![info exists output] || ![file isdirectory $output]} {
    error "full-board profile requires an existing output directory"
}
if {[get_property PART [current_design]] ne "xc7z030sbg485-1" ||
        [get_property TOP [current_design]] ne "te0715_domain_link_top"} {
    error "full-board profile requires the TE0715 domain-link top and part"
}
set board_profile_directory [file dirname [file normalize [info script]]]
source [file join $board_profile_directory domain_board_constraints.tcl]
source [file join $board_profile_directory domain_board_cdc.tcl]
source [file join $board_profile_directory domain_board_checks.tcl]
unset board_profile_directory
