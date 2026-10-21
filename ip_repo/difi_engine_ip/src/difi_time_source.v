module difi_time_source #(
    parameter integer CLK_FREQ_HZ = 100_000_000
)(
    
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        time_load,
    input  wire [31:0] load_time_sec,
    input  wire [63:0] load_time_ps,

    output reg  [31:0] time_sec,
    output reg  [63:0] time_ps,
    output reg         time_valid
);

localparam [63:0] PS_PER_SECOND = 64'd1_000_000_000_000;

localparam [63:0] PS_PER_CLK = PS_PER_SECOND / CLK_FREQ_HZ;

wire load_accepted;
wire [63:0] next_time_ps;

assign load_accepted = time_load && (load_time_ps < PS_PER_SECOND);

assign next_time_ps = time_ps + PS_PER_CLK;

always @(posedge aclk or negedge aresetn)
begin
    if (!aresetn)
    begin
        time_sec   <= 32'd0;
        time_ps    <= 64'd0;
        time_valid <= 1'b0;
    end
    else
    begin
        // Time loading takes priority.
        if (load_accepted)
        begin
            time_sec   <= load_time_sec;
            time_ps    <= load_time_ps;
            time_valid <= 1'b1;
        end

        else if (time_valid)
        begin
            if (next_time_ps >= PS_PER_SECOND)
            begin
                time_ps <= next_time_ps - PS_PER_SECOND;
                time_sec <= time_sec + 1'b1;
            end

            else
            begin
                time_ps <= next_time_ps;
            end
        end
    end
end

endmodule
