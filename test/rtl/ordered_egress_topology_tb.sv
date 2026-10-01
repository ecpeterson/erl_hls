`timescale 1ns/1ps

// Public frames prove repeated self-delivery, source order across aliased
// outputs, and reset recovery. No generated internal signals are inspected.
module ordered_egress_topology_tb;
    localparam ROUNDS = 16;
    localparam FRAMES = 3*ROUNDS + 1;
    reg clk = 0, reset = 1, release_sink = 0;
    reg [31:0] flow = 32'h13579bdf;
    wire ready = release_sink && (flow[0] || flow[1]);
    wire [127:0] frame;
    wire valid;
    reg stalled = 0;
    reg [127:0] held;
    integer received = 0, stalled_cycles = 0, clocks = 0;
    integer expected;

    __ordered_egress_topology__Top_0_next dut (
        .clk(clk), .reset(reset), ._ordered_values_out_rdy(ready),
        ._ordered_values_out(frame), ._ordered_values_out_vld(valid)
    );
    always #5 clk = ~clk;
    always @(negedge clk) flow <= {flow[30:0], flow[31]^flow[21]^flow[1]^flow[0]};

    always @(posedge clk) begin
        clocks = clocks + 1;
        if (clocks > 20000) $fatal(1, "ordered topology progress timeout");
        if (reset) begin
            received = 0;
            stalled = 0;
        end else begin
            if ((^{valid, ready}) === 1'bx) $fatal(1, "unknown handshake");
            if (stalled && (!valid || frame !== held))
                $fatal(1, "ordered output changed under backpressure");
            stalled = valid && !ready;
            held = frame;
            if (stalled) stalled_cycles = stalled_cycles + 1;
            if (valid && ready) begin
                if (received >= FRAMES) $fatal(1, "unexpected output after completion");
                if (received == FRAMES-1) expected = 4*ROUNDS;
                else case (received % 3)
                    0: expected = 4*(received/3) + 3;
                    1: expected = 4*(received/3) + 1;
                    2: expected = 4*(received/3) + 2;
                endcase
                if (frame !== {32'h01000003, 64'b0, expected[31:0]})
                    $fatal(1, "frame %0d: expected value %0d, got %032h", received, expected, frame);
                received = received + 1;
            end
        end
    end

    task automatic restart;
        begin
            @(negedge clk); reset = 1; release_sink = 0;
            repeat (5) @(negedge clk);
            reset = 0;
            wait (valid);
            repeat (100) @(negedge clk);
        end
    endtask

    initial begin
        restart();
        // Discard a frame held at the sink, then reset again mid-stream.
        restart();
        release_sink = 1;
        wait (received >= 7);
        restart();
        release_sink = 1;
        wait (received == FRAMES);
        repeat (200) @(negedge clk);
        if (stalled_cycles < 300) $fatal(1, "insufficient stall coverage");
        $display("PASS: %0d self-send rounds, aliased source order, stalls and reset (%0d clocks)", ROUNDS, clocks);
        $finish;
    end
endmodule
