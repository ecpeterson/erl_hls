// Finite public-pin witness: two independent host recipients and real peer feedback.
module tb;
reg clk=0,reset=1;integer cycle=0,epoch,limit,i,k,cmd,stalled,accepted,kind;
integer counts[0:2];reg [2:0] last_stalled;reg [127:0] last_data[0:2];
wire [2:0] valid,ready;wire [127:0] data[0:2];
reg ingress_valid=0;reg [193:0] ingress_data=0;
assign ready[0]=kind!=0 || (cycle>120 && cycle%5!=epoch);
assign ready[1]=kind!=0 || (cycle>300 && cycle%7!=epoch);
assign ready[2]=kind!=0 || (cycle>50 && cycle%3!=epoch%3);
@@WIRING@@
// Independently construct the ordinary flattened SpatialFrame, not actor bit order.
function [193:0] packet(input integer x0,y0,x1,y1,target,n);
  packet={16'(x0),16'(y0),16'(x1),16'(y1),2'(target),8'd1,8'd0,8'd0,8'd4,64'd0,32'(n)};
endfunction
function [193:0] command(input integer index);
  case(index)
    0:command=packet(0,0,2,1,0,2);
    1:command=packet(0,0,0,0,0,3);
    2:command=packet(2,1,2,1,0,4);
    3:command=packet(0,0,2,1,1,1);
    4:command=packet(1,0,1,0,0,7); // Valid empty rectangle selection.
    default:command=packet(0,0,2,1,0,7);
  endcase
endfunction
function integer expected(input integer actor,index);
  if(actor==2) expected=0;
  else if(index<2) expected=0;
  else if(index==2) expected=2;
  else if(actor==0) expected=index==3 ? 5 : index==4 ? 6 : 13;
  else expected=index==3 ? 6 : 13;
endfunction
// Reset while idle, with a postponed host record, and with backpressured outputs.
task restart;
begin
  reset=1;ingress_valid=0;#5;clk=1;#5;clk=0;#1;
  if(valid!==0 || ingress_ready!==0 || ingress_fault!==0 || startup_done!==0) $fatal(1,"reset exposed ownership");
  reset=0;cmd=0;stalled=0;accepted=0;last_stalled=0;
  for(i=0;i<3;i=i+1) counts[i]=0;
end
endtask
initial begin
kind=0;
for(epoch=0;epoch<5;epoch=epoch+1) begin
 restart();limit=epoch==0 ? 5 : epoch==1 ? 40 : epoch==2 ? 170 : 1600;
 for(cycle=0;cycle<limit;cycle=cycle+1) begin
   ingress_valid=cmd<6;ingress_data=command(cmd);#4;
   if(faults!==0 || ingress_fault!==0) $fatal(1,"unexpected source/ingress fault");
   if(!startup_done && ingress_ready) $fatal(1,"host entered before startup consumption");
   if(ingress_valid && !ingress_ready) stalled=stalled+1;
   if(ingress_valid && ingress_ready) begin cmd=cmd+1;accepted=accepted+1;end
   for(i=0;i<3;i=i+1) begin
     if(last_stalled[i] && (!valid[i] || data[i]!==last_data[i])) $fatal(1,"changed stalled output");
     if(valid[i] && ready[i]) begin
       k=counts[i];
       if(data[i]!=={64'b0,32'(expected(i,k)),8'(i==2 ? 4 : 7),24'd1})
         $fatal(1,"wrong ingress output/order actor=%0d index=%0d data=%h",i,k,data[i]);
       if(k>=(i==0 ? 6 : i==1 ? 5 : 2)) $fatal(1,"duplicate ingress delivery");
       counts[i]=k+1;
     end
     last_stalled[i]=valid[i] && !ready[i];last_data[i]=data[i];
   end
   clk=1;#5;clk=0;#1;
 end
 if(epoch>=3 && (counts[0]!=6 || counts[1]!=5 || counts[2]!=2 || accepted!=6 || stalled<10 || !ingress_ready))
   $fatal(1,"incomplete ingress witness counts=%0d/%0d/%0d accepted=%0d stalled=%0d",counts[0],counts[1],counts[2],accepted,stalled);
end
// Every malformed command faults without dispatch, including a valid empty selection's bad schema.
kind=1;
for(epoch=0;epoch<8;epoch=epoch+1) begin
 restart();ingress_data=packet(0,0,2,1,0,2);
 case(epoch)
  0:ingress_data=packet(2,0,0,1,0,2);
  1:ingress_data=packet(0,0,3,1,0,2);
  2:ingress_data=packet(0,0,2,1,3,2);
  3:begin ingress_data=packet(1,0,1,0,0,2);ingress_data[103:96]=8'd250;end
  4:ingress_data[127:120]=8'd2;
  5:ingress_data[119:112]=8'd1;
  6:ingress_data[111:104]=8'd1;
  7:ingress_data[32]=1'b1;
 endcase
 for(cycle=0;cycle<120;cycle=cycle+1) begin
  ingress_valid=accepted==0;#4;
  if(ingress_valid && ingress_ready) accepted=accepted+1;
  if(faults!==0) $fatal(1,"malformed packet reached source");
  for(i=0;i<3;i=i+1) if(valid[i] && ready[i]) begin
    if(i==2 || counts[i]!=0 || data[i]!=={96'd0,8'd7,24'd1}) $fatal(1,"malformed packet delivered");
    counts[i]=counts[i]+1;
  end
  clk=1;#5;clk=0;#1;
 end
 if(accepted!=1 || !ingress_fault || ingress_ready || counts[0]!=1 || counts[1]!=1)
   $fatal(1,"missing sticky malformed fault kind=%0d",epoch);
end
// Canonical semantic failure must reach the actor and must not retire its host slot.
kind=2;
for(epoch=0;epoch<2;epoch=epoch+1) begin
 restart();ingress_data=packet(0,0,0,0,0,9);
 for(cycle=0;cycle<200;cycle=cycle+1) begin
  ingress_valid=accepted==0;#4;
  if(ingress_valid && ingress_ready) accepted=accepted+1;
  if(ingress_fault || actor_0_fault || actor_1_fault || actor_2_fault || actor_1_failure || actor_2_failure)
    $fatal(1,"canonical source failure mislabeled");
  clk=1;#5;clk=0;#1;
 end
 if(accepted!=1 || actor_0_failure==0 || ingress_ready) $fatal(1,"missing retained source failure");
end
$display("PROTOCOL_INGRESS_PASS outputs=13 commands=6 malformed=8 source_failure=2");$finish;
end
endmodule
