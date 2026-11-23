// Split an ordered command only at the network boundary. A start can pass
// only when the network confirms prior setup has drained. The completion
// register acknowledges that actual handshake and remains stable under stalls.
// Coordinated reset cancels the command source, this bridge and the network.
module hls_partition_activation #(parameter INGRESS_BITS=194)(
    input wire clk, reset,
    input wire [INGRESS_BITS:0] command, input wire command_valid, output wire command_ready,
    output wire [INGRESS_BITS-1:0] ingress_data, output wire ingress_valid, input wire ingress_ready,
    output wire start_valid, input wire start_ready,
    output wire started, output wire started_valid, input wire started_ready
);
    reg pending;
    wire is_start;
    assign is_start=command[INGRESS_BITS];
    assign ingress_data=command[INGRESS_BITS-1:0];
    assign ingress_valid=!reset && !pending && command_valid && !is_start;
    assign start_valid=!reset && !pending && command_valid && is_start;
    assign command_ready=!reset && !pending && (is_start ? start_ready : ingress_ready);
    assign started=1'b1;
    assign started_valid=!reset && pending;
    always @(posedge clk) begin
        if(reset) pending<=0;
        else if(start_valid && start_ready) pending<=1;
        else if(started_valid && started_ready) pending<=0;
    end
endmodule
