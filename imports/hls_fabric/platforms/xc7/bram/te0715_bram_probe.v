// Self-test the inferred wide simple-dual-port RAM shapes used by the
// repetition scheduler and debug trace. Results leave the PL through the PS
// register page, so the tested memories are not also the observation path.
module bram_shape_test #(
    parameter integer WIDTH = 1,
    parameter integer ADDRESS_WIDTH = 1,
    parameter integer BANK = 0
) (
    input  wire        clock,
    input  wire        reset_n,
    output reg         done,
    output reg         failed,
    output reg  [15:0] mismatch_count,
    output reg  [2:0]  first_pattern,
    output reg  [4:0]  first_address,
    output reg  [15:0] first_lane_mask,
    output reg  [31:0] first_digest,
    output reg  [31:0] first_actual,
    output reg  [31:0] first_expected
);
    localparam integer DEPTH = 1 << ADDRESS_WIDTH;
    localparam [3:0] INITIAL_REQUEST = 0, INITIAL_CHECK = 1,
                     WRITE_ROWS = 2, REQUEST_READ = 3, CHECK_READ = 4,
                     COLLISION_REQUEST = 5, COLLISION_CHECK = 6,
                     VERIFY_REQUEST = 7, VERIFY_CHECK = 8, FINISHED = 9;

    (* ram_style = "block" *) reg [WIDTH-1:0] memory [0:DEPTH-1];
    integer initial_address;
    initial begin
        for (initial_address = 0; initial_address < DEPTH;
             initial_address = initial_address + 1)
            memory[initial_address] = 0;
    end
    reg [WIDTH-1:0] read_data;
    reg [WIDTH-1:0] expected_data;
    reg [3:0] state;
    reg [2:0] pattern;
    reg [ADDRESS_WIDTH-1:0] address;
    reg [ADDRESS_WIDTH-1:0] pending_address;
    wire write_enable = state == WRITE_ROWS || state == COLLISION_REQUEST;
    wire read_enable = state == INITIAL_REQUEST || state == REQUEST_READ ||
                       state == COLLISION_REQUEST || state == VERIFY_REQUEST;
    wire [WIDTH-1:0] write_data = state == COLLISION_REQUEST ?
        test_data(0, address) : test_data(pattern, address);
    wire check_cycle = state == INITIAL_CHECK || state == CHECK_READ ||
                       state == COLLISION_CHECK || state == VERIFY_CHECK;
    wire [2:0] check_pattern = state == INITIAL_CHECK ? 5 :
                               state == COLLISION_CHECK ? 6 :
                               state == VERIFY_CHECK ? 7 : pattern;

    // Each row combines uniform, bit-alternating, lane-distinct and walking
    // patterns. Every 36-bit logical lane differs in the latter two cases.
    function automatic [WIDTH-1:0] test_data;
        input [2:0] selected_pattern;
        input [ADDRESS_WIDTH-1:0] selected_address;
        integer bit_index;
        integer lane;
        integer position;
        begin
            for (bit_index = 0; bit_index < WIDTH; bit_index = bit_index + 1) begin
                lane = bit_index / 36;
                position = bit_index % 36;
                case (selected_pattern)
                    0: test_data[bit_index] = 1'b0;
                    1: test_data[bit_index] = 1'b1;
                    2: test_data[bit_index] =
                        (bit_index % 2) ^ selected_address[bit_index % ADDRESS_WIDTH] ^
                        ((lane + BANK) % 2);
                    3: test_data[bit_index] =
                        (position == ((3 * lane + 5 * BANK) % 36)) ^
                        selected_address[(bit_index + lane) % ADDRESS_WIDTH];
                    default: test_data[bit_index] =
                        ((32'h9e3779b9 >> (bit_index % 32)) & 1) ^
                        selected_address[(bit_index + 2 * lane + BANK) % ADDRESS_WIDTH] ^
                        ((lane >> (bit_index % 3)) & 1);
                endcase
            end
        end
    endfunction

    // Report a stable low word even when this generic module is parsed before
    // WIDTH is specialized by hierarchy elaboration.
    function automatic [31:0] low_word;
        input [WIDTH-1:0] value;
        integer low_bit;
        begin
            low_word = 0;
            for (low_bit = 0; low_bit < 32; low_bit = low_bit + 1)
                if (low_bit < WIDTH)
                    low_word[low_bit] = value[low_bit];
        end
    endfunction

    wire [WIDTH-1:0] difference = read_data ^ expected_data;
    reg [15:0] lane_mask;
    reg [31:0] difference_digest;
    integer compare_bit;
    always @* begin
        lane_mask = 0;
        difference_digest = 0;
        for (compare_bit = 0; compare_bit < WIDTH; compare_bit = compare_bit + 1) begin
            lane_mask[compare_bit / 36] =
                lane_mask[compare_bit / 36] | difference[compare_bit];
            difference_digest[compare_bit % 32] =
                difference_digest[compare_bit % 32] ^ difference[compare_bit];
        end
    end

    // These two processes deliberately match hls_1r1w_ram's inferred
    // read-before-write, synchronous-read contract.
    always @(posedge clock) begin
        if (write_enable)
            memory[address] <= write_data;
    end

    always @(posedge clock) begin
        if (read_enable)
            read_data <= memory[address];
    end

    always @(posedge clock) begin
        if (!reset_n) begin
            done <= 0;
            failed <= 0;
            mismatch_count <= 0;
            first_pattern <= 0;
            first_address <= 0;
            first_lane_mask <= 0;
            first_digest <= 0;
            first_actual <= 0;
            first_expected <= 0;
            expected_data <= 0;
            pending_address <= 0;
            pattern <= 0;
            address <= 0;
            state <= INITIAL_REQUEST;
        end else begin
            if (check_cycle && |difference) begin
                failed <= 1;
                if (mismatch_count == 0) begin
                    first_pattern <= check_pattern;
                    first_address <= pending_address;
                    first_lane_mask <= lane_mask;
                    first_digest <= difference_digest;
                    first_actual <= low_word(read_data);
                    first_expected <= low_word(expected_data);
                end
                if (mismatch_count != 16'hffff)
                    mismatch_count <= mismatch_count + 1'b1;
            end
            case (state)
                INITIAL_REQUEST: begin
                    pending_address <= address;
                    expected_data <= 0;
                    state <= INITIAL_CHECK;
                end
                INITIAL_CHECK: begin
                    if (pending_address == DEPTH - 1) begin
                        address <= 0;
                        state <= WRITE_ROWS;
                    end else begin
                        address <= pending_address + 1'b1;
                        state <= INITIAL_REQUEST;
                    end
                end
                WRITE_ROWS: begin
                    if (address == DEPTH - 1) begin
                        address <= 0;
                        state <= REQUEST_READ;
                    end else address <= address + 1'b1;
                end
                REQUEST_READ: begin
                    pending_address <= address;
                    expected_data <= test_data(pattern, address);
                    state <= CHECK_READ;
                end
                CHECK_READ: begin
                    if (pending_address == DEPTH - 1) begin
                        address <= 0;
                        if (pattern == 4) begin
                            state <= COLLISION_REQUEST;
                        end else begin
                            pattern <= pattern + 1'b1;
                            state <= WRITE_ROWS;
                        end
                    end else begin
                        address <= pending_address + 1'b1;
                        state <= REQUEST_READ;
                    end
                end
                COLLISION_REQUEST: begin
                    pending_address <= address;
                    expected_data <= test_data(4, address);
                    state <= COLLISION_CHECK;
                end
                COLLISION_CHECK: state <= VERIFY_REQUEST;
                VERIFY_REQUEST: begin
                    expected_data <= test_data(0, address);
                    state <= VERIFY_CHECK;
                end
                VERIFY_CHECK: begin
                    if (pending_address == DEPTH - 1) begin
                        done <= 1;
                        state <= FINISHED;
                    end else begin
                        address <= pending_address + 1'b1;
                        state <= COLLISION_REQUEST;
                    end
                end
                default: state <= FINISHED;
            endcase
        end
    end
endmodule

// Run all production RAM shapes concurrently and page their first failures.
module bram_probe_core (
    input  wire         clock,
    input  wire         reset_n,
    input  wire [31:0]  control,
    output reg  [127:0] status
);
    wire [3:0] done;
    wire [3:0] failed;
    wire [63:0] mismatch_count;
    wire [11:0] first_pattern;
    wire [19:0] first_address;
    wire [63:0] first_lane_mask;
    wire [127:0] first_digest;
    wire [127:0] first_actual;
    wire [127:0] first_expected;

    bram_shape_test #(.WIDTH(387), .ADDRESS_WIDTH(2), .BANK(0)) state_a (
        .clock(clock), .reset_n(reset_n), .done(done[0]), .failed(failed[0]),
        .mismatch_count(mismatch_count[15:0]), .first_pattern(first_pattern[2:0]),
        .first_address(first_address[4:0]), .first_lane_mask(first_lane_mask[15:0]),
        .first_digest(first_digest[31:0]), .first_actual(first_actual[31:0]),
        .first_expected(first_expected[31:0]));
    bram_shape_test #(.WIDTH(537), .ADDRESS_WIDTH(2), .BANK(1)) state_b (
        .clock(clock), .reset_n(reset_n), .done(done[1]), .failed(failed[1]),
        .mismatch_count(mismatch_count[31:16]), .first_pattern(first_pattern[5:3]),
        .first_address(first_address[9:5]), .first_lane_mask(first_lane_mask[31:16]),
        .first_digest(first_digest[63:32]), .first_actual(first_actual[63:32]),
        .first_expected(first_expected[63:32]));
    bram_shape_test #(.WIDTH(128), .ADDRESS_WIDTH(4), .BANK(2)) mailbox (
        .clock(clock), .reset_n(reset_n), .done(done[2]), .failed(failed[2]),
        .mismatch_count(mismatch_count[47:32]), .first_pattern(first_pattern[8:6]),
        .first_address(first_address[14:10]), .first_lane_mask(first_lane_mask[47:32]),
        .first_digest(first_digest[95:64]), .first_actual(first_actual[95:64]),
        .first_expected(first_expected[95:64]));
    bram_shape_test #(.WIDTH(192), .ADDRESS_WIDTH(5), .BANK(3)) trace (
        .clock(clock), .reset_n(reset_n), .done(done[3]), .failed(failed[3]),
        .mismatch_count(mismatch_count[63:48]), .first_pattern(first_pattern[11:9]),
        .first_address(first_address[19:15]), .first_lane_mask(first_lane_mask[63:48]),
        .first_digest(first_digest[127:96]), .first_actual(first_actual[127:96]),
        .first_expected(first_expected[127:96]));

    reg selected_done;
    reg selected_failed;
    reg [15:0] selected_count;
    reg [2:0] selected_pattern;
    reg [4:0] selected_address;
    reg [15:0] selected_lane_mask;
    reg [31:0] selected_digest;
    reg [31:0] selected_actual;
    reg [31:0] selected_expected;
    reg [1:0] bank;
    always @* begin
        bank = control[1:0];
        selected_done = done[bank];
        selected_failed = failed[bank];
        selected_count = mismatch_count[16*bank +: 16];
        selected_pattern = first_pattern[3*bank +: 3];
        selected_address = first_address[5*bank +: 5];
        selected_lane_mask = first_lane_mask[16*bank +: 16];
        selected_digest = first_digest[32*bank +: 32];
        selected_actual = first_actual[32*bank +: 32];
        selected_expected = first_expected[32*bank +: 32];
        status[31:0] = {16'h4252, 8'h01, 4'h4, |failed, &done,
                        selected_failed, selected_done};
        status[63:32] = {selected_count, 2'b0, bank, selected_pattern,
                         selected_address, 4'b0};
        if (control[4]) begin
            status[95:64] = selected_actual;
            status[127:96] = selected_expected;
        end else begin
            status[95:64] = {16'b0, selected_lane_mask};
            status[127:96] = selected_digest;
        end
    end
endmodule

// No PL package pins are used. FCLK0, reset and GP0 are configured by the PS.
module te0715_bram_probe_top;
    wire clock;
    wire reset_n;
    wire [31:0] control;
    wire [127:0] status;
    zynq_probe_ps #(.EXTENDED(1), .IDENTITY(32'h4252414d), .ABI(1)) processor_shell (
        .status(status), .control(control), .clock(clock), .reset_n(reset_n));
    bram_probe_core probe(.clock(clock), .reset_n(reset_n),
                          .control(control), .status(status));
endmodule
