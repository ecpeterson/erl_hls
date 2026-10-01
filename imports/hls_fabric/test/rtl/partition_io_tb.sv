`timescale 1ns/1ps
// Exercise only the gateway's public ports: packet framing, attachment,
// command ordering, external arbitration and stable transfers under stalls.
module partition_io_tb;
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
    wire output_ready = cycle % 7 >= 3;
    reg held = 0;
    reg [32:0] held_beat;
    partition_io dut(.clk(clk), .reset(reset),
`ifdef PARTITION_TILE
        ._tile_gateway(272'h123456780001), ._tile_gateway_vld(1'b1), ._tile_gateway_rdy(),
        ._tile_host(16'd1), ._tile_host_vld(1'b1), ._tile_host_rdy(),
`endif
        ._app_in(input_beat), ._app_in_vld(input_valid), ._app_in_rdy(input_ready),
        ._app_out(output_beat), ._app_out_vld(output_valid), ._app_out_rdy(output_ready),
        ._control_out(control), ._control_out_vld(control_valid), ._control_out_rdy(control_ready),
        ._events_in__0(event0), ._events_in__0_vld(valid0), ._events_in__0_rdy(ready0),
        ._events_in__1(event1), ._events_in__1_vld(valid1), ._events_in__1_rdy(ready1));

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (cycle > 200000) $fatal(1, "gateway timeout");
        if (reset) begin
            words = 0; acknowledgments = 0; faults = 0; events = 0; commands = 0; held = 0;
        end else begin
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
            if (control_valid && control_ready) begin
                if (control !== {16'd2,16'd3,16'd4,16'd5,2'd2,8'd1,8'd0,8'd0,8'd6,64'd0,32'habcdef01})
                    $fatal(1, "bad spatial command %h", control);
                commands = commands + 1;
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

    // Corrupt one command field at a time after a valid attachment.
    task invalid_command(input integer kind);
        begin
            beat(kind == 0 ? 32'h00010006 : 32'h00010007, 0);
            beat(kind == 1 ? 32'h02010005 : kind == 2 ? 32'h02000105 :
                 kind == 3 ? 32'h03000005 : 32'h02000005, 0);
            beat(kind == 4 ? 32'h00030009 : 32'h00030002, 0);
            beat(32'h00050004, 0);
            beat(kind == 5 ? 32'd4 : 32'd2, 0);
            beat(kind == 6 ? 32'h06010001 : kind == 7 ? 32'h06000101 :
                 kind == 8 ? 32'h06000002 : 32'h06000001, 0);
            beat(32'habcdef01, 1);
        end
    endtask

    initial begin
        restart();
        // Events offered before attachment must remain pending until its acknowledgment.
        event0 = {8'd1,8'd0,8'd0,8'd6,64'd0,32'h11111111};
        event1 = {8'd1,8'd0,8'd0,8'd6,64'd0,32'h22222222};
        valid0 = 1; valid1 = 1;
        repeat (20) @(negedge clk);
        if (ready0 || ready1 || output_valid) $fatal(1, "events escaped before attachment");
        fork
            attach(8, 8, 32'h12345678);
            begin @(posedge clk); while (!ready0) @(posedge clk); @(negedge clk); valid0 = 0; end
            begin @(posedge clk); while (!ready1) @(posedge clk); @(negedge clk); valid1 = 0; end
        join
        wait(events == 2);
        control_ready = 0;
        fork
            begin command(); command(); end
            begin repeat (100) @(negedge clk); control_ready = 1; end
        join
        wait(commands == 2);
        attach(8, 8, 32'h12345678);
        wait(faults == 1);
        command(); repeat (30) @(negedge clk);
        if (commands != 2 || acknowledgments != 1) $fatal(1, "poisoned connection resumed");

        // Exhaust framing around both supported payload lengths. Every rejected
        // attach emits one fault and cannot be repaired by a second attach.
        for (integer declared = 0; declared <= 9; declared = declared+1) begin
            for (integer actual = 0; actual <= 9; actual = actual+1) begin
                restart(); attach(declared, actual, 32'h12345678);
                if (declared == 8 && actual == 8) wait(acknowledgments == 1);
                else begin
                    wait(faults == 1);
                    attach(8, 8, 32'h12345678);
                    repeat (20) @(negedge clk);
                    if (acknowledgments != 0 || faults != 1) $fatal(1, "bad frame activated gateway");
                end
            end
        end
        for (integer kind = 0; kind < 9; kind = kind+1) begin
            restart(); attach(8, 8, 32'h12345678); wait(acknowledgments == 1);
            invalid_command(kind); wait(faults == 1);
            if (commands != 0) $fatal(1, "invalid command escaped %0d", kind);
        end
        // A coordinated reset clears a partial packet; its tail is not replayed.
        restart(); attach(8, 8, 32'h12345678); wait(acknowledgments == 1);
        beat(32'h00010007, 0); beat(32'h02000005, 0); beat(32'h00030002, 0);
        restart(); attach(8, 8, 32'h12345678); wait(acknowledgments == 1);
        command(); wait(commands == 1);
        restart(); attach(8, 300, 32'h12345678); wait(faults == 1);
        restart(); attach(8, 8, 32'h87654321); wait(faults == 1);
        restart(); command(); wait(faults == 1);
        if (commands != 0) $fatal(1, "command admitted before attachment");
        $display("PASS: routed gateway framing, identity, ordered controls, arbitration and stalls");
        $finish;
    end
endmodule
