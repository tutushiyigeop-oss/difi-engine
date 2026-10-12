// ------------------------------------------------------------------
// DIFI Signal Data parser: validate a full packet before releasing IQ.
// ------------------------------------------------------------------
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
 

// FSM State Defination
// Receive, discard malformed packets, then emit metadata and buffered IQ.
reg [2:0] current_state;
reg [2:0] next_state;
localparam ST_IDLE = 3'd0;
localparam ST_RECV = 3'd1;
localparam ST_DROP = 3'd2;
localparam ST_META = 3'd3;
localparam ST_OUTPUT = 3'd4;


// Handshake
wire s_axis_handshake;
wire m_axis_handshake;
wire m_meta_handshake;

assign s_axis_handshake = s_axis_pkt_tvalid & s_axis_pkt_tready;
assign m_axis_handshake = m_axis_iq_tvalid & m_axis_iq_tready;
assign m_meta_handshake = m_meta_valid & m_meta_ready;


// Counter
reg [8:0] word_count;
// The receive word counter includes the prologue; the read pointer does not.
reg [8:0] payload_rd_ptr;


// Snapshot
reg [15:0] packet_size_reg;
reg snapshot_stream_filter_enable;
reg [3:0] snapshot_pkt_seq;
reg [31:0] snapshot_expected_stream_id;
reg [31:0] snapshot_received_stream_id;
reg [31:0] snapshot_time_sec;
reg [31:0] snapshot_time_h_ps;
reg [31:0] snapshot_time_l_ps;
// One complete packet of IQ is buffered until validation succeeds.
// Synchronous read is required for Zynq-7000 Block RAM inference.
// The memory is deliberately NOT reset: only validated packets are released.
(* ram_style = "block" *) reg [31:0] snapshot_payload [0:255];
reg [31:0] payload_q;

wire        payload_wr_en;
wire [7:0]  payload_wr_addr;
wire        payload_rd_en;
wire [7:0]  payload_rd_addr;


// Tkeep Error
wire tkeep_error;

// Every accepted 32-bit word must contain four valid bytes.
assign tkeep_error =
    s_axis_handshake&&
    (s_axis_pkt_tkeep!=4'b1111);


// Word0 Packet Type Error
wire word0_type_error;

assign word0_type_error = 
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    (s_axis_pkt_tdata[31:28]!=`DIFI_DATA_PKT_TYPE);


// Word0 Fixed Header fields Error
wire word0_header_error;

assign word0_header_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    ((s_axis_pkt_tdata[27]!=`DIFI_CLASS_ID_PRESENT)||
    (s_axis_pkt_tdata[26:25]!=`DIFI_PROFILE_BITS)||
    (s_axis_pkt_tdata[24]!=`DIFI_DATA_TSM)||
    (s_axis_pkt_tdata[23:22]!=`DIFI_TSI_UTC)||
    (s_axis_pkt_tdata[21:20]!=`DIFI_TSF_REALTIME_PS));


// Word0 Packet Size Error
wire word0_size_error;

assign word0_size_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    ((s_axis_pkt_tdata[15:0]<=`DIFI_DATA_PROLOGUE_WORDS)||
    (s_axis_pkt_tdata[15:0]>(`DIFI_DATA_PROLOGUE_WORDS+`DIFI_DATA_MAX_SAMPLES)));


// Word0 TLAST Error
wire word0_tlast_error;

assign word0_tlast_error =
    (current_state==ST_IDLE)&&
    s_axis_handshake&&
    s_axis_pkt_tlast;


// Overall Word0 Error
wire word0_error;

// A rejected first word is never used to initialize packet metadata.
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
    (word_count==9'd1)&&
    s_axis_handshake&&
    snapshot_stream_filter_enable&&
    (s_axis_pkt_tdata!=snapshot_expected_stream_id);


// Invalid OUI, ICC, or PCC (Word2-3)
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


// Truncated Packet Error
wire truncated_packet_error;

// Early TLAST is truncation; missing TLAST at the declared end is oversize.
assign truncated_packet_error =
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count<(packet_size_reg-16'd1));


// Oversized Packet Error
wire oversized_packet_error;

assign oversized_packet_error = 
    (current_state==ST_RECV)&&
    s_axis_handshake&&
    !s_axis_pkt_tlast&&
    (word_count==(packet_size_reg-16'd1));


// ST_RECV Error (except "Sequence discontinuity")
wire recv_error;

// Fatal errors prevent metadata and IQ from being emitted.
assign recv_error = 
    word1_error||
    word2_error||
    word3_error||
    tkeep_error||
    truncated_packet_error||
    oversized_packet_error;


// ------------------------------------------------------------------
// Synchronous IQ payload memory: simple-dual-port BRAM inference
// ------------------------------------------------------------------
// Preserve the original per-beat validation gate for RAM writes.
assign payload_wr_en =
    (current_state == ST_RECV) &&
    s_axis_handshake &&
    !recv_error &&
    (word_count >= `DIFI_DATA_PROLOGUE_WORDS);

// Only the low eight address bits are needed for a 256 x 32 memory.
assign payload_wr_addr = word_count - `DIFI_DATA_PROLOGUE_WORDS;

// One-cycle look-ahead: fetch Sample 0 on metadata acceptance, then
// fetch Sample (n+1) as Sample n actually handshakes downstream.
// No new RAM read during output backpressure or on the final sample.
assign payload_rd_en =
    m_meta_handshake ||
    ((current_state == ST_OUTPUT) && m_axis_handshake && !m_axis_iq_tlast);

assign payload_rd_addr =
    m_meta_handshake ? 8'd0 : (payload_rd_ptr[7:0] + 8'd1);

// No asynchronous reset on the RAM array or registered read data.
always @(posedge aclk)
begin
    if (payload_wr_en)
        snapshot_payload[payload_wr_addr] <= s_axis_pkt_tdata;

    if (payload_rd_en)
        payload_q <= snapshot_payload[payload_rd_addr];
end


// ST_RECV No Error (except "Sequence discontinuity")
wire recv_no_error;

// Commit the packet only when its declared final word arrives intact.
assign recv_no_error =
    (current_state==ST_RECV)&&
    (!recv_error)&&
    s_axis_handshake&&
    s_axis_pkt_tlast&&
    (word_count>=`DIFI_DATA_PROLOGUE_WORDS)&&
    (word_count==(packet_size_reg-16'd1));

// Sequence discontinuity (report only, do not discard)
reg base_active;
reg [31:0] base_stream_id;
reg [3:0] base_seq_num;
wire [3:0] expect_seq_num;
wire seq_discontinuity_error;
// Four-bit arithmetic implements the required 15-to-0 wraparound.
assign expect_seq_num = base_seq_num + 4'd1;
// Sequence errors are checked only on a complete, otherwise valid packet.
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
        // Skip the remainder of a malformed packet unless TLAST ends it here.
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
        // An error on TLAST allows the next packet to start immediately.
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

        // A validated packet exposes metadata before its IQ payload.
        else if(recv_no_error)
        begin
            next_state = ST_META;
        end
    end

    // Drain discarded words through TLAST without emitting more errors.
    ST_DROP:
    begin
        if(s_axis_pkt_tlast&&s_axis_handshake)
        begin
            next_state = ST_IDLE;
        end
    end

    // Metadata remains available until the consumer accepts it.
    ST_META:
    begin
        if(m_meta_handshake)
        begin
            next_state = ST_OUTPUT;
        end
    end

    // Return to IDLE only after the final IQ handshake.
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


// ------------------------------------------------------------------
// 3. Combinational ready/valid, metadata, and IQ outputs
// ------------------------------------------------------------------
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

    // Present received metadata, not the configured filter target.
    ST_META:
    begin
        m_meta_stream_id = snapshot_received_stream_id;
        m_meta_seq = snapshot_pkt_seq;
        m_meta_time_sec = snapshot_time_sec;
        m_meta_time_ps = {snapshot_time_h_ps,snapshot_time_l_ps};
        m_meta_sample_count = packet_size_reg - `DIFI_DATA_PROLOGUE_WORDS;
        m_meta_valid = 1;
    end

    // Synchronous RAM Q and the read pointer hold during backpressure.
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


// ------------------------------------------------------------------
// 4. Snapshot storage, error reporting, and sequence baseline
// ------------------------------------------------------------------
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
        // Clear by default so each detected error produces a one-cycle pulse.
        error_valid <= 0;

        case (current_state)
        ST_IDLE:
        begin
            // Capture per-packet configuration only on an accepted Word0.
            if(word0_accept)
            begin
                packet_size_reg <= s_axis_pkt_tdata[15:0];
                snapshot_pkt_seq <= s_axis_pkt_tdata[19:16];
                snapshot_stream_filter_enable <= cfg_stream_filter_enable;
                snapshot_expected_stream_id <= cfg_expected_stream_id;
            end

            else
            begin
                // Report one Word0 error using the agreed priority order.
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
            // Store received fields and IQ only when this beat has no fatal error.
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

            // Prioritize truncation, size, class, and SID errors on this beat.
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

            // Discontinuity is reported once but does not discard valid IQ.
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

        // Count accepted words; reset at the actual packet boundary.
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

        // Only complete, structurally valid packets establish a new baseline.
        if(recv_no_error)
        begin
            base_active <= 1;
            base_seq_num <= snapshot_pkt_seq;
            base_stream_id <= snapshot_received_stream_id;
        end
    end
end

endmodule
