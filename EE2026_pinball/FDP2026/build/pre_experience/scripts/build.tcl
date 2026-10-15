# Run from any working directory: vivado -mode batch -source scripts/build.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build]
file mkdir $out
set_param general.maxThreads 4
create_project -in_memory -part xc7a35tcpg236-1
read_vhdl [file join $root FDP2026.srcs sources_1 new Ps2Interface.vhd]
read_vhdl [file join $root FDP2026.srcs sources_1 new Mouse_Control.vhd]
read_verilog [glob [file join $root FDP2026.srcs sources_1 new *.v]]
read_xdc [file join $root FDP2026.srcs constrs_1 new Basys3_Master.xdc]
synth_design -top My_Top_Module -part xc7a35tcpg236-1
# Verify physical OLED placement, not just the top-level bus name.
set oled_package_pins {K17 M18 N17 P18 L17 M19 P17 R18}
for {set i 0} {$i < 8} {incr i} {
    set oled_port [get_ports [format {JC[%d]} $i]]
    if {[llength $oled_port] != 1 || [get_property PACKAGE_PIN $oled_port] ne [lindex $oled_package_pins $i]} {
        error "Incorrect JC OLED pin mapping at bit $i"
    }
}
if {[llength [get_ports -quiet JA*]]} {error "Unexpected JA output in JC design"}
read_xdc [file join $root FDP2026.srcs constrs_1 new Pinball_Physics_Timing.xdc]
set snapshot_regs [get_cells -hierarchical -filter {REF_NAME =~ FD* && NAME =~ physics/collision_*_reg* && NAME !~ physics/collision_busy_reg* && NAME !~ physics/collision_wait_reg*}]
if {[llength $snapshot_regs] < 50} {
    error "Isolated collision snapshot registers missing; check the 16-cycle timing contract"
}
write_checkpoint -force [file join $out synthesized.dcp]
report_utilization -file [file join $out utilization_synth.rpt]
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
report_io -file [file join $out io.rpt]
report_clock_interaction -file [file join $out clocks.rpt]
report_exceptions -file [file join $out exceptions.rpt]
write_checkpoint -force [file join $out routed.dcp]
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_paths] && [get_property SLACK $setup_paths] < 0} {
    error "Setup timing failed; inspect build/timing.rpt"
}
if {[llength $hold_paths] && [get_property SLACK $hold_paths] < 0} {
    error "Hold timing failed; inspect build/timing.rpt"
}
write_bitstream -force [file join $out pinball_basys3.bit]
puts "BUILD PASSED: [file join $out pinball_basys3.bit]"
