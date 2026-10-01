`timescale 1ns/1ps
module credit_link_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1;
  integer cycle = 0;
  integer epoch = 0;
  localparam COUNT = 48;
  integer sent [0:3];
  integer received [0:3];
  wire [127:0] input_frame [0:3];
  wire [127:0] output_frame [0:3];
  wire [3:0] input_ready, output_valid;
  reg [3:0] output_ready;
  wire [32:0] a_tx, b_tx;
  wire a_valid, a_ready, b_valid, b_ready, a_rx_ready, b_rx_ready;
  wire [31:0] a_fault, b_fault;
  wire a_fault_valid, b_fault_valid;
  wire ab_gate = (cycle % 11 >= 3) && !(cycle >= 300 && cycle < 500);
  wire ba_gate = (cycle % 7 >= 2);
  assign a_ready = b_rx_ready && ab_gate;
  assign b_ready = a_rx_ready && ba_gate;

  function automatic [127:0] sample(input integer lane, input integer ordinal);
    sample = {32'h03000042 ^ lane ^ (epoch * 32'h10000), 32'h31415926 ^ ordinal,
              32'hf0e1d2c3 ^ (ordinal * 32'd17), 32'habcd0000 + lane * 32'd256 + ordinal};
  endfunction
  genvar i;
  generate for (i=0; i<4; i=i+1) begin
    assign input_frame[i] = sample(i, sent[i]);
  end endgenerate

  link a(.clk(clk), .reset(reset),
    ._link_in(b_tx), ._link_in_vld(b_valid && ba_gate), ._link_in_rdy(a_rx_ready),
    ._link_out(a_tx), ._link_out_vld(a_valid), ._link_out_rdy(a_ready),
    ._frames_in__0(input_frame[0]), ._frames_in__0_vld(sent[0]<COUNT), ._frames_in__0_rdy(input_ready[0]),
    ._frames_in__1(input_frame[1]), ._frames_in__1_vld(sent[1]<COUNT), ._frames_in__1_rdy(input_ready[1]),
    ._frames_out__0(output_frame[2]), ._frames_out__0_vld(output_valid[2]), ._frames_out__0_rdy(output_ready[2]),
    ._frames_out__1(output_frame[3]), ._frames_out__1_vld(output_valid[3]), ._frames_out__1_rdy(output_ready[3]),
    ._fault_out(a_fault), ._fault_out_vld(a_fault_valid), ._fault_out_rdy(1'b1));
  link b(.clk(clk), .reset(reset),
    ._link_in(a_tx), ._link_in_vld(a_valid && ab_gate), ._link_in_rdy(b_rx_ready),
    ._link_out(b_tx), ._link_out_vld(b_valid), ._link_out_rdy(b_ready),
    ._frames_in__0(input_frame[2]), ._frames_in__0_vld(sent[2]<COUNT), ._frames_in__0_rdy(input_ready[2]),
    ._frames_in__1(input_frame[3]), ._frames_in__1_vld(sent[3]<COUNT), ._frames_in__1_rdy(input_ready[3]),
    ._frames_out__0(output_frame[0]), ._frames_out__0_vld(output_valid[0]), ._frames_out__0_rdy(output_ready[0]),
    ._frames_out__1(output_frame[1]), ._frames_out__1_vld(output_valid[1]), ._frames_out__1_rdy(output_ready[1]),
    ._fault_out(b_fault), ._fault_out_vld(b_fault_valid), ._fault_out_rdy(1'b1));

  reg a_stalled = 0, b_stalled = 0;
  reg [32:0] previous_a, previous_b;
  integer k;
  integer a_stage=0,b_stage=0;
  integer a_credit[0:1],b_credit[0:1];
  integer wire_lane;
  initial begin
    for(k=0;k<4;k=k+1) begin sent[k]=0; received[k]=0; end
    output_ready=0;
    repeat(8) @(negedge clk);
    reset=0;
    // Reset the whole link while queues and a partial packet are occupied.
    // New payloads identify their activation, so stale delivery cannot pass.
    wait(cycle>=200 && (a_stage!=0 || b_stage!=0));
    @(negedge clk);
    if(a_stage==0 && b_stage==0) $fatal(1,"reset did not interrupt a packet");
    reset=1;
    repeat(8) @(negedge clk);
    cycle=0;epoch=1;
    for(k=0;k<4;k=k+1) begin sent[k]=0;received[k]=0;end
    reset=0;
  end
  always @(negedge clk) begin
    output_ready[0] = cycle >= 3000 && cycle % 5 != 0;
    output_ready[1] = cycle % 3 != 0;
    output_ready[2] = cycle % 13 >= 5;
    output_ready[3] = cycle % 9 >= 2;
  end
  always @(posedge clk) if(reset) begin
    a_stalled <= 0;b_stalled <= 0;
    a_stage=0;b_stage=0;
    for(k=0;k<2;k=k+1) begin a_credit[k]=1;b_credit[k]=1;end
  end else begin
    cycle <= cycle+1;
    if(a_fault_valid || b_fault_valid) $fatal(1,"unexpected fault a=%d b=%d",a_fault,b_fault);
    if(a_stalled && (!a_valid || a_tx !== previous_a)) $fatal(1,"A changed a stalled beat");
    if(b_stalled && (!b_valid || b_tx !== previous_b)) $fatal(1,"B changed a stalled beat");
    a_stalled <= a_valid && !a_ready;
    b_stalled <= b_valid && !b_ready;
    previous_a <= a_tx; previous_b <= b_tx;
    // Count data reservations and returned credits at the public wire. No
    // internal signal lookup is needed to establish the one-credit bound.
    if(a_valid && a_ready) begin
      wire_lane=a_tx[14:0];
      if(a_stage==0) begin
        if(a_tx[31:16]!=16'h4850 || wire_lane>1) $fatal(1,"invalid A header");
        if(a_tx[15]) begin
          b_credit[wire_lane]=b_credit[wire_lane]+1;
          if(b_credit[wire_lane]>1 || !a_tx[32]) $fatal(1,"excess B credit");
        end else begin
          a_credit[wire_lane]=a_credit[wire_lane]-1;
          if(a_credit[wire_lane]<0 || a_tx[32]) $fatal(1,"A sent without credit");
          a_stage=1;
        end
      end else begin
        if(a_tx[32] !== (a_stage==4)) $fatal(1,"A framing");
        a_stage=(a_stage==4)?0:a_stage+1;
      end
    end
    if(b_valid && b_ready) begin
      wire_lane=b_tx[14:0];
      if(b_stage==0) begin
        if(b_tx[31:16]!=16'h4850 || wire_lane>1) $fatal(1,"invalid B header");
        if(b_tx[15]) begin
          a_credit[wire_lane]=a_credit[wire_lane]+1;
          if(a_credit[wire_lane]>1 || !b_tx[32]) $fatal(1,"excess A credit");
        end else begin
          b_credit[wire_lane]=b_credit[wire_lane]-1;
          if(b_credit[wire_lane]<0 || b_tx[32]) $fatal(1,"B sent without credit");
          b_stage=1;
        end
      end else begin
        if(b_tx[32] !== (b_stage==4)) $fatal(1,"B framing");
        b_stage=(b_stage==4)?0:b_stage+1;
      end
    end
    for(k=0;k<4;k=k+1) begin
      if(input_ready[k] && sent[k]<COUNT) sent[k] <= sent[k]+1;
      if(output_valid[k] && output_ready[k]) begin
        if(received[k]>=COUNT || output_frame[k] !== sample(k,received[k]))
          $fatal(1,"lane %d ordinal %d received %h expected %h",k,received[k],output_frame[k],sample(k,received[k]));
        received[k] <= received[k]+1;
      end
    end
    if(cycle==2999) begin
      if(received[0]!=0 || received[1]!=COUNT || received[2]!=COUNT || received[3]!=COUNT)
        $fatal(1,"blocked lane prevented independent progress: %d %d %d %d",received[0],received[1],received[2],received[3]);
      $display("PASS: blocked lane isolated; other lanes delivered %0d/%0d/%0d",received[1],received[2],received[3]);
    end
    if(received[0]==COUNT && received[1]==COUNT && received[2]==COUNT && received[3]==COUNT) begin
      $display("PASS: credit link delivered %0d ordered frames in %0d cycles",4*COUNT,cycle);
      $finish;
    end
    if(cycle>30000) $fatal(1,"link timeout: %d %d %d %d",received[0],received[1],received[2],received[3]);
  end
endmodule
