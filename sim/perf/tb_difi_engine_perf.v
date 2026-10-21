`timescale 1ns/1ps

// Drain startup Version/Context packets before starting timing.
module tb_difi_engine_perf;

  parameter integer MAX_PACKETS = 2000;
  localparam integer SAMPLES_PER_PACKET = 256;
  localparam integer CLK_MHZ = 100;
  localparam integer WATCHDOG_CYCLES = 3000000;

  reg aclk = 1'b0;
  always #5 aclk = ~aclk;
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
  wire [31:0] cfg_context_period_ms;
  wire [31:0] cfg_version_period_ms;
  wire tx_busy;

  reg perf_active;
  integer packet_limit;
  integer total_samples;
  integer input_count;
  integer output_count;
  integer meta_count;
  integer data_tx_packet_count;
  integer context_count;
  integer version_count;
  integer error_count;
  integer tx_word_idx;
  integer cycle_counter;
  integer first_input_cycle;
  integer last_output_cycle;

  wire data_available = perf_active && (input_count < total_samples);
  wire [31:0] s_axis_iq_tdata;
  wire s_axis_iq_tvalid = perf_active && (input_count < total_samples);
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
  wire m_axis_iq_tlast;
  wire m_data_meta_valid;
  wire [31:0] m_data_meta_stream_id;
  wire [3:0] m_data_meta_seq;
  wire [31:0] m_data_meta_time_sec;
  wire [63:0] m_data_meta_time_ps;
  wire [15:0] m_data_meta_sample_count;
  wire m_ctx_valid;
  wire m_ver_valid;
  wire rx_dispatch_error_valid;
  wire [3:0] rx_dispatch_error_code;
  wire rx_data_error_valid;
  wire [3:0] rx_data_error_code;
  wire rx_context_error_valid;
  wire [3:0] rx_context_error_code;
  wire rx_version_error_valid;
  wire [3:0] rx_version_error_code;

  assign s_axis_rx_pkt_tdata  = m_axis_tx_pkt_tdata;
  assign s_axis_rx_pkt_tvalid = m_axis_tx_pkt_tvalid;
  assign s_axis_rx_pkt_tkeep  = m_axis_tx_pkt_tkeep;
  assign s_axis_rx_pkt_tlast  = m_axis_tx_pkt_tlast;
  assign m_axis_tx_pkt_tready = s_axis_rx_pkt_tready;

  function [31:0] sample_pattern;
    input integer index;
    reg [31:0] x;
    begin
      x = (index * 32'h9E37_79B9) ^ 32'hD1F0_1234;
      sample_pattern = {x[15:0], x[31:16]};
    end
  endfunction
  assign s_axis_iq_tdata = sample_pattern(input_count);

  difi_engine_top dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .time_sec(time_sec), .time_ps(time_ps), .time_valid(time_valid),
    .data_available(data_available),
    .context_periodic_trigger(1'b0), .version_periodic_trigger(1'b0),
    .cfg_context_period_ms(cfg_context_period_ms),
    .cfg_version_period_ms(cfg_version_period_ms), .tx_busy(tx_busy),
    .s_axis_iq_tdata(s_axis_iq_tdata), .s_axis_iq_tvalid(s_axis_iq_tvalid),
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
    .m_axis_iq_tvalid(m_axis_iq_tvalid), .m_axis_iq_tready(1'b1),
    .m_axis_iq_tlast(m_axis_iq_tlast),
    .m_data_meta_valid(m_data_meta_valid), .m_data_meta_ready(1'b1),
    .m_data_meta_stream_id(m_data_meta_stream_id),
    .m_data_meta_seq(m_data_meta_seq),
    .m_data_meta_time_sec(m_data_meta_time_sec),
    .m_data_meta_time_ps(m_data_meta_time_ps),
    .m_data_meta_sample_count(m_data_meta_sample_count),
    .m_ctx_valid(m_ctx_valid), .m_ctx_ready(1'b1),
    .m_ver_valid(m_ver_valid), .m_ver_ready(1'b1),
    .rx_dispatch_error_valid(rx_dispatch_error_valid),
    .rx_dispatch_error_code(rx_dispatch_error_code),
    .rx_data_error_valid(rx_data_error_valid),
    .rx_data_error_code(rx_data_error_code),
    .rx_context_error_valid(rx_context_error_valid),
    .rx_context_error_code(rx_context_error_code),
    .rx_version_error_valid(rx_version_error_valid),
    .rx_version_error_code(rx_version_error_code)
  );

  integer packet_in_cycle [0:MAX_PACKETS-1];
  integer packet_first_out_cycle [0:MAX_PACKETS-1];
  integer packet_last_out_cycle [0:MAX_PACKETS-1];

  task fail;
    input [8*160-1:0] reason;
    begin
      $display("[FAIL] cycle=%0d in=%0d out=%0d meta=%0d: %0s",
               cycle_counter, input_count, output_count, meta_count, reason);
      $finish;
    end
  endtask

  task axi_write;
    input [7:0] addr;
    input [31:0] value;
    integer timeout;
    reg aw_done, w_done, b_done;
    begin
      @(negedge aclk);
      s_axi_awaddr=addr; s_axi_awprot=0; s_axi_awvalid=1;
      s_axi_wdata=value; s_axi_wstrb=4'hF; s_axi_wvalid=1;
      s_axi_bready=1;
      aw_done=0; w_done=0; b_done=0; timeout=0;
      while (!b_done && timeout<100) begin
        @(posedge aclk);
        if (s_axi_awvalid && s_axi_awready) aw_done=1;
        if (s_axi_wvalid && s_axi_wready) w_done=1;
        if (s_axi_bvalid && s_axi_bready) begin
          if (s_axi_bresp !== 2'b00) fail("AXI4-Lite write failed");
          b_done=1;
        end
        @(negedge aclk);
        if (aw_done) s_axi_awvalid=0;
        if (w_done) s_axi_wvalid=0;
        timeout=timeout+1;
      end
      if (!b_done) fail("AXI4-Lite write timeout");
      s_axi_bready=0;
    end
  endtask

  always @(posedge aclk) begin
    if (!aresetn) begin
      cycle_counter <= 0;
      input_count <= 0;
      output_count <= 0;
      meta_count <= 0;
      data_tx_packet_count <= 0;
      context_count <= 0;
      version_count <= 0;
      error_count <= 0;
      tx_word_idx <= 0;
      first_input_cycle <= -1;
      last_output_cycle <= -1;
    end else begin
      cycle_counter <= cycle_counter + 1;

      if (rx_dispatch_error_valid || rx_data_error_valid ||
          rx_context_error_valid || rx_version_error_valid) begin
        error_count <= error_count+1;
        $display("ERR: disp=%b/%h data=%b/%h ctx=%b/%h ver=%b/%h",
                  rx_dispatch_error_valid,rx_dispatch_error_code,
                  rx_data_error_valid,rx_data_error_code,
                  rx_context_error_valid,rx_context_error_code,
                  rx_version_error_valid,rx_version_error_code);
        fail("DUT emitted an error event");
      end

      if (m_ctx_valid) context_count <= context_count + 1;
      if (m_ver_valid) version_count <= version_count + 1;

      if (m_axis_tx_pkt_tvalid && m_axis_tx_pkt_tready) begin
        if (m_axis_tx_pkt_tkeep !== 4'hF) fail("TX TKEEP mismatch");
        if (perf_active && tx_word_idx==0 && m_axis_tx_pkt_tdata[31:28]!==4'h1)
          fail("Unexpected Context/Version packet during Data benchmark");
        if (m_axis_tx_pkt_tlast) begin
          if (perf_active) begin
            if (tx_word_idx != SAMPLES_PER_PACKET+6)
              fail("TX Data Packet length mismatch");
            data_tx_packet_count <= data_tx_packet_count + 1;
          end
          tx_word_idx <= 0;
        end else begin
          tx_word_idx <= tx_word_idx+1;
        end
      end

      if (perf_active && s_axis_iq_tvalid && s_axis_iq_tready) begin
        if (input_count >= total_samples) fail("Input overrun");
        if ((input_count % SAMPLES_PER_PACKET)==0) begin
          packet_in_cycle[input_count/SAMPLES_PER_PACKET] = cycle_counter;
          if (input_count==0) first_input_cycle <= cycle_counter;
        end
        input_count <= input_count+1;
      end

      if (m_data_meta_valid) begin
        if (!perf_active) fail("Unexpected Data metadata before benchmark");
        if (meta_count >= packet_limit) fail("Extra Data metadata");
        if (m_data_meta_stream_id !== 32'd1 ||
            m_data_meta_seq !== (meta_count % 16) ||
            m_data_meta_sample_count !== SAMPLES_PER_PACKET ||
            m_data_meta_time_sec !== time_sec ||
            m_data_meta_time_ps !== time_ps)
          fail("Data metadata mismatch");
        meta_count <= meta_count+1;
      end

      if (m_axis_iq_tvalid) begin
        if (!perf_active) fail("Unexpected IQ before benchmark");
        if (output_count>=total_samples) fail("Extra output IQ");
        if (meta_count <= (output_count/SAMPLES_PER_PACKET))
          fail("IQ emitted before Metadata handshake");
        if (m_axis_iq_tdata !== sample_pattern(output_count)) begin
          $display("  IQ index=%0d got=%08h expected=%08h",
                    output_count,m_axis_iq_tdata,sample_pattern(output_count));
          fail("IQ data corrupted or reordered");
        end
        if (m_axis_iq_tlast !== ((output_count % SAMPLES_PER_PACKET)==SAMPLES_PER_PACKET-1))
          fail("IQ TLAST misplaced");
        if ((output_count % SAMPLES_PER_PACKET)==0)
          packet_first_out_cycle[output_count/SAMPLES_PER_PACKET]=cycle_counter;
        if (m_axis_iq_tlast)
          packet_last_out_cycle[output_count/SAMPLES_PER_PACKET]=cycle_counter;
        if (output_count==total_samples-1) last_output_cycle <= cycle_counter;
        output_count <= output_count+1;
      end
    end
  end

  integer i, timeout, csv, latency_cycles, completion_cycles;
  integer min_latency, max_latency;
  reg [63:0] sum_latency;
  reg [8*256-1:0] csv_path;
  real avg_latency;
  real payload_mb_s;
  integer total_cycles;

  initial begin
    aresetn=0;
    s_axi_awaddr=0; s_axi_awprot=0; s_axi_awvalid=0;
    s_axi_wdata=0; s_axi_wstrb=0; s_axi_wvalid=0; s_axi_bready=0;
    s_axi_araddr=0; s_axi_arprot=0; s_axi_arvalid=0; s_axi_rready=0;
    time_sec=32'd1000; time_ps=64'd123456789; time_valid=0;
    perf_active=0;
    packet_limit=100;
    if ($value$plusargs("packets=%d", packet_limit)) begin end
    if (packet_limit < 1 || packet_limit>MAX_PACKETS) fail("Invalid +packets count");
    total_samples=packet_limit*SAMPLES_PER_PACKET;
    csv_path="sim/perf/difi_perf_latency.csv";
    if ($value$plusargs("csv=%s", csv_path)) begin end

    repeat(8) @(negedge aclk);
    aresetn=1;
    
    axi_write(8'h18, 32'd256);  
    axi_write(8'h04, 32'd1);    
    
    repeat(12) @(negedge aclk);
    axi_write(8'h00, 32'd1);    
    @(negedge aclk); time_valid=1;

    timeout=0;
    while ((context_count<1 || version_count<1 || tx_busy || m_axis_tx_pkt_tvalid) && timeout<10000) begin
      @(negedge aclk);
      timeout=timeout+1;
    end
    if (timeout>=10000) fail("Bootstrap Version/Context timeout");
    repeat(8) @(negedge aclk);
    if (context_count!=1 || version_count!=1)
      fail("Unexpected startup Context/Version count");
    if (tx_word_idx!=0) fail("TX boundary not idle at measurement start");

    $display("[INFO] benchmark: %0d Data packets x 256 samples, 100 MHz, ideal TX->RX direct link", packet_limit);
    @(negedge aclk); perf_active=1;

    timeout=0;
    while ((output_count<total_samples) && timeout<WATCHDOG_CYCLES) begin
      @(negedge aclk);
      timeout=timeout+1;
    end
    if (output_count!=total_samples) fail("IQ completion timeout");
    repeat(20) @(negedge aclk);
    if (input_count!=total_samples || output_count!=total_samples ||
        meta_count!=packet_limit || data_tx_packet_count!=packet_limit)
      fail("Missing/duplicate IQ, TX packet, or Metadata");
    if (context_count!=1 || version_count!=1 || error_count!=0)
      fail("Unexpected Context/Version/Error during Data run");
    if (first_input_cycle<0 || last_output_cycle<first_input_cycle)
      fail("Invalid benchmark time interval");

    total_cycles=last_output_cycle-first_input_cycle+1;
    
    payload_mb_s=(total_samples*400.0)/total_cycles;
    min_latency=2147483647;
    max_latency=0;
    sum_latency=0;
    csv=$fopen(csv_path,"w");
    if (!csv) fail("Cannot open CSV path (ensure sim/perf exists)");
    $fdisplay(csv,"packet_index,first_input_cycle,first_output_cycle,last_output_cycle,first_iq_latency_cycles,packet_completion_cycles");
    for (i=0;i<packet_limit;i=i+1) begin
      latency_cycles=packet_first_out_cycle[i]-packet_in_cycle[i];
      completion_cycles=packet_last_out_cycle[i]-packet_in_cycle[i];
      if (latency_cycles<0 || completion_cycles<latency_cycles)
        fail("Invalid per-packet latency");
      if (latency_cycles<min_latency) min_latency=latency_cycles;
      if (latency_cycles>max_latency) max_latency=latency_cycles;
      sum_latency=sum_latency+latency_cycles;
      $fdisplay(csv,"%0d,%0d,%0d,%0d,%0d,%0d",i,
          packet_in_cycle[i],packet_first_out_cycle[i],packet_last_out_cycle[i],
          latency_cycles,completion_cycles);
    end
    $fclose(csv);
    avg_latency=sum_latency*1.0/packet_limit;

    $display("[RESULT] packets=%0d samples=%0d duration_cycles=%0d", packet_limit,total_samples,total_cycles);
    $display("[RESULT] IQ_payload_throughput_MBps=%0.3f",payload_mb_s);
    $display("[RESULT] first_IQ_latency_cycles min=%0d avg=%0.3f max=%0d",min_latency,avg_latency,max_latency);
    $display("[RESULT] first_IQ_latency_ns min=%0d avg=%0.3f max=%0d",min_latency*10,avg_latency*10.0,max_latency*10);
    $display("[RESULT] correct_IQ=%0d, metadata=%0d, data_packets=%0d, error_events=%0d", output_count,meta_count,data_tx_packet_count,error_count);
    $display("[RESULT] raw_per_packet_CSV=%0s",csv_path);
    $display("[PASS] tb_difi_engine_perf");
    $finish;
  end
endmodule
