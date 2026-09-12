`timescale 1ns/1ps
module hls_actor_snapshot_tb;
    reg clk=0, reset=1, write_enable=0;
    reg [1:0] write_address=0;
    reg [24:0] write_value=0;
    wire [191:0] values;
    reg mailbox_valid=0; reg [71:0] mailbox_values=0;
    reg [23:0] expected_mailbox[0:2];
    reg [25:0] expected [0:2];
    integer i, n;
    always #5 clk=~clk;
    hls_actor_snapshot #(.SLOTS(3), .ADDRESS_WIDTH(2), .MAILBOX(1)) dut (.*);
    initial begin
        // Includes unused address 3, disabled writes, repeated writes, phase
        // 255, both flags, and reset coincident with an accepted application write.
        for(n=0; n<1024; n=n+1) begin
            @(negedge clk);
            reset = n == 0 || n == 511;
            write_enable = n%5 != 0;
            mailbox_valid = n%3 == 0;
            mailbox_values = {24'(n), 24'(n*7), 24'(n*13)};
            write_address = n%4;
            write_value = (n * 65537) & 25'h1ffffff;
            @(posedge clk);
            for(i=0; i<3; i=i+1) begin
                if(reset) begin expected[i]=0; expected_mailbox[i]=0; end
                else if(write_enable && write_address==i) expected[i]={1'b1,write_value};
                if (!reset && mailbox_valid) expected_mailbox[i] = mailbox_values[i*24+:24];
            end
            #1;
            for(i=0; i<3; i=i+1) begin
                if(values[i*64+:32] !== {6'b0,expected[i]}) $fatal(1,"snapshot slot %0d at %0d",i,n);
                if(values[i*64+32+:32] !== {8'b0,expected_mailbox[i]}) $fatal(1,"mailbox snapshot");
            end
        end
        $display("PASS: committed writes, slot isolation, disabled/out-of-range writes and reset validity");
        $finish;
    end
endmodule
