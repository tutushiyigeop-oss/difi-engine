// Output IQ only after the full packet passes validation.

`include "difi_v1_1_defs.vh"
module difi_data_parser (
    input  wire        aclk,
    input  wire        aresetn,
 
    input  wire [31:0] s_axis_pkt_tdata,
    input  wire        s_axis_pkt_tvalid,
    output reg         s_axis_pkt_tready,
    input  wire [3:0]  s_axis_pkt_tkeep,
    input  wire        s_axis_pkt_tlast,
 
    input  wire        cfg_stream_filter_enable,
    input  wire [31:0] cfg_expected_stream_id,
 
    output reg  [31:0] m_axis_iq_tdata,
    output reg         m_axis_iq_tvalid,
    input  wire        m_axis_iq_tready,
    output reg         m_axis_iq_tlast,
 
    output reg         m_meta_valid,
    input  wire        m_meta_ready,
    output reg  [31:0] m_meta_stream_id,
    output reg  [3:0]  m_meta_seq,
    output reg  [31:0] m_meta_time_sec,
    output reg  [63:0] m_meta_time_ps,
    output reg  [15:0] m_meta_sample_count,
 
    output reg         error_valid,
    output reg  [3:0]  error_code
);
 
reg [2:0] current_state;
reg [2:0] next_state;
localparam ST_IDLE = 3'd0;
localparam ST_RECV = 3'd1;
localparam ST_DROP = 3'd2;
localparam ST_META = 3'd3;
localparam ST_OUTPUT = 3'd4;

wire s_axis_handshake;
wire m_axis_handshake;
wire m_meta_handshake;

assign s_axis_handshake = s_axis_pkt_tvalid & s_axis_pkt_tready;
assign m_axis_handshake = m_axis_iq_tvalid & m_axis_iq_tready;
assign m_meta_handshake = m_meta_valid & m_meta_ready;

reg [8:0] word_count;
// The receive count includes the header; the read pointer counts only IQ.
reg [8:0] payload_rd_ptr;

reg [15:0] packet_size_reg;
reg snapshot_stream_filter_enable;
reg [3:0] snapshot_pkt_seq;
reg [31:0] snapshot_expected_stream_id;
reg [31:0] snapshot_received_stream_id;
reg [31:0] snapshot_time_sec;
reg [31:0] snapshot_time_h_ps;
reg [31:0] snapshot_time_l_ps;
// Buffer the full IQ packet and output it only after validation.
// Use synchronous reads to allow block RAM.
// Do not reset the memory; output only validated data.
(* ram_style = "block" *) reg [31:0] snapshot_payload [0:255];
reg [31:0] payload_q;

wire        payload_wr_en;
wire [7:0]  payload_wr_addr;
wire        payload_rd_en;
wire [7:0]  payload_rd_addr;

wire tkeep_error;

// All 4 bytes of each 32-bit word must be valid.
assign tkeep_error =
    s_axis_handshake&&
    (s_axis_pkt_tkeep!=4'b1111);

wire word0_type_error;

assign word0_type_error = 
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata[31:28]!=`DIFI_DATA_PKT_TYPE);

wire word0_header_error;

assign word0_header_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    ((s_axis_pkt_tdata[27]!=`DIFI_CLASS_ID_PRESENT)||
    (s_axis_pkt_tdata[26:25]!=`DIFI_PROFILE_BITS)||
    (s_axis_pkt_tdata[24]!=`DIFI_DATA_TSM)||
    (s_axis_pkt_tdata[23:22]!=`DIFI_TSI_UTC)||
    (s_axis_pkt_tdata[21:20]!=`DIFI_TSF_REALTIME_PS));

wire word0_size_error;

assign word0_size_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    ((s_axis_pkt_tdata[15:0]<=`DIFI_DATA_PROLOGUE_WORDS)||
    (s_axis_pkt_tdata[15:0]>(`DIFI_DATA_PROLOGUE_WORDS+`DIFI_DATA_MAX_SAMPLES)));

wire word0_tlast_error;

assign word0_tlast_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    s_axis_pkt_tlast;

wire word0_error;

// An invalid first word does not update metadata.
assign word0_error =
    (current_state==ST_IDLE)&&
    (word0_type_error||
    word0_header_error||
    word0_size_error||
    word0_tlast_error||
    tkeep_error);

wire word0_accept;

assign word0_accept =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    !word0_error;

wire word1_error;

assign word1_error =
    (current_state==ST_RECV)&&
    (word_count==9'd1)&&
    s_axis_handshake&&
    snapshot_stream_filter_enable&&
    (s_axis_pkt_tdata!=snapshot_expected_stream_id);

wire word2_error;
wire word3_error;

assign word2_error =
    (current_state==ST_RECV)&&
    (word_count==9'd2)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_OUI_WORD);
assign word3_error =
    (current_state==ST_RECV)&&
    (word_count==9'd3)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata!=`DIFI_DATA_CLASS_WORD);

wire truncated_packet_error;

// Early TLAST means truncation; no TLAST at the declared end means an oversized packet.
assign truncated_packet_error =
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count<(packet_size_reg-16'd1));

wire oversized_packet_error;

assign oversized_packet_error = 
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    !s_axis_pkt_tlast&&
    (word_count==(packet_size_reg-16'd1));

wire recv_error;

assign recv_error = 
    word1_error||
    word2_error||
    word3_error||
    tkeep_error||
    truncated_packet_error||
    oversized_packet_error;

assign payload_wr_en =
    (current_state == ST_RECV) &&
    s_axis_handshake &&
    !recv_error &&
    (word_count >= `DIFI_DATA_PROLOGUE_WORDS);

// A 256-word memory needs only the low 8 address bits.
assign payload_wr_addr = word_count - `DIFI_DATA_PROLOGUE_WORDS;

// Prefetch the first sample, then read the next as each sample is output.

// Stop prefetching during output stalls or on the last sample.
assign payload_rd_en =
    m_meta_handshake ||
    ((current_state == ST_OUTPUT) && m_axis_handshake && !m_axis_iq_tlast);

assign payload_rd_addr =
    m_meta_handshake ? 8'd0 : (payload_rd_ptr[7:0] + 8'd1);

// RAM and read-data registers have no asynchronous reset.
always @(posedge aclk)
begin
    if (payload_wr_en)
        snapshot_payload[payload_wr_addr] <= s_axis_pkt_tdata;

    if (payload_rd_en)
        payload_q <= snapshot_payload[payload_rd_addr];
end

wire recv_no_error;

assign recv_no_error =
    (current_state==ST_RECV)&&
    (!recv_error)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count>=`DIFI_DATA_PROLOGUE_WORDS)&&
    (word_count==(packet_size_reg-16'd1));

// Report sequence discontinuities without discarding the packet.
reg base_active;
reg [31:0] base_stream_id;
reg [3:0] base_seq_num;
wire [3:0] expect_seq_num;
wire seq_discontinuity_error;

assign expect_seq_num = base_seq_num + 4'd1;
// Check the sequence only for complete, valid packets.
assign seq_discontinuity_error =
    recv_no_error&&
    base_active&&
    (snapshot_received_stream_id==base_stream_id)&&
    (snapshot_pkt_seq!=expect_seq_num);

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

        // Output metadata before IQ.
        else if(recv_no_error)
        begin
            next_state = ST_META;
        end
    end

    // Discard through TLAST without repeating the error.
    ST_DROP:
    begin
        if(s_axis_pkt_tlast&&s_axis_handshake)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_META:
    begin
        if(m_meta_handshake)
        begin
            next_state = ST_OUTPUT;
        end
    end

    ST_OUTPUT:
    begin
        if(m_axis_handshake&&(payload_rd_ptr==(packet_size_reg - `DIFI_DATA_PROLOGUE_WORDS-16'd1)))
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
    s_axis_pkt_tready = 0;
    m_meta_valid = 0;
    m_axis_iq_tvalid = 0;
    m_axis_iq_tdata = 0;
    m_axis_iq_tlast = 0;
    m_meta_stream_id = 0;
    m_meta_seq = 0;
    m_meta_time_sec = 0;
    m_meta_time_ps = 0;
    m_meta_sample_count = 0;

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

    // Output the metadata actually received.
    ST_META:
    begin
        m_meta_stream_id = snapshot_received_stream_id;
        m_meta_seq = snapshot_pkt_seq;
        m_meta_time_sec = snapshot_time_sec;
        m_meta_time_ps = {snapshot_time_h_ps,snapshot_time_l_ps};
        m_meta_sample_count = packet_size_reg - `DIFI_DATA_PROLOGUE_WORDS;
        m_meta_valid = 1;
    end

    // Hold data and the read pointer during output stalls.
    ST_OUTPUT:
    begin
        m_axis_iq_tdata = payload_q;
        m_axis_iq_tvalid = 1;

        if(payload_rd_ptr==(packet_size_reg - `DIFI_DATA_PROLOGUE_WORDS-16'd1))
        begin
            m_axis_iq_tlast = 1;
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
        packet_size_reg <= 0;
        snapshot_stream_filter_enable <= 0;
        snapshot_expected_stream_id <= 0;
        error_valid <= 0;
        error_code <= 0;
        snapshot_time_sec <= 0;
        snapshot_time_h_ps <= 0;
        snapshot_time_l_ps <= 0;
        word_count <= 0;
        payload_rd_ptr <= 0;
        snapshot_received_stream_id <= 0;
        base_active <= 0;
        snapshot_pkt_seq <= 0;
        base_seq_num <= 0;
        base_stream_id <= 0;
    end

    else
    begin
        
        error_valid <= 0;

        case (current_state)
        ST_IDLE:
        begin
            // Save the packet configuration on a valid Word0 transfer.
            if(word0_accept)
            begin
                packet_size_reg <= s_axis_pkt_tdata[15:0];
                snapshot_pkt_seq <= s_axis_pkt_tdata[19:16];
                snapshot_stream_filter_enable <= cfg_stream_filter_enable;
                snapshot_expected_stream_id <= cfg_expected_stream_id;
            end

            else
            begin
                // Report only one Word0 error, in priority order.
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
                    if(word_count == 9'd1)
                    begin
                        snapshot_received_stream_id <= s_axis_pkt_tdata;
                    end

                    if(word_count==9'd4)
                    begin
                        snapshot_time_sec <= s_axis_pkt_tdata;
                    end

                    if(word_count==9'd5)
                    begin
                        snapshot_time_h_ps <= s_axis_pkt_tdata;
                    end

                    if(word_count==9'd6)
                    begin
                        snapshot_time_l_ps <= s_axis_pkt_tdata;
                    end

                end
            end

            // Error priority: truncation, length, class, then SID.
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

            // Report a sequence error once and keep valid IQ.
            else if(seq_discontinuity_error)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_SEQ;
            end
        end

        ST_OUTPUT:
        begin
            if(m_axis_handshake)
            begin
                if(!m_axis_iq_tlast)
                begin
                    payload_rd_ptr <= payload_rd_ptr + 1;
                end

                else
                begin
                    payload_rd_ptr <= 0;
                end
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

        // Update the sequence baseline only for complete, valid packets.
        if(recv_no_error)
        begin
            base_active <= 1;
            base_seq_num <= snapshot_pkt_seq;
            base_stream_id <= snapshot_received_stream_id;
        end
    end
end

endmodule
