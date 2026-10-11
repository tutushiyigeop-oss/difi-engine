`timescale 1ns/1ps
`include "difi_cfg_regmap.vh"

// Verilog-2001 standalone, self-checking testbench for difi_cfg_regs (v1.4).
// Only the DUT is instantiated. Scheduler ACK / Context Done are modeled at the
// interface so their edge cases are tested independently of Scheduler behavior.
module tb_difi_cfg_regs;
    localparam integer CLK_PERIOD_NS = 10;
    localparam integer TIMEOUT_CYCLES = 100;
    localparam [63:0] RF_NEW = 64'd2_450_000_000;
    localparam [31:0] SID_NEW = 32'hA5C3_1209;

    reg         aclk;
    reg         aresetn;

    reg  [7:0]  s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;

    reg  [7:0]  s_axi_araddr;
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    wire        tx_enable;
    wire        cfg_commit_req;
    reg         cfg_commit_ack;
    wire        context_change_pending;
    reg         context_change_done;
    reg         tx_busy;
    reg         time_valid;

    wire [31:0] cfg_data_stream_id;
    wire [31:0] cfg_version_stream_id;
    wire [15:0] cfg_samples_per_packet;
    wire [31:0] cfg_sample_rate_hz;
    wire [31:0] cfg_bandwidth_hz;
    wire [63:0] cfg_rf_freq_hz;
    wire [31:0] cfg_context_period_ms;
    wire [31:0] cfg_version_period_ms;
    wire        cfg_rx_data_filter_enable;
    wire [31:0] cfg_rx_expected_data_stream_id;
    wire        cfg_rx_version_filter_enable;
    wire [31:0] cfg_rx_expected_version_stream_id;

    integer checks;
    integer scenarios;
    reg [1:0] last_bresp;
    reg [31:0] last_rdata;
    reg [1:0] last_rresp;
    reg last_bstall;
    reg last_rstall;

    always #(CLK_PERIOD_NS/2) aclk = ~aclk;

    difi_cfg_regs dut (
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

    // Passive independent protocol monitors: remain active during *all* tests.
    // Sample at the rising edge (pre-NBA values) to check the previous stall.
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            last_bstall <= 1'b0;
            last_rstall <= 1'b0;
            last_bresp <= 2'b00;
            last_rdata <= 32'd0;
            last_rresp <= 2'b00;
        end else begin
            if (last_bstall && (s_axi_bvalid !== 1'b1 ||
                                s_axi_bresp !== last_bresp))
                begin $display("FAIL tb_difi_cfg_regs: AXI B changed while stalled at %0t", $time); $finish; end
            if (last_rstall && (s_axi_rvalid !== 1'b1 ||
                                s_axi_rdata !== last_rdata ||
                                s_axi_rresp !== last_rresp))
                begin $display("FAIL tb_difi_cfg_regs: AXI R changed while stalled at %0t", $time); $finish; end
            last_bstall <= (s_axi_bvalid === 1'b1 && s_axi_bready === 1'b0);
            last_rstall <= (s_axi_rvalid === 1'b1 && s_axi_rready === 1'b0);
            last_bresp <= s_axi_bresp;
            last_rdata <= s_axi_rdata;
            last_rresp <= s_axi_rresp;
        end
    end

    task automatic eq32;
        input [8*128-1:0] tag;
        input [31:0] got;
        input [31:0] exp;
        begin
            checks = checks + 1;
            if (got !== exp)
                begin $display("FAIL tb_difi_cfg_regs: %0s got=%08h expected=%08h at %0t", tag, got, exp, $time); $finish; end
        end
    endtask

    task automatic eq64;
        input [8*128-1:0] tag;
        input [63:0] got;
        input [63:0] exp;
        begin
            checks = checks + 1;
            if (got !== exp)
                begin $display("FAIL tb_difi_cfg_regs: %0s got=%016h expected=%016h at %0t", tag, got, exp, $time); $finish; end
        end
    endtask

    task automatic eq1;
        input [8*128-1:0] tag;
        input got;
        input exp;
        begin
            checks = checks + 1;
            if (got !== exp)
                begin $display("FAIL tb_difi_cfg_regs: %0s got=%b expected=%b at %0t", tag, got, exp, $time); $finish; end
        end
    endtask

    task automatic scenario;
        input [8*128-1:0] name;
        begin
            scenarios = scenarios + 1;
            $display("[TEST %0d] %0s", scenarios, name);
        end
    endtask

    task automatic send_aw;
        input [7:0] addr;
        integer cycles;
        reg accepted;
        begin
            @(negedge aclk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1'b1;
            cycles = 0;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_awready === 1'b1)
                    accepted = 1;
                else if (cycles >= TIMEOUT_CYCLES)
                    begin $display("FAIL tb_difi_cfg_regs: AW handshake timeout addr=%02h", addr); $finish; end
                cycles = cycles + 1;
            end
            @(negedge aclk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task automatic send_w;
        input [31:0] data;
        input [3:0] strb;
        integer cycles;
        reg accepted;
        begin
            @(negedge aclk);
            s_axi_wdata = data;
            s_axi_wstrb = strb;
            s_axi_wvalid = 1'b1;
            cycles = 0;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_wready === 1'b1)
                    accepted = 1;
                else if (cycles >= TIMEOUT_CYCLES)
                    begin $display("FAIL tb_difi_cfg_regs: W handshake timeout data=%08h", data); $finish; end
                cycles = cycles + 1;
            end
            @(negedge aclk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task automatic send_ar;
        input [7:0] addr;
        integer cycles;
        reg accepted;
        begin
            @(negedge aclk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1'b1;
            cycles = 0;
            accepted = 0;
            while (!accepted) begin
                @(posedge aclk);
                if (s_axi_arready === 1'b1)
                    accepted = 1;
                else if (cycles >= TIMEOUT_CYCLES)
                    begin $display("FAIL tb_difi_cfg_regs: AR handshake timeout addr=%02h", addr); $finish; end
                cycles = cycles + 1;
            end
            @(negedge aclk);
            s_axi_arvalid = 1'b0;
        end
    endtask

    // BREADY stays low until the response was checked, including optional stall.
    task automatic collect_b;
        input [1:0] exp_resp;
        input integer hold_cycles;
        integer cycles;
        reg seen;
        reg [1:0] snapshot;
        begin
            cycles = 0;
            seen = 0;
            while (!seen) begin
                @(negedge aclk);
                if (s_axi_bvalid === 1'b1) seen = 1;
                else if (cycles >= TIMEOUT_CYCLES)
                    begin $display("FAIL tb_difi_cfg_regs: B response timeout"); $finish; end
                cycles = cycles + 1;
            end
            snapshot = s_axi_bresp;
            eq32("BRESP", {30'd0, snapshot}, {30'd0, exp_resp});
            repeat (hold_cycles) begin
                @(posedge aclk);
                #1;
                eq1("BVALID hold", s_axi_bvalid, 1'b1);
                eq1("AWREADY blocked by B", s_axi_awready, 1'b0);
                eq1("WREADY blocked by B", s_axi_wready, 1'b0);
                eq32("BRESP hold", {30'd0, s_axi_bresp}, {30'd0, snapshot});
            end
            @(negedge aclk);
            s_axi_bready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_bready = 1'b0;
            eq1("BVALID consumed", s_axi_bvalid, 1'b0);
        end
    endtask

    task automatic collect_r;
        input [31:0] exp_data;
        input [1:0] exp_resp;
        input integer hold_cycles;
        integer cycles;
        reg seen;
        reg [31:0] snapshot_data;
        reg [1:0] snapshot_resp;
        begin
            cycles = 0;
            seen = 0;
            while (!seen) begin
                @(negedge aclk);
                if (s_axi_rvalid === 1'b1) seen = 1;
                else if (cycles >= TIMEOUT_CYCLES)
                    begin $display("FAIL tb_difi_cfg_regs: R response timeout"); $finish; end
                cycles = cycles + 1;
            end
            snapshot_data = s_axi_rdata;
            snapshot_resp = s_axi_rresp;
            eq32("RDATA", snapshot_data, exp_data);
            eq32("RRESP", {30'd0, snapshot_resp}, {30'd0, exp_resp});
            repeat (hold_cycles) begin
                @(posedge aclk);
                #1;
                eq1("RVALID hold", s_axi_rvalid, 1'b1);
                eq32("RDATA hold", s_axi_rdata, snapshot_data);
                eq32("RRESP hold", {30'd0, s_axi_rresp}, {30'd0, snapshot_resp});
            end
            @(negedge aclk);
            s_axi_rready = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            s_axi_rready = 1'b0;
            eq1("RVALID consumed", s_axi_rvalid, 1'b0);
        end
    endtask

    task automatic wr;
        input [7:0] addr;
        input [31:0] data;
        input [3:0] strb;
        input [1:0] response;
        input integer aw_delay;
        input integer w_delay;
        input integer b_hold;
        begin
            fork
                begin
                    repeat (aw_delay) @(posedge aclk);
                    send_aw(addr);
                end
                begin
                    repeat (w_delay) @(posedge aclk);
                    send_w(data, strb);
                end
            join
            collect_b(response, b_hold);
        end
    endtask

    task automatic rd;
        input [7:0] addr;
        input [31:0] data;
        input [1:0] response;
        input integer r_hold;
        begin
            send_ar(addr);
            collect_r(data, response, r_hold);
        end
    endtask

    // Exercise all 16 WSTRB masks against an independent byte-merge oracle.
    task automatic sweep_all_wstrb;
        reg [31:0] expected;
        reg [31:0] payload;
        integer mask_idx, byte_idx;
        begin
            expected = 32'hAA00_00DD; // previously written RX_DATA_SID value
            for (mask_idx = 0; mask_idx < 16; mask_idx = mask_idx + 1) begin
                payload = 32'h7654_3210 ^ (32'h0102_0408 * mask_idx);
                for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1)
                    if ((mask_idx & (1 << byte_idx)) != 0)
                        expected[byte_idx*8 +: 8] = payload[byte_idx*8 +: 8];
                wr(`DIFI_REG_RX_DATA_SID, payload, mask_idx[3:0],
                   `BRESP_OKAY, 0, 0, 0);
                rd_ok(`DIFI_REG_RX_DATA_SID, expected);
                eq32("WSTRB direct output", cfg_rx_expected_data_stream_id, expected);
            end
        end
    endtask

    task automatic wr_ok;
        input [7:0] addr;
        input [31:0] data;
        begin
            wr(addr, data, 4'hF, `BRESP_OKAY, 0, 0, 0);
        end
    endtask

    task automatic rd_ok;
        input [7:0] addr;
        input [31:0] data;
        begin
            rd(addr, data, `RRESP_OKAY, 0);
        end
    endtask

    task automatic pulse_ack;
        begin
            @(negedge aclk);
            cfg_commit_ack = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            cfg_commit_ack = 1'b0;
        end
    endtask

    task automatic pulse_done;
        begin
            @(negedge aclk);
            context_change_done = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            context_change_done = 1'b0;
        end
    endtask

    task automatic invalid_commit;
        input [31:0] error_code;
        begin
            wr(`DIFI_REG_COMMAND, 32'd1, 4'b0001, `BRESP_SLVERR, 0, 0, 0);
            eq1("invalid commit does not assert req", cfg_commit_req, 1'b0);
            rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, error_code);
            rd_ok(`DIFI_REG_STATUS, 32'h00000020 | {27'd0,time_valid,tx_enable,tx_busy,context_change_pending,cfg_commit_req});
        end
    endtask

    initial begin
        #2_000_000;
        begin $display("FAIL tb_difi_cfg_regs: GLOBAL TIMEOUT: testbench did not complete"); $finish; end
    end

    initial begin
        aclk = 1'b0;
        checks = 0;
        scenarios = 0;
        aresetn = 1'b0;
        s_axi_awaddr = 0; s_axi_awprot = 0; s_axi_awvalid = 0;
        s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0; s_axi_arprot = 0; s_axi_arvalid = 0;
        s_axi_rready = 0;
        cfg_commit_ack = 0; context_change_done = 0;
        tx_busy = 0; time_valid = 0;
        if ($test$plusargs("VCD")) begin
            $dumpfile("tb_difi_cfg_regs.vcd");
            $dumpvars(0, tb_difi_cfg_regs);
        end
        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        @(negedge aclk);

        scenario("reset defaults: 25 mapped reads, active outputs, pending");
        eq1("reset tx enable", tx_enable, 0);
        eq1("reset commit req", cfg_commit_req, 0);
        eq1("reset context pending", context_change_pending, 1);
        eq32("reset active SID", cfg_data_stream_id, `DIFI_CFG_DEFAULT_DATA_SID);
        eq32("reset version SID", cfg_version_stream_id, `DIFI_CFG_DEFAULT_VERSION_SID);
        eq32("reset samples", {16'd0,cfg_samples_per_packet}, 32'd256);
        eq32("reset fs", cfg_sample_rate_hz, 32'd1000000);
        eq32("reset bw", cfg_bandwidth_hz, 32'd1000000);
        eq64("reset rf", cfg_rf_freq_hz, 64'd0);
        eq32("reset ctx period", cfg_context_period_ms, 32'd1000);
        eq32("reset ver period", cfg_version_period_ms, 32'd1000);
        eq1("reset rx data filter", cfg_rx_data_filter_enable, 0);
        eq1("reset rx version filter", cfg_rx_version_filter_enable, 0);
        eq32("reset rx expected data", cfg_rx_expected_data_stream_id, 32'd1);
        eq32("reset rx expected ver", cfg_rx_expected_version_stream_id, 32'd2);
        rd_ok(`DIFI_REG_CONTROL, 0);
        rd_ok(`DIFI_REG_COMMAND, 0);
        rd_ok(`DIFI_REG_STATUS, 2);
        rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, 0);
        rd_ok(`DIFI_REG_DATA_STREAM_ID, 1);
        rd_ok(`DIFI_REG_VERSION_STREAM_ID, 2);
        rd_ok(`DIFI_REG_SAMPLES_PER_PACKET, 256);
        rd_ok(`DIFI_REG_SAMPLE_RATE_HZ, 1000000);
        rd_ok(`DIFI_REG_BANDWIDTH_HZ, 1000000);
        rd_ok(`DIFI_REG_RF_FREQ_LOW, 0);
        rd_ok(`DIFI_REG_RF_FREQ_HIGH, 0);
        rd_ok(`DIFI_REG_CONTEXT_PERIOD_MS, 1000);
        rd_ok(`DIFI_REG_VERSION_PERIOD_MS, 1000);
        rd_ok(`DIFI_REG_RX_FILTER_CTRL, 0);
        rd_ok(`DIFI_REG_RX_DATA_SID, 1);
        rd_ok(`DIFI_REG_RX_VERSION_SID, 2);
        rd_ok(`DIFI_REG_ACTIVE_DATA_SID, 1);
        rd_ok(`DIFI_REG_ACTIVE_VERSION_SID, 2);
        rd_ok(`DIFI_REG_ACTIVE_SAMPLES, 256);
        rd_ok(`DIFI_REG_ACTIVE_SAMPLE_RATE, 1000000);
        rd_ok(`DIFI_REG_ACTIVE_BANDWIDTH, 1000000);
        rd_ok(`DIFI_REG_ACTIVE_RF_LOW, 0);
        rd_ok(`DIFI_REG_ACTIVE_RF_HIGH, 0);
        rd_ok(`DIFI_REG_ACTIVE_CTX_PERIOD, 1000);
        rd_ok(`DIFI_REG_ACTIVE_VER_PERIOD, 1000);
        pulse_done();
        eq1("initial context Done clears pending", context_change_pending, 0);

        scenario("AW/W ordering, WSTRB, reserved control bits, R/B stalls");
        wr(`DIFI_REG_CONTROL, 32'hFFFF_FFFF, 4'b0001, `BRESP_OKAY, 0, 5, 5);  // AW first
        eq1("control enable", tx_enable, 1);
        rd(`DIFI_REG_CONTROL, 1, `RRESP_OKAY, 9);
        wr(`DIFI_REG_CONTROL, 32'd0, 4'b0001, `BRESP_OKAY, 7, 0, 0); // W first
        eq1("control disable", tx_enable, 0);
        wr(`DIFI_REG_CONTROL, 32'hFFFF_FFFF, 4'b0000, `BRESP_OKAY, 0, 0, 0);
        eq1("zero strobe control", tx_enable, 0);
        wr(`DIFI_REG_DATA_STREAM_ID, 32'h1122_3344, 4'b0101, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_DATA_STREAM_ID, 32'h0022_0044);
        wr_ok(`DIFI_REG_DATA_STREAM_ID, SID_NEW);
        wr(`DIFI_REG_SAMPLES_PER_PACKET, 32'hDEAD_BEEF, 4'b1100, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_SAMPLES_PER_PACKET, 256); // upper 16 bits ignored
        wr(`DIFI_REG_SAMPLES_PER_PACKET, 32'hFFFF_0010, 4'b0011, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_SAMPLES_PER_PACKET, 16);
        wr(`DIFI_REG_RX_FILTER_CTRL, 32'hFFFF_FFFF, 4'b0010, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_RX_FILTER_CTRL, 0);
        wr(`DIFI_REG_RX_FILTER_CTRL, 32'hFFFF_FFFF, 4'b0001, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_RX_FILTER_CTRL, 3);
        eq1("rx data enable direct", cfg_rx_data_filter_enable, 1);
        eq1("rx ver enable direct", cfg_rx_version_filter_enable, 1);
        wr(`DIFI_REG_RX_DATA_SID, 32'hAABB_CCDD, 4'b1001, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_RX_DATA_SID, 32'hAA00_00DD);
        eq32("RX direct data sid", cfg_rx_expected_data_stream_id, 32'hAA00_00DD);
        wr_ok(`DIFI_REG_RX_VERSION_SID, 32'h1122_3344);
        eq32("RX direct ver sid", cfg_rx_expected_version_stream_id, 32'h1122_3344);
        wr(`DIFI_REG_COMMAND, 32'd1, 4'b0000, `BRESP_OKAY, 0, 0, 0);
        wr(`DIFI_REG_COMMAND, 32'd1, 4'b0010, `BRESP_OKAY, 0, 0, 0);
        wr(`DIFI_REG_COMMAND, 32'd0, 4'b0001, `BRESP_OKAY, 0, 0, 0);
        eq1("no command issued", cfg_commit_req, 0);
        rd_ok(`DIFI_REG_COMMAND, 0);

        scenario("all 16 WSTRB byte-mask combinations");
        sweep_all_wstrb();
        wr_ok(`DIFI_REG_RX_DATA_SID, 32'hAA00_00DD);

        scenario("RO writes -> SLVERR; holes/unaligned -> DECERR");
        wr(`DIFI_REG_STATUS, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_LAST_COMMIT_ERROR, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_DATA_SID, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_VERSION_SID, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_SAMPLES, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_SAMPLE_RATE, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_BANDWIDTH, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_RF_LOW, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_RF_HIGH, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_CTX_PERIOD, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(`DIFI_REG_ACTIVE_VER_PERIOD, 0, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        wr(8'h01, 0, 4'hF, `BRESP_DECERR, 0, 0, 1);
        wr(8'h0D, 0, 4'hF, `BRESP_DECERR, 0, 0, 0);
        wr(8'h61, 0, 4'hF, `BRESP_DECERR, 0, 0, 0);
        wr(8'h64, 0, 4'hF, `BRESP_DECERR, 0, 0, 0);
        wr(8'hFF, 0, 4'hF, `BRESP_DECERR, 0, 0, 0);
        rd(8'h01, 0, `RRESP_DECERR, 6);
        rd(8'h0D, 0, `RRESP_DECERR, 0);
        rd(8'h61, 0, `RRESP_DECERR, 0);
        rd(8'h64, 0, `RRESP_DECERR, 0);
        rd(8'hFF, 0, `RRESP_DECERR, 0);
        rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, 0); // no commit error from bus errors

        scenario("same-cycle AR and write execution returns PRE-write snapshot");
        // Complete AW/W handshakes (at edge A), FSM transitions to EXECUTE
        // one rising edge later (B). AR is then driven before edge C, when
        // the pending write actually executes. Read returns old Shadow value.
        fork
            send_aw(`DIFI_REG_VERSION_STREAM_ID);
            send_w(32'h1234_5678, 4'hF);
        join
        @(posedge aclk); // edge B: state transitions to EXECUTE
        send_ar(`DIFI_REG_VERSION_STREAM_ID); // edge C: read & write same edge
        collect_r(2, `RRESP_OKAY, 4);
        collect_b(`BRESP_OKAY, 2);
        rd_ok(`DIFI_REG_VERSION_STREAM_ID, 32'h1234_5678);

        scenario("independent AXI R and B channels while B response stalled");
        fork
            begin
                wr(`DIFI_REG_RX_VERSION_SID, 32'h5555_AAAA, 4'hF,
                   `BRESP_OKAY, 0, 0, 15);
            end
            begin
                repeat (6) @(posedge aclk);
                rd(`DIFI_REG_RX_DATA_SID, 32'hAA00_00DD, `RRESP_OKAY, 3);
            end
        join
        rd_ok(`DIFI_REG_RX_VERSION_SID, 32'h5555_AAAA);

        scenario("back-to-back write attempts while first B is stalled");
        fork
            begin
                wr(`DIFI_REG_RX_DATA_SID, 32'h0011_2233, 4'hF,
                   `BRESP_OKAY, 0, 0, 16);
            end
            begin
                repeat (6) @(posedge aclk);
                wr(`DIFI_REG_RX_VERSION_SID, 32'h7788_99AA, 4'hF,
                   `BRESP_OKAY, 0, 0, 0);
            end
        join
        rd_ok(`DIFI_REG_RX_DATA_SID, 32'h0011_2233);
        rd_ok(`DIFI_REG_RX_VERSION_SID, 32'h7788_99AA);

        scenario("write while R is stalled preserves original read snapshot");
        fork
            begin
                rd(`DIFI_REG_RX_DATA_SID, 32'h0011_2233, `RRESP_OKAY, 18);
            end
            begin
                repeat (5) @(posedge aclk);
                wr(`DIFI_REG_RX_DATA_SID, 32'hDEAD_1234, 4'hF,
                   `BRESP_OKAY, 0, 0, 0);
            end
        join
        rd_ok(`DIFI_REG_RX_DATA_SID, 32'hDEAD_1234);

        scenario("legal commit, delayed ACK, active snapshot, BUSY, RX bypass");
        wr_ok(`DIFI_REG_SAMPLE_RATE_HZ, 32'd2_000_000);
        wr_ok(`DIFI_REG_BANDWIDTH_HZ, 32'd1_000_000);
        wr_ok(`DIFI_REG_RF_FREQ_LOW, RF_NEW[31:0]);
        wr_ok(`DIFI_REG_RF_FREQ_HIGH, RF_NEW[63:32]);
        wr_ok(`DIFI_REG_CONTEXT_PERIOD_MS, 0); // zero disables periodic only
        wr_ok(`DIFI_REG_VERSION_PERIOD_MS, 250);
        rd_ok(`DIFI_REG_ACTIVE_DATA_SID, 1);
        wr_ok(`DIFI_REG_COMMAND, 1);
        eq1("commit request asserted", cfg_commit_req, 1);
        rd_ok(`DIFI_REG_STATUS, 1);
        repeat (20) begin
            @(negedge aclk);
            eq1("req sticky without ack", cfg_commit_req, 1);
            eq32("active stays old", cfg_data_stream_id, 1);
            eq64("RF active stays old", cfg_rf_freq_hz, 0);
        end
        wr(`DIFI_REG_DATA_STREAM_ID, 32'hDEAD_BEEF, 4'hF, `BRESP_SLVERR, 0, 0, 0);
        rd_ok(`DIFI_REG_DATA_STREAM_ID, SID_NEW);
        wr(`DIFI_REG_COMMAND, 1, 4'h1, `BRESP_SLVERR, 0, 0, 0);
        rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, `DIFI_COMMIT_ERR_BUSY);
        rd_ok(`DIFI_REG_STATUS, 32'h21);
        wr_ok(`DIFI_REG_RX_VERSION_SID, 32'h1122_7788); // allowed while pending
        eq32("RX filter bypasses TX commit", cfg_rx_expected_version_stream_id, 32'h1122_7788);
        wr_ok(`DIFI_REG_CONTROL, 32'd0); // allowed while pending
        tx_busy = 1; time_valid = 0; // must NOT be prerequisites for ACK
        pulse_ack();
        eq1("req cleared on ack", cfg_commit_req, 0);
        eq1("ctx pending set on ack", context_change_pending, 1);
        eq32("committed data sid", cfg_data_stream_id, SID_NEW);
        eq32("committed ver sid", cfg_version_stream_id, 32'h1234_5678);
        eq32("committed samples", {16'd0,cfg_samples_per_packet}, 16);
        eq32("committed fs", cfg_sample_rate_hz, 2000000);
        eq32("committed bw", cfg_bandwidth_hz, 1000000);
        eq64("committed rf", cfg_rf_freq_hz, RF_NEW);
        eq32("committed ctx period", cfg_context_period_ms, 0);
        eq32("committed ver period", cfg_version_period_ms, 250);
        rd_ok(`DIFI_REG_ACTIVE_RF_LOW, RF_NEW[31:0]);
        rd_ok(`DIFI_REG_ACTIVE_RF_HIGH, RF_NEW[63:32]);
        rd_ok(`DIFI_REG_STATUS, 32'h26); // error + tx busy + context pending
        pulse_done();
        eq1("ctx pending cleared by done", context_change_pending, 0);
        tx_busy = 0; time_valid = 0;
        pulse_ack(); // spurious ACK must do nothing
        eq1("spurious ACK leaves pending clear", context_change_pending, 0);
        eq32("spurious ACK leaves active unchanged", cfg_data_stream_id, SID_NEW);

        scenario("invalid parameter priority and no active mutation");
        wr_ok(`DIFI_REG_SAMPLES_PER_PACKET, 0);
        wr_ok(`DIFI_REG_SAMPLE_RATE_HZ, 0);
        wr_ok(`DIFI_REG_BANDWIDTH_HZ, 0);
        invalid_commit(`DIFI_COMMIT_ERR_SAMPLES); // multiple errors -> first error
        wr_ok(`DIFI_REG_SAMPLES_PER_PACKET, 257);
        invalid_commit(`DIFI_COMMIT_ERR_SAMPLES);
        wr_ok(`DIFI_REG_SAMPLES_PER_PACKET, 16);
        invalid_commit(`DIFI_COMMIT_ERR_SAMPLE_RATE);
        wr_ok(`DIFI_REG_SAMPLE_RATE_HZ, 2_000_000);
        invalid_commit(`DIFI_COMMIT_ERR_BANDWIDTH);
        wr_ok(`DIFI_REG_BANDWIDTH_HZ, 2_000_001);
        invalid_commit(`DIFI_COMMIT_ERR_BANDWIDTH);
        wr_ok(`DIFI_REG_BANDWIDTH_HZ, 1_000_000);
        wr_ok(`DIFI_REG_RF_FREQ_HIGH, 32'h0000_0020); // >100 GHz
        invalid_commit(`DIFI_COMMIT_ERR_RF_FREQ);
        eq32("rejected config must not mutate active", cfg_data_stream_id, SID_NEW);
        eq64("rejected RF must not mutate active", cfg_rf_freq_hz, RF_NEW);
        wr_ok(`DIFI_REG_RF_FREQ_HIGH, RF_NEW[63:32]);
        wr_ok(`DIFI_REG_RF_FREQ_LOW, RF_NEW[31:0]);
        wr(`DIFI_REG_COMMAND, 0, 4'h1, `BRESP_OKAY, 0, 0, 0);
        rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, `DIFI_COMMIT_ERR_RF_FREQ);

        scenario("successful command clears stale error; same-edge ACK+Done set wins");
        wr_ok(`DIFI_REG_DATA_STREAM_ID, 32'h1234_4321);
        wr_ok(`DIFI_REG_COMMAND, 1);
        eq1("accepted req", cfg_commit_req, 1);
        rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, 0);
        // old changed Context completes on precisely the new ACK edge
        @(negedge aclk);
        context_change_done = 1;
        cfg_commit_ack = 1;
        @(posedge aclk);
        @(negedge aclk);
        context_change_done = 0;
        cfg_commit_ack = 0;
        eq1("ACK+Done: newer pending set wins", context_change_pending, 1);
        eq1("ACK+Done: request consumed", cfg_commit_req, 0);
        eq32("ACK+Done active updated", cfg_data_stream_id, 32'h1234_4321);
        pulse_done();
        eq1("Done clears new pending", context_change_pending, 0);

        scenario("reset mid-pending restores Shadow/Active and status");
        wr_ok(`DIFI_REG_DATA_STREAM_ID, 32'hABCD_EF01);
        wr_ok(`DIFI_REG_COMMAND, 1);
        eq1("pre-reset req", cfg_commit_req, 1);
        @(negedge aclk);
        aresetn = 0;
        repeat (4) @(negedge aclk);
        aresetn = 1;
        @(negedge aclk);
        eq1("reset midreq clears request", cfg_commit_req, 0);
        eq1("reset reasserts context pending", context_change_pending, 1);
        eq32("reset active", cfg_data_stream_id, 1);
        rd_ok(`DIFI_REG_DATA_STREAM_ID, 1);
        rd_ok(`DIFI_REG_ACTIVE_DATA_SID, 1);
        rd_ok(`DIFI_REG_LAST_COMMIT_ERROR, 0);

        $display("PASS tb_difi_cfg_regs: %0d scenarios, %0d checks", scenarios, checks);
        $finish;
    end
endmodule
