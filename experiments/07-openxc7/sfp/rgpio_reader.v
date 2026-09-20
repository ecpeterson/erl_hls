`default_nettype none

// Read Trenz's 32-bit RGPIO slave continuously without activating its controls.
// Writes only an echoed challenge byte; bits 31:28 stay F (activation is A).
// All internal logic uses clock. QUARTER_CYCLES >= 4 allows the return signal
// two synchronizer stages plus settling before sampling. At 25 MHz, 25 gives
// a 250-kHz wire clock. snapshot updates atomically with a one-cycle valid pulse.
module rgpio_reader #(parameter QUARTER_CYCLES = 25)(
    input wire clock, reset_n,
    input wire [7:0] challenge,
    input wire rx,
    output reg tx, serial_clock,
    output reg [31:0] snapshot,
    output reg valid
);
    localparam DIV_BITS = $clog2(QUARTER_CYCLES);
    reg [DIV_BITS-1:0] divider;
    reg [1:0] phase;
    reg [4:0] bit_index;
    reg [1:0] priming;
    reg [31:0] transmit, receive;
    (* ASYNC_REG = "TRUE" *) reg rx_meta, rx_sync;
    always @(posedge clock) begin
        if (!reset_n) begin
            divider <= 0;
            phase <= 0;
            bit_index <= 0;
            priming <= 2;
            transmit <= 32'hf0000000;
            receive <= 0;
            snapshot <= 0;
            valid <= 0;
            serial_clock <= 0;
            tx <= 0;
            rx_meta <= 0;
            rx_sync <= 0;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            valid <= 0;
            if (divider == QUARTER_CYCLES-1) begin
                divider <= 0;
                phase <= phase + 1'b1;
                case (phase)
                    // Rising edges carry data; falling edges carry a latch flag.
                    0: tx <= transmit[31-bit_index];
                    1: serial_clock <= 1;
                    2: begin
                        tx <= bit_index == 31;
                        receive <= {receive[30:0], rx_sync};
                        // The vendor slave loads its reply on the falling edge
                        // AFTER the latch flag, one bit into the following frame.
                        if (bit_index == 0) begin
                            if (priming != 0) priming <= priming - 1'b1;
                            else begin
                                snapshot <= {receive[30:0], rx_sync};
                                valid <= 1;
                            end
                        end
                    end
                    3: begin
                        serial_clock <= 0;
                        bit_index <= bit_index + 1'b1;
                        if (bit_index == 31) transmit <= {24'hf00000, challenge};
                    end
                endcase
            end else divider <= divider + 1'b1;
        end
    end
endmodule

// A status page in the existing GP0 probe's FCLK domain. Software can challenge
// the echo using control[7:0]. Frames counts wire transactions, not good replies;
// software must verify marker A and a changed echo before trusting status.
module sfp_status # (parameter QUARTER_CYCLES = 25)(
    input wire clock, reset_n, rx,
    input wire [31:0] control,
    output wire tx, serial_clock,
    output wire [127:0] status
);
    wire [31:0] snapshot;
    wire valid;
    localparam [31:0] SERIAL_DIVISOR = QUARTER_CYCLES;
    reg [31:0] frames;
    rgpio_reader #(.QUARTER_CYCLES(QUARTER_CYCLES)) reader(
        .clock(clock), .reset_n(reset_n), .challenge(control[7:0]), .rx(rx),
        .tx(tx), .serial_clock(serial_clock), .snapshot(snapshot), .valid(valid));
    always @(posedge clock) begin
        if (!reset_n) frames <= 0;
        else if (valid) frames <= frames + 1'b1;
    end
    // 0x14 raw word, 0x18 transaction count, 0x1c quarter-cycle divisor, 0x20 zero.
    assign status = {32'b0, SERIAL_DIVISOR, frames, snapshot};
endmodule

`default_nettype wire
