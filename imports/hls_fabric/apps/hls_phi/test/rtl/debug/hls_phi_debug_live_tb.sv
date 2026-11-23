`timescale 1ns/1ps
// VPI touches only the two public streams. Fault controls act at the external
// sinks; the complete production application receives the same input schedule.
module hls_phi_debug_live_tb;
    reg clk=0, resetn=0;
    always #5 clk=~clk;
    reg [31:0] s_axis_tdata=0, s_dbg_tdata=0;
    reg [3:0] s_axis_tkeep=15, s_dbg_tkeep=15;
    reg s_axis_tvalid=0, s_axis_tlast=0, s_dbg_tvalid=0, s_dbg_tlast=0;
    wire s_axis_tready, s_dbg_tready;
    wire [31:0] m_axis_tdata, m_dbg_tdata;
    wire [3:0] m_axis_tkeep, m_dbg_tkeep;
    wire m_axis_tvalid, m_axis_tlast, m_dbg_tvalid, m_dbg_tlast;
    reg m_axis_tready=0, m_dbg_tready=0;
    reg app_released=0, debug_released=1;
    wire app_ready=m_axis_tready && app_released;
    wire debug_ready=m_dbg_tready && debug_released;
    wire app_valid, debug_valid;
    assign m_axis_tvalid=app_valid && app_released;
    assign m_dbg_tvalid=debug_valid && debug_released;
    hls_debug_application dut (
        .aclk(clk), .aresetn(resetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep), .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep), .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(app_valid), .m_axis_tready(app_ready),
        .s_dbg_tdata(s_dbg_tdata), .s_dbg_tkeep(s_dbg_tkeep), .s_dbg_tlast(s_dbg_tlast),
        .s_dbg_tvalid(s_dbg_tvalid), .s_dbg_tready(s_dbg_tready),
        .m_dbg_tdata(m_dbg_tdata), .m_dbg_tkeep(m_dbg_tkeep), .m_dbg_tlast(m_dbg_tlast),
        .m_dbg_tvalid(debug_valid), .m_dbg_tready(debug_ready));
    wire ref_ready, ref_valid, ref_last;
    wire [31:0] ref_data;
    wire [3:0] ref_keep;
    phi_memory_top reference (
        .aclk(clk), .aresetn(resetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep), .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(ref_ready),
        .m_axis_tdata(ref_data), .m_axis_tkeep(ref_keep), .m_axis_tlast(ref_last),
        .m_axis_tvalid(ref_valid), .m_axis_tready(app_ready));
    integer cycles=0, last_output=0, release_cycle=0, held_outputs=0;
    integer completion_cycle=0, completion_output=0, complete_fd;
    integer rx_beats=0, tx_beats=0, fd;
    always @(posedge clk) if(resetn) begin
        cycles=cycles+1;
        if(s_axis_tready !== ref_ready || app_valid !== ref_valid ||
            (app_valid && {m_axis_tlast,m_axis_tkeep,m_axis_tdata} !== {ref_last,ref_keep,ref_data}))
            $fatal(1,"production/all-hooks application differs at cycle %0d",cycles);
        if(s_axis_tvalid && s_axis_tready) rx_beats=rx_beats+1;
        if(app_valid && app_ready) begin
            tx_beats=tx_beats+1; last_output=cycles;
            if(!debug_released) held_outputs=held_outputs+1;
        end
        if(cycles>2000000) $fatal(1,"host timeout");
    end
    always @(negedge clk) if(resetn && cycles%100==0 && completion_cycle==0) begin
        complete_fd=$fopen("application_complete","r");
        if(complete_fd) begin
            $fclose(complete_fd);completion_cycle=cycles;completion_output=last_output;
        end
    end
    task automatic await_command(input string name);
        integer handle;
        begin
            handle=0;
            while(!handle) begin
                repeat(100) @(negedge clk); handle=$fopen(name,"r");
            end
            $fclose(handle);
        end
    endtask
    task automatic ack(input string name);
        integer handle;
        begin handle=$fopen(name,"w");$fclose(handle);end
    endtask
    initial begin
        repeat(5) @(negedge clk); resetn=1;
        await_command("block");
        while(!app_valid) @(negedge clk);
        repeat(5000) @(negedge clk);
        ack("blocked");
        await_command("hold_debug");
        debug_released=0; ack("debug_held");
        while(!debug_valid) @(negedge clk);
        ack("reply_held");
        app_released=1;release_cycle=cycles;
        // More than a trace bank's worth of real traffic must pass while the
        // trace response is held. Bound simulated time as well as host time.
        while(held_outputs<512 && cycles-release_cycle<10000) @(negedge clk);
        if(held_outputs<512) $fatal(1,"application stopped progressing with debug reply blocked");
        debug_released=1;ack("debug_released");
        await_command("done");
        fd=$fopen("application.json","w");
        $fwrite(fd,"{\"cycles\":%0d,\"release_cycle\":%0d,\"last_output\":%0d,\"recovery_cycles\":%0d,\"rx_beats\":%0d,\"tx_beats\":%0d,\"tx_beats_while_debug_blocked\":%0d}\n",
            cycles,release_cycle,completion_output,completion_output-release_cycle,rx_beats,tx_beats,held_outputs);
        $fclose(fd);
        $display("PASS: production/all-hooks cycle equality for %0d cycles; %0d beats during debug stall",cycles,held_outputs);
        $finish;
    end
endmodule
