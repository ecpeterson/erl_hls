// Bounded debug command receiver. A rejected packet is drained through TLAST;
// payload words never become headers. Output remains stable until accepted.
module hls_debug_frame_rx #(
    parameter integer MAX_WORDS = 4
) (
    input wire clk,
    input wire reset,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_last,
    input wire s_valid,
    output wire s_ready,
    output reg [31:0] header,
    output reg [MAX_WORDS*32-1:0] payload,
    output reg malformed,
    output reg valid,
    input wire ready
);
    localparam integer COUNT_BITS = $clog2(MAX_WORDS + 2);
    reg in_frame;
    reg bad;
    reg [COUNT_BITS-1:0] count;
    wire bad_keep = s_keep != 4'hf;
    assign s_ready = !valid;

    always @(posedge clk) begin
        if (reset) begin
            in_frame <= 0;
            bad <= 0;
            count <= 0;
            header <= 0;
            payload <= 0;
            malformed <= 0;
            valid <= 0;
        end else begin
            if (valid && ready) valid <= 0;
            if (s_valid && s_ready) begin
                if (!in_frame) begin
                    header <= s_data;
                    payload <= 0;
                    count <= 0;
                    bad <= bad_keep || s_data[23:16] != 0 || s_data[7:0] > MAX_WORDS;
                    in_frame <= !s_last;
                    if (s_last) begin
                        valid <= 1;
                        malformed <= bad_keep || s_data[23:16] != 0 || s_data[7:0] != 0;
                    end
                end else begin
                    if (count < MAX_WORDS) payload[count*32 +: 32] <= s_data;
                    if (count < MAX_WORDS + 1) count <= count + 1'b1;
                    bad <= bad || bad_keep || count >= MAX_WORDS;
                    if (s_last) begin
                        in_frame <= 0;
                        valid <= 1;
                        malformed <= bad || bad_keep || count >= MAX_WORDS ||
                            count + 1 != header[7:0];
                    end
                end
            end
        end
    end
endmodule
