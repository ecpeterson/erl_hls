// One explicit startup attempt for a buffered GTX channel. clock is 25 MHz;
// parameters shorten delays in simulation only. run=0 holds/reset-clears the
// attempt; run=1 starts it. Faults latch until run=0. PLL lock and reset-done
// inputs are asynchronous. Fresh snapshot pulses witness user-clock progress.
// READY means reset completed, not that PRBS or the external link is healthy.
module gtx_probe_control #(
    parameter BOOT_CYCLES = 32, parameter RESET_CYCLES = 8, parameter SETTLE_CYCLES = 1024,
    parameter TIMEOUT_CYCLES = 25000, parameter CLOCK_TIMEOUT = 1024
)(
    input wire clock, input wire reset_n, input wire run,
    input wire pll_lock, input wire tx_done, input wire rx_done,
    input wire tx_fresh, input wire rx_fresh,
    output reg pll_reset = 0, output reg gt_reset = 0,
    output reg user_ready = 0, output reg measure = 0,
    output wire [31:0] status
);
    localparam BOOT=0, HOLD=1, LOCK=2, CLOCKS=3, DONE=4, SETTLE=5, READY=6, FAULT=7;
    reg [2:0] state = BOOT;
    reg [3:0] fault;
    reg [31:0] timer, watchdog, tx_age, rx_age;
    reg [3:0] tx_seen, rx_seen;
    (* ASYNC_REG = "TRUE" *) reg [1:0] lock_sync, tx_sync, rx_sync;
    wire clocks_live = tx_seen == 8 && rx_seen == 8 &&
                       tx_age < CLOCK_TIMEOUT && rx_age < CLOCK_TIMEOUT;
    assign status = {16'b0, fault, 3'b0, measure, 1'b0, rx_sync[1], tx_sync[1], lock_sync[1], 1'b0, state};

    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            lock_sync <= 0; tx_sync <= 0; rx_sync <= 0;
        end else begin
            lock_sync <= {lock_sync[0], pll_lock};
            tx_sync <= {tx_sync[0], tx_done};
            rx_sync <= {rx_sync[0], rx_done};
        end
    end

    // Registered reset controls avoid glitches on the GTX asynchronous inputs.
    // Wait >500 ns after configuration before first asserting any GTX reset.
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            state <= BOOT; fault <= 0; timer <= 0; watchdog <= 0;
            tx_age <= 0; rx_age <= 0; tx_seen <= 0; rx_seen <= 0;
            pll_reset <= 0; gt_reset <= 0; user_ready <= 0; measure <= 0;
        end else begin
            if (tx_fresh) begin
                tx_age <= 0;
                if (tx_seen < 8) tx_seen <= tx_seen + 1'b1;
            end
            else if (tx_age < CLOCK_TIMEOUT) tx_age <= tx_age + 1'b1;
            if (rx_fresh) begin
                rx_age <= 0;
                if (rx_seen < 8) rx_seen <= rx_seen + 1'b1;
            end
            else if (rx_age < CLOCK_TIMEOUT) rx_age <= rx_age + 1'b1;
            if (state == BOOT) begin
                if (timer == BOOT_CYCLES-1) begin
                    state <= HOLD; timer <= 0; pll_reset <= 1; gt_reset <= 1;
                end else timer <= timer + 1'b1;
            end else if (!run) begin
                state <= HOLD; fault <= 0; timer <= 0; watchdog <= 0;
                tx_seen <= 0; rx_seen <= 0; tx_age <= 0; rx_age <= 0;
                pll_reset <= 1; gt_reset <= 1; user_ready <= 0; measure <= 0;
            end else if (state != FAULT) begin
                if (state != READY) watchdog <= watchdog + 1'b1;
                case (state)
                    // Hold a complete reset pulse and observe the previous lock
                    // disappear before accepting lock from this attempt.
                    HOLD: begin
                        if (timer < RESET_CYCLES-1) timer <= timer + 1'b1;
                        else if (!lock_sync[1]) begin state <= LOCK; pll_reset <= 0; end
                    end
                    LOCK: if (lock_sync[1]) begin
                        state <= CLOCKS; gt_reset <= 0;
                        // Demand repeated post-lock progress; one delayed
                        // snapshot from before reset cannot establish readiness.
                        tx_seen <= 0; rx_seen <= 0;
                    end
                    CLOCKS: if (clocks_live) begin state <= DONE; user_ready <= 1; end
                    DONE: if (tx_sync[1] && rx_sync[1]) begin state <= SETTLE; timer <= 0; end
                    SETTLE: begin
                        if (timer == SETTLE_CYCLES-1) begin state <= READY; measure <= 1; end
                        else timer <= timer + 1'b1;
                    end
                    default: ;
                endcase
                if (state > LOCK && !lock_sync[1]) begin
                    state <= FAULT; fault <= 4'b0010; gt_reset <= 1; user_ready <= 0; measure <= 0;
                end else if (state >= SETTLE && (!tx_sync[1] || !rx_sync[1])) begin
                    state <= FAULT; fault <= 4'b0100; gt_reset <= 1; user_ready <= 0; measure <= 0;
                end else if (state == READY && !clocks_live) begin
                    state <= FAULT; fault <= 4'b1000; gt_reset <= 1; user_ready <= 0; measure <= 0;
                end else if (state != READY && watchdog == TIMEOUT_CYCLES-1) begin
                    state <= FAULT; fault <= 4'b0001; gt_reset <= 1; user_ready <= 0; measure <= 0;
                end
            end
        end
    end
endmodule
