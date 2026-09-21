// Coherent held-bus snapshot into a running control clock, even when the source
// can stop. reset_n asserts in both domains and releases locally. Values remain
// last-observed when source_clock stops; reset clears them without a source edge.
// Constrain the held bus to settle before its two-flop acknowledgement arrives.
module ethernet_snapshot #(parameter WIDTH=32)(
    input wire clock, source_clock, reset_n,
    input wire [WIDTH-1:0] value,
    output reg [WIDTH-1:0] sampled
);
    wire destination_reset_n, source_reset_n;
    zynq_probe_reset dr(clock, reset_n, destination_reset_n);
    zynq_probe_reset sr(source_clock, reset_n, source_reset_n);
    reg request, acknowledge;
    reg [WIDTH-1:0] held;
    (* ASYNC_REG="TRUE" *) reg [1:0] request_sync, ack_sync;
    always @(posedge source_clock or negedge source_reset_n) begin
        if(!source_reset_n) begin request_sync<=0; acknowledge<=0; held<=0; end
        else begin
            request_sync<={request_sync[0],request};
            if(request_sync[1]!=acknowledge) begin held<=value; acknowledge<=request_sync[1]; end
        end
    end
    always @(posedge clock or negedge destination_reset_n) begin
        if(!destination_reset_n) begin request<=1; ack_sync<=0; sampled<=0; end
        else begin
            ack_sync<={ack_sync[0],acknowledge};
            if(ack_sync[1]==request) begin sampled<=held; request<=!request; end
        end
    end
endmodule
