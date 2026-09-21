`timescale 1ns/1ps
// Exercise the actual vendor GTX model: clocks, PRBS loopback and error injection.
// This is digital primitive simulation, not an analog/channel qualification.
module gtx_tb;
    reg clock=0, ref_p=0;
    always #20 clock=~clock;
    always #4 ref_p=~ref_p;
    reg pll_reset=1, gt_reset=1, user_ready=0, measure=0, force_error=0;
    wire pll_lock, tx_done, rx_done, rx_error, tx_out, rx_out, tx_clock, rx_clock;
    wire tx_p, tx_n;
    BUFG tx_buffer(.I(tx_out),.O(tx_clock));
    BUFG rx_buffer(.I(rx_out),.O(rx_clock));
    te0715_gtx_channel #(.PRBS(1),.EXTERNAL(0)) dut(
        .clock(clock),.ref_p(ref_p),.ref_n(!ref_p),.gt_rx_p(tx_p),.gt_rx_n(tx_n),
        .gt_tx_p(tx_p),.gt_tx_n(tx_n),.pll_reset(pll_reset),.gt_reset(gt_reset),
        .user_ready(user_ready),.force_error(force_error),.measure(measure),.align(1'b0),
        .tx_clock(tx_clock),.rx_clock(rx_clock),.tx_data(16'b0),.tx_dispval(2'b0),.tx_dispmode(2'b0),
        .pll_lock(pll_lock),.tx_done(tx_done),.rx_done(rx_done),.rx_error(rx_error),
        .tx_out_clock(tx_out),.rx_out_clock(rx_out));
    integer errors=0;
    always @(posedge rx_clock) if(measure && rx_error) errors<=errors+1;
    realtime previous, elapsed;
    initial begin
        #4000; pll_reset=0;
        wait(pll_lock===1'b1);
        repeat(50) @(negedge clock);
        gt_reset=0;
        repeat(50) @(negedge clock);
        user_ready=1;
        wait(tx_done===1'b1 && rx_done===1'b1);
        repeat(3000) @(negedge rx_clock);
        previous=$realtime;
        // The recovered-clock model can move an individual edge as its CDR
        // tracks PRBS. Measure frequency over a window, then check data errors.
        repeat(256) @(negedge rx_clock);
        elapsed=$realtime-previous;
        $display("RX recovered-clock mean period: %0.6f ns",elapsed/256.0);
        if(elapsed/256.0<15.99 || elapsed/256.0>16.01)
            $fatal(1,"RX clock mean period: %0.6f ns",elapsed/256.0);
        measure=1;
        repeat(256) @(negedge rx_clock);
        if(errors!=0) $fatal(1,"clean PRBS reported %0d errors",errors);
        @(negedge tx_clock); force_error=1;
        @(negedge tx_clock); force_error=0;
        repeat(256) @(negedge rx_clock);
        if(errors==0) $fatal(1,"forced PRBS error was not observed");
        $display("PASS: vendor GTX lock, reset, 62.5-MHz RX, clean PRBS and injected error");
        $finish;
    end
    initial begin #2000000; $fatal(1,"GTX timeout lock=%b tx_done=%b rx_done=%b errors=%d",pll_lock,tx_done,rx_done,errors); end
endmodule
