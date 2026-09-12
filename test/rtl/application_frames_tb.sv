`timescale 1ns/1ps
module application_frames_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] beat_in = 0;
    reg beat_valid = 0;
    wire beat_ready;
    wire [127:0] frame_out;
    wire frame_valid;
    reg frame_ready = 0;
    integer cycles = 0, expected_count = 0, received = 0, issued = 0;
    reg allow_credit = 0;
    wire credit_valid = allow_credit && issued <= received;
    wire credit_ready;
    reg [127:0] expected [0:255];
    reg [127:0] held;
    reg stalled = 0;
    integer declared, actual, n;

    application_frames dut(.clk(clk), .reset(reset),
        ._beat_in(beat_in), ._beat_in_vld(beat_valid), ._beat_in_rdy(beat_ready),
        ._frame_out(frame_out), ._frame_out_vld(frame_valid), ._frame_out_rdy(frame_ready)
`ifdef RESERVED
        , ._admission_in(1'b1), ._admission_in_vld(credit_valid), ._admission_in_rdy(credit_ready)
`endif
    );

    always @(negedge clk) frame_ready = !reset && (cycles % 11 >= 5);
    always @(posedge clk) begin
        if (reset) begin
            cycles = 0; received = 0; issued = 0; stalled = 0;
        end else begin
            cycles = cycles + 1;
`ifdef RESERVED
            if (credit_valid && credit_ready) issued = issued + 1;
`endif
            if (stalled && (!frame_valid || frame_out !== held))
                $fatal(1, "assembled frame changed under backpressure");
            stalled = frame_valid && !frame_ready;
            held = frame_out;
            if (frame_valid && frame_ready) begin
                if (received >= expected_count || frame_out !== expected[received])
                    $fatal(1, "frame %0d: got %h, expected %h (count %0d)",
                        received, frame_out, expected[received], expected_count);
                received = received + 1;
            end
        end
    end

    task automatic beat(input [31:0] word, input last);
        begin
            @(negedge clk); beat_in = {last, word}; beat_valid = 1;
            do @(posedge clk); while (!beat_ready);
            // The next call can replace this beat at the next falling edge,
            // exercising consecutive accepted beats with no mandatory bubble.
            beat_valid <= 0;
        end
    endtask

    task automatic route(input [15:0] source, input [15:0] destination, input last);
        begin
`ifdef ROUTED
            beat({source, destination}, last);
`endif
        end
    endtask

    task automatic drained;
        begin
            while (received < expected_count) @(negedge clk);
            repeat (25) @(negedge clk);
        end
    endtask

    task automatic packet(input integer length, input integer count,
        input [15:0] destination);
        reg [95:0] payload;
        integer i;
        begin
            payload = 0;
            for (i = 0; i < count && i < 3; i = i + 1)
                payload[32*i+:32] = 32'hf1230000 + i;
            if (length == count && count <= 3 && destination != 99) begin
                expected[expected_count] = {length[7:0], 8'h9a, 8'hbc, 8'h07, payload};
                expected_count = expected_count + 1;
            end
            route(7, destination, 0);
            beat({8'h07, 8'hbc, 8'h9a, length[7:0]}, count == 0);
            for (i = 0; i < count; i = i + 1)
                beat(32'hf1230000 + i, i + 1 == count);
            drained();
        end
    endtask

    task automatic restart;
        begin
            @(negedge clk); reset = 1; beat_valid = 0; allow_credit = 0;
            expected_count = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    initial begin
        restart();
`ifdef RESERVED
        // No beat may be accepted before the first mailbox reservation.
        @(negedge clk); beat_valid = 1; beat_in = {1'b1, 32'h07000000};
        repeat (30) begin
            @(posedge clk);
            if (beat_ready || frame_valid) $fatal(1, "input accepted without admission");
        end
        @(negedge clk); beat_valid = 0;
`endif
        allow_credit = 1;
        for (declared = 0; declared <= 5; declared = declared + 1)
            for (actual = 0; actual <= 5; actual = actual + 1)
                packet(declared, actual, 1);
        // Long packets cannot wrap a rejected length back into a valid one.
        packet(1, 257, 1);
        packet(255, 255, 1);
        packet(3, 3, 1);
`ifdef ROUTED
        for (n = 0; n <= 5; n = n + 1) packet(n, 5-n, 99);
        packet(255, 260, 99);
        route(7, 99, 1); // route-only packet
        route(7, 1, 1);  // no application header to forward
`ifdef PAIR
        packet(2, 2, 2);
`else
        // Correct destination with the wrong source is also drained.
        route(8, 1, 0); beat(32'h07000001, 0); beat(99, 1);
`endif
        packet(1, 1, 1);
`endif
        // A missing TLAST does not make a later header-looking word a header.
        route(7, 1, 0);
        beat(32'h07000001, 0); beat(66, 0);
        for (n = 0; n < 300; n = n + 1) beat(32'h07000000, 0);
        beat(32'h07000000, 1); // only now is the rejected packet complete
        packet(1, 1, 1);
`ifdef ROUTED
        route(7, 99, 0);
        beat(32'h00070001, 0); // looks like a route to endpoint one
        beat(32'h07000000, 1);
        packet(1, 1, 1);
`endif
        // Reset aborts an unterminated packet and its admission session.
        route(7, 1, 0); beat(32'h07000001, 0); beat(66, 0);
        repeat (25) @(negedge clk);
        restart(); allow_credit = 1;
        packet(3, 3, 1);
        drained();
        $display("PASS: lengths, capacity, routes, long drains, reset, backpressure and admission");
        $finish;
    end
    initial begin #2000000; $fatal(1, "receive framing timeout (credit lost or frame missing)"); end
endmodule
