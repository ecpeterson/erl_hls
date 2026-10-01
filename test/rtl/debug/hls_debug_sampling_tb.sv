`timescale 1ns/1ps
// Public-port regression: offer the next query while holding the current
// reply. Diagnose missed observations from GET_COUNTERS, and verify frozen
// trace contents while the other bank overflows. No private DUT signals.
module hls_debug_sampling_tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [31:0] request_data = 0;
    reg [3:0] request_keep = 15;
    reg request_valid = 0, request_last = 1, response_ready = 0;
    reg hold_tail = 0;
    wire request_ready, response_valid, response_last;
    wire accept_response = response_ready && !(hold_tail && response_last);
    wire [31:0] response_data;
    wire [3:0] response_keep;
    integer cycles = 0, written = 0, consumed = 0, requests = 0;
    reg [36:0] replies [0:8191];
    reg stalled = 0;
    reg [36:0] held;

    hls_debug_monitor dut (
        .aclk(clk), .aresetn(!reset),
        .app_rx_tdata(32'h07001100), .app_rx_tvalid(1'b1),
        .app_rx_tready(1'b1), .app_rx_tlast(1'b1),
        .app_tx_tdata(32'h09002200), .app_tx_tvalid(1'b1),
        .app_tx_tready(1'b1), .app_tx_tlast(1'b1),
        .s_dbg_tdata(request_data), .s_dbg_tkeep(request_keep),
        .s_dbg_tvalid(request_valid), .s_dbg_tlast(request_last),
        .s_dbg_tready(request_ready),
        .m_dbg_tdata(response_data), .m_dbg_tkeep(response_keep),
        .m_dbg_tvalid(response_valid), .m_dbg_tlast(response_last),
        .m_dbg_tready(accept_response)
    );

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (cycles > 30000) $fatal(1, "sampling test timeout");
        if (reset) stalled <= 0;
        else begin
            if (stalled && (!response_valid || {response_keep, response_last, response_data} !== held))
                $fatal(1, "reply changed while stalled");
            stalled <= response_valid && !accept_response;
            held <= {response_keep, response_last, response_data};
            if (request_valid && request_ready) requests = requests + 1;
            if (response_valid && accept_response) begin
                if (written == 8192) $fatal(1, "reply storage exhausted");
                replies[written] = {response_keep, response_last, response_data};
                written = written + 1;
            end
        end
    end

    task automatic send(input [31:0] word, input last, input [3:0] keep);
        begin
            @(negedge clk);
            request_data = word; request_last = last; request_keep = keep; request_valid = 1;
            @(posedge clk);
            while (!request_ready) @(posedge clk);
            @(negedge clk); request_valid = 0;
        end
    endtask

    task automatic take(output [31:0] word, input last);
        begin
            @(negedge clk);
            while (consumed == written) @(negedge clk);
            if (replies[consumed][36:32] !== {4'hf, last})
                $fatal(1, "reply framing at word %0d", consumed);
            word = replies[consumed][31:0];
            consumed = consumed + 1;
        end
    endtask

    task automatic expect_word(input [31:0] expected, input last);
        reg [31:0] word;
        begin
            take(word, last);
            if (word !== expected) $fatal(1, "expected %h, got %h", expected, word);
        end
    endtask

    task automatic counters(input [7:0] txid);
        reg [31:0] count, drops, framing, sample;
        reg [31:0] stream_counts [0:5];
        integer i;
        begin
            expect_word({8'h81, 8'd0, txid, 8'd10}, 0);
            expect_word(5, 0);
            take(count, 0);
            if (!count) $fatal(1, "vacuous counters");
            for (i = 0; i < 6; i = i + 1) begin
                take(sample, 0); stream_counts[i] = sample;
            end
            take(drops, 0);
            take(framing, 1);
            if (drops !== 0) $fatal(1, "query backpressure lost observations: %0d", drops);
            if (framing !== 0) $fatal(1, "unexpected framing gap");
            for (i = 0; i < 6; i = i + 1)
                if (stream_counts[i] !== (i % 3 == 2 ? 0 : count))
                    $fatal(1, "stream count %0d disagrees with sampled cycles", i);
        end
    endtask

    // Every application clock emits RX then TX. The first frozen bank holds
    // precisely clocks 1..32 even while hundreds of new events arrive.
    task automatic trace_reply(input [7:0] txid, input integer first_cycle, output integer next_cycle);
        reg [31:0] dropped;
        integer n;
        begin
            expect_word({8'h83, 8'd0, txid, 8'd198}, 0);
            expect_word(2, 0); expect_word(3, 0); expect_word(64, 0);
            take(dropped, 0);
            if (dropped == 0) $fatal(1, "trace overflow not exercised");
            next_cycle = first_cycle + (64 + dropped)/2;
            expect_word(0, 0); expect_word(0, 0);
            for (n = 0; n < 64; n = n + 1) begin
                expect_word(n/2 + first_cycle, 0); expect_word(0, 0);
                expect_word(n % 2 == 0 ? 32'h01011107 : 32'h02012209, n == 63);
            end
        end
    endtask

    task automatic restart;
        begin
            @(negedge clk); reset = 1; request_valid = 0; response_ready = 0; hold_tail = 0;
            repeat (2) @(negedge clk);
            consumed = written;
            reset = 0;
        end
    endtask

    // Hold an earlier reply while offering the next valid request. The
    // second send runs concurrently with readout, obeying ready/valid.
    task automatic overlap(input [7:0] op, input next_trace, input at_tail);
        integer accepted, next_cycle, unused;
        begin
            restart();
            repeat (80) @(negedge clk);
            // The generated server can start its next activation before the
            // final beat retires. Holding only the reply header misses that
            // overlap, so exercise both the header and the final beat.
            hold_tail = at_tail; response_ready = at_tail;
            send({op, 8'd0, 8'h11, 8'd0}, 1, 15);
            while (!response_valid || (at_tail && !response_last)) @(negedge clk);
            accepted = requests;
            fork
                send({(next_trace ? 8'h03 : 8'h01), 8'd0, 8'h22, 8'd0}, 1, 15);
                begin
                    repeat (96) @(negedge clk);
                    if (requests != accepted) $fatal(1, "next query admitted before reply completed");
                    response_ready = 1; hold_tail = 0;
                    case (op)
                        8'h01: counters(8'h11);
                        8'h03: trace_reply(8'h11, 1, next_cycle);
                        default: begin expect_word(32'hff001101, 0); expect_word(1, 1); end
                    endcase
                end
            join
            if (next_trace) trace_reply(8'h22, next_cycle, unused);
            else counters(8'h22);
            send(32'h01003300, 1, 15); counters(8'h33);
        end
    endtask

    integer next_cycle;
    initial begin
        overlap(8'hfc, 0, 1);
        overlap(8'h01, 0, 1);
        overlap(8'h03, 1, 0);
        overlap(8'h03, 1, 1);
        // Unterminated malformed requests must keep draining until TLAST;
        // the one-reply fence must not block their payload.
        send(32'h03004402, 0, 15);
        send(32'h03005500, 0, 15);
        send(32'h03006600, 1, 15);
        expect_word(32'hff004401, 0); expect_word(1, 1);
        send(32'h01007700, 1, 7);
        expect_word(32'hff007701, 0); expect_word(1, 1);
        send(32'h01008800, 1, 15); counters(8'h88);
        // Reset aborts a stalled reply and releases admission for the new
        // session. Check a fresh first trace and zero sampling drops again.
        @(negedge clk); response_ready = 0;
        send(32'h03009900, 1, 15);
        while (!response_valid) @(negedge clk);
        restart();
        repeat (80) @(negedge clk);
        response_ready = 1;
        send(32'h0300aa00, 1, 15); trace_reply(8'haa, 1, next_cycle);
        send(32'h0100bb00, 1, 15); counters(8'hbb);
        repeat (20) @(negedge clk);
        if (consumed != written) $fatal(1, "unsolicited reply");
        $display("PASS: overlapping queries, held replies, frozen trace bank, overflow, malformed frames and reset; no missed observations");
        $finish;
    end
endmodule
