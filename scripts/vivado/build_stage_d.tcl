# DIFI Stage D: create a fresh hardware project from the verified B6 v0.2
# snapshot, then apply upgrade_b6_to_half_duplex.tcl. Vivado 2024.2.
# Copy this script plus upgrade_... into repo/scripts/vivado/ and copy the tap
# Verilog into repo/rtl/board/. From repo root:
# vivado -mode batch -source scripts/vivado/build_stage_d.tcl

namespace eval stage_d {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
    proc say {s} { puts "STAGE_D: $s" }
    proc die {s} { error "STAGE_D: $s" }
}

if {[catch {version -short} ver] || $ver ne "2024.2"} {
    stage_d::die "Use Vivado 2024.2; received '$ver'"
}
if {[llength [get_projects -quiet]] != 0} {
    stage_d::die "Open Vivado batch process with no project already open"
}
set root $stage_d::root
set snap_dir [file join $root scripts vivado generated b6_udp_rx]
set b6_tcl [file join $snap_dir bd.tcl]
set manifest [file join $snap_dir manifest.tcl]
set patch [file join $root scripts vivado upgrade_b6_to_half_duplex.tcl]
set tap [file join $root rtl board difi_iq_axis_tap.v]
set mon [file join $root rtl board difi_b6_rx_meta_monitor.v]
foreach f [list $b6_tcl $manifest $patch $tap $mon] {
    if {![file isfile $f]} { stage_d::die "Missing required file: $f" }
}
source $manifest
if {![array exists ::difi_manifest] || $::difi_manifest(target) ne "b6_udp_rx"} {
    stage_d::die "Expected actual B6 v0.2 manifest"
}
if {$::difi_manifest(part) ne "xc7z020clg400-2" || $::difi_manifest(vivado_version) ne "2024.2"} {
    stage_d::die "Unexpected B6 target part or Vivado version"
}
set proj_name difi_stage_d_half_duplex
set proj_dir [file join $root vivado rebuilt half_duplex]
if {[file exists $proj_dir]} {
    stage_d::die "Refusing to overwrite $proj_dir. Back up/rename this directory manually before retry."
}
file mkdir $proj_dir
create_project $proj_name $proj_dir -part $::difi_manifest(part)
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list [file join $root ip_repo]] [current_project]
update_ip_catalog -rebuild
add_files -fileset sources_1 -norecurse [list $mon]
update_compile_order -fileset sources_1

# Only regenerate B6 from its committed original BD Tcl, do not reassemble
# a network from memory or a placeholder B5 diagram.
source $b6_tcl
set bd_file ""
foreach x [get_files -quiet *.bd] {
    if {[file rootname [file tail $x]] eq $::difi_manifest(bd_name)} {
        set bd_file $x; break
    }
}
if {$bd_file eq ""} { stage_d::die "Expected B6 BD not generated" }
open_bd_design $bd_file
source $patch
stage_d::say "Mutated B6 source BD to Stage D; exporting snapshot"
write_bd_tcl -force [file join $proj_dir stage_d_design.tcl]
foreach rel $::difi_manifest(exported_xdc) {
    add_files -fileset constrs_1 -norecurse [file join $snap_dir $rel]
}
generate_target all [get_files $bd_file]
set wrappers [make_wrapper -files [get_files $bd_file] -top]
if {[llength $wrappers] == 0} { stage_d::die "No generated BD wrapper" }
add_files -norecurse $wrappers
update_compile_order -fileset sources_1
set_property top $::difi_manifest(original_top) [get_filesets sources_1]
set actual_top [get_property TOP [get_filesets sources_1]]
if {$actual_top ne $::difi_manifest(original_top)} { stage_d::die "Incorrect top: $actual_top" }
validate_bd_design
save_bd_design
close_project
stage_d::say "New XPR: [file join $proj_dir $proj_name.xpr]"
stage_d::say "BD only. NEXT: run verify_stage_d.tcl for synthesis/route/bitstream/XSA."
