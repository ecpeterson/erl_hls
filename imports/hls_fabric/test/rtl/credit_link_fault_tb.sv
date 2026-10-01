`timescale 1ns/1ps
module credit_link_fault_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg reset=1;
  reg [32:0] beat=0;
  reg valid=0;
  wire ready;
  wire [31:0] fault;
  wire fault_valid;
  wire frame0_valid,frame1_valid;
  integer timeout,observed;
  link dut(.clk(clk),.reset(reset),._link_in(beat),._link_in_vld(valid),._link_in_rdy(ready),
    ._link_out_rdy(1'b1),._frames_in__0(128'b0),._frames_in__0_vld(1'b0),
    ._frames_in__1(128'b0),._frames_in__1_vld(1'b0),
    ._frames_out__0_vld(frame0_valid),._frames_out__0_rdy(1'b1),
    ._frames_out__1_vld(frame1_valid),._frames_out__1_rdy(1'b1),
    ._fault_out(fault),._fault_out_vld(fault_valid),._fault_out_rdy(1'b1));
  always @(posedge clk) if(!reset) begin
    if(frame0_valid || frame1_valid) $fatal(1,"malformed packet delivered an application frame");
    if(fault_valid) begin
      if(observed!=0) $fatal(1,"fault reported more than once");
      observed=fault;
    end
  end
  task restart;
    begin
      @(negedge clk); reset=1; valid=0;
      repeat(8) @(negedge clk);
      observed=0; reset=0;
    end
  endtask
  task send(input [31:0] word,input last);
    begin
      @(negedge clk); beat={last,word};valid=1;
      timeout=0;
      @(posedge clk);
      while(!ready) begin
        @(posedge clk); timeout=timeout+1;
        if(timeout>100) $fatal(1,"raw injection blocked");
      end
      @(negedge clk);valid=0;
    end
  endtask
  task expect_fault(input integer code);
    begin
      timeout=0;
      while(observed==0) begin
        @(negedge clk);timeout=timeout+1;
        if(timeout>100) $fatal(1,"missing fault %d",code);
      end
      if(observed!=code) $fatal(1,"fault %d expected %d",observed,code);
      repeat(20) @(negedge clk);
    end
  endtask
  initial begin
    restart();send(32'hdead0000,0);expect_fault(1);
    restart();send(32'h48500002,0);expect_fault(2);
    restart();send(32'h48500000,1);expect_fault(3);
    restart();send(32'h48508000,0);expect_fault(3);
    restart();send(32'h48500000,0);send(32'h0,1);expect_fault(3);
    restart();send(32'h48500000,0);send(0,0);send(0,0);send(0,0);send(0,0);expect_fault(3);
    restart();send(32'h48508000,1);expect_fault(4);
    $display("PASS: tag, lane, short/long framing and excess-credit faults");$finish;
  end
endmodule
