`timescale 1ns/1ps

// TODO: Once erl_xls can transpile message sends, investigate generating this
// scenario from the same Erlang test process used by the EUnit regression.
module regsvc_tb;
    reg         clk = 1'b0;
    reg         resetn = 1'b0;
    reg  [31:0] s_data = 32'b0;
    reg  [3:0]  s_keep = 4'hf;
    reg         s_valid = 1'b0;
    wire        s_ready;
    reg         s_last = 1'b0;

    wire [31:0] m_data;
    wire [3:0]  m_keep;
    wire        m_valid;
    reg         m_ready = 1'b1;
    wire        m_last;

    reg  [31:0] dbg_s_data = 32'b0;
    reg  [3:0]  dbg_s_keep = 4'hf;
    reg         dbg_s_valid = 1'b0;
    wire        dbg_s_ready;
    reg         dbg_s_last = 1'b0;
    wire [31:0] dbg_m_data;
    wire [3:0]  dbg_m_keep;
    wire        dbg_m_valid;
    reg         dbg_m_ready = 1'b1;
    wire        dbg_m_last;

    reg [31:0] debug_word;

    integer accepted_output_beats = 0;

    axis_regsvc_instrumented_wrapper dut (
        .aclk(clk),
        .aresetn(resetn),
        .s_axis_tdata(s_data),
        .s_axis_tkeep(s_keep),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .s_axis_tlast(s_last),
        .m_axis_tdata(m_data),
        .m_axis_tkeep(m_keep),
        .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready),
        .m_axis_tlast(m_last),
        .s_dbg_tdata(dbg_s_data),
        .s_dbg_tkeep(dbg_s_keep),
        .s_dbg_tvalid(dbg_s_valid),
        .s_dbg_tready(dbg_s_ready),
        .s_dbg_tlast(dbg_s_last),
        .m_dbg_tdata(dbg_m_data),
        .m_dbg_tkeep(dbg_m_keep),
        .m_dbg_tvalid(dbg_m_valid),
        .m_dbg_tready(dbg_m_ready),
        .m_dbg_tlast(dbg_m_last)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (resetn && m_valid && m_ready)
            accepted_output_beats <= accepted_output_beats + 1;
    end

    function automatic [31:0] header;
        input [7:0] tag;
        input [7:0] txid;
        input [7:0] payload_words;
        begin
            header = {tag, 8'h00, txid, payload_words};
        end
    endfunction

    task automatic send_beat;
        input [31:0] word;
        input        last;
        begin
            @(negedge clk);
            s_data = word;
            s_last = last;
            s_valid = 1'b1;
            while (!s_ready)
                @(posedge clk);
            @(negedge clk);
            s_valid = 1'b0;
            s_last = 1'b0;
            s_data = 32'b0;
        end
    endtask

    task automatic send_debug_get_counters;
        input [7:0] txid;
        begin
            @(negedge clk);
            dbg_s_data = header(8'hd0, txid, 8'd0);
            dbg_s_last = 1'b1;
            dbg_s_valid = 1'b1;
            while (!dbg_s_ready)
                @(posedge clk);
            @(negedge clk);
            dbg_s_data = 32'b0;
            dbg_s_last = 1'b0;
            dbg_s_valid = 1'b0;
        end
    endtask

    task automatic send_debug_get_state;
        input [7:0] txid;
        begin
            @(negedge clk);
            dbg_s_data = header(8'hd2, txid, 8'd0);
            dbg_s_last = 1'b1;
            dbg_s_valid = 1'b1;
            while (!dbg_s_ready)
                @(posedge clk);
            @(negedge clk);
            dbg_s_data = 32'b0;
            dbg_s_last = 1'b0;
            dbg_s_valid = 1'b0;
        end
    endtask

    task automatic receive_debug_beat;
        output [31:0] word;
        input         expected_last;
        begin : wait_for_debug_beat
            forever begin
                @(posedge clk);
                if (dbg_m_valid && dbg_m_ready) begin
                    word = dbg_m_data;
                    if (dbg_m_last !== expected_last) begin
                        $display("FAIL: expected debug TLAST %0d, got %0d for word %08x",
                                 expected_last, dbg_m_last, dbg_m_data);
                        $fatal(1);
                    end
                    if (dbg_m_keep !== 4'hf) begin
                        $display("FAIL: expected debug TKEEP=f, got %x", dbg_m_keep);
                        $fatal(1);
                    end
                    disable wait_for_debug_beat;
                end
            end
        end
    endtask

    task automatic expect_debug_beat;
        input [31:0] expected_word;
        input        expected_last;
        begin
            receive_debug_beat(debug_word, expected_last);
            if (debug_word !== expected_word) begin
                $display("FAIL: expected debug word %08x, got %08x",
                         expected_word, debug_word);
                $fatal(1);
            end
        end
    endtask

    task automatic send_ping;
        input [7:0] txid;
        input [31:0] value;
        begin
            send_beat(header(8'd5, txid, 8'd1), 1'b0);
            send_beat(value, 1'b1);
        end
    endtask

    task automatic send_get;
        input [7:0] txid;
        input [31:0] register;
        begin
            send_beat(header(8'd4, txid, 8'd1), 1'b0);
            send_beat(register, 1'b1);
        end
    endtask

    task automatic send_set;
        input [7:0] txid;
        input [31:0] register;
        input [31:0] value;
        input [31:0] mask;
        begin
            send_beat(header(8'd3, txid, 8'd3), 1'b0);
            send_beat(register, 1'b0);
            send_beat(value, 1'b0);
            send_beat(mask, 1'b1);
        end
    endtask

    task automatic send_bulk_get;
        input [7:0] txid;
        input [31:0] start;
        input [31:0] count;
        begin
            send_beat(header(8'd6, txid, 8'd2), 1'b0);
            send_beat(start, 1'b0);
            send_beat(count, 1'b1);
        end
    endtask

    task automatic expect_beat;
        input [31:0] expected_word;
        input        expected_last;
        begin : wait_for_beat
            forever begin
                @(posedge clk);
                if (m_valid && m_ready) begin
                    if (m_data !== expected_word) begin
                        $display("FAIL: expected word %08x, got %08x", expected_word, m_data);
                        $fatal(1);
                    end
                    if (m_last !== expected_last) begin
                        $display("FAIL: expected TLAST %0d, got %0d for word %08x",
                                 expected_last, m_last, m_data);
                        $fatal(1);
                    end
                    if (m_keep !== 4'hf) begin
                        $display("FAIL: expected TKEEP=f, got %x", m_keep);
                        $fatal(1);
                    end
                    disable wait_for_beat;
                end
            end
        end
    endtask

    task automatic expect_one_word_reply;
        input [7:0] tag;
        input [7:0] txid;
        input [31:0] value;
        begin
            expect_beat(header(tag, txid, 8'd1), 1'b0);
            expect_beat(value, 1'b1);
        end
    endtask

    initial begin : watchdog
        #200000;
        $display("FAIL: simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        // Tx must wait for a real response frame instead of emitting its
        // zero-initialized state after reset.
        repeat (8) begin
            @(posedge clk);
            if (m_valid) begin
                $display("FAIL: application output became valid before a request");
                $fatal(1);
            end
        end

        // Basic call/reply and transaction-ID preservation.
        send_ping(8'h11, 32'h12345678);
        expect_one_word_reply(8'd7, 8'h11, 32'h12345678);

        // Casts have no reply, but update state for subsequent calls.
        send_set(8'h20, 32'd0, 32'd2, 32'hffffffff);
        send_get(8'h21, 32'd0);
        expect_one_word_reply(8'd8, 8'h21, 32'd2);

        // Masked update: 2 | 1 = 3.
        send_set(8'h22, 32'd0, 32'd1, 32'd1);
        send_get(8'h23, 32'd0);
        expect_one_word_reply(8'd8, 8'h23, 32'd3);

        // The logical variable-length bulk result is carried in a fixed-width
        // three-word hardware payload.
        send_set(8'h24, 32'd1, 32'd4, 32'hffffffff);
        send_bulk_get(8'h25, 32'd0, 32'd3);
        expect_beat(header(8'd9, 8'h25, 8'd3), 1'b0);
        expect_beat(32'd0, 1'b0);
        expect_beat(32'd4, 1'b0);
        expect_beat(32'd3, 1'b1);

        // Backpressure must hold the first reply beat stable rather than lose
        // or partially transmit the frame.
        m_ready = 1'b0;
        send_ping(8'h30, 32'hfeedface);
        while (!m_valid)
            @(posedge clk);
        repeat (8) @(posedge clk);
        if (!m_valid || m_data !== header(8'd7, 8'h30, 8'd1) || m_last) begin
            $display("FAIL: reply was not held at its header under backpressure");
            $fatal(1);
        end

        // The management path must remain responsive while the application
        // output is blocked. The eight counter words are: version, cycles,
        // RX beats, RX frames, RX stalls, TX beats, TX frames, TX stalls.
        send_debug_get_counters(8'h55);
        expect_debug_beat(header(8'hd1, 8'h55, 8'd8), 1'b0);
        expect_debug_beat(32'd2, 1'b0);
        receive_debug_beat(debug_word, 1'b0); // cycles
        receive_debug_beat(debug_word, 1'b0); // RX beats
        receive_debug_beat(debug_word, 1'b0); // RX frames
        receive_debug_beat(debug_word, 1'b0); // RX stalls
        receive_debug_beat(debug_word, 1'b0); // TX beats
        receive_debug_beat(debug_word, 1'b0); // TX frames
        receive_debug_beat(debug_word, 1'b1); // TX stalls
        if (debug_word < 32'd8) begin
            $display("FAIL: debug snapshot missed application TX stall cycles: %0d",
                     debug_word);
            $fatal(1);
        end

        // State is reported from the last committed Service transaction. The
        // packed list is least-significant-word first on the wire, so the
        // logical register array arrives in reverse order after its version.
        send_debug_get_state(8'h56);
        expect_debug_beat(header(8'hd3, 8'h56, 8'd17), 1'b0);
        expect_debug_beat(32'd1, 1'b0); // state schema version
        repeat (14)
            expect_debug_beat(32'd0, 1'b0);
        expect_debug_beat(32'd4, 1'b0);
        expect_debug_beat(32'd3, 1'b1);

        m_ready = 1'b1;
        expect_one_word_reply(8'd7, 8'h30, 32'hfeedface);

        // A failed literal match emits ERROR and resets the service state.
        send_get(8'h40, 32'd16);
        expect_beat(header(8'd1, 8'h40, 8'd0), 1'b1);
        send_get(8'h41, 32'd0);
        expect_one_word_reply(8'd8, 8'h41, 32'd0);

        @(negedge clk);
        if (accepted_output_beats !== 15) begin
            $display("FAIL: expected 15 accepted output beats, got %0d",
                     accepted_output_beats);
            $fatal(1);
        end
        $display("PASS: regsvc RTL behavior (%0d output beats)",
                 accepted_output_beats);
        $finish;
    end
endmodule
