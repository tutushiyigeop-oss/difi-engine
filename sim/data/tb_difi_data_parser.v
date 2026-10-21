`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

module tb_difi_data_parser;
    localparam integer MAX_SAMPLES = 256;
    localparam integer MAX_WORDS   = 600; 
    localparam integer WAIT_LIMIT  = 20000;
    localparam integer RUN_TIMESTAMP_STRICT = 0;
    localparam integer RUN_MULTI_SID_STRICT = 0;

    reg         aclk, aresetn;
    reg  [31:0] s_axis_pkt_tdata;
    reg         s_axis_pkt_tvalid;
    wire        s_axis_pkt_tready;
    reg  [3:0]  s_axis_pkt_tkeep;
    reg         s_axis_pkt_tlast;
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

    wire pkt_fire  = s_axis_pkt_tvalid && s_axis_pkt_tready;
    wire iq_fire   = m_axis_iq_tvalid && m_axis_iq_tready;
    wire meta_fire = m_meta_valid && m_meta_ready;

    difi_data_parser dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_pkt_tdata(s_axis_pkt_tdata),
        .s_axis_pkt_tvalid(s_axis_pkt_tvalid),
        .s_axis_pkt_tready(s_axis_pkt_tready),
        .s_axis_pkt_tkeep(s_axis_pkt_tkeep),
        .s_axis_pkt_tlast(s_axis_pkt_tlast),
        .cfg_stream_filter_enable(cfg_stream_filter_enable),
        .cfg_expected_stream_id(cfg_expected_stream_id),
        .m_axis_iq_tdata(m_axis_iq_tdata),
        .m_axis_iq_tvalid(m_axis_iq_tvalid),
        .m_axis_iq_tready(m_axis_iq_tready),
        .m_axis_iq_tlast(m_axis_iq_tlast),
        .m_meta_valid(m_meta_valid),
        .m_meta_ready(m_meta_ready),
        .m_meta_stream_id(m_meta_stream_id),
        .m_meta_seq(m_meta_seq),
        .m_meta_time_sec(m_meta_time_sec),
        .m_meta_time_ps(m_meta_time_ps),
        .m_meta_sample_count(m_meta_sample_count),
        .error_valid(error_valid), .error_code(error_code)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    reg [31:0] tx_word [0:MAX_WORDS-1];
    reg [3:0]  tx_keep [0:MAX_WORDS-1];
    reg        tx_last [0:MAX_WORDS-1];
    reg [31:0] golden_iq [0:MAX_SAMPLES-1];
    integer tx_len, golden_n, golden_err_count, golden_meta_count;
    reg [3:0] golden_err_code;
    reg [31:0] golden_sid, golden_sec;
    reg [3:0]  golden_seq;
    reg [63:0] golden_ps;
    integer current_tc, passed, skipped;
    reg watch_active;

    integer rx_seen, rx_last_seen, iq_seen, meta_seen, err_seen;
    reg hold_iq, hold_meta, hold_rx;
    reg [31:0] held_rx_data;
    reg [3:0] held_rx_keep;
    reg held_rx_last;
    reg [31:0] held_iq_data;
    reg held_iq_last;
    reg [31:0] held_sid, held_sec;
    reg [3:0] held_seq;
    reg [63:0] held_ps;
    reg [15:0] held_count;
    reg previous_err;

    reg stall_meta, stall_iq;
    integer meta_stall_cycles, iq_stall_cycles;
    integer meta_stall_hits;
    integer iq_stall_hits [0:MAX_SAMPLES-1];
    integer gap_mode;

    task fail;
        input [8*200-1:0] message;
        begin
            $display("[FAIL] TC%0d @%0t: %0s", current_tc, $time, message);
            $display("  rx=%0d/%0d(last=%0d), meta=%0d/%0d, iq=%0d/%0d, err=%0d/%0d, err_code=%h",
                     rx_seen, tx_len, rx_last_seen, meta_seen, golden_meta_count,
                     iq_seen, golden_n, err_seen, golden_err_count, error_code);
            $finish;
        end
    endtask

    function [31:0] sample_value;
        input integer idx, tag, reference;
        begin
            if (reference != 0) begin
                case (idx)
                    0: sample_value = 32'h0001_FFFF;
                    1: sample_value = 32'h7FFF_8000;
                    2: sample_value = 32'hFFFE_0003;
                    3: sample_value = 32'h0000_0000;
                    default: sample_value = 32'hxxxx_xxxx;
                endcase
            end else begin
                sample_value = 32'h1357_9BDF ^ (tag * 32'h0001_0001)
                                              ^ (idx * 32'h0001_0103);
            end
        end
    endfunction

    task make_packet;
        input integer n;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        input integer tag, reference;
        integer j;
        begin
            if (n < 1 || n > MAX_SAMPLES)
                fail("Illegal testbench N");
            tx_len = 7 + n;
            tx_word[0] = 32'h1860_0000 | ({28'd0,seq} << 16) | tx_len;
            tx_word[1] = sid;
            tx_word[2] = 32'h006A_621E;
            tx_word[3] = 32'h0000_0000;
            tx_word[4] = sec;
            tx_word[5] = ps[63:32];
            tx_word[6] = ps[31:0];
            for (j = 0; j < n; j = j + 1)
                tx_word[7+j] = sample_value(j, tag, reference);
            for (j = 0; j < tx_len; j = j + 1) begin
                tx_keep[j] = 4'hF;
                tx_last[j] = (j == tx_len-1);
            end
        end
    endtask

    task arm_case;
        input integer n, tag, reference, error_expected;
        input [3:0] error_expected_code;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        input integer with_meta_stall, with_iq_stall;
        integer j;
        begin
            @(negedge aclk);
            if (watch_active)
                fail("Previous case still armed");
            if (s_axis_pkt_tvalid !== 1'b0)
                fail("Input still valid before arming");
            golden_n         = (error_expected == 1) ? 0 : n;
            golden_meta_count = (error_expected == 1) ? 0 : 1;
            golden_err_count = (error_expected != 0) ? 1 : 0;
            golden_err_code  = error_expected_code;
            golden_sid = sid;
            golden_seq = seq;
            golden_sec = sec;
            golden_ps  = ps;
            rx_seen = 0;
            rx_last_seen = 0;
            iq_seen = 0;
            meta_seen = 0;
            err_seen = 0;
            meta_stall_hits = 0;
            stall_meta = (with_meta_stall != 0);
            stall_iq   = (with_iq_stall != 0);
            meta_stall_cycles = 4;
            iq_stall_cycles = 3;
            for (j = 0; j < MAX_SAMPLES; j = j+1) begin
                iq_stall_hits[j] = 0;
                if (j < n)
                    golden_iq[j] = sample_value(j, tag, reference);
            end
            watch_active = 1'b1;
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            hold_iq = 1'b0;
            hold_meta = 1'b0;
            hold_rx = 1'b0;
            previous_err = 1'b0;
        end else begin
            if (hold_rx) begin
                if (s_axis_pkt_tvalid !== 1'b1 ||
                    s_axis_pkt_tdata !== held_rx_data ||
                    s_axis_pkt_tkeep !== held_rx_keep ||
                    s_axis_pkt_tlast !== held_rx_last)
                    fail("Input AXIS source changed its beat while stalled");
            end
            hold_rx = (s_axis_pkt_tvalid === 1'b1 &&
                       s_axis_pkt_tready === 1'b0);
            if (hold_rx) begin
                held_rx_data = s_axis_pkt_tdata;
                held_rx_keep = s_axis_pkt_tkeep;
                held_rx_last = s_axis_pkt_tlast;
            end
            if (hold_iq) begin
                if (m_axis_iq_tvalid !== 1'b1 ||
                    m_axis_iq_tdata !== held_iq_data ||
                    m_axis_iq_tlast !== held_iq_last)
                    fail("IQ output changed while stalled");
            end
            if (hold_meta) begin
                if (m_meta_valid !== 1'b1 ||
                    m_meta_stream_id !== held_sid ||
                    m_meta_seq !== held_seq ||
                    m_meta_time_sec !== held_sec ||
                    m_meta_time_ps !== held_ps ||
                    m_meta_sample_count !== held_count)
                    fail("Metadata changed while stalled");
            end

            if (m_meta_valid === 1'b1 && !watch_active)
                fail("Unarmed metadata output");
            if (m_axis_iq_tvalid === 1'b1 && !watch_active)
                fail("Unarmed IQ output");
            if (watch_active && m_meta_valid === 1'b1 &&
                meta_seen >= golden_meta_count)
                fail("Metadata VALID asserted when no metadata is due");
            if (watch_active && m_axis_iq_tvalid === 1'b1 &&
                (golden_n == 0 || meta_seen != 1 || iq_seen >= golden_n))
                fail("Unexpected IQ VALID or IQ arrived before metadata handshake");
            if (error_valid === 1'b1 && !watch_active)
                fail("Unarmed error event");
            if (error_valid !== 1'b0 && error_valid !== 1'b1)
                fail("error_valid is X/Z");
            if (error_valid === 1'b1 && previous_err)
                fail("error_valid not a one-cycle pulse");
            previous_err = error_valid;

            if (pkt_fire) begin
                if (!watch_active) fail("Unexpected input transfer");
                rx_seen = rx_seen + 1;
                if (s_axis_pkt_tlast === 1'b1)
                    rx_last_seen = rx_last_seen + 1;
            end
            if (m_meta_valid === 1'b1 && m_meta_ready === 1'b0) begin
                if (stall_meta) meta_stall_hits = meta_stall_hits + 1;
            end
            if (m_axis_iq_tvalid === 1'b1 && m_axis_iq_tready === 1'b0) begin
                if (stall_iq && iq_seen < MAX_SAMPLES)
                    iq_stall_hits[iq_seen] = iq_stall_hits[iq_seen] + 1;
            end

            hold_meta = (m_meta_valid === 1'b1 && m_meta_ready === 1'b0);
            if (hold_meta) begin
                held_sid   = m_meta_stream_id;
                held_seq   = m_meta_seq;
                held_sec   = m_meta_time_sec;
                held_ps    = m_meta_time_ps;
                held_count = m_meta_sample_count;
            end
            hold_iq = (m_axis_iq_tvalid === 1'b1 && m_axis_iq_tready === 1'b0);
            if (hold_iq) begin
                held_iq_data = m_axis_iq_tdata;
                held_iq_last = m_axis_iq_tlast;
            end

            if (error_valid === 1'b1) begin
                if (golden_err_code == `DIFI_ERR_SEQ && rx_last_seen != 1)
                    fail("Sequence error reported before complete packet");
                if (!watch_active || err_seen >= golden_err_count)
                    fail("Unexpected/duplicate error event");
                if (error_code !== golden_err_code) begin
                    $display("  Expected error=%h, got=%h", golden_err_code, error_code);
                    fail("Incorrect error code/priority");
                end
                err_seen = err_seen + 1;
            end
            if (meta_fire) begin
                if (!watch_active || meta_seen >= golden_meta_count)
                    fail("Unexpected/duplicate metadata");
                if (rx_last_seen !== 1)
                    fail("Metadata committed before complete input packet");
                if (m_meta_stream_id !== golden_sid ||
                    m_meta_seq !== golden_seq ||
                    m_meta_time_sec !== golden_sec ||
                    m_meta_time_ps !== golden_ps ||
                    m_meta_sample_count !== golden_n) begin
                    $display("  META expected: SID=%h seq=%h sec=%h ps=%h samples=%0d",
                             golden_sid,golden_seq,golden_sec,golden_ps,golden_n);
                    $display("  META actual:   SID=%h seq=%h sec=%h ps=%h samples=%0d",
                             m_meta_stream_id,m_meta_seq,m_meta_time_sec,m_meta_time_ps,m_meta_sample_count);
                    fail("Metadata mismatch");
                end
                meta_seen = meta_seen + 1;
            end
            if (iq_fire) begin
                if (!watch_active || meta_seen != 1)
                    fail("IQ emitted before metadata handshake");
                if (iq_seen >= golden_n)
                    fail("Unexpected/extra IQ sample");
                if (m_axis_iq_tdata !== golden_iq[iq_seen]) begin
                    $display("  IQ[%0d]: expected=%h actual=%h",iq_seen,golden_iq[iq_seen],m_axis_iq_tdata);
                    fail("IQ data mismatch");
                end
                if (m_axis_iq_tlast !== (iq_seen == golden_n-1))
                    fail("IQ TLAST mismatch");
                iq_seen = iq_seen + 1;
            end
        end
    end

    always @(negedge aclk) begin
        if (!aresetn) begin
            m_meta_ready = 1'b1;
            m_axis_iq_tready = 1'b1;
        end else begin
            if (watch_active && stall_meta && m_meta_valid === 1'b1 &&
                meta_stall_hits < meta_stall_cycles)
                m_meta_ready = 1'b0;
            else
                m_meta_ready = 1'b1;

            if (watch_active && stall_iq && m_axis_iq_tvalid === 1'b1 &&
                iq_seen < golden_n &&
                (iq_seen == 0 || iq_seen == golden_n-1 ||
                 iq_seen == 1 || (iq_seen % 17) == 0) &&
                iq_stall_hits[iq_seen] < iq_stall_cycles)
                m_axis_iq_tready = 1'b0;
            else
                m_axis_iq_tready = 1'b1;
        end
    end

    task send_word;
        input [31:0] data;
        input [3:0] keep;
        input last;
        integer waited;
        begin
            @(negedge aclk);
            s_axis_pkt_tdata  = data;
            s_axis_pkt_tkeep  = keep;
            s_axis_pkt_tlast  = last;
            s_axis_pkt_tvalid = 1'b1;
            waited = 0;
            @(posedge aclk);
            while (s_axis_pkt_tready !== 1'b1 && waited < WAIT_LIMIT) begin
                waited = waited + 1;
                @(posedge aclk);
            end
            if (s_axis_pkt_tready !== 1'b1)
                fail("Timeout waiting for s_axis_pkt_tready");
        end
    endtask

    task stop_input;
        begin
            @(negedge aclk);
            s_axis_pkt_tvalid = 1'b0;
            s_axis_pkt_tlast  = 1'b0;
            s_axis_pkt_tkeep  = 4'hF;
        end
    endtask

    task transmit_prepared;
        integer j, idle_clocks;
        begin
            if (!watch_active) fail("Transmit without arm_case");
            for (j = 0; j < tx_len; j = j+1) begin
                if (gap_mode != 0 && j != 0) begin
                    idle_clocks = (j * 7 + current_tc) % 4;
                    repeat (idle_clocks) begin
                        @(negedge aclk);
                        s_axis_pkt_tvalid = 1'b0;
                    end
                end
                send_word(tx_word[j], tx_keep[j], tx_last[j]);
            end
            stop_input;
        end
    endtask

    task finish_case;
        integer waits, quiet;
        begin
            waits = 0;
            while ((meta_seen != golden_meta_count || iq_seen != golden_n ||
                    err_seen != golden_err_count) && waits < WAIT_LIMIT) begin
                @(negedge aclk);
                waits = waits + 1;
            end
            if (waits >= WAIT_LIMIT)
                fail("Timeout waiting for expected metadata/IQ/error");
            
            repeat (5) @(negedge aclk);
            if (rx_seen != tx_len || rx_last_seen != 1 ||
                meta_seen != golden_meta_count || iq_seen != golden_n ||
                err_seen != golden_err_count)
                fail("Final scoreboard count mismatch");
            if (stall_meta && golden_meta_count != 0 &&
                meta_stall_hits < meta_stall_cycles)
                fail("Metadata backpressure was not actually exercised");
            if (stall_iq && golden_n != 0 &&
                (iq_stall_hits[0] < iq_stall_cycles ||
                 iq_stall_hits[golden_n-1] < iq_stall_cycles))
                fail("IQ backpressure was not exercised at first/last sample");
            $display("[PASS] TC%0d: in=%0d meta=%0d iq=%0d err=%0d%s",
                     current_tc,rx_seen,meta_seen,iq_seen,err_seen,
                     gap_mode ? " (input gaps)" : "");
            passed = passed + 1;
            watch_active = 1'b0;
            stall_meta = 1'b0;
            stall_iq = 1'b0;
            gap_mode = 0;
        end
    endtask

    task execute_case;
        begin
            transmit_prepared;
            finish_case;
        end
    endtask

    task reset_dut;
        begin
            @(negedge aclk);
            aresetn = 1'b0;
            watch_active = 1'b0;
            s_axis_pkt_tvalid = 1'b0;
            s_axis_pkt_tdata = 32'd0;
            s_axis_pkt_tlast = 1'b0;
            s_axis_pkt_tkeep = 4'hF;
            stall_meta = 1'b0;
            stall_iq = 1'b0;
            repeat (4) @(negedge aclk);
            aresetn = 1'b1;
            repeat (2) @(negedge aclk);
            if (m_meta_valid !== 1'b0 || m_axis_iq_tvalid !== 1'b0 ||
                error_valid !== 1'b0)
                fail("Outputs were not cleared after reset");
        end
    endtask

    task run_good;
        input integer n, tag, reference, meta_bp, iq_bp;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        begin
            make_packet(n,sid,sec,seq,ps,tag,reference);
            arm_case(n,tag,reference,0,4'd0,sid,sec,seq,ps,meta_bp,iq_bp);
            execute_case;
        end
    endtask

    task run_bad;
        input integer n, tag, reference;
        input [3:0] err;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        begin
            arm_case(n,tag,reference,1,err,sid,sec,seq,ps,0,0);
            execute_case;
        end
    endtask

    task run_seq_issue;
        input integer n, tag;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        begin
            make_packet(n,sid,sec,seq,ps,tag,0);
            
            arm_case(n,tag,0,2,`DIFI_ERR_SEQ,sid,sec,seq,ps,0,0);
            execute_case;
        end
    endtask

    integer j, p, bad_at, n, old_err;
    initial begin
        aresetn = 1'b0;
        s_axis_pkt_tdata = 0;
        s_axis_pkt_tvalid = 0;
        s_axis_pkt_tkeep = 4'hF;
        s_axis_pkt_tlast = 0;
        cfg_stream_filter_enable = 1;
        cfg_expected_stream_id = 32'h0000_0001;
        m_meta_ready = 1;
        m_axis_iq_tready = 1;
        current_tc=0; passed=0; skipped=0;
        watch_active=0; stall_meta=0; stall_iq=0;
        meta_stall_cycles=4; iq_stall_cycles=3; gap_mode=0;
        rx_seen=0; rx_last_seen=0; iq_seen=0; meta_seen=0; err_seen=0;
        hold_iq=0; hold_meta=0; hold_rx=0; previous_err=0;
        tx_len=0; golden_n=0; golden_meta_count=0; golden_err_count=0;
        for (j=0;j<MAX_SAMPLES;j=j+1) iq_stall_hits[j]=0;
        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc=1;
        $display("\n=== TC01: independent 4-sample reference vector ===");
        run_good(4, 1, 1, 0, 0, 32'd1, 32'd100, 4'd0, 64'd0);

        current_tc=2;
        $display("\n=== TC02: minimum/maximum payload length and data patterns ===");
        run_good(1,2,0,0,0,32'd1,32'd101,4'd1,64'd1234);
        run_good(256,3,0,0,0,32'd1,32'd102,4'd2,64'd999999999999);
        run_good(2,4,0,0,0,32'd1,32'd103,4'd3,64'd987654321);
        run_good(127,5,0,0,0,32'd1,32'd104,4'd4,64'd0);
        run_good(255,6,0,0,0,32'd1,32'd105,4'd5,64'd1);

        current_tc=3;
        $display("\n=== TC03: continuous input, input bubbles, full AXIS scoreboard ===");
        gap_mode=1;
        run_good(32,7,0,0,0,32'd1,32'd106,4'd6,64'd123456789);
        gap_mode=1;
        run_good(256,8,0,0,0,32'd1,32'd107,4'd7,64'd4321);

        current_tc=4;
        $display("\n=== TC04: metadata and IQ backpressure, including TLAST ===");
        run_good(1,9,0,1,1,32'd1,32'd108,4'd8,64'd0);
        run_good(4,10,0,1,1,32'd1,32'd109,4'd9,64'd12);
        run_good(256,11,0,1,1,32'd1,32'd110,4'd10,64'd987);

        current_tc=5;
        $display("\n=== TC05: initial arbitrary seq, complete wrap, many packets ===");
        reset_dut;
        for (p=0;p<20;p=p+1)
            run_good(4,20+p,0,0,0,32'd1,32'd200+p,(9+p) & 15,64'd0);

        current_tc=6;
        $display("\n=== TC06: skipped sequence, re-base on discontinuity ===");
        reset_dut;
        run_good(4,50,0,0,0,32'd1,32'd300,4'd2,64'd0);
        make_packet(4,32'd1,32'd301,4'd5,64'd0,51,0);
        run_seq_issue(4,51,32'd1,32'd301,4'd5,64'd0);
        run_good(4,52,0,0,0,32'd1,32'd302,4'd6,64'd0);

        current_tc=7;
        $display("\n=== TC07: 7->0 anomaly; duplicate sequence ===");
        reset_dut;
        run_good(4,53,0,0,0,32'd1,32'd303,4'd7,64'd0);
        run_seq_issue(4,54,32'd1,32'd304,4'd0,64'd0);
        run_good(4,55,0,0,0,32'd1,32'd305,4'd1,64'd0);
        reset_dut;
        run_good(4,56,0,0,0,32'd1,32'd306,4'd5,64'd0);
        run_seq_issue(4,57,32'd1,32'd307,4'd5,64'd0);
        run_good(4,58,0,0,0,32'd1,32'd308,4'd6,64'd0);

        current_tc=8;
        $display("\n=== TC08: rejected packets must not change sequence baseline ===");
        reset_dut;
        run_good(4,60,0,0,0,32'd1,32'd400,4'd2,64'd0);
        make_packet(4,32'd1,32'd401,4'd3,64'd0,61,0);
        tx_word[2] = tx_word[2] ^ 32'h0000_0001;
        run_bad(4,61,0,`DIFI_ERR_CLASS,32'd1,32'd401,4'd3,64'd0);
        run_seq_issue(4,62,32'd1,32'd402,4'd4,64'd0);
        run_good(4,63,0,0,0,32'd1,32'd403,4'd5,64'd0);
        make_packet(4,32'd2,32'd404,4'd6,64'd0,64,0);
        run_bad(4,64,0,`DIFI_ERR_STREAM_ID,32'd2,32'd404,4'd6,64'd0);
        run_seq_issue(4,65,32'd1,32'd405,4'd7,64'd0);
        run_good(4,66,0,0,0,32'd1,32'd406,4'd8,64'd0);

        current_tc=9;
        $display("\n=== TC09: unsupported packet types ===");
        for (p=0;p<4;p=p+1) begin
            make_packet(4,32'd1,32'd500,4'd0,64'd0,70+p,0);
            case(p)
                0: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF);
                1: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h4000_0000;
                2: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h5000_0000;
                3: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'hF000_0000;
            endcase
            run_bad(4,70+p,0,`DIFI_ERR_UNSUPPORTED_TYPE,32'd1,32'd500,4'd0,64'd0);
        end

        current_tc=10;
        $display("\n=== TC10: every frozen header field (C/reserved/TSM/TSI/TSF) ===");
        for (p=20;p<=27;p=p+1) begin
            make_packet(4,32'd1,32'd501,4'd0,64'd0,80+p,0);
            tx_word[0] = tx_word[0] ^ (32'h1 << p);
            run_bad(4,80+p,0,`DIFI_ERR_HEADER,32'd1,32'd501,4'd0,64'd0);
        end

        current_tc=11;
        $display("\n=== TC11: invalid advertised Packet Size ===");
        for (p=0;p<4;p=p+1) begin
            make_packet(4,32'd1,32'd502,4'd0,64'd0,110+p,0);
            case(p)
                0: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 32'd0;
                1: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 32'd7;
                2: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 32'd264;
                3: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 32'd65535;
            endcase
            run_bad(4,110+p,0,`DIFI_ERR_SIZE,32'd1,32'd502,4'd0,64'd0);
        end

        current_tc=12;
        $display("\n=== TC12: Word0 TLAST and multi-error priority ===");
        for (p=0;p<5;p=p+1) begin
            make_packet(4,32'd1,32'd503,4'd0,64'd0,120+p,0);
            tx_len=1;
            tx_last[0]=1;
            case(p)
                0: begin end 
                1: tx_word[0] = tx_word[0] ^ 32'h1000_0000; 
                2: tx_word[0] = tx_word[0] ^ 32'h0800_0000; 
                3: tx_word[0] = (tx_word[0] & 32'hFFFF_0000); 
                4: tx_keep[0] = 4'b0111; 
            endcase
            if (p==1)
                run_bad(4,120+p,0,`DIFI_ERR_UNSUPPORTED_TYPE,32'd1,32'd503,4'd0,64'd0);
            else if (p==2)
                run_bad(4,120+p,0,`DIFI_ERR_HEADER,32'd1,32'd503,4'd0,64'd0);
            else
                run_bad(4,120+p,0,`DIFI_ERR_TRUNCATED,32'd1,32'd503,4'd0,64'd0);
        end

        current_tc=13;
        $display("\n=== TC13: SID filter enabled / disabled / actual SID metadata ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0001;
        make_packet(4,32'h0000_1234,32'd504,4'd4,64'd0,130,0);
        run_bad(4,130,0,`DIFI_ERR_STREAM_ID,32'h0000_1234,32'd504,4'd4,64'd0);
        cfg_stream_filter_enable=0;
        run_good(4,131,0,0,0,32'h0000_1234,32'd505,4'd9,64'd456);
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0001;

        current_tc=14;
        $display("\n=== TC14: OUI reserved/OUI bits and ICC/PCC ===");
        for (p=0;p<4;p=p+1) begin
            make_packet(4,32'd1,32'd506,4'd0,64'd0,140+p,0);
            case(p)
                0: tx_word[2] = tx_word[2] ^ 32'h0100_0000;
                1: tx_word[2] = tx_word[2] ^ 32'h0000_0001;
                2: tx_word[3] = tx_word[3] ^ 32'h0001_0000;
                3: tx_word[3] = tx_word[3] ^ 32'h0000_0001;
            endcase
            run_bad(4,140+p,0,`DIFI_ERR_CLASS,32'd1,32'd506,4'd0,64'd0);
        end

        current_tc=15;
        $display("\n=== TC15: early TLAST at Word1/2/3/4/5/6/7/9 ===");
        for (p=1;p<=9;p=p+1) begin
            make_packet(4,32'd1,32'd507,4'd0,64'd0,150+p,0);
            tx_len=p+1;
            tx_last[p]=1;
            run_bad(4,150+p,0,`DIFI_ERR_TRUNCATED,32'd1,32'd507,4'd0,64'd0);
        end

        current_tc=16;
        $display("\n=== TC16: TKEEP invalid at every prologue / payload / TLAST ===");
        for (p=0;p<=10;p=p+1) begin
            make_packet(4,32'd1,32'd508,4'd0,64'd0,170+p,0);
            tx_keep[p]=(p % 2 == 0) ? 4'b0111 : 4'b0000;
            run_bad(4,170+p,0,`DIFI_ERR_SIZE,32'd1,32'd508,4'd0,64'd0);
        end

        current_tc=17;
        $display("\n=== TC17: same-word priority TLAST over TKEEP/SID/CLASS ===");
        for (p=1;p<=3;p=p+1) begin
            make_packet(4,32'd1,32'd509,4'd0,64'd0,190+p,0);
            tx_len=p+1;
            tx_last[p]=1;
            tx_keep[p]=4'b0011;
            if (p==1) tx_word[p]=32'd2; 
            if (p==2) tx_word[p]=32'd0; 
            if (p==3) tx_word[p]=32'd1; 
            run_bad(4,190+p,0,`DIFI_ERR_TRUNCATED,32'd1,32'd509,4'd0,64'd0);
        end
        make_packet(4,32'd2,32'd510,4'd0,64'd0,195,0);
        tx_len=2; tx_last[1]=1;
        run_bad(4,195,0,`DIFI_ERR_TRUNCATED,32'd2,32'd510,4'd0,64'd0);
        make_packet(4,32'd1,32'd511,4'd0,64'd0,196,0);
        tx_word[2]=0; tx_len=3; tx_last[2]=1;
        run_bad(4,196,0,`DIFI_ERR_TRUNCATED,32'd1,32'd511,4'd0,64'd0);

        current_tc=18;
        $display("\n=== TC18: declared final word without TLAST, drain extra beats ===");
        for (p=0;p<2;p=p+1) begin
            make_packet(p?256:1,32'd1,32'd512,4'd0,64'd0,200+p,0);
            tx_last[tx_len-1]=0;
            for (j=0;j<1+2*p;j=j+1) begin
                tx_word[tx_len+j]=32'hCAFE_0000 | j;
                tx_keep[tx_len+j]=4'hF;
                tx_last[tx_len+j]=(j==2*p);
            end
            tx_len=tx_len+1+2*p;
            run_bad(p?256:1,200+p,0,`DIFI_ERR_SIZE,32'd1,32'd512,4'd0,64'd0);
        end

        current_tc=19;
        $display("\n=== TC19: oversized packet with >512 words in DROP ===");
        make_packet(1,32'd1,32'd513,4'd0,64'd0,210,0);
        tx_last[7]=0;
        for (p=8;p<540;p=p+1) begin
            tx_word[p]=32'h8000_0000 | p;
            tx_keep[p]=4'hF;
            tx_last[p]=(p==539);
        end
        tx_len=540;
        run_bad(1,210,0,`DIFI_ERR_SIZE,32'd1,32'd513,4'd0,64'd0);
        run_good(4,211,0,0,0,32'd1,32'd514,4'd10,64'd0);

        current_tc=20;
        $display("\n=== TC20: configuration snapshot at Word0 handshake ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0011;
        make_packet(4,32'h0000_0011,32'd600,4'd7,64'd9876,220,0);
        arm_case(4,220,0,0,4'd0,32'h11,32'd600,4'd7,64'd9876,0,0);
        send_word(tx_word[0],tx_keep[0],tx_last[0]);
        
        @(negedge aclk);
        s_axis_pkt_tvalid=1'b0;
        cfg_stream_filter_enable=0;
        cfg_expected_stream_id=32'h0000_0022;
        for (p=1;p<tx_len;p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        finish_case;
        cfg_stream_filter_enable=1;
        run_good(4,221,0,0,0,32'h22,32'd601,4'd8,64'd5678);
        // Enabling the filter after Word0 does not affect the current packet.
        cfg_stream_filter_enable=0;
        make_packet(4,32'h1234_5678,32'd602,4'd9,64'd0,222,0);
        arm_case(4,222,0,0,4'd0,32'h1234_5678,32'd602,4'd9,64'd0,0,0);
        send_word(tx_word[0],tx_keep[0],tx_last[0]);
        
        @(negedge aclk);
        s_axis_pkt_tvalid=1'b0;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0001;
        for (p=1;p<tx_len;p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        finish_case;

        current_tc=21;
        $display("\n=== TC21: TVALID=0 prevents any consumption or errors ===");
        @(negedge aclk);
        s_axis_pkt_tvalid=0;
        s_axis_pkt_tdata=32'hFFFF_FFFF;
        s_axis_pkt_tlast=1;
        s_axis_pkt_tkeep=0;
        repeat(5) @(negedge aclk);
        if (error_valid !== 0 || m_meta_valid !== 0 || m_axis_iq_tvalid !== 0)
            fail("Invalid input without TVALID caused output");
        s_axis_pkt_tlast=0;
        s_axis_pkt_tkeep=4'hF;
        cfg_expected_stream_id=32'd1;
        run_good(4,230,0,0,0,32'd1,32'd610,4'd10,64'd0);

        current_tc=22;
        $display("\n=== TC22: input READY deasserted during META and OUTPUT ===");
        make_packet(32,32'd1,32'd611,4'd11,64'd0,240,0);
        arm_case(32,240,0,0,4'd0,32'd1,32'd611,4'd11,64'd0,1,1);
        meta_stall_cycles=12;
        iq_stall_cycles=12;
        transmit_prepared;
        
        repeat(4) begin
            @(posedge aclk);
            if(s_axis_pkt_tready !== 0 || m_meta_valid !== 1)
                fail("Input READY high during metadata pending");
        end
        
        p=0;
        while (m_axis_iq_tvalid !== 1 && p<200) begin
            @(negedge aclk);
            p=p+1;
        end
        if(m_axis_iq_tvalid !== 1) fail("Timeout waiting for IQ output");
        repeat(4) begin
            @(posedge aclk);
            if(s_axis_pkt_tready !== 0)
                fail("Input READY high during IQ output");
        end
        finish_case;

        current_tc=23;
        $display("\n=== TC23: reset aborts incomplete RX without stale outputs ===");
        make_packet(4,32'd1,32'd700,4'd4,64'd0,250,0);
        arm_case(4,250,0,0,4'd0,32'd1,32'd700,4'd4,64'd0,0,0);
        for(p=0;p<3;p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        if (m_meta_valid !== 0 || m_axis_iq_tvalid !== 0)
            fail("Partial input produced output before reset");
        reset_dut;
        run_good(4,251,0,0,0,32'd1,32'd701,4'd9,64'd0);

        current_tc=24;
        $display("\n=== TC24: reset aborts pending Metadata cleanly ===");
        make_packet(4,32'd1,32'd702,4'd10,64'd0,260,0);
        arm_case(4,260,0,0,4'd0,32'd1,32'd702,4'd10,64'd0,1,0);
        meta_stall_cycles=1000;
        transmit_prepared;
        @(negedge aclk);
        s_axis_pkt_tvalid=1; s_axis_pkt_tdata=32'h1860_0008;
        s_axis_pkt_tkeep=4'hF; s_axis_pkt_tlast=0;
        repeat(3) begin
            @(negedge aclk);
            if(m_meta_valid !== 1 || m_meta_ready !== 0 ||
               m_axis_iq_tvalid !== 0 || s_axis_pkt_tready !== 0)
                fail("Metadata or held next Word0 wasn't blocked before reset");
        end
        reset_dut; 
        run_good(4,261,0,0,0,32'd1,32'd703,4'd4,64'd0);

        current_tc=25;
        $display("\n=== TC25: reset aborts stalled IQ output cleanly ===");
        make_packet(4,32'd1,32'd704,4'd5,64'd0,270,0);
        arm_case(4,270,0,0,4'd0,32'd1,32'd704,4'd5,64'd0,0,1);
        iq_stall_cycles=1000;
        transmit_prepared;
        p=0;
        while ((m_axis_iq_tvalid !== 1 || m_axis_iq_tready !== 0) && p<100) begin
            @(negedge aclk);
            p=p+1;
        end
        if(p>=100) fail("IQ wasn't stalled before reset");
        @(negedge aclk);
        s_axis_pkt_tvalid=1; s_axis_pkt_tdata=32'h1860_0008;
        s_axis_pkt_tkeep=4'hF; s_axis_pkt_tlast=0;
        repeat(3) begin
            @(negedge aclk);
            if(s_axis_pkt_tready !== 0 || m_axis_iq_tready !== 0)
                fail("Queued next Word0 wasn't blocked during IQ output");
        end
        reset_dut;
        run_good(4,271,0,0,0,32'd1,32'd705,4'd11,64'd0);

        current_tc=26;
        $display("\n=== TC26: 40 deterministic pseudo-random positive cases ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd1;
        for (p=0;p<40;p=p+1) begin
            n = 1 + ((p*73+17) % 256);
            run_good(n,300+p,0,(p%4==0),(p%3==0),
                     32'd1,32'd1000+p,(p&15),
                     (p*64'd271828183) % 64'd1000000000000);
        end

        current_tc=27;
        $display("\n=== TC27: 24 deterministic varied malformed packets ===");
        for (p=0;p<24;p=p+1) begin
            n=1+((p*19+7)%32);
            make_packet(n,32'd1,32'd1200+p,4'd0,64'd0,400+p,0);
            case(p%4)
                0: begin
                    tx_keep[(p*11)%tx_len]=4'b1011;
                    old_err=`DIFI_ERR_SIZE;
                end
                1: begin
                    bad_at=1+((p*7)%(tx_len-2));
                    tx_len=bad_at+1;
                    tx_last[bad_at]=1;
                    old_err=`DIFI_ERR_TRUNCATED;
                end
                2: begin
                    tx_word[3]=32'h0000_0001;
                    old_err=`DIFI_ERR_CLASS;
                end
                3: begin
                    tx_last[tx_len-1]=0;
                    tx_word[tx_len]=32'hDEAD_0000|p;
                    tx_keep[tx_len]=4'hF;
                    tx_last[tx_len]=1;
                    tx_len=tx_len+1;
                    old_err=`DIFI_ERR_SIZE;
                end
            endcase
            run_bad(n,400+p,0,old_err,32'd1,32'd1200+p,4'd0,64'd0);
        end

        current_tc=28;
        $display("\n=== TC28: known spec gaps (opt-in strict tests) ===");
        if (RUN_MULTI_SID_STRICT != 0) begin
            
            reset_dut;
            cfg_stream_filter_enable=0;
            run_good(4,280,0,0,0,32'd1,32'd800,4'd3,64'd0);
            run_good(4,281,0,0,0,32'd2,32'd801,4'd9,64'd0);
            run_good(4,282,0,0,0,32'd1,32'd802,4'd4,64'd0);
        end else begin
            $display("[SKIP] Multi-SID rebaseline: not implemented in current parser");
            skipped=skipped+1;
        end
        if (RUN_TIMESTAMP_STRICT != 0) begin
`ifdef DIFI_ERR_TIMESTAMP
            
            reset_dut;
            cfg_stream_filter_enable=1;
            cfg_expected_stream_id=32'd1;
            make_packet(4,32'd1,32'd803,4'd1,64'd1000000000000,283,0);
            run_bad(4,283,0,`DIFI_ERR_TIMESTAMP,
                    32'd1,32'd803,4'd1,64'd1000000000000);
`else
            fail("RUN_TIMESTAMP_STRICT requires DIFI_ERR_TIMESTAMP in defs header");
`endif
        end else begin
            $display("[SKIP] Invalid time_ps rejection: error-code policy not frozen / RTL not implemented");
            skipped=skipped+1;
        end

        $display("\nALL ENABLED TESTS PASSED: %0d packets/cases, %0d skipped strict features",
                 passed, skipped);
        $finish;
    end

    initial begin
        #3000000;
        fail("Global simulation deadlock timeout");
    end
endmodule
