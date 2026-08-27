`timescale 1ns/1ps

module regsvc_pair_harness_tb;
    reg clock = 1'b0;
    wire activity;

    integer active_cycles = 0;
    reg saw_app_one = 1'b0;
    reg saw_app_two = 1'b0;
    reg saw_debug_one = 1'b0;
    reg saw_debug_two = 1'b0;
    reg [7:0] app_ops_one = 8'b0;
    reg [7:0] app_ops_two = 8'b0;
    reg [3:0] debug_ops_one = 4'b0;
    reg [3:0] debug_ops_two = 4'b0;
    reg saw_app_response = 1'b0;
    reg saw_debug_response = 1'b0;
    reg saw_digest = 1'b0;

    regsvc_pair_openxc7_harness dut (
        .clock(clock),
        .activity(activity)
    );

    always #5 clock = ~clock;

    always @(posedge clock) begin
        if (dut.resetn) begin
            active_cycles <= active_cycles + 1;
            if (dut.routed_pair.app_one_in_valid &&
                    dut.routed_pair.app_one_in_ready)
                saw_app_one <= 1'b1;
            if (dut.routed_pair.app_two_in_valid &&
                    dut.routed_pair.app_two_in_ready)
                saw_app_two <= 1'b1;
            if (dut.routed_pair.debug_one_in_valid &&
                    dut.routed_pair.debug_one_in_ready)
                saw_debug_one <= 1'b1;
            if (dut.routed_pair.debug_two_in_valid &&
                    dut.routed_pair.debug_two_in_ready)
                saw_debug_two <= 1'b1;
            if (dut.app_phase == dut.APP_HEADER && dut.app_request_ready) begin
                if (dut.app_destination)
                    app_ops_two[dut.app_operation] <= 1'b1;
                else
                    app_ops_one[dut.app_operation] <= 1'b1;
            end
            if (dut.debug_phase == dut.DEBUG_HEADER &&
                    dut.debug_request_ready) begin
                if (dut.debug_destination)
                    debug_ops_two[dut.debug_operation] <= 1'b1;
                else
                    debug_ops_one[dut.debug_operation] <= 1'b1;
            end
            if (dut.app_response_valid)
                saw_app_response <= 1'b1;
            if (dut.debug_response_valid)
                saw_debug_response <= 1'b1;
            if (dut.response_digest != 32'b0)
                saw_digest <= 1'b1;

            if (active_cycles == 5000) begin
                if (!saw_app_one || !saw_app_two ||
                        !saw_debug_one || !saw_debug_two) begin
                    $display("FAIL: harness did not reach every endpoint");
                    $fatal(1);
                end
                if (app_ops_one != 8'hff || app_ops_two != 8'hff ||
                        debug_ops_one != 4'hf || debug_ops_two != 4'hf) begin
                    $display("FAIL: harness did not issue every request kind");
                    $fatal(1);
                end
                if (!saw_app_response || !saw_debug_response || !saw_digest) begin
                    $display("FAIL: harness did not retain observable replies");
                    $fatal(1);
                end
                $display("PASS: openXC7 regsvc harness traffic");
                $finish;
            end
        end
    end

    initial begin
        #100000;
        $display("FAIL: openXC7 harness simulation timed out");
        $fatal(1);
    end
endmodule
