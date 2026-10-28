`timescale 1ns/1ps
// Test public control/status boundaries with independent, stoppable user clocks.
// GTX analog behavior is deliberately not modeled by this regression.
module gtx_probe_tb;
    reg clock=0, tx_clock=0, rx_clock=0, tx_on=1, rx_on=1;
    always #20 clock = !clock;
    always #8 if (tx_on) tx_clock = !tx_clock;
    always #11 if (rx_on) rx_clock = !rx_clock;
    reg reset_n=0, run=0, pll_lock=0, tx_done=0, rx_done=0, rx_error=0;
    wire pll_reset, gt_reset, user_ready, measure, tx_fresh, rx_fresh, rx_enable;
    wire [31:0] status, rx_words, rx_errors, tx_words;
    wire sample_reset_n = reset_n && run;
`ifdef MAPPED
    gtx_probe_control_mapped controller(.*);
    gtx_probe_sample_mapped rx_sample(
`else
    gtx_probe_control #(.BOOT_CYCLES(8), .SETTLE_CYCLES(12),
        .TIMEOUT_CYCLES(200), .CLOCK_TIMEOUT(40)) controller(.*);
    gtx_probe_sample rx_sample(
`endif
        .clock(clock), .source_clock(rx_clock), .reset_n(sample_reset_n),
        .enable(measure), .error(rx_error), .source_enable(rx_enable),
        .words(rx_words), .errors(rx_errors), .fresh(rx_fresh));
`ifdef MAPPED
    gtx_probe_sample_mapped tx_sample(
`else
    gtx_probe_sample tx_sample(
`endif
        .clock(clock), .source_clock(tx_clock), .reset_n(sample_reset_n),
        .enable(1'b0), .error(1'b0), .words(tx_words), .fresh(tx_fresh));

    // Allow a bounded number of control-clock edges to reach a public state.
    task automatic await_state(input [2:0] expected, input integer limit);
        integer i;
        begin
            i=0;
            while (status[2:0] !== expected && i<limit) begin
                @(negedge clock); i=i+1;
            end
            if (status[2:0] !== expected)
                $fatal(1, "state timeout: expected %d, status %h", expected, status);
        end
    endtask

    // A new attempt clears snapshots even when the RX clock is absent.
    task automatic clear_attempt;
        begin
            @(negedge clock); run=0; pll_lock=0; tx_done=0; rx_done=0;
            repeat(5) @(negedge clock);
            if (!pll_reset || !gt_reset || user_ready || measure || status[15:12])
                $fatal(1, "hold did not clear attempt");
            if (rx_words || rx_errors || tx_words) $fatal(1, "stale snapshot after reset");
        end
    endtask

    // Model lock, clock startup, then reset-done in their required order.
    task automatic start_attempt;
        begin
            @(negedge clock); run=1;
            await_state(2, 15);
            if (pll_reset || !gt_reset || user_ready) $fatal(1, "PLL wait sequencing");
            pll_lock=1;
            await_state(4, 100);
            if (gt_reset || !user_ready || measure) $fatal(1, "reset-done wait sequencing");
            tx_done=1; rx_done=1;
            await_state(6, 30);
            if (!measure || status[6:4] !== 3'b111) $fatal(1, "missing ready status");
        end
    endtask

    // Faults stop measurement and persist even if the failed input recovers.
    task automatic check_fault(input [3:0] expected);
        begin
            await_state(7, 220);
            if (status[15:12] !== expected || measure || !gt_reset || user_ready)
                $fatal(1, "fault mismatch: %h", status);
            repeat(10) @(negedge clock);
            if (status[2:0] !== 7) $fatal(1, "fault automatically restarted");
        end
    endtask

    initial begin
        // Assert reset with an edge, including for mapped flip-flops with INITs.
        #1; reset_n=1; #1; reset_n=0;
        repeat(3) @(negedge clock);
        reset_n=1;
        repeat(7) begin
            @(negedge clock);
            if (pll_reset || gt_reset) $fatal(1, "reset asserted before boot delay");
        end
        await_state(1, 3);
        clear_attempt;
        run=1;
        check_fault(1); // Missing reference/PLL lock, no implicit retry.
        clear_attempt;
        pll_lock=1; repeat(4) @(negedge clock); run=1;
        repeat(20) @(negedge clock);
        if (!pll_reset || !gt_reset) $fatal(1, "stale high PLL lock bypassed reset");
        check_fault(1);
        clear_attempt;
        start_attempt;

        // Count exactly seven error cycles; reads are coherent delayed snapshots.
        wait(rx_enable); @(negedge rx_clock); rx_error=1;
        repeat(7) @(negedge rx_clock);
        rx_error=0;
        repeat(30) @(negedge clock);
        if (rx_errors !== 7 || rx_words <= 7 || tx_words == 0)
            $fatal(1, "PRBS snapshots words=%d errors=%d", rx_words, rx_errors);

        @(negedge rx_clock); rx_on=0;
        check_fault(8);
        clear_attempt; // Clock is still stopped during coordinated reset.
        rx_on=1;
        start_attempt;
        repeat(10) @(negedge clock);
        if (rx_errors !== 0) $fatal(1, "errors leaked across attempts");
        rx_done=0;
        check_fault(4);
        clear_attempt;
        start_attempt;
        pll_lock=0;
        check_fault(2);

        clear_attempt;
        @(negedge rx_clock); rx_on=0;
        run=1; await_state(2, 15); pll_lock=1;
        repeat(100) @(negedge clock);
        if (user_ready) $fatal(1, "accepted an absent RX user clock");
        check_fault(1);
        $display("PASS: GTX reset order, timeouts, stopped clocks, PRBS snapshots and restart");
        $finish;
    end
    initial begin #1000000; $fatal(1, "test timeout"); end
endmodule
