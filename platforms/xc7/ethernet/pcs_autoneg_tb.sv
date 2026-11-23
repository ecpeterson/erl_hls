`timescale 1ns/1ps
// Two PCS instances start far apart; a break-link zero word is not an ability.
module pcs_autoneg_tb;
    reg clock_a = 0, clock_b = 0, reset_a = 1, reset_b = 1;
    always #4 clock_a = !clock_a;
    initial begin #1.25; forever #4.0004 clock_b = !clock_b; end
    wire [9:0] tbi_a, tbi_b;
    wire link_a, link_b, ack_a, ack_b, empty_a, empty_b;
    wire [15:0] ability_a, ability_b;

    liteeth_pcs_probe a(
        .eth_tx_clk(clock_a), .eth_rx_clk(clock_b),
        .eth_tx_rst(reset_a), .eth_rx_rst(reset_a),
        .tbi_tx(tbi_a), .tbi_rx(tbi_b), .link(link_a),
        .lp_abi(ability_a), .autoneg_ack(ack_a), .config_empty(empty_a));
    liteeth_pcs_probe b(
        .eth_tx_clk(clock_b), .eth_rx_clk(clock_a),
        .eth_tx_rst(reset_b), .eth_rx_rst(reset_b),
        .tbi_tx(tbi_b), .tbi_rx(tbi_a), .link(link_b),
        .lp_abi(ability_b), .autoneg_ack(ack_b), .config_empty(empty_b));

    integer cycle, late_cycles = 400;
    initial begin
        if (!$value$plusargs("late_cycles=%d", late_cycles)) late_cycles = 400;
        repeat (4) @(posedge clock_a);
        reset_a = 0;
        repeat (late_cycles) @(posedge clock_a);
        reset_b = 0;
        repeat (70) begin
            @(posedge clock_a);
            if (empty_b && ack_a)
                $fatal(1, "early peer accepted the late peer's empty break-link word");
        end
        for (cycle = 0; cycle < 2500; cycle = cycle + 1) begin
            @(posedge clock_a);
            if (link_a && link_b) begin
                $display("PASS: late PCS peer ignores break-link zero and negotiates");
                $finish;
            end
        end
        $fatal(1, "late peer deadlock link=%b%b ack=%b%b empty=%b%b ability=%h/%h",
               link_a, link_b, ack_a, ack_b, empty_a, empty_b, ability_a, ability_b);
    end
endmodule
