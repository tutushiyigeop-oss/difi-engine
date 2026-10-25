# DIFI Stage D: run actual Vivado synthesis, route, bitstream and XSA export.
# Vivado 2024.2, run only AFTER build_stage_d.tcl returned successfully.
# vivado -mode batch -source scripts/vivado/verify_stage_d.tcl
# Does not erase runs or overwrite prior report output.
namespace eval stage_d_verify {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
    proc die {s} { error "STAGE_D_VERIFY: $s" }
    proc say {s} { puts "STAGE_D_VERIFY: $s" }
    proc ensure_run {name} {
        set r [get_runs $name]
        if {[llength $r] != 1} { die "Missing run $name" }
        set status [get_property STATUS $r]
        set progress [get_property PROGRESS $r]
        if {$progress ne "100%" || [string first "Complete" $status] < 0} {
            die "$name incomplete: status=$status progress=$progress"
        }
    }
}
if {[catch {version -short} ver] || $ver ne "2024.2"} {
    stage_d_verify::die "Vivado 2024.2 required"
}
if {[llength [get_projects -quiet]] > 0} { stage_d_verify::die "Use fresh Vivado session" }
set root $stage_d_verify::root
set proj_dir [file join $root vivado rebuilt half_duplex]
set proj_name difi_stage_d_half_duplex
set xpr [file join $proj_dir $proj_name.xpr]
set results [file join $root report results vivado_rebuild half_duplex]
if {![file isfile $xpr]} { stage_d_verify::die "Project missing: $xpr" }
if {[file exists [file join $results SUCCESS.txt]]} {
    stage_d_verify::die "Success report exists. Will not replace archived evidence."
}
file mkdir $results
open_project $xpr
if {[get_property TOP [get_filesets sources_1]] ne "difi_ip_test_wrapper"} {
    stage_d_verify::die "Unexpected project top"
}
if {[get_property PART [current_project]] ne "xc7z020clg400-2"} {
    stage_d_verify::die "Unexpected chip part"
}
stage_d_verify::say "Synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
stage_d_verify::ensure_run synth_1
stage_d_verify::say "Implementation..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
stage_d_verify::ensure_run impl_1
open_run impl_1
report_timing_summary -file [file join $results timing_summary.rpt]
report_utilization -file [file join $results utilization.rpt]
report_drc -file [file join $results drc.rpt]
report_clocks -file [file join $results clocks.rpt]
set setup [get_timing_paths -setup -max_paths 1]
if {[llength $setup] < 1} { stage_d_verify::die "No setup path. Check timing constraints" }
set wns [get_property SLACK [lindex $setup 0]]
set hold [get_timing_paths -hold -max_paths 1]
set whs "N/A"
if {[llength $hold] > 0} {
    set whs [get_property SLACK [lindex $hold 0]]
}
if {$wns < 0} { stage_d_verify::die "Post-route setup timing failed WNS=$wns" }
if {$whs ne "N/A" && $whs < 0} { stage_d_verify::die "Post-route hold timing failed WHS=$whs" }
set bits [glob -nocomplain -directory [file join $proj_dir $proj_name.runs impl_1] *.bit]
if {[llength $bits] != 1} { stage_d_verify::die "Expected one bitstream; found [llength $bits]" }
set xsa [file join $proj_dir stage_d_half_duplex.xsa]
write_hw_platform -fixed -include_bit -force $xsa
if {![file exists $xsa]} { stage_d_verify::die "XSA not exported" }
set f [open [file join $results SUCCESS.txt] w]
puts $f "Stage D tool result: PASS (NOT board tested)"
puts $f "Vivado: $ver"
puts $f "Part: [get_property PART [current_project]]"
puts $f "Top: [get_property TOP [get_filesets sources_1]]"
puts $f "WNS: $wns ns"
puts $f "WHS: $whs ns"
puts $f "Bitstream: [lindex $bits 0]"
puts $f "XSA: $xsa"
puts $f "Next gates: Vitis DMA0 RX test, Vitis DMA1 TX test, same XSA without re-download, no concurrent transfer."
close $f
close_project
stage_d_verify::say "Build passed (not board tested). XSA: $xsa"
