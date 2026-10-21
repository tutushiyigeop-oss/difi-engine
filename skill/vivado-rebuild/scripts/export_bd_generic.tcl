# Source in an EXISTING Vivado GUI project. Does not run implementation.
# Usage:
#   source path/to/skill/vivado-rebuild/scripts/export_bd_generic.tcl
#   vrskill::export_bd path/to/project_config.tcl D:/checkout/root
source [file join [file dirname [info script]] common.tcl]

proc ::vrskill::export_bd {config_file repo_root} {
    set cfg [::vrskill::load_config $config_file $repo_root]
    ::vrskill::verify_version $cfg
    if {[llength [get_projects -quiet]] != 1} {
        ::vrskill::die "Open the one original Vivado project to export"
    }
    set live_part [get_property PART [current_project]]
    set live_top [get_property TOP [get_filesets sources_1]]
    if {$live_part ne [dict get $cfg part] || $live_top ne [dict get $cfg top]} {
        ::vrskill::die "Wrong original project: part=$live_part top=$live_top"
    }
    set bd_name [dict get $cfg bd_name]
    set bd_path ""
    foreach f [get_files -quiet *.bd] {
        if {[file rootname [file tail $f]] eq $bd_name} { set bd_path $f; break }
    }
    if {$bd_path eq ""} { ::vrskill::die "BD $bd_name.bd absent in original project" }
    open_bd_design $bd_path
    # No attempt to guess external IP configuration or connections.
    set out [::vrskill::absolute_from_root [dict get $cfg _root] [dict get $cfg snapshot_rel]]
    file mkdir $out
    ::vrskill::log "Export $bd_name from original project to $out"
    validate_bd_design
    save_bd_design
    set snapshot [file join $out bd.tcl]
    write_bd_tcl -force $snapshot
    if {![file isfile $snapshot] || [file size $snapshot] < 128} {
        ::vrskill::die "write_bd_tcl failed to create a usable snapshot"
    }

    set exported_xdc {}
    set constr [get_filesets -quiet constrs_1]
    if {[llength $constr]} {
        set n 0
        foreach f [get_files -quiet -of_objects $constr] {
            set path [get_property NAME $f]
            if {![string equal -nocase [file extension $path] ".xdc"]} { continue }
            if {![file isfile $path]} {
                ::vrskill::log "WARNING: XDC is missing or inaccessible: $path"
                continue
            }
            incr n
            set rel [format "constraints/%02d_%s" $n [file tail $path]]
            file mkdir [file join $out constraints]
            file copy -force $path [file join $out $rel]
            lappend exported_xdc $rel
        }
    }
    set ip_repos {}
    catch {set ip_repos [get_property ip_repo_paths [current_project]]}
    set manifest [dict create bd_name $bd_name part $live_part top $live_top \
        vivado_version [version -short] exported_xdc $exported_xdc \
        original_ip_repo_paths $ip_repos]
    set handle [open [file join $out manifest.tcl] w]
    puts $handle "# Generated from the verified ORIGINAL project; do not edit unless audited."
    puts $handle [list set ::vrskill_snapshot $manifest]
    close $handle

    set handle [open [file join $out export_info.txt] w]
    puts $handle "Original project: [get_property NAME [current_project]]"
    puts $handle "BD: $bd_name | top: $live_top | part: $live_part | Vivado: [version -short]"
    puts $handle "Repo-relative RTL globs (MANUAL CONFIG, audit before rebuilding): [dict get $cfg rtl_globs]"
    puts $handle "Repo-relative custom IP dirs (MANUAL CONFIG): [dict get $cfg ip_repo_dirs]"
    puts $handle "Source project IP repository paths (audit for external dependencies): $ip_repos"
    puts $handle "Exported XDC: $exported_xdc"
    puts $handle "NOTE: Generated wrapper, IP-managed constraints and externally stored files may need separate handling."
    puts $handle "Cells / VLNV:"
    foreach cell [get_bd_cells -quiet -hier] {
        set vlnv ""
        catch {set vlnv [get_property VLNV $cell]}
        puts $handle "  $cell | $vlnv"
    }
    close $handle
    ::vrskill::log "Saved bd.tcl, manifest.tcl, export_info.txt and user XDC copies in $out"
    ::vrskill::log "Do NOT claim reproduction until a fresh project builds and on-board test passes."
    return $out
}
