`timescale 1ns/1ps
// Self-checking TB with deterministic gaps/backpressure, retained-beat monitor,
// transaction scoreboard, TLAST/TKEEP checks, watchdog, optional CSV trace.
// Icarus Verilog: iverilog -g2012 -s tb_axis_register_slice -o out.vvp DUT.v this.v
module tb_axis_register_slice;
    localparam integer BEATS = 16;
    reg aclk = 1'b0;
    always #5 aclk = ~aclk;
    reg aresetn = 1'b0;
    reg [31:0] s_axis_tdata = 0;
    reg [3:0]  s_axis_tkeep = 0;
    reg        s_axis_tlast = 0;
    reg        s_axis_tvalid = 0;
    wire       s_axis_tready;
    wire [31:0] m_axis_tdata;
    wire [3:0] m_axis_tkeep;
    wire       m_axis_tlast, m_axis_tvalid;
    reg        m_axis_tready = 0;
    integer cycle = 0;
    integer accepted = 0, emitted = 0, stall_cycles = 0;
    integer packet_count = 0;
    reg hold_input = 0, hold_output = 0;
    reg [31:0] hold_data;
    reg [3:0] hold_keep;
    reg hold_last;
    reg [8*256-1:0] trace_file;
    integer trace_fd = 0;

    axis_register_slice dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready)
    );

    function [31:0] word_value(input integer index);
        word_value = 32'h1BADC0DE ^ (index * 32'h00010003);
    endfunction
    function [3:0] keep_value(input integer index);
        // For the test's packet profile, partial bytes allowed on TLAST only.
        keep_value = (index == 7) ? 4'h3 :
                     (index == 15) ? 4'h7 : 4'hF;
    endfunction
    function last_value(input integer index);
        last_value = (index == 3 || index == 7 || index == 15);
    endfunction

    initial begin
        if ($value$plusargs("trace=%s", trace_file)) begin
            trace_fd = $fopen(trace_file, "w");
            if (trace_fd == 0) $fatal(1, "Cannot open trace path");
            $fdisplay(trace_fd, "cycle,aresetn,tvalid,tready,tdata,tkeep,tlast");
        end
        repeat (5) @(negedge aclk);
        aresetn = 1'b1;
        wait (emitted == BEATS);
        repeat (3) @(negedge aclk);
        if (accepted !== BEATS || emitted !== BEATS || packet_count !== 3)
            $fatal(1, "Missing/extra transfers or bad packet count");
        if (stall_cycles < 3)
            $fatal(1, "Insufficient backpressure coverage");
        if (trace_fd) $fclose(trace_fd);
        $display("[PASS] tb_axis_register_slice: 16 beats, 3 packets, stalls=%0d", stall_cycles);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "WATCHDOG: simulation did not finish");
    end

    // Drive inputs on negedge. If previous posedge was stalled, the source
    // retains TVALID/TDATA/TKEEP/TLAST across the next posedge.
    always @(negedge aclk) if (aresetn) begin
        m_axis_tready = ((cycle % 7) >= 3);
        if (!hold_input) begin
            if (accepted < BEATS && (cycle % 5 != 1)) begin
                s_axis_tvalid = 1;
                s_axis_tdata = word_value(accepted);
                s_axis_tkeep = keep_value(accepted);
                s_axis_tlast = last_value(accepted);
            end else begin
                s_axis_tvalid = 0;
                s_axis_tdata = 0;
                s_axis_tkeep = 0;
                s_axis_tlast = 0;
            end
        end
    end

    always @(posedge aclk) begin
        if (trace_fd)
            $fdisplay(trace_fd, "%0d,%0d,%0d,%0d,0x%08h,0x%01h,%0d",
                      cycle, aresetn, m_axis_tvalid, m_axis_tready,
                      m_axis_tdata, m_axis_tkeep, m_axis_tlast);
        cycle = cycle + 1;
        if (!aresetn) begin
            hold_input = 0;
            hold_output = 0;
        end else begin
            if (hold_output && (m_axis_tvalid !== 1'b1 ||
                m_axis_tdata !== hold_data ||
                m_axis_tkeep !== hold_keep ||
                m_axis_tlast !== hold_last))
                $fatal(1, "AXIS output changed while stalled");
            hold_output = (m_axis_tvalid && !m_axis_tready);
            if (hold_output) begin
                hold_data = m_axis_tdata;
                hold_keep = m_axis_tkeep;
                hold_last = m_axis_tlast;
                stall_cycles = stall_cycles + 1;
            end
            hold_input = (s_axis_tvalid && !s_axis_tready);
            if (s_axis_tvalid && s_axis_tready) accepted = accepted + 1;
            if (m_axis_tvalid && m_axis_tready) begin
                if (emitted >= BEATS) $fatal(1, "Extra output word");
                if (m_axis_tdata !== word_value(emitted) ||
                    m_axis_tkeep !== keep_value(emitted) ||
                    m_axis_tlast !== last_value(emitted))
                    $fatal(1, "Scoreboard mismatch at output beat %0d", emitted);
                if (m_axis_tlast) packet_count = packet_count + 1;
                emitted = emitted + 1;
            end
        end
    end
endmodule
