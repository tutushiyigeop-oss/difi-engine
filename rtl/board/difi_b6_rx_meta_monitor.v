// B6 diagnostic monitor for accepted DIFI RX metadata.
// Connect every input to difi_engine_ip pins in the SAME aclk domain.
// Connect gpio_count and gpio_detail to two 32-bit INPUT channels of AXI GPIO.
// Counter overflow saturates; do not use for sustained throughput tests.
module difi_b6_rx_meta_monitor (
    input wire aclk,
    input wire aresetn,
    input wire m_ver_valid,
    input wire m_ver_ready,
    input wire [3:0] m_ver_seq,
    input wire m_ver_changed,
    input wire m_ctx_valid,
    input wire m_ctx_ready,
    input wire [3:0] m_ctx_seq,
    input wire m_ctx_changed,
    input wire rx_dispatch_error_valid,
    input wire rx_data_error_valid,
    input wire rx_context_error_valid,
    input wire rx_version_error_valid,
    output wire [31:0] gpio_count,
    output wire [31:0] gpio_detail
);
    reg [15:0] version_count;
    reg [15:0] context_count;
    reg [3:0] last_version_seq;
    reg [3:0] last_context_seq;
    reg last_version_changed;
    reg last_context_changed;
    reg [3:0] version_errors;
    reg [3:0] context_errors;
    reg [3:0] dispatch_errors;
    reg [3:0] data_errors;

    // ch1: [31:16] version accepted; [15:0] context accepted.
    assign gpio_count = {version_count, context_count};
    // ch2: [31:28] data errors, [27:24] dispatch errors,
    //      [23:20] version errors, [19:16] context errors,
    //      [15:10] reserved, [9] ver_changed, [8] ctx_changed,
    //      [7:4] last ver seq, [3:0] last ctx seq.
    assign gpio_detail = {
        data_errors, dispatch_errors, version_errors, context_errors,
        6'b0, last_version_changed, last_context_changed,
        last_version_seq, last_context_seq
    };

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            version_count <= 0;
            context_count <= 0;
            last_version_seq <= 0;
            last_context_seq <= 0;
            last_version_changed <= 0;
            last_context_changed <= 0;
            version_errors <= 0;
            context_errors <= 0;
            dispatch_errors <= 0;
            data_errors <= 0;
        end else begin
            if (m_ver_valid && m_ver_ready) begin
                if (version_count != 16'hffff)
                    version_count <= version_count + 16'd1;
                last_version_seq <= m_ver_seq;
                last_version_changed <= m_ver_changed;
            end
            if (m_ctx_valid && m_ctx_ready) begin
                if (context_count != 16'hffff)
                    context_count <= context_count + 16'd1;
                last_context_seq <= m_ctx_seq;
                last_context_changed <= m_ctx_changed;
            end
            if (rx_version_error_valid && version_errors != 4'hf)
                version_errors <= version_errors + 4'd1;
            if (rx_context_error_valid && context_errors != 4'hf)
                context_errors <= context_errors + 4'd1;
            if (rx_dispatch_error_valid && dispatch_errors != 4'hf)
                dispatch_errors <= dispatch_errors + 4'd1;
            if (rx_data_error_valid && data_errors != 4'hf)
                data_errors <= data_errors + 4'd1;
        end
    end
endmodule
