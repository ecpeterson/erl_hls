// Public-port witness: each actor retains its own result through contention,
// independent output stalls and resets at every early owner transition.
module tb;
localparam N=@@MEMBERS@@;
reg clk=0,reset=1;
integer cycle=0,cut,part,limit,i,stalled=0;
integer counts[0:N-1];
wire [N-1:0] valid,ready;
wire [127:0] data[0:N-1];
reg [N-1:0] held;
reg [127:0] previous[0:N-1];
genvar g;
generate for(g=0;g<N;g=g+1) begin
  assign ready[g]=cycle>20+g*5 && cycle%(g+3)!=0;
end endgenerate
@@WIRING@@
initial begin
  for(cut=0;cut<32;cut=cut+1) begin
    for(part=0;part<2;part=part+1) begin
      reset=1;#5;clk=1;#5;clk=0;#1;
      if(valid!==0) $fatal(1,"reset exposed result");
      reset=0;held=0;
      for(i=0;i<N;i=i+1) counts[i]=0;
      limit=part==0 ? cut : 100;
      for(cycle=0;cycle<limit;cycle=cycle+1) begin
        #4;
        if(faults!==0) $fatal(1,"source fault");
        for(i=0;i<N;i=i+1) begin
          if(held[i] && (!valid[i] || data[i]!==previous[i])) $fatal(1,"changed stalled result");
          if(valid[i] && ready[i]) begin
            if(counts[i]!=0 || data[i][47:32]!=(i+2)*(i+5)) $fatal(1,"wrong owner/result %0d %h",i,data[i]);
            counts[i]=counts[i]+1;
          end
          held[i]=valid[i] && !ready[i];previous[i]=data[i];
          if(held[i]) stalled=stalled+1;
        end
        clk=1;#5;clk=0;#1;
      end
      if(part==1) for(i=0;i<N;i=i+1) if(counts[i]!=1) $fatal(1,"missing result");
    end
  end
  if(stalled==0) $fatal(1,"no stall coverage");
  $display("ARITHMETIC_PASS members=%0d resets=32 stalled=%0d",N,stalled);$finish;
end
endmodule
