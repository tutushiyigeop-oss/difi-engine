// Data packet: 7 header words followed by IQ.

`include "difi_v1_1_defs.vh"
module difi_data_packetizer (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        pkt_start,
    output reg         pkt_busy,
    output reg         pkt_done,

    input  wire [31:0] s_axis_iq_tdata,
    input  wire        s_axis_iq_tvalid,
    output reg         s_axis_iq_tready,

    input  wire [31:0] cfg_data_stream_id,
    input  wire [15:0] cfg_samples_per_packet,

    input  wire [31:0] time_sec,
    input  wire [63:0] time_ps,
    input  wire        time_valid,

    output reg  [31:0] m_axis_pkt_tdata,
    output reg         m_axis_pkt_tvalid,
    input  wire        m_axis_pkt_tready,
    output wire [3:0]  m_axis_pkt_tkeep,
    output reg         m_axis_pkt_tlast
);

reg [2:0] current_state;
reg [2:0] next_state;
localparam ST_IDLE         = 3'd0;
localparam ST_WAIT_FIRST   = 3'd1;
localparam ST_SEND_HEADER  = 3'd2;
localparam ST_SEND_FIRST   = 3'd3;
localparam ST_SEND_PAYLOAD = 3'd4;

localparam PROLOGUE_WORDS = 3'd7;

wire s_axis_handshake;
wire m_axis_handshake;

reg [31:0] first_sample_reg;
reg [31:0] snapshot_stream_id;

reg [15:0] snapshot_samples;
reg [31:0] snapshot_time_sec;
// Transfer only when both TVALID and TREADY are high.
reg [63:0] snapshot_time_ps;

reg [3:0] pkt_seq;

reg [2:0] header_index;
reg [15:0] sample_index;

assign s_axis_handshake = s_axis_iq_tready & s_axis_iq_tvalid;
assign m_axis_handshake = m_axis_pkt_tready & m_axis_pkt_tvalid;

assign m_axis_pkt_tkeep = 4'b1111;

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

always @(*) 
begin
    next_state = current_state;

    case (current_state)
    ST_IDLE:
    begin

        if(pkt_start)
        begin
            next_state = ST_WAIT_FIRST;
        end
    end

    ST_WAIT_FIRST:
    begin
        if(s_axis_handshake)
        begin
            next_state = ST_SEND_HEADER;
        end
    end
    // Send the header only after receiving the first IQ sample.

    ST_SEND_HEADER:
    begin
        if((header_index==PROLOGUE_WORDS-1)&&m_axis_handshake)
        begin
            next_state = ST_SEND_FIRST;
        end
    end
    
    ST_SEND_FIRST:
    begin
        if(m_axis_handshake&&(snapshot_samples>1))
        begin
            next_state = ST_SEND_PAYLOAD;
        end

        else if(m_axis_handshake&&(snapshot_samples==1))
        begin
            next_state = ST_IDLE;
        end

        else
        begin
            next_state = current_state;
        end
    end

    ST_SEND_PAYLOAD:
    begin
        if((sample_index==snapshot_samples-2)&&m_axis_handshake)
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

always @(*) 
begin
    s_axis_iq_tready = 0;
    pkt_busy = 1;
    m_axis_pkt_tvalid = 0;
    m_axis_pkt_tlast = 0;
    m_axis_pkt_tdata = 32'b0;

    case (current_state)
    ST_IDLE:
    begin
        pkt_busy = 0;
    end

    ST_WAIT_FIRST:
    begin
        s_axis_iq_tready = time_valid;
    end

    ST_SEND_HEADER:
    begin
    // Accept the first sample only when time is valid.
        case (header_index)
        3'd0:
        begin
            m_axis_pkt_tdata = {`DIFI_DATA_PKT_TYPE,`DIFI_CLASS_ID_PRESENT,`DIFI_PROFILE_BITS,`DIFI_DATA_TSM,`DIFI_TSI_UTC,`DIFI_TSF_REALTIME_PS,pkt_seq,snapshot_samples+16'd7};
            m_axis_pkt_tvalid = 1;
    
        end

        3'd1:
        begin
            m_axis_pkt_tdata = snapshot_stream_id;
            m_axis_pkt_tvalid = 1;
        end

        3'd2:
        begin
            m_axis_pkt_tdata = `DIFI_OUI_WORD;
            m_axis_pkt_tvalid = 1;
        end

        3'd3:
        begin
            m_axis_pkt_tdata = `DIFI_DATA_CLASS_WORD;
            m_axis_pkt_tvalid = 1;
        end

        3'd4:
        begin
            m_axis_pkt_tdata = snapshot_time_sec;
            m_axis_pkt_tvalid = 1;
        end

        3'd5:
        begin
            m_axis_pkt_tdata = snapshot_time_ps[63:32];
            m_axis_pkt_tvalid = 1;
        end

        3'd6:
        begin
            m_axis_pkt_tdata = snapshot_time_ps[31:0];
            m_axis_pkt_tvalid = 1;
        end

        default:
        begin
            
        end
        endcase
    end

    ST_SEND_FIRST:
    begin
        m_axis_pkt_tdata = first_sample_reg;
        m_axis_pkt_tvalid = 1;
        if(snapshot_samples==1)
        begin
            m_axis_pkt_tlast = 1;
    
        end
    end

    ST_SEND_PAYLOAD:
    begin
        m_axis_pkt_tdata = s_axis_iq_tdata;
        m_axis_pkt_tvalid = s_axis_iq_tvalid;
        s_axis_iq_tready = m_axis_pkt_tready;
        if(sample_index==snapshot_samples-2)
        begin
    
            m_axis_pkt_tlast = 1;
        end
    end

    default:
    begin

    end
    endcase
end

always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        header_index <= 0;
        sample_index <= 0;
        pkt_done <= 0;

        pkt_seq <= 0;
        first_sample_reg <= 0;
        snapshot_stream_id <= 0;
        snapshot_samples <= 0;
        snapshot_time_sec <= 0;
        snapshot_time_ps <= 0;
    end

    else
    begin
        pkt_done <= 0;

        case (current_state)
        ST_IDLE:
        begin
            header_index <= 0;
            sample_index <= 0;
        
        end

        ST_WAIT_FIRST:
        begin
            if(s_axis_handshake)
            begin
                first_sample_reg <= s_axis_iq_tdata;
                snapshot_stream_id <= cfg_data_stream_id;
                snapshot_samples <= cfg_samples_per_packet;
        
                snapshot_time_sec <= time_sec;
                snapshot_time_ps <= time_ps;
            end
        end

        ST_SEND_HEADER:
        begin
            if(m_axis_handshake)
            begin
                header_index <= header_index + 1;
            end
        end

        ST_SEND_PAYLOAD:
        begin
            if(m_axis_handshake)
            begin
                sample_index <= sample_index + 1;
            end
        end

        default:
        begin
            
        end
        endcase

        // Update the sequence only after the full packet is sent.
        if(m_axis_handshake&&m_axis_pkt_tlast)
        begin
            pkt_done <= 1;
            pkt_seq <= pkt_seq + 1;
        end
    end
end

endmodule
