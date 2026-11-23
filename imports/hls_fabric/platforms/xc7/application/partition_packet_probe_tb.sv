`timescale 1ns/1ps

module partition_packet_probe_tb;
    reg clock = 0;
    reg reset_n = 0;
    reg tx_frame_accepted = 0;
    reg rx_frame_accepted = 0;
    reg link_rx_frame_delivered = 0;
    reg [2:0] packet_fault = 0;
    reg tx_link_async = 0;
    reg rx_link_async = 0;
    reg [5:0] mac_status_async = 0;
    wire [31:0] event_data;
    wire event_valid;
    reg [7:0] adapter_observed = 0;
    reg [5:0] mac_observed = 0;
    integer event_count = 0;

    always #5 clock = ~clock;

    partition_packet_probe dut(
        .clock(clock), .reset_n(reset_n),
        .tx_frame_accepted(tx_frame_accepted),
        .rx_frame_accepted(rx_frame_accepted),
        .link_rx_frame_delivered(link_rx_frame_delivered),
        .packet_fault(packet_fault),
        .tx_link_async(tx_link_async), .rx_link_async(rx_link_async),
        .mac_status_async(mac_status_async),
        .event_data(event_data), .event_valid(event_valid)
    );

    always @(posedge clock) begin
        if (event_valid) begin
            event_count <= event_count + 1;
            if (event_data[31:24] == 8'hd1)
                adapter_observed <= adapter_observed | event_data[15:8];
            else if (event_data[31:24] == 8'hd2)
                mac_observed <= mac_observed | event_data[13:8];
            else
                $fatal(1, "unexpected event %h", event_data);
        end
    end

    initial begin
        repeat (3) @(negedge clock);
        reset_n = 1;
        tx_link_async = 1;
        rx_link_async = 1;
        tx_frame_accepted = 1;
        mac_status_async = 6'b000011;
        @(negedge clock);
        tx_frame_accepted = 0;
        repeat (5) @(negedge clock);
        rx_frame_accepted = 1;
        link_rx_frame_delivered = 1;
        packet_fault = 3'b111;
        mac_status_async = 6'b111111;
        @(negedge clock);
        rx_frame_accepted = 0;
        link_rx_frame_delivered = 0;
        repeat (8) @(negedge clock);
        if (adapter_observed != 8'hff)
            $fatal(1, "missing adapter flags %h", adapter_observed);
        if (mac_observed != 6'h3f)
            $fatal(1, "missing MAC flags %h", mac_observed);
        if (event_count < 2)
            $fatal(1, "too few diagnostic events %0d", event_count);

        // Repeated levels and handshakes must not consume trace capacity.
        tx_frame_accepted = 1;
        rx_frame_accepted = 1;
        link_rx_frame_delivered = 1;
        repeat (3) @(negedge clock);
        if (event_valid)
            $fatal(1, "repeated status emitted another event");
        $display("PASS: packet-boundary probe retains each first transition once");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "timeout");
    end
endmodule
