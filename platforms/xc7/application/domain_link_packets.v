// One opaque endpoint packet per private Ethernet frame. Atomic local packet
// acceptance retains all 32 words; only the declared 11 ACK or 32 DATA words
// cross the wire. Namespace, generation, incarnations and publication sequence
// belong to that endpoint packet, never to a carrier-wide sequence counter.
//
// Incremental storage: two 1024-bit packet buffers and 82 framing/control bits.
// TX has one whole-packet writer/word reader; RX one word writer/packet reader.
// The inherited DMA's two 512x32 CDC memories and all its control/reset storage
// remain additional whole-image cost. No endpoint or application reset enters
// this module. Cold reset requires exclusion of the forgotten link namespace.
//
// MAC bytes are assumed to have passed frame integrity checks. This is a
// dedicated point-to-point carrier: unrelated Ethernet frames are fatal private
// envelope violations, not shared-LAN traffic. ROLE must be 1 or 2.
// Directional active loss after startup is fatal until cold reset, even
// if active recovers between host edges; retained DMA packets cannot restart.
// MAC whole-frame loss is supplied separately; integrity-filtered missing frames
// cannot be detected from accepted bytes alone. Its six capture/synchronizer bits
// are charged in the frontend alongside six local reset-release bits.
// Local errors stop their producing direction immediately. The host observes
// synchronized fault levels, then the other direction observes synchronized
// stop. Accepted work may complete before that local stop observation; it is
// not replayed after active recovery. Only cold reset rearms either direction.
// Simulation bounds assume running clocks and do not establish metastability MTBF.
module domain_link_packets #(
    parameter [7:0] ROLE = 8'd1
) (
    input wire clock, cold_reset_n,
    input wire tx_clock, rx_clock,
    input wire tx_active_n, rx_active_n,
    // Qualified MAC loss is cold-reset sticky and synchronized to clock upstream.
    input wire physical_loss,
    // Same-direction cold-sticky MAC loss, never sampled in the other clock.
    input wire tx_physical_loss, rx_physical_loss,
    input wire [1023:0] packet_tx,
    input wire [5:0] packet_tx_words,
    input wire packet_tx_valid,
    output wire packet_tx_ready,
    output wire [1023:0] packet_rx,
    output wire [5:0] packet_rx_words,
    output wire packet_rx_valid,
    input wire packet_rx_ready,
    output wire [7:0] tx_data,
    output wire tx_valid, tx_last,
    input wire tx_ready,
    input wire [7:0] rx_data,
    input wire rx_valid, rx_last,
    output wire rx_ready,
    output wire [31:0] fault,
    output reg armed,
    output wire tx_packet_accepted,
    output wire tx_frame_committed,
    output wire rx_frame_accepted,
    output wire rx_packet_delivered
);
    localparam [7:0] PEER = ROLE == 8'd1 ? 8'd2 : 8'd1;
    localparam [31:0] MAGIC = 32'h444c4845;
    wire role_ok = ROLE == 8'd1 || ROLE == 8'd2;

    // Each direction owns its stop state. Readiness/fault levels cross to the
    // host through two flops; host arm/stop levels cross back independently.
    wire host_cold_n, rx_cold_n;
    zynq_probe_reset host_cold(clock, cold_reset_n, host_cold_n);
    wire tx_local_ready, rx_local_ready, tx_active_lost, rx_active_lost;
    wire tx_local_armed, rx_local_armed;
    wire tx_live, rx_live;
    reg arm_request;
    wire fatal;
    reg tx_protocol_fault, rx_protocol_fault, dma_invalid_seen;
    reg rx_wire_fault;
    reg [7:0] rx_wire_count;
    (* ASYNC_REG="TRUE" *) reg tx_ready_meta, tx_ready_sync, rx_ready_meta, rx_ready_sync;
    (* ASYNC_REG="TRUE" *) reg tx_lost_meta, tx_lost_sync, rx_lost_meta, rx_lost_sync;
    (* ASYNC_REG="TRUE" *) reg rx_wire_meta, rx_wire_sync;
    (* ASYNC_REG="TRUE" *) reg tx_armed_meta, tx_armed_sync, rx_armed_meta, rx_armed_sync;
    always @(posedge clock or negedge host_cold_n) begin
        if (!host_cold_n) begin
            tx_ready_meta <= 0; tx_ready_sync <= 0; rx_ready_meta <= 0; rx_ready_sync <= 0;
            tx_lost_meta <= 0; tx_lost_sync <= 0; rx_lost_meta <= 0; rx_lost_sync <= 0;
            rx_wire_meta <= 0; rx_wire_sync <= 0; armed <= 0; arm_request <= 0;
            tx_armed_meta <= 0; tx_armed_sync <= 0; rx_armed_meta <= 0; rx_armed_sync <= 0;
        end else begin
            tx_ready_meta <= tx_local_ready; tx_ready_sync <= tx_ready_meta;
            rx_ready_meta <= rx_local_ready; rx_ready_sync <= rx_ready_meta;
            tx_lost_meta <= tx_active_lost; tx_lost_sync <= tx_lost_meta;
            rx_lost_meta <= rx_active_lost; rx_lost_sync <= rx_lost_meta;
            rx_wire_meta <= rx_wire_fault; rx_wire_sync <= rx_wire_meta;
            tx_armed_meta <= tx_local_armed; tx_armed_sync <= tx_armed_meta;
            rx_armed_meta <= rx_local_armed; rx_armed_sync <= rx_armed_meta;
            if (tx_ready_sync && rx_ready_sync && !fatal) arm_request <= 1;
            if (tx_armed_sync && rx_armed_sync && !fatal) armed <= 1;
        end
    end
    wire lost = tx_lost_sync || rx_lost_sync;
    assign fault = {25'd0, physical_loss, !role_ok, rx_wire_sync, dma_invalid_seen,
                    rx_protocol_fault, tx_protocol_fault, lost};
    assign fatal = |fault;
    wire live = host_cold_n && armed && tx_ready_sync && rx_ready_sync && !fatal;
    domain_link_direction tx_guard(
        .local_clock(tx_clock), .cold_reset_n(cold_reset_n), .active_n(tx_active_n),
        .local_fault(tx_physical_loss), .host_arm(arm_request), .host_stop(fatal),
        .local_cold_n(), .ready(tx_local_ready), .local_armed(tx_local_armed),
        .active_lost(tx_active_lost), .live(tx_live)
    );
    domain_link_direction rx_guard(
        .local_clock(rx_clock), .cold_reset_n(cold_reset_n), .active_n(rx_active_n),
        .local_fault(rx_wire_fault || rx_physical_loss), .host_arm(arm_request), .host_stop(fatal),
        .local_cold_n(rx_cold_n), .ready(rx_local_ready), .local_armed(rx_local_armed),
        .active_lost(rx_active_lost), .live(rx_live)
    );

    // Count accepted bytes as well as host words: the inherited DMA otherwise
    // silently discards very short frames without reporting an RX error.
    always @(posedge rx_clock or negedge rx_cold_n) begin
        if (!rx_cold_n) begin rx_wire_count <= 0; rx_wire_fault <= 0; end
        else if (rx_valid && rx_ready) begin
            if (rx_last) begin
                if (rx_wire_count != 8'd67 && rx_wire_count != 8'd151) rx_wire_fault <= 1;
                rx_wire_count <= 0;
            end else if (rx_wire_count == 8'd151) rx_wire_fault <= 1;
            else rx_wire_count <= rx_wire_count + 1'b1;
        end
    end

    reg [1023:0] tx_packet;
    reg tx_busy;
    reg [5:0] tx_word_count, tx_index;
    wire tx_length_ok = packet_tx_words == 6'd11 || packet_tx_words == 6'd32;
    assign packet_tx_ready = live && !tx_busy && tx_length_ok;
    assign tx_packet_accepted = packet_tx_valid && packet_tx_ready;

    // DMA word zero is a byte length; six following words are the fixed
    // Ethernet/alignment/magic/role envelope. Opaque packet word zero follows.
    reg [31:0] host_tx_data;
    always @* begin
        case (tx_index)
            0: host_tx_data = 32'd24 + ({26'd0, tx_word_count} << 2);
            1: host_tx_data = 32'h00000002;
            2: host_tx_data = 32'h00020000 | ({24'd0, PEER} << 8);
            3: host_tx_data = {ROLE, 24'd0};
            4: host_tx_data = 32'h0000b588;
            5: host_tx_data = MAGIC;
            6: host_tx_data = {8'd0, 2'd0, tx_word_count, ROLE, 8'd2};
            default: host_tx_data = tx_packet[(tx_index - 6'd7)*32 +: 32];
        endcase
    end
    wire host_tx_valid = live && tx_busy;
    wire host_tx_last = tx_index == 6'd6 + tx_word_count;
    wire host_tx_ready;
    wire host_tx_take = host_tx_valid && host_tx_ready;
    assign tx_frame_committed = host_tx_take && host_tx_last;
    always @(posedge clock or negedge host_cold_n) begin
        if (!host_cold_n) begin
            tx_packet <= 0; tx_busy <= 0; tx_word_count <= 0; tx_index <= 0;
            tx_protocol_fault <= 0;
        end else begin
            if (live && !tx_busy && packet_tx_valid && !tx_length_ok) tx_protocol_fault <= 1;
            if (tx_packet_accepted) begin
                tx_packet <= packet_tx; tx_word_count <= packet_tx_words;
                tx_busy <= 1; tx_index <= 0;
            end
            if (host_tx_take) begin
                if (host_tx_last) begin tx_busy <= 0; tx_index <= 0; end
                else tx_index <= tx_index + 1'b1;
            end
        end
    end

    reg [1023:0] rx_packet;
    reg rx_busy;
    reg [5:0] rx_word_count, rx_index;
    wire [31:0] host_rx_data;
    wire host_rx_valid, host_rx_last;
    wire host_rx_ready = live && !rx_busy;
    wire host_rx_take = host_rx_valid && host_rx_ready;
    wire rx_expected_last = rx_index >= 6'd7 && rx_index == 6'd6 + rx_word_count;
    reg rx_word_bad;
    always @* begin
        rx_word_bad = host_rx_last != rx_expected_last;
        case (rx_index)
            0: rx_word_bad = rx_word_bad || (host_rx_data != 32'd68 && host_rx_data != 32'd152);
            1: rx_word_bad = rx_word_bad || host_rx_data != 32'h00000002;
            2: rx_word_bad = rx_word_bad || host_rx_data != (32'h00020000 | ({24'd0, ROLE} << 8));
            3: rx_word_bad = rx_word_bad || host_rx_data != {PEER, 24'd0};
            4: rx_word_bad = rx_word_bad || host_rx_data != 32'h0000b588;
            5: rx_word_bad = rx_word_bad || host_rx_data != MAGIC;
            6: rx_word_bad = rx_word_bad || host_rx_data != {8'd0, 2'd0, rx_word_count, PEER, 8'd2};
            default: rx_word_bad = rx_word_bad;
        endcase
    end
    assign packet_rx = rx_packet;
    assign packet_rx_words = rx_word_count;
    assign packet_rx_valid = live && rx_busy;
    assign rx_packet_delivered = packet_rx_valid && packet_rx_ready;
    assign rx_frame_accepted = host_rx_take && host_rx_last && !rx_word_bad;
    always @(posedge clock or negedge host_cold_n) begin
        if (!host_cold_n) begin
            rx_packet <= 0; rx_busy <= 0; rx_word_count <= 0; rx_index <= 0;
            rx_protocol_fault <= 0;
        end else begin
            if (host_rx_take) begin
                if (rx_word_bad) rx_protocol_fault <= 1;
                else begin
                    if (rx_index == 0) begin
                        rx_word_count <= host_rx_data == 32'd68 ? 6'd11 : 6'd32;
                        rx_packet <= 0;
                    end
                    if (rx_index >= 6'd7) rx_packet[(rx_index - 6'd7)*32 +: 32] <= host_rx_data;
                    if (host_rx_last) begin rx_busy <= 1; rx_index <= 0; end
                    else rx_index <= rx_index + 1'b1;
                end
            end
            if (rx_packet_delivered) rx_busy <= 0;
        end
    end

    wire dma_invalid;
    wire [7:0] dma_tx_data;
    wire dma_tx_valid, dma_tx_last, dma_rx_ready;
    always @(posedge clock or negedge host_cold_n) begin
        if (!host_cold_n) dma_invalid_seen <= 0;
        else if (dma_invalid) dma_invalid_seen <= 1;
    end

    // Host ownership gates use only control-clock status; byte gates use their
    // own direction guard. Retained DMA cursors cannot restart after a fault,
    // even if active recovers before the host observes the synchronized cause.
    assign tx_data = dma_tx_data;
    assign tx_valid = tx_live && dma_tx_valid;
    assign tx_last = dma_tx_last;
    assign rx_ready = rx_live && dma_rx_ready;
    ethernet_dma_packets bridge(
        .clock(clock), .reset_n(cold_reset_n), .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_active_n(tx_live), .rx_active_n(rx_live),
        .host_tx_data(host_tx_data), .host_tx_valid(host_tx_valid),
        .host_tx_last(host_tx_last), .host_tx_ready(host_tx_ready),
        .host_rx_data(host_rx_data), .host_rx_valid(host_rx_valid),
        .host_rx_last(host_rx_last), .host_rx_ready(host_rx_ready),
        .tx_data(dma_tx_data), .tx_valid(dma_tx_valid), .tx_last(dma_tx_last),
        .tx_ready(tx_ready && tx_live), .rx_data(rx_data), .rx_valid(rx_valid && rx_live),
        .rx_last(rx_last), .rx_ready(dma_rx_ready), .tx_invalid(dma_invalid)
    );
endmodule

// One clock owns readiness, arm acknowledgement and irreversible stop. Thirteen
// bits: three two-stage reset releases, arm/stop synchronizers (four), and three
// retained flags. Active settling before the local arm handoff is harmless.
// After local_armed, even sub-clock active loss asynchronously clears health_held
// and it cannot recover before cold reset. No active/fault signal resets the
// retained CDC slot: only its direction cursor is held stopped by live=0.
module domain_link_direction(
    input wire local_clock, cold_reset_n, active_n, local_fault,
    input wire host_arm, host_stop,
    output wire local_cold_n, ready, active_lost, live,
    output reg local_armed
);
    wire active_release_n, run_release_n;
    zynq_probe_reset cold_release(local_clock, cold_reset_n, local_cold_n);
    zynq_probe_reset active_release(local_clock, local_cold_n && active_n, active_release_n);
    (* ASYNC_REG="TRUE" *) reg arm_meta, arm_sync, stop_meta, stop_sync;
    reg stopped, health_held;
    wire health_reset_n = local_cold_n && active_n;
    always @(posedge local_clock or negedge health_reset_n) begin
        if (!health_reset_n) health_held <= 0;
        else if (!local_armed) health_held <= 1;
    end
    always @(posedge local_clock or negedge local_cold_n) begin
        if (!local_cold_n) begin
            arm_meta <= 0; arm_sync <= 0; stop_meta <= 0; stop_sync <= 0;
            local_armed <= 0; stopped <= 0;
        end else begin
            arm_meta <= host_arm; arm_sync <= arm_meta;
            stop_meta <= host_stop; stop_sync <= stop_meta;
            if (arm_sync && ready) local_armed <= 1;
            if (local_fault || stop_sync) stopped <= 1;
        end
    end
    assign active_lost = local_armed && !health_held;
    // The only asynchronous functional assertion is reset. Its release is local
    // and synchronized; active recovery cannot release a post-arm loss.
    zynq_probe_reset run_release(local_clock,
        local_cold_n && active_n && !active_lost && !local_fault && !stop_sync && !stopped,
        run_release_n);
    assign ready = active_release_n && run_release_n;
    assign live = local_armed && ready;
endmodule
