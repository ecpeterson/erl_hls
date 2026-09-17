// Safety on the real generated Observer/DebugServer composition. No request
// well-formedness, input-stability, or eventual output-readiness assumption.
// The only startup boundary is a sampled synchronous reset. Later resets are
// arbitrary; this property does not promise to preserve an interrupted reply.
module hls_debug_sampling_formal (
    input clk, reset,
    input [103:0] observation,
    input [31:0] request_data,
    input [3:0] request_keep,
    input request_valid, request_last, response_ready,
    output bad
);
    wire observation_ready;
    reg initialized = 0;
    always @(posedge clk)
        if (reset) initialized <= 1;

    hls_debug_capture dut (
        .aclk(clk), .aresetn(!reset),
        .observation_data(observation), .observation_valid(!reset),
        .observation_ready(observation_ready),
        .s_dbg_tdata(request_data), .s_dbg_tkeep(request_keep),
        .s_dbg_tvalid(request_valid), .s_dbg_tlast(request_last),
        .m_dbg_tready(response_ready)
    );

    // Production's passive tap offers a sample on every non-reset cycle.
    // Its cumulative drop counter therefore stays zero if this cannot occur.
    assign bad = initialized && !reset && !observation_ready;
endmodule
