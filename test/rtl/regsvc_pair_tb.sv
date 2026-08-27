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

    axis_regsvc_pair_top dut (
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

    task automatic send_debug_counters;
        input [15:0] endpoint;
        input [7:0] txid;
        begin
            @(negedge clk);
            dbg_s_data = route(16'd0, endpoint);
            dbg_s_last = 1'b0;
            dbg_s_valid = 1'b1;
            while (!dbg_s_ready)
                @(posedge clk);
            @(negedge clk);
            dbg_s_data = header(8'h01, txid, 8'd0);
            dbg_s_last = 1'b1;
            while (!dbg_s_ready)
                @(posedge clk);
            @(negedge clk);
            dbg_s_data = 32'b0;
            dbg_s_last = 1'b0;
            dbg_s_valid = 1'b0;
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
        begin
            receive_app_beat(observed_word, 1'b0);
            if (observed_word !== header(8'd7, endpoint[7:0], 8'd1)) begin
                $display("FAIL: endpoint %0d response header was %08x",
                         endpoint, observed_word);
                $fatal(1);
            end
            receive_app_beat(observed_word, 1'b1);
            if (observed_word !== (endpoint == 16'd1 ?
                    32'h11111111 : 32'h22222222)) begin
                $display("FAIL: endpoint %0d response payload was %08x",
                         endpoint, observed_word);
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
        for (index = 0; index < 8; index = index + 1)
            receive_debug_beat(observed_word, index == 7);
        if (observed_word == 32'd0) begin
            $display("FAIL: blocked routed reply produced no endpoint TX stalls");
            $fatal(1);
        end

        // Releasing the output must emit the entirety of the selected packet
        // before arbitration moves to the other endpoint.
        m_ready = 1'b1;
        receive_app_beat(observed_word, 1'b0);
        if (observed_word !== route(first_endpoint, 16'd0)) begin
            $display("FAIL: first route beat changed on release");
            $fatal(1);
        end
        expect_app_reply(first_endpoint);

        receive_app_beat(observed_word, 1'b0);
        second_endpoint = observed_word[31:16];
        if (observed_word[15:0] !== 16'd0 ||
                second_endpoint === first_endpoint ||
                (second_endpoint !== 16'd1 && second_endpoint !== 16'd2)) begin
            $display("FAIL: malformed second routed response %08x", observed_word);
            $fatal(1);
        end
        expect_app_reply(second_endpoint);

        $display("PASS: routed regsvc pair");
        $finish;
    end
endmodule
