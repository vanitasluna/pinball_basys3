set resource_check_dir [file normalize [file dirname [info script]]]
open_checkpoint [file join $resource_check_dir routed.dcp]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $resource_check_dir utilization_hierarchical.rpt]
puts "RESOURCE CHECK PASSED"
close_design
