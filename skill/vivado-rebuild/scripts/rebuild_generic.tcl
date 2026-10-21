# Run in a FRESH Vivado batch session from the repository root:
# vivado -mode batch -source skill/vivado-rebuild/scripts/rebuild_generic.tcl -tclargs config_path
# Optional second Tcl arg: absolute repository root. Default: [pwd].
source [file join [file dirname [info script]] common.tcl]

proc ::vrskill::rebuild {cfg_path repo_root} {
    set cfg [::vrskill::load_config $cfg_path $repo_root]
    ::vrskill::verify_version $cfg
    if {[llength [get_projects -quiet]] > 0} {
        ::vrskill::die "Rebuild must run in a fresh Vivado batch session"
    }
    set root [dict get $cfg _root]
    set out [::vrskill::absolute_from_root $root [dict get $cfg build_rel]]
    set snapshot [::vrskill::absolute_from_root $root [dict get $cfg snapshot_rel]]
    set script [file join $snapshot bd.tcl]
    if {![file isfile $script]} { ::vrskill::die "Missing exported $script" }
    set meta [::vrskill::read_snapshot $snapshot]
    ::vrskill::check_identity $cfg $meta
    if {[file exists $out]} { ::vrskill::die "Rebuild folder already exists; will not overwrite: $out" }

    # Validate all user dependencies BEFORE creating any project files.
    set sources {}
    foreach pattern [dict get $cfg rtl_globs] {
        set files [glob -nocomplain -types f -directory $root -- $pattern]
        if {[llength $files] == 0} { ::vrskill::die "RTL pattern matched no files: $pattern" }
        foreach f $files { lappend sources [file normalize $f] }
    }
    set sources [lsort -unique $sources]
    set include_dirs {}
    foreach p [dict get $cfg include_dirs] {
        set d [::vrskill::absolute_from_root $root $p]
        if {![file isdirectory $d]} { ::vrskill::die "Missing include directory $p" }
        lappend include_dirs $d
    }
    set repos {}
    foreach p [dict get $cfg ip_repo_dirs] {
        set d [::vrskill::absolute_from_root $root $p]
        if {![file isdirectory $d]} { ::vrskill::die "Missing IP repository $p" }
        lappend repos $d
    }
    foreach rel [dict get $meta exported_xdc] {
        if {![file isfile [file join $snapshot $rel]]} { ::vrskill::die "Missing exported XDC: $rel" }
    }

    create_project [dict get $cfg name] $out -part [dict get $cfg part]
    set_property target_language Verilog [current_project]
    if {[llength $repos]} {
        set_property ip_repo_paths $repos [current_project]
        update_ip_catalog -rebuild
    }
    if {[llength $sources]} {
        add_files -fileset sources_1 -norecurse $sources
        if {[llength $include_dirs]} {
            set_property include_dirs $include_dirs [get_filesets sources_1]
        }
        update_compile_order -fileset sources_1
    }
    ::vrskill::log "Sourcing REAL BD Tcl $script"
    source $script
    set actual_bd ""
    foreach f [get_files -quiet *.bd] {
        if {[file rootname [file tail $f]] eq [dict get $cfg bd_name]} { set actual_bd $f; break }
    }
    if {$actual_bd eq ""} { ::vrskill::die "Rebuilt BD missing" }
    open_bd_design $actual_bd
    validate_bd_design
    save_bd_design
    foreach rel [dict get $meta exported_xdc] {
        add_files -fileset constrs_1 -norecurse [file join $snapshot $rel]
    }
    generate_target all [get_files $actual_bd]
    set wrapper [make_wrapper -files [get_files $actual_bd] -top]
    if {[llength $wrapper] == 0} { ::vrskill::die "make_wrapper returned no source" }
    add_files -norecurse $wrapper
    update_compile_order -fileset sources_1
    set_property top [dict get $cfg top] [get_filesets sources_1]
    close_project
    set xpr [file join $out "[dict get $cfg name].xpr"]
    if {![file isfile $xpr]} { ::vrskill::die "XPR not created: $xpr" }
    ::vrskill::log "BD rebuild PASS (not yet implemented): $xpr"
    return $xpr
}

if {![info exists ::vrskill_skip_autorun]} {
    if {![info exists ::argv] || [llength $::argv] < 1 || [llength $::argv] > 2} {
        error "Usage: vivado -mode batch -source rebuild_generic.tcl -tclargs config.tcl ?repo_root?"
    }
    set root [expr {[llength $::argv] == 2 ? [lindex $::argv 1] : [pwd]}]
    ::vrskill::rebuild [lindex $::argv 0] $root
}
