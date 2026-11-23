`timescale 1ns/1ps

// Exercise the compiled example only through its declared command/report ports.
// All values come from independent arithmetic checked against actual BEAM actors.
module telemetry_example_tb;
    `include "telemetry_vectors.svh"
    reg clk = 0, reset = 1, release_sink = 0;
    reg [193:0] command = 0;
    reg command_valid = 0;
    wire command_ready, report_valid;
    wire [127:0] report;
    integer cycles = 0, received = 0, flow_cycle = 0;
    integer input_stalls = 0, output_stalls = 0;
    reg held_valid = 0;
    reg [127:0] held_report;
    wire report_ready = !reset && release_sink && flow_cycle % 7 != 0 && flow_cycle % 11 != 0;
    reg [193:0] commands [0:COMMAND_COUNT-1];
    reg [193:0] partial [0:PARTIAL_COUNT-1];
    reg [193:0] first [0:FIRST_COUNT-1];
    reg [193:0] invalid [0:INVALID_COUNT-1];
    reg [127:0] expected [0:REPORT_COUNT-1];
    string directory;
    integer index;

    telemetry_top dut(.clk(clk), .reset(reset),
        ._commands_in(command), ._commands_in_vld(command_valid), ._commands_in_rdy(command_ready),
        ._reports_out(report), ._reports_out_vld(report_valid), ._reports_out_rdy(report_ready));
    always #5 clk = ~clk;

    // Sink scheduling changes between handshake edges, never during their sampling.
    always @(negedge clk) flow_cycle = flow_cycle + 1;

    // Compare every accepted frame, and require stable output throughout each stall.
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (cycles > 50000) $fatal(1, "telemetry progress timeout: %0d reports", received);
        if (reset) begin
            received = 0;
            held_valid = 0;
        end else begin
            if ((^{command_ready, report_valid, report_ready}) === 1'bx)
                $fatal(1, "unknown public handshake");
            if (held_valid && (!report_valid || report !== held_report))
                $fatal(1, "report changed while stalled");
            held_valid = report_valid && !report_ready;
            held_report = report;
            if (command_valid && !command_ready) input_stalls = input_stalls + 1;
            if (held_valid) output_stalls = output_stalls + 1;
            if (report_valid && report_ready) begin
                if (received >= REPORT_COUNT) $fatal(1, "unexpected extra report: %h", report);
                if (report !== expected[received])
                    $fatal(1, "report %0d differs from BEAM: expected %h got %h", received, expected[received], report);
                received = received + 1;
            end
        end
    end

    // Inputs retain their complete packet until the one public admission handshake.
    task automatic send(input [193:0] packet);
        begin
            @(negedge clk); command = packet; command_valid = 1;
            do @(posedge clk); while (!command_ready);
            @(negedge clk); command_valid = 0;
        end
    endtask

    // Coordinated reset discards partial windows and unconsumed reports together.
    task automatic restart;
        begin
            @(negedge clk); reset = 1; release_sink = 0; command_valid = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    // A complete transcript runs while a bounded, independently stalled sink drains it.
    task automatic complete_run;
        integer item;
        integer stalled_before;
        begin
            restart();
            stalled_before = output_stalls;
            fork
                begin
                    for (item = 0; item < INVALID_COUNT; item = item + 1) send(invalid[item]);
                    for (item = 0; item < COMMAND_COUNT; item = item + 1) send(commands[item]);
                end
                begin
                    wait (report_valid);
                    repeat (100) @(negedge clk);
                    release_sink = 1;
                end
            join
            wait (received == REPORT_COUNT);
            repeat (150) @(negedge clk);
            if (output_stalls - stalled_before < 100) $fatal(1, "missing long report stall");
        end
    endtask

    initial begin
        if (!$value$plusargs("vectors=%s", directory)) $fatal(1, "missing vector directory");
        $readmemh($sformatf("%s/commands.mem", directory), commands);
        $readmemh($sformatf("%s/partial.mem", directory), partial);
        $readmemh($sformatf("%s/first.mem", directory), first);
        $readmemh($sformatf("%s/invalid.mem", directory), invalid);
        $readmemh($sformatf("%s/expected.mem", directory), expected);
        restart();
        for (index = 0; index < PARTIAL_COUNT; index = index + 1) send(partial[index]);
        repeat (100) begin
            @(negedge clk);
            if (report_valid) $fatal(1, "partial window emitted a report");
        end
        restart();
        for (index = 0; index < FIRST_COUNT; index = index + 1) send(first[index]);
        wait (report_valid);
        if (report !== expected[0]) $fatal(1, "first held summary differs from BEAM: expected %h got %h", expected[0], report);
        repeat (50) @(negedge clk);
        complete_run();
        complete_run();
        if (input_stalls == 0) $fatal(1, "missing input backpressure coverage");
        $display("PASS: telemetry CPU/RTL windows, malformed ingress, stalls and reset (%0d reports per incarnation, %0d cycles)", REPORT_COUNT, cycles);
        $finish;
    end
endmodule
