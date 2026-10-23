// Finite public-pin witness: identifiable source order across independent endpoints.
module tb;
reg clk=0,reset=1,start_valid=0,ingress_valid=0;reg [193:0] ingress_data=0;
integer cycle=0,epoch,limit,i,j,source,position,commands,starts;
integer counts[0:3];reg [2:0] last_stalled;reg [127:0] last_data[0:2];
reg old_running,handshake;wire [2:0] valid,ready;wire [127:0] data[0:2];
assign ready[0]=cycle>200 && cycle%5!=epoch;
assign ready[1]=cycle>450 && cycle%7!=epoch;
assign ready[2]=cycle%2==0;
@@EXPECTED@@
@@WIRING@@
// Ordinary flattened SpatialFrame: payload value, cfg/work selector and inclusive geometry.
function [193:0] packet(input integer lo,hi,tag,value);
 packet={16'(lo),16'd0,16'(hi),16'd0,2'd0,8'd1,8'd0,8'd0,8'(tag),64'd0,32'(value)};
endfunction
// Reset before/after held selections, partially delivered batches and host commands.
task restart;
begin
 reset=1;ingress_valid=0;start_valid=0;#5;clk=1;#5;clk=0;#1;
 if(valid!==0 || running!==0 || ingress_ready!==0 || startup_done!==0 || start_ready!==0)
   $fatal(1,"reset exposed boundary ownership");
 reset=0;commands=0;starts=0;last_stalled=0;
 for(i=0;i<4;i=i+1) counts[i]=0;
end
endtask
initial begin
for(epoch=0;epoch<6;epoch=epoch+1) begin
 restart();limit=epoch==0 ? 5 : epoch==1 ? 80 : epoch==2 ? 350 : epoch==3 ? 650 : 1600;
 for(cycle=0;cycle<limit;cycle=cycle+1) begin
  ingress_valid=cycle>80 && (commands<2 || (commands<7 && running && counts[0]==commands-1 && counts[1]==commands-1 && counts[2]==commands-1 && counts[3]==commands-1));
  ingress_data=commands==0 ? packet(0,0,3,1) : commands==1 ? packet(1,1,3,2) : packet(0,3,4,commands<4 ? commands-1 : commands+6);
  start_valid=commands>=2 && cycle>100;#4;
  if(faults!==0 || ingress_fault!==0) $fatal(1,"unexpected source fault");
  if(valid[2]!==0 || data[2]!==0) $fatal(1,"unused endpoint became active");
  if(cycle==400 && (counts[0]!=1 || counts[1]!=1 || counts[2]!=1 || counts[3]!=0))
    $fatal(1,"independent endpoint was stalled");
  old_running=running;handshake=start_valid && start_ready;
  if(handshake) starts=starts+1;
  if(ingress_valid && ingress_ready) commands=commands+1;
  for(i=0;i<3;i=i+1) begin
   if(last_stalled[i] && (!valid[i] || data[i]!==last_data[i])) $fatal(1,"changed stalled boundary frame");
   if(valid[i] && ready[i]) begin
    source=-1;position=-1;
    for(j=0;j<4;j=j+1) if(counts[j]<6 && data[i]===expected(j,counts[j])) begin source=j;position=counts[j];end
    if(source<0 || (i==0 && source==3) || (i==1 && source!=3) || i==2)
      $fatal(1,"wrong boundary frame/order endpoint=%0d data=%h",i,data[i]);
    counts[source]=position+1;
   end
   last_stalled[i]=valid[i] && !ready[i];last_data[i]=data[i];
  end
  clk=1;#5;clk=0;#1;
  if(running!==(old_running || handshake)) $fatal(1,"start passthrough mismatch");
 end
 if(epoch>=4 && (counts[0]!=6 || counts[1]!=6 || counts[2]!=6 || counts[3]!=6 || commands!=7 || starts!=1 || !ingress_ready))
   $fatal(1,"incomplete boundary witness counts=%0d/%0d/%0d/%0d commands=%0d starts=%0d",counts[0],counts[1],counts[2],counts[3],commands,starts);
end
$display("PROTOCOL_BOUNDARY_PASS outputs=24 commands=7 starts=1");$finish;
end
endmodule
