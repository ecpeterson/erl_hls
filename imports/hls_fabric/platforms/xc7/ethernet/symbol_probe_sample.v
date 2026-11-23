// Coherent raw-symbol diagnostics from the recovered 62.5-MHz GTX word clock.
// PATTERN is the repeated 20-bit serial word; every two-word window is searched
// at all 20 bit phases. Counters wrap. A held snapshot crosses to the 25-MHz
// control domain after its synchronized acknowledgement has allowed settling.
module ethernet_symbol_probe_sample #(
    parameter [19:0] PATTERN = {10'h283, 10'h17c}
)(
    input wire clock, source_clock, reset_n, enable,
    input wire [19:0] word,
    output reg [31:0] raw_phase, words, patterns, aligned, swapped, phase_changes,
    output reg fresh
);
    localparam [19:0] SWAPPED = {PATTERN[9:0], PATTERN[19:10]};
    wire destination_reset_n, source_reset_n;
    zynq_probe_reset dr(clock, reset_n, destination_reset_n);
    zynq_probe_reset sr(source_clock, reset_n, source_reset_n);
    reg request, acknowledge;
    (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync, ack_sync, enable_sync;
    reg [19:0] previous;
    wire [39:0] window = {word, previous};
    reg history_valid, phase_valid, found;
    reg [4:0] phase, found_phase;
    reg [31:0] word_count, pattern_count, aligned_count, swapped_count, change_count;
    reg [191:0] snapshot;
    integer candidate;

    // The repeated, non-10-bit-periodic word has one matching phase per window.
    always @* begin
        found = 0;
        found_phase = 0;
        for (candidate = 0; candidate < 20; candidate = candidate + 1)
            if (window[candidate +: 20] == PATTERN) begin
                found = 1;
                found_phase = candidate;
            end
    end

    always @(posedge source_clock or negedge source_reset_n) begin
        if (!source_reset_n) begin
            request_sync <= 0; enable_sync <= 0; acknowledge <= 0;
            previous <= 0; history_valid <= 0; phase_valid <= 0; phase <= 0;
            word_count <= 0; pattern_count <= 0; aligned_count <= 0;
            swapped_count <= 0; change_count <= 0; snapshot <= 0;
        end else begin
            request_sync <= {request_sync[0], request};
            enable_sync <= {enable_sync[0], enable};
            previous <= word;
            if (enable_sync[1]) begin
                history_valid <= 1;
                word_count <= word_count + 1'b1;
                if (word == PATTERN) aligned_count <= aligned_count + 1'b1;
                if (word == SWAPPED) swapped_count <= swapped_count + 1'b1;
                if (history_valid && found) begin
                    pattern_count <= pattern_count + 1'b1;
                    if (phase_valid && found_phase != phase)
                        change_count <= change_count + 1'b1;
                    phase <= found_phase;
                    phase_valid <= 1;
                end
            end else begin
                history_valid <= 0;
                phase_valid <= 0;
            end
            if (request_sync[1] != acknowledge) begin
                snapshot <= {change_count, swapped_count, aligned_count,
                             pattern_count, word_count,
                             6'b0, phase_valid, phase, word};
                acknowledge <= request_sync[1];
            end
        end
    end

    always @(posedge clock or negedge destination_reset_n) begin
        if (!destination_reset_n) begin
            request <= 1; ack_sync <= 0; raw_phase <= 0; words <= 0;
            patterns <= 0; aligned <= 0; swapped <= 0; phase_changes <= 0; fresh <= 0;
        end else begin
            ack_sync <= {ack_sync[0], acknowledge};
            fresh <= 0;
            if (ack_sync[1] == request) begin
                {phase_changes, swapped, aligned, patterns, words, raw_phase} <= snapshot;
                fresh <= 1;
                request <= !request;
            end
        end
    end
endmodule
