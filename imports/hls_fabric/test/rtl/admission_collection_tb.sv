`timescale 1ns/1ps
// Ordinary actor frames and live progress exercise both collector and mailbox paths.
module admission_collection_tb;
  reg clk=0, reset=1, request_valid=0, ready=0;
  always #5 clk=~clk;
  reg [193:0] request=0;
  wire request_ready, valid_a, valid_b, observation_valid;
  wire [127:0] result_a, result_b;
  wire [183:0] observation;
  wire [91:0] a=observation[0+:92], b=observation[92+:92];
  integer count_a=0, count_b=0, writes_a=0, saved_writes=0;
  reg [7:0] want_a=10, want_b=2;
  reg held_a=0, held_b=0;
  reg [127:0] prior_a, prior_b;
  collection_wrapper dut(.*);

  // Holding external results cannot destabilize a frame or suppress live queries.
  always @(posedge clk) begin
    if (reset) begin count_a=0; count_b=0; writes_a=0; held_a=0; held_b=0; end
    else begin
      if(dut.scheduler_0_state_wr_en && dut.scheduler_0_state_wr_addr==0) writes_a=writes_a+1;
      if(held_a && (!valid_a || result_a !== prior_a)) $fatal(1,"stalled A changed");
      if(held_b && (!valid_b || result_b !== prior_b)) $fatal(1,"stalled B changed");
      held_a=valid_a && !ready; held_b=valid_b && !ready;
      prior_a=result_a; prior_b=result_b;
      if(valid_a && ready) begin
        if(result_a !== {8'd1,8'd0,8'd0,8'd5,88'd0,want_a}) $fatal(1,"wrong A result %h",result_a);
        count_a=count_a+1;
      end
      if(valid_b && ready) begin
        if(result_b !== {8'd1,8'd0,8'd0,8'd5,88'd0,want_b}) $fatal(1,"wrong B result %h",result_b);
        count_b=count_b+1;
      end
    end
  end

  // A point rectangle selects one of two ordinary actors sharing one scheduler.
  task automatic packet(input [15:0] actor, input [7:0] tag, input [7:0] words, input [95:0] payload);
    begin
      @(negedge clk); request={actor,16'd0,actor,16'd0,2'd0,words,16'd0,tag,payload}; request_valid=1;
      do @(posedge clk); while(!request_ready);
      @(negedge clk); request_valid=0;
    end
  endtask
  task automatic open_set(input [15:0] actor, input [7:0] mask);
    packet(actor,3,2,{56'd0,mask,32'd7});
  endtask
  task automatic piece(input [15:0] actor, input [31:0] member, input [7:0] value);
    packet(actor,4,3,{24'd0,value,member,32'd7});
  endtask
  task automatic wait_a(input [1:0] status, input [5:0] seen);
    while(!(observation_valid && a[25] && a[26+:2]==status && a[86+:6]==seen)) @(negedge clk);
  endtask
  task automatic restart;
    begin
      @(negedge clk); reset=1; ready=0; request_valid=0;
      repeat(5) @(negedge clk);
      reset=0;
    end
  endtask

  initial begin
    restart();
    // B receives an early ordinary mailbox contribution. A collects while idle.
    piece(1,0,4); open_set(1,33); open_set(0,3);
    wait_a(1,0); saved_writes=writes_a;
    piece(0,0,9); wait_a(1,1);
    if(writes_a != saved_writes) $fatal(1,"admission contribution visited actor RAM");
    piece(0,1,3); piece(1,5,6);
    while(!(valid_a && valid_b)) @(negedge clk);
    repeat(100) @(negedge clk);
    ready=1; repeat(100) @(negedge clk);
    if(count_a!=1 || count_b!=1) $fatal(1,"lost or repeated completion");

    // Reset must discard a partial collector window as well as ordinary RAM state.
    restart(); open_set(0,3); wait_a(1,0); piece(0,0,9); wait_a(1,1);
    restart(); want_a=6;
    open_set(0,3); wait_a(1,0); piece(0,0,4); wait_a(1,1);
    // Duplicate fallback fails B without losing A's independently held partial sum.
    open_set(1,3); piece(1,0,1); piece(1,0,2); piece(0,1,2);
    while(!(observation_valid && b[9+:16]!=0 && valid_a)) @(negedge clk);
    ready=1; repeat(100) @(negedge clk);
    if(count_a!=1 || count_b!=0) $fatal(1,"failure crossed actor boundary");
    $display("PASS: collection matches early delivery, stalls, reset and independent failure");
    $finish;
  end
  initial begin #1000000; $fatal(1,"collector RTL timeout: a=%h b=%h",a,b); end
endmodule
