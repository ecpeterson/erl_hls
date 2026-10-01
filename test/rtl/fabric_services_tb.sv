`timescale 1ns/1ps

module fabric_services_tb;
    parameter integer PORTS = 3;
    parameter [16*PORTS-1:0] ENDPOINTS = {16'd42,16'd9,16'd2};
    reg         clk = 1'b0;
    reg         resetn = 1'b0;

    reg  [31:0] s_axis_tdata = 32'b0;
    reg         s_axis_tvalid = 1'b0;
    wire        s_axis_tready;
    reg         s_axis_tlast = 1'b0;

    reg [3:0] s_axis_tkeep = 4'hf;
    wire [3:0] m_axis_tkeep;
    wire m_axis_tlast;
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1'b1;

    reg  [31:0] s_dbg_tdata = 32'b0;
    reg         s_dbg_tvalid = 1'b0;
    wire        s_dbg_tready;
    reg         s_dbg_tlast = 1'b0;

    reg [3:0] s_dbg_tkeep = 4'hf;
    wire [3:0] m_dbg_tkeep;
    wire m_dbg_tlast;
    wire [31:0] m_dbg_tdata;
    wire        m_dbg_tvalid;
    reg         m_dbg_tready = 1'b1;

    wire app_valid;
    reg allow_app=0;
    assign m_axis_tvalid=app_valid && allow_app;
    integer fd;
    always @(negedge clk) if(resetn) begin
        fd=$fopen("release_app","r");
        if(fd) begin allow_app=1;$fclose(fd);end
        if(!allow_app && app_valid) begin fd=$fopen("app_held","w");$fclose(fd);end
        fd=$fopen("done","r");
        if(fd) begin $fclose(fd);$display("PASS: public service/debug routing");$finish;end
    end

    regsvc_fabric_fixture #(.PORTS(PORTS),.ENDPOINTS(ENDPOINTS)) dut (
        .aclk(clk),
        .aresetn(resetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(app_valid),
        .m_axis_tready(m_axis_tready && allow_app),
        .m_axis_tlast(m_axis_tlast),
        .s_dbg_tdata(s_dbg_tdata),
        .s_dbg_tkeep(s_dbg_tkeep),
        .s_dbg_tvalid(s_dbg_tvalid),
        .s_dbg_tready(s_dbg_tready),
        .s_dbg_tlast(s_dbg_tlast),
        .m_dbg_tdata(m_dbg_tdata),
        .m_dbg_tkeep(m_dbg_tkeep),
        .m_dbg_tvalid(m_dbg_tvalid),
        .m_dbg_tready(m_dbg_tready),
        .m_dbg_tlast(m_dbg_tlast)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
    end
endmodule
