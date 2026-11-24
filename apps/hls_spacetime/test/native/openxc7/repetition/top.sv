// Compile-only N2 boundary. Both streams and all six fault flags stay observable.
// failure_actor selects one combinational failure word in the same clock interval.
module top(input wire clk, reset, input wire [31:0] s_app_tdata,
    input wire s_app_tlast, s_app_tvalid, output wire s_app_tready,
    output wire [31:0] m_app_tdata, output wire m_app_tlast, m_app_tvalid,
    input wire m_app_tready, output wire startup_done, running, ingress_fault,
    output wire [5:0] fault, input wire [2:0] failure_actor, output wire [15:0] failure);
    wire [15:0] words [0:5];
    assign failure = failure_actor < 6 ? words[failure_actor] : 16'b0;

    spacetime_native_top application (
        .clk(clk), .reset(reset), .s_app_tdata(s_app_tdata), .s_app_tlast(s_app_tlast),
        .s_app_tvalid(s_app_tvalid), .s_app_tready(s_app_tready), .m_app_tdata(m_app_tdata),
        .m_app_tlast(m_app_tlast), .m_app_tvalid(m_app_tvalid), .m_app_tready(m_app_tready),
        .startup_done(startup_done), .running(running), .ingress_fault(ingress_fault),
        .actor_0_fault(fault[0]), .actor_0_failure(words[0]),
        .actor_1_fault(fault[1]), .actor_1_failure(words[1]),
        .actor_2_fault(fault[2]), .actor_2_failure(words[2]),
        .actor_3_fault(fault[3]), .actor_3_failure(words[3]),
        .actor_4_fault(fault[4]), .actor_4_failure(words[4]),
        .actor_5_fault(fault[5]), .actor_5_failure(words[5]));
endmodule
