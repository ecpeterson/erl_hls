// Check real generated per-producer ownership across early input, stalls and reset.
module direct_collection_tb;
  parameter [7:0] TAG_BEGIN_SET=0,TAG_PIECE=0,TAG_RESULT=0;
  parameter OBSERVATION_BITS=1;
  reg clk=0, reset=1;
  wire [OBSERVATION_BITS-1:0] observation;
  wire observation_valid;
  reg saw_failure=0;
  always #5 clk=~clk;
  reg [127:0] first=0, second=0, startup=0;
  reg fv=0, sv=0, iv=0, ready=0;
  wire fr,sr,ir,valid;
  wire [135:0] output_data;
  integer cycles=0, outputs=0, expected=0, marker_mode=0, last_output_cycle=0;
  integer expected_value;
  reg stalled=0;
  reg [135:0] held_output=0;
  collector dut(.clk(clk),.reset(reset),._inputs__0(first),._inputs__0_vld(fv),._inputs__0_rdy(fr),
    ._inputs__1(second),._inputs__1_vld(sv),._inputs__1_rdy(sr),._startup(startup),._startup_vld(iv),
    ._startup_rdy(ir),._output(output_data),._output_vld(valid),._output_rdy(ready),
    ._observation(observation),._observation_vld(observation_valid),._observation_rdy(1'b1));

  // A frame has an eight-bit word count and tag above its packed record bits.
  function automatic [127:0] piece(input integer key, member, value);
    piece={8'd3,16'd0,TAG_PIECE,24'd0,value[7:0],member[31:0],key[31:0]};
  endfunction
  function automatic [127:0] opening(input integer key);
    opening={8'd2,16'd0,TAG_BEGIN_SET,56'd0,8'd63,key[31:0]};
  endfunction
  // Hold a producer's frame until its own ready/valid transfer, with no retries.
  task automatic send_piece(input integer lane,key,member,value);
    begin
      @(negedge clk);
      if(lane==0) begin first=piece(key,member,value);fv=1;end
      else begin second=piece(key,member,value);sv=1;end
      @(posedge clk);
      while (!(lane==0 ? fr : sr)) @(posedge clk);
      @(negedge clk);
      if(lane==0) fv=0; else sv=0;
    end
  endtask
  task automatic send_open(input integer key);
    begin
      @(negedge clk);startup=opening(key);iv=1;
      @(posedge clk);while(!ir) @(posedge clk);
      @(negedge clk);iv=0;
    end
  endtask
  // Restart clears old contributions as well as held inputs and publication.
  task automatic restart;
    begin
      @(negedge clk);reset=1;fv=0;sv=0;iv=0;ready=0;
      repeat(4) @(negedge clk);
      outputs=0;saw_failure=0;reset=0;
    end
  endtask
  always @(posedge clk) begin
    cycles<=cycles+1;
    if(cycles>2500) $fatal(1,"timeout");
    // A committed effect cannot change or disappear while the consumer stalls.
    if(reset) stalled<=0;
    else begin
      if(stalled && (!valid || output_data!==held_output))
        $fatal(1,"output changed while backpressured");
      stalled<=valid && !ready;
      if(valid && !ready) held_output<=output_data;
    end
    if(!reset && observation_valid && observation[24:9]!=0) saw_failure<=1;
    if(!reset && valid && ready) begin
      expected_value=marker_mode && outputs==0 ? 255 :
                     marker_mode && outputs==1 ? 254 : expected;
      if(output_data[103:96]!==TAG_RESULT || output_data[7:0]!==expected_value[7:0])
        $fatal(1,"wrong output: %h expected %d",output_data,expected_value);
      if(marker_mode==1 && outputs==1 && cycles!=last_output_cycle+2)
        $fatal(1,"registered actor entry cadence changed");
      last_output_cycle<=cycles;
      outputs<=outputs+1;
    end
  end
  initial begin
    repeat(4) @(negedge clk);reset=0;
    // Capture both producers before opening; stall the sole completed result.
    fork
      begin send_piece(0,7,0,1);send_piece(0,7,2,4);send_piece(0,7,4,16);end
      begin send_piece(1,7,5,32);send_piece(1,7,3,8);send_piece(1,7,1,2);end
    join
    repeat(10) @(negedge clk);
    if(valid) $fatal(1,"published before opening");
    send_open(7);
    repeat(30) @(negedge clk);
    if(!valid) $fatal(1,"completed result missing under stall");
    expected=63;ready=1;
    repeat(20) @(negedge clk);
    if(outputs!=1) $fatal(1,"duplicate or missing completion");
    restart();send_piece(0,7,0,255);repeat(5) @(negedge clk);
    restart();send_open(9);expected=63;ready=1;
    fork
      begin send_piece(0,9,4,16);send_piece(0,9,2,4);send_piece(0,9,0,1);end
      begin send_piece(1,9,1,2);send_piece(1,9,3,8);send_piece(1,9,5,32);end
    join
    repeat(30) @(negedge clk);
    if(outputs!=1 || saw_failure) $fatal(1,"reset leaked stale collection");
    // Reset with a fully computed, unpublished result must discard that effect.
    restart();send_open(10);
    fork
      begin send_piece(0,10,0,1);send_piece(0,10,2,4);send_piece(0,10,4,16);end
      begin send_piece(1,10,1,2);send_piece(1,10,3,8);send_piece(1,10,5,32);end
    join
    repeat(30) @(negedge clk);
    if(!valid) $fatal(1,"missing held effect before reset");
    restart();ready=1;
    repeat(20) @(negedge clk);
    if(valid || outputs!=0) $fatal(1,"reset leaked a retained effect");
    send_open(10);
    send_piece(0,10,0,1);send_piece(1,10,0,2);
    repeat(30) @(negedge clk);
    if(outputs!=0 || !saw_failure) $fatal(1,"duplicate member did not fail through debug observation");
    // Actor entry effects retain the two-clock registered grant/execute cadence.
    restart();marker_mode=1;expected=63;
    fork
      begin send_piece(0,8,0,1);send_piece(0,8,2,4);send_piece(0,8,4,16);end
      begin send_piece(1,8,1,2);send_piece(1,8,3,8);send_piece(1,8,5,32);end
    join
    send_open(8);repeat(30) @(negedge clk);
    if(!valid) $fatal(1,"missing first entry effect under stall");
    ready=1;repeat(30) @(negedge clk);
    if(outputs!=3 || saw_failure) $fatal(1,"ordered entry effects did not drain");
    // Registered opening validation follows both committed entry effects; it
    // reports a fault without retracting either or publishing a completion.
    restart();marker_mode=2;send_piece(0,7,0,1);send_open(8);
    repeat(30) @(negedge clk);
    if(!valid) $fatal(1,"missing committed effect before opening fault");
    ready=1;repeat(30) @(negedge clk);
    if(outputs!=2 || !saw_failure) $fatal(1,"opening fault lost or duplicated committed effects");
    $display("PASS: early/open input, two producer orders, stable held output, partial/held-effect reset, registered entry cadence and protocol failures");
    $finish;
  end
endmodule
