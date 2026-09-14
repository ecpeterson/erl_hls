`timescale 1ns/1ps

// Both designs see the same reset and sink readiness. Compare public events,
// including payloads held across stalls; no private scheduler signals are read.
module phi_compare_tb;
    reg clock = 0;
    always #5 clock = ~clock;
    integer cycle = 0;
    reg [31:0] flow = 32'h13579bdf;
    wire resetn = cycle >= 4 && !(cycle >= 6000 && cycle < 6004);
    wire x_ready = (flow[0] | flow[1]) && !(cycle >= 500 && cycle < 1800);
    wire z_ready = (flow[2] | flow[3]) && !(cycle >= 2500 && cycle < 4000);
    wire [127:0] bx, bz, cx, cz;
    wire bx_valid, bz_valid, cx_valid, cz_valid;
    integer x_frames = 0, z_frames = 0, x_after_reset = 0, z_after_reset = 0;
    integer x_stalls = 0, z_stalls = 0;

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
            if (bx_valid !== cx_valid || bz_valid !== cz_valid ||
                (bx_valid && bx !== cx) || (bz_valid && bz !== cz))
                $fatal(1, "public output mismatch at cycle %0d", cycle);
            if (bx_valid && !x_ready) x_stalls = x_stalls + 1;
            if (bz_valid && !z_ready) z_stalls = z_stalls + 1;
            if (bx_valid && x_ready) begin
                x_frames = x_frames + 1;
                if (cycle > 6004) x_after_reset = x_after_reset + 1;
            end
            if (bz_valid && z_ready) begin
                z_frames = z_frames + 1;
                if (cycle > 6004) z_after_reset = z_after_reset + 1;
            end
        end
        if (cycle == 12000) begin
            if (x_after_reset < 100 || z_after_reset < 100 || x_stalls < 1000 || z_stalls < 1000)
                $fatal(1, "insufficient stall or reset coverage");
            $display("PASS: cycle-exact D3 public outputs through 12000 cycles, long stalls and reset; X=%0d Z=%0d frames, X=%0d Z=%0d stalled cycles", x_frames, z_frames, x_stalls, z_stalls);
            $finish;
        end
    end
endmodule
