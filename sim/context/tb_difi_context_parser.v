`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

module tb_difi_context_parser;
    localparam integer CONTEXT_WORDS = 27;
    localparam integer MAX_WORDS     = 400; 
    localparam integer WAIT_LIMIT    = 20000;

    reg         aclk, aresetn;
    reg  [31:0] s_axis_pkt_tdata;
    reg         s_axis_pkt_tvalid;
    wire        s_axis_pkt_tready;
    reg  [3:0]  s_axis_pkt_tkeep;
    reg         s_axis_pkt_tlast;
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

    wire pkt_fire  = s_axis_pkt_tvalid && s_axis_pkt_tready;
    wire meta_fire = m_ctx_valid && m_ctx_ready;

    difi_context_parser dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_pkt_tdata(s_axis_pkt_tdata),
        .s_axis_pkt_tvalid(s_axis_pkt_tvalid),
        .s_axis_pkt_tready(s_axis_pkt_tready),
        .s_axis_pkt_tkeep(s_axis_pkt_tkeep),
        .s_axis_pkt_tlast(s_axis_pkt_tlast),
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

    reg [31:0] tx_word [0:MAX_WORDS-1];
    reg [3:0]  tx_keep [0:MAX_WORDS-1];
    reg        tx_last [0:MAX_WORDS-1];
    integer tx_len;

    integer golden_err_count, golden_meta_count;
    reg [3:0]  golden_err_code;
    reg [31:0] golden_sid, golden_sec;
    reg [3:0]  golden_seq;
    reg [63:0] golden_ps;
    reg        golden_changed;
    reg [31:0] golden_bw_hz;
    reg [63:0] golden_rf_hz;
    reg [31:0] golden_fs_hz;

    integer current_tc, passed;
    reg watch_active;

    integer rx_seen, rx_last_seen, meta_seen, err_seen;
    reg hold_meta, hold_rx;
    reg [31:0] held_rx_data;
    reg [3:0]  held_rx_keep;
    reg        held_rx_last;
    reg [31:0] held_sid, held_sec;
    reg [3:0]  held_seq;
    reg [63:0] held_ps;
    reg        held_changed;
    reg [31:0] held_bw_hz;
    reg [63:0] held_rf_hz;
    reg [31:0] held_fs_hz;
    reg previous_err;

    reg stall_meta;
    integer meta_stall_cycles;
    integer meta_stall_hits;
    integer gap_mode;

    function [63:0] hz_to_raw;
        input [63:0] hz;
        begin
            hz_to_raw = hz << `DIFI_FREQ_FRAC_BITS;
        end
    endfunction

    task fail;
        input [8*220-1:0] message;
        begin
            $display("[FAIL] TC%0d @%0t: %0s", current_tc, $time, message);
            $display("  rx=%0d/%0d(last=%0d), meta=%0d/%0d, err=%0d/%0d, err_code=%h",
                     rx_seen, tx_len, rx_last_seen, meta_seen, golden_meta_count,
                     err_seen, golden_err_count, error_code);
            $finish;
        end
    endtask

    task make_packet;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [31:0] bw_hz;
        input [63:0] rf_hz;
        input [31:0] fs_hz;
        reg [63:0] raw;
        integer j;
        begin
            tx_len = CONTEXT_WORDS;
            tx_word[0]  = `DIFI_CONTEXT_HEADER_BASE | ({28'd0,seq} << 16);
            tx_word[1]  = sid;
            tx_word[2]  = `DIFI_OUI_WORD;
            tx_word[3]  = `DIFI_CONTEXT_CLASS_WORD;
            tx_word[4]  = sec;
            tx_word[5]  = ps[63:32];
            tx_word[6]  = ps[31:0];
            tx_word[7]  = changed ? `DIFI_CONTEXT_CIF_CHANGED
                                  : `DIFI_CONTEXT_CIF_NO_CHANGE;
            tx_word[8]  = `DIFI_CONTEXT_REF_POINT;

            raw = hz_to_raw({32'd0,bw_hz});
            tx_word[9]  = raw[63:32];
            tx_word[10] = raw[31:0];

            tx_word[11] = `DIFI_ZERO_WORD;
            tx_word[12] = `DIFI_ZERO_WORD;

            raw = hz_to_raw(rf_hz);
            tx_word[13] = raw[63:32];
            tx_word[14] = raw[31:0];

            tx_word[15] = `DIFI_ZERO_WORD;
            tx_word[16] = `DIFI_ZERO_WORD;
            tx_word[17] = `DIFI_ZERO_WORD;
            tx_word[18] = `DIFI_ZERO_WORD;

            raw = hz_to_raw({32'd0,fs_hz});
            tx_word[19] = raw[63:32];
            tx_word[20] = raw[31:0];

            tx_word[21] = `DIFI_ZERO_WORD;
            tx_word[22] = `DIFI_ZERO_WORD;
            tx_word[23] = `DIFI_ZERO_WORD;
            tx_word[24] = `DIFI_ZERO_WORD;
            tx_word[25] = `DIFI_CONTEXT_DPF_WORD0;
            tx_word[26] = `DIFI_CONTEXT_DPF_WORD1;

            for (j=0; j<tx_len; j=j+1) begin
                tx_keep[j] = `DIFI_TKEEP_FULL;
                tx_last[j] = (j == CONTEXT_WORDS-1);
            end
        end
    endtask

    task check_reference_context_vector;
        integer k;
        reg [31:0] expected;
        begin
            if (tx_len != CONTEXT_WORDS)
                fail("Reference Context vector length is not 27 words");
            for (k=0; k<CONTEXT_WORDS; k=k+1) begin
                case (k)
                    0:  expected = 32'h4960_001B;
                    1:  expected = 32'h0000_0001;
                    2:  expected = 32'h006A_621E;
                    3:  expected = 32'h0000_0001;
                    4:  expected = 32'h0000_0064;
                    5:  expected = 32'h0000_0000;
                    6:  expected = 32'h0000_0000;
                    7:  expected = 32'hFBB9_8000;
                    8:  expected = 32'h0000_0064;
                    9:  expected = 32'h0000_0989;
                    10: expected = 32'h6800_0000;
                    11: expected = 32'h0000_0000;
                    12: expected = 32'h0000_0000;
                    13: expected = 32'h0000_5F5E;
                    14: expected = 32'h1000_0000;
                    15: expected = 32'h0000_0000;
                    16: expected = 32'h0000_0000;
                    17: expected = 32'h0000_0000;
                    18: expected = 32'h0000_0000;
                    19: expected = 32'h0000_1312;
                    20: expected = 32'hD000_0000;
                    21: expected = 32'h0000_0000;
                    22: expected = 32'h0000_0000;
                    23: expected = 32'h0000_0000;
                    24: expected = 32'h0000_0000;
                    25: expected = 32'hA000_03CF;
                    26: expected = 32'h0000_0000;
                    default: expected = 32'hxxxx_xxxx;
                endcase
                if (tx_word[k] !== expected) begin
                    $display("  Reference Word%0d expected=%h actual=%h", k, expected, tx_word[k]);
                    fail("TB Context reference-vector builder mismatch");
                end
                if (tx_keep[k] !== `DIFI_TKEEP_FULL ||
                    tx_last[k] !== (k == CONTEXT_WORDS-1))
                    fail("TB Context reference-vector KEEP/TLAST mismatch");
            end
        end
    endtask

    task arm_case;
        input integer error_expected;
        input [3:0] error_expected_code;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [31:0] bw_hz;
        input [63:0] rf_hz;
        input [31:0] fs_hz;
        input integer with_meta_stall;
        begin
            @(negedge aclk);
            if (watch_active)
                fail("Previous case still armed");
            if (s_axis_pkt_tvalid !== 1'b0)
                fail("Input still valid before arming");

            golden_meta_count = (error_expected == 1) ? 0 : 1;
            golden_err_count  = (error_expected != 0) ? 1 : 0;
            golden_err_code   = error_expected_code;
            golden_sid        = sid;
            golden_sec        = sec;
            golden_seq        = seq;
            golden_ps         = ps;
            golden_changed    = changed;
            golden_bw_hz      = bw_hz;
            golden_rf_hz      = rf_hz;
            golden_fs_hz      = fs_hz;

            rx_seen = 0;
            rx_last_seen = 0;
            meta_seen = 0;
            err_seen = 0;
            meta_stall_hits = 0;
            stall_meta = (with_meta_stall != 0);
            meta_stall_cycles = 4;
            watch_active = 1'b1;
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            hold_meta = 1'b0;
            hold_rx = 1'b0;
            previous_err = 1'b0;
        end else begin
            
            if (hold_rx) begin
                if (s_axis_pkt_tvalid !== 1'b1 ||
                    s_axis_pkt_tdata  !== held_rx_data ||
                    s_axis_pkt_tkeep  !== held_rx_keep ||
                    s_axis_pkt_tlast  !== held_rx_last)
                    fail("Input AXIS source changed its beat while stalled");
            end
            hold_rx = (s_axis_pkt_tvalid === 1'b1 &&
                       s_axis_pkt_tready === 1'b0);
            if (hold_rx) begin
                held_rx_data = s_axis_pkt_tdata;
                held_rx_keep = s_axis_pkt_tkeep;
                held_rx_last = s_axis_pkt_tlast;
            end

            if (hold_meta) begin
                if (m_ctx_valid !== 1'b1 ||
                    m_ctx_stream_id      !== held_sid ||
                    m_ctx_seq            !== held_seq ||
                    m_ctx_time_sec       !== held_sec ||
                    m_ctx_time_ps        !== held_ps ||
                    m_ctx_changed        !== held_changed ||
                    m_ctx_bandwidth_hz   !== held_bw_hz ||
                    m_ctx_rf_freq_hz     !== held_rf_hz ||
                    m_ctx_sample_rate_hz !== held_fs_hz)
                    fail("Context metadata changed while stalled");
            end

            if (m_ctx_valid === 1'b1 && !watch_active)
                fail("Unarmed metadata output");
            if (error_valid === 1'b1 && !watch_active)
                fail("Unarmed error event");
            if (error_valid !== 1'b0 && error_valid !== 1'b1)
                fail("error_valid is X/Z");
            if (error_valid === 1'b1 && previous_err)
                fail("error_valid not a one-cycle pulse");
            previous_err = error_valid;

            if (watch_active && m_ctx_valid === 1'b1) begin
                if (meta_seen >= golden_meta_count)
                    fail("Metadata VALID asserted when no metadata is due");
                if (rx_last_seen !== 1)
                    fail("Metadata became valid before complete input packet");
            end

            if (pkt_fire) begin
                if (!watch_active)
                    fail("Unexpected input transfer");
                rx_seen = rx_seen + 1;
                if (s_axis_pkt_tlast === 1'b1)
                    rx_last_seen = rx_last_seen + 1;
            end

            if (m_ctx_valid === 1'b1 && m_ctx_ready === 1'b0) begin
                if (stall_meta)
                    meta_stall_hits = meta_stall_hits + 1;
            end

            hold_meta = (m_ctx_valid === 1'b1 && m_ctx_ready === 1'b0);
            if (hold_meta) begin
                held_sid     = m_ctx_stream_id;
                held_seq     = m_ctx_seq;
                held_sec     = m_ctx_time_sec;
                held_ps      = m_ctx_time_ps;
                held_changed = m_ctx_changed;
                held_bw_hz   = m_ctx_bandwidth_hz;
                held_rf_hz   = m_ctx_rf_freq_hz;
                held_fs_hz   = m_ctx_sample_rate_hz;
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
                if (m_ctx_stream_id      !== golden_sid ||
                    m_ctx_seq            !== golden_seq ||
                    m_ctx_time_sec       !== golden_sec ||
                    m_ctx_time_ps        !== golden_ps ||
                    m_ctx_changed        !== golden_changed ||
                    m_ctx_bandwidth_hz   !== golden_bw_hz ||
                    m_ctx_rf_freq_hz     !== golden_rf_hz ||
                    m_ctx_sample_rate_hz !== golden_fs_hz) begin
                    $display("  META expected: SID=%h seq=%h sec=%h ps=%h chg=%b BW=%0d RF=%0d Fs=%0d",
                             golden_sid,golden_seq,golden_sec,golden_ps,golden_changed,
                             golden_bw_hz,golden_rf_hz,golden_fs_hz);
                    $display("  META actual:   SID=%h seq=%h sec=%h ps=%h chg=%b BW=%0d RF=%0d Fs=%0d",
                             m_ctx_stream_id,m_ctx_seq,m_ctx_time_sec,m_ctx_time_ps,m_ctx_changed,
                             m_ctx_bandwidth_hz,m_ctx_rf_freq_hz,m_ctx_sample_rate_hz);
                    fail("Context metadata mismatch");
                end
                meta_seen = meta_seen + 1;
            end
        end
    end

    always @(negedge aclk) begin
        if (!aresetn) begin
            m_ctx_ready = 1'b1;
        end else begin
            if (watch_active && stall_meta && m_ctx_valid === 1'b1 &&
                meta_stall_hits < meta_stall_cycles)
                m_ctx_ready = 1'b0;
            else
                m_ctx_ready = 1'b1;
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
            s_axis_pkt_tkeep  = `DIFI_TKEEP_FULL;
        end
    endtask

    task transmit_prepared;
        integer j, idle_clocks;
        begin
            if (!watch_active)
                fail("Transmit without arm_case");
            for (j=0; j<tx_len; j=j+1) begin
                if (gap_mode != 0 && j != 0) begin
                    idle_clocks = (j*7 + current_tc) % 4;
                    repeat (idle_clocks) begin
                        @(negedge aclk);
                        s_axis_pkt_tvalid = 1'b0;
                    end
                end
                send_word(tx_word[j],tx_keep[j],tx_last[j]);
            end
            stop_input;
        end
    endtask

    task finish_case;
        integer waits;
        begin
            waits = 0;
            while ((meta_seen != golden_meta_count ||
                    err_seen  != golden_err_count) && waits < WAIT_LIMIT) begin
                @(negedge aclk);
                waits = waits + 1;
            end
            if (waits >= WAIT_LIMIT)
                fail("Timeout waiting for expected metadata/error");

            repeat (5) @(negedge aclk);
            if (rx_seen != tx_len || rx_last_seen != 1 ||
                meta_seen != golden_meta_count ||
                err_seen != golden_err_count)
                fail("Final scoreboard count mismatch");
            if (stall_meta && golden_meta_count != 0 &&
                meta_stall_hits < meta_stall_cycles)
                fail("Metadata backpressure was not actually exercised");

            $display("[PASS] TC%0d: in=%0d meta=%0d err=%0d%s",
                     current_tc,rx_seen,meta_seen,err_seen,
                     gap_mode ? " (input gaps)" : "");
            passed = passed + 1;
            watch_active = 1'b0;
            stall_meta = 1'b0;
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
            s_axis_pkt_tkeep = `DIFI_TKEEP_FULL;
            stall_meta = 1'b0;
            repeat (4) @(negedge aclk);
            aresetn = 1'b1;
            repeat (2) @(negedge aclk);
            if (m_ctx_valid !== 1'b0 || error_valid !== 1'b0)
                fail("Outputs were not cleared after reset");
        end
    endtask

    task run_good;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [31:0] bw_hz;
        input [63:0] rf_hz;
        input [31:0] fs_hz;
        input integer meta_bp;
        begin
            make_packet(sid,sec,seq,ps,changed,bw_hz,rf_hz,fs_hz);
            arm_case(0,4'd0,sid,sec,seq,ps,changed,bw_hz,rf_hz,fs_hz,meta_bp);
            execute_case;
        end
    endtask

    task run_bad;
        input [3:0] err;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [31:0] bw_hz;
        input [63:0] rf_hz;
        input [31:0] fs_hz;
        begin
            arm_case(1,err,sid,sec,seq,ps,changed,bw_hz,rf_hz,fs_hz,0);
            execute_case;
        end
    endtask

    task run_seq_issue;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [31:0] bw_hz;
        input [63:0] rf_hz;
        input [31:0] fs_hz;
        begin
            make_packet(sid,sec,seq,ps,changed,bw_hz,rf_hz,fs_hz);
            arm_case(2,`DIFI_ERR_SEQ,sid,sec,seq,ps,changed,bw_hz,rf_hz,fs_hz,0);
            execute_case;
        end
    endtask

    integer j, p, bad_at, old_err;
    integer fs_i, bw_i;
    reg [63:0] raw64;
    reg [63:0] rf_rand;

    initial begin
        aresetn = 1'b0;
        s_axis_pkt_tdata = 32'd0;
        s_axis_pkt_tvalid = 1'b0;
        s_axis_pkt_tkeep = `DIFI_TKEEP_FULL;
        s_axis_pkt_tlast = 1'b0;
        cfg_stream_filter_enable = 1'b1;
        cfg_expected_stream_id = 32'h0000_0001;
        m_ctx_ready = 1'b1;

        current_tc=0; passed=0;
        watch_active=0; stall_meta=0; meta_stall_cycles=4; gap_mode=0;
        rx_seen=0; rx_last_seen=0; meta_seen=0; err_seen=0;
        hold_meta=0; hold_rx=0; previous_err=0;
        tx_len=0; golden_meta_count=0; golden_err_count=0;

        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc=1;
        $display("\n=== TC01: frozen Appendix-C 27-word Signal Context reference vector ===");
        make_packet(32'd1,32'd100,4'd0,64'd0,1'b1,
                    32'd10000000,64'd100000000,32'd20000000);
        check_reference_context_vector;
        arm_case(0,4'd0,32'd1,32'd100,4'd0,64'd0,1'b1,
                 32'd10000000,64'd100000000,32'd20000000,0);
        execute_case;

        current_tc=2;
        $display("\n=== TC02: changed=0 and legal dynamic-field boundaries ===");
        reset_dut;
        run_good(32'd1,32'd101,4'd5,64'd0,1'b0,
                 32'd1,64'd0,32'd1,0);
        run_good(32'd1,32'd102,4'd6,64'd999999999999,1'b1,
                 32'hFFFF_FFFF,64'd100000000000,32'hFFFF_FFFF,0);

        current_tc=3;
        $display("\n=== TC03: continuous input and deterministic TVALID bubbles ===");
        reset_dut;
        gap_mode=1;
        run_good(32'd1,32'd110,4'd9,64'd987654321,1'b1,
                 32'd10000000,64'd915000000,32'd20000000,0);
        gap_mode=1;
        run_good(32'd1,32'd111,4'd10,64'd42,1'b0,
                 32'd12000000,64'd2400000000,32'd25000000,0);

        current_tc=4;
        $display("\n=== TC04: Metadata backpressure; every field must stay stable ===");
        reset_dut;
        run_good(32'd1,32'd120,4'd7,64'd777777777,1'b1,
                 32'd25000000,64'd3500000000,32'd50000000,1);
        run_good(32'd1,32'd121,4'd8,64'd0,1'b0,
                 32'd30000000,64'd3600000000,32'd60000000,1);

        current_tc=5;
        $display("\n=== TC05: arbitrary initial Sequence, mod-16 wrap, many packets ===");
        reset_dut;
        for (p=0; p<20; p=p+1)
            run_good(32'd1,32'd200+p,(9+p)&15,64'd0,(p&1),
                     32'd1000000+p,64'd1000000000+p,32'd2000000+p,0);

        current_tc=6;
        $display("\n=== TC06: skipped Sequence is nonfatal and re-bases ===");
        reset_dut;
        run_good(32'd1,32'd300,4'd2,64'd0,1'b1,
                 32'd10000000,64'd100000000,32'd20000000,0);
        run_seq_issue(32'd1,32'd301,4'd5,64'd0,1'b0,
                      32'd10000000,64'd100000000,32'd20000000);
        run_good(32'd1,32'd302,4'd6,64'd0,1'b0,
                 32'd10000000,64'd100000000,32'd20000000,0);

        current_tc=7;
        $display("\n=== TC07: duplicate Sequence is nonfatal and re-bases ===");
        reset_dut;
        run_good(32'd1,32'd310,4'd5,64'd0,1'b1,
                 32'd8000000,64'd500000000,32'd16000000,0);
        run_seq_issue(32'd1,32'd311,4'd5,64'd0,1'b0,
                      32'd8000000,64'd500000000,32'd16000000);
        run_good(32'd1,32'd312,4'd6,64'd0,1'b0,
                 32'd8000000,64'd500000000,32'd16000000,0);

        current_tc=8;
        $display("\n=== TC08: rejected packets must not update Sequence baseline ===");
        reset_dut;
        run_good(32'd1,32'd320,4'd2,64'd0,1'b1,
                 32'd10000000,64'd1000000000,32'd20000000,0);
        make_packet(32'd1,32'd321,4'd3,64'd0,1'b0,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[2] = tx_word[2] ^ 32'h0000_0001;
        run_bad(`DIFI_ERR_CLASS,32'd1,32'd321,4'd3,64'd0,1'b0,
                32'd10000000,64'd1000000000,32'd20000000);
        
        run_seq_issue(32'd1,32'd322,4'd4,64'd0,1'b0,
                      32'd10000000,64'd1000000000,32'd20000000);
        run_good(32'd1,32'd323,4'd5,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);

        current_tc=9;
        $display("\n=== TC09: SID filter and first-version single-stream SID re-baseline ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd1;
        make_packet(32'h0000_1234,32'd330,4'd4,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        run_bad(`DIFI_ERR_STREAM_ID,32'h0000_1234,32'd330,4'd4,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        cfg_stream_filter_enable=0;
        run_good(32'h0000_1234,32'd331,4'd9,64'd0,1'b1,
                 32'd10000000,64'd1000000000,32'd20000000,0);
        
        run_good(32'hABCD_0002,32'd332,4'd2,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);
        run_good(32'hABCD_0002,32'd333,4'd3,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);
        
        run_good(32'h0000_1234,32'd334,4'd10,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd1;

        current_tc=10;
        $display("\n=== TC10: unsupported Packet Types ===");
        reset_dut;
        for (p=0; p<4; p=p+1) begin
            make_packet(32'd1,32'd400,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            case (p)
                0: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h0000_0000;
                1: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h1000_0000;
                2: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h5000_0000;
                3: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'hF000_0000;
            endcase
            run_bad(`DIFI_ERR_UNSUPPORTED_TYPE,32'd1,32'd400,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=11;
        $display("\n=== TC11: every frozen header bit C/reserved/TSM/TSI/TSF ===");
        reset_dut;
        for (p=20; p<=27; p=p+1) begin
            make_packet(32'd1,32'd401,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            tx_word[0] = tx_word[0] ^ (32'h1 << p);
            run_bad(`DIFI_ERR_HEADER,32'd1,32'd401,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=12;
        $display("\n=== TC12: invalid advertised fixed Packet Size ===");
        reset_dut;
        for (p=0; p<4; p=p+1) begin
            make_packet(32'd1,32'd402,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            case (p)
                0: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'd0;
                1: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'd26;
                2: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'd28;
                3: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'hFFFF;
            endcase
            run_bad(`DIFI_ERR_SIZE,32'd1,32'd402,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=13;
        $display("\n=== TC13: Word0 TLAST and Word0 multi-error priority ===");
        reset_dut;
        for (p=0; p<5; p=p+1) begin
            make_packet(32'd1,32'd403,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            tx_len=1;
            tx_last[0]=1'b1;
            case (p)
                0: begin end
                1: tx_word[0] = tx_word[0] ^ 32'h1000_0000; 
                2: tx_word[0] = tx_word[0] ^ 32'h0800_0000; 
                3: tx_word[0] = (tx_word[0] & 32'hFFFF_0000); 
                4: tx_keep[0] = 4'b0111; 
            endcase
            if (p==1)
                run_bad(`DIFI_ERR_UNSUPPORTED_TYPE,32'd1,32'd403,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            else if (p==2)
                run_bad(`DIFI_ERR_HEADER,32'd1,32'd403,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            else
                run_bad(`DIFI_ERR_TRUNCATED,32'd1,32'd403,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=14;
        $display("\n=== TC14: OUI padding/OUI bits and ICC/PCC ===");
        reset_dut;
        for (p=0; p<4; p=p+1) begin
            make_packet(32'd1,32'd404,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            case (p)
                0: tx_word[2] = tx_word[2] ^ 32'h0100_0000;
                1: tx_word[2] = tx_word[2] ^ 32'h0000_0001;
                2: tx_word[3] = tx_word[3] ^ 32'h0001_0000;
                3: tx_word[3] = tx_word[3] ^ 32'h0000_0001;
            endcase
            run_bad(`DIFI_ERR_CLASS,32'd1,32'd404,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=15;
        $display("\n=== TC15: early TLAST at every Word1..Word25 ===");
        reset_dut;
        for (p=1; p<=25; p=p+1) begin
            make_packet(32'd1,32'd405,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            tx_len=p+1;
            tx_last[p]=1'b1;
            run_bad(`DIFI_ERR_TRUNCATED,32'd1,32'd405,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=16;
        $display("\n=== TC16: invalid TKEEP at every Word0..Word26 ===");
        reset_dut;
        for (p=0; p<CONTEXT_WORDS; p=p+1) begin
            make_packet(32'd1,32'd406,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            tx_keep[p]=(p&1) ? 4'b0000 : 4'b0111;
            run_bad(`DIFI_ERR_SIZE,32'd1,32'd406,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=17;
        $display("\n=== TC17: same-beat error priority ===");
        reset_dut;
        // Early TLAST takes priority over SID/TKEEP errors.
        make_packet(32'd1,32'd407,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[1]=32'd2; tx_keep[1]=4'b0011; tx_last[1]=1; tx_len=2;
        run_bad(`DIFI_ERR_TRUNCATED,32'd1,32'd407,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        // Early TLAST takes priority over class/TKEEP errors.
        make_packet(32'd1,32'd408,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[2]=32'd0; tx_keep[2]=4'b0011; tx_last[2]=1; tx_len=3;
        run_bad(`DIFI_ERR_TRUNCATED,32'd1,32'd408,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        // Early TLAST takes priority over Context-field/TKEEP errors.
        make_packet(32'd1,32'd409,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[7]=32'd0; tx_keep[7]=4'b0011; tx_last[7]=1; tx_len=8;
        run_bad(`DIFI_ERR_TRUNCATED,32'd1,32'd409,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        // Without early TLAST, TKEEP/length errors take priority over Context-field errors.
        make_packet(32'd1,32'd410,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[7]=32'd0; tx_keep[7]=4'b0011;
        run_bad(`DIFI_ERR_SIZE,32'd1,32'd410,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        
        make_packet(32'd1,32'd411,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[26]=32'hDEAD_BEEF;
        tx_last[26]=0;
        tx_word[27]=32'h1234_5678; tx_keep[27]=4'hF; tx_last[27]=1;
        tx_len=28;
        run_bad(`DIFI_ERR_SIZE,32'd1,32'd411,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);

        current_tc=18;
        $display("\n=== TC18: missing TLAST at Word26, drain extra beats and recover ===");
        reset_dut;
        make_packet(32'd1,32'd420,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_last[26]=0;
        for (j=27; j<34; j=j+1) begin
            tx_word[j]=32'hCAFE_0000 | j;
            tx_keep[j]=4'hF;
            tx_last[j]=(j==33);
        end
        tx_len=34;
        run_bad(`DIFI_ERR_SIZE,32'd1,32'd420,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        run_good(32'd1,32'd421,4'd5,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);

        current_tc=19;
        $display("\n=== TC19: prolonged ST_DROP across word_count wrap, then recovery ===");
        reset_dut;
        make_packet(32'd1,32'd430,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_last[26]=0;
        for (j=27; j<220; j=j+1) begin
            tx_word[j]=32'h8000_0000 | j;
            tx_keep[j]=4'hF;
            tx_last[j]=(j==219);
        end
        tx_len=220;
        run_bad(`DIFI_ERR_SIZE,32'd1,32'd430,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        run_good(32'd1,32'd431,4'd9,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);

        current_tc=20;
        $display("\n=== TC20: every CIF/fixed Context field is checked ===");
        reset_dut;
        for (p=0; p<14; p=p+1) begin
            make_packet(32'd1,32'd440,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            case (p)
                0:  tx_word[7]  = 32'h1234_5678; 
                1:  tx_word[8]  = tx_word[8] ^ 32'h1; 
                2:  tx_word[11] = 32'h1;
                3:  tx_word[12] = 32'h1;
                4:  tx_word[15] = 32'h1;
                5:  tx_word[16] = 32'h1;
                6:  tx_word[17] = 32'h1;
                7:  tx_word[18] = 32'h1;
                8:  tx_word[21] = 32'h1;
                9:  tx_word[22] = 32'h1;
                10: tx_word[23] = 32'h1;
                11: tx_word[24] = 32'h1;
                12: tx_word[25] = tx_word[25] ^ 32'h1;
                13: tx_word[26] = tx_word[26] ^ 32'h1;
            endcase
            run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd440,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        current_tc=21;
        $display("\n=== TC21: invalid fractional timestamp boundaries ===");
        reset_dut;
        make_packet(32'd1,32'd450,4'd0,64'd1000000000000,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd450,4'd0,64'd1000000000000,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        make_packet(32'd1,32'd451,4'd0,64'hFFFF_FFFF_FFFF_FFFF,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd451,4'd0,64'hFFFF_FFFF_FFFF_FFFF,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);

        current_tc=22;
        $display("\n=== TC22: invalid Bandwidth raw value/range/relationship ===");
        reset_dut;
        
        make_packet(32'd1,32'd460,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[10]=tx_word[10] | 32'h1;
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd460,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        
        make_packet(32'd1,32'd461,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[9]=0; tx_word[10]=0;
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd461,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        
        make_packet(32'd1,32'd462,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        raw64=64'h0010_0000_0000_0000;
        tx_word[9]=raw64[63:32]; tx_word[10]=raw64[31:0];
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd462,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        
        make_packet(32'd1,32'd463,4'd0,64'd0,1'b1,
                    32'd20000000,64'd1000000000,32'd10000000);
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd463,4'd0,64'd0,1'b1,
                32'd20000000,64'd1000000000,32'd10000000);

        current_tc=23;
        $display("\n=== TC23: invalid Sample Rate raw value/range ===");
        reset_dut;
        make_packet(32'd1,32'd470,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[20]=tx_word[20] | 32'h1;
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd470,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        make_packet(32'd1,32'd471,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[19]=0; tx_word[20]=0;
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd471,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        make_packet(32'd1,32'd472,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        raw64=64'h0010_0000_0000_0000;
        tx_word[19]=raw64[63:32]; tx_word[20]=raw64[31:0];
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd472,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);

        current_tc=24;
        $display("\n=== TC24: invalid RF raw value/sign/range ===");
        reset_dut;
        make_packet(32'd1,32'd480,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        tx_word[14]=tx_word[14] | 32'h1;
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd480,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        make_packet(32'd1,32'd481,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        raw64=64'h8000_0000_0000_0000;
        tx_word[13]=raw64[63:32]; tx_word[14]=raw64[31:0];
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd481,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);
        make_packet(32'd1,32'd482,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        raw64=hz_to_raw(64'd100000000001);
        tx_word[13]=raw64[63:32]; tx_word[14]=raw64[31:0];
        run_bad(`DIFI_ERR_CONTEXT_FIELD,32'd1,32'd482,4'd0,64'd0,1'b1,
                32'd10000000,64'd1000000000,32'd20000000);

        current_tc=25;
        $display("\n=== TC25: cfg filter/expected SID snapshot exactly at Word0 handshake ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0011;
        make_packet(32'h0000_0011,32'd500,4'd7,64'd9876,1'b1,
                    32'd10000000,64'd1800000000,32'd20000000);
        arm_case(0,4'd0,32'h11,32'd500,4'd7,64'd9876,1'b1,
                 32'd10000000,64'd1800000000,32'd20000000,0);
        send_word(tx_word[0],tx_keep[0],tx_last[0]);
        
        @(negedge aclk);
        s_axis_pkt_tvalid=1'b0;
        cfg_stream_filter_enable=0;
        cfg_expected_stream_id=32'h0000_0022;
        for (p=1; p<tx_len; p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        finish_case;

        reset_dut;
        cfg_stream_filter_enable=0;
        cfg_expected_stream_id=32'h0000_0001;
        make_packet(32'h1234_5678,32'd501,4'd9,64'd0,1'b0,
                    32'd12000000,64'd2200000000,32'd24000000);
        arm_case(0,4'd0,32'h1234_5678,32'd501,4'd9,64'd0,1'b0,
                 32'd12000000,64'd2200000000,32'd24000000,0);
        send_word(tx_word[0],tx_keep[0],tx_last[0]);
        @(negedge aclk);
        s_axis_pkt_tvalid=1'b0;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0001;
        for (p=1; p<tx_len; p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        finish_case;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd1;

        current_tc=26;
        $display("\n=== TC26: TVALID=0 means no consumption and no error ===");
        reset_dut;
        @(negedge aclk);
        s_axis_pkt_tvalid=0;
        s_axis_pkt_tdata=32'hFFFF_FFFF;
        s_axis_pkt_tlast=1;
        s_axis_pkt_tkeep=0;
        repeat(5) @(negedge aclk);
        if (error_valid !== 0 || m_ctx_valid !== 0)
            fail("Invalid input without TVALID caused output");
        s_axis_pkt_tlast=0;
        s_axis_pkt_tkeep=`DIFI_TKEEP_FULL;
        run_good(32'd1,32'd510,4'd3,64'd0,1'b1,
                 32'd10000000,64'd1000000000,32'd20000000,0);

        current_tc=27;
        $display("\n=== TC27: input READY must stay low while Metadata is pending ===");
        reset_dut;
        make_packet(32'd1,32'd520,4'd4,64'd123,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        arm_case(0,4'd0,32'd1,32'd520,4'd4,64'd123,1'b1,
                 32'd10000000,64'd1000000000,32'd20000000,1);
        meta_stall_cycles=12;
        transmit_prepared;
        repeat(4) begin
            @(posedge aclk);
            if (s_axis_pkt_tready !== 0 || m_ctx_valid !== 1 || m_ctx_ready !== 0)
                fail("Input READY high or metadata not held while Metadata pending");
        end
        finish_case;

        current_tc=28;
        $display("\n=== TC28: reset aborts incomplete RX without stale metadata/error ===");
        reset_dut;
        make_packet(32'd1,32'd530,4'd6,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        arm_case(0,4'd0,32'd1,32'd530,4'd6,64'd0,1'b1,
                 32'd10000000,64'd1000000000,32'd20000000,0);
        for (p=0; p<9; p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        if (m_ctx_valid !== 0)
            fail("Partial packet produced metadata before reset");
        reset_dut;
        run_good(32'd1,32'd531,4'd11,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);

        current_tc=29;
        $display("\n=== TC29: reset aborts stalled Metadata and a held next Word0 ===");
        reset_dut;
        make_packet(32'd1,32'd540,4'd10,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        arm_case(0,4'd0,32'd1,32'd540,4'd10,64'd0,1'b1,
                 32'd10000000,64'd1000000000,32'd20000000,1);
        meta_stall_cycles=1000;
        transmit_prepared;
        @(negedge aclk);
        
        s_axis_pkt_tvalid=1;
        s_axis_pkt_tdata=`DIFI_CONTEXT_HEADER_BASE;
        s_axis_pkt_tkeep=`DIFI_TKEEP_FULL;
        s_axis_pkt_tlast=0;
        repeat(3) begin
            @(negedge aclk);
            if (m_ctx_valid !== 1 || m_ctx_ready !== 0 || s_axis_pkt_tready !== 0)
                fail("Pending Metadata or next Word0 was not held before reset");
        end
        reset_dut; 
        run_good(32'd1,32'd541,4'd1,64'd0,1'b0,
                 32'd10000000,64'd1000000000,32'd20000000,0);

        current_tc=30;
        $display("\n=== TC30: 40 deterministic pseudo-random legal Context packets ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd1;
        for (p=0; p<40; p=p+1) begin
            fs_i = 1000000 + ((p*104729 + 12345) % 100000000);
            bw_i = 1 + ((p*65537 + 77) % fs_i);
            rf_rand = 64'd100000000 + ((p*64'd32452843) % 64'd99900000000);
            run_good(32'd1,32'd1000+p,p&15,
                     (p*64'd271828183) % 64'd1000000000000,
                     (p&1),bw_i,rf_rand,fs_i,(p%4==0));
        end

        current_tc=31;
        $display("\n=== TC31: 32 deterministic varied malformed packets ===");
        reset_dut;
        for (p=0; p<32; p=p+1) begin
            make_packet(32'd1,32'd1200+p,4'd0,64'd0,1'b1,
                        32'd10000000,64'd1000000000,32'd20000000);
            case (p%8)
                0: begin
                    tx_keep[(p*11)%CONTEXT_WORDS]=4'b1011;
                    old_err=`DIFI_ERR_SIZE;
                end
                1: begin
                    bad_at=1+((p*7)%25);
                    tx_len=bad_at+1;
                    tx_last[bad_at]=1;
                    old_err=`DIFI_ERR_TRUNCATED;
                end
                2: begin
                    tx_word[3]=32'h0000_0000;
                    old_err=`DIFI_ERR_CLASS;
                end
                3: begin
                    tx_word[7]=32'hDEAD_BEEF;
                    old_err=`DIFI_ERR_CONTEXT_FIELD;
                end
                4: begin
                    tx_word[10]=tx_word[10] | 32'h1;
                    old_err=`DIFI_ERR_CONTEXT_FIELD;
                end
                5: begin
                    tx_word[20]=0;
                    tx_word[19]=0;
                    old_err=`DIFI_ERR_CONTEXT_FIELD;
                end
                6: begin
                    tx_last[26]=0;
                    tx_word[27]=32'hDEAD_0000|p;
                    tx_keep[27]=4'hF;
                    tx_last[27]=1;
                    tx_len=28;
                    old_err=`DIFI_ERR_SIZE;
                end
                7: begin
                    tx_word[0]=tx_word[0] ^ 32'h0100_0000;
                    old_err=`DIFI_ERR_HEADER;
                end
            endcase
            run_bad(old_err,32'd1,32'd1200+p,4'd0,64'd0,1'b1,
                    32'd10000000,64'd1000000000,32'd20000000);
        end

        $display("\nALL CONTEXT PARSER TESTS PASSED: %0d packet/case executions", passed);
        $finish;
    end

    initial begin
        #5000000;
        fail("Global simulation deadlock timeout");
    end
endmodule
