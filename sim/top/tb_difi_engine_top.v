`timescale 1ns/1ps
`include "difi_v1_1_defs.vh"
// DIFI v1.5 full-engine regression; Verilog-2001.
// No RTL mocks: one cfg_regs, 3 TX, scheduler, dispatch, 3 RX parsers.
// Separate packet-level golden model and independent RX injection path.
module tb_difi_engine_top;

    reg aclk;
    reg aresetn;
    reg [7:0] s_axi_awaddr;
    reg [2:0] s_axi_awprot;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [7:0] s_axi_araddr;
    reg [2:0] s_axi_arprot;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;
    reg [31:0] time_sec;
    reg [63:0] time_ps;
    reg time_valid;
    reg data_available;
    reg context_periodic_trigger;
    reg version_periodic_trigger;
    wire [31:0] cfg_context_period_ms;
    wire [31:0] cfg_version_period_ms;
    wire tx_busy;
    reg [31:0] s_axis_iq_tdata;
    reg s_axis_iq_tvalid;
    wire s_axis_iq_tready;
    wire [31:0] m_axis_tx_pkt_tdata;
    wire m_axis_tx_pkt_tvalid;
    wire m_axis_tx_pkt_tready;
    wire [3:0] m_axis_tx_pkt_tkeep;
    wire m_axis_tx_pkt_tlast;
    wire [31:0] s_axis_rx_pkt_tdata;
    wire s_axis_rx_pkt_tvalid;
    wire s_axis_rx_pkt_tready;
    wire [3:0] s_axis_rx_pkt_tkeep;
    wire s_axis_rx_pkt_tlast;
    wire [31:0] m_axis_iq_tdata;
    wire m_axis_iq_tvalid;
    wire m_axis_iq_tready;
    wire m_axis_iq_tlast;
    wire m_data_meta_valid;
    wire m_data_meta_ready;
    wire [31:0] m_data_meta_stream_id;
    wire [3:0] m_data_meta_seq;
    wire [31:0] m_data_meta_time_sec;
    wire [63:0] m_data_meta_time_ps;
    wire [15:0] m_data_meta_sample_count;
    wire m_ctx_valid;
    wire m_ctx_ready;
    wire [31:0] m_ctx_stream_id;
    wire [3:0] m_ctx_seq;
    wire [31:0] m_ctx_time_sec;
    wire [63:0] m_ctx_time_ps;
    wire m_ctx_changed;
    wire [31:0] m_ctx_bandwidth_hz;
    wire [63:0] m_ctx_rf_freq_hz;
    wire [31:0] m_ctx_sample_rate_hz;
    wire m_ver_valid;
    wire m_ver_ready;
    wire [31:0] m_ver_stream_id;
    wire [3:0] m_ver_seq;
    wire [31:0] m_ver_time_sec;
    wire [63:0] m_ver_time_ps;
    wire m_ver_changed;
    wire [31:0] m_ver_info;
    wire rx_dispatch_error_valid;
    wire [3:0] rx_dispatch_error_code;
    wire rx_data_error_valid;
    wire [3:0] rx_data_error_code;
    wire rx_context_error_valid;
    wire [3:0] rx_context_error_code;
    wire rx_version_error_valid;
    wire [3:0] rx_version_error_code;

difi_engine_top dut (
    .aclk(aclk),
    .aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .time_sec(time_sec),
    .time_ps(time_ps),
    .time_valid(time_valid),
    .data_available(data_available),
    .context_periodic_trigger(context_periodic_trigger),
    .version_periodic_trigger(version_periodic_trigger),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms),
    .tx_busy(tx_busy),
    .s_axis_iq_tdata(s_axis_iq_tdata),
    .s_axis_iq_tvalid(s_axis_iq_tvalid),
    .s_axis_iq_tready(s_axis_iq_tready),
    .m_axis_tx_pkt_tdata(m_axis_tx_pkt_tdata),
    .m_axis_tx_pkt_tvalid(m_axis_tx_pkt_tvalid),
    .m_axis_tx_pkt_tready(m_axis_tx_pkt_tready),
    .m_axis_tx_pkt_tkeep(m_axis_tx_pkt_tkeep),
    .m_axis_tx_pkt_tlast(m_axis_tx_pkt_tlast),
    .s_axis_rx_pkt_tdata(s_axis_rx_pkt_tdata),
    .s_axis_rx_pkt_tvalid(s_axis_rx_pkt_tvalid),
    .s_axis_rx_pkt_tready(s_axis_rx_pkt_tready),
    .s_axis_rx_pkt_tkeep(s_axis_rx_pkt_tkeep),
    .s_axis_rx_pkt_tlast(s_axis_rx_pkt_tlast),
    .m_axis_iq_tdata(m_axis_iq_tdata),
    .m_axis_iq_tvalid(m_axis_iq_tvalid),
    .m_axis_iq_tready(m_axis_iq_tready),
    .m_axis_iq_tlast(m_axis_iq_tlast),
    .m_data_meta_valid(m_data_meta_valid),
    .m_data_meta_ready(m_data_meta_ready),
    .m_data_meta_stream_id(m_data_meta_stream_id),
    .m_data_meta_seq(m_data_meta_seq),
    .m_data_meta_time_sec(m_data_meta_time_sec),
    .m_data_meta_time_ps(m_data_meta_time_ps),
    .m_data_meta_sample_count(m_data_meta_sample_count),
    .m_ctx_valid(m_ctx_valid),
    .m_ctx_ready(m_ctx_ready),
    .m_ctx_stream_id(m_ctx_stream_id),
    .m_ctx_seq(m_ctx_seq),
    .m_ctx_time_sec(m_ctx_time_sec),
    .m_ctx_time_ps(m_ctx_time_ps),
    .m_ctx_changed(m_ctx_changed),
    .m_ctx_bandwidth_hz(m_ctx_bandwidth_hz),
    .m_ctx_rf_freq_hz(m_ctx_rf_freq_hz),
    .m_ctx_sample_rate_hz(m_ctx_sample_rate_hz),
    .m_ver_valid(m_ver_valid),
    .m_ver_ready(m_ver_ready),
    .m_ver_stream_id(m_ver_stream_id),
    .m_ver_seq(m_ver_seq),
    .m_ver_time_sec(m_ver_time_sec),
    .m_ver_time_ps(m_ver_time_ps),
    .m_ver_changed(m_ver_changed),
    .m_ver_info(m_ver_info),
    .rx_dispatch_error_valid(rx_dispatch_error_valid),
    .rx_dispatch_error_code(rx_dispatch_error_code),
    .rx_data_error_valid(rx_data_error_valid),
    .rx_data_error_code(rx_data_error_code),
    .rx_context_error_valid(rx_context_error_valid),
    .rx_context_error_code(rx_context_error_code),
    .rx_version_error_valid(rx_version_error_valid),
    .rx_version_error_code(rx_version_error_code)
);
// -----------------------------------------------------------------------------
// TB infrastructure.  Main path: TX -> optional beat stalls -> RX.
// Injection path uses the same RX input, with TX disabled/idle.
// TX/RX are NOT tied inside difi_engine_top itself.
// -----------------------------------------------------------------------------
localparam integer MAX_EXPECT = 96;
localparam integer MAX_IQ = 256;
localparam integer MAX_CYCLES = 180000;
localparam [1:0] OKAY=2'b00, SLVERR=2'b10;
localparam [3:0] K_DATA=4'h1, K_CTX=4'h4, K_VER=4'h5;
localparam [1:0] SRC_DISPATCH=2'd0, SRC_DATA=2'd1,
                 SRC_CONTEXT=2'd2, SRC_VERSION=2'd3;
localparam [7:0] REG_CONTROL=8'h00, REG_COMMAND=8'h04,
                 REG_STATUS=8'h08, REG_LAST_ERR=8'h0C,
                 REG_DATA_SID=8'h10, REG_VER_SID=8'h14,
                 REG_SAMPLES=8'h18, REG_FS=8'h1C,
                 REG_BW=8'h20, REG_RF_LO=8'h24, REG_RF_HI=8'h28,
                 REG_CTX_PERIOD=8'h2C, REG_VER_PERIOD=8'h30,
                 REG_RX_FILTER=8'h34, REG_RX_DATA_SID=8'h38,
                 REG_RX_VER_SID=8'h3C, REG_ACTIVE_DATA_SID=8'h40,
                 REG_ACTIVE_VER_SID=8'h44, REG_ACTIVE_SAMPLES=8'h48;

initial aclk=1'b0;
always #5 aclk=~aclk;
integer cycles;
reg loopback_en;
reg tx_force_stall;
reg stress_ready;
reg rx_inject_valid, rx_inject_last;
reg [31:0] rx_inject_data;
reg [3:0] rx_inject_keep;
reg [31:0] inject_word [0:300];
reg [3:0] inject_keep [0:300];
reg inject_last [0:300];
integer inject_len;
// One-beat *testbench-only* AXIS elastic buffer: ensures that injected
// backpressure never creates an illegal TVALID drop at the RX interface.
// It also permits deliberate inter-beat stalls without altering the DUT.
reg link_valid;
reg [31:0] link_data;
reg [3:0] link_keep;
reg link_last;
reg [2:0] link_delay;
wire tx_capture;
wire rx_deliver;
assign m_axis_tx_pkt_tready = loopback_en && !tx_force_stall &&
                               !link_valid && (link_delay==0);
assign tx_capture = m_axis_tx_pkt_tvalid && m_axis_tx_pkt_tready;
assign rx_deliver = loopback_en && link_valid && s_axis_rx_pkt_tready;
assign s_axis_rx_pkt_tdata  = loopback_en ? link_data : rx_inject_data;
assign s_axis_rx_pkt_tvalid = loopback_en ? link_valid : rx_inject_valid;
assign s_axis_rx_pkt_tkeep  = loopback_en ? link_keep : rx_inject_keep;
assign s_axis_rx_pkt_tlast  = loopback_en ? link_last : rx_inject_last;
always @(posedge aclk or negedge aresetn)begin
  if(!aresetn)begin
    link_valid<=0;link_delay<=0;
    link_data<=0;link_keep<=0;link_last<=0;
  end else if(loopback_en)begin
    if(link_valid)begin
      if(rx_deliver)begin
        link_valid<=0;
        link_delay<=stress_ready ? (cycles % 4) : 0;
      end
    end else if(tx_capture)begin
      link_valid<=1;
      link_data<=m_axis_tx_pkt_tdata;
      link_keep<=m_axis_tx_pkt_tkeep;
      link_last<=m_axis_tx_pkt_tlast;
    end else if(link_delay!=0)begin
      link_delay<=link_delay-1'b1;
    end
  end else begin
    link_valid<=0;
    link_delay<=0;
  end
end
assign m_axis_iq_tready    = !stress_ready || ((cycles%7)!=1 && (cycles%7)!=2);
assign m_data_meta_ready   = !stress_ready || ((cycles%11)>=5);
assign m_ctx_ready         = !stress_ready || ((cycles%13)>=6);
assign m_ver_ready         = !stress_ready || ((cycles%9)>=3);

// Packet reference model: expectations may be TX+RX or RX only.
reg [3:0]  ex_kind [0:MAX_EXPECT-1];
reg [31:0] ex_sid  [0:MAX_EXPECT-1];
reg [3:0]  ex_seq  [0:MAX_EXPECT-1];
reg [31:0] ex_sec  [0:MAX_EXPECT-1];
reg [63:0] ex_ps   [0:MAX_EXPECT-1];
reg [15:0] ex_n    [0:MAX_EXPECT-1];
integer    ex_tag  [0:MAX_EXPECT-1];
reg        ex_changed [0:MAX_EXPECT-1];
reg [31:0] ex_bw   [0:MAX_EXPECT-1];
reg [63:0] ex_rf   [0:MAX_EXPECT-1];
reg [31:0] ex_fs   [0:MAX_EXPECT-1];
reg [31:0] ex_info [0:MAX_EXPECT-1];
integer ex_total;
integer ex_tx_id  [0:MAX_EXPECT-1];
integer ex_data_id[0:MAX_EXPECT-1];
integer ex_ctx_id [0:MAX_EXPECT-1];
integer ex_ver_id [0:MAX_EXPECT-1];
integer ex_tx_count, ex_data_count, ex_ctx_count, ex_ver_count;
integer tx_seen, tx_word_index, data_meta_seen, ctx_seen, ver_seen;
integer iq_packets_seen, iq_word_index;
integer checks, current_tc;
integer tx_start_data, tx_start_ctx, tx_start_ver, ack_count, change_done_count;
reg [3:0] seq_data, seq_ctx, seq_ver;

reg [1:0] err_expect_src [0:63];
reg [3:0] err_expect_code[0:63];
integer err_expected, err_seen;
reg held_tx;
reg [31:0] held_tx_word;
reg [3:0] held_tx_keep;
reg held_tx_last;
reg held_rx;
reg [36:0] held_rx_bus;
reg held_iq;
reg [32:0] held_iq_bus;
reg held_dm, held_cm, held_vm;
reg [147:0] held_dm_bus;
reg [260:0] held_cm_bus;
reg [164:0] held_vm_bus;

function [31:0] iq_pattern;
  input integer tag, idx;
  begin
    iq_pattern = 32'h13579BDF ^ (tag*32'h00010001) ^ (idx*32'h00010103);
  end
endfunction

function [31:0] golden_word;
  input integer id, idx;
  reg [63:0] raw;
  begin
    golden_word=32'hDEADBEEF;
    case(ex_kind[id])
      K_DATA: begin
        case(idx)
          0: golden_word=32'h18600000 | ({28'd0,ex_seq[id]}<<16) | (7+ex_n[id]);
          1: golden_word=ex_sid[id];
          2: golden_word=`DIFI_OUI_WORD;
          3: golden_word=`DIFI_DATA_CLASS_WORD;
          4: golden_word=ex_sec[id];
          5: golden_word=ex_ps[id][63:32];
          6: golden_word=ex_ps[id][31:0];
          default: golden_word=iq_pattern(ex_tag[id],idx-7);
        endcase
      end
      K_CTX: begin
        case(idx)
          0: golden_word=`DIFI_CONTEXT_HEADER_BASE | ({28'd0,ex_seq[id]}<<16);
          1: golden_word=ex_sid[id];
          2: golden_word=`DIFI_OUI_WORD;
          3: golden_word=`DIFI_CONTEXT_CLASS_WORD;
          4: golden_word=ex_sec[id];
          5: golden_word=ex_ps[id][63:32];
          6: golden_word=ex_ps[id][31:0];
          7: golden_word=ex_changed[id] ? `DIFI_CONTEXT_CIF_CHANGED : `DIFI_CONTEXT_CIF_NO_CHANGE;
          8: golden_word=`DIFI_CONTEXT_REF_POINT;
          9,10: begin
            raw={32'd0,ex_bw[id]} << 20;
            golden_word=(idx==9) ? raw[63:32]:raw[31:0];
          end
          13,14: begin
            raw=ex_rf[id] << 20;
            golden_word=(idx==13) ? raw[63:32]:raw[31:0];
          end
          19,20: begin
            raw={32'd0,ex_fs[id]} << 20;
            golden_word=(idx==19) ? raw[63:32]:raw[31:0];
          end
          25: golden_word=`DIFI_CONTEXT_DPF_WORD0;
          26: golden_word=`DIFI_CONTEXT_DPF_WORD1;
          default: golden_word=0;
        endcase
      end
      K_VER: begin
        case(idx)
          0: golden_word=`DIFI_VERSION_HEADER_BASE | ({28'd0,ex_seq[id]}<<16);
          1: golden_word=ex_sid[id];
          2: golden_word=`DIFI_OUI_WORD;
          3: golden_word=`DIFI_VERSION_CLASS_WORD;
          4: golden_word=ex_sec[id];
          5: golden_word=ex_ps[id][63:32];
          6: golden_word=ex_ps[id][31:0];
          7: golden_word=ex_changed[id] ? `DIFI_VERSION_CIF_CHANGED : `DIFI_VERSION_CIF_NO_CHANGE;
          8: golden_word=`DIFI_VERSION_CIF1_WORD;
          9: golden_word=`DIFI_VERSION_V49_SPEC_WORD;
          10: golden_word=ex_info[id];
        endcase
      end
    endcase
  end
endfunction

function integer golden_length;
  input integer id;
  begin
    case(ex_kind[id])
      K_DATA: golden_length=7+ex_n[id];
      K_CTX: golden_length=27;
      K_VER: golden_length=11;
      default: golden_length=-1;
    endcase
  end
endfunction

task fail;
  input [8*230-1:0] reason;
  begin
    $display("[FAIL] TC%0d time=%0t cycles=%0d: %0s",current_tc,$time,cycles,reason);
    $display("  tx=%0d/%0d(word=%0d) dataMeta=%0d/%0d ctx=%0d/%0d ver=%0d/%0d IQpkts=%0d err=%0d/%0d",
         tx_seen,ex_tx_count,tx_word_index,data_meta_seen,ex_data_count,
         ctx_seen,ex_ctx_count,ver_seen,ex_ver_count,iq_packets_seen,err_seen,err_expected);
    $finish;
  end
endtask

task eq32;
  input [31:0] got,want;
  input [8*160-1:0] message;
  begin
    checks=checks+1;
    if(got!==want)begin
      $display("  got=%08h want=%08h",got,want);
      fail(message);
    end
  end
endtask

task eq64;
  input [63:0] got,want;
  input [8*160-1:0] message;
  begin
    checks=checks+1;
    if(got!==want)begin
      $display("  got=%016h want=%016h",got,want);
      fail(message);
    end
  end
endtask

task clear_expect;
  begin
    ex_total=0;ex_tx_count=0;ex_data_count=0;ex_ctx_count=0;ex_ver_count=0;
    err_expected=0;
    seq_data=0;seq_ctx=0;seq_ver=0;
  end
endtask

task add_expect;
  input [3:0] typ;
  input [31:0] sid,sec;
  input [3:0] seq;
  input [63:0] ps;
  input integer n,tag;
  input changed;
  input [31:0] bw,fs,info;
  input [63:0] rf;
  input is_tx, is_rx;
  integer k;
  begin
    if(ex_total>=MAX_EXPECT) fail("Expectation table overflow");
    k=ex_total;
    ex_total=ex_total+1;
    ex_kind[k]=typ;ex_sid[k]=sid;ex_seq[k]=seq;
    ex_sec[k]=sec;ex_ps[k]=ps;ex_n[k]=n;ex_tag[k]=tag;
    ex_changed[k]=changed;ex_bw[k]=bw;ex_rf[k]=rf;ex_fs[k]=fs;ex_info[k]=info;
    if(is_tx)begin
      ex_tx_id[ex_tx_count]=k;
      ex_tx_count=ex_tx_count+1;
    end
    if(is_rx)begin
      case(typ)
        K_DATA: begin ex_data_id[ex_data_count]=k; ex_data_count=ex_data_count+1; end
        K_CTX:  begin ex_ctx_id[ex_ctx_count]=k; ex_ctx_count=ex_ctx_count+1; end
        K_VER:  begin ex_ver_id[ex_ver_count]=k; ex_ver_count=ex_ver_count+1; end
        default: fail("Invalid expectation packet type");
      endcase
    end
  end
endtask

task expect_data;
  input integer n,tag;
  input [31:0] sid;
  input should_parse;
  begin
    add_expect(K_DATA,sid,time_sec,seq_data,time_ps,n,tag,1'b0,
               0,0,0,0,1'b1,should_parse);
    seq_data=seq_data+4'd1;
  end
endtask

task expect_ctx;
  input changed;
  input [31:0] sid, bw, fs;
  input [63:0] rf;
  input should_parse;
  begin
    add_expect(K_CTX,sid,time_sec,seq_ctx,time_ps,0,0,changed,
               bw,fs,0,rf,1'b1,should_parse);
    seq_ctx=seq_ctx+4'd1;
  end
endtask

task expect_ver;
  input changed;
  input [31:0] sid;
  input should_parse;
  begin
    // Defaults of difi_version_generator in the repository: 2026, day 252.
    add_expect(K_VER,sid,time_sec,seq_ver,time_ps,0,0,changed,
               0,0,32'h34FC0400,0,1'b1,should_parse);
    seq_ver=seq_ver+4'd1;
  end
endtask

task add_rx_only_ver;
  input [3:0] seq;
  begin
    add_expect(K_VER,32'd2,32'd4050,seq,64'd0,0,0,1'b0,
               0,0,32'h34FC0400,0,1'b0,1'b1);
  end
endtask

task expect_error;
  input [1:0] src;
  input [3:0] code;
  begin
    if(err_expected>=64) fail("Error expectation table overflow");
    err_expect_src[err_expected]=src;
    err_expect_code[err_expected]=code;
    err_expected=err_expected+1;
  end
endtask

task check_error;
  input [1:0] src;
  input [3:0] code;
  begin
    checks=checks+1;
    if(err_seen>=err_expected)fail("Unexpected extra error event");
    if(err_expect_src[err_seen]!==src || err_expect_code[err_seen]!==code)begin
      $display("  error #%0d: source=%0d code=%h expected source=%0d code=%h",
          err_seen,src,code,err_expect_src[err_seen],err_expect_code[err_seen]);
      fail("Wrong error source/code or error ordering");
    end
    err_seen=err_seen+1;
  end
endtask

// -----------------------------------------------------------------------------
// Handshake monitors: all golden checks independent of DUT internal payload.
// Sample before NBA state updates; stimulus changes on negedge.
// -----------------------------------------------------------------------------
always @(posedge aclk) begin : scoreboard
  integer id, expected_len;
  if(!aresetn)begin
    tx_seen=0;tx_word_index=0;
    data_meta_seen=0;ctx_seen=0;ver_seen=0;
    iq_packets_seen=0;iq_word_index=0;
    err_seen=0;
    held_tx=0;held_rx=0;held_iq=0;
    held_dm=0;held_cm=0;held_vm=0;
    tx_start_data=0;tx_start_ctx=0;tx_start_ver=0;
    ack_count=0;change_done_count=0;
  end else begin
    // TX AXIS invariants, including a stalled TLAST.
    if(held_tx)begin
      checks=checks+1;
      if(m_axis_tx_pkt_tvalid!==1'b1 ||
         m_axis_tx_pkt_tdata!==held_tx_word ||
         m_axis_tx_pkt_tkeep!==held_tx_keep ||
         m_axis_tx_pkt_tlast!==held_tx_last)
         fail("TX AXIS violated stable-while-stalled requirement");
    end
    held_tx=m_axis_tx_pkt_tvalid && !m_axis_tx_pkt_tready;
    if(held_tx)begin
      held_tx_word=m_axis_tx_pkt_tdata;
      held_tx_keep=m_axis_tx_pkt_tkeep;
      held_tx_last=m_axis_tx_pkt_tlast;
    end

    // Verify stall stability at both sides of the link and at all RX outputs.
    if(held_rx)begin
      checks=checks+1;
      if(!s_axis_rx_pkt_tvalid ||
         {s_axis_rx_pkt_tdata,s_axis_rx_pkt_tkeep,s_axis_rx_pkt_tlast} !== held_rx_bus)
         fail("RX input AXIS not stable during backpressure");
    end
    held_rx=s_axis_rx_pkt_tvalid && !s_axis_rx_pkt_tready;
    if(held_rx) held_rx_bus={s_axis_rx_pkt_tdata,s_axis_rx_pkt_tkeep,s_axis_rx_pkt_tlast};
    if(held_iq)begin
      checks=checks+1;
      if(!m_axis_iq_tvalid || {m_axis_iq_tdata,m_axis_iq_tlast} !== held_iq_bus)
        fail("RX IQ changed under backpressure");
    end
    held_iq=m_axis_iq_tvalid && !m_axis_iq_tready;
    if(held_iq)held_iq_bus={m_axis_iq_tdata,m_axis_iq_tlast};

    if(held_dm)begin
      checks=checks+1;
      if(!m_data_meta_valid || {m_data_meta_stream_id,m_data_meta_seq,
         m_data_meta_time_sec,m_data_meta_time_ps,m_data_meta_sample_count} !== held_dm_bus)
         fail("Data metadata changed under backpressure");
    end
    held_dm=m_data_meta_valid && !m_data_meta_ready;
    if(held_dm)held_dm_bus={m_data_meta_stream_id,m_data_meta_seq,
                            m_data_meta_time_sec,m_data_meta_time_ps,m_data_meta_sample_count};
    if(held_cm)begin
      checks=checks+1;
      if(!m_ctx_valid || {m_ctx_stream_id,m_ctx_seq,m_ctx_time_sec,m_ctx_time_ps,
          m_ctx_changed,m_ctx_bandwidth_hz,m_ctx_rf_freq_hz,
          m_ctx_sample_rate_hz} !== held_cm_bus)
         fail("Context metadata changed under backpressure");
    end
    held_cm=m_ctx_valid && !m_ctx_ready;
    if(held_cm)held_cm_bus={m_ctx_stream_id,m_ctx_seq,m_ctx_time_sec,m_ctx_time_ps,
         m_ctx_changed,m_ctx_bandwidth_hz,m_ctx_rf_freq_hz,m_ctx_sample_rate_hz};
    if(held_vm)begin
      checks=checks+1;
      if(!m_ver_valid || {m_ver_stream_id,m_ver_seq,m_ver_time_sec,m_ver_time_ps,
          m_ver_changed,m_ver_info} !== held_vm_bus)
         fail("Version metadata changed under backpressure");
    end
    held_vm=m_ver_valid && !m_ver_ready;
    if(held_vm)held_vm_bus={m_ver_stream_id,m_ver_seq,m_ver_time_sec,m_ver_time_ps,
         m_ver_changed,m_ver_info};

    if(dut.data_pkt_start)tx_start_data=tx_start_data+1;
    if(dut.context_pkt_start)tx_start_ctx=tx_start_ctx+1;
    if(dut.version_pkt_start)tx_start_ver=tx_start_ver+1;
    if((dut.data_pkt_start && dut.context_pkt_start)||
       (dut.data_pkt_start && dut.version_pkt_start)||
       (dut.context_pkt_start && dut.version_pkt_start))
       fail("Two TX pkt_start events overlapped");
    if((dut.data_pkt_start||dut.context_pkt_start||dut.version_pkt_start) &&
       (!dut.tx_enable || !time_valid))
       fail("Packet started while disabled/time invalid");
    if(dut.cfg_commit_ack)begin
      ack_count=ack_count+1;
      if(tx_busy || !dut.cfg_commit_req || dut.data_pkt_start ||
         dut.context_pkt_start || dut.version_pkt_start)
         fail("Invalid commit ACK boundary");
    end
    if(dut.context_change_done)begin
      change_done_count=change_done_count+1;
      if(!dut.context_pkt_done)fail("Changed Context done without complete packet");
    end

    if(m_axis_tx_pkt_tvalid && m_axis_tx_pkt_tready)begin
      if(tx_seen>=ex_tx_count)fail("Unexpected TX packet beat");
      id=ex_tx_id[tx_seen];
      expected_len=golden_length(id);
      if(tx_word_index>=expected_len)fail("TX packet too long");
      eq32(m_axis_tx_pkt_tdata,golden_word(id,tx_word_index),"TX word mismatch");
      checks=checks+1;
      if(m_axis_tx_pkt_tkeep!==4'hF)fail("TX bad TKEEP");
      if(m_axis_tx_pkt_tlast!==(tx_word_index==expected_len-1))
         fail("TX misplaced TLAST");
      if(m_axis_tx_pkt_tlast)begin
        tx_seen=tx_seen+1;
        tx_word_index=0;
      end else tx_word_index=tx_word_index+1;
    end

    if(m_data_meta_valid && m_data_meta_ready)begin
      if(data_meta_seen>=ex_data_count)fail("Unexpected Data metadata");
      id=ex_data_id[data_meta_seen];
      eq32(m_data_meta_stream_id,ex_sid[id],"Data meta SID");
      eq32({28'd0,m_data_meta_seq},{28'd0,ex_seq[id]},"Data meta seq");
      eq32(m_data_meta_time_sec,ex_sec[id],"Data meta timestamp sec");
      eq64(m_data_meta_time_ps,ex_ps[id],"Data meta timestamp ps");
      eq32({16'd0,m_data_meta_sample_count},{16'd0,ex_n[id]},"Data meta sample count");
      data_meta_seen=data_meta_seen+1;
    end
    if(m_ctx_valid && m_ctx_ready)begin
      if(ctx_seen>=ex_ctx_count)fail("Unexpected Context metadata");
      id=ex_ctx_id[ctx_seen];
      eq32(m_ctx_stream_id,ex_sid[id],"Context meta SID");
      eq32({28'd0,m_ctx_seq},{28'd0,ex_seq[id]},"Context meta seq");
      eq32(m_ctx_time_sec,ex_sec[id],"Context timestamp sec");
      eq64(m_ctx_time_ps,ex_ps[id],"Context timestamp ps");
      eq32({31'd0,m_ctx_changed},{31'd0,ex_changed[id]},"Context change bit");
      eq32(m_ctx_bandwidth_hz,ex_bw[id],"Context bandwidth");
      eq64(m_ctx_rf_freq_hz,ex_rf[id],"Context RF");
      eq32(m_ctx_sample_rate_hz,ex_fs[id],"Context sample rate");
      ctx_seen=ctx_seen+1;
    end
    if(m_ver_valid && m_ver_ready)begin
      if(ver_seen>=ex_ver_count)fail("Unexpected Version metadata");
      id=ex_ver_id[ver_seen];
      eq32(m_ver_stream_id,ex_sid[id],"Version meta SID");
      eq32({28'd0,m_ver_seq},{28'd0,ex_seq[id]},"Version meta seq");
      eq32(m_ver_time_sec,ex_sec[id],"Version timestamp sec");
      eq64(m_ver_time_ps,ex_ps[id],"Version timestamp ps");
      eq32({31'd0,m_ver_changed},{31'd0,ex_changed[id]},"Version changed bit");
      eq32(m_ver_info,ex_info[id],"Version info");
      ver_seen=ver_seen+1;
    end
    if(m_axis_iq_tvalid && m_axis_iq_tready)begin
      if(iq_packets_seen>=ex_data_count)fail("Unexpected extra IQ beat");
      if(data_meta_seen<=iq_packets_seen)
         fail("IQ appeared before its Data metadata handshake");
      id=ex_data_id[iq_packets_seen];
      eq32(m_axis_iq_tdata,iq_pattern(ex_tag[id],iq_word_index),"RX IQ payload mismatch");
      checks=checks+1;
      if(m_axis_iq_tlast!==(iq_word_index==ex_n[id]-1))
         fail("IQ TLAST at wrong sample");
      if(m_axis_iq_tlast)begin
         iq_packets_seen=iq_packets_seen+1;
         iq_word_index=0;
      end else iq_word_index=iq_word_index+1;
    end
    if(rx_dispatch_error_valid)check_error(SRC_DISPATCH,rx_dispatch_error_code);
    if(rx_data_error_valid)check_error(SRC_DATA,rx_data_error_code);
    if(rx_context_error_valid)check_error(SRC_CONTEXT,rx_context_error_code);
    if(rx_version_error_valid)check_error(SRC_VERSION,rx_version_error_code);
  end
end

always @(posedge aclk) begin
  if(!aresetn) cycles<=0;
  else cycles<=cycles+1;
end
initial begin
  #1800000;
  fail("Global simulation watchdog timed out");
end

// -----------------------------------------------------------------------------
// Stimulus/AXI4-Lite bus functional models (AW and W independent ready).
// Every wait is bounded; no waveform-only pass criteria.
// -----------------------------------------------------------------------------
task axi_write;
  input [7:0] addr;
  input [31:0] value;
  input [3:0] strb;
  input [1:0] exp_resp;
  integer timeout;
  reg aw_done,w_done,b_done;
  begin
    @(negedge aclk);
    s_axi_awaddr=addr;s_axi_awprot=0;s_axi_awvalid=1;
    s_axi_wdata=value;s_axi_wstrb=strb;s_axi_wvalid=1;
    s_axi_bready=1;
    aw_done=0;w_done=0;b_done=0;timeout=0;
    while(!b_done && timeout<100)begin
      @(posedge aclk);
      if(s_axi_awvalid && s_axi_awready)aw_done=1;
      if(s_axi_wvalid && s_axi_wready)w_done=1;
      if(s_axi_bvalid && s_axi_bready)begin
        eq32({30'd0,s_axi_bresp},{30'd0,exp_resp},"AXI write BRESP");
        b_done=1;
      end
      @(negedge aclk);
      if(aw_done)s_axi_awvalid=0;
      if(w_done)s_axi_wvalid=0;
      timeout=timeout+1;
    end
    if(!b_done)fail("AXI write response timeout");
    s_axi_bready=0;
  end
endtask

task axi_read;
  input [7:0] addr;
  input [31:0] exp_data;
  integer timeout;
  reg ar_done,r_done;
  begin
    @(negedge aclk);
    s_axi_araddr=addr;s_axi_arprot=0;s_axi_arvalid=1;
    s_axi_rready=1;
    ar_done=0;r_done=0;timeout=0;
    while(!r_done && timeout<100)begin
      @(posedge aclk);
      if(s_axi_arvalid && s_axi_arready)ar_done=1;
      if(s_axi_rvalid && s_axi_rready)begin
        eq32({30'd0,s_axi_rresp},32'd0,"AXI read RRESP");
        eq32(s_axi_rdata,exp_data,"AXI read RDATA");
        r_done=1;
      end
      @(negedge aclk);
      if(ar_done)s_axi_arvalid=0;
      timeout=timeout+1;
    end
    if(!r_done)fail("AXI read response timeout");
    s_axi_rready=0;
  end
endtask

task wait_all;
  integer t;
  reg finished;
  begin
    t=0; finished=0;
    while(!finished && t<MAX_CYCLES)begin
      @(negedge aclk);
      finished = tx_seen==ex_tx_count && data_meta_seen==ex_data_count &&
                 ctx_seen==ex_ctx_count && ver_seen==ex_ver_count &&
                 iq_packets_seen==ex_data_count && err_seen==err_expected &&
                 tx_word_index==0 && iq_word_index==0;
      t=t+1;
    end
    if(!finished)fail("Timeout waiting for expected TX/RX completions");
    repeat(8) @(negedge aclk); // catch delayed duplicate events
    if(tx_seen!=ex_tx_count || data_meta_seen!=ex_data_count ||
       ctx_seen!=ex_ctx_count || ver_seen!=ex_ver_count ||
       iq_packets_seen!=ex_data_count || err_seen!=err_expected)
       fail("Completion counts changed unexpectedly");
  end
endtask

task wait_tx_count;
  input integer target;
  integer t;
  begin
    t=0;
    while(tx_seen<target && t<MAX_CYCLES)begin
      @(negedge aclk);t=t+1;
    end
    if(tx_seen<target)fail("Timeout waiting for TX packet count");
  end
endtask

task wait_ack_count;
  input integer target;
  integer t;
  begin
    t=0;
    while(ack_count<target && t<3000)begin
      @(negedge aclk);t=t+1;
    end
    if(ack_count<target)fail("Timeout waiting for commit ACK");
  end
endtask

task wait_pending_clear;
  integer t;
  begin
    t=0;
    while(dut.context_change_pending!==1'b0 && t<3000)begin
      @(negedge aclk);t=t+1;
    end
    if(dut.context_change_pending!==1'b0)fail("Context change never cleared");
  end
endtask

task send_iq;
  input integer n,tag,gaps;
  integer j,timeout,k;
  begin
    for(j=0;j<n;j=j+1)begin
      if(gaps!=0 && j!=0)begin
        @(negedge aclk);
        s_axis_iq_tvalid=0;
        data_available=0;
        for(k=0;k<((j*3+tag)%4);k=k+1)@(negedge aclk);
      end
      @(negedge aclk);
      s_axis_iq_tdata=iq_pattern(tag,j);
      s_axis_iq_tvalid=1;
      data_available=1;
      timeout=0;
      @(posedge aclk);
      while(s_axis_iq_tready!==1'b1 && timeout<MAX_CYCLES)begin
        timeout=timeout+1; @(posedge aclk);
      end
      if(s_axis_iq_tready!==1'b1)fail("Timeout: source IQ sample never accepted");
    end
    @(negedge aclk);
    s_axis_iq_tvalid=0;
    data_available=0;
  end
endtask

task pulse_context;
  begin
    @(negedge aclk);context_periodic_trigger=1;
    @(negedge aclk);context_periodic_trigger=0;
  end
endtask

task pulse_version;
  begin
    @(negedge aclk);version_periodic_trigger=1;
    @(negedge aclk);version_periodic_trigger=0;
  end
endtask

task pulse_both;
  begin
    @(negedge aclk);
    context_periodic_trigger=1;version_periodic_trigger=1;
    @(negedge aclk);
    context_periodic_trigger=0;version_periodic_trigger=0;
  end
endtask

task inject_prepared;
  integer j,t;
  begin
    if(loopback_en)fail("RX injection requires loopback disabled");
    for(j=0;j<inject_len;j=j+1)begin
      @(negedge aclk);
      rx_inject_data=inject_word[j];rx_inject_keep=inject_keep[j];
      rx_inject_last=inject_last[j];rx_inject_valid=1;
      t=0;
      @(posedge aclk);
      while(s_axis_rx_pkt_tready!==1'b1 && t<MAX_CYCLES)begin
        t=t+1;@(posedge aclk);
      end
      if(s_axis_rx_pkt_tready!==1'b1)fail("Injected RX beat timeout");
    end
    @(negedge aclk);
    rx_inject_valid=0;rx_inject_last=0;
  end
endtask

task make_inject_data;
  input integer n,tag;
  input [31:0] sid;
  input [3:0] seq;
  integer j;
  begin
    inject_len=n+7;
    inject_word[0]=32'h18600000 | ({28'd0,seq}<<16) | inject_len;
    inject_word[1]=sid;
    inject_word[2]=`DIFI_OUI_WORD;
    inject_word[3]=`DIFI_DATA_CLASS_WORD;
    inject_word[4]=32'd4050;
    inject_word[5]=0;inject_word[6]=0;
    for(j=0;j<n;j=j+1)inject_word[j+7]=iq_pattern(tag,j);
    for(j=0;j<inject_len;j=j+1)begin
      inject_keep[j]=4'hF;inject_last[j]=(j==inject_len-1);
    end
  end
endtask

task make_inject_ctx;
  input [31:0] sid;
  input [3:0] seq;
  integer j;
  reg [63:0] raw;
  begin
    inject_len=27;
    for(j=0;j<27;j=j+1)begin
      inject_word[j]=0;
      inject_keep[j]=4'hF;inject_last[j]=(j==26);
    end
    inject_word[0]=`DIFI_CONTEXT_HEADER_BASE | ({28'd0,seq}<<16);
    inject_word[1]=sid;
    inject_word[2]=`DIFI_OUI_WORD;
    inject_word[3]=`DIFI_CONTEXT_CLASS_WORD;
    inject_word[4]=32'd4050;
    inject_word[7]=`DIFI_CONTEXT_CIF_NO_CHANGE;
    inject_word[8]=`DIFI_CONTEXT_REF_POINT;
    raw=64'd1000000<<20;
    inject_word[9]=raw[63:32];inject_word[10]=raw[31:0];
    inject_word[13]=0;inject_word[14]=0;
    inject_word[19]=raw[63:32];inject_word[20]=raw[31:0];
    inject_word[25]=`DIFI_CONTEXT_DPF_WORD0;
    inject_word[26]=`DIFI_CONTEXT_DPF_WORD1;
  end
endtask

task make_inject_ver;
  input [31:0] sid;
  input [3:0] seq;
  integer j;
  begin
    inject_len=11;
    for(j=0;j<11;j=j+1)begin
      inject_word[j]=0;
      inject_keep[j]=4'hF;inject_last[j]=(j==10);
    end
    inject_word[0]=`DIFI_VERSION_HEADER_BASE | ({28'd0,seq}<<16);
    inject_word[1]=sid;
    inject_word[2]=`DIFI_OUI_WORD;
    inject_word[3]=`DIFI_VERSION_CLASS_WORD;
    inject_word[4]=32'd4050;
    inject_word[7]=`DIFI_VERSION_CIF_NO_CHANGE;
    inject_word[8]=`DIFI_VERSION_CIF1_WORD;
    inject_word[9]=`DIFI_VERSION_V49_SPEC_WORD;
    inject_word[10]=32'h34FC0400;
  end
endtask

task quiet_for;
  input integer n;
  integer x;
  begin
    for(x=0;x<n;x=x+1)@(negedge aclk);
  end
endtask

integer i,base,old_ack,old_done;
initial begin
  // Reset and defaults.
  aresetn=0;
  s_axi_awaddr=0;s_axi_awprot=0;s_axi_awvalid=0;
  s_axi_wdata=0;s_axi_wstrb=0;s_axi_wvalid=0;s_axi_bready=0;
  s_axi_araddr=0;s_axi_arprot=0;s_axi_arvalid=0;s_axi_rready=0;
  time_sec=32'd1000;time_ps=64'd123456789;time_valid=0;
  data_available=0;context_periodic_trigger=0;version_periodic_trigger=0;
  s_axis_iq_tdata=0;s_axis_iq_tvalid=0;
  loopback_en=1;tx_force_stall=0;stress_ready=0;
  rx_inject_valid=0;rx_inject_data=0;rx_inject_last=0;rx_inject_keep=4'hF;
  cycles=0;checks=0;current_tc=0;
  clear_expect;
  if($test$plusargs("vcd"))begin
    $dumpfile("tb_difi_engine_top.vcd");
    $dumpvars(0,tb_difi_engine_top);
  end
  repeat(6)@(negedge aclk);
  aresetn=1;
  quiet_for(3);

  current_tc=1;
  $display("[TC01] Reset mirrors, disabled TX, time_valid gating");
  axi_read(REG_CONTROL,0);
  axi_read(REG_ACTIVE_SAMPLES,256);
  axi_read(REG_ACTIVE_DATA_SID,1);
  axi_read(REG_ACTIVE_VER_SID,2);
  eq32(cfg_context_period_ms,1000,"Default context period");
  eq32(cfg_version_period_ms,1000,"Default version period");
  axi_write(REG_CONTROL,1,4'h1,OKAY);
  quiet_for(25); // tx_enable alone may not send with invalid time.
  if(tx_seen!=0 || tx_busy)fail("TX started before valid Time Source");

  current_tc=2;
  $display("[TC02] Version(changed) -> Context(changed) after time becomes valid");
  expect_ver(1,2,1);
  expect_ctx(1,1,1000000,1000000,0,1);
  @(negedge aclk);time_valid=1;
  wait_all;
  wait_pending_clear;

  current_tc=3;
  $display("[TC03] Max Data N=256, complete TX/RX IQ preservation");
  stress_ready=1;
  expect_data(256,10,1,1);
  send_iq(256,10,1);
  wait_all;
  stress_ready=0;

  current_tc=4;
  $display("[TC04] Concurrent periodic triggers; Context(no change) before Version");
  expect_ctx(0,1,1000000,1000000,0,1);
  expect_ver(0,2,1);
  pulse_both;
  wait_all;

  current_tc=5;
  $display("[TC05] Atomic AXI commit, changed Context + new active fields");
  axi_write(REG_DATA_SID,32'h00001111,4'hF,OKAY);
  axi_write(REG_VER_SID,32'h00002222,4'hF,OKAY);
  axi_write(REG_SAMPLES,4,4'hF,OKAY);
  axi_write(REG_FS,2000000,4'hF,OKAY);
  axi_write(REG_BW,1000000,4'hF,OKAY);
  axi_write(REG_RF_LO,100000000,4'hF,OKAY);
  axi_write(REG_RF_HI,0,4'hF,OKAY);
  axi_write(REG_CTX_PERIOD,500,4'hF,OKAY);
  axi_write(REG_VER_PERIOD,0,4'hF,OKAY);
  axi_read(REG_ACTIVE_DATA_SID,1); // shadow must not leak into active.
  old_ack=ack_count;
  expect_ctx(1,32'h1111,1000000,2000000,100000000,1);
  axi_write(REG_COMMAND,1,4'h1,OKAY);
  wait_ack_count(old_ack+1);
  wait_all;
  wait_pending_clear;
  axi_read(REG_ACTIVE_DATA_SID,32'h1111);
  axi_read(REG_ACTIVE_VER_SID,32'h2222);
  axi_read(REG_ACTIVE_SAMPLES,4);
  eq32(cfg_context_period_ms,500,"New context period output");
  eq32(cfg_version_period_ms,0,"Zero Version period output");

  current_tc=6;
  $display("[TC06] RX filters enabled and independent Version SID");
  axi_write(REG_RX_DATA_SID,32'h1111,4'hF,OKAY);
  axi_write(REG_RX_VER_SID,32'h2222,4'hF,OKAY);
  axi_write(REG_RX_FILTER,3,4'h1,OKAY);
  expect_ver(0,32'h2222,1);
  pulse_version;
  wait_all;
  expect_data(4,20,32'h1111,1);
  send_iq(4,20,0);
  wait_all;

  current_tc=7;
  $display("[TC07] Busy Data ownership + Commit; wait boundary; Changed Context");
  axi_write(REG_SAMPLES,1,4'hF,OKAY); // shadow changes before in-flight packet.
  base=tx_seen;
  expect_data(4,21,32'h1111,1);
  expect_ctx(1,32'h1111,1000000,2000000,100000000,1);
  old_ack=ack_count;
  fork
    begin
      send_iq(4,21,0);
    end
    begin
      i=0;
      while((!tx_busy || tx_word_index<2) && i<5000)begin
        @(negedge aclk);i=i+1;
      end
      if(i>=5000)fail("Data did not start before commit test");
      @(negedge aclk);tx_force_stall=1;
      axi_write(REG_COMMAND,1,4'h1,OKAY);
      if(ack_count!=old_ack)fail("ACK occurred while Data TX stalled");
      quiet_for(17);
      if(ack_count!=old_ack)fail("Commit ACK did not wait for packet boundary");
      @(negedge aclk);tx_force_stall=0;
    end
  join
  wait_ack_count(old_ack+1);
  wait_all;
  axi_read(REG_ACTIVE_SAMPLES,1);
  wait_pending_clear;

  current_tc=8;
  $display("[TC08] Single-sample Data, RX IQ TLAST, stalls");
  stress_ready=1;
  expect_data(1,30,32'h1111,1);
  send_iq(1,30,0);
  wait_all;
  stress_ready=0;

  current_tc=9;
  $display("[TC09] Periodic triggers while busy, coalescing and arbitration");
  expect_data(1,31,32'h1111,1);
  expect_ctx(0,32'h1111,1000000,2000000,100000000,1);
  expect_ver(0,32'h2222,1);
  // Stall on the Data packet while injecting multiple periodic events.
  fork
    begin send_iq(1,31,0); end
    begin
      i=0;
      while((!tx_busy || tx_word_index<1) && i<4000)begin
        @(negedge aclk);i=i+1;
      end
      if(i>=4000)fail("No active packet for trigger-coalescing test");
      @(negedge aclk);tx_force_stall=1;
      pulse_both;
      pulse_both;
      @(negedge aclk);tx_force_stall=0;
    end
  join
  wait_all;

  current_tc=10;
  $display("[TC10] RX filter mismatch drops IQ, independent of TX packet correctness");
  axi_write(REG_RX_DATA_SID,32'h9999,4'hF,OKAY);
  expect_data(1,40,32'h1111,0); // TX expected, RX must reject.
  expect_error(SRC_DATA,`DIFI_ERR_STREAM_ID);
  send_iq(1,40,0);
  wait_all;
  axi_write(REG_RX_DATA_SID,32'h1111,4'hF,OKAY);
  // Lost sequence due to rejected packet: next valid Data is nonfatally reported.
  expect_data(1,41,32'h1111,1);
  expect_error(SRC_DATA,`DIFI_ERR_SEQ);
  send_iq(1,41,0);
  wait_all;

  current_tc=11;
  $display("[TC11] tx_enable off: no new packet; periodic trigger remembered");
  axi_write(REG_CONTROL,0,4'h1,OKAY);
  pulse_context;
  quiet_for(30);
  if(tx_busy || tx_seen!=ex_tx_count)fail("TX sent packet despite disable");
  expect_ctx(0,32'h1111,1000000,2000000,100000000,1);
  axi_write(REG_CONTROL,1,4'h1,OKAY);
  wait_all;

  current_tc=12;
  $display("[TC12] Data/Context/Version independent 4-bit sequence wrap");
  // 16 iterations with each type, checking whole words and metadata.
  for(i=0;i<16;i=i+1)begin
    expect_data(1,50+i,32'h1111,1);
    send_iq(1,50+i,0);
    wait_all;
    expect_ctx(0,32'h1111,1000000,2000000,100000000,1);
    pulse_context;
    wait_all;
    expect_ver(0,32'h2222,1);
    pulse_version;
    wait_all;
  end

  current_tc=13;
  $display("[TC13] IQ TVALID cannot start Data without data_available");
  expect_data(1,77,32'h1111,1);
  @(negedge aclk);
  s_axis_iq_tdata=iq_pattern(77,0);
  s_axis_iq_tvalid=1;
  data_available=0;
  quiet_for(22);
  if(tx_seen!=ex_tx_count-1 || s_axis_iq_tready)
      fail("Spontaneous Data start despite data_available=0");
  @(negedge aclk);data_available=1;
  i=0;
  @(posedge aclk);
  while(s_axis_iq_tready!==1'b1 && i<10000)begin
    i=i+1;@(posedge aclk);
  end
  if(i>=10000)fail("IQ did not resume when data_available asserted");
  @(negedge aclk);s_axis_iq_tvalid=0;data_available=0;
  wait_all;

  current_tc=14;
  $display("[TC14] Disabling TX mid-packet does not abort current packet");
  expect_data(1,78,32'h1111,1);
  fork
    begin send_iq(1,78,0); end
    begin
      i=0;
      while((!tx_busy || tx_word_index<2) && i<4000)begin
        @(negedge aclk);i=i+1;
      end
      if(i>=4000)fail("No in-flight Data for TX disable test");
      @(negedge aclk);tx_force_stall=1;
      axi_write(REG_CONTROL,0,4'h1,OKAY);
      if(!tx_busy)fail("tx_enable=0 aborted in-flight packet");
      quiet_for(13);
      if(!tx_busy)fail("Ownership lost on stalled packet");
      @(negedge aclk);tx_force_stall=0;
    end
  join
  wait_all;
  quiet_for(20);
  if(tx_busy)fail("TX remained busy after disabled packet completion");

  current_tc=15;
  $display("[TC15] Commit ACK while TX disabled and time invalid");
  @(negedge aclk);time_valid=0;
  axi_write(REG_SAMPLES,2,4'hF,OKAY);
  old_ack=ack_count;
  axi_write(REG_COMMAND,1,4'h1,OKAY);
  wait_ack_count(old_ack+1);
  if(!dut.context_change_pending)fail("Commit failed to mark Context change");
  quiet_for(13);
  if(tx_seen!=ex_tx_count)fail("Disabled+invalid-time TX unexpectedly active");
  expect_ctx(1,32'h1111,1000000,2000000,100000000,1);
  @(negedge aclk);time_valid=1;
  axi_write(REG_CONTROL,1,4'h1,OKAY);
  wait_all;
  wait_pending_clear;
  axi_read(REG_ACTIVE_SAMPLES,2);

  current_tc=16;
  $display("[TC16] Invalid Commit rejected; Active and schedule unchanged");
  axi_write(REG_SAMPLES,0,4'hF,OKAY);
  axi_write(REG_COMMAND,1,4'h1,SLVERR);
  axi_read(REG_LAST_ERR,1); // invalid samples: highest-priority commit error
  axi_read(REG_ACTIVE_SAMPLES,2);
  quiet_for(12);
  if(tx_seen!=ex_tx_count || dut.context_change_pending)
      fail("Rejected Commit created an unexpected Context announcement");
  axi_write(REG_SAMPLES,2,4'hF,OKAY);

  current_tc=17;
  $display("[TC17] Data timestamp snapshot while Packet output is backpressured");
  @(negedge aclk);
  time_sec=32'd2000;
  time_ps=64'd987654321;
  expect_data(2,79,32'h1111,1);
  fork
    begin send_iq(2,79,0); end
    begin
      i=0;
      while((!tx_busy || tx_word_index<3) && i<4000)begin
        @(negedge aclk);i=i+1;
      end
      if(i>=4000)fail("Data header absent in timestamp snapshot test");
      @(negedge aclk);tx_force_stall=1;
      @(negedge aclk);time_sec=32'd2099;time_ps=64'd12;
      quiet_for(14);
      @(negedge aclk);tx_force_stall=0;
    end
  join
  wait_all;
  expect_data(2,80,32'h1111,1);
  send_iq(2,80,0);
  wait_all;

  current_tc=18;
  $display("[TC18] RX-only malformed packets: type/header/length/class/TKEEP");
  axi_write(REG_CONTROL,0,4'h1,OKAY);
  quiet_for(10);
  if(tx_busy)fail("TX not idle before external RX injection");
  @(negedge aclk);loopback_en=0;
  // Unknown packet type -> Dispatch only (one error on TLAST).
  make_inject_data(1,90,32'h1111,4'd0);
  inject_word[0]=32'hF8600008;
  expect_error(SRC_DISPATCH,`DIFI_ERR_UNSUPPORTED_TYPE);
  inject_prepared;
  wait_all;
  // Data bad Word0 fixed fields -> HEADER.
  make_inject_data(1,90,32'h1111,4'd0);
  inject_word[0]=inject_word[0] | 32'h01000000; // invalid TSM bit
  expect_error(SRC_DATA,`DIFI_ERR_HEADER);
  inject_prepared;
  wait_all;
  // Data TKEEP mismatch.
  make_inject_data(1,90,32'h1111,4'd0);
  inject_keep[3]=4'b0111;
  expect_error(SRC_DATA,`DIFI_ERR_SIZE);
  inject_prepared;
  wait_all;
  // Invalid declared Data Size in Word0.
  make_inject_data(1,90,32'h1111,4'd0);
  inject_word[0]=(inject_word[0] & 32'hFFFF0000) | 32'd2;
  expect_error(SRC_DATA,`DIFI_ERR_SIZE);
  inject_prepared;
  wait_all;
  // Missing TLAST at the declared final beat -> oversized frame.
  make_inject_data(1,90,32'h1111,4'd0);
  inject_last[7]=0;
  inject_word[8]=32'h12345678;
  inject_keep[8]=4'hF;
  inject_last[8]=1;
  inject_len=9;
  expect_error(SRC_DATA,`DIFI_ERR_SIZE);
  inject_prepared;
  wait_all;
  // Data wrong Class ID.
  make_inject_data(1,90,32'h1111,4'd0);
  inject_word[2]=32'h12345678;
  expect_error(SRC_DATA,`DIFI_ERR_CLASS);
  inject_prepared;
  wait_all;
  // Data early TLAST.
  make_inject_data(1,90,32'h1111,4'd0);
  inject_len=4;
  inject_last[3]=1;
  expect_error(SRC_DATA,`DIFI_ERR_TRUNCATED);
  inject_prepared;
  wait_all;

  current_tc=19;
  $display("[TC19] Context / Version semantic errors and recovery");
  make_inject_ctx(32'h1111,4'd0);
  inject_word[25]=0;
  expect_error(SRC_CONTEXT,`DIFI_ERR_CONTEXT_FIELD);
  inject_prepared;
  wait_all;
  make_inject_ver(32'h2222,4'd0);
  inject_word[9]=0;
  expect_error(SRC_VERSION,`DIFI_ERR_VERSION_FIELD);
  inject_prepared;
  wait_all;
  // Independent RX Stream ID filtering in Context and Version.
  make_inject_ctx(32'h9999,4'd0);
  expect_error(SRC_CONTEXT,`DIFI_ERR_STREAM_ID);
  inject_prepared;
  wait_all;
  make_inject_ver(32'h9999,4'd0);
  expect_error(SRC_VERSION,`DIFI_ERR_STREAM_ID);
  inject_prepared;
  wait_all;

  current_tc=20;
  $display("[TC20] Nonfatal Version sequence discontinuity and valid recovery");
  // Previous valid Version baseline is TX seq_ver-1. Deliberately skip several.
  make_inject_ver(32'h2222,seq_ver+4'd3);
  add_expect(K_VER,32'h2222,32'd4050,seq_ver+4'd3,64'd0,0,0,0,
             0,0,32'h34FC0400,0,0,1);
  expect_error(SRC_VERSION,`DIFI_ERR_SEQ);
  inject_prepared;
  wait_all;
  make_inject_ver(32'h2222,seq_ver+4'd4);
  add_expect(K_VER,32'h2222,32'd4050,seq_ver+4'd4,64'd0,0,0,0,
             0,0,32'h34FC0400,0,0,1);
  inject_prepared;
  wait_all;

  current_tc=21;
  $display("[TC21] External RX may operate while TX is disabled; no cross-path leakage");
  make_inject_data(2,91,32'h1111,seq_data+4'd5);
  add_expect(K_DATA,32'h1111,32'd4050,seq_data+4'd5,64'd0,2,91,0,
             0,0,0,0,0,1);
  expect_error(SRC_DATA,`DIFI_ERR_SEQ);
  inject_prepared;
  wait_all;
  make_inject_data(2,92,32'h1111,seq_data+4'd6);
  add_expect(K_DATA,32'h1111,32'd4050,seq_data+4'd6,64'd0,2,92,0,
             0,0,0,0,0,1);
  // Second payload must match tag 92; continuous metadata/IQ processing.
  inject_prepared;
  wait_all;

  $display("[PASS] tb_difi_engine_top all 21 test groups; checks=%0d TXpkt=%0d DataMeta=%0d ContextMeta=%0d VersionMeta=%0d IQpkt=%0d errors=%0d",
      checks,tx_seen,data_meta_seen,ctx_seen,ver_seen,iq_packets_seen,err_seen);
  $finish;
end
endmodule
