# Verify only the NEWLY rebuilt project, not the original Vivado project.
# vivado -mode batch -source skill/vivado-rebuild/scripts/verify_impl_generic.tcl -tclargs config.tcl ?repo_root?
source [file join [file dirname [info script]] common.tcl]

proc ::vrskill::assert_complete {run} {
    set r [get_runs $run]
    if {[llength $r] != 1} { ::vrskill::die "Run $run is missing" }
    set progress [get_property PROGRESS $r]
    set status [get_property STATUS $r]
    if {$progress ne "100%" || [string first "Complete" $status] < 0} {
        ::vrskill::die "Run $run not complete: $status ($progress)"
    }
}

proc ::vrskill::verify_impl {cfg_path repo_root} {
    set cfg [::vrskill::load_config $cfg_path $repo_root]
    ::vrskill::verify_version $cfg
    set root [dict get $cfg _root]
    set build [::vrskill::absolute_from_root $root [dict get $cfg build_rel]]
    set report [::vrskill::absolute_from_root $root [dict get $cfg report_rel]]
    set xpr [file join $build "[dict get $cfg name].xpr"]
    if {![file isfile $xpr]} { ::vrskill::die "Missing rebuilt XPR: $xpr" }
    if {[file exists [file join $report SUCCESS.txt]]} {
        ::vrskill::die "SUCCESS.txt already exists; refusing to overwrite verified evidence"
    }
    if {[llength [get_projects -quiet]]} { ::vrskill::die "Close previous project before batch verification" }
    open_project $xpr
    set top [get_property TOP [get_filesets sources_1]]
    set part [get_property PART [current_project]]
    if {$top ne [dict get $cfg top] || $part ne [dict get $cfg part]} {
        ::vrskill::die "Unexpected top or part in rebuilt project"
    }
    file mkdir $report
    ::vrskill::log "Launch synth_1 for $top"
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    ::vrskill::assert_complete synth_1

    ::vrskill::log "Launch impl_1 through write_bitstream"
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    ::vrskill::assert_complete impl_1
    open_run impl_1
    report_utilization -file [file join $report utilization.rpt]
    report_timing_summary -file [file join $report timing_summary.rpt]
    report_drc -file [file join $report drc.rpt]
    report_clocks -file [file join $report clocks.rpt]
    check_timing -verbose -file [file join $report check_timing.rpt]
    if {[llength [get_clocks -quiet]] == 0} { ::vrskill::die "No clocks: invalid timing sign-off" }
    set setup_paths [get_timing_paths -setup -max_paths 1]
    set hold_paths [get_timing_paths -hold -max_paths 1]
    if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {
        ::vrskill::die "No constrained setup/hold timing path; inspect check_timing.rpt"
    }
    set wns [get_property SLACK [lindex $setup_paths 0]]
    set whs [get_property SLACK [lindex $hold_paths 0]]
    if {$wns < 0.0 || $whs < 0.0} { ::vrskill::die "Timing FAILED: WNS=$wns WHS=$whs" }

    set bits [glob -nocomplain -directory [file join $build "[dict get $cfg name].runs" impl_1] *.bit]
    if {[llength $bits] != 1 || ![file isfile [lindex $bits 0]]} {
        ::vrskill::die "Expected exactly one Bitstream (.bit)"
    }
    set xsa [file join $build "[dict get $cfg name]_rebuilt.xsa"]
    write_hw_platform -fixed -include_bit -force $xsa
    if {![file isfile $xsa]} { ::vrskill::die "XSA export failed" }

    set handle [open [file join $report SUCCESS.txt] w]
    puts $handle "Result: PASS (Vivado build/timing only; NOT on-board functional validation)"
    puts $handle "Project: [dict get $cfg name]"
    puts $handle "Vivado: [version -short]"
    puts $handle "Part: $part"
    puts $handle "Top: $top"
    puts $handle "Synthesis: [get_property STATUS [get_runs synth_1]]"
    puts $handle "Implementation: [get_property STATUS [get_runs impl_1]]"
    puts $handle "Setup WNS (ns): $wns"
    puts $handle "Hold WHS (ns): $whs"
    puts $handle "Bitstream: [lindex $bits 0]"
    puts $handle "XSA: $xsa"
    puts $handle "Required separate sign-off: I/O constraints, DRC, CDC, hardware and Vitis application testing"
    close $handle
    close_project
    ::vrskill::log "PASS: $report/SUCCESS.txt"
}

if {![info exists ::vrskill_skip_autorun]} {
    if {![info exists ::argv] || [llength $::argv] < 1 || [llength $::argv] > 2} {
        error "Usage: vivado -mode batch -source verify_impl_generic.tcl -tclargs config.tcl ?repo_root?"
    }
    set root [expr {[llength $::argv] == 2 ? [lindex $::argv 1] : [pwd]}]
    ::vrskill::verify_impl [lindex $::argv 0] $root
}
