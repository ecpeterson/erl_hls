`timescale 1ns/1ps

module xls_trace_store_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [133:0] write_request = 134'd0;
    reg write_request_valid = 1'b0;
    wire write_request_ready;
    reg [6:0] read_request = 7'd0;
    reg read_request_valid = 1'b0;
    wire read_request_ready;
    wire [63:0] read_response;
    wire read_response_valid;
    reg read_response_ready = 1'b1;

    xls_trace_store dut (
        .clk(clk),
        .reset(reset),
        .write_request(write_request),
        .write_request_valid(write_request_valid),
        .write_request_ready(write_request_ready),
        .read_request(read_request),
        .read_request_valid(read_request_valid),
        .read_request_ready(read_request_ready),
        .read_response(read_response),
        .read_response_valid(read_response_valid),
        .read_response_ready(read_response_ready)
    );

    always #5 clk = ~clk;

    task automatic write_row;
        input [5:0] address;
        input [127:0] data;
        begin
            @(negedge clk);
            if (!write_request_ready) begin
                $display("FAIL: trace writes must always be ready");
                $fatal(1);
            end
            write_request = {address, data};
            write_request_valid = 1'b1;
            @(negedge clk);
            write_request_valid = 1'b0;
        end
    endtask

    task automatic read_event;
        input [5:0] address;
        input high;
        input [63:0] expected;
        begin
            @(negedge clk);
            while (!read_request_ready)
                @(negedge clk);
            read_request = {address, high};
            read_request_valid = 1'b1;
            @(negedge clk);
            read_request_valid = 1'b0;
            while (!read_response_valid)
                @(posedge clk);
            if (read_response !== expected) begin
                $display("FAIL: trace RAM[%0d].%0d expected %016x, got %016x",
                         address, high, expected, read_response);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        write_row(6'd3, 128'h00112233445566778899aabbccddeeff);
        read_event(6'd3, 1'b0, 64'h8899aabbccddeeff);
        read_event(6'd3, 1'b1, 64'h0011223344556677);

        // A frozen bank may be read while Observer writes the same row number
        // in the other logical bank.
        @(negedge clk);
        read_request = {6'd3, 1'b0};
        read_request_valid = 1'b1;
        write_request = {
            6'd35,
            128'hffeeddccbbaa99887766554433221100
        };
        write_request_valid = 1'b1;
        @(negedge clk);
        read_request_valid = 1'b0;
        write_request_valid = 1'b0;
        while (!read_response_valid)
            @(posedge clk);
        if (read_response !== 64'h8899aabbccddeeff) begin
            $display("FAIL: concurrent trace-bank read returned %016x",
                     read_response);
            $fatal(1);
        end

        // The response slot, not the writer, carries debug backpressure.
        read_response_ready = 1'b0;
        write_row(6'd36, 128'h0123456789abcdeffedcba9876543210);
        repeat (3) begin
            @(posedge clk);
            if (!read_response_valid ||
                    read_response !== 64'h8899aabbccddeeff ||
                    read_request_ready ||
                    !write_request_ready) begin
                $display("FAIL: trace read response was not held stable");
                $fatal(1);
            end
        end
        read_response_ready = 1'b1;
        @(posedge clk);

        read_event(6'd35, 1'b1, 64'hffeeddccbbaa9988);
        read_event(6'd36, 1'b0, 64'hfedcba9876543210);
        $display("PASS: inferred 1R1W trace store");
        $finish;
    end
endmodule
