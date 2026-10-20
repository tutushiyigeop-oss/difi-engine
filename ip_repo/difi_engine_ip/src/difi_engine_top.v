// -----------------------------------------------------------------------------
// DIFI 1.1 FPGA Digital IF Protocol Engine - structural top-level
// Interface contract: DIFI_RTL_Interface_Spec_v1_5, section 11.8 / appendix A.10
// Verilog-2001; one aclk / aresetn domain.
//
// Nine frozen RTL blocks; no extra arbitration FSM, FIFO, CDC, timer, UDP stack,
// error merge, or internal TX-to-RX loopback.
// Time source, IQ availability and periodic triggers are external contracts.
// -----------------------------------------------------------------------------
module difi_engine_top (
    // Clock/Reset
    input  wire         aclk,
    input  wire         aresetn,

    // AXI-Lite AW
    input  wire [7:0]   s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,

    // AXI-Lite W
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,

    // AXI-Lite B
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,

    // AXI-Lite AR
    input  wire [7:0]   s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,

    // AXI-Lite R
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    // Time
    input  wire [31:0]  time_sec,
    input  wire [63:0]  time_ps,
    input  wire         time_valid,

    // Schedule
    input  wire         data_available,
    input  wire         context_periodic_trigger,
    input  wire         version_periodic_trigger,
    output wire [31:0]  cfg_context_period_ms,
    output wire [31:0]  cfg_version_period_ms,
    output wire         tx_busy,

    // TX IQ
    input  wire [31:0]  s_axis_iq_tdata,
    input  wire         s_axis_iq_tvalid,
    output wire         s_axis_iq_tready,

    // TX Packet
    output wire [31:0]  m_axis_tx_pkt_tdata,
    output wire         m_axis_tx_pkt_tvalid,
    input  wire         m_axis_tx_pkt_tready,
    output wire [3:0]   m_axis_tx_pkt_tkeep,
    output wire         m_axis_tx_pkt_tlast,

    // RX Packet
    input  wire [31:0]  s_axis_rx_pkt_tdata,
    input  wire         s_axis_rx_pkt_tvalid,
    output wire         s_axis_rx_pkt_tready,
    input  wire [3:0]   s_axis_rx_pkt_tkeep,
    input  wire         s_axis_rx_pkt_tlast,

    // RX IQ
    output wire [31:0]  m_axis_iq_tdata,
    output wire         m_axis_iq_tvalid,
    input  wire         m_axis_iq_tready,
    output wire         m_axis_iq_tlast,

    // RX Data Meta
    output wire         m_data_meta_valid,
    input  wire         m_data_meta_ready,
    output wire [31:0]  m_data_meta_stream_id,
    output wire [3:0]   m_data_meta_seq,
    output wire [31:0]  m_data_meta_time_sec,
    output wire [63:0]  m_data_meta_time_ps,
    output wire [15:0]  m_data_meta_sample_count,

    // RX Context Meta
    output wire         m_ctx_valid,
    input  wire         m_ctx_ready,
    output wire [31:0]  m_ctx_stream_id,
    output wire [3:0]   m_ctx_seq,
    output wire [31:0]  m_ctx_time_sec,
    output wire [63:0]  m_ctx_time_ps,
    output wire         m_ctx_changed,
    output wire [31:0]  m_ctx_bandwidth_hz,
    output wire [63:0]  m_ctx_rf_freq_hz,
    output wire [31:0]  m_ctx_sample_rate_hz,

    // RX Version Meta
    output wire         m_ver_valid,
    input  wire         m_ver_ready,
    output wire [31:0]  m_ver_stream_id,
    output wire [3:0]   m_ver_seq,
    output wire [31:0]  m_ver_time_sec,
    output wire [63:0]  m_ver_time_ps,
    output wire         m_ver_changed,
    output wire [31:0]  m_ver_info,

    // Error Events
    output wire         rx_dispatch_error_valid,
    output wire [3:0]   rx_dispatch_error_code,
    output wire         rx_data_error_valid,
    output wire [3:0]   rx_data_error_code,
    output wire         rx_context_error_valid,
    output wire [3:0]   rx_context_error_code,
    output wire         rx_version_error_valid,
    output wire [3:0]   rx_version_error_code
);

// -----------------------------------------------------------------------------
// 1. Configuration and cross-module control
// -----------------------------------------------------------------------------
wire        tx_enable;
wire        cfg_commit_req;
wire        cfg_commit_ack;
wire        context_change_pending;
wire        context_change_done;

wire [31:0] cfg_data_stream_id;
wire [31:0] cfg_version_stream_id;
wire [15:0] cfg_samples_per_packet;
wire [31:0] cfg_sample_rate_hz;
wire [31:0] cfg_bandwidth_hz;
wire [63:0] cfg_rf_freq_hz;
wire        cfg_rx_data_filter_enable;
wire [31:0] cfg_rx_expected_data_stream_id;
wire        cfg_rx_version_filter_enable;
wire [31:0] cfg_rx_expected_version_stream_id;

// TX generator transaction controls and three independent packet streams.
wire data_pkt_start;
wire data_pkt_busy;
wire data_pkt_done;
wire context_pkt_start;
wire context_pkt_busy;
wire context_pkt_done;
wire version_pkt_start;
wire version_pkt_busy;
wire version_pkt_done;

wire [31:0] data_pkt_tdata;
wire        data_pkt_tvalid;
wire        data_pkt_tready;
wire [3:0]  data_pkt_tkeep;
wire        data_pkt_tlast;

wire [31:0] context_pkt_tdata;
wire        context_pkt_tvalid;
wire        context_pkt_tready;
wire [3:0]  context_pkt_tkeep;
wire        context_pkt_tlast;

wire [31:0] version_pkt_tdata;
wire        version_pkt_tvalid;
wire        version_pkt_tready;
wire [3:0]  version_pkt_tkeep;
wire        version_pkt_tlast;

// RX Dispatch's three independent packet streams; each Parser owns TREADY.
wire [31:0] rx_data_pkt_tdata;
wire        rx_data_pkt_tvalid;
wire        rx_data_pkt_tready;
wire [3:0]  rx_data_pkt_tkeep;
wire        rx_data_pkt_tlast;

wire [31:0] rx_context_pkt_tdata;
wire        rx_context_pkt_tvalid;
wire        rx_context_pkt_tready;
wire [3:0]  rx_context_pkt_tkeep;
wire        rx_context_pkt_tlast;

wire [31:0] rx_version_pkt_tdata;
wire        rx_version_pkt_tvalid;
wire        rx_version_pkt_tready;
wire [3:0]  rx_version_pkt_tkeep;
wire        rx_version_pkt_tlast;

// -----------------------------------------------------------------------------
// 2. AXI4-Lite configuration, active TX config and RX filters
// -----------------------------------------------------------------------------
difi_cfg_regs u_cfg_regs (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .s_axi_awaddr                        (s_axi_awaddr),
    .s_axi_awprot                        (s_axi_awprot),
    .s_axi_awvalid                       (s_axi_awvalid),
    .s_axi_awready                       (s_axi_awready),
    .s_axi_wdata                         (s_axi_wdata),
    .s_axi_wstrb                         (s_axi_wstrb),
    .s_axi_wvalid                        (s_axi_wvalid),
    .s_axi_wready                        (s_axi_wready),
    .s_axi_bresp                         (s_axi_bresp),
    .s_axi_bvalid                        (s_axi_bvalid),
    .s_axi_bready                        (s_axi_bready),
    .s_axi_araddr                        (s_axi_araddr),
    .s_axi_arprot                        (s_axi_arprot),
    .s_axi_arvalid                       (s_axi_arvalid),
    .s_axi_arready                       (s_axi_arready),
    .s_axi_rdata                         (s_axi_rdata),
    .s_axi_rresp                         (s_axi_rresp),
    .s_axi_rvalid                        (s_axi_rvalid),
    .s_axi_rready                        (s_axi_rready),
    .tx_enable                           (tx_enable),
    .cfg_commit_req                      (cfg_commit_req),
    .cfg_commit_ack                      (cfg_commit_ack),
    .context_change_pending              (context_change_pending),
    .context_change_done                 (context_change_done),
    .tx_busy                             (tx_busy),
    .time_valid                          (time_valid),
    .cfg_data_stream_id                  (cfg_data_stream_id),
    .cfg_version_stream_id               (cfg_version_stream_id),
    .cfg_samples_per_packet              (cfg_samples_per_packet),
    .cfg_sample_rate_hz                  (cfg_sample_rate_hz),
    .cfg_bandwidth_hz                    (cfg_bandwidth_hz),
    .cfg_rf_freq_hz                      (cfg_rf_freq_hz),
    .cfg_context_period_ms               (cfg_context_period_ms),
    .cfg_version_period_ms               (cfg_version_period_ms),
    .cfg_rx_data_filter_enable           (cfg_rx_data_filter_enable),
    .cfg_rx_expected_data_stream_id      (cfg_rx_expected_data_stream_id),
    .cfg_rx_version_filter_enable        (cfg_rx_version_filter_enable),
    .cfg_rx_expected_version_stream_id   (cfg_rx_expected_version_stream_id)
);

// -----------------------------------------------------------------------------
// 3. Three independent DIFI transmit generators
// -----------------------------------------------------------------------------
difi_data_packetizer u_data_packetizer (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .pkt_start                           (data_pkt_start),
    .pkt_busy                            (data_pkt_busy),
    .pkt_done                            (data_pkt_done),
    .s_axis_iq_tdata                     (s_axis_iq_tdata),
    .s_axis_iq_tvalid                    (s_axis_iq_tvalid),
    .s_axis_iq_tready                    (s_axis_iq_tready),
    .cfg_data_stream_id                  (cfg_data_stream_id),
    .cfg_samples_per_packet              (cfg_samples_per_packet),
    .time_sec                            (time_sec),
    .time_ps                             (time_ps),
    .time_valid                          (time_valid),
    .m_axis_pkt_tdata                    (data_pkt_tdata),
    .m_axis_pkt_tvalid                   (data_pkt_tvalid),
    .m_axis_pkt_tready                   (data_pkt_tready),
    .m_axis_pkt_tkeep                    (data_pkt_tkeep),
    .m_axis_pkt_tlast                    (data_pkt_tlast)
);

difi_context_generator u_context_generator (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .pkt_start                           (context_pkt_start),
    .pkt_busy                            (context_pkt_busy),
    .pkt_done                            (context_pkt_done),
    .cfg_data_stream_id                  (cfg_data_stream_id),
    .cfg_sample_rate_hz                  (cfg_sample_rate_hz),
    .cfg_bandwidth_hz                    (cfg_bandwidth_hz),
    .cfg_rf_freq_hz                      (cfg_rf_freq_hz),
    .cfg_context_change_pending          (context_change_pending),
    .context_change_done                 (context_change_done),
    .time_sec                            (time_sec),
    .time_ps                             (time_ps),
    .time_valid                          (time_valid),
    .m_axis_pkt_tdata                    (context_pkt_tdata),
    .m_axis_pkt_tvalid                   (context_pkt_tvalid),
    .m_axis_pkt_tready                   (context_pkt_tready),
    .m_axis_pkt_tkeep                    (context_pkt_tkeep),
    .m_axis_pkt_tlast                    (context_pkt_tlast)
);

difi_version_generator u_version_generator (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .pkt_start                           (version_pkt_start),
    .pkt_busy                            (version_pkt_busy),
    .pkt_done                            (version_pkt_done),
    .cfg_version_stream_id               (cfg_version_stream_id),
    .time_sec                            (time_sec),
    .time_ps                             (time_ps),
    .time_valid                          (time_valid),
    .m_axis_pkt_tdata                    (version_pkt_tdata),
    .m_axis_pkt_tvalid                   (version_pkt_tvalid),
    .m_axis_pkt_tready                   (version_pkt_tready),
    .m_axis_pkt_tkeep                    (version_pkt_tkeep),
    .m_axis_pkt_tlast                    (version_pkt_tlast)
);

// -----------------------------------------------------------------------------
// 4. Packet-boundary TX ownership and 3-to-1 AXIS mux
// -----------------------------------------------------------------------------
difi_tx_scheduler u_tx_scheduler (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .tx_enable                           (tx_enable),
    .time_valid                          (time_valid),
    .data_available                      (data_available),
    .cfg_commit_req                      (cfg_commit_req),
    .cfg_commit_ack                      (cfg_commit_ack),
    .context_change_pending              (context_change_pending),
    .context_periodic_trigger            (context_periodic_trigger),
    .version_periodic_trigger            (version_periodic_trigger),
    .data_pkt_start                      (data_pkt_start),
    .data_pkt_busy                       (data_pkt_busy),
    .data_pkt_done                       (data_pkt_done),
    .s_axis_data_tdata                   (data_pkt_tdata),
    .s_axis_data_tvalid                  (data_pkt_tvalid),
    .s_axis_data_tready                  (data_pkt_tready),
    .s_axis_data_tkeep                   (data_pkt_tkeep),
    .s_axis_data_tlast                   (data_pkt_tlast),
    .context_pkt_start                   (context_pkt_start),
    .context_pkt_busy                    (context_pkt_busy),
    .context_pkt_done                    (context_pkt_done),
    .s_axis_context_tdata                (context_pkt_tdata),
    .s_axis_context_tvalid               (context_pkt_tvalid),
    .s_axis_context_tready               (context_pkt_tready),
    .s_axis_context_tkeep                (context_pkt_tkeep),
    .s_axis_context_tlast                (context_pkt_tlast),
    .version_pkt_start                   (version_pkt_start),
    .version_pkt_busy                    (version_pkt_busy),
    .version_pkt_done                    (version_pkt_done),
    .s_axis_version_tdata                (version_pkt_tdata),
    .s_axis_version_tvalid               (version_pkt_tvalid),
    .s_axis_version_tready               (version_pkt_tready),
    .s_axis_version_tkeep                (version_pkt_tkeep),
    .s_axis_version_tlast                (version_pkt_tlast),
    .m_axis_pkt_tdata                    (m_axis_tx_pkt_tdata),
    .m_axis_pkt_tvalid                   (m_axis_tx_pkt_tvalid),
    .m_axis_pkt_tready                   (m_axis_tx_pkt_tready),
    .m_axis_pkt_tkeep                    (m_axis_tx_pkt_tkeep),
    .m_axis_pkt_tlast                    (m_axis_tx_pkt_tlast),
    .tx_busy                             (tx_busy)
);

// -----------------------------------------------------------------------------
// 5. RX packet-type dispatch; route is locked through TLAST
// -----------------------------------------------------------------------------
difi_rx_dispatch u_rx_dispatch (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .s_axis_pkt_tdata                    (s_axis_rx_pkt_tdata),
    .s_axis_pkt_tvalid                   (s_axis_rx_pkt_tvalid),
    .s_axis_pkt_tready                   (s_axis_rx_pkt_tready),
    .s_axis_pkt_tkeep                    (s_axis_rx_pkt_tkeep),
    .s_axis_pkt_tlast                    (s_axis_rx_pkt_tlast),
    .m_data_tdata                        (rx_data_pkt_tdata),
    .m_data_tvalid                       (rx_data_pkt_tvalid),
    .m_data_tready                       (rx_data_pkt_tready),
    .m_data_tkeep                        (rx_data_pkt_tkeep),
    .m_data_tlast                        (rx_data_pkt_tlast),
    .m_context_tdata                     (rx_context_pkt_tdata),
    .m_context_tvalid                    (rx_context_pkt_tvalid),
    .m_context_tready                    (rx_context_pkt_tready),
    .m_context_tkeep                     (rx_context_pkt_tkeep),
    .m_context_tlast                     (rx_context_pkt_tlast),
    .m_version_tdata                     (rx_version_pkt_tdata),
    .m_version_tvalid                    (rx_version_pkt_tvalid),
    .m_version_tready                    (rx_version_pkt_tready),
    .m_version_tkeep                     (rx_version_pkt_tkeep),
    .m_version_tlast                     (rx_version_pkt_tlast),
    .error_valid                         (rx_dispatch_error_valid),
    .error_code                          (rx_dispatch_error_code)
);

// -----------------------------------------------------------------------------
// 6. Three RX protocol parsers and four independent error events
// -----------------------------------------------------------------------------
difi_data_parser u_data_parser (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .s_axis_pkt_tdata                    (rx_data_pkt_tdata),
    .s_axis_pkt_tvalid                   (rx_data_pkt_tvalid),
    .s_axis_pkt_tready                   (rx_data_pkt_tready),
    .s_axis_pkt_tkeep                    (rx_data_pkt_tkeep),
    .s_axis_pkt_tlast                    (rx_data_pkt_tlast),
    .cfg_stream_filter_enable            (cfg_rx_data_filter_enable),
    .cfg_expected_stream_id              (cfg_rx_expected_data_stream_id),
    .m_axis_iq_tdata                     (m_axis_iq_tdata),
    .m_axis_iq_tvalid                    (m_axis_iq_tvalid),
    .m_axis_iq_tready                    (m_axis_iq_tready),
    .m_axis_iq_tlast                     (m_axis_iq_tlast),
    .m_meta_valid                        (m_data_meta_valid),
    .m_meta_ready                        (m_data_meta_ready),
    .m_meta_stream_id                    (m_data_meta_stream_id),
    .m_meta_seq                          (m_data_meta_seq),
    .m_meta_time_sec                     (m_data_meta_time_sec),
    .m_meta_time_ps                      (m_data_meta_time_ps),
    .m_meta_sample_count                 (m_data_meta_sample_count),
    .error_valid                         (rx_data_error_valid),
    .error_code                          (rx_data_error_code)
);

difi_context_parser u_context_parser (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .s_axis_pkt_tdata                    (rx_context_pkt_tdata),
    .s_axis_pkt_tvalid                   (rx_context_pkt_tvalid),
    .s_axis_pkt_tready                   (rx_context_pkt_tready),
    .s_axis_pkt_tkeep                    (rx_context_pkt_tkeep),
    .s_axis_pkt_tlast                    (rx_context_pkt_tlast),
    .cfg_stream_filter_enable            (cfg_rx_data_filter_enable),
    .cfg_expected_stream_id              (cfg_rx_expected_data_stream_id),
    .m_ctx_valid                         (m_ctx_valid),
    .m_ctx_ready                         (m_ctx_ready),
    .m_ctx_stream_id                     (m_ctx_stream_id),
    .m_ctx_seq                           (m_ctx_seq),
    .m_ctx_time_sec                      (m_ctx_time_sec),
    .m_ctx_time_ps                       (m_ctx_time_ps),
    .m_ctx_changed                       (m_ctx_changed),
    .m_ctx_bandwidth_hz                  (m_ctx_bandwidth_hz),
    .m_ctx_rf_freq_hz                    (m_ctx_rf_freq_hz),
    .m_ctx_sample_rate_hz                (m_ctx_sample_rate_hz),
    .error_valid                         (rx_context_error_valid),
    .error_code                          (rx_context_error_code)
);

difi_version_parser u_version_parser (
    .aclk                                (aclk),
    .aresetn                             (aresetn),
    .s_axis_pkt_tdata                    (rx_version_pkt_tdata),
    .s_axis_pkt_tvalid                   (rx_version_pkt_tvalid),
    .s_axis_pkt_tready                   (rx_version_pkt_tready),
    .s_axis_pkt_tkeep                    (rx_version_pkt_tkeep),
    .s_axis_pkt_tlast                    (rx_version_pkt_tlast),
    .cfg_stream_filter_enable            (cfg_rx_version_filter_enable),
    .cfg_expected_stream_id              (cfg_rx_expected_version_stream_id),
    .m_ver_valid                         (m_ver_valid),
    .m_ver_ready                         (m_ver_ready),
    .m_ver_stream_id                     (m_ver_stream_id),
    .m_ver_seq                           (m_ver_seq),
    .m_ver_time_sec                      (m_ver_time_sec),
    .m_ver_time_ps                       (m_ver_time_ps),
    .m_ver_changed                       (m_ver_changed),
    .m_ver_info                          (m_ver_info),
    .error_valid                         (rx_version_error_valid),
    .error_code                          (rx_version_error_code)
);

endmodule
