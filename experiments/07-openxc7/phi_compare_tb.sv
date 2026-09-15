`timescale 1ns/1ps

// Both designs see the same reset and sink readiness. Compare public events,
// including payloads held across stalls; no private scheduler signals are read.
module phi_compare_tb;
    parameter CYCLE_EXACT = 1;
    reg clock = 0;
    always #5 clock = ~clock;
    integer cycle = 0;
    reg [31:0] flow = 32'h13579bdf;
    wire resetn = cycle >= 4 && !(cycle >= 6000 && cycle < 6004);
    wire x_ready = (flow[0] | flow[1]) && !(cycle >= 500 && cycle < 1800);
    wire z_ready = (flow[2] | flow[3]) && !(cycle >= 2500 && cycle < 4000);
    wire [127:0] bx, bz, cx, cz;
    wire bx_valid, bz_valid, cx_valid, cz_valid;
    reg [127:0] events [0:1][0:17][0:255];
    reg [127:0] held [0:1][0:1];
    reg stalled [0:1][0:1];
    integer count [0:1][0:17];
    integer matched [0:17];
    integer total_matched [0:1];
    integer stall_cycles [0:1][0:1];
    integer variant, side, actor;

    task automatic sample;
        input integer variant, side;
        input [127:0] frame;
        input valid, ready;
        integer actor, x, y;
        begin
            if (stalled[variant][side] && (!valid || frame !== held[variant][side]))
                $fatal(1, "variant %0d plane %0d changed event across backpressure", variant, side);
            held[variant][side] = frame;
            stalled[variant][side] = valid && !ready;
            if (valid && !ready) stall_cycles[variant][side] = stall_cycles[variant][side] + 1;
            if (valid && ready) begin
                x = frame[47:32];
                y = frame[63:48];
                if (x >= 3 || y >= 3) $fatal(1, "out-of-range coordinate");
                actor = 9*side + 3*x + y;
                if (count[variant][actor] >= 256) $fatal(1, "comparison buffer exhausted");
                events[variant][actor][count[variant][actor]] = frame;
                count[variant][actor] = count[variant][actor] + 1;
            end
        end
    endtask

    initial begin
        total_matched[0] = 0;
        total_matched[1] = 0;
        for (variant = 0; variant < 2; variant = variant + 1)
            for (side = 0; side < 2; side = side + 1)
                stall_cycles[variant][side] = 0;
    end

    baseline_phi_decoder_profile_top baseline (
        .aclk(clock), .aresetn(resetn),
        .x_decoder_event(bx), .x_decoder_event_valid(bx_valid), .x_decoder_event_ready(x_ready),
        .z_decoder_event(bz), .z_decoder_event_valid(bz_valid), .z_decoder_event_ready(z_ready)
    );
    phi_decoder_profile_top candidate (
        .aclk(clock), .aresetn(resetn),
        .x_decoder_event(cx), .x_decoder_event_valid(cx_valid), .x_decoder_event_ready(x_ready),
        .z_decoder_event(cz), .z_decoder_event_valid(cz_valid), .z_decoder_event_ready(z_ready)
    );

    always @(posedge clock) begin
        cycle <= cycle + 1;
        flow <= {flow[30:0], flow[31] ^ flow[21] ^ flow[1] ^ flow[0]};
        if (resetn) begin
            if ((^{bx_valid, bz_valid, cx_valid, cz_valid}) === 1'bx)
                $fatal(1, "unknown handshake at cycle %0d", cycle);
            if ((bx_valid && (^bx) === 1'bx) || (bz_valid && (^bz) === 1'bx) ||
                (cx_valid && (^cx) === 1'bx) || (cz_valid && (^cz) === 1'bx))
                $fatal(1, "unknown payload at cycle %0d", cycle);
            if (CYCLE_EXACT && (bx_valid !== cx_valid || bz_valid !== cz_valid ||
                (bx_valid && bx !== cx) || (bz_valid && bz !== cz)))
                $fatal(1, "public output mismatch at cycle %0d", cycle);
            sample(0, 0, bx, bx_valid, x_ready);
            sample(0, 1, bz, bz_valid, z_ready);
            sample(1, 0, cx, cx_valid, x_ready);
            sample(1, 1, cz, cz_valid, z_ready);
            // Actors progress at each design's own pace; arbitration may reorder
            // different actors. Compare each actor's common event prefix, keeping
            // its correction/status order and payloads. Reset discards in-flight tails.
            for (actor = 0; actor < 18; actor = actor + 1) begin
                if (matched[actor] < count[0][actor] && matched[actor] < count[1][actor]) begin
                    if (events[0][actor][matched[actor]] !== events[1][actor][matched[actor]]) begin
                        $display("baseline=%032h candidate=%032h", events[0][actor][matched[actor]], events[1][actor][matched[actor]]);
                        $fatal(1, "actor %0d event %0d differs at cycle %0d", actor, matched[actor], cycle);
                    end
                    matched[actor] = matched[actor] + 1;
                    total_matched[actor/9] = total_matched[actor/9] + 1;
                end
            end
        end else begin
            for (actor = 0; actor < 18; actor = actor + 1) begin
                if (cycle == 6000 && matched[actor] < 8)
                    $fatal(1, "actor %0d has insufficient pre-reset coverage", actor);
                matched[actor] = 0;
                count[0][actor] = 0;
                count[1][actor] = 0;
            end
            for (variant = 0; variant < 2; variant = variant + 1)
                for (side = 0; side < 2; side = side + 1)
                    stalled[variant][side] = 0;
        end
        if (cycle == 12000) begin
            for (actor = 0; actor < 18; actor = actor + 1)
                if (matched[actor] < 8)
                    $fatal(1, "actor %0d has insufficient post-reset coverage", actor);
            for (variant = 0; variant < 2; variant = variant + 1)
                for (side = 0; side < 2; side = side + 1)
                    if (stall_cycles[variant][side] < 1000)
                        $fatal(1, "insufficient stall coverage");
            $display("PASS: D3 public outputs through 12000 cycles, long stalls and reset; cycle_exact=%0d X=%0d Z=%0d matched per-actor frames", CYCLE_EXACT, total_matched[0], total_matched[1]);
            $display("stalled cycles: baseline X=%0d Z=%0d; candidate X=%0d Z=%0d", stall_cycles[0][0], stall_cycles[0][1], stall_cycles[1][0], stall_cycles[1][1]);
            $finish;
        end
    end
endmodule
