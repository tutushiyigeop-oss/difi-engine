`timescale 1ns/1ps

module tb_difi_periodic_trigger_gen;

parameter integer TB_CLK_FREQ_HZ = 10_000;
localparam integer CLKS_PER_MS = TB_CLK_FREQ_HZ / 1000;

reg         aclk;
reg         aresetn;
reg [31:0]  cfg_context_period_ms;
reg [31:0]  cfg_version_period_ms;
wire        context_periodic_trigger;
wire        version_periodic_trigger;

difi_periodic_trigger_gen #(
    .CLK_FREQ_HZ(TB_CLK_FREQ_HZ)
) dut (
    .aclk                     (aclk),
    .aresetn                  (aresetn),
    .cfg_context_period_ms    (cfg_context_period_ms),
    .cfg_version_period_ms    (cfg_version_period_ms),
    .context_periodic_trigger (context_periodic_trigger),
    .version_periodic_trigger (version_periodic_trigger)
);

always #5 aclk = ~aclk;

integer ref_div_phase;
reg     ref_tick;
reg [31:0] ref_prev_cfg_ctx;
reg [31:0] ref_prev_cfg_ver;
reg [31:0] ref_elapsed_ctx_ms;
reg [31:0] ref_elapsed_ver_ms;
reg     exp_ctx_pulse;
reg     exp_ver_pulse;

integer checked_cycles;
integer ctx_pulses;
integer ver_pulses;
integer simultaneous_pulses;
integer checks_passed;
reg     monitor_enable;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        ref_div_phase       = 0;
        ref_tick            = 1'b0;
        ref_prev_cfg_ctx    = 32'd0;
        ref_prev_cfg_ver    = 32'd0;
        ref_elapsed_ctx_ms  = 32'd0;
        ref_elapsed_ver_ms  = 32'd0;
        exp_ctx_pulse       = 1'b0;
        exp_ver_pulse       = 1'b0;
    end else begin
        ref_tick = (ref_div_phase == CLKS_PER_MS - 1);
        if (ref_tick)
            ref_div_phase = 0;
        else
            ref_div_phase = ref_div_phase + 1;

        exp_ctx_pulse = 1'b0;
        exp_ver_pulse = 1'b0;

        // A new period setting takes priority over the current due event.
        if ((cfg_context_period_ms == 32'd0) ||
            (cfg_context_period_ms != ref_prev_cfg_ctx)) begin
            ref_elapsed_ctx_ms = 32'd0;
        end else if (ref_tick) begin
            ref_elapsed_ctx_ms = ref_elapsed_ctx_ms + 1'b1;
            if (ref_elapsed_ctx_ms == cfg_context_period_ms) begin
                ref_elapsed_ctx_ms = 32'd0;
                exp_ctx_pulse = 1'b1;
            end
        end

        if ((cfg_version_period_ms == 32'd0) ||
            (cfg_version_period_ms != ref_prev_cfg_ver)) begin
            ref_elapsed_ver_ms = 32'd0;
        end else if (ref_tick) begin
            ref_elapsed_ver_ms = ref_elapsed_ver_ms + 1'b1;
            if (ref_elapsed_ver_ms == cfg_version_period_ms) begin
                ref_elapsed_ver_ms = 32'd0;
                exp_ver_pulse = 1'b1;
            end
        end

        ref_prev_cfg_ctx = cfg_context_period_ms;
        ref_prev_cfg_ver = cfg_version_period_ms;
    end

    // Delay #1 to check after register updates.
    #1;
    if (monitor_enable) begin
        if ((context_periodic_trigger !== exp_ctx_pulse) ||
            (version_periodic_trigger !== exp_ver_pulse)) begin
            $display("[FAIL] t=%0t ns, ctx_period=%0d, ver_period=%0d", 
                     $time, cfg_context_period_ms, cfg_version_period_ms);
            $display("       expected ctx/ver = %b/%b, actual = %b/%b",
                     exp_ctx_pulse, exp_ver_pulse,
                     context_periodic_trigger, version_periodic_trigger);
            $display("       ref_div_phase=%0d, ctx_elapsed_ms=%0d, ver_elapsed_ms=%0d",
                     ref_div_phase, ref_elapsed_ctx_ms, ref_elapsed_ver_ms);
            $finish;
        end

        if (aresetn) begin
            checked_cycles = checked_cycles + 1;
            if (context_periodic_trigger === 1'b1)
                ctx_pulses = ctx_pulses + 1;
            if (version_periodic_trigger === 1'b1)
                ver_pulses = ver_pulses + 1;
            if ((context_periodic_trigger === 1'b1) &&
                (version_periodic_trigger === 1'b1))
                simultaneous_pulses = simultaneous_pulses + 1;
        end
    end
end

// Drive inputs on falling edges to avoid the sampling edge.
task wait_clocks;
    input integer n;
    begin
        repeat (n) @(negedge aclk);
    end
endtask

task reset_dut;
    begin
        @(negedge aclk);
        aresetn = 1'b0;
        cfg_context_period_ms = 32'd0;
        cfg_version_period_ms = 32'd0;
        wait_clocks(3);
        aresetn = 1'b1;
    end
endtask

task set_cfg_at_ms_boundary;
    input [31:0] ctx_ms;
    input [31:0] ver_ms;
    begin
        @(negedge aclk);
        while (ref_div_phase != 0)
            @(negedge aclk);
        cfg_context_period_ms = ctx_ms;
        cfg_version_period_ms = ver_ms;
    end
endtask

task set_cfg_before_ms_tick;
    input [31:0] ctx_ms;
    input [31:0] ver_ms;
    begin
        @(negedge aclk);
        while (ref_div_phase != CLKS_PER_MS - 1)
            @(negedge aclk);
        cfg_context_period_ms = ctx_ms;
        cfg_version_period_ms = ver_ms;
    end
endtask

task expect_pulse_delta;
    input [8*64-1:0] test_name;
    input integer ctx_before;
    input integer ver_before;
    input integer both_before;
    input integer expected_ctx;
    input integer expected_ver;
    input integer expected_both;
    begin
        if (((ctx_pulses - ctx_before) != expected_ctx) ||
            ((ver_pulses - ver_before) != expected_ver) ||
            ((simultaneous_pulses - both_before) != expected_both)) begin
            $display("[FAIL] %0s", test_name);
            $display("       expected increments ctx/ver/both=%0d/%0d/%0d",
                     expected_ctx, expected_ver, expected_both);
            $display("       actual increments   ctx/ver/both=%0d/%0d/%0d",
                     ctx_pulses-ctx_before, ver_pulses-ver_before,
                     simultaneous_pulses-both_before);
            $finish;
        end else begin
            checks_passed = checks_passed + 1;
            $display("[PASS] %0s: ctx=%0d, ver=%0d, both=%0d",
                     test_name, expected_ctx, expected_ver, expected_both);
        end
    end
endtask

integer c0;
integer v0;
integer b0;

initial begin
    aclk                  = 1'b0;
    aresetn               = 1'b0;
    cfg_context_period_ms = 32'd0;
    cfg_version_period_ms = 32'd0;
    monitor_enable        = 1'b0;
    checked_cycles        = 0;
    ctx_pulses            = 0;
    ver_pulses            = 0;
    simultaneous_pulses   = 0;
    checks_passed         = 0;

    if ((TB_CLK_FREQ_HZ < 1000) || (TB_CLK_FREQ_HZ % 1000 != 0) ||
        (CLKS_PER_MS < 2)) begin
        $display("[FAIL] TB_CLK_FREQ_HZ must yield at least 2 integer clocks per ms.");
        $finish;
    end

    wait_clocks(4);
    monitor_enable = 1'b1;
    aresetn = 1'b1;
    wait_clocks(3*CLKS_PER_MS+3);
    expect_pulse_delta("T01 reset/default period 0", 0, 0, 0, 0, 0, 0);

    reset_dut;
    set_cfg_at_ms_boundary(32'd2, 32'd3);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(6*CLKS_PER_MS);
    expect_pulse_delta("T02 independent 2ms/3ms, 6ms window", c0,v0,b0,3,2,1);
    wait_clocks(1);
    if ((context_periodic_trigger !== 1'b0) ||
        (version_periodic_trigger !== 1'b0)) begin
        $display("[FAIL] T02 pulses must deassert after one aclk cycle");
        $finish;
    end
    checks_passed=checks_passed+1;
    $display("[PASS] T03 single-clock pulse width");

    reset_dut;
    set_cfg_at_ms_boundary(32'd1, 32'd0);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(5*CLKS_PER_MS);
    expect_pulse_delta("T04 1ms period", c0,v0,b0,5,0,0);
    if (context_periodic_trigger !== 1'b1) begin
        $display("[FAIL] T04 fifth 1-ms trigger not present before disable");
        $finish;
    end
    cfg_context_period_ms = 32'd0; 
    wait_clocks(1);
    if (context_periodic_trigger !== 1'b0) begin
        $display("[FAIL] T05 disable must clear a previously high pulse");
        $finish;
    end
    wait_clocks(5*CLKS_PER_MS);
    expect_pulse_delta("T05 disable directly after trigger", c0,v0,b0,5,0,0);

    reset_dut;
    set_cfg_at_ms_boundary(32'd8, 32'd0);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(5*CLKS_PER_MS);
    expect_pulse_delta("T06 no early event at 5/8ms", c0,v0,b0,0,0,0);
    cfg_context_period_ms = 32'd3;
    wait_clocks(1);
    if (context_periodic_trigger !== 1'b0) begin
        $display("[FAIL] T06 period decrease caused an immediate trigger");
        $finish;
    end
    wait_clocks(3*CLKS_PER_MS-1);
    expect_pulse_delta("T06 period change restarts count", c0,v0,b0,1,0,0);

    reset_dut;
    set_cfg_at_ms_boundary(32'd1, 32'd0);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(3*CLKS_PER_MS);
    expect_pulse_delta("T07 initial 1ms phase", c0,v0,b0,3,0,0);
    cfg_context_period_ms = 32'd5;
    wait_clocks(4*CLKS_PER_MS);
    expect_pulse_delta("T07 no stale count after 1->5", c0,v0,b0,3,0,0);
    wait_clocks(CLKS_PER_MS);
    expect_pulse_delta("T07 first new 5ms event", c0,v0,b0,4,0,0);
    cfg_context_period_ms = 32'd1;
    wait_clocks(2*CLKS_PER_MS);
    expect_pulse_delta("T07 5->1ms restart", c0,v0,b0,6,0,0);

    reset_dut;
    set_cfg_at_ms_boundary(32'd2, 32'd3);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(3*CLKS_PER_MS);
    cfg_context_period_ms = 32'd5;
    wait_clocks(6*CLKS_PER_MS);
    expect_pulse_delta("T08 independent configuration changes", c0,v0,b0,2,3,0);

    reset_dut;
    set_cfg_before_ms_tick(32'd2, 32'd2);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(2*CLKS_PER_MS);
    expect_pulse_delta("T09 cfg change beats same-edge tick", c0,v0,b0,0,0,0);
    wait_clocks(1);
    expect_pulse_delta("T09 due on next tick", c0,v0,b0,1,1,1);

    reset_dut;
    set_cfg_at_ms_boundary(32'd4, 32'd6);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(3*CLKS_PER_MS);
    expect_pulse_delta("T10 partial count before reset", c0,v0,b0,0,0,0);
    aresetn = 1'b0;  
    wait_clocks(3);
    aresetn = 1'b1;
    
    wait_clocks(4*CLKS_PER_MS);
    expect_pulse_delta("T10 ctx period restarts after reset", c0,v0,b0,1,0,0);
    wait_clocks(2*CLKS_PER_MS);
    expect_pulse_delta("T10 ver period restarts after reset", c0,v0,b0,1,1,0);

    reset_dut;
    set_cfg_at_ms_boundary(32'hFFFF_FFFF, 32'hFFFF_FFFF);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(10*CLKS_PER_MS);
    expect_pulse_delta("T11 32-bit maximum periods", c0,v0,b0,0,0,0);

    reset_dut;
    set_cfg_at_ms_boundary(32'd2, 32'd2);
    c0=ctx_pulses; v0=ver_pulses; b0=simultaneous_pulses;
    wait_clocks(2*CLKS_PER_MS);
    cfg_version_period_ms = 32'd0;
    wait_clocks(4*CLKS_PER_MS);
    expect_pulse_delta("T12 disable version only", c0,v0,b0,3,1,1);

    $display("============================================================");
    $display("ALL TESTS PASS (%0d checks, %0d checked clock cycles)",
             checks_passed, checked_cycles);
    $display("============================================================");
    $finish;
end

initial begin
    #200000;
    $display("[FAIL] Global simulation timeout");
    $finish;
end

endmodule
