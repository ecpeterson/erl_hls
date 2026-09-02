// Routed phi-memory gateway plus the shared passive boundary monitor. The
// application gateway owns endpoint 1 on its application stream. The debug
// stream uses the existing two-endpoint router fixture with endpoint 1 active;
// endpoint 2 is tied off until debug endpoint allocation is generated.
module phi_memory_debug_top (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    output wire [31:0] m_axis_tdata,
    output wire [3:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,

    input  wire [31:0] s_dbg_tdata,
    input  wire [3:0]  s_dbg_tkeep,
    input  wire        s_dbg_tvalid,
    output wire        s_dbg_tready,
    input  wire        s_dbg_tlast,

    output wire [31:0] m_dbg_tdata,
    output wire [3:0]  m_dbg_tkeep,
    output wire        m_dbg_tvalid,
    input  wire        m_dbg_tready,
    output wire        m_dbg_tlast
);
    wire [32:0] routed_in = {s_axis_tlast, s_axis_tdata};
    wire [32:0] routed_out;

    wire [32:0] debug_shared_in = {s_dbg_tlast, s_dbg_tdata};
    wire [32:0] debug_shared_out;
    wire [32:0] debug_local_in;
    wire [32:0] debug_local_out;
    wire        debug_local_in_valid;
    wire        debug_local_in_ready;
    wire        debug_local_out_valid;
    wire        debug_local_out_ready;

    wire [31:0] data_state_addr;
    wire [441:0] data_state_wr_data;
    wire data_state_we;
    wire data_state_re;
    wire [441:0] data_state_rd_data;
    wire [31:0] data_mailbox_addr;
    wire [127:0] data_mailbox_wr_data;
    wire data_mailbox_we;
    wire data_mailbox_re;
    wire [127:0] data_mailbox_rd_data;

    wire [31:0] phi_state_addr;
    wire [553:0] phi_state_wr_data;
    wire phi_state_we;
    wire phi_state_re;
    wire [553:0] phi_state_rd_data;
    wire [31:0] phi_mailbox_addr;
    wire [127:0] phi_mailbox_wr_data;
    wire phi_mailbox_we;
    wire phi_mailbox_re;
    wire [127:0] phi_mailbox_rd_data;

    wire [31:0] syndrome_state_addr;
    wire [441:0] syndrome_state_wr_data;
    wire syndrome_state_we;
    wire syndrome_state_re;
    wire [441:0] syndrome_state_rd_data;
    wire [31:0] syndrome_mailbox_addr;
    wire [127:0] syndrome_mailbox_wr_data;
    wire syndrome_mailbox_we;
    wire syndrome_mailbox_re;
    wire [127:0] syndrome_mailbox_rd_data;

    __phi_memory_gateway__Top_0_next application (
        .clk(aclk),
        .reset(!aresetn),
        ._routed_in(routed_in),
        ._routed_in_vld(s_axis_tvalid),
        ._routed_in_rdy(s_axis_tready),
        ._routed_out(routed_out),
        ._routed_out_vld(m_axis_tvalid),
        ._routed_out_rdy(m_axis_tready),
        .scheduler_0_state_addr(data_state_addr),
        .scheduler_0_state_wr_data(data_state_wr_data),
        .scheduler_0_state_we(data_state_we),
        .scheduler_0_state_re(data_state_re),
        .scheduler_0_state_rd_data(data_state_rd_data),
        .scheduler_0_mailbox_addr(data_mailbox_addr),
        .scheduler_0_mailbox_wr_data(data_mailbox_wr_data),
        .scheduler_0_mailbox_we(data_mailbox_we),
        .scheduler_0_mailbox_re(data_mailbox_re),
        .scheduler_0_mailbox_rd_data(data_mailbox_rd_data),
        .scheduler_1_state_addr(phi_state_addr),
        .scheduler_1_state_wr_data(phi_state_wr_data),
        .scheduler_1_state_we(phi_state_we),
        .scheduler_1_state_re(phi_state_re),
        .scheduler_1_state_rd_data(phi_state_rd_data),
        .scheduler_1_mailbox_addr(phi_mailbox_addr),
        .scheduler_1_mailbox_wr_data(phi_mailbox_wr_data),
        .scheduler_1_mailbox_we(phi_mailbox_we),
        .scheduler_1_mailbox_re(phi_mailbox_re),
        .scheduler_1_mailbox_rd_data(phi_mailbox_rd_data),
        .scheduler_2_state_addr(syndrome_state_addr),
        .scheduler_2_state_wr_data(syndrome_state_wr_data),
        .scheduler_2_state_we(syndrome_state_we),
        .scheduler_2_state_re(syndrome_state_re),
        .scheduler_2_state_rd_data(syndrome_state_rd_data),
        .scheduler_2_mailbox_addr(syndrome_mailbox_addr),
        .scheduler_2_mailbox_wr_data(syndrome_mailbox_wr_data),
        .scheduler_2_mailbox_we(syndrome_mailbox_we),
        .scheduler_2_mailbox_re(syndrome_mailbox_re),
        .scheduler_2_mailbox_rd_data(syndrome_mailbox_rd_data)
    );

    hls_1rw_ram #(.WIDTH(442), .ADDRESS_WIDTH(5)) data_state (
        .clk(aclk),
        .addr(data_state_addr[4:0]),
        .wr_data(data_state_wr_data),
        .we(data_state_we),
        .re(data_state_re),
        .rd_data(data_state_rd_data)
    );

    hls_1rw_ram #(.WIDTH(554), .ADDRESS_WIDTH(5)) phi_state (
        .clk(aclk),
        .addr(phi_state_addr[4:0]),
        .wr_data(phi_state_wr_data),
        .we(phi_state_we),
        .re(phi_state_re),
        .rd_data(phi_state_rd_data)
    );

    hls_1rw_ram #(.WIDTH(442), .ADDRESS_WIDTH(5)) syndrome_state (
        .clk(aclk),
        .addr(syndrome_state_addr[4:0]),
        .wr_data(syndrome_state_wr_data),
        .we(syndrome_state_we),
        .re(syndrome_state_re),
        .rd_data(syndrome_state_rd_data)
    );

    hls_1rw_ram #(.WIDTH(128), .ADDRESS_WIDTH(7)) data_mailbox (
        .clk(aclk),
        .addr(data_mailbox_addr[6:0]),
        .wr_data(data_mailbox_wr_data),
        .we(data_mailbox_we),
        .re(data_mailbox_re),
        .rd_data(data_mailbox_rd_data)
    );

    hls_1rw_ram #(.WIDTH(128), .ADDRESS_WIDTH(7)) phi_mailbox (
        .clk(aclk),
        .addr(phi_mailbox_addr[6:0]),
        .wr_data(phi_mailbox_wr_data),
        .we(phi_mailbox_we),
        .re(phi_mailbox_re),
        .rd_data(phi_mailbox_rd_data)
    );

    hls_1rw_ram #(.WIDTH(128), .ADDRESS_WIDTH(7)) syndrome_mailbox (
        .clk(aclk),
        .addr(syndrome_mailbox_addr[6:0]),
        .wr_data(syndrome_mailbox_wr_data),
        .we(syndrome_mailbox_we),
        .re(syndrome_mailbox_re),
        .rd_data(syndrome_mailbox_rd_data)
    );

    __hls_fabric_router__PairIngress_0_next debug_ingress (
        .clk(aclk),
        .reset(!aresetn),
        ._shared_in(debug_shared_in),
        ._shared_in_vld(s_dbg_tvalid),
        ._shared_in_rdy(s_dbg_tready),
        ._endpoint_one_out(debug_local_in),
        ._endpoint_one_out_vld(debug_local_in_valid),
        ._endpoint_one_out_rdy(debug_local_in_ready),
        ._endpoint_two_out(),
        ._endpoint_two_out_vld(),
        ._endpoint_two_out_rdy(1'b1)
    );

    __hls_fabric_router__PairEgress_0_next debug_egress (
        .clk(aclk),
        .reset(!aresetn),
        ._endpoint_one_in(debug_local_out),
        ._endpoint_one_in_vld(debug_local_out_valid),
        ._endpoint_one_in_rdy(debug_local_out_ready),
        ._endpoint_two_in(33'b0),
        ._endpoint_two_in_vld(1'b0),
        ._endpoint_two_in_rdy(),
        ._shared_out(debug_shared_out),
        ._shared_out_vld(m_dbg_tvalid),
        ._shared_out_rdy(m_dbg_tready)
    );

    hls_debug_monitor debug_monitor (
        .aclk(aclk),
        .aresetn(aresetn),
        .app_rx_tdata(s_axis_tdata),
        .app_rx_tvalid(s_axis_tvalid),
        .app_rx_tready(s_axis_tready),
        .app_rx_tlast(s_axis_tlast),
        .app_tx_tdata(routed_out[31:0]),
        .app_tx_tvalid(m_axis_tvalid),
        .app_tx_tready(m_axis_tready),
        .app_tx_tlast(routed_out[32]),
        .s_dbg_tdata(debug_local_in[31:0]),
        .s_dbg_tkeep(4'hf),
        .s_dbg_tvalid(debug_local_in_valid),
        .s_dbg_tready(debug_local_in_ready),
        .s_dbg_tlast(debug_local_in[32]),
        .m_dbg_tdata(debug_local_out[31:0]),
        .m_dbg_tkeep(),
        .m_dbg_tvalid(debug_local_out_valid),
        .m_dbg_tready(debug_local_out_ready),
        .m_dbg_tlast(debug_local_out[32])
    );

    assign m_axis_tdata = routed_out[31:0];
    assign m_axis_tlast = routed_out[32];
    assign m_axis_tkeep = 4'hf;
    assign m_dbg_tdata = debug_shared_out[31:0];
    assign m_dbg_tlast = debug_shared_out[32];
    assign m_dbg_tkeep = 4'hf;

endmodule
