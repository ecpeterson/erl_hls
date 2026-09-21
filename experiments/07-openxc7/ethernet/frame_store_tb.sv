`timescale 1ns/1ps
// Focused admission races independent of the MAC: release during a dropped
// frame, length saturation, abort of a partial frame, and simultaneous pop/push.
module frame_store_tb;
    reg clk=0, rst=1, flush=0, abort_partial=0;
    always #4 clk=!clk;
    reg in_valid=0, in_last=0, in_error=0, out_ready=0;
    reg [7:0] in_data=0;
    wire in_ready, out_valid, out_last;
    wire [7:0] out_data;
    wire [1:0] queued;
    wire [31:0] accepted, dropped, overflowed, aborted;
    ethernet_frame_store #(.DROP_WHEN_FULL(1), .MIN_BYTES(1)) dut(.*);
    integer expect_length[0:15], expect_tag[0:15];
    integer expected=0, received=0, offset=0;
    always @(posedge clk) if (!rst && out_valid && out_ready) begin
        if (received>=expected || out_data !== ((offset+expect_tag[received]) & 8'hff) ||
            out_last !== (offset==expect_length[received]-1))
            $fatal(1,"store order/data/last mismatch frame=%0d offset=%0d data=%x",received,offset,out_data);
        if (out_last) begin received=received+1;offset=0;end
        else offset=offset+1;
    end

    // Register an expected frame before enabling its delivery.
    task expect_frame(input integer length, tag);
        begin expect_length[expected]=length; expect_tag[expected]=tag; expected=expected+1; end
    endtask

    // Deliver one byte, retaining it until the store's ready handshake.
    task byte_in(input integer data, input bit last, error);
        begin
            @(negedge clk);in_valid=1;in_data=data;in_last=last;in_error=error;
            @(posedge clk); if(!in_ready) $fatal(1,"RX input backpressured");
        end
    endtask

    // End a byte sequence without changing frame boundaries.
    task idle;
        begin @(negedge clk);in_valid=0;in_last=0;in_error=0;end
    endtask

    integer i;
    initial begin
        repeat(4) @(negedge clk);rst=0;
        expect_frame(1,11);byte_in(11,1,0);
        expect_frame(1,22);byte_in(22,1,0);idle();
        // Free both slots after the third frame was rejected at admission.
        for(i=0;i<80;i=i+1) begin
            byte_in(i,i==79,0);
            if(i==3) out_ready=1;
        end
        idle();repeat(10) @(negedge clk);
        if(received!=2 || accepted!=2 || dropped!=1 || overflowed!=1) $fatal(1,"late slot reuse accepted a tail");
        // An oversized frame must not wrap its length back into writable space.
        for(i=0;i<5000;i=i+1) byte_in(i,i==4999,0);
        idle();
        expect_frame(1,33);byte_in(33,1,0);idle();
        wait(received==3);
        if(dropped!=2) $fatal(1,"length saturation missing");
        // An early error is sticky even when the final byte is clean.
        byte_in(44,0,1);byte_in(45,1,0);idle();
        if(dropped!=3) $fatal(1,"early error lost");
        // Keep a complete frame stalled while aborting a different partial one.
        out_ready=0;
        expect_frame(1,55);byte_in(55,1,0);
        byte_in(66,0,0);idle();abort_partial=1;
        @(negedge clk);abort_partial=0;
        if(aborted!=1 || queued!=1) $fatal(1,"partial abort changed committed frame");
        // Its final output transfer and the next input commit coincide.
        expect_frame(1,77);
        @(negedge clk);out_ready=1;in_valid=1;in_data=77;in_last=1;
        @(posedge clk);
        if(!out_valid || !out_last || !in_ready) $fatal(1,"did not exercise simultaneous release/commit");
        idle();wait(received==5);
        repeat(4) @(negedge clk);
        if(queued!=0 || accepted!=5) $fatal(1,"simultaneous release/commit lost a slot");
        // Flush owns both queued frames and the unfinished input reservation.
        out_ready=0;byte_in(88,1,0);byte_in(99,0,0);idle();flush=1;
        @(negedge clk);flush=0;
        if(aborted!=3 || queued!=0 || out_valid) $fatal(1,"flush accounting");
        expect_frame(1,111);byte_in(111,1,0);idle();out_ready=1;
        wait(received==6);
        $display("PASS: frame admission races, saturation, sticky errors, abort and flush");
        $finish;
    end
    initial begin #100000; $fatal(1,"frame store timeout");end
endmodule
