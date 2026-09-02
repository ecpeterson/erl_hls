`timescale 1ns/1ps

// Fixed-distance, time-multiplexed baseline for the phi memory experiment.
//
// This is intentionally not a second general backend. It implements the
// canonical d=3, 50%-noise fixture behind the same routed application stream
// as phi_memory_gateway. The actor graph's barriers are replaced by one
// globally synchronous controller: data and syndrome updates are scanned,
// both Jacobi rounds use separate old/new field arrays, all moves are chosen
// from one snapshot, and move parity is committed in a second pass.
//
// The design favors a resource lower bound over throughput. One restoring
// divider is shared by every Q15.16 update, and every event is serialized
// before the next decoder step begins.

module phi_memory_raw_d3 (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    output reg  [31:0] m_axis_tdata,
    output wire [3:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);
    localparam integer DISTANCE = 3;
    localparam integer DATA_COUNT = 18;
    localparam integer PLANE_COUNT = 9;
    localparam integer PHI_COUNT = 18;

    localparam [31:0] SEED_STRIDE = 32'h9e3779b9;
    localparam [31:0] NOISE_RATE = 32'h80000000;

    localparam [31:0] INPUT_ROUTE = 32'h00000001;
    localparam [31:0] CUTOFF_HEADER = 32'h0f010003;
    localparam [31:0] UPDATE_HEADER = 32'h10010003;
    localparam [31:0] QUERY_HEADER = 32'h0d010004;

    localparam [15:0] DATA_ENDPOINT = 16'd2;
    localparam [15:0] X_ANNOUNCEMENTS_ENDPOINT = 16'd3;
    localparam [15:0] X_DECODER_EVENTS_ENDPOINT = 16'd4;
    localparam [15:0] Z_ANNOUNCEMENTS_ENDPOINT = 16'd5;
    localparam [15:0] Z_DECODER_EVENTS_ENDPOINT = 16'd6;

    localparam [7:0] OP_ANNOUNCEMENT = 8'd10;
    localparam [7:0] OP_CORRECTION = 8'd11;
    localparam [7:0] OP_PAULI_REPLY = 8'd14;
    localparam [7:0] OP_STATUS = 8'd17;

    localparam [3:0] NORTH = 4'd1;
    localparam [3:0] EAST = 4'd2;
    localparam [3:0] WEST = 4'd4;
    localparam [3:0] SOUTH = 4'd8;

    localparam [4:0] S_INIT = 5'd0;
    localparam [4:0] S_WAIT_CUTOFF = 5'd1;
    localparam [4:0] S_DATA = 5'd2;
    localparam [4:0] S_SYNDROME = 5'd3;
    localparam [4:0] S_DIFF_PREP = 5'd4;
    localparam [4:0] S_DIVIDE_PHI0 = 5'd5;
    localparam [4:0] S_DIVIDE_PHI1 = 5'd6;
    localparam [4:0] S_COMPARE = 5'd7;
    localparam [4:0] S_APPLY = 5'd8;
    localparam [4:0] S_EMIT = 5'd9;
    localparam [4:0] S_WAIT_QUERY = 5'd10;
    localparam [4:0] S_REPLY = 5'd11;

    localparam [2:0] EMIT_ANNOUNCE_X = 3'd0;
    localparam [2:0] EMIT_ANNOUNCE_Z = 3'd1;
    localparam [2:0] EMIT_CORRECTION_X = 3'd2;
    localparam [2:0] EMIT_CORRECTION_Z = 3'd3;
    localparam [2:0] EMIT_STATUS_X = 3'd4;
    localparam [2:0] EMIT_STATUS_Z = 3'd5;
    localparam [2:0] EMIT_DONE = 3'd6;

    localparam [2:0] IN_ROUTE = 3'd0;
    localparam [2:0] IN_HEADER = 3'd1;
    localparam [2:0] IN_RECT0 = 3'd2;
    localparam [2:0] IN_RECT1 = 3'd3;
    localparam [2:0] IN_PAYLOAD0 = 3'd4;
    localparam [2:0] IN_PAYLOAD1 = 3'd5;
    localparam [2:0] IN_DROP = 3'd6;

    reg [4:0] engine_state;
    reg [31:0] step;
    reg [4:0] cell_index;

    // Source order is k=3*x+y for each 3x3 family. Physical data order is
    // q=6*x+y, so even and odd startup families interleave in this array.
    reg [31:0] data_rng [0:DATA_COUNT-1];
    reg [1:0] data_pauli [0:DATA_COUNT-1];
    reg data_event [0:DATA_COUNT-1];

    reg [31:0] syndrome_rng [0:PHI_COUNT-1];
    reg syndrome_previous [0:PHI_COUNT-1];
    reg syndrome_event [0:PHI_COUNT-1];
    reg syndrome_quiet [0:PHI_COUNT-1];

    reg [31:0] phi_rng [0:PHI_COUNT-1];
    reg phi_anyon [0:PHI_COUNT-1];
    reg signed [31:0] phi0_a [0:PHI_COUNT-1];
    reg signed [31:0] phi1_a [0:PHI_COUNT-1];
    reg signed [31:0] phi0_b [0:PHI_COUNT-1];
    reg signed [31:0] phi1_b [0:PHI_COUNT-1];
    reg [3:0] move_direction [0:PHI_COUNT-1];

    reg [2:0] init_family;
    reg [3:0] init_position;
    reg [31:0] seed_cursor;

    reg cutoff_received;
    reg [31:0] cutoff_step;
    reg query_pending;
    reg [31:0] query_request_id;
    reg [1:0] query_measurement;
    reg [15:0] query_x0;
    reg [15:0] query_y0;
    reg [15:0] query_x1;
    reg [15:0] query_y1;

    reg diffusion_round;
    reg signed [36:0] pending_phi1_numerator;
    reg signed [31:0] pending_new_phi0;

    reg [37:0] div_dividend;
    reg [37:0] div_quotient;
    reg [5:0] div_remainder;
    reg [5:0] div_divisor;
    reg [5:0] div_bit;
    reg div_negative;

    reg anyon_seen;
    reg quiescent_after_step;
    reg [2:0] emit_phase;
    reg [5:0] emit_index;

    reg out_busy;
    reg [2:0] out_word;
    reg [15:0] out_source;
    reg [7:0] out_op;
    reg [31:0] out_payload0;
    reg [31:0] out_payload1;
    reg [31:0] out_payload2;

    reg [2:0] in_state;
    reg [31:0] in_header;
    reg [15:0] in_x0;
    reg [15:0] in_y0;
    reg [15:0] in_x1;
    reg [15:0] in_y1;
    reg [31:0] in_payload0;

    integer i;

    function automatic [31:0] xorshift32(input [31:0] value);
        reg [31:0] first;
        reg [31:0] second;
        begin
            first = value ^ (value << 13);
            second = first ^ (first >> 17);
            xorshift32 = second ^ (second << 5);
        end
    endfunction

    function automatic [4:0] physical_data_index(
        input integer x,
        input integer y
    );
        integer wrapped_y;
        begin
            if (y < 0)
                wrapped_y = y + 6;
            else if (y >= 6)
                wrapped_y = y - 6;
            else
                wrapped_y = y;
            physical_data_index = x * 6 + wrapped_y;
        end
    endfunction

    function automatic [4:0] syndrome_data_index(
        input [4:0] index,
        input [1:0] arm
    );
        integer local_index;
        integer x;
        integer y;
        integer xp;
        begin
            local_index = index;
            if (local_index >= PLANE_COUNT)
                local_index = local_index - PLANE_COUNT;
            x = local_index / 3;
            y = local_index % 3;
            xp = (x == 2) ? 0 : x + 1;
            if (index < PLANE_COUNT) begin
                case (arm)
                    0: syndrome_data_index = physical_data_index(x, 2*y-1);
                    1: syndrome_data_index = physical_data_index(xp, 2*y);
                    2: syndrome_data_index = physical_data_index(x, 2*y);
                    default:
                        syndrome_data_index = physical_data_index(x, 2*y+1);
                endcase
            end else begin
                case (arm)
                    0: syndrome_data_index = physical_data_index(xp, 2*y);
                    1: syndrome_data_index = physical_data_index(xp, 2*y+1);
                    2: syndrome_data_index = physical_data_index(x, 2*y+1);
                    default:
                        syndrome_data_index = physical_data_index(xp, 2*y+2);
                endcase
            end
        end
    endfunction

    function automatic [4:0] phi_neighbor(
        input [4:0] index,
        input [3:0] direction
    );
        integer plane;
        integer local_index;
        integer x;
        integer y;
        integer nx;
        integer ny;
        begin
            plane = (index >= PLANE_COUNT) ? PLANE_COUNT : 0;
            local_index = index - plane;
            x = local_index / 3;
            y = local_index % 3;
            nx = x;
            ny = y;
            case (direction)
                NORTH: ny = (y == 0) ? 2 : y - 1;
                EAST: nx = (x == 2) ? 0 : x + 1;
                WEST: nx = (x == 0) ? 2 : x - 1;
                SOUTH: ny = (y == 2) ? 0 : y + 1;
                default: begin nx = x; ny = y; end
            endcase
            phi_neighbor = plane + 3*nx + ny;
        end
    endfunction

    function automatic signed [36:0] center_numerator(
        input signed [31:0] center0,
        input signed [31:0] center1,
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
            p0 = center0;
            p1 = center1;
            n = north;
            e = east;
            w = west;
            s = south;
            center_numerator = (p0 <<< 4) + (p0 <<< 1) +
                (p1 <<< 1) + n + e + w + s;
        end
    endfunction

    function automatic signed [36:0] bulk_numerator(
        input signed [31:0] center0,
        input signed [31:0] center1,
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
            p0 = center0;
            p1 = center1;
            n = north;
            e = east;
            w = west;
            s = south;
            bulk_numerator = p0 + (p1 <<< 4) - p1 + n + e + w + s;
        end
    endfunction

    function automatic [36:0] magnitude37(input signed [36:0] value);
        begin
            magnitude37 = value[36] ? -value : value;
        end
    endfunction

    function automatic signed [38:0] signed_quotient(
        input negative,
        input [37:0] magnitude
    );
        reg signed [38:0] positive;
        begin
            positive = $signed({1'b0, magnitude});
            signed_quotient = negative ? -positive : positive;
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

    function automatic [3:0] winner_direction(input [4:0] index);
        reg signed [31:0] best;
        reg signed [31:0] candidate;
        reg [3:0] direction;
        reg unique_best;
        begin
            best = phi0_a[phi_neighbor(index, NORTH)];
            direction = NORTH;
            unique_best = 1'b1;

            candidate = phi0_a[phi_neighbor(index, EAST)];
            if (candidate > best) begin
                best = candidate;
                direction = EAST;
                unique_best = 1'b1;
            end else if (candidate == best) begin
                unique_best = 1'b0;
            end

            candidate = phi0_a[phi_neighbor(index, WEST)];
            if (candidate > best) begin
                best = candidate;
                direction = WEST;
                unique_best = 1'b1;
            end else if (candidate == best) begin
                unique_best = 1'b0;
            end

            candidate = phi0_a[phi_neighbor(index, SOUTH)];
            if (candidate > best) begin
                direction = SOUTH;
                unique_best = 1'b1;
            end else if (candidate == best) begin
                unique_best = 1'b0;
            end

            winner_direction = unique_best ? direction : 4'd0;
        end
    endfunction

    function automatic data_selected(
        input [4:0] index,
        input [15:0] x0,
        input [15:0] y0,
        input [15:0] x1,
        input [15:0] y1
    );
        integer x;
        integer y;
        begin
            x = index / 6;
            y = index % 6;
            data_selected = x >= x0 && x <= x1 && y >= y0 && y <= y1;
        end
    endfunction

    function automatic [31:0] phi_coordinate_word(input [5:0] index);
        reg [15:0] x;
        reg [15:0] y;
        begin
            x = index / 3;
            y = index % 3;
            phi_coordinate_word = {y, x};
        end
    endfunction

    function automatic [31:0] data_coordinate_word(input [5:0] index);
        reg [15:0] x;
        reg [15:0] y;
        begin
            x = index / 6;
            y = index % 6;
            data_coordinate_word = {y, x};
        end
    endfunction

    function automatic pauli_anticommutes(
        input [1:0] left,
        input [1:0] right
    );
        begin
            pauli_anticommutes =
                (((left >> 1) & right) ^ (left & (right >> 1))) & 1'b1;
        end
    endfunction

    task automatic queue_event(
        input [15:0] source,
        input [7:0] op,
        input [31:0] payload0,
        input [31:0] payload1,
        input [31:0] payload2
    );
        begin
            out_source <= source;
            out_op <= op;
            out_payload0 <= payload0;
            out_payload1 <= payload1;
            out_payload2 <= payload2;
            out_word <= 3'd0;
            out_busy <= 1'b1;
        end
    endtask

    wire [31:0] data_next_random = xorshift32(data_rng[cell_index]);
    wire noise_quiet = step >= cutoff_step;
    wire data_next_event = !noise_quiet && data_next_random < NOISE_RATE;

    wire syndrome_parity =
        data_event[syndrome_data_index(cell_index, 0)] ^
        data_event[syndrome_data_index(cell_index, 1)] ^
        data_event[syndrome_data_index(cell_index, 2)] ^
        data_event[syndrome_data_index(cell_index, 3)];
    wire [31:0] syndrome_next_random =
        xorshift32(syndrome_rng[cell_index]);
    wire syndrome_measurement =
        !noise_quiet && syndrome_next_random < NOISE_RATE;
    wire syndrome_detection = syndrome_parity ^ syndrome_measurement ^
        syndrome_previous[cell_index];

    wire [4:0] diff_north = phi_neighbor(cell_index, NORTH);
    wire [4:0] diff_east = phi_neighbor(cell_index, EAST);
    wire [4:0] diff_west = phi_neighbor(cell_index, WEST);
    wire [4:0] diff_south = phi_neighbor(cell_index, SOUTH);
    wire signed [31:0] diff_phi0 = diffusion_round ?
        phi0_b[cell_index] : phi0_a[cell_index];
    wire signed [31:0] diff_phi1 = diffusion_round ?
        phi1_b[cell_index] : phi1_a[cell_index];
    wire signed [31:0] diff_north0 = diffusion_round ?
        phi0_b[diff_north] : phi0_a[diff_north];
    wire signed [31:0] diff_east0 = diffusion_round ?
        phi0_b[diff_east] : phi0_a[diff_east];
    wire signed [31:0] diff_west0 = diffusion_round ?
        phi0_b[diff_west] : phi0_a[diff_west];
    wire signed [31:0] diff_south0 = diffusion_round ?
        phi0_b[diff_south] : phi0_a[diff_south];
    wire signed [31:0] diff_north1 = diffusion_round ?
        phi1_b[diff_north] : phi1_a[diff_north];
    wire signed [31:0] diff_east1 = diffusion_round ?
        phi1_b[diff_east] : phi1_a[diff_east];
    wire signed [31:0] diff_west1 = diffusion_round ?
        phi1_b[diff_west] : phi1_a[diff_west];
    wire signed [31:0] diff_south1 = diffusion_round ?
        phi1_b[diff_south] : phi1_a[diff_south];
    wire signed [36:0] phi0_numerator = center_numerator(
        diff_phi0, diff_phi1,
        diff_north0, diff_east0, diff_west0, diff_south0
    );
    wire signed [36:0] phi1_numerator = bulk_numerator(
        diff_phi0, diff_phi1,
        diff_north1, diff_east1, diff_west1, diff_south1
    );

    wire [6:0] shifted_remainder =
        {div_remainder, div_dividend[div_bit]};
    wire division_takes = shifted_remainder >= {1'b0, div_divisor};
    wire [37:0] division_quotient = div_quotient |
        (division_takes ? (38'b1 << div_bit) : 38'b0);
    wire [5:0] division_remainder = division_takes ?
        shifted_remainder - {1'b0, div_divisor} : shifted_remainder[5:0];
    wire signed [38:0] completed_quotient =
        signed_quotient(div_negative, division_quotient);
    wire signed [38:0] completed_phi0 = completed_quotient +
        (phi_anyon[cell_index] ? 39'sd65536 : 39'sd0);

    wire [3:0] selected_direction = winner_direction(cell_index);
    wire [31:0] phi_next_random = xorshift32(phi_rng[cell_index]);
    wire selected_move = phi_anyon[cell_index] &&
        selected_direction != 0 && phi_next_random[31];

    wire incoming_move =
        (move_direction[phi_neighbor(cell_index, NORTH)] == SOUTH) ^
        (move_direction[phi_neighbor(cell_index, EAST)] == WEST) ^
        (move_direction[phi_neighbor(cell_index, WEST)] == EAST) ^
        (move_direction[phi_neighbor(cell_index, SOUTH)] == NORTH);
    wire next_anyon = phi_anyon[cell_index] ^
        (move_direction[cell_index] != 0) ^ incoming_move;

    wire rectangle_valid = in_x0 <= in_x1 && in_x1 < DISTANCE &&
        in_y0 <= in_y1 && in_y1 < 2*DISTANCE;

    assign s_axis_tready = 1'b1;
    assign m_axis_tkeep = 4'hf;
    assign m_axis_tvalid = out_busy;
    assign m_axis_tlast = out_busy && out_word == 3'd4;

    always @* begin
        case (out_word)
            3'd0: m_axis_tdata = {out_source, 16'd0};
            3'd1: m_axis_tdata = {out_op, 8'd1, 8'd0, 8'd3};
            3'd2: m_axis_tdata = out_payload0;
            3'd3: m_axis_tdata = out_payload1;
            default: m_axis_tdata = out_payload2;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            engine_state <= S_INIT;
            step <= 32'd0;
            cell_index <= 5'd0;
            init_family <= 3'd0;
            init_position <= 4'd0;
            seed_cursor <= SEED_STRIDE;
            cutoff_received <= 1'b0;
            cutoff_step <= 32'd0;
            query_pending <= 1'b0;
            query_request_id <= 32'd0;
            query_measurement <= 2'd0;
            query_x0 <= 16'd0;
            query_y0 <= 16'd0;
            query_x1 <= 16'd0;
            query_y1 <= 16'd0;
            diffusion_round <= 1'b0;
            pending_phi1_numerator <= 37'sd0;
            pending_new_phi0 <= 32'sd0;
            div_dividend <= 38'd0;
            div_quotient <= 38'd0;
            div_remainder <= 6'd0;
            div_divisor <= 6'd0;
            div_bit <= 6'd0;
            div_negative <= 1'b0;
            anyon_seen <= 1'b0;
            quiescent_after_step <= 1'b0;
            emit_phase <= EMIT_DONE;
            emit_index <= 6'd0;
            out_busy <= 1'b0;
            out_word <= 3'd0;
            out_source <= 16'd0;
            out_op <= 8'd0;
            out_payload0 <= 32'd0;
            out_payload1 <= 32'd0;
            out_payload2 <= 32'd0;
            in_state <= IN_ROUTE;
            in_header <= 32'd0;
            in_x0 <= 16'd0;
            in_y0 <= 16'd0;
            in_x1 <= 16'd0;
            in_y1 <= 16'd0;
            in_payload0 <= 32'd0;
        end else begin
            // Independent routed-command receiver. Invalid packets are
            // drained through TLAST so the next route beat resynchronizes.
            if (s_axis_tvalid) begin
                case (in_state)
                    IN_ROUTE: begin
                        if (!s_axis_tlast && s_axis_tdata == INPUT_ROUTE)
                            in_state <= IN_HEADER;
                        else if (!s_axis_tlast)
                            in_state <= IN_DROP;
                    end
                    IN_HEADER: begin
                        in_header <= s_axis_tdata;
                        if (s_axis_tlast)
                            in_state <= IN_ROUTE;
                        else if (s_axis_tdata == CUTOFF_HEADER ||
                                 s_axis_tdata == UPDATE_HEADER ||
                                 s_axis_tdata == QUERY_HEADER)
                            in_state <= IN_RECT0;
                        else
                            in_state <= IN_DROP;
                    end
                    IN_RECT0: begin
                        if (s_axis_tlast) begin
                            in_state <= IN_ROUTE;
                        end else begin
                            in_x0 <= s_axis_tdata[15:0];
                            in_y0 <= s_axis_tdata[31:16];
                            in_state <= IN_RECT1;
                        end
                    end
                    IN_RECT1: begin
                        if (s_axis_tlast) begin
                            in_state <= IN_ROUTE;
                        end else begin
                            in_x1 <= s_axis_tdata[15:0];
                            in_y1 <= s_axis_tdata[31:16];
                            in_state <= IN_PAYLOAD0;
                        end
                    end
                    IN_PAYLOAD0: begin
                        if (in_header == QUERY_HEADER) begin
                            if (s_axis_tlast)
                                in_state <= IN_ROUTE;
                            else begin
                                in_payload0 <= s_axis_tdata;
                                in_state <= IN_PAYLOAD1;
                            end
                        end else begin
                            if (s_axis_tlast && rectangle_valid) begin
                                if (in_header == CUTOFF_HEADER &&
                                    in_x0 == 0 && in_y0 == 0 &&
                                    in_x1 == 2 && in_y1 == 5 &&
                                    !cutoff_received) begin
                                    cutoff_step <= s_axis_tdata;
                                    cutoff_received <= 1'b1;
                                end else if (in_header == UPDATE_HEADER &&
                                             s_axis_tdata <= 3) begin
                                    for (i = 0; i < DATA_COUNT; i = i + 1)
                                        if (data_selected(
                                                i, in_x0, in_y0,
                                                in_x1, in_y1))
                                            data_pauli[i] <=
                                                data_pauli[i] ^
                                                s_axis_tdata[1:0];
                                end
                            end
                            in_state <= s_axis_tlast ? IN_ROUTE : IN_DROP;
                        end
                    end
                    IN_PAYLOAD1: begin
                        if (s_axis_tlast && rectangle_valid &&
                            s_axis_tdata <= 3) begin
                            query_request_id <= in_payload0;
                            query_measurement <= s_axis_tdata[1:0];
                            query_x0 <= in_x0;
                            query_y0 <= in_y0;
                            query_x1 <= in_x1;
                            query_y1 <= in_y1;
                            query_pending <= 1'b1;
                        end
                        in_state <= s_axis_tlast ? IN_ROUTE : IN_DROP;
                    end
                    default: begin
                        if (s_axis_tlast)
                            in_state <= IN_ROUTE;
                    end
                endcase
            end

            if (out_busy && m_axis_tready) begin
                if (out_word == 3'd4)
                    out_busy <= 1'b0;
                else
                    out_word <= out_word + 1'b1;
            end

            case (engine_state)
                S_INIT: begin
                    case (init_family)
                        0: begin
                            data_rng[(init_position/3)*6 +
                                2*(init_position%3)] <= seed_cursor;
                            data_pauli[(init_position/3)*6 +
                                2*(init_position%3)] <= 2'd0;
                            data_event[(init_position/3)*6 +
                                2*(init_position%3)] <= 1'b0;
                        end
                        1: begin
                            data_rng[(init_position/3)*6 +
                                2*(init_position%3) + 1] <= seed_cursor;
                            data_pauli[(init_position/3)*6 +
                                2*(init_position%3) + 1] <= 2'd0;
                            data_event[(init_position/3)*6 +
                                2*(init_position%3) + 1] <= 1'b0;
                        end
                        2, 3: begin
                            syndrome_rng[(init_family-2)*9 +
                                init_position] <= seed_cursor;
                            syndrome_previous[(init_family-2)*9 +
                                init_position] <= 1'b0;
                            syndrome_event[(init_family-2)*9 +
                                init_position] <= 1'b0;
                            syndrome_quiet[(init_family-2)*9 +
                                init_position] <= 1'b0;
                        end
                        default: begin
                            phi_rng[(init_family-4)*9 + init_position]
                                <= seed_cursor;
                            phi_anyon[(init_family-4)*9 + init_position]
                                <= 1'b0;
                            phi0_a[(init_family-4)*9 + init_position]
                                <= 32'sd0;
                            phi1_a[(init_family-4)*9 + init_position]
                                <= 32'sd0;
                            phi0_b[(init_family-4)*9 + init_position]
                                <= 32'sd0;
                            phi1_b[(init_family-4)*9 + init_position]
                                <= 32'sd0;
                            move_direction[(init_family-4)*9 + init_position]
                                <= 4'd0;
                        end
                    endcase
                    seed_cursor <= seed_cursor + SEED_STRIDE;
                    if (init_position == 8) begin
                        init_position <= 0;
                        if (init_family == 5) begin
                            engine_state <= S_WAIT_CUTOFF;
                            cell_index <= 0;
                        end else begin
                            init_family <= init_family + 1'b1;
                        end
                    end else begin
                        init_position <= init_position + 1'b1;
                    end
                end

                S_WAIT_CUTOFF: begin
                    if (cutoff_received) begin
                        step <= 0;
                        cell_index <= 0;
                        engine_state <= S_DATA;
                    end
                end

                S_DATA: begin
                    if (noise_quiet) begin
                        data_event[cell_index] <= 1'b0;
                    end else begin
                        data_rng[cell_index] <= data_next_random;
                        data_event[cell_index] <= data_next_event;
                        if (data_next_event)
                            data_pauli[cell_index] <=
                                data_pauli[cell_index] ^ 2'd3;
                    end
                    if (cell_index == DATA_COUNT-1) begin
                        cell_index <= 0;
                        engine_state <= S_SYNDROME;
                    end else begin
                        cell_index <= cell_index + 1'b1;
                    end
                end

                S_SYNDROME: begin
                    if (!noise_quiet)
                        syndrome_rng[cell_index] <= syndrome_next_random;
                    syndrome_previous[cell_index] <= syndrome_measurement;
                    syndrome_event[cell_index] <= syndrome_detection;
                    syndrome_quiet[cell_index] <= noise_quiet;
                    phi_anyon[cell_index] <=
                        phi_anyon[cell_index] ^ syndrome_detection;
                    if (cell_index == PHI_COUNT-1) begin
                        cell_index <= 0;
                        diffusion_round <= 1'b0;
                        engine_state <= S_DIFF_PREP;
                    end else begin
                        cell_index <= cell_index + 1'b1;
                    end
                end

                S_DIFF_PREP: begin
                    pending_phi1_numerator <= phi1_numerator;
                    div_dividend <= {1'b0, magnitude37(phi0_numerator)} + 12;
                    div_quotient <= 0;
                    div_remainder <= 0;
                    div_divisor <= 24;
                    div_bit <= 37;
                    div_negative <= phi0_numerator[36];
                    engine_state <= S_DIVIDE_PHI0;
                end

                S_DIVIDE_PHI0: begin
                    div_quotient <= division_quotient;
                    div_remainder <= division_remainder;
                    if (div_bit == 0) begin
                        pending_new_phi0 <= saturate_s32(completed_phi0);
                        div_dividend <=
                            {1'b0, magnitude37(pending_phi1_numerator)} + 10;
                        div_quotient <= 0;
                        div_remainder <= 0;
                        div_divisor <= 20;
                        div_bit <= 37;
                        div_negative <= pending_phi1_numerator[36];
                        engine_state <= S_DIVIDE_PHI1;
                    end else begin
                        div_bit <= div_bit - 1'b1;
                    end
                end

                S_DIVIDE_PHI1: begin
                    div_quotient <= division_quotient;
                    div_remainder <= division_remainder;
                    if (div_bit == 0) begin
                        if (!diffusion_round) begin
                            phi0_b[cell_index] <= pending_new_phi0;
                            phi1_b[cell_index] <=
                                saturate_s32(completed_quotient);
                        end else begin
                            phi0_a[cell_index] <= pending_new_phi0;
                            phi1_a[cell_index] <=
                                saturate_s32(completed_quotient);
                        end
                        if (cell_index == PHI_COUNT-1) begin
                            cell_index <= 0;
                            if (!diffusion_round) begin
                                diffusion_round <= 1'b1;
                                engine_state <= S_DIFF_PREP;
                            end else begin
                                engine_state <= S_COMPARE;
                            end
                        end else begin
                            cell_index <= cell_index + 1'b1;
                            engine_state <= S_DIFF_PREP;
                        end
                    end else begin
                        div_bit <= div_bit - 1'b1;
                    end
                end

                S_COMPARE: begin
                    phi_rng[cell_index] <= phi_next_random;
                    move_direction[cell_index] <= selected_move ?
                        selected_direction : 4'd0;
                    if (cell_index == PHI_COUNT-1) begin
                        cell_index <= 0;
                        anyon_seen <= 1'b0;
                        engine_state <= S_APPLY;
                    end else begin
                        cell_index <= cell_index + 1'b1;
                    end
                end

                S_APPLY: begin
                    phi_anyon[cell_index] <= next_anyon;
                    if (cell_index == PHI_COUNT-1) begin
                        quiescent_after_step <= noise_quiet &&
                            !(anyon_seen || next_anyon);
                        emit_phase <= EMIT_ANNOUNCE_X;
                        emit_index <= 0;
                        cell_index <= 0;
                        engine_state <= S_EMIT;
                    end else begin
                        anyon_seen <= anyon_seen || next_anyon;
                        cell_index <= cell_index + 1'b1;
                    end
                end

                S_EMIT: begin
                    if (!out_busy) begin
                        case (emit_phase)
                            EMIT_ANNOUNCE_X, EMIT_ANNOUNCE_Z: begin
                                queue_event(
                                    emit_phase == EMIT_ANNOUNCE_X ?
                                        X_ANNOUNCEMENTS_ENDPOINT :
                                        Z_ANNOUNCEMENTS_ENDPOINT,
                                    OP_ANNOUNCEMENT,
                                    step,
                                    {30'd0,
                                        syndrome_quiet[
                                            (emit_phase ==
                                                EMIT_ANNOUNCE_Z ? 9 : 0) +
                                            emit_index],
                                        syndrome_event[
                                            (emit_phase ==
                                                EMIT_ANNOUNCE_Z ? 9 : 0) +
                                            emit_index]},
                                    phi_coordinate_word(emit_index)
                                );
                                if (emit_index == 8) begin
                                    emit_index <= 0;
                                    emit_phase <= emit_phase + 1'b1;
                                end else begin
                                    emit_index <= emit_index + 1'b1;
                                end
                            end
                            EMIT_CORRECTION_X, EMIT_CORRECTION_Z: begin
                                if (move_direction[
                                        (emit_phase ==
                                            EMIT_CORRECTION_Z ? 9 : 0) +
                                        emit_index] != 0) begin
                                    queue_event(
                                        emit_phase == EMIT_CORRECTION_X ?
                                            X_DECODER_EVENTS_ENDPOINT :
                                            Z_DECODER_EVENTS_ENDPOINT,
                                        OP_CORRECTION,
                                        step,
                                        phi_coordinate_word(emit_index),
                                        move_direction[
                                            (emit_phase ==
                                                EMIT_CORRECTION_Z ? 9 : 0) +
                                            emit_index]
                                    );
                                end
                                if (emit_index == 8) begin
                                    emit_index <= 0;
                                    emit_phase <= emit_phase + 1'b1;
                                end else begin
                                    emit_index <= emit_index + 1'b1;
                                end
                            end
                            EMIT_STATUS_X, EMIT_STATUS_Z: begin
                                queue_event(
                                    emit_phase == EMIT_STATUS_X ?
                                        X_DECODER_EVENTS_ENDPOINT :
                                        Z_DECODER_EVENTS_ENDPOINT,
                                    OP_STATUS,
                                    step,
                                    phi_coordinate_word(emit_index),
                                    {30'd0,
                                        syndrome_quiet[
                                            (emit_phase ==
                                                EMIT_STATUS_Z ? 9 : 0) +
                                            emit_index],
                                        phi_anyon[
                                            (emit_phase ==
                                                EMIT_STATUS_Z ? 9 : 0) +
                                            emit_index]}
                                );
                                if (emit_index == 8) begin
                                    emit_index <= 0;
                                    if (emit_phase == EMIT_STATUS_Z)
                                        emit_phase <= EMIT_DONE;
                                    else
                                        emit_phase <= emit_phase + 1'b1;
                                end else begin
                                    emit_index <= emit_index + 1'b1;
                                end
                            end
                            default: begin
                                if (quiescent_after_step) begin
                                    engine_state <= S_WAIT_QUERY;
                                end else begin
                                    step <= step + 1'b1;
                                    cell_index <= 0;
                                    engine_state <= S_DATA;
                                end
                            end
                        endcase
                    end
                end

                S_WAIT_QUERY: begin
                    if (query_pending) begin
                        query_pending <= 1'b0;
                        emit_index <= 0;
                        engine_state <= S_REPLY;
                    end
                end

                S_REPLY: begin
                    if (!out_busy) begin
                        if (emit_index == DATA_COUNT) begin
                            engine_state <= S_WAIT_QUERY;
                        end else begin
                            if (data_selected(
                                    emit_index,
                                    query_x0, query_y0,
                                    query_x1, query_y1)) begin
                                queue_event(
                                    DATA_ENDPOINT,
                                    OP_PAULI_REPLY,
                                    query_request_id,
                                    data_coordinate_word(emit_index),
                                    {31'd0, pauli_anticommutes(
                                        data_pauli[emit_index],
                                        query_measurement)}
                                );
                            end
                            emit_index <= emit_index + 1'b1;
                        end
                    end
                end

                default: engine_state <= S_INIT;
            endcase
        end
    end

    wire _unused_tkeep = &s_axis_tkeep;
endmodule
