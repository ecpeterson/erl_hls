// Coherent clock/error snapshots from a potentially stopped GTX user clock.
// reset_n must assert for both domains together; each releases synchronously.
// Words wrap modulo 2^32; errors saturate and count asserted error cycles while
// enabled, not bit errors. fresh pulses only when a new snapshot arrives.
module gtx_probe_sample(
    input wire clock, input wire source_clock, input wire reset_n,
    input wire enable, input wire error,
    output wire source_enable,
    output reg [31:0] words, output reg [31:0] errors, output reg fresh
);
    wire destination_reset_n, source_reset_n;
    zynq_probe_reset dr(clock, reset_n, destination_reset_n);
    zynq_probe_reset sr(source_clock, reset_n, source_reset_n);
    reg request, acknowledge;
    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync, ack_sync, enable_sync;
    reg [31:0] word_count, error_count;
    reg [63:0] snapshot;
    assign source_enable = enable_sync[1];

    always @(posedge source_clock or negedge source_reset_n) begin
        if (!source_reset_n) begin
            request_sync <= 0; enable_sync <= 0; acknowledge <= 0;
            word_count <= 0; error_count <= 0; snapshot <= 0;
        end else begin
            request_sync <= {request_sync[0], request};
            enable_sync <= {enable_sync[0], enable};
            word_count <= word_count + 1'b1;
            if (source_enable && error && error_count != 32'hffffffff)
                error_count <= error_count + 1'b1;
            if (request_sync[1] != acknowledge) begin
                snapshot <= {error_count, word_count};
                acknowledge <= request_sync[1];
            end
        end
    end

    // The source holds snapshot until another request. Synchronizing its ack
    // leaves two destination edges for the bundled bus to settle before capture.
    always @(posedge clock or negedge destination_reset_n) begin
        if (!destination_reset_n) begin
            request <= 1; ack_sync <= 0; words <= 0; errors <= 0; fresh <= 0;
        end else begin
            ack_sync <= {ack_sync[0], acknowledge};
            fresh <= 0;
            if (ack_sync[1] == request) begin
                {errors, words} <= snapshot;
                fresh <= 1;
                request <= !request;
            end
        end
    end
endmodule
