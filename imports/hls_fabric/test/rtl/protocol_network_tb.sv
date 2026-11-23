// Finite source/feedback witness. Only public boundary pins are observed; all
// publications and feedback come from actual compiled Erlang source owners.
module tb;
reg clk=0,reset=1;
integer cycle=0,epoch,limit,i,k,value,op,delta,total,independent,stalled;
integer counts[0:2],increments[0:7];
reg [2:0] last_stalled;
reg [127:0] last_data[0:2];
wire [2:0] valid,ready;
wire [127:0] data[0:2];
assign ready[0]=cycle>120 && cycle%5!=epoch;
assign ready[1]=cycle>12 && cycle%7!=epoch;
assign ready[2]=cycle>55 && cycle%3!=epoch;
@@WIRING@@
initial begin
  // Reset first interrupts held publications and pending feedback. The following
  // two full incarnations have different independent backpressure schedules.
  for(epoch=0;epoch<3;epoch=epoch+1) begin
    reset=1;#5;clk=1;#5;clk=0;#1;
    if(valid!==0) $fatal(1,"reset exposed output");
    reset=0;last_stalled=0;total=0;independent=0;stalled=0;
    for(i=0;i<3;i=i+1) counts[i]=0;
    for(i=0;i<8;i=i+1) increments[i]=0;
    limit=epoch==0 ? 40 : 600;
    for(cycle=0;cycle<limit;cycle=cycle+1) begin
      #4;
      if(faults!==0) $fatal(1,"source/publication fault");
      if(cycle==0 && valid!==0) $fatal(1,"startup exposed uninitialized output");
      for(i=0;i<3;i=i+1) begin
        if(last_stalled[i] && (!valid[i] || data[i]!==last_data[i])) $fatal(1,"changed stalled output");
        if(valid[i] && ready[i]) begin
          k=counts[i];
          if(i<2 || k<3) begin
            if((i<2 && k>=9) || (i==2 && k>=3)) $fatal(1,"duplicate source batch");
            op=k%3==1 ? 4 : 3;
            value=k%3==1 ? 7 : (k%3==0 ? 3 : 5)+(i<2 ? k/3 : 0);
          end else begin
            if(k>=21) $fatal(1,"duplicate sink result");
            op=5;value=data[i][63:32];delta=value-total;
            if(delta<0 || delta>7 || (delta!=0 && delta<3)) $fatal(1,"wrong source arithmetic");
            increments[delta]=increments[delta]+1;total=value;
            if(!ready[0]) independent=independent+1;
          end
          if(data[i]!=={64'b0,32'(value),8'(op),24'h000001}) $fatal(1,"wrong frame/order actor=%0d index=%0d",i,k);
          counts[i]=k+1;
        end
        last_stalled[i]=valid[i] && !ready[i];last_data[i]=data[i];
        if(last_stalled[i]) stalled=stalled+1;
      end
      clk=1;#5;clk=0;#1;
    end
    if(epoch==0) begin if(valid==0) $fatal(1,"reset did not interrupt publication"); end
    else if(counts[0]!=9 || counts[1]!=9 || counts[2]!=21 || total!=60 || valid!=0 ||
            increments[0]!=6 || increments[3]!=2 || increments[4]!=2 || increments[5]!=4 ||
            increments[6]!=2 || increments[7]!=2 || independent==0 || stalled<50)
      $fatal(1,"incomplete witness counts=%0d,%0d,%0d sum=%0d independent=%0d",counts[0],counts[1],counts[2],total,independent);
  end
  $display("PROTOCOL_NETWORK_PASS outputs=39 sum=60");$finish;
end
endmodule
