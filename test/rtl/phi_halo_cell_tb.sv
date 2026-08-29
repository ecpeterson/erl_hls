`timescale 1ns/1ps

module phi_halo_cell_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;

    reg [31:0] input_data = 32'b0;
    reg input_last = 1'b0;
    reg input_valid = 1'b0;
    wire input_ready;

    wire [32:0] output_beat;
    wire output_valid;
    reg output_ready = 1'b0;

    reg [31:0] observed_word;

    __phi_halo_cell__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_halo_cell__ext_recv({input_last, input_data}),
        .phi_halo_cell__ext_recv_vld(input_valid),
        .phi_halo_cell__ext_send_rdy(output_ready),
        .phi_halo_cell__ext_recv_rdy(input_ready),
        .phi_halo_cell__ext_send(output_beat),
        .phi_halo_cell__ext_send_vld(output_valid)
    );

    always #5 clk = ~clk;

    function automatic [31:0] header;
        input [7:0] tag;
        input [7:0] txid;
        input [7:0] payload_words;
        begin
            header = {tag, 8'h00, txid, payload_words};
        end
    endfunction

    task automatic send_beat;
        input [31:0] word;
        input last;
        begin
            @(negedge clk);
            input_data = word;
            input_last = last;
            input_valid = 1'b1;
            while (!input_ready)
                @(posedge clk);
            @(negedge clk);
            input_data = 32'b0;
            input_last = 1'b0;
            input_valid = 1'b0;
        end
    endtask

    task automatic send_halo;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            send_beat(header(8'd3, 8'h00, 8'd3), 1'b0);
            send_beat(epoch, 1'b0);
            // Fixed arrays cast element zero into the most-significant bits,
            // so the least-significant-word-first wire order is reversed.
            send_beat(layer_one, 1'b0);
            send_beat(layer_zero, 1'b1);
        end
    endtask

    task automatic expect_beat;
        input [31:0] expected_word;
        input expected_last;
        begin : wait_for_beat
            @(negedge clk);
            output_ready = 1'b1;
            forever begin
                @(posedge clk);
                if (output_valid && output_ready) begin
                    observed_word = output_beat[31:0];
                    if (observed_word !== expected_word) begin
                        $display("FAIL: expected %08x, got %08x",
                                 expected_word, observed_word);
                        $fatal(1);
                    end
                    if (output_beat[32] !== expected_last) begin
                        $display("FAIL: TLAST mismatch for %08x", observed_word);
                        $fatal(1);
                    end
                    disable wait_for_beat;
                end
            end
        end
    endtask

    task automatic expect_halo;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            expect_beat(header(8'd3, 8'h00, 8'd3), 1'b0);
            expect_beat(epoch, 1'b0);
            expect_beat(layer_one, 1'b0);
            expect_beat(layer_zero, 1'b1);
            @(negedge clk);
            output_ready = 1'b0;
        end
    endtask

    initial begin : watchdog
        #3000000;
        $display("FAIL: phi halo simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Every cell seeds the mesh; no coordinator sends a diffuse request.
        // Until that boot output commits, Service has not reserved an input
        // slot and ReservedRx must not accept even the first beat of a frame.
        repeat (3) @(posedge clk);
        if (input_ready !== 1'b0) begin
            $display("FAIL: input became ready without mailbox credit");
            $fatal(1);
        end
        expect_halo(32'd0, 32'd0, 32'd0);

        send_halo(32'd0, 32'd32, 32'd48);
        send_halo(32'd0, 32'd64, 32'd80);
        send_halo(32'd0, 32'd16, 32'd32);
        send_halo(32'd0, 32'd48, 32'd64);
        expect_halo(32'd1, 32'd15, 32'd14);

        // Four epoch-2 messages arrive around epoch-1 messages. They are
        // retained while younger current input completes the first join, then
        // replayed after the outer phase toggles.
        send_halo(32'd1, 32'd16, 32'd32);
        send_halo(32'd2, 32'd0, 32'd0);
        send_halo(32'd1, 32'd16, 32'd32);
        send_halo(32'd2, 32'd0, 32'd0);
        send_halo(32'd1, 32'd16, 32'd32);
        send_halo(32'd2, 32'd0, 32'd0);
        send_halo(32'd2, 32'd0, 32'd0);
        send_halo(32'd1, 32'd16, 32'd32);

        expect_halo(32'd2, 32'd20, 32'd18);
        expect_halo(32'd3, 32'd19, 32'd13);

        $display("PASS: autonomous phi mailbox RTL behavior");
        $finish;
    end
endmodule
