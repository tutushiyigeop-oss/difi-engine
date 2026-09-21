`timescale 1ns / 1ps
// Packetizer -> Parser integration testbench (Verilog-2001).
// The golden packet and IQ values are generated independently of either DUT.
// Add both RTL modules and this testbench as separate simulation sources.


module tb_difi_loopback;

    localparam integer MAX_SAMPLES = 256;
    localparam integer MAX_PACKETS = 160;
    localparam integer WAIT_LIMIT  = 100000;

    // ------------------------------------------------------------------
    // 1. DUT connections: NO intermediate FIFO or behavioral packet model.
    // ------------------------------------------------------------------
    reg         aclk, aresetn;
    reg         pkt_start;
    wire        pkt_busy, pkt_done;
    reg  [31:0] s_axis_iq_tdata;
    reg         s_axis_iq_tvalid;
    wire        s_axis_iq_tready;
    reg  [31:0] cfg_data_stream_id;
    reg  [15:0] cfg_samples_per_packet;
    reg  [31:0] time_sec;
    reg  [63:0] time_ps;
    reg         time_valid;

    wire [31:0] link_tdata;
    wire        link_tvalid, link_tready;
    wire [3:0]  link_tkeep;
    wire        link_tlast;

    reg         cfg_stream_filter_enable;
    reg  [31:0] cfg_expected_stream_id;
    wire [31:0] m_axis_iq_tdata;
    wire        m_axis_iq_tvalid;
    reg         m_axis_iq_tready;
    wire        m_axis_iq_tlast;
    wire        m_meta_valid;
    reg         m_meta_ready;
    wire [31:0] m_meta_stream_id;
    wire [3:0]  m_meta_seq;
    wire [31:0] m_meta_time_sec;
    wire [63:0] m_meta_time_ps;
    wire [15:0] m_meta_sample_count;
    wire        error_valid;
    wire [3:0]  error_code;

    wire src_fire  = s_axis_iq_tvalid && s_axis_iq_tready;
    wire link_fire = link_tvalid && link_tready;
    wire meta_fire = m_meta_valid && m_meta_ready;
    wire out_fire  = m_axis_iq_tvalid && m_axis_iq_tready;

    difi_data_packetizer u_packetizer (
        .aclk(aclk), .aresetn(aresetn),
        .pkt_start(pkt_start), .pkt_busy(pkt_busy), .pkt_done(pkt_done),
        .s_axis_iq_tdata(s_axis_iq_tdata),
        .s_axis_iq_tvalid(s_axis_iq_tvalid),
        .s_axis_iq_tready(s_axis_iq_tready),
        .cfg_data_stream_id(cfg_data_stream_id),
        .cfg_samples_per_packet(cfg_samples_per_packet),
        .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
        .m_axis_pkt_tdata(link_tdata),
        .m_axis_pkt_tvalid(link_tvalid),
        .m_axis_pkt_tready(link_tready),
        .m_axis_pkt_tkeep(link_tkeep),
        .m_axis_pkt_tlast(link_tlast)
    );

    difi_data_parser u_parser (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_pkt_tdata(link_tdata),
        .s_axis_pkt_tvalid(link_tvalid),
        .s_axis_pkt_tready(link_tready),
        .s_axis_pkt_tkeep(link_tkeep),
        .s_axis_pkt_tlast(link_tlast),
        .cfg_stream_filter_enable(cfg_stream_filter_enable),
        .cfg_expected_stream_id(cfg_expected_stream_id),
        .m_axis_iq_tdata(m_axis_iq_tdata),
        .m_axis_iq_tvalid(m_axis_iq_tvalid),
        .m_axis_iq_tready(m_axis_iq_tready),
        .m_axis_iq_tlast(m_axis_iq_tlast),
        .m_meta_valid(m_meta_valid), .m_meta_ready(m_meta_ready),
        .m_meta_stream_id(m_meta_stream_id), .m_meta_seq(m_meta_seq),
        .m_meta_time_sec(m_meta_time_sec), .m_meta_time_ps(m_meta_time_ps),
        .m_meta_sample_count(m_meta_sample_count),
        .error_valid(error_valid), .error_code(error_code)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk; // 100 MHz

    // ------------------------------------------------------------------
    // 2. Golden transactions: expected values NEVER read from DUT internals.
    // ------------------------------------------------------------------
    integer golden_n       [0:MAX_PACKETS-1];
    reg [31:0] golden_sid   [0:MAX_PACKETS-1];
    reg [31:0] golden_sec   [0:MAX_PACKETS-1];
    reg [63:0] golden_ps    [0:MAX_PACKETS-1];
    reg [3:0]  golden_seq   [0:MAX_PACKETS-1];
    integer golden_tag     [0:MAX_PACKETS-1];
    integer golden_pattern [0:MAX_PACKETS-1];
    integer golden_mode    [0:MAX_PACKETS-1];
    integer golden_tc      [0:MAX_PACKETS-1];
    integer q_count, seq_model, current_tc, passed;
    integer src_id, src_sample;
    integer link_id, link_word;
    integer meta_id, out_id, out_sample;
    integer done_id;

    // Coverage counters are incremented only for REAL stalled VALID beats.
    integer src_stall_total, link_stall_total;
    integer meta_stall_total, iq_stall_total;
    integer meta_stall_now, iq_stall_now;
    integer first_iq_stalls, middle_iq_stalls, last_iq_stalls;
    integer time_gate_cycles, overlap_events;
    integer tick;
    reg     previous_done;
    reg     hold_src, hold_link, hold_meta, hold_out;
    reg [31:0] saved_src, saved_link, saved_out;
    reg [3:0]  saved_keep;
    reg        saved_link_last, saved_out_last;
    reg [31:0] saved_sid, saved_sec;
    reg [3:0]  saved_seq;
    reg [63:0] saved_ps;
    reg [15:0] saved_n;
    reg        release_meta, release_iq;
    reg [31:0] rng;

    task fail;
        input [8*200-1:0] message;
        begin
            $display("[FAIL] TC%0d time=%0t: %0s", current_tc, $time, message);
            $display("  queued=%0d src=%0d:%0d link=%0d:%0d meta=%0d iq=%0d:%0d done=%0d",
                     q_count, src_id, src_sample, link_id, link_word,
                     meta_id, out_id, out_sample, done_id);
            $display("  src v/r=%b/%b link v/r=%b/%b meta v/r=%b/%b iq v/r=%b/%b error=%b/%h",
                     s_axis_iq_tvalid, s_axis_iq_tready,
                     link_tvalid, link_tready, m_meta_valid, m_meta_ready,
                     m_axis_iq_tvalid, m_axis_iq_tready, error_valid, error_code);
            $fatal(1, "Integration scoreboard failure");
        end
    endtask

    function [31:0] sample_value;
        input integer index, tag, pattern;
        begin
            case (pattern)
                1: begin
                    case (index)
                        0: sample_value = 32'h0001_FFFF;
                        1: sample_value = 32'h7FFF_8000;
                        2: sample_value = 32'hFFFE_0003;
                        3: sample_value = 32'h0000_0000;
                        default: sample_value = 32'hBAD0_BAD0;
                    endcase
                end
                2: sample_value = (index & 1) ? 32'h5555_5555 : 32'hAAAA_AAAA;
                3: sample_value = 32'h0000_0000;
                4: sample_value = 32'hFFFF_FFFF;
                5: sample_value = (index & 1) ? 32'h8000_7FFF : 32'h7FFF_8000;
                default: sample_value = 32'h1357_9BDF ^ (tag * 32'h0001_0001)
                                                      ^ (index * 32'h0001_0103);
            endcase
        end
    endfunction

    // Independent fixed DIFI reference header (no DUT macro used here).
    function [31:0] reference_word;
        input integer packet, word;
        begin
            case (word)
                0: reference_word = 32'h1860_0000 |
                                    ({28'd0,golden_seq[packet]} << 16) |
                                    (7 + golden_n[packet]);
                1: reference_word = golden_sid[packet];
                2: reference_word = 32'h006A_621E;
                3: reference_word = 32'h0000_0000;
                4: reference_word = golden_sec[packet];
                5: reference_word = golden_ps[packet][63:32];
                6: reference_word = golden_ps[packet][31:0];
                default: reference_word = sample_value(word - 7,
                                                       golden_tag[packet],
                                                       golden_pattern[packet]);
            endcase
        end
    endfunction

    task queue_packet;
        input integer n;
        input [31:0] sid, sec;
        input [63:0] ps;
        input integer tag, pattern, ready_mode;
        begin
            if (q_count >= MAX_PACKETS || n < 1 || n > MAX_SAMPLES)
                fail("Invalid testbench transaction configuration");
            golden_n[q_count]       = n;
            golden_sid[q_count]     = sid;
            golden_sec[q_count]     = sec;
            golden_ps[q_count]      = ps;
            golden_seq[q_count]     = seq_model;
            golden_tag[q_count]     = tag;
            golden_pattern[q_count] = pattern;
            golden_mode[q_count]    = ready_mode;
            golden_tc[q_count]      = current_tc;
            q_count = q_count + 1;
            seq_model = (seq_model + 1) & 15;
        end
    endtask

    // ------------------------------------------------------------------
    // 3. Edge-based scoreboard and AXI stability assertions.
    // ------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            previous_done = 1'b0;
            hold_src      = 1'b0;
            hold_link     = 1'b0;
            hold_meta     = 1'b0;
            hold_out      = 1'b0;
            meta_stall_now = 0;
            iq_stall_now   = 0;
        end else begin
            if (error_valid !== 1'b0)
                fail("Parser raised an error on a packetizer-generated packet");

            // Every AXI source must hold VALID and its payload during a stall.
            if (hold_src && (s_axis_iq_tvalid !== 1'b1 ||
                             s_axis_iq_tdata !== saved_src))
                fail("Source IQ changed while stalled");
            if (hold_link && (link_tvalid !== 1'b1 ||
                              link_tdata !== saved_link ||
                              link_tkeep !== saved_keep ||
                              link_tlast !== saved_link_last))
                fail("Packetizer link beat changed while stalled");
            if (hold_meta && (m_meta_valid !== 1'b1 ||
                              m_meta_stream_id !== saved_sid ||
                              m_meta_seq !== saved_seq ||
                              m_meta_time_sec !== saved_sec ||
                              m_meta_time_ps !== saved_ps ||
                              m_meta_sample_count !== saved_n))
                fail("Parser metadata changed while stalled");
            if (hold_out && (m_axis_iq_tvalid !== 1'b1 ||
                             m_axis_iq_tdata !== saved_out ||
                             m_axis_iq_tlast !== saved_out_last))
                fail("Parser IQ changed while stalled");

            hold_src  = (s_axis_iq_tvalid === 1'b1 && s_axis_iq_tready === 1'b0);
            hold_link = (link_tvalid === 1'b1 && link_tready === 1'b0);
            hold_meta = (m_meta_valid === 1'b1 && m_meta_ready === 1'b0);
            hold_out  = (m_axis_iq_tvalid === 1'b1 && m_axis_iq_tready === 1'b0);
            if (hold_src) begin
                saved_src = s_axis_iq_tdata;
                src_stall_total = src_stall_total + 1;
                if (!time_valid) time_gate_cycles = time_gate_cycles + 1;
            end
            if (hold_link) begin
                saved_link      = link_tdata;
                saved_keep      = link_tkeep;
                saved_link_last = link_tlast;
                link_stall_total = link_stall_total + 1;
                if (link_id > out_id) overlap_events = overlap_events + 1;
            end
            if (hold_meta) begin
                saved_sid = m_meta_stream_id;
                saved_seq = m_meta_seq;
                saved_sec = m_meta_time_sec;
                saved_ps  = m_meta_time_ps;
                saved_n   = m_meta_sample_count;
                meta_stall_total = meta_stall_total + 1;
                meta_stall_now = meta_stall_now + 1;
            end
            if (hold_out) begin
                saved_out      = m_axis_iq_tdata;
                saved_out_last = m_axis_iq_tlast;
                iq_stall_total = iq_stall_total + 1;
                iq_stall_now = iq_stall_now + 1;
                if (out_sample == 0) first_iq_stalls = first_iq_stalls + 1;
                else if (out_id < q_count && out_sample == golden_n[out_id]-1)
                    last_iq_stalls = last_iq_stalls + 1;
                else middle_iq_stalls = middle_iq_stalls + 1;
            end

            if (src_fire) begin
                if (src_id >= q_count || src_sample >= golden_n[src_id])
                    fail("Unexpected/extra IQ input handshake");
                if (s_axis_iq_tdata !== sample_value(src_sample,
                        golden_tag[src_id], golden_pattern[src_id]))
                    fail("Source IQ handshake differs from original golden sample");
                src_sample = src_sample + 1;
                if (src_sample == golden_n[src_id]) begin
                    src_id = src_id + 1;
                    src_sample = 0;
                end
            end

            if (link_fire) begin
                if (link_id >= q_count || link_word >= 7 + golden_n[link_id])
                    fail("Unexpected/extra intermediate packet word");
                if (link_tdata !== reference_word(link_id,link_word)) begin
                    $display("  link[%0d][%0d] expected=%08h actual=%08h",
                             link_id,link_word,reference_word(link_id,link_word),link_tdata);
                    fail("Packetizer word mismatch against independent reference");
                end
                if (link_tkeep !== 4'hF ||
                    link_tlast !== (link_word == 6 + golden_n[link_id]))
                    fail("Intermediate TKEEP/TLAST mismatch");
                link_word = link_word + 1;
                if (link_word == 7 + golden_n[link_id]) begin
                    link_id = link_id + 1;
                    link_word = 0;
                end
            end

            if (meta_fire) begin
                if (meta_id >= q_count || link_id <= meta_id || meta_id != out_id)
                    fail("Unexpected/early/duplicate metadata handshake");
                if (m_meta_stream_id !== golden_sid[meta_id] ||
                    m_meta_seq !== golden_seq[meta_id] ||
                    m_meta_time_sec !== golden_sec[meta_id] ||
                    m_meta_time_ps !== golden_ps[meta_id] ||
                    m_meta_sample_count !== golden_n[meta_id]) begin
                    $display("  meta[%0d]: expected SID=%h SEQ=%h SEC=%h PS=%h N=%0d",
                        meta_id, golden_sid[meta_id], golden_seq[meta_id],
                        golden_sec[meta_id], golden_ps[meta_id], golden_n[meta_id]);
                    $display("  meta actual: SID=%h SEQ=%h SEC=%h PS=%h N=%0d",
                        m_meta_stream_id,m_meta_seq,m_meta_time_sec,m_meta_time_ps,
                        m_meta_sample_count);
                    fail("Parser metadata mismatch");
                end
                meta_id = meta_id + 1;
                meta_stall_now = 0;
            end

            if (out_fire) begin
                if (out_id >= q_count || meta_id <= out_id ||
                    out_sample >= golden_n[out_id])
                    fail("Unexpected/early/extra recovered IQ sample");
                if (m_axis_iq_tdata !== sample_value(out_sample,
                        golden_tag[out_id], golden_pattern[out_id])) begin
                    $display("  IQ[%0d][%0d]: expected=%08h actual=%08h",
                        out_id, out_sample,
                        sample_value(out_sample,golden_tag[out_id],golden_pattern[out_id]),
                        m_axis_iq_tdata);
                    fail("END-TO-END SAMPLE MISMATCH");
                end
                if (m_axis_iq_tlast !== (out_sample == golden_n[out_id]-1))
                    fail("Recovered IQ TLAST mismatch");
                out_sample = out_sample + 1;
                iq_stall_now = 0;
                if (out_sample == golden_n[out_id]) begin
                    $display("[PASS] TC%0d packet=%0d N=%0d seq=%0d SID=%08h (word/sample/meta checked)",
                        golden_tc[out_id], out_id, golden_n[out_id],
                        golden_seq[out_id],golden_sid[out_id]);
                    passed = passed + 1;
                    out_id = out_id + 1;
                    out_sample = 0;
                end
            end

            if (pkt_done === 1'b1) begin
                if (previous_done || link_id <= done_id || done_id >= q_count)
                    fail("pkt_done duplicated or not associated with a completed packet");
                done_id = done_id + 1;
            end else if (pkt_done !== 1'b0) begin
                fail("pkt_done is unknown");
            end
            previous_done = pkt_done;
            tick = tick + 1;
        end
    end

    // ------------------------------------------------------------------
    // 4. Single-owner READY driver: controlled deterministic backpressure.
    // Modes: 0=none, 1=targeted, 2=long, 3=periodic, 4=manual META,
    //        5=manual first IQ. Both receivers are driven only here.
    // ------------------------------------------------------------------
    always @(negedge aclk) begin
        if (!aresetn) begin
            m_meta_ready     = 1'b1;
            m_axis_iq_tready = 1'b1;
        end else begin
            m_meta_ready     = 1'b1;
            m_axis_iq_tready = 1'b1;
            if (meta_id < q_count) begin
                case (golden_mode[meta_id])
                    1: if (meta_stall_now < 3) m_meta_ready = 1'b0;
                    2: if (meta_stall_now < 18) m_meta_ready = 1'b0;
                    3: if ((tick % 7) < 3) m_meta_ready = 1'b0;
                    4: if (!release_meta) m_meta_ready = 1'b0;
                    default: begin end
                endcase
            end
            if (out_id < q_count) begin
                case (golden_mode[out_id])
                    1: if ((out_sample == 0 ||
                           out_sample == golden_n[out_id]/2 ||
                           out_sample == golden_n[out_id]-1) &&
                           iq_stall_now < 3)
                           m_axis_iq_tready = 1'b0;
                    2: if ((out_sample == 0 || out_sample == golden_n[out_id]-1) &&
                           iq_stall_now < 18)
                           m_axis_iq_tready = 1'b0;
                    3: if ((tick % 5) < 2) m_axis_iq_tready = 1'b0;
                    5: if (!release_iq) m_axis_iq_tready = 1'b0;
                    default: begin end
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // 5. Stimulus: drive ONLY on falling edges, sample ONLY on handshakes.
    // ------------------------------------------------------------------
    task send_sample;
        input integer packet, sample, gap_mode, gate_first;
        integer gap, guard;
        begin
            gap = 0;
            if (sample != 0) begin
                if (gap_mode == 1) gap = (sample % 4);
                if (gap_mode == 2) gap = (sample % 11);
                if (gap_mode == 3) gap = ((sample*7 + packet) % 9);
            end
            repeat (gap) @(negedge aclk);
            @(negedge aclk);
            s_axis_iq_tdata  = sample_value(sample,
                                   golden_tag[packet],golden_pattern[packet]);
            s_axis_iq_tvalid = 1'b1;
            if (sample == 0 && gate_first != 0) begin
                repeat (5) begin
                    @(posedge aclk);
                    if (s_axis_iq_tready !== 1'b0 || link_tvalid !== 1'b0)
                        fail("First IQ consumed/header emitted while time_valid=0");
                end
                @(negedge aclk);
                time_valid = 1'b1;
            end
            guard = 0;
            @(posedge aclk);
            while (s_axis_iq_tready !== 1'b1 && guard < WAIT_LIMIT) begin
                @(posedge aclk);
                guard = guard + 1;
            end
            if (s_axis_iq_tready !== 1'b1)
                fail("Timeout waiting for source IQ handshake");
            @(negedge aclk);
            s_axis_iq_tvalid = 1'b0;
        end
    endtask

    task run_packet;
        input integer n;
        input [31:0] sid, sec;
        input [63:0] ps;
        input integer tag, pattern, mode, gaps, gate_time, change_cfg;
        integer id, j, guard;
        begin
            queue_packet(n,sid,sec,ps,tag,pattern,mode);
            id = q_count - 1;
            @(negedge aclk);
            if (pkt_busy !== 1'b0 || pkt_start !== 1'b0)
                fail("Packetizer not IDLE before pkt_start");
            cfg_data_stream_id     = sid;
            cfg_samples_per_packet = n;
            time_sec               = sec;
            time_ps                = ps;
            time_valid             = (gate_time == 0);
            cfg_stream_filter_enable = 1'b1;
            cfg_expected_stream_id   = sid;
            pkt_start = 1'b1;
            @(negedge aclk);
            pkt_start = 1'b0;
            if (pkt_busy !== 1'b1)
                fail("pkt_busy did not rise after pkt_start");
            for (j = 0; j < n; j = j + 1) begin
                send_sample(id,j,gaps,gate_time);
                if (j == 0 && change_cfg != 0) begin
                    // Packetizer snapshots these on the FIRST IQ handshake.
                    cfg_data_stream_id     = sid ^ 32'h00FF_00FF;
                    cfg_samples_per_packet = 16'd1;
                    time_sec               = sec + 32'd99;
                    time_ps                = ps + 64'd12345;
                    // Parser snapshots its filter on the WORD0 handshake.
                    guard = 0;
                    while (link_id == id && link_word == 0 && guard < WAIT_LIMIT) begin
                        @(negedge aclk);
                        guard = guard + 1;
                    end
                    if (link_id == id && link_word == 0)
                        fail("Timeout waiting for Word0 in snapshot test");
                    cfg_expected_stream_id = sid ^ 32'hFFFF_FFFF;
                    cfg_stream_filter_enable = 1'b0;
                end
            end
            guard = 0;
            while (done_id < id + 1 && guard < WAIT_LIMIT) begin
                @(negedge aclk);
                guard = guard + 1;
            end
            if (done_id < id + 1)
                fail("Timeout waiting for packetizer pkt_done");
        end
    endtask

    task wait_drain;
        integer guard;
        begin
            guard = 0;
            while ((src_id != q_count || link_id != q_count ||
                    done_id != q_count || meta_id != q_count ||
                    out_id != q_count) && guard < WAIT_LIMIT) begin
                @(negedge aclk);
                guard = guard + 1;
            end
            if (src_id != q_count || link_id != q_count ||
                done_id != q_count || meta_id != q_count ||
                out_id != q_count || out_sample != 0 || link_word != 0 ||
                src_sample != 0)
                fail("Timeout/incomplete end-to-end drain");
            repeat (3) @(negedge aclk);
            if (pkt_busy !== 1'b0 || pkt_done !== 1'b0 ||
                link_tvalid !== 1'b0 || m_meta_valid !== 1'b0 ||
                m_axis_iq_tvalid !== 1'b0)
                fail("Unexpected trailing activity after drain");
        end
    endtask

    task apply_idle_reset;
        begin
            wait_drain;
            @(negedge aclk);
            aresetn = 1'b0;
            pkt_start = 1'b0;
            s_axis_iq_tvalid = 1'b0;
            repeat (4) @(negedge aclk);
            seq_model = 0;
            aresetn = 1'b1;
            repeat (2) @(negedge aclk);
            if (pkt_busy !== 1'b0 || link_tvalid !== 1'b0 ||
                m_meta_valid !== 1'b0 || m_axis_iq_tvalid !== 1'b0)
                fail("Reset failed to restore idle outputs");
        end
    endtask

    // ------------------------------------------------------------------
    // 6. Main test plan: directed, overlapped, and deterministic stress.
    // ------------------------------------------------------------------
    integer p, k;
    integer link_stalls_before;
    initial begin
        aresetn = 1'b0;
        pkt_start = 1'b0;
        s_axis_iq_tdata = 0;
        s_axis_iq_tvalid = 1'b0;
        cfg_data_stream_id = 32'd1;
        cfg_samples_per_packet = 16'd4;
        time_sec = 0;
        time_ps = 0;
        time_valid = 1'b1;
        cfg_stream_filter_enable = 1'b1;
        cfg_expected_stream_id = 32'd1;
        m_meta_ready = 1'b1;
        m_axis_iq_tready = 1'b1;
        release_meta = 1'b0;
        release_iq = 1'b0;
        q_count = 0;
        seq_model = 0;
        current_tc = 0;
        passed = 0;
        src_id = 0; src_sample = 0;
        link_id = 0; link_word = 0;
        meta_id = 0; out_id = 0; out_sample = 0; done_id = 0;
        src_stall_total = 0; link_stall_total = 0;
        meta_stall_total = 0; iq_stall_total = 0;
        meta_stall_now = 0; iq_stall_now = 0;
        first_iq_stalls = 0; middle_iq_stalls = 0; last_iq_stalls = 0;
        time_gate_cycles = 0; overlap_events = 0;
        tick = 0;
        rng = 32'h5A17_C0DE;
        previous_done = 0;
        hold_src = 0; hold_link = 0; hold_meta = 0; hold_out = 0;

        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc = 1;
        $display("\n=== TC01: independent 4-sample golden vector ===");
        run_packet(4,32'd1,32'd100,64'd0,1,1,0,0,0,0);
        wait_drain;

        current_tc = 2;
        $display("\n=== TC02: N=1/2/127/255/256 and IQ bit patterns ===");
        run_packet(1,  32'd1,32'd101,64'd123,2,0,0,0,0,0);
        run_packet(2,  32'd1,32'd102,64'd456,3,5,0,0,0,0);
        run_packet(127,32'd1,32'd103,64'd789,4,2,0,0,0,0);
        run_packet(255,32'd1,32'd104,64'd987,5,3,0,0,0,0);
        run_packet(256,32'd1,32'd105,64'd654,6,4,0,0,0,0);
        wait_drain;

        current_tc = 3;
        $display("\n=== TC03: 20 packets, sequence 15->0 and no false errors ===");
        for (p=0;p<20;p=p+1)
            run_packet(4,32'd1,32'd200+p,64'd123456+p,p+10,0,0,0,0,0);
        wait_drain;

        current_tc = 4;
        $display("\n=== TC04: input bubbles, sample order and boundary gaps ===");
        run_packet(32, 32'h1122_3344,32'd300,64'd1000,40,0,0,1,0,0);
        run_packet(256,32'h1122_3344,32'd301,64'd2000,41,0,0,2,0,0);
        wait_drain;

        current_tc = 5;
        $display("\n=== TC05: targeted META/first/middle/last IQ backpressure ===");
        run_packet(1,32'd1,32'd400,64'd5,50,0,1,0,0,0);
        run_packet(4,32'd1,32'd401,64'd6,51,0,1,0,0,0);
        run_packet(256,32'd1,32'd402,64'd7,52,0,1,0,0,0);
        wait_drain;
        if (meta_stall_total < 9 || first_iq_stalls < 9 ||
            middle_iq_stalls < 3 || last_iq_stalls < 6)
            fail("Targeted backpressure coverage was not exercised");

        current_tc = 6;
        $display("\n=== TC06: extended stalls plus periodic ready toggling ===");
        run_packet(16,32'h1234_5678,32'd500,64'd8,60,0,2,0,0,0);
        run_packet(64,32'h1234_5678,32'd501,64'd9,61,0,3,1,0,0);
        wait_drain;

        current_tc = 7;
        $display("\n=== TC07: first-IQ time_valid gate ===");
        run_packet(4,32'd1,32'd600,64'd987654321,70,0,0,0,1,0);
        wait_drain;
        if (time_gate_cycles < 5)
            fail("time_valid gate was not actually exercised");

        current_tc = 8;
        $display("\n=== TC08: packetizer and parser config/timestamp snapshots ===");
        run_packet(4,32'h0123_4567,32'd700,64'd111222333,80,0,0,0,0,1);
        wait_drain;

        current_tc = 9;
        $display("\n=== TC09: genuine packet-to-packet overlap / no intermediate FIFO ===");
        link_stalls_before = link_stall_total;
        run_packet(256,32'd1,32'd800,64'd100,90,0,1,0,0,0);
        // Start the next packet when the first parser is still outputting IQ.
        run_packet(16,32'd1,32'd801,64'd101,91,0,0,0,0,0);
        run_packet(4,32'd1,32'd802,64'd102,92,0,0,0,0,0);
        wait_drain;
        if (link_stall_total <= link_stalls_before)
            fail("Packet-to-packet link stall/overlap was not exercised");

        current_tc = 10;
        $display("\n=== TC10: manual 8+ cycle metadata stall ===");
        release_meta = 1'b0;
        run_packet(4,32'd1,32'd900,64'd0,100,0,4,0,0,0);
        while (meta_stall_now < 8) @(negedge aclk);
        release_meta = 1'b1;
        wait_drain;

        current_tc = 11;
        $display("\n=== TC11: manual 8+ cycle IQ stall ===");
        release_iq = 1'b0;
        run_packet(4,32'd1,32'd901,64'd0,101,0,5,0,0,0);
        while (iq_stall_now < 8) @(negedge aclk);
        release_iq = 1'b1;
        wait_drain;

        current_tc = 12;
        $display("\n=== TC12: 48 deterministic stress transactions ===");
        for (p=0;p<48;p=p+1) begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
            k = 1 + ((rng & 32'h0000_FFFF) % 256);
            run_packet(k,32'h0A00_0000 | (p & 3),32'd1000+p,
                       64'd1000 + ((rng & 32'h0000_FFFF)*64'd100000),
                       p+120,p%6,p%4,p%4,0,0);
        end
        wait_drain;

        current_tc = 13;
        $display("\n=== TC13: both DUTs reset, packet sequence/base restart ===");
        apply_idle_reset;
        run_packet(4,32'd1,32'd2000,64'd0,200,0,0,0,0,0);
        run_packet(1,32'd1,32'd2001,64'd0,201,0,1,0,0,0);
        wait_drain;

        current_tc = 14;
        $display("\n=== TC14: reset while packetizer waits for first IQ ===");
        @(negedge aclk);
        cfg_data_stream_id = 32'd1;
        cfg_samples_per_packet = 4;
        time_valid = 1'b0;
        pkt_start = 1'b1;
        @(negedge aclk);
        pkt_start = 1'b0;
        repeat (4) begin
            @(posedge aclk);
            if (pkt_busy !== 1'b1 || link_tvalid !== 1'b0)
                fail("Unexpected data while waiting for timestamp");
        end
        @(negedge aclk);
        aresetn = 1'b0;
        s_axis_iq_tvalid = 1'b0;
        repeat (4) @(negedge aclk);
        aresetn = 1'b1;
        seq_model = 0;
        time_valid = 1'b1;
        repeat (2) @(negedge aclk);
        if (pkt_busy !== 1'b0 || link_tvalid !== 1'b0)
            fail("Reset in WAIT_FIRST did not abort pending packet");
        run_packet(4,32'd1,32'd2100,64'd0,210,0,0,0,0,0);
        wait_drain;

        if (passed != q_count)
            fail("End-of-suite packet count mismatch");
        if (src_stall_total == 0 || link_stall_total == 0 ||
            meta_stall_total == 0 || iq_stall_total == 0 || overlap_events == 0)
            fail("A required integration backpressure/overlap path was untested");
        $display("\nALL TESTS PASSED: TC01-TC14, %0d packets", passed);
        $display("  stalls: src=%0d link=%0d meta=%0d IQ=%0d, time-gate=%0d, overlap=%0d",
                 src_stall_total,link_stall_total,meta_stall_total,iq_stall_total,
                 time_gate_cycles,overlap_events);
        $finish;
    end

    // Global deadlock protection, including accidentally unbounded wait loops.
    initial begin
        #5000000;
        fail("Global simulation timeout");
    end

endmodule
