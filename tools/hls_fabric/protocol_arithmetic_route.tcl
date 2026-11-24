# Route one generated arithmetic network with a closed, single-threaded XC7 recipe.
# Usage: vivado -mode batch -source protocol_arithmetic_route.tcl -tclargs INPUT OUTPUT
if {[llength $argv] != 2} {error "expected INPUT and OUTPUT"}
set input [file normalize [lindex $argv 0]]
set output [file normalize [lindex $argv 1]]
set route_recipe [file normalize [info script]]
if {![file isdirectory $input]} {error "missing route input"}
if {[file exists $output]} {error "route output already exists"}
if {[file dirname $route_recipe] ne $input} {error "route recipe must be part of the frozen input"}

set part xc7z030sbg485-1
set top protocol_network
set clock clk
set period 10.0
set threads 1
set placement Default
set physical_optimization Default
set routing Default

file mkdir $output
file copy [file join $input identity.json] [file join $output input-identity.json]
file copy [file join $input core.v] [file join $output core.v]
file copy [file join $input protocol_network.sv] [file join $output protocol_network.sv]
file copy $route_recipe [file join $output protocol_arithmetic_route.tcl]
set_param general.maxThreads $threads
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
read_verilog [file join $output core.v]
read_verilog -sv [file join $output protocol_network.sv]

set constraints [file join $output workload.xdc]
set stream [open $constraints w]
puts $stream "create_clock -name workload -period $period \[get_ports $clock\]"
close $stream
read_xdc $constraints

synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt
# The witness times the synchronous implementation, not arbitrary external I/O delay.
set inputs [get_ports -quiet -filter "DIRECTION == IN && NAME != $clock"]
if {[llength $inputs]} {set_false_path -from $inputs}
set outputs [get_ports -quiet -filter {DIRECTION == OUT}]
if {[llength $outputs]} {set_false_path -to $outputs}
report_utilization -hierarchical -file [file join $output synthesis-utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output synthesis-timing.rpt]
write_checkpoint -force [file join $output synthesized.dcp]

opt_design
place_design -directive $placement
phys_opt_design -directive $physical_optimization
route_design -directive $routing
set incomplete_nets [get_nets -hierarchical -filter {ROUTE_STATUS == UNROUTED || ROUTE_STATUS == PARTIAL}]
if {[llength $incomplete_nets]} {error "route left incomplete nets: [llength $incomplete_nets]"}
set route_status "Route Complete"
write_checkpoint -force [file join $output routed.dcp]
report_utilization -hierarchical -file [file join $output utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -max_paths 20 -file [file join $output timing.rpt]
report_timing -max_paths 50 -path_type full_clock_expanded -file [file join $output paths.rpt]
report_route_status -file [file join $output route-status.rpt]
check_timing -verbose -file [file join $output coverage.rpt]
report_drc -file [file join $output drc.rpt]

set stream [open [file join $output recipe.txt] w]
puts $stream "tool=[version -short]"
puts $stream "part=$part"
puts $stream "top=$top"
puts $stream "clock=$clock"
puts $stream "period_ns=$period"
puts $stream "threads=[get_param general.maxThreads]"
puts $stream "synth_flatten=rebuilt"
puts $stream "place_directive=$placement"
puts $stream "phys_opt_directive=$physical_optimization"
puts $stream "route_directive=$routing"
puts $stream "external_io_false_paths=true"
puts $stream "route_status=$route_status"
close $stream
puts "PROTOCOL_ARITHMETIC_ROUTE_COMPLETE"
