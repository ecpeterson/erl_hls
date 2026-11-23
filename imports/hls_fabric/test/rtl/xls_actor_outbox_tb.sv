`timescale 1ns/1ps
// Repeatedly run actor 1 while actor 0 is stalled, then exchange their roles.
module xls_actor_outbox_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [127:0] command0=0, command1=0;
    reg command0_valid=0, command1_valid=0, report0_ready=0, report1_ready=0;
    wire command0_ready, command1_ready, report0_valid, report1_valid;
    wire [127:0] report0, report1;
    wire [47:0] observation;
    wire observation_valid;
    reg [31:0] expected [0:23];
    integer seen0=0, seen1=0, round;
    reg blocked0=0, blocked1=0;
    `OUTBOX_TOP dut(.*);

    // Enqueue one update without assuming scheduler latency or relative clocks.
    task automatic add(input integer actor);
        begin
            @(negedge clk);
            if (actor==0) begin command0={32'h01000003,64'd0,32'd1}; command0_valid=1; end
            else begin command1={32'h01000003,64'd0,32'd1}; command1_valid=1; end
            @(posedge clk);
            while (!(actor==0 ? command0_ready : command1_ready)) @(posedge clk);
            @(negedge clk); if (actor==0) command0_valid=0; else command1_valid=0;
        end
    endtask

    // Reset both actors even with outstanding batches; RAM itself is not reset.
    task automatic restart;
        begin
            @(negedge clk); reset=1; command0_valid=0; command1_valid=0;
            report0_ready=0; report1_ready=0;
            repeat(5) @(negedge clk);
            seen0=0; seen1=0; blocked0=0; blocked1=0; reset=0;
        end
    endtask

    // Check every accepted effect against the BEAM counter and source order.
    always @(posedge clk) if (!reset) begin
        if (report0_valid && report0_ready) begin
            if (report0 !== {32'h02000004,32'd0,32'(seen0%3),expected[seen0/3]})
                $fatal(1,"actor 0 effect %0d mismatch: %h",seen0,report0);
            seen0=seen0+1;
        end
        if (report1_valid && report1_ready) begin
            if (report1 !== {32'h02000004,32'd0,32'(seen1%3),expected[seen1/3]})
                $fatal(1,"actor 1 effect %0d mismatch: %h",seen1,report1);
            seen1=seen1+1;
        end
        if (observation_valid) begin
            // Public mailbox words expose in-flight/egress state, not RAM data.
            if (observation[19]) blocked0=1;
            if (observation[43]) blocked1=1;
        end
    end

    initial begin
        $readmemh("expected.hex",expected);
        restart();
        // A's output remains unread while B completes 24 full callbacks.
        fork begin add(0); add(0); add(0); end join_none
        while (!report0_valid) @(negedge clk);
        report1_ready=1;
        for (round=1;round<=24;round=round+1) begin
            add(1);
            while (seen1<round*3) @(negedge clk);
        end
        if (seen0!=0) $fatal(1,"blocked output advanced");
`ifdef SHARED_OUTBOX
        if (!blocked0) $fatal(1,"public observation missed actor 0 outbox pressure");
`endif
        report0_ready=1;
        while (seen0<9) @(negedge clk);
        wait fork;
        repeat(100) @(negedge clk);
        if (seen0!=9 || seen1!=72) $fatal(1,"extra output");
        // Reverse identities, including reset with the previous actor RAM live.
        restart(); fork begin add(1); add(1); add(1); end join_none
        while (!report1_valid) @(negedge clk);
        report0_ready=1;
        for (round=1;round<=24;round=round+1) begin
            add(0);
            while (seen0<round*3) @(negedge clk);
        end
`ifdef SHARED_OUTBOX
        if (!blocked1) $fatal(1,"public observation missed actor 1 outbox pressure");
`endif
        report1_ready=1;
        while (seen1<9) @(negedge clk);
        wait fork;
        // Discard an in-progress batch by coordinated reset, then check fresh state.
        restart(); add(0);
        while (!report0_valid) @(negedge clk);
        restart(); report0_ready=1; report1_ready=1;
        add(0); add(1);
        while (seen0<3 || seen1<3) @(negedge clk);
        repeat(100) @(negedge clk);
        if (seen0!=3 || seen1!=3) $fatal(1,"stale output after reset");
        $display("PASS: independent actors progress through 24 three-effect batches in both directions; order and reset match BEAM");
        $finish;
    end
    initial begin #3000000; $fatal(1,"actor outbox progress timeout: %0d/%0d",seen0,seen1); end
endmodule
