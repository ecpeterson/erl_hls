`timescale 1ns/1ps
module async_fifo_tb;
    parameter ADDR_BITS = 3;
    parameter WRITE_HALF = 3;
    parameter READ_HALF = 7;
    localparam CAPACITY = 1 << ADDR_BITS;
    reg wr_clk = 0, rd_clk = 0, reset = 0;
    reg pause_write = 0, pause_read = 0;
    always #WRITE_HALF if (!pause_write) wr_clk = !wr_clk;
    initial begin
        #1;
        forever #READ_HALF if (!pause_read) rd_clk = !rd_clk;
    end
    reg sending = 0, receiving = 0, randomized = 0;
    reg [36:0] in_data = 0;
    reg in_valid = 0, out_ready = 0;
    wire in_ready, out_valid;
    wire [36:0] out_data;
    integer written = 0, read_count = 0, epoch = 0, wraps = 0;
    reg [31:0] writer_rng = 32'h832ab07f, reader_rng = 32'h135f891b;
    reg [36:0] held;
    reg stalled = 0, writer_accepted = 0;
`ifdef MAPPED
    hls_async_fifo_mapped dut(.*);
`else
    hls_async_fifo #(.WIDTH(37), .ADDR_BITS(ADDR_BITS)) dut(.*);
`endif

    function [36:0] word(input integer n, input integer generation);
        // Distinct words include nontrivial TKEEP/TLAST, just like debug beats.
        word = {n[0], n[3:0] ^ 4'hb, generation[7:0], n[23:0]};
    endfunction
    function [31:0] next_rng(input [31:0] v);
        next_rng = {v[30:0], v[31] ^ v[21] ^ v[1] ^ v[0]};
    endfunction

    always @(negedge wr_clk) begin
        writer_rng <= next_rng(writer_rng);
        if (reset) in_valid = 0;
        else if (!in_valid || writer_accepted) begin
            in_valid = sending && (!randomized || writer_rng[1:0] != 0);
            in_data = word(written, epoch);
        end
    end
    always @(negedge rd_clk) begin
        reader_rng <= next_rng(reader_rng);
        out_ready = !reset && receiving && (!randomized || reader_rng[2:0] < 5);
    end
    always @(posedge wr_clk or posedge reset) begin
        writer_accepted = !reset && in_valid && in_ready;
        if (reset) written = 0;
        else if (in_valid && in_ready) begin
            if (in_data !== word(written, epoch)) $fatal(1, "test source changed a beat");
            written = written + 1;
        end
    end
    always @(posedge rd_clk or posedge reset) begin
        if (reset) begin read_count = 0; stalled = 0; end
        else begin
            if (out_valid === 1'bx) $fatal(1, "unknown valid");
            if (stalled && (!out_valid || out_data !== held))
                $fatal(1, "read data changed during backpressure");
            stalled = out_valid && !out_ready;
            held = out_data;
            if (out_valid && out_ready) begin
                if (out_data !== word(read_count, epoch))
                    $fatal(1, "order/epoch mismatch: got %h expected %h", out_data, word(read_count, epoch));
                read_count = read_count + 1;
            end
        end
    end

    task reset_pair;
        begin
            // Off either active edge, including when one clock is stopped.
            #2; reset = 1; epoch = epoch + 1;
            #2;
            if (in_ready || out_valid) $fatal(1, "reset did not quiesce both ports");
            #(4 * (WRITE_HALF + READ_HALF)); reset = 0;
        end
    endtask
    task drain;
        begin
            sending = 0; receiving = 1; randomized = 0;
            repeat (8 * CAPACITY + 20) @(negedge rd_clk);
            if (written != read_count || out_valid)
                $fatal(1, "drain mismatch %0d/%0d", read_count, written);
        end
    endtask
    initial begin
        reset_pair();
        // Exactly the advertised capacity is usable without a reader.
        sending = 1;
        repeat (CAPACITY + 20) @(negedge wr_clk);
        if (written != CAPACITY || in_ready) $fatal(1, "wrong FIFO capacity: %0d", written);
        repeat (20) @(negedge rd_clk);
        drain();
        randomized = 1; sending = 1;
        repeat (3000) @(negedge wr_clk);
        wraps = written / CAPACITY;
        if (wraps < 10) $fatal(1, "insufficient wraparound exercise");

        // A stopped reader must turn into bounded backpressure, then recover.
        @(negedge rd_clk); pause_read = 1;
        repeat (CAPACITY + 30) @(negedge wr_clk);
        if (in_ready) $fatal(1, "stopped reader did not backpressure writer");
        pause_read = 0;
        drain();
        // A stopped writer may leave an empty reader indefinitely.
        @(negedge wr_clk); pause_write = 1;
        repeat (30) @(negedge rd_clk);
        if (out_valid) $fatal(1, "stopped writer produced phantom data");
        pause_write = 0;

        sending = 1; receiving = 0;
        repeat (CAPACITY + 20) @(negedge wr_clk);
        @(negedge rd_clk); pause_read = 1;
        reset_pair();
        repeat (CAPACITY + 20) @(negedge wr_clk);
        if (out_valid) $fatal(1, "stopped domain released reset without a clock");
        pause_read = 0;
        drain();

        randomized = 1; sending = 1;
        repeat (200) @(negedge wr_clk);
        reset_pair();
        repeat (1000) @(negedge wr_clk);
        drain();
        $display("PASS: async FIFO depth=%0d clocks=%0d/%0d epochs=%0d wraps=%0d final=%0d words",
            CAPACITY, 2*WRITE_HALF, 2*READ_HALF, epoch, wraps, read_count);
        $finish;
    end
    initial begin #1000000; $fatal(1, "async FIFO timeout"); end
endmodule
