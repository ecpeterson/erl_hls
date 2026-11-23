// Finite public-pin witness: setup consumes while internal captures wait for start.
module tb;
reg clk=0,reset=1,start_valid=0,ingress_valid=0;
reg [193:0] ingress_data=0;
integer cycle=0,epoch,limit,i,k,kind=0,commands,starts;
integer counts[0:2];reg [2:0] last_stalled;reg [127:0] last_data[0:2];
reg old_running,handshake;
wire [2:0] valid,ready;wire [127:0] data[0:2];
assign ready[0]=kind!=0 || (cycle>300 && cycle%5!=epoch);
assign ready[1]=kind!=0 || (cycle>750 && cycle%7!=epoch);
assign ready[2]=kind!=0 || (cycle>700 && cycle%3!=epoch%3);
@@WIRING@@
// Independent ordinary SpatialFrame encoder: one target on a two-cell line.
function [193:0] packet(input integer last,n);
  packet={16'd0,16'd0,16'(last),16'd0,2'd0,8'd1,8'd0,8'd0,8'd4,64'd0,32'(n)};
endfunction
// Common reset also cancels start, a pending setup command and all old captures.
task restart;
begin
 reset=1;ingress_valid=0;start_valid=0;#5;clk=1;#5;clk=0;#1;
 if(valid!==0 || ingress_ready!==0 || ingress_fault!==0 || startup_done!==0 || running!==0 || start_ready!==0)
   $fatal(1,"reset exposed activation/ownership");
 reset=0;commands=0;starts=0;last_stalled=0;
 for(i=0;i<3;i=i+1) counts[i]=0;
end
endtask
// Hold captures through setup/output stalls, then score every per-sender result.
initial begin
for(epoch=0;epoch<6;epoch=epoch+1) begin
 restart();limit=epoch==0 ? 5 : epoch==1 ? 40 : epoch==2 ? 680 : epoch==3 ? 850 : 1600;
 for(cycle=0;cycle<limit;cycle=cycle+1) begin
   ingress_valid=commands==0 || (commands==1 && cycle>=500) ||
      (commands==2 && counts[0]>=3 && counts[1]>=3);
   ingress_data=commands==0 ? packet(1,5) : commands==1 ? packet(1,6) : packet(0,3);
   // A held initial start competes with setup; a later pulse competes with new setup.
   start_valid=(commands==0) || cycle==500 || cycle>=650;
   #4;
   if(faults!==0 || ingress_fault!==0) $fatal(1,"unexpected activation fault");
   if(start_ready && (running || !startup_done || !ingress_ready || ingress_valid))
     $fatal(1,"premature start readiness");
   if(!running && (valid[2] || counts[0]>1 || counts[1]>1)) $fatal(1,"internal traffic before start");
   if(cycle==499 && (running || !start_ready || commands!=1)) $fatal(1,"setup did not finish while stopped");
   if(cycle==649 && (running || !start_ready || commands!=2)) $fatal(1,"competing setup/start was not serialized");
   old_running=running;handshake=start_valid && start_ready;
   if(handshake) starts=starts+1;
   if(ingress_valid && ingress_ready) commands=commands+1;
   for(i=0;i<3;i=i+1) begin
     if(last_stalled[i] && (!valid[i] || data[i]!==last_data[i])) $fatal(1,"changed stalled output");
     if(valid[i] && ready[i]) begin
       k=counts[i];
       if(data[i]!=={64'd0,32'(i==2 ? 1 : k==0 ? 0 : k==1 ? 7 : k==2 ? 8 : 11),8'(i==2 ? 4 : 7),24'd1})
         $fatal(1,"wrong activation output/order actor=%0d index=%0d data=%h",i,k,data[i]);
       if(k>=(i==0 ? 4 : i==1 ? 3 : 2)) $fatal(1,"duplicate activation delivery");
       counts[i]=k+1;
     end
     last_stalled[i]=valid[i] && !ready[i];last_data[i]=data[i];
   end
   clk=1;#5;clk=0;#1;
   if(running!==(old_running || handshake)) $fatal(1,"start did not register exactly once");
 end
 if(epoch>=4 && (counts[0]!=4 || counts[1]!=3 || counts[2]!=2 || commands!=3 || starts!=1 || !ingress_ready || !running))
   $fatal(1,"incomplete activation witness counts=%0d/%0d/%0d commands=%0d starts=%0d",counts[0],counts[1],counts[2],commands,starts);
end
// Malformed setup, canonical source failure and a postponed setup all prevent start.
for(kind=1;kind<=3;kind=kind+1) begin
 for(epoch=0;epoch<2;epoch=epoch+1) begin
  restart();ingress_data=packet(1,kind==2 ? 9 : kind==3 ? 7 : 5);
  if(kind==1) ingress_data[103:96]=8'd250;
  for(cycle=0;cycle<200;cycle=cycle+1) begin
   ingress_valid=commands==0;start_valid=1;#4;
   if(ingress_valid && ingress_ready) commands=commands+1;
   if(running || start_ready || valid[2]) $fatal(1,"blocked setup incorrectly started");
   clk=1;#5;clk=0;#1;
  end
  if(commands!=1 || ingress_ready) $fatal(1,"setup ownership was lost");
  if(kind==1 && (!ingress_fault || faults!==0)) $fatal(1,"malformed setup did not fault cleanly");
  if(kind==2 && (ingress_fault || actor_0_failure==0 || actor_1_failure==0)) $fatal(1,"source setup failure was lost");
  if(kind==3 && (ingress_fault || faults!==0)) $fatal(1,"postponed setup was mislabeled");
 end
end
$display("PROTOCOL_ACTIVATION_PASS outputs=9 commands=3 starts=1 blocked=6");$finish;
end
endmodule
