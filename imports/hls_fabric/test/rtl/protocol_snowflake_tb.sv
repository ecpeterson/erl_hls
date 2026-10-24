// D2/H2 source graph, eight finite sheets. Only public pins enter this scoreboard.
module tb;
reg clk=0,reset=1,start_valid=0,ingress_valid=0;
reg [193:0] ingress_data=0;
wire [2:0] ready,valid;
wire [127:0] data[0:2];
integer cycle,epoch,commands,rounds,starts,i,j,owner,retired,limit;
integer counts[0:@@OWNERS@@-1];
reg [2:0] stalled;
reg [127:0] held[0:2];
reg corrupt,completed;
@@WIRING@@
@@TABLES@@
// Spatial ingress uses flattened struct order; egress uses canonical wire words.
function [193:0] packet(input [127:0] frame);
 packet={66'd0,frame[7:0],frame[15:8],frame[23:16],frame[31:24],frame[127:32]};
endfunction
// Independent backpressure reaches held publication without modifying actor inputs.
assign ready[0]=cycle>100 && cycle%5!=0;
assign ready[1]=cycle>250 && cycle%7!=0;
assign ready[2]=cycle%3!=0;
initial begin
 completed=0;corrupt=$test$plusargs("corrupt");
 // First abandon an in-flight incarnation; then replay the complete finite stream.
 for(epoch=0;epoch<2 && !completed;epoch=epoch+1) begin
  reset=1;start_valid=0;ingress_valid=0;stalled=0;
  #5;clk=1;#5;clk=0;#1;
  if(valid!==0 || running!==0 || ingress_ready!==0) $fatal(1,"reset exposed ownership");
  reset=0;commands=0;rounds=0;starts=0;retired=0;
  for(i=0;i<@@OWNERS@@;i=i+1) counts[i]=0;
  limit=epoch==0 ? 180 : 100000;
  for(cycle=0;cycle<limit && !completed;cycle=cycle+1) begin
   start_valid=starts==0;
   // Activate before offering work; then allow one sheet to overlap its predecessor.
   ingress_valid=running && commands<8 && commands<rounds+2;
   ingress_data=packet(input_frame(commands));
   #4;
   if(fault) begin
    @@FAULTS@@
    $fatal(1,"actor or ingress fault cycle=%0d",cycle);
   end
   if(ingress_valid && ingress_ready) commands=commands+1;
   if(start_valid && start_ready) starts=starts+1;
   for(i=0;i<3;i=i+1) begin
    if(stalled[i] && (!valid[i] || data[i]!==held[i])) $fatal(1,"unstable held output");
    stalled[i]=valid[i] && !ready[i];held[i]=data[i];
   end
   if(valid[@@UNEXPECTED@@]) $fatal(1,"unexpected boundary traffic");
   if(valid[@@ROUNDS@@] && ready[@@ROUNDS@@]) begin
    if(rounds>=8 || data[@@ROUNDS@@] !== (round_frame(rounds) ^ (corrupt ? 128'd1 : 128'd0)))
     $fatal(1,"wrong round frame/order index=%0d actual=%h expected=%h",rounds,data[@@ROUNDS@@],round_frame(rounds));
    rounds=rounds+1;
   end
   if(valid[@@CORRECTIONS@@] && ready[@@CORRECTIONS@@]) begin
    owner=-1;
    for(j=0;j<@@OWNERS@@;j=j+1)
     if(counts[j]<6 && data[@@CORRECTIONS@@]===correction_frame(6*j+counts[j])) owner=j;
    if(owner<0) $fatal(1,"wrong correction frame/order %h",data[@@CORRECTIONS@@]);
    counts[owner]=counts[owner]+1;retired=retired+1;
   end
   clk=1;#5;clk=0;#1;
   if(epoch==1 && rounds==8 && retired==6*@@OWNERS@@) begin
    if(commands!=8 || starts!=1) $fatal(1,"incomplete command stream");
    completed=1;
   end
  end
 end
 if(!completed) $fatal(1,"incomplete Snowflake witness commands=%0d rounds=%0d corrections=%0d",commands,rounds,retired);
 else begin
  $display("SNOWFLAKE_PASS sheets=8 cycles=%0d corrections=%0d",cycle,retired);$finish;
 end
end
endmodule
