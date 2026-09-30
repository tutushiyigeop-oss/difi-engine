`timescale 1ns / 1ps

module tb_difi_tx_scheduler;


// ==================================================================
// 1. Constants
// ==================================================================
localparam [3:0] TYPE_DATA    = 4'h1;
localparam [3:0] TYPE_CONTEXT = 4'h4;
localparam [3:0] TYPE_VERSION = 4'h5;


// ==================================================================
// 2. Clock / Reset
// ==================================================================
reg aclk;
reg aresetn;

initial aclk = 1'b0;
always #5 aclk = ~aclk;       // 100 MHz


// ==================================================================
// 3. Scheduler control
// ==================================================================
reg  tx_enable;
reg  time_valid;
reg  data_available;

reg  cfg_commit_req;
wire cfg_commit_ack;

reg  context_change_pending;
reg  context_change_set;

reg  context_periodic_trigger;
reg  version_periodic_trigger;

wire tx_busy;


// ==================================================================
// 4. Time Source
// ==================================================================
reg [31:0] time_sec;
reg [63:0] time_ps;


// ==================================================================
// 5. Data Packetizer signals
// ==================================================================
wire        data_pkt_start;
wire        data_pkt_busy;
wire        data_pkt_done;

reg  [31:0] cfg_data_stream_id;
reg  [15:0] cfg_samples_per_packet;

wire [31:0] s_axis_iq_tdata;
wire        s_axis_iq_tvalid;
wire        s_axis_iq_tready;

reg         iq_feed_enable;
reg  [31:0] iq_counter;

wire [31:0] data_axis_tdata;
wire        data_axis_tvalid;
wire        data_axis_tready;
wire [3:0]  data_axis_tkeep;
wire        data_axis_tlast;


// ==================================================================
// 6. Context Generator signals
// ==================================================================
wire        context_pkt_start;
wire        context_pkt_busy;
wire        context_pkt_done;

reg  [31:0] cfg_sample_rate_hz;
reg  [31:0] cfg_bandwidth_hz;
reg  [63:0] cfg_rf_freq_hz;

wire        context_change_done;

wire [31:0] context_axis_tdata;
wire        context_axis_tvalid;
wire        context_axis_tready;
wire [3:0]  context_axis_tkeep;
wire        context_axis_tlast;


// ==================================================================
// 7. Version Generator signals
// ==================================================================
wire        version_pkt_start;
wire        version_pkt_busy;
wire        version_pkt_done;

reg  [31:0] cfg_version_stream_id;

wire [31:0] version_axis_tdata;
wire        version_axis_tvalid;
wire        version_axis_tready;
wire [3:0]  version_axis_tkeep;
wire        version_axis_tlast;


// ==================================================================
// 8. Merged Scheduler AXIS
// ==================================================================
wire [31:0] m_axis_pkt_tdata;
wire        m_axis_pkt_tvalid;
reg         m_axis_pkt_tready;
wire [3:0]  m_axis_pkt_tkeep;
wire        m_axis_pkt_tlast;

wire merged_fire;

assign merged_fire =
    m_axis_pkt_tvalid &&
    m_axis_pkt_tready;


// ==================================================================
// 9. IQ Source
// ==================================================================
assign s_axis_iq_tdata  = iq_counter;
assign s_axis_iq_tvalid = iq_feed_enable;

always @(posedge aclk or negedge aresetn)
begin
    if (!aresetn)
    begin
        iq_counter <= 32'h0001_0001;
    end

    else if (s_axis_iq_tvalid && s_axis_iq_tready)
    begin
        iq_counter <= iq_counter + 32'h0001_0001;
    end
end


// ==================================================================
// 10. Simple cfg_regs model for context_change_pending
// ==================================================================
always @(posedge aclk or negedge aresetn)
begin
    if (!aresetn)
    begin
        context_change_pending <= 1'b0;
    end

    else
    begin
        if (context_change_done)
            context_change_pending <= 1'b0;

        // SET priority
        if (context_change_set)
            context_change_pending <= 1'b1;
    end
end


// ==================================================================
// 11. Data Packetizer
// ==================================================================
difi_data_packetizer u_data_packetizer (
    .aclk                   (aclk),
    .aresetn                (aresetn),

    .pkt_start              (data_pkt_start),
    .pkt_busy               (data_pkt_busy),
    .pkt_done               (data_pkt_done),

    .s_axis_iq_tdata        (s_axis_iq_tdata),
    .s_axis_iq_tvalid       (s_axis_iq_tvalid),
    .s_axis_iq_tready       (s_axis_iq_tready),

    .cfg_data_stream_id     (cfg_data_stream_id),
    .cfg_samples_per_packet (cfg_samples_per_packet),

    .time_sec               (time_sec),
    .time_ps                (time_ps),
    .time_valid             (time_valid),

    .m_axis_pkt_tdata       (data_axis_tdata),
    .m_axis_pkt_tvalid      (data_axis_tvalid),
    .m_axis_pkt_tready      (data_axis_tready),
    .m_axis_pkt_tkeep       (data_axis_tkeep),
    .m_axis_pkt_tlast       (data_axis_tlast)
);


// ==================================================================
// 12. Context Generator
// ==================================================================
difi_context_generator u_context_generator (
    .aclk                        (aclk),
    .aresetn                     (aresetn),

    .pkt_start                   (context_pkt_start),
    .pkt_busy                    (context_pkt_busy),
    .pkt_done                    (context_pkt_done),

    .cfg_data_stream_id          (cfg_data_stream_id),
    .cfg_sample_rate_hz          (cfg_sample_rate_hz),
    .cfg_bandwidth_hz            (cfg_bandwidth_hz),
    .cfg_rf_freq_hz              (cfg_rf_freq_hz),

    .cfg_context_change_pending  (context_change_pending),
    .context_change_done         (context_change_done),

    .time_sec                    (time_sec),
    .time_ps                     (time_ps),
    .time_valid                  (time_valid),

    .m_axis_pkt_tdata            (context_axis_tdata),
    .m_axis_pkt_tvalid           (context_axis_tvalid),
    .m_axis_pkt_tready           (context_axis_tready),
    .m_axis_pkt_tkeep            (context_axis_tkeep),
    .m_axis_pkt_tlast            (context_axis_tlast)
);


// ==================================================================
// 13. Version Generator
// ==================================================================
difi_version_generator u_version_generator (
    .aclk                    (aclk),
    .aresetn                 (aresetn),

    .pkt_start               (version_pkt_start),
    .pkt_busy                (version_pkt_busy),
    .pkt_done                (version_pkt_done),

    .cfg_version_stream_id   (cfg_version_stream_id),

    .time_sec                (time_sec),
    .time_ps                 (time_ps),
    .time_valid              (time_valid),

    .m_axis_pkt_tdata        (version_axis_tdata),
    .m_axis_pkt_tvalid       (version_axis_tvalid),
    .m_axis_pkt_tready       (version_axis_tready),
    .m_axis_pkt_tkeep        (version_axis_tkeep),
    .m_axis_pkt_tlast        (version_axis_tlast)
);


// ==================================================================
// 14. TX Scheduler
// ==================================================================
difi_tx_scheduler dut (
    .aclk                     (aclk),
    .aresetn                  (aresetn),

    .tx_enable                (tx_enable),
    .time_valid               (time_valid),

    .data_available           (data_available),

    .cfg_commit_req           (cfg_commit_req),
    .cfg_commit_ack           (cfg_commit_ack),

    .context_change_pending   (context_change_pending),
    .context_periodic_trigger (context_periodic_trigger),
    .version_periodic_trigger (version_periodic_trigger),

    .data_pkt_start           (data_pkt_start),
    .data_pkt_busy            (data_pkt_busy),
    .data_pkt_done            (data_pkt_done),

    .s_axis_data_tdata        (data_axis_tdata),
    .s_axis_data_tvalid       (data_axis_tvalid),
    .s_axis_data_tready       (data_axis_tready),
    .s_axis_data_tkeep        (data_axis_tkeep),
    .s_axis_data_tlast        (data_axis_tlast),

    .context_pkt_start        (context_pkt_start),
    .context_pkt_busy         (context_pkt_busy),
    .context_pkt_done         (context_pkt_done),

    .s_axis_context_tdata     (context_axis_tdata),
    .s_axis_context_tvalid    (context_axis_tvalid),
    .s_axis_context_tready    (context_axis_tready),
    .s_axis_context_tkeep     (context_axis_tkeep),
    .s_axis_context_tlast     (context_axis_tlast),

    .version_pkt_start        (version_pkt_start),
    .version_pkt_busy         (version_pkt_busy),
    .version_pkt_done         (version_pkt_done),

    .s_axis_version_tdata     (version_axis_tdata),
    .s_axis_version_tvalid    (version_axis_tvalid),
    .s_axis_version_tready    (version_axis_tready),
    .s_axis_version_tkeep     (version_axis_tkeep),
    .s_axis_version_tlast     (version_axis_tlast),

    .m_axis_pkt_tdata         (m_axis_pkt_tdata),
    .m_axis_pkt_tvalid        (m_axis_pkt_tvalid),
    .m_axis_pkt_tready        (m_axis_pkt_tready),
    .m_axis_pkt_tkeep         (m_axis_pkt_tkeep),
    .m_axis_pkt_tlast         (m_axis_pkt_tlast),

    .tx_busy                  (tx_busy)
);


// ==================================================================
// 15. Test bookkeeping
// ==================================================================
integer current_tc;
integer pass_count;

integer packet_count;
reg [3:0] packet_type_log [0:31];

reg       packet_active;
reg [3:0] current_packet_type;

integer packet_word_count;

reg        held_valid;
reg [31:0] held_data;
reg [3:0]  held_keep;
reg        held_last;

reg previous_ack;


// ==================================================================
// 16. FAIL helper
// ==================================================================
task fail;
    input [8*160-1:0] reason;

    begin
        $display(
            "[FAIL] TC%0d time=%0t : %0s",
            current_tc,
            $time,
            reason
        );

        $finish;
    end
endtask


task pass;
    input [8*120-1:0] text;

    begin
        $display(
            "[PASS] TC%0d : %0s",
            current_tc,
            text
        );

        pass_count = pass_count + 1;
    end
endtask


// ==================================================================
// 17. Packet output monitor
//
// Record Packet Type from Word0.
// ==================================================================
always @(posedge aclk)
begin
    if (!aresetn)
    begin
        packet_count        = 0;
        packet_active       = 1'b0;
        current_packet_type = 4'd0;
        packet_word_count   = 0;
    end

    else if (merged_fire)
    begin
        if (!packet_active)
        begin
            packet_active       = 1'b1;
            current_packet_type = m_axis_pkt_tdata[31:28];
            packet_word_count   = 0;
        end

        packet_word_count =
            packet_word_count + 1;

        if (m_axis_pkt_tkeep !== 4'b1111)
        begin
            fail("Merged TKEEP is not 4'b1111");
        end

        if (m_axis_pkt_tlast)
        begin
            packet_type_log[packet_count] =
                current_packet_type;

            packet_count =
                packet_count + 1;

            packet_active =
                1'b0;
        end
    end
end


// ==================================================================
// 18. AXIS backpressure stability monitor
// ==================================================================
always @(posedge aclk)
begin
    if (!aresetn)
    begin
        held_valid = 1'b0;
    end

    else
    begin
        if (held_valid)
        begin
            if (
                m_axis_pkt_tvalid !== 1'b1 ||
                m_axis_pkt_tdata  !== held_data ||
                m_axis_pkt_tkeep  !== held_keep ||
                m_axis_pkt_tlast  !== held_last
            )
            begin
                fail(
                    "Merged AXIS changed while TREADY=0"
                );
            end
        end

        held_valid =
            m_axis_pkt_tvalid &&
            !m_axis_pkt_tready;

        if (held_valid)
        begin
            held_data = m_axis_pkt_tdata;
            held_keep = m_axis_pkt_tkeep;
            held_last = m_axis_pkt_tlast;
        end
    end
end


// ==================================================================
// 19. Basic Scheduler assertions
// ==================================================================
always @(posedge aclk)
begin
    if (!aresetn)
    begin
        previous_ack = 1'b0;
    end

    else
    begin
        if (
            (data_pkt_start && context_pkt_start) ||
            (data_pkt_start && version_pkt_start) ||
            (context_pkt_start && version_pkt_start)
        )
        begin
            fail(
                "More than one pkt_start asserted"
            );
        end

        if (
            (data_pkt_start ||
             context_pkt_start ||
             version_pkt_start) &&
            (!tx_enable || !time_valid)
        )
        begin
            fail(
                "Packet started while TX/time disabled"
            );
        end

        if (
            cfg_commit_ack &&
            (data_pkt_start ||
             context_pkt_start ||
             version_pkt_start)
        )
        begin
            fail(
                "cfg_commit_ack overlaps pkt_start"
            );
        end

        if (
            cfg_commit_ack &&
            previous_ack
        )
        begin
            fail(
                "cfg_commit_ack lasted more than one cycle"
            );
        end

        previous_ack =
            cfg_commit_ack;
    end
end


// ==================================================================
// 20. Utility tasks
// ==================================================================
task pulse_context_change;
begin
    @(negedge aclk);
    context_change_set = 1'b1;

    @(negedge aclk);
    context_change_set = 1'b0;
end
endtask


task pulse_context_periodic;
begin
    @(negedge aclk);
    context_periodic_trigger = 1'b1;

    @(negedge aclk);
    context_periodic_trigger = 1'b0;
end
endtask


task pulse_version_periodic;
begin
    @(negedge aclk);
    version_periodic_trigger = 1'b1;

    @(negedge aclk);
    version_periodic_trigger = 1'b0;
end
endtask


task wait_packet_count;
    input integer target;

    integer timeout;

begin
    timeout = 0;

    while (
        packet_count < target &&
        timeout < 5000
    )
    begin
        @(negedge aclk);

        timeout =
            timeout + 1;
    end

    if (packet_count < target)
    begin
        fail(
            "Timed out waiting for packet"
        );
    end
end
endtask


task wait_data_busy;
    integer timeout;

begin
    timeout = 0;

    while (
        data_pkt_busy !== 1'b1 &&
        timeout < 1000
    )
    begin
        @(negedge aclk);

        timeout =
            timeout + 1;
    end

    if (data_pkt_busy !== 1'b1)
    begin
        fail(
            "Timed out waiting for Data start"
        );
    end
end
endtask


task request_one_data;
begin
    @(negedge aclk);

    data_available =
        1'b1;

    wait_data_busy;

    // Scheduler has granted this Data packet.
    data_available =
        1'b0;
end
endtask


task wait_commit_ack;
    integer timeout;

begin
    timeout = 0;

    while (
        cfg_commit_ack !== 1'b1 &&
        timeout < 1000
    )
    begin
        @(negedge aclk);

        timeout =
            timeout + 1;
    end

    if (cfg_commit_ack !== 1'b1)
    begin
        fail(
            "Timed out waiting for cfg_commit_ack"
        );
    end
end
endtask


task expect_no_new_packet;
    input integer old_count;
    input integer cycles;

    integer k;

begin
    for (k = 0; k < cycles; k = k + 1)
    begin
        @(negedge aclk);

        if (packet_count != old_count)
        begin
            fail(
                "Unexpected packet was transmitted"
            );
        end
    end
end
endtask


// ==================================================================
// 21. Main Test
// ==================================================================
integer base;

initial
begin

    // --------------------------------------------------------------
    // Initial values
    // --------------------------------------------------------------
    aresetn = 1'b0;

    tx_enable      = 1'b0;
    time_valid     = 1'b1;
    data_available = 1'b0;

    cfg_commit_req = 1'b0;

    context_change_set        = 1'b0;
    context_periodic_trigger  = 1'b0;
    version_periodic_trigger  = 1'b0;

    time_sec = 32'd100;
    time_ps  = 64'd0;

    cfg_data_stream_id      = 32'h0000_0001;
    cfg_version_stream_id   = 32'h0000_0100;

    cfg_samples_per_packet  = 16'd8;

    cfg_sample_rate_hz      = 32'd20_000_000;
    cfg_bandwidth_hz        = 32'd10_000_000;
    cfg_rf_freq_hz          = 64'd100_000_000;

    iq_feed_enable          = 1'b1;

    m_axis_pkt_tready       = 1'b1;

    current_tc              = 0;
    pass_count              = 0;

    held_valid              = 1'b0;
    previous_ack            = 1'b0;


    // --------------------------------------------------------------
    // Reset
    // --------------------------------------------------------------
    repeat (5)
        @(negedge aclk);

    aresetn = 1'b1;

    repeat (2)
        @(negedge aclk);


    // ==============================================================
    // TC01
    // Startup:
    // Version -> Context(change) -> Data
    // ==============================================================
    current_tc = 1;

    $display(
        "\n=== TC01: startup Version -> Context -> Data ==="
    );

    pulse_context_change;

    base =
        packet_count;

    tx_enable =
        1'b1;

    request_one_data;

    wait_packet_count(
        base + 3
    );

    if (
        packet_type_log[base]     != TYPE_VERSION ||
        packet_type_log[base + 1] != TYPE_CONTEXT ||
        packet_type_log[base + 2] != TYPE_DATA
    )
    begin
        fail(
            "Startup packet order is wrong"
        );
    end

    pass(
        "Version -> Context -> Data"
    );


    // ==============================================================
    // TC02
    // tx_enable / time_valid gating
    // ==============================================================
    current_tc = 2;

    $display(
        "\n=== TC02: tx_enable / time_valid gating ==="
    );

    base =
        packet_count;

    tx_enable      = 1'b0;
    data_available = 1'b1;

    expect_no_new_packet(
        base,
        5
    );

    tx_enable  = 1'b1;
    time_valid = 1'b0;

    expect_no_new_packet(
        base,
        5
    );

    time_valid = 1'b1;

    wait_data_busy;

    data_available =
        1'b0;

    wait_packet_count(
        base + 1
    );

    if (
        packet_type_log[base] !=
        TYPE_DATA
    )
    begin
        fail(
            "Expected Data after gate release"
        );
    end

    pass(
        "TX/time gates work"
    );


    // ==============================================================
    // TC03
    //
    // During Data:
    // Context trigger twice + Version trigger once
    //
    // Expected:
    // Data -> Context -> Version
    //
    // Repeated Context triggers must coalesce.
    // ==============================================================
    current_tc = 3;

    $display(
        "\n=== TC03: periodic pending / coalescing / priority ==="
    );

    cfg_samples_per_packet =
        16'd32;

    base =
        packet_count;

    request_one_data;

    pulse_context_periodic;
    pulse_context_periodic;
    pulse_version_periodic;

    wait_packet_count(
        base + 3
    );

    if (
        packet_type_log[base]     != TYPE_DATA ||
        packet_type_log[base + 1] != TYPE_CONTEXT ||
        packet_type_log[base + 2] != TYPE_VERSION
    )
    begin
        fail(
            "Periodic arbitration order is wrong"
        );
    end

    // No second Context should remain from the repeated trigger.
    expect_no_new_packet(
        base + 3,
        10
    );

    pass(
        "pending, coalescing and priority work"
    );


    // ==============================================================
    // TC04
    //
    // Stall the final beat of a Data packet.
    // A Context trigger arrives while stalled.
    //
    // Expected:
    // ownership remains Data until TLAST handshake,
    // then Context is sent.
    // ==============================================================
    current_tc = 4;

    $display(
        "\n=== TC04: TLAST backpressure / ownership lock ==="
    );

    cfg_samples_per_packet =
        16'd16;

    base =
        packet_count;

    request_one_data;


    // Data packet has 7 + 16 = 23 words.
    // Wait until 22 words have already handshaken.
    while (
        !packet_active ||
        current_packet_type != TYPE_DATA ||
        packet_word_count < 22
    )
    begin
        @(negedge aclk);
    end


    // Stall before final Word handshake.
    m_axis_pkt_tready =
        1'b0;


    pulse_context_periodic;


    repeat (4)
        @(negedge aclk);


    if (
        m_axis_pkt_tvalid !== 1'b1 ||
        m_axis_pkt_tlast  !== 1'b1
    )
    begin
        fail(
            "Final Data beat not held during backpressure"
        );
    end


    // Release TLAST beat.
    m_axis_pkt_tready =
        1'b1;


    wait_packet_count(
        base + 2
    );


    if (
        packet_type_log[base]     != TYPE_DATA ||
        packet_type_log[base + 1] != TYPE_CONTEXT
    )
    begin
        fail(
            "Context preempted Data before TLAST handshake"
        );
    end


    pass(
        "TLAST stall keeps ownership locked"
    );


    // ==============================================================
    // TC05
    //
    // cfg_commit_req arrives while Data is active.
    //
    // ACK must wait for Data packet boundary.
    // After commit:
    //
    // Context(change) -> Data
    // ==============================================================
    current_tc = 5;

    $display(
        "\n=== TC05: cfg_commit_req / ack boundary ==="
    );

    cfg_samples_per_packet =
        16'd32;

    base =
        packet_count;

    request_one_data;


    @(negedge aclk);

    cfg_commit_req =
        1'b1;


    // ACK may not happen while Data owns TX.
    repeat (5)
    begin
        @(negedge aclk);

        if (cfg_commit_ack)
        begin
            fail(
                "cfg_commit_ack asserted during active Data"
            );
        end
    end


    // First packet is Data.
    wait_packet_count(
        base + 1
    );


    wait_commit_ack;


    // Emulate cfg_regs shadow -> active.
    @(negedge aclk);

    cfg_commit_req =
        1'b0;

    context_change_set =
        1'b1;


    @(negedge aclk);

    context_change_set =
        1'b0;


    // Request next Data immediately.
    // Context(change) must still win.
    request_one_data;


    wait_packet_count(
        base + 3
    );


    if (
        packet_type_log[base]     != TYPE_DATA ||
        packet_type_log[base + 1] != TYPE_CONTEXT ||
        packet_type_log[base + 2] != TYPE_DATA
    )
    begin
        fail(
            "Commit did not enforce Context-before-Data"
        );
    end


    pass(
        "commit waits boundary and announces Context first"
    );


    // ==============================================================
    // TC06
    //
    // tx_enable goes low while Data owns TX.
    //
    // Current Data must finish.
    // Version pending waits until TX re-enabled.
    // ==============================================================
    current_tc = 6;

    $display(
        "\n=== TC06: tx_enable low during active packet ==="
    );

    cfg_samples_per_packet =
        16'd32;

    base =
        packet_count;

    request_one_data;


    @(negedge aclk);

    tx_enable =
        1'b0;


    pulse_version_periodic;


    // Current Data must still complete.
    wait_packet_count(
        base + 1
    );


    if (
        packet_type_log[base] !=
        TYPE_DATA
    )
    begin
        fail(
            "Active Data was aborted"
        );
    end


    // Version cannot start while disabled.
    expect_no_new_packet(
        base + 1,
        8
    );


    tx_enable =
        1'b1;


    wait_packet_count(
        base + 2
    );


    if (
        packet_type_log[base + 1] !=
        TYPE_VERSION
    )
    begin
        fail(
            "Version pending was not preserved"
        );
    end


    pass(
        "tx_enable only blocks new packets"
    );


    // ==============================================================
    // TC07
    //
    // cfg_commit_ack must still work with:
    // tx_enable=0 and time_valid=0.
    // ==============================================================
    current_tc = 7;

    $display(
        "\n=== TC07: commit ACK independent of TX/time ==="
    );

    base =
        packet_count;

    tx_enable  =
        1'b0;

    time_valid =
        1'b0;

    cfg_commit_req =
        1'b1;


    wait_commit_ack;


    if (
        packet_count != base
    )
    begin
        fail(
            "Packet transmitted during disabled commit test"
        );
    end


    @(negedge aclk);

    cfg_commit_req =
        1'b0;


    repeat (2)
        @(negedge aclk);


    if (cfg_commit_ack)
    begin
        fail(
            "cfg_commit_ack did not return low"
        );
    end


    time_valid =
        1'b1;

    tx_enable =
        1'b1;


    pass(
        "commit ACK works independently"
    );


    // ==============================================================
    // Final
    // ==============================================================
    if (pass_count != 7)
    begin
        fail(
            "Unexpected pass count"
        );
    end


    $display(
        "\nALL TESTS PASSED: TC01-TC07"
    );

    $display(
        "Total merged packets = %0d",
        packet_count
    );

    $finish;
end


// ==================================================================
// 22. Global timeout
// ==================================================================
initial
begin
    #200000;

    fail(
        "Global simulation timeout"
    );
end


endmodule