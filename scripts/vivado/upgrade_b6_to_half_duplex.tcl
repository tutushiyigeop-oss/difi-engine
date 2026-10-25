# Stage D prototype: patch an OPEN B6 v0.2 block design into a shared-bitstream,
# dual-DMA, software-time-multiplexed DIFI engine hardware platform.
# Intended for Vivado 2024.2. NOT a prevalidated routed implementation.
# Must be sourced from within an expendable COPY/clean rebuild of the B6 BD.
# The original B6 source/XSA/bitstream should remain unchanged.
#
# From repo root after opening a copied B6 project/BD:
#   source scripts/vivado/upgrade_b6_to_half_duplex.tcl
#
# New address map: 0x40000000 CTRL; 0x40001000 TIME; 0x40400000
# RX DMA0; 0x40410000 TX DMA1; 0x41200000 B6 RX metadata monitor GPIO.

set here [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $here .. ..]]
set tap_file [file join $repo_root rtl board difi_iq_axis_tap.v]
if {![file exists $tap_file]} {
    error "StageD: Missing RTL file: $tap_file"
}
if {[llength [get_projects -quiet]] != 1} {
    error "StageD: Open exactly one Vivado project with the B6 v0.2 BD first"
}
set old_bd [current_bd_design]
if {$old_bd eq ""} {
    error "StageD: Open B6 Block Design in Vivado before sourcing this patch"
}
current_bd_instance /
foreach c {difi_engine_ip_0 axi_dma_0 axi_smc axi_mem_intercon processing_system7_0 rst_ps7_0_100M difi_b6_rx_meta_moni_0 axi_gpio_0} {
    if {[llength [get_bd_cells -quiet $c]] != 1} {
        error "StageD: Wrong BD or missing cell: $c"
    }
}
foreach c {axi_dma_1 difi_iq_axis_tap_0} {
    if {[llength [get_bd_cells -quiet $c]]} {
        error "StageD: Cell $c already exists; do not apply patch twice"
    }
}
if {[llength [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins -quiet difi_engine_ip_0/S_AXIS_IQ]]]} {
    error "StageD: DIFI S_AXIS_IQ already has an AXIS connection"
}
if {[llength [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins -quiet difi_engine_ip_0/M_AXIS_TX_PKT]]]} {
    error "StageD: DIFI M_AXIS_TX_PKT already has an AXIS connection"
}

# Add standalone protocol-neutral module WITHOUT editing the packaged IP.
add_files -norecurse -fileset sources_1 $tap_file
update_compile_order -fileset sources_1

# B6 has both scalar pins tied to constant-low. Free them BEFORE connecting
# the now-live stream interface and the activity tap.
foreach pin {difi_engine_ip_0/data_available difi_engine_ip_0/s_axis_iq_tvalid} {
    set pin_obj [get_bd_pins -quiet $pin]
    if {[llength $pin_obj] != 1} { error "StageD: Missing pin $pin" }
    set attached_net [get_bd_nets -quiet -of_objects $pin_obj]
    if {[llength $attached_net] > 1} { error "StageD: Multiple unexpected scalar nets on $pin" }
    if {[llength $attached_net] == 1} {
        disconnect_bd_net $attached_net $pin_obj
    }
}

# GP0 -> 5 AXI-Lite registers; HP0 <- 4 DMA memory-mapped master ports.
set_property CONFIG.NUM_MI {5} [get_bd_cells axi_smc]
set_property CONFIG.NUM_SI {4} [get_bd_cells axi_mem_intercon]

set dma1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_1]
set_property CONFIG.c_include_sg {0} $dma1
set tap [create_bd_cell -type module -reference difi_iq_axis_tap difi_iq_axis_tap_0]
if {[llength $tap] != 1} { error "StageD: IQ axis tap creation failed" }

# Control: AXI-Lite for TX DMA1; leave existing RX DMA0 and monitor intact.
connect_bd_intf_net [get_bd_intf_pins axi_smc/M04_AXI] [get_bd_intf_pins axi_dma_1/S_AXI_LITE]

# TX path: DDR -> TX DMA1 -> IQ Tap -> DIFI packetizer -> TX DMA1 -> DDR.
connect_bd_intf_net [get_bd_intf_pins axi_dma_1/M_AXIS_MM2S] [get_bd_intf_pins difi_iq_axis_tap_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins difi_iq_axis_tap_0/M_AXIS] [get_bd_intf_pins difi_engine_ip_0/S_AXIS_IQ]
connect_bd_intf_net [get_bd_intf_pins difi_engine_ip_0/M_AXIS_TX_PKT] [get_bd_intf_pins axi_dma_1/S_AXIS_S2MM]
connect_bd_net [get_bd_pins difi_iq_axis_tap_0/data_available] [get_bd_pins difi_engine_ip_0/data_available]

# Both TX DMA memory channels use existing AXI_HP0 via expanded interconnect.
connect_bd_intf_net [get_bd_intf_pins axi_dma_1/M_AXI_MM2S] [get_bd_intf_pins axi_mem_intercon/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_1/M_AXI_S2MM] [get_bd_intf_pins axi_mem_intercon/S03_AXI]

# All Stage D PL components stay on the proven 100 MHz FCLK0 / reset domain.
set clk0 [get_bd_pins processing_system7_0/FCLK_CLK0]
foreach pin {
    axi_dma_1/s_axi_lite_aclk
    axi_dma_1/m_axi_mm2s_aclk
    axi_dma_1/m_axi_s2mm_aclk
    axi_mem_intercon/S02_ACLK
    axi_mem_intercon/S03_ACLK
    difi_iq_axis_tap_0/aclk
} {
    if {[llength [get_bd_pins -quiet $pin]] != 1} { error "StageD: Missing clock pin $pin" }
    connect_bd_net $clk0 [get_bd_pins $pin]
}
set rstn [get_bd_pins rst_ps7_0_100M/peripheral_aresetn]
foreach pin {
    axi_dma_1/axi_resetn
    axi_mem_intercon/S02_ARESETN
    axi_mem_intercon/S03_ARESETN
    difi_iq_axis_tap_0/aresetn
} {
    if {[llength [get_bd_pins -quiet $pin]] != 1} { error "StageD: Missing reset pin $pin" }
    connect_bd_net $rstn [get_bd_pins $pin]
}

# Do not modify the proven RX DMA0, DIFI CTRL/TIME, or B6 monitor addresses.
assign_bd_address -offset 0x40410000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces processing_system7_0/Data] \
    [get_bd_addr_segs axi_dma_1/S_AXI_LITE/Reg] -force
assign_bd_address -offset 0x00000000 -range 0x40000000 \
    -target_address_space [get_bd_addr_spaces axi_dma_1/Data_MM2S] \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force
assign_bd_address -offset 0x00000000 -range 0x40000000 \
    -target_address_space [get_bd_addr_spaces axi_dma_1/Data_S2MM] \
    [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM] -force

# Prefer hard failures. IP Integrator validation does not prove functionality.
validate_bd_design
save_bd_design
puts "StageD: BD patch and validation returned. Next: generate output products, synthesize, route, check timing, bitstream and XSA."
