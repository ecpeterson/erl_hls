// Small native-packer regression: both O and CO leave the carry through distinct
// LUT consumers, including a bit-one split which creates a new CO0 consumer.
// MODE=0/1 uses explicit constant root carry-in; MODE=2 uses a real carry spine.
module carry_head_fixture #(parameter MODE = 0) (
    input wire [3:0] select_bits,
    input wire [3:0] generate_bits,
    input wire dynamic_carry,
    input wire salt,
    output wire [3:0] result
);
    wire carry_in;
    generate if (MODE == 2) begin : dynamic_source
        wire [3:0] upstream_carry;
        (* keep *) CARRY4 upstream(.CI(1'b0), .CYINIT(1'b0),
            .S(4'b1110), .DI({3'b000, dynamic_carry}), .O(), .CO(upstream_carry));
        assign carry_in = upstream_carry[3];
    end else begin : constant_source
        assign carry_in = 1'b0;
    end endgenerate
    wire [3:0] sums, carries;
    (* keep *) CARRY4 target(.CI(carry_in), .CYINIT(MODE == 1),
        .S(select_bits), .DI(generate_bits), .O(sums), .CO(carries));
    (* keep *) LUT2 #(.INIT(4'h6)) sum0(.I0(sums[0]), .I1(salt), .O(result[0]));
    (* keep *) LUT2 #(.INIT(4'h6)) carry0(.I0(carries[0]), .I1(salt), .O(result[1]));
    (* keep *) LUT2 #(.INIT(4'h6)) sum1(.I0(sums[1]), .I1(salt), .O(result[2]));
    (* keep *) LUT2 #(.INIT(4'h6)) carry1(.I0(carries[1]), .I1(salt), .O(result[3]));
endmodule
