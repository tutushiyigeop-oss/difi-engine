`timescale 1ns/1ps
// DIFI v1.4 config-to-TX integration verification.
// IEEE 1364-2001 (Verilog-2001). No SystemVerilog features.
// Real DUTs: cfg_regs, tx_scheduler, data_packetizer,
//            context_generator, version_generator.
module tb_difi_cfg_tx_integration;

localparam [7:0] REG_CONTROL = 8'h00;
localparam [7:0] REG_COMMAND = 8'h04;
localparam [7:0] REG_STATUS  = 8'h08;
localparam [7:0] REG_DATA_SID = 8'h10;
localparam [7:0] REG_VERSION_SID = 8'h14;
localparam [7:0] REG_SAMPLES = 8'h18;
localparam [7:0] REG_FS = 8'h1C;
localparam [7:0] REG_BW = 8'h20;
localparam [7:0] REG_RF_LO = 8'h24;
localparam [7:0] REG_RF_HI = 8'h28;
localparam [7:0] REG_CTX_PERIOD = 8'h2C;
localparam [7:0] REG_VER_PERIOD = 8'h30;
localparam [7:0] REG_RX_CTRL = 8'h34;
localparam [7:0] REG_RX_DATA_SID = 8'h38;
localparam [7:0] REG_ACTIVE_DATA_SID = 8'h40;
localparam [7:0] REG_ACTIVE_SAMPLES = 8'h48;
localparam [7:0] REG_ACTIVE_FS = 8'h4C;
localparam [7:0] REG_ACTIVE_BW = 8'h50;
localparam [7:0] REG_ACTIVE_RF_LO = 8'h54;
localparam [7:0] REG_ACTIVE_RF_HI = 8'h58;
localparam [7:0] REG_ACTIVE_CTX_PERIOD = 8'h5C;
localparam [7:0] REG_ACTIVE_VER_PERIOD = 8'h60;
localparam [1:0] OKAY = 2'b00;
localparam [1:0] SLVERR = 2'b10;
localparam [3:0] TYPE_DATA = 4'h1;
localparam [3:0] TYPE_CONTEXT = 4'h4;
localparam [3:0] TYPE_VERSION = 4'h5;
localparam [31:0] CIF_CTX_CHANGED = 32'hFBB98000;
localparam [31:0] CIF_CTX_NOCHANGE = 32'h7BB98000;
localparam [31:0] CIF_VERSION_CHANGED = 32'h80000002;
localparam [31:0] CIF_VERSION_NOCHANGE = 32'h00000002;

reg aclk;
reg aresetn;
initial aclk = 0;
always #5 aclk = ~aclk;

reg [7:0] s_axi_awaddr;
reg [2:0] s_axi_awprot;
reg s_axi_awvalid;
wire s_axi_awready;
reg [31:0] s_axi_wdata;
reg [3:0] s_axi_wstrb;
reg s_axi_wvalid;
wire s_axi_wready;
wire [1:0] s_axi_bresp;
wire s_axi_bvalid;
reg s_axi_bready;
reg [7:0] s_axi_araddr;
reg [2:0] s_axi_arprot;
reg s_axi_arvalid;
wire s_axi_arready;
wire [31:0] s_axi_rdata;
wire [1:0] s_axi_rresp;
wire s_axi_rvalid;
reg s_axi_rready;

wire tx_enable;
wire cfg_commit_req;
wire cfg_commit_ack;
wire context_change_pending;
wire context_change_done;
wire tx_busy;
reg time_valid;
reg [31:0] time_sec;
reg [63:0] time_ps;
wire [31:0] cfg_data_stream_id;
wire [31:0] cfg_version_stream_id;
wire [15:0] cfg_samples_per_packet;
wire [31:0] cfg_sample_rate_hz;
wire [31:0] cfg_bandwidth_hz;
wire [63:0] cfg_rf_freq_hz;
wire [31:0] cfg_context_period_ms;
wire [31:0] cfg_version_period_ms;
wire cfg_rx_data_filter_enable;
wire [31:0] cfg_rx_expected_data_stream_id;
wire cfg_rx_version_filter_enable;
wire [31:0] cfg_rx_expected_version_stream_id;

reg data_available;
reg context_periodic_trigger;
reg version_periodic_trigger;
wire data_pkt_start;
wire context_pkt_start;
wire version_pkt_start;
wire data_pkt_busy, data_pkt_done;
wire context_pkt_busy, context_pkt_done;
wire version_pkt_busy, version_pkt_done;
wire [31:0] data_tdata, context_tdata, version_tdata;
wire data_tvalid, context_tvalid, version_tvalid;
wire data_tready, context_tready, version_tready;
wire [3:0] data_tkeep, context_tkeep, version_tkeep;
wire data_tlast, context_tlast, version_tlast;
wire [31:0] merged_tdata;
wire merged_tvalid;
wire [3:0] merged_tkeep;
wire merged_tlast;
reg merged_tready;
reg [31:0] iq_sample;
wire iq_tready;

// --------------------------------------------------------------------
// DUT interconnect - no behavioral replacement for real TX blocks.
// --------------------------------------------------------------------
difi_cfg_regs u_cfg (
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
    .tx_enable(tx_enable), .cfg_commit_req(cfg_commit_req),
    .cfg_commit_ack(cfg_commit_ack),
    .context_change_pending(context_change_pending),
    .context_change_done(context_change_done),
    .tx_busy(tx_busy), .time_valid(time_valid),
    .cfg_data_stream_id(cfg_data_stream_id),
    .cfg_version_stream_id(cfg_version_stream_id),
    .cfg_samples_per_packet(cfg_samples_per_packet),
    .cfg_sample_rate_hz(cfg_sample_rate_hz),
    .cfg_bandwidth_hz(cfg_bandwidth_hz),
    .cfg_rf_freq_hz(cfg_rf_freq_hz),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms),
    .cfg_rx_data_filter_enable(cfg_rx_data_filter_enable),
    .cfg_rx_expected_data_stream_id(cfg_rx_expected_data_stream_id),
    .cfg_rx_version_filter_enable(cfg_rx_version_filter_enable),
    .cfg_rx_expected_version_stream_id(cfg_rx_expected_version_stream_id)
);

difi_tx_scheduler u_sched (
    .aclk(aclk), .aresetn(aresetn), .tx_enable(tx_enable),
    .time_valid(time_valid), .data_available(data_available),
    .cfg_commit_req(cfg_commit_req), .cfg_commit_ack(cfg_commit_ack),
    .context_change_pending(context_change_pending),
    .context_periodic_trigger(context_periodic_trigger),
    .version_periodic_trigger(version_periodic_trigger),
    .data_pkt_start(data_pkt_start), .data_pkt_busy(data_pkt_busy),
    .data_pkt_done(data_pkt_done),
    .s_axis_data_tdata(data_tdata), .s_axis_data_tvalid(data_tvalid),
    .s_axis_data_tready(data_tready), .s_axis_data_tkeep(data_tkeep),
    .s_axis_data_tlast(data_tlast),
    .context_pkt_start(context_pkt_start),
    .context_pkt_busy(context_pkt_busy), .context_pkt_done(context_pkt_done),
    .s_axis_context_tdata(context_tdata),
    .s_axis_context_tvalid(context_tvalid),
    .s_axis_context_tready(context_tready),
    .s_axis_context_tkeep(context_tkeep),
    .s_axis_context_tlast(context_tlast),
    .version_pkt_start(version_pkt_start),
    .version_pkt_busy(version_pkt_busy), .version_pkt_done(version_pkt_done),
    .s_axis_version_tdata(version_tdata),
    .s_axis_version_tvalid(version_tvalid),
    .s_axis_version_tready(version_tready),
    .s_axis_version_tkeep(version_tkeep),
    .s_axis_version_tlast(version_tlast),
    .m_axis_pkt_tdata(merged_tdata),
    .m_axis_pkt_tvalid(merged_tvalid),
    .m_axis_pkt_tready(merged_tready),
    .m_axis_pkt_tkeep(merged_tkeep),
    .m_axis_pkt_tlast(merged_tlast), .tx_busy(tx_busy)
);

difi_data_packetizer u_data (
    .aclk(aclk), .aresetn(aresetn),
    .pkt_start(data_pkt_start), .pkt_busy(data_pkt_busy),
    .pkt_done(data_pkt_done),
    .s_axis_iq_tdata(iq_sample), .s_axis_iq_tvalid(1'b1),
    .s_axis_iq_tready(iq_tready),
    .cfg_data_stream_id(cfg_data_stream_id),
    .cfg_samples_per_packet(cfg_samples_per_packet),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
    .m_axis_pkt_tdata(data_tdata), .m_axis_pkt_tvalid(data_tvalid),
    .m_axis_pkt_tready(data_tready),
    .m_axis_pkt_tkeep(data_tkeep), .m_axis_pkt_tlast(data_tlast)
);

difi_context_generator u_ctx (
    .aclk(aclk), .aresetn(aresetn),
    .pkt_start(context_pkt_start), .pkt_busy(context_pkt_busy),
    .pkt_done(context_pkt_done),
    .cfg_data_stream_id(cfg_data_stream_id),
    .cfg_sample_rate_hz(cfg_sample_rate_hz),
    .cfg_bandwidth_hz(cfg_bandwidth_hz),
    .cfg_rf_freq_hz(cfg_rf_freq_hz),
    .cfg_context_change_pending(context_change_pending),
    .context_change_done(context_change_done),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
    .m_axis_pkt_tdata(context_tdata),
    .m_axis_pkt_tvalid(context_tvalid),
    .m_axis_pkt_tready(context_tready),
    .m_axis_pkt_tkeep(context_tkeep), .m_axis_pkt_tlast(context_tlast)
);

difi_version_generator u_ver (
    .aclk(aclk), .aresetn(aresetn),
    .pkt_start(version_pkt_start), .pkt_busy(version_pkt_busy),
    .pkt_done(version_pkt_done),
    .cfg_version_stream_id(cfg_version_stream_id),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
    .m_axis_pkt_tdata(version_tdata),
    .m_axis_pkt_tvalid(version_tvalid),
    .m_axis_pkt_tready(version_tready),
    .m_axis_pkt_tkeep(version_tkeep), .m_axis_pkt_tlast(version_tlast)
);

always @(posedge aclk or negedge aresetn)
    if (!aresetn) iq_sample <= 32'h1111_0000;
    else if (iq_tready) iq_sample <= iq_sample + 32'd1;

// --------------------------------------------------------------------
// Scoreboard. Capture each packet's actual handshaken words.
// --------------------------------------------------------------------
integer packets;
integer word_index;
reg [3:0] packet_type [0:63];
reg [31:0] packet_header [0:63];
reg [31:0] packet_sid [0:63];
reg [31:0] packet_cif [0:63];
reg [31:0] packet_bw_hi [0:63];
reg [31:0] packet_bw_lo [0:63];
reg [31:0] packet_rf_hi [0:63];
reg [31:0] packet_rf_lo [0:63];
reg [31:0] packet_fs_hi [0:63];
reg [31:0] packet_fs_lo [0:63];
integer packet_len [0:63];
integer checks;
integer tc;
reg held;
reg [31:0] held_data;
reg [3:0] held_keep;
reg held_last;
integer starts;
integer acks;
integer changed_done_count;
reg prev_ack;

// Never silently continue after a failed assertion.
task fail;
    input [8*160-1:0] reason;
    begin
        $display("FAIL tb_difi_cfg_tx_integration: TC%0d cycle_time=%0t: %0s", tc, $time, reason);
        $finish;
    end
endtask

task assert_equal32;
    input [31:0] actual;
    input [31:0] expected;
    input [8*120-1:0] what;
    begin
        checks = checks + 1;
        if (actual !== expected) begin
            $display("   actual=%08h expected=%08h", actual, expected);
            fail(what);
        end
    end
endtask

task assert_equal_int;
    input integer actual;
    input integer expected;
    input [8*120-1:0] what;
    begin
        checks = checks + 1;
        if (actual != expected) begin
            $display("   actual=%0d expected=%0d", actual, expected);
            fail(what);
        end
    end
endtask

always @(posedge aclk) begin
    if (!aresetn) begin
        packets = 0;
        word_index = 0;
        held = 0;
        starts = 0;
        acks = 0;
        changed_done_count = 0;
        prev_ack = 0;
    end else begin
        if (data_pkt_start || context_pkt_start || version_pkt_start) begin
            starts = starts + 1;
            checks = checks + 1;
            if ((data_pkt_start && context_pkt_start) ||
                (data_pkt_start && version_pkt_start) ||
                (context_pkt_start && version_pkt_start))
                fail("Multiple pkt_start simultaneously");
            if (!tx_enable || !time_valid)
                fail("Packet started with tx_enable=0 or time_valid=0");
        end
        if (cfg_commit_ack) begin
            acks = acks + 1;
            checks = checks + 1;
            if (!cfg_commit_req) fail("Unsolicited commit ACK");
            if (tx_busy) fail("ACK during packet ownership");
            if (data_pkt_start || context_pkt_start || version_pkt_start)
                fail("Commit ACK overlaps pkt_start");
            if (prev_ack) fail("ACK held for multiple cycles");
        end
        prev_ack = cfg_commit_ack;
        if (context_change_done) changed_done_count = changed_done_count + 1;
        if (held) begin
            checks = checks + 1;
            if (merged_tvalid !== 1'b1 || merged_tdata !== held_data ||
                merged_tlast !== held_last || merged_tkeep !== held_keep)
                fail("Merged AXIS output changed during backpressure");
        end
        held = merged_tvalid && !merged_tready;
        if (held) begin
            held_data = merged_tdata;
            held_keep = merged_tkeep;
            held_last = merged_tlast;
        end
        if (merged_tvalid && merged_tready) begin
            if (packets >= 64) fail("Scoreboard capacity exhausted");
            checks = checks + 1;
            if (merged_tkeep !== 4'b1111)
                fail("Packet word has incorrect TKEEP");
            if (word_index == 0) begin
                packet_type[packets] = merged_tdata[31:28];
                packet_header[packets] = merged_tdata;
                packet_sid[packets] = 0;
                packet_cif[packets] = 0;
                packet_bw_hi[packets] = 0;
                packet_bw_lo[packets] = 0;
                packet_rf_hi[packets] = 0;
                packet_rf_lo[packets] = 0;
                packet_fs_hi[packets] = 0;
                packet_fs_lo[packets] = 0;
                checks = checks + 1;
                if (merged_tdata[31:28] != TYPE_DATA &&
                    merged_tdata[31:28] != TYPE_CONTEXT &&
                    merged_tdata[31:28] != TYPE_VERSION)
                    fail("Unknown packet type on merged AXIS");
            end
            if (word_index == 1) packet_sid[packets] = merged_tdata;
            if (word_index == 7 && packet_type[packets] != TYPE_DATA)
                packet_cif[packets] = merged_tdata;
            if (word_index == 9 && packet_type[packets] == TYPE_CONTEXT)
                packet_bw_hi[packets] = merged_tdata;
            if (word_index == 10 && packet_type[packets] == TYPE_CONTEXT)
                packet_bw_lo[packets] = merged_tdata;
            if (word_index == 13 && packet_type[packets] == TYPE_CONTEXT)
                packet_rf_hi[packets] = merged_tdata;
            if (word_index == 14 && packet_type[packets] == TYPE_CONTEXT)
                packet_rf_lo[packets] = merged_tdata;
            if (word_index == 19 && packet_type[packets] == TYPE_CONTEXT)
                packet_fs_hi[packets] = merged_tdata;
            if (word_index == 20 && packet_type[packets] == TYPE_CONTEXT)
                packet_fs_lo[packets] = merged_tdata;
            word_index = word_index + 1;
            if (merged_tlast) begin
                checks = checks + 1;
                if (word_index != packet_header[packets][15:0])
                    fail("TLAST word count differs from Packet Size");
                packet_len[packets] = word_index;
                $display("  pkt[%0d]: type=%h SID=%08h words=%0d CIF=%08h",
                         packets, packet_type[packets], packet_sid[packets],
                         word_index, packet_cif[packets]);
                packets = packets + 1;
                word_index = 0;
            end
        end
    end
end

// --------------------------------------------------------------------
// Master BFM: tasks drive on falling edges; DUT samples rising edges.
// Timeout bounded and each channel independently handshaken.
// --------------------------------------------------------------------
task axi_write;
    input [7:0] addr;
    input [31:0] value;
    input [3:0] mask;
    input [1:0] expected_resp;
    integer elapsed;
    reg aw_done;
    reg w_done;
    reg b_done;
    begin
        @(negedge aclk);
        s_axi_awaddr = addr;
        s_axi_wdata = value;
        s_axi_wstrb = mask;
        s_axi_awvalid = 1;
        s_axi_wvalid = 1;
        s_axi_bready = 1;
        aw_done = 0;
        w_done = 0;
        b_done = 0;
        elapsed = 0;
        while (!b_done) begin
            @(posedge aclk);
            if (s_axi_awvalid && s_axi_awready) aw_done = 1;
            if (s_axi_wvalid && s_axi_wready) w_done = 1;
            if (s_axi_bvalid && s_axi_bready) begin
                if (s_axi_bresp !== expected_resp) begin
                    $display("  write addr=%02h data=%08h resp=%b expected=%b",
                             addr, value, s_axi_bresp, expected_resp);
                    fail("AXI write BRESP mismatch");
                end
                checks = checks + 1;
                b_done = 1;
            end
            @(negedge aclk);
            if (aw_done) s_axi_awvalid = 0;
            if (w_done) s_axi_wvalid = 0;
            elapsed = elapsed + 1;
            if (elapsed > 100) fail("AXI write timeout");
        end
        s_axi_bready = 0;
    end
endtask

task axi_read_check;
    input [7:0] addr;
    input [31:0] expected_value;
    input [1:0] expected_resp;
    integer elapsed;
    reg ar_done;
    reg r_done;
    begin
        @(negedge aclk);
        s_axi_araddr = addr;
        s_axi_arvalid = 1;
        s_axi_rready = 1;
        ar_done = 0;
        r_done = 0;
        elapsed = 0;
        while (!r_done) begin
            @(posedge aclk);
            if (s_axi_arvalid && s_axi_arready) ar_done = 1;
            if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rresp !== expected_resp ||
                    s_axi_rdata !== expected_value) begin
                    $display("  read addr=%02h data=%08h expected=%08h resp=%b expected=%b",
                             addr, s_axi_rdata, expected_value,
                             s_axi_rresp, expected_resp);
                    fail("AXI read mismatch");
                end
                checks = checks + 1;
                r_done = 1;
            end
            @(negedge aclk);
            if (ar_done) s_axi_arvalid = 0;
            elapsed = elapsed + 1;
            if (elapsed > 100) fail("AXI read timeout");
        end
        s_axi_rready = 0;
    end
endtask

task wait_packets;
    input integer target;
    integer elapsed;
    begin
        elapsed = 0;
        while (packets < target && elapsed < 7000) begin
            @(negedge aclk);
            elapsed = elapsed + 1;
        end
        if (packets < target) fail("Timeout waiting for complete packets");
    end
endtask

task wait_ack_count;
    input integer target;
    integer elapsed;
    begin
        elapsed = 0;
        while (acks < target && elapsed < 1000) begin
            @(negedge aclk);
            elapsed = elapsed + 1;
        end
        if (acks < target) fail("Timeout waiting for Scheduler ACK");
    end
endtask

task wait_req_clear;
    integer elapsed;
    begin
        elapsed = 0;
        while (cfg_commit_req !== 1'b0 && elapsed < 1000) begin
            @(negedge aclk);
            elapsed = elapsed + 1;
        end
        if (cfg_commit_req !== 1'b0) fail("Commit request never cleared");
    end
endtask

task wait_pending_clear;
    integer elapsed;
    begin
        elapsed = 0;
        while (context_change_pending !== 1'b0 && elapsed < 300) begin
            @(negedge aclk);
            elapsed = elapsed + 1;
        end
        if (context_change_pending !== 1'b0)
            fail("Context pending not cleared after changed Context TLAST");
    end
endtask

task request_one_data;
    integer elapsed;
    reg granted;
    begin
        @(negedge aclk);
        data_available = 1;
        elapsed = 0;
        granted = 0;
        while (!granted && elapsed < 3000) begin
            @(posedge aclk);
            if (data_pkt_start) granted = 1;
            @(negedge aclk);
            elapsed = elapsed + 1;
        end
        if (!granted) fail("No Data packet grant");
        data_available = 0;
    end
endtask

task periodic_both;
    begin
        @(negedge aclk);
        context_periodic_trigger = 1;
        version_periodic_trigger = 1;
        @(negedge aclk);
        context_periodic_trigger = 0;
        version_periodic_trigger = 0;
    end
endtask

integer base;
integer old_acks;
integer old_starts;
integer old_packets;
integer i;
reg [63:0] expected_bw;
reg [63:0] expected_fs;
reg [63:0] expected_rf;

initial begin
    aresetn = 0;
    s_axi_awaddr = 0; s_axi_awprot = 0;
    s_axi_awvalid = 0;
    s_axi_wdata = 0; s_axi_wstrb = 0;
    s_axi_wvalid = 0; s_axi_bready = 0;
    s_axi_araddr = 0; s_axi_arprot = 0;
    s_axi_arvalid = 0; s_axi_rready = 0;
    time_valid = 1;
    time_sec = 32'd1000;
    time_ps = 64'd123456789;
    data_available = 0;
    context_periodic_trigger = 0;
    version_periodic_trigger = 0;
    merged_tready = 1;
    tc = 0; checks = 0;

    repeat (6) @(negedge aclk);
    aresetn = 1;
    repeat (3) @(negedge aclk);

    // TEST 1: startup uses real version and context generators.
    tc = 1;
    $display("[TEST 1] Startup Version(changed) -> Context(changed) -> Data");
    assert_equal32({31'd0, context_change_pending}, 32'd1, "Reset Context Pending");
    axi_read_check(REG_ACTIVE_SAMPLES, 32'd256, OKAY);
    axi_read_check(REG_ACTIVE_DATA_SID, 32'd1, OKAY);
    axi_write(REG_CONTROL, 32'd1, 4'h1, OKAY);
    wait_packets(2);
    wait_pending_clear;
    assert_equal_int(packet_type[0], TYPE_VERSION, "Startup first must be Version");
    assert_equal_int(packet_type[1], TYPE_CONTEXT, "Startup second must be Context");
    assert_equal32(packet_cif[0], CIF_VERSION_CHANGED, "First Version should be changed");
    assert_equal32(packet_cif[1], CIF_CTX_CHANGED, "First Context should be changed");
    assert_equal32(packet_sid[0], 32'd2, "Default Version SID");
    assert_equal32(packet_sid[1], 32'd1, "Default Context SID");
    request_one_data;
    wait_packets(3);
    assert_equal_int(packet_type[2], TYPE_DATA, "Startup Data type");
    assert_equal32(packet_sid[2], 32'd1, "Startup Data SID");
    assert_equal_int(packet_len[2], 263, "Startup samples=256");

    // TEST 2: Commit while a real Data packet is stalled mid-packet.
    tc = 2;
    $display("[TEST 2] Shadow writes + Commit during stalled Data; no early ACK");
    base = packets;
    request_one_data;
    // Wait for the outgoing Data packet, then force backpressure.
    i = 0;
    while (((packet_type[base] !== TYPE_DATA) || (packets != base) || (word_index < 2)) && i < 800) begin
        @(negedge aclk);
        i = i + 1;
    end
    if (i >= 800) fail("Failed to observe in-flight Data packet");
    merged_tready = 0;
    axi_write(REG_DATA_SID, 32'h89ABCDEF, 4'hf, OKAY);
    axi_write(REG_VERSION_SID, 32'h13572468, 4'hf, OKAY);
    axi_write(REG_SAMPLES, 32'd3, 4'hf, OKAY);
    axi_write(REG_FS, 32'd8000000, 4'hf, OKAY);
    axi_write(REG_BW, 32'd4000000, 4'hf, OKAY);
    axi_write(REG_RF_LO, 32'hc7652400, 4'hf, OKAY); // 42 GHz low 32 bits
    axi_write(REG_RF_HI, 32'h00000009, 4'hf, OKAY); // 42 GHz high 32 bits
    axi_write(REG_CTX_PERIOD, 32'd250, 4'hf, OKAY);
    axi_write(REG_VER_PERIOD, 32'd500, 4'hf, OKAY);
    assert_equal32(cfg_data_stream_id, 32'd1, "Active must not change on Shadow writes");
    old_acks = acks;
    axi_write(REG_COMMAND, 32'd1, 4'h1, OKAY);
    assert_equal32({31'd0, cfg_commit_req}, 32'd1, "Commit REQ holds during packet");
    repeat (12) begin
        @(negedge aclk);
        assert_equal_int(acks, old_acks, "ACK must wait for Data TLAST");
        assert_equal32(cfg_data_stream_id, 32'd1, "Active SID unchanged before ACK");
    end
    axi_write(REG_SAMPLES, 32'd8, 4'hf, SLVERR);
    axi_read_check(REG_ACTIVE_SAMPLES, 32'd256, OKAY);
    merged_tready = 1;
    wait_packets(base+1);
    assert_equal_int(packet_type[base], TYPE_DATA, "In-flight packet type Data");
    assert_equal32(packet_sid[base], 32'd1, "In-flight Data retains old SID");
    assert_equal_int(packet_len[base], 263, "In-flight Data retains old sample count");
    wait_ack_count(old_acks+1);
    wait_req_clear;
    assert_equal32(cfg_data_stream_id, 32'h89ABCDEF, "New Active SID after ACK");
    assert_equal32({16'd0, cfg_samples_per_packet}, 32'd3, "New Active samples after ACK");
    assert_equal32(cfg_sample_rate_hz, 32'd8000000, "New Active Fs after ACK");
    assert_equal32(cfg_bandwidth_hz, 32'd4000000, "New Active BW after ACK");
    axi_read_check(REG_ACTIVE_SAMPLES, 32'd3, OKAY);
    axi_read_check(REG_ACTIVE_CTX_PERIOD, 32'd250, OKAY);
    axi_read_check(REG_ACTIVE_VER_PERIOD, 32'd500, OKAY);
    // Scheduler must announce new Context before granting a new Data packet.
    request_one_data;
    wait_packets(base+3);
    wait_pending_clear;
    assert_equal_int(packet_type[base+1], TYPE_CONTEXT, "Changed Context after ACK");
    assert_equal_int(packet_type[base+2], TYPE_DATA, "New Data after changed Context");
    assert_equal32(packet_cif[base+1], CIF_CTX_CHANGED, "Context change flag after commit");
    assert_equal32(packet_sid[base+1], 32'h89ABCDEF, "New Context SID");
    assert_equal32(packet_sid[base+2], 32'h89ABCDEF, "New Data SID");
    assert_equal_int(packet_len[base+2], 10, "New Data packet size = 7 + 3");
    expected_bw = 64'd4000000 << 20;
    expected_fs = 64'd8000000 << 20;
    expected_rf = 64'd42000000000 << 20;
    assert_equal32(packet_bw_hi[base+1], expected_bw[63:32], "Context BW high");
    assert_equal32(packet_bw_lo[base+1], expected_bw[31:0], "Context BW low");
    assert_equal32(packet_fs_hi[base+1], expected_fs[63:32], "Context Fs high");
    assert_equal32(packet_fs_lo[base+1], expected_fs[31:0], "Context Fs low");
    assert_equal32(packet_rf_hi[base+1], expected_rf[63:32], "Context RF high");
    assert_equal32(packet_rf_lo[base+1], expected_rf[31:0], "Context RF low");

    // TEST 3: periodic Context and Version; neither should look changed.
    tc = 3;
    $display("[TEST 3] Periodic Context -> Version, with unchanged CIF");
    base = packets;
    periodic_both;
    wait_packets(base+2);
    assert_equal_int(packet_type[base], TYPE_CONTEXT, "Periodic priority Context first");
    assert_equal_int(packet_type[base+1], TYPE_VERSION, "Periodic Version second");
    assert_equal32(packet_cif[base], CIF_CTX_NOCHANGE, "Periodic Context must not change");
    assert_equal32(packet_cif[base+1], CIF_VERSION_NOCHANGE, "Periodic Version no-change CIF");
    assert_equal32(packet_sid[base+1], 32'h13572468, "New Version SID effective");
    assert_equal32({31'd0, context_change_pending}, 32'd0,
                   "Periodic Context must not set pending");

    // TEST 4: Commit succeeds even if TX disabled and time source invalid.
    tc = 4;
    $display("[TEST 4] Disabled/time-invalid Commit, resume -> changed Context -> Data");
    axi_write(REG_CONTROL, 32'd0, 4'h1, OKAY);
    time_valid = 0;
    base = packets;
    old_starts = starts;
    old_acks = acks;
    axi_write(REG_DATA_SID, 32'h01234567, 4'hf, OKAY);
    axi_write(REG_SAMPLES, 32'd1, 4'hf, OKAY);
    axi_write(REG_COMMAND, 32'd1, 4'h1, OKAY);
    wait_ack_count(old_acks+1);
    wait_req_clear;
    assert_equal_int(packets, base, "No packets while TX/time disabled");
    assert_equal_int(starts, old_starts, "No packet starts while disabled");
    assert_equal32(cfg_data_stream_id, 32'h01234567, "Active updates even with TX disabled");
    assert_equal32({31'd0, context_change_pending}, 32'd1, "Commit creates Context pending");
    axi_read_check(REG_STATUS, 32'h00000002, OKAY); // bit1=1 only
    time_valid = 1;
    axi_write(REG_CONTROL, 32'd1, 4'h1, OKAY);
    request_one_data;
    wait_packets(base+2);
    wait_pending_clear;
    assert_equal_int(packet_type[base], TYPE_CONTEXT, "Changed Context on TX resume");
    assert_equal_int(packet_type[base+1], TYPE_DATA, "Data after resume Context");
    assert_equal32(packet_cif[base], CIF_CTX_CHANGED, "Resume Context change");
    assert_equal32(packet_sid[base], 32'h01234567, "Resume Context SID");
    assert_equal32(packet_sid[base+1], 32'h01234567, "Resume Data SID");
    assert_equal_int(packet_len[base+1], 8, "N=1 Data packet length");

    // TEST 5: RX filter updates bypass TX Commit.
    tc = 5;
    $display("[TEST 5] RX direct-update path independent of TX commit");
    axi_write(REG_RX_DATA_SID, 32'hCAFEBABE, 4'hf, OKAY);
    axi_write(REG_RX_CTRL, 32'd1, 4'h1, OKAY);
    assert_equal32(cfg_rx_expected_data_stream_id, 32'hCAFEBABE, "RX filter SID immediate");
    assert_equal32({31'd0, cfg_rx_data_filter_enable}, 32'd1, "RX filter enable immediate");
    assert_equal32(cfg_data_stream_id, 32'h01234567, "RX writes cannot mutate TX Active");

    // TEST 6: reset re-arms startup and restores defaults on all 5 DUTs.
    tc = 6;
    $display("[TEST 6] Reset restores config and startup packet sequence");
    axi_write(REG_CONTROL, 32'd0, 4'h1, OKAY);
    @(negedge aclk);
    aresetn = 0;
    repeat (5) @(negedge aclk);
    aresetn = 1;
    repeat (3) @(negedge aclk);
    assert_equal32(cfg_data_stream_id, 32'd1, "Reset Active SID");
    assert_equal32({16'd0,cfg_samples_per_packet}, 32'd256, "Reset Active samples");
    assert_equal32({31'd0, context_change_pending}, 32'd1, "Reset pending=1");
    assert_equal32({31'd0, tx_enable}, 32'd0, "Reset tx_enable=0");
    axi_write(REG_CONTROL, 32'd1, 4'h1, OKAY);
    wait_packets(2);
    wait_pending_clear;
    assert_equal_int(packet_type[0], TYPE_VERSION, "Reboot Version first");
    assert_equal_int(packet_type[1], TYPE_CONTEXT, "Reboot Context second");
    assert_equal32(packet_cif[0], CIF_VERSION_CHANGED, "Reboot Version changed");
    assert_equal32(packet_cif[1], CIF_CTX_CHANGED, "Reboot Context changed");

    $display("PASS tb_difi_cfg_tx_integration: 6 scenarios, %0d checks", checks);
    $finish;
end

initial begin
    #1000000;
    fail("Global integration timeout");
end
endmodule
