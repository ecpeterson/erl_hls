// Arbitrary application writes, mailbox publications, queries, and later resets.
// The SAT driver asserts reset on the first sampled clock edge.
module hls_actor_snapshot_formal #(
    parameter SLOTS=3, MAILBOX=1,
    parameter AW=SLOTS < 2 ? 1 : $clog2(SLOTS)
)(
    input clk, reset, write_enable, mailbox_valid,
    input [AW-1:0] write_address, read_address,
    input [24:0] write_value,
    input [SLOTS*24-1:0] mailbox_values,
    output match
);
    wire [63:0] value;
    hls_actor_snapshot #(.SLOTS(SLOTS), .ADDRESS_WIDTH(AW), .MAILBOX(MAILBOX)) dut (.*);
    reg started=0;
    always @(posedge clk) begin
        started <= 1;
    end
    wire [SLOTS*64-1:0] reference;
    genvar slot;
    generate for(slot=0; slot<SLOTS; slot=slot+1) begin: actor
        reg [25:0] state;
        reg [23:0] mailbox;
        always @(posedge clk) begin
            if(reset) begin state<=0; mailbox<=0; end
            else begin
                if(write_enable && write_address==slot) state<={1'b1,write_value};
                if(mailbox_valid) mailbox<=mailbox_values[slot*24+:24];
            end
        end
        assign reference[slot*64+:64] = {8'b0, (MAILBOX ? mailbox : 24'b0), 6'b0, state};
    end endgenerate
    wire [63:0] expected = read_address < SLOTS ? reference[read_address*64+:64] : 64'b0;
    assign match = !started || value == expected;
endmodule
