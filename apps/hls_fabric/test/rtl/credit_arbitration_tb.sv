`timescale 1ns/1ps
// Public-port checks for sparse traffic, saturated classes, fairness and stalls.
module credit_arbitration_tb;
  parameter SPARSE_LIMIT=400;
  localparam TX=12, RX=3, COUNT=24;
  reg clk=0;
  always #5 clk=~clk;
  reg reset=1;
  integer scenario=0, cycle=0, stage=0, lane=0;
  integer sent[0:TX-1], received[0:TX-1], last_grant[0:TX-1];
  integer returns_sent[0:RX-1], returns_received[0:RX-1], last_return[0:RX-1];
  wire [127:0] frames[0:TX-1];
  wire [TX-1:0] frame_ready, frame_valid, credit_ready;
  reg [TX-1:0] credit_valid=0;
  wire [RX-1:0] return_ready, return_valid;
  wire [32:0] beat;
  wire valid;
  wire ready = scenario==0 || (scenario==1 && cycle%9 >= 2) || (scenario>=2 && cycle>=40);
  wire [31:0] fault;
  wire fault_valid;
  reg stalled=0;
  reg [32:0] previous;
  reg [127:0] expected;
  integer k, total, returned, finish_cycle;

  // Distinct opaque payloads retain all bits and identify the reset activation.
  function automatic [127:0] sample(input integer id, input integer ordinal);
    sample={8'd3,8'h29,8'h37,8'h42,32'hdead0000+id+scenario*32'h100,
      32'hcafe0000+ordinal,32'h15926535^(ordinal*32'd65537)};
  endfunction
  genvar i;
  generate for(i=0;i<TX;i=i+1) begin
    assign frames[i]=sample(i,sent[i]);
    assign frame_valid[i]=sent[i]<COUNT &&
      (scenario==1 || (i==TX-1 && (scenario!=3 || cycle>=1)) ||
       (scenario==2 && i==0 && cycle>=20));
  end
  for(i=0;i<RX;i=i+1) begin
    assign return_valid[i]=(scenario==1 && returns_sent[i]<COUNT*TX/RX) ||
      (scenario==3 && i==0 && cycle>=20 && returns_sent[i]<COUNT);
  end endgenerate

  arbiter dut(.clk(clk),.reset(reset),
    ._link_out(beat),._link_out_vld(valid),._link_out_rdy(ready),
    ._fault_out(fault),._fault_out_vld(fault_valid),._fault_out_rdy(1'b1),
    @@CONNECTIONS@@);

  wire done=(scenario==0 && total==COUNT) ||
    (scenario==1 && total==COUNT*TX && returned==COUNT*TX) ||
    (scenario==2 && total==COUNT*2) ||
    (scenario==3 && total==COUNT && returned==COUNT);

  // Each test owns a fresh activation; the second applies recurring wire stalls.
  initial begin
    // The final cases introduce a higher-priority data lane or a credit return
    // while a data header is stalled. Neither may replace the offered word.
    for(scenario=0;scenario<4;scenario=scenario+1) begin
      reset=1;
      repeat(8) @(negedge clk);
      cycle=0; stage=0; stalled=0; credit_valid=0;
      for(k=0;k<TX;k=k+1) begin sent[k]=0;received[k]=0;last_grant[k]=0;end
      for(k=0;k<RX;k=k+1) begin returns_sent[k]=0;returns_received[k]=0;last_return[k]=0;end
      reset=0;
      wait(done);
      @(negedge clk);
      finish_cycle=cycle;
      $display("METRIC scenario=%0d cycles=%0d frames=%0d returns=%0d",scenario,cycle,total,returned);
      if(scenario==0 && finish_cycle>SPARSE_LIMIT) $fatal(1,"sparse service still scales with empty lanes");
      if(scenario==1 && finish_cycle>3200) $fatal(1,"saturated service exceeded its progress bound");
      reset=1;
    end
    $display("PASS: sparse/saturated/delayed lanes, bounded fairness, stable stalls and opaque payloads");
    $finish;
  end
  always @* begin
    total=0;returned=0;
    for(integer j=0;j<TX;j=j+1) total=total+received[j];
    for(integer j=0;j<RX;j=j+1) returned=returned+returns_received[j];
  end
  always @(posedge clk) if(!reset) begin
    cycle<=cycle+1;
    if(cycle>20000) $fatal(1,"arbitration timeout");
    if(fault_valid) $fatal(1,"unexpected transmit fault %0d",fault);
    if(stalled && (!valid || beat!==previous)) $fatal(1,"changed a stalled beat");
    stalled<=valid&&!ready; previous<=beat;
    for(k=0;k<TX;k=k+1) begin
      if(frame_valid[k]&&frame_ready[k]) sent[k]<=sent[k]+1;
      if(credit_valid[k]&&credit_ready[k]) credit_valid[k]<=0;
      // Every busy lane must keep receiving grants while it still offers work.
      if(scenario==1 && received[k]<COUNT && cycle-last_grant[k]>180)
        $fatal(1,"starved data lane %0d",k);
    end
    for(k=0;k<RX;k=k+1) begin
      if(return_valid[k]&&return_ready[k]) returns_sent[k]<=returns_sent[k]+1;
      // Credit returns must progress while data traffic remains saturated.
      if(scenario==1 && returns_received[k]<COUNT*TX/RX && cycle-last_return[k]>60)
        $fatal(1,"starved return lane %0d",k);
    end
    if(valid&&ready) begin
      if(stage==0) begin
        if(beat[31:16]!=16'h4850) $fatal(1,"wrong wire tag");
        if(beat[15]) begin
          if(beat[14:0]>=RX || !beat[32]) $fatal(1,"bad return header");
          if(returns_received[beat[14:0]]>=returns_sent[beat[14:0]]+(return_valid[beat[14:0]]&&return_ready[beat[14:0]]))
            $fatal(1,"return was duplicated or fabricated");
          returns_received[beat[14:0]]<=returns_received[beat[14:0]]+1;
          last_return[beat[14:0]]<=cycle;
        end else begin
          lane=beat[14:0];
          if(lane>=TX || beat[32] || received[lane]>=sent[lane]+(frame_valid[lane]&&frame_ready[lane])) $fatal(1,"bad data header");
          expected=sample(lane,received[lane]); stage=1;last_grant[lane]<=cycle;
        end
      end else begin
        if(beat[32] !== (stage==4)) $fatal(1,"bad packet boundary");
        if(stage==1) begin
          if(beat[31:0]!=={expected[103:96],expected[111:104],expected[119:112],expected[127:120]})
            $fatal(1,"corrupt frame header");
        end else if(beat[31:0]!==expected[(stage-2)*32+:32]) $fatal(1,"corrupt frame payload");
        if(stage==4) begin
          received[lane]<=received[lane]+1;
          credit_valid[lane]<=1;
          stage=0;
        end else stage=stage+1;
      end
    end
  end
endmodule
