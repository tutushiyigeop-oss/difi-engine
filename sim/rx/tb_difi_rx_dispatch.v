`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

module tb_difi_rx_dispatch;
    localparam integer MAX_WORDS  = 256;
    localparam integer WAIT_LIMIT = 20000;

    localparam [1:0] ROUTE_DATA    = 2'd0;
    localparam [1:0] ROUTE_CONTEXT = 2'd1;
    localparam [1:0] ROUTE_VERSION = 2'd2;
    localparam [1:0] ROUTE_DROP    = 2'd3;

    reg         aclk, aresetn;

    reg  [31:0] s_axis_pkt_tdata;
    reg         s_axis_pkt_tvalid;
    wire        s_axis_pkt_tready;
    reg  [3:0]  s_axis_pkt_tkeep;
    reg         s_axis_pkt_tlast;

    wire [31:0] m_data_tdata;
    wire        m_data_tvalid;
    reg         m_data_tready;
    wire [3:0]  m_data_tkeep;
    wire        m_data_tlast;

    wire [31:0] m_context_tdata;
    wire        m_context_tvalid;
    reg         m_context_tready;
    wire [3:0]  m_context_tkeep;
    wire        m_context_tlast;

    wire [31:0] m_version_tdata;
    wire        m_version_tvalid;
    reg         m_version_tready;
    wire [3:0]  m_version_tkeep;
    wire        m_version_tlast;

    wire        error_valid;
    wire [3:0]  error_code;

    wire pkt_fire     = s_axis_pkt_tvalid && s_axis_pkt_tready;
    wire data_fire    = m_data_tvalid    && m_data_tready;
    wire context_fire = m_context_tvalid && m_context_tready;
    wire version_fire = m_version_tvalid && m_version_tready;

    difi_rx_dispatch dut (
        .aclk(aclk),
        .aresetn(aresetn),

        .s_axis_pkt_tdata(s_axis_pkt_tdata),
        .s_axis_pkt_tvalid(s_axis_pkt_tvalid),
        .s_axis_pkt_tready(s_axis_pkt_tready),
        .s_axis_pkt_tkeep(s_axis_pkt_tkeep),
        .s_axis_pkt_tlast(s_axis_pkt_tlast),

        .m_data_tdata(m_data_tdata),
        .m_data_tvalid(m_data_tvalid),
        .m_data_tready(m_data_tready),
        .m_data_tkeep(m_data_tkeep),
        .m_data_tlast(m_data_tlast),

        .m_context_tdata(m_context_tdata),
        .m_context_tvalid(m_context_tvalid),
        .m_context_tready(m_context_tready),
        .m_context_tkeep(m_context_tkeep),
        .m_context_tlast(m_context_tlast),

        .m_version_tdata(m_version_tdata),
        .m_version_tvalid(m_version_tvalid),
        .m_version_tready(m_version_tready),
        .m_version_tkeep(m_version_tkeep),
        .m_version_tlast(m_version_tlast),

        .error_valid(error_valid),
        .error_code(error_code)
    );

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    reg [31:0] tx_word  [0:MAX_WORDS-1];
    reg [3:0]  tx_keep  [0:MAX_WORDS-1];
    reg        tx_last  [0:MAX_WORDS-1];
    reg [1:0]  tx_route [0:MAX_WORDS-1];
    integer tx_len;

    integer golden_packet_count;
    integer golden_data_count;
    integer golden_context_count;
    integer golden_version_count;
    integer golden_drop_count;
    integer golden_err_count;

    integer current_tc, passed;
    reg watch_active;

    integer rx_seen, rx_last_seen;
    integer data_seen, context_seen, version_seen, drop_seen;
    integer drop_last_seen, err_seen;

    reg        hold_rx;
    reg [31:0] held_rx_data;
    reg [3:0]  held_rx_keep;
    reg        held_rx_last;

    reg        hold_data, hold_context, hold_version;
    reg [31:0] held_data_data, held_context_data, held_version_data;
    reg [3:0]  held_data_keep, held_context_keep, held_version_keep;
    reg        held_data_last, held_context_last, held_version_last;

    reg previous_err;

    integer stall_at0, stall_cycles0;
    integer stall_at1, stall_cycles1;
    integer stall_at2, stall_cycles2;
    integer gap_mode;

    task fail;
        input [8*220-1:0] message;
        begin
            $display("[FAIL] TC%0d @%0t: %0s", current_tc, $time, message);
            $display("  in=%0d/%0d(last=%0d/%0d), data=%0d/%0d, ctx=%0d/%0d, ver=%0d/%0d, drop=%0d/%0d, err=%0d/%0d code=%h",
                     rx_seen,tx_len,rx_last_seen,golden_packet_count,
                     data_seen,golden_data_count,
                     context_seen,golden_context_count,
                     version_seen,golden_version_count,
                     drop_seen,golden_drop_count,
                     err_seen,golden_err_count,error_code);
            $finish;
        end
    endtask

    task clear_stream;
        begin
            tx_len = 0;
            golden_packet_count  = 0;
            golden_data_count    = 0;
            golden_context_count = 0;
            golden_version_count = 0;
            golden_drop_count    = 0;
            golden_err_count     = 0;
        end
    endtask

    task append_packet;
        input [1:0] route;
        input integer words;
        input [7:0] tag;
        integer base, j;
        begin
            if (words < 1)
                fail("append_packet called with words < 1");
            if ((tx_len + words) > MAX_WORDS)
                fail("Prepared stream exceeds MAX_WORDS");

            base = tx_len;

            for (j=0; j<words; j=j+1) begin
                tx_word[base+j]  = {tag, 16'hA500, j[7:0]};
                tx_keep[base+j]  = `DIFI_TKEEP_FULL;
                tx_last[base+j]  = (j == words-1);
                tx_route[base+j] = route;
            end

            case (route)
                ROUTE_DATA: begin
                    
                    tx_word[base] = 32'h1860_0000 | words[15:0];
                    golden_data_count = golden_data_count + words;
                end

                ROUTE_CONTEXT: begin
                    tx_word[base] = 32'h4960_0000 | words[15:0];
                    golden_context_count = golden_context_count + words;
                end

                ROUTE_VERSION: begin
                    tx_word[base] = 32'h5960_0000 | words[15:0];
                    golden_version_count = golden_version_count + words;
                end

                ROUTE_DROP: begin
                    tx_word[base] = 32'hF660_0000 | words[15:0];
                    golden_drop_count = golden_drop_count + words;
                    golden_err_count  = golden_err_count + 1;
                end

                default: fail("Unknown route in append_packet");
            endcase

            tx_len = tx_len + words;
            golden_packet_count = golden_packet_count + 1;
        end
    endtask

    task append_unsupported_packet;
        input [3:0] packet_type;
        input integer words;
        input [7:0] tag;
        integer base;
        begin
            if (packet_type == 4'h1 || packet_type == 4'h4 || packet_type == 4'h5)
                fail("append_unsupported_packet got a supported type");

            base = tx_len;
            append_packet(ROUTE_DROP,words,tag);
            tx_word[base][31:28] = packet_type;
        end
    endtask

    task arm_case;
        begin
            @(negedge aclk);
            if (watch_active)
                fail("Previous case still armed");
            if (s_axis_pkt_tvalid !== 1'b0)
                fail("Input still valid before arming");

            rx_seen = 0;
            rx_last_seen = 0;
            data_seen = 0;
            context_seen = 0;
            version_seen = 0;
            drop_seen = 0;
            drop_last_seen = 0;
            err_seen = 0;

            stall_at0 = -1; stall_cycles0 = 0;
            stall_at1 = -1; stall_cycles1 = 0;
            stall_at2 = -1; stall_cycles2 = 0;
            gap_mode = 0;
            watch_active = 1'b1;
        end
    endtask

    always @(posedge aclk) begin
        if (!aresetn) begin
            hold_rx = 1'b0;
            hold_data = 1'b0;
            hold_context = 1'b0;
            hold_version = 1'b0;
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

            if (hold_data) begin
                if (m_data_tvalid !== 1'b1 ||
                    m_data_tdata  !== held_data_data ||
                    m_data_tkeep  !== held_data_keep ||
                    m_data_tlast  !== held_data_last)
                    fail("Data output changed while stalled");
            end
            if (hold_context) begin
                if (m_context_tvalid !== 1'b1 ||
                    m_context_tdata  !== held_context_data ||
                    m_context_tkeep  !== held_context_keep ||
                    m_context_tlast  !== held_context_last)
                    fail("Context output changed while stalled");
            end
            if (hold_version) begin
                if (m_version_tvalid !== 1'b1 ||
                    m_version_tdata  !== held_version_data ||
                    m_version_tkeep  !== held_version_keep ||
                    m_version_tlast  !== held_version_last)
                    fail("Version output changed while stalled");
            end

            hold_data = (m_data_tvalid === 1'b1 && m_data_tready === 1'b0);
            hold_context = (m_context_tvalid === 1'b1 && m_context_tready === 1'b0);
            hold_version = (m_version_tvalid === 1'b1 && m_version_tready === 1'b0);
            if (hold_data) begin
                held_data_data = m_data_tdata;
                held_data_keep = m_data_tkeep;
                held_data_last = m_data_tlast;
            end
            if (hold_context) begin
                held_context_data = m_context_tdata;
                held_context_keep = m_context_tkeep;
                held_context_last = m_context_tlast;
            end
            if (hold_version) begin
                held_version_data = m_version_tdata;
                held_version_keep = m_version_tkeep;
                held_version_last = m_version_tlast;
            end

            if ((m_data_tvalid && m_context_tvalid) ||
                (m_data_tvalid && m_version_tvalid) ||
                (m_context_tvalid && m_version_tvalid))
                fail("More than one Parser TVALID asserted simultaneously");

            if ((m_data_tvalid || m_context_tvalid || m_version_tvalid) && !watch_active)
                fail("Unarmed Parser output");
            if (error_valid === 1'b1 && !watch_active)
                fail("Unarmed Dispatch error event");
            if (error_valid !== 1'b0 && error_valid !== 1'b1)
                fail("error_valid is X/Z");
            if (error_valid === 1'b1 && previous_err)
                fail("error_valid not a one-cycle pulse");
            previous_err = error_valid;

            if (m_data_tvalid === 1'b1) begin
                if (!watch_active || rx_seen >= tx_len)
                    fail("Data TVALID outside prepared stream");
                if (tx_route[rx_seen] !== ROUTE_DATA)
                    fail("Beat routed to Data Parser but golden route is different");
                if (m_data_tdata !== s_axis_pkt_tdata ||
                    m_data_tkeep !== s_axis_pkt_tkeep ||
                    m_data_tlast !== s_axis_pkt_tlast)
                    fail("Data route did not preserve TDATA/TKEEP/TLAST");
                if (s_axis_pkt_tready !== m_data_tready)
                    fail("Data TREADY was not propagated upstream");
            end

            if (m_context_tvalid === 1'b1) begin
                if (!watch_active || rx_seen >= tx_len)
                    fail("Context TVALID outside prepared stream");
                if (tx_route[rx_seen] !== ROUTE_CONTEXT)
                    fail("Beat routed to Context Parser but golden route is different");
                if (m_context_tdata !== s_axis_pkt_tdata ||
                    m_context_tkeep !== s_axis_pkt_tkeep ||
                    m_context_tlast !== s_axis_pkt_tlast)
                    fail("Context route did not preserve TDATA/TKEEP/TLAST");
                if (s_axis_pkt_tready !== m_context_tready)
                    fail("Context TREADY was not propagated upstream");
            end

            if (m_version_tvalid === 1'b1) begin
                if (!watch_active || rx_seen >= tx_len)
                    fail("Version TVALID outside prepared stream");
                if (tx_route[rx_seen] !== ROUTE_VERSION)
                    fail("Beat routed to Version Parser but golden route is different");
                if (m_version_tdata !== s_axis_pkt_tdata ||
                    m_version_tkeep !== s_axis_pkt_tkeep ||
                    m_version_tlast !== s_axis_pkt_tlast)
                    fail("Version route did not preserve TDATA/TKEEP/TLAST");
                if (s_axis_pkt_tready !== m_version_tready)
                    fail("Version TREADY was not propagated upstream");
            end

            if (pkt_fire) begin
                if (!watch_active || rx_seen >= tx_len)
                    fail("Unexpected input transfer");

                if (s_axis_pkt_tdata !== tx_word[rx_seen] ||
                    s_axis_pkt_tkeep !== tx_keep[rx_seen] ||
                    s_axis_pkt_tlast !== tx_last[rx_seen])
                    fail("Input transfer differs from prepared stream");

                case (tx_route[rx_seen])
                    ROUTE_DATA: begin
                        if (!data_fire || context_fire || version_fire)
                            fail("Data input handshake did not coincide with exactly one Data handshake");
                    end

                    ROUTE_CONTEXT: begin
                        if (data_fire || !context_fire || version_fire)
                            fail("Context input handshake did not coincide with exactly one Context handshake");
                    end

                    ROUTE_VERSION: begin
                        if (data_fire || context_fire || !version_fire)
                            fail("Version input handshake did not coincide with exactly one Version handshake");
                    end

                    ROUTE_DROP: begin
                        if (data_fire || context_fire || version_fire)
                            fail("Unsupported packet leaked into a Parser");
                        drop_seen = drop_seen + 1;
                        if (s_axis_pkt_tlast === 1'b1)
                            drop_last_seen = drop_last_seen + 1;
                    end

                    default: fail("Unknown golden route at input handshake");
                endcase

                rx_seen = rx_seen + 1;
                if (s_axis_pkt_tlast === 1'b1)
                    rx_last_seen = rx_last_seen + 1;
            end

            if (data_fire)
                data_seen = data_seen + 1;
            if (context_fire)
                context_seen = context_seen + 1;
            if (version_fire)
                version_seen = version_seen + 1;

            if (error_valid === 1'b1) begin
                if (err_seen >= golden_err_count)
                    fail("Unexpected/duplicate Dispatch error event");
                if (error_code !== `DIFI_ERR_UNSUPPORTED_TYPE)
                    fail("Incorrect Dispatch error code");
                if (drop_last_seen <= err_seen)
                    fail("Unsupported-Type error reported before packet TLAST was drained");
                err_seen = err_seen + 1;
            end
        end
    end

    task set_route_ready;
        input [1:0] route;
        input value;
        begin
            case (route)
                ROUTE_DATA:    m_data_tready    = value;
                ROUTE_CONTEXT: m_context_tready = value;
                ROUTE_VERSION: m_version_tready = value;
                ROUTE_DROP: begin end
                default: fail("Unknown route in set_route_ready");
            endcase
        end
    endtask

    task send_word;
        input [31:0] data;
        input [3:0] keep;
        input last;
        input [1:0] route;
        input integer stall_cycles;
        integer waited;
        begin
            @(negedge aclk);

            if (route != ROUTE_DROP && stall_cycles > 0)
                set_route_ready(route,1'b0);

            s_axis_pkt_tdata  = data;
            s_axis_pkt_tkeep  = keep;
            s_axis_pkt_tlast  = last;
            s_axis_pkt_tvalid = 1'b1;

            if (route != ROUTE_DROP && stall_cycles > 0) begin
                repeat (stall_cycles) @(negedge aclk);
                set_route_ready(route,1'b1);
            end

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
        integer j, idle_clocks, local_stall;
        begin
            if (!watch_active)
                fail("Transmit without arm_case");

            for (j=0; j<tx_len; j=j+1) begin
                if (gap_mode != 0 && j != 0) begin
                    idle_clocks = (j*5 + current_tc) % 4;
                    repeat (idle_clocks) begin
                        @(negedge aclk);
                        s_axis_pkt_tvalid = 1'b0;
                    end
                end

                local_stall = 0;
                if (j == stall_at0)
                    local_stall = stall_cycles0;
                else if (j == stall_at1)
                    local_stall = stall_cycles1;
                else if (j == stall_at2)
                    local_stall = stall_cycles2;

                send_word(tx_word[j],tx_keep[j],tx_last[j],tx_route[j],local_stall);
            end
            stop_input;
        end
    endtask

    task finish_case;
        integer waits;
        begin
            waits = 0;
            while ((rx_seen != tx_len || err_seen != golden_err_count) &&
                   waits < WAIT_LIMIT) begin
                @(negedge aclk);
                waits = waits + 1;
            end
            if (waits >= WAIT_LIMIT)
                fail("Timeout waiting for expected transfers/error events");

            repeat (5) @(negedge aclk);

            if (rx_seen != tx_len ||
                rx_last_seen != golden_packet_count ||
                data_seen != golden_data_count ||
                context_seen != golden_context_count ||
                version_seen != golden_version_count ||
                drop_seen != golden_drop_count ||
                err_seen != golden_err_count)
                fail("Final scoreboard count mismatch");

            $display("[PASS] TC%0d: in=%0d packets=%0d data=%0d ctx=%0d ver=%0d drop=%0d err=%0d%s",
                     current_tc,rx_seen,golden_packet_count,
                     data_seen,context_seen,version_seen,drop_seen,err_seen,
                     gap_mode ? " (input gaps)" : "");

            passed = passed + 1;
            watch_active = 1'b0;
            stall_at0 = -1; stall_at1 = -1; stall_at2 = -1;
            gap_mode = 0;

            m_data_tready    = 1'b1;
            m_context_tready = 1'b1;
            m_version_tready = 1'b1;
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
            s_axis_pkt_tdata  = 32'd0;
            s_axis_pkt_tlast  = 1'b0;
            s_axis_pkt_tkeep  = `DIFI_TKEEP_FULL;
            m_data_tready     = 1'b1;
            m_context_tready  = 1'b1;
            m_version_tready  = 1'b1;
            repeat (4) @(negedge aclk);
            aresetn = 1'b1;
            repeat (2) @(negedge aclk);

            if (m_data_tvalid !== 1'b0 ||
                m_context_tvalid !== 1'b0 ||
                m_version_tvalid !== 1'b0 ||
                error_valid !== 1'b0)
                fail("Outputs were not cleared after reset");
        end
    endtask

    integer base;

    initial begin
        aresetn = 1'b0;
        s_axis_pkt_tdata  = 32'd0;
        s_axis_pkt_tvalid = 1'b0;
        s_axis_pkt_tkeep  = `DIFI_TKEEP_FULL;
        s_axis_pkt_tlast  = 1'b0;

        m_data_tready    = 1'b1;
        m_context_tready = 1'b1;
        m_version_tready = 1'b1;

        current_tc = 0;
        passed = 0;
        watch_active = 1'b0;
        hold_rx = 1'b0;
        hold_data = 1'b0;
        hold_context = 1'b0;
        hold_version = 1'b0;
        previous_err = 1'b0;
        clear_stream;

        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(negedge aclk);

        current_tc = 1;
        $display("\n=== TC01: complete Data packet, including Word0 ===");
        clear_stream;
        append_packet(ROUTE_DATA,10,8'h11);
        if (tx_word[0][31:28] !== 4'h1)
            fail("TB Data builder Packet Type is not 1");
        arm_case;
        execute_case;

        current_tc = 2;
        $display("\n=== TC02: complete 27-word Context packet, including Word0 ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_CONTEXT,27,8'h22);
        if (tx_word[0][31:28] !== 4'h4)
            fail("TB Context builder Packet Type is not 4");
        arm_case;
        execute_case;

        current_tc = 3;
        $display("\n=== TC03: complete 11-word Version packet, including Word0 ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_VERSION,11,8'h33);
        if (tx_word[0][31:28] !== 4'h5)
            fail("TB Version builder Packet Type is not 5");
        arm_case;
        execute_case;

        current_tc = 4;
        $display("\n=== TC04: route lock ignores payload high nibbles; TKEEP passes unchanged ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_DATA,9,8'h44);
        
        tx_word[1][31:28] = 4'h4;
        tx_word[2][31:28] = 4'h5;
        tx_word[3][31:28] = 4'hF;
        
        tx_keep[4] = 4'b0111;
        tx_keep[5] = 4'b0011;
        arm_case;
        execute_case;

        current_tc = 5;
        $display("\n=== TC05: Data Parser backpressure on Word0, middle beat and TLAST ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_DATA,8,8'h55);
        arm_case;
        stall_at0 = 0; stall_cycles0 = 3;
        stall_at1 = 4; stall_cycles1 = 2;
        stall_at2 = 7; stall_cycles2 = 4;
        
        m_context_tready = 1'b0;
        m_version_tready = 1'b0;
        execute_case;

        current_tc = 6;
        $display("\n=== TC06: Context route with TVALID gaps and downstream backpressure ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_CONTEXT,12,8'h66);
        arm_case;
        gap_mode = 1;
        stall_at0 = 0;  stall_cycles0 = 2;
        stall_at1 = 6;  stall_cycles1 = 3;
        stall_at2 = 11; stall_cycles2 = 2;
        execute_case;

        current_tc = 7;
        $display("\n=== TC07: continuous mixed Data -> Context -> Version, no TVALID gap ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_DATA,8,8'h71);
        append_packet(ROUTE_CONTEXT,27,8'h72);
        append_packet(ROUTE_VERSION,11,8'h73);
        arm_case;
        
        stall_at0 = 8;  stall_cycles0 = 2;
        stall_at1 = 35; stall_cycles1 = 3;
        execute_case;

        current_tc = 8;
        $display("\n=== TC08: one-word unsupported packet, one error, immediate Data recovery ===");
        reset_dut;
        clear_stream;
        append_unsupported_packet(4'hF,1,8'h81);
        append_packet(ROUTE_DATA,8,8'h82);
        arm_case;
        execute_case;

        current_tc = 9;
        $display("\n=== TC09: multiword unsupported packet drains to TLAST, never leaks, then recovers ===");
        reset_dut;
        clear_stream;
        append_unsupported_packet(4'hE,7,8'h91);
        
        tx_word[1][31:28] = 4'h1;
        tx_word[2][31:28] = 4'h4;
        tx_word[3][31:28] = 4'h5;
        append_packet(ROUTE_CONTEXT,9,8'h92);
        arm_case;
        execute_case;

        current_tc = 10;
        $display("\n=== TC10: several unsupported Packet Types each produce exactly one event ===");
        reset_dut;
        clear_stream;
        append_unsupported_packet(4'h0,2,8'hA0);
        append_unsupported_packet(4'h2,3,8'hA2);
        append_unsupported_packet(4'h3,1,8'hA3);
        append_unsupported_packet(4'h6,4,8'hA6);
        append_unsupported_packet(4'hF,2,8'hAF);
        append_packet(ROUTE_VERSION,6,8'hA5);
        arm_case;
        execute_case;

        current_tc = 11;
        $display("\n=== TC11: Context TREADY path ignores Data/Version TREADY ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_CONTEXT,6,8'hB1);
        arm_case;
        m_data_tready = 1'b0;
        m_version_tready = 1'b0;
        stall_at0 = 2; stall_cycles0 = 3;
        execute_case;

        current_tc = 12;
        $display("\n=== TC12: Version TREADY path ignores Data/Context TREADY ===");
        reset_dut;
        clear_stream;
        append_packet(ROUTE_VERSION,6,8'hC1);
        arm_case;
        m_data_tready = 1'b0;
        m_context_tready = 1'b0;
        stall_at0 = 4; stall_cycles0 = 3;
        execute_case;

        $display("\n============================================================");
        $display("ALL %0d difi_rx_dispatch TEST CASES PASSED", passed);
        $display("============================================================\n");
        $finish;
    end

endmodule
