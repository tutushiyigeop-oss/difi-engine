# DIFI: snapshot the *real* Block Design from the CURRENT open Vivado project.
# Vivado 2024.2.  Run from the Vivado Tcl Console:
#   source D:/Study/project/DIFI/scripts/vivado/export_bd.tcl
#   difi::export_bd packaged_ip
#   # OR, in the B5 (not B4) project: difi::export_bd b5_raw_export
#
# This script DOES NOT reconstruct a guessed Block Design.  It records the
# current actual project/BD and exports a portable write_bd_tcl source.

namespace eval difi {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
}

proc difi::fail {message} { error "DIFI EXPORT: $message" }
proc difi::say {message} { puts "\[DIFI EXPORT\] $message" }

proc difi::assert_vivado {} {
    # Vivado can expose some commands through Tcl autoload. Checking
    # [info commands ...] may wrongly reject otherwise valid commands.
    if {[catch {version -short} ver]} {
        difi::fail "Cannot query Vivado version. Run inside Vivado Tcl Console."
    }
    if {[catch {current_project} project] || $project eq ""} {
        difi::fail "No active Vivado project. Open the original project first."
    }
    difi::say "Vivado version: $ver"
}

proc difi::cells_contain {needle} {
    foreach cell [get_bd_cells -quiet -hier] {
        set descr "$cell"
        foreach prop {VLNV REF_NAME CONFIG.Component_Name} {
            if {![catch {get_property $prop $cell} value]} { append descr " $value" }
        }
        if {[string first $needle $descr] >= 0} { return 1 }
    }
    return 0
}

proc difi::export_bd {target} {
    variable root
    difi::assert_vivado
    array set targets {
        packaged_ip    {difi_ip_test difi_ip_test_wrapper}
        b5_raw_export  {difi_system difi_system_wrapper}
    }
    if {![info exists targets($target)]} {
        difi::fail "Unknown target '$target'. Choose packaged_ip or b5_raw_export."
    }
    if {[llength [get_projects -quiet]] != 1} {
        difi::fail "Open exactly one appropriate Vivado project first."
    }
    lassign $targets($target) bd_name expected_top
    set project [current_project]
    set part [get_property PART $project]
    set original_top [get_property TOP [get_filesets sources_1]]
    if {$original_top ne $expected_top} {
        difi::fail "Wrong project? TOP is '$original_top', expected '$expected_top' for $target."
    }
    set bd_file ""
    foreach item [get_files -quiet *.bd] {
        if {[file rootname [file tail $item]] eq $bd_name} { set bd_file $item; break }
    }
    if {$bd_file eq ""} {
        difi::fail "Missing $bd_name.bd. Open its original project (not another project)."
    }
    if {$target eq "b5_raw_export"} {
        # B4 and B5 have identical BD name AND wrapper top.  Identify B5
        # explicitly, rather than exporting an old decoded-IQ loopback.
        set found_source [expr {[llength [get_files -quiet *difi_engine_board_b5.v]] > 0}]
        open_bd_design $bd_file
        set found_cell [difi::cells_contain difi_board_raw_packet_export]
        if {!$found_cell} {
            difi::fail "difi_system may be B4: BD has no B5 raw-export cell (difi_board_raw_packet_export). Refusing to mislabel it."
        }
        if {!$found_source} {
            difi::say "WARNING: B5 cell found, but original board RTL filename was not in get_files; check exported RTL dependency paths."
        }
    } else {
        open_bd_design $bd_file
        if {![difi::cells_contain difi_engine_ip]} {
            difi::fail "Expected packaged difi_engine_ip instance was not found in $bd_name."
        }
    }
    set out [file normalize [file join $root scripts vivado generated $target]]
    file mkdir $out
    set snapshot [file join $out bd.tcl]
    # Preserve IP version checks so incompatible Vivado releases do not
    # silently substitute different core versions.
    difi::say "Exporting real $bd_name.bd -> $snapshot"
    validate_bd_design
    save_bd_design
    write_bd_tcl -force $snapshot
    if {![file exists $snapshot] || [file size $snapshot] < 128} {
        difi::fail "write_bd_tcl did not produce a nonempty snapshot."
    }

    # Preserve source-level user XDC files, including their content.  XDCs
    # owned by managed IP may require separate audit after reconstruction.
    set copied_xdcs {}
    set constraint_set [get_filesets -quiet constrs_1]
    if {[llength $constraint_set] != 0} {
        set idx 0
        foreach xdc [get_files -quiet -of_objects $constraint_set] {
            set path [get_property NAME $xdc]
            if {![string equal -nocase [file extension $path] ".xdc"]} { continue }
            if {![file isfile $path]} {
                difi::say "WARNING: external/missing XDC, not copied: $path"
                continue
            }
            incr idx
            set rel [format "constraints/%02d_%s" $idx [file tail $path]]
            file mkdir [file join $out constraints]
            file copy -force $path [file join $out $rel]
            lappend copied_xdcs $rel
        }
    }

    # Record relevant project info without relying on absolute original paths.
    set recorded_ip_repos {}
    if {![catch {get_property ip_repo_paths $project} repos]} {
        foreach repo $repos { lappend recorded_ip_repos [file normalize $repo] }
    }
    set manifest [file join $out manifest.tcl]
    set f [open $manifest w]
    puts $f "# Produced by export_bd.tcl from the real Vivado project."
    puts $f "# Safe Tcl data; sourced by rebuild_bd.tcl."
    puts $f [list array set ::difi_manifest [list \
        target $target bd_name $bd_name original_top $original_top \
        part $part vivado_version [version -short] \
        exported_xdc $copied_xdcs \
        original_ip_repos $recorded_ip_repos]]
    close $f

    set info_file [open [file join $out export_info.txt] w]
    puts $info_file "Target: $target"
    puts $info_file "BD: $bd_name"
    puts $info_file "Top: $original_top"
    puts $info_file "Part: $part"
    puts $info_file "Vivado version: [version -short]"
    puts $info_file "Original project: [get_property NAME $project]"
    puts $info_file "Original XDC paths (copies are saved alongside bd.tcl):"
    foreach rel $copied_xdcs { puts $info_file "  $rel" }
    puts $info_file "Original IP repositories (for auditing custom IP dependencies):"
    foreach repo $recorded_ip_repos { puts $info_file "  $repo" }
    puts $info_file "BD cells and VLNVs:"
    foreach cell [get_bd_cells -quiet -hier] {
        set vlnv ""
        catch {set vlnv [get_property VLNV $cell]}
        puts $info_file "  $cell | $vlnv"
    }
    close $info_file

    difi::say "Snapshot saved to: $out"
    difi::say "Review bd.tcl, manifest.tcl, export_info.txt and copied constraints."
    difi::say "Then commit scripts/vivado/generated/$target/."
    difi::say "IMPORTANT: export != validated recreation. Next run rebuild_bd.tcl in a FRESH project."
    return $out
}
