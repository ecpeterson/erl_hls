`timescale 1ns/1ps

module xls_debug_tap_tb;
    localparam integer STATE_BITS = 32;
    localparam integer OBSERVATION_BITS = STATE_BITS + 32 + 2 * (32 + 3) + 1;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    reg app_state_valid = 1'b0;
    reg [STATE_BITS-1:0] app_state_data = {STATE_BITS{1'b0}};
    reg observation_ready = 1'b1;
    wire [OBSERVATION_BITS-1:0] observation_data;
    wire observation_valid;

    wire observed_state_valid = observation_data[0];
    wire [31:0] observation_drops = observation_data[102:71];
    wire [STATE_BITS-1:0] observed_state_data = observation_data[134:103];

    xls_debug_tap #(
        .STATE_BITS(STATE_BITS)
    ) dut (
        .aclk(clk),
        .aresetn(resetn),
        .app_rx_tvalid(1'b0),
        .app_rx_tready(1'b0),
        .app_rx_tlast(1'b0),
        .app_rx_tdata(32'd0),
        .app_tx_tvalid(1'b0),
        .app_tx_tready(1'b0),
        .app_tx_tlast(1'b0),
        .app_tx_tdata(32'd0),
        .app_state_data(app_state_data),
        .app_state_valid(app_state_valid),
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

        // Three blocked observer cycles are counted, while commit pulses are
        // coalesced into the newest state until observation resumes.
        observation_ready = 1'b0;
        app_state_data = 32'h11111111;
        app_state_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        app_state_valid = 1'b0;
        @(posedge clk);
        @(negedge clk);
        app_state_data = 32'h22222222;
        app_state_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        app_state_valid = 1'b0;

        if (observation_drops !== 32'd3 ||
                !observed_state_valid ||
                observed_state_data !== 32'h22222222) begin
            $display("FAIL: tap did not retain drops and newest state");
            $fatal(1);
        end

        observation_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        if (observation_drops !== 32'd3 || observed_state_valid) begin
            $display("FAIL: tap did not clear a consumed state pulse");
            $fatal(1);
        end

        $display("PASS: passive debug tap");
        $finish;
    end
endmodule
