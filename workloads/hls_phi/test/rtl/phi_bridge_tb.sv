`timescale 1ns/1ps

// Three independent clocks: VPI's host and the two XLS devices. Only public
// ports are observed. Common reset retires both graphs and every crossing.
module phi_bridge_tb;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;
    reg clk0 = 0, clk1 = 0, reset = 0, paused = 0;
    integer half0 = 3, half1 = 7;
    integer periodic_stalls = 1;
    initial if ($value$plusargs("STALLS=%d", periodic_stalls)) begin end
    initial begin
        if ($value$plusargs("HALF0=%d", half0)) begin end
        forever #(half0) clk0 = !clk0;
    end
    initial begin
        if ($value$plusargs("HALF1=%d", half1)) begin end
        #1;
        forever #(half1) if (!paused) clk1 = !clk1;
    end
    wire reset0, reset1;
    hls_clock_reset device0_reset(.clk(clk0), .reset(reset), .local_reset(reset0));
    hls_clock_reset device1_reset(.clk(clk1), .reset(reset), .local_reset(reset1));

    reg [31:0] s_axis_tdata = 0, s_dbg_tdata = 0;
    reg [3:0] s_axis_tkeep = 15, s_dbg_tkeep = 15;
    reg s_axis_tlast = 0, s_axis_tvalid = 0;
    reg s_dbg_tlast = 0, s_dbg_tvalid = 0;
    wire s_axis_tready, s_dbg_tready;
    wire [31:0] m_axis_tdata, m_dbg_tdata;
    wire [3:0] m_axis_tkeep, m_dbg_tkeep;
    wire m_axis_tlast, m_axis_tvalid, m_dbg_tlast, m_dbg_tvalid;
    reg m_axis_tready = 0, m_dbg_tready = 0;
    wire [31:0] s_device0_tdata;
    wire [3:0] s_device0_tkeep;
    wire s_device0_tlast, s_device0_tvalid, s_device0_tready;
    wire [31:0] m_device0_tdata;
    wire [3:0] m_device0_tkeep;
    wire m_device0_tlast, m_device0_tvalid, m_device0_tready;
    hls_async_fifo #(.WIDTH(37)) debug0_request(
        .reset(reset), .wr_clk(clk), .rd_clk(clk0),
        .in_data({s_axis_tlast, s_axis_tkeep, s_axis_tdata}),
        .in_valid(s_axis_tvalid), .in_ready(s_axis_tready),
        .out_data({s_device0_tlast, s_device0_tkeep, s_device0_tdata}),
        .out_valid(s_device0_tvalid), .out_ready(s_device0_tready));
    hls_async_fifo #(.WIDTH(37)) debug0_response(
        .reset(reset), .wr_clk(clk0), .rd_clk(clk),
        .in_data({m_device0_tlast, m_device0_tkeep, m_device0_tdata}),
        .in_valid(m_device0_tvalid), .in_ready(m_device0_tready),
        .out_data({m_axis_tlast, m_axis_tkeep, m_axis_tdata}),
        .out_valid(m_axis_tvalid), .out_ready(m_axis_tready));
    wire [31:0] s_device1_tdata;
    wire [3:0] s_device1_tkeep;
    wire s_device1_tlast, s_device1_tvalid, s_device1_tready;
    wire [31:0] m_device1_tdata;
    wire [3:0] m_device1_tkeep;
    wire m_device1_tlast, m_device1_tvalid, m_device1_tready;
    hls_async_fifo #(.WIDTH(37)) debug1_request(
        .reset(reset), .wr_clk(clk), .rd_clk(clk1),
        .in_data({s_dbg_tlast, s_dbg_tkeep, s_dbg_tdata}),
        .in_valid(s_dbg_tvalid), .in_ready(s_dbg_tready),
        .out_data({s_device1_tlast, s_device1_tkeep, s_device1_tdata}),
        .out_valid(s_device1_tvalid), .out_ready(s_device1_tready));
    hls_async_fifo #(.WIDTH(37)) debug1_response(
        .reset(reset), .wr_clk(clk1), .rd_clk(clk),
        .in_data({m_device1_tlast, m_device1_tkeep, m_device1_tdata}),
        .in_valid(m_device1_tvalid), .in_ready(m_device1_tready),
        .out_data({m_dbg_tlast, m_dbg_tkeep, m_dbg_tdata}),
        .out_valid(m_dbg_tvalid), .out_ready(m_dbg_tready));

    wire [32:0] tx0_data, tx1_data, staged0_data, staged1_data, link01_data, link10_data;
    wire tx0_valid, tx0_ready, tx1_valid, tx1_ready;
    wire staged0_valid, staged0_ready, staged1_valid, staged1_ready;
    wire link01_valid, link01_ready, link10_valid, link10_ready;
    wire [31:0] fault0, fault1;
    wire fault0_valid, fault1_valid;
    reg released = 1, admit0 = 0, admit1 = 0;
    integer cycles = 0, cycles0 = 0, cycles1 = 0, reports, links, fd;
    reg pause_requested = 0, resume_requested = 0, release_announced = 0;

    // Admission controls are local to their source clock and never withdraw
    // a beat already presented to either crossing's write port.
    always @(negedge clk0) begin
        admit0 = released && (paused || !periodic_stalls || cycles0 % 17 >= 5);
        if (resetn && released && !release_announced) begin
            release_announced = 1;
            fd = $fopen("link_released", "w"); $fclose(fd);
        end
    end
    always @(negedge clk1) admit1 = !periodic_stalls || cycles1 % 13 >= 4;
    phi_bridge_delay admission0(.clk(clk0), .reset(reset0), .admit(admit0),
        .in_data(tx0_data), .in_valid(tx0_valid), .in_ready(tx0_ready),
        .out_data(staged0_data), .out_valid(staged0_valid), .out_ready(staged0_ready));
    phi_bridge_delay admission1(.clk(clk1), .reset(reset1), .admit(admit1),
        .in_data(tx1_data), .in_valid(tx1_valid), .in_ready(tx1_ready),
        .out_data(staged1_data), .out_valid(staged1_valid), .out_ready(staged1_ready));
    hls_async_fifo link01(.reset(reset), .wr_clk(clk0), .rd_clk(clk1),
        .in_data(staged0_data), .in_valid(staged0_valid), .in_ready(staged0_ready),
        .out_data(link01_data), .out_valid(link01_valid), .out_ready(link01_ready));
    hls_async_fifo link10(.reset(reset), .wr_clk(clk1), .rd_clk(clk0),
        .in_data(staged1_data), .in_valid(staged1_valid), .in_ready(staged1_ready),
        .out_data(link10_data), .out_valid(link10_valid), .out_ready(link10_ready));

    `ifdef PHI_MEMORY
        `include "phi_memory_transport.svh"
    `else
        wire event_ready0 = 1, event_ready1 = 1;
    `endif
    `include "phi_devices.vh"
    `ifdef PHI_PROFILE
        `include "phi_memory_profile.svh"
    `endif

    initial begin
        reports = $fopen("reports.log", "w");
        links = $fopen("link.log", "w");
        if (!reports || !links) $fatal(1, "cannot open public observation logs");
        #1; reset = 1;
        repeat (8) @(negedge clk0);
        repeat (8) @(negedge clk1);
        reset = 0;
        `ifndef PHI_PROFILE
        // Warm up, then discard a partially transmitted packet by restarting
        // the complete application, before exposing the host debug transport.
        wait(staged0_valid && staged0_ready && !staged0_data[32]);
        @(posedge clk0);
        @(negedge clk0);
        reset = 1;
        released = 0;
        repeat (8) @(negedge clk0);
        repeat (8) @(negedge clk1);
        reset = 0;
        `endif
        resetn = 1;
        wait(!reset0 && !reset1);
        fd = $fopen("activated", "w"); $fclose(fd);
        `ifndef PHI_PROFILE
        $display("Restarted both actor graphs after interrupting a link packet");
        `endif
    end

    always @(posedge clk0) begin
        if (reset0) cycles0 <= 0;
        else begin
            cycles0 <= cycles0 + 1;
            if (fault0_valid) $fatal(1, "device0 link protocol fault %h", fault0);
            if (resetn && link10_valid && link10_ready) $fdisplay(links, "1 %09h", link10_data);
        end
    end
    always @(posedge clk1) begin
        if (reset1) cycles1 <= 0;
        else begin
            cycles1 <= cycles1 + 1;
            if (fault1_valid) $fatal(1, "device1 link protocol fault %h", fault1);
            if (resetn && link01_valid && link01_ready) $fdisplay(links, "0 %09h", link01_data);
        end
    end
    always @(posedge clk) if (resetn) begin
        cycles <= cycles + 1;
        if (cycles > 10000000) $fatal(1, "host query timeout");
    end
    // Stop only at a falling edge. Resuming the oscillator needs the still
    // running host clock, not an edge of the clock which has been stopped.
    always @(negedge clk1) if (pause_requested && !resume_requested) begin
        paused = 1;
        fd = $fopen("peer_paused", "w"); $fclose(fd);
    end
    always @(negedge clk) if (resetn && cycles % 100 == 0) begin
        fd = $fopen("pause_peer", "r");
        if (fd) begin pause_requested = 1; $fclose(fd); end
        fd = $fopen("resume_peer", "r");
        if (fd) begin
            resume_requested = 1; paused = 0; $fclose(fd);
            fd = $fopen("peer_resumed", "w"); $fclose(fd);
        end
        fd = $fopen("release_link", "r");
        if (fd) begin released = 1; $fclose(fd); end
        fd = $fopen("done", "r");
        if (fd) begin
            $fclose(fd); $fclose(reports); $fclose(links);
            `ifndef PHI_PROFILE
            if (!pause_requested || !resume_requested) $fatal(1, "missing stopped-clock exercise");
            `endif
            $display("PASS: two-device phi bridge clocks=%0d/%0d ns (%0d host cycles)",
                2*half0, 2*half1, cycles);
            $finish;
        end
    end
    initial begin #200000000; $fatal(1, "phi bridge timeout"); end
endmodule

`include "phi_link_delay.svh"
