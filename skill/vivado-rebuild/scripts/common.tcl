# Shared helpers for the reusable Vivado BD workflow.
# No Vivado calls occur merely by sourcing this file.
namespace eval ::vrskill {}

proc ::vrskill::die {message} { error "VIVADO-REBUILD SKILL: $message" }
proc ::vrskill::log {message} { puts "\[VIVADO-REBUILD SKILL\] $message" }

proc ::vrskill::vivado_version {} {
    if {[catch {version -short} v]} {
        ::vrskill::die "Vivado Tcl command unavailable. Run in the Vivado Tcl Console or vivado -mode batch."
    }
    return $v
}

proc ::vrskill::absolute_from_root {root relative} {
    if {[file pathtype $relative] ne "relative"} {
        ::vrskill::die "Expected a repository-relative path, got '$relative'"
    }
    set path [file normalize [file join $root $relative]]
    set prefix "${root}/"
    if {($path ne $root) && [string first $prefix "${path}/"] != 0} {
        ::vrskill::die "Path escapes repository root: $relative"
    }
    return $path
}

proc ::vrskill::load_config {config_file repo_root} {
    set repo_root [file normalize $repo_root]
    if {![file isdirectory $repo_root]} { ::vrskill::die "Repository root not found: $repo_root" }
    set cfg_path [file normalize [file join $repo_root $config_file]]
    if {![file isfile $cfg_path]} { ::vrskill::die "Missing config Tcl: $cfg_path" }
    catch {unset ::vrskill_config}
    # Only source CONFIG FILES YOU TRUST. Tcl configuration is executable code.
    source $cfg_path
    if {![info exists ::vrskill_config]} { ::vrskill::die "Config must define ::vrskill_config" }
    set cfg $::vrskill_config
    foreach key {name bd_name part top vivado_version snapshot_rel build_rel report_rel rtl_globs include_dirs ip_repo_dirs} {
        if {![dict exists $cfg $key]} { ::vrskill::die "Config missing required key '$key'" }
    }
    foreach key {name bd_name top} {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} [dict get $cfg $key]]} {
            ::vrskill::die "Invalid $key: [dict get $cfg $key]"
        }
    }
    if {![regexp {^[A-Za-z0-9_-]+$} [dict get $cfg name]]} { ::vrskill::die "Invalid project label" }
    foreach key {snapshot_rel build_rel report_rel} {
        ::vrskill::absolute_from_root $repo_root [dict get $cfg $key]
    }
    dict set cfg _root $repo_root
    return $cfg
}

proc ::vrskill::read_snapshot {snapshot_dir} {
    set file [file join $snapshot_dir manifest.tcl]
    if {![file isfile $file]} { ::vrskill::die "Missing manifest: $file" }
    catch {unset ::vrskill_snapshot}
    source $file
    if {![info exists ::vrskill_snapshot]} { ::vrskill::die "Invalid manifest (missing ::vrskill_snapshot)" }
    return $::vrskill_snapshot
}

proc ::vrskill::check_identity {cfg meta} {
    foreach key {bd_name part top} {
        if {![dict exists $meta $key] || [dict get $meta $key] ne [dict get $cfg $key]} {
            ::vrskill::die "Exported $key does not match config ($key): re-check you opened the correct project"
        }
    }
    if {![dict exists $meta vivado_version] || [dict get $meta vivado_version] ne [dict get $cfg vivado_version]} {
        ::vrskill::die "Snapshot Vivado version differs from config; do not silently upgrade IPs"
    }
}

proc ::vrskill::verify_version {cfg} {
    set live [::vrskill::vivado_version]
    if {$live ne [dict get $cfg vivado_version]} {
        ::vrskill::die "Vivado version mismatch (required [dict get $cfg vivado_version], actual $live)"
    }
    ::vrskill::log "Vivado $live; project [dict get $cfg name]"
}
