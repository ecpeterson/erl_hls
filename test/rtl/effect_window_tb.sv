`timescale 1ns/1ps

module effect_window_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg [2:0] requests = 0;
    wire [2:0] request_ready;
    wire [2:0] grants, grant_valid;
    reg [2:0] grant_ready = 0;
    reg [2:0] releases = 0;
    wire [2:0] release_ready;

    __effect_window_rtl__ArbiterTop_0_next dut (
        .clk(clk), .reset(reset),
        ._requests__0(1'b1), ._requests__0_vld(requests[0]), ._requests__0_rdy(request_ready[0]),
        ._requests__1(1'b1), ._requests__1_vld(requests[1]), ._requests__1_rdy(request_ready[1]),
        ._requests__2(1'b1), ._requests__2_vld(requests[2]), ._requests__2_rdy(request_ready[2]),
        ._grants__0(grants[0]), ._grants__0_vld(grant_valid[0]), ._grants__0_rdy(grant_ready[0]),
        ._grants__1(grants[1]), ._grants__1_vld(grant_valid[1]), ._grants__1_rdy(grant_ready[1]),
        ._grants__2(grants[2]), ._grants__2_vld(grant_valid[2]), ._grants__2_rdy(grant_ready[2]),
        ._releases__0(1'b1), ._releases__0_vld(releases[0]), ._releases__0_rdy(release_ready[0]),
        ._releases__1(1'b1), ._releases__1_vld(releases[1]), ._releases__1_rdy(release_ready[1]),
        ._releases__2(1'b1), ._releases__2_vld(releases[2]), ._releases__2_rdy(release_ready[2])
    );

    localparam TARGET = 64;
    integer requested [0:2];
    integer granted [0:2];
    integer released [0:2];
    integer owner, hold_until, total_grants;
    integer cycle, client, epoch, completed_at;
    reg [2:0] blocked_grants;
    reg [31:0] rng;

    initial begin
        // Reset and replay with different stalls, including outstanding work
        // at the end of the first epoch, to check reset clears reservations.
        for (epoch = 0; epoch < 3; epoch = epoch + 1) begin
            @(negedge clk);
            reset = 1;
            requests = 0;
            releases = 0;
            grant_ready = 0;
            repeat (4) @(negedge clk);
            reset = 0;
            owner = -1;
            hold_until = 0;
            total_grants = 0;
            completed_at = -1;
            blocked_grants = 0;
            rng = 32'h93ac17e5 ^ epoch;
            for (client = 0; client < 3; client = client + 1) begin
                requested[client] = 0;
                granted[client] = 0;
                released[client] = 0;
            end
            for (cycle = 0; cycle < (epoch == 0 ? 180 : 12000); cycle = cycle + 1) begin
                @(negedge clk);
                rng = rng ^ (rng << 13);
                rng = rng ^ (rng >> 17);
                rng = rng ^ (rng << 5);
                for (client = 0; client < 3; client = client + 1) begin
                    requests[client] = (client == 1 || total_grants > 0) &&
                        requested[client] < TARGET &&
                        requested[client] == granted[client];
                    grant_ready[client] = cycle >= 64 &&
                        (epoch == 2 || rng[client] || rng[client + 8]);
                    releases[client] = owner == client && cycle >= hold_until;
                end
                @(posedge clk);
                if ((^{grant_valid, requests & request_ready, releases & release_ready}) === 1'bx)
                    $fatal(1, "unknown handshake control");
                if ((grant_valid & blocked_grants) !== blocked_grants)
                    $fatal(1, "grant valid dropped while blocked");
                blocked_grants = grant_valid & ~grant_ready;
                for (client = 0; client < 3; client = client + 1) begin
                    if (requests[client] && request_ready[client])
                        requested[client] = requested[client] + 1;
                    if (releases[client] && release_ready[client]) begin
                        if (owner != client) $fatal(1, "release without ownership");
                        owner = -1;
                        released[client] = released[client] + 1;
                    end
                end
                for (client = 0; client < 3; client = client + 1) begin
                    if (grant_valid[client] && grants[client] !== 1'b1)
                        $fatal(1, "invalid grant payload");
                    if (grant_valid[client] && grant_ready[client]) begin
                        if (owner != -1) $fatal(1, "two simultaneous owners");
                        if (requested[client] <= granted[client])
                            $fatal(1, "unsolicited or duplicate grant");
                        // Seed owner one, then queue all contenders while it
                        // holds ownership. This tests wraparound independently
                        // of when each pipeline stage captures its inputs.
                        if (total_grants < 3 && client != (total_grants + 1) % 3)
                            $fatal(1, "initial round-robin order violated");
                        owner = client;
                        hold_until = cycle + (total_grants < 3 ? 40 : 3 + rng[7:4]);
                        granted[client] = granted[client] + 1;
                        total_grants = total_grants + 1;
                    end
                end
                if (released[0] == TARGET && released[1] == TARGET && released[2] == TARGET) begin
                    if (completed_at == -1) completed_at = cycle;
                    if (cycle == completed_at + 32) begin
                        $display("PASS: epoch %0d, %0d grants, %0d cycles", epoch, total_grants, cycle);
                        cycle = 12000;
                    end
                end
            end
            if (epoch == 0 && (owner == -1 ||
                    requested[0] + requested[1] + requested[2] <= total_grants))
                $fatal(1, "reset fixture must leave an owner and pending requests");
            if (epoch != 0 && completed_at == -1)
                $fatal(1, "lost request, reservation leak, or starvation");
        end
        $finish;
    end
endmodule
