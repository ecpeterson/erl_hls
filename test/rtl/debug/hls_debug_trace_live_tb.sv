`timescale 1ns/1ps
// A passive observation provider, an explicit sampling fault gate, and the
// production collector. The host sees only the routed debug stream. No private
// observer/scheduler state is read or forced.
module hls_debug_trace_live_tb;
    reg clk=0, resetn=0;
    always #5 clk=~clk;
    reg [31:0] s_dbg_tdata=0;
    reg [3:0] s_dbg_tkeep=15;
    reg s_dbg_tvalid=0, s_dbg_tlast=0;
    wire s_dbg_tready;
    wire [31:0] m_dbg_tdata;
    wire [3:0] m_dbg_tkeep;
    wire m_dbg_tvalid, m_dbg_tlast;
    reg m_dbg_tready=0;
    reg [31:0] rx_data=0, tx_data=0;
    reg rx_valid=0, rx_ready=1, rx_last=0;
    reg tx_valid=0, tx_ready=1, tx_last=0;
    reg sample_enabled=1;
    wire [103:0] observation;
    wire observation_valid, capture_ready;
    wire [31:0] request_data,response_data;
    wire [3:0] request_keep,response_keep;
    wire request_valid,request_ready,request_last,response_valid,response_ready,response_last;
    integer accepted_rx=0,accepted_tx=0;
    always @(posedge clk) if(resetn) begin
        if(rx_valid && rx_ready) accepted_rx=accepted_rx+1;
        if(tx_valid && tx_ready) accepted_tx=accepted_tx+1;
    end

    hls_debug_tap #(.ROUTED(1)) tap (
        .aclk(clk),.aresetn(resetn),
        .app_rx_tdata(rx_data),.app_rx_tvalid(rx_valid),.app_rx_tready(rx_ready),.app_rx_tlast(rx_last),
        .app_tx_tdata(tx_data),.app_tx_tvalid(tx_valid),.app_tx_tready(tx_ready),.app_tx_tlast(tx_last),
        .observation_data(observation),.observation_valid(observation_valid),
        .observation_ready(sample_enabled && capture_ready));
    hls_debug_capture capture (
        .aclk(clk),.aresetn(resetn),.observation_data(observation),
        .observation_valid(observation_valid && sample_enabled),.observation_ready(capture_ready),
        .s_dbg_tdata(request_data),.s_dbg_tkeep(request_keep),.s_dbg_tlast(request_last),
        .s_dbg_tvalid(request_valid),.s_dbg_tready(request_ready),
        .m_dbg_tdata(response_data),.m_dbg_tkeep(response_keep),.m_dbg_tlast(response_last),
        .m_dbg_tvalid(response_valid),.m_dbg_tready(response_ready));
    hls_debug_route #(.ENDPOINT(1)) route (
        .clk(clk),.reset(!resetn),
        .s_data(s_dbg_tdata),.s_keep(s_dbg_tkeep),.s_valid(s_dbg_tvalid),.s_ready(s_dbg_tready),.s_last(s_dbg_tlast),
        .m_data(m_dbg_tdata),.m_keep(m_dbg_tkeep),.m_valid(m_dbg_tvalid),.m_ready(m_dbg_tready),.m_last(m_dbg_tlast),
        .request_data(request_data),.request_keep(request_keep),.request_valid(request_valid),.request_ready(request_ready),.request_last(request_last),
        .response_data(response_data),.response_keep(response_keep),.response_valid(response_valid),.response_ready(response_ready),.response_last(response_last));

    // Independent application driver; it does not inspect observation_ready.
    task automatic beat(input [31:0] word,input last,input sample,input both);
        begin
            @(negedge clk);
            rx_data=word;rx_valid=1;rx_last=last;sample_enabled=sample;
            tx_data=word;tx_valid=both;tx_last=last;
            @(negedge clk);
            rx_valid=0;tx_valid=0;sample_enabled=1;
        end
    endtask
    task automatic packet(input [7:0] id,input both);
        begin
            beat(32'h12345678,0,1,both);
            beat({8'h07,8'd0,id,8'd0},1,1,both);
        end
    endtask
    task automatic command(input integer number);
        integer fd;
        string name;
        begin
            name=$sformatf("phase_%0d",number);
            fd=0;
            while(!fd) begin @(negedge clk); fd=$fopen(name,"r"); end
            $fclose(fd);
        end
    endtask
    task automatic done(input integer number);
        integer fd;
        string name;
        begin
            repeat(16) @(negedge clk);
            name=$sformatf("done_%0d",number);
            fd=$fopen(name,"w");$fclose(fd);
        end
    endtask
    integer i;
    initial begin
        repeat(5) @(negedge clk); resetn=1;
        command(0);
        packet(8'h10,1); // Simultaneous RX/TX: one trace RAM row.
        done(0);

        command(1);
        // Drop a header after its route. Payload must not become a header.
        beat(32'h12345678,0,1,0);
        beat(32'h07001102,0,0,0);
        beat(32'hfa00ee00,0,1,0);
        done(1); // No TLAST yet: both framing states remain uncertain.

        command(2);
        // A stalled TLAST cannot restore synchronization.
        rx_ready=0;
        rx_data=32'hfa00ee00;rx_valid=1;rx_last=1;
        done(2);

        command(3);
        // Hold valid/data/last throughout the stall, then accept that beat.
        rx_ready=1;
        @(negedge clk);rx_valid=0;
        packet(8'h12,0);
        done(3); // RX recovered; TX has not seen an accepted TLAST.

        command(4);
        // A second gap loses a route. Both directions recover independently.
        beat(32'h12345678,0,0,1);
        beat(32'h07001300,1,1,1);
        packet(8'h14,1);
        done(4);

        command(5);
        // A lost final payload beat must suppress the following whole packet.
        beat(32'h12345678,0,1,0);
        beat(32'h07001501,0,1,0);
        beat(32'hdeadbeef,1,0,0);
        packet(8'h16,0);
        packet(8'h17,0);
        done(5);

        command(6);
        // Fill a bank, then lose observations before an overflowing header.
        for(i=0;i<64;i=i+1) packet(i,0);
        beat(32'h12345678,0,0,0);
        beat(32'h07008000,1,1,0);
        packet(8'h81,0);
        done(6);

        command(7);
        // Draining a full bank must not clear unreported gap information.
        packet(8'h82,0);
        done(7);

        command(8);
        // Reset only after the previous debug transaction completed. The host
        // replaces its debug client; no in-flight frame is aborted.
        @(negedge clk); resetn=0;
        repeat(5) @(negedge clk); resetn=1;
        packet(8'h90,1);
        done(8);
        command(9);
        $display("PASS: debug-only diagnosis completed; independent application accepted RX=%0d TX=%0d beats",accepted_rx,accepted_tx);
        $finish;
    end
    initial begin #50000000; $fatal(1,"host debug trace test timed out"); end
endmodule
