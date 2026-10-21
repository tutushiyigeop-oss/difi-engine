`include "difi_v1_1_defs.vh"

module difi_tx_scheduler (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        tx_enable,
    input  wire        time_valid,

    input  wire        data_available,

    input  wire        cfg_commit_req,
    output reg         cfg_commit_ack,

    input  wire        context_change_pending,
    input  wire        context_periodic_trigger,
    input  wire        version_periodic_trigger,

    output wire        data_pkt_start,
    input  wire        data_pkt_busy,
    input  wire        data_pkt_done,

    input  wire [31:0] s_axis_data_tdata,
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire [3:0]  s_axis_data_tkeep,
    input  wire        s_axis_data_tlast,

    output wire        context_pkt_start,
    input  wire        context_pkt_busy,
    input  wire        context_pkt_done,

    input  wire [31:0] s_axis_context_tdata,
    input  wire        s_axis_context_tvalid,
    output wire        s_axis_context_tready,
    input  wire [3:0]  s_axis_context_tkeep,
    input  wire        s_axis_context_tlast,

    output wire        version_pkt_start,
    input  wire        version_pkt_busy,
    input  wire        version_pkt_done,

    input  wire [31:0] s_axis_version_tdata,
    input  wire        s_axis_version_tvalid,
    output wire        s_axis_version_tready,
    input  wire [3:0]  s_axis_version_tkeep,
    input  wire        s_axis_version_tlast,

    output wire [31:0] m_axis_pkt_tdata,
    output wire        m_axis_pkt_tvalid,
    input  wire        m_axis_pkt_tready,
    output wire [3:0]  m_axis_pkt_tkeep,
    output wire        m_axis_pkt_tlast,

    output wire        tx_busy
);

reg [1:0] current_state;
reg [1:0] next_state;
localparam ST_IDLE = 2'd0;
localparam ST_SEND_DATA = 2'd1;
localparam ST_SEND_CONTEXT = 2'd2;
localparam ST_SEND_VERSION = 2'd3;

reg startup_version_pending;
reg context_periodic_pending;
reg version_periodic_pending;

assign s_axis_data_tready = (current_state==ST_SEND_DATA) ? m_axis_pkt_tready:0;
assign s_axis_context_tready = (current_state==ST_SEND_CONTEXT) ? m_axis_pkt_tready:0;
assign s_axis_version_tready = (current_state==ST_SEND_VERSION) ? m_axis_pkt_tready:0;

assign m_axis_pkt_tdata = 
    (current_state==ST_SEND_DATA) ? s_axis_data_tdata:
    (current_state==ST_SEND_CONTEXT) ? s_axis_context_tdata:
    (current_state==ST_SEND_VERSION) ? s_axis_version_tdata:0;

assign m_axis_pkt_tvalid = 
    (current_state==ST_SEND_DATA) ? s_axis_data_tvalid:
    (current_state==ST_SEND_CONTEXT) ? s_axis_context_tvalid:
    (current_state==ST_SEND_VERSION) ? s_axis_version_tvalid:0;

assign m_axis_pkt_tlast = 
    (current_state==ST_SEND_DATA) ? s_axis_data_tlast:
    (current_state==ST_SEND_CONTEXT) ? s_axis_context_tlast:
    (current_state==ST_SEND_VERSION) ? s_axis_version_tlast:0;

assign m_axis_pkt_tkeep = 
    (current_state==ST_SEND_DATA) ? s_axis_data_tkeep:
    (current_state==ST_SEND_CONTEXT) ? s_axis_context_tkeep:
    (current_state==ST_SEND_VERSION) ? s_axis_version_tkeep:0;

assign tx_busy = 
    (current_state==ST_SEND_DATA) ? 1:
    (current_state==ST_SEND_CONTEXT) ? 1:
    (current_state==ST_SEND_VERSION) ? 1:0;

assign data_pkt_start = aresetn&&(current_state==ST_IDLE)&&(next_state==ST_SEND_DATA);
assign context_pkt_start = aresetn&&(current_state==ST_IDLE)&&(next_state==ST_SEND_CONTEXT);
assign version_pkt_start = aresetn&&(current_state==ST_IDLE)&&(next_state==ST_SEND_VERSION);

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
        if(!cfg_commit_req&&!cfg_commit_ack)
        begin
            if(tx_enable&&time_valid)
            begin
                if(startup_version_pending)
                begin
                    if(!version_pkt_busy)
                    begin
                        next_state = ST_SEND_VERSION;
                    end
                end

                else if(context_change_pending)
                begin
                    if(!context_pkt_busy)
                    begin
                        next_state = ST_SEND_CONTEXT;
                    end
                end

                else if(context_periodic_pending)
                begin
                    if(!context_pkt_busy)
                    begin
                        next_state = ST_SEND_CONTEXT;
                    end
                end

                else if(version_periodic_pending)
                begin
                    if(!version_pkt_busy)
                    begin
                        next_state = ST_SEND_VERSION;
                    end
                end

                else if(data_available)
                begin
                    if(!data_pkt_busy)
                    begin
                        next_state = ST_SEND_DATA;
                    end
                end
            end
        end
    end

    ST_SEND_DATA:
    begin
        if(data_pkt_done)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_SEND_CONTEXT:
    begin
        if(context_pkt_done)
        begin
            next_state = ST_IDLE;
        end
    end

    ST_SEND_VERSION:
    begin
        if(version_pkt_done)
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

always @(posedge aclk or negedge aresetn) 
begin
    if (!aresetn)
    begin
        context_periodic_pending <= 0;
        version_periodic_pending <= 0;
        startup_version_pending <= 1;
        cfg_commit_ack <= 0;
    end

    else
    begin
        cfg_commit_ack <= 0;

        case (current_state)
        ST_IDLE:
        begin
            if(!tx_busy&&cfg_commit_req&&!cfg_commit_ack)
            begin
                cfg_commit_ack <= 1;
            end
        end

        ST_SEND_VERSION:
        begin
            if(version_pkt_done)
            begin
                startup_version_pending <= 0;
            end
        end

        default:
        begin
            
        end
        endcase

        if(context_pkt_start)
        begin
            context_periodic_pending <= 1'b0;
        end

        if(version_pkt_start)
        begin
            version_periodic_pending <= 1'b0;
        end

        if(context_periodic_trigger)
        begin
            context_periodic_pending <= 1'b1;
        end

        if(version_periodic_trigger)
        begin
            version_periodic_pending <= 1'b1;
        end
    end
end

endmodule
