`timescale 1ns / 1ps

module tb_difi_version_generator;

    localparam integer WORDS      = 11;
    localparam integer WAIT_LIMIT = 10000;

    localparam [6:0] TB_BUILD_YEAR_OFFSET = 7'd26;
    localparam [8:0] TB_BUILD_DAY_OF_YEAR = 9'd252;

    reg         aclk;
    reg         aresetn;
    reg         pkt_start;
    wire        pkt_busy;
    wire        pkt_done;

    reg  [31:0] cfg_version_stream_id;

    reg  [31:0] time_sec;
    reg  [63:0] time_ps;
    reg         time_valid;

    wire [31:0] m_axis_pkt_tdata;
    wire        m_axis_pkt_tvalid;
    reg         m_axis_pkt_tready;
    wire [3:0]  m_axis_pkt_tkeep;
    wire        m_axis_pkt_tlast;

    wire        m_axis_fire;
    assign m_axis_fire = m_axis_pkt_tvalid && m_axis_pkt_tready;

    difi_version_generator #(
        .BUILD_YEAR_OFFSET(TB_BUILD_YEAR_OFFSET),
        .BUILD_DAY_OF_YEAR(TB_BUILD_DAY_OF_YEAR)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),

        .pkt_start(pkt_start),
        .pkt_busy(pkt_busy),
        .pkt_done(pkt_done),

        .cfg_version_stream_id(cfg_version_stream_id),

        .time_sec(time_sec),
        .time_ps(time_ps),
        .time_valid(time_valid),

        .m_axis_pkt_tdata(m_axis_pkt_tdata),
        .m_axis_pkt_tvalid(m_axis_pkt_tvalid),
        .m_axis_pkt_tready(m_axis_pkt_tready),
        .m_axis_pkt_tkeep(m_axis_pkt_tkeep),
        .m_axis_pkt_tlast(m_axis_pkt_tlast)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    reg [31:0] golden_word [0:WORDS-1];

    reg [3:0] model_seq;
    reg       model_first_version_pending;
    reg       golden_changed;

    reg       watch_active;
    integer   current_tc;
    integer   passed;
    integer   total_packets;
    integer   total_stalls;
    integer   cycles;

    integer   word_seen;
    integer   last_seen;
    integer   starts_seen;
    integer   done_seen;

    integer   stall_hits [0:WORDS-1];
    integer   ready_mode;
    integer   case_ready_mode;
    integer   stall_word;

    reg       previous_done;
    reg       completion_due;

    reg       held_beat;
    reg [31:0] held_data;
    reg [3:0]  held_keep;
    reg        held_last;

    integer k;

    task fail;
        input [8*240-1:0] message;
        begin
            $display("[FAIL] TC%0d @%0t: %0s", current_tc, $time, message);
            $display("       words=%0d/11 last=%0d starts=%0d done=%0d seq_model=%0d first_pending=%0d",
                     word_seen, last_seen, starts_seen, done_seen,
                     model_seq, model_first_version_pending);
            $display("       AXIS: data=%h valid=%b ready=%b keep=%h last=%b busy=%b done=%b",
                     m_axis_pkt_tdata, m_axis_pkt_tvalid, m_axis_pkt_tready,
                     m_axis_pkt_tkeep, m_axis_pkt_tlast, pkt_busy, pkt_done);
            $fatal(1, "Version generator test failed");
        end
    endtask

    task make_golden;
        input [31:0] sid;
        input [31:0] sec;
        input [63:0] ps;
        input        changed;
        integer n;
        begin
            if (ps >= 64'd1000000000000)
                fail("Test supplied time_ps outside frozen project profile");

            for (n=0; n<WORDS; n=n+1)
                golden_word[n] = 32'h0000_0000;

            golden_word[0]  = 32'h5960_000B | ({28'd0, model_seq} << 16);
            golden_word[1]  = sid;
            golden_word[2]  = 32'h006A_621E;
            golden_word[3]  = 32'h0001_0004;
            golden_word[4]  = sec;
            golden_word[5]  = ps[63:32];
            golden_word[6]  = ps[31:0];
            golden_word[7]  = changed ? 32'h8000_0002 : 32'h0000_0002;
            golden_word[8]  = 32'h0000_000C;
            golden_word[9]  = 32'h0000_0004;
            golden_word[10] = {TB_BUILD_YEAR_OFFSET,
                               TB_BUILD_DAY_OF_YEAR,
                               6'd1,
                               4'd0,
                               6'd0};
        end
    endtask

    task check_reference_fixture;
        reg [31:0] literal [0:WORDS-1];
        integer n;
        begin
            literal[0]  = 32'h5960_000B;
            literal[1]  = 32'h0000_0002;
            literal[2]  = 32'h006A_621E;
            literal[3]  = 32'h0001_0004;
            literal[4]  = 32'h0000_0064;
            literal[5]  = 32'h0000_0000;
            literal[6]  = 32'h0000_0000;
            literal[7]  = 32'h8000_0002;
            literal[8]  = 32'h0000_000C;
            literal[9]  = 32'h0000_0004;
            literal[10] = 32'h34FC_0400;

            for (n=0; n<WORDS; n=n+1) begin
                if (golden_word[n] !== literal[n]) begin
                    $display("  Reference word%0d: expected=%h model=%h",
                             n, literal[n], golden_word[n]);
                    fail("Independent reference fixture does not match golden builder");
                end
            end
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            held_beat      = 1'b0;
            completion_due = 1'b0;
            previous_done  = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (m_axis_pkt_tkeep !== 4'hF)
                fail("TKEEP must always be 4'b1111");
            if (pkt_busy !== 1'b0 && pkt_busy !== 1'b1)
                fail("pkt_busy is X/Z");
            if (m_axis_pkt_tvalid !== 1'b0 && m_axis_pkt_tvalid !== 1'b1)
                fail("TVALID is X/Z");
            if (pkt_done !== 1'b0 && pkt_done !== 1'b1)
                fail("pkt_done is X/Z");

            if (pkt_done && previous_done)
                fail("pkt_done must be a one-clock pulse");
            previous_done = pkt_done;

            if (completion_due) begin
                if (pkt_done !== 1'b1)
                    fail("Missing pkt_done immediately after Word10 handshake");
                if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0 ||
                    m_axis_pkt_tlast !== 1'b0)
                    fail("Generator did not return to idle after final handshake");
                done_seen = done_seen + 1;
                completion_due = 1'b0;
            end else if (pkt_done !== 1'b0) begin
                fail("Early, duplicate, or unarmed pkt_done pulse");
            end

            // Accept a start request only when idle and time is valid.
            if (pkt_start === 1'b1 && time_valid === 1'b1 &&
                pkt_busy === 1'b0) begin
                if (!watch_active || starts_seen != 0)
                    fail("Unexpected or repeated start acceptance");
                starts_seen = starts_seen + 1;
            end

            if (pkt_busy === 1'b1) begin
                if (!watch_active || starts_seen != 1)
                    fail("Generator busy without one accepted start");
                if (m_axis_pkt_tvalid !== 1'b1)
                    fail("Output bubble: SEND state must present a valid word");
            end else if (m_axis_pkt_tvalid !== 1'b0 ||
                         m_axis_pkt_tlast !== 1'b0) begin
                fail("TVALID/TLAST asserted while generator is idle");
            end

            if (held_beat) begin
                if (m_axis_pkt_tvalid !== 1'b1 ||
                    m_axis_pkt_tdata !== held_data ||
                    m_axis_pkt_tkeep !== held_keep ||
                    m_axis_pkt_tlast !== held_last)
                    fail("AXIS beat changed while backpressured");
            end

            if (m_axis_pkt_tvalid === 1'b1) begin
                if (!watch_active || word_seen >= WORDS)
                    fail("Unarmed or extra output word");

                if (m_axis_pkt_tdata !== golden_word[word_seen]) begin
                    $display("  Word[%0d]: expected=%h actual=%h",
                             word_seen, golden_word[word_seen], m_axis_pkt_tdata);
                    fail("DIFI Version word mismatch");
                end

                if (m_axis_pkt_tlast !== (word_seen == WORDS-1))
                    fail("TLAST must appear only on Word10");
            end

            if (m_axis_pkt_tvalid === 1'b1 &&
                m_axis_pkt_tready === 1'b0) begin
                if (word_seen >= WORDS)
                    fail("Stall beyond end of packet");
                stall_hits[word_seen] = stall_hits[word_seen] + 1;
                total_stalls = total_stalls + 1;
            end

            held_beat = (m_axis_pkt_tvalid === 1'b1 &&
                         m_axis_pkt_tready === 1'b0);
            if (held_beat) begin
                held_data = m_axis_pkt_tdata;
                held_keep = m_axis_pkt_tkeep;
                held_last = m_axis_pkt_tlast;
            end

            if (m_axis_fire) begin
                if (word_seen >= WORDS)
                    fail("More than 11 words transferred");

                if (word_seen == WORDS-1) begin
                    last_seen = last_seen + 1;
                    if (last_seen != 1)
                        fail("More than one final handshake");
                    completion_due = 1'b1;
                end

                word_seen = word_seen + 1;
            end
        end
    end

    always @(negedge aclk) begin
        #1;
        if (!aresetn) begin
            m_axis_pkt_tready = 1'b1;
        end else begin
            case (ready_mode)
                0: begin
                    m_axis_pkt_tready = 1'b1;
                end

                1: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        (word_seen == 0 || word_seen == 7 || word_seen == 10) &&
                        stall_hits[word_seen] < 4)
                        m_axis_pkt_tready = 1'b0;
                    else
                        m_axis_pkt_tready = 1'b1;
                end

                2: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        stall_hits[word_seen] < 2)
                        m_axis_pkt_tready = 1'b0;
                    else
                        m_axis_pkt_tready = 1'b1;
                end

                3: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        ((word_seen == 0  && stall_hits[0]  < 3) ||
                         (word_seen == 10 && stall_hits[10] < 40)))
                        m_axis_pkt_tready = 1'b0;
                    else
                        m_axis_pkt_tready = 1'b1;
                end

                4: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        word_seen == stall_word)
                        m_axis_pkt_tready = 1'b0;
                    else
                        m_axis_pkt_tready = 1'b1;
                end

                5: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        (((word_seen == 0 || word_seen == 10) &&
                          stall_hits[word_seen] < 3) ||
                         ((cycles * 7 + word_seen * 11) % 5 < 2)))
                        m_axis_pkt_tready = 1'b0;
                    else
                        m_axis_pkt_tready = 1'b1;
                end

                default: begin
                    m_axis_pkt_tready = 1'b1;
                end
            endcase
        end
    end

    task begin_packet;
        input [31:0] sid;
        input [31:0] sec;
        input [63:0] ps;
        input integer bp_mode;
        integer n;
        begin
            @(negedge aclk);

            if (watch_active || pkt_busy !== 1'b0 ||
                m_axis_pkt_tvalid !== 1'b0 || pkt_done !== 1'b0)
                fail("Previous packet has not become idle");

            cfg_version_stream_id = sid;
            time_sec = sec;
            time_ps = ps;
            time_valid = 1'b1;

            ready_mode = bp_mode;
            case_ready_mode = bp_mode;

            word_seen = 0;
            last_seen = 0;
            starts_seen = 0;
            done_seen = 0;

            for (n=0; n<WORDS; n=n+1)
                stall_hits[n] = 0;

            golden_changed = model_first_version_pending;
            make_golden(sid, sec, ps, golden_changed);
            watch_active = 1'b1;

            #2 pkt_start = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            pkt_start = 1'b0;
        end
    endtask

    task wait_until_word;
        input integer target;
        integer waited;
        begin
            waited = 0;
            
            while (word_seen < target && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end
            if (word_seen < target)
                fail("Timeout waiting for word index");
        end
    endtask

    task finish_packet;
        integer waited;
        integer n;
        begin
            waited = 0;
            while (done_seen == 0 && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end

            if (done_seen != 1)
                fail("Timeout waiting for complete packet / pkt_done");

            repeat (5) @(negedge aclk);

            if (word_seen != WORDS || last_seen != 1 ||
                starts_seen != 1 || done_seen != 1)
                fail("Final word/start/done scoreboard counts mismatch");

            if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0 ||
                m_axis_pkt_tlast !== 1'b0 || pkt_done !== 1'b0)
                fail("Generator not quiescent after completion");

            if (case_ready_mode == 1 &&
                (stall_hits[0] < 4 || stall_hits[7] < 4 ||
                 stall_hits[10] < 4))
                fail("Selected-word backpressure was not actually exercised");

            if (case_ready_mode == 2) begin
                for (n=0; n<WORDS; n=n+1)
                    if (stall_hits[n] < 2)
                        fail("Every-word backpressure was not actually exercised");
            end

            if (case_ready_mode == 3 &&
                (stall_hits[0] < 3 || stall_hits[10] < 40))
                fail("Long first/final-word stalls were not exercised");

            if (case_ready_mode == 5 &&
                (stall_hits[0] < 3 || stall_hits[10] < 3))
                fail("Pseudo-random endpoint stalls were not exercised");

            $display("[PASS] TC%0d packet=%0d seq=%0d changed=%0d mode=%0d (stalls W0=%0d W7=%0d W10=%0d)",
                     current_tc, total_packets+1, model_seq,
                     golden_changed, case_ready_mode,
                     stall_hits[0], stall_hits[7], stall_hits[10]);

            total_packets = total_packets + 1;
            passed = passed + 1;

            model_seq = model_seq + 4'd1;
            model_first_version_pending = 1'b0;

            watch_active = 1'b0;
            ready_mode = 0;
        end
    endtask

    task run_packet;
        input [31:0] sid;
        input [31:0] sec;
        input [63:0] ps;
        input integer bp_mode;
        begin
            begin_packet(sid, sec, ps, bp_mode);
            finish_packet;
        end
    endtask

    task reset_dut;
        integer n;
        begin
            @(negedge aclk);
            aresetn = 1'b0;
            pkt_start = 1'b0;
            watch_active = 1'b0;
            ready_mode = 0;
            time_valid = 1'b0;

            model_seq = 4'd0;
            model_first_version_pending = 1'b1;

            word_seen = 0;
            last_seen = 0;
            starts_seen = 0;
            done_seen = 0;

            for (n=0; n<WORDS; n=n+1)
                stall_hits[n] = 0;

            repeat (4) @(negedge aclk);
            aresetn = 1'b1;
            repeat (2) @(negedge aclk);

            if (pkt_busy !== 1'b0 || pkt_done !== 1'b0 ||
                m_axis_pkt_tvalid !== 1'b0 || m_axis_pkt_tlast !== 1'b0 ||
                m_axis_pkt_tkeep !== 4'hF)
                fail("Reset did not restore an idle, quiet generator");
        end
    endtask

    task abort_at_word;
        input integer index;
        integer waited;
        begin
            stall_word = index;
            begin_packet(32'h5500_0000 | index,
                         32'd700 + index,
                         64'd123456789,
                         4);

            wait_until_word(index);

            waited = 0;
            while (stall_hits[index] < 4 && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end

            if (stall_hits[index] < 4 || pkt_busy !== 1'b1 ||
                m_axis_pkt_tvalid !== 1'b1 || done_seen != 0)
                fail("Failed to arrange an in-flight stalled packet for reset");

            reset_dut;

            run_packet(32'h0000_0002,
                       32'd800 + index,
                       64'd0,
                       0);
        end
    endtask

    integer p;
    reg [31:0] sid_var;
    reg [63:0] ps_var;

    initial begin
        aresetn = 1'b0;
        pkt_start = 1'b0;
        cfg_version_stream_id = 32'd0;
        time_sec = 32'd0;
        time_ps = 64'd0;
        time_valid = 1'b0;
        m_axis_pkt_tready = 1'b1;

        watch_active = 1'b0;
        current_tc = 0;
        passed = 0;
        total_packets = 0;
        total_stalls = 0;
        cycles = 0;

        model_seq = 4'd0;
        model_first_version_pending = 1'b1;
        golden_changed = 1'b0;

        ready_mode = 0;
        case_ready_mode = 0;
        stall_word = 0;

        word_seen = 0;
        last_seen = 0;
        starts_seen = 0;
        done_seen = 0;

        held_beat = 1'b0;
        completion_due = 1'b0;
        previous_done = 1'b0;

        for (k=0; k<WORDS; k=k+1)
            stall_hits[k] = 0;

        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_difi_version_generator.vcd");
            $dumpvars(0, tb_difi_version_generator);
        end

        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc = 1;
        $display("\n=== TC01: complete 11-word known-answer first-Version vector ===");
        begin_packet(32'h0000_0002,
                     32'd100,
                     64'd0,
                     0);
        check_reference_fixture;
        finish_packet;

        current_tc = 2;
        $display("\n=== TC02: subsequent Version packets use no-change and increment seq ===");
        run_packet(32'h0000_0002, 32'd101, 64'd1, 0);
        run_packet(32'h0000_0002, 32'd102, 64'd999999999999, 0);

        current_tc = 3;
        $display("\n=== TC03: time_valid=0 rejects start and does not queue it ===");
        @(negedge aclk);
        if (watch_active || pkt_busy !== 1'b0)
            fail("Not idle before invalid-time test");

        cfg_version_stream_id = 32'h1234_5678;
        time_sec = 32'd200;
        time_ps = 64'd1234;
        time_valid = 1'b0;
        pkt_start = 1'b1;

        repeat (6) begin
            @(negedge aclk);
            if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0 ||
                pkt_done !== 1'b0)
                fail("time_valid=0 must reject start and keep generator idle");
        end

        pkt_start = 1'b0;
        time_valid = 1'b1;
        repeat (4) @(negedge aclk);

        if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0)
            fail("Rejected start was incorrectly queued internally");

        $display("[PASS] TC03 invalid-time start was rejected");
        passed = passed + 1;

        current_tc = 4;
        $display("\n=== TC04: SID/time are snapshotted exactly at accepted start ===");
        begin_packet(32'h1122_3344,
                     32'h0102_0304,
                     64'h0000_00AA_BBCC_DDEE,
                     1);

        cfg_version_stream_id = 32'hDEAD_BEEF;
        time_sec = 32'hFFFF_FFFF;
        time_ps = 64'h0000_00FF_FFFF_FFFF;
        time_valid = 1'b0;
        finish_packet;

        run_packet(32'hDEAD_BEEF,
                   32'hFFFF_FFFF,
                   64'd999999999999,
                   0);

        current_tc = 5;
        $display("\n=== TC05: selected Word0/CIF0/Word10 backpressure ===");
        run_packet(32'hA5A5_0001,
                   32'd300,
                   64'd456789000001,
                   1);

        current_tc = 6;
        $display("\n=== TC06: every one of 11 words stalled for 2 cycles ===");
        run_packet(32'hA5A5_0002,
                   32'd301,
                   64'd999999999999,
                   2);

        current_tc = 7;
        $display("\n=== TC07: Word10 held under backpressure for >=40 cycles ===");
        run_packet(32'hA5A5_0003,
                   32'd302,
                   64'd123456789,
                   3);

        current_tc = 8;
        $display("\n=== TC08: pkt_start while busy is ignored ===");
        begin_packet(32'hCAFE_0001,
                     32'd400,
                     64'd10,
                     2);

        wait_until_word(5);
        @(negedge aclk);
        cfg_version_stream_id = 32'hCAFE_FFFF;
        pkt_start = 1'b1;
        repeat (3) @(negedge aclk);
        pkt_start = 1'b0;
        finish_packet;

        repeat (5) @(negedge aclk);
        if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0 ||
            pkt_done !== 1'b0)
            fail("Busy-time pkt_start created a phantom packet");

        current_tc = 9;
        $display("\n=== TC09: VERSION_STREAM_ID change affects next packet but does NOT reassert changed ===");
        run_packet(32'h0000_1001, 32'd500, 64'd20, 0);
        run_packet(32'h0000_2002, 32'd501, 64'd21, 0);
        
        current_tc = 10;
        $display("\n=== TC10: independent Version sequence wraps 15 -> 0 ===");
        reset_dut;
        for (p=0; p<18; p=p+1) begin
            run_packet(32'h0000_0002,
                       32'd600 + p,
                       p,
                       0);
        end

        current_tc = 11;
        $display("\n=== TC11: reset while final Word10 is stalled; no stale done, fresh first-Version after reset ===");
        reset_dut;
        abort_at_word(10);

        current_tc = 12;
        $display("\n=== TC12: 24 reproducible packets with variable SID/time and bursty stalls ===");
        reset_dut;
        for (p=0; p<24; p=p+1) begin
            sid_var = 32'h5A5A_0000 ^ (p * 32'h0001_0103);
            ps_var  = (p * 64'd2718281829) % 64'd1000000000000;
            run_packet(sid_var,
                       32'd1000 + p,
                       ps_var,
                       (p[0] == 1'b0) ? 5 : 0);
        end

        $display("\nALL ENABLED TESTS PASSED: %0d checks, %0d complete packets, %0d AXIS stall cycles",
                 passed, total_packets, total_stalls);
        $finish;
    end

    initial begin
        #10000000;
        fail("Global deadlock timeout");
    end

endmodule
