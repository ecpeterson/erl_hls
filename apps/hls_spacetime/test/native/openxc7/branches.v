// Two distinct observable registers share one LUT output through two net aliases.
module top(input wire clock, output wire activity);
    wire d, q, d_alias;
    assign d_alias = d;
    LUT1 #(.INIT(2'b01)) invert (.I0(q), .O(d));
    FDRE #(.INIT(1'b0)) first (.C(clock), .CE(1'b1), .R(1'b0), .D(d), .Q(q));
    FDSE #(.INIT(1'b1)) second (.C(clock), .CE(1'b1), .S(1'b0), .D(d_alias), .Q(activity));
endmodule
