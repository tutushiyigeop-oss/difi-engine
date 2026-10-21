`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

module tb_difi_version_loopback;

    localparam integer VERSION_WORDS = 11;
    localparam integer WAIT_LIMIT    = 20000;
    localparam integer QUEUE_DEPTH   = 128;

    localparam [6:0] BUILD_YEAR_OFFSET = 7'd26;
    localparam [8:0] BUILD_DAY_OF_YEAR = 9'd252;
    localparam [31:0] BUILD_INFO_WORD   = 32'h34FC_0400;

    reg aclk;
    reg aresetn;

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    reg         pkt_start;
    wire        pkt_busy;
    wire        pkt_done;

    reg  [31:0] cfg_version_stream_id;

    reg  [31:0] time_sec;
    reg  [63:0] time_ps;
    reg         time_valid;

    wire [31:0] gen_tdata;
    wire        gen_tvalid;
    wire        gen_tready;
    wire [3:0]  gen_tkeep;
    wire        gen_tlast;

    reg         link_gate;

    wire [31:0] parser_tdata;
    wire        parser_tvalid;
    wire        parser_tready;
    wire [3:0]  parser_tkeep;
    wire        parser_tlast;

    assign parser_tdata  = gen_tdata;
    assign parser_tvalid = gen_tvalid && link_gate;
    assign parser_tkeep  = gen_tkeep;
    assign parser_tlast  = gen_tlast;

    assign gen_tready    = parser_tready && link_gate;

    wire link_fire = gen_tvalid && gen_tready;

    reg         cfg_stream_filter_enable;
    reg  [31:0] cfg_expected_stream_id;

    wire        m_ver_valid;
    reg         manual_meta_block;
    wire        m_ver_ready;

    wire [31:0] m_ver_stream_id;
    wire [3:0]  m_ver_seq;
    wire [31:0] m_ver_time_sec;
    wire [63:0] m_ver_time_ps;
    wire        m_ver_changed;
    wire [31:0] m_ver_info;

    wire        error_valid;
    wire [3:0]  error_code;

    assign m_ver_ready = !manual_meta_block;

    wire meta_fire = m_ver_valid && m_ver_ready;

    difi_version_generator #(
        .BUILD_YEAR_OFFSET(BUILD_YEAR_OFFSET),
        .BUILD_DAY_OF_YEAR(BUILD_DAY_OF_YEAR)
    ) u_version_generator (
        .aclk                  (aclk),
        .aresetn               (aresetn),

        .pkt_start             (pkt_start),
        .pkt_busy              (pkt_busy),
        .pkt_done              (pkt_done),

        .cfg_version_stream_id (cfg_version_stream_id),

        .time_sec              (time_sec),
        .time_ps               (time_ps),
        .time_valid            (time_valid),

        .m_axis_pkt_tdata      (gen_tdata),
        .m_axis_pkt_tvalid     (gen_tvalid),
        .m_axis_pkt_tready     (gen_tready),
        .m_axis_pkt_tkeep      (gen_tkeep),
        .m_axis_pkt_tlast      (gen_tlast)
    );

    difi_version_parser u_version_parser (
        .aclk                  (aclk),
        .aresetn               (aresetn),

        .s_axis_pkt_tdata      (parser_tdata),
        .s_axis_pkt_tvalid     (parser_tvalid),
        .s_axis_pkt_tready     (parser_tready),
        .s_axis_pkt_tkeep      (parser_tkeep),
        .s_axis_pkt_tlast      (parser_tlast),

        .cfg_stream_filter_enable (cfg_stream_filter_enable),
        .cfg_expected_stream_id   (cfg_expected_stream_id),

        .m_ver_valid           (m_ver_valid),
        .m_ver_ready           (m_ver_ready),
        .m_ver_stream_id       (m_ver_stream_id),
        .m_ver_seq             (m_ver_seq),
        .m_ver_time_sec        (m_ver_time_sec),
        .m_ver_time_ps         (m_ver_time_ps),
        .m_ver_changed         (m_ver_changed),
        .m_ver_info            (m_ver_info),

        .error_valid           (error_valid),
        .error_code            (error_code)
    );

    integer current_tc;
    integer passed;

    integer cycles;
    integer total_packets;
    integer total_metadata;
    integer total_errors;

    reg [3:0] model_seq;
    reg       model_first_version_pending;

    reg [31:0] golden_word [0:VERSION_WORDS-1];
    integer    tx_word_seen;
    integer    tx_last_seen;
    integer    current_packet_active;
    integer    current_packet_done_seen;

    integer    link_mode;
    integer    throttle_hits [0:VERSION_WORDS-1];

    reg        hold_gen;
    reg [31:0] held_gen_data;
    reg [3:0]  held_gen_keep;
    reg        held_gen_last;

    reg        hold_meta;
    reg [31:0] held_meta_sid;
    reg [3:0]  held_meta_seq;
    reg [31:0] held_meta_sec;
    reg [63:0] held_meta_ps;
    reg        held_meta_changed;
    reg [31:0] held_meta_info;

    reg        previous_done;
    reg        completion_due;

    reg [31:0] exp_sid     [0:QUEUE_DEPTH-1];
    reg [3:0]  exp_seq     [0:QUEUE_DEPTH-1];
    reg [31:0] exp_sec     [0:QUEUE_DEPTH-1];
    reg [63:0] exp_ps      [0:QUEUE_DEPTH-1];
    reg        exp_changed [0:QUEUE_DEPTH-1];
    reg [31:0] exp_info    [0:QUEUE_DEPTH-1];

    integer exp_wr;
    integer exp_rd;

    task fail;
        input [8*240-1:0] message;
        begin
            $display("");
            $display("[FAIL] TC%0d @ %0t : %0s", current_tc, $time, message);
            $display("       TX: active=%0d words=%0d last=%0d busy=%b done=%b",
                     current_packet_active, tx_word_seen, tx_last_seen,
                     pkt_busy, pkt_done);
            $display("       LINK: valid=%b ready=%b gate=%b data=%h keep=%h last=%b parser_ready=%b",
                     gen_tvalid, gen_tready, link_gate,
                     gen_tdata, gen_tkeep, gen_tlast, parser_tready);
            $display("       META: valid=%b ready=%b sid=%h seq=%h sec=%h ps=%h changed=%b info=%h",
                     m_ver_valid, m_ver_ready, m_ver_stream_id, m_ver_seq,
                     m_ver_time_sec, m_ver_time_ps, m_ver_changed, m_ver_info);
            $display("       ERR: valid=%b code=%h  queue=%0d/%0d",
                     error_valid, error_code, exp_rd, exp_wr);
            $finish;
        end
    endtask

    task clear_throttle_counters;
        integer j;
        begin
            for (j = 0; j < VERSION_WORDS; j = j + 1)
                throttle_hits[j] = 0;
        end
    endtask

    task make_golden_packet;
        input [31:0] sid;
        input [31:0] sec;
        input [63:0] ps;
        input [3:0]  seq;
        input        changed;
        begin
            golden_word[0]  = 32'h5960_000B | ({28'd0, seq} << 16);
            golden_word[1]  = sid;
            golden_word[2]  = 32'h006A_621E;
            golden_word[3]  = 32'h0001_0004;
            golden_word[4]  = sec;
            golden_word[5]  = ps[63:32];
            golden_word[6]  = ps[31:0];
            golden_word[7]  = changed ? 32'h8000_0002 : 32'h0000_0002;
            golden_word[8]  = 32'h0000_000C;
            golden_word[9]  = 32'h0000_0004;
            golden_word[10] = BUILD_INFO_WORD;
        end
    endtask

    task push_expected_metadata;
        input [31:0] sid;
        input [3:0]  seq;
        input [31:0] sec;
        input [63:0] ps;
        input        changed;
        begin
            if (exp_wr >= QUEUE_DEPTH)
                fail("Expected-metadata queue overflow");

            exp_sid[exp_wr]     = sid;
            exp_seq[exp_wr]     = seq;
            exp_sec[exp_wr]     = sec;
            exp_ps[exp_wr]      = ps;
            exp_changed[exp_wr] = changed;
            exp_info[exp_wr]    = BUILD_INFO_WORD;
            exp_wr              = exp_wr + 1;
        end
    endtask

    task reset_dut;
        integer j;
        begin
            @(negedge aclk);

            pkt_start                  = 1'b0;
            cfg_version_stream_id      = 32'h0000_0002;
            time_sec                   = 32'd0;
            time_ps                    = 64'd0;
            time_valid                 = 1'b0;

            cfg_stream_filter_enable   = 1'b1;
            cfg_expected_stream_id     = 32'h0000_0002;

            manual_meta_block          = 1'b0;
            link_mode                  = 0;
            link_gate                  = 1'b1;

            aresetn                    = 1'b0;

            repeat (5) @(posedge aclk);

            @(negedge aclk);
            aresetn = 1'b1;

            model_seq                    = 4'd0;
            model_first_version_pending  = 1'b1;

            tx_word_seen                = 0;
            tx_last_seen                = 0;
            current_packet_active       = 0;
            current_packet_done_seen    = 0;

            exp_wr                      = 0;
            exp_rd                      = 0;

            completion_due              = 1'b0;
            previous_done               = 1'b0;
            hold_gen                    = 1'b0;
            hold_meta                   = 1'b0;

            clear_throttle_counters();

            repeat (3) @(negedge aclk);

            if (pkt_busy !== 1'b0 ||
                pkt_done !== 1'b0 ||
                gen_tvalid !== 1'b0 ||
                m_ver_valid !== 1'b0 ||
                error_valid !== 1'b0)
                fail("DUTs are not quiescent after reset");
        end
    endtask

    task launch_packet;
        input [31:0] sid;
        input [31:0] sec;
        input [63:0] ps;
        input integer bp_mode;

        reg expected_changed;
        reg [3:0] expected_seq;
        begin
            @(negedge aclk);

            if (current_packet_active)
                fail("Attempted to launch while previous TX packet is active");

            if (pkt_busy !== 1'b0 || gen_tvalid !== 1'b0)
                fail("Generator is not idle before launch");

            if (ps >= 64'd1000000000000)
                fail("Test attempted to launch an invalid timestamp");

            expected_seq     = model_seq;
            expected_changed = model_first_version_pending;

            cfg_version_stream_id    = sid;
            cfg_expected_stream_id   = sid;
            cfg_stream_filter_enable = 1'b1;

            time_sec   = sec;
            time_ps    = ps;
            time_valid = 1'b1;

            link_mode = bp_mode;

            tx_word_seen             = 0;
            tx_last_seen             = 0;
            current_packet_done_seen = 0;
            current_packet_active    = 1;
            completion_due           = 1'b0;

            clear_throttle_counters();

            make_golden_packet(
                sid,
                sec,
                ps,
                expected_seq,
                expected_changed
            );

            push_expected_metadata(
                sid,
                expected_seq,
                sec,
                ps,
                expected_changed
            );

            #2 pkt_start = 1'b1;
            @(posedge aclk);     
            @(negedge aclk);
            pkt_start = 1'b0;

            if (pkt_busy !== 1'b1)
                fail("Generator did not enter busy after a legal pkt_start");
        end
    endtask

    task wait_current_tx_done;
        integer waited;
        begin
            waited = 0;

            while (current_packet_active && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end

            if (current_packet_active)
                fail("Timeout waiting for Version generator packet completion");

            if (current_packet_done_seen != 1)
                fail("Expected exactly one pkt_done for the packet");
        end
    endtask

    task wait_all_metadata;
        integer waited;
        begin
            waited = 0;

            while (((exp_rd != exp_wr) || m_ver_valid) &&
                   waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end

            if ((exp_rd != exp_wr) || m_ver_valid)
                fail("Timeout waiting for Version metadata queue to drain");
        end
    endtask

    task run_packet;
        input [31:0] sid;
        input [31:0] sec;
        input [63:0] ps;
        input integer bp_mode;
        begin
            launch_packet(sid, sec, ps, bp_mode);
            wait_current_tx_done();
            wait_all_metadata();

            $display("[PASS] TC%0d packet=%0d seq=%0d SID=%h mode=%0d",
                     current_tc, total_packets, model_seq - 4'd1, sid, bp_mode);
            passed = passed + 1;
        end
    endtask

    task wait_until_tx_word_count;
        input integer target;
        integer waited;
        begin
            waited = 0;

            while (tx_word_seen < target && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end

            if (tx_word_seen < target)
                fail("Timeout waiting for requested transmitted word count");
        end
    endtask

    task wait_until_meta_valid;
        integer waited;
        begin
            waited = 0;

            while (!m_ver_valid && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end

            if (!m_ver_valid)
                fail("Timeout waiting for m_ver_valid");
        end
    endtask

    task rejected_start_without_time;
        integer before_wr;
        reg [3:0] before_seq;
        begin
            @(negedge aclk);

            if (pkt_busy !== 1'b0 || gen_tvalid !== 1'b0 ||
                current_packet_active)
                fail("Generator is not idle before rejected-start test");

            before_wr  = exp_wr;
            before_seq = model_seq;

            cfg_version_stream_id = 32'h0000_0066;
            time_sec               = 32'h1122_3344;
            time_ps                = 64'd12345;
            time_valid             = 1'b0;

            #2 pkt_start = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            pkt_start = 1'b0;

            repeat (5) @(negedge aclk);

            if (pkt_busy !== 1'b0 ||
                gen_tvalid !== 1'b0 ||
                pkt_done !== 1'b0)
                fail("time_valid=0 pkt_start was incorrectly accepted");

            if (exp_wr != before_wr || model_seq != before_seq)
                fail("Rejected start changed the reference transaction state");

            if (m_ver_valid !== 1'b0 || error_valid !== 1'b0)
                fail("Rejected start unexpectedly reached parser");

            time_valid = 1'b1;
        end
    endtask

    always @(negedge aclk) begin
        #1;

        if (!aresetn) begin
            link_gate = 1'b1;
        end
        else begin
            case (link_mode)

                0:
                    link_gate = 1'b1;

                1:
                    begin
                        if (current_packet_active &&
                            gen_tvalid &&
                            (tx_word_seen == 0 ||
                             tx_word_seen == 5 ||
                             tx_word_seen == 10) &&
                            throttle_hits[tx_word_seen] < 3)
                            link_gate = 1'b0;
                        else
                            link_gate = 1'b1;
                    end

                2:
                    begin
                        if (current_packet_active &&
                            gen_tvalid &&
                            throttle_hits[tx_word_seen] < 2)
                            link_gate = 1'b0;
                        else
                            link_gate = 1'b1;
                    end

                3:
                    begin
                        if (current_packet_active &&
                            gen_tvalid &&
                            (((cycles + tx_word_seen * 7) % 5) < 2))
                            link_gate = 1'b0;
                        else
                            link_gate = 1'b1;
                    end

                4:
                    begin
                        if (current_packet_active &&
                            gen_tvalid &&
                            tx_word_seen == 10 &&
                            throttle_hits[10] < 25)
                            link_gate = 1'b0;
                        else
                            link_gate = 1'b1;
                    end

                default:
                    link_gate = 1'b1;

            endcase
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            cycles          = 0;
            hold_gen        = 1'b0;
            hold_meta       = 1'b0;
            previous_done   = 1'b0;
            completion_due  = 1'b0;
        end
        else begin
            cycles = cycles + 1;

            if (gen_tvalid !== 1'b0 && gen_tvalid !== 1'b1)
                fail("Generator TVALID is X/Z");

            if (gen_tready !== 1'b0 && gen_tready !== 1'b1)
                fail("Generator TREADY is X/Z");

            if (parser_tready !== 1'b0 && parser_tready !== 1'b1)
                fail("Parser TREADY is X/Z");

            if (m_ver_valid !== 1'b0 && m_ver_valid !== 1'b1)
                fail("m_ver_valid is X/Z");

            if (error_valid !== 1'b0 && error_valid !== 1'b1)
                fail("error_valid is X/Z");

            if (pkt_done !== 1'b0 && pkt_done !== 1'b1)
                fail("pkt_done is X/Z");

            if (gen_tkeep !== 4'hF)
                fail("Generator TKEEP must always be 4'b1111");

            if (pkt_done && previous_done)
                fail("pkt_done is wider than one clock");

            previous_done = pkt_done;

            if (hold_gen) begin
                if (gen_tvalid !== 1'b1 ||
                    gen_tdata  !== held_gen_data ||
                    gen_tkeep  !== held_gen_keep ||
                    gen_tlast  !== held_gen_last)
                    fail("Generator changed AXIS beat while backpressured");
            end

            hold_gen = (gen_tvalid === 1'b1 &&
                        gen_tready === 1'b0);

            if (hold_gen) begin
                held_gen_data = gen_tdata;
                held_gen_keep = gen_tkeep;
                held_gen_last = gen_tlast;
            end

            if (gen_tvalid === 1'b1) begin
                if (!current_packet_active)
                    fail("Generator asserted TVALID without an armed packet");

                if (tx_word_seen >= VERSION_WORDS)
                    fail("Generator presented more than 11 Version words");

                if (gen_tdata !== golden_word[tx_word_seen]) begin
                    $display("       WORD%0d expected=%h actual=%h",
                             tx_word_seen,
                             golden_word[tx_word_seen],
                             gen_tdata);
                    fail("Generator word mismatch inside Version loopback");
                end

                if (gen_tlast !== (tx_word_seen == VERSION_WORDS-1))
                    fail("Generator TLAST must appear only on Word10");
            end

            if (current_packet_active &&
                gen_tvalid === 1'b1 &&
                link_gate === 1'b0) begin

                if (tx_word_seen >= VERSION_WORDS)
                    fail("Throttle attempted beyond end of packet");

                throttle_hits[tx_word_seen] =
                    throttle_hits[tx_word_seen] + 1;
            end

            if (completion_due) begin
                if (pkt_done !== 1'b1)
                    fail("Missing pkt_done after final Version word handshake");

                if (pkt_busy !== 1'b0)
                    fail("pkt_busy did not clear after final handshake");

                current_packet_done_seen =
                    current_packet_done_seen + 1;

                if (current_packet_done_seen != 1)
                    fail("Duplicate pkt_done for one Version packet");

                current_packet_active = 0;
                completion_due        = 1'b0;
                total_packets         = total_packets + 1;
            end
            else if (pkt_done === 1'b1) begin
                fail("Early or unarmed pkt_done");
            end

            if (link_fire) begin
                if (!current_packet_active)
                    fail("Unexpected Version link transfer");

                if (tx_word_seen >= VERSION_WORDS)
                    fail("More than 11 Version beats transferred");

                if (gen_tdata !== golden_word[tx_word_seen])
                    fail("Transferred Version word differs from golden packet");

                if (tx_word_seen == VERSION_WORDS-1) begin
                    if (gen_tlast !== 1'b1)
                        fail("Final Version word transferred without TLAST");

                    tx_last_seen = tx_last_seen + 1;

                    if (tx_last_seen != 1)
                        fail("More than one TLAST transfer in one Version packet");

                    completion_due = 1'b1;

                    // Update the TX sequence only after the full packet is sent.
                    model_seq = model_seq + 4'd1;
                    model_first_version_pending = 1'b0;
                end

                tx_word_seen = tx_word_seen + 1;
            end

            if (error_valid === 1'b1) begin
                total_errors = total_errors + 1;
                $display("       Unexpected parser error_code=%h", error_code);
                fail("Parser rejected a packet generated by Version Generator");
            end

            if (hold_meta) begin
                if (m_ver_valid     !== 1'b1 ||
                    m_ver_stream_id !== held_meta_sid ||
                    m_ver_seq       !== held_meta_seq ||
                    m_ver_time_sec  !== held_meta_sec ||
                    m_ver_time_ps   !== held_meta_ps ||
                    m_ver_changed   !== held_meta_changed ||
                    m_ver_info      !== held_meta_info)
                    fail("Version metadata changed while m_ver_ready=0");
            end

            hold_meta = (m_ver_valid === 1'b1 &&
                         m_ver_ready === 1'b0);

            if (hold_meta) begin
                held_meta_sid     = m_ver_stream_id;
                held_meta_seq     = m_ver_seq;
                held_meta_sec     = m_ver_time_sec;
                held_meta_ps      = m_ver_time_ps;
                held_meta_changed = m_ver_changed;
                held_meta_info    = m_ver_info;
            end

            if (m_ver_valid === 1'b1 && exp_rd >= exp_wr)
                fail("Parser produced metadata with no expected transaction");

            if (meta_fire) begin
                if (exp_rd >= exp_wr)
                    fail("Unexpected Version metadata handshake");

                if (m_ver_stream_id !== exp_sid[exp_rd] ||
                    m_ver_seq       !== exp_seq[exp_rd] ||
                    m_ver_time_sec  !== exp_sec[exp_rd] ||
                    m_ver_time_ps   !== exp_ps[exp_rd] ||
                    m_ver_changed   !== exp_changed[exp_rd] ||
                    m_ver_info      !== exp_info[exp_rd]) begin

                    $display("       META expected: sid=%h seq=%h sec=%h ps=%h changed=%b info=%h",
                             exp_sid[exp_rd],
                             exp_seq[exp_rd],
                             exp_sec[exp_rd],
                             exp_ps[exp_rd],
                             exp_changed[exp_rd],
                             exp_info[exp_rd]);

                    $display("       META actual:   sid=%h seq=%h sec=%h ps=%h changed=%b info=%h",
                             m_ver_stream_id,
                             m_ver_seq,
                             m_ver_time_sec,
                             m_ver_time_ps,
                             m_ver_changed,
                             m_ver_info);

                    fail("Generator -> Parser metadata mismatch");
                end

                exp_rd         = exp_rd + 1;
                total_metadata = total_metadata + 1;
            end
        end
    end

    integer n;

    initial begin
        aresetn                  = 1'b0;
        pkt_start               = 1'b0;
        cfg_version_stream_id   = 32'h0000_0002;
        time_sec                = 32'd0;
        time_ps                 = 64'd0;
        time_valid              = 1'b0;

        cfg_stream_filter_enable = 1'b1;
        cfg_expected_stream_id   = 32'h0000_0002;

        manual_meta_block       = 1'b0;
        link_gate               = 1'b1;
        link_mode               = 0;

        current_tc              = 0;
        passed                  = 0;

        cycles                  = 0;
        total_packets           = 0;
        total_metadata          = 0;
        total_errors            = 0;

        model_seq               = 4'd0;
        model_first_version_pending = 1'b1;

        exp_wr                  = 0;
        exp_rd                  = 0;

        current_packet_active   = 0;
        current_packet_done_seen= 0;
        tx_word_seen            = 0;
        tx_last_seen            = 0;

        hold_gen                = 1'b0;
        hold_meta               = 1'b0;
        previous_done           = 1'b0;
        completion_due          = 1'b0;

        clear_throttle_counters();

        repeat (2) @(negedge aclk);
        reset_dut();

        current_tc = 1;
        run_packet(
            32'h0000_0002,
            32'h0000_0064,
            64'd0,
            0
        );

        current_tc = 2;
        run_packet(
            32'h0000_0002,
            32'h0000_0065,
            64'd123456789,
            0
        );

        current_tc = 3;
        run_packet(
            32'h0000_0002,
            32'h0102_0304,
            64'd999999999999,
            1
        );

        if (throttle_hits[0] < 3 ||
            throttle_hits[5] < 3 ||
            throttle_hits[10] < 3)
            fail("TC3 did not actually exercise selected-word stalls");

        current_tc = 4;
        run_packet(
            32'h0000_0002,
            32'h1111_2222,
            64'd987654321,
            2
        );

        for (n = 0; n < VERSION_WORDS; n = n + 1)
            if (throttle_hits[n] < 2)
                fail("TC4 did not stall every Version word");

        current_tc = 5;
        run_packet(
            32'h0000_0002,
            32'h2222_3333,
            64'd777777777,
            4
        );

        if (throttle_hits[10] < 25)
            fail("TC5 did not exercise long final-word backpressure");

        // Keep using the configuration saved at the start of the current packet.
        
        current_tc = 6;

        launch_packet(
            32'h1357_2468,
            32'h1234_5678,
            64'd555555555,
            1
        );

        @(negedge aclk);
        cfg_version_stream_id = 32'hDEAD_BEEF;
        time_sec              = 32'hCAFE_BABE;
        time_ps               = 64'd1;

        wait_until_tx_word_count(1);

        @(negedge aclk);
        cfg_expected_stream_id = 32'h0BAD_F00D;

        wait_current_tx_done();
        wait_all_metadata();

        $display("[PASS] TC%0d packet-boundary snapshot preserved on TX and RX", current_tc);
        passed = passed + 1;

        current_tc = 7;
        manual_meta_block = 1'b1;

        launch_packet(
            32'h0000_0042,
            32'h3333_4444,
            64'd42424242,
            0
        );

        wait_current_tx_done();
        wait_until_meta_valid();

        repeat (12) @(negedge aclk);

        if (!m_ver_valid)
            fail("Metadata did not remain valid while blocked");

        manual_meta_block = 1'b0;
        wait_all_metadata();

        $display("[PASS] TC%0d metadata backpressure/stability", current_tc);
        passed = passed + 1;

        current_tc = 8;
        manual_meta_block = 1'b1;

        launch_packet(
            32'h0000_0050,
            32'h4444_0001,
            64'd111,
            0
        );

        wait_current_tx_done();
        wait_until_meta_valid();

        launch_packet(
            32'h0000_0050,
            32'h4444_0002,
            64'd222,
            0
        );

        repeat (10) @(negedge aclk);

        if (tx_word_seen != 0)
            fail("Parser accepted next packet while previous metadata was blocked");

        if (!gen_tvalid || gen_tready)
            fail("Next Generator Word0 was not correctly backpressured");

        manual_meta_block = 1'b0;

        wait_current_tx_done();
        wait_all_metadata();

        $display("[PASS] TC%0d pending metadata backpressures the next packet", current_tc);
        passed = passed + 1;

        current_tc = 9;
        run_packet(
            32'hABCD_0001,
            32'h5555_0001,
            64'd333,
            0
        );

        current_tc = 10;
        rejected_start_without_time();

        run_packet(
            32'hABCD_0001,
            32'h5555_0002,
            64'd444,
            0
        );

        current_tc = 11;

        while (model_seq != 4'hF) begin
            run_packet(
                32'hABCD_0001,
                32'h6000_0000 + {28'd0, model_seq},
                {60'd0, model_seq},
                3
            );
        end

        run_packet(
            32'hABCD_0001,
            32'h6FFF_000F,
            64'd15,
            1
        );

        if (model_seq !== 4'h0)
            fail("Generator sequence did not wrap 15 -> 0");

        run_packet(
            32'hABCD_0001,
            32'h7000_0000,
            64'd16,
            1
        );

        current_tc = 12;

        wait_all_metadata();
        reset_dut();

        run_packet(
            32'h0000_0002,
            32'h0000_0064,
            64'd0,
            0
        );

        repeat (10) @(negedge aclk);

        if (error_valid !== 1'b0 || total_errors != 0)
            fail("Unexpected parser error remained at end of loopback test");

        if (exp_rd != exp_wr)
            fail("Not all expected metadata transactions were consumed");

        $display("");
        $display("============================================================");
        $display(" tb_difi_version_loopback PASSED");
        $display(" passed test groups = %0d", passed);
        $display(" packets transferred = %0d", total_packets);
        $display(" metadata committed  = %0d", total_metadata);
        $display(" parser errors       = %0d", total_errors);
        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
