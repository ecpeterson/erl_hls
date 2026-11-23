module memory_export_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, request_valid=0, write_enable=0, read_enable=0;
    reg [3:0] write_address=0, read_address=0;
    reg [31:0] write_data=0;
    reg [3:0] byte_enable=15;
    wire request_ready;
    wire [31:0] first, second, lookup, masked;
    wire ready_observed;
    wire [31:0] first_observed, second_observed, lookup_observed, masked_observed;
    memory_export_fixture original (.*);
    observed instrumented (.clk(clk), .reset(reset), .request_valid(request_valid),
        .request_ready(ready_observed), .write_enable(write_enable), .read_enable(read_enable),
        .write_address(write_address), .read_address(read_address), .write_data(write_data),
        .byte_enable(byte_enable), .masked(masked_observed),
        .first(first_observed), .second(second_observed), .lookup(lookup_observed),
        .hls_probe_values());
    reg [31:0] expected [0:15];
    reg [31:0] expected_masked [0:15];
    reg [31:0] held=0, held_masked=0, random_bits=32'h8ae9123f;
    integer cycle, index, lane;
    initial begin
        repeat(3) @(negedge clk);
        reset=0; request_valid=1;
        // Verify that initialized data survives without a preceding write.
        for (index=0; index<16; index=index+1) begin
            read_address=index; #1;
            if (lookup !== (index+16)*17 || lookup_observed !== lookup)
                $fatal(1,"lost table initialization at %0d", index);
        end
        @(negedge clk); write_enable=1;
        for (index=0; index<16; index=index+1) begin
            write_address=index; write_data=32'h12340000+index; expected[index]=write_data;
            expected_masked[index]=write_data;
            @(negedge clk);
        end
        // Include same-address reads/writes, disabled ports and requests, and
        // reset while memory contains live data. Read-before-write is promised.
        for (cycle=0; cycle<1024; cycle=cycle+1) begin
            random_bits={random_bits[30:0],random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
            reset=(cycle%97==0); request_valid=(cycle%7!=0);
            write_enable=(cycle%3!=0); read_enable=(cycle%5!=0);
            read_address=random_bits[3:0];
            write_address=(cycle%2==0) ? read_address : random_bits[7:4];
            write_data=random_bits;
            byte_enable=random_bits[11:8];
            if (!reset && request_valid && read_enable) begin
                held=expected[read_address]; held_masked=expected_masked[read_address];
            end
            if (!reset && request_valid && write_enable) begin
                expected[write_address]=write_data;
                for (lane=0; lane<4; lane=lane+1)
                    if (byte_enable[lane]) expected_masked[write_address][8*lane+:8]=write_data[8*lane+:8];
            end
            @(posedge clk); #1;
            if ({request_ready,first,second,lookup,masked} !==
                {ready_observed,first_observed,second_observed,lookup_observed,masked_observed})
                $fatal(1,"export changed memory behavior at cycle %0d",cycle);
            // Before the first read, the block RAM outputs are unspecified.
            if (cycle>1 && (first !== held || second !== ~held || masked !== held_masked || lookup !== expected[read_address]))
                $fatal(1,"memory contract changed at cycle %0d",cycle);
            @(negedge clk);
        end
        $display("PASS: memory export preserves initialization, collisions, enables and reset behavior");
        $finish;
    end
endmodule
