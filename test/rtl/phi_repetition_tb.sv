`timescale 1ns/1ps
// Complete physical-noise workload, recording only accepted public frames.
module phi_repetition_tb;
  parameter N=3, STALLED=0;
  reg clk=0, resetn=0, ready=1;
  wire [127:0] frame;
  wire valid;
  integer cycles=0, step, x, value, kind, statuses=0, warmup=0, elapsed, fd, i;
  reg [N-1:0] seen[0:32];
  reg blocked=0;
  reg [127:0] prior;
  phi_repetition_top dut(.aclk(clk),.aresetn(resetn),.decoder_event(frame),
    .decoder_event_valid(valid),.decoder_event_ready(ready),
    .control(194'b0),.control_valid(1'b0),.control_ready(),
    .measurement(),.measurement_valid(),.measurement_ready(1'b1));
  always #5 clk=~clk;
  always @(negedge clk) ready=!STALLED || cycles%17>=7;
  always @(posedge clk) if(resetn) begin
    cycles=cycles+1;
    if(blocked && (!valid || frame!==prior)) $fatal(1,"blocked output changed");
    blocked=valid && !ready; prior=frame;
    if(valid && ready) begin
      if((^frame)===1'bx) $fatal(1,"unknown frame");
      step=frame[31:0]; x=frame[47:32]; value=frame[95:64]; kind=frame[103:96];
      if(x>=N || frame[63:48]!=0) $fatal(1,"invalid line coordinate");
      if(frame[127:96]!=32'h0300000b && frame[127:96]!=32'h03000011) $fatal(1,"unexpected public event");
      if(kind==17 && value>3) $fatal(1,"invalid status flags");
      if(kind==11 && value!=2 && value!=4) $fatal(1,"orthogonal correction");
      if(step<=32) begin
        $fdisplay(fd,"%0d %0d %0d %0d",x,step,kind,value);
        if(kind==17) begin
          if(seen[step][x]) $fatal(1,"duplicate status");
          seen[step][x]=1; statuses=statuses+1;
          if(step==8 && (&seen[8])) warmup=cycles;
          if(statuses==33*N) begin
            elapsed=cycles-warmup;
            $display("PASS N=%0d cycles_per_step=%0f stalled=%0d",N,elapsed/24.0,STALLED);
            $fclose(fd); $finish;
          end
        end
      end
    end
    if(cycles>300000) $fatal(1,"repetition workload timed out after %0d statuses",statuses);
  end
  initial begin
    for(i=0;i<=32;i=i+1) seen[i]=0;
    fd=$fopen("events.txt","w");
    if(fd==0) $fatal(1,"cannot open events file");
    repeat(8) @(negedge clk); resetn=1;
  end
endmodule
