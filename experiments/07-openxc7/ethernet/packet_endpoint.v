// Simulation/synthesis boundary for an untagged Ethernet frame service, without
// PS, GTX or board pins. TX streams/counters use eth_tx_clk; RX uses eth_rx_clk.
// Both clocks are 125 MHz, RX recovered from the peer. TBI symbols are 10 bits,
// bit 0 first. TX accepts 14..1514 bytes including addresses/type, excluding FCS;
// RX emits 60..1514 bytes including padding, excluding preamble/FCS.
// Link loss flushes TX (the producer must restart its frame) and aborts partial
// RX, preserving already committed RX frames even under consumer backpressure.
// Reset both domains together for a new experiment. No CDC to a host clock yet.
module ethernet_packet_endpoint (
    input wire eth_tx_clk, eth_tx_rst, eth_rx_clk, eth_rx_rst,
    input wire [9:0] tbi_rx,
    output wire [9:0] tbi_tx,
    output wire link_tx, link_rx, restart, align,
    input wire tx_valid, tx_last,
    input wire [7:0] tx_data,
    output wire tx_ready,
    output wire rx_valid, rx_last,
    output wire [7:0] rx_data,
    input wire rx_ready,
    output wire [1:0] tx_queued, rx_queued,
    output wire [31:0] tx_accepted, tx_dropped, tx_overflowed, tx_aborted,
    output wire [31:0] rx_accepted, rx_dropped, rx_overflowed, rx_aborted,
    output wire [31:0] preamble_errors, crc_errors
);
    wire to_mac_valid, to_mac_last, to_mac_ready;
    wire [7:0] to_mac_data;
    wire from_mac_valid, from_mac_last, from_mac_error;
    wire [7:0] from_mac_data;
    ethernet_frame_store tx_store (
        .clk(eth_tx_clk), .rst(eth_tx_rst), .flush(!link_tx), .abort_partial(1'b0),
        .in_valid(tx_valid), .in_ready(tx_ready), .in_data(tx_data),
        .in_last(tx_last), .in_error(1'b0), .out_valid(to_mac_valid),
        .out_ready(to_mac_ready), .out_data(to_mac_data), .out_last(to_mac_last),
        .queued(tx_queued), .accepted(tx_accepted), .dropped(tx_dropped),
        .overflowed(tx_overflowed), .aborted(tx_aborted)
    );
    ethernet_frame_store #(.DROP_WHEN_FULL(1), .MIN_BYTES(60)) rx_store (
        .clk(eth_rx_clk), .rst(eth_rx_rst), .flush(1'b0), .abort_partial(!link_rx),
        .in_valid(from_mac_valid), .in_ready(), .in_data(from_mac_data),
        .in_last(from_mac_last), .in_error(from_mac_error), .out_valid(rx_valid),
        .out_ready(rx_ready), .out_data(rx_data), .out_last(rx_last),
        .queued(rx_queued), .accepted(rx_accepted), .dropped(rx_dropped),
        .overflowed(rx_overflowed), .aborted(rx_aborted)
    );
    liteeth_packet_core core (
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .tbi_rx(tbi_rx), .tbi_tx(tbi_tx), .link_tx(link_tx), .link_rx(link_rx),
        .restart(restart), .align(align), .tx_valid(to_mac_valid), .tx_ready(to_mac_ready),
        .tx_data(to_mac_data), .tx_last(to_mac_last), .rx_valid(from_mac_valid),
        .rx_data(from_mac_data), .rx_last(from_mac_last), .rx_error(from_mac_error),
        .preamble_errors(preamble_errors), .crc_errors(crc_errors)
    );
endmodule
