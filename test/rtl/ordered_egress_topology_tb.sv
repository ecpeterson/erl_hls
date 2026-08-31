`timescale 1ns/1ps

module ordered_egress_topology_tb;
    localparam [7:0] ORDERED_VALUE_TAG = 8'd3;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg ordered_values_ready = 1'b0;
    wire [127:0] ordered_values;
    wire ordered_values_valid;

    reg [127:0] captured [0:2];
    reg [127:0] stalled_value;
    integer captured_count = 0;
    integer cycle;

    __ordered_egress_topology__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .ordered_egress_topology__ordered_values_out_rdy(
            ordered_values_ready
        ),
        .ordered_egress_topology__ordered_values_out(ordered_values),
        .ordered_egress_topology__ordered_values_out_vld(
            ordered_values_valid
        )
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!reset && ordered_values_valid && ordered_values_ready) begin
            if (captured_count >= 3) begin
                $display("FAIL: ordered egress emitted an unexpected value");
                $fatal(1);
            end else begin
                captured[captured_count] <= ordered_values;
                captured_count <= captured_count + 1;
            end
        end
    end

    task automatic wait_for_valid;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && !ordered_values_valid;
                    cycle = cycle + 1)
                @(posedge clk);
            if (!ordered_values_valid) begin
                $display("FAIL: ordered egress never became valid");
                $fatal(1);
            end
        end
    endtask

    task automatic wait_for_count;
        input integer target;
        input integer timeout_cycles;
        begin
            for (cycle = 0;
                    cycle < timeout_cycles && captured_count < target;
                    cycle = cycle + 1)
                @(posedge clk);
            if (captured_count < target) begin
                $display("FAIL: expected %0d ordered values, got %0d",
                    target, captured_count);
                $fatal(1);
            end
            @(negedge clk);
        end
    endtask

    task automatic check_value;
        input integer index;
        input [31:0] expected;
        reg [31:0] header;
        begin
            header = captured[index][127:96];
            if (header[7:0] !== ORDERED_VALUE_TAG ||
                    header[31:24] !== 8'd1) begin
                $display("FAIL: ordered value %0d has header %08x",
                    index, header);
                $fatal(1);
            end
            if (captured[index][31:0] !== expected) begin
                $display("FAIL: ordered value %0d expected %0d, got %0d",
                    index, expected, captured[index][31:0]);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        wait_for_valid(1000);
        stalled_value = ordered_values;
        repeat (100) begin
            @(posedge clk);
            if (!ordered_values_valid || ordered_values !== stalled_value) begin
                $display("FAIL: ordered output changed under backpressure");
                $fatal(1);
            end
        end

        @(negedge clk);
        ordered_values_ready = 1'b1;
        wait_for_count(3, 1000);
        check_value(0, 32'd3);
        check_value(1, 32'd1);
        check_value(2, 32'd2);

        $display("PASS: aliased actor egress preserves source order");
        $finish;
    end
endmodule
