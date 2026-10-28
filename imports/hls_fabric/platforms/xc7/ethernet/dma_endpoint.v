// Board-only packet endpoint variant with one elastic TX beat between the
// frame store and generated PCS/MAC. The boundary breaks the combinational
// ready path observed in the integrated DMA route; frame semantics are those
// of ethernet_packet_endpoint. This does not replace the reusable endpoint.
module ethernet_dma_packet_endpoint(
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
    wire stored_valid, stored_last, stored_ready;
    wire [7:0] stored_data;
    wire core_tx_ready, mac_valid, mac_last, mac_error;
    wire [7:0] mac_data;
    reg [1:0] pipe_count;
    reg pipe_last_0, pipe_last_1;
    reg [7:0] pipe_data_0, pipe_data_1;
    wire pipe_push=stored_valid && stored_ready;
    wire pipe_pop=pipe_count!=0 && core_tx_ready;
    assign stored_ready=pipe_count!=2;
    always @(posedge eth_tx_clk) begin
        if (eth_tx_rst || !link_tx) pipe_count<=0;
        else case ({pipe_push,pipe_pop})
        2'b10: begin
            if(pipe_count==0) begin pipe_data_0<=stored_data; pipe_last_0<=stored_last; end
            else begin pipe_data_1<=stored_data; pipe_last_1<=stored_last; end
            pipe_count<=pipe_count+1'b1;
        end
        2'b01: begin
            if(pipe_count==2) begin pipe_data_0<=pipe_data_1; pipe_last_0<=pipe_last_1; end
            pipe_count<=pipe_count-1'b1;
        end
        2'b11: begin
            // Simultaneous transfer at occupancy one replaces the head beat.
            pipe_data_0<=stored_data; pipe_last_0<=stored_last;
        end
        default: pipe_count<=pipe_count;
        endcase
    end
    ethernet_frame_store tx_store(
        .clk(eth_tx_clk), .rst(eth_tx_rst), .flush(!link_tx), .abort_partial(1'b0),
        .in_valid(tx_valid), .in_ready(tx_ready), .in_data(tx_data),
        .in_last(tx_last), .in_error(1'b0), .out_valid(stored_valid),
        .out_ready(stored_ready), .out_data(stored_data), .out_last(stored_last),
        .queued(tx_queued), .accepted(tx_accepted), .dropped(tx_dropped),
        .overflowed(tx_overflowed), .aborted(tx_aborted)
    );

    reg from_mac_valid, from_mac_last, from_mac_error;
    reg [7:0] from_mac_data;
    always @(posedge eth_rx_clk) begin
        if(eth_rx_rst || !link_rx) from_mac_valid<=0;
        else from_mac_valid<=mac_valid;
        from_mac_data<=mac_data; from_mac_last<=mac_last; from_mac_error<=mac_error;
    end
    ethernet_frame_store #(.DROP_WHEN_FULL(1), .MIN_BYTES(60)) rx_store(
        .clk(eth_rx_clk), .rst(eth_rx_rst), .flush(1'b0), .abort_partial(!link_rx),
        .in_valid(from_mac_valid), .in_ready(), .in_data(from_mac_data),
        .in_last(from_mac_last), .in_error(from_mac_error), .out_valid(rx_valid),
        .out_ready(rx_ready), .out_data(rx_data), .out_last(rx_last),
        .queued(rx_queued), .accepted(rx_accepted), .dropped(rx_dropped),
        .overflowed(rx_overflowed), .aborted(rx_aborted)
    );
    liteeth_packet_core core(
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .tbi_rx(tbi_rx), .tbi_tx(tbi_tx), .link_tx(link_tx), .link_rx(link_rx),
        .restart(restart), .align(align), .tx_valid(pipe_count!=0),
        .tx_ready(core_tx_ready), .tx_data(pipe_data_0), .tx_last(pipe_last_0),
        .rx_valid(mac_valid), .rx_data(mac_data), .rx_last(mac_last),
        .rx_error(mac_error), .preamble_errors(preamble_errors), .crc_errors(crc_errors)
    );
endmodule

// Adapt the pipelined packet endpoint to the proven raw 20-bit GTX mapping.
module ethernet_dma_gtx_packet_endpoint(
    input wire eth_tx_clk, eth_tx_rst, eth_rx_clk, eth_rx_rst,
    input wire eth_tx_half_clk, eth_tx_half_rst, eth_rx_half_clk, eth_rx_half_rst,
    output wire [15:0] gt_tx_data,
    output wire [1:0] gt_tx_dispval, gt_tx_dispmode,
    input wire [15:0] gt_rx_data,
    input wire [1:0] gt_rx_charisk, gt_rx_disperr,
    output wire gt_align,
    output wire link_tx, link_rx, restart,
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
    wire [9:0] tbi_tx, tbi_rx;
    wire [19:0] tx_word, rx_word;
    wire align;
    assign gt_tx_data={tx_word[17:10],tx_word[7:0]};
    assign gt_tx_dispval={tx_word[18],tx_word[8]};
    assign gt_tx_dispmode={tx_word[19],tx_word[9]};
    assign rx_word={gt_rx_disperr[1],gt_rx_charisk[1],gt_rx_data[15:8],
                    gt_rx_disperr[0],gt_rx_charisk[0],gt_rx_data[7:0]};
    reg align_registered=0;
    always @(posedge eth_tx_clk)
        if(eth_tx_rst) align_registered<=0; else align_registered<=align;
    (* ASYNC_REG="TRUE" *) reg [1:0] align_sync=0;
    always @(posedge eth_rx_half_clk)
        if(eth_rx_half_rst) align_sync<=0; else align_sync<={align_sync[0],align_registered};
    assign gt_align=align_sync[1];
    liteeth_pcs_gearbox gearbox(
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .eth_tx_half_clk(eth_tx_half_clk), .eth_tx_half_rst(eth_tx_half_rst),
        .eth_rx_half_clk(eth_rx_half_clk), .eth_rx_half_rst(eth_rx_half_rst),
        .tx_data(tbi_tx), .tx_data_half(tx_word), .rx_data_half(rx_word), .rx_data(tbi_rx)
    );
    ethernet_dma_packet_endpoint packets(
        .eth_tx_clk(eth_tx_clk), .eth_tx_rst(eth_tx_rst),
        .eth_rx_clk(eth_rx_clk), .eth_rx_rst(eth_rx_rst),
        .tbi_tx(tbi_tx), .tbi_rx(tbi_rx), .align(align),
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
endmodule

// Run the pipelined endpoint under the existing hard-GTX startup controller.
module ethernet_dma_supervised_endpoint #(
    parameter BOOT_CYCLES=32, RESET_CYCLES=8, SETTLE_CYCLES=1024,
    parameter TIMEOUT_CYCLES=25000, CLOCK_TIMEOUT=1024
)(
    input wire control_clk, reset_n, run,
    input wire pll_lock, tx_done, rx_done,
    output wire pll_reset, gt_reset, user_ready,
    output wire [31:0] status,
    input wire eth_tx_clk, eth_rx_clk, eth_tx_half_clk, eth_rx_half_clk,
    output wire tx_reset_n, rx_reset_n,
    output wire [15:0] gt_tx_data,
    output wire [1:0] gt_tx_dispval, gt_tx_dispmode,
    input wire [15:0] gt_rx_data,
    input wire [1:0] gt_rx_charisk, gt_rx_disperr,
    output wire gt_align, link_tx, link_rx, restart,
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
    wire control_reset_n, tx_fresh, rx_fresh, physical_ready;
    zynq_probe_reset cr(control_clk,reset_n,control_reset_n);
    ethernet_clock_pair tx_watch(control_clk,control_reset_n,eth_tx_clk,eth_tx_half_clk,tx_fresh);
    ethernet_clock_pair rx_watch(control_clk,control_reset_n,eth_rx_clk,eth_rx_half_clk,rx_fresh);
    gtx_probe_control #(.BOOT_CYCLES(BOOT_CYCLES),.RESET_CYCLES(RESET_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),
        .CLOCK_TIMEOUT(CLOCK_TIMEOUT)) control(
        .clock(control_clk),.reset_n(control_reset_n),.run(run),
        .pll_lock(pll_lock),.tx_done(tx_done),.rx_done(rx_done),
        .tx_fresh(tx_fresh),.rx_fresh(rx_fresh),.pll_reset(pll_reset),
        .gt_reset(gt_reset),.user_ready(user_ready),.measure(physical_ready),.status(status)
    );
    wire packet_reset_n=reset_n && physical_ready;
    wire tx_half_reset_n, rx_half_reset_n;
    zynq_probe_reset tr(eth_tx_clk,packet_reset_n,tx_reset_n);
    zynq_probe_reset rr(eth_rx_clk,packet_reset_n,rx_reset_n);
    zynq_probe_reset th(eth_tx_half_clk,packet_reset_n,tx_half_reset_n);
    zynq_probe_reset rh(eth_rx_half_clk,packet_reset_n,rx_half_reset_n);
    wire raw_tx_ready, raw_rx_valid, raw_link_tx, raw_link_rx, raw_restart, raw_align;
    assign tx_ready=tx_reset_n && raw_tx_ready;
    assign rx_valid=rx_reset_n && raw_rx_valid;
    assign link_tx=tx_reset_n && raw_link_tx;
    assign link_rx=rx_reset_n && raw_link_rx;
    assign restart=tx_reset_n && raw_restart;
    assign gt_align=rx_half_reset_n && raw_align;
    ethernet_dma_gtx_packet_endpoint packets(
        .eth_tx_clk(eth_tx_clk),.eth_tx_rst(!tx_reset_n),
        .eth_rx_clk(eth_rx_clk),.eth_rx_rst(!rx_reset_n),
        .eth_tx_half_clk(eth_tx_half_clk),.eth_tx_half_rst(!tx_half_reset_n),
        .eth_rx_half_clk(eth_rx_half_clk),.eth_rx_half_rst(!rx_half_reset_n),
        .gt_tx_data(gt_tx_data),.gt_tx_dispval(gt_tx_dispval),.gt_tx_dispmode(gt_tx_dispmode),
        .gt_rx_data(gt_rx_data),.gt_rx_charisk(gt_rx_charisk),.gt_rx_disperr(gt_rx_disperr),
        .gt_align(raw_align),.link_tx(raw_link_tx),.link_rx(raw_link_rx),.restart(raw_restart),
        .tx_valid(tx_valid && tx_reset_n),.tx_last(tx_last),.tx_data(tx_data),.tx_ready(raw_tx_ready),
        .rx_valid(raw_rx_valid),.rx_last(rx_last),.rx_data(rx_data),.rx_ready(rx_ready && rx_reset_n),
        .tx_queued(tx_queued),.rx_queued(rx_queued),
        .tx_accepted(tx_accepted),.tx_dropped(tx_dropped),
        .tx_overflowed(tx_overflowed),.tx_aborted(tx_aborted),
        .rx_accepted(rx_accepted),.rx_dropped(rx_dropped),
        .rx_overflowed(rx_overflowed),.rx_aborted(rx_aborted),
        .preamble_errors(preamble_errors),.crc_errors(crc_errors)
    );
endmodule
