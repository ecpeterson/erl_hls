// Test-only ideal serializer, recovered-clock word assembly and comma aligner.
// It models digital bit ordering only: no analog GTX/CDR, elastic-buffer latency,
// lock/reset timing or electrical behavior. The synthesized DUT is the endpoint.
module gearbox_packet_fixture (
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

    reg tx_half=0, rx_half=0;
    integer bit_offset=0, phase=0;
    initial begin
        if ($value$plusargs("bit_offset=%d",bit_offset)) begin end
        if ($value$plusargs("half_phase=%d",phase)) begin end
        tx_half=phase; rx_half=phase;
    end
    // Ideal edge-aligned 2:1 clocks. Blocking clock assignment deliberately
    // triggers half-domain flops before the full-domain nonblocking updates.
    always @(posedge eth_tx_clk) tx_half = !tx_half;
    always @(posedge eth_rx_clk) rx_half = !rx_half;
    wire [15:0] tx_pins;
    wire [1:0] tx_val, tx_mode;
    wire [19:0] tx_word = {tx_mode[1],tx_val[1],tx_pins[15:8],
                           tx_mode[0],tx_val[0],tx_pins[7:0]};
    reg [19:0] serialized=0;
    reg [9:0] serial_tx=0;
    assign tbi_tx=serial_tx;
    always @(negedge eth_tx_clk) begin
        if (tx_half) begin
            serialized=tx_word;
            serial_tx=tx_word[9:0];
        end else serial_tx=serialized[19:10];
    end
    reg [59:0] history=0;
    reg [19:0] rx_word=0;
    integer displacement=0, candidate;
    wire gt_align;
    // A serial receiver can begin at any of 20 bit positions. While alignment
    // is requested, select a K28.5 at the first symbol of the GTX word. Hold the
    // offset during packets. This behavioral oracle does not use PCSGearbox.
    always @(posedge eth_rx_clk) history <= {tbi_rx,history[59:10]};
    always @(posedge rx_half) begin
        if (eth_rx_rst) begin displacement=bit_offset; rx_word<=0; end
        else begin
            if (gt_align)
                for(candidate=0;candidate<20;candidate=candidate+1)
                    if (history[candidate+:10]==10'h17c || history[candidate+:10]==10'h283)
                        displacement=candidate;
            rx_word <= history >> displacement;
        end
    end
    ethernet_gtx_packet_endpoint dut (
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .eth_tx_half_clk(tx_half), .eth_tx_half_rst(eth_tx_rst),
        .eth_rx_half_clk(rx_half), .eth_rx_half_rst(eth_rx_rst),
        .gt_tx_data(tx_pins), .gt_tx_dispval(tx_val), .gt_tx_dispmode(tx_mode),
        .gt_rx_data({rx_word[17:10],rx_word[7:0]}),
        .gt_rx_charisk({rx_word[18],rx_word[8]}),
        .gt_rx_disperr({rx_word[19],rx_word[9]}), .gt_align(gt_align),
        .link_tx(link_tx), .link_rx(link_rx), .restart(restart),
        .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(rx_valid), .rx_last(rx_last), .rx_data(rx_data), .rx_ready(rx_ready),
        .tx_queued(tx_queued), .rx_queued(rx_queued),
        .tx_accepted(tx_accepted), .tx_dropped(tx_dropped),
        .tx_overflowed(tx_overflowed), .tx_aborted(tx_aborted),
        .rx_accepted(rx_accepted), .rx_dropped(rx_dropped),
        .rx_overflowed(rx_overflowed), .rx_aborted(rx_aborted),
        .preamble_errors(preamble_errors), .crc_errors(crc_errors)
    );
    assign align=gt_align;
endmodule
