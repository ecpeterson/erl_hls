module hls_actor_observation_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg request_valid = 0;
    wire request_ready, admission_valid;
    reg egress_ready = 0;
    wire [135:0] egress;
    wire egress_valid;
    wire [48:0] observation;
    wire observation_valid;
    reg [48:0] retained = 0;
    reg observed = 0;
    integer reports = 0;
    `include "actor_observation_expected.svh"

    debug_commit dut (
        .clk(clk), .reset(reset),
        ._request(REQUEST), ._request_vld(request_valid), ._request_rdy(request_ready),
        ._egress(egress), ._egress_vld(egress_valid), ._egress_rdy(egress_ready),
        ._admission(), ._admission_vld(admission_valid), ._admission_rdy(1'b1),
        ._actor_debug_out(observation), ._actor_debug_out_vld(observation_valid),
        ._actor_debug_out_rdy(1'b1)
    );

    always @(posedge clk) begin
        if (reset) begin
            retained <= 0;
            observed <= 0;
            reports <= 0;
        end else begin
            if (observation_valid) begin
                // The first publication is init's committed Machine, before
                // the initial boot entry clears enter_pending.
                if (!observed && observation !== {24'h800000, 25'h100})
                    $fatal(1, "first publication skipped initialized state: %h", observation);
                observed <= 1;
                retained <= observation;
            end
            if (egress_valid && egress_ready) begin
                if (egress !== (reports == 0 ? {8'd0, FIRST} : {8'd1, SECOND}))
                    $fatal(1, "unexpected output effect %0d: %h", reports, egress);
                reports <= reports + 1;
            end
        end
    end

    initial begin
        repeat (6) @(negedge clk);
        reset = 0;
        wait (admission_valid);
        @(negedge clk) request_valid = 1;
        do @(posedge clk); while (!request_ready);
        @(negedge clk) request_valid = 0;
        repeat (100) @(negedge clk);
        // The first registered egress holds its value, and the second effect
        // blocks this entry's retirement. Only incoming Machine is committed.
        if (!egress_valid || reports != 0 || retained !== {24'h800000, 25'h101})
            $fatal(1, "uncommitted entry completion observed while egress stalled: %h", retained);
        egress_ready = 1;
        repeat (100) @(negedge clk);
        if (reports != 2 || retained !== {24'h810000, 25'h1})
            $fatal(1, "entry did not retire after both effects: reports=%0d state=%h", reports, retained);
        $display("PASS: diagnostic state remains committed across a blocked output effect");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "actor observation timeout");
    end
endmodule
