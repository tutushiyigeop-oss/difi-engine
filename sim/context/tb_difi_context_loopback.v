`timescale 1ns / 1ps

module tb_difi_context_loopback;

    localparam integer MAX_PACKETS = 96;
    localparam integer WAIT_LIMIT  = 100000;

    reg         aclk;
    reg         aresetn;

    reg         pkt_start;
    wire        pkt_busy;
    wire        pkt_done;

    reg  [31:0] cfg_data_stream_id;
    reg  [31:0] cfg_sample_rate_hz;
    reg  [31:0] cfg_bandwidth_hz;
    reg  [63:0] cfg_rf_freq_hz;
    reg         cfg_context_change_pending;
    wire        context_change_done;

    reg  [31:0] time_sec;
    reg  [63:0] time_ps;
    reg         time_valid;

    wire [31:0] link_tdata;
    wire        link_tvalid;
    wire        link_tready;
    wire [3:0]  link_tkeep;
    wire        link_tlast;

    reg         cfg_stream_filter_enable;
    reg  [31:0] cfg_expected_stream_id;

    wire        m_ctx_valid;
    reg         m_ctx_ready;
    wire [31:0] m_ctx_stream_id;
    wire [3:0]  m_ctx_seq;
    wire [31:0] m_ctx_time_sec;
    wire [63:0] m_ctx_time_ps;
    wire        m_ctx_changed;
    wire [31:0] m_ctx_bandwidth_hz;
    wire [63:0] m_ctx_rf_freq_hz;
    wire [31:0] m_ctx_sample_rate_hz;

    wire        error_valid;
    wire [3:0]  error_code;

    wire link_fire = link_tvalid && link_tready;
    wire meta_fire = m_ctx_valid && m_ctx_ready;

    difi_context_generator u_generator (
        .aclk(aclk),
        .aresetn(aresetn),
        .pkt_start(pkt_start),
        .pkt_busy(pkt_busy),
        .pkt_done(pkt_done),
        .cfg_data_stream_id(cfg_data_stream_id),
        .cfg_sample_rate_hz(cfg_sample_rate_hz),
        .cfg_bandwidth_hz(cfg_bandwidth_hz),
        .cfg_rf_freq_hz(cfg_rf_freq_hz),
        .cfg_context_change_pending(cfg_context_change_pending),
        .context_change_done(context_change_done),
        .time_sec(time_sec),
        .time_ps(time_ps),
        .time_valid(time_valid),
        .m_axis_pkt_tdata(link_tdata),
        .m_axis_pkt_tvalid(link_tvalid),
        .m_axis_pkt_tready(link_tready),
        .m_axis_pkt_tkeep(link_tkeep),
        .m_axis_pkt_tlast(link_tlast)
    );

    difi_context_parser u_parser (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_pkt_tdata(link_tdata),
        .s_axis_pkt_tvalid(link_tvalid),
        .s_axis_pkt_tready(link_tready),
        .s_axis_pkt_tkeep(link_tkeep),
        .s_axis_pkt_tlast(link_tlast),
        .cfg_stream_filter_enable(cfg_stream_filter_enable),
        .cfg_expected_stream_id(cfg_expected_stream_id),
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
        .error_valid(error_valid),
        .error_code(error_code)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk; 

    reg [31:0] golden_sid       [0:MAX_PACKETS-1];
    reg [31:0] golden_fs        [0:MAX_PACKETS-1];
    reg [31:0] golden_bw        [0:MAX_PACKETS-1];
    reg [63:0] golden_rf        [0:MAX_PACKETS-1];
    reg [63:0] golden_bw_raw    [0:MAX_PACKETS-1];
    reg [63:0] golden_rf_raw    [0:MAX_PACKETS-1];
    reg [63:0] golden_fs_raw    [0:MAX_PACKETS-1];
    reg        golden_change    [0:MAX_PACKETS-1];
    reg [31:0] golden_sec       [0:MAX_PACKETS-1];
    reg [63:0] golden_ps        [0:MAX_PACKETS-1];
    reg [3:0]  golden_seq       [0:MAX_PACKETS-1];
    integer    golden_mode      [0:MAX_PACKETS-1];
    integer    golden_tc        [0:MAX_PACKETS-1];

    integer q_count;
    integer seq_model;
    integer current_tc;
    integer passed;

    integer link_id;
    integer link_word;
    integer meta_id;
    integer done_id;

    integer tick;
    integer link_stall_total;
    integer meta_stall_total;
    integer meta_stall_now;
    integer overlap_stall_total;
    integer change_done_total;

    reg previous_done;
    reg previous_change_done;

    reg hold_link;
    reg hold_meta;
    reg [31:0] saved_link_data;
    reg [3:0]  saved_link_keep;
    reg        saved_link_last;

    reg [31:0] saved_ctx_sid;
    reg [3:0]  saved_ctx_seq;
    reg [31:0] saved_ctx_sec;
    reg [63:0] saved_ctx_ps;
    reg        saved_ctx_changed;
    reg [31:0] saved_ctx_bw;
    reg [63:0] saved_ctx_rf;
    reg [31:0] saved_ctx_fs;

    reg release_meta;

    task fail;
        input [8*220-1:0] message;
        begin
            $display("[FAIL] TC%0d time=%0t: %0s", current_tc, $time, message);
            $display("  queued=%0d link=%0d:%0d meta=%0d done=%0d",
                     q_count, link_id, link_word, meta_id, done_id);
            $display("  busy/start=%b/%b link v/r=%b/%b meta v/r=%b/%b done/change_done=%b/%b error=%b/%h",
                     pkt_busy, pkt_start,
                     link_tvalid, link_tready,
                     m_ctx_valid, m_ctx_ready,
                     pkt_done, context_change_done,
                     error_valid, error_code);
            $fatal(1, "Context loopback scoreboard failure");
        end
    endtask

    function [31:0] reference_word;
        input integer packet;
        input integer word_index;
        begin
            case (word_index)
                 0: reference_word = 32'h4960_001B |
                                     ({28'd0, golden_seq[packet]} << 16);
                 1: reference_word = golden_sid[packet];
                 2: reference_word = 32'h006A_621E;
                 3: reference_word = 32'h0000_0001;
                 4: reference_word = golden_sec[packet];
                 5: reference_word = golden_ps[packet][63:32];
                 6: reference_word = golden_ps[packet][31:0];
                 7: reference_word = golden_change[packet] ?
                                     32'hFBB9_8000 : 32'h7BB9_8000;
                 8: reference_word = 32'h0000_0064;
                 9: reference_word = golden_bw_raw[packet][63:32];
                10: reference_word = golden_bw_raw[packet][31:0];
                11: reference_word = 32'h0000_0000;
                12: reference_word = 32'h0000_0000;
                13: reference_word = golden_rf_raw[packet][63:32];
                14: reference_word = golden_rf_raw[packet][31:0];
                15: reference_word = 32'h0000_0000;
                16: reference_word = 32'h0000_0000;
                17: reference_word = 32'h0000_0000;
                18: reference_word = 32'h0000_0000;
                19: reference_word = golden_fs_raw[packet][63:32];
                20: reference_word = golden_fs_raw[packet][31:0];
                21: reference_word = 32'h0000_0000;
                22: reference_word = 32'h0000_0000;
                23: reference_word = 32'h0000_0000;
                24: reference_word = 32'h0000_0000;
                25: reference_word = 32'hA000_03CF;
                26: reference_word = 32'h0000_0000;
                default: reference_word = 32'hDEAD_BEEF;
            endcase
        end
    endfunction

    task queue_packet;
        input [31:0] sid;
        input [31:0] fs;
        input [31:0] bw;
        input [63:0] rf;
        input        change_flag;
        input [31:0] sec;
        input [63:0] ps;
        input integer ready_mode;
        begin
            if (q_count >= MAX_PACKETS)
                fail("Golden queue overflow");
            if (fs == 0 || bw == 0 || bw > fs)
                fail("Invalid golden BW/Fs configuration");
            if (rf > 64'd100000000000)
                fail("Invalid golden RF configuration");
            if (ps >= 64'd1000000000000)
                fail("Invalid golden timestamp configuration");

            golden_sid[q_count]    = sid;
            golden_fs[q_count]     = fs;
            golden_bw[q_count]     = bw;
            golden_rf[q_count]     = rf;
            golden_bw_raw[q_count] = ({32'd0, bw} << 20);
            golden_rf_raw[q_count] = (rf << 20);
            golden_fs_raw[q_count] = ({32'd0, fs} << 20);
            golden_change[q_count] = change_flag;
            golden_sec[q_count]    = sec;
            golden_ps[q_count]     = ps;
            golden_seq[q_count]    = seq_model[3:0];
            golden_mode[q_count]   = ready_mode;
            golden_tc[q_count]     = current_tc;

            q_count = q_count + 1;
            seq_model = (seq_model + 1) & 15;
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            previous_done        = 1'b0;
            previous_change_done = 1'b0;
            hold_link            = 1'b0;
            hold_meta            = 1'b0;
            meta_stall_now       = 0;
        end else begin
            
            if (error_valid !== 1'b0)
                fail("Parser raised an error on a generator-produced Context packet");

            if (hold_link && (link_tvalid !== 1'b1 ||
                              link_tdata  !== saved_link_data ||
                              link_tkeep  !== saved_link_keep ||
                              link_tlast  !== saved_link_last))
                fail("Generator packet beat changed while stalled");

            // Keep metadata stable while VALID=1 and READY=0.
            if (hold_meta && (m_ctx_valid          !== 1'b1 ||
                              m_ctx_stream_id      !== saved_ctx_sid ||
                              m_ctx_seq            !== saved_ctx_seq ||
                              m_ctx_time_sec       !== saved_ctx_sec ||
                              m_ctx_time_ps        !== saved_ctx_ps ||
                              m_ctx_changed        !== saved_ctx_changed ||
                              m_ctx_bandwidth_hz   !== saved_ctx_bw ||
                              m_ctx_rf_freq_hz     !== saved_ctx_rf ||
                              m_ctx_sample_rate_hz !== saved_ctx_fs))
                fail("Context metadata changed while stalled");

            hold_link = (link_tvalid === 1'b1 && link_tready === 1'b0);
            hold_meta = (m_ctx_valid === 1'b1 && m_ctx_ready === 1'b0);

            if (hold_link) begin
                saved_link_data = link_tdata;
                saved_link_keep = link_tkeep;
                saved_link_last = link_tlast;
                link_stall_total = link_stall_total + 1;
                if (meta_id < q_count)
                    overlap_stall_total = overlap_stall_total + 1;
            end

            if (hold_meta) begin
                saved_ctx_sid     = m_ctx_stream_id;
                saved_ctx_seq     = m_ctx_seq;
                saved_ctx_sec     = m_ctx_time_sec;
                saved_ctx_ps      = m_ctx_time_ps;
                saved_ctx_changed = m_ctx_changed;
                saved_ctx_bw      = m_ctx_bandwidth_hz;
                saved_ctx_rf      = m_ctx_rf_freq_hz;
                saved_ctx_fs      = m_ctx_sample_rate_hz;
                meta_stall_total  = meta_stall_total + 1;
                meta_stall_now    = meta_stall_now + 1;
            end

            if (link_fire) begin
                if (link_id >= q_count || link_word >= 27)
                    fail("Unexpected/extra Context packet word");

                if (link_tdata !== reference_word(link_id, link_word)) begin
                    $display("  link[%0d][%0d] expected=%08h actual=%08h",
                             link_id, link_word,
                             reference_word(link_id, link_word), link_tdata);
                    fail("Generator Context word mismatch against independent reference");
                end

                if (link_tkeep !== 4'hF)
                    fail("Generator TKEEP is not 4'b1111");
                if (link_tlast !== (link_word == 26))
                    fail("Generator TLAST is not exactly on Word26");

                link_word = link_word + 1;
                if (link_word == 27) begin
                    link_id = link_id + 1;
                    link_word = 0;
                end
            end

            if (meta_fire) begin
                if (meta_id >= q_count || link_id <= meta_id)
                    fail("Unexpected/early/duplicate Context metadata handshake");

                if (m_ctx_stream_id      !== golden_sid[meta_id] ||
                    m_ctx_seq            !== golden_seq[meta_id] ||
                    m_ctx_time_sec       !== golden_sec[meta_id] ||
                    m_ctx_time_ps        !== golden_ps[meta_id] ||
                    m_ctx_changed        !== golden_change[meta_id] ||
                    m_ctx_bandwidth_hz   !== golden_bw[meta_id] ||
                    m_ctx_rf_freq_hz     !== golden_rf[meta_id] ||
                    m_ctx_sample_rate_hz !== golden_fs[meta_id]) begin
                    $display("  meta[%0d] expected: SID=%08h SEQ=%0d SEC=%08h PS=%0d CHG=%b BW=%0d RF=%0d FS=%0d",
                             meta_id, golden_sid[meta_id], golden_seq[meta_id],
                             golden_sec[meta_id], golden_ps[meta_id], golden_change[meta_id],
                             golden_bw[meta_id], golden_rf[meta_id], golden_fs[meta_id]);
                    $display("  meta actual:      SID=%08h SEQ=%0d SEC=%08h PS=%0d CHG=%b BW=%0d RF=%0d FS=%0d",
                             m_ctx_stream_id, m_ctx_seq, m_ctx_time_sec, m_ctx_time_ps,
                             m_ctx_changed, m_ctx_bandwidth_hz,
                             m_ctx_rf_freq_hz, m_ctx_sample_rate_hz);
                    fail("Parser Context metadata mismatch");
                end

                $display("[PASS] TC%0d packet=%0d seq=%0d SID=%08h change=%b BW=%0d RF=%0d Fs=%0d",
                         golden_tc[meta_id], meta_id, golden_seq[meta_id],
                         golden_sid[meta_id], golden_change[meta_id],
                         golden_bw[meta_id], golden_rf[meta_id], golden_fs[meta_id]);

                passed = passed + 1;
                meta_id = meta_id + 1;
                meta_stall_now = 0;
            end

            if (pkt_done === 1'b1) begin
                if (previous_done || done_id >= q_count || link_id <= done_id)
                    fail("pkt_done duplicated or occurred before complete packet handshake");

                if (context_change_done !== golden_change[done_id])
                    fail("context_change_done does not match the snapshotted change flag");

                if (context_change_done === 1'b1)
                    change_done_total = change_done_total + 1;

                done_id = done_id + 1;
            end else if (pkt_done !== 1'b0) begin
                fail("pkt_done is unknown");
            end

            if (context_change_done === 1'b1 && pkt_done !== 1'b1)
                fail("context_change_done asserted without pkt_done");
            if (context_change_done !== 1'b0 && context_change_done !== 1'b1)
                fail("context_change_done is unknown");
            if (previous_change_done && context_change_done)
                fail("context_change_done lasted more than one cycle");

            previous_done        = pkt_done;
            previous_change_done = context_change_done;
            tick = tick + 1;
        end
    end

    always @(negedge aclk) begin
        if (!aresetn) begin
            m_ctx_ready = 1'b1;
        end else begin
            m_ctx_ready = 1'b1;
            if (meta_id < q_count) begin
                case (golden_mode[meta_id])
                    1: if (meta_stall_now < 3)
                           m_ctx_ready = 1'b0;
                    2: if (meta_stall_now < 18)
                           m_ctx_ready = 1'b0;
                    3: if ((tick % 7) < 3)
                           m_ctx_ready = 1'b0;
                    4: if (!release_meta)
                           m_ctx_ready = 1'b0;
                    default: begin end
                endcase
            end
        end
    end

    task run_packet;
        input [31:0] sid;
        input [31:0] fs;
        input [31:0] bw;
        input [63:0] rf;
        input        change_flag;
        input [31:0] sec;
        input [63:0] ps;
        input integer ready_mode;
        input integer filter_enable;
        input integer snapshot_test;
        integer id;
        integer guard;
        begin
            queue_packet(sid, fs, bw, rf, change_flag, sec, ps, ready_mode);
            id = q_count - 1;

            guard = 0;
            while (pkt_busy !== 1'b0 && guard < WAIT_LIMIT) begin
                @(negedge aclk);
                guard = guard + 1;
            end
            if (pkt_busy !== 1'b0)
                fail("Timeout waiting for Context Generator idle");

            @(negedge aclk);
            cfg_data_stream_id          = sid;
            cfg_sample_rate_hz          = fs;
            cfg_bandwidth_hz            = bw;
            cfg_rf_freq_hz              = rf;
            cfg_context_change_pending  = change_flag;
            time_sec                    = sec;
            time_ps                     = ps;
            time_valid                  = 1'b1;
            cfg_stream_filter_enable    = filter_enable;
            cfg_expected_stream_id      = sid;

            pkt_start = 1'b1;
            @(negedge aclk);
            pkt_start = 1'b0;

            if (pkt_busy !== 1'b1)
                fail("pkt_busy did not rise after accepted Context pkt_start");

            if (snapshot_test != 0) begin
                
                cfg_data_stream_id         = sid ^ 32'h00FF_00FF;
                cfg_sample_rate_hz         = fs + 32'd123;
                cfg_bandwidth_hz           = 32'd1;
                cfg_rf_freq_hz             = rf + 64'd12345;
                cfg_context_change_pending = ~change_flag;
                time_sec                   = sec + 32'd99;
                if (ps < 64'd999999987655)
                    time_ps = ps + 64'd12345;
                else
                    time_ps = 64'd0;

                // Save this packet's filter settings when receiving Word0.
                
                guard = 0;
                while ((link_id == id) && (link_word == 0) &&
                       (guard < WAIT_LIMIT)) begin
                    @(negedge aclk);
                    guard = guard + 1;
                end
                if ((link_id == id) && (link_word == 0))
                    fail("Timeout waiting for Context Word0 in snapshot test");

                cfg_stream_filter_enable = 1'b1;
                cfg_expected_stream_id   = sid ^ 32'hFFFF_FFFF;
            end

            guard = 0;
            while (done_id < id + 1 && guard < WAIT_LIMIT) begin
                @(negedge aclk);
                guard = guard + 1;
            end
            if (done_id < id + 1)
                fail("Timeout waiting for Context Generator pkt_done");
        end
    endtask

    task wait_drain;
        integer guard;
        begin
            guard = 0;
            while ((link_id != q_count || done_id != q_count ||
                    meta_id != q_count) && guard < WAIT_LIMIT) begin
                @(negedge aclk);
                guard = guard + 1;
            end

            if (link_id != q_count || done_id != q_count ||
                meta_id != q_count || link_word != 0)
                fail("Timeout/incomplete Context loopback drain");

            repeat (3) @(negedge aclk);
            if (pkt_busy !== 1'b0 || pkt_done !== 1'b0 ||
                context_change_done !== 1'b0 ||
                link_tvalid !== 1'b0 || m_ctx_valid !== 1'b0)
                fail("Unexpected trailing activity after Context drain");
        end
    endtask

    task apply_idle_reset;
        begin
            wait_drain;
            @(negedge aclk);
            aresetn  = 1'b0;
            pkt_start = 1'b0;
            time_valid = 1'b0;
            repeat (4) @(negedge aclk);

            seq_model = 0;
            aresetn = 1'b1;
            time_valid = 1'b1;
            repeat (2) @(negedge aclk);

            if (pkt_busy !== 1'b0 || pkt_done !== 1'b0 ||
                context_change_done !== 1'b0 ||
                link_tvalid !== 1'b0 || m_ctx_valid !== 1'b0)
                fail("Reset failed to restore Context loopback idle state");
        end
    endtask

    integer p;
    integer link_stalls_before;
    integer change_done_before;
    reg [31:0] stress_fs;
    reg [31:0] stress_bw;
    reg [63:0] stress_rf;
    reg [63:0] stress_ps;

    initial begin
        aresetn = 1'b0;
        pkt_start = 1'b0;
        cfg_data_stream_id = 32'd1;
        cfg_sample_rate_hz = 32'd20000000;
        cfg_bandwidth_hz = 32'd10000000;
        cfg_rf_freq_hz = 64'd100000000;
        cfg_context_change_pending = 1'b1;
        time_sec = 32'd0;
        time_ps = 64'd0;
        time_valid = 1'b1;
        cfg_stream_filter_enable = 1'b1;
        cfg_expected_stream_id = 32'd1;
        m_ctx_ready = 1'b1;
        release_meta = 1'b0;

        q_count = 0;
        seq_model = 0;
        current_tc = 0;
        passed = 0;
        link_id = 0;
        link_word = 0;
        meta_id = 0;
        done_id = 0;
        tick = 0;
        link_stall_total = 0;
        meta_stall_total = 0;
        meta_stall_now = 0;
        overlap_stall_total = 0;
        change_done_total = 0;
        previous_done = 1'b0;
        previous_change_done = 1'b0;
        hold_link = 1'b0;
        hold_meta = 1'b0;

        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc = 1;
        $display("\n=== TC01: official 27-word Signal Context golden vector ===");
        run_packet(32'h0000_0001,
                   32'd20000000,
                   32'd10000000,
                   64'd100000000,
                   1'b1,
                   32'd100,
                   64'd0,
                   0, 1, 0);
        wait_drain;

        current_tc = 2;
        $display("\n=== TC02: Context no-change + alternate valid metadata ===");
        run_packet(32'h1122_3344,
                   32'd16000000,
                   32'd8000000,
                   64'd2450000000,
                   1'b0,
                   32'd123456,
                   64'd987654321,
                   0, 1, 0);
        wait_drain;

        current_tc = 3;
        $display("\n=== TC03: Context legal boundary values ===");
        run_packet(32'h0000_0001,
                   32'd1,
                   32'd1,
                   64'd0,
                   1'b1,
                   32'hFFFF_FFFE,
                   64'd999999999999,
                   1, 1, 0);
        run_packet(32'h0000_0001,
                   32'hFFFF_FFFF,
                   32'hFFFF_FFFF,
                   64'd100000000000,
                   1'b0,
                   32'hFFFF_FFFF,
                   64'd1,
                   1, 1, 0);
        wait_drain;

        current_tc = 4;
        $display("\n=== TC04: 20 Context packets, sequence wraparound ===");
        for (p = 0; p < 20; p = p + 1) begin
            run_packet(32'h0000_0001,
                       32'd20000000,
                       32'd10000000,
                       64'd100000000 + p,
                       (p % 3) == 0,
                       32'd1000 + p,
                       64'd100 + p,
                       0, 1, 0);
        end
        wait_drain;

        current_tc = 5;
        $display("\n=== TC05: metadata backpressure and natural packet overlap ===");
        link_stalls_before = link_stall_total;
        run_packet(32'hA5A5_0001,
                   32'd40000000,
                   32'd20000000,
                   64'd3500000000,
                   1'b1,
                   32'd2000,
                   64'd55,
                   2, 1, 0);
        
        run_packet(32'hA5A5_0001,
                   32'd40000000,
                   32'd10000000,
                   64'd3500000001,
                   1'b0,
                   32'd2001,
                   64'd56,
                   0, 1, 0);
        wait_drain;
        if (link_stall_total <= link_stalls_before)
            fail("Natural Generator->Parser link backpressure was not exercised");
        if (meta_stall_total < 18)
            fail("Long metadata backpressure was not exercised");

        current_tc = 6;
        $display("\n=== TC06: Generator config/time/change + Parser filter snapshots ===");
        run_packet(32'h0123_4567,
                   32'd32000000,
                   32'd12000000,
                   64'd9150000000,
                   1'b1,
                   32'd3000,
                   64'd123456789,
                   1, 1, 1);
        wait_drain;

        run_packet(32'h89AB_CDEF,
                   32'd25000000,
                   32'd5000000,
                   64'd2400000000,
                   1'b0,
                   32'd3001,
                   64'd222333444,
                   0, 1, 1);
        wait_drain;

        current_tc = 7;
        $display("\n=== TC07: time_valid=0 rejects Context pkt_start ===");
        @(negedge aclk);
        time_valid = 1'b0;
        pkt_start = 1'b1;
        @(negedge aclk);
        pkt_start = 1'b0;
        repeat (6) begin
            @(posedge aclk);
            if (pkt_busy !== 1'b0 || link_tvalid !== 1'b0 ||
                pkt_done !== 1'b0 || context_change_done !== 1'b0)
                fail("Context Generator accepted/emitted packet while time_valid=0");
        end
        @(negedge aclk);
        time_valid = 1'b1;
        run_packet(32'h0000_0001,
                   32'd20000000,
                   32'd10000000,
                   64'd100000000,
                   1'b1,
                   32'd4000,
                   64'd0,
                   0, 1, 0);
        wait_drain;

        current_tc = 8;
        $display("\n=== TC08: filter disabled, SID A -> B -> A ===");
        run_packet(32'h0000_00A1,
                   32'd12000000, 32'd6000000, 64'd700000000,
                   1'b0, 32'd5000, 64'd10, 0, 0, 0);
        run_packet(32'h0000_00B2,
                   32'd12000000, 32'd6000000, 64'd800000000,
                   1'b0, 32'd5001, 64'd11, 0, 0, 0);
        run_packet(32'h0000_00A1,
                   32'd12000000, 32'd6000000, 64'd900000000,
                   1'b1, 32'd5002, 64'd12, 0, 0, 0);
        wait_drain;

        current_tc = 9;
        $display("\n=== TC09: 24 deterministic Context stress packets ===");
        for (p = 0; p < 24; p = p + 1) begin
            stress_fs = 32'd2000000 + p * 32'd1000000;
            stress_bw = 32'd1000000 + p * 32'd250000;
            if (stress_bw > stress_fs)
                stress_bw = stress_fs;
            stress_rf = 64'd100000000 + p * 64'd125000000;
            stress_ps = 64'd1000 + p * 64'd1234567;

            run_packet(32'h0C00_0000 | (p & 3),
                       stress_fs,
                       stress_bw,
                       stress_rf,
                       (p & 1),
                       32'd6000 + p,
                       stress_ps,
                       p % 4,
                       1,
                       0);
        end
        wait_drain;

        current_tc = 10;
        $display("\n=== TC10: idle reset, sequence/baseline restart ===");
        apply_idle_reset;
        change_done_before = change_done_total;
        run_packet(32'h0000_0001,
                   32'd20000000,
                   32'd10000000,
                   64'd100000000,
                   1'b1,
                   32'd7000,
                   64'd0,
                   1, 1, 0);
        run_packet(32'h0000_0001,
                   32'd20000000,
                   32'd10000000,
                   64'd100000000,
                   1'b0,
                   32'd7001,
                   64'd1,
                   0, 1, 0);
        wait_drain;
        if (change_done_total != change_done_before + 1)
            fail("context_change_done count incorrect after reset test");

        if (passed != q_count)
            fail("End-of-suite Context packet count mismatch");
        if (meta_stall_total == 0 || link_stall_total == 0 ||
            overlap_stall_total == 0)
            fail("Required Context backpressure/overlap coverage was not exercised");

        $display("\nALL CONTEXT LOOPBACK TESTS PASSED: TC01-TC10, %0d packets", passed);
        $display("  stalls: link=%0d metadata=%0d overlap=%0d, context_change_done=%0d",
                 link_stall_total, meta_stall_total,
                 overlap_stall_total, change_done_total);
        $finish;
    end

    initial begin
        #5000000;
        fail("Global Context loopback simulation timeout");
    end

endmodule
