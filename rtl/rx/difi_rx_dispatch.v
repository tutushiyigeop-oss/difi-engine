`include "../include/difi_v1_1_defs.vh"

module difi_rx_dispatch (
    input  wire        aclk,
    input  wire        aresetn,

    // RX input packet stream
    input  wire [31:0] s_axis_pkt_tdata,
    input  wire        s_axis_pkt_tvalid,
    output wire        s_axis_pkt_tready,
    input  wire [3:0]  s_axis_pkt_tkeep,
    input  wire        s_axis_pkt_tlast,

    // To Data Parser
    output wire [31:0] m_data_tdata,
    output wire        m_data_tvalid,
    input  wire        m_data_tready,
    output wire [3:0]  m_data_tkeep,
    output wire        m_data_tlast,

    // To Context Parser
    output wire [31:0] m_context_tdata,
    output wire        m_context_tvalid,
    input  wire        m_context_tready,
    output wire [3:0]  m_context_tkeep,
    output wire        m_context_tlast,

    // To Version Parser
    output wire [31:0] m_version_tdata,
    output wire        m_version_tvalid,
    input  wire        m_version_tready,
    output wire [3:0]  m_version_tkeep,
    output wire        m_version_tlast,

    // Error
    output reg         error_valid,
    output reg  [3:0]  error_code
);


// FSM State Defination
reg [2:0] current_state;
reg [2:0] next_state;
localparam ST_IDLE = 3'd0;
localparam ST_RECV_DATA = 3'd1;
localparam ST_RECV_CONTEXT = 3'd2;
localparam ST_RECV_VERSION = 3'd3;
localparam ST_DROP = 3'd4;


// Handshake
wire s_axis_handshake;
assign s_axis_handshake = s_axis_pkt_tvalid & s_axis_pkt_tready;


// MUX for Tready
assign s_axis_pkt_tready = 
    (current_state==ST_IDLE)?0:
    (current_state==ST_RECV_DATA)?m_data_tready:
    (current_state==ST_RECV_CONTEXT)?m_context_tready:
    (current_state==ST_RECV_VERSION)?m_version_tready:
    (current_state==ST_DROP)?1:0;


// MUX for Tdata
assign m_data_tdata = s_axis_pkt_tdata;
assign m_context_tdata = s_axis_pkt_tdata;
assign m_version_tdata = s_axis_pkt_tdata;


// MUX for Tvalid
assign m_data_tvalid = (current_state==ST_RECV_DATA)?s_axis_pkt_tvalid:0;
assign m_context_tvalid = (current_state==ST_RECV_CONTEXT)?s_axis_pkt_tvalid:0;
assign m_version_tvalid = (current_state==ST_RECV_VERSION)?s_axis_pkt_tvalid:0;


// MUX for Tlast
assign m_data_tlast = (current_state==ST_RECV_DATA)?s_axis_pkt_tlast:0;
assign m_context_tlast = (current_state==ST_RECV_CONTEXT)?s_axis_pkt_tlast:0;
assign m_version_tlast = (current_state==ST_RECV_VERSION)?s_axis_pkt_tlast:0;


// MUX for Tkeep
assign m_data_tkeep = (current_state==ST_RECV_DATA)?s_axis_pkt_tkeep:0;
assign m_context_tkeep = (current_state==ST_RECV_CONTEXT)?s_axis_pkt_tkeep:0;
assign m_version_tkeep = (current_state==ST_RECV_VERSION)?s_axis_pkt_tkeep:0;


// Header type part
wire [3:0] pkt_type;
assign pkt_type = s_axis_pkt_tdata[31:28];


// Word0 Packet Type Error/No Error
wire word0_type_error;
assign word0_type_error = 
    (current_state==ST_IDLE)&&
    s_axis_pkt_tvalid&&
    ((pkt_type!=`DIFI_DATA_PKT_TYPE)&&
    (pkt_type!=`DIFI_CONTEXT_PKT_TYPE)&&
    (pkt_type!=`DIFI_VERSION_PKT_TYPE));


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
        if(s_axis_pkt_tvalid)
        begin
            if(word0_type_error)
            begin
                next_state = ST_DROP;
            end

            else
            begin
                case (pkt_type)
                `DIFI_DATA_PKT_TYPE:
                begin
                    next_state = ST_RECV_DATA;
                end

                `DIFI_CONTEXT_PKT_TYPE:
                begin
                    next_state = ST_RECV_CONTEXT;
                end

                `DIFI_VERSION_PKT_TYPE:
                begin
                    next_state = ST_RECV_VERSION;
                end

                default:
                begin
                    next_state = ST_IDLE;
                end
                endcase
            end
        end
    end

    ST_RECV_DATA:
    begin
        if(s_axis_handshake&&s_axis_pkt_tlast)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_RECV_CONTEXT:
    begin
        if(s_axis_handshake&&s_axis_pkt_tlast)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_RECV_VERSION:
    begin
        if(s_axis_handshake&&s_axis_pkt_tlast)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_DROP:
    begin
        if(s_axis_handshake&&s_axis_pkt_tlast)
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
// 3. Report Error
// ------------------------------------------------------------------
always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        error_valid <= 0;
        error_code <= 0;
    end

    else
    begin
        error_valid <= 0;

        case (current_state)
        ST_DROP:
        begin
            if(s_axis_pkt_tlast&&s_axis_handshake)
            begin
                error_valid <= 1;
                error_code <= `DIFI_ERR_UNSUPPORTED_TYPE;
            end
        end

        default:
        begin
            
        end
        endcase
    end
end


endmodule