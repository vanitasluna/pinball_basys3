set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build routed.dcp]
foreach path [get_timing_paths -max_paths 100 -nworst 1 -slack_lesser_than 0] {
    puts "FAIL_PATH [get_property SLACK $path] [get_property STARTPOINT_PIN $path] -> [get_property ENDPOINT_PIN $path]"
}
report_timing -max_paths 50 -nworst 1 -slack_lesser_than 0 -file [file join $root build failing_paths.rpt]
