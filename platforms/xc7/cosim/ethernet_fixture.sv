`timescale 1ns/1ps
// Test wiring only: DMA packets traverse the real PCS/MAC in ideal TBI loopback.
// The 25-MHz host stepping schedule advances an independent 125-MHz link clock.
// cut injects invalid symbols; hold_rx stalls the public return stream. Neither
// control resets AXI or reaches into the mailbox, CDC slot or MAC internals.
module ethernet_cosim_fixture(
    input wire clock, reset_n, cut, hold_rx,
    input wire [31:0] tx_data,
    input wire tx_valid, tx_last,
    output wire tx_ready,
    output wire [31:0] rx_data,
    output wire rx_valid, rx_last,
    input wire rx_ready,
    output wire [31:0] status
);
    reg packet_clock=0;
    always #4 packet_clock=!packet_clock;
    wire packet_reset_n;
    zynq_probe_reset packet_reset(packet_clock, reset_n, packet_reset_n);
    wire [9:0] symbols;
    wire link_tx, link_rx;
    wire [7:0] tx_byte, rx_byte;
    wire byte_tx_valid, byte_tx_last, byte_tx_ready, byte_rx_valid, byte_rx_last, byte_rx_ready;
    wire returning, invalid;
    assign rx_valid=returning && !hold_rx;
    assign status={28'b0,returning,invalid,link_rx,link_tx};
    ethernet_dma_packets bridge(
        .clock(clock), .reset_n(reset_n), .tx_clock(packet_clock), .rx_clock(packet_clock),
        .tx_active_n(packet_reset_n && link_tx), .rx_active_n(packet_reset_n),
        .host_tx_data(tx_data), .host_tx_valid(tx_valid), .host_tx_last(tx_last), .host_tx_ready(tx_ready),
        .host_rx_data(rx_data), .host_rx_valid(returning), .host_rx_last(rx_last), .host_rx_ready(rx_ready && !hold_rx),
        .tx_data(tx_byte), .tx_valid(byte_tx_valid), .tx_last(byte_tx_last), .tx_ready(byte_tx_ready),
        .rx_data(rx_byte), .rx_valid(byte_rx_valid), .rx_last(byte_rx_last), .rx_ready(byte_rx_ready),
        .tx_invalid(invalid)
    );
    ethernet_packet_endpoint packets(
        .eth_tx_clk(packet_clock), .eth_rx_clk(packet_clock), .eth_tx_rst(!packet_reset_n), .eth_rx_rst(!packet_reset_n),
        .tbi_rx(cut ? 10'b0 : symbols), .tbi_tx(symbols), .link_tx(link_tx), .link_rx(link_rx),
        .tx_data(tx_byte), .tx_valid(byte_tx_valid), .tx_last(byte_tx_last), .tx_ready(byte_tx_ready),
        .rx_data(rx_byte), .rx_valid(byte_rx_valid), .rx_last(byte_rx_last), .rx_ready(byte_rx_ready)
    );
endmodule
