// Pulse fresh in the always-running control domain only after BOTH clocks
// acknowledge a new request. Unlike a free-running toggle, the handshake cannot
// alias at a rational clock ratio. reset_n asserts asynchronously in all domains;
// no packet reset is fed back here, since clock progress is needed to release it.
module ethernet_clock_pair (
    input wire control_clk, reset_n, full_clk, half_clk,
    output reg fresh
);
    wire full_reset_n, half_reset_n;
    zynq_probe_reset fr(full_clk, reset_n, full_reset_n);
    zynq_probe_reset hr(half_clk, reset_n, half_reset_n);
    reg request;
    (* ASYNC_REG = "TRUE" *) reg [1:0] full_request, half_request;
    (* ASYNC_REG = "TRUE" *) reg [1:0] full_ack, half_ack;
    always @(posedge full_clk or negedge full_reset_n)
        if (!full_reset_n) full_request <= 0;
        else full_request <= {full_request[0], request};
    always @(posedge half_clk or negedge half_reset_n)
        if (!half_reset_n) half_request <= 0;
        else half_request <= {half_request[0], request};
    always @(posedge control_clk or negedge reset_n) begin
        if (!reset_n) begin
            request <= 1; full_ack <= 0; half_ack <= 0; fresh <= 0;
        end else begin
            full_ack <= {full_ack[0], full_request[1]};
            half_ack <= {half_ack[0], half_request[1]};
            fresh <= 0;
            if (full_ack[1] == request && half_ack[1] == request) begin
                fresh <= 1;
                request <= !request;
            end
        end
    end
endmodule
