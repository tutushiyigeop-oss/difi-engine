`include "difi_cfg_regmap.vh"

module difi_cfg_regs (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI4-Lite Write Address
    input  wire [7:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    // AXI4-Lite Write Data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    // AXI4-Lite Write Response
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    // AXI4-Lite Read Address
    input  wire [7:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    // AXI4-Lite Read Data
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // Control / Commit
    output wire        tx_enable,
    output wire        cfg_commit_req,
    input  wire        cfg_commit_ack,

    output wire        context_change_pending,
    input  wire        context_change_done,

    // Live Status
    input  wire        tx_busy,
    input  wire        time_valid,

    // TX Active Configuration
    output wire [31:0] cfg_data_stream_id,
    output wire [31:0] cfg_version_stream_id,
    output wire [15:0] cfg_samples_per_packet,
    output wire [31:0] cfg_sample_rate_hz,
    output wire [31:0] cfg_bandwidth_hz,
    output wire [63:0] cfg_rf_freq_hz,
    output wire [31:0] cfg_context_period_ms,
    output wire [31:0] cfg_version_period_ms,

    // RX Filter Configuration
    output wire        cfg_rx_data_filter_enable,
    output wire [31:0] cfg_rx_expected_data_stream_id,
    output wire        cfg_rx_version_filter_enable,
    output wire [31:0] cfg_rx_expected_version_stream_id
);


// FSM State Defination
reg [1:0] write_current_state;
reg [1:0] write_next_state;
localparam ST_W_COLLECT = 2'd0;
localparam ST_W_EXECUTE = 2'd1;
localparam ST_W_RESPONSE = 2'd2;

reg read_current_state;
reg read_next_state;
localparam ST_R_IDLE = 1'd0;
localparam ST_R_RESPONSE = 1'd1;


// AXI4-Lite
reg [7:0] awaddr_reg;
reg aw_pending;
reg [31:0] wdata_reg;
reg [3:0] wstrb_reg;
reg w_pending;
reg [1:0] bresp_reg;
reg bvalid_reg;
reg [31:0] rdata_reg;
reg [1:0] rresp_reg;
reg rvalid_reg;

assign s_axi_bresp = bresp_reg;
assign s_axi_bvalid = bvalid_reg;
assign s_axi_awready = !aw_pending && !bvalid_reg;
assign s_axi_wready = !w_pending && !bvalid_reg;
assign s_axi_rdata = rdata_reg;
assign s_axi_rresp = rresp_reg;
assign s_axi_rvalid = rvalid_reg;
assign s_axi_arready = (!rvalid_reg) && (read_current_state == ST_R_IDLE);

wire aw_handshake;
wire w_handshake;
wire b_handshake;
wire ar_handshake;
wire r_handshake;

assign aw_handshake = s_axi_awvalid && s_axi_awready;
assign w_handshake = s_axi_wvalid && s_axi_wready;
assign b_handshake = s_axi_bvalid && s_axi_bready;
assign ar_handshake = s_axi_arvalid && s_axi_arready;
assign r_handshake = s_axi_rvalid && s_axi_rready;

wire write_execute;
assign write_execute = aw_pending && w_pending && !bvalid_reg;

function [31:0] apply_wstrb;
    input [31:0] old_data;
    input [31:0] new_data;
    input [3:0]  strb;

    integer i;

    begin
        apply_wstrb = old_data;

        for (i = 0; i < 4; i = i + 1) 
        begin
            if (strb[i])
            begin
                apply_wstrb[i*8 +: 8] = new_data[i*8 +: 8];
            end
        end
    end
endfunction


// TX Shadow / Active reg
reg [31:0] shadow_data_sid;
reg [31:0] active_data_sid;

reg [31:0] shadow_version_sid;
reg [31:0] active_version_sid;

reg [15:0] shadow_samples;
reg [15:0] active_samples;

reg [31:0] shadow_sample_rate;
reg [31:0] active_sample_rate;

reg [31:0] shadow_bandwidth;
reg [31:0] active_bandwidth;

reg [63:0] shadow_rf_freq;
reg [63:0] active_rf_freq;

reg [31:0] shadow_context_period;
reg [31:0] active_context_period;

reg [31:0] shadow_version_period;
reg [31:0] active_version_period;

assign cfg_data_stream_id = active_data_sid;
assign cfg_version_stream_id = active_version_sid;
assign cfg_samples_per_packet = active_samples;
assign cfg_sample_rate_hz = active_sample_rate;
assign cfg_bandwidth_hz = active_bandwidth;
assign cfg_rf_freq_hz = active_rf_freq;
assign cfg_context_period_ms = active_context_period;
assign cfg_version_period_ms = active_version_period;


// RX Config / In time control reg
reg tx_enable_reg;
reg [1:0] rx_filter_ctrl_reg;
reg [31:0] rx_expected_data_sid_reg;
reg [31:0] rx_expected_version_sid_reg;
assign tx_enable = tx_enable_reg;
assign cfg_rx_data_filter_enable = rx_filter_ctrl_reg[0];
assign cfg_rx_version_filter_enable = rx_filter_ctrl_reg[1];
assign cfg_rx_expected_data_stream_id = rx_expected_data_sid_reg;
assign cfg_rx_expected_version_stream_id = rx_expected_version_sid_reg;


// Commit / Context control reg
reg cfg_commit_req_reg;
reg context_change_pending_reg;
reg [31:0] last_commit_error_reg;
assign cfg_commit_req = cfg_commit_req_reg;
assign context_change_pending = context_change_pending_reg;


// ------------------------------------------------------------------
// 1. State register
// ------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        write_current_state <= ST_W_COLLECT;
        read_current_state <= ST_R_IDLE;
    end

    else
    begin
        write_current_state <= write_next_state;
        read_current_state<= read_next_state;
    end
end


// ------------------------------------------------------------------
// 2. Next-state logic
// ------------------------------------------------------------------
always @(*) 
begin
    write_next_state = write_current_state;
    read_next_state = read_current_state;

    case (write_current_state)
    ST_W_COLLECT:
    begin
        if(write_execute)
        begin
            write_next_state = ST_W_EXECUTE;
        end
    end

    ST_W_EXECUTE:
    begin
        write_next_state = ST_W_RESPONSE;
    end

    ST_W_RESPONSE:
    begin
        if(b_handshake)
        begin
            write_next_state = ST_W_COLLECT;
        end
    end

    default:
    begin
        write_next_state = ST_W_COLLECT;
    end
    endcase

    case (read_current_state)
    ST_R_IDLE:
    begin
        if(ar_handshake)
        begin
            read_next_state = ST_R_RESPONSE;
        end
    end

    ST_R_RESPONSE:
    begin
        if(r_handshake)
        begin
            read_next_state = ST_R_IDLE;
        end
    end

    default:
    begin
        read_next_state = ST_R_IDLE;
    end
    endcase
end


// ------------------------------------------------------------------
// 3. 
// ------------------------------------------------------------------


// ------------------------------------------------------------------
// 4. 
// ------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) 
begin
    if(!aresetn)
    begin
        aw_pending <= 0;
        awaddr_reg <= 0;
        w_pending <= 0;
        wstrb_reg <= 0;
        wdata_reg <= 0;
        bvalid_reg <= 0;
        bresp_reg <= 0;
        tx_enable_reg <= `DIFI_CFG_DEFAULT_TX_ENABLE;
        context_change_pending_reg <= `DIFI_CFG_DEFAULT_CTX_PENDING;
        cfg_commit_req_reg <= `DIFI_CFG_DEFAULT_COMMIT_REQ;
        last_commit_error_reg <= `DIFI_CFG_DEFAULT_COMMIT_ERROR;
        rx_filter_ctrl_reg <= `DIFI_CFG_DEFAULT_RX_FILTER_CTRL;
        rx_expected_data_sid_reg <= `DIFI_CFG_DEFAULT_RX_DATA_SID;
        rx_expected_version_sid_reg <= `DIFI_CFG_DEFAULT_RX_VERSION_SID;
        shadow_data_sid <= `DIFI_CFG_DEFAULT_DATA_SID;
        shadow_version_sid <= `DIFI_CFG_DEFAULT_VERSION_SID;
        shadow_samples <= `DIFI_CFG_DEFAULT_SAMPLES;
        shadow_sample_rate <= `DIFI_CFG_DEFAULT_SAMPLE_RATE;
        shadow_bandwidth <= `DIFI_CFG_DEFAULT_BANDWIDTH;
        shadow_rf_freq <= `DIFI_CFG_DEFAULT_RF_FREQ;
        shadow_context_period <= `DIFI_CFG_DEFAULT_CTX_PERIOD;
        shadow_version_period <= `DIFI_CFG_DEFAULT_VER_PERIOD;
        active_data_sid <= `DIFI_CFG_DEFAULT_DATA_SID;
        active_version_sid <= `DIFI_CFG_DEFAULT_VERSION_SID;
        active_samples <= `DIFI_CFG_DEFAULT_SAMPLES;
        active_sample_rate <= `DIFI_CFG_DEFAULT_SAMPLE_RATE;
        active_bandwidth <= `DIFI_CFG_DEFAULT_BANDWIDTH;
        active_rf_freq <= `DIFI_CFG_DEFAULT_RF_FREQ;
        active_context_period <= `DIFI_CFG_DEFAULT_CTX_PERIOD;
        active_version_period <= `DIFI_CFG_DEFAULT_VER_PERIOD;
        rdata_reg <= 0;
        rresp_reg <= 0;
        rvalid_reg <= 0;
        

    end

    else
    begin
        case (write_current_state)
        ST_W_COLLECT:
        begin
            if(aw_handshake)
            begin
                aw_pending <= 1;
                awaddr_reg <= s_axi_awaddr; 
            end

            if(w_handshake)
            begin
                w_pending <= 1;
                wstrb_reg <= s_axi_wstrb;
                wdata_reg <= s_axi_wdata;
            end
        end

        ST_W_EXECUTE:
        begin
            case (awaddr_reg)
            // 0x00
            `DIFI_REG_CONTROL:
            begin
                if(wstrb_reg[0])
                begin
                    tx_enable_reg <= wdata_reg[0];
                end

                bresp_reg <= `BRESP_OKAY;
            end

            // 0x04
            `DIFI_REG_COMMAND:
            begin
                if(wstrb_reg[0]&&wdata_reg[0])
                begin
                    if(cfg_commit_req_reg)
                    begin
                        bresp_reg <= `BRESP_SLVERR;
                        last_commit_error_reg <= `DIFI_COMMIT_ERR_BUSY;
                    end

                    else
                    begin
                        if(!(shadow_samples>=1&&shadow_samples<=256))
                        begin
                            bresp_reg <= `BRESP_SLVERR;
                            last_commit_error_reg <= `DIFI_COMMIT_ERR_SAMPLES;
                        end

                        else if(!(shadow_sample_rate!=0))
                        begin
                            bresp_reg <= `BRESP_SLVERR;
                            last_commit_error_reg <= `DIFI_COMMIT_ERR_SAMPLE_RATE;
                        end

                        else if(!((shadow_bandwidth!=0&&shadow_bandwidth<=shadow_sample_rate)))
                        begin
                            bresp_reg <= `BRESP_SLVERR;
                            last_commit_error_reg <= `DIFI_COMMIT_ERR_BANDWIDTH;
                        end

                        else if(!(shadow_rf_freq<=64'd100_000_000_000))
                        begin
                            bresp_reg <= `BRESP_SLVERR;
                            last_commit_error_reg <= `DIFI_COMMIT_ERR_RF_FREQ;
                        end

                        else
                        begin
                            cfg_commit_req_reg <= 1;
                            last_commit_error_reg <= `DIFI_COMMIT_ERR_NONE;
                            bresp_reg <= `BRESP_OKAY;
                        end
                    end
                end

                else
                begin
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x08
            `DIFI_REG_STATUS:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x0C
            `DIFI_REG_LAST_COMMIT_ERROR:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x10
            `DIFI_REG_DATA_STREAM_ID:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_data_sid <= apply_wstrb(shadow_data_sid,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x14
            `DIFI_REG_VERSION_STREAM_ID:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_version_sid <= apply_wstrb(shadow_version_sid,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x18
            `DIFI_REG_SAMPLES_PER_PACKET:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_samples <= apply_wstrb(shadow_samples,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x1C
            `DIFI_REG_SAMPLE_RATE_HZ:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_sample_rate <= apply_wstrb(shadow_sample_rate,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x20
            `DIFI_REG_BANDWIDTH_HZ:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_bandwidth <= apply_wstrb(shadow_bandwidth,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x24
            `DIFI_REG_RF_FREQ_LOW:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_rf_freq[31:0] <= apply_wstrb(shadow_rf_freq[31:0],wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x28
            `DIFI_REG_RF_FREQ_HIGH:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_rf_freq[63:32] <= apply_wstrb(shadow_rf_freq[63:32],wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x2C
            `DIFI_REG_CONTEXT_PERIOD_MS:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_context_period <= apply_wstrb(shadow_context_period,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x30
            `DIFI_REG_VERSION_PERIOD_MS:
            begin
                if(cfg_commit_req_reg)
                begin
                    bresp_reg <= `BRESP_SLVERR;
                end

                else
                begin
                    shadow_version_period <= apply_wstrb(shadow_version_period,wdata_reg,wstrb_reg);
                    bresp_reg <= `BRESP_OKAY;
                end
            end

            // 0x34
            `DIFI_REG_RX_FILTER_CTRL:
            begin
                if(wstrb_reg[0])
                begin
                    rx_filter_ctrl_reg <= wdata_reg[1:0];
                end

                bresp_reg <= `BRESP_OKAY;
            end

            // 0x38
            `DIFI_REG_RX_DATA_SID:
            begin
                rx_expected_data_sid_reg <= apply_wstrb(rx_expected_data_sid_reg,wdata_reg,wstrb_reg);
                bresp_reg <= `BRESP_OKAY;
            end

            // 0x3C
            `DIFI_REG_RX_VERSION_SID:
            begin
                rx_expected_version_sid_reg <= apply_wstrb(rx_expected_version_sid_reg,wdata_reg,wstrb_reg);
                bresp_reg <= `BRESP_OKAY;
            end

            // 0x40
            `DIFI_REG_ACTIVE_DATA_SID:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x44
            `DIFI_REG_ACTIVE_VERSION_SID:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x48
            `DIFI_REG_ACTIVE_SAMPLES:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x4C
            `DIFI_REG_ACTIVE_SAMPLE_RATE:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x50
            `DIFI_REG_ACTIVE_BANDWIDTH:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x54
            `DIFI_REG_ACTIVE_RF_LOW:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x58
            `DIFI_REG_ACTIVE_RF_HIGH:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x5C
            `DIFI_REG_ACTIVE_CTX_PERIOD:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            // 0x60
            `DIFI_REG_ACTIVE_VER_PERIOD:
            begin
                bresp_reg <= `BRESP_SLVERR;
            end

            default:
            begin
                bresp_reg <= `BRESP_DECERR;
            end
            endcase
        end

        ST_W_RESPONSE:
        begin
            if(!bvalid_reg)
            begin
                bvalid_reg <= 1;
            end
        end

        default:
        begin
            
        end
        endcase

        case (read_current_state)
        ST_R_IDLE:
        begin
            if(ar_handshake)
            begin
                case (s_axi_araddr)
                // 0x00
                `DIFI_REG_CONTROL:
                begin
                    rdata_reg <= {31'd0, tx_enable_reg};
                    rresp_reg <= `RRESP_OKAY;

                end

                // 0x04
                `DIFI_REG_COMMAND:
                begin
                    rdata_reg <= 0;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x08
                `DIFI_REG_STATUS:
                begin
                    rdata_reg <= {26'd0,(last_commit_error_reg!=0),time_valid,tx_enable_reg,tx_busy,context_change_pending_reg,cfg_commit_req_reg};
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x0C
                `DIFI_REG_LAST_COMMIT_ERROR:
                begin
                    rdata_reg <= last_commit_error_reg;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x10
                `DIFI_REG_DATA_STREAM_ID:
                begin
                    rdata_reg <= shadow_data_sid;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x14
                `DIFI_REG_VERSION_STREAM_ID:
                begin
                    rdata_reg <= shadow_version_sid;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x18
                `DIFI_REG_SAMPLES_PER_PACKET:
                begin
                    rdata_reg <= {16'd0,shadow_samples};
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x1C
                `DIFI_REG_SAMPLE_RATE_HZ:
                begin
                    rdata_reg <= shadow_sample_rate;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x20
                `DIFI_REG_BANDWIDTH_HZ:
                begin
                    rdata_reg <= shadow_bandwidth;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x24
                `DIFI_REG_RF_FREQ_LOW:
                begin
                    rdata_reg <= shadow_rf_freq[31:0];
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x28
                `DIFI_REG_RF_FREQ_HIGH:
                begin
                    rdata_reg <= shadow_rf_freq[63:32];
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x2C
                `DIFI_REG_CONTEXT_PERIOD_MS:
                begin
                    rdata_reg <= shadow_context_period;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x30
                `DIFI_REG_VERSION_PERIOD_MS:
                begin
                    rdata_reg <= shadow_version_period;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x34
                `DIFI_REG_RX_FILTER_CTRL:
                begin
                    rdata_reg <= {30'd0,rx_filter_ctrl_reg[1:0]};
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x38
                `DIFI_REG_RX_DATA_SID:
                begin
                    rdata_reg <= rx_expected_data_sid_reg;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x3C
                `DIFI_REG_RX_VERSION_SID:
                begin
                    rdata_reg <= rx_expected_version_sid_reg;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x40
                `DIFI_REG_ACTIVE_DATA_SID:
                begin
                    rdata_reg <= active_data_sid;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x44
                `DIFI_REG_ACTIVE_VERSION_SID:
                begin
                    rdata_reg <= active_version_sid;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x48
                `DIFI_REG_ACTIVE_SAMPLES:
                begin
                    rdata_reg <= {16'd0,active_samples};
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x4C
                `DIFI_REG_ACTIVE_SAMPLE_RATE:
                begin
                    rdata_reg <= active_sample_rate;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x50
                `DIFI_REG_ACTIVE_BANDWIDTH:
                begin
                    rdata_reg <= active_bandwidth;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x54
                `DIFI_REG_ACTIVE_RF_LOW:
                begin
                    rdata_reg <= active_rf_freq[31:0];
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x58
                `DIFI_REG_ACTIVE_RF_HIGH:
                begin
                    rdata_reg <= active_rf_freq[63:32];
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x5C
                `DIFI_REG_ACTIVE_CTX_PERIOD:
                begin
                    rdata_reg <= active_context_period;
                    rresp_reg <= `RRESP_OKAY;
                end

                // 0x60
                `DIFI_REG_ACTIVE_VER_PERIOD:
                begin
                    rdata_reg <= active_version_period;
                    rresp_reg <= `RRESP_OKAY;
                end

                default:
                begin
                    rresp_reg <= `RRESP_DECERR;
                    rdata_reg <= 32'd0;
                end
                endcase
            end
        end

        ST_R_RESPONSE:
        begin
            if(!rvalid_reg)
            begin
                rvalid_reg <= 1;
            end
        end

        default:
        begin
            
        end
        endcase

        if(context_change_done)
        begin
            context_change_pending_reg <= 0;
        end

        if(cfg_commit_ack&&cfg_commit_req_reg)
        begin
            cfg_commit_req_reg <= 0;
            context_change_pending_reg <= 1;
            active_data_sid <= shadow_data_sid;
            active_version_sid <= shadow_version_sid;
            active_samples <= shadow_samples;
            active_sample_rate <= shadow_sample_rate;
            active_bandwidth <= shadow_bandwidth;
            active_rf_freq <= shadow_rf_freq;
            active_context_period <= shadow_context_period;
            active_version_period <= shadow_version_period;
        end

        if(r_handshake)
        begin
            rvalid_reg <= 0;
        end

        if(b_handshake)
        begin
            bvalid_reg <= 0;
            aw_pending<= 0;
            w_pending <= 0;
        end
    end
end

endmodule
