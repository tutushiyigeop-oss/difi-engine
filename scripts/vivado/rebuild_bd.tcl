# Rebuild a new, separate Vivado project from an EXISTING real BD snapshot.
# Run from the DIFI checkout (any cwd is accepted):
#   vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs packaged_ip
#   vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b5_raw_export
#   vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs b6_udp_rx
#
# Does not synthesize or implement automatically.  Reports BD-level
# validation only; a full bitstream and Vitis XSA require further steps.

namespace eval difi {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
}
proc difi::die {message} { error "DIFI REBUILD: $message" }
proc difi::msg {message} { puts "\[DIFI REBUILD\] $message" }

proc difi::check_vivado {} {
    # Vivado commands may be autoloaded and absent from [info commands]
    # until they are actually called.  Query a real Vivado command instead.
    if {[catch {version -short} ver]} {
        difi::die "Vivado version unavailable. Run with vivado -mode batch."
    }
    difi::msg "Vivado version: $ver"
}

proc difi::add_b5_sources {root} {
    set files {}
    foreach folder {include common context data rx tx version top} {
        set d [file join $root rtl $folder]
        if {![file isdirectory $d]} { difi::die "Missing RTL directory: $d" }
        foreach ext {v vh} {
            foreach file [glob -nocomplain -directory $d *.$ext] {
                lappend files [file normalize $file]
            }
        }
    }
    set board_file [file join $root rtl board difi_engine_board_b5.v]
    if {![file exists $board_file]} { difi::die "Missing $board_file" }
    lappend files [file normalize $board_file]
    if {[llength $files] < 10} { difi::die "Suspiciously few RTL sources. Wrong checkout?" }
    add_files -fileset sources_1 -norecurse $files
    set_property include_dirs [list [file join $root rtl include]] [get_filesets sources_1]
    # Module-reference cells in BD Tcl depend on Vivado discovering the RTL
    # hierarchy before create_bd_cell -type module -reference is executed.
    update_compile_order -fileset sources_1
    difi::msg "Added [llength $files] source/header files, including B5 raw export."
}

# B6 v0.2 is an IP-repository design with one user RTL Module Reference.
# The real BD snapshot is required; this function never constructs a BD graph.
proc difi::add_b6_sources {root} {
    set monitor [file join $root rtl board difi_b6_rx_meta_monitor.v]
    if {![file isfile $monitor]} {
        difi::die "Missing B6 monitor RTL: $monitor"
    }
    add_files -fileset sources_1 -norecurse [list $monitor]
    update_compile_order -fileset sources_1
    difi::msg "Added B6 Metadata Monitor Module Reference source."
}

proc difi::rebuild {target} {
    variable root
    difi::check_vivado
    if {$target ni {packaged_ip b5_raw_export b6_udp_rx}} {
        difi::die "Usage: -tclargs packaged_ip | b5_raw_export | b6_udp_rx"
    }
    set snapshot_dir [file normalize [file join $root scripts vivado generated $target]]
    set bd_script [file join $snapshot_dir bd.tcl]
    set manifest [file join $snapshot_dir manifest.tcl]
    if {![file isfile $bd_script] || ![file isfile $manifest]} {
        difi::die "Real BD export missing in $snapshot_dir. First OPEN ORIGINAL PROJECT and run export_bd.tcl."
    }
    catch {unset ::difi_manifest}
    source $manifest
    if {![array exists ::difi_manifest]} { difi::die "Corrupt or missing export manifest" }
    foreach key {target bd_name part original_top vivado_version exported_xdc} {
        if {![info exists ::difi_manifest($key)]} { difi::die "Manifest missing $key" }
    }
    if {$::difi_manifest(target) ne $target} { difi::die "Manifest target does not match requested target" }
    set bd_name $::difi_manifest(bd_name)
    set part $::difi_manifest(part)
    if {[version -short] ne $::difi_manifest(vivado_version)} {
        difi::die "Vivado version mismatch: exported $::difi_manifest(vivado_version), current [version -short]. Use same version (2024.2) first."
    }
    if {[llength [get_projects -quiet]] > 0} {
        difi::die "Another project is already open. Run in a fresh Vivado batch process."
    }

    # Generated .xpr, run data, and logs stay under vivado/, already ignored
    # in the project's .gitignore. Never overwrite existing project data.
    set name "difi_rebuilt_$target"
    set project_dir [file normalize [file join $root vivado rebuilt $target]]
    if {[file exists $project_dir]} {
        difi::die "Existing rebuild directory: $project_dir. Rename/remove it manually before retrying; refusing to overwrite."
    }
    file mkdir $project_dir
    difi::msg "Create $name for $part at $project_dir"
    create_project $name $project_dir -part $part
    set_property target_language Verilog [current_project]

    if {$target eq "packaged_ip" || $target eq "b6_udp_rx"} {
        set repo [file normalize [file join $root ip_repo difi_engine_ip]]
        if {![file isfile [file join $repo component.xml]]} {
            difi::die "Packaged IP component.xml missing: $repo"
        }
        set_property ip_repo_paths [list [file join $root ip_repo]] [current_project]
        update_ip_catalog -rebuild
        difi::msg "Using custom packaged DIFI IP from $repo"
        if {$target eq "b6_udp_rx"} { difi::add_b6_sources $root }
    } else {
        difi::add_b5_sources $root
    }

    # write_bd_tcl creates the COMPLETE block graph using saved Vivado IP
    # configuration and wiring. Do not create a same-name BD in advance.
    difi::msg "Source actual BD snapshot $bd_script"
    source $bd_script
    set bd_files [get_files -quiet *.bd]
    set bd_file ""
    foreach item $bd_files {
        if {[file rootname [file tail $item]] eq $bd_name} { set bd_file $item; break }
    }
    if {$bd_file eq ""} { difi::die "Reconstructed BD $bd_name.bd was not found" }
    open_bd_design $bd_file
    validate_bd_design
    save_bd_design
    difi::msg "Block Design validation passed: $bd_name"

    foreach rel $::difi_manifest(exported_xdc) {
        set file [file join $snapshot_dir $rel]
        if {![file isfile $file]} { difi::die "Missing exported XDC: $file" }
        add_files -fileset constrs_1 -norecurse $file
    }

    generate_target all [get_files $bd_file]
    set wrappers [make_wrapper -files [get_files $bd_file] -top]
    if {[llength $wrappers] == 0} { difi::die "make_wrapper returned no file" }
    add_files -norecurse $wrappers
    update_compile_order -fileset sources_1
    set_property top $::difi_manifest(original_top) [get_filesets sources_1]
    # create_project already created the .xpr.  Do not save_project_as here:
    # that would duplicate/overwrite the same project and generated IP tree.
    close_project
    if {![file isfile [file join $project_dir "$name.xpr"]]} {
        difi::die "Expected XPR not found after close_project"
    }
    difi::msg "Created and validated fresh project: $project_dir/$name.xpr"
    difi::msg "NEXT: inspect Address Editor, project constraints, GEM0/MIO, clocks, then run implementation."
    difi::msg "Do not claim end-to-end reproduction before bitstream/XSA/Vitis regression."
}

# Command-line execution only, also allow source inspection under tclsh.
if {![info exists ::DIFI_SKIP_AUTORUN]} {
    if {![info exists ::argv] || [llength $::argv] != 1} {
        error "Usage: vivado -mode batch -source scripts/vivado/rebuild_bd.tcl -tclargs packaged_ip|b5_raw_export|b6_udp_rx"
    }
    difi::rebuild [lindex $::argv 0]
}
