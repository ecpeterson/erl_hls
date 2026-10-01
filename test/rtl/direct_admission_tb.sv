`timescale 1ns/1ps

// A host-side credit ledger drives only the Service's public channels. Loop
// effects return as requests; every request must own an accepted credit.
module direct_admission_tb;
    localparam ROUNDS = 16;
    reg clk = 0, reset = 1;
    reg [31:0] flow = 32'h2468ace1;
    integer clocks = 0, epoch_clocks = 0;
    wire admission_ready = epoch_clocks > 120 && (flow[0] || flow[1]);
    wire egress_ready = epoch_clocks > 40 &&
        !(epoch_clocks >= 300 && epoch_clocks < 380) && (flow[2] || flow[3]);
    wire admission, admission_valid, egress_valid, request_ready;
    wire [135:0] egress;
    reg request_valid = 0;
    reg [127:0] request = 0, pending_frame = 0;
    reg pending = 0, request_stalled = 0;
    reg egress_stalled = 0, admission_stalled = 0;
    reg [135:0] held_egress;
    integer credits = 0, requests = 0, effects = 0;
    integer credit_stalls = 0, effect_stalls = 0;
    integer expected_value, expected_port;
    reg complete = 0;

    direct_admission_service dut (
        .clk(clk), .reset(reset), ._req_in(request), ._req_in_vld(request_valid),
        ._req_in_rdy(request_ready), ._egress_out(egress),
        ._egress_out_vld(egress_valid), ._egress_out_rdy(egress_ready),
        ._admission_out(admission), ._admission_out_vld(admission_valid),
        ._admission_out_rdy(admission_ready)
    );
    always #5 clk = ~clk;
    always @(negedge clk) begin
        flow <= {flow[30:0], flow[31]^flow[21]^flow[1]^flow[0]};
        if (reset) begin request_valid = 0; request = 0; end
        else if (!request_stalled) begin
            request_valid = pending && credits > requests && (flow[4] || flow[5]);
            request = pending_frame;
        end
    end

    always @(posedge clk) begin
        clocks = clocks + 1;
        if (clocks > 20000) $fatal(1, "direct service progress timeout");
        if (reset) begin
            epoch_clocks = 0; credits = 0; requests = 0; effects = 0;
            pending = 0; request_stalled = 0; egress_stalled = 0;
            admission_stalled = 0; complete = 0;
        end else begin
            epoch_clocks = epoch_clocks + 1;
            if ((^{request_ready, admission_valid, egress_valid}) === 1'bx)
                $fatal(1, "unknown service handshake");
            if (egress_stalled && (!egress_valid || egress !== held_egress))
                $fatal(1, "effect changed across a stall");
            if (admission_stalled && !admission_valid)
                $fatal(1, "credit withdrawn across a stall");
            if (admission_valid && admission !== 1'b1) $fatal(1, "invalid credit word");
            egress_stalled = egress_valid && !egress_ready;
            admission_stalled = admission_valid && !admission_ready;
            request_stalled = request_valid && !request_ready;
            held_egress = egress;
            if (egress_stalled) effect_stalls = effect_stalls + 1;
            if (admission_stalled) credit_stalls = credit_stalls + 1;
            if (request_valid && request_ready) begin
                if (!pending || credits <= requests) $fatal(1, "unreserved request");
                requests = requests + 1;
                pending = 0;
            end
            if (admission_valid && admission_ready) credits = credits + 1;
            if (credits < requests || credits - requests > 1)
                $fatal(1, "one-slot mailbox overgranted: credits=%0d requests=%0d", credits, requests);
            if (egress_valid && egress_ready) begin
                if (effects > 4*ROUNDS) $fatal(1, "unexpected effect after completion");
                if (effects == 4*ROUNDS) begin
                    expected_port = 0; expected_value = 4*ROUNDS; complete = 1;
                end else case (effects % 4)
                    0: begin expected_port = 2; expected_value = 4*(effects/4) + 3; end
                    1: begin expected_port = 0; expected_value = 4*(effects/4) + 1; end
                    2: begin expected_port = 1; expected_value = 4*(effects/4) + 2; end
                    3: begin expected_port = 3; expected_value = effects/4 + 1; end
                endcase
                if (egress !== {expected_port[7:0], 32'h01000003, 64'b0, expected_value[31:0]})
                    $fatal(1, "effect %0d: expected port=%0d value=%0d, got %034h", effects, expected_port, expected_value, egress);
                if (expected_port == 3) begin
                    if (pending) $fatal(1, "second loop effect before first request consumed");
                    pending = 1;
                    pending_frame = egress[127:0];
                end
                effects = effects + 1;
            end
        end
    end

    task automatic restart;
        begin
            @(negedge clk); reset = 1;
            repeat (5) @(negedge clk);
            reset = 0;
        end
    endtask
    initial begin
        restart();
        // Reset while a granted reservation and its self-send are outstanding.
        wait (pending && credits > requests);
        restart();
        wait (requests >= 4);
        restart();
        wait (complete);
        repeat (200) @(negedge clk);
        if (requests != ROUNDS || effects != 4*ROUNDS+1 || pending)
            $fatal(1, "incomplete loop population");
        if (credit_stalls == 0 || effect_stalls == 0) $fatal(1, "unused backpressure");
        $display("PASS: direct service credit conservation, %0d requests/%0d credits, independent stalls and reset", requests, credits);
        $finish;
    end
endmodule
