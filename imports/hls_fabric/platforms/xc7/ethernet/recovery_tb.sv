`timescale 1ns/1ps
// Model physical status, never internal DUT state. Pause clocks without removing
// lock/reset-done to exercise the independent watchdog; frame checks use only
// public streams. The ideal serializer is the same one as the gearbox tests.
module recovery_tb;
    parameter STARTUP_TIMEOUT=25000;
    reg control_clk=0, clock_a=0, clock_b=0, reset=1, run=0;
    reg stop_a=0, stop_b=0, tx_half_enable=1, rx_half_enable=1;
    reg lose_lock=0, lose_done=0, stale_lock=0;
    always #20 control_clk=!control_clk;
    always #4 if (!stop_a) clock_a=!clock_a;
    initial begin #1.25; forever #4.0004 if (!stop_b) clock_b=!clock_b; end
    wire [9:0] wire_a, wire_b;
    wire pll_reset_a, gt_reset_a, user_ready_a, pll_reset_b, gt_reset_b, user_ready_b;
    wire tx_reset_a, rx_reset_a, tx_reset_b, rx_reset_b;
    wire [31:0] status_a, status_b;
    wire up_a, up_b, rx_up_a, rx_up_b;
    reg tx_valid=0, tx_last=0, reverse_valid=0, reverse_last=0;
    reg [7:0] tx_data=0, reverse_data=0;
    wire tx_ready, reverse_ready, rx_valid, rx_last, reverse_rx_valid, reverse_rx_last;
    wire [7:0] rx_data, reverse_rx_data;
    reg consume=1;
    wire [1:0] rx_queued_a, rx_queued_b;
    wire [31:0] accepted_a, accepted_b;
    gearbox_packet_fixture a (
        .control_clk(control_clk), .run(run),
        .pll_lock(stale_lock || (!pll_reset_a && !lose_lock)),
        .tx_done(user_ready_a && !gt_reset_a && !lose_done),
        .rx_done(user_ready_a && !gt_reset_a),
        .tx_half_enable(tx_half_enable), .rx_half_enable(rx_half_enable),
        .pll_reset(pll_reset_a), .gt_reset(gt_reset_a), .user_ready(user_ready_a),
        .tx_reset_n(tx_reset_a), .rx_reset_n(rx_reset_a), .status(status_a),
        .eth_tx_clk(clock_a), .eth_rx_clk(clock_b), .eth_tx_rst(reset), .eth_rx_rst(reset),
        .tbi_rx(wire_b), .tbi_tx(wire_a), .link_tx(up_a), .link_rx(rx_up_a),
        .tx_valid(tx_valid), .tx_data(tx_data), .tx_last(tx_last), .tx_ready(tx_ready),
        .rx_ready(consume), .rx_valid(reverse_rx_valid), .rx_data(reverse_rx_data), .rx_last(reverse_rx_last),
        .rx_queued(rx_queued_a), .rx_accepted(accepted_a)
    );
    gearbox_packet_fixture b (
        .control_clk(control_clk), .run(run), .pll_lock(!pll_reset_b),
        .tx_done(user_ready_b && !gt_reset_b), .rx_done(user_ready_b && !gt_reset_b),
        .tx_half_enable(1'b1), .rx_half_enable(1'b1),
        .pll_reset(pll_reset_b), .gt_reset(gt_reset_b), .user_ready(user_ready_b),
        .tx_reset_n(tx_reset_b), .rx_reset_n(rx_reset_b), .status(status_b),
        .eth_tx_clk(clock_b), .eth_rx_clk(clock_a), .eth_tx_rst(reset), .eth_rx_rst(reset),
        .tbi_rx(wire_a), .tbi_tx(wire_b), .link_tx(up_b), .link_rx(rx_up_b),
        .tx_valid(reverse_valid), .tx_data(reverse_data), .tx_last(reverse_last), .tx_ready(reverse_ready),
        .rx_ready(consume), .rx_valid(rx_valid), .rx_data(rx_data), .rx_last(rx_last),
        .rx_queued(rx_queued_b), .rx_accepted(accepted_b)
    );

    integer tag=1, offset_a=0, offset_b=0, received_a=0, received_b=0;
    reg expect_a=0, expect_b=0;
    always @(posedge clock_b) if (rx_reset_a && reverse_rx_valid && consume) begin
        if (!expect_a || reverse_rx_data !== ((offset_a*17+tag+80)&255) ||
            reverse_rx_last !== (offset_a==96)) $fatal(1,"A stale/corrupt frame at %d",offset_a);
        if (reverse_rx_last) begin received_a=received_a+1; offset_a=0; expect_a=0; end
        else offset_a=offset_a+1;
    end
    always @(posedge clock_a) if (rx_reset_b && rx_valid && consume) begin
        if (!expect_b || rx_data !== ((offset_b*17+tag)&255) ||
            rx_last !== (offset_b==96)) $fatal(1,"B stale/corrupt frame at %d",offset_b);
        if (rx_last) begin received_b=received_b+1; offset_b=0; expect_b=0; end
        else offset_b=offset_b+1;
    end
    // Stream reset withdraws validity even if the owning clock no longer moves.
    always @(negedge control_clk) if (!reset) begin
        if ((!tx_reset_a && tx_ready) || (!rx_reset_a && reverse_rx_valid) ||
            (!tx_reset_b && reverse_ready) || (!rx_reset_b && rx_valid))
            $fatal(1,"handshake survived stream reset");
    end

    // Commit a full frame, or deliberately leave a producer prefix unfinished.
    task send_a(input integer count, complete);
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                @(negedge clock_a); tx_valid=1; tx_data=i*17+tag; tx_last=complete && i==count-1;
                @(posedge clock_a); while(!tx_ready) @(posedge clock_a);
            end
            @(negedge clock_a); tx_valid=0; tx_last=0;
        end
    endtask
    // Reverse-direction frame exercises the independent recovered clock domain.
    task send_b(input integer count);
        integer i;
        begin
            for(i=0;i<count;i=i+1) begin
                @(negedge clock_b); reverse_valid=1; reverse_data=i*17+tag+80; reverse_last=i==count-1;
                @(posedge clock_b); while(!reverse_ready) @(posedge clock_b);
            end
            @(negedge clock_b); reverse_valid=0; reverse_last=0;
        end
    endtask
    // The caller must clear stale producer/consumer state across hard recovery.
    task start;
        begin
            @(negedge control_clk); run=0;
            repeat(12) @(negedge control_clk);
            run=1;
            wait(up_a && up_b && rx_up_a && rx_up_b);
            repeat(20) @(negedge control_clk);
            if (accepted_a!=0 || accepted_b!=0 || rx_queued_a!=0 || rx_queued_b!=0)
                $fatal(1,"old frames/counters survived restart");
            consume=1; tag=tag+1;
        end
    endtask
    // Check bidirectional delivery before/after every independent injected fault.
    task traffic;
        begin
            expect_a=1; expect_b=1;
            fork send_a(97,1); send_b(97); join
            wait(!expect_a && !expect_b);
            repeat(100) @(negedge clock_a);
        end
    endtask
    // Hold a committed RX frame and interrupt the opposite TX producer prefix.
    task queued_traffic;
        begin
            consume=0;
            send_b(97); wait(rx_queued_a==1);
            send_a(31,0);
        end
    endtask
    // The declared watchdog bound includes one in-flight handshake, synchronizer
    // latency, and the controller's fault edge. No dependence on stopped clocks.
    task fault(input integer reason);
        integer edges;
        begin
            edges=0;
            while(status_a[2:0]!=7 && edges<1040) begin @(negedge control_clk); edges=edges+1; end
            if (status_a[2:0]!=7 || status_a[15:12]!=reason || tx_reset_a || rx_reset_a)
                $fatal(1,"fault missing/wrong: %h after %d cycles",status_a,edges);
            if (tx_ready || reverse_rx_valid || up_a || rx_up_a || !gt_reset_a)
                $fatal(1,"fault left packet service active");
            $display("fault %0d latched in %0d control cycles",reason,edges);
        end
    endtask
    // Recovery of physical levels alone must not silently start a new session.
    task remains_faulted;
        begin
            repeat(80) @(negedge control_clk);
            if (status_a[2:0]!=7 || tx_reset_a || rx_reset_a) $fatal(1,"automatic restart");
        end
    endtask

    integer kind;
    initial begin
        repeat(10) @(negedge control_clk); reset=0;
        start(); traffic();
        for(kind=0;kind<6;kind=kind+1) begin
            queued_traffic();
            case(kind)
                0: begin @(negedge clock_a); stop_a=1; end
                1: begin @(posedge clock_b); #1; stop_b=1; end
                2: tx_half_enable=0;
                3: rx_half_enable=0;
                4: lose_lock=1;
                5: lose_done=1;
            endcase
            fault(kind==4 ? 2 : kind==5 ? 4 : 8);
            // Restored physical levels do not authorize a new session.
            stop_a=0; stop_b=0; tx_half_enable=1; rx_half_enable=1; lose_lock=0; lose_done=0;
            remains_faulted();
            start(); traffic();
        end
        // Stop in the middle of an actual on-wire packet, rather than only
        // interrupting host assembly or holding a completed receive frame.
        consume=0; send_a(1514,1); repeat(100) @(negedge clock_a);
        stop_a=1; fault(8); stop_a=0; remains_faulted(); start(); traffic();
        // An old high lock cannot satisfy startup. Verify bounded timeout and
        // repeat recovery without reconfiguring or globally resetting the DUT.
        @(negedge control_clk); run=0; stale_lock=1;
        repeat(12) @(negedge control_clk); run=1;
        repeat(STARTUP_TIMEOUT+20) @(negedge control_clk);
        if(status_a[2:0]!=7 || status_a[15:12]!=1) $fatal(1,"stale startup lock accepted");
        stale_lock=0; start(); traffic();
        // Assert global reset while a source is frozen; no source edge is
        // needed to withdraw externally visible handshakes.
        queued_traffic(); @(posedge clock_b); #1; stop_b=1; reset=1;
        repeat(10) @(negedge control_clk);
        if(tx_ready || reverse_rx_valid || tx_reset_a || rx_reset_a) $fatal(1,"stopped reset");
        run=0; stop_b=0; reset=0; start(); traffic();
        $display("PASS: clock/lock/reset-done faults, stale lock, explicit restart, stopped-clock reset; %0d/%0d checked frames",received_a,received_b);
        $finish;
    end
    initial begin #15000000; $fatal(1,"recovery timeout status=%h/%h",status_a,status_b); end
endmodule
