module difi_tx_board_test (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXIS_IQ:M_AXIS_PKT, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input wire aresetn,

    // Keep GPIO bit0 low at startup; 0->1->0 triggers one packet.
    input wire start_level,
    output wire pkt_busy,
    output wire pkt_done,

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

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TDATA" *)
    output wire [31:0] m_axis_pkt_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TVALID" *)
    output wire m_axis_pkt_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TREADY" *)
    input wire m_axis_pkt_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TKEEP" *)
    output wire [3:0] m_axis_pkt_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_PKT TLAST" *)
    output wire m_axis_pkt_tlast
);
    reg start_level_d;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            start_level_d <= 1'b0;
        else
            start_level_d <= start_level;
    end

    wire start_pulse = start_level && !start_level_d;

    // Fixed test time, not real UTC.
    difi_data_packetizer u_data_packetizer (
        .aclk(aclk),
        .aresetn(aresetn),
        .pkt_start(start_pulse),
        .pkt_busy(pkt_busy),
        .pkt_done(pkt_done),
        .s_axis_iq_tdata(s_axis_iq_tdata),
        .s_axis_iq_tvalid(s_axis_iq_tvalid),
        .s_axis_iq_tready(s_axis_iq_tready),
        .cfg_data_stream_id(32'h0000_0001),
        .cfg_samples_per_packet(16'd256),
        .time_sec(32'd1700000000),
        .time_ps(64'd0),
        .time_valid(1'b1),
        .m_axis_pkt_tdata(m_axis_pkt_tdata),
        .m_axis_pkt_tvalid(m_axis_pkt_tvalid),
        .m_axis_pkt_tready(m_axis_pkt_tready),
        .m_axis_pkt_tkeep(m_axis_pkt_tkeep),
        .m_axis_pkt_tlast(m_axis_pkt_tlast)
    );

    // Pack 256 IQ samples per packet and ignore input TLAST.
endmodule
