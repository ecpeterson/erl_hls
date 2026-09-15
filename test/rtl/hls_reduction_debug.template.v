// Hold three participants at boot, then deliver their configuration through the
// public application ingress. No simulator reads or writes actor internals.
module @NAME@_wrapper (
    input wire clk, reset, release_contributions,
    output wire [127:0] _reports_out,
    output wire _reports_out_vld,
    input wire _reports_out_rdy
);
@WIRES@
    reg [15:0] participant = 0;
    wire command_ready;
    wire command_valid = participant < 2 || (release_contributions && participant < 5);
    // XLS packs structs in declaration order, most significant field first:
    // Rectangle, target, then Frame {Header, payload}.
    wire [193:0] command = {participant, 16'd0, participant, 16'd0,
        2'd0, 8'd1, 8'd0, 8'd0, 8'd@CONFIGURE@, 80'd0, participant};
    always @(posedge clk) begin
        if (reset) participant <= 0;
        else if (command_valid && command_ready) participant <= participant + 1'b1;
    end
    @NAME@ dut (
        .clk(clk), .reset(reset),
        ._commands_in(command), ._commands_in_vld(command_valid), ._commands_in_rdy(command_ready),
        ._reports_out(_reports_out), ._reports_out_vld(_reports_out_vld), ._reports_out_rdy(_reports_out_rdy)
@PORTS@
    );
@RAMS@
endmodule
