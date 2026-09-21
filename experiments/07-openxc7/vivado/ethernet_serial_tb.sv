`timescale 1ns/1ps
// Exercise the complete board datapath with real GTX/MMCM simulation models.
// Only PS software/register access and negotiation/traffic timers are accelerated.
module ethernet_serial_tb;
    reg ref_p=0;
    always #4 ref_p=~ref_p;
    wire tx_p, tx_n;
    te0715_ethernet_top dut(.ref_p(ref_p),.ref_n(!ref_p),
        .gt_rx_p(tx_p),.gt_rx_n(tx_n),.gt_tx_p(tx_p),.gt_tx_n(tx_n));
    defparam dut.traffic.GAP_CYCLES=128;
    // Observe existing endpoint counters as well as the host-visible snapshot.
    initial forever begin
        #50000;
        $display("ENDPOINT %0t: tx=%0d rx=%0d drop=%0d preamble=%0d crc=%0d", $time,
                 dut.packets.tx_accepted, dut.packets.rx_accepted, dut.packets.rx_dropped,
                 dut.packets.preamble_errors, dut.packets.crc_errors);
    end
    initial begin #2000000; $fatal(1,"serial Ethernet timeout"); end
endmodule

// Model the existing PS shell's public control/status boundary at 25 MHz.
module zynq_probe_ps #(
    parameter EXTENDED=0, parameter [31:0] IDENTITY=0, parameter [31:0] ABI=1
)(input wire [127:0] status, output reg [31:0] control=0,
  output reg clock=0, reset_n=0);
    always #20 clock=~clock;
    reg [31:0] previous=32'hffffffff;
    always @(negedge clock) begin
        if(status[31:0]!==previous) begin
            $display("STATUS %0t: %h", $time, status[31:0]);
            previous=status[31:0];
        end
        if(reset_n && control[0] && status[2:0]===3'd7)
            $fatal(1,"GTX controller fault: %h",status[31:0]);
    end
    integer attempt;
    initial begin
        #2000; reset_n=1;
        for(attempt=0; attempt<2; attempt=attempt+1) begin
            @(negedge clock); control=3;
            wait(status[16]===1'b1 && status[17]===1'b1);
            // Six short frames need far less than this 40-us delivery budget.
            repeat(1000) @(negedge clock);
            if(status[95:64]<6 || status[63:32]<6)
                $fatal(1,"serial packet delivery timeout: %h",status);
            if(status[127:96]!==0) $fatal(1,"serial packet integrity error: %h",status);
            $display("PASS: vendor serial Ethernet attempt %0d status=%h",attempt,status);
            @(negedge clock); control=0;
            repeat(1200) @(negedge clock);
        end
        $display("PASS: complete MAC/PCS/gearbox/GTX/MMCM frame loopback and restart");
        $finish;
    end
endmodule
