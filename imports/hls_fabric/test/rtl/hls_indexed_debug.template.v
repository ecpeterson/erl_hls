// Deliver the successor before the missing current member; stall only public boundaries.
module actor_debug_wrapper (
    input wire clk, reset, release_contributions,
    output wire [127:0] _reports_out,
    output wire _reports_out_vld,
    input wire _reports_out_rdy
);
@WIRES@
    reg [1:0] sent = 0;
    wire command_ready;
    wire command_valid = sent < 2 || (release_contributions && sent < 3);
    wire [31:0] key = sent == 0 ? 32'd1 : 32'd0;
    wire [31:0] member = sent == 1 ? 32'd1 : 32'd0;
    wire [7:0] value = sent == 0 ? 8'd99 : (sent == 1 ? 8'd7 : 8'd11);
    // Little-endian packed record fields start at the low end of the frame payload.
    wire [193:0] command = {64'd0, 2'd0, 8'd3, 8'd0, 8'd0, 8'd@PIECE@, 24'd0, value, member, key};
    always @(posedge clk) begin
        if (reset) sent <= 0;
        else if (command_valid && command_ready) sent <= sent + 1'b1;
    end
    actor_debug dut (
        .clk(clk), .reset(reset),
        ._commands_in(command), ._commands_in_vld(command_valid), ._commands_in_rdy(command_ready),
        ._reports_out(_reports_out), ._reports_out_vld(_reports_out_vld), ._reports_out_rdy(_reports_out_rdy)
@PORTS@
    );
@RAMS@
endmodule
