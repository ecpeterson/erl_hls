// A one-beat elastic link stage. Assertions cover the complete public wire
// contract, including stable data/TLAST during downstream backpressure.
module phi_bridge_delay #(parameter WIDTH=33)(input wire clk, reset, admit,
    input wire [WIDTH-1:0] in_data, input wire in_valid, output wire in_ready,
    output wire [WIDTH-1:0] out_data, output wire out_valid, input wire out_ready);
    reg full = 0;
    reg [WIDTH-1:0] data = 0, held = 0;
    reg stalled = 0;
    assign in_ready = admit && (!full || out_ready);
    assign out_valid = full;
    assign out_data = data;
    always @(posedge clk) begin
        if (reset) begin
            full <= 0;
            stalled <= 0;
        end else begin
            if (in_valid === 1'bx || (full && out_ready === 1'bx))
                $fatal(1, "unknown link handshake");
            if (stalled && (!in_valid || in_data !== held))
                $fatal(1, "link source changed a stalled beat");
            if (in_valid && (^in_data === 1'bx || in_ready === 1'bx))
                $fatal(1, "unknown link transfer");
            stalled <= in_valid && !in_ready;
            held <= in_data;
            if (in_valid && in_ready) begin
                data <= in_data;
                full <= 1;
            end else if (out_ready) begin
                full <= 0;
            end
        end
    end
endmodule
