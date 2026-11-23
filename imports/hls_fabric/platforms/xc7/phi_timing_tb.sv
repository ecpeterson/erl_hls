`timescale 1ns/1ps

// Inspect only the handwritten harness and the decoder's public event streams.
module phi_timing_tb #(
    parameter WIDTH = 3, HEIGHT = 3,
    parameter X_ENABLED = 1, Z_ENABLED = 1
);
    localparam TARGET_STEP = 32;
    localparam CELLS = WIDTH * HEIGHT;
    localparam [CELLS-1:0] COMPLETE = {CELLS{1'b1}};
    reg clock = 0;
    wire activity;
    phi_timing_harness dut (.clock(clock), .activity(activity));
    always #5 clock = ~clock;

    reg [CELLS-1:0] status [0:1][0:TARGET_STEP];
    reg [127:0] held [0:1];
    reg stalled [0:1];
    integer corrections [0:1];
    integer stalls [0:1];
    integer cycles = 0, warmup = 0;
    integer plane, step;

    // Require complete status sets and stable payloads under sink stalls.
    task automatic sample;
        input integer side;
        input [127:0] frame;
        input valid, ready;
        integer x, y, timestep;
        reg [31:0] value;
        reg [CELLS-1:0] coordinate;
        begin
            if ((^{valid, ready}) === 1'bx)
                $fatal(1, "unknown event handshake");
            if (stalled[side] && (!valid || frame !== held[side]))
                $fatal(1, "event changed across backpressure");
            stalled[side] = valid && !ready;
            held[side] = frame;
            if (stalled[side]) stalls[side] = stalls[side] + 1;
            if (valid && ready) begin
                if ((^frame) === 1'bx) $fatal(1, "unknown accepted event");
                x = frame[47:32];
                y = frame[63:48];
                timestep = frame[31:0];
                value = frame[95:64];
                if (x >= WIDTH || y >= HEIGHT) $fatal(1, "out-of-range coordinate");
                coordinate = {{(CELLS-1){1'b0}}, 1'b1} << (HEIGHT*x + y);
                case (frame[127:96])
                    32'h0300000b: begin
                        if (!(value == 1 || value == 2 || value == 4 || value == 8))
                            $fatal(1, "invalid correction direction");
                        corrections[side] = corrections[side] + 1;
                    end
                    32'h03000011: begin
                        if (value > 3) $fatal(1, "invalid status flags");
                        if (timestep >= 0 && timestep <= TARGET_STEP) begin
                            if (status[side][timestep] & coordinate)
                                $fatal(1, "duplicate status");
                            status[side][timestep] = status[side][timestep] | coordinate;
                        end
                    end
                    default: $fatal(1, "unexpected event header");
                endcase
            end
        end
    endtask

    initial begin
        for (plane = 0; plane < 2; plane = plane + 1) begin
            stalled[plane] = 0;
            corrections[plane] = 0;
            stalls[plane] = 0;
            for (step = 0; step <= TARGET_STEP; step = step + 1)
                status[plane][step] = 0;
        end
    end

    always @(posedge clock) if (dut.resetn) begin
        cycles = cycles + 1;
        sample(0, dut.x_event, dut.x_valid, dut.x_ready);
        sample(1, dut.z_event, dut.z_valid, dut.z_ready);
        if (activity !== 1'b0 && activity !== 1'b1) $fatal(1, "unknown activity digest");
        if ((!X_ENABLED && dut.x_valid) || (!Z_ENABLED && dut.z_valid))
            $fatal(1, "omitted plane produced an event");
        if (warmup == 0 && (!X_ENABLED || status[0][8] == COMPLETE) &&
                           (!Z_ENABLED || status[1][8] == COMPLETE))
            warmup = cycles;
        if ((!X_ENABLED || status[0][TARGET_STEP] == COMPLETE) &&
            (!Z_ENABLED || status[1][TARGET_STEP] == COMPLETE)) begin
            for (plane = 0; plane < 2; plane = plane + 1) begin
                if ((plane == 0 && X_ENABLED) || (plane == 1 && Z_ENABLED)) begin
                    if (stalls[plane] == 0) $fatal(1, "unused backpressure");
                    // Tiny periodic graphs merge opposite neighbors and cannot
                    // select a unique correction. Larger graphs must do so.
                    if ((WIDTH > 2 || HEIGHT > 2) && corrections[plane] == 0)
                        $fatal(1, "trivial correction workload");
                    for (step = 0; step <= TARGET_STEP; step = step + 1)
                        if (status[plane][step] != COMPLETE) $fatal(1, "incomplete status set");
                end
            end
            $display("PASS: %0dx%0d timing harness completed all coordinates through step %0d", WIDTH, HEIGHT, TARGET_STEP);
            $display("cycles_per_step=%0f x_stalls=%0d z_stalls=%0d x_corrections=%0d z_corrections=%0d",
                (cycles-warmup)*1.0/(TARGET_STEP-8), stalls[0], stalls[1], corrections[0], corrections[1]);
            $finish;
        end
        if (cycles >= 500000) $fatal(1, "decoder progress timeout");
    end
endmodule
