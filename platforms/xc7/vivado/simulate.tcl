# Run the owned lane against installed vendor primitives; no hardware access.
set root [file dirname [file normalize [info script]]]
set packets [expr {[llength $argv] && [lindex $argv 0] eq "ethernet"}]
set name [expr {$packets ? "ethernet-simulation" : "gtx-simulation"}]
set output [file join $root results $name]
file mkdir $output
if {$packets} {
    # Use the synthesized MAC/PCS with the vendor primitives. XSim 2024.2 can
    # spin in the generated procedural ready/valid network at first admission;
    # structural combinational cells also match the circuit being implemented.
    create_project -in_memory -part xc7z030sbg485-1
    cd [file join $root inputs generated-sim]
    read_verilog liteeth_packet_core.v
    synth_design -top liteeth_packet_core -mode out_of_context -flatten_hierarchy rebuilt
    write_verilog -force -mode funcsim [file join $output packet-core.v]
    close_project
}
create_project -force gtx_sim [file join $output project] -part xc7z030sbg485-1
if {$packets} {
    add_files [file join $output packet-core.v]
    add_files [file join $root inputs generated-sim liteeth_pcs_gearbox.v]
    add_files [glob [file join $root inputs ethernet *.v]]
    add_files [file join $root inputs gtx te0715_gtx_channel.v]
    add_files [file join $root inputs gtx gtx_probe_control.v]
    add_files [file join $root inputs zynq_ps_probe.v]
    add_files -fileset sim_1 [file join $root inputs ethernet_serial_tb.sv]
    set_property top ethernet_serial_tb [get_filesets sim_1]
} else {
    add_files [file join $root inputs gtx te0715_gtx_channel.v]
    add_files -fileset sim_1 [file join $root inputs gtx_tb.sv]
    set_property top gtx_tb [get_filesets sim_1]
}
set_property xsim.simulate.runtime all [get_filesets sim_1]
launch_simulation
close_sim
# XSim can return successfully after an HDL assertion. Require the terminal
# testbench marker, not merely a successful simulator process exit.
set stream [open [file join $output project gtx_sim.sim sim_1 behav xsim simulate.log] r]
set transcript [read $stream]
close $stream
set marker [expr {$packets ? "PASS: complete MAC/PCS/gearbox/GTX/MMCM frame loopback and restart" :
                            "PASS: vendor GTX lock, reset, 62.5-MHz RX, clean PRBS and injected error"}]
if {[string first $marker $transcript] < 0 || [string first "Fatal:" $transcript] >= 0} {
    error "simulation did not complete: see $output"
}
puts "SIMULATION_COMPLETE $name"
