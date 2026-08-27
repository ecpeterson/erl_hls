module xls_debug_tap #(
    parameter integer STATE_BITS = 512,
    parameter integer STREAM_OBSERVATION_BITS = 32 + 3,
    parameter integer OBSERVATION_BITS =
        STATE_BITS + 32 + 2 * STREAM_OBSERVATION_BITS + 1
) (
    input  wire                  aclk,
    input  wire                  aresetn,
    input  wire                  app_rx_tvalid,
    input  wire                  app_rx_tready,
    input  wire                  app_rx_tlast,
    input  wire [31:0]           app_rx_tdata,
    input  wire                  app_tx_tvalid,
    input  wire                  app_tx_tready,
    input  wire                  app_tx_tlast,
    input  wire [31:0]           app_tx_tdata,
    input  wire [STATE_BITS-1:0] app_state_data,
    input  wire                  app_state_valid,
    output wire [OBSERVATION_BITS-1:0] observation_data,
    output wire                  observation_valid,
    input  wire                  observation_ready
);
    reg [31:0] observation_drops;
    reg [STATE_BITS-1:0] pending_state_data;
    reg                  pending_state_valid;

    wire [STATE_BITS-1:0] observed_state_data = app_state_valid ?
        app_state_data : pending_state_data;
    wire observed_state_valid = app_state_valid || pending_state_valid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            observation_drops <= 32'd0;
            pending_state_data <= {STATE_BITS{1'b0}};
            pending_state_valid <= 1'b0;
        end else begin
            if (!observation_ready)
                observation_drops <= observation_drops + 32'd1;

            // State commits are pulses from the application. Retain the
            // newest one until Observer accepts an observation; this mirror
            // never feeds ready back to the application.
            if (app_state_valid) begin
                pending_state_data <= app_state_data;
                pending_state_valid <= !observation_ready;
            end else if (observation_ready) begin
                pending_state_valid <= 1'b0;
            end
        end
    end

    assign observation_data = {
        observed_state_data,
        observation_drops,
        app_tx_tdata,
        app_tx_tlast,
        app_tx_tready,
        app_tx_tvalid,
        app_rx_tdata,
        app_rx_tlast,
        app_rx_tready,
        app_rx_tvalid,
        observed_state_valid
    };
    assign observation_valid = aresetn;
endmodule
