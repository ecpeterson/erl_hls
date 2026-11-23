// One role of the two-board actor fixture. The application and its serial
// credit link run at the 25-MHz PS fabric clock. Complete link packets cross
// into the independent 1000BASE-X domains as checked private Ethernet frames.
// Bank 0 is the local application stream. Bank 1 fabric-routes the passive
// debug monitor as endpoint 1, matching the public BEAM debug client contract.
// Instrumented scheduler-RAM builds add endpoint 2 without altering any
// observed ready path: it counts graph output and scheduler memory requests.
module te0715_partition_link_top #(
    parameter [7:0] ROLE = 8'd1,
    parameter DEBUG_PRIVATE_LINK = 1'b0
) (
    input wire ref_p, ref_n, gt_rx_p, gt_rx_n,
    output wire gt_tx_p, gt_tx_n
);
    wire [3:0] fclk, freset_n;
    wire clock, gp_reset_n, reset_n;
    wire [11:0] awid, wid, bid, arid, rid;
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [3:0] awlen, arlen, wstrb;
    wire [1:0] awsize, arsize, awburst, arburst, awlock, arlock, bresp, rresp;
    wire awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire arvalid, arready, rvalid, rready, rlast;
    wire [1:0] irq;

    wire [63:0] dma_tx_data, dma_rx_data;
    wire [1:0] dma_tx_last, dma_tx_valid, dma_tx_ready;
    wire [1:0] dma_rx_last, dma_rx_valid, dma_rx_ready;
    wire [32:0] app_in = {dma_tx_last[0], dma_tx_data[31:0]};
    wire app_in_ready;
    wire [32:0] app_out;
    wire app_out_valid;
    assign dma_tx_ready[0] = app_in_ready;
    assign dma_rx_data[31:0] = app_out[31:0];
    assign dma_rx_last[0] = app_out[32];
    assign dma_rx_valid[0] = app_out_valid;

    wire [32:0] link_out, link_in;
    wire link_out_valid, link_out_ready, link_in_valid, link_in_ready;
    wire [31:0] application_fault;
    wire application_fault_valid;
`ifdef HLS_SCHEDULER_PROBE
    wire [4:0] scheduler_probe;
`endif
    link_application application(
        .clk(clock), .reset(!reset_n),
        ._link_0_in(link_in), ._link_0_in_vld(link_in_valid),
        ._link_0_in_rdy(link_in_ready),
        ._link_0_out(link_out), ._link_0_out_vld(link_out_valid),
        ._link_0_out_rdy(link_out_ready),
        ._fault_0_out(application_fault),
        ._fault_0_out_vld(application_fault_valid), ._fault_0_out_rdy(1'b1),
        ._app_in(app_in), ._app_in_vld(dma_tx_valid[0]), ._app_in_rdy(app_in_ready),
        ._app_out(app_out), ._app_out_vld(app_out_valid),
        ._app_out_rdy(dma_rx_ready[0])
`ifdef HLS_SCHEDULER_PROBE
        , ._scheduler_probe(scheduler_probe)
`endif
    );

`ifdef HLS_SCHEDULER_PROBE
    localparam integer DEBUG_PORTS = 2;
    localparam [31:0] DEBUG_ENDPOINTS = {16'd2, 16'd1};
`elsif HLS_PACKET_PROBE
    localparam integer DEBUG_PORTS = 2;
    localparam [31:0] DEBUG_ENDPOINTS = {16'd2, 16'd1};
`else
    localparam integer DEBUG_PORTS = 1;
    localparam [15:0] DEBUG_ENDPOINTS = 16'd1;
`endif
    wire [32:0] debug_local_in;
    wire [3:0] debug_local_keep_in;
    wire [DEBUG_PORTS-1:0] debug_local_in_valid, debug_local_in_ready;
    wire [32*DEBUG_PORTS-1:0] debug_local_out_data;
    wire [4*DEBUG_PORTS-1:0] debug_local_out_keep;
    wire [DEBUG_PORTS-1:0] debug_local_out_last;
    wire [DEBUG_PORTS-1:0] debug_local_out_valid, debug_local_out_ready;
    wire [31:0] debug_rx_data = DEBUG_PRIVATE_LINK ? link_out[31:0] : dma_tx_data[31:0];
    wire debug_rx_valid = DEBUG_PRIVATE_LINK ? link_out_valid : dma_tx_valid[0];
    wire debug_rx_ready = DEBUG_PRIVATE_LINK ? link_out_ready : dma_tx_ready[0];
    wire debug_rx_last = DEBUG_PRIVATE_LINK ? link_out[32] : dma_tx_last[0];
    wire [31:0] debug_tx_data = DEBUG_PRIVATE_LINK ? link_in[31:0] : dma_rx_data[31:0];
    wire debug_tx_valid = DEBUG_PRIVATE_LINK ? link_in_valid : dma_rx_valid[0];
    wire debug_tx_ready = DEBUG_PRIVATE_LINK ? link_in_ready : dma_rx_ready[0];
    wire debug_tx_last = DEBUG_PRIVATE_LINK ? link_in[32] : dma_rx_last[0];
    hls_fabric_ingress #(.PORTS(DEBUG_PORTS), .ENDPOINTS(DEBUG_ENDPOINTS)) debug_ingress(
        .clk(clock), .reset(!reset_n),
        .s_data(dma_tx_data[63:32]), .s_keep(4'hf), .s_last(dma_tx_last[1]),
        .s_valid(dma_tx_valid[1]), .s_ready(dma_tx_ready[1]),
        .m_data(debug_local_in[31:0]), .m_keep(debug_local_keep_in),
        .m_last(debug_local_in[32]), .m_source(), .m_valid(debug_local_in_valid),
        .m_ready(debug_local_in_ready), .route_error()
    );
    hls_fabric_egress #(.PORTS(DEBUG_PORTS), .ENDPOINTS(DEBUG_ENDPOINTS)) debug_egress(
        .clk(clock), .reset(!reset_n),
        .s_data(debug_local_out_data), .s_keep(debug_local_out_keep),
        .s_last(debug_local_out_last), .s_valid(debug_local_out_valid),
        .s_destination({DEBUG_PORTS{16'd0}}), .s_ready(debug_local_out_ready),
        .m_data(dma_rx_data[63:32]), .m_keep(), .m_last(dma_rx_last[1]),
        .m_valid(dma_rx_valid[1]), .m_ready(dma_rx_ready[1])
    );
    hls_debug_monitor #(.ROUTED(1)) debug(
        .aclk(clock), .aresetn(reset_n),
        .app_rx_tdata(debug_rx_data), .app_rx_tvalid(debug_rx_valid),
        .app_rx_tready(debug_rx_ready), .app_rx_tlast(debug_rx_last),
        .app_tx_tdata(debug_tx_data), .app_tx_tvalid(debug_tx_valid),
        .app_tx_tready(debug_tx_ready), .app_tx_tlast(debug_tx_last),
        .s_dbg_tdata(debug_local_in[31:0]), .s_dbg_tkeep(debug_local_keep_in),
        .s_dbg_tvalid(debug_local_in_valid[0]), .s_dbg_tready(debug_local_in_ready[0]),
        .s_dbg_tlast(debug_local_in[32]),
        .m_dbg_tdata(debug_local_out_data[31:0]), .m_dbg_tkeep(debug_local_out_keep[3:0]),
        .m_dbg_tvalid(debug_local_out_valid[0]), .m_dbg_tready(debug_local_out_ready[0]),
        .m_dbg_tlast(debug_local_out_last[0])
    );
`ifdef HLS_SCHEDULER_PROBE
    // Each accepted synthetic one-beat event records the five raw probe flags
    // in trace tx_id: state read/write, mailbox read/write, mailbox snapshot.
    wire scheduler_activity = |scheduler_probe[3:0];
    wire [31:0] scheduler_activity_data =
        {8'hd0, 8'h00, 3'b000, scheduler_probe, 8'h00};
    hls_debug_monitor #(.ROUTED(0)) stage_debug(
        .aclk(clock), .aresetn(reset_n),
        .app_rx_tdata(link_out[31:0]), .app_rx_tvalid(link_out_valid),
        .app_rx_tready(link_out_ready), .app_rx_tlast(link_out[32]),
        .app_tx_tdata(scheduler_activity_data), .app_tx_tvalid(scheduler_activity),
        .app_tx_tready(1'b1), .app_tx_tlast(1'b1),
        .s_dbg_tdata(debug_local_in[31:0]), .s_dbg_tkeep(debug_local_keep_in),
        .s_dbg_tvalid(debug_local_in_valid[1]), .s_dbg_tready(debug_local_in_ready[1]),
        .s_dbg_tlast(debug_local_in[32]),
        .m_dbg_tdata(debug_local_out_data[63:32]),
        .m_dbg_tkeep(debug_local_out_keep[7:4]),
        .m_dbg_tvalid(debug_local_out_valid[1]), .m_dbg_tready(debug_local_out_ready[1]),
        .m_dbg_tlast(debug_local_out_last[1])
    );
`endif

    wire [7:0] tx_data, packet_rx_data, bridge_rx_data;
    wire tx_valid, tx_last, tx_ready;
    wire packet_rx_valid, packet_rx_last, packet_rx_ready;
    wire bridge_rx_valid, bridge_rx_last, bridge_rx_ready;
    wire [31:0] link_packet_fault;
    wire packet_tx_frame_accepted;
    wire packet_rx_frame_accepted;
    wire packet_link_rx_frame_delivered;
    wire pll_reset, gt_reset, user_ready, pll_lock, tx_done, rx_done;
    wire tx_out_clock, rx_out_clock, tx_clock, rx_clock, tx_half_clock, rx_half_clock;
    wire tx_locked, rx_locked, tx_reset_n, rx_reset_n, link_tx, link_rx, align;
    wire [15:0] tx_pins, rx_pins;
    wire [1:0] tx_dispval, tx_dispmode, rx_charisk, rx_disperr;
    wire [31:0] physical_status;
    wire [1:0] packet_tx_queued, packet_rx_queued;
    wire [31:0] packet_tx_accepted, packet_tx_dropped;
    wire [31:0] packet_tx_overflowed, packet_tx_aborted;
    wire [31:0] packet_rx_accepted, packet_rx_dropped;
    wire [31:0] packet_rx_overflowed, packet_rx_aborted;
    wire [31:0] packet_preamble_errors, packet_crc_errors;

    partition_link_packets #(.ROLE(ROLE)) framing(
        .clock(clock), .reset_n(reset_n), .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_active_n(tx_reset_n && link_tx), .rx_active_n(rx_reset_n),
        .link_tx(link_out), .link_tx_valid(link_out_valid), .link_tx_ready(link_out_ready),
        .link_rx(link_in), .link_rx_valid(link_in_valid), .link_rx_ready(link_in_ready),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .rx_data(bridge_rx_data), .rx_valid(bridge_rx_valid),
        .rx_last(bridge_rx_last), .rx_ready(bridge_rx_ready), .fault(link_packet_fault),
        .tx_frame_accepted(packet_tx_frame_accepted),
        .rx_frame_accepted(packet_rx_frame_accepted),
        .link_rx_frame_delivered(packet_link_rx_frame_delivered)
    );

    // Preserve a complete endpoint frame while isolating its release decision
    // from the receive CDC slot's RAM write enable.
    reg rx_pipe_valid, rx_pipe_last;
    reg [7:0] rx_pipe_data;
    assign packet_rx_ready = !rx_pipe_valid || bridge_rx_ready;
    assign bridge_rx_valid = rx_pipe_valid;
    assign bridge_rx_last = rx_pipe_last;
    assign bridge_rx_data = rx_pipe_data;
    always @(posedge rx_clock or negedge rx_reset_n) begin
        if (!rx_reset_n) rx_pipe_valid <= 0;
        else if (packet_rx_ready) begin
            rx_pipe_valid <= packet_rx_valid;
            if (packet_rx_valid) begin
                rx_pipe_last <= packet_rx_last;
                rx_pipe_data <= packet_rx_data;
            end
        end
    end

    (* ASYNC_REG="TRUE" *) reg [1:0] done_meta, done_sync;
    (* ASYNC_REG="TRUE" *) reg [1:0] lock_meta, lock_sync;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            done_meta <= 0; done_sync <= 0; lock_meta <= 0; lock_sync <= 0;
        end else begin
            done_meta <= {rx_done, tx_done}; done_sync <= done_meta;
            lock_meta <= {rx_locked, tx_locked}; lock_sync <= lock_meta;
        end
    end
    ethernet_dma_supervised_endpoint packets(
        .control_clk(clock), .reset_n(reset_n), .run(1'b1),
        .pll_lock(pll_lock), .tx_done(done_sync[0] && lock_sync[0]),
        .rx_done(done_sync[1] && lock_sync[1]),
        .pll_reset(pll_reset), .gt_reset(gt_reset), .user_ready(user_ready),
        .status(physical_status),
        .eth_tx_clk(tx_clock), .eth_rx_clk(rx_clock),
        .eth_tx_half_clk(tx_half_clock), .eth_rx_half_clk(rx_half_clock),
        .tx_reset_n(tx_reset_n), .rx_reset_n(rx_reset_n),
        .gt_tx_data(tx_pins), .gt_tx_dispval(tx_dispval), .gt_tx_dispmode(tx_dispmode),
        .gt_rx_data(rx_pins), .gt_rx_charisk(rx_charisk), .gt_rx_disperr(rx_disperr),
        .gt_align(align), .link_tx(link_tx), .link_rx(link_rx),
        .tx_valid(tx_valid), .tx_last(tx_last), .tx_data(tx_data), .tx_ready(tx_ready),
        .rx_valid(packet_rx_valid), .rx_last(packet_rx_last),
        .rx_data(packet_rx_data), .rx_ready(packet_rx_ready),
        .tx_queued(packet_tx_queued), .rx_queued(packet_rx_queued),
        .tx_accepted(packet_tx_accepted), .tx_dropped(packet_tx_dropped),
        .tx_overflowed(packet_tx_overflowed), .tx_aborted(packet_tx_aborted),
        .rx_accepted(packet_rx_accepted), .rx_dropped(packet_rx_dropped),
        .rx_overflowed(packet_rx_overflowed), .rx_aborted(packet_rx_aborted),
        .preamble_errors(packet_preamble_errors), .crc_errors(packet_crc_errors)
    );
`ifdef HLS_PACKET_PROBE
    // Endpoint 2 records the first observed transition at each private packet
    // boundary. Adapter events use op 0xd1 and MAC events use op 0xd2; their
    // bit masks are retained in trace tx_id without entering a ready path.
    wire [5:0] packet_mac_status_async = {
        |packet_crc_errors,
        |packet_preamble_errors,
        (|packet_rx_dropped) | (|packet_rx_overflowed) | (|packet_rx_aborted),
        |packet_rx_accepted,
        (|packet_tx_dropped) | (|packet_tx_overflowed) | (|packet_tx_aborted),
        |packet_tx_accepted
    };
    wire [31:0] packet_event_data;
    wire packet_event_valid;
    partition_packet_probe packet_probe(
        .clock(clock), .reset_n(reset_n),
        .tx_frame_accepted(packet_tx_frame_accepted),
        .rx_frame_accepted(packet_rx_frame_accepted),
        .link_rx_frame_delivered(packet_link_rx_frame_delivered),
        .packet_fault(link_packet_fault[2:0]),
        .tx_link_async(link_tx), .rx_link_async(link_rx),
        .mac_status_async(packet_mac_status_async),
        .event_data(packet_event_data), .event_valid(packet_event_valid)
    );

    hls_debug_monitor #(.ROUTED(0)) packet_debug(
        .aclk(clock), .aresetn(reset_n),
        .app_rx_tdata(link_out[31:0]), .app_rx_tvalid(link_out_valid),
        .app_rx_tready(link_out_ready), .app_rx_tlast(link_out[32]),
        .app_tx_tdata(packet_event_data),
        .app_tx_tvalid(packet_event_valid),
        .app_tx_tready(1'b1), .app_tx_tlast(1'b1),
        .s_dbg_tdata(debug_local_in[31:0]), .s_dbg_tkeep(debug_local_keep_in),
        .s_dbg_tvalid(debug_local_in_valid[1]), .s_dbg_tready(debug_local_in_ready[1]),
        .s_dbg_tlast(debug_local_in[32]),
        .m_dbg_tdata(debug_local_out_data[63:32]),
        .m_dbg_tkeep(debug_local_out_keep[7:4]),
        .m_dbg_tvalid(debug_local_out_valid[1]), .m_dbg_tready(debug_local_out_ready[1]),
        .m_dbg_tlast(debug_local_out_last[1])
    );
`endif
    ethernet_gtx_clocks clocks(
        .clock(clock), .reset_n(reset_n), .gt_reset(gt_reset),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock),
        .tx_clock(tx_clock), .rx_clock(rx_clock),
        .tx_half_clock(tx_half_clock), .rx_half_clock(rx_half_clock),
        .tx_locked(tx_locked), .rx_locked(rx_locked)
    );
    te0715_gtx_channel #(.PRBS(0), .EXTERNAL(1)) transceiver(
        .clock(clock), .ref_p(ref_p), .ref_n(ref_n),
        .gt_rx_p(gt_rx_p), .gt_rx_n(gt_rx_n), .gt_tx_p(gt_tx_p), .gt_tx_n(gt_tx_n),
        .pll_reset(pll_reset), .gt_reset(gt_reset),
        .user_ready(user_ready && tx_locked && rx_locked),
        .force_error(1'b0), .measure(1'b0), .align(align),
        .tx_clock(tx_half_clock), .rx_clock(rx_half_clock),
        .tx_data(tx_pins), .tx_dispval(tx_dispval), .tx_dispmode(tx_dispmode),
        .rx_data(rx_pins), .rx_charisk(rx_charisk), .rx_disperr(rx_disperr),
        .pll_lock(pll_lock), .tx_done(tx_done), .rx_done(rx_done),
        .tx_out_clock(tx_out_clock), .rx_out_clock(rx_out_clock)
    );

    BUFG fabric_clock(.I(fclk[0]), .O(clock));
    zynq_probe_reset reset_sync(.clock(clock),
        .reset_n_async(freset_n[0] && gp_reset_n), .reset_n(reset_n));
    zynq_dma_pair transport(
        .clock(clock), .reset_n(reset_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize({1'b0, awsize}),
        .awburst(awburst), .awlock(awlock), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready), .bid(bid), .bresp(bresp),
        .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize({1'b0, arsize}),
        .arburst(arburst), .arlock(arlock), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .tx_data(dma_tx_data), .tx_last(dma_tx_last),
        .tx_valid(dma_tx_valid), .tx_ready(dma_tx_ready),
        .rx_data(dma_rx_data), .rx_last(dma_rx_last),
        .rx_valid(dma_rx_valid), .rx_ready(dma_rx_ready), .irq(irq)
    );
    PS7 processor(
        .FCLKCLK(fclk), .FCLKRESETN(freset_n), .FCLKCLKTRIGN(4'b0),
        .FPGAIDLEN(1'b1), .DDRARB(4'b0), .IRQF2P({18'b0, irq}),
        .MAXIGP0ACLK(clock), .MAXIGP0ARESETN(gp_reset_n),
        .MAXIGP0AWID(awid), .MAXIGP0AWADDR(awaddr), .MAXIGP0AWLEN(awlen),
        .MAXIGP0AWSIZE(awsize), .MAXIGP0AWBURST(awburst), .MAXIGP0AWLOCK(awlock),
        .MAXIGP0AWVALID(awvalid), .MAXIGP0AWREADY(awready),
        .MAXIGP0WID(wid), .MAXIGP0WDATA(wdata), .MAXIGP0WSTRB(wstrb),
        .MAXIGP0WLAST(wlast), .MAXIGP0WVALID(wvalid), .MAXIGP0WREADY(wready),
        .MAXIGP0BID(bid), .MAXIGP0BRESP(bresp), .MAXIGP0BVALID(bvalid), .MAXIGP0BREADY(bready),
        .MAXIGP0ARID(arid), .MAXIGP0ARADDR(araddr), .MAXIGP0ARLEN(arlen),
        .MAXIGP0ARSIZE(arsize), .MAXIGP0ARBURST(arburst), .MAXIGP0ARLOCK(arlock),
        .MAXIGP0ARVALID(arvalid), .MAXIGP0ARREADY(arready),
        .MAXIGP0RID(rid), .MAXIGP0RDATA(rdata), .MAXIGP0RRESP(rresp),
        .MAXIGP0RLAST(rlast), .MAXIGP0RVALID(rvalid), .MAXIGP0RREADY(rready)
    );
endmodule
