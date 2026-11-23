`timescale 1ns/1ps
// Check the generated prefix drainer at accepted ready/valid boundaries.
module parallel_outbox_tb;
  parameter LANES = 4;
  reg clk=0, reset=1;
  always #4 clk=~clk;
  reg [65:0] batches=0;
  reg batch_valid=0;
  wire batch_ready;
  wire [130:0] effects;
  wire effect_valid;
  reg effect_ready=1;
  wire [32:0] credits;
  wire credit_valid;
  reg credit_ready=1;
  wire [130:0] fragments [0:LANES-1];
  wire [LANES-1:0] fragment_valid;
  reg [LANES-1:0] fragment_ready='1;
  parallel_outbox dut(.clk(clk), .reset(reset), ._batches(batches), ._batches_vld(batch_valid), ._batches_rdy(batch_ready),
    ._effects(effects), ._effects_vld(effect_valid), ._effects_rdy(effect_ready),
    ._credits(credits), ._credits_vld(credit_valid), ._credits_rdy(credit_ready),
    @@CONNECTIONS@@);
  integer cycle=0, mode=0, base=0, ordinary=0, returned=0, total=0;
  integer seen [0:LANES-1], first [0:LANES-1];
  reg [130:0] held [0:LANES-1];
  reg [LANES-1:0] stalled=0;
  integer i, position;
  always @(posedge clk) begin
    cycle=cycle+1;
    if (!reset) begin
      for (i=0;i<LANES;i=i+1) begin
        if (stalled[i] && (!fragment_valid[i] || fragments[i] !== held[i])) $fatal(1,"stalled fragment changed");
        stalled[i]=fragment_valid[i] && !fragment_ready[i];
        held[i]=fragments[i];
        if (fragment_valid[i] && fragment_ready[i]) begin
          position=(LANES==2?2*i+seen[i]:LANES==3?(i==0?seen[i]:i+1):i+seen[i]*LANES);
          if ((mode!=1 && mode!=2) || position>=4) $fatal(1,"unexpected fragment");
          if (fragments[i][130:128] !== position || fragments[i][95:0] !== base+position) $fatal(1,"wrong/reordered fragment");
          if (seen[i]==0) first[i]=cycle;
          seen[i]=seen[i]+1; total=total+1;
        end
      end
      if (effect_valid && effect_ready) begin
        position=ordinary+(mode==2?4:0);
        if ((mode!=0 && mode!=2) || effects[130:128]!==3'd4 || effects[95:0]!==base+position) $fatal(1,"wrong ordinary effect");
        if (mode==2 && total<4) $fatal(1,"tail overtook prefix");
        ordinary=ordinary+1; total=total+1;
      end
      if (credit_valid && credit_ready) begin
        if (credits!==33'd1 || total!=(mode==0?3:mode==1?4:mode==2?6:0)) $fatal(1,"premature/wrong credit total=%0d mode=%0d",total,mode);
        returned=returned+1;
      end
    end else stalled=0;
    if (cycle>1000) $fatal(1,"timeout");
  end
  // Each batch has one reservation; drive only at the falling edge.
  task start_batch(input integer m, input integer b);
    begin
      @(negedge clk); mode=m; base=b; ordinary=0; total=0; returned=0;
      for (integer j=0;j<LANES;j=j+1) begin seen[j]=0; first[j]=-1; end
      batches={32'd0,m[1:0],b[31:0]}; batch_valid=1;
      do @(posedge clk); while (!batch_ready);
      @(negedge clk); batch_valid=0;
    end
  endtask
  task finish_batch;
    begin wait(returned==1); repeat(4) @(negedge clk); if(returned!=1) $fatal(1,"duplicate credit"); end
  endtask
  initial begin
    repeat(4) @(negedge clk); reset=0;
    start_batch(1,100); finish_batch();
    for(integer j=1;j<LANES;j=j+1) if(LANES==4 && first[j]!=first[0]) $fatal(1,"independent lanes serialized");
    fragment_ready[LANES<4?1:0]=0; start_batch(2,200);
    repeat(15) @(negedge clk);
    if(LANES<4 && seen[0]!=2) $fatal(1,"later blocked lane prevented earlier source effect");
    if(LANES==4) for(integer j=1;j<LANES;j=j+1) if(seen[j]==0) $fatal(1,"blocked lane stopped bystander");
    if(returned!=0 || ordinary!=0) $fatal(1,"blocked prefix retired");
    fragment_ready='1; finish_batch();
    effect_ready=0; start_batch(2,250); repeat(15) @(negedge clk);
    if(returned!=0 || total!=4) $fatal(1,"blocked ordinary tail retired");
    effect_ready=1; finish_batch();
    start_batch(0,300); finish_batch();
    start_batch(3,400); finish_batch();
    credit_ready=0; start_batch(1,500); repeat(15) @(negedge clk);
    if(!credit_valid || returned!=0 || total!=4) $fatal(1,"credit stall failed");
    credit_ready=1; finish_batch();
    fragment_ready=0; start_batch(1,600); repeat(8) @(negedge clk);
    reset=1; repeat(4) @(negedge clk); reset=0; fragment_ready='1;
    repeat(8) @(negedge clk);
    if(returned!=0 || total!=0) $fatal(1,"reset leaked batch");
    start_batch(2,700); finish_batch();
    $display("PASS parallel prefix lanes=%0d: simultaneous, aliased order, stalls, tails, empty, credits, reset",LANES);
    $finish;
  end
endmodule
