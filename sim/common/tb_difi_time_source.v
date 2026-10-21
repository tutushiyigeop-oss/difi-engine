`timescale 1ns/1ps

module tb_difi_time_source;

parameter integer TB_CLK_FREQ_HZ = 100_000_000;
localparam [63:0] PS_PER_SECOND = 64'd1_000_000_000_000;
localparam [63:0] TB_PS_PER_CLK  = PS_PER_SECOND / TB_CLK_FREQ_HZ;

reg         aclk;
reg         aresetn;
reg         time_load;
reg  [31:0] load_time_sec;
reg  [63:0] load_time_ps;
wire [31:0] time_sec;
wire [63:0] time_ps;
wire        time_valid;

difi_time_source #(
    .CLK_FREQ_HZ(TB_CLK_FREQ_HZ)
) dut (
    .aclk          (aclk),
    .aresetn       (aresetn),
    .time_load     (time_load),
    .load_time_sec (load_time_sec),
    .load_time_ps  (load_time_ps),
    .time_sec      (time_sec),
    .time_ps       (time_ps),
    .time_valid    (time_valid)
);

always #5 aclk = ~aclk;

// The reference model stores the start time and elapsed picoseconds separately.

reg [31:0] golden_base_sec;
reg [63:0] golden_base_ps;
reg [95:0] golden_elapsed_ps;
reg [95:0] golden_fractional_total;
reg        golden_valid;
reg [31:0] expected_sec;
reg [63:0] expected_ps;

integer checked_cycles;
integer test_count;
reg     monitor_enable;

task fail_test;
    input [8*128-1:0] message;
    begin
        $display("============================================================");
        $display("[FAIL] %0s at simtime %0t", message, $time);
        $display("  input: rstn=%b load=%b load_sec=%0d load_ps=%0d",
                 aresetn, time_load, load_time_sec, load_time_ps);
        $display("  actual: sec=%0d ps=%0d valid=%b",
                 time_sec, time_ps, time_valid);
        $display("  golden: sec=%0d ps=%0d valid=%b",
                 expected_sec, expected_ps, golden_valid);
        $display("============================================================");
        $finish_and_return(1);
    end
endtask

always @(posedge aclk or negedge aresetn)
begin
    if (!aresetn)
    begin
        golden_base_sec   = 32'd0;
        golden_base_ps    = 64'd0;
        golden_elapsed_ps = 96'd0;
        golden_valid      = 1'b0;
    end
    else if (time_load && (load_time_ps < PS_PER_SECOND))
    begin
        golden_base_sec   = load_time_sec;
        golden_base_ps    = load_time_ps;
        golden_elapsed_ps = 96'd0;
        golden_valid      = 1'b1;
    end
    else if (golden_valid)
    begin
        
        golden_elapsed_ps = golden_elapsed_ps + {32'd0, TB_PS_PER_CLK};
    end

    golden_fractional_total = {32'd0, golden_base_ps} + golden_elapsed_ps;
    expected_sec = golden_base_sec
                 + (golden_fractional_total / PS_PER_SECOND);
    expected_ps  = golden_fractional_total % PS_PER_SECOND;

    #1;
    if (monitor_enable)
    begin
        checked_cycles = checked_cycles + 1;
        if ((time_valid !== golden_valid) ||
            (time_sec   !== expected_sec) ||
            (time_ps    !== expected_ps))
            fail_test("Cycle-by-cycle scoreboard mismatch");

        if (time_ps >= PS_PER_SECOND)
            fail_test("time_ps must always stay below 1 second");
    end
end

// Drive inputs on falling edges to avoid the sampling edge.
task wait_cycles;
    input integer count;
    begin
        repeat (count) @(negedge aclk);
    end
endtask

task expect_time;
    input [31:0] sec;
    input [63:0] ps;
    input        valid;
    input [8*128-1:0] label;
    begin
        if ((time_sec !== sec) ||
            (time_ps !== ps) ||
            (time_valid !== valid))
            fail_test(label);
    end
endtask

task pass_case;
    input [8*128-1:0] label;
    begin
        test_count = test_count + 1;
        $display("[PASS] T%02d %0s", test_count, label);
    end
endtask

task pulse_load;
    input [31:0] sec;
    input [63:0] ps;
    begin
        @(negedge aclk);
        load_time_sec = sec;
        load_time_ps  = ps;
        time_load     = 1'b1;
        @(negedge aclk);
        time_load     = 1'b0;
    end
endtask

task assert_continuous_ticks;
    input integer n;
    reg [31:0] last_sec;
    reg [63:0] last_ps;
    reg [31:0] next_sec;
    reg [63:0] next_ps;
    reg [63:0] ps_sum;
    integer i;
    begin
        last_sec = time_sec;
        last_ps  = time_ps;
        for (i = 0; i < n; i = i + 1)
        begin
            @(negedge aclk);
            ps_sum = last_ps + TB_PS_PER_CLK;
            if (ps_sum >= PS_PER_SECOND)
            begin
                next_sec = last_sec + 1'b1;
                next_ps  = ps_sum - PS_PER_SECOND;
            end
            else
            begin
                next_sec = last_sec;
                next_ps  = ps_sum;
            end
            if ((time_valid !== 1'b1) ||
                (time_sec !== next_sec) ||
                (time_ps !== next_ps))
                fail_test("Continuous tick spacing");
            last_sec = time_sec;
            last_ps  = time_ps;
        end
    end
endtask

initial
begin
    aclk           = 1'b0;
    aresetn        = 1'b0;
    time_load      = 1'b0;
    load_time_sec  = 32'd0;
    load_time_ps   = 64'd0;
    golden_base_sec   = 32'd0;
    golden_base_ps    = 64'd0;
    golden_elapsed_ps = 96'd0;
    golden_fractional_total = 96'd0;
    golden_valid      = 1'b0;
    expected_sec   = 32'd0;
    expected_ps    = 64'd0;
    checked_cycles = 0;
    test_count     = 0;
    monitor_enable = 1'b1;

    if ((TB_CLK_FREQ_HZ <= 0) ||
        ((PS_PER_SECOND % TB_CLK_FREQ_HZ) != 0) ||
        (TB_PS_PER_CLK == 0) ||
        (TB_PS_PER_CLK > PS_PER_SECOND))
    begin
        $display("[FAIL] TB_CLK_FREQ_HZ must be a positive exact divisor of 10^12");
        $finish_and_return(1);
    end

    $display("DIFI Time Source self-checking TB");
    $display("CLK_FREQ_HZ=%0d, PS_PER_CLK=%0d", TB_CLK_FREQ_HZ, TB_PS_PER_CLK);

    wait_cycles(3);
    expect_time(32'd0, 64'd0, 1'b0, "T01 initial reset values");
    pass_case("Asynchronous reset values");

    aresetn = 1'b1;
    wait_cycles(7);
    expect_time(32'd0, 64'd0, 1'b0, "T02 uninitialized output stability");
    
    pulse_load(32'd77, PS_PER_SECOND);
    expect_time(32'd0, 64'd0, 1'b0,
                "T02 invalid initial load must not assert valid");
    pass_case("Uninitialized clock remains invalid, even after illegal load");

    pulse_load(32'd123, 64'd250_000_000_123);
    expect_time(32'd123, 64'd250_000_000_123, 1'b1,
                "T03 exact timestamp initialization");
    pass_case("Atomic legal load, time_valid asserts");

    wait_cycles(7);
    expect_time(32'd123, 64'd250_000_000_123 + 7*TB_PS_PER_CLK,
                1'b1, "T04 fixed picosecond increment");
    pass_case("Precise per-cycle picosecond increment");

    pulse_load(32'd40, PS_PER_SECOND - TB_PS_PER_CLK);
    expect_time(32'd40, PS_PER_SECOND - TB_PS_PER_CLK, 1'b1,
                "T05 before exact carry");
    wait_cycles(1);
    expect_time(32'd41, 64'd0, 1'b1, "T05 exact second carry");
    pass_case("Exact second carry: zero remainder");

    pulse_load(32'd50, PS_PER_SECOND - (TB_PS_PER_CLK / 2));
    wait_cycles(1);
    expect_time(32'd51, TB_PS_PER_CLK - (TB_PS_PER_CLK / 2),
                1'b1, "T06 second carry with remainder");
    pass_case("Second carry preserves sub-second remainder");

    // An invalid load request must not interrupt timekeeping.
    @(negedge aclk);
    time_load     = 1'b1;
    load_time_sec = 32'd999;
    load_time_ps  = PS_PER_SECOND;  
    assert_continuous_ticks(3);
    time_load = 1'b0;
    pass_case("Illegal load rejected; original timestamp retained");

    @(negedge aclk);
    time_load     = 1'b1;
    load_time_sec = 32'd888;
    load_time_ps  = PS_PER_SECOND + 64'd25;
    assert_continuous_ticks(2);
    time_load = 1'b0;
    pass_case("Repeated illegal loads do not pause the clock");

    pulse_load(32'd11, 64'd333_000_000_007);
    expect_time(32'd11, 64'd333_000_000_007, 1'b1,
                "T09 hot reload must replace old time exactly");
    wait_cycles(3);
    expect_time(32'd11, 64'd333_000_000_007 + 3*TB_PS_PER_CLK,
                1'b1, "T09 counting after hot reload");
    pass_case("Hot reload atomically replaces an existing timestamp");

    pulse_load(32'd70, PS_PER_SECOND - TB_PS_PER_CLK);
    
    time_load     = 1'b1;
    load_time_sec = 32'd200;
    load_time_ps  = 64'd12_345;
    @(negedge aclk);
    time_load = 1'b0;
    expect_time(32'd200, 64'd12_345, 1'b1,
                "T10 load must win over a pending carry");
    pass_case("Valid load has priority over second carry");

    pulse_load(32'd1000, PS_PER_SECOND - 30*TB_PS_PER_CLK);
    assert_continuous_ticks(250);
    expect_time(32'd1001, 220*TB_PS_PER_CLK, 1'b1,
                "T11 uninterrupted sequence across second rollover");
    pass_case("250 consecutive precise increments and a rollover");

    #1;
    aresetn = 1'b0;
    #1;
    expect_time(32'd0, 64'd0, 1'b0,
                "T12 asynchronous mid-operation reset");
    wait_cycles(4);
    aresetn = 1'b1;
    wait_cycles(5);
    expect_time(32'd0, 64'd0, 1'b0,
                "T12 remain invalid following reset");
    pass_case("Mid-operation asynchronous reset and invalid state");

    pulse_load(32'd320, PS_PER_SECOND - 64'd1);
    wait_cycles(1);
    expect_time(32'd321, TB_PS_PER_CLK - 64'd1, 1'b1,
                "T13 maximum legal fractional timestamp");
    pass_case("Boundary value: load_ps = 10^12-1");

    pulse_load(32'hffff_ffff, PS_PER_SECOND - TB_PS_PER_CLK);
    assert_continuous_ticks(3);
    expect_time(32'd0, 2*TB_PS_PER_CLK, 1'b1,
                "T14 32-bit seconds rollover and continued ticking");
    pass_case("32-bit second counter wraps modulo 2^32");

    $display("============================================================");
    $display("ALL TESTS PASS (%0d test cases, %0d checked clock events)",
             test_count, checked_cycles);
    $display("============================================================");
    $finish;
end

initial
begin
    #100000;
    fail_test("Testbench timeout");
end

endmodule
