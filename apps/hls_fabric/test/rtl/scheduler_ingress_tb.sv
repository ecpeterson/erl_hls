// Public ready/valid traffic checks ordering, bounded polling, fairness and reset.
`timescale 1ns/1ps
module scheduler_ingress_tb;
  parameter N = 2;
  parameter EXPECTED_NS = 8;
  reg clk = 0;
  always #4 clk = ~clk;
  reg reset = 1;
  reg [127:0] frames [N];
  reg [N-1:0] valid = 0;
  wire [N-1:0] ready;
  wire [160:0] request;
  wire request_valid;
  reg request_ready = 0;
  integer seq_no [N];
  integer grants [N];
  integer last_grant [N];
  reg [127:0] expected [8192];
  integer admitted_at [8192];
  integer measured = 0;
  integer pushed = 0, popped = 0, cycle = 0, epoch = 0;
  integer i, accepted, gap = 0;
  reg [N-1:0] accepted_lanes;
  reg held = 0;
  reg [160:0] held_request;
  ingress dut(.clk(clk), .reset(reset),
    @@CONNECTIONS@@,
    ._request_out(request), ._request_out_vld(request_valid), ._request_out_rdy(request_ready));

  // Scoreboard order is the observed grant order, independent of the chosen polling phase.
  always @(posedge clk) begin
    accepted_lanes = 0;
    if (!reset) begin
      accepted = 0;
      for (i=0;i<N;i=i+1) if (valid[i] && ready[i]) begin
        accepted = accepted + 1;
        expected[pushed] = frames[i];
        admitted_at[pushed] = cycle;
        if (cycle > 180 && cycle < 500 && last_grant[i] >= 0 && pushed-last_grant[i] > N)
          $fatal(1,"starved lane %0d",i);
        last_grant[i] = pushed;
        pushed = pushed + 1;
        grants[i] = grants[i] + 1;
        seq_no[i] = seq_no[i] + 1;
        accepted_lanes[i] = 1;
      end
      if (accepted > 1) $fatal(1,"multiple ingress grants in one clock");
      if (held && (!request_valid || request !== held_request)) $fatal(1,"unstable stalled request");
      if (request_valid && request_ready) begin
        if (popped >= pushed || request[160:129] !== 32'd3 || request[0] !== 1'b0 || request[128:1] !== expected[popped])
          $fatal(1,"missing/reordered/malformed request at %0d",popped);
        if (cycle > 40 && cycle < 110) begin
          if (8*(cycle-admitted_at[popped]) != EXPECTED_NS)
            $fatal(1,"unexpected sparse-lane latency: %0d ns",8*(cycle-admitted_at[popped]));
          measured = measured + 1;
        end
        popped = popped + 1;
      end
      held = request_valid && !request_ready;
      held_request = request;
      // Alternating polling allows one empty turn between grants to the last lane.
      if (cycle > 40 && cycle < 110 && request_ready && valid[N-1]) begin
        if (accepted == 0) gap = gap + 1; else gap = 0;
        if (gap > 1) $fatal(1,"empty-input polling delayed the offered lane");
      end
    end else begin
      held = 0;
      gap = 0;
    end
  end

  // Hold offered words through backpressure; vary availability and output readiness.
  initial begin
    for (epoch=0;epoch<2;epoch=epoch+1) begin
      reset = 1; valid = 0; request_ready = 0; pushed = 0; popped = 0; measured = 0;
      for (i=0;i<N;i=i+1) begin seq_no[i]=0; grants[i]=0; last_grant[i]=-1; frames[i]=0; end
      repeat(5) @(negedge clk);
      reset = 0;
      for (cycle=0;cycle<900;cycle=cycle+1) begin
        request_ready = cycle < 110 || cycle >= 800 || (cycle%11 < 7);
        for (i=0;i<N;i=i+1) begin
          if (accepted_lanes[i]) valid[i]=0;
          if (cycle >= 20 && cycle < 120 && i == N-1) valid[i]=1;
          if (cycle >= 120 && cycle < 520) valid[i]=1;
          if (cycle >= 520 && cycle < 780 && (cycle+3*i)%7 == 0) valid[i]=1;
          if (!valid[i] || accepted_lanes[i]) frames[i] = (128'(epoch)<<96) | (128'(i)<<64) | 128'(seq_no[i]);
        end
        @(negedge clk);
      end
      if (pushed != popped) $fatal(1,"incomplete drain %0d/%0d",popped,pushed);
      for (i=0;i<N;i=i+1) if (grants[i] < 10) $fatal(1,"lane never exercised");
      if (measured < 20) $fatal(1,"latency interval not exercised");
      $display("PASS: ingress inputs=%0d epoch=%0d frames=%0d latency=%0d ns samples=%0d",N,epoch,popped,EXPECTED_NS,measured);
      if (epoch == 0) begin
        // Reset with accepted requests still blocked, then reject any old-epoch output.
        request_ready = 0;
        repeat(8) begin
          for (i=0;i<N;i=i+1) begin
            valid[i] = 1;
            if (accepted_lanes[i]) frames[i] = (128'(i)<<64) | 128'(seq_no[i]);
          end
          @(negedge clk);
        end
        if (pushed == popped) $fatal(1,"reset did not exercise buffered requests");
        $display("PASS: reset discards %0d accepted blocked requests",pushed-popped);
      end
    end
    $finish;
  end
endmodule
