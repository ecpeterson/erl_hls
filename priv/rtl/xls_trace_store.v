// Ready/valid seam around one inferred simple-dual-port trace memory.
//
// Observer writes are always accepted. DebugServer reads may be backpressured
// independently, so draining a frozen bank never changes Observer's sampling
// schedule. The memory has no reset or initializer: retained-count metadata
// prevents reads from unwritten rows and lets synthesis infer block RAM.
module xls_trace_store #(
    parameter integer ADDR_WIDTH = 6,
    parameter integer ROW_WIDTH = 128,
    parameter integer EVENT_WIDTH = 64
) (
    input  wire                        clk,
    input  wire                        reset,

    input  wire [ADDR_WIDTH+ROW_WIDTH-1:0] write_request,
    input  wire                        write_request_valid,
    output wire                        write_request_ready,

    input  wire [ADDR_WIDTH:0]         read_request,
    input  wire                        read_request_valid,
    output wire                        read_request_ready,
    output wire [EVENT_WIDTH-1:0]      read_response,
    output reg                         read_response_valid,
    input  wire                        read_response_ready
);
    localparam integer DEPTH = 1 << ADDR_WIDTH;

    wire [ADDR_WIDTH-1:0] write_address =
        write_request[ADDR_WIDTH+ROW_WIDTH-1:ROW_WIDTH];
    wire [ROW_WIDTH-1:0] write_data = write_request[ROW_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] read_address = read_request[ADDR_WIDTH:1];
    wire read_high = read_request[0];

    (* ram_style = "block" *) reg [ROW_WIDTH-1:0] memory [0:DEPTH-1];
    reg [ROW_WIDTH-1:0] read_row;
    reg read_row_high;

    assign write_request_ready = 1'b1;
    assign read_request_ready =
        !read_response_valid || read_response_ready;
    assign read_response = read_row_high ?
        read_row[ROW_WIDTH-1:EVENT_WIDTH] :
        read_row[EVENT_WIDTH-1:0];

    always @(posedge clk) begin
        if (write_request_valid)
            memory[write_address] <= write_data;

        if (reset) begin
            read_response_valid <= 1'b0;
        end else if (read_request_ready) begin
            read_response_valid <= read_request_valid;
            if (read_request_valid) begin
                read_row <= memory[read_address];
                read_row_high <= read_high;
            end
        end
    end
endmodule
