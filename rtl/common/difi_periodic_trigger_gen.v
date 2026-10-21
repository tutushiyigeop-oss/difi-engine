module difi_periodic_trigger_gen #(
    parameter integer CLK_FREQ_HZ = 100_000_000
)(
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] cfg_context_period_ms,
    input  wire [31:0] cfg_version_period_ms,

    output reg         context_periodic_trigger,
    output reg         version_periodic_trigger
);

// CLK_FREQ_HZ must be at least 1000 and a multiple of 1000.
localparam integer CLKS_PER_MS = CLK_FREQ_HZ / 1000;

reg [31:0] ms_div_count;
wire ms_tick;

assign ms_tick = (ms_div_count == CLKS_PER_MS - 1);

reg [31:0] count_ctx;
reg [31:0] count_ver;

reg [31:0] prev_cfg_ctx;
reg [31:0] prev_cfg_ver;

always @(posedge aclk or negedge aresetn)
begin
    if (!aresetn)
    begin
        ms_div_count <= 32'd0;

        count_ctx <= 32'd0;
        count_ver <= 32'd0;

        prev_cfg_ctx <= 32'd0;
        prev_cfg_ver <= 32'd0;

        context_periodic_trigger <= 1'b0;
        version_periodic_trigger <= 1'b0;
    end
    else
    begin
        
        if (ms_tick)
            ms_div_count <= 32'd0;
        else
            ms_div_count <= ms_div_count + 1'b1;

        context_periodic_trigger <= 1'b0;
        version_periodic_trigger <= 1'b0;

        prev_cfg_ctx <= cfg_context_period_ms;
        prev_cfg_ver <= cfg_version_period_ms;

        if ((cfg_context_period_ms == 0) ||
            (cfg_context_period_ms != prev_cfg_ctx))
        begin
            count_ctx <= 32'd0;
        end
        else if (ms_tick)
        begin
            if (count_ctx == cfg_context_period_ms - 1'b1)
            begin
                count_ctx <= 32'd0;
                context_periodic_trigger <= 1'b1;
            end
            else
            begin
                count_ctx <= count_ctx + 1'b1;
            end
        end

        if ((cfg_version_period_ms == 0) ||
            (cfg_version_period_ms != prev_cfg_ver))
        begin
            count_ver <= 32'd0;
        end
        else if (ms_tick)
        begin
            if (count_ver == cfg_version_period_ms - 1'b1)
            begin
                count_ver <= 32'd0;
                version_periodic_trigger <= 1'b1;
            end
            else
            begin
                count_ver <= count_ver + 1'b1;
            end
        end
    end
end

endmodule
