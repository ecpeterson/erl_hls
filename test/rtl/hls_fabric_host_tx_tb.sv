`timescale 1ns/1ps

module hls_fabric_host_tx_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [143:0] frame_in = 144'b0;
    reg frame_in_valid = 1'b0;
    wire frame_in_ready;
    wire [32:0] routed_out;
    wire routed_out_valid;
    reg routed_out_ready = 1'b1;

    integer output_index = 0;
    integer cycle = 0;
    integer stall_cycles = 0;
    reg output_started = 1'b0;
    reg stall_started = 1'b0;
    reg stalled_last;
    reg [31:0] stalled_word;

    __hls_fabric_router__HostRoutedTx_0_next dut (
        .clk(clk),
        .reset(reset),
        ._frame_in(frame_in),
        ._frame_in_vld(frame_in_valid),
        ._frame_in_rdy(frame_in_ready),
        ._routed_out(routed_out),
        ._routed_out_vld(routed_out_valid),
        ._routed_out_rdy(routed_out_ready)
    );

    always #5 clk = ~clk;

    function automatic [31:0] expected_word(input integer index);
        case (index)
            0: expected_word = 32'h1234_0000;
            1: expected_word = 32'ha5_01_02_03;
            2: expected_word = 32'h1111_1111;
            3: expected_word = 32'h2222_2222;
            4: expected_word = 32'h3333_3333;
            5: expected_word = 32'h5678_0000;
            6: expected_word = 32'hb6_01_04_03;
            7: expected_word = 32'h4444_4444;
            8: expected_word = 32'h5555_5555;
            default: expected_word = 32'h6666_6666;
        endcase
    endfunction

    task automatic drive_until_accepted(input [143:0] value);
        begin
            @(negedge clk);
            frame_in = value;
            frame_in_valid = 1'b1;
            @(posedge clk);
            while (!frame_in_ready) @(posedge clk);
        end
    endtask

    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (!reset && output_started && output_index < 10 &&
                routed_out_ready && !routed_out_valid) begin
            $fatal(1, "bubble at output index %0d, cycle %0d",
                output_index, cycle);
        end
        if (!reset && routed_out_valid && !routed_out_ready) begin
            if (stall_cycles > 0 &&
                    (routed_out[31:0] !== stalled_word ||
                     routed_out[32] !== stalled_last)) begin
                $fatal(1, "output changed under backpressure");
            end
            stalled_word <= routed_out[31:0];
            stalled_last <= routed_out[32];
            stall_cycles <= stall_cycles + 1;
        end
        if (!reset && routed_out_valid && routed_out_ready) begin
            output_started <= 1'b1;
            if (routed_out[31:0] !== expected_word(output_index)) begin
                $fatal(1, "word %0d: got %08x expected %08x",
                    output_index, routed_out[31:0],
                    expected_word(output_index));
            end
            if (routed_out[32] !== (output_index == 4 || output_index == 9)) begin
                $fatal(1, "TLAST mismatch at output index %0d", output_index);
            end
            output_index <= output_index + 1;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        fork
            begin
                // Generated channel ports flatten Header in declaration order:
                // payload_words, txid, flags, op. RoutedTx emits wire order.
                drive_until_accepted({16'h1234, 32'h03_02_01_a5,
                    96'h3333_3333_2222_2222_1111_1111});
                drive_until_accepted({16'h5678, 32'h03_04_01_b6,
                    96'h6666_6666_5555_5555_4444_4444});
                @(negedge clk);
                frame_in_valid = 1'b0;
            end
            begin
                wait (output_index == 2);
                @(negedge clk);
                routed_out_ready = 1'b0;
                repeat (3) @(negedge clk);
                routed_out_ready = 1'b1;
                stall_started = 1'b1;
            end
        join

        wait (output_index == 10);
        @(posedge clk);
        if (!stall_started || stall_cycles < 2) begin
            $fatal(1, "backpressure interval was not exercised");
        end
        $display("PASS hls_fabric_host_tx");
        $finish;
    end

    initial begin
        repeat (200) @(posedge clk);
        $fatal(1, "timeout after %0d outputs", output_index);
    end
endmodule
