`timescale 1ns/1ps
module partition_reduction_tb;
  reg clk=0, reset=1;
  always #4 clk=~clk;
  integer cycle=0, left_sent=0, right_sent=0, openings=0, received=0;
  integer final_arrival=-1;
  wire left_ready, right_ready, open_ready, report_valid;
  wire [255:0] report;
  wire left_valid=!reset && left_sent<6;
  wire right_valid=!reset && right_sent<6 &&
    (right_sent<2 || (right_sent<4 && cycle>=70) || cycle>=110+10*(right_sent-4));
  wire open_valid=!reset && openings<3 && cycle>=30+30*openings;
  wire report_ready=cycle>=50 && (cycle<80 || cycle>=100);
  wire [31:0] lv=left_sent<2 ? left_sent+1 : left_sent<4 ? 10*(left_sent-1) : left_sent;
  wire [31:0] rv=right_sent<2 ? right_sent+3 : right_sent<4 ? 10*(right_sent+1) : right_sent;
  wire [127:0] left_data={32'd3, 32'd7+left_sent/32'd2, lv, -lv};
  wire [127:0] right_data={right_sent==4 ? 32'd0 : 32'd3, 32'd7+right_sent/32'd2, rv, -rv};
  reduction_probe dut(.clk(clk),.reset(reset),
    ._left(left_data),._left_vld(left_valid),._left_rdy(left_ready),
    ._right(right_data),._right_vld(right_valid),._right_rdy(right_ready),
    ._opened(1'b1),._opened_vld(open_valid),._opened_rdy(open_ready),
    ._report(report),._report_vld(report_valid),._report_rdy(report_ready));
  reg stalled=0;
  reg [255:0] held;
  initial begin repeat(5) @(negedge clk); reset=0; end
  always @(posedge clk) if (!reset) begin
    cycle<=cycle+1;
    if (left_valid && left_ready) left_sent<=left_sent+1;
    if (right_valid && right_ready) begin
      right_sent<=right_sent+1;
      if (right_sent==5) final_arrival<=cycle;
    end
    if (open_valid && open_ready) openings<=openings+1;
    if (stalled && (!report_valid || held!==report)) $fatal(1,"stalled aggregate changed");
    stalled<=report_valid && !report_ready;
    held<=report;
    if (report_valid) begin
      if (openings<=received) $fatal(1,"aggregate overtook its opening");
      if (right_sent<2*(received+1)) $fatal(1,"aggregate omitted a contributor");
    end
    if (report_valid && report_ready) begin
      if (report[255:224]!==0 || report[223:192]!==7+received) $fatal(1,"window order/slot changed");
      if (received<2) begin
        if (report[191:160]!==4 || report[159:128]!==0) $fatal(1,"healthy aggregate failed");
        if ($signed(report[127:64])!==(received==0 ? 64'sd10 : 64'sd100) ||
            $signed(report[63:0])!==(received==0 ? -64'sd10 : -64'sd100)) $fatal(1,"fold crossed windows");
      end else begin
        if (report[191:160]!==3 || report[159:128]===0 || final_arrival<0)
          $fatal(1,"malformed population did not drain before failure");
      end
      received<=received+1;
      if (received==2) begin
        $display("PASS: opening fence, aliased lookahead, delayed contributor, stalled output and full-population failure");
        $finish;
      end
    end
    if (cycle==500) $fatal(1,"reduction probe timed out");
  end
endmodule
