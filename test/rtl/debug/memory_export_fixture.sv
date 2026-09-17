// Tiny forced BRAMs make loss of synthesis intent observable even when the
// default heuristic would prefer LUT RAM. The table must stay distributed.
module memory_export_fixture (
    input wire clk, reset,
    input wire request_valid,
    output wire request_ready,
    input wire write_enable, read_enable,
    input wire [3:0] write_address, read_address,
    input wire [31:0] write_data,
    input wire [3:0] byte_enable,
    output wire [31:0] first, second, lookup,
    output reg [31:0] masked
);
    assign request_ready = !reset;
    wire accepted = request_valid && request_ready;
    hls_1r1w_ram #(.WIDTH(32), .ADDRESS_WIDTH(4)) first_ram (
        .clk(clk), .wr_addr(write_address), .wr_data(write_data),
        .wr_en(accepted && write_enable), .rd_addr(read_address),
        .rd_en(accepted && read_enable), .rd_data(first)
    );
    // Equal enables within a byte can be combined; different byte enables
    // must remain independent.
    (* ram_style = "block" *) reg [31:0] masked_data [0:15];
    genvar byte_index;
    generate for (byte_index=0; byte_index<4; byte_index=byte_index+1) begin
        always @(posedge clk)
            if (accepted && write_enable && byte_enable[byte_index])
                masked_data[write_address][8*byte_index+:8] <= write_data[8*byte_index+:8];
    end endgenerate
    always @(posedge clk)
        if (accepted && read_enable) masked <= masked_data[read_address];
    hls_1r1w_ram #(.WIDTH(32), .ADDRESS_WIDTH(4)) second_ram (
        .clk(clk), .wr_addr(write_address), .wr_data(~write_data),
        .wr_en(accepted && write_enable), .rd_addr(read_address),
        .rd_en(accepted && read_enable), .rd_data(second)
    );
    // Nonzero origin and initial contents exercise more than an attribute
    // text search. The audit must preserve geometry and initialization too.
    (* ram_style = "distributed" *) reg [31:0] table_data [16:31];
    integer i;
    initial for (i=16; i<32; i=i+1) table_data[i] = i * 17;
    always @(posedge clk)
        if (accepted && write_enable) table_data[{1'b1, write_address}] <= write_data;
    assign lookup = table_data[{1'b1, read_address}];
endmodule
