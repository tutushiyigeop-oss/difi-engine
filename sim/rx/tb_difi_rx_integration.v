`timescale 1ns / 1ps
`include "difi_v1_1_defs.vh"

// Integration test: a REAL difi_rx_dispatch feeding all three REAL parsers.
// Verilog-2001; no TX generator, mock parser, or hierarchical force is used.
module tb_difi_rx_integration;
    localparam integer MAX_WORDS = 263;
    localparam integer TIMEOUT   = 20000;
    localparam [2:0] ERR_NONE=0, ERR_DISPATCH=1, ERR_DATA=2,
                     ERR_CONTEXT=3, ERR_VERSION=4;

    reg aclk = 1'b0;
    always #5 aclk = ~aclk;
    reg aresetn;

    reg  [31:0] s_axis_pkt_tdata;
    reg         s_axis_pkt_tvalid;
    wire        s_axis_pkt_tready;
    reg  [3:0]  s_axis_pkt_tkeep;
    reg         s_axis_pkt_tlast;

    wire [31:0] data_tdata, context_tdata, version_tdata;
    wire [3:0] data_tkeep, context_tkeep, version_tkeep;
    wire data_tvalid, data_tready, data_tlast;
    wire context_tvalid, context_tready, context_tlast;
    wire version_tvalid, version_tready, version_tlast;
    wire dispatch_error_valid;
    wire [3:0] dispatch_error_code;

    reg data_filter_enable, version_filter_enable;
    reg [31:0] expected_data_sid, expected_version_sid;

    wire [31:0] data_iq_tdata;
    wire data_iq_tvalid, data_iq_tlast;
    reg  data_iq_tready;
    wire data_meta_valid;
    reg  data_meta_ready;
    wire [31:0] data_meta_stream_id, data_meta_time_sec;
    wire [3:0]  data_meta_seq;
    wire [63:0] data_meta_time_ps;
    wire [15:0] data_meta_sample_count;
    wire data_error_valid;
    wire [3:0] data_error_code;

    wire context_meta_valid;
    reg  context_meta_ready;
    wire [31:0] context_meta_stream_id, context_meta_time_sec;
    wire [3:0] context_meta_seq;
    wire [63:0] context_meta_time_ps, context_meta_rf_freq_hz;
    wire context_meta_changed;
    wire [31:0] context_meta_bandwidth_hz, context_meta_sample_rate_hz;
    wire context_error_valid;
    wire [3:0] context_error_code;

    wire version_meta_valid;
    reg  version_meta_ready;
    wire [31:0] version_meta_stream_id, version_meta_time_sec, version_meta_info;
    wire [3:0] version_meta_seq;
    wire [63:0] version_meta_time_ps;
    wire version_meta_changed;
    wire version_error_valid;
    wire [3:0] version_error_code;

    // Wire the actual dispatch outputs to the actual parser inputs.
    difi_rx_dispatch u_dispatch (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_pkt_tdata(s_axis_pkt_tdata),
        .s_axis_pkt_tvalid(s_axis_pkt_tvalid),
        .s_axis_pkt_tready(s_axis_pkt_tready),
        .s_axis_pkt_tkeep(s_axis_pkt_tkeep),
        .s_axis_pkt_tlast(s_axis_pkt_tlast),
        .m_data_tdata(data_tdata), .m_data_tvalid(data_tvalid),
        .m_data_tready(data_tready), .m_data_tkeep(data_tkeep),
        .m_data_tlast(data_tlast),
        .m_context_tdata(context_tdata), .m_context_tvalid(context_tvalid),
        .m_context_tready(context_tready), .m_context_tkeep(context_tkeep),
        .m_context_tlast(context_tlast),
        .m_version_tdata(version_tdata), .m_version_tvalid(version_tvalid),
        .m_version_tready(version_tready), .m_version_tkeep(version_tkeep),
        .m_version_tlast(version_tlast),
        .error_valid(dispatch_error_valid), .error_code(dispatch_error_code)
    );

    difi_data_parser u_data (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_pkt_tdata(data_tdata), .s_axis_pkt_tvalid(data_tvalid),
        .s_axis_pkt_tready(data_tready), .s_axis_pkt_tkeep(data_tkeep),
        .s_axis_pkt_tlast(data_tlast),
        .cfg_stream_filter_enable(data_filter_enable),
        .cfg_expected_stream_id(expected_data_sid),
        .m_axis_iq_tdata(data_iq_tdata), .m_axis_iq_tvalid(data_iq_tvalid),
        .m_axis_iq_tready(data_iq_tready), .m_axis_iq_tlast(data_iq_tlast),
        .m_meta_valid(data_meta_valid), .m_meta_ready(data_meta_ready),
        .m_meta_stream_id(data_meta_stream_id), .m_meta_seq(data_meta_seq),
        .m_meta_time_sec(data_meta_time_sec), .m_meta_time_ps(data_meta_time_ps),
        .m_meta_sample_count(data_meta_sample_count),
        .error_valid(data_error_valid), .error_code(data_error_code)
    );

    difi_context_parser u_context (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_pkt_tdata(context_tdata), .s_axis_pkt_tvalid(context_tvalid),
        .s_axis_pkt_tready(context_tready), .s_axis_pkt_tkeep(context_tkeep),
        .s_axis_pkt_tlast(context_tlast),
        .cfg_stream_filter_enable(data_filter_enable),
        .cfg_expected_stream_id(expected_data_sid),
        .m_ctx_valid(context_meta_valid), .m_ctx_ready(context_meta_ready),
        .m_ctx_stream_id(context_meta_stream_id), .m_ctx_seq(context_meta_seq),
        .m_ctx_time_sec(context_meta_time_sec), .m_ctx_time_ps(context_meta_time_ps),
        .m_ctx_changed(context_meta_changed),
        .m_ctx_bandwidth_hz(context_meta_bandwidth_hz),
        .m_ctx_rf_freq_hz(context_meta_rf_freq_hz),
        .m_ctx_sample_rate_hz(context_meta_sample_rate_hz),
        .error_valid(context_error_valid), .error_code(context_error_code)
    );

    difi_version_parser u_version (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_pkt_tdata(version_tdata), .s_axis_pkt_tvalid(version_tvalid),
        .s_axis_pkt_tready(version_tready), .s_axis_pkt_tkeep(version_tkeep),
        .s_axis_pkt_tlast(version_tlast),
        .cfg_stream_filter_enable(version_filter_enable),
        .cfg_expected_stream_id(expected_version_sid),
        .m_ver_valid(version_meta_valid), .m_ver_ready(version_meta_ready),
        .m_ver_stream_id(version_meta_stream_id), .m_ver_seq(version_meta_seq),
        .m_ver_time_sec(version_meta_time_sec), .m_ver_time_ps(version_meta_time_ps),
        .m_ver_changed(version_meta_changed), .m_ver_info(version_meta_info),
        .error_valid(version_error_valid), .error_code(version_error_code)
    );

    // Packet stimulus and an independent, transaction-level scoreboard.
    reg [31:0] words [0:MAX_WORDS-1];
    reg [3:0] keeps [0:MAX_WORDS-1];
    reg lasts [0:MAX_WORDS-1];
    reg [31:0] expected_iq [0:255];
    integer tx_len, testcase, cycles;
    reg active_case, stress_ready;
    integer seen_input, seen_last, seen_data_meta, seen_context_meta,
            seen_version_meta, seen_iq, seen_error;
    integer want_data_meta, want_context_meta, want_version_meta, want_iq;
    reg [2:0] want_error_source;
    reg [3:0] want_error_code;
    reg [31:0] want_sid, want_sec, want_bw, want_fs, want_info;
    reg [3:0] want_seq;
    reg [63:0] want_ps, want_rf;
    reg want_changed;
    reg prev_iq_stall, prev_d_meta_stall, prev_c_meta_stall, prev_v_meta_stall;
    reg [31:0] held_iq_data, held_d_sid, held_c_sid, held_v_sid;
    reg held_iq_last;

    function [31:0] iq_pattern;
        input integer i, tag;
        begin
            iq_pattern = 32'h1357_9BDF ^ (tag * 32'h0001_0001)
                                       ^ (i * 32'h0001_0103);
        end
    endfunction

    task die;
        input [8*180-1:0] why;
        begin
            $display("[FAIL] TC%0d time=%0t: %0s", testcase, $time, why);
            $display("input=%0d/%0d last=%0d d/c/v=%0d/%0d/%0d IQ=%0d/%0d err=%0d source=%0d code=%h",
                seen_input, tx_len, seen_last, seen_data_meta, seen_context_meta,
                seen_version_meta, seen_iq, want_iq, seen_error,
                want_error_source, want_error_code);
            $fatal(1);
        end
    endtask

    task init_words;
        input integer count;
        integer j;
        begin
            tx_len = count;
            for (j=0;j<count;j=j+1) begin
                words[j] = 0;
                keeps[j] = 4'hF;
                lasts[j] = (j==count-1);
            end
        end
    endtask

    task build_data;
        input integer n, tag;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        integer j;
        begin
            if (n<1 || n>256) die("Testbench Data sample count out of bounds");
            init_words(7+n);
            words[0] = 32'h1860_0000 | ({28'd0,seq} << 16) | (7+n);
            words[1] = sid; words[2] = `DIFI_OUI_WORD;
            words[3] = `DIFI_DATA_CLASS_WORD;
            words[4] = sec; words[5] = ps[63:32]; words[6] = ps[31:0];
            for (j=0;j<n;j=j+1) begin
                words[7+j] = iq_pattern(j,tag);
                expected_iq[j] = words[7+j];
            end
            want_sid = sid; want_sec = sec; want_ps = ps; want_seq = seq;
            want_data_meta=1; want_context_meta=0; want_version_meta=0;
            want_iq=n;
        end
    endtask

    task build_context;
        input [31:0] sid, sec, bw, fs;
        input [3:0] seq;
        input [63:0] ps, rf;
        input changed;
        reg [63:0] raw;
        begin
            init_words(27);
            words[0] = `DIFI_CONTEXT_HEADER_BASE | ({28'd0,seq} << 16);
            words[1] = sid; words[2] = `DIFI_OUI_WORD;
            words[3] = `DIFI_CONTEXT_CLASS_WORD;
            words[4] = sec; words[5] = ps[63:32]; words[6] = ps[31:0];
            words[7] = changed ? `DIFI_CONTEXT_CIF_CHANGED : `DIFI_CONTEXT_CIF_NO_CHANGE;
            words[8] = `DIFI_CONTEXT_REF_POINT;
            raw = {32'd0,bw} << 20;
            words[9] = raw[63:32]; words[10] = raw[31:0];
            raw = rf << 20;
            words[13] = raw[63:32]; words[14] = raw[31:0];
            raw = {32'd0,fs} << 20;
            words[19] = raw[63:32]; words[20] = raw[31:0];
            words[25] = `DIFI_CONTEXT_DPF_WORD0;
            words[26] = `DIFI_CONTEXT_DPF_WORD1;
            want_sid=sid; want_sec=sec; want_seq=seq; want_ps=ps;
            want_bw=bw; want_rf=rf; want_fs=fs; want_changed=changed;
            want_data_meta=0; want_context_meta=1; want_version_meta=0;
            want_iq=0;
        end
    endtask

    task build_version;
        input [31:0] sid, sec;
        input [3:0] seq;
        input [63:0] ps;
        input changed;
        begin
            init_words(11);
            words[0] = `DIFI_VERSION_HEADER_BASE | ({28'd0,seq} << 16);
            words[1] = sid; words[2] = `DIFI_OUI_WORD;
            words[3] = `DIFI_VERSION_CLASS_WORD;
            words[4] = sec; words[5] = ps[63:32]; words[6] = ps[31:0];
            words[7] = changed ? `DIFI_VERSION_CIF_CHANGED : `DIFI_VERSION_CIF_NO_CHANGE;
            words[8] = `DIFI_VERSION_CIF1_WORD;
            words[9] = `DIFI_VERSION_V49_SPEC_WORD;
            words[10] = {7'd26,9'd252,`DIFI_VERSION_REVISION,
                         `DIFI_VERSION_TYPE,`DIFI_VERSION_ICD_VERSION};
            want_sid=sid; want_sec=sec; want_seq=seq; want_ps=ps;
            want_changed=changed; want_info=words[10];
            want_data_meta=0; want_context_meta=0; want_version_meta=1;
            want_iq=0;
        end
    endtask

    // For malformed packets, no Parser metadata or IQ may escape.
    task reject_packet;
        input [2:0] source;
        input [3:0] code;
        begin
            want_data_meta=0; want_context_meta=0; want_version_meta=0;
            want_iq=0; want_error_source=source; want_error_code=code;
        end
    endtask

    task arm_case;
        input integer id;
        input stress;
        begin
            @(negedge aclk);
            testcase=id; active_case=1; stress_ready=stress;
            seen_input=0; seen_last=0; seen_data_meta=0;
            seen_context_meta=0; seen_version_meta=0;
            seen_iq=0; seen_error=0;
            prev_iq_stall=0; prev_d_meta_stall=0;
            prev_c_meta_stall=0; prev_v_meta_stall=0;
        end
    endtask

    // Input is held unchanged until a positive-edge TVALID && TREADY.
    // The optional deterministic bubbles exercise the AXIS valid/ready path.
    task send_word;
        input [31:0] word_value;
        input [3:0] keep_value;
        input last_value;
        integer waited;
        begin
            @(negedge aclk);
            s_axis_pkt_tdata=word_value;
            s_axis_pkt_tkeep=keep_value;
            s_axis_pkt_tlast=last_value;
            s_axis_pkt_tvalid=1;
            waited=0;
            @(posedge aclk);
            while (s_axis_pkt_tready !== 1'b1 && waited<TIMEOUT) begin
                waited=waited+1;
                @(posedge aclk);
            end
            if (s_axis_pkt_tready !== 1'b1) die("Input backpressure timeout");
        end
    endtask

    task transmit;
        integer j, k;
        begin
            for (j=0;j<tx_len;j=j+1) begin
                if ((j%7)==3) begin
                    @(negedge aclk); s_axis_pkt_tvalid=0;
                    for (k=0;k<(testcase%3);k=k+1) @(negedge aclk);
                end
                send_word(words[j],keeps[j],lasts[j]);
            end
            @(negedge aclk);
            s_axis_pkt_tvalid=0;
            s_axis_pkt_tlast=0;
        end
    endtask

    // No case is declared PASS just because the input finished transferring.
    // Wait for the parser's eventual metadata and (for Data) complete IQ burst.
    task finish_case;
        integer n;
        begin
            n=0;
            while ((seen_input!=tx_len || seen_last!=1 ||
                    seen_data_meta!=want_data_meta ||
                    seen_context_meta!=want_context_meta ||
                    seen_version_meta!=want_version_meta ||
                    seen_iq!=want_iq ||
                    seen_error!=(want_error_source!=ERR_NONE)) && n<TIMEOUT) begin
                @(negedge aclk);
                n=n+1;
            end
            if (n>=TIMEOUT) die("Timeout waiting for parser outputs/events");
            // Catch any duplicate/late valid/error event.
            repeat (8) @(negedge aclk);
            if (seen_input!=tx_len || seen_last!=1 ||
                seen_data_meta!=want_data_meta ||
                seen_context_meta!=want_context_meta ||
                seen_version_meta!=want_version_meta || seen_iq!=want_iq ||
                seen_error!=(want_error_source!=ERR_NONE))
                die("Final scoreboard mismatch");
            active_case=0; stress_ready=0;
            $display("[PASS] TC%0d: input=%0d IQ=%0d Data/Context/Version Meta=%0d/%0d/%0d error=%0d",
                testcase,seen_input,seen_iq,seen_data_meta,
                seen_context_meta,seen_version_meta,seen_error);
        end
    endtask

    // All monitoring is at the active clock edge. Metadata may be delayed by
    // downstream ready, and IQ MUST follow the Data metadata handshake.
    always @(posedge aclk) begin
        if (aresetn && active_case) begin
            if (want_data_meta==0 && data_meta_valid)
                die("Unexpected Data metadata VALID");
            if (want_context_meta==0 && context_meta_valid)
                die("Unexpected Context metadata VALID");
            if (want_version_meta==0 && version_meta_valid)
                die("Unexpected Version metadata VALID");
            if (want_iq==0 && data_iq_tvalid)
                die("Unexpected IQ VALID from invalid/non-Data packet");
            if (prev_iq_stall && (!data_iq_tvalid ||
                data_iq_tdata !== held_iq_data ||
                data_iq_tlast !== held_iq_last))
                die("IQ AXIS payload changed during backpressure");
            if (prev_d_meta_stall && (!data_meta_valid ||
                data_meta_stream_id !== held_d_sid))
                die("Data metadata changed/dropped under backpressure");
            if (prev_c_meta_stall && (!context_meta_valid ||
                context_meta_stream_id !== held_c_sid))
                die("Context metadata changed/dropped under backpressure");
            if (prev_v_meta_stall && (!version_meta_valid ||
                version_meta_stream_id !== held_v_sid))
                die("Version metadata changed/dropped under backpressure");
            prev_iq_stall = data_iq_tvalid && !data_iq_tready;
            held_iq_data = data_iq_tdata;
            held_iq_last = data_iq_tlast;
            prev_d_meta_stall = data_meta_valid && !data_meta_ready;
            held_d_sid = data_meta_stream_id;
            prev_c_meta_stall = context_meta_valid && !context_meta_ready;
            held_c_sid = context_meta_stream_id;
            prev_v_meta_stall = version_meta_valid && !version_meta_ready;
            held_v_sid = version_meta_stream_id;
            if (s_axis_pkt_tvalid && s_axis_pkt_tready) begin
                seen_input=seen_input+1;
                if (s_axis_pkt_tlast) seen_last=seen_last+1;
                if (seen_input>tx_len || seen_last>1) die("Unexpected input transfer");
            end
            if (data_meta_valid && data_meta_ready) begin
                seen_data_meta=seen_data_meta+1;
                if (seen_data_meta>want_data_meta ||
                    data_meta_stream_id !== want_sid || data_meta_seq !== want_seq ||
                    data_meta_time_sec !== want_sec || data_meta_time_ps !== want_ps ||
                    data_meta_sample_count !== want_iq)
                    die("Data metadata mismatch or unexpected Data metadata");
            end
            if (context_meta_valid && context_meta_ready) begin
                seen_context_meta=seen_context_meta+1;
                if (seen_context_meta>want_context_meta ||
                    context_meta_stream_id !== want_sid || context_meta_seq !== want_seq ||
                    context_meta_time_sec !== want_sec || context_meta_time_ps !== want_ps ||
                    context_meta_changed !== want_changed ||
                    context_meta_bandwidth_hz !== want_bw ||
                    context_meta_rf_freq_hz !== want_rf ||
                    context_meta_sample_rate_hz !== want_fs)
                    die("Context metadata mismatch or unexpected Context metadata");
            end
            if (version_meta_valid && version_meta_ready) begin
                seen_version_meta=seen_version_meta+1;
                if (seen_version_meta>want_version_meta ||
                    version_meta_stream_id !== want_sid || version_meta_seq !== want_seq ||
                    version_meta_time_sec !== want_sec || version_meta_time_ps !== want_ps ||
                    version_meta_changed !== want_changed || version_meta_info !== want_info)
                    die("Version metadata mismatch or unexpected Version metadata");
            end
            if (data_iq_tvalid && data_iq_tready) begin
                if (seen_data_meta!=1 || seen_iq>=want_iq)
                    die("IQ received before Data metadata or from invalid packet");
                if (data_iq_tdata !== expected_iq[seen_iq] ||
                    data_iq_tlast !== (seen_iq==want_iq-1))
                    die("IQ data/order/TLAST mismatch");
                seen_iq=seen_iq+1;
            end
            if (dispatch_error_valid || data_error_valid ||
                context_error_valid || version_error_valid) begin
                seen_error=seen_error+1;
                if (seen_error>1) die("Unexpected duplicate/simultaneous error");
                case (want_error_source)
                    ERR_DISPATCH: if (!dispatch_error_valid ||
                        dispatch_error_code !== want_error_code ||
                        data_error_valid || context_error_valid || version_error_valid)
                        die("Dispatch error routing/code mismatch");
                    ERR_DATA: if (!data_error_valid ||
                        data_error_code !== want_error_code ||
                        dispatch_error_valid || context_error_valid || version_error_valid)
                        die("Data parser error routing/code mismatch");
                    ERR_CONTEXT: if (!context_error_valid ||
                        context_error_code !== want_error_code ||
                        dispatch_error_valid || data_error_valid || version_error_valid)
                        die("Context parser error routing/code mismatch");
                    ERR_VERSION: if (!version_error_valid ||
                        version_error_code !== want_error_code ||
                        dispatch_error_valid || data_error_valid || context_error_valid)
                        die("Version parser error routing/code mismatch");
                    default: die("Unexpected error event");
                endcase
            end
        end
    end

    // Deterministic backpressure on all three metadata sinks and IQ sink.
    // This tests real parser->dispatch ready propagation, not mocked ready.
    always @(negedge aclk) begin
        if (!aresetn) begin
            cycles=0;
            data_meta_ready=1;
            context_meta_ready=1;
            version_meta_ready=1;
            data_iq_tready=1;
        end else begin
            cycles=cycles+1;
            if (stress_ready) begin
                data_meta_ready     = ((cycles % 7) >= 3);
                context_meta_ready  = ((cycles % 5) >= 2);
                version_meta_ready  = ((cycles % 6) >= 3);
                data_iq_tready      = ((cycles % 4) >= 2);
            end else begin
                data_meta_ready=1;
                context_meta_ready=1;
                version_meta_ready=1;
                data_iq_tready=1;
            end
        end
    end

    initial begin
        aresetn=0;
        s_axis_pkt_tdata=0; s_axis_pkt_tvalid=0;
        s_axis_pkt_tkeep=4'hF; s_axis_pkt_tlast=0;
        data_filter_enable=0; version_filter_enable=0;
        expected_data_sid=32'd1; expected_version_sid=32'd2;
        active_case=0; stress_ready=0; testcase=0;
        want_error_source=ERR_NONE; want_error_code=0;
        tx_len=0; cycles=0;
        repeat (5) @(negedge aclk);
        aresetn=1;

        // Three real parsers in an interleaved flow; each keeps its own Seq baseline.
        build_context(32'd1,32'd100,32'h00BEBC20,32'd25000000,
                      4'd0,64'd123456,64'd2450000000,1'b1);
        want_error_source=ERR_NONE; arm_case(1,1); transmit; finish_case;

        build_data(4,10,32'd1,32'd101,4'd0,64'd987654);
        want_error_source=ERR_NONE; arm_case(2,1); transmit; finish_case;

        build_version(32'd2,32'd102,4'd0,64'd0,1'b1);
        want_error_source=ERR_NONE; arm_case(3,1); transmit; finish_case;

        build_data(1,11,32'd1,32'd103,4'd1,64'd2000);
        want_error_source=ERR_NONE; arm_case(4,1); transmit; finish_case;

        build_context(32'd1,32'd104,32'h00BEBC20,32'd25000000,
                      4'd1,64'd333,64'd2450000000,1'b0);
        want_error_source=ERR_NONE; arm_case(5,1); transmit; finish_case;

        build_version(32'd2,32'd105,4'd1,64'd444,1'b0);
        want_error_source=ERR_NONE; arm_case(6,1); transmit; finish_case;

        // Unsupported Type is drained ONLY by Dispatch.
        init_words(3);
        words[0]=32'hF860_0003; words[1]=32'h1234_5678; words[2]=0;
        reject_packet(ERR_DISPATCH,`DIFI_ERR_UNSUPPORTED_TYPE);
        arm_case(7,1); transmit; finish_case;

        build_data(3,12,32'd1,32'd106,4'd2,64'd555);
        words[0]=words[0] ^ 32'h0800_0000; // C=0 -> Header error
        reject_packet(ERR_DATA,`DIFI_ERR_HEADER);
        arm_case(8,1); transmit; finish_case;

        build_context(32'd1,32'd107,32'h00BEBC20,32'd25000000,
                      4'd2,64'd0,64'd2450000000,1'b0);
        words[25]=words[25] ^ 32'h0000_0001; // illegal Payload Format
        reject_packet(ERR_CONTEXT,`DIFI_ERR_CONTEXT_FIELD);
        arm_case(9,1); transmit; finish_case;

        build_version(32'd2,32'd108,4'd2,64'd0,1'b0);
        words[8]=words[8] ^ 32'h0000_0001; // invalid CIF1
        reject_packet(ERR_VERSION,`DIFI_ERR_VERSION_FIELD);
        arm_case(10,1); transmit; finish_case;

        // Fatal invalid packets must not advance the individual Seq baselines.
        // Previous *accepted* Data Seq=1; Seq=4 is nonfatal discontinuity.
        build_data(5,13,32'd1,32'd109,4'd4,64'd111);
        want_error_source=ERR_DATA; want_error_code=`DIFI_ERR_SEQ;
        arm_case(11,1); transmit; finish_case;

        build_data(2,14,32'd1,32'd110,4'd5,64'd222);
        want_error_source=ERR_NONE; arm_case(12,1); transmit; finish_case;

        data_filter_enable=1;
        build_data(3,15,32'd99,32'd111,4'd6,64'd333);
        reject_packet(ERR_DATA,`DIFI_ERR_STREAM_ID);
        arm_case(13,1); transmit; finish_case;

        build_context(32'd99,32'd112,32'h00BEBC20,32'd25000000,
                      4'd3,64'd0,64'd2450000000,1'b0);
        reject_packet(ERR_CONTEXT,`DIFI_ERR_STREAM_ID);
        arm_case(14,1); transmit; finish_case;

        version_filter_enable=1;
        build_version(32'd99,32'd113,4'd3,64'd0,1'b0);
        reject_packet(ERR_VERSION,`DIFI_ERR_STREAM_ID);
        arm_case(15,1); transmit; finish_case;

        build_data(4,16,32'd1,32'd114,4'd6,64'd444);
        want_error_source=ERR_NONE; arm_case(16,1); transmit; finish_case;

        build_version(32'd2,32'd115,4'd2,64'd0,1'b0);
        keeps[5]=4'b0111; // malformed TKEEP, classified as Size error
        reject_packet(ERR_VERSION,`DIFI_ERR_SIZE);
        arm_case(17,1); transmit; finish_case;

        build_data(3,17,32'd1,32'd116,4'd7,64'd555);
        tx_len=9; lasts[8]=1; // advertised 10 words, TLAST at word 8
        lasts[9]=0;
        reject_packet(ERR_DATA,`DIFI_ERR_TRUNCATED);
        arm_case(18,1); transmit; finish_case;

        // Final recovery, proving malformed packets do not poison boundaries.
        build_data(4,18,32'd1,32'd117,4'd7,64'd666);
        want_error_source=ERR_NONE; arm_case(19,1); transmit; finish_case;

        $display("[PASS] All 19 RX Dispatch + 3 real Parser integration tests");
        $finish;
    end

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_difi_rx_integration.vcd");
            $dumpvars(0,tb_difi_rx_integration);
        end
    end

    initial begin
        #20000000;
        die("Global watchdog timeout");
    end
endmodule
