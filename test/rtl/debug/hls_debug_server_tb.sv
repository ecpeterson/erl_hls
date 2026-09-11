`timescale 1ns/1ps
module hls_debug_server_tb;
    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;
    reg [36:0] request = 0;
    reg request_valid = 0;
    wire request_ready;
    wire [36:0] response;
    wire response_valid;
    reg response_ready = 0;
    reg block_response = 0;
    wire timing = $test$plusargs("timing");
    wire [7:0] snapshot_request;
    wire snapshot_request_valid;
    reg [362:0] snapshot = 0;
    reg snapshot_valid = 0;
    wire snapshot_ready;
    wire trace_read_valid;
    integer cycle = 0, snapshots = 0, drains = 0;
    reg trace_available = 1;
    reg [36:0] received [0:4095];
    integer written = 0, consumed = 0;
    reg stalled = 0;
    reg [36:0] held;

    __hls_debug_server__DebugServer_0_next dut (
        .clk(clk), .reset(reset),
        ._request_in(request), ._request_in_vld(request_valid), ._request_in_rdy(request_ready),
        ._response_out(response), ._response_out_vld(response_valid), ._response_out_rdy(response_ready),
        ._snapshot_request_out(snapshot_request), ._snapshot_request_out_vld(snapshot_request_valid),
        ._snapshot_request_out_rdy(!snapshot_valid),
        ._snapshot_in(snapshot), ._snapshot_in_vld(snapshot_valid), ._snapshot_in_rdy(snapshot_ready),
        ._trace_read_request_out(), ._trace_read_request_out_vld(trace_read_valid),
        ._trace_read_request_out_rdy(1'b1), ._trace_read_response_in(64'b0),
        ._trace_read_response_in_vld(1'b0), ._trace_read_response_in_rdy()
    );

    always @(negedge clk) response_ready = !reset && !block_response && (timing || cycle % 7 >= 3);
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (cycle > 20000) $fatal(1, "debug server timeout");
        if (reset) begin
            snapshot_valid <= 0;
            trace_available <= 1;
            stalled <= 0;
        end else begin
            if (timing && request_valid && request_ready)
                $display("TIMING request cycle=%0d word=%h", cycle, request[31:0]);
            if (stalled && (response_valid !== 1'b1 || response !== held))
                $fatal(1, "debug response changed under backpressure");
            stalled <= response_valid && !response_ready;
            held <= response;
            if (response_valid && response_ready) begin
                if ((^response) === 1'bx) $fatal(1, "unknown response bits");
                if (timing) $display("TIMING response cycle=%0d word=%h last=%b",
                    cycle, response[31:0], response[32]);
                received[written] = response;
                written = written + 1;
            end
            if (snapshot_valid && snapshot_ready) snapshot_valid <= 0;
            if (snapshot_request_valid && !snapshot_valid) begin
                snapshots = snapshots + 1;
                // One odd pending trace event, so no external trace RAM read is needed.
                snapshot <= {224'd0, 32'd0, 2'd0, 1'b0,
                    (trace_available ? 7'd1 : 7'd0), 32'd0,
                    trace_available, 64'h12345678_01020304};
                snapshot_valid <= 1;
                if (snapshot_request == 8'h03) begin
                    drains = drains + 1;
                    trace_available <= 0;
                end
            end
            if (trace_read_valid) $fatal(1, "unexpected trace RAM access");
        end
    end

    task automatic send_beat(input [31:0] word, input last, input [3:0] keep);
        begin
            @(negedge clk);
            request = {keep, last, word};
            request_valid = 1;
            @(posedge clk);
            while (!request_ready) @(posedge clk);
            @(negedge clk);
            request_valid = 0;
        end
    endtask

    task automatic expect_word(input [31:0] word, input last);
        begin
            @(negedge clk);
            while (consumed == written) @(negedge clk);
            if (received[consumed] !== {4'hf, last, word})
                $fatal(1, "response word %0d: expected %h last=%0d, got %h",
                    consumed, word, last, received[consumed]);
            consumed = consumed + 1;
        end
    endtask

    task automatic expect_error(input [7:0] txid);
        begin
            expect_word({8'hff, 8'd0, txid, 8'd1}, 0);
            expect_word(1, 1);
        end
    endtask

    task automatic counters(input [7:0] txid);
        begin
            send_beat({8'h01, 8'd0, txid, 8'd0}, 1, 4'hf);
            expect_word({8'h81, 8'd0, txid, 8'd8}, 0);
            expect_word(4, 0);
            repeat (6) expect_word(0, 0);
            expect_word(0, 1);
        end
    endtask

    task automatic trace_reply(input [7:0] txid, input present);
        begin
            send_beat({8'h03, 8'd0, txid, 8'd0}, 1, 4'hf);
            expect_word({8'h83, 8'd0, txid, (present ? 8'd7 : 8'd5)}, 0);
            expect_word(1, 0);
            expect_word(2, 0);
            expect_word(present ? 1 : 0, 0);
            expect_word(0, 0);
            expect_word(0, !present);
            if (present) begin
                expect_word(32'h12345678, 0);
                expect_word(32'h01020304, 1);
            end
        end
    endtask

    integer before_snapshots, before_drains, before_output, i;
    initial begin
        repeat (5) @(negedge clk);
        reset = 0;
        if (timing) begin
            counters(8'h11);
            trace_reply(8'h55, 1);
            trace_reply(8'h56, 0);
            $display("PASS: valid debug reply timing");
            $finish;
        end
        counters(8'h11);
        // Payloads look like commands: they must be drained, never dispatched.
        block_response = 1;
        send_beat(32'h01002202, 0, 4'hf);
        send_beat(32'h03003300, 0, 4'hf);
        send_beat(32'h03004400, 1, 4'hf);
        repeat (20) @(negedge clk);
        if (snapshots != 1) $fatal(1, "rejected request queried blocked observer");
        block_response = 0;
        expect_error(8'h22);
        trace_reply(8'h55, 1);
        trace_reply(8'h56, 0);
        if (snapshots != 3 || drains != 2)
            $fatal(1, "malformed request reached the observer: snapshots=%0d drains=%0d", snapshots, drains);

        before_snapshots = snapshots;
        send_beat(32'h01006001, 1, 4'hf); expect_error(8'h60); // early TLAST
        send_beat(32'h03006100, 1, 4'h7); expect_error(8'h61); // partial keep
        send_beat(32'h03016200, 1, 4'hf); expect_error(8'h62); // reserved flags
        send_beat(32'h02006300, 1, 4'hf); expect_error(8'h63); // unsupported command
        send_beat(32'h83006400, 1, 4'hf); expect_error(8'h64); // reply direction
        send_beat(32'h03006500, 0, 4'hf); // missing TLAST on an empty request
        send_beat(32'h03006600, 1, 4'hf); expect_error(8'h65);
        // Oversized/late packet, beyond the eight-bit length field's range.
        send_beat(32'h030067ff, 0, 4'hf);
        for (i = 0; i < 300; i = i + 1) send_beat(32'h03007700, 0, 4'hf);
        send_beat(32'h03007800, 1, 4'hf); expect_error(8'h67);
        if (snapshots != before_snapshots) $fatal(1, "rejection queried the observer");
        counters(8'h68);

        before_snapshots = snapshots; before_drains = drains; before_output = written;
        send_beat(32'h03007001, 0, 4'hf);
        repeat (3) send_beat(32'h03007100, 0, 4'hf);
        repeat (50) @(negedge clk);
        if (snapshots != before_snapshots || drains != before_drains || written != before_output)
            $fatal(1, "unterminated request had a side effect");
        // Reset is the abort boundary when no terminating TLAST arrives.
        reset = 1;
        repeat (5) @(negedge clk);
        reset = 0;
        trace_reply(8'h72, 1);
        counters(8'h73);
        repeat (30) @(negedge clk);
        if (consumed != written) $fatal(1, "unsolicited debug reply");
        $display("PASS: malformed debug packets drain without observer/trace side effects; reset and stalled replies recover");
        $finish;
    end
endmodule
