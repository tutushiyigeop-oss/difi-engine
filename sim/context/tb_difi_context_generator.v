`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

module tb_difi_context_generator;
    localparam integer WORDS       = 27;
    localparam integer WAIT_LIMIT  = 20000;
    localparam [63:0] MAX_PS       = 64'd999999999999;

    reg         aclk, aresetn;
    reg         pkt_start;
    wire        pkt_busy, pkt_done;
    reg  [31:0] cfg_data_stream_id;
    reg  [31:0] cfg_sample_rate_hz, cfg_bandwidth_hz;
    reg  [63:0] cfg_rf_freq_hz;
    reg         cfg_context_change_pending;
    wire        context_change_done;
    reg  [31:0] time_sec;
    reg  [63:0] time_ps;
    reg         time_valid;
    wire [31:0] m_axis_pkt_tdata;
    wire        m_axis_pkt_tvalid;
    reg         m_axis_pkt_tready;
    wire [3:0]  m_axis_pkt_tkeep;
    wire        m_axis_pkt_tlast;
    wire        m_axis_fire = m_axis_pkt_tvalid && m_axis_pkt_tready;

    difi_context_generator dut (
        .aclk(aclk), .aresetn(aresetn),
        .pkt_start(pkt_start), .pkt_busy(pkt_busy), .pkt_done(pkt_done),
        .cfg_data_stream_id(cfg_data_stream_id),
        .cfg_sample_rate_hz(cfg_sample_rate_hz),
        .cfg_bandwidth_hz(cfg_bandwidth_hz),
        .cfg_rf_freq_hz(cfg_rf_freq_hz),
        .cfg_context_change_pending(cfg_context_change_pending),
        .context_change_done(context_change_done),
        .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
        .m_axis_pkt_tdata(m_axis_pkt_tdata),
        .m_axis_pkt_tvalid(m_axis_pkt_tvalid),
        .m_axis_pkt_tready(m_axis_pkt_tready),
        .m_axis_pkt_tkeep(m_axis_pkt_tkeep),
        .m_axis_pkt_tlast(m_axis_pkt_tlast)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    reg [31:0] golden_word [0:WORDS-1];
    reg [3:0]  model_seq;
    reg        golden_change;
    reg        watch_active;
    integer    current_tc, passed, skipped;
    integer    word_seen, last_seen, starts_seen, done_seen, change_seen;
    integer    stall_hits [0:WORDS-1];
    integer    total_stalls, total_packets;
    integer    cycles;
    integer    ready_mode, case_ready_mode, stall_word;
    reg        previous_done, previous_change;
    reg        completion_due, completion_change_due;
    reg        held_beat;
    reg [31:0] held_data;
    reg [3:0]  held_keep;
    reg        held_last;
    integer    k;

    task fail;
        input [8*240-1:0] message;
        begin
            $display("[FAIL] TC%0d @%0t: %0s", current_tc, $time, message);
            $display("       words=%0d/27 last=%0d starts=%0d done=%0d change=%0d seq_model=%0d",
                     word_seen, last_seen, starts_seen, done_seen,
                     change_seen, model_seq);
            $display("       AXIS: data=%h valid=%b ready=%b keep=%h last=%b busy=%b",
                     m_axis_pkt_tdata, m_axis_pkt_tvalid, m_axis_pkt_tready,
                     m_axis_pkt_tkeep, m_axis_pkt_tlast, pkt_busy);
            $fatal(1, "Context generator test failed");
        end
    endtask

    // Scale in 64 bits before splitting the high and low words.
    task make_golden;
        input [31:0] sid, fs_hz, bw_hz, sec;
        input [63:0] rf_hz, ps;
        input        changed;
        reg [63:0] bw_scaled, rf_scaled, fs_scaled;
        integer n;
        begin
            if (ps > MAX_PS || fs_hz == 0 || bw_hz == 0 || bw_hz > fs_hz ||
                rf_hz > 64'd100000000000)
                fail("Test supplied config outside the frozen project profile");
            bw_scaled = {32'd0, bw_hz} * 64'd1048576;
            rf_scaled = rf_hz * 64'd1048576;
            fs_scaled = {32'd0, fs_hz} * 64'd1048576;
            for (n=0; n<WORDS; n=n+1)
                golden_word[n] = 32'h00000000;
            golden_word[0]  = 32'h4960001B | ({28'd0,model_seq} << 16);
            golden_word[1]  = sid;
            golden_word[2]  = 32'h006A621E;
            golden_word[3]  = 32'h00000001;
            golden_word[4]  = sec;
            golden_word[5]  = ps[63:32];
            golden_word[6]  = ps[31:0];
            golden_word[7]  = changed ? 32'hFBB98000 : 32'h7BB98000;
            golden_word[8]  = 32'h00000064;
            golden_word[9]  = bw_scaled[63:32];
            golden_word[10] = bw_scaled[31:0];
            
            golden_word[13] = rf_scaled[63:32];
            golden_word[14] = rf_scaled[31:0];
            golden_word[19] = fs_scaled[63:32];
            golden_word[20] = fs_scaled[31:0];
            
            golden_word[25] = 32'hA00003CF;
            golden_word[26] = 32'h00000000;
        end
    endtask

    task check_reference_fixture;
        reg [31:0] literal [0:WORDS-1];
        integer n;
        begin
            for (n=0; n<WORDS; n=n+1) literal[n] = 32'd0;
            literal[0] = 32'h4960001B; literal[1] = 32'h00000001;
            literal[2] = 32'h006A621E; literal[3] = 32'h00000001;
            literal[4] = 32'h00000064;
            literal[7] = 32'hFBB98000; literal[8] = 32'h00000064;
            literal[9] = 32'h00000989; literal[10] = 32'h68000000;
            literal[13] = 32'h00005F5E; literal[14] = 32'h10000000;
            literal[19] = 32'h00001312; literal[20] = 32'hD0000000;
            literal[25] = 32'hA00003CF;
            for (n=0; n<WORDS; n=n+1)
                if (golden_word[n] !== literal[n]) begin
                    $display("  Appendix C.2 word%0d: expected=%h model=%h",
                             n, literal[n], golden_word[n]);
                    fail("Independent reference fixture does not match golden builder");
                end
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            held_beat            = 1'b0;
            completion_due       = 1'b0;
            completion_change_due= 1'b0;
            previous_done        = 1'b0;
            previous_change      = 1'b0;
        end else begin
            cycles = cycles + 1;

            if (m_axis_pkt_tkeep !== 4'hF)
                fail("TKEEP must be 4'b1111 on every cycle");
            if (pkt_busy !== 1'b0 && pkt_busy !== 1'b1)
                fail("pkt_busy is X/Z");
            if (m_axis_pkt_tvalid !== 1'b0 && m_axis_pkt_tvalid !== 1'b1)
                fail("TVALID is X/Z");
            if (pkt_done !== 1'b0 && pkt_done !== 1'b1)
                fail("pkt_done is X/Z");
            if (context_change_done !== 1'b0 && context_change_done !== 1'b1)
                fail("context_change_done is X/Z");
            if (pkt_done && previous_done)
                fail("pkt_done must be a one-clock pulse");
            if (context_change_done && previous_change)
                fail("context_change_done must be a one-clock pulse");
            previous_done   = pkt_done;
            previous_change = context_change_done;

            if (completion_due) begin
                if (pkt_done !== 1'b1)
                    fail("Missing pkt_done immediately after last-word handshake");
                if (context_change_done !== completion_change_due)
                    fail("Incorrect change_done following last-word handshake");
                if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0)
                    fail("Generator did not return to idle after last handshake");
                done_seen = done_seen + 1;
                if (completion_change_due)
                    change_seen = change_seen + 1;
                completion_due = 1'b0;
                completion_change_due = 1'b0;
            end else if (pkt_done !== 1'b0 || context_change_done !== 1'b0) begin
                fail("Early, duplicate, or unarmed completion pulse");
            end

            if (pkt_start === 1'b1 && time_valid === 1'b1 &&
                pkt_busy === 1'b0) begin
                if (!watch_active || starts_seen != 0)
                    fail("Unexpected or repeated start acceptance");
                starts_seen = starts_seen + 1;
            end
            if (pkt_busy === 1'b1) begin
                if (!watch_active || starts_seen != 1)
                    fail("Generator busy without an accepted start");
                if (m_axis_pkt_tvalid !== 1'b1)
                    fail("Output bubble: sending state must present a valid word");
            end else if (m_axis_pkt_tvalid !== 1'b0 || m_axis_pkt_tlast !== 1'b0) begin
                fail("Output TVALID/TLAST asserted while generator is idle");
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
                    fail("Unarmed/extra output word");
                if (m_axis_pkt_tdata !== golden_word[word_seen]) begin
                    $display("  Word[%0d]: expected=%h actual=%h",
                             word_seen, golden_word[word_seen], m_axis_pkt_tdata);
                    fail("DIFI Context word mismatch");
                end
                if (m_axis_pkt_tlast !== (word_seen == WORDS-1))
                    fail("TLAST must appear only on Word26");
            end

            if (m_axis_pkt_tvalid === 1'b1 && m_axis_pkt_tready === 1'b0) begin
                if (word_seen >= WORDS) fail("Stall beyond end of packet");
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
                if (word_seen >= WORDS) fail("More than 27 words transferred");
                if (word_seen == WORDS-1) begin
                    last_seen = last_seen + 1;
                    if (last_seen != 1) fail("More than one final handshake");
                    completion_due = 1'b1;
                    completion_change_due = golden_change;
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
                0: m_axis_pkt_tready = 1'b1;
                1: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        (word_seen==0 || word_seen==7 || word_seen==9 ||
                         word_seen==13 || word_seen==19 || word_seen==25 ||
                         word_seen==26) && stall_hits[word_seen] < 4)
                        m_axis_pkt_tready = 1'b0;
                    else m_axis_pkt_tready = 1'b1;
                end
                2: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        stall_hits[word_seen] < 2)
                        m_axis_pkt_tready = 1'b0;
                    else m_axis_pkt_tready = 1'b1;
                end
                3: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        ((word_seen==0 || word_seen==26) &&
                         stall_hits[word_seen] < 3 ||
                         ((cycles*7 + word_seen*11) % 5 < 2)))
                        m_axis_pkt_tready = 1'b0;
                    else m_axis_pkt_tready = 1'b1;
                end
                4: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        ((word_seen == 0 && stall_hits[0] < 3) ||
                         (word_seen == 26 && stall_hits[26] < 40)))
                        m_axis_pkt_tready = 1'b0;
                    else m_axis_pkt_tready = 1'b1;
                end
                5: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        word_seen == stall_word)
                        m_axis_pkt_tready = 1'b0;
                    else m_axis_pkt_tready = 1'b1;
                end
                6: begin
                    if (watch_active && m_axis_pkt_tvalid &&
                        (((word_seen==0 || word_seen==26) &&
                          stall_hits[word_seen] < 3) ||
                         (cycles % 17 < 7)))
                        m_axis_pkt_tready = 1'b0;
                    else m_axis_pkt_tready = 1'b1;
                end
                default: m_axis_pkt_tready = 1'b1;
            endcase
        end
    end

    task begin_packet;
        input [31:0] sid, fs, bw, sec;
        input [63:0] rf, ps;
        input change_bit;
        input integer bp_mode;
        integer n;
        begin
            @(negedge aclk);
            if (watch_active || pkt_busy !== 1'b0 ||
                m_axis_pkt_tvalid !== 1'b0 || pkt_done !== 1'b0 ||
                context_change_done !== 1'b0)
                fail("Previous packet has not become idle");
            cfg_data_stream_id = sid;
            cfg_sample_rate_hz = fs;
            cfg_bandwidth_hz = bw;
            cfg_rf_freq_hz = rf;
            cfg_context_change_pending = change_bit;
            time_sec = sec;
            time_ps = ps;
            time_valid = 1'b1;
            ready_mode = bp_mode;
            case_ready_mode = bp_mode;
            word_seen = 0; last_seen = 0; starts_seen = 0;
            done_seen = 0; change_seen = 0;
            for (n=0; n<WORDS; n=n+1)
                stall_hits[n] = 0;
            golden_change = change_bit;
            make_golden(sid, fs, bw, sec, rf, ps, change_bit);
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
            if (word_seen < target) fail("Timeout waiting for word index");
        end
    endtask

    task finish_packet;
        integer waited, n;
        begin
            waited = 0;
            while (done_seen == 0 && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end
            if (done_seen != 1) fail("Timeout waiting for complete packet/done");
            repeat (6) @(negedge aclk); 
            if (word_seen != WORDS || last_seen != 1 || starts_seen != 1 ||
                done_seen != 1 || change_seen != (golden_change ? 1 : 0))
                fail("Final word/start/done/change scoreboard counts mismatch");
            if (pkt_busy !== 1'b0 || m_axis_pkt_tvalid !== 1'b0 ||
                m_axis_pkt_tlast !== 1'b0 || pkt_done !== 1'b0 ||
                context_change_done !== 1'b0)
                fail("Generator not quiescent after completion");
            if (case_ready_mode == 1 &&
                (stall_hits[0]<4 || stall_hits[7]<4 || stall_hits[9]<4 ||
                 stall_hits[13]<4 || stall_hits[19]<4 || stall_hits[25]<4 ||
                 stall_hits[26]<4))
                fail("Selected-word backpressure not actually exercised");
            if (case_ready_mode == 2)
                for (n=0; n<WORDS; n=n+1)
                    if (stall_hits[n] < 2)
                        fail("Every-word backpressure not actually exercised");
            if (case_ready_mode == 4 &&
                (stall_hits[0] < 3 || stall_hits[26] < 40))
                fail("Long first/last-word stalls were not exercised");
            if ((case_ready_mode == 3 || case_ready_mode == 6) &&
                (stall_hits[0] < 3 || stall_hits[26] < 3))
                fail("Random/bursty endpoint backpressure not exercised");
            $display("[PASS] TC%0d packet=%0d seq=%0d change=%0d mode=%0d (stalls W0=%0d W26=%0d)",
                     current_tc,total_packets+1,model_seq,golden_change,
                     case_ready_mode,stall_hits[0],stall_hits[26]);
            total_packets = total_packets + 1;
            passed = passed + 1;
            model_seq = model_seq + 4'd1;
            watch_active = 1'b0;
            ready_mode = 0;
        end
    endtask

    task run_packet;
        input [31:0] sid, fs, bw, sec;
        input [63:0] rf, ps;
        input change_bit;
        input integer bp_mode;
        begin
            begin_packet(sid,fs,bw,sec,rf,ps,change_bit,bp_mode);
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
            cfg_context_change_pending = 1'b0;
            time_valid = 1'b0;
            model_seq = 4'd0;
            word_seen = 0; last_seen = 0; starts_seen = 0;
            done_seen = 0; change_seen = 0;
            for (n=0; n<WORDS; n=n+1) stall_hits[n] = 0;
            repeat (4) @(negedge aclk);
            aresetn = 1'b1;
            repeat (2) @(negedge aclk);
            if (pkt_busy !== 1'b0 || pkt_done !== 1'b0 ||
                context_change_done !== 1'b0 ||
                m_axis_pkt_tvalid !== 1'b0 || m_axis_pkt_tlast !== 1'b0 ||
                m_axis_pkt_tkeep !== 4'hF)
                fail("Reset did not restore an idle, quiet generator");
        end
    endtask

    task abort_at_word;
        input integer index;
        integer waited;
        begin
            begin_packet(32'h12340000 | index,32'd20000000,
                         32'd10000000,32'd500+index,
                         64'd2400000000,64'd123456789,
                         1'b1,5);
            
            @(negedge aclk);
            stall_word = index;
            wait_until_word(index);
            waited = 0;
            while (stall_hits[index] < 4 && waited < WAIT_LIMIT) begin
                @(negedge aclk);
                waited = waited + 1;
            end
            if (stall_hits[index] < 4 || pkt_busy !== 1'b1 ||
                m_axis_pkt_tvalid !== 1'b1 ||
                done_seen != 0 || change_seen != 0)
                fail("Failed to arrange an in-flight stalled packet for reset");
            reset_dut;
            // Restart the sequence at zero after abort; no stale output should remain.
            run_packet(32'd1,32'd20000000,32'd10000000,32'd600+index,
                       64'd100000000,64'd0,1'b1,0);
        end
    endtask

    integer j, p;
    reg [63:0] rf_var, ps_var;
    reg [31:0] fs_var, bw_var, sid_var;
    initial begin
        aresetn = 1'b0;
        pkt_start = 1'b0;
        cfg_data_stream_id = 32'd0;
        cfg_sample_rate_hz = 32'd0;
        cfg_bandwidth_hz = 32'd0;
        cfg_rf_freq_hz = 64'd0;
        cfg_context_change_pending = 1'b0;
        time_sec = 32'd0;
        time_ps = 64'd0;
        time_valid = 1'b0;
        m_axis_pkt_tready = 1'b1;
        watch_active = 1'b0;
        current_tc = 0; passed = 0; skipped = 0;
        total_packets = 0; total_stalls = 0; cycles = 0;
        model_seq = 4'd0;
        ready_mode = 0; case_ready_mode = 0; stall_word = 0;
        word_seen = 0; last_seen = 0; starts_seen = 0;
        done_seen = 0; change_seen = 0;
        held_beat = 0; completion_due = 0;
        completion_change_due = 0;
        previous_done = 0; previous_change = 0;
        for (j=0; j<WORDS; j=j+1) stall_hits[j] = 0;
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_difi_context_generator.vcd");
            $dumpvars(0,tb_difi_context_generator);
        end
        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc=1;
        $display("\n=== TC01: project Appendix C.2 complete 27-word known-answer vector ===");
        
        begin_packet(32'd1,32'd20000000,32'd10000000,32'd100,
                     64'd100000000,64'd0,1'b1,0);
        check_reference_fixture;
        finish_packet;

        current_tc=2;
        $display("\n=== TC02: periodic Context, changed=0, adjacent packets ===");
        run_packet(32'd1,32'd20000000,32'd10000000,32'd101,
                   64'd100000000,64'd0,1'b0,0);
        run_packet(32'd1,32'd20000000,32'd10000000,32'd102,
                   64'd100000000,64'd0,1'b0,0);

        current_tc=3;
        $display("\n=== TC03: min/max legal Hz, RF, time_ps and 32-bit fields ===");
        run_packet(32'h00000000,32'd1,32'd1,32'd0,
                   64'd0,64'd0,1'b1,0);
        run_packet(32'hFFFFFFFF,32'hFFFFFFFF,32'hFFFFFFFF,32'hFFFFFFFF,
                   64'd100000000000,MAX_PS,1'b0,0);
        run_packet(32'h89ABCDEF,32'd4294967295,32'd1,32'h80000000,
                   64'd4294967295,64'd4294967296,1'b1,0);
        run_packet(32'h10203040,32'd25000000,32'd24999999,32'h7FFFFFFF,
                   64'd2400000000,64'd1,1'b0,0);

        current_tc=4;
        $display("\n=== TC04: selected Word0/CIF/BW/RF/Fs/DPF/Word26 stalls ===");
        run_packet(32'hDEADBEEF,32'd25000000,32'd12000000,32'd200,
                   64'd2500000000,64'd456789000001,1'b1,1);

        current_tc=5;
        $display("\n=== TC05: every one of 27 words stalled (2 cycles per word) ===");
        run_packet(32'h12345678,32'd32000000,32'd16000000,32'd201,
                   64'd5500000000,MAX_PS,1'b0,2);

        current_tc=6;
        $display("\n=== TC06: Word26 held at TLAST for >=40 cycles; no early done/seq ===");
        run_packet(32'd3,32'd20000000,32'd10000000,32'd202,
                   64'd6000000000,64'd123456,1'b1,4);

        current_tc=7;
        $display("\n=== TC07: time_valid=0 refuses start (no implicit queued request) ===");
        @(negedge aclk);
        if (watch_active || pkt_busy !== 0) fail("Not idle before invalid-time test");
        time_valid=0;
        pkt_start=1;
        repeat (6) begin
            @(negedge aclk);
            if (pkt_busy !== 0 || m_axis_pkt_tvalid !== 0 ||
                pkt_done !== 0 || context_change_done !== 0)
                fail("Invalid time must reject start and keep all outputs idle");
        end
        pkt_start=0;
        time_valid=1;
        repeat (5) @(negedge aclk);
        if (pkt_busy !== 0 || m_axis_pkt_tvalid !== 0)
            fail("Rejected start was incorrectly queued internally");
        $display("[PASS] TC07 invalid-time start was rejected");
        passed=passed+1;
        run_packet(32'd7,32'd20000000,32'd10000000,32'd203,
                   64'd100000000,64'd9,1'b0,0);

        current_tc=8;
        $display("\n=== TC08: all config/time/pending change immediately AFTER accept ===");
        begin_packet(32'h00000111,32'd20000000,32'd10000000,32'd300,
                     64'd4900000000,64'd100,1'b1,1);
        
        cfg_data_stream_id=32'h99999999;
        cfg_sample_rate_hz=32'd0;
        cfg_bandwidth_hz=32'd0;
        cfg_rf_freq_hz=64'hFFFFFFFFFFFFFFFF;
        cfg_context_change_pending=0;
        time_sec=32'hFFFFFFFF;
        time_ps=64'hFFFFFFFFFFFFFFFF;
        time_valid=0;
        finish_packet;
        
        run_packet(32'h99999999,32'd25000000,32'd12500000,32'd301,
                   64'd7700000000,64'd1234,1'b0,0);

        current_tc=9;
        $display("\n=== TC09: midpacket config/time mutation at RF word ===");
        begin_packet(32'hAABBCCDD,32'd40000000,32'd30000000,32'd400,
                     64'd3500000000,64'd987654321000,1'b0,2);
        wait_until_word(13);
        
        @(negedge aclk);
        cfg_rf_freq_hz=64'd100000000000;
        cfg_sample_rate_hz=32'd2;
        cfg_bandwidth_hz=32'd1;
        cfg_data_stream_id=32'd99;
        cfg_context_change_pending=1;
        time_sec=32'd999;
        time_ps=64'd0;
        time_valid=0;
        finish_packet;
        
        current_tc=10;
        $display("\n=== TC10: pkt_start while busy ignored, even if time_valid toggles ===");
        begin_packet(32'd77,32'd10000000,32'd5000000,32'd401,
                     64'd100000000,64'd10,1'b1,2);
        wait_until_word(5);
        @(negedge aclk);
        pkt_start=1;
        time_valid=0;
        repeat (4) @(negedge aclk);
        pkt_start=0;
        time_valid=1;
        finish_packet; 

        current_tc=11;
        $display("\n=== TC11: pending changes at LAST WORD are not re-snapshotted ===");
        begin_packet(32'd78,32'd30000000,32'd15000000,32'd402,
                     64'd4300000000,64'd11,1'b0,4);
        wait_until_word(26);
        @(negedge aclk);
        cfg_context_change_pending=1; 
        finish_packet; 
        run_packet(32'd78,32'd30000000,32'd15000000,32'd403,
                   64'd4300000000,64'd12,1'b1,0);
        
        begin_packet(32'd78,32'd30000000,32'd15000000,32'd404,
                     64'd4300000000,64'd13,1'b1,4);
        wait_until_word(26);
        @(negedge aclk);
        cfg_context_change_pending=0;
        finish_packet;

        current_tc=12;
        $display("\n=== TC12: 20 packets, independent seq increment and 15->0 wrap ===");
        reset_dut;
        for (p=0; p<20; p=p+1)
            run_packet(32'd1,32'd20000000,32'd10000000,32'd500+p,
                       64'd2400000000,64'd100+p,(p%3==0),p%3);

        current_tc=13;
        $display("\n=== TC13: reset at Word0 while held under backpressure ===");
        reset_dut;
        abort_at_word(0);

        current_tc=14;
        $display("\n=== TC14: reset at middle Word13 while held ===");
        abort_at_word(13);

        current_tc=15;
        $display("\n=== TC15: reset at final Word26 while held (no stale done) ===");
        abort_at_word(26);

        current_tc=16;
        $display("\n=== TC16: 64 reproducible variable-config and pseudo-random stall packets ===");
        reset_dut;
        for (p=0; p<64; p=p+1) begin
            sid_var=32'hA5A50000 ^ (p*32'h00010103);
            fs_var=32'd1000000 + ((p*9973)%32'd100000000);
            bw_var=1 + (fs_var * 1 / 2);
            rf_var=64'd100000000 + ((p*64'd1729382257)%64'd99900000000);
            ps_var=(p*64'd2718281829)%64'd1000000000000;
            run_packet(sid_var,fs_var,bw_var,32'd1000+p,rf_var,ps_var,
                       (p%5==0), (p%2==0)?3:6);
        end

        current_tc=17;
        $display("\n=== TC17: extended 80-packet continuous ready stress, alternating change ===");
        for (p=0; p<80; p=p+1)
            run_packet(32'd2+(p%3),32'd20000000,32'd10000000,
                       32'd2000+p,64'd100000000+(p*64'd1000000),
                       p*64'd1234567,(p%2==0),0);

        $display("\nALL ENABLED TESTS PASSED: %0d checks, %0d complete packets, %0d AXIS stall cycles, %0d skipped",
                 passed,total_packets,total_stalls,skipped);
        $finish;
    end

    initial begin
        #15000000;
        fail("Global deadlock timeout");
    end
endmodule
