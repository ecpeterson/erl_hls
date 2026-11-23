`timescale 1ns/1ps
// Four peers reuse the same lane IDs. Blocking peer 0 must not consume another peer's credits.
module partition_peers_tb;
    localparam COUNT = 24;
    reg clk = 0, reset = 1;
    always #5 clk = !clk;
    integer cycle = 0;
    integer sent [0:15], received [0:15];
    wire [127:0] frame_in [0:15], frame_out [0:15];
    wire in_ready [0:15], out_valid [0:15];
    reg out_ready [0:15];
    wire [32:0] tx [0:3], back [0:3];
    wire tx_valid [0:3], tx_ready [0:3], back_valid [0:3], back_ready [0:3];
    wire [31:0] fault [0:7];
    wire fault_valid [0:7];

    function automatic [127:0] sample(input integer lane, input integer ordinal);
        sample = {32'h12340000 | lane, 32'h89abcdef ^ ordinal, 32'h76543210 ^ lane, 32'habcd0000 | ordinal};
    endfunction
    for (genvar i = 0; i < 16; i = i+1) begin
        assign frame_in[i] = sample(i, sent[i]);
    end
    `include "partition_peers_devices.vh"
    initial begin
        for (integer i = 0; i < 16; i = i+1) begin sent[i] = 0; received[i] = 0; out_ready[i] = 0; end
        repeat (8) @(negedge clk);
        reset = 0;
    end
    always @(negedge clk) begin
        for (integer i = 0; i < 16; i = i+1)
            out_ready[i] = (i % 8 >= 2 || cycle >= 2000) && (cycle+i) % 7 >= 2;
    end
    always @(posedge clk) if (!reset) begin
        cycle <= cycle+1;
        for (integer p = 0; p < 8; p = p+1)
            if (fault_valid[p] !== 1'b0) $fatal(1, "peer protocol fault %0d: %h", p, fault[p]);
        for (integer i = 0; i < 16; i = i+1) begin
            if (sent[i] < COUNT && in_ready[i]) sent[i] <= sent[i]+1;
            if (out_valid[i] && out_ready[i]) begin
                if (received[i] >= COUNT || frame_out[i] !== sample(i ^ 8, received[i]))
                    $fatal(1, "misrouted, missing, repeated or reordered frame on %0d", i);
                received[i] <= received[i]+1;
            end
            if (cycle == 1500 && i % 8 >= 2 && received[i] != COUNT)
                $fatal(1, "blocked peer stalled unrelated peer %0d", i);
            if (cycle == 1500 && i % 8 < 2 && received[i] != 0)
                $fatal(1, "blocked recipient accepted a frame");
        end
        if (cycle == 3500) begin
            for (integer i = 0; i < 16; i = i+1)
                if (received[i] != COUNT) $fatal(1, "missing final frames on %0d", i);
            $display("PASS: four peers, reused lane IDs, blocked-peer isolation, 384 ordered frames");
            $finish;
        end
    end
    initial begin #40000; $fatal(1, "peer isolation timeout"); end
endmodule
