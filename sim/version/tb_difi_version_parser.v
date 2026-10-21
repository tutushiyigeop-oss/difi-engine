`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

module tb_difi_version_parser;
    localparam integer VERSION_WORDS = 11;
    localparam integer MAX_WORDS     = 128;
    localparam integer WAIT_LIMIT    = 20000;

    reg         aclk, aresetn;
    reg  [31:0] s_axis_pkt_tdata;
    reg         s_axis_pkt_tvalid;
    wire        s_axis_pkt_tready;
    reg  [3:0]  s_axis_pkt_tkeep;
    reg         s_axis_pkt_tlast;
    reg         cfg_stream_filter_enable;
    reg  [31:0] cfg_expected_stream_id;

    wire        m_ver_valid;
    reg         m_ver_ready;
    wire [31:0] m_ver_stream_id;
    wire [3:0]  m_ver_seq;
    wire [31:0] m_ver_time_sec;
    wire [63:0] m_ver_time_ps;
    wire        m_ver_changed;
    wire [31:0] m_ver_info;

    wire        error_valid;
    wire [3:0]  error_code;

    wire pkt_fire  = s_axis_pkt_tvalid && s_axis_pkt_tready;
    wire meta_fire = m_ver_valid && m_ver_ready;

    difi_version_parser dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_pkt_tdata(s_axis_pkt_tdata),
        .s_axis_pkt_tvalid(s_axis_pkt_tvalid),
        .s_axis_pkt_tready(s_axis_pkt_tready),
        .s_axis_pkt_tkeep(s_axis_pkt_tkeep),
        .s_axis_pkt_tlast(s_axis_pkt_tlast),
        .cfg_stream_filter_enable(cfg_stream_filter_enable),
        .cfg_expected_stream_id(cfg_expected_stream_id),
        .m_ver_valid(m_ver_valid),
        .m_ver_ready(m_ver_ready),
        .m_ver_stream_id(m_ver_stream_id),
        .m_ver_seq(m_ver_seq),
        .m_ver_time_sec(m_ver_time_sec),
        .m_ver_time_ps(m_ver_time_ps),
        .m_ver_changed(m_ver_changed),
        .m_ver_info(m_ver_info),
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
    reg [31:0] golden_sid, golden_sec, golden_info;
    reg [3:0]  golden_seq;
    reg [63:0] golden_ps;
    reg        golden_changed;

    integer current_tc, passed;
    reg watch_active;

    integer rx_seen, rx_last_seen, meta_seen, err_seen;
    reg hold_meta, hold_rx;
    reg [31:0] held_rx_data;
    reg [3:0]  held_rx_keep;
    reg        held_rx_last;
    reg [31:0] held_sid, held_sec, held_info;
    reg [3:0]  held_seq;
    reg [63:0] held_ps;
    reg        held_changed;
    reg previous_err;

    reg stall_meta;
    integer meta_stall_cycles;
    integer meta_stall_hits;
    integer gap_mode;

    function [31:0] make_version_info;
        input [6:0] year_offset;
        input [8:0] day_of_year;
        begin
            make_version_info = {
                year_offset,
                day_of_year,
                `DIFI_VERSION_REVISION,
                `DIFI_VERSION_TYPE,
                `DIFI_VERSION_ICD_VERSION
            };
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
        input [6:0]  year_offset;
        input [8:0]  day_of_year;
        integer j;
        begin
            tx_len = VERSION_WORDS;
            tx_word[0]  = `DIFI_VERSION_HEADER_BASE | ({28'd0,seq} << 16);
            tx_word[1]  = sid;
            tx_word[2]  = `DIFI_OUI_WORD;
            tx_word[3]  = `DIFI_VERSION_CLASS_WORD;
            tx_word[4]  = sec;
            tx_word[5]  = ps[63:32];
            tx_word[6]  = ps[31:0];
            tx_word[7]  = changed ? `DIFI_VERSION_CIF_CHANGED
                                  : `DIFI_VERSION_CIF_NO_CHANGE;
            tx_word[8]  = `DIFI_VERSION_CIF1_WORD;
            tx_word[9]  = `DIFI_VERSION_V49_SPEC_WORD;
            tx_word[10] = make_version_info(year_offset,day_of_year);

            for (j=0; j<tx_len; j=j+1) begin
                tx_keep[j] = `DIFI_TKEEP_FULL;
                tx_last[j] = (j == VERSION_WORDS-1);
            end
        end
    endtask

    task check_reference_version_vector;
        integer k;
        reg [31:0] expected;
        begin
            if (tx_len != VERSION_WORDS)
                fail("Reference Version vector length is not 11 words");
            for (k=0; k<VERSION_WORDS; k=k+1) begin
                case (k)
                    0:  expected = 32'h5960_000B;
                    1:  expected = 32'h0000_0002;
                    2:  expected = 32'h006A_621E;
                    3:  expected = 32'h0001_0004;
                    4:  expected = 32'h0000_0064;
                    5:  expected = 32'h0000_0000;
                    6:  expected = 32'h0000_0000;
                    7:  expected = 32'h8000_0002;
                    8:  expected = 32'h0000_000C;
                    9:  expected = 32'h0000_0004;
                    10: expected = 32'h34FC_0400;
                    default: expected = 32'hxxxx_xxxx;
                endcase
                if (tx_word[k] !== expected) begin
                    $display("  Reference Word%0d expected=%h actual=%h", k, expected, tx_word[k]);
                    fail("TB Version reference-vector builder mismatch");
                end
                if (tx_keep[k] !== `DIFI_TKEEP_FULL ||
                    tx_last[k] !== (k == VERSION_WORDS-1))
                    fail("TB Version reference-vector KEEP/TLAST mismatch");
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
        input [31:0] info;
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
            golden_info       = info;

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
            // Keep transmitted data stable while reception is stalled.
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

            // Keep metadata stable while reception is stalled.
            if (hold_meta) begin
                if (m_ver_valid     !== 1'b1 ||
                    m_ver_stream_id !== held_sid ||
                    m_ver_seq       !== held_seq ||
                    m_ver_time_sec  !== held_sec ||
                    m_ver_time_ps   !== held_ps ||
                    m_ver_changed   !== held_changed ||
                    m_ver_info      !== held_info)
                    fail("Version metadata changed while stalled");
            end

            if (m_ver_valid === 1'b1 && !watch_active)
                fail("Unarmed metadata output");
            if (error_valid === 1'b1 && !watch_active)
                fail("Unarmed error event");
            if (error_valid !== 1'b0 && error_valid !== 1'b1)
                fail("error_valid is X/Z");
            if (error_valid === 1'b1 && previous_err)
                fail("error_valid not a one-cycle pulse");
            previous_err = error_valid;

            if (watch_active && m_ver_valid === 1'b1) begin
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

            if (m_ver_valid === 1'b1 && m_ver_ready === 1'b0) begin
                if (stall_meta)
                    meta_stall_hits = meta_stall_hits + 1;
            end

            hold_meta = (m_ver_valid === 1'b1 && m_ver_ready === 1'b0);
            if (hold_meta) begin
                held_sid     = m_ver_stream_id;
                held_seq     = m_ver_seq;
                held_sec     = m_ver_time_sec;
                held_ps      = m_ver_time_ps;
                held_changed = m_ver_changed;
                held_info    = m_ver_info;
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
                if (m_ver_stream_id !== golden_sid ||
                    m_ver_seq       !== golden_seq ||
                    m_ver_time_sec  !== golden_sec ||
                    m_ver_time_ps   !== golden_ps ||
                    m_ver_changed   !== golden_changed ||
                    m_ver_info      !== golden_info) begin
                    $display("  META expected: SID=%h seq=%h sec=%h ps=%h chg=%b info=%h",
                             golden_sid,golden_seq,golden_sec,golden_ps,golden_changed,golden_info);
                    $display("  META actual:   SID=%h seq=%h sec=%h ps=%h chg=%b info=%h",
                             m_ver_stream_id,m_ver_seq,m_ver_time_sec,m_ver_time_ps,m_ver_changed,m_ver_info);
                    fail("Version metadata mismatch");
                end
                meta_seen = meta_seen + 1;
            end
        end
    end

    always @(negedge aclk) begin
        if (!aresetn) begin
            m_ver_ready = 1'b1;
        end else begin
            if (watch_active && stall_meta && m_ver_valid === 1'b1 &&
                meta_stall_hits < meta_stall_cycles)
                m_ver_ready = 1'b0;
            else
                m_ver_ready = 1'b1;
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
            if (m_ver_valid !== 1'b0 || error_valid !== 1'b0)
                fail("Outputs were not cleared after reset");
        end
    endtask

    task run_good;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [6:0]  year_offset;
        input [8:0]  day_of_year;
        input integer meta_bp;
        reg [31:0] info;
        begin
            info = make_version_info(year_offset,day_of_year);
            make_packet(sid,sec,seq,ps,changed,year_offset,day_of_year);
            arm_case(0,4'd0,sid,sec,seq,ps,changed,info,meta_bp);
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
        input [31:0] info;
        begin
            arm_case(1,err,sid,sec,seq,ps,changed,info,0);
            execute_case;
        end
    endtask

    task run_seq_issue;
        input [31:0] sid;
        input [31:0] sec;
        input [3:0]  seq;
        input [63:0] ps;
        input        changed;
        input [6:0]  year_offset;
        input [8:0]  day_of_year;
        reg [31:0] info;
        begin
            info = make_version_info(year_offset,day_of_year);
            make_packet(sid,sec,seq,ps,changed,year_offset,day_of_year);
            arm_case(2,`DIFI_ERR_SEQ,sid,sec,seq,ps,changed,info,0);
            execute_case;
        end
    endtask

    integer j, p, bad_at, old_err;
    reg [31:0] info_tmp;
    reg [31:0] pseudo_sid;
    reg [31:0] pseudo_sec;
    reg [63:0] pseudo_ps;
    reg [6:0]  pseudo_year;
    reg [8:0]  pseudo_day;

    initial begin
        aresetn = 1'b0;
        s_axis_pkt_tdata = 32'd0;
        s_axis_pkt_tvalid = 1'b0;
        s_axis_pkt_tkeep = `DIFI_TKEEP_FULL;
        s_axis_pkt_tlast = 1'b0;
        cfg_stream_filter_enable = 1'b1;
        cfg_expected_stream_id = 32'h0000_0002;
        m_ver_ready = 1'b1;

        current_tc=0; passed=0;
        watch_active=0; stall_meta=0; meta_stall_cycles=4; gap_mode=0;
        rx_seen=0; rx_last_seen=0; meta_seen=0; err_seen=0;
        hold_meta=0; hold_rx=0; previous_err=0;
        tx_len=0; golden_meta_count=0; golden_err_count=0;

        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc=1;
        $display("\n=== TC01: frozen Appendix-C 11-word Version Context reference vector ===");
        make_packet(32'd2,32'd100,4'd0,64'd0,1'b1,7'd26,9'd252);
        check_reference_version_vector;
        arm_case(0,4'd0,32'd2,32'd100,4'd0,64'd0,1'b1,32'h34FC_0400,0);
        execute_case;

        current_tc=2;
        $display("\n=== TC02: changed=0 and legal Version/timestamp boundaries ===");
        reset_dut;
        run_good(32'd2,32'd101,4'd5,64'd0,1'b0,7'd0,9'd1,0);
        run_good(32'd2,32'd102,4'd6,64'd999999999999,1'b1,7'd127,9'd366,0);

        current_tc=3;
        $display("\n=== TC03: deterministic TVALID bubbles inside legal packets ===");
        reset_dut;
        gap_mode=1;
        run_good(32'd2,32'd110,4'd9,64'd987654321,1'b1,7'd26,9'd200,0);
        gap_mode=1;
        run_good(32'd2,32'd111,4'd10,64'd42,1'b0,7'd31,9'd365,0);

        current_tc=4;
        $display("\n=== TC04: Metadata backpressure; every field must stay stable ===");
        reset_dut;
        run_good(32'd2,32'd120,4'd7,64'd777777777,1'b1,7'd26,9'd252,1);
        run_good(32'd2,32'd121,4'd8,64'd0,1'b0,7'd27,9'd1,1);

        current_tc=5;
        $display("\n=== TC05: arbitrary initial Sequence, mod-16 wrap, many packets ===");
        reset_dut;
        for (p=0; p<20; p=p+1)
            run_good(32'd2,32'd200+p,(9+p)&15,
                     (p*64'd1234567)%64'd1000000000000,
                     (p&1),7'd26+(p%3),(p%366)+1,0);

        current_tc=6;
        $display("\n=== TC06: skipped Sequence is nonfatal and re-bases ===");
        reset_dut;
        run_good(32'd2,32'd300,4'd2,64'd0,1'b1,7'd26,9'd252,0);
        run_seq_issue(32'd2,32'd301,4'd5,64'd0,1'b0,7'd26,9'd253);
        run_good(32'd2,32'd302,4'd6,64'd0,1'b0,7'd26,9'd254,0);

        current_tc=7;
        $display("\n=== TC07: duplicate Sequence is nonfatal and re-bases ===");
        reset_dut;
        run_good(32'd2,32'd310,4'd5,64'd0,1'b1,7'd26,9'd252,0);
        run_seq_issue(32'd2,32'd311,4'd5,64'd0,1'b0,7'd26,9'd253);
        run_good(32'd2,32'd312,4'd6,64'd0,1'b0,7'd26,9'd254,0);

        current_tc=8;
        $display("\n=== TC08: rejected packet must not update Sequence baseline ===");
        reset_dut;
        run_good(32'd2,32'd320,4'd2,64'd0,1'b1,7'd26,9'd252,0);
        make_packet(32'd2,32'd321,4'd3,64'd0,1'b0,7'd26,9'd253);
        tx_word[2] = tx_word[2] ^ 32'h0000_0001;
        run_bad(`DIFI_ERR_CLASS,32'd2,32'd321,4'd3,64'd0,1'b0,
                make_version_info(7'd26,9'd253));
        
        run_seq_issue(32'd2,32'd322,4'd4,64'd0,1'b0,7'd26,9'd254);
        run_good(32'd2,32'd323,4'd5,64'd0,1'b0,7'd26,9'd255,0);

        current_tc=9;
        $display("\n=== TC09: Version SID filter and filter-disabled SID re-baseline ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd2;
        make_packet(32'h0000_1234,32'd330,4'd4,64'd0,1'b1,7'd26,9'd252);
        run_bad(`DIFI_ERR_STREAM_ID,32'h0000_1234,32'd330,4'd4,64'd0,1'b1,
                make_version_info(7'd26,9'd252));
        cfg_stream_filter_enable=0;
        run_good(32'h0000_1234,32'd331,4'd9,64'd0,1'b1,7'd26,9'd253,0);
        
        run_good(32'hABCD_0002,32'd332,4'd2,64'd0,1'b0,7'd26,9'd254,0);
        run_good(32'hABCD_0002,32'd333,4'd3,64'd0,1'b0,7'd26,9'd255,0);
        run_good(32'h0000_1234,32'd334,4'd10,64'd0,1'b0,7'd26,9'd256,0);
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd2;

        current_tc=10;
        $display("\n=== TC10: unsupported Packet Types ===");
        reset_dut;
        for (p=0; p<4; p=p+1) begin
            make_packet(32'd2,32'd400,4'd0,64'd0,1'b1,7'd26,9'd252);
            case (p)
                0: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h0000_0000;
                1: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h1000_0000;
                2: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'h4000_0000;
                3: tx_word[0] = (tx_word[0] & 32'h0FFF_FFFF) | 32'hF000_0000;
            endcase
            run_bad(`DIFI_ERR_UNSUPPORTED_TYPE,32'd2,32'd400,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=11;
        $display("\n=== TC11: every frozen header bit C/reserved/TSM/TSI/TSF ===");
        reset_dut;
        for (p=20; p<=27; p=p+1) begin
            make_packet(32'd2,32'd401,4'd0,64'd0,1'b1,7'd26,9'd252);
            tx_word[0] = tx_word[0] ^ (32'h1 << p);
            run_bad(`DIFI_ERR_HEADER,32'd2,32'd401,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=12;
        $display("\n=== TC12: invalid advertised fixed Packet Size ===");
        reset_dut;
        for (p=0; p<4; p=p+1) begin
            make_packet(32'd2,32'd402,4'd0,64'd0,1'b1,7'd26,9'd252);
            case (p)
                0: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'd0;
                1: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'd10;
                2: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'd12;
                3: tx_word[0] = (tx_word[0] & 32'hFFFF_0000) | 16'hFFFF;
            endcase
            run_bad(`DIFI_ERR_SIZE,32'd2,32'd402,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=13;
        $display("\n=== TC13: Word0 TLAST and same-beat error priority ===");
        reset_dut;
        for (p=0; p<5; p=p+1) begin
            make_packet(32'd2,32'd403,4'd0,64'd0,1'b1,7'd26,9'd252);
            tx_len=1;
            tx_last[0]=1'b1;
            case (p)
                0: old_err=`DIFI_ERR_TRUNCATED;
                1: begin tx_word[0]=tx_word[0]^32'h1000_0000; old_err=`DIFI_ERR_UNSUPPORTED_TYPE; end
                2: begin tx_word[0]=tx_word[0]^32'h0800_0000; old_err=`DIFI_ERR_HEADER; end
                3: begin tx_word[0]=(tx_word[0]&32'hFFFF_0000); old_err=`DIFI_ERR_TRUNCATED; end
                4: begin tx_keep[0]=4'b0111; old_err=`DIFI_ERR_TRUNCATED; end
            endcase
            run_bad(old_err,32'd2,32'd403,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=14;
        $display("\n=== TC14: invalid TKEEP at every packet Word ===");
        reset_dut;
        for (bad_at=0; bad_at<VERSION_WORDS; bad_at=bad_at+1) begin
            make_packet(32'd2,32'd410+bad_at,4'd0,64'd0,1'b1,7'd26,9'd252);
            tx_keep[bad_at]=4'b1110;
            run_bad(`DIFI_ERR_SIZE,32'd2,32'd410+bad_at,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=15;
        $display("\n=== TC15: TLAST early at every position Word0..Word9 ===");
        reset_dut;
        for (bad_at=0; bad_at<VERSION_WORDS-1; bad_at=bad_at+1) begin
            make_packet(32'd2,32'd430+bad_at,4'd0,64'd0,1'b1,7'd26,9'd252);
            tx_len=bad_at+1;
            tx_last[bad_at]=1'b1;
            run_bad(`DIFI_ERR_TRUNCATED,32'd2,32'd430+bad_at,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=16;
        $display("\n=== TC16: missing Word10 TLAST, oversized packet, prolonged ST_DROP ===");
        reset_dut;
        make_packet(32'd2,32'd450,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_last[10]=1'b0;
        for (j=11; j<31; j=j+1) begin
            tx_word[j]=32'hDEAD_0000 | j;
            tx_keep[j]=`DIFI_TKEEP_FULL;
            tx_last[j]=1'b0;
        end
        tx_last[30]=1'b1;
        tx_len=31;
        run_bad(`DIFI_ERR_SIZE,32'd2,32'd450,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));

        current_tc=17;
        $display("\n=== TC17: OUI and ICC/PCC Class errors ===");
        reset_dut;
        make_packet(32'd2,32'd460,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[2]=32'h006A_621F;
        run_bad(`DIFI_ERR_CLASS,32'd2,32'd460,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));
        make_packet(32'd2,32'd461,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[3]=32'h0001_0005;
        run_bad(`DIFI_ERR_CLASS,32'd2,32'd461,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));

        current_tc=18;
        $display("\n=== TC18: invalid CIF0 values ===");
        reset_dut;
        for (p=0; p<3; p=p+1) begin
            make_packet(32'd2,32'd470+p,4'd0,64'd0,1'b1,7'd26,9'd252);
            case (p)
                0: tx_word[7]=32'h0000_0000;
                1: tx_word[7]=32'h8000_0000;
                2: tx_word[7]=32'hDEAD_BEEF;
            endcase
            run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd470+p,4'd0,64'd0,1'b1,
                    make_version_info(7'd26,9'd252));
        end

        current_tc=19;
        $display("\n=== TC19: invalid CIF1 and V49 Spec Version ===");
        reset_dut;
        make_packet(32'd2,32'd480,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[8]=32'h0000_000D;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd480,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));
        make_packet(32'd2,32'd481,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[9]=32'h0000_0005;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd481,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));

        current_tc=20;
        $display("\n=== TC20: invalid Word10 Day/Revision/Type/ICD fields ===");
        reset_dut;
        
        make_packet(32'd2,32'd490,4'd0,64'd0,1'b1,7'd26,9'd1);
        tx_word[10][24:16]=9'd0;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd490,4'd0,64'd0,1'b1,tx_word[10]);
        
        make_packet(32'd2,32'd491,4'd0,64'd0,1'b1,7'd26,9'd1);
        tx_word[10][24:16]=9'd367;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd491,4'd0,64'd0,1'b1,tx_word[10]);
        
        make_packet(32'd2,32'd492,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[10][15:10]=6'd2;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd492,4'd0,64'd0,1'b1,tx_word[10]);
        
        make_packet(32'd2,32'd493,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[10][9:6]=4'd1;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd493,4'd0,64'd0,1'b1,tx_word[10]);
        
        make_packet(32'd2,32'd494,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[10][5:0]=6'd1;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd494,4'd0,64'd0,1'b1,tx_word[10]);

        current_tc=21;
        $display("\n=== TC21: invalid fractional timestamp (>= 10^12 ps) ===");
        reset_dut;
        make_packet(32'd2,32'd500,4'd0,64'd1000000000000,1'b1,7'd26,9'd252);
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd500,4'd0,64'd1000000000000,1'b1,
                make_version_info(7'd26,9'd252));
        make_packet(32'd2,32'd501,4'd0,64'hFFFF_FFFF_FFFF_FFFF,1'b0,7'd26,9'd252);
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd501,4'd0,64'hFFFF_FFFF_FFFF_FFFF,1'b0,
                make_version_info(7'd26,9'd252));

        current_tc=22;
        $display("\n=== TC22: cfg filter/expected Version SID snapshot exactly at Word0 ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0011;
        make_packet(32'h0000_0011,32'd510,4'd7,64'd9876,1'b1,7'd26,9'd252);
        arm_case(0,4'd0,32'h11,32'd510,4'd7,64'd9876,1'b1,
                 make_version_info(7'd26,9'd252),0);
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
        cfg_expected_stream_id=32'h0000_0002;
        make_packet(32'h1234_5678,32'd511,4'd9,64'd0,1'b0,7'd26,9'd253);
        arm_case(0,4'd0,32'h1234_5678,32'd511,4'd9,64'd0,1'b0,
                 make_version_info(7'd26,9'd253),0);
        send_word(tx_word[0],tx_keep[0],tx_last[0]);
        @(negedge aclk);
        s_axis_pkt_tvalid=1'b0;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'h0000_0002;
        for (p=1; p<tx_len; p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        finish_case;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd2;

        current_tc=23;
        $display("\n=== TC23: TVALID=0 means no consumption and no error ===");
        reset_dut;
        @(negedge aclk);
        s_axis_pkt_tvalid=0;
        s_axis_pkt_tdata=32'hFFFF_FFFF;
        s_axis_pkt_tlast=1;
        s_axis_pkt_tkeep=0;
        repeat(5) @(negedge aclk);
        if (error_valid !== 0 || m_ver_valid !== 0)
            fail("Invalid input without TVALID caused output");
        s_axis_pkt_tlast=0;
        s_axis_pkt_tkeep=`DIFI_TKEEP_FULL;
        run_good(32'd2,32'd520,4'd3,64'd0,1'b1,7'd26,9'd252,0);

        current_tc=24;
        $display("\n=== TC24: revised first-detected fatal error policy ===");
        reset_dut;
        // An earlier SID error takes priority over a later class error.
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd2;
        make_packet(32'h0000_1234,32'd530,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[2]=32'h0000_0000;
        run_bad(`DIFI_ERR_STREAM_ID,32'h0000_1234,32'd530,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));
        // An earlier Version-field error takes priority over a later missing TLAST.
        make_packet(32'd2,32'd531,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[7]=32'hDEAD_BEEF;
        tx_last[10]=1'b0;
        tx_word[11]=32'hDEAD_000B;
        tx_keep[11]=`DIFI_TKEEP_FULL;
        tx_last[11]=1'b1;
        tx_len=12;
        run_bad(`DIFI_ERR_VERSION_FIELD,32'd2,32'd531,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));
        
        make_packet(32'd2,32'd532,4'd0,64'd0,1'b1,7'd26,9'd252);
        tx_word[2]=32'h0000_0000;
        tx_keep[2]=4'b0111;
        run_bad(`DIFI_ERR_SIZE,32'd2,32'd532,4'd0,64'd0,1'b1,
                make_version_info(7'd26,9'd252));

        current_tc=25;
        $display("\n=== TC25: input READY stays low while Metadata is pending ===");
        reset_dut;
        make_packet(32'd2,32'd540,4'd4,64'd123,1'b1,7'd26,9'd252);
        arm_case(0,4'd0,32'd2,32'd540,4'd4,64'd123,1'b1,
                 make_version_info(7'd26,9'd252),1);
        meta_stall_cycles=12;
        transmit_prepared;
        repeat(4) begin
            @(posedge aclk);
            if (s_axis_pkt_tready !== 0 || m_ver_valid !== 1 || m_ver_ready !== 0)
                fail("Input READY high or metadata not held while Metadata pending");
        end
        finish_case;

        current_tc=26;
        $display("\n=== TC26: reset aborts incomplete RX without stale metadata/error ===");
        reset_dut;
        make_packet(32'd2,32'd550,4'd6,64'd0,1'b1,7'd26,9'd252);
        arm_case(0,4'd0,32'd2,32'd550,4'd6,64'd0,1'b1,
                 make_version_info(7'd26,9'd252),0);
        for (p=0; p<6; p=p+1)
            send_word(tx_word[p],tx_keep[p],tx_last[p]);
        stop_input;
        if (m_ver_valid !== 0)
            fail("Partial packet produced metadata before reset");
        reset_dut;
        run_good(32'd2,32'd551,4'd11,64'd0,1'b0,7'd26,9'd253,0);

        current_tc=27;
        $display("\n=== TC27: reset aborts stalled Metadata and held next Word0 ===");
        reset_dut;
        make_packet(32'd2,32'd560,4'd10,64'd0,1'b1,7'd26,9'd252);
        arm_case(0,4'd0,32'd2,32'd560,4'd10,64'd0,1'b1,
                 make_version_info(7'd26,9'd252),1);
        meta_stall_cycles=1000;
        transmit_prepared;
        @(negedge aclk);
        s_axis_pkt_tvalid=1;
        s_axis_pkt_tdata=`DIFI_VERSION_HEADER_BASE;
        s_axis_pkt_tkeep=`DIFI_TKEEP_FULL;
        s_axis_pkt_tlast=0;
        repeat(3) begin
            @(negedge aclk);
            if (m_ver_valid !== 1 || m_ver_ready !== 0 || s_axis_pkt_tready !== 0)
                fail("Pending Metadata or next Word0 was not held before reset");
        end
        reset_dut;
        run_good(32'd2,32'd561,4'd1,64'd0,1'b0,7'd26,9'd253,0);

        current_tc=28;
        $display("\n=== TC28: 40 deterministic varied legal Version packets ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd2;
        for (p=0; p<40; p=p+1) begin
            pseudo_sid  = 32'd2;
            pseudo_sec  = 32'd1000+p;
            pseudo_ps   = (p*64'd271828183) % 64'd1000000000000;
            pseudo_year = (p*13+7) & 7'h7F;
            pseudo_day  = ((p*37+11)%366)+1;
            run_good(pseudo_sid,pseudo_sec,p&15,pseudo_ps,(p&1),
                     pseudo_year,pseudo_day,(p%5==0));
        end

        current_tc=29;
        $display("\n=== TC29: 40 deterministic malformed Version packets ===");
        reset_dut;
        cfg_stream_filter_enable=1;
        cfg_expected_stream_id=32'd2;
        for (p=0; p<40; p=p+1) begin
            make_packet(32'd2,32'd1200+p,4'd0,64'd0,1'b1,7'd26,9'd252);
            old_err=0;
            case (p%10)
                0: begin
                    tx_keep[(p*7)%VERSION_WORDS]=4'b1011;
                    old_err=`DIFI_ERR_SIZE;
                end
                1: begin
                    bad_at=(p*5)%(VERSION_WORDS-1);
                    tx_len=bad_at+1;
                    tx_last[bad_at]=1'b1;
                    old_err=`DIFI_ERR_TRUNCATED;
                end
                2: begin
                    tx_word[2]=32'h0000_0000;
                    old_err=`DIFI_ERR_CLASS;
                end
                3: begin
                    tx_word[7]=32'hDEAD_BEEF;
                    old_err=`DIFI_ERR_VERSION_FIELD;
                end
                4: begin
                    tx_word[8]=32'h0000_0000;
                    old_err=`DIFI_ERR_VERSION_FIELD;
                end
                5: begin
                    tx_word[9]=32'h0000_0000;
                    old_err=`DIFI_ERR_VERSION_FIELD;
                end
                6: begin
                    tx_word[10][24:16]=9'd0;
                    old_err=`DIFI_ERR_VERSION_FIELD;
                end
                7: begin
                    tx_word[0]=tx_word[0]^32'h0100_0000;
                    old_err=`DIFI_ERR_HEADER;
                end
                8: begin
                    tx_last[10]=1'b0;
                    tx_word[11]=32'hDEAD_0000|p;
                    tx_keep[11]=`DIFI_TKEEP_FULL;
                    tx_last[11]=1'b1;
                    tx_len=12;
                    old_err=`DIFI_ERR_SIZE;
                end
                9: begin
                    tx_word[3]=32'h0000_0000;
                    old_err=`DIFI_ERR_CLASS;
                end
            endcase
            run_bad(old_err,32'd2,32'd1200+p,4'd0,64'd0,1'b1,tx_word[10]);
        end

        $display("\n============================================================");
        $display("ALL VERSION PARSER TESTS PASSED: %0d cases", passed);
        $display("============================================================\n");
        $finish;
    end

endmodule
