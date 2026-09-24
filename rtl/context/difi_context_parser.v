`include "../include/difi_v1_1_defs.vh"
module difi_context_parser (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axis_pkt_tdata,
    input  wire        s_axis_pkt_tvalid,
    output reg         s_axis_pkt_tready,
    input  wire [3:0]  s_axis_pkt_tkeep,
    input  wire        s_axis_pkt_tlast,

    input  wire        cfg_stream_filter_enable,
    input  wire [31:0] cfg_expected_stream_id,

    output reg         m_ctx_valid,
    input  wire        m_ctx_ready,

    output reg  [31:0] m_ctx_stream_id,
    output reg  [3:0]  m_ctx_seq,
    output reg  [31:0] m_ctx_time_sec,
    output reg  [63:0] m_ctx_time_ps,
    output reg         m_ctx_changed,
    output reg  [31:0] m_ctx_bandwidth_hz,
    output reg  [63:0] m_ctx_rf_freq_hz,
    output reg  [31:0] m_ctx_sample_rate_hz,


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
wire m_ctx_handshake;
assign s_axis_handshake = s_axis_pkt_tvalid & s_axis_pkt_tready;
assign m_ctx_handshake = m_ctx_valid & m_ctx_ready;

// Counter
reg [4:0] word_count;

// Snapshot & Temp
reg [3:0] snapshot_pkt_seq;
reg snapshot_stream_filter_enable;
reg [31:0] snapshot_expected_stream_id;
reg [31:0] snapshot_received_stream_id;
reg [31:0] snapshot_m_ctx_time_sec;
reg [63:0] snapshot_m_ctx_time_ps;
wire [31:0] temp_m_ctx_bandwidth_hz;
wire [63:0] temp_m_ctx_rf_freq_hz;
wire [31:0] temp_m_ctx_sample_rate_hz;
reg temp_m_ctx_changed;
reg [63:0] bw_raw;
reg [63:0] rf_raw;
reg [63:0] fs_raw;
assign temp_m_ctx_bandwidth_hz = bw_raw >> 20;
assign temp_m_ctx_rf_freq_hz = rf_raw >> 20;
assign temp_m_ctx_sample_rate_hz = fs_raw >> 20;

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
    (s_axis_pkt_tdata[31:28]!=`DIFI_CONTEXT_PKT_TYPE);

// Word0 Fixed Header fields Error
wire word0_header_error;
assign word0_header_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    ((s_axis_pkt_tdata[27]!=`DIFI_CLASS_ID_PRESENT)||
    (s_axis_pkt_tdata[26:25]!=`DIFI_PROFILE_BITS)||
    (s_axis_pkt_tdata[24]!=`DIFI_CONTEXT_TSM)||
    (s_axis_pkt_tdata[23:22]!=`DIFI_TSI_UTC)||
    (s_axis_pkt_tdata[21:20]!=`DIFI_TSF_REALTIME_PS));

// Word0 Packet Size Error
wire word0_size_error;
assign word0_size_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata[15:0]!=`DIFI_CONTEXT_PKT_WORDS);

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
    (word_count==5'd1)&&
    s_axis_handshake&&
    snapshot_stream_filter_enable&&
    (s_axis_pkt_tdata!=snapshot_expected_stream_id);

// Invalid OUI, ICC, or PCC (Word2-3)
wire word2_error;
wire word3_error;
assign word2_error =
    (current_state==ST_RECV)&&
    (word_count==5'd2)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_OUI_WORD);
assign word3_error =
    (current_state==ST_RECV)&&
    (word_count==5'd3)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_CONTEXT_CLASS_WORD);

// Context Specific Segment Error
wire wordspe_error;
assign wordspe_error = 
    ((current_state==ST_RECV)&&(s_axis_handshake))&&
    (((word_count==5'd7)&&(s_axis_pkt_tdata!=`DIFI_CONTEXT_CIF_CHANGED)&&(s_axis_pkt_tdata!=`DIFI_CONTEXT_CIF_NO_CHANGE))||
    ((word_count==5'd8)&&(s_axis_pkt_tdata!=`DIFI_CONTEXT_REF_POINT))||
    ((word_count==5'd25)&&(s_axis_pkt_tdata!=`DIFI_CONTEXT_DPF_WORD0))||
    ((word_count==5'd26)&&(s_axis_pkt_tdata!=`DIFI_CONTEXT_DPF_WORD1))||
    (((word_count>=5'd11&&word_count<=5'd12)||(word_count>=5'd15&&word_count<=5'd18)||(word_count>=5'd21&&word_count<=5'd24))&&(s_axis_pkt_tdata!=`DIFI_ZERO_WORD)));

// Context Value Error
wire context_value_error;
assign context_value_error =
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    (word_count==`DIFI_CONTEXT_LAST_WORD)&&
    ((snapshot_m_ctx_time_ps >= 64'd1000000000000)||
    (bw_raw[19:0]!=20'd0)||
    (fs_raw[19:0]!=20'd0)||
    (rf_raw[19:0]!=20'd0)||
    ((bw_raw>>20)>64'h0000_0000_FFFF_FFFF)||
    ((fs_raw>>20)>64'h0000_0000_FFFF_FFFF)||
    ((bw_raw>>20)==0)||
    ((fs_raw>>20)==0)||
    (bw_raw>fs_raw)||
    rf_raw[63]||
    ((rf_raw>>20)>64'd100000000000));

// Truncated Packet Error
wire truncated_packet_error;
assign truncated_packet_error =
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count<`DIFI_CONTEXT_LAST_WORD);

// Oversized Packet Error
wire oversized_packet_error;
assign oversized_packet_error = 
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    !s_axis_pkt_tlast&&
    (word_count==`DIFI_CONTEXT_LAST_WORD);

// ST_RECV Error (except "Sequence discontinuity")
wire recv_error;
assign recv_error = 
    word1_error||
    word2_error||
    word3_error||
    tkeep_error||
    wordspe_error||
    context_value_error||
    truncated_packet_error||
    oversized_packet_error;

// ST_RECV No Error (except "Sequence discontinuity")
wire recv_no_error;
assign recv_no_error =
    (current_state==ST_RECV)&&
    (!recv_error)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count==`DIFI_CONTEXT_LAST_WORD);

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
        if(m_ctx_handshake)
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
    m_ctx_valid = 0;
    m_ctx_stream_id = snapshot_received_stream_id;
    m_ctx_seq = snapshot_pkt_seq;
    m_ctx_time_sec = snapshot_m_ctx_time_sec;
    m_ctx_time_ps = snapshot_m_ctx_time_ps;
    m_ctx_changed = temp_m_ctx_changed;
    m_ctx_bandwidth_hz = temp_m_ctx_bandwidth_hz;
    m_ctx_rf_freq_hz = temp_m_ctx_rf_freq_hz;
    m_ctx_sample_rate_hz = temp_m_ctx_sample_rate_hz;

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
        m_ctx_valid = 1;
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
        snapshot_m_ctx_time_sec <= 0;
        snapshot_m_ctx_time_ps <= 0;
        temp_m_ctx_changed <= 0;
        bw_raw <= 0;
        rf_raw <= 0;
        fs_raw <= 0;
        base_stream_id <= 0;
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
                    5'd1:
                    begin
                        snapshot_received_stream_id <= s_axis_pkt_tdata;
                    end

                    5'd4:
                    begin
                        snapshot_m_ctx_time_sec <= s_axis_pkt_tdata;
                    end

                    5'd5:
                    begin
                        snapshot_m_ctx_time_ps[63:32] <= s_axis_pkt_tdata;
                    end

                    5'd6:
                    begin
                        snapshot_m_ctx_time_ps[31:0] <= s_axis_pkt_tdata;
                    end

                    5'd7:
                    begin
                        if(s_axis_pkt_tdata==`DIFI_CONTEXT_CIF_CHANGED)
                        begin
                            temp_m_ctx_changed <= 1;
                        end

                        if(s_axis_pkt_tdata==`DIFI_CONTEXT_CIF_NO_CHANGE)
                        begin
                            temp_m_ctx_changed <= 0;
                        end
                    end

                    5'd9:
                    begin
                        bw_raw[63:32] <= s_axis_pkt_tdata;
                    end

                    5'd10:
                    begin
                        bw_raw[31:0] <= s_axis_pkt_tdata;
                    end

                    5'd13:
                    begin
                        rf_raw[63:32] <= s_axis_pkt_tdata;
                    end

                    5'd14:
                    begin
                        rf_raw[31:0] <= s_axis_pkt_tdata;
                    end

                    5'd19:
                    begin
                        fs_raw[63:32] <= s_axis_pkt_tdata;
                    end

                    5'd20:
                    begin
                        fs_raw[31:0] <= s_axis_pkt_tdata;
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

            else if(wordspe_error || context_value_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_CONTEXT_FIELD;
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
