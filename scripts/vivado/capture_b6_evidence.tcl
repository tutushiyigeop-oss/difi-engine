# B6 v0.2 evidence capture from the REAL currently open Vivado project.
# Vivado 2024.2 Tcl Console (NOT the old packaged_ip project):
# source D:/Study/project/DIFI/scripts/vivado/capture_b6_evidence.tcl
# difi_b6::export_snapshot
# difi_b6::capture_implementation
#
# Exports into /vivado/b6_archive_staging/ (GIT-IGNORED) for manual review.
# Never touches existing packaged_ip, B5, or working Bitstream/XSA files.

namespace eval difi_b6 {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
}
proc difi_b6::die {msg} { error "B6 CAPTURE: $msg" }
proc difi_b6::msg {msg} { puts "\[B6 CAPTURE\] $msg" }
proc difi_b6::project_check {} {
    if {[catch {version -short} ver]} { difi_b6::die "Must run inside Vivado Tcl Console" }
    if {$ver ne "2024.2"} { difi_b6::die "Expected Vivado 2024.2; got $ver" }
    if {[llength [get_projects -quiet]] != 1} { difi_b6::die "Open exactly one REAL B6 project" }
    if {![string equal -nocase [get_property PART [current_project]] "xc7z020clg400-2"]} {
        difi_b6::die "Unexpected device part: [get_property PART [current_project]]"
    }
    return [current_project]
}
proc difi_b6::one_cell {purpose token property} {
    set matches {}
    foreach c [get_bd_cells -quiet -hier] {
        if {![catch {set val [get_property $property $c]}] && [string first $token $val] >= 0} {
            lappend matches $c
        }
    }
    if {[llength $matches] != 1} {
        difi_b6::die "Expected exactly 1 $purpose, found [llength $matches]. Inspect opened BD; cannot label it B6."
    }
    return [lindex $matches 0]
}
# RTL module-reference BD cells may not have a REF_NAME property.
# Recognize the B6 monitor by its unique FUNCTIONAL PORT SIGNATURE instead
# of a cell name or a synthesized netlist-only property.
proc difi_b6::monitor_candidates {} {
    set matches {}
    foreach c [get_bd_cells -quiet -hier] {
        set matches_signature 1
        foreach p {gpio_count gpio_detail m_ver_valid m_ver_ready m_ctx_valid m_ctx_ready rx_version_error_valid} {
            if {[llength [get_bd_pins -quiet "${c}/${p}"]] != 1} {
                set matches_signature 0
                break
            }
        }
        if {$matches_signature} { lappend matches $c }
    }
    return $matches
}

# Read-only diagnostic; safe even if the BD is incomplete.
# In Vivado Tcl Console: difi_b6::diagnose_monitor
proc difi_b6::diagnose_monitor {} {
    set bd_files [get_files -quiet *.bd]
    difi_b6::msg "Open project: [current_project]; BD files: $bd_files"
    if {[llength $bd_files] == 1} {
        open_bd_design [lindex $bd_files 0]
    }
    difi_b6::msg "BD cells (type / VLNV / monitor output pins):"
    foreach c [get_bd_cells -quiet -hier] {
        set typ "<unknown>"
        set vlnv "<none>"
        catch {set typ [get_property TYPE $c]}
        catch {set vlnv [get_property VLNV $c]}
        set nc [llength [get_bd_pins -quiet "${c}/gpio_count"]]
        set nd [llength [get_bd_pins -quiet "${c}/gpio_detail"]]
        difi_b6::msg "  $c | TYPE=$typ | VLNV=$vlnv | gpio_count=$nc gpio_detail=$nd"
    }
    difi_b6::msg "Signature matches: [difi_b6::monitor_candidates]"
}

proc difi_b6::find_monitor {} {
    set matches [difi_b6::monitor_candidates]
    if {[llength $matches] != 1} {
        difi_b6::diagnose_monitor
        difi_b6::die "Expected exactly one B6 Metadata Monitor matching its RTL port signature; found [llength $matches]. If zero, inspect the displayed cells and confirm the correct B6 v0.2 Block Design is open."
    }
    difi_b6::msg "PASS B6 Metadata Monitor by port signature: [lindex $matches 0]"
    return [lindex $matches 0]
}

proc difi_b6::same_axis_net {pin_a pin_b} {
    set a [get_bd_intf_pins -quiet $pin_a]
    set b [get_bd_intf_pins -quiet $pin_b]
    if {[llength $a] != 1 || [llength $b] != 1} {
        difi_b6::die "Missing AXIS pin: $pin_a or $pin_b"
    }
    set n1 [get_bd_intf_nets -quiet -of_objects $a]
    set n2 [get_bd_intf_nets -quiet -of_objects $b]
    if {[llength $n1] != 1 || [llength $n2] != 1 || $n1 ne $n2} {
        difi_b6::die "Wrong AXIS wiring: $pin_a and $pin_b are not on the same interface net"
    }
    difi_b6::msg "PASS AXIS: $pin_a <-> $pin_b ($n1)"
    return $n1
}
proc difi_b6::check_bd {} {
    set bd_files [get_files -quiet *.bd]
    if {[llength $bd_files] != 1} {
        difi_b6::die "Expected exactly ONE .bd in active B6 project; got [llength $bd_files]. Select a single-BD project for export."
    }
    set bd_file [lindex $bd_files 0]
    open_bd_design $bd_file
    set ps  [difi_b6::one_cell "Zynq PS7" "xilinx.com:ip:processing_system7:" VLNV]
    set dma [difi_b6::one_cell "AXI DMA" "xilinx.com:ip:axi_dma:" VLNV]
    set eng [difi_b6::one_cell "DIFI engine" "difi_engine_ip" VLNV]
    set mon [difi_b6::find_monitor]
    set gpio [difi_b6::one_cell "monitor AXI GPIO" "xilinx.com:ip:axi_gpio:" VLNV]

    set gem [get_property CONFIG.PCW_EN_ENET0 $ps]
    set mdio [get_property CONFIG.PCW_ENET0_GRP_MDIO_IO $ps]
    set mdc_en [get_property CONFIG.PCW_ENET0_GRP_MDIO_ENABLE $ps]
    if {$gem ne "1" || $mdc_en ne "1" ||
        ![regexp -nocase {MIO[[:space:]]*52[[:space:]]*\.\.[[:space:]]*53} $mdio]} {
        difi_b6::die "PS GEM0 MDIO not as B5: GEM0=$gem MDIO_enable=$mdc_en MDIO_IO='$mdio' (want MIO 52 .. 53)"
    }
    difi_b6::msg "PASS PS GEM0 MDIO=$mdio"

    difi_b6::same_axis_net "$dma/M_AXIS_MM2S" "$eng/S_AXIS_RX_PKT"
    difi_b6::same_axis_net "$eng/M_AXIS_IQ" "$dma/S_AXIS_S2MM"
    foreach port {gpio_count gpio_detail} {
        set pin [get_bd_pins -quiet "$mon/$port"]
        if {[llength $pin] != 1 || [llength [get_bd_nets -quiet -of_objects $pin]] == 0} {
            difi_b6::die "Monitor output '$port' is not connected"
        }
    }
    foreach pin {gpio_io_i gpio2_io_i} {
        set gp [get_bd_pins -quiet "$gpio/$pin"]
        if {[llength $gp] != 1 || [llength [get_bd_nets -quiet -of_objects $gp]] == 0} {
            difi_b6::die "AXI GPIO $pin missing/unconnected; require dual input channels"
        }
    }
    if {[get_property CONFIG.C_IS_DUAL $gpio] ne "1"} {
        difi_b6::die "Monitor GPIO is not dual-channel"
    }
    difi_b6::msg "PASS monitor / dual AXI GPIO observed"
    validate_bd_design
    difi_b6::msg "PASS validate_bd_design"
    return [list $bd_file $ps $dma $eng $mon $gpio]
}
proc difi_b6::export_snapshot {} {
    variable root
    set prj [difi_b6::project_check]
    lassign [difi_b6::check_bd] bd_file ps dma eng mon gpio
    set out [file join $root vivado b6_archive_staging snapshot]
    if {[file exists $out]} { difi_b6::die "Refusing to overwrite staging snapshot at $out; review/rename it first" }
    file mkdir $out
    save_bd_design
    write_bd_tcl -force [file join $out bd.tcl]
    if {[file size [file join $out bd.tcl]] < 128} { difi_b6::die "BD Tcl unexpectedly small" }

    set xdc_list {}
    set constraints [get_filesets -quiet constrs_1]
    if {[llength $constraints] != 0} {
        set n 0
        foreach item [get_files -quiet -of_objects $constraints] {
            set p [get_property NAME $item]
            if {![string equal -nocase [file extension $p] ".xdc"]} { continue }
            if {![file isfile $p]} { difi_b6::die "Missing project XDC: $p" }
            incr n
            set rel [format "constraints/%02d_%s" $n [file tail $p]]
            file mkdir [file join $out constraints]
            file copy $p [file join $out $rel]
            lappend xdc_list $rel
        }
    }
    set bd_name [file rootname [file tail $bd_file]]
    set part [get_property PART $prj]
    set top [get_property TOP [get_filesets sources_1]]
    set mf [open [file join $out manifest.tcl] w]
    puts $mf "# Real B6 export from opened Vivado project; only SOURCE after review."
    puts $mf [list array set ::difi_manifest [list target b6_udp_rx bd_name $bd_name \
        original_top $top part $part vivado_version [version -short] \
        exported_xdc $xdc_list original_ip_repos {}]]
    close $mf
    set ff [open [file join $out export_info.txt] w]
    puts $ff "Target: b6_udp_rx"
    puts $ff "BD: $bd_name"
    puts $ff "Top: $top"
    puts $ff "Part: $part"
    puts $ff "Vivado: [version -short]"
    puts $ff "PS GEM0 MDIO: [get_property CONFIG.PCW_ENET0_GRP_MDIO_IO $ps]"
    puts $ff "PS GEM0 IO: [get_property CONFIG.PCW_ENET0_ENET0_IO $ps]"
    puts $ff "AXI DMA: $dma"
    puts $ff "DIFI engine: $eng"
    puts $ff "B6 Metadata Monitor: $mon"
    puts $ff "Monitor AXI GPIO: $gpio"
    puts $ff "Monitor GPIO configured base in PS C: 0x41200000 (verify Address Editor)"
    puts $ff "XDC copies: $xdc_list"
    puts $ff "Cells:"
    foreach c [get_bd_cells -quiet -hier] {
        set vn ""; catch {set vn [get_property VLNV $c]}
        set typ ""; catch {set typ [get_property TYPE $c]}
        puts $ff "  $c | TYPE=$typ | VLNV=$vn"
    }
    close $ff
    difi_b6::msg "STAGED BD Tcl, manifest, XDC and config: $out"
    difi_b6::msg "NEXT: inspect files/privacy and copy into scripts/vivado/generated/b6_udp_rx, then rebuild."
    return $out
}
proc difi_b6::capture_implementation {} {
    variable root
    set prj [difi_b6::project_check]
    # Require actual B6 Block Design, not an old successful B5 implementation.
    difi_b6::check_bd
    set run [get_runs -quiet impl_1]
    if {[llength $run] != 1} { difi_b6::die "impl_1 not found" }
    set status [get_property STATUS $run]
    set progress [get_property PROGRESS $run]
    if {$progress ne "100%" || [string first "Complete" $status] < 0} {
        difi_b6::die "impl_1 not complete: status='$status', progress=$progress"
    }
    set out [file join $root vivado b6_archive_staging implementation]
    if {[file exists $out]} { difi_b6::die "Refusing to overwrite staged reports at $out; review/rename first" }
    file mkdir $out
    open_run impl_1
    report_utilization -file [file join $out utilization.rpt]
    report_timing_summary -file [file join $out timing_summary.rpt]
    report_drc -file [file join $out drc.rpt]
    report_clocks -file [file join $out clocks.rpt]
    set paths [get_timing_paths -setup -max_paths 1]
    set slack "NOT_FOUND"
    if {[llength $paths]} { set slack [get_property SLACK [lindex $paths 0]] }
    set hp [get_timing_paths -hold -max_paths 1]
    set hslack "NOT_FOUND"
    if {[llength $hp]} { set hslack [get_property SLACK [lindex $hp 0]] }
    set xsa [file join $out b6_from_verified_impl.xsa]
    set xsa_ok 1
    if {[catch {write_hw_platform -fixed -include_bit -force $xsa} reason]} {
        set xsa_ok 0
        difi_b6::msg "WARNING: XSA export failed: $reason"
    }
    set f [open [file join $out capture_info.txt] w]
    puts $f "Evidence: REAL B6 implementation run; not independent rebuild."
    puts $f "Vivado: [version -short]"
    puts $f "Part: [get_property PART $prj]"
    puts $f "Top: [get_property TOP [get_filesets sources_1]]"
    puts $f "impl_1 status: $status"
    puts $f "impl_1 progress: $progress"
    puts $f "Worst setup path slack ns: $slack"
    puts $f "Worst hold path slack ns: $hslack"
    puts $f "XSA export success: $xsa_ok"
    puts $f "Board/Vitis outcome: SEE separately archived real UART log, NOT claimed here."
    puts $f "Run pairing with tested ELF/Bitstream: TO BE CONFIRMED by project owner."
    close $f
    difi_b6::msg "STAGED routed reports and optional XSA under: $out"
    difi_b6::msg "Do NOT commit .xsa; archive its SHA256 locally and commit the report with version mapping."
    return $out
}
