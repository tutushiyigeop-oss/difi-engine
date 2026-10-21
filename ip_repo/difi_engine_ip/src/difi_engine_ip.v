// CLK_FREQ_HZ must match the actual PL clock.

// Use cfg_samples_per_packet to define input packet boundaries.

// Connect metadata READY at the receiver; tie it high if unused.

module difi_engine_ip #(
    parameter integer CLK_FREQ_HZ = 100_000_000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
        (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI_CTRL:S_AXI_TIME:S_AXIS_IQ:M_AXIS_TX_PKT:S_AXIS_RX_PKT:M_AXIS_IQ, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
        (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWADDR" *)
        (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CTRL, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
    input wire [7:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWPROT" *)
    input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWVALID" *)
    input wire s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL AWREADY" *)
    output wire s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WDATA" *)
    input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WSTRB" *)
    input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WVALID" *)
    input wire s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL WREADY" *)
    output wire s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BRESP" *)
    output wire [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BVALID" *)
    output wire s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL BREADY" *)
    input wire s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARADDR" *)
    input wire [7:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARPROT" *)
    input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARVALID" *)
    input wire s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL ARREADY" *)
    output wire s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RDATA" *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RRESP" *)
    output wire [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RVALID" *)
    output wire s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CTRL RREADY" *)
    input wire s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWADDR" *)
        (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_TIME, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 8" *)
    input wire [7:0] s_axi_time_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWPROT" *)
    input wire [2:0] s_axi_time_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWVALID" *)
    input wire s_axi_time_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME AWREADY" *)
    output wire s_axi_time_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WDATA" *)
    input wire [31:0] s_axi_time_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WSTRB" *)
    input wire [3:0] s_axi_time_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WVALID" *)
    input wire s_axi_time_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME WREADY" *)
    output wire s_axi_time_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME BRESP" *)
    output wire [1:0] s_axi_time_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME BVALID" *)
    output wire s_axi_time_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME BREADY" *)
    input wire s_axi_time_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARADDR" *)
    input wire [7:0] s_axi_time_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARPROT" *)
    input wire [2:0] s_axi_time_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARVALID" *)
    input wire s_axi_time_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME ARREADY" *)
    output wire s_axi_time_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RDATA" *)
    output wire [31:0] s_axi_time_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RRESP" *)
    output wire [1:0] s_axi_time_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RVALID" *)
    output wire s_axi_time_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_TIME RREADY" *)
    input wire s_axi_time_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TDATA" *)
    input wire [31:0] s_axis_iq_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TVALID" *)
    input wire s_axis_iq_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TREADY" *)
    output wire s_axis_iq_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TKEEP" *)
    input wire [3:0] s_axis_iq_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TLAST" *)
    input wire s_axis_iq_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX_PKT TDATA" *)
    output wire [31:0] m_axis_tx_pkt_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX_PKT TVALID" *)
    output wire m_axis_tx_pkt_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX_PKT TREADY" *)
    input wire m_axis_tx_pkt_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX_PKT TKEEP" *)
    output wire [3:0] m_axis_tx_pkt_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_TX_PKT TLAST" *)
    output wire m_axis_tx_pkt_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX_PKT TDATA" *)
    input wire [31:0] s_axis_rx_pkt_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX_PKT TVALID" *)
    input wire s_axis_rx_pkt_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX_PKT TREADY" *)
    output wire s_axis_rx_pkt_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX_PKT TKEEP" *)
    input wire [3:0] s_axis_rx_pkt_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_RX_PKT TLAST" *)
    input wire s_axis_rx_pkt_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_IQ TDATA" *)
    output wire [31:0] m_axis_iq_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_IQ TVALID" *)
    output wire m_axis_iq_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_IQ TREADY" *)
    input wire m_axis_iq_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_IQ TKEEP" *)
    output wire [3:0] m_axis_iq_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_IQ TLAST" *)
    output wire m_axis_iq_tlast,
    
    input wire data_available,
    output wire tx_busy,
    output wire m_data_meta_valid,
    input wire m_data_meta_ready,
    output wire [31:0] m_data_meta_stream_id,
    output wire [3:0] m_data_meta_seq,
    output wire [31:0] m_data_meta_time_sec,
    output wire [63:0] m_data_meta_time_ps,
    output wire [15:0] m_data_meta_sample_count,
    output wire m_ctx_valid,
    input wire m_ctx_ready,
    output wire [31:0] m_ctx_stream_id,
    output wire [3:0] m_ctx_seq,
    output wire [31:0] m_ctx_time_sec,
    output wire [63:0] m_ctx_time_ps,
    output wire m_ctx_changed,
    output wire [31:0] m_ctx_bandwidth_hz,
    output wire [63:0] m_ctx_rf_freq_hz,
    output wire [31:0] m_ctx_sample_rate_hz,
    output wire m_ver_valid,
    input wire m_ver_ready,
    output wire [31:0] m_ver_stream_id,
    output wire [3:0] m_ver_seq,
    output wire [31:0] m_ver_time_sec,
    output wire [63:0] m_ver_time_ps,
    output wire m_ver_changed,
    output wire [31:0] m_ver_info,
    output wire rx_dispatch_error_valid,
    output wire [3:0] rx_dispatch_error_code,
    output wire rx_data_error_valid,
    output wire [3:0] rx_data_error_code,
    output wire rx_context_error_valid,
    output wire [3:0] rx_context_error_code,
    output wire rx_version_error_valid,
    output wire [3:0] rx_version_error_code
);

wire [31:0] time_sec;
wire [63:0] time_ps;
wire time_valid;
wire [31:0] cfg_context_period_ms;
wire [31:0] cfg_version_period_ms;
wire context_periodic_trigger;
wire version_periodic_trigger;
wire time_cfg_load;
wire [31:0] time_cfg_sec;
wire [63:0] time_cfg_ps;

assign m_axis_iq_tkeep = 4'b1111;

difi_time_cfg_regs u_time_cfg_regs (
    .aclk(aclk),
    .aresetn(aresetn),
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

difi_time_source #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ)
) u_time_source (
    .aclk(aclk),
    .aresetn(aresetn),
    .time_load(time_cfg_load),
    .load_time_sec(time_cfg_sec),
    .load_time_ps(time_cfg_ps),
    .time_sec(time_sec),
    .time_ps(time_ps),
    .time_valid(time_valid)
);

difi_periodic_trigger_gen #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ)
) u_periodic_trigger_gen (
    .aclk(aclk),
    .aresetn(aresetn),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms),
    .context_periodic_trigger(context_periodic_trigger),
    .version_periodic_trigger(version_periodic_trigger)
);

difi_engine_top u_engine (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .time_sec(time_sec),
    .time_ps(time_ps),
    .time_valid(time_valid),
    .data_available(data_available),
    .context_periodic_trigger(context_periodic_trigger),
    .version_periodic_trigger(version_periodic_trigger),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms),
    .tx_busy(tx_busy),
    .s_axis_iq_tdata(s_axis_iq_tdata),
    .s_axis_iq_tvalid(s_axis_iq_tvalid),
    .s_axis_iq_tready(s_axis_iq_tready),
    .m_axis_tx_pkt_tdata(m_axis_tx_pkt_tdata),
    .m_axis_tx_pkt_tvalid(m_axis_tx_pkt_tvalid),
    .m_axis_tx_pkt_tready(m_axis_tx_pkt_tready),
    .m_axis_tx_pkt_tkeep(m_axis_tx_pkt_tkeep),
    .m_axis_tx_pkt_tlast(m_axis_tx_pkt_tlast),
    .s_axis_rx_pkt_tdata(s_axis_rx_pkt_tdata),
    .s_axis_rx_pkt_tvalid(s_axis_rx_pkt_tvalid),
    .s_axis_rx_pkt_tready(s_axis_rx_pkt_tready),
    .s_axis_rx_pkt_tkeep(s_axis_rx_pkt_tkeep),
    .s_axis_rx_pkt_tlast(s_axis_rx_pkt_tlast),
    .m_axis_iq_tdata(m_axis_iq_tdata),
    .m_axis_iq_tvalid(m_axis_iq_tvalid),
    .m_axis_iq_tready(m_axis_iq_tready),
    .m_axis_iq_tlast(m_axis_iq_tlast),
    .m_data_meta_valid(m_data_meta_valid),
    .m_data_meta_ready(m_data_meta_ready),
    .m_data_meta_stream_id(m_data_meta_stream_id),
    .m_data_meta_seq(m_data_meta_seq),
    .m_data_meta_time_sec(m_data_meta_time_sec),
    .m_data_meta_time_ps(m_data_meta_time_ps),
    .m_data_meta_sample_count(m_data_meta_sample_count),
    .m_ctx_valid(m_ctx_valid),
    .m_ctx_ready(m_ctx_ready),
    .m_ctx_stream_id(m_ctx_stream_id),
    .m_ctx_seq(m_ctx_seq),
    .m_ctx_time_sec(m_ctx_time_sec),
    .m_ctx_time_ps(m_ctx_time_ps),
    .m_ctx_changed(m_ctx_changed),
    .m_ctx_bandwidth_hz(m_ctx_bandwidth_hz),
    .m_ctx_rf_freq_hz(m_ctx_rf_freq_hz),
    .m_ctx_sample_rate_hz(m_ctx_sample_rate_hz),
    .m_ver_valid(m_ver_valid),
    .m_ver_ready(m_ver_ready),
    .m_ver_stream_id(m_ver_stream_id),
    .m_ver_seq(m_ver_seq),
    .m_ver_time_sec(m_ver_time_sec),
    .m_ver_time_ps(m_ver_time_ps),
    .m_ver_changed(m_ver_changed),
    .m_ver_info(m_ver_info),
    .rx_dispatch_error_valid(rx_dispatch_error_valid),
    .rx_dispatch_error_code(rx_dispatch_error_code),
    .rx_data_error_valid(rx_data_error_valid),
    .rx_data_error_code(rx_data_error_code),
    .rx_context_error_valid(rx_context_error_valid),
    .rx_context_error_code(rx_context_error_code),
    .rx_version_error_valid(rx_version_error_valid),
    .rx_version_error_code(rx_version_error_code)
);

endmodule
