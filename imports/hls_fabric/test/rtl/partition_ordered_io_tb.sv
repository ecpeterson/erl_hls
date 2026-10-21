`timescale 1ns/1ps
// Exercise only the gateway's public ports: packet framing, attachment,
// command ordering, external arbitration and stable transfers under stalls.
module partition_ordered_io_tb;
    reg clk = 0, reset = 1;
    always #5 clk = !clk;
    reg [32:0] input_beat = 0;
    reg input_valid = 0;
    wire input_ready;
    wire [32:0] output_beat;
    wire output_valid;
    wire [193:0] control;
    wire control_valid;
    reg control_ready = 1;
    reg [127:0] event0 = 0, event1 = 0;
    reg valid0 = 0, valid1 = 0;
    wire ready0, ready1;
    integer cycle = 0, words = 0, acknowledgments = 0, faults = 0, events = 0, commands = 0;
    reg [31:0] packet [0:9];
    wire output_ready;
    assign output_ready = cycle % 7 >= 3;
    reg held = 0;
    reg [32:0] held_beat;
    wire [194:0] ordered;
    wire ordered_valid, ordered_ready, started, started_valid, started_ready, start_valid;
    reg running = 0;
    integer drain = 0, starts = 0, start_replies = 0;
    reg permit_start = 1;
    wire start_ready;
    assign start_ready = !reset && !running && drain == 0 && !control_valid && permit_start;
    hls_partition_activation bridge(.clk(clk),.reset(reset),
        .command(ordered),.command_valid(ordered_valid),.command_ready(ordered_ready),
        .ingress_data(control),.ingress_valid(control_valid),.ingress_ready(control_ready && drain==0),
        .start_valid(start_valid),.start_ready(start_ready),
        .started(started),.started_valid(started_valid),.started_ready(started_ready));
    partition_io dut(.clk(clk), .reset(reset),
        ._app_in(input_beat), ._app_in_vld(input_valid), ._app_in_rdy(input_ready),
        ._app_out(output_beat), ._app_out_vld(output_valid), ._app_out_rdy(output_ready),
        ._commands_out(ordered), ._commands_out_vld(ordered_valid), ._commands_out_rdy(ordered_ready),
        ._started_in(started), ._started_in_vld(started_valid), ._started_in_rdy(started_ready),
        ._events_in__0(event0), ._events_in__0_vld(valid0), ._events_in__0_rdy(ready0),
        ._events_in__1(event1), ._events_in__1_vld(valid1), ._events_in__1_rdy(ready1));

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (cycle > 200000) $fatal(1, "gateway timeout");
        if (reset) begin
            words = 0; acknowledgments = 0; faults = 0; events = 0; commands = 0; held = 0; running = 0; drain = 0; starts = 0; start_replies = 0;
        end else begin
            if (drain > 0) drain <= drain - 1;
            if (start_valid && start_ready) begin
                if (commands < 2 || drain != 0) $fatal(1,"start overtook setup");
                starts = starts + 1; running <= 1;
            end
            if (held && (!output_valid || output_beat !== held_beat)) $fatal(1, "unstable stalled output");
            held = output_valid && !output_ready;
            held_beat = output_beat;
            if (output_valid && output_ready) begin
                if (words > 9) $fatal(1, "oversized output");
                packet[words] = output_beat[31:0];
                words = words + 1;
                if (output_beat[32]) begin
                    if (packet[0] == 32'h00070001) begin
                        if (packet[1] == 32'h81000008) begin
                            if (words != 10 || packet[2] != 32'h12345678) $fatal(1, "identity mismatch");
                            for (integer i = 3; i < 10; i = i+1) if (packet[i] != 0) $fatal(1, "identity padding");
                            acknowledgments = acknowledgments + 1;
                        end else if (packet[1] == 32'h83000001 && words == 3 && packet[2] == 0) begin
                            if (starts != 1 || !running) $fatal(1,"premature start reply");
                            start_replies = start_replies + 1;
                        end else if (packet[1] == 32'hff000001 && words == 3 && packet[2] == 1) faults = faults + 1;
                        else $fatal(1, "bad management frame");
                    end else begin
                        if (acknowledgments != 1 || words != 3 || packet[1] != 32'h06000001) $fatal(1, "bad event envelope");
                        if (packet[0] == 32'h00080001 && packet[2] == 32'h11111111) events = events + 1;
                        else if (packet[0] == 32'h00090001 && packet[2] == 32'h22222222) events = events + 1;
                        else $fatal(1, "event route/payload mismatch");
                    end
                    words = 0;
                end
            end
            if (control_valid && control_ready && drain==0) begin
                if (control !== {16'd2,16'd3,16'd4,16'd5,2'd2,8'd1,8'd0,8'd0,8'd6,64'd0,32'habcdef01})
                    $fatal(1, "bad spatial command %h", control);
                commands = commands + 1; drain <= 50;
            end
        end
    end

    // Drive before the accepting edge and retain the entire beat until ready.
    task beat(input [31:0] word, input last);
        begin
            @(negedge clk); input_beat = {last, word}; input_valid = 1;
            @(posedge clk); while (!input_ready) @(posedge clk);
            @(negedge clk); input_valid = 0;
        end
    endtask
    // Reset the gateway and all public test sources together.
    task restart;
        begin
            @(negedge clk); reset = 1; input_valid = 0; valid0 = 0; valid1 = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask
    // Vary declared and actual lengths independently at the public boundary.
    task attach(input integer declared, input integer actual, input [31:0] identity);
        begin
            beat(32'h00010007, 0);
            beat(32'h01000000 | declared, actual == 0);
            for (integer i = 0; i < actual; i = i+1) beat(i == 0 ? identity : 0, i == actual-1);
        end
    endtask
    // Send a spatial command with visibly distinct coordinates and payload.
    task command;
        begin
            beat(32'h00010007, 0); beat(32'h02000005, 0);
            beat(32'h00030002, 0); beat(32'h00050004, 0); beat(32'd2, 0);
            beat(32'h06000001, 0); beat(32'habcdef01, 1);
        end
    endtask

    // Start is one explicit zero word, distinct from attachment and rectangle commands.
    task start_packet(input [31:0] value);
        begin beat(32'h00010007,0); beat(32'h03000001,0); beat(value,1); end
    endtask

    initial begin
        restart(); attach(8,8,32'h12345678); wait(acknowledgments==1);
        if (running || starts || start_replies) $fatal(1,"attachment activated network");
        permit_start=0; control_ready=0;
        fork
            begin command(); command(); start_packet(0); end
            begin
                repeat(100) @(negedge clk); control_ready=1;
                wait(commands==2); repeat(80) @(negedge clk);
                if (running || start_replies) $fatal(1,"start ignored network readiness");
                permit_start=1;
            end
        join
        wait(start_replies==1);
        // A start reply must not disable subsequent application output.
        event0={8'd1,8'd0,8'd0,8'd6,64'd0,32'h11111111}; valid0=1;
        @(posedge clk); while(!ready0) @(posedge clk); @(negedge clk); valid0=0;
        wait(events==1);
        start_packet(0); wait(faults==1);
        if(starts!=1 || start_replies!=1) $fatal(1,"duplicate start accepted");

        restart(); start_packet(0); wait(faults==1);
        if(starts) $fatal(1,"unattached start accepted");
        restart(); attach(8,8,32'h12345678); wait(acknowledgments==1);
        start_packet(1); wait(faults==1);
        if(starts) $fatal(1,"noncanonical start accepted");

        // Reset cancels an admitted start still waiting for the network.
        restart(); attach(8,8,32'h12345678); wait(acknowledgments==1);
        command(); command(); wait(commands==2); permit_start=0;
        fork : cancel_pending
            begin start_packet(0); end
            begin wait(start_valid); repeat(10) @(negedge clk); restart(); end
        join_any
        disable cancel_pending;
        restart(); permit_start=1;
        repeat(80) @(negedge clk);
        if(start_valid || started_valid || starts || start_replies || output_valid) $fatal(1,"reset replayed start");
        attach(8,8,32'h12345678); wait(acknowledgments==1);
        command(); command(); start_packet(0); wait(start_replies==1);
        if(faults) $fatal(1,"fresh activation faulted");
        $display("PASS: ordered setup/start, actual activation acknowledgment, stalls, duplicate rejection and reset");
        $finish;
    end
endmodule
