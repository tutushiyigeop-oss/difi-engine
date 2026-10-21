`include "difi_time_cfg_regmap.vh"

// Unmapped or unaligned accesses return DECERR.
// Writes to the read-only status register return SLVERR.
// Reject loads with ps >= 10^12; return SLVERR and latch the error.
// Writes honor WSTRB; COMMAND requires WSTRB[0].
// Address and data may arrive in either order; hold responses stable while waiting.

module difi_time_cfg_regs (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [7:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    
    input  wire [7:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output reg         time_load,
    output reg  [31:0] load_time_sec,
    output reg  [63:0] load_time_ps,
    input  wire        time_valid
);

localparam [63:0] PS_PER_SECOND = `DIFI_TIME_PS_PER_SECOND;
localparam [63:0] DEFAULT_SHADOW_PS = `DIFI_TIME_DEFAULT_SHADOW_PS;
wire [31:0] status_word;
reg        last_load_error;
assign status_word = ({31'd0, time_valid} << `DIFI_TIME_STATUS_VALID_BIT)
                   | ({31'd0, last_load_error} << `DIFI_TIME_STATUS_ERROR_BIT);

reg [31:0] shadow_sec;
reg [31:0] shadow_ps_lo;
reg [31:0] shadow_ps_hi;

reg        aw_pending;
reg [7:0]  awaddr_reg;
reg        w_pending;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;

assign s_axi_awready = aresetn && !aw_pending && !s_axi_bvalid;
assign s_axi_wready  = aresetn && !w_pending  && !s_axi_bvalid;
assign s_axi_arready = aresetn && !s_axi_rvalid;

function [31:0] apply_wstrb;
    input [31:0] old_data;
    input [31:0] new_data;
    input [3:0]  strobe;
    integer i;
    begin
        apply_wstrb = old_data;
        for (i = 0; i < 4; i = i + 1)
            if (strobe[i])
                apply_wstrb[i*8 +: 8] = new_data[i*8 +: 8];
    end
endfunction

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        aw_pending     <= 1'b0;
        awaddr_reg     <= 8'd0;
        w_pending      <= 1'b0;
        wdata_reg      <= 32'd0;
        wstrb_reg      <= 4'd0;
        s_axi_bvalid   <= 1'b0;
        s_axi_bresp    <= `DIFI_TIME_AXI_OKAY;
        s_axi_rvalid   <= 1'b0;
        s_axi_rdata    <= 32'd0;
        s_axi_rresp    <= `DIFI_TIME_AXI_OKAY;
        shadow_sec     <= `DIFI_TIME_DEFAULT_SHADOW_SEC;
        shadow_ps_lo   <= DEFAULT_SHADOW_PS[31:0];
        shadow_ps_hi   <= DEFAULT_SHADOW_PS[63:32];
        last_load_error<= `DIFI_TIME_DEFAULT_LAST_ERROR;
        time_load      <= 1'b0;
        load_time_sec  <= 32'd0;
        load_time_ps   <= 64'd0;
    end else begin
        // Latch time values together; the load pulse lasts one cycle.
        time_load <= 1'b0;

        if (s_axi_awvalid && s_axi_awready) begin
            aw_pending <= 1'b1;
            awaddr_reg <= s_axi_awaddr;
        end
        if (s_axi_wvalid && s_axi_wready) begin
            w_pending  <= 1'b1;
            wdata_reg  <= s_axi_wdata;
            wstrb_reg  <= s_axi_wstrb;
        end

        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;

        // Write only after both address and data have arrived.
        if (aw_pending && w_pending && !s_axi_bvalid) begin
            aw_pending <= 1'b0;
            w_pending  <= 1'b0;
            s_axi_bvalid <= 1'b1;
            s_axi_bresp <= `DIFI_TIME_AXI_OKAY;

            case (awaddr_reg)
                `DIFI_TIME_REG_SEC: shadow_sec   <= apply_wstrb(shadow_sec,   wdata_reg, wstrb_reg);
                `DIFI_TIME_REG_PS_LO: shadow_ps_lo <= apply_wstrb(shadow_ps_lo, wdata_reg, wstrb_reg);
                `DIFI_TIME_REG_PS_HI: shadow_ps_hi <= apply_wstrb(shadow_ps_hi, wdata_reg, wstrb_reg);
                `DIFI_TIME_REG_COMMAND: begin
                    if (wstrb_reg[0] && wdata_reg[`DIFI_TIME_CMD_LOAD_BIT]) begin
                        if ({shadow_ps_hi, shadow_ps_lo} < PS_PER_SECOND) begin
                            // Snapshot all time fields together on load.
                            
                            load_time_sec <= shadow_sec;
                            load_time_ps  <= {shadow_ps_hi, shadow_ps_lo};
                            time_load <= 1'b1;
                            last_load_error <= 1'b0;
                        end else begin
                            s_axi_bresp <= `DIFI_TIME_AXI_SLVERR;
                            last_load_error <= 1'b1;
                        end
                    end
                end
                `DIFI_TIME_REG_STATUS: s_axi_bresp <= `DIFI_TIME_AXI_SLVERR; 
                default: s_axi_bresp <= `DIFI_TIME_AXI_DECERR; 
            endcase
        end

        if (s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 1'b0;

        if (s_axi_arvalid && s_axi_arready) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rresp <= `DIFI_TIME_AXI_OKAY;
            s_axi_rdata <= 32'd0;
            case (s_axi_araddr)
                `DIFI_TIME_REG_SEC: s_axi_rdata <= shadow_sec;
                `DIFI_TIME_REG_PS_LO: s_axi_rdata <= shadow_ps_lo;
                `DIFI_TIME_REG_PS_HI: s_axi_rdata <= shadow_ps_hi;
                `DIFI_TIME_REG_COMMAND: s_axi_rdata <= 32'd0;
                `DIFI_TIME_REG_STATUS: s_axi_rdata <= status_word;
                default: s_axi_rresp <= `DIFI_TIME_AXI_DECERR;
            endcase
        end
    end
end

endmodule
