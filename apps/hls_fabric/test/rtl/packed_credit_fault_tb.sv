`timescale 1ns/1ps
// Inject malformed boundary transfers; every case starts a common reset epoch.
module packed_credit_fault_tb;
  parameter WORDS=4, CREDITS=4, COMPACT=0;
  localparam WIDTH=34*WORDS;
  reg clk=0, reset=1;
  always #4 clk=~clk;
  reg [WIDTH-1:0] incoming=0;
  reg incoming_valid=0;
  wire incoming_ready;
  wire [WIDTH-1:0] outgoing;
  wire outgoing_valid;
  wire [31:0] fault;
  wire fault_valid;
  wire [127:0] frames[0:0][0:7], delivered[0:0][0:7];
  wire [7:0] frame_valid[0:0], frame_ready[0:0], delivered_valid[0:0], delivered_ready[0:0];
  integer reports=0, expected=0, cases=0, allowed=0, delivered_count=0;
  genvar device,lane;
  for(device=0;device<1;device=device+1) begin
    for(lane=0;lane<8;lane=lane+1) begin
      assign frames[device][lane]=0;
      assign frame_valid[device][lane]=0;
      assign delivered_ready[device][lane]=1;
    end
    packed_link dut(.clk(clk),.reset(reset),
      ._link_in(incoming),._link_in_vld(incoming_valid),._link_in_rdy(incoming_ready),
      ._link_out(outgoing),._link_out_vld(outgoing_valid),._link_out_rdy(1'b1),
      ._fault_out(fault),._fault_out_vld(fault_valid),._fault_out_rdy(1'b1),
      @@CONNECTIONS@@);
  end

  // Fault cases deliver nothing; the legal regrouping case drains every frame in order.
  always @(posedge clk) if(!reset) begin
    if(delivered_valid[0]!=0) begin
      delivered_count=delivered_count+$countones(delivered_valid[0]);
      if(delivered_count>allowed) $fatal(1,"malformed packet delivered");
      if(allowed!=0) begin
        if(delivered_valid[0]!==8'b1) $fatal(1,"regrouped frame changed lane");
        case(delivered_count)
          1: if(delivered[0][0]!==128'h000000a5000000000000000000000000) $fatal(1,"first frame changed");
          2: if(delivered[0][0]!==128'h0000005a000000000000000000000000) $fatal(1,"second frame changed");
          3: if(delivered[0][0]!==128'h00000080000000000000000000000000) $fatal(1,"third frame changed");
          4: if(delivered[0][0]!==128'h000000ff000000000000000000000000) $fatal(1,"fourth frame changed");
        endcase
      end
    end
    if(fault_valid) begin
      if(fault!==expected || reports!=0) $fatal(1,"wrong/repeated fault: %0d expected %0d",fault,expected);
      reports=reports+1;
    end
  end

  // Reset clears a previous fault and every partial frame before the next case.
  task begin_case(input integer code);
    begin
      @(negedge clk); reset=1;incoming_valid=0;
      repeat(8) @(negedge clk);
      reports=0;expected=code;allowed=0;delivered_count=0;reset=0;cases=cases+1;
    end
  endtask

  // Only offered public transfers are injected; each remains stable until accepted.
  task transfer(input reg [WIDTH-1:0] value);
    integer waited;
    begin
      @(negedge clk); incoming=value;incoming_valid=1;waited=0;
      @(posedge clk);
      while(!incoming_ready) begin
        waited=waited+1;if(waited>100) $fatal(1,"injection stalled");
        @(posedge clk);
      end
      @(negedge clk); incoming_valid=0;
    end
  endtask

  // A single valid word also exercises partially filled wide transfers.
  task word(input reg [32:0] value);
    begin transfer({1'b1,value}); end
  endtask

  // Once reported, receive faults hold input closed until the common reset.
  task end_case;
    begin
      repeat(40) @(negedge clk);
      if(delivered_count!=allowed) $fatal(1,"valid prefix lost");
      if(reports!=(expected!=0)) $fatal(1,"wrong fault count for %0d",expected);
      if(expected!=0 && expected!=4 && incoming_ready) $fatal(1,"faulted receiver reopened");
      if(expected==4 && frame_ready[0]!=0) $fatal(1,"faulted transmitter reopened");
    end
  endtask

  initial begin
    begin_case(1);word(33'h012340000);end_case;
    begin_case(2);word(33'h048500008);end_case;
    begin_case(2);word(33'h148508008);end_case;
    begin_case(3);word(33'h148500000);end_case;
    begin_case(3);word(33'h048508000);end_case;
    begin_case(3);word(33'h048500000);word(33'h10000002a);end_case;
    begin_case(3);word(33'h048500000);repeat(4) word(33'h00000002a);end_case;
    // No data has reserved a slot, so even one incoming credit is excessive.
    begin_case(4);word(33'h148508000);end_case;
    begin_case(5);transfer(0);end_case;
    if(WORDS>1) begin
      begin_case(5);transfer({{(WIDTH-1){1'b0}},1'b1} << 67);end_case;
    end
    if(WORDS>2) begin
      begin_case(5);transfer(({{(WIDTH-1){1'b0}},1'b1} << 101) | 34'h248500000);end_case;
    end
    if(COMPACT) begin
      begin_case(3);word(33'h04851a580);end_case;
      begin_case(2);word(33'h14851a51f);end_case;
      begin_case(3);word(33'h14851a520);end_case;
      begin_case(3);word(33'h04851a500);end_case;
      begin_case(3);word(33'h04851a520);word(33'h000000001);end_case;
      // A serializer may regroup two valid packets for the same lane into one transfer.
      if(WORDS>1 && CREDITS>=2) begin
        begin_case(0);allowed=2;
        transfer((WIDTH'(34'h348515a00) << 34) | WIDTH'(34'h34851a500));end_case;
      end
      // Repeated tails must also resume correctly on successive activations.
      if(WORDS==4 && CREDITS>=4) begin
        begin_case(0);allowed=4;
        transfer((WIDTH'(34'h34851ff00) << 102) | (WIDTH'(34'h348518000) << 68)
          | (WIDTH'(34'h348515a00) << 34) | WIDTH'(34'h34851a500));end_case;
      end
    end
    $display("PASS: %0d packed framing/credit cases, WORDS=%0d CREDITS=%0d",cases,WORDS,CREDITS);
    $finish;
  end
  initial begin #100000; $fatal(1,"fault test timeout"); end
endmodule
