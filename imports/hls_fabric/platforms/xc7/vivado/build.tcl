# Implement one probe and retain analysis artifacts. This never programs hardware.
# Usage: vivado -mode batch -source build.tcl -tclargs PROFILE
set root [file dirname [file normalize [info script]]]
set profile [lindex $argv 0]
set workload_period [expr {[llength $argv] > 1 ? [lindex $argv 1] : 10.0}]
if {![string is double -strict $workload_period] || $workload_period <= 0} {error "invalid period"}
if {$profile ni {register dma prbs ethernet-loopback ethernet-external phi micro}} {
    error "unknown profile: $profile"
}
set output [file join $root results $profile]
if {[llength $argv] > 1} {set output [file join $root results "$profile-${workload_period}ns"]}
file mkdir $output
file delete -force [file join $output candidate.bit]
file copy -force [file join $root manifest.json] [file join $output input-manifest.json]
set_param general.maxThreads 4
create_project -in_memory -part xc7z030sbg485-1
set_property target_language Verilog [current_project]
cd [file join $root inputs generated]
set files [glob *.v]
lappend files ../zynq_ps_probe.v ../zynq_ps_probe_top.v
foreach pattern {../gtx/*.v ../ethernet/*.v ../dma/*.v} {
    lappend files {*}[glob $pattern]
}
if {$profile eq "phi"} {set files [glob ../phi/*.v]}
if {$profile eq "micro"} {set files [list ../micro.v]}
foreach file $files {read_verilog -sv $file}
set top [dict get {register zynq_ps_probe_top dma zynq_dma_top prbs te0715_gtx_top
                  ethernet-loopback te0715_ethernet_top ethernet-external te0715_ethernet_top
                  phi phi_timing_harness micro timing_micro} $profile]
set generics {}
if {$profile eq "ethernet-external"} {set generics {-generic EXTERNAL=1}}
synth_design -top $top -part xc7z030sbg485-1 -flatten_hierarchy rebuilt {*}$generics
source [file join $root constraints.tcl]
source [file join $root cdc.tcl]
write_checkpoint -force [file join $output synthesized.dcp]
report_utilization -hierarchical -file [file join $output synthesis-utilization.rpt]
check_timing -verbose -file [file join $output synthesis-check-timing.rpt]
report_cdc -details -file [file join $output synthesis-cdc.rpt]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $output routed.dcp]
write_verilog -force -mode timesim [file join $output routed.v]
write_sdf -force [file join $output routed.sdf]
write_xdc -force [file join $output effective.xdc]
report_utilization -hierarchical -file [file join $output utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $output timing.rpt]
report_timing -delay_type max -max_paths 100 -nworst 3 -path_type full_clock_expanded -file [file join $output setup-paths.rpt]
report_timing -delay_type min -max_paths 50 -path_type full_clock_expanded -file [file join $output hold-paths.rpt]
report_clocks -file [file join $output clocks.rpt]
report_clock_interaction -file [file join $output clock-interaction.rpt]
report_cdc -details -file [file join $output cdc.rpt]
report_drc -file [file join $output drc.rpt]
report_methodology -file [file join $output methodology.rpt]
report_route_status -file [file join $output route-status.rpt]
set hard_file [open [file join $output hard-primitives.rpt] w]
foreach cell [get_cells -hier -filter {REF_NAME =~ RAMB* || REF_NAME == DSP48E1 || REF_NAME == GTXE2_CHANNEL}] {
    puts $hard_file [report_property -all -return_string $cell]
}
close $hard_file
set version_file [open [file join $output version.txt] w]
puts $version_file [version]
close $version_file
# A timing harness has arbitrary I/O and must never become a board image.
if {$profile ni {phi micro}} {
    # Retain failed reports/checkpoints, but do not publish a mistimed candidate.
    set stream [open [file join $output timing.rpt] r]
    set summary [read $stream]
    close $stream
    if {![regexp {\n\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+([0-9]+)\s+([0-9]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+([0-9]+)\s+([0-9]+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+([0-9]+)\s+([0-9]+)\s*\n} $summary row wns tns setup_fail setup_total whs ths hold_fail hold_total wpws tpws pulse_fail pulse_total]} {
        error "missing timing summary"
    }
    if {$setup_fail || $hold_fail || $pulse_fail || $wns < 0 || $whs < 0 || $wpws < 0} {
        error "timing failed; no board candidate emitted"
    }
    foreach check {no_clock unconstrained_internal_endpoints no_input_delay no_output_delay generated_clocks loops} {
        if {![regexp "checking $check \\(0\\)" $summary]} {
            error "incomplete timing constraints: $check"
        }
    }
    set_property CFGBVS VCCO [current_design]
    set_property CONFIG_VOLTAGE 3.3 [current_design]
    write_bitstream -force [file join $output candidate.bit]
}
puts "BATCH_COMPLETE $profile"
