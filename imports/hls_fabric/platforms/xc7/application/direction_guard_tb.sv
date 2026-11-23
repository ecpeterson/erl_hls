`timescale 1ns/1ps
// Finite local-direction witness: ideal clocks, not a metastability/MTBF proof.
module direction_guard_tb;
    reg local_clock=0, clock_running=1, cold_reset_n=0, active_n=0;
    reg local_fault=0, host_arm=0, host_stop=0;
    wire local_cold_n, ready, active_lost, live, local_armed;
    always #5 if(clock_running) local_clock=~local_clock;
    domain_link_direction dut(.*);

    // All retained loss/arm state is reset only through this cold boundary.
    task automatic cold_start;
        begin
            cold_reset_n=0; active_n=0; host_arm=0; host_stop=0; local_fault=0;
            clock_running=1;
            repeat(5) @(negedge local_clock);
            cold_reset_n=1;
            repeat(5) @(negedge local_clock);
            if(ready || live || active_lost || local_armed) $fatal(1,"startup admitted traffic");
            active_n=1;
            repeat(8) @(negedge local_clock);
            if(!ready || live || local_armed) $fatal(1,"local readiness/arm separation failed");
        end
    endtask
    // Host request must traverse its synchronizer before the local acknowledgement.
    task automatic arm;
        begin
            host_arm=1;
            @(negedge local_clock);
            if(local_armed) $fatal(1,"arm bypassed synchronizer");
            repeat(3) @(negedge local_clock);
            if(!local_armed || !live || active_lost) $fatal(1,"arm handoff failed");
        end
    endtask
    // Neither request/session-like changes nor active recovery may restart a cursor.
    task automatic retained_stop;
        begin
            active_n=1; local_fault=0; host_stop=0; host_arm=0;
            repeat(8) @(negedge local_clock);
            host_arm=1;
            repeat(8) @(negedge local_clock);
            if(live || ready || !local_armed) $fatal(1,"retained stop was rearmed");
        end
    endtask
    initial begin
        cold_start();
        // No arm request: initial link settling is harmless, including a pulse
        // shorter than the local/control period and a stopped clock.
        clock_running=0; active_n=0; #2; active_n=1; #3;
        if(active_lost || local_armed || live) $fatal(1,"pre-arm settling became a failure");
        clock_running=1;
        repeat(8) @(negedge local_clock);
        if(!ready || active_lost) $fatal(1,"pre-arm settling did not recover");
        arm();
        // Once locally armed, active loss asserts stop even without another edge.
        clock_running=0; active_n=0; #1;
        if(live || !active_lost) $fatal(1,"clock-stopped active loss not retained");
        active_n=1; #3;
        if(live || !active_lost) $fatal(1,"short active recovery replayed retained work");
        clock_running=1; retained_stop();
        cold_start(); arm();
        local_fault=1; #1;
        if(live) $fatal(1,"source-local loss did not stop immediately");
        repeat(2) @(negedge local_clock);
        retained_stop();
        cold_start(); arm();
        host_stop=1;
        @(negedge local_clock);
        if(!live) $fatal(1,"host stop bypassed its synchronizer");
        repeat(3) @(negedge local_clock);
        if(live) $fatal(1,"host stop exceeded crossing bound");
        retained_stop();
        cold_start(); arm();
        if(!live) $fatal(1,"cold-only rearm failed");
        $display("DOMAIN_DIRECTION_GUARD_PASS settling=1 stopped_clock=1 local_fault=1 host_stop=1 cold_rearm=1");
        $finish;
    end
    initial begin #100000; $fatal(1,"direction guard witness timeout"); end
endmodule
