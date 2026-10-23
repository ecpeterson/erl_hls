// Finite public-pin witness. All inputs beyond reset/readiness come from source
// startup records or actual peer actors; no fixture injects runtime publications.
module tb;
reg clk=0,reset=1;
integer cycle=0,epoch=0,limit,i,k,expected,main_count,peer_count,seen_done,stalled,independent;
wire [1:0] valid,ready;
wire [127:0] data[0:1];
reg [1:0] last_stalled;
reg [127:0] last_data[0:1];
assign ready[0]=cycle>120 && cycle%5!=epoch;
assign ready[1]=cycle>180 && cycle%7!=epoch;
@@WIRING@@
initial begin
  for(epoch=0;epoch<5;epoch=epoch+1) begin
    reset=1;#5;clk=1;#5;clk=0;#1;
    if(valid!==0 || startup_done!==0) $fatal(1,"reset exposed output/completion");
    reset=0;main_count=0;peer_count=0;seen_done=0;stalled=0;independent=0;last_stalled=0;
    limit=epoch==0 ? 4 : epoch==1 ? 30 : epoch==2 ? 100 : 600;
    for(cycle=0;cycle<limit;cycle=cycle+1) begin
      #4;
      if(faults!==0) $fatal(1,"unexpected source/publication fault");
      if(startup_done) begin
        seen_done=seen_done+1;
        if(main_count<6) independent=independent+1;
      end
      for(i=0;i<2;i=i+1) begin
        if(last_stalled[i] && (!valid[i] || data[i]!==last_data[i])) $fatal(1,"changed stalled frame");
        if(valid[i] && ready[i]) begin
          k=i==0 ? main_count : peer_count;
          expected=i==0 ? (k<2 ? 0 : k==2 ? 2 : k==3 ? 5 : 8) : (k==0 ? 0 : k==1 ? 2 : k==2 ? 5 : 8);
          if(i==0 && k==5) begin
            if(data[i]!=={32'b0,32'd4,32'd8,8'd8,24'd2} || !startup_done) $fatal(1,"wrong final result");
          end else if(data[i]!=={64'b0,32'(expected),8'(i==0 ? 7 : 4),24'd1})
            $fatal(1,"wrong startup order/data source=%0d index=%0d frame=%h",i,k,data[i]);
          if((i==0 && k>=6) || (i==1 && k>=4)) $fatal(1,"duplicate startup output");
          if(i==0) main_count=k+1;else peer_count=k+1;
        end
        last_stalled[i]=valid[i] && !ready[i];last_data[i]=data[i];
        if(last_stalled[i]) stalled=stalled+1;
      end
      clk=1;#5;clk=0;#1;
    end
    if(epoch>=3 && (main_count!=6 || peer_count!=4 || valid!=0 || seen_done==0 || independent==0 || stalled<50))
      $fatal(1,"incomplete startup witness main=%0d peer=%0d done=%0d",main_count,peer_count,seen_done);
  end
  $display("PROTOCOL_STARTUP_PASS outputs=10 sum=8 acknowledgments=4");$finish;
end
endmodule
