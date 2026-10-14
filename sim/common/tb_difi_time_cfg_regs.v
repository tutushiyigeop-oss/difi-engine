`timescale 1ns/1ps
`include "difi_time_cfg_regmap.vh"
// Self-checking AXI4-Lite UTC control + real Time Source interaction.
module tb_difi_time_cfg_regs;

reg aclk = 1'b0;
always #5 aclk = ~aclk;
reg aresetn = 1'b0;
reg [7:0] awaddr = 0;
reg [2:0] awprot = 0;
reg awvalid = 0;
wire awready;
reg [31:0] wdata = 0;
reg [3:0] wstrb = 0;
reg wvalid = 0;
wire wready;
wire [1:0] bresp;
wire bvalid;
reg bready = 1;
reg [7:0] araddr = 0;
reg [2:0] arprot = 0;
reg arvalid = 0;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready = 1;
wire time_load;
wire [31:0] load_sec;
wire [63:0] load_ps;
wire [31:0] time_sec;
wire [63:0] time_ps;
wire time_valid;
integer pulse_count = 0;
integer checks = 0;

difi_time_cfg_regs dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arprot(arprot),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready),
    .time_load(time_load), .load_time_sec(load_sec),
    .load_time_ps(load_ps), .time_valid(time_valid)
);

difi_time_source #(.CLK_FREQ_HZ(100_000_000)) u_time (
    .aclk(aclk), .aresetn(aresetn), .time_load(time_load),
    .load_time_sec(load_sec), .load_time_ps(load_ps),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid)
);

always @(posedge aclk) if (aresetn && time_load) pulse_count = pulse_count + 1;

task expect;
    input condition;
    input [255:0] message;
    begin
        checks = checks + 1;
        if (condition !== 1'b1) begin
            $display("[FAIL] %0s at %0t", message, $time);
            $finish_and_return(1);
        end
    end
endtask

task send_aw;
    input [7:0] address;
    begin
        @(negedge aclk);
        awaddr = address; awvalid = 1'b1;
        @(posedge aclk);
        while (!awready) @(posedge aclk);
        @(negedge aclk);
        awvalid = 1'b0;
    end
endtask

task send_w;
    input [31:0] data;
    input [3:0]  strb;
    begin
        @(negedge aclk);
        wdata = data; wstrb = strb; wvalid = 1'b1;
        @(posedge aclk);
        while (!wready) @(posedge aclk);
        @(negedge aclk);
        wvalid = 1'b0;
    end
endtask

task axi_write;
    input [7:0] address;
    input [31:0] data;
    input [3:0] strb;
    input integer w_first;
    input [1:0] exp_resp;
    begin
        if (w_first == 1) begin
            send_w(data, strb);
            send_aw(address);
        end else if (w_first == 2) begin
            fork
                send_aw(address);
                send_w(data, strb);
            join
        end else begin
            send_aw(address);
            send_w(data, strb);
        end
        @(negedge aclk);
        while (!bvalid) @(negedge aclk);
        expect(bresp == exp_resp, "AXI write response");
    end
endtask

task axi_read;
    input [7:0] address;
    input [31:0] exp_data;
    input [1:0] exp_resp;
    begin
        @(negedge aclk);
        araddr = address; arvalid = 1;
        @(posedge aclk);
        while (!arready) @(posedge aclk);
        @(negedge aclk);
        arvalid = 0;
        while (!rvalid) @(negedge aclk);
        expect(rresp == exp_resp, "AXI read response");
        if (exp_resp == 2'b00)
            expect(rdata == exp_data, "AXI read data");
    end
endtask

initial begin
    // No wave generation by default; can enable for debug.
    repeat (4) @(negedge aclk);
    aresetn = 1;
    repeat (3) @(negedge aclk);
    expect(time_valid == 0, "reset: time source invalid");
    axi_read(`DIFI_TIME_REG_STATUS, 32'd0, 2'b00);
    $display("[PASS] reset and invalid initial time");

    // Verify independent AW/W channel arrival orders and byte strobes.
    axi_write(`DIFI_TIME_REG_SEC, 32'd100, 4'hf, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_PS_LO, 32'hAAAA_BBBB, 4'hf, 1, 2'b00);
    axi_write(`DIFI_TIME_REG_PS_LO, 32'h0000_1122, 4'b0011, 2, 2'b00);
    axi_read(`DIFI_TIME_REG_PS_LO, 32'hAAAA_1122, 2'b00);
    axi_write(`DIFI_TIME_REG_PS_LO, 32'd0, 4'hf, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_PS_HI, 32'd0, 4'hf, 0, 2'b00);
    $display("[PASS] AW/W any order; partial WSTRB");

    // W1P command uses a snapshot of complete shadow fields.
    axi_write(`DIFI_TIME_REG_COMMAND, 32'd1, 4'hf, 2, 2'b00);
    repeat (3) @(negedge aclk);
    expect(time_valid && time_sec == 100, "UTC init became valid");
    expect(pulse_count == 1, "one pulse per accepted command");
    axi_read(`DIFI_TIME_REG_STATUS, 32'h1, 2'b00);
    axi_read(`DIFI_TIME_REG_COMMAND, 32'd0, 2'b00);
    $display("[PASS] atomic UTC initialization and one-cycle load");

    // Illegal ps=10^12: 0x000000E8_D4A51000.
    axi_write(`DIFI_TIME_REG_PS_LO, 32'hD4A51000, 4'hf, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_PS_HI, 32'h000000E8, 4'hf, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_COMMAND, 32'd1, 4'hf, 0, 2'b10);
    repeat (3) @(negedge aclk);
    expect(pulse_count == 1 && time_valid, "illegal load rejected");
    axi_read(`DIFI_TIME_REG_STATUS, 32'h3, 2'b00);
    $display("[PASS] bad picoseconds rejected without stopping time");

    // Restore legal near-carry time; load should clear sticky error.
    axi_write(`DIFI_TIME_REG_SEC, 32'd321, 4'hf, 0, 2'b00);
    // Easier unambiguous near-second value via explicit 64-bit slices.
    axi_write(`DIFI_TIME_REG_PS_LO, (64'd999999990000 & 64'hFFFFFFFF), 4'hf, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_PS_HI, (64'd999999990000 >> 32), 4'hf, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_COMMAND, 32'd1, 4'hf, 0, 2'b00);
    repeat (3) @(negedge aclk);
    expect(pulse_count == 2 && time_sec == 322 && time_ps <= 64'd100000,
           "legal hot reload; second rollover");
    axi_read(`DIFI_TIME_REG_STATUS, 32'h1, 2'b00);
    $display("[PASS] reload and second carry, previous error cleared");

    // Verify erroneous control/strobes and unmapped accesses.
    axi_write(`DIFI_TIME_REG_COMMAND, 32'd1, 4'b0000, 0, 2'b00);
    axi_write(`DIFI_TIME_REG_COMMAND, 32'd0, 4'hf, 0, 2'b00);
    repeat (3) @(negedge aclk);
    expect(pulse_count == 2, "strobe=0 or command=0 no load");
    axi_write(`DIFI_TIME_REG_STATUS, 32'd1, 4'hf, 0, 2'b10);
    axi_write(8'h03, 32'd1, 4'hf, 0, 2'b11);
    axi_read(8'hFC, 32'd0, 2'b11);
    $display("[PASS] write to RO, unaligned and unmapped responses");

    // B-channel backpressure must hold BVALID/BRESP.
    bready = 0;
    send_aw(`DIFI_TIME_REG_SEC);
    send_w(32'd321, 4'hf);
    @(negedge aclk);
    while (!bvalid) @(negedge aclk);
    repeat (4) begin
        expect(bvalid && bresp == 2'b00, "B held while stalled");
        @(negedge aclk);
    end
    bready = 1;
    repeat (2) @(negedge aclk);
    expect(!bvalid, "B clears after handshake");

    // R-channel backpressure must hold RVALID/RDATA/RRESP.
    rready = 0;
    @(negedge aclk);
    araddr = `DIFI_TIME_REG_SEC;
    arvalid = 1;
    @(posedge aclk);
    while (!arready) @(posedge aclk);
    @(negedge aclk);
    arvalid = 0;
    while (!rvalid) @(negedge aclk);
    repeat (4) begin
        expect(rvalid && rdata == 321 && rresp == 2'b00,
               "R held while stalled");
        @(negedge aclk);
    end
    rready = 1;
    repeat (2) @(negedge aclk);
    expect(!rvalid, "R clears after handshake");
    $display("[PASS] AXI4-Lite B/R backpressure and response stability");

    $display("ALL TESTS PASS (%0d checks)", checks);
    $finish;
end

initial begin
    #2000000;
    $display("[FAIL] Testbench timeout");
    $finish_and_return(1);
end
endmodule
