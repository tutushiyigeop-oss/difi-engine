// Each DIFI packet ends with TLAST; the PS must rearm S2MM for each packet.

module difi_engine_board_b1 (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS_IQ:M_AXIS_PKT:S_AXI_CTRL, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input wire aresetn,

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

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TDATA" *)
    input  wire [31:0] s_axis_iq_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TVALID" *)
    input  wire        s_axis_iq_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TREADY" *)
    output wire        s_axis_iq_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TKEEP" *)
    input  wire [3:0]  s_axis_iq_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TLAST" *)
    input  wire        s_axis_iq_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TDATA" *)
    output wire [31:0] m_axis_pkt_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TVALID" *)
    output wire        m_axis_pkt_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TREADY" *)
    input  wire        m_axis_pkt_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TKEEP" *)
    output wire [3:0]  m_axis_pkt_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TLAST" *)
    output wire        m_axis_pkt_tlast,

    output wire tx_busy
);

    // This test uses fixed time, not real UTC.
    localparam [31:0] TEST_TIME_SEC = 32'd1700000000; 
    localparam [63:0] TEST_TIME_PS  = 64'd0;

    wire data_available = s_axis_iq_tvalid;
    wire [31:0] unused_context_period_ms;
    wire [31:0] unused_version_period_ms;

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

        .time_sec(TEST_TIME_SEC),
        .time_ps(TEST_TIME_PS),
        .time_valid(1'b1),
        .data_available(data_available),
        .context_periodic_trigger(1'b0),
        .version_periodic_trigger(1'b0),
        .cfg_context_period_ms(unused_context_period_ms),
        .cfg_version_period_ms(unused_version_period_ms),
        .tx_busy(tx_busy),

        .s_axis_iq_tdata(s_axis_iq_tdata),
        .s_axis_iq_tvalid(s_axis_iq_tvalid),
        .s_axis_iq_tready(s_axis_iq_tready),
        .m_axis_tx_pkt_tdata(m_axis_pkt_tdata),
        .m_axis_tx_pkt_tvalid(m_axis_pkt_tvalid),
        .m_axis_tx_pkt_tready(m_axis_pkt_tready),
        .m_axis_tx_pkt_tkeep(m_axis_pkt_tkeep),
        .m_axis_tx_pkt_tlast(m_axis_pkt_tlast),

        .s_axis_rx_pkt_tdata(32'd0),
        .s_axis_rx_pkt_tvalid(1'b0),
        .s_axis_rx_pkt_tready(),
        .s_axis_rx_pkt_tkeep(4'h0),
        .s_axis_rx_pkt_tlast(1'b0),
        .m_axis_iq_tdata(),
        .m_axis_iq_tvalid(),
        .m_axis_iq_tready(1'b1),
        .m_axis_iq_tlast(),

        .m_data_meta_valid(),
        .m_data_meta_ready(1'b1),
        .m_data_meta_stream_id(),
        .m_data_meta_seq(),
        .m_data_meta_time_sec(),
        .m_data_meta_time_ps(),
        .m_data_meta_sample_count(),
        .m_ctx_valid(),
        .m_ctx_ready(1'b1),
        .m_ctx_stream_id(),
        .m_ctx_seq(),
        .m_ctx_time_sec(),
        .m_ctx_time_ps(),
        .m_ctx_changed(),
        .m_ctx_bandwidth_hz(),
        .m_ctx_rf_freq_hz(),
        .m_ctx_sample_rate_hz(),
        .m_ver_valid(),
        .m_ver_ready(1'b1),
        .m_ver_stream_id(),
        .m_ver_seq(),
        .m_ver_time_sec(),
        .m_ver_time_ps(),
        .m_ver_changed(),
        .m_ver_info(),
        .rx_dispatch_error_valid(),
        .rx_dispatch_error_code(),
        .rx_data_error_valid(),
        .rx_data_error_code(),
        .rx_context_error_valid(),
        .rx_context_error_code(),
        .rx_version_error_valid(),
        .rx_version_error_code()
    );

    // B1 does not use input IQ TKEEP/TLAST.
    // Each IQ word is 4 bytes, with a fixed 256 samples per packet.
    
endmodule
