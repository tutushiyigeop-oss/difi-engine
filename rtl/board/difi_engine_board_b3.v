// Enable TX through AXI4-Lite after committing the configuration.
module difi_engine_board_b3 (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS_IQ:M_AXIS_IQ:S_AXI_CTRL, ASSOCIATED_RESET aresetn" *)
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
    input wire [31:0] s_axis_iq_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TVALID" *)
    input wire s_axis_iq_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TREADY" *)
    output wire s_axis_iq_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TKEEP" *)
    input wire [3:0] s_axis_iq_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_IQ TLAST" *)
    input wire s_axis_iq_tlast,

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

    input wire [4:0] dbg_page,
    output reg [31:0] dbg_rdata
);

assign m_axis_iq_tkeep = 4'b1111;

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
wire [31:0] unused_context_period, unused_version_period;
wire unused_tx_busy;

wire [31:0] loop_pkt_tdata;
wire        loop_pkt_tvalid;
wire        loop_pkt_tready;
wire [3:0]  loop_pkt_tkeep;
wire        loop_pkt_tlast;
wire        loop_pkt_hs = loop_pkt_tvalid && loop_pkt_tready;
reg  [31:0] tx_packet_count, tx_beat_count;

difi_engine_top u_engine (
  .aclk(aclk), .aresetn(aresetn),
  .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
  .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
  .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
  .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
  .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
  .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
  .s_axi_arprot(s_axi_arprot), .s_axi_arvalid(s_axi_arvalid),
  .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
  .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
  .s_axi_rready(s_axi_rready),

  .time_sec(32'h6553F100), .time_ps(64'd0), .time_valid(1'b1),
  .data_available(s_axis_iq_tvalid), .context_periodic_trigger(1'b0),
  .version_periodic_trigger(1'b0),
  .cfg_context_period_ms(unused_context_period),
  .cfg_version_period_ms(unused_version_period), .tx_busy(unused_tx_busy),

  .s_axis_iq_tdata(s_axis_iq_tdata), .s_axis_iq_tvalid(s_axis_iq_tvalid),
  .s_axis_iq_tready(s_axis_iq_tready),
  .m_axis_tx_pkt_tdata(loop_pkt_tdata),
  .m_axis_tx_pkt_tvalid(loop_pkt_tvalid),
  .m_axis_tx_pkt_tready(loop_pkt_tready),
  .m_axis_tx_pkt_tkeep(loop_pkt_tkeep),
  .m_axis_tx_pkt_tlast(loop_pkt_tlast),

  .s_axis_rx_pkt_tdata(loop_pkt_tdata),
  .s_axis_rx_pkt_tvalid(loop_pkt_tvalid),
  .s_axis_rx_pkt_tready(loop_pkt_tready),
  .s_axis_rx_pkt_tkeep(loop_pkt_tkeep),
  .s_axis_rx_pkt_tlast(loop_pkt_tlast),

  .m_axis_iq_tdata(m_axis_iq_tdata),
  .m_axis_iq_tvalid(m_axis_iq_tvalid),
  .m_axis_iq_tready(m_axis_iq_tready),
  .m_axis_iq_tlast(m_axis_iq_tlast),

  .m_data_meta_valid(data_meta_valid), .m_data_meta_ready(1'b1),
  .m_data_meta_stream_id(data_meta_sid), .m_data_meta_seq(data_meta_seq),
  .m_data_meta_time_sec(data_meta_sec), .m_data_meta_time_ps(data_meta_ps),
  .m_data_meta_sample_count(data_meta_samples),
  .m_ctx_valid(ctx_meta_valid), .m_ctx_ready(1'b1),
  .m_ctx_stream_id(ctx_sid), .m_ctx_seq(ctx_seq),
  .m_ctx_time_sec(ctx_sec), .m_ctx_time_ps(ctx_ps),
  .m_ctx_changed(ctx_changed), .m_ctx_bandwidth_hz(ctx_bw),
  .m_ctx_rf_freq_hz(ctx_rf), .m_ctx_sample_rate_hz(ctx_fs),
  .m_ver_valid(ver_meta_valid), .m_ver_ready(1'b1),
  .m_ver_stream_id(ver_sid), .m_ver_seq(ver_seq),
  .m_ver_time_sec(ver_sec), .m_ver_time_ps(ver_ps),
  .m_ver_changed(ver_changed), .m_ver_info(ver_info),
  .rx_dispatch_error_valid(e_dispatch),
  .rx_dispatch_error_code(e_dispatch_code),
  .rx_data_error_valid(e_data), .rx_data_error_code(e_data_code),
  .rx_context_error_valid(e_ctx), .rx_context_error_code(e_ctx_code),
  .rx_version_error_valid(e_ver), .rx_version_error_code(e_ver_code)
);

reg [31:0] cnt_data, cnt_ctx, cnt_ver;
reg [31:0] cnt_e_dispatch, cnt_e_data, cnt_e_ctx, cnt_e_ver;
reg [31:0] last_error;
reg [31:0] m_data_sid, m_data_sec, m_data_ps_hi, m_data_ps_lo;
reg [3:0] m_data_seq;
reg [15:0] m_data_samples;
reg [31:0] m_ctx_sid, m_ctx_sec, m_ctx_ps_hi, m_ctx_ps_lo;
reg [3:0] m_ctx_seq;
reg m_ctx_changed;
reg [31:0] m_ctx_bw, m_ctx_rf_hi, m_ctx_rf_lo, m_ctx_fs;
reg [31:0] m_ver_sid, m_ver_sec, m_ver_ps_hi, m_ver_ps_lo;
reg [3:0] m_ver_seq;
reg m_ver_changed;
reg [31:0] m_ver_info;

always @(posedge aclk or negedge aresetn) begin
  if (!aresetn) begin
    cnt_data <= 0; cnt_ctx <= 0; cnt_ver <= 0;
    tx_packet_count <= 0; tx_beat_count <= 0;
    cnt_e_dispatch <= 0; cnt_e_data <= 0;
    cnt_e_ctx <= 0; cnt_e_ver <= 0;
    last_error <= 0;
    m_data_sid <= 0; m_data_seq <= 0; m_data_samples <= 0;
    m_data_sec <= 0; m_data_ps_hi <= 0; m_data_ps_lo <= 0;
    m_ctx_sid <= 0; m_ctx_seq <= 0; m_ctx_changed <= 0;
    m_ctx_sec <= 0; m_ctx_ps_hi <= 0; m_ctx_ps_lo <= 0;
    m_ctx_bw <= 0; m_ctx_rf_hi <= 0; m_ctx_rf_lo <= 0; m_ctx_fs <= 0;
    m_ver_sid <= 0; m_ver_seq <= 0; m_ver_changed <= 0;
    m_ver_sec <= 0; m_ver_ps_hi <= 0; m_ver_ps_lo <= 0; m_ver_info <= 0;
  end else begin
    if (loop_pkt_hs) begin
      tx_beat_count <= tx_beat_count + 1'b1;
      if (loop_pkt_tlast) tx_packet_count <= tx_packet_count + 1'b1;
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
      m_ctx_sid <= ctx_sid; m_ctx_seq <= ctx_seq; m_ctx_changed <= ctx_changed;
      m_ctx_sec <= ctx_sec; m_ctx_ps_hi <= ctx_ps[63:32];
      m_ctx_ps_lo <= ctx_ps[31:0]; m_ctx_bw <= ctx_bw;
      m_ctx_rf_hi <= ctx_rf[63:32]; m_ctx_rf_lo <= ctx_rf[31:0];
      m_ctx_fs <= ctx_fs;
    end
    if (ver_meta_valid) begin
      cnt_ver <= cnt_ver + 1'b1;
      m_ver_sid <= ver_sid; m_ver_seq <= ver_seq; m_ver_changed <= ver_changed;
      m_ver_sec <= ver_sec; m_ver_ps_hi <= ver_ps[63:32];
      m_ver_ps_lo <= ver_ps[31:0]; m_ver_info <= ver_info;
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
  case(dbg_page)
    5'd0: dbg_rdata = 32'hB3000003;
    5'd1: dbg_rdata = cnt_data;
    5'd2: dbg_rdata = cnt_ctx;
    5'd3: dbg_rdata = cnt_ver;
    5'd4: dbg_rdata = cnt_e_dispatch;
    5'd5: dbg_rdata = cnt_e_data;
    5'd6: dbg_rdata = cnt_e_ctx;
    5'd7: dbg_rdata = cnt_e_ver;
    5'd8: dbg_rdata = last_error;
    5'd9: dbg_rdata = m_data_sid;
    5'd10: dbg_rdata = {12'd0,m_data_samples,m_data_seq};
    5'd11: dbg_rdata = m_data_sec;
    5'd12: dbg_rdata = m_data_ps_hi;
    5'd13: dbg_rdata = m_data_ps_lo;
    5'd14: dbg_rdata = m_ctx_sid;
    5'd15: dbg_rdata = {27'd0,m_ctx_changed,m_ctx_seq};
    5'd16: dbg_rdata = m_ctx_bw;
    5'd17: dbg_rdata = m_ctx_rf_hi;
    5'd18: dbg_rdata = m_ctx_rf_lo;
    5'd19: dbg_rdata = m_ctx_fs;
    5'd20: dbg_rdata = m_ctx_sec;
    5'd21: dbg_rdata = m_ctx_ps_hi;
    5'd22: dbg_rdata = m_ctx_ps_lo;
    5'd23: dbg_rdata = m_ver_sid;
    5'd24: dbg_rdata = {27'd0,m_ver_changed,m_ver_seq};
    5'd25: dbg_rdata = m_ver_info;
    5'd26: dbg_rdata = m_ver_sec;
    5'd27: dbg_rdata = m_ver_ps_hi;
    5'd28: dbg_rdata = m_ver_ps_lo;
    5'd29: dbg_rdata = tx_packet_count;
    5'd30: dbg_rdata = tx_beat_count;
    5'd31: dbg_rdata = 32'hB3F0001F;
    default: dbg_rdata = 32'd0;
  endcase
end
endmodule
