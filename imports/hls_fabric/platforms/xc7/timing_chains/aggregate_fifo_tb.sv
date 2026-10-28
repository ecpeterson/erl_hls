// Queue-model witness for the generated 218-bit aggregate FIFO. A stalled
// producer retains its item; reset may discard an accepted, undelivered item.
module aggregate_fifo_tb;
  reg clk=0, reset=1, push_valid=0, pop_ready=0;
  reg [217:0] push_data=0;
  wire push_ready, pop_valid;
  wire [217:0] pop_data;
  `DUT dut(.*);
  always #5 clk=~clk;
  reg occupied=0, producer_stalled=0, consumer_stalled=0;
  reg [217:0] held=0, last_output=0;
  reg [31:0] random_state=32'hbeef1234;
  integer cycle, word, pushes=0, pops=0, discarded=0, bypasses=0, recoveries=0;
  integer full_stalls=0;

  // Deterministic stimulus includes adjacent transfers, long stalls and reset.
  initial begin
    for(cycle=0; cycle<6000; cycle=cycle+1) begin
      @(negedge clk);
      reset=(cycle<3 || cycle%503==0);
      random_state=random_state*32'd1664525+32'd1013904223;
      pop_ready=cycle>=5900 || ((cycle%113)<73 && random_state[25]);
      if(reset || !producer_stalled) begin
        push_valid=cycle<5900 && random_state[29];
        for(word=0; word<7; word=word+1) begin
          random_state=random_state*32'd1664525+32'd1013904223;
          push_data=(push_data<<32) | random_state;
        end
      end
      #1;
      if(!reset) begin
        if(push_ready !== !occupied) $fatal(1,"upstream ready is not occupancy-only at %0d",cycle);
        if(pop_valid !== (occupied || push_valid)) $fatal(1,"valid mismatch at %0d",cycle);
        if(pop_valid && pop_data !== (occupied ? held : push_data)) $fatal(1,"payload mismatch at %0d",cycle);
        if(consumer_stalled && (!pop_valid || pop_data !== last_output)) $fatal(1,"stalled output changed");
      end
      @(posedge clk);
      if(reset) begin
        if(occupied) discarded=discarded+1;
        occupied=0; producer_stalled=0; consumer_stalled=0;
      end else begin
        if(occupied && !pop_ready) full_stalls=full_stalls+1;
        if(occupied && pop_ready && push_valid) recoveries=recoveries+1;
        if(!occupied && push_valid && pop_ready) bypasses=bypasses+1;
        if(push_valid && push_ready) pushes=pushes+1;
        if(pop_valid && pop_ready) pops=pops+1;
        if(push_valid && push_ready && !pop_ready) begin
          occupied=1; held=push_data;
        end else if(pop_valid && pop_ready) occupied=0;
        producer_stalled=push_valid && !push_ready;
        consumer_stalled=pop_valid && !pop_ready;
        last_output=pop_data;
      end
    end
    if(occupied || pushes!=pops+discarded || !bypasses || !recoveries || !discarded || !full_stalls)
      $fatal(1,"incomplete queue accounting or coverage");
    $display("PASS: aggregate FIFO pushes=%0d pops=%0d reset_discarded=%0d bypasses=%0d full_recovery=%0d full_stalls=%0d",
      pushes,pops,discarded,bypasses,recoveries,full_stalls);
    $finish;
  end
endmodule
