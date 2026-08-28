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
    reg output_ready = 1'b1;

    wire [359:0] committed_state;
    wire committed_state_valid;
    reg [31:0] observed_word;

    __phi_halo_cell__Top_0_next dut (
        .clk(clk),
        .reset(reset),
        .phi_halo_cell__ext_recv({input_last, input_data}),
        .phi_halo_cell__ext_recv_vld(input_valid),
        .phi_halo_cell__ext_send_rdy(output_ready),
        .phi_halo_cell__ext_state_rdy(1'b1),
        .phi_halo_cell__ext_recv_rdy(input_ready),
        .phi_halo_cell__ext_send(output_beat),
        .phi_halo_cell__ext_send_vld(output_valid),
        .phi_halo_cell__ext_state(committed_state),
        .phi_halo_cell__ext_state_vld(committed_state_valid)
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
        input [7:0] tag;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            send_beat(header(tag, 8'h00, 8'd3), 1'b0);
            send_beat(epoch, 1'b0);
            // DSLX array element zero occupies the most-significant bits, so
            // the least-significant-word-first AXIS format carries layer one
            // before layer zero.  The generated Erlang codec hides this.
            send_beat(layer_one, 1'b0);
            send_beat(layer_zero, 1'b1);
        end
    endtask

    task automatic send_zero_halos;
        input [31:0] epoch;
        begin
            send_halo(8'd3, epoch, 32'd0, 32'd0);
            send_halo(8'd4, epoch, 32'd0, 32'd0);
            send_halo(8'd5, epoch, 32'd0, 32'd0);
            send_halo(8'd6, epoch, 32'd0, 32'd0);
        end
    endtask

    task automatic send_diffuse;
        input [7:0] txid;
        input [31:0] epoch;
        input [31:0] charge;
        begin
            send_beat(header(8'd7, txid, 8'd2), 1'b0);
            send_beat(epoch, 1'b0);
            send_beat(charge, 1'b1);
        end
    endtask

    task automatic expect_beat;
        input [31:0] expected_word;
        input expected_last;
        begin : wait_for_beat
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

    task automatic expect_field;
        input [7:0] txid;
        input [31:0] epoch;
        input [31:0] layer_zero;
        input [31:0] layer_one;
        begin
            expect_beat(header(8'd8, txid, 8'd3), 1'b0);
            expect_beat(epoch, 1'b0);
            // See send_halo: fixed-size arrays use reverse wire order.
            expect_beat(layer_one, 1'b0);
            expect_beat(layer_zero, 1'b1);
        end
    endtask

    initial begin : watchdog
        #2000000;
        $display("FAIL: phi halo simulation timed out");
        $fatal(1);
    end

    initial begin : scenario
        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        send_zero_halos(32'd0);
        send_diffuse(8'h11, 32'd0, 32'h20000000);
        expect_field(8'h11, 32'd1, 32'h20000000, 32'd0);

        // Multiplication by ten overflows u32 before the right shift. This
        // distinguishes fixed-width DSLX arithmetic from BEAM bignums.
        send_zero_halos(32'd1);
        send_diffuse(8'h12, 32'd1, 32'd0);
        expect_field(8'h12, 32'd2, 32'h04000000, 32'h04000000);

        $display("PASS: phi halo generated RTL behavior");
        $finish;
    end
endmodule
