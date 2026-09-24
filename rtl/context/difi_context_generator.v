`include "../include/difi_v1_1_defs.vh"
module difi_context_generator (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        pkt_start,
    output reg         pkt_busy,
    output reg         pkt_done,

    input  wire [31:0] cfg_data_stream_id,
    input  wire [31:0] cfg_sample_rate_hz,
    input  wire [31:0] cfg_bandwidth_hz,
    input  wire [63:0] cfg_rf_freq_hz,

    input  wire        cfg_context_change_pending,
    output reg         context_change_done,

    input  wire [31:0] time_sec,
    input  wire [63:0] time_ps,
    input  wire        time_valid,

    output reg  [31:0] m_axis_pkt_tdata,
    output reg         m_axis_pkt_tvalid,
    input  wire        m_axis_pkt_tready,
    output wire [3:0]  m_axis_pkt_tkeep,
    output reg         m_axis_pkt_tlast
);

// FSM State Definition
reg current_state;
reg next_state;

localparam ST_IDLE = 1'b0;
localparam ST_SEND = 1'b1;

// Handshake
wire m_axis_handshake;
assign m_axis_handshake = m_axis_pkt_tvalid & m_axis_pkt_tready;

// Tkeep
assign m_axis_pkt_tkeep = 4'b1111;

// Counter
reg [3:0] context_seq;
reg [4:0] word_count;

// Snapshot
reg [31:0] snapshot_cfg_data_stream_id; // Word1
reg [31:0] snapshot_cfg_sample_rate_hz;
reg [31:0] snapshot_cfg_bandwidth_hz;
reg [31:0] snapshot_cfg_rf_freq_h_hz;
reg [31:0] snapshot_cfg_rf_freq_l_hz;
reg snapshot_cfg_context_change_pending;
reg [31:0] snapshot_time_sec; // Word4
reg [31:0] snapshot_time_h_ps; // Word5
reg [31:0] snapshot_time_l_ps; // Word6

// Segment
wire [31:0] header; // Word0
wire [31:0] cif0; // Word7
wire [63:0] bw_raw; // Word9-10
wire [63:0] rf_raw; // Word13-14
wire [63:0] fs_raw; // Word19-20
assign header = `DIFI_CONTEXT_HEADER_BASE | ({28'd0, context_seq} << 16);
assign cif0 = 
    snapshot_cfg_context_change_pending ? 
    `DIFI_CONTEXT_CIF_CHANGED : `DIFI_CONTEXT_CIF_NO_CHANGE;
assign bw_raw = {32'd0, snapshot_cfg_bandwidth_hz} << 20;
assign rf_raw = {snapshot_cfg_rf_freq_h_hz,snapshot_cfg_rf_freq_l_hz} << 20;
assign fs_raw = {32'd0, snapshot_cfg_sample_rate_hz} << 20;


// ------------------------------------------------------------------
// 1. State register
// ------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        current_state <= ST_IDLE;
    end

    else
    begin
        current_state <= next_state;
    end
end


// ------------------------------------------------------------------
// 2. Next-state logic
// ------------------------------------------------------------------
always @(*) 
begin
    next_state = current_state;

    case (current_state)
    ST_IDLE:
    begin
        if(pkt_start&&time_valid)
        begin
            next_state = ST_SEND;
        end
    end

    ST_SEND:
    begin
        if(m_axis_handshake&&m_axis_pkt_tlast)
        begin
            next_state = ST_IDLE;
        end
    end

    default:
    begin
        next_state = ST_IDLE;
    end
    endcase
end


// ------------------------------------------------------------------
// 3. Combinational block
// ------------------------------------------------------------------
always @(*) 
begin
    pkt_busy = 0;
    m_axis_pkt_tvalid = 0;
    m_axis_pkt_tdata = 0;
    m_axis_pkt_tlast = 0;

    case (current_state)
    ST_SEND:
    begin
        pkt_busy = 1;

        if(word_count==26)
        begin
            m_axis_pkt_tlast = 1;
        end

        case (word_count)
        5'd0:
        begin
            m_axis_pkt_tdata = header;
            m_axis_pkt_tvalid = 1;
        end

        5'd1:
        begin
            m_axis_pkt_tdata = snapshot_cfg_data_stream_id;
            m_axis_pkt_tvalid = 1;
        end

        5'd2:
        begin
            m_axis_pkt_tdata = `DIFI_OUI_WORD;
            m_axis_pkt_tvalid = 1;
        end

        5'd3:
        begin
            m_axis_pkt_tdata = `DIFI_CONTEXT_CLASS_WORD;
            m_axis_pkt_tvalid = 1;
        end

        5'd4:
        begin
            m_axis_pkt_tdata = snapshot_time_sec;
            m_axis_pkt_tvalid = 1;
        end

        5'd5:
        begin
            m_axis_pkt_tdata = snapshot_time_h_ps;
            m_axis_pkt_tvalid = 1;
        end

        5'd6:
        begin
            m_axis_pkt_tdata = snapshot_time_l_ps;
            m_axis_pkt_tvalid = 1;
        end

        5'd7:
        begin
            m_axis_pkt_tdata = cif0;
            m_axis_pkt_tvalid = 1;
        end

        5'd8:
        begin
            m_axis_pkt_tdata = `DIFI_CONTEXT_REF_POINT;
            m_axis_pkt_tvalid = 1;
        end

        5'd9:
        begin
            m_axis_pkt_tdata = bw_raw[63:32];
            m_axis_pkt_tvalid = 1;
        end

        5'd10:
        begin
            m_axis_pkt_tdata = bw_raw[31:0];
            m_axis_pkt_tvalid = 1;
        end

        5'd13:
        begin
            m_axis_pkt_tdata = rf_raw[63:32];
            m_axis_pkt_tvalid = 1;
        end

        5'd14:
        begin
            m_axis_pkt_tdata = rf_raw[31:0];
            m_axis_pkt_tvalid = 1;
        end

        5'd19:
        begin
            m_axis_pkt_tdata = fs_raw[63:32];
            m_axis_pkt_tvalid = 1;
        end

        5'd20:
        begin
            m_axis_pkt_tdata = fs_raw[31:0];
            m_axis_pkt_tvalid = 1;
        end

        5'd25:
        begin
            m_axis_pkt_tdata = `DIFI_CONTEXT_DPF_WORD0;
            m_axis_pkt_tvalid = 1;
        end

        5'd26:
        begin
            m_axis_pkt_tdata = `DIFI_CONTEXT_DPF_WORD1;
            m_axis_pkt_tvalid = 1;
        end

        default:
        begin
            if(word_count>5'd26)
            begin
                m_axis_pkt_tdata = 0;
                m_axis_pkt_tvalid = 0;
            end

            else
            begin
                m_axis_pkt_tdata = `DIFI_ZERO_WORD;
                m_axis_pkt_tvalid = 1;
            end
        end
        endcase
    end

    default:
    begin
        
    end
    endcase
end


// ------------------------------------------------------------------
// 4. Snapshot storage , Update/Reset counter
// ------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        snapshot_time_sec <= 0;
        snapshot_time_h_ps <= 0;
        snapshot_time_l_ps <= 0;
        snapshot_cfg_data_stream_id <= 0;
        snapshot_cfg_sample_rate_hz <= 0;
        snapshot_cfg_bandwidth_hz <= 0;
        snapshot_cfg_rf_freq_h_hz <= 0;
        snapshot_cfg_rf_freq_l_hz <= 0;
        snapshot_cfg_context_change_pending <= 0;
        context_seq <= 0;
        word_count <= 0;
        context_change_done <= 0;
        pkt_done <= 0;
    end

    else
    begin
        context_change_done <= 0;
        pkt_done <= 0;

        case (current_state)
        ST_IDLE:
        begin
            if(pkt_start&&time_valid)
            begin
                snapshot_cfg_data_stream_id <= cfg_data_stream_id;
                snapshot_cfg_sample_rate_hz <= cfg_sample_rate_hz;
                snapshot_cfg_bandwidth_hz <= cfg_bandwidth_hz;
                snapshot_cfg_rf_freq_h_hz <= cfg_rf_freq_hz[63:32];
                snapshot_cfg_rf_freq_l_hz <= cfg_rf_freq_hz[31:0];
                snapshot_cfg_context_change_pending <= cfg_context_change_pending;
                snapshot_time_sec <= time_sec;
                snapshot_time_h_ps <= time_ps[63:32];
                snapshot_time_l_ps <= time_ps[31:0];
            end
        end

        ST_SEND:
        begin
            if(m_axis_handshake)
            begin
                if(!m_axis_pkt_tlast)
                begin
                    word_count <= word_count + 1;
                end

                else
                begin
                    if(snapshot_cfg_context_change_pending)
                    begin
                        context_change_done <= 1;
                    end

                    word_count <= 0;
                    context_seq <= context_seq + 1;
                    pkt_done <= 1;
                end
            end
        end

        default:
        begin
            
        end
        endcase
    end
end
endmodule