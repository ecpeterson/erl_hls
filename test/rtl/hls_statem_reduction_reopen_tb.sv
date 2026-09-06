`timescale 1ns/1ps

module hls_statem_reduction_reopen_tb;
    localparam integer DATA_LSB = 16;
    localparam integer DATA_BITS = 128;
    localparam integer REDUCTION_LSB = 146;
    localparam integer REDUCTION_BITS = 117;
    localparam [DATA_BITS-1:0] ORIGINAL_DATA = {
        32'h44444444,
        32'h33333333,
        32'h22222222,
        32'h11111111
    };
    localparam [REDUCTION_BITS-1:0] ORIGINAL_REDUCTION = {
        32'd1,          // accumulator.contributions
        32'h11223344,  // accumulator.value
        3'd0,          // seen
        8'd1,          // remaining
        32'ha5a51234,  // key
        8'd0,          // COUNTING site
        2'd1           // OPEN status
    };

    reg clk = 1'b0;
    reg reset = 1'b1;

    wire [262:0] result_machine;
    wire result_valid;
    reg result_ready = 1'b1;

    __hls_statem_reduction_reopen_top__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        ._result_out_rdy(result_ready),
        ._result_out(result_machine),
        ._result_out_vld(result_valid)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        while (!result_valid)
            @(posedge clk);
        @(negedge clk);

        if (result_machine[145] !== 1'b1) begin
            $display("FAIL: second open did not fail the shared machine");
            $fatal(1);
        end
        if (result_machine[DATA_LSB +: DATA_BITS] !== ORIGINAL_DATA) begin
            $display("FAIL: second open overwrote the original actor data");
            $display(" expected data %h", ORIGINAL_DATA);
            $display("      got data %h",
                result_machine[DATA_LSB +: DATA_BITS]);
            $fatal(1);
        end
        if (result_machine[REDUCTION_LSB +: REDUCTION_BITS] !==
                ORIGINAL_REDUCTION) begin
            $display("FAIL: second open overwrote the original reduction");
            $display(" expected reduction %h", ORIGINAL_REDUCTION);
            $display("      got reduction %h",
                result_machine[REDUCTION_LSB +: REDUCTION_BITS]);
            $fatal(1);
        end

        $display(
            "PASS: failed second open preserved actor and reduction state"
        );
        $finish;
    end
endmodule
