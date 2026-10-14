set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root FDP2026.xpr]
if {[get_property PART [current_project]] ne "xc7a35tcpg236-1"} {error "Wrong FPGA part"}
if {[get_property TOP [get_filesets sources_1]] ne "My_Top_Module"} {error "Wrong design top"}
if {[get_property TOP [get_filesets sim_1]] ne "tb_top"} {error "Wrong simulation top"}
set timing_file [get_files *Pinball_Physics_Timing.xdc]
if {[llength $timing_file] != 1 || [get_property USED_IN_SYNTHESIS $timing_file]} {
    error "Physics timing constraints must be implementation only"
}
if {![get_property USED_IN_IMPLEMENTATION $timing_file]} {error "Missing implementation constraints"}
set_property -name xsim.elaborate.xelab.more_options -value {--timescale 1ns/1ps} -objects [get_filesets sim_1]
set_property xsim.simulate.runtime {100us} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "PROJECT VERIFIED: design top, part, implementation-only timing, simulation top and timescale"
close_project
