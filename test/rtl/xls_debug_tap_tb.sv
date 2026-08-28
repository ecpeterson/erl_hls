`timescale 1ns/1ps

module xls_debug_tap_tb;
    localparam integer OBSERVATION_BITS = 32 + 2 * (32 + 3);

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg app_rx_valid = 1'b0;
    reg app_rx_ready = 1'b0;
    reg app_rx_last = 1'b0;
    reg [31:0] app_rx_data = 32'd0;
    reg app_tx_valid = 1'b0;
    reg app_tx_ready = 1'b0;
    reg app_tx_last = 1'b0;
    reg [31:0] app_tx_data = 32'd0;
    reg observation_ready = 1'b1;
    wire [OBSERVATION_BITS-1:0] observation_data;
    wire observation_valid;

    wire observed_rx_valid = observation_data[0];
    wire observed_rx_ready = observation_data[1];
    wire observed_rx_last = observation_data[2];
    wire [31:0] observed_rx_data = observation_data[34:3];
    wire observed_tx_valid = observation_data[35];
    wire observed_tx_ready = observation_data[36];
    wire observed_tx_last = observation_data[37];
    wire [31:0] observed_tx_data = observation_data[69:38];
    wire [31:0] observation_drops = observation_data[101:70];

    xls_debug_tap dut (
        .aclk(clk),
        .aresetn(resetn),
        .app_rx_tvalid(app_rx_valid),
        .app_rx_tready(app_rx_ready),
        .app_rx_tlast(app_rx_last),
        .app_rx_tdata(app_rx_data),
        .app_tx_tvalid(app_tx_valid),
        .app_tx_tready(app_tx_ready),
        .app_tx_tlast(app_tx_last),
        .app_tx_tdata(app_tx_data),
        .observation_data(observation_data),
        .observation_valid(observation_valid),
        .observation_ready(observation_ready)
    );

    always #5 clk = ~clk;

    initial begin : watchdog
        #10000;
        $display("FAIL: debug-tap simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        repeat (3) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        if (!observation_valid || observation_drops !== 32'd0) begin
            $display("FAIL: malformed first observation");
            $fatal(1);
        end

        app_rx_data = 32'h11223344;
        app_rx_last = 1'b1;
        app_rx_ready = 1'b0;
        app_rx_valid = 1'b1;
        app_tx_data = 32'haabbccdd;
        app_tx_last = 1'b0;
        app_tx_ready = 1'b1;
        app_tx_valid = 1'b1;
        #1;
        if (!observed_rx_valid || observed_rx_ready || !observed_rx_last ||
                observed_rx_data !== 32'h11223344 ||
                !observed_tx_valid || !observed_tx_ready || observed_tx_last ||
                observed_tx_data !== 32'haabbccdd) begin
            $display("FAIL: tap packed the stream observation incorrectly");
            $fatal(1);
        end

        // Three blocked observer cycles are counted. Stream signals remain a
        // purely passive, current-cycle view; the tap retains no process state.
        observation_ready = 1'b0;
        @(posedge clk);
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);

        if (observation_drops !== 32'd3) begin
            $display("FAIL: tap did not count blocked observations");
            $fatal(1);
        end

        observation_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        if (observation_drops !== 32'd3) begin
            $display("FAIL: tap changed its drop count while ready");
            $fatal(1);
        end

        $display("PASS: passive debug tap");
        $finish;
    end
endmodule
