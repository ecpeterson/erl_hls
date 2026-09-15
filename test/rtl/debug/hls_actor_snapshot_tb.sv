`timescale 1ns/1ps
// A register-array reference checks the externally observed semantics across
// memory geometries, including simultaneous read/write and reset after reuse.
module snapshot_case #(parameter SLOTS=3, MAILBOX=1, REDUCTION_WIDTH=0)(output reg done=0);
    localparam AW = SLOTS < 2 ? 1 : $clog2(SLOTS);
    reg clk=0, reset=1, write_enable=0;
    reg [AW-1:0] write_address=0, read_address=0;
    reg [24+REDUCTION_WIDTH:0] write_value=0;
    wire [127:0] value;
    reg [127:0] captured;
    reg mailbox_valid=0;
    reg [SLOTS*24-1:0] mailbox_values=0;
    reg [23:0] expected_mailbox[0:SLOTS-1];
    reg [25+REDUCTION_WIDTH:0] expected[0:SLOTS-1];
    reg [127:0] before_write;
    integer i, n;
    always #5 clk=~clk;
    hls_actor_snapshot #(.SLOTS(SLOTS), .ADDRESS_WIDTH(AW), .MAILBOX(MAILBOX), .REDUCTION_WIDTH(REDUCTION_WIDTH)) dut (.*);
    // The real query controller captures on this same edge, without forwarding.
    always @(posedge clk) captured <= value;
    function [127:0] reference_value(input integer address);
        if (address >= SLOTS) reference_value = 0;
        else begin
            reference_value = {72'b0, (MAILBOX ? expected_mailbox[address] : 24'b0),
                                6'b0, expected[address][25:0]};
            reference_value = reference_value | ((128'(expected[address]) >> 26) << 56);
        end
    endfunction
    initial begin
        for(n=0; n<4096; n=n+1) begin
            @(negedge clk);
            reset = n == 0 || n == 2052; // Coincides with valid writes and mailbox publication.
            write_enable = n%5 != 0;
            mailbox_valid = n%3 == 0;
            for(i=0; i<SLOTS; i=i+1)
                mailbox_values[i*24+:24] = (n*65537) ^ (i*7919);
            write_address = n;
            // Collisions, independent reads, and unused non-power-of-two rows.
            read_address = n%3 == 0 ? write_address : n/3;
            write_value = (128'(n * 65537) << 60) ^ (128'(n * 7919) << 24) ^ n;
            #1; before_write = reference_value(read_address);
            @(posedge clk);
            for(i=0; i<SLOTS; i=i+1) begin
                if(reset) begin expected[i]=0; expected_mailbox[i]=0; end
                else begin
                    if(write_enable && write_address==i) expected[i]=(128'(write_value) >> 25 << 26) | (1 << 25) | (write_value & 25'h1ffffff);
                    if(mailbox_valid) expected_mailbox[i]=mailbox_values[i*24+:24];
                end
            end
            #1;
            if(n != 0 && captured !== before_write)
                $fatal(1,"pre-write query SLOTS=%0d MAILBOX=%0d cycle=%0d",SLOTS,MAILBOX,n);
            if(value !== reference_value(read_address))
                $fatal(1,"updated snapshot SLOTS=%0d MAILBOX=%0d cycle=%0d",SLOTS,MAILBOX,n);
            // A different asynchronous read must not need another clock edge.
            read_address = read_address + 1'b1;
            #1;
            if(value !== reference_value(read_address)) $fatal(1,"asynchronous selection");
        end
        done=1;
    end
endmodule

module hls_actor_snapshot_tb;
    wire [5:0] done;
    snapshot_case #(.SLOTS(1), .MAILBOX(0)) a(done[0]);
    snapshot_case #(.SLOTS(1), .MAILBOX(1)) b(done[1]);
    snapshot_case #(.SLOTS(3), .MAILBOX(0), .REDUCTION_WIDTH(53)) c(done[2]);
    snapshot_case #(.SLOTS(9), .MAILBOX(1), .REDUCTION_WIDTH(66)) d(done[3]);
    snapshot_case #(.SLOTS(32), .MAILBOX(0)) e(done[4]);
    snapshot_case #(.SLOTS(65), .MAILBOX(1), .REDUCTION_WIDTH(59)) f(done[5]);
    initial begin
        wait(&done);
        $display("PASS: committed writes, asynchronous queries, collisions, invalid rows and reset across six bank geometries");
        $finish;
    end
endmodule
