`timescale 1ns/1ps

// Area/latency witness for time-multiplexing the phi Q15.16 recurrence.
//
// This is not part of the raw decoder boundary.  It isolates exactly the two
// rounded divisions performed for one phi cell, so independent lane counts can
// be mapped without duplicating unrelated command, event, and state machinery.
module phi_relax_lane (
    input  wire               aclk,
    input  wire               aresetn,
    input  wire               start,
    input  wire               anyon,
    input  wire signed [31:0] center0,
    input  wire signed [31:0] center1,
    input  wire signed [31:0] north0,
    input  wire signed [31:0] east0,
    input  wire signed [31:0] west0,
    input  wire signed [31:0] south0,
    input  wire signed [31:0] north1,
    input  wire signed [31:0] east1,
    input  wire signed [31:0] west1,
    input  wire signed [31:0] south1,
    output reg                done,
    output wire               busy,
    output reg signed [31:0]  result0,
    output reg signed [31:0]  result1
);
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] DIVIDE_0 = 2'd1;
    localparam [1:0] DIVIDE_1 = 2'd2;

    reg [1:0] state;
    reg pending_anyon;
    reg signed [36:0] pending_numerator1;
    reg [37:0] dividend;
    reg [37:0] quotient;
    reg [5:0] remainder;
    reg [5:0] divisor;
    reg [5:0] bit_index;
    reg negative;

    function automatic signed [36:0] center_numerator(
        input signed [31:0] phi0,
        input signed [31:0] phi1,
        input signed [31:0] north,
        input signed [31:0] east,
        input signed [31:0] west,
        input signed [31:0] south
    );
        reg signed [36:0] p0;
        reg signed [36:0] p1;
        reg signed [36:0] n;
        reg signed [36:0] e;
        reg signed [36:0] w;
        reg signed [36:0] s;
        begin
            p0 = phi0;
            p1 = phi1;
            n = north;
            e = east;
            w = west;
            s = south;
            center_numerator = (p0 <<< 4) + (p0 <<< 1) +
                (p1 <<< 1) + n + e + w + s;
        end
    endfunction

    function automatic signed [36:0] bulk_numerator(
        input signed [31:0] phi0,
        input signed [31:0] phi1,
        input signed [31:0] north,
        input signed [31:0] east,
        input signed [31:0] west,
        input signed [31:0] south
    );
        reg signed [36:0] p0;
        reg signed [36:0] p1;
        reg signed [36:0] n;
        reg signed [36:0] e;
        reg signed [36:0] w;
        reg signed [36:0] s;
        begin
            p0 = phi0;
            p1 = phi1;
            n = north;
            e = east;
            w = west;
            s = south;
            bulk_numerator = p0 + (p1 <<< 4) - p1 + n + e + w + s;
        end
    endfunction

    function automatic [36:0] magnitude37(input signed [36:0] value);
        magnitude37 = value[36] ? -value : value;
    endfunction

    function automatic signed [38:0] signed_quotient(
        input is_negative,
        input [37:0] magnitude
    );
        reg signed [38:0] positive;
        begin
            positive = $signed({1'b0, magnitude});
            signed_quotient = is_negative ? -positive : positive;
        end
    endfunction

    function automatic signed [31:0] saturate_s32(
        input signed [38:0] value
    );
        begin
            if (value > 39'sd2147483647)
                saturate_s32 = 32'sh7fffffff;
            else if (value < -39'sd2147483648)
                saturate_s32 = -32'sd2147483648;
            else
                saturate_s32 = value[31:0];
        end
    endfunction

    wire signed [36:0] numerator0 = center_numerator(
        center0, center1, north0, east0, west0, south0
    );
    wire signed [36:0] numerator1 = bulk_numerator(
        center0, center1, north1, east1, west1, south1
    );
    wire [6:0] shifted_remainder =
        {remainder, dividend[bit_index]};
    wire division_takes = shifted_remainder >= {1'b0, divisor};
    wire [37:0] next_quotient = quotient |
        (division_takes ? (38'b1 << bit_index) : 38'b0);
    wire [5:0] next_remainder = division_takes ?
        shifted_remainder - {1'b0, divisor} : shifted_remainder[5:0];
    wire signed [38:0] completed_quotient =
        signed_quotient(negative, next_quotient);

    assign busy = state != IDLE;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state <= IDLE;
            pending_anyon <= 1'b0;
            pending_numerator1 <= 37'sd0;
            dividend <= 38'd0;
            quotient <= 38'd0;
            remainder <= 6'd0;
            divisor <= 6'd0;
            bit_index <= 6'd0;
            negative <= 1'b0;
            done <= 1'b0;
            result0 <= 32'sd0;
            result1 <= 32'sd0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: if (start) begin
                    pending_anyon <= anyon;
                    pending_numerator1 <= numerator1;
                    dividend <= {1'b0, magnitude37(numerator0)} + 38'd12;
                    quotient <= 38'd0;
                    remainder <= 6'd0;
                    divisor <= 6'd24;
                    bit_index <= 6'd37;
                    negative <= numerator0[36];
                    state <= DIVIDE_0;
                end
                DIVIDE_0: begin
                    quotient <= next_quotient;
                    remainder <= next_remainder;
                    if (bit_index == 0) begin
                        result0 <= saturate_s32(
                            completed_quotient +
                            (pending_anyon ? 39'sd65536 : 39'sd0)
                        );
                        dividend <=
                            {1'b0, magnitude37(pending_numerator1)} + 38'd10;
                        quotient <= 38'd0;
                        remainder <= 6'd0;
                        divisor <= 6'd20;
                        bit_index <= 6'd37;
                        negative <= pending_numerator1[36];
                        state <= DIVIDE_1;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                    end
                end
                DIVIDE_1: begin
                    quotient <= next_quotient;
                    remainder <= next_remainder;
                    if (bit_index == 0) begin
                        result1 <= saturate_s32(completed_quotient);
                        done <= 1'b1;
                        state <= IDLE;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

module phi_relax_bank #(
    parameter integer LANES = 1
) (
    input  wire                   aclk,
    input  wire                   aresetn,
    input  wire [LANES-1:0]       start,
    input  wire [LANES-1:0]       anyon,
    input  wire [32*LANES-1:0]    center0,
    input  wire [32*LANES-1:0]    center1,
    input  wire [32*LANES-1:0]    north0,
    input  wire [32*LANES-1:0]    east0,
    input  wire [32*LANES-1:0]    west0,
    input  wire [32*LANES-1:0]    south0,
    input  wire [32*LANES-1:0]    north1,
    input  wire [32*LANES-1:0]    east1,
    input  wire [32*LANES-1:0]    west1,
    input  wire [32*LANES-1:0]    south1,
    output wire [LANES-1:0]       done,
    output wire [LANES-1:0]       busy,
    output wire [32*LANES-1:0]    result0,
    output wire [32*LANES-1:0]    result1
);
    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : lanes
            phi_relax_lane relax (
                .aclk(aclk),
                .aresetn(aresetn),
                .start(start[lane]),
                .anyon(anyon[lane]),
                .center0(center0[32*lane +: 32]),
                .center1(center1[32*lane +: 32]),
                .north0(north0[32*lane +: 32]),
                .east0(east0[32*lane +: 32]),
                .west0(west0[32*lane +: 32]),
                .south0(south0[32*lane +: 32]),
                .north1(north1[32*lane +: 32]),
                .east1(east1[32*lane +: 32]),
                .west1(west1[32*lane +: 32]),
                .south1(south1[32*lane +: 32]),
                .done(done[lane]),
                .busy(busy[lane]),
                .result0(result0[32*lane +: 32]),
                .result1(result1[32*lane +: 32])
            );
        end
    endgenerate
endmodule

module phi_relax_bank_1 (
    input wire aclk, input wire aresetn,
    input wire [0:0] start, input wire [0:0] anyon,
    input wire [31:0] center0, center1, north0, east0, west0, south0,
    input wire [31:0] north1, east1, west1, south1,
    output wire [0:0] done, output wire [0:0] busy,
    output wire [31:0] result0, result1
);
    phi_relax_bank #(.LANES(1)) bank (.*);
endmodule

`define PHI_RELAX_BANK_TOP(N) \
module phi_relax_bank_``N ( \
    input wire aclk, input wire aresetn, \
    input wire [N-1:0] start, input wire [N-1:0] anyon, \
    input wire [32*N-1:0] center0, center1, north0, east0, west0, south0, \
    input wire [32*N-1:0] north1, east1, west1, south1, \
    output wire [N-1:0] done, output wire [N-1:0] busy, \
    output wire [32*N-1:0] result0, result1 \
); \
    phi_relax_bank #(.LANES(N)) bank (.*); \
endmodule

`PHI_RELAX_BANK_TOP(2)
`PHI_RELAX_BANK_TOP(4)
`PHI_RELAX_BANK_TOP(9)
`PHI_RELAX_BANK_TOP(18)
