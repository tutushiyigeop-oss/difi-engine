# DIFI: independent implementation check for an already rebuilt Vivado project.
# Vivado 2024.2; do not run from the original, known-good Vivado projects.
# Usage (from any working directory):
#   vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs packaged_ip
#   vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b5_raw_export
#   vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs b6_udp_rx
# This script never deletes/resets runs and never overwrites original projects.

namespace eval difi_verify {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
}

proc difi_verify::fail {reason} { error "DIFI IMPLEMENTATION: $reason" }
proc difi_verify::msg {message} { puts "\[DIFI IMPLEMENTATION\] $message" }

proc difi_verify::assert_run_pass {run_name} {
    set run [get_runs $run_name]
    if {[llength $run] != 1} { difi_verify::fail "Missing expected run $run_name" }
    set status [get_property STATUS $run]
    set progress [get_property PROGRESS $run]
    difi_verify::msg "$run_name status='$status' progress='$progress'"
    if {$progress ne "100%" || [string first "Complete" $status] < 0} {
        difi_verify::fail "$run_name did not complete successfully; inspect Vivado run logs"
    }
}

proc difi_verify::run {target} {
    variable root
    if {$target ni {packaged_ip b5_raw_export b6_udp_rx}} {
        difi_verify::fail "Choose packaged_ip, b5_raw_export, or b6_udp_rx"
    }
    if {[catch {version -short} ver]} { difi_verify::fail "Run inside Vivado 2024.2" }
    if {$ver ne "2024.2"} { difi_verify::fail "Expected Vivado 2024.2; got '$ver'" }

    set project_name "difi_rebuilt_$target"
    set project_dir [file join $root vivado rebuilt $target]
    set xpr [file join $project_dir "$project_name.xpr"]
    if {![file isfile $xpr]} {
        difi_verify::fail "Missing rebuilt XPR: $xpr; run rebuild_bd.tcl first"
    }
    if {[llength [get_projects -quiet]] > 0} {
        difi_verify::fail "Close any other project; this command runs in a fresh Vivado batch session"
    }

    set snapshot [file join $root scripts vivado generated $target manifest.tcl]
    if {![file isfile $snapshot]} { difi_verify::fail "Missing export manifest $snapshot" }
    catch {unset ::difi_manifest}
    source $snapshot
    if {![array exists ::difi_manifest]} { difi_verify::fail "Invalid manifest" }

    open_project $xpr
    set top [get_property TOP [get_filesets sources_1]]
    set part [get_property PART [current_project]]
    if {$top ne $::difi_manifest(original_top)} {
        difi_verify::fail "Unexpected top '$top', expected '$::difi_manifest(original_top)'"
    }
    if {$part ne $::difi_manifest(part)} {
        difi_verify::fail "Unexpected part '$part', expected '$::difi_manifest(part)'"
    }
    if {[llength [get_files -quiet *.bd]] == 0} { difi_verify::fail "No Block Design found" }
    difi_verify::msg "Target=$target; Vivado=$ver; part=$part; top=$top"

    # Do not overwrite an earlier finished reproducibility result by accident.
    set out [file join $root report results vivado_rebuild $target]
    if {[file exists [file join $out SUCCESS.txt]]} {
        difi_verify::fail "A prior successful report exists in $out; archive it before a new build"
    }
    file mkdir $out

    difi_verify::msg "Starting synthesis (freshly rebuilt project; jobs=4)"
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    difi_verify::assert_run_pass synth_1

    difi_verify::msg "Starting implementation through write_bitstream (jobs=4)"
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    difi_verify::assert_run_pass impl_1

    # Reports come from the newly routed implementation, NOT earlier archive runs.
    open_run impl_1
    report_utilization -file [file join $out utilization.rpt]
    report_timing_summary -file [file join $out timing_summary.rpt]
    report_drc -file [file join $out drc.rpt]
    report_clocks -file [file join $out clocks.rpt]

    set setup_paths [get_timing_paths -setup -max_paths 1]
    if {[llength $setup_paths] == 0} {
        difi_verify::fail "No constrained setup timing path found; review clocks and constraints"
    }
    set setup_wns [get_property SLACK [lindex $setup_paths 0]]
    set hold_paths [get_timing_paths -hold -max_paths 1]
    set hold_whs "not_found"
    if {[llength $hold_paths] != 0} {
        set hold_whs [get_property SLACK [lindex $hold_paths 0]]
    }
    difi_verify::msg "Post-route setup WNS=$setup_wns ns; hold WHS=$hold_whs ns"
    if {$setup_wns < 0.0} { difi_verify::fail "Setup timing not met; do not accept this build" }
    if {$hold_whs ne "not_found" && $hold_whs < 0.0} {
        difi_verify::fail "Hold timing not met; do not accept this build"
    }

    set bits [glob -nocomplain -directory [file join $project_dir "$project_name.runs" impl_1] *.bit]
    if {[llength $bits] != 1 || ![file isfile [lindex $bits 0]]} {
        difi_verify::fail "Expected one generated .bit under the rebuilt impl_1 directory; got [llength $bits]"
    }
    set bit_path [lindex $bits 0]
    difi_verify::msg "Bitstream: $bit_path"

    set xsa [file join $project_dir "${target}_rebuilt.xsa"]
    write_hw_platform -fixed -include_bit -force $xsa
    if {![file isfile $xsa]} { difi_verify::fail "XSA export did not produce $xsa" }

    # Preserve a concise, reviewable outcome separate from the ignored Vivado workspace.
    set summary [open [file join $out SUCCESS.txt] w]
    puts $summary "Result: PASS (tool build and post-route timing; Vitis/board not yet retested)"
    puts $summary "Vivado: $ver"
    puts $summary "Target: $target"
    puts $summary "Part: $part"
    puts $summary "Top: $top"
    puts $summary "Synthesis status: [get_property STATUS [get_runs synth_1]]"
    puts $summary "Implementation status: [get_property STATUS [get_runs impl_1]]"
    puts $summary "Setup WNS (ns): $setup_wns"
    puts $summary "Hold WHS (ns): $hold_whs"
    puts $summary "Bitstream: $bit_path"
    puts $summary "XSA: $xsa"
    puts $summary "Not yet tested: regenerated XSA imported into Vitis; on-board IQ/UDP validation"
    close $summary
    close_project
    difi_verify::msg "PASS. Reports in $out; XSA=$xsa"
}

if {![info exists ::DIFI_VERIFY_SKIP_AUTORUN]} {
    if {![info exists ::argv] || [llength $::argv] != 1} {
        error "Usage: vivado -mode batch -source scripts/vivado/verify_rebuilt_impl.tcl -tclargs packaged_ip|b5_raw_export|b6_udp_rx"
    }
    difi_verify::run [lindex $::argv 0]
}
