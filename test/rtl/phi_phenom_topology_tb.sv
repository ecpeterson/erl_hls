`timescale 1ns/1ps

module phi_phenom_topology_tb;
    localparam [7:0] PHENOM_ANYON_TAG = 8'd10;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg announcement_ready = 1'b0;
    wire [127:0] announcement;
    wire announcement_valid;

    reg [127:0] captured [0:3];
    reg [127:0] stalled_announcement;
    integer announcement_count = 0;
    integer cycle;

    __phi_phenom_topology__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_phenom_topology__announcement_out_rdy(announcement_ready),
        .phi_phenom_topology__announcement_out(announcement),
        .phi_phenom_topology__announcement_out_vld(announcement_valid)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && announcement_valid && announcement_ready) begin
            captured[announcement_count] <= announcement;
            announcement_count <= announcement_count + 1;
        end
    end

    task automatic wait_for_valid;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && !announcement_valid;
                    cycle = cycle + 1)
                @(posedge clk);
            if (!announcement_valid) begin
                $display("FAIL: timed out waiting for an announcement");
                $fatal(1);
            end
        end
    endtask

    task automatic wait_for_count;
        input integer target;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && announcement_count < target;
                    cycle = cycle + 1)
                @(posedge clk);
            if (announcement_count < target) begin
                $display("FAIL: timed out waiting for announcement %0d", target);
                $fatal(1);
            end
            @(negedge clk);
        end
    endtask

    task automatic check_announcement;
        input integer index;
        input [31:0] expected_step;
        input [31:0] expected_present;
        reg [31:0] header;
        begin
            header = captured[index][127:96];
            if (header[7:0] !== PHENOM_ANYON_TAG ||
                    header[31:24] !== 8'd2) begin
                $display(
                    "FAIL: announcement %0d has malformed header %08x",
                    index,
                    header
                );
                $fatal(1);
            end
            if (captured[index][31:0] !== expected_step) begin
                $display(
                    "FAIL: announcement %0d expected step %0d, got %0d",
                    index,
                    expected_step,
                    captured[index][31:0]
                );
                $fatal(1);
            end
            if (captured[index][63:32] !== expected_present) begin
                $display(
                    "FAIL: announcement %0d expected present %0d, got %0d",
                    index,
                    expected_present,
                    captured[index][63:32]
                );
                $fatal(1);
            end
            if (captured[index][95:64] !== 32'd0) begin
                $display("FAIL: announcement %0d has nonzero padding", index);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // The tap is part of the protocol path. Hold its external side stalled
        // long enough to prove that one complete Frame remains stable and that
        // the cyclic network resumes after backpressure is removed.
        wait_for_valid(20000);
        stalled_announcement = announcement;
        repeat (1000) begin
            @(posedge clk);
            if (!announcement_valid) begin
                $display("FAIL: stalled announcement dropped valid");
                $fatal(1);
            end
            if (announcement !== stalled_announcement) begin
                $display("FAIL: stalled announcement changed");
                $fatal(1);
            end
        end

        @(negedge clk);
        announcement_ready = 1'b1;
        wait_for_count(2, 50000);

        // The syndrome seed and half-range measurement threshold produce a
        // measurement fault at step zero and its falling edge at step one.
        // Four identical data events cancel in this one-cell periodic fixture.
        check_announcement(0, 32'd0, 32'd1);
        check_announcement(1, 32'd1, 32'd1);

        $display("PASS: closed phi/phenom frame topology");
        $finish;
    end
endmodule
