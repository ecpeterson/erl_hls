`timescale 1ns/1ps
// Saturated opaque per-lane traffic over two full credit bridges. DELAY adds
// independently buffered wire stages; no ready/valid signal is forced inside a DUT.
module credit_service_tb;
  parameter ACTIVE=8, DELAY=2;
  localparam LANES=8, WARMUP=1024, WINDOW=8192, STOP=WARMUP+WINDOW, BIN=1024;
  reg clk=0, reset=1;
  always #4 clk=~clk;
  integer cycle=0, sent[0:1][0:7], received[0:1][0:7];
  wire [127:0] frames[0:1][0:7], delivered[0:1][0:7];
  wire [7:0] frame_valid[0:1], frame_ready[0:1], delivered_valid[0:1];
  wire [32:0] tx[0:1], rx[0:1];
  wire tx_valid[0:1], tx_ready[0:1], rx_valid[0:1], rx_ready[0:1];
  wire [31:0] fault[0:1];
  wire fault_valid[0:1];
  integer words[0:1][0:7], messages[0:1][0:7], blocked[0:1][0:7];
  integer d, lane, b, outstanding;
  reg finished[0:1][0:7];
  reg stalled[0:1];
  reg [32:0] previous[0:1];

  // Each frame identifies its origin, lane and sequence and exercises all bits.
  function automatic [127:0] sample(input integer owner, input integer lane_id, input integer ordinal);
    sample={8'd3,8'h29,8'h37,8'h42,32'hdead0000+owner*32'd16+lane_id,
            32'hcafe0000+ordinal,32'h15926535^(ordinal*32'd65537)};
  endfunction
  genvar device, i;
  generate for(device=0;device<2;device=device+1) begin
    for(i=0;i<LANES;i=i+1) begin
      assign frames[device][i]=sample(device,i,sent[device][i]);
      assign frame_valid[device][i]=i<ACTIVE && !finished[device][i];
    end
    // The receiver is always able to ingest a completed frame.
    credit_service dut(.clk(clk),.reset(reset),
      ._link_in(rx[device]),._link_in_vld(rx_valid[device]),._link_in_rdy(rx_ready[device]),
      ._link_out(tx[device]),._link_out_vld(tx_valid[device]),._link_out_rdy(tx_ready[device]),
      ._fault_out(fault[device]),._fault_out_vld(fault_valid[device]),._fault_out_rdy(1'b1),
      @@CONNECTIONS@@);
    if(DELAY==0) begin
      assign rx[1-device]=tx[device];
      assign rx_valid[1-device]=tx_valid[device];
      assign tx_ready[device]=rx_ready[1-device];
    end else begin
      // Elastic stages retain the offered word when the next stage is occupied.
      reg [32:0] data[0:DELAY-1];
      reg [DELAY-1:0] valid=0;
      wire [DELAY:0] ready;
      assign ready[DELAY]=rx_ready[1-device];
      assign rx[1-device]=data[DELAY-1];
      assign rx_valid[1-device]=valid[DELAY-1];
      assign tx_ready[device]=ready[0];
      for(i=0;i<DELAY;i=i+1) begin
        assign ready[i]=!valid[i] || ready[i+1];
        always @(posedge clk) begin
          if(reset) valid[i]<=0;
          else if(ready[i]) begin
            valid[i]<=i==0 ? tx_valid[device] : valid[i-1];
            data[i]<=i==0 ? tx[device] : data[i-1];
          end
        end
      end
    end
  end endgenerate

  // Measure only the fixed steady offered-load window, then check complete drain.
  initial begin
    if(ACTIVE<1 || ACTIVE>LANES || DELAY<0) $fatal(1,"invalid service scenario");
    for(d=0;d<2;d=d+1) begin
      stalled[d]=0;
      for(lane=0;lane<LANES;lane=lane+1) begin sent[d][lane]=0;received[d][lane]=0;finished[d][lane]=0;end
      for(b=0;b<8;b=b+1) begin words[d][b]=0;messages[d][b]=0;blocked[d][b]=0;end
    end
    repeat(8) @(negedge clk);
    reset=0;
    wait(cycle>=STOP+512);
    @(negedge clk);
    outstanding=0;
    for(d=0;d<2;d=d+1) begin
      for(lane=0;lane<LANES;lane=lane+1) begin
        outstanding=outstanding+sent[d][lane]-received[1-d][lane];
        if(lane<ACTIVE && received[1-d][lane]<20) $fatal(1,"lane failed to progress");
      end
      for(b=0;b<8;b=b+1)
        $display("METRIC device=%0d bin=%0d cycles=%0d words=%0d frames=%0d blocked=%0d",d,b,BIN,words[d][b],messages[d][b],blocked[d][b]);
    end
    if(outstanding!=0) $fatal(1,"frames failed to drain");
    $display("PASS: complete ordered payloads and progress ACTIVE=%0d DELAY=%0d",ACTIVE,DELAY);
    $finish;
  end
  always @(posedge clk) if(!reset) begin
    cycle<=cycle+1;
    for(d=0;d<2;d=d+1) begin
      if(fault_valid[d]) $fatal(1,"bridge fault %0d",fault[d]);
      if(stalled[d] && (!tx_valid[d] || tx[d]!==previous[d])) $fatal(1,"stalled word changed");
      stalled[d]<=tx_valid[d]&&!tx_ready[d]; previous[d]<=tx[d];
      if(cycle>=WARMUP && cycle<STOP) begin
        b=(cycle-WARMUP)/BIN;
        words[d][b]<=words[d][b]+(tx_valid[d]&&tx_ready[d]);
        blocked[d][b]<=blocked[d][b]+(tx_valid[d]&&!tx_ready[d]);
        messages[d][b]<=messages[d][b]+$countones(delivered_valid[d]);
      end
      for(lane=0;lane<LANES;lane=lane+1) begin
        if(frame_valid[d][lane]&&frame_ready[d][lane]) begin
          sent[d][lane]<=sent[d][lane]+1;
          if(cycle>=STOP-1) finished[d][lane]<=1;
        end
        if(delivered_valid[d][lane]) begin
          if(delivered[d][lane]!==sample(1-d,lane,received[d][lane])) $fatal(1,"wrong lane/order/payload");
          received[d][lane]<=received[d][lane]+1;
        end
      end
    end
  end
endmodule
