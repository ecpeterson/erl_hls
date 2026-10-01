`timescale 1ns/1ps
// First-word visibility must use both synchronizers, without a third flag clock.
module async_fifo_latency_tb;
    reg reset = 1, wr_clk = 0, rd_clk = 0;
    reg [36:0] in_data = 37'h1abcdef123;
    reg in_valid = 0, out_ready = 0;
    wire in_ready, out_valid;
    wire [36:0] out_data;
`ifdef MAPPED
    hls_async_fifo_mapped dut(.*);
`else
    hls_async_fifo #(.WIDTH(37), .ADDR_BITS(3)) dut(.*);
`endif
    // Advance independently, with observations after nonblocking updates settle.
    task write_edge;
        begin #3; wr_clk = 1; #3; wr_clk = 0; end
    endtask
    task read_edge;
        begin #5; rd_clk = 1; #5; rd_clk = 0; end
    endtask
    initial begin
        write_edge(); read_edge(); reset = 0;
        repeat (3) begin write_edge(); read_edge(); end
        if (!in_ready || out_valid) $fatal(1, "reset release failed");
        in_valid = 1; write_edge(); in_valid = 0;
        if (out_valid) $fatal(1, "write crossed without a read clock");
        read_edge();
        if (out_valid) $fatal(1, "write bypassed the second synchronizer");
        read_edge();
        if (!out_valid || out_data !== in_data) $fatal(1, "first word needs an extra flag clock");
        repeat (3) begin
            read_edge();
            if (!out_valid || out_data !== in_data) $fatal(1, "stalled word changed");
        end
        out_ready = 1; read_edge();
        if (out_valid) $fatal(1, "last word was duplicated");
        $display("PASS: async FIFO first word visible after two read clocks");
        $finish;
    end
    initial begin #10000; $fatal(1, "FIFO latency timeout"); end
endmodule
