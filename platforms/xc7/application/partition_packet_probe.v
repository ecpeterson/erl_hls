// Retain the first observed transition at each private packet boundary.
// Adapter flags are synchronous to clock. MAC counters and PCS link signals
// cross only as monotone nonzero status through two-flop synchronizers; these
// observations diagnose a boundary but do not qualify CDC timing or counters.
// The consumer must accept every asserted one-cycle event.
module partition_packet_probe(
    input wire clock, reset_n,
    input wire tx_frame_accepted,
    input wire rx_frame_accepted,
    input wire link_rx_frame_delivered,
    input wire [2:0] packet_fault,
    input wire tx_link_async, rx_link_async,
    input wire [5:0] mac_status_async,
    output wire [31:0] event_data,
    output wire event_valid
);
    (* ASYNC_REG="TRUE" *) reg [1:0] tx_link_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] rx_link_sync;
    (* ASYNC_REG="TRUE" *) reg [5:0] mac_status_meta;
    (* ASYNC_REG="TRUE" *) reg [5:0] mac_status_sync;
    reg [7:0] adapter_seen;
    reg [5:0] mac_seen;
    reg [5:0] mac_pending;

    wire [7:0] adapter_status = {
        rx_link_sync[1],
        tx_link_sync[1],
        packet_fault,
        link_rx_frame_delivered,
        rx_frame_accepted,
        tx_frame_accepted
    };
    wire [7:0] adapter_rise = adapter_status & ~adapter_seen;
    wire [5:0] mac_rise = mac_status_sync & ~mac_seen;
    wire [5:0] mac_available = mac_pending | mac_rise;
    wire send_adapter = |adapter_rise;
    wire send_mac = !send_adapter && |mac_available;

    assign event_valid = send_adapter || send_mac;
    assign event_data = send_adapter ?
        {8'hd1, 8'h00, adapter_rise, 8'h00} :
        {8'hd2, 8'h00, 2'b00, mac_available, 8'h00};

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            tx_link_sync <= 0;
            rx_link_sync <= 0;
            mac_status_meta <= 0;
            mac_status_sync <= 0;
            adapter_seen <= 0;
            mac_seen <= 0;
            mac_pending <= 0;
        end else begin
            tx_link_sync <= {tx_link_sync[0], tx_link_async};
            rx_link_sync <= {rx_link_sync[0], rx_link_async};
            mac_status_meta <= mac_status_async;
            mac_status_sync <= mac_status_meta;
            adapter_seen <= adapter_seen | adapter_status;
            mac_seen <= mac_seen | mac_status_sync;
            if (send_mac)
                mac_pending <= 0;
            else
                mac_pending <= mac_available;
        end
    end
endmodule
