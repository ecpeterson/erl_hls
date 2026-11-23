# Synthesize and route unchanged portable RTL on a selected FPGA; never emit a bitstream.
# Usage: vivado -mode batch -source technology_compare.tcl -tclargs INPUT_DIR TOP CLOCK PART OUTPUT [PERIOD_NS] [synthesis|route] [MAX_THREADS]
set input [file normalize [lindex $argv 0]]
set top [lindex $argv 1]
set clock [lindex $argv 2]
set part [lindex $argv 3]
set output [file normalize [lindex $argv 4]]
set period [expr {[llength $argv] > 5 ? [lindex $argv 5] : 5.0}]
set stop_after [expr {[llength $argv] > 6 ? [lindex $argv 6] : "route"}]
if {$stop_after ni {synthesis route}} {error "invalid measurement stage"}
if {![string is double -strict $period] || $period <= 0} {error "invalid period"}
set max_threads [expr {[llength $argv] > 7 ? [lindex $argv 7] : 2}]
if {![string is integer -strict $max_threads] || $max_threads < 1 || $max_threads > 8} {
    error "max_threads must be an integer from 1 through 8"
}
file mkdir $output
set_param general.maxThreads $max_threads
puts "TECHNOLOGY_MAX_THREADS=[get_param general.maxThreads]"
create_project -in_memory -part $part
foreach source [lsort [glob [file join $input *.v]]] {read_verilog -sv $source}
set constraints [file join $output workload.xdc]
set stream [open $constraints w]
puts $stream "create_clock -name workload -period $period \[get_ports $clock\]"
close $stream
read_xdc $constraints
synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt
# Only external paths are excluded. State, RAM, DSP and register control arcs stay timed.
set inputs [get_ports -quiet -filter "DIRECTION == IN && NAME != $clock"]
if {[llength $inputs]} {set_false_path -from $inputs}
set outputs [get_ports -quiet -filter {DIRECTION == OUT}]
if {[llength $outputs]} {set_false_path -to $outputs}
report_utilization -hierarchical -file [file join $output synthesis-utilization.rpt]
report_utilization -file [file join $output synthesis-capacity.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output synthesis-timing.rpt]
report_timing -max_paths 20 -path_type full_clock_expanded -file [file join $output synthesis-paths.rpt]
write_checkpoint -force [file join $output synthesized.dcp]
if {$stop_after eq "synthesis"} {
    set stream [open [file join $output version.txt] w]
    puts $stream [version]
    puts $stream "part=$part top=$top clock=$clock period=$period stage=synthesis max_threads=$max_threads"
    close $stream
    puts "TECHNOLOGY_SYNTHESIS_COMPLETE"
    exit 0
}
opt_design
place_design -directive Default
phys_opt_design -directive Default
route_design -directive Default
write_checkpoint -force [file join $output routed.dcp]
report_utilization -hierarchical -file [file join $output utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $output timing.rpt]
report_timing -max_paths 50 -path_type full_clock_expanded -file [file join $output paths.rpt]
report_timing -delay_type min -max_paths 10 -file [file join $output hold.rpt]
report_route_status -file [file join $output route.rpt]
check_timing -verbose -file [file join $output coverage.rpt]
report_drc -file [file join $output drc.rpt]
set hard [get_cells -quiet -hier -filter {REF_NAME =~ RAMB* || REF_NAME =~ DSP* || REF_NAME =~ SRL*}]
if {[llength $hard]} {report_pulse_width -cells $hard -limit 10000 -file [file join $output hard-clock.rpt]}
set ram [get_cells -quiet -hier -filter {REF_NAME =~ RAMB*}]
set dsp [get_cells -quiet -hier -filter {REF_NAME =~ DSP*}]
set ff [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]
set controls [get_pins -quiet -of_objects $ff -filter {REF_PIN_NAME == CE || REF_PIN_NAME == R || REF_PIN_NAME == S}]
foreach {name cells direction} [list ram $ram -from dsp $dsp -through control $controls -to] {
    if {[llength $cells]} {report_timing $direction $cells -max_paths 10 -path_type full_clock_expanded -file [file join $output "paths-$name.rpt"]}
}
set stream [open [file join $output version.txt] w]
puts $stream [version]
puts $stream "part=$part top=$top clock=$clock period=$period stage=route max_threads=$max_threads"
close $stream
puts "TECHNOLOGY_COMPARE_COMPLETE"
