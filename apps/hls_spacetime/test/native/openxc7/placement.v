// One synchronous feedback path with observable output and package-constrained I/O.
module top(input wire clock, output wire activity);
    wire d, q;
    LUT1 #(.INIT(2'b01)) invert (.I0(q), .O(d));
    FDRE #(.INIT(1'b0)) state (.C(clock), .CE(1'b1), .R(1'b0), .D(d), .Q(q));
    assign activity = q;
endmodule
