// Private routed shell retaining requester identity across service calls.
module hls_device_services #(
    parameter integer PORTS = 2,
    parameter integer APP_CONTEXT_SLOTS = 16,
    parameter integer DEBUG_CONTEXT_SLOTS = 16,
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
    wire [15:0] app_source;
    wire [16*PORTS-1:0] app_destination;
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
        .m_valid(app_in_valid),.m_ready(app_in_ready),.m_source(app_source),.route_error()
    );
    hls_fabric_egress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) app_egress (
        .clk(aclk),.reset(!aresetn),
        .s_data(app_out_data),.s_keep(app_out_keep),.s_last(app_out_last),
        .s_valid(app_out_valid),.s_ready(app_out_ready),.s_destination(app_destination),
        .m_data(m_axis_tdata),.m_keep(m_axis_tkeep),.m_last(m_axis_tlast),
        .m_valid(m_axis_tvalid),.m_ready(m_axis_tready)
    );

    wire [15:0] debug_source;
    wire [16*PORTS-1:0] debug_destination;
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
        .m_valid(debug_in_valid),.m_ready(debug_in_ready),.m_source(debug_source),.route_error()
    );
    hls_fabric_egress #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) debug_egress (
        .clk(aclk),.reset(!aresetn),
        .s_data(debug_out_data),.s_keep(debug_out_keep),.s_last(debug_out_last),
        .s_valid(debug_out_valid),.s_ready(debug_out_ready),.s_destination(debug_destination),
        .m_data(m_dbg_tdata),.m_keep(m_dbg_tkeep),.m_last(m_dbg_tlast),
        .m_valid(m_dbg_tvalid),.m_ready(m_dbg_tready)
    );

    genvar p;
    generate for(p=0;p<PORTS;p=p+1) begin: endpoint

        wire [31:0] app_request_data, app_reply_data;
        wire [3:0] app_request_keep, app_reply_keep;
        wire app_request_last, app_request_valid, app_request_ready;
        wire app_reply_last, app_reply_valid, app_reply_ready;
        hls_return_routes #(.SLOTS(APP_CONTEXT_SLOTS), .CAST_TXID(255)) app_contexts (
            .clk(aclk), .reset(!aresetn),
            .s_data(app_in_data), .s_keep(app_in_keep), .s_last(app_in_last),
            .s_valid(app_in_valid[p]), .s_ready(app_in_ready[p]), .s_source(app_source),
            .request_data(app_request_data), .request_keep(app_request_keep),
            .request_last(app_request_last), .request_valid(app_request_valid),
            .request_ready(app_request_ready),
            .reply_data(app_reply_data), .reply_keep(app_reply_keep), .reply_last(app_reply_last),
            .reply_valid(app_reply_valid), .reply_ready(app_reply_ready),
            .m_data(app_out_data[32*p+:32]), .m_keep(app_out_keep[4*p+:4]),
            .m_last(app_out_last[p]), .m_valid(app_out_valid[p]), .m_ready(app_out_ready[p]),
            .m_destination(app_destination[16*p+:16]), .context_busy(), .dropped_reply()
        );

        wire [31:0] debug_request_data, debug_reply_data;
        wire [3:0] debug_request_keep, debug_reply_keep;
        wire debug_request_last, debug_request_valid, debug_request_ready;
        wire debug_reply_last, debug_reply_valid, debug_reply_ready;
        hls_return_routes #(.SLOTS(DEBUG_CONTEXT_SLOTS), .CAST_TXID(-1)) debug_contexts (
            .clk(aclk), .reset(!aresetn),
            .s_data(debug_in_data), .s_keep(debug_in_keep), .s_last(debug_in_last),
            .s_valid(debug_in_valid[p]), .s_ready(debug_in_ready[p]), .s_source(debug_source),
            .request_data(debug_request_data), .request_keep(debug_request_keep),
            .request_last(debug_request_last), .request_valid(debug_request_valid),
            .request_ready(debug_request_ready),
            .reply_data(debug_reply_data), .reply_keep(debug_reply_keep), .reply_last(debug_reply_last),
            .reply_valid(debug_reply_valid), .reply_ready(debug_reply_ready),
            .m_data(debug_out_data[32*p+:32]), .m_keep(debug_out_keep[4*p+:4]),
            .m_last(debug_out_last[p]), .m_valid(debug_out_valid[p]), .m_ready(debug_out_ready[p]),
            .m_destination(debug_destination[16*p+:16]), .context_busy(), .dropped_reply()
        );

        axis_regsvc_debug_top service (
            .aclk(aclk),.aresetn(aresetn),

            .s_axis_tdata(app_request_data),
            .s_axis_tkeep(app_request_keep),
            .s_axis_tlast(app_request_last),
            .s_axis_tvalid(app_request_valid),
            .s_axis_tready(app_request_ready),
            .m_axis_tdata(app_reply_data),
            .m_axis_tkeep(app_reply_keep),
            .m_axis_tlast(app_reply_last),
            .m_axis_tvalid(app_reply_valid),
            .m_axis_tready(app_reply_ready),
            .s_dbg_tdata(debug_request_data),
            .s_dbg_tkeep(debug_request_keep),
            .s_dbg_tlast(debug_request_last),
            .s_dbg_tvalid(debug_request_valid),
            .s_dbg_tready(debug_request_ready),
            .m_dbg_tdata(debug_reply_data),
            .m_dbg_tkeep(debug_reply_keep),
            .m_dbg_tlast(debug_reply_last),
            .m_dbg_tvalid(debug_reply_valid),
            .m_dbg_tready(debug_reply_ready)
        );
    end endgenerate
endmodule
