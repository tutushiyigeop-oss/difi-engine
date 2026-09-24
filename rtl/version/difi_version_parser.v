`include "../include/difi_v1_1_defs.vh"

module difi_version_parser (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axis_pkt_tdata,
    input  wire        s_axis_pkt_tvalid,
    output reg         s_axis_pkt_tready,
    input  wire [3:0]  s_axis_pkt_tkeep,
    input  wire        s_axis_pkt_tlast,

    input  wire        cfg_stream_filter_enable,
    input  wire [31:0] cfg_expected_stream_id,

    output reg         m_ver_valid,
    input  wire        m_ver_ready,
    output reg  [31:0] m_ver_stream_id,
    output reg  [3:0]  m_ver_seq,
    output reg  [31:0] m_ver_time_sec,
    output reg  [63:0] m_ver_time_ps,
    output reg         m_ver_changed,
    output reg  [31:0] m_ver_info,

    output reg         error_valid,
    output reg  [3:0]  error_code
);


// FSM State Defination
reg [1:0] current_state;
reg [1:0] next_state;
localparam ST_IDLE = 2'd0;
localparam ST_RECV = 2'd1;
localparam ST_DROP = 2'd2;
localparam ST_META = 2'd3;


// Handshake
wire s_axis_handshake;
wire m_ver_handshake;
assign s_axis_handshake = s_axis_pkt_tvalid & s_axis_pkt_tready;
assign m_ver_handshake = m_ver_valid & m_ver_ready;


// Counter
reg [3:0] word_count;


// Snapshot & Temp
reg [3:0] snapshot_pkt_seq;
reg snapshot_stream_filter_enable;
reg [31:0] snapshot_expected_stream_id;
reg [31:0] snapshot_received_stream_id;
reg [31:0] snapshot_m_ver_time_sec;
reg [63:0] snapshot_m_ver_time_ps;
reg [31:0] snapshot_m_ver_info;
reg temp_m_ver_changed;


// Tkeep Error
wire tkeep_error;
assign tkeep_error =
    s_axis_handshake&&
    (s_axis_pkt_tkeep!=4'b1111);


// Word0 Packet Type Error
wire word0_type_error;
assign word0_type_error = 
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata[31:28]!=`DIFI_VERSION_PKT_TYPE);


// Word0 Fixed Header fields Error
wire word0_header_error;
assign word0_header_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    ((s_axis_pkt_tdata[27]!=`DIFI_CLASS_ID_PRESENT)||
    (s_axis_pkt_tdata[26:25]!=`DIFI_PROFILE_BITS)||
    (s_axis_pkt_tdata[24]!=`DIFI_VERSION_TSM)||
    (s_axis_pkt_tdata[23:22]!=`DIFI_TSI_UTC)||
    (s_axis_pkt_tdata[21:20]!=`DIFI_TSF_REALTIME_PS));


// Word0 Packet Size Error
wire word0_size_error;
assign word0_size_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata[15:0]!=`DIFI_VERSION_PKT_WORDS);


// Word0 TLAST Error
wire word0_tlast_error;
assign word0_tlast_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    s_axis_pkt_tlast;


// Overall Word0 Error
wire word0_error;
assign word0_error =
    (current_state==ST_IDLE)&&
    (word0_type_error||
    word0_header_error||
    word0_size_error||
    word0_tlast_error||
    tkeep_error);


// Word0 Accept
wire word0_accept;
assign word0_accept =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    !word0_error;


// Word1 Stream ID Mismatch
wire word1_error;
assign word1_error =
    (current_state==ST_RECV)&&
    (word_count==4'd1)&&
    s_axis_handshake&&
    snapshot_stream_filter_enable&&
    (s_axis_pkt_tdata!=snapshot_expected_stream_id);


// Invalid OUI, ICC, or PCC (Word2-3)
wire word2_error;
wire word3_error;
assign word2_error =
    (current_state==ST_RECV)&&
    (word_count==4'd2)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_OUI_WORD);
assign word3_error =
    (current_state==ST_RECV)&&
    (word_count==4'd3)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_VERSION_CLASS_WORD);


// Invalid Fractional Timestamp
wire version_value_error;
assign version_value_error =
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    (word_count==`DIFI_VERSION_LAST_WORD)&&
    (snapshot_m_ver_time_ps>=64'd1000000000000);


// Invalid CIF0 (Word7)
wire word7_error;
assign word7_error =
    (current_state==ST_RECV)&&
    (word_count==4'd7)&&
    ((s_axis_pkt_tdata!=`DIFI_VERSION_CIF_CHANGED)&&(s_axis_pkt_tdata!=`DIFI_VERSION_CIF_NO_CHANGE))&&
    s_axis_handshake;


// Invalid CIF1 (Word8)
wire word8_error;
assign word8_error =
    (current_state==ST_RECV)&&
    (word_count==4'd8)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_VERSION_CIF1_WORD);


// Invalid V49 Spec Version (Word9)
wire word9_error;
assign word9_error =
    (current_state==ST_RECV)&&
    (word_count==4'd9)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_VERSION_V49_SPEC_WORD);


// Invalid Version Information (Word10)
wire word10_error;
assign word10_error =
    (current_state==ST_RECV)&&
    (word_count==4'd10)&&
    s_axis_handshake&&
    ((!(s_axis_pkt_tdata[24:16]>=9'd1&&s_axis_pkt_tdata[24:16]<=9'd366))||
    (s_axis_pkt_tdata[15:10]!=`DIFI_VERSION_REVISION)||
    (s_axis_pkt_tdata[9:6]!=`DIFI_VERSION_TYPE)||
    (s_axis_pkt_tdata[5:0]!=`DIFI_VERSION_ICD_VERSION));


// Truncated Packet Error
wire truncated_packet_error;
assign truncated_packet_error =
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count<`DIFI_VERSION_LAST_WORD);


// Oversized Packet Error
wire oversized_packet_error;
assign oversized_packet_error = 
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    !s_axis_pkt_tlast&&
    (word_count==`DIFI_VERSION_LAST_WORD);


// ST_RECV Error (except "Sequence discontinuity")
wire recv_error;
assign recv_error = 
    word1_error||
    word2_error||
    word3_error||
    tkeep_error||
    word7_error||
    word8_error||
    word9_error||
    word10_error||
    version_value_error||
    truncated_packet_error||
    oversized_packet_error;


// ST_RECV No Error (except "Sequence discontinuity")
wire recv_no_error;
assign recv_no_error =
    (current_state==ST_RECV)&&
    (!recv_error)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count==`DIFI_VERSION_LAST_WORD);


// Sequence discontinuity (report only, do not discard)
reg base_active;
reg [31:0] base_stream_id;
reg [3:0] base_seq_num;
wire [3:0] expect_seq_num;
wire seq_discontinuity_error;
assign expect_seq_num = base_seq_num + 4'd1;
assign seq_discontinuity_error =
    recv_no_error&&
    base_active&&
    (snapshot_received_stream_id==base_stream_id)&&
    (snapshot_pkt_seq!=expect_seq_num);


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
// 2. Next-state logic and packet-boundary recovery
// ------------------------------------------------------------------
always @(*) 
begin
    next_state = current_state;

    case (current_state)
    ST_IDLE:
    begin
        if(word0_error)
        begin
            if(word0_tlast_error)
            begin
                next_state = ST_IDLE;
            end

            else
            begin
                next_state = ST_DROP;
            end
        end

        if(word0_accept)
        begin
            next_state = ST_RECV;
        end
    end

    ST_RECV:
    begin
        if(recv_error)
        begin
            if(s_axis_pkt_tlast)
            begin
                next_state = ST_IDLE;
            end
            
            else
            begin
                next_state = ST_DROP;
            end     
        end

        else if(recv_no_error)
        begin
            next_state = ST_META;
        end
    end

    ST_DROP:
    begin
        if(s_axis_pkt_tlast&&s_axis_handshake)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_META:
    begin
        if(m_ver_handshake)
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
// 3. Combinational ready/valid, metadata, and IQ outputs
// ------------------------------------------------------------------
always @(*) 
begin
    s_axis_pkt_tready = 0;
    m_ver_valid = 0;
    m_ver_stream_id = snapshot_received_stream_id;
    m_ver_seq = snapshot_pkt_seq;
    m_ver_time_sec = snapshot_m_ver_time_sec;
    m_ver_time_ps = snapshot_m_ver_time_ps;
    m_ver_changed = temp_m_ver_changed;
    m_ver_info = snapshot_m_ver_info;

    case (current_state)
    ST_IDLE:
    begin
        s_axis_pkt_tready = 1;
    end

    ST_RECV:
    begin
        s_axis_pkt_tready = 1;
    end

    ST_DROP:
    begin
        s_axis_pkt_tready = 1;
    end

    ST_META:
    begin
        m_ver_valid = 1;
    end

    default:
    begin
        
    end
    endcase
end


// ------------------------------------------------------------------
// 4. Snapshot storage, error reporting, and sequence baseline
// ------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        snapshot_stream_filter_enable <= 0;
        snapshot_expected_stream_id <= 0;
        error_valid <= 0;
        error_code <= 0;
        word_count <= 0;
        snapshot_received_stream_id <= 0;
        base_active <= 0;
        snapshot_pkt_seq <= 0;
        base_seq_num <= 0;
        snapshot_m_ver_time_sec <= 0;
        snapshot_m_ver_time_ps <= 0;
        temp_m_ver_changed <= 0;
        base_stream_id <= 0;
        snapshot_m_ver_info <= 0;
    end

    else
    begin
        error_valid <= 0;

        case (current_state)
        ST_IDLE:
        begin
            if(word0_accept)
            begin
                snapshot_pkt_seq <= s_axis_pkt_tdata[19:16];
                snapshot_stream_filter_enable <= cfg_stream_filter_enable;
                snapshot_expected_stream_id <= cfg_expected_stream_id;
            end

            else
            begin

                if(word0_type_error)
                begin
                    error_valid <= 1;
                    error_code <= `DIFI_ERR_UNSUPPORTED_TYPE;
                end

                else if(word0_header_error)
                begin
                    error_valid <= 1;
                    error_code <= `DIFI_ERR_HEADER;
                end

                else if(word0_tlast_error)
                begin
                    error_valid <= 1;
                    error_code <= `DIFI_ERR_TRUNCATED;
                end

                else if(word0_size_error||tkeep_error)
                begin
                    error_valid <= 1;
                    error_code <= `DIFI_ERR_SIZE;
                end
            end
        end

        ST_RECV:
        begin
            if(s_axis_handshake)
            begin
                if(!recv_error)
                begin
                    case (word_count)
                    4'd1:
                    begin
                        snapshot_received_stream_id <= s_axis_pkt_tdata;
                    end

                    4'd4:
                    begin
                        snapshot_m_ver_time_sec <= s_axis_pkt_tdata;
                    end

                    4'd5:
                    begin
                        snapshot_m_ver_time_ps[63:32] <= s_axis_pkt_tdata;
                    end

                    4'd6:
                    begin
                        snapshot_m_ver_time_ps[31:0] <= s_axis_pkt_tdata;
                    end

                    4'd7:
                    begin
                        if(s_axis_pkt_tdata==`DIFI_VERSION_CIF_CHANGED)
                        begin
                            temp_m_ver_changed <= 1;
                        end

                        if(s_axis_pkt_tdata==`DIFI_VERSION_CIF_NO_CHANGE)
                        begin
                            temp_m_ver_changed <= 0;
                        end
                    end

                    4'd10:
                    begin
                        snapshot_m_ver_info <= s_axis_pkt_tdata;
                    end

                    default:
                    begin

                    end
                    endcase
                end
            end


            if(truncated_packet_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_TRUNCATED;
            end
        
            else if(oversized_packet_error||tkeep_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_SIZE;
            end

            else if(word2_error||word3_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_CLASS;
            end

            else if(word1_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_STREAM_ID;
            end

            else if(word10_error || word9_error || word8_error || word7_error || version_value_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_VERSION_FIELD;
            end

            else if(seq_discontinuity_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_SEQ;
            end
        end

        default:
        begin
            
        end
        endcase

        if(s_axis_handshake)
        begin
            if(s_axis_pkt_tlast==0)
            begin
                word_count <= word_count + 1;
            end

            if(s_axis_pkt_tlast==1)
            begin
                word_count <= 0;
            end
        end

        if(recv_no_error)
        begin
            base_active <= 1;
            base_seq_num <= snapshot_pkt_seq;
            base_stream_id <= snapshot_received_stream_id;
        end
    end
end

endmodule