`timescale 1ns/1ps

// Directed port witness; every compared memory location is explicitly written.
module hls_indexed_gather_ram_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg [1:0] rd_addr = 0;
    reg rd_en = 0;
    wire [31:0] rd_data;
    reg [1:0] wr_addr = 0;
    reg [31:0] wr_data = 0;
    reg [3:0] wr_mask = 0;
    reg wr_en = 0;
    reg output_known = 0;
    reg [31:0] held_data = 0;
    integer checks = 0;

    hls_indexed_gather_ram #(
        .ELEMENT_BITS(8), .MEMBERS(4), .ADDRESS_WIDTH(2)
    ) dut (
        .clk(clk), .rd_addr(rd_addr), .rd_en(rd_en), .rd_data(rd_data),
        .wr_addr(wr_addr), .wr_data(wr_data), .wr_mask(wr_mask), .wr_en(wr_en)
    );

    // Requests cannot alter output before the next edge; disabled reads retain it.
    task step;
        input write_enable;
        input [1:0] write_address;
        input [31:0] write_data;
        input [3:0] write_mask;
        input read_enable;
        input [1:0] read_address;
        input [31:0] expected;
        begin
            @(negedge clk);
            wr_en = write_enable;
            wr_addr = write_address;
            wr_data = write_data;
            wr_mask = write_mask;
            rd_en = read_enable;
            rd_addr = read_address;
            #1;
            if (output_known && rd_data !== held_data)
                $fatal(1, "read changed before its acceptance edge");
            @(posedge clk);
            #1;
            if (read_enable) begin
                if (rd_data !== expected)
                    $fatal(1, "read %0d: got %08x expected %08x", read_address, rd_data, expected);
                output_known = 1;
                held_data = expected;
            end else if (output_known && rd_data !== held_data) begin
                $fatal(1, "disabled read changed its held result");
            end
            checks = checks + 1;
        end
    endtask

    // Exercise independent ports, zero/single/sparse masks and read-first collision.
    initial begin
        step(1, 0, 32'h44332211, 4'b1111, 0, 0, 0);
        step(1, 1, 32'h88776655, 4'b1111, 0, 0, 0);
        step(1, 2, 32'hccbbaa99, 4'b1111, 0, 0, 0);
        step(1, 3, 32'hfedcba98, 4'b1111, 0, 0, 0);
        step(0, 0, 0, 0, 1, 0, 32'h44332211);
        step(1, 0, 32'hffffffff, 4'b0000, 1, 0, 32'h44332211);
        step(0, 0, 0, 0, 1, 0, 32'h44332211);
        step(1, 0, 32'h00ee0000, 4'b0100, 1, 1, 32'h88776655);
        step(0, 0, 0, 0, 1, 0, 32'h44ee2211);
        step(1, 0, 32'hdd0000aa, 4'b1001, 1, 2, 32'hccbbaa99);
        step(0, 0, 0, 0, 1, 0, 32'hddee22aa);
        step(1, 0, 32'h0000bb00, 4'b0010, 1, 0, 32'hddee22aa);
        step(0, 0, 0, 0, 1, 0, 32'hddeebbaa);
        step(0, 0, 32'h00000000, 4'b1111, 1, 0, 32'hddeebbaa);
        step(1, 1, 32'h01020304, 4'b1111, 0, 1, 0);
        step(0, 0, 0, 0, 1, 1, 32'h01020304);
        step(0, 0, 0, 0, 1, 3, 32'hfedcba98);
        $display("PASS: indexed gather RAM %0d directed cycles", checks);
        $finish;
    end
endmodule
