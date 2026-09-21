`timescale 1ns/1ps
// Check complete packet transfer through public ports, including stopped domains.
module dma_packets_tb;
    reg clock=0, tx_clock=0, rx_clock=0, reset_n=0;
    reg tx_active_n=0, rx_active_n=0, tx_running=1, rx_running=1;
    always #20 clock=!clock;
    always #4 if(tx_running) tx_clock=!tx_clock;
    always #4.001 if(rx_running) rx_clock=!rx_clock;
    reg [31:0] host_tx_data=0;
    reg host_tx_valid=0, host_tx_last=0, host_rx_ready=0;
    wire host_tx_ready, host_rx_valid, host_rx_last;
    wire [31:0] host_rx_data;
    wire [7:0] tx_data;
    wire tx_valid, tx_last, rx_ready, tx_invalid;
    reg tx_ready=0, rx_valid=0, rx_last=0;
    reg [7:0] rx_data=0;
    ethernet_dma_packets dut(.*);

    // Distinguish packet, word and byte positions, including final partial words.
    function automatic [7:0] pattern(input integer index, key);
        pattern = (index*37) ^ (index>>3) ^ key;
    endfunction

    // Publish one word and hold it until the host-side stream accepts it.
    task automatic host_word(input [31:0] value, input last);
        @(negedge clock); host_tx_valid=1; host_tx_data=value; host_tx_last=last;
        @(posedge clock); while(!host_tx_ready) @(posedge clock);
        @(negedge clock); host_tx_valid=0;
    endtask

    // Submit the fixture's private length envelope; padding deliberately differs.
    task automatic send_host(input integer length, key);
        reg [31:0] word;
        host_word(length,0);
        for(integer i=0;i<length;i=i+4) begin
            for(integer j=0;j<4;j=j+1) word[j*8+:8]=i+j<length ? pattern(i+j,key) : 8'hef;
            host_word(word,i+4>=length);
        end
    endtask

    // Receive an exact byte sequence while inserting deterministic stalls.
    task automatic check_tx(input integer length, key);
        for(integer i=0;i<length;i=i+1) begin
            @(negedge tx_clock); tx_ready=0;
            repeat(i%3) @(negedge tx_clock);
            tx_ready=1;
            @(posedge tx_clock); while(!tx_valid) @(posedge tx_clock);
            if(tx_data!==pattern(i,key) || tx_last!==(i==length-1))
                $fatal(1,"TX byte %0d/%0d: %x last=%b",i,length,tx_data,tx_last);
        end
        @(negedge tx_clock); tx_ready=0;
    endtask

    // Supply Ethernet bytes; only the final beat commits a receive packet.
    task automatic send_rx(input integer length, key, input commit);
        for(integer i=0;i<length;i=i+1) begin
            @(negedge rx_clock); rx_valid=1; rx_data=pattern(i,key); rx_last=commit && i==length-1;
            @(posedge rx_clock); while(!rx_ready) @(posedge rx_clock);
        end
        @(negedge rx_clock); rx_valid=0;
    endtask

    // Verify length, zero tail padding and whole-word host stalls.
    task automatic check_host(input integer length, key);
        reg [31:0] expected;
        for(integer word=0;word<1+(length+3)/4;word=word+1) begin
            if(word==0) expected=length;
            else for(integer j=0;j<4;j=j+1)
                expected[j*8+:8]=(word-1)*4+j<length ? pattern((word-1)*4+j,key) : 0;
            @(negedge clock); host_rx_ready=0;
            repeat(word%4) @(negedge clock);
            host_rx_ready=1;
            @(posedge clock); while(!host_rx_valid) @(posedge clock);
            if(host_rx_data!==expected || host_rx_last!==(word==(length+3)/4))
                $fatal(1,"RX word %0d length=%0d: %x expected=%x last=%b",word,length,host_rx_data,expected,host_rx_last);
        end
        @(negedge clock); host_rx_ready=0;
    endtask

    // Assert shared reset only while test users are quiescent, then release locally.
    task automatic start;
        reset_n=0; tx_active_n=0; rx_active_n=0;
        repeat(4) @(negedge clock); reset_n=1;
        repeat(4) @(negedge tx_clock); tx_active_n=1;
        repeat(4) @(negedge rx_clock); rx_active_n=1;
    endtask

    integer sizes[0:12]='{14,15,16,17,60,61,64,255,256,257,1020,1513,1514};
    initial begin
        start;
        for(integer n=0;n<13;n=n+1) begin
            fork
                send_host(sizes[n],n+11);
                check_tx(sizes[n],n+11);
                send_rx(sizes[12-n],n+71,1);
                check_host(sizes[12-n],n+71);
            join
        end
        // A completed RX remains readable while its producing clock is absent.
        send_rx(67,121,1);
        rx_active_n=0; rx_running=0;
        check_host(67,121);
        rx_running=1;
        repeat(5) @(negedge rx_clock); rx_active_n=1;
        // A partial RX must not precede the replacement packet after restart.
        send_rx(9,15,0); rx_active_n=0;
        repeat(6) @(negedge clock);
        if(host_rx_valid) $fatal(1,"partial RX escaped");
        @(negedge rx_clock); rx_active_n=1;
        fork send_rx(19,217,1); check_host(19,217); join
        // Interrupt transmission after a prefix; the retained slot restarts whole.
        fork
            send_host(91,52);
            begin
                @(negedge tx_clock); tx_ready=1;
                repeat(7) begin @(posedge tx_clock); while(!tx_valid) @(posedge tx_clock); end
                @(negedge tx_clock); tx_ready=0; tx_active_n=0; tx_running=0;
                repeat(10) @(negedge clock);
                tx_running=1;
                repeat(4) @(negedge tx_clock); tx_active_n=1;
                check_tx(91,52);
            end
        join
        if(tx_invalid) $fatal(1,"valid envelope rejected");
        host_word(14,0); host_word(32'h1234,1);
        repeat(10) @(negedge clock);
        if(!tx_invalid || tx_valid) $fatal(1,"truncated envelope published");
        $display("PASS: packet CDC, exact byte lengths, stalls, stopped clocks and whole-frame restart");
        $finish;
    end
    initial begin #20000000; $fatal(1,"packet CDC timeout"); end
endmodule
