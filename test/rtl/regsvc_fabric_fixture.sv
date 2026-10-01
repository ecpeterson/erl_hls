// Single-device service fixture. Both streams route independently; ordinary
// regsvc endpoints return to the host (endpoint zero). Port zero is the least
// significant ENDPOINTS element. The default remains the two-service example.
module regsvc_fabric_fixture #(
    parameter integer PORTS = 2,
    parameter [16*PORTS-1:0] ENDPOINTS = {16'd2,16'd1}
) (
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
    wire [31:0] app_in_data;
    wire [3:0] app_in_keep;
    wire app_in_last;
    wire [PORTS-1:0] app_in_valid, app_in_ready;
    wire [32*PORTS-1:0] app_out_data;
    wire [4*PORTS-1:0] app_out_keep;
    wire [PORTS-1:0] app_out_last, app_out_valid, app_out_ready;
    hls_fabric_ingress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) app_ingress (
        .clk(aclk),.reset(!aresetn),
        .s_data(s_axis_tdata),.s_keep(s_axis_tkeep),.s_last(s_axis_tlast),
        .s_valid(s_axis_tvalid),.s_ready(s_axis_tready),
        .m_data(app_in_data),.m_keep(app_in_keep),.m_last(app_in_last),
        .m_valid(app_in_valid),.m_ready(app_in_ready),.m_source(),.route_error()
    );
    hls_fabric_egress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) app_egress (
        .clk(aclk),.reset(!aresetn),
        .s_data(app_out_data),.s_keep(app_out_keep),.s_last(app_out_last),
        .s_valid(app_out_valid),.s_ready(app_out_ready),.s_destination({16*PORTS{1'b0}}),
        .m_data(m_axis_tdata),.m_keep(m_axis_tkeep),.m_last(m_axis_tlast),
        .m_valid(m_axis_tvalid),.m_ready(m_axis_tready)
    );

    wire [31:0] debug_in_data;
    wire [3:0] debug_in_keep;
    wire debug_in_last;
    wire [PORTS-1:0] debug_in_valid, debug_in_ready;
    wire [32*PORTS-1:0] debug_out_data;
    wire [4*PORTS-1:0] debug_out_keep;
    wire [PORTS-1:0] debug_out_last, debug_out_valid, debug_out_ready;
    hls_fabric_ingress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) debug_ingress (
        .clk(aclk),.reset(!aresetn),
        .s_data(s_dbg_tdata),.s_keep(s_dbg_tkeep),.s_last(s_dbg_tlast),
        .s_valid(s_dbg_tvalid),.s_ready(s_dbg_tready),
        .m_data(debug_in_data),.m_keep(debug_in_keep),.m_last(debug_in_last),
        .m_valid(debug_in_valid),.m_ready(debug_in_ready),.m_source(),.route_error()
    );
    hls_fabric_egress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) debug_egress (
        .clk(aclk),.reset(!aresetn),
        .s_data(debug_out_data),.s_keep(debug_out_keep),.s_last(debug_out_last),
        .s_valid(debug_out_valid),.s_ready(debug_out_ready),.s_destination({16*PORTS{1'b0}}),
        .m_data(m_dbg_tdata),.m_keep(m_dbg_tkeep),.m_last(m_dbg_tlast),
        .m_valid(m_dbg_tvalid),.m_ready(m_dbg_tready)
    );

    genvar p;
    generate for(p=0;p<PORTS;p=p+1) begin: endpoint
        axis_regsvc_debug_top service (
            .aclk(aclk),.aresetn(aresetn),

            .s_axis_tdata(app_in_data),
            .s_axis_tkeep(app_in_keep),
            .s_axis_tlast(app_in_last),
            .s_axis_tvalid(app_in_valid[p]),
            .s_axis_tready(app_in_ready[p]),
            .m_axis_tdata(app_out_data[32*p+:32]),
            .m_axis_tkeep(app_out_keep[4*p+:4]),
            .m_axis_tlast(app_out_last[p]),
            .m_axis_tvalid(app_out_valid[p]),
            .m_axis_tready(app_out_ready[p]),
            .s_dbg_tdata(debug_in_data),
            .s_dbg_tkeep(debug_in_keep),
            .s_dbg_tlast(debug_in_last),
            .s_dbg_tvalid(debug_in_valid[p]),
            .s_dbg_tready(debug_in_ready[p]),
            .m_dbg_tdata(debug_out_data[32*p+:32]),
            .m_dbg_tkeep(debug_out_keep[4*p+:4]),
            .m_dbg_tlast(debug_out_last[p]),
            .m_dbg_tvalid(debug_out_valid[p]),
            .m_dbg_tready(debug_out_ready[p])
        );
    end endgenerate
endmodule
