`timescale 1ns/1ps

module regsvc_pair_tb;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg [31:0] s_data = 32'b0;
    reg s_valid = 1'b0;
    wire s_ready;
    reg s_last = 1'b0;
    wire [31:0] m_data;
    wire m_valid;
    reg m_ready = 1'b1;
    wire m_last;

    reg [31:0] dbg_s_data = 32'b0;
    reg dbg_s_valid = 1'b0;
    wire dbg_s_ready;
    reg dbg_s_last = 1'b0;
    wire [31:0] dbg_m_data;
    wire dbg_m_valid;
    reg dbg_m_ready = 1'b1;
    wire dbg_m_last;

    reg [15:0] first_endpoint;
    reg [15:0] second_endpoint;
    reg [31:0] observed_word;
    integer index;

    regsvc_pair_fixture dut (
        .aclk(clk),
        .aresetn(resetn),
        .s_axis_tdata(s_data),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .s_axis_tlast(s_last),
        .m_axis_tdata(m_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready),
        .m_axis_tlast(m_last),
        .s_dbg_tdata(dbg_s_data),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(dbg_s_valid),
        .s_dbg_tready(dbg_s_ready),
        .s_dbg_tlast(dbg_s_last),
        .m_dbg_tdata(dbg_m_data),
        .m_dbg_tkeep(),
        .m_dbg_tvalid(dbg_m_valid),
        .m_dbg_tready(dbg_m_ready),
        .m_dbg_tlast(dbg_m_last)
    );

    always #5 clk = ~clk;

    function automatic [31:0] route;
        input [15:0] source;
        input [15:0] destination;
        begin
            route = {source, destination};
        end
    endfunction

    function automatic [31:0] header;
        input [7:0] tag;
        input [7:0] txid;
        input [7:0] payload_words;
        begin
            header = {tag, 8'h00, txid, payload_words};
        end
    endfunction

    task automatic send_app_beat;
        input [31:0] word;
        input last;
        begin
            @(negedge clk);
            s_data = word;
            s_last = last;
            s_valid = 1'b1;
            while (!s_ready)
                @(posedge clk);
            @(negedge clk);
            s_data = 32'b0;
            s_last = 1'b0;
            s_valid = 1'b0;
        end
    endtask

    task automatic send_ping;
        input [15:0] endpoint;
        input [7:0] txid;
        input [31:0] value;
        begin
            send_app_beat(route(16'd0, endpoint), 1'b0);
            send_app_beat(header(8'd5, txid, 8'd1), 1'b0);
            send_app_beat(value, 1'b1);
        end
    endtask

    task automatic send_debug_request;
        input [15:0] endpoint;
        input [7:0] txid;
        input [7:0] tag;
        begin
            @(negedge clk);
            dbg_s_data = route(16'd0, endpoint);
            dbg_s_last = 1'b0;
            dbg_s_valid = 1'b1;
            while (!dbg_s_ready)
                @(posedge clk);
            @(negedge clk);
            dbg_s_data = header(tag, txid, 8'd0);
            dbg_s_last = 1'b1;
            while (!dbg_s_ready)
                @(posedge clk);
            @(negedge clk);
            dbg_s_data = 32'b0;
            dbg_s_last = 1'b0;
            dbg_s_valid = 1'b0;
        end
    endtask

    task automatic send_debug_counters;
        input [15:0] endpoint;
        input [7:0] txid;
        begin
            send_debug_request(endpoint, txid, 8'h01);
        end
    endtask

    task automatic send_debug_trace;
        input [15:0] endpoint;
        input [7:0] txid;
        begin
            send_debug_request(endpoint, txid, 8'h03);
        end
    endtask

    task automatic send_reserved_state_request;
        input [15:0] endpoint;
        input [7:0] txid;
        begin
            send_debug_request(endpoint, txid, 8'h02);
        end
    endtask

    task automatic receive_app_beat;
        output [31:0] word;
        input expected_last;
        begin : wait_for_app
            forever begin
                @(posedge clk);
                if (m_valid && m_ready) begin
                    word = m_data;
                    if (m_last !== expected_last) begin
                        $display("FAIL: application TLAST mismatch for %08x", m_data);
                        $fatal(1);
                    end
                    disable wait_for_app;
                end
            end
        end
    endtask

    task automatic expect_app_reply;
        input [15:0] endpoint;
        input [7:0] txid;
        input [31:0] value;
        begin
            receive_app_beat(observed_word, 1'b0);
            if (observed_word !== header(8'd7, txid, 8'd1)) begin
                $display("FAIL: endpoint %0d response header was %08x",
                         endpoint, observed_word);
                $fatal(1);
            end
            receive_app_beat(observed_word, 1'b1);
            if (observed_word !== value) begin
                $display("FAIL: endpoint %0d response payload was %08x",
                         endpoint, observed_word);
                $fatal(1);
            end
        end
    endtask

    task automatic expect_two_event_trace;
        input [15:0] endpoint;
        input [7:0] debug_txid;
        input [7:0] app_txid;
        reg [31:0] rx_cycle;
        reg [31:0] tx_cycle;
        begin
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== route(endpoint, 16'd0)) begin
                $display("FAIL: trace reply came from wrong endpoint: %08x",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== header(8'h83, debug_txid, 8'd9)) begin
                $display("FAIL: malformed debug trace header: %08x",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd1) begin
                $display("FAIL: unexpected trace version %0d", observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd2) begin
                $display("FAIL: unexpected trace record width %0d", observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd2) begin
                $display("FAIL: expected two retained trace events, got %0d",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd0) begin
                $display("FAIL: endpoint unexpectedly dropped trace events");
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd0) begin
                $display("FAIL: trace reported observation drops");
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word == 32'd0) begin
                $display("FAIL: application RX trace timestamp was zero");
                $fatal(1);
            end
            rx_cycle = observed_word;
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== {8'h01, 8'h00, app_txid, 8'd5}) begin
                $display("FAIL: malformed application RX trace event %08x",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word == 32'd0) begin
                $display("FAIL: application TX trace timestamp was zero");
                $fatal(1);
            end
            tx_cycle = observed_word;
            receive_debug_beat(observed_word, 1'b1);
            if (observed_word !== {8'h02, 8'h00, app_txid, 8'd7}) begin
                $display("FAIL: malformed application TX trace event %08x",
                         observed_word);
                $fatal(1);
            end
            if (tx_cycle < rx_cycle) begin
                $display("FAIL: trace timestamps ran backwards: RX %0d, TX %0d",
                         rx_cycle, tx_cycle);
                $fatal(1);
            end
        end
    endtask

    task automatic expect_one_event_trace;
        input [15:0] endpoint;
        input [7:0] debug_txid;
        input [31:0] event_metadata;
        begin
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== route(endpoint, 16'd0)) begin
                $display("FAIL: trace reply came from wrong endpoint: %08x",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== header(8'h83, debug_txid, 8'd7)) begin
                $display("FAIL: malformed debug trace header: %08x",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd1) begin
                $display("FAIL: unexpected trace version %0d", observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd2) begin
                $display("FAIL: unexpected trace record width %0d", observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd1) begin
                $display("FAIL: expected one retained trace event, got %0d",
                         observed_word);
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd0) begin
                $display("FAIL: endpoint unexpectedly dropped trace events");
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word !== 32'd0) begin
                $display("FAIL: trace reported observation drops");
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b0);
            if (observed_word == 32'd0) begin
                $display("FAIL: application trace timestamp was zero");
                $fatal(1);
            end
            receive_debug_beat(observed_word, 1'b1);
            if (observed_word !== event_metadata) begin
                $display("FAIL: malformed application trace event %08x",
                         observed_word);
                $fatal(1);
            end
        end
    endtask

    task automatic receive_debug_beat;
        output [31:0] word;
        input expected_last;
        begin : wait_for_debug
            forever begin
                @(posedge clk);
                if (dbg_m_valid && dbg_m_ready) begin
                    word = dbg_m_data;
                    if (dbg_m_last !== expected_last) begin
                        $display("FAIL: debug TLAST mismatch for %08x", dbg_m_data);
                        $fatal(1);
                    end
                    disable wait_for_debug;
                end
            end
        end
    endtask

    initial begin : watchdog
        #300000;
        $display("FAIL: pair simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        // Neither endpoint may turn its zero-initialized output state into a
        // routed packet before a real request arrives.
        repeat (8) begin
            @(posedge clk);
            if (m_valid || dbg_m_valid) begin
                $display("FAIL: routed output became valid before a request");
                $fatal(1);
            end
        end

        // Let both independent processes produce replies while the one shared
        // application output is blocked.
        m_ready = 1'b0;
        send_ping(16'd1, 8'd1, 32'h11111111);
        send_ping(16'd2, 8'd2, 32'h22222222);
        while (!m_valid)
            @(posedge clk);
        first_endpoint = m_data[31:16];
        if (m_data[15:0] !== 16'd0 ||
                (first_endpoint !== 16'd1 && first_endpoint !== 16'd2) ||
                m_last) begin
            $display("FAIL: malformed first routed response %08x", m_data);
            $fatal(1);
        end
        repeat (8) begin
            @(posedge clk);
            if (!m_valid || m_data !== route(first_endpoint, 16'd0) || m_last) begin
                $display("FAIL: route beat changed under backpressure");
                $fatal(1);
            end
        end

        // Debug routing and serialization remain independent of the blocked
        // application router.
        send_debug_counters(16'd2, 8'h55);
        receive_debug_beat(observed_word, 1'b0);
        if (observed_word !== route(16'd2, 16'd0)) begin
            $display("FAIL: debug reply came from wrong endpoint: %08x",
                     observed_word);
            $fatal(1);
        end
        receive_debug_beat(observed_word, 1'b0);
        if (observed_word !== header(8'h81, 8'h55, 8'd8)) begin
            $display("FAIL: malformed debug counters header: %08x", observed_word);
            $fatal(1);
        end
        for (index = 0; index < 8; index = index + 1) begin
            receive_debug_beat(observed_word, index == 7);
            if (index == 0 && observed_word !== 32'd4) begin
                $display("FAIL: unexpected debug protocol version %0d",
                         observed_word);
                $fatal(1);
            end
        end
        if (observed_word == 32'd0) begin
            $display("FAIL: blocked routed reply produced no endpoint TX stalls");
            $fatal(1);
        end

        // The former passive full-state read is deliberately not part of
        // protocol version 4. Keep its old tag reserved and verify that stale
        // clients receive a bounded error instead of a state snapshot.
        send_reserved_state_request(first_endpoint, 8'h57);
        receive_debug_beat(observed_word, 1'b0);
        if (observed_word !== route(first_endpoint, 16'd0)) begin
            $display("FAIL: reserved-tag reply came from wrong endpoint: %08x",
                     observed_word);
            $fatal(1);
        end
        receive_debug_beat(observed_word, 1'b0);
        if (observed_word !== header(8'hff, 8'h57, 8'd1)) begin
            $display("FAIL: malformed reserved-tag error header: %08x",
                     observed_word);
            $fatal(1);
        end
        receive_debug_beat(observed_word, 1'b1);
        if (observed_word !== 32'd1) begin
            $display("FAIL: unexpected reserved-tag error code %0d",
                     observed_word);
            $fatal(1);
        end

        // With consumer input flops disabled, the selected endpoint has
        // accepted its request but cannot transfer its response into the
        // blocked shared router. The independent trace therefore contains the
        // request header alone; the response is observed after release below.
        send_debug_trace(first_endpoint, 8'h56);
        expect_one_event_trace(
            first_endpoint,
            8'h56,
            {8'h01, 8'h00, first_endpoint[7:0], 8'd5});

        // Releasing the output must emit the entirety of the selected packet
        // before arbitration moves to the other endpoint.
        m_ready = 1'b1;
        receive_app_beat(observed_word, 1'b0);
        if (observed_word !== route(first_endpoint, 16'd0)) begin
            $display("FAIL: first route beat changed on release");
            $fatal(1);
        end
        expect_app_reply(
            first_endpoint,
            first_endpoint[7:0],
            first_endpoint == 16'd1 ? 32'h11111111 : 32'h22222222);

        receive_app_beat(observed_word, 1'b0);
        second_endpoint = observed_word[31:16];
        if (observed_word[15:0] !== 16'd0 ||
                second_endpoint === first_endpoint ||
                (second_endpoint !== 16'd1 && second_endpoint !== 16'd2)) begin
            $display("FAIL: malformed second routed response %08x", observed_word);
            $fatal(1);
        end
        expect_app_reply(
            second_endpoint,
            second_endpoint[7:0],
            second_endpoint == 16'd1 ? 32'h11111111 : 32'h22222222);

        // The first endpoint's response crossed its local boundary only after
        // the shared output was released. Snapshot that deferred TX event so
        // the next trace bank starts empty for the overlap checks.
        send_debug_trace(first_endpoint, 8'h5a);
        expect_one_event_trace(
            first_endpoint,
            8'h5a,
            {8'h02, 8'h00, first_endpoint[7:0], 8'd7});

        // Populate the alternate trace bank, then freeze it and hold its reply
        // at the shared debug output. Application traffic must continue into
        // the newly active bank, without changing the blocked debug packet.
        @(negedge clk);
        m_ready = 1'b0;
        send_ping(first_endpoint, 8'h60, 32'hcafef00d);
        @(negedge clk);
        m_ready = 1'b1;
        receive_app_beat(observed_word, 1'b0);
        if (observed_word !== route(first_endpoint, 16'd0)) begin
            $display("FAIL: first overlap ping came from wrong endpoint: %08x",
                     observed_word);
            $fatal(1);
        end
        expect_app_reply(first_endpoint, 8'h60, 32'hcafef00d);

        dbg_m_ready = 1'b0;
        send_debug_trace(first_endpoint, 8'h58);
        while (!dbg_m_valid)
            @(posedge clk);
        if (dbg_m_data !== route(first_endpoint, 16'd0) || dbg_m_last) begin
            $display("FAIL: malformed blocked trace route %08x", dbg_m_data);
            $fatal(1);
        end

        @(negedge clk);
        m_ready = 1'b0;
        send_ping(first_endpoint, 8'h61, 32'hfacefeed);
        @(negedge clk);
        m_ready = 1'b1;
        receive_app_beat(observed_word, 1'b0);
        if (observed_word !== route(first_endpoint, 16'd0)) begin
            $display("FAIL: second overlap ping came from wrong endpoint: %08x",
                     observed_word);
            $fatal(1);
        end
        expect_app_reply(first_endpoint, 8'h61, 32'hfacefeed);
        if (!dbg_m_valid ||
                dbg_m_data !== route(first_endpoint, 16'd0) ||
                dbg_m_last) begin
            $display("FAIL: blocked debug packet changed during application traffic");
            $fatal(1);
        end

        @(negedge clk);
        dbg_m_ready = 1'b1;
        expect_two_event_trace(first_endpoint, 8'h58, 8'h60);

        send_debug_trace(first_endpoint, 8'h59);
        expect_two_event_trace(first_endpoint, 8'h59, 8'h61);

        $display("PASS: routed regsvc pair");
        $finish;
    end
endmodule
