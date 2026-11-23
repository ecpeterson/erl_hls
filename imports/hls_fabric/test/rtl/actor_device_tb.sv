`timescale 1ns/1ps

// VPI transports AXI beats only. Reports are sampled at the application's
// public output handshake; actor state is queried through the debug service.
module actor_device_tb;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    reg [31:0] s_axis_tdata = 0;
    reg [3:0] s_axis_tkeep = 15;
    reg s_axis_tlast = 0, s_axis_tvalid = 0;
    wire s_axis_tready;
    wire [31:0] m_axis_tdata = 0;
    wire [3:0] m_axis_tkeep = 15;
    wire m_axis_tlast = 0, m_axis_tvalid = 0;
    reg m_axis_tready = 0;

    reg [31:0] s_dbg_tdata = 0;
    reg [3:0] s_dbg_tkeep = 15;
    reg s_dbg_tlast = 0, s_dbg_tvalid = 0;
    wire s_dbg_tready;
    wire [31:0] m_dbg_tdata;
    wire [3:0] m_dbg_tkeep;
    wire m_dbg_tlast, m_dbg_tvalid;
    reg m_dbg_tready = 0;

    wire [127:0] report;
    wire report_valid;
    reg allow_app = 0, held_recorded = 0;
    integer reports, fd, cycles = 0;

    hls_debug_application dut (
        .clk(clk), .reset(!resetn),
        ._routed_in({s_axis_tlast, s_axis_tdata}),
        ._routed_in_vld(s_axis_tvalid), ._routed_in_rdy(s_axis_tready),
        ._reports_out(report), ._reports_out_vld(report_valid),
        ._reports_out_rdy(allow_app),
        .s_dbg_tdata(s_dbg_tdata), .s_dbg_tkeep(s_dbg_tkeep),
        .s_dbg_tlast(s_dbg_tlast), .s_dbg_tvalid(s_dbg_tvalid),
        .s_dbg_tready(s_dbg_tready),
        .m_dbg_tdata(m_dbg_tdata), .m_dbg_tkeep(m_dbg_tkeep),
        .m_dbg_tlast(m_dbg_tlast), .m_dbg_tvalid(m_dbg_tvalid),
        .m_dbg_tready(m_dbg_tready)
    );

    initial begin
        reports = $fopen("reports.log", "w");
        if (!reports) $fatal(1, "cannot open external report log");
        repeat (5) @(negedge clk);
        resetn = 1;
    end

    always @(posedge clk) if (resetn) begin
        cycles = cycles + 1;
        if (cycles > 5000000) $fatal(1, "host query timeout");
        if (s_axis_tvalid && s_axis_tready && s_axis_tkeep != 15)
            $fatal(1, "actor ingress requires complete words");
        if (report_valid && allow_app) begin
            $fdisplay(reports, "%032h", report);
            $fflush(reports);
        end
    end

    always @(negedge clk) if (resetn && cycles % 100 == 0) begin
        fd = $fopen("release_app", "r");
        if (fd) begin
            allow_app = 1;
            $fclose(fd);
        end
        if (report_valid && !allow_app && !held_recorded) begin
            held_recorded = 1;
            fd = $fopen("app_held", "w");
            $fclose(fd);
        end
        fd = $fopen("done", "r");
        if (fd) begin
            $fclose(fd);
            $fclose(reports);
            $display("PASS: actor PID casts and public debug queries (%0d cycles)", cycles);
            $finish;
        end
    end
endmodule
