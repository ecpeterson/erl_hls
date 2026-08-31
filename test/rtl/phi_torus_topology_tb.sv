`timescale 1ns/1ps

module phi_torus_topology_tb;
    localparam [7:0] PHENOM_REQUEST_TAG = 8'd7;
    localparam integer CELL_COUNT = 6;

    reg clk = 1'b0;
    reg reset = 1'b1;

    reg syndrome_ready = 1'b0;
    wire [127:0] syndrome_request;
    wire syndrome_valid;

    wire correction_ready = 1'b1;
    wire [127:0] correction;
    wire correction_valid;

    reg [127:0] captured [0:CELL_COUNT-1];
    reg [127:0] stalled_request;
    integer request_count = 0;
    integer cycle;
    integer index;

    __phi_torus_topology__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_torus_topology__syndrome_requests_out_rdy(syndrome_ready),
        .phi_torus_topology__syndrome_requests_out(syndrome_request),
        .phi_torus_topology__syndrome_requests_out_vld(syndrome_valid),
        .phi_torus_topology__corrections_out_rdy(correction_ready),
        .phi_torus_topology__corrections_out(correction),
        .phi_torus_topology__corrections_out_vld(correction_valid)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && syndrome_valid && syndrome_ready) begin
            if (request_count >= CELL_COUNT) begin
                $display("FAIL: torus emitted an unexpected request");
                $fatal(1);
            end
            captured[request_count] <= syndrome_request;
            request_count <= request_count + 1;
        end
        if (!reset && correction_valid && correction_ready) begin
            $display("FAIL: torus emitted a correction without a measurement");
            $fatal(1);
        end
    end

    task automatic wait_for_valid;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && !syndrome_valid;
                    cycle = cycle + 1)
                @(posedge clk);
            if (!syndrome_valid) begin
                $display("FAIL: timed out waiting for a torus request");
                $fatal(1);
            end
        end
    endtask

    task automatic wait_for_all_requests;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && request_count < CELL_COUNT;
                    cycle = cycle + 1)
                @(posedge clk);
            if (request_count < CELL_COUNT) begin
                $display(
                    "FAIL: expected %0d requests, received %0d",
                    CELL_COUNT,
                    request_count
                );
                $fatal(1);
            end
            @(negedge clk);
        end
    endtask

    task automatic check_request;
        input integer request_index;
        reg [31:0] header;
        begin
            header = captured[request_index][127:96];
            if (header[7:0] !== PHENOM_REQUEST_TAG ||
                    header[31:24] !== 8'd1) begin
                $display(
                    "FAIL: request %0d has malformed header %08x",
                    request_index,
                    header
                );
                $fatal(1);
            end
            if (captured[request_index][95:0] !== 96'd0) begin
                $display(
                    "FAIL: request %0d has nonzero step or padding",
                    request_index
                );
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Every family member begins by issuing one syndrome request. Hold the
        // scalar merge boundary stalled to exercise stable backpressure first.
        wait_for_valid(20000);
        stalled_request = syndrome_request;
        repeat (100) begin
            @(posedge clk);
            if (!syndrome_valid || syndrome_request !== stalled_request) begin
                $display("FAIL: stalled torus request was not stable");
                $fatal(1);
            end
        end

        @(negedge clk);
        syndrome_ready = 1'b1;
        wait_for_all_requests(20000);

        for (index = 0; index < CELL_COUNT; index = index + 1)
            check_request(index);

        repeat (100) @(posedge clk);
        if (request_count !== CELL_COUNT) begin
            $display("FAIL: torus duplicated an initial request");
            $fatal(1);
        end

        $display("PASS: compact 2x3 phi torus elaboration and merge");
        $finish;
    end
endmodule
