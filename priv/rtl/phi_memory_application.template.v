// Gateway, independent host serializer, and scheduler memories.
    wire [32:0] routed_in = {s_axis_tlast, s_axis_tdata};
    wire [143:0] routed_frame_out;
    wire         routed_frame_out_valid;
    wire         routed_frame_out_ready;
    wire [32:0] routed_out;

@SCHEDULER_WIRES@
    __phi_memory_gateway__Top_0_next application (
        .clk(aclk),
        .reset(!aresetn),
        ._routed_in(routed_in),
        ._routed_in_vld(s_axis_tvalid),
        ._routed_in_rdy(s_axis_tready),
        ._routed_frame_out(routed_frame_out),
        ._routed_frame_out_vld(routed_frame_out_valid),
        ._routed_frame_out_rdy(routed_frame_out_ready)@APPLICATION_RAM_PORTS@
    );

    __hls_fabric_router__HostRoutedTx_0_next application_egress (
        .clk(aclk),
        .reset(!aresetn),
        ._frame_in(routed_frame_out),
        ._frame_in_vld(routed_frame_out_valid),
        ._frame_in_rdy(routed_frame_out_ready),
        ._routed_out(routed_out),
        ._routed_out_vld(m_axis_tvalid),
        ._routed_out_rdy(m_axis_tready)
    );

@SCHEDULER_RAMS@
    assign m_axis_tdata = routed_out[31:0];
    assign m_axis_tlast = routed_out[32];
    assign m_axis_tkeep = 4'hf;
