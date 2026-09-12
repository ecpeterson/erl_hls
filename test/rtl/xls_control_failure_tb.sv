`timescale 1ns/1ps
module xls_control_failure_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:4095];
    integer expected_count = 0, received = 0, cycles = 0, txid = 0, vectors = 0;
    reg [32:0] held;
    reg stalled = 0;
    reg [31:0] mode = 0, x = 0, y = 0;
    wire [34:0] outcome;

    control_service dut(.clk(clk), .reset(reset),
        ._ext_recv(request), ._ext_recv_vld(request_valid), ._ext_recv_rdy(request_ready),
        ._ext_send(reply), ._ext_send_vld(reply_valid), ._ext_send_rdy(reply_ready));
    control_probe expression(.mode(mode), .x(x), .y(y), .out(outcome));

    always @(negedge clk) reply_ready = !reset && cycles % 13 >= 7;
    always @(posedge clk) if (!reset) begin
        cycles = cycles + 1;
        if (stalled && (!reply_valid || reply !== held))
            $fatal(1, "reply changed under backpressure");
        held = reply;
        stalled = reply_valid && !reply_ready;
        if (reply_valid && reply_ready) begin
            if (received >= expected_count || reply !== expected[received])
                $fatal(1, "reply beat %0d: got %h, expected %h", received, reply, expected[received]);
            received = received + 1;
        end
    end

    task automatic beat(input [31:0] word, input last);
        begin
            @(negedge clk); request = {last, word}; request_valid = 1;
            do @(posedge clk); while (!request_ready);
            request_valid <= 0;
        end
    endtask

    task automatic expect_reply(input [7:0] tag, input [31:0] value);
        begin
            expected[expected_count] = {1'b0, tag, 8'd0, txid[7:0], 8'd1};
            expected[expected_count + 1] = {1'b1, value};
            expected_count = expected_count + 2;
        end
    endtask

    task automatic drained;
        begin
            while (received < expected_count) @(negedge clk);
            repeat (4) @(negedge clk);
        end
    endtask

    task automatic read_state(input [31:0] value);
        begin
            expect_reply(6, value);
            beat({8'd4, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
            txid = txid + 1;
            drained();
        end
    endtask

    task automatic probe(input [31:0] m, input [31:0] left, input [31:0] right,
        input [2:0] code, input [31:0] value);
        begin
            mode = m; x = left; y = right; #1;
            if (outcome !== {code, value})
                $fatal(1, "mode=%0d x=%0d y=%0d: outcome %h != %h", m, left, right, outcome, {code, value});
            expect_reply(code == 0 ? 6 : 1, code == 0 ? value : {29'd0, code});
            beat({8'd3, 8'd0, txid[7:0], 8'd3}, 0);
            beat(m, 0); beat(left, 0); beat(right, 1);
            txid = txid + 1;
            drained();
            // Existing callback-failure policy clears GS state; successful
            // callbacks commit their returned value. No implicit fallthrough.
            read_state(value);
            vectors = vectors + 1;
        end
    endtask

    initial begin
        repeat (5) @(negedge clk); reset = 0;
        read_state(7);
        `include "control_vectors.svh"
        beat({8'd5, 8'd0, txid[7:0], 8'd1}, 0); beat(99, 1);
        txid = txid + 1; read_state(99);
        expect_reply(1, 5);
        beat({8'd5, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
        txid = txid + 1; drained(); read_state(0);
        repeat (100) @(negedge clk);
        $display("PASS: %0d BEAM/expression/service vectors, typed call/cast errors and stalled replies", vectors);
        $finish;
    end
    initial begin #2000000; $fatal(1, "control failure timeout"); end
endmodule
