`timescale 1ns/1ps
// Observe the frozen four-Phi harness without driving the scheduler or its memories.
module transaction_tb;
    reg clock = 0;
    wire activity;
    phi_timing_harness dut (.clock(clock), .activity(activity));
    always #10 clock = ~clock;

    `define RAM dut.decoder.scheduler_2_state
    `define EXEC dut.decoder.application.__phi_decoder_profile_topology__SchedulerGrid_0_next_inst.__phi_halo_cell__SharedService_0__2_2_2_2_next_inst.__phi_halo_cell__SharedExecutor_0_next_inst
    integer cycle = 0;

    // Sample controls and the accepted executor input before the active edge.
    // One ns later all nonblocking writes, including the synchronous read output, have settled.
    always @(posedge clock) begin
        $write("%0d %b %b %b %b %b %h %h %b %b %h %h %h %b %b %h ",
            cycle, dut.resetn, `RAM.wr_en, `RAM.wr_addr, `RAM.rd_en, `RAM.rd_addr,
            `RAM.wr_data, `RAM.rd_data, `EXEC._request_in_vld, `EXEC._request_in_rdy,
            `EXEC.rounded__3, `EXEC.umul_164656, `EXEC.request_machine__1,
            `EXEC.negative__3, `EXEC.p0_stage_done, `EXEC.p0_sel_80258);
        #1;
        $display("%h %h %h %h", `RAM.rd_data, `RAM.memory[0], `RAM.memory[1], `EXEC.p0_sel_80258);
        cycle = cycle + 1;
        if (cycle == 4096) begin
            $display("END %0d", cycle);
            $finish;
        end
    end
    `undef RAM
    `undef EXEC
endmodule
