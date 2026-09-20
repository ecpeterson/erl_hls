`timescale 1ns/1ps

// The reference is GHDL's translation of Trenz's released slave, not a second
// implementation of our reader. Delay its output to exercise sampling margins.
module sfp_status_tb;
    reg clock = 0, reset_n = 0;
    always #5 clock = ~clock;
    reg [31:0] control = 0;
    wire [127:0] status;
    wire tx, serial_clock, slave_tx, scl, sda_release;
    wire [1:0] select_bus;
    reg sda_in = 1;
    reg [1:0] fault = 0;
    wire delayed_rx;
    assign #7 delayed_rx = fault == 1 ? 1'b0 : fault == 2 ? 1'b1 : slave_tx;
`ifdef MAPPED
    sfp_status_mapped dut(
`else
    sfp_status #(.QUARTER_CYCLES(4)) dut(
`endif
        .clock(clock), .reset_n(reset_n), .control(control), .rx(delayed_rx),
        .tx(tx), .serial_clock(serial_clock), .status(status),
        .i2c_sda_in(sda_in), .i2c_scl(scl), .i2c_sda_release(sda_release),
        .i2c_select(select_bus));

    wire [31:0] received;
    reg [2:0] flags = 0;
    wire [31:0] reply = {4'ha, 8'b0, flags, 9'b0, received[7:0]};
    ddsrpi_slave vendor(.RX_CLK(serial_clock), .RX_DATA(tx), .TX_DATA(slave_tx),
        .gpio_out(received), .gpio_in(reply), .resetn(1'b1));
    integer activation_errors = 0;
    always @(received) begin
        if (received[31:28] === 4'ha) begin
            activation_errors = activation_errors + 1;
            $fatal(1, "carrier controls activated");
        end
    end

    // Poll the atomic word until a whole fresh reply arrives; bound wire progress.
    task automatic expect_word(input [31:0] expected);
        integer elapsed;
        begin
            elapsed = 0;
            while (status[31:0] !== expected && elapsed < 3500) begin
                @(negedge clock);
                elapsed = elapsed + 1;
            end
            if (status[31:0] !== expected)
                $fatal(1, "reply %08x, expected %08x", status[31:0], expected);
        end
    endtask

    integer i;
    reg [31:0] before_frames;
    initial begin
        repeat (4) @(negedge clock);
        reset_n = 1;
        // Exercise every GPIO command and unrelated bit; no non-SFP selection.
        for (i = 0; i < 8; i = i + 1) begin
            control = 32'hfffffc75 | ((i & 3) << 8);
            sda_in = (i >> 2) & 1;
            repeat (4) @(negedge clock);
            if (scl !== !control[8] || sda_release !== !control[9] || select_bus !== 0)
                $fatal(1, "I2C command routing");
            if (status[127:96] !== {31'b0, sda_in}) $fatal(1, "SDA readback");
        end
        reset_n = 0;
        repeat (3) @(negedge clock);
        if (!scl || !sda_release || status[127:96] !== 1) $fatal(1, "I2C reset idle");
        reset_n = 1;
        for (i = 0; i < 8; i = i + 1) begin
            flags = i;
            // Every writable bit is exercised, including a putative activation
            // nibble. Only the low challenge byte can reach carrier payloads.
            control = 32'hffffff00 | (8'h5a ^ i);
            expect_word(32'ha0000000 | (i << 17) | (8'h5a ^ i));
        end
        before_frames = status[63:32];
        repeat (600) @(negedge clock);
        if (status[63:32] == before_frames) $fatal(1, "frozen transaction counter");
        fault = 1;
        expect_word(0);
        fault = 2;
        expect_word(32'hffffffff);
        fault = 0;
        expect_word(32'ha00e005d);
        // Reset partway through each quarter phase. The slave is deliberately
        // left running: the next latch flags must repair framing on their own.
        for (i = 0; i < 16; i = i + 1) begin
            repeat (17+i) @(negedge clock);
            reset_n = 0;
            repeat (3) @(negedge clock);
            if (status[63:0] !== 0) $fatal(1, "status not cleared by reset");
            control = i;
            reset_n = 1;
            expect_word(32'ha00e0000 | i);
        end
        if (activation_errors) $fatal(1, "unexpected activation");
        $display("PASS: Trenz slave interoperability, status flags, echo, stuck wire, reset reframing; no control activation");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "SFP probe timeout");
    end
endmodule
