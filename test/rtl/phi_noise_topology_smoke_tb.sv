`timescale 1ns/1ps

module phi_noise_topology_smoke_tb;
    localparam [7:0] PHENOM_ANYON_TAG = 8'd10;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg x_ready = 1'b0;
    wire [127:0] x_announcement;
    wire x_valid;

    reg z_ready = 1'b0;
    wire [127:0] z_announcement;
    wire z_valid;

    wire x_correction_ready = 1'b1;
    wire [127:0] x_correction;
    wire x_correction_valid;

    wire z_correction_ready = 1'b1;
    wire [127:0] z_correction;
    wire z_correction_valid;

    reg [127:0] captured_x;
    reg [127:0] captured_z;
    reg [127:0] stalled_x;
    reg [127:0] stalled_z;
    integer x_count = 0;
    integer z_count = 0;
    integer cycle;

    __phi_noise_topology_smoke__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_noise_topology_smoke__x_announcements_out_rdy(x_ready),
        .phi_noise_topology_smoke__x_announcements_out(x_announcement),
        .phi_noise_topology_smoke__x_announcements_out_vld(x_valid),
        .phi_noise_topology_smoke__z_announcements_out_rdy(z_ready),
        .phi_noise_topology_smoke__z_announcements_out(z_announcement),
        .phi_noise_topology_smoke__z_announcements_out_vld(z_valid),
        .phi_noise_topology_smoke__x_corrections_out_rdy(x_correction_ready),
        .phi_noise_topology_smoke__x_corrections_out(x_correction),
        .phi_noise_topology_smoke__x_corrections_out_vld(x_correction_valid),
        .phi_noise_topology_smoke__z_corrections_out_rdy(z_correction_ready),
        .phi_noise_topology_smoke__z_corrections_out(z_correction),
        .phi_noise_topology_smoke__z_corrections_out_vld(z_correction_valid)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && x_valid && x_ready && x_count == 0) begin
            captured_x <= x_announcement;
            x_count <= 1;
        end
        if (!reset && z_valid && z_ready && z_count == 0) begin
            captured_z <= z_announcement;
            z_count <= 1;
        end
        if (!reset && x_correction_valid && x_correction_ready) begin
            $display("FAIL: distance-one x plane emitted a correction");
            $fatal(1);
        end
        if (!reset && z_correction_valid && z_correction_ready) begin
            $display("FAIL: distance-one z plane emitted a correction");
            $fatal(1);
        end
    end

    task automatic wait_for_both_valid;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && !(x_valid && z_valid);
                    cycle = cycle + 1)
                @(posedge clk);
            if (!(x_valid && z_valid)) begin
                $display("FAIL: timed out waiting for x and z announcements");
                $fatal(1);
            end
        end
    endtask

    task automatic wait_for_both_captured;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && !(x_count == 1 && z_count == 1);
                    cycle = cycle + 1)
                @(posedge clk);
            if (!(x_count == 1 && z_count == 1)) begin
                $display("FAIL: timed out accepting x and z announcements");
                $fatal(1);
            end
            @(negedge clk);
        end
    endtask

    task automatic check_announcement;
        input [127:0] frame;
        input [7:0] plane;
        reg [31:0] header;
        begin
            header = frame[127:96];
            if (header[7:0] !== PHENOM_ANYON_TAG ||
                    header[31:24] !== 8'd3) begin
                $display("FAIL: %s announcement has malformed header %08x",
                    plane, header);
                $fatal(1);
            end
            if (frame[31:0] !== 32'd0) begin
                $display("FAIL: %s announcement has unexpected step %0d",
                    plane, frame[31:0]);
                $fatal(1);
            end
            if (frame[63:32] > 32'd1 || frame[95:64] !== 32'd0) begin
                $display("FAIL: %s announcement has malformed payload", plane);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Keep both observation branches stalled until each plane has produced
        // its first complete result. They are independent outputs, and each
        // must retain its own frame while backpressured.
        wait_for_both_valid(100000);
        stalled_x = x_announcement;
        stalled_z = z_announcement;
        repeat (200) begin
            @(posedge clk);
            if (!x_valid || x_announcement !== stalled_x) begin
                $display("FAIL: stalled x announcement was not stable");
                $fatal(1);
            end
            if (!z_valid || z_announcement !== stalled_z) begin
                $display("FAIL: stalled z announcement was not stable");
                $fatal(1);
            end
        end

        @(negedge clk);
        x_ready = 1'b1;
        z_ready = 1'b1;
        wait_for_both_captured(100000);

        check_announcement(captured_x, "x");
        check_announcement(captured_z, "z");

        $display("PASS: distance-one phi/noise family topology");
        $finish;
    end
endmodule
