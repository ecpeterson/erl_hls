module hls_debug_tap #(
    parameter integer STREAM_OBSERVATION_BITS = 32 + 3,
    parameter integer OBSERVATION_BITS =
        32 + 2 * STREAM_OBSERVATION_BITS
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
    output wire [OBSERVATION_BITS-1:0] observation_data,
    output wire                  observation_valid,
    input  wire                  observation_ready
);
    reg [31:0] observation_drops;

    always @(posedge aclk) begin
        if (!aresetn)
            observation_drops <= 32'd0;
        else if (!observation_ready)
            observation_drops <= observation_drops + 32'd1;
    end

    assign observation_data = {
        observation_drops,
        app_tx_tdata,
        app_tx_tlast,
        app_tx_tready,
        app_tx_tvalid,
        app_rx_tdata,
        app_rx_tlast,
        app_rx_tready,
        app_rx_tvalid
    };
    assign observation_valid = aresetn;
endmodule
