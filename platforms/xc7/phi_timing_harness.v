`default_nettype none

// A two-pin timing workload, not a board top. Registers isolate the decoder
// boundary from the digest; an independent LFSR keeps sink backpressure live.
module phi_timing_harness (
    input wire clock,
    output wire activity
);
    reg [3:0] reset_pipe = 0;
    reg [31:0] flow = 32'h13579bdf;
    wire resetn = reset_pipe[3];
    wire [127:0] x_event, z_event;
    wire x_valid, z_valid;
    wire x_ready = flow[0] | flow[1];
    wire z_ready = flow[2] | flow[3];
    reg [127:0] x_capture = 0, z_capture = 0;
    reg [1:0] valid_capture = 0;
    reg [31:0] digest = 0;

    phi_decoder_profile_top decoder (
        .aclk(clock), .aresetn(resetn),
        .x_decoder_event(x_event), .x_decoder_event_valid(x_valid),
        .x_decoder_event_ready(x_ready),
        .z_decoder_event(z_event), .z_decoder_event_valid(z_valid),
        .z_decoder_event_ready(z_ready)
    );

    always @(posedge clock) begin
        reset_pipe <= {reset_pipe[2:0], 1'b1};
        flow <= {flow[30:0], flow[31] ^ flow[21] ^ flow[1] ^ flow[0]};
        // Retain every event bit. Invalid-cycle payload is unspecified and
        // must not poison the simulation digest with uninitialized data.
        if (resetn && x_valid) x_capture <= x_event;
        if (resetn && z_valid) z_capture <= z_event;
        valid_capture <= resetn ? {x_valid, z_valid} : 2'b0;
        digest <= {digest[30:0], digest[31]} ^
            x_capture[31:0] ^ x_capture[63:32] ^
            x_capture[95:64] ^ x_capture[127:96] ^
            z_capture[31:0] ^ z_capture[63:32] ^
            z_capture[95:64] ^ z_capture[127:96] ^
            {30'b0, valid_capture};
    end
    assign activity = digest[0];
endmodule

`default_nettype wire
