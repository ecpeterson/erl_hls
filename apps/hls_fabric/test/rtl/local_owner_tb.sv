// Finite source witnesses: independent frame/retirement scoreboards, two reset
// incarnations, stalled publication, and no duplicated selected-head retirement.
module tb;
parameter ROLE=0;
localparam REQUESTS=(ROLE==0 || ROLE==3) ? 2 : 5;
localparam EMISSIONS=ROLE==1 ? 0 : (ROLE==3 ? 4 : 2);
reg clk=0, reset=1, received=0, output_ready=0;
reg [127:0] frame=0;
wire [158:0] observation;
wire input_ready,head_done,dispatched,phase_boundary,output_valid;
wire [1:0] directive;
wire [7:0] port;
wire [127:0] effect;
wire [15:0] failure;
assign {input_ready,head_done,dispatched,directive,phase_boundary,output_valid,port,effect,failure}=observation;
local_actor dut(.clk(clk),.reset(reset),._commands({reset,received,frame,32'b0,output_ready}),
  ._commands_vld(1'b1),._commands_rdy(),._observations(observation),
  ._observations_vld(),._observations_rdy(1'b1));
integer cycle,incarnation,accepted,retired,emitted,held,stalls;
// Ordinary wire encoding: header then little-endian source record fields.
function [127:0] message(input integer i);
  reg [31:0] value,member;
  begin
    value=i+2;
    member=i==2 ? 9 : (i==3 ? 2 : 7);
    if(ROLE==0 || ROLE==3) message={64'b0,(i==0 ? 32'd3 : 32'd5),32'h03000001};
    else if(ROLE==1) message=i<2 ? {32'b0,value,32'b0,32'h03000002} : {value,member,32'b0,32'h04000003};
    else if(i==1) message={56'b0,8'd5,32'd2,32'h03000002};
    else if(i==4) message={56'b0,8'd5,32'd2,32'h05000002};
    else message={24'b0,(i==2 ? 8'd3 : 8'd7),(i==2 ? 32'd2 : 32'd0),32'd2,32'h04000003};
  end
endfunction
// Distinct sequence values catch omissions, repetitions and within-batch reorder.
function [31:0] expected_value(input integer i);
  begin
    if(ROLE==2) expected_value=i==0 ? 307 : 312;
    else if(ROLE==3) case(i) 0:expected_value=3;1:expected_value=103;2:expected_value=8;default:expected_value=108;endcase
    else expected_value=i==0 ? 3 : 8;
  end
endfunction
reg [127:0] last_effect;
reg stalled;
initial begin
  for(incarnation=0;incarnation<2;incarnation=incarnation+1) begin
    reset=1;received=1;output_ready=1;
    #5;clk=1;#5;clk=0;#1;
    if(observation!==159'b0) $fatal(1,"reset exposed ownership");
    reset=0;accepted=0;retired=0;emitted=0;held=0;stalls=0;stalled=0;
    for(cycle=0;cycle<100;cycle=cycle+1) begin
      received=accepted<REQUESTS && !held;
      frame=message(accepted);
      output_ready=cycle>30 && cycle%5!=0;
      #4;
      if(cycle==0 && (input_ready || head_done || output_valid)) $fatal(1,"handshake before source initialization");
      if(failure!==0) $fatal(1,"unexpected source fault");
      if(stalled && (!output_valid || effect!==last_effect)) $fatal(1,"publication changed during stall");
      if(input_ready && received) begin accepted=accepted+1;held=1;end
      if(head_done) begin
        if(!held || !dispatched || directive!=(ROLE==2 && retired==0 ? 1 : 0)) $fatal(1,"bad retirement");
        if((ROLE==0 || ROLE==3) && !phase_boundary) $fatal(1,"missing boundary");
        held=0;retired=retired+1;
      end
      if(output_valid && output_ready) begin
        if(port!=(ROLE==3 ? emitted%2 : 0) || effect[31:0] !== (ROLE==2 ? 32'h06000001 : 32'h04000001) || effect[127:64]!==0 ||
          effect[63:32] !== expected_value(emitted)) $fatal(1,"wrong or duplicate publication");
        emitted=emitted+1;
      end
      stalled=output_valid && !output_ready;last_effect=effect;
      if(stalled) stalls=stalls+1;
      clk=1;#5;clk=0;#1;
    end
    if(accepted!=REQUESTS || retired!=REQUESTS || emitted!=EMISSIONS || held || (ROLE!=1 && stalls==0)) $fatal(1,"missing progress/coverage");
  end
  // Reset an owned action before it can retire or publish, then drain only init.
  if(ROLE==0 || ROLE==3) begin
  received=1;frame={64'b0,32'd7,32'h03000001};output_ready=0;#4;clk=1;#5;clk=0;#1;
  reset=1;#4;clk=1;#5;clk=0;#1;reset=0;received=0;output_ready=1;
  repeat(8) begin #4;if(head_done || output_valid) $fatal(1,"stale ownership after reset");clk=1;#5;clk=0;#1;end
  end
  $display("LOCAL_OWNER_PASS role=%0d", ROLE);$finish;
end
endmodule
