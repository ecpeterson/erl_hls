`timescale 1ns/1ps
module xls_control_failure_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [32:0] request = 0;
    reg request_valid = 0, reply_ready = 0;
    wire request_ready, reply_valid;
    wire [32:0] reply;
    reg [32:0] expected [0:16383];
    reg [32:0] expected_mask [0:16383];
    reg [31:0] last_fault;
    integer expected_count = 0, received = 0, cycles = 0, txid = 0, vectors = 0;
    reg [32:0] held;
    reg stalled = 0;
    reg [31:0] mode = 0, x = 0, y = 0;
    wire [35:0] outcome;

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
            if (received >= expected_count || (reply & expected_mask[received]) !== (expected[received] & expected_mask[received]))
                $fatal(1, "reply beat %0d: got %h, expected %h", received, reply, expected[received]);
            if (reply[32] && expected_mask[received] != 33'h1ffffffff) last_fault = reply[31:0];
            received = received + 1;
        end
    end else stalled = 0;

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
            expected_mask[expected_count] = 33'h1ffffffff;
            expected_mask[expected_count + 1] = 33'h1ffffffff;
            expected_count = expected_count + 2;
        end
    endtask

    task automatic expect_source_fault(input [3:0] code);
        begin
            expect_reply(1, 32'hc0000000 | code);
            expected_mask[expected_count - 1] = 33'h1ffff000f;
        end
    endtask

    task automatic restart;
        begin
            @(negedge clk); reset = 1; request_valid = 0;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask

    task automatic sticky_read;
        begin
            expect_reply(1, last_fault);
            beat({8'd4, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
            txid = txid + 1; drained();
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
        input [3:0] code, input [31:0] value);
        begin
            mode = m; x = left; y = right; #1;
            if (outcome !== {code, value})
                $fatal(1, "mode=%0d x=%0d y=%0d: outcome %h != %h", m, left, right, outcome, {code, value});
            if (code == 0) expect_reply(6, value); else expect_source_fault(code);
            beat({8'd3, 8'd0, txid[7:0], 8'd3}, 0);
            beat(m, 0); beat(left, 0); beat(right, 1);
            txid = txid + 1;
            drained();
            if (code == 0) read_state(value);
            else begin
                if (last_fault[15:4] == 0) $fatal(1, "body fault lost its source identity");
                // Later valid calls/casts cannot clear, replace or bypass the first fault.
                sticky_read();
                expect_reply(1, last_fault);
                beat({8'd5, 8'd0, txid[7:0], 8'd1}, 0); beat(123, 1);
                txid = txid + 1; drained();
                sticky_read();
                restart(); read_state(7);
            end
            vectors = vectors + 1;
        end
    endtask

    initial begin
        restart();
        read_state(7);
        `include "control_vectors.svh"
        beat({8'd5, 8'd0, txid[7:0], 8'd1}, 0); beat(99, 1);
        txid = txid + 1; read_state(99);
        // A malformed known operation and an unknown operation preserve live state.
        expect_reply(1, 3);
        beat({8'd3, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
        txid = txid + 1; drained(); read_state(99);
        expect_reply(1, 1);
        beat({8'd255, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
        txid = txid + 1; drained(); read_state(99);
        expect_source_fault(5);
        beat({8'd5, 8'd0, txid[7:0], 8'd1}, 0); beat(0, 1);
        txid = txid + 1; drained(); sticky_read();
        restart(); read_state(7);
        repeat (100) @(negedge clk);
        $display("PASS: %0d BEAM/expression/service vectors, terminal call/cast errors, sticky source identity, admission rejection, reset and stalled replies", vectors);
        $finish;
    end
    initial begin #2000000; $fatal(1, "control failure timeout"); end
endmodule
