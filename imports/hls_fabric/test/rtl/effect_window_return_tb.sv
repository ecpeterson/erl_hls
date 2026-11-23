`timescale 1ns/1ps

module effect_window_return_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [1:0] ready = 0;
    wire [1:0] returned, valid;

    __effect_window_rtl__ReturnTop_0_next dut (
        .clk(clk), .reset(reset),
        ._returned_0(returned[0]), ._returned_0_vld(valid[0]), ._returned_0_rdy(ready[0]),
        ._returned_1(returned[1]), ._returned_1_vld(valid[1]), ._returned_1_rdy(ready[1])
    );

    integer cycle, client;
    integer count [0:1];
    reg [1:0] blocked;
    reg [31:0] rng = 32'h29b437cd;

    initial begin
        count[0] = 0;
        count[1] = 0;
        blocked = 0;
        repeat (4) @(negedge clk);
        reset = 0;
        for (cycle = 0; cycle < 8000; cycle = cycle + 1) begin
            @(negedge clk);
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
            // First block both observers, then block one while the other is
            // ready, then alternate random stalls and sustained readiness.
            ready[0] = cycle >= 160 && (cycle >= 1200 || rng[0]);
            ready[1] = cycle >= 80 && (cycle >= 1200 || rng[8]);
            @(posedge clk);
            if ((^valid) === 1'bx) $fatal(1, "unknown returned-grant validity");
            if ((valid & blocked) !== blocked)
                $fatal(1, "returned-grant observation lost under backpressure");
            blocked = valid & ~ready;
            for (client = 0; client < 2; client = client + 1) begin
                if (valid[client] && returned[client] !== 1'b1)
                    $fatal(1, "invalid returned-grant payload");
                if (valid[client] && ready[client]) count[client] = count[client] + 1;
            end
            if (cycle >= 1200 && count[0] >= 100 && count[1] >= 100) begin
                $display("PASS: immediate return/re-request clients made progress (%0d, %0d)", count[0], count[1]);
                $finish;
            end
        end
        $fatal(1, "immediate return/re-request deadlock or starvation");
    end
endmodule
