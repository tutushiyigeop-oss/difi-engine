`timescale 1ns/1ps
// DELIBERATELY BROKEN DUT. Use ONLY to demonstrate detection of stall violation.
// Same module name as the correct template, so compile only one at a time.
module axis_register_slice (
    input wire aclk, input wire aresetn,
    input wire [31:0] s_axis_tdata, input wire [3:0] s_axis_tkeep,
    input wire s_axis_tlast, input wire s_axis_tvalid,
    output wire s_axis_tready,
    output wire [31:0] m_axis_tdata, output wire [3:0] m_axis_tkeep,
    output wire m_axis_tlast, output wire m_axis_tvalid,
    input wire m_axis_tready
);
    reg [31:0] data_q;
    reg [3:0] keep_q;
    reg last_q, valid_q;
    assign s_axis_tready = !valid_q || m_axis_tready;
    assign m_axis_tdata = data_q;
    assign m_axis_tkeep = keep_q;
    assign m_axis_tlast = last_q;
    assign m_axis_tvalid = valid_q;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            data_q <= 0; keep_q <= 0; last_q <= 0; valid_q <= 0;
        end else if (s_axis_tready) begin
            valid_q <= s_axis_tvalid;
            if (s_axis_tvalid) begin
                data_q <= s_axis_tdata;
                keep_q <= s_axis_tkeep;
                last_q <= s_axis_tlast;
            end
        end else if (valid_q && !m_axis_tready) begin
            data_q <= data_q ^ 32'h0000_0001; // BUG: changes output while stalled
        end
    end
endmodule
