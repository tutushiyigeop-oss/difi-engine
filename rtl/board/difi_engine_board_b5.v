// -----------------------------------------------------------------------------
// DIFI 1.1 B5 raw-packet export board shell (Zynq-7020, Verilog-2001)
//
// Based on difi_engine_board.v (B4, feature/rtl-integration, 2026-10-14).
// This is a SEPARATE module.  Keep the original B4 source unchanged.
//
// B4: DMA MM2S IQ -> Engine TX -> Engine RX -> DMA S2MM decoded IQ
// B5: DMA MM2S IQ -> Engine TX -------------> DMA S2MM DIFI Packet
//
// Board ports use S_AXIS_IQ for IQ input and M_AXIS_PKT for DIFI packet output.
// Unlike the B4 loopback, B5 exports complete DIFI packet words directly.
// One complete packet per S2MM Simple DMA transfer, delimited by TLAST.
// The DIFI core, AXI-Lite maps and common blocks are unchanged.
//
// IMPORTANT: NO buffering of the TX AXIS packet stream in this shell.
// The AXI DMA S2MM must support backpressure between packets.
// RX parsers are intentionally disconnected; RX metadata counters stay zero.
// -----------------------------------------------------------------------------
module difi_board_raw_packet_export #(
    parameter integer CLK_FREQ_HZ = 100_000_000
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS_IQ:M_AXIS_PKT:S_AXI_CTRL:S_AXI_TIME, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input wire aresetn,

    // S_AXI_CTRL: original DIFI configuration slave, offset 0x00..0xFF
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CTRL, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
    input  wire [7:0]  s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWPROT" *)
    input  wire [2:0]  s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWREADY" *)
    output wire        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WSTRB" *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WVALID" *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WREADY" *)
    output wire        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BRESP" *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BVALID" *)
    output wire        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BREADY" *)
    input  wire        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARADDR" *)
    input  wire [7:0]  s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARPROT" *)
    input  wire [2:0]  s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARREADY" *)
    output wire        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RRESP" *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RVALID" *)
    output wire        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RREADY" *)
    input  wire        s_axi_rready,

    // S_AXI_TIME: separate v1.7 time initialization slave
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_TIME, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
    input  wire [7:0]  s_axi_time_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWPROT" *)
    input  wire [2:0]  s_axi_time_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWVALID" *)
    input  wire        s_axi_time_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWREADY" *)
    output wire        s_axi_time_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WDATA" *)
    input  wire [31:0] s_axi_time_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WSTRB" *)
    input  wire [3:0]  s_axi_time_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WVALID" *)
    input  wire        s_axi_time_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WREADY" *)
    output wire        s_axi_time_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME BRESP" *)
    output wire [1:0]  s_axi_time_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME BVALID" *)
    output wire        s_axi_time_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME BREADY" *)
    input  wire        s_axi_time_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARADDR" *)
    input  wire [7:0]  s_axi_time_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARPROT" *)
    input  wire [2:0]  s_axi_time_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARVALID" *)
    input  wire        s_axi_time_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARREADY" *)
    output wire        s_axi_time_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RDATA" *)
    output wire [31:0] s_axi_time_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RRESP" *)
    output wire [1:0]  s_axi_time_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RVALID" *)
    output wire        s_axi_time_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RREADY" *)
    input  wire        s_axi_time_rready,

    // Original MM2S IQ input; TKEEP/TLAST are unused by the IQ packetizer.
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TDATA" *)
    input wire [31:0] s_axis_iq_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TVALID" *)
    input wire        s_axis_iq_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TREADY" *)
    output wire       s_axis_iq_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TKEEP" *)
    input wire [3:0]  s_axis_iq_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TLAST" *)
    input wire        s_axis_iq_tlast,

    // B5 raw DIFI packet AXI4-Stream to DMA S2MM (not decoded IQ).
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TDATA" *)
    output wire [31:0] m_axis_pkt_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TVALID" *)
    output wire        m_axis_pkt_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TREADY" *)
    input wire         m_axis_pkt_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TKEEP" *)
    output wire [3:0]  m_axis_pkt_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TLAST" *)
    output wire        m_axis_pkt_tlast,

    // Unchanged two-channel AXI GPIO debug port.
    input wire [4:0]   dbg_page,
    output reg [31:0] dbg_rdata
);

// -----------------------------------------------------------------------------
// 1. Time configuration, time source, and periodic triggers (same as B4).
// -----------------------------------------------------------------------------
wire [31:0] time_sec;
wire [63:0] time_ps;
wire        time_valid;
wire [31:0] cfg_context_period_ms;
wire [31:0] cfg_version_period_ms;
wire        context_periodic_trigger;
wire        version_periodic_trigger;
wire        tx_busy;
wire        time_cfg_load;
wire [31:0] time_cfg_sec;
wire [63:0] time_cfg_ps;

difi_time_cfg_regs u_time_cfg_regs (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(s_axi_time_awaddr),
    .s_axi_awprot(s_axi_time_awprot),
    .s_axi_awvalid(s_axi_time_awvalid),
    .s_axi_awready(s_axi_time_awready),
    .s_axi_wdata(s_axi_time_wdata),
    .s_axi_wstrb(s_axi_time_wstrb),
    .s_axi_wvalid(s_axi_time_wvalid),
    .s_axi_wready(s_axi_time_wready),
    .s_axi_bresp(s_axi_time_bresp),
    .s_axi_bvalid(s_axi_time_bvalid),
    .s_axi_bready(s_axi_time_bready),
    .s_axi_araddr(s_axi_time_araddr),
    .s_axi_arprot(s_axi_time_arprot),
    .s_axi_arvalid(s_axi_time_arvalid),
    .s_axi_arready(s_axi_time_arready),
    .s_axi_rdata(s_axi_time_rdata),
    .s_axi_rresp(s_axi_time_rresp),
    .s_axi_rvalid(s_axi_time_rvalid),
    .s_axi_rready(s_axi_time_rready),
    .time_load(time_cfg_load),
    .load_time_sec(time_cfg_sec),
    .load_time_ps(time_cfg_ps),
    .time_valid(time_valid)
);

difi_time_source #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) u_time_source (
    .aclk(aclk), .aresetn(aresetn),
    .time_load(time_cfg_load),
    .load_time_sec(time_cfg_sec),
    .load_time_ps(time_cfg_ps),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid)
);

difi_periodic_trigger_gen #(.CLK_FREQ_HZ(CLK_FREQ_HZ))
    u_periodic_trigger_gen (
    .aclk(aclk), .aresetn(aresetn),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms),
    .context_periodic_trigger(context_periodic_trigger),
    .version_periodic_trigger(version_periodic_trigger)
);

// -----------------------------------------------------------------------------
// 2. Raw export. TX -> S2MM; RX Packet input disabled.
// -----------------------------------------------------------------------------
wire [31:0] tx_pkt_tdata;
wire        tx_pkt_tvalid;
wire        tx_pkt_tready;
wire [3:0]  tx_pkt_tkeep;
wire        tx_pkt_tlast;
wire        tx_pkt_handshake = tx_pkt_tvalid && tx_pkt_tready;

assign m_axis_pkt_tdata  = tx_pkt_tdata;
assign m_axis_pkt_tvalid = tx_pkt_tvalid;
assign m_axis_pkt_tkeep  = tx_pkt_tkeep;
assign m_axis_pkt_tlast  = tx_pkt_tlast;
assign tx_pkt_tready    = m_axis_pkt_tready;

// RX metadata/error wires stay connected to the legacy GPIO monitor.
// They do not fire in B5 since the RX stream is inactive.
wire data_meta_valid;
wire [31:0] data_meta_sid, data_meta_sec;
wire [3:0] data_meta_seq;
wire [63:0] data_meta_ps;
wire [15:0] data_meta_samples;
wire ctx_meta_valid, ctx_changed;
wire [31:0] ctx_sid, ctx_sec, ctx_bw, ctx_fs;
wire [3:0] ctx_seq;
wire [63:0] ctx_ps, ctx_rf;
wire ver_meta_valid, ver_changed;
wire [31:0] ver_sid, ver_sec, ver_info;
wire [3:0] ver_seq;
wire [63:0] ver_ps;
wire e_dispatch, e_data, e_ctx, e_ver;
wire [3:0] e_dispatch_code, e_data_code, e_ctx_code, e_ver_code;

difi_engine_top u_engine (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
    .data_available(s_axis_iq_tvalid),
    .context_periodic_trigger(context_periodic_trigger),
    .version_periodic_trigger(version_periodic_trigger),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms),
    .tx_busy(tx_busy),

    .s_axis_iq_tdata(s_axis_iq_tdata),
    .s_axis_iq_tvalid(s_axis_iq_tvalid),
    .s_axis_iq_tready(s_axis_iq_tready),
    .m_axis_tx_pkt_tdata(tx_pkt_tdata),
    .m_axis_tx_pkt_tvalid(tx_pkt_tvalid),
    .m_axis_tx_pkt_tready(tx_pkt_tready),
    .m_axis_tx_pkt_tkeep(tx_pkt_tkeep),
    .m_axis_tx_pkt_tlast(tx_pkt_tlast),

    // A deliberately empty RX stream: B5 tests TX interoperability only.
    .s_axis_rx_pkt_tdata(32'd0),
    .s_axis_rx_pkt_tvalid(1'b0),
    .s_axis_rx_pkt_tready(),
    .s_axis_rx_pkt_tkeep(4'b0000),
    .s_axis_rx_pkt_tlast(1'b0),
    .m_axis_iq_tdata(),
    .m_axis_iq_tvalid(),
    .m_axis_iq_tready(1'b1),
    .m_axis_iq_tlast(),

    .m_data_meta_valid(data_meta_valid), .m_data_meta_ready(1'b1),
    .m_data_meta_stream_id(data_meta_sid),
    .m_data_meta_seq(data_meta_seq),
    .m_data_meta_time_sec(data_meta_sec),
    .m_data_meta_time_ps(data_meta_ps),
    .m_data_meta_sample_count(data_meta_samples),
    .m_ctx_valid(ctx_meta_valid), .m_ctx_ready(1'b1),
    .m_ctx_stream_id(ctx_sid), .m_ctx_seq(ctx_seq),
    .m_ctx_time_sec(ctx_sec), .m_ctx_time_ps(ctx_ps),
    .m_ctx_changed(ctx_changed),
    .m_ctx_bandwidth_hz(ctx_bw),
    .m_ctx_rf_freq_hz(ctx_rf),
    .m_ctx_sample_rate_hz(ctx_fs),
    .m_ver_valid(ver_meta_valid), .m_ver_ready(1'b1),
    .m_ver_stream_id(ver_sid), .m_ver_seq(ver_seq),
    .m_ver_time_sec(ver_sec), .m_ver_time_ps(ver_ps),
    .m_ver_changed(ver_changed), .m_ver_info(ver_info),
    .rx_dispatch_error_valid(e_dispatch),
    .rx_dispatch_error_code(e_dispatch_code),
    .rx_data_error_valid(e_data), .rx_data_error_code(e_data_code),
    .rx_context_error_valid(e_ctx),
    .rx_context_error_code(e_ctx_code),
    .rx_version_error_valid(e_ver),
    .rx_version_error_code(e_ver_code)
);

// -----------------------------------------------------------------------------
// 3. B4-compatible AXI GPIO monitor (5-bit page and 32-bit snapshot).
// Page 29/30 count *actual TX Packet AXIS handshakes* in both B4 and B5.
// RX-related pages 1..28 remain zero in B5 by design.
// -----------------------------------------------------------------------------
reg [31:0] tx_packet_count, tx_beat_count;
reg [31:0] cnt_data, cnt_ctx, cnt_ver;
reg [31:0] cnt_e_dispatch, cnt_e_data, cnt_e_ctx, cnt_e_ver;
reg [31:0] last_error;
reg [31:0] m_data_sid, m_data_sec, m_data_ps_hi, m_data_ps_lo;
reg [3:0]  m_data_seq;
reg [15:0] m_data_samples;
reg [31:0] m_ctx_sid, m_ctx_sec, m_ctx_ps_hi, m_ctx_ps_lo;
reg [3:0]  m_ctx_seq;
reg        m_ctx_changed;
reg [31:0] m_ctx_bw, m_ctx_rf_hi, m_ctx_rf_lo, m_ctx_fs;
reg [31:0] m_ver_sid, m_ver_sec, m_ver_ps_hi, m_ver_ps_lo;
reg [3:0]  m_ver_seq;
reg        m_ver_changed;
reg [31:0] m_ver_info;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        tx_packet_count <= 0; tx_beat_count <= 0;
        cnt_data <= 0; cnt_ctx <= 0; cnt_ver <= 0;
        cnt_e_dispatch <= 0; cnt_e_data <= 0;
        cnt_e_ctx <= 0; cnt_e_ver <= 0;
        last_error <= 0;
        m_data_sid <= 0; m_data_seq <= 0; m_data_samples <= 0;
        m_data_sec <= 0; m_data_ps_hi <= 0; m_data_ps_lo <= 0;
        m_ctx_sid <= 0; m_ctx_seq <= 0; m_ctx_changed <= 0;
        m_ctx_sec <= 0; m_ctx_ps_hi <= 0; m_ctx_ps_lo <= 0;
        m_ctx_bw <= 0; m_ctx_rf_hi <= 0; m_ctx_rf_lo <= 0; m_ctx_fs <= 0;
        m_ver_sid <= 0; m_ver_seq <= 0; m_ver_changed <= 0;
        m_ver_sec <= 0; m_ver_ps_hi <= 0; m_ver_ps_lo <= 0;
        m_ver_info <= 0;
    end else begin
        if (tx_pkt_handshake) begin
            tx_beat_count <= tx_beat_count + 1'b1;
            if (tx_pkt_tlast)
                tx_packet_count <= tx_packet_count + 1'b1;
        end
        if (data_meta_valid) begin
            cnt_data <= cnt_data + 1'b1;
            m_data_sid <= data_meta_sid;
            m_data_seq <= data_meta_seq;
            m_data_samples <= data_meta_samples;
            m_data_sec <= data_meta_sec;
            m_data_ps_hi <= data_meta_ps[63:32];
            m_data_ps_lo <= data_meta_ps[31:0];
        end
        if (ctx_meta_valid) begin
            cnt_ctx <= cnt_ctx + 1'b1;
            m_ctx_sid <= ctx_sid;
            m_ctx_seq <= ctx_seq;
            m_ctx_changed <= ctx_changed;
            m_ctx_sec <= ctx_sec;
            m_ctx_ps_hi <= ctx_ps[63:32];
            m_ctx_ps_lo <= ctx_ps[31:0];
            m_ctx_bw <= ctx_bw;
            m_ctx_rf_hi <= ctx_rf[63:32];
            m_ctx_rf_lo <= ctx_rf[31:0];
            m_ctx_fs <= ctx_fs;
        end
        if (ver_meta_valid) begin
            cnt_ver <= cnt_ver + 1'b1;
            m_ver_sid <= ver_sid;
            m_ver_seq <= ver_seq;
            m_ver_changed <= ver_changed;
            m_ver_sec <= ver_sec;
            m_ver_ps_hi <= ver_ps[63:32];
            m_ver_ps_lo <= ver_ps[31:0];
            m_ver_info <= ver_info;
        end
        if (e_dispatch) begin
            cnt_e_dispatch <= cnt_e_dispatch + 1'b1;
            last_error <= {20'd0, 4'd1, 4'd0, e_dispatch_code};
        end
        if (e_data) begin
            cnt_e_data <= cnt_e_data + 1'b1;
            last_error <= {20'd0, 4'd2, 4'd0, e_data_code};
        end
        if (e_ctx) begin
            cnt_e_ctx <= cnt_e_ctx + 1'b1;
            last_error <= {20'd0, 4'd3, 4'd0, e_ctx_code};
        end
        if (e_ver) begin
            cnt_e_ver <= cnt_e_ver + 1'b1;
            last_error <= {20'd0, 4'd4, 4'd0, e_ver_code};
        end
    end
end

always @(*) begin
    dbg_rdata = 32'd0;
    case (dbg_page)
        5'd0:  dbg_rdata = 32'hD1F100B5; // B5 build signature
        5'd1:  dbg_rdata = cnt_data;
        5'd2:  dbg_rdata = cnt_ctx;
        5'd3:  dbg_rdata = cnt_ver;
        5'd4:  dbg_rdata = cnt_e_dispatch;
        5'd5:  dbg_rdata = cnt_e_data;
        5'd6:  dbg_rdata = cnt_e_ctx;
        5'd7:  dbg_rdata = cnt_e_ver;
        5'd8:  dbg_rdata = last_error;
        5'd9:  dbg_rdata = m_data_sid;
        5'd10: dbg_rdata = {12'd0, m_data_samples, m_data_seq};
        5'd11: dbg_rdata = m_data_sec;
        5'd12: dbg_rdata = m_data_ps_hi;
        5'd13: dbg_rdata = m_data_ps_lo;
        5'd14: dbg_rdata = m_ctx_sid;
        5'd15: dbg_rdata = {27'd0, m_ctx_changed, m_ctx_seq};
        5'd16: dbg_rdata = m_ctx_bw;
        5'd17: dbg_rdata = m_ctx_rf_hi;
        5'd18: dbg_rdata = m_ctx_rf_lo;
        5'd19: dbg_rdata = m_ctx_fs;
        5'd20: dbg_rdata = m_ctx_sec;
        5'd21: dbg_rdata = m_ctx_ps_hi;
        5'd22: dbg_rdata = m_ctx_ps_lo;
        5'd23: dbg_rdata = m_ver_sid;
        5'd24: dbg_rdata = {27'd0, m_ver_changed, m_ver_seq};
        5'd25: dbg_rdata = m_ver_info;
        5'd26: dbg_rdata = m_ver_sec;
        5'd27: dbg_rdata = m_ver_ps_hi;
        5'd28: dbg_rdata = m_ver_ps_lo;
        5'd29: dbg_rdata = tx_packet_count;
        5'd30: dbg_rdata = tx_beat_count;
        5'd31: dbg_rdata = 32'hD1F1F01F;
        default: dbg_rdata = 32'd0;
    endcase
end
endmodule
