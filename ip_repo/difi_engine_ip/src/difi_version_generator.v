`include "difi_v1_1_defs.vh"

module difi_version_generator #(
    parameter [6:0] BUILD_YEAR_OFFSET = 7'd26,
    parameter [8:0] BUILD_DAY_OF_YEAR = 9'd252
) (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        pkt_start,
    output reg         pkt_busy,
    output reg         pkt_done,

    input  wire [31:0] cfg_version_stream_id,

    input  wire [31:0] time_sec,
    input  wire [63:0] time_ps,
    input  wire        time_valid,

    output reg  [31:0] m_axis_pkt_tdata,
    output reg         m_axis_pkt_tvalid,
    input  wire        m_axis_pkt_tready,
    output wire [3:0]  m_axis_pkt_tkeep,
    output reg         m_axis_pkt_tlast
);


// Tkeep
assign m_axis_pkt_tkeep = 4'b1111;

// FSM State Definition
reg current_state;
reg next_state;
localparam ST_IDLE = 1'b0;
localparam ST_SEND = 1'b1;

// Handshake
wire m_axis_handshake;
assign m_axis_handshake = m_axis_pkt_tvalid & m_axis_pkt_tready;

// Counter
reg [3:0] version_seq;
reg [4:0] word_count;

// Snapshot
reg [31:0] snapshot_cfg_version_stream_id; // Word1
reg [31:0] snapshot_time_sec; // Word4
reg [31:0] snapshot_time_h_ps; // Word5
reg [31:0] snapshot_time_l_ps; // Word6

// Segment
wire [31:0] header; // Word0
wire [31:0] cif0; // Word7
wire [31:0] version_info; // Word10
reg first_version_sent;
assign header = `DIFI_VERSION_HEADER_BASE | ({28'd0, version_seq} << 16);
assign cif0 = 
    first_version_sent ? 
    `DIFI_VERSION_CIF_NO_CHANGE : `DIFI_VERSION_CIF_CHANGED;
assign version_info = 
    {BUILD_YEAR_OFFSET,
    BUILD_DAY_OF_YEAR,
    `DIFI_VERSION_REVISION,
    `DIFI_VERSION_TYPE,
    `DIFI_VERSION_ICD_VERSION};


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

        if(word_count==`DIFI_VERSION_LAST_WORD)
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
            m_axis_pkt_tdata = snapshot_cfg_version_stream_id;
            m_axis_pkt_tvalid = 1;
        end

        5'd2:
        begin
            m_axis_pkt_tdata = `DIFI_OUI_WORD;
            m_axis_pkt_tvalid = 1;
        end

        5'd3:
        begin
            m_axis_pkt_tdata = `DIFI_VERSION_CLASS_WORD;
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
            m_axis_pkt_tdata = `DIFI_VERSION_CIF1_WORD;
            m_axis_pkt_tvalid = 1;
        end

        5'd9:
        begin
            m_axis_pkt_tdata = `DIFI_VERSION_V49_SPEC_WORD;
            m_axis_pkt_tvalid = 1;
        end

        5'd10:
        begin
            m_axis_pkt_tdata = version_info;
            m_axis_pkt_tvalid = 1;
        end

        default:
        begin
            m_axis_pkt_tvalid = 0;
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
        snapshot_cfg_version_stream_id <= 0;
        version_seq <= 0;
        word_count <= 0;
        first_version_sent <= 0;
        pkt_done <= 0;
    end

    else
    begin
        pkt_done <= 0;

        case (current_state)
        ST_IDLE:
        begin
            if(pkt_start&&time_valid)
            begin
                snapshot_cfg_version_stream_id <= cfg_version_stream_id;
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
                    word_count <= 0;
                    version_seq <= version_seq + 1;
                    pkt_done <= 1;
                    first_version_sent <= 1;
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