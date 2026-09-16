`timescale 1ns/1ps
// The bridge drives only the two public AXI streams. The monitor observes
// accepted application transfers; neither it nor the host reads internal RTL.
module packed_samples_tb;
    reg clk=0, resetn=0;
    always #5 clk=~clk;
    reg [31:0] s_axis_tdata=0, s_dbg_tdata=0;
    reg [3:0] s_axis_tkeep=15, s_dbg_tkeep=15;
    reg s_axis_tvalid=0, s_axis_tlast=0, s_dbg_tvalid=0, s_dbg_tlast=0;
    reg m_axis_tready=0, m_dbg_tready=0;
    wire s_axis_tready, s_dbg_tready, m_axis_tlast, m_dbg_tlast, m_axis_tvalid, m_dbg_tvalid;
    wire [31:0] m_axis_tdata, m_dbg_tdata;
    wire [3:0] m_axis_tkeep, m_dbg_tkeep;
    wire [31:0] app_in_data, dbg_in_data, dbg_out_data;
    wire [3:0] app_in_keep, dbg_in_keep, dbg_out_keep;
    wire app_in_last, app_in_valid, app_in_ready, app_out_valid, app_out_ready;
    wire dbg_in_last, dbg_in_valid, dbg_in_ready, dbg_out_last, dbg_out_valid, dbg_out_ready;
    wire [32:0] app_out;
    reg allow_app=0;
    wire routed_app_valid;
    assign m_axis_tvalid=routed_app_valid && allow_app;

    hls_debug_route #(.ENDPOINTS(1)) app_route (
        .clk(clk),.reset(!resetn),
        .s_data(s_axis_tdata),.s_keep(s_axis_tkeep),.s_last(s_axis_tlast),.s_valid(s_axis_tvalid),.s_ready(s_axis_tready),
        .m_data(m_axis_tdata),.m_keep(m_axis_tkeep),.m_last(m_axis_tlast),.m_valid(routed_app_valid),.m_ready(m_axis_tready && allow_app),
        .request_data(app_in_data),.request_keep(app_in_keep),.request_last(app_in_last),.request_valid(app_in_valid),.request_ready(app_in_ready),
        .response_data(app_out[31:0]),.response_keep(4'hf),.response_last(app_out[32]),.response_valid(app_out_valid),.response_ready(app_out_ready));
    __packed_samples__Top_0_next application (
        .clk(clk),.reset(!resetn),
        ._ext_recv({app_in_last,app_in_data}),._ext_recv_vld(app_in_valid),._ext_recv_rdy(app_in_ready),
        ._ext_send(app_out),._ext_send_vld(app_out_valid),._ext_send_rdy(app_out_ready));
    hls_debug_route #(.ENDPOINTS(1)) debug_route (
        .clk(clk),.reset(!resetn),
        .s_data(s_dbg_tdata),.s_keep(s_dbg_tkeep),.s_last(s_dbg_tlast),.s_valid(s_dbg_tvalid),.s_ready(s_dbg_tready),
        .m_data(m_dbg_tdata),.m_keep(m_dbg_tkeep),.m_last(m_dbg_tlast),.m_valid(m_dbg_tvalid),.m_ready(m_dbg_tready),
        .request_data(dbg_in_data),.request_keep(dbg_in_keep),.request_last(dbg_in_last),.request_valid(dbg_in_valid),.request_ready(dbg_in_ready),
        .response_data(dbg_out_data),.response_keep(dbg_out_keep),.response_last(dbg_out_last),.response_valid(dbg_out_valid),.response_ready(dbg_out_ready));
    hls_debug_monitor monitor (
        .aclk(clk),.aresetn(resetn),
        .app_rx_tdata(app_in_data),.app_rx_tvalid(app_in_valid),.app_rx_tready(app_in_ready),.app_rx_tlast(app_in_last),
        .app_tx_tdata(app_out[31:0]),.app_tx_tvalid(app_out_valid),.app_tx_tready(app_out_ready),.app_tx_tlast(app_out[32]),
        .s_dbg_tdata(dbg_in_data),.s_dbg_tkeep(dbg_in_keep),.s_dbg_tvalid(dbg_in_valid),.s_dbg_tready(dbg_in_ready),.s_dbg_tlast(dbg_in_last),
        .m_dbg_tdata(dbg_out_data),.m_dbg_tkeep(dbg_out_keep),.m_dbg_tvalid(dbg_out_valid),.m_dbg_tready(dbg_out_ready),.m_dbg_tlast(dbg_out_last));

    // A deliberate output stall is observable through public counters. The
    // host releases it only after recording that diagnosis.
    integer fd;
    reg stalled=0;
    reg [32:0] held;
    always @(posedge clk) if(resetn) begin
        if(stalled && (!app_out_valid || app_out !== held)) $fatal(1,"unstable application reply");
        stalled=app_out_valid && !app_out_ready;
        held=app_out;
    end
    always @(negedge clk) if(resetn) begin
        if(!allow_app) begin
            fd=$fopen("release_app","r");
            if(fd) begin $fclose(fd);allow_app=1;end
        end
        fd=$fopen("done","r");
        if(fd) begin $fclose(fd);$display("PASS: packed samples through public app/debug streams");$finish;end
    end
    initial begin repeat(5) @(negedge clk);resetn=1;end
endmodule
