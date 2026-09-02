`timescale 1ns/1ps

module phi_memory_raw_d3_tb;
    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg [31:0] s_data = 0;
    reg s_valid = 0;
    wire s_ready;
    reg s_last = 0;

    wire [31:0] m_data;
    wire m_valid;
    reg m_ready = 0;
    wire m_last;

    reg pause_output = 0;
    integer cycle = 0;
    reg previous_stalled = 0;
    reg [31:0] stalled_data = 0;
    reg stalled_last = 0;

    integer correction_count = 0;
    integer x_correction_count = 0;
    integer z_correction_count = 0;
    integer x_empty_count = 0;
    integer z_empty_count = 0;
    reg [8:0] x_empty_seen = 0;
    reg [8:0] z_empty_seen = 0;
    integer reply_count = 0;
    reg [17:0] reply_seen = 0;
    // Compact regression witness over every correction field in emission order.
    reg [63:0] correction_hash = 64'hcbf29ce484222325;

    phi_memory_raw_d3 dut (
        .aclk(clk),
        .aresetn(resetn),
        .s_axis_tdata(s_data),
        .s_axis_tkeep(4'hf),
        .s_axis_tvalid(s_valid),
        .s_axis_tready(s_ready),
        .s_axis_tlast(s_last),
        .m_axis_tdata(m_data),
        .m_axis_tkeep(),
        .m_axis_tvalid(m_valid),
        .m_axis_tready(m_ready),
        .m_axis_tlast(m_last)
    );

    always #5 clk = ~clk;

    always @(negedge clk) begin
        if (!resetn) begin
            cycle <= 0;
            m_ready <= 0;
        end else begin
            cycle <= cycle + 1;
            m_ready <= !pause_output && (cycle % 7 != 3);
        end
    end

    // AXIS payload and TLAST must remain stable under backpressure.
    always @(posedge clk) begin
        if (resetn && previous_stalled) begin
            if (!m_valid || m_data !== stalled_data || m_last !== stalled_last)
                $fatal(1, "output changed while stalled");
        end
        previous_stalled <= resetn && m_valid && !m_ready;
        if (m_valid && !m_ready) begin
            stalled_data <= m_data;
            stalled_last <= m_last;
        end
    end

    task automatic send_word(input [31:0] word, input last);
        begin
            @(negedge clk);
            s_data = word;
            s_last = last;
            s_valid = 1;
            do @(posedge clk); while (!s_ready);
            @(negedge clk);
            s_valid = 0;
            s_last = 0;
            s_data = 0;
        end
    endtask

    task automatic send_cutoff;
        begin
            send_word(32'h00000001, 0);
            send_word(32'h0f010003, 0);
            send_word(32'h00000000, 0);
            send_word(32'h00050002, 0);
            send_word(32'd16, 1);
        end
    endtask

    task automatic send_update(
        input [15:0] x,
        input [15:0] y,
        input [1:0] pauli
    );
        reg [31:0] coordinate;
        begin
            coordinate = {y, x};
            pause_output = 1;
            send_word(32'h00000001, 0);
            send_word(32'h10010003, 0);
            send_word(coordinate, 0);
            send_word(coordinate, 0);
            send_word({30'd0, pauli}, 1);
            @(negedge clk);
            pause_output = 0;
        end
    endtask

    task automatic send_query;
        begin
            pause_output = 1;
            send_word(32'h00000001, 0);
            send_word(32'h0d010004, 0);
            send_word(32'h00000000, 0);
            send_word(32'h00050002, 0);
            send_word(32'h00504849, 0);
            send_word(32'd1, 1);
            @(negedge clk);
            pause_output = 0;
        end
    endtask

    task automatic receive_word(output reg [31:0] word, output reg last);
        begin : wait_for_word
            forever begin
                @(posedge clk);
                if (m_valid && m_ready) begin
                    word = m_data;
                    last = m_last;
                    disable wait_for_word;
                end
            end
        end
    endtask

    task automatic receive_packet(
        output reg [15:0] source,
        output reg [7:0] op,
        output reg [31:0] payload0,
        output reg [31:0] payload1,
        output reg [31:0] payload2
    );
        reg [31:0] word;
        reg last;
        integer n;
        begin
            receive_word(word, last);
            if (last || word[15:0] != 0)
                $fatal(1, "invalid route word %08x last=%d", word, last);
            source = word[31:16];
            receive_word(word, last);
            if (last || word[23:0] != 24'h010003)
                $fatal(1, "invalid event header %08x last=%d", word, last);
            op = word[31:24];
            receive_word(payload0, last);
            if (last) $fatal(1, "early TLAST on payload 0");
            receive_word(payload1, last);
            if (last) $fatal(1, "early TLAST on payload 1");
            receive_word(payload2, last);
            if (!last) $fatal(1, "missing final TLAST");
        end
    endtask

    function automatic [31:0] wrap3(input [31:0] value);
        begin
            wrap3 = value >= 3 ? value - 3 : value;
        end
    endfunction

    function automatic [31:0] wrap6_signed(input integer value);
        begin
            if (value < 0)
                wrap6_signed = value + 6;
            else if (value >= 6)
                wrap6_signed = value - 6;
            else
                wrap6_signed = value;
        end
    endfunction

    task automatic apply_correction(
        input [15:0] source,
        input [31:0] coordinate,
        input [31:0] direction
    );
        reg [31:0] x;
        reg [31:0] y;
        reg [31:0] data_x;
        reg [31:0] data_y;
        reg [1:0] pauli;
        begin
            x = coordinate[15:0];
            y = coordinate[31:16];
            if (source == 4) begin
                pauli = 1;
                case (direction)
                    1: begin data_x = x; data_y = wrap6_signed(2*y-1); end
                    2: begin data_x = wrap3(x+1); data_y = 2*y; end
                    4: begin data_x = x; data_y = 2*y; end
                    8: begin data_x = x; data_y = 2*y+1; end
                    default: $fatal(1, "invalid X direction %d", direction);
                endcase
            end else begin
                pauli = 2;
                case (direction)
                    1: begin data_x = wrap3(x+1); data_y = 2*y; end
                    2: begin data_x = wrap3(x+1); data_y = 2*y+1; end
                    4: begin data_x = x; data_y = 2*y+1; end
                    8: begin
                        data_x = wrap3(x+1);
                        data_y = wrap6_signed(2*y+2);
                    end
                    default: $fatal(1, "invalid Z direction %d", direction);
                endcase
            end
            send_update(data_x[15:0], data_y[15:0], pauli);
        end
    endtask

    function automatic expected_anticommutation(
        input [15:0] x,
        input [15:0] y
    );
        begin
            expected_anticommutation =
                (x == 0 && (y == 2 || y == 3)) ||
                (x == 1 && y == 3) ||
                (x == 2 && (y == 0 || y == 1 || y == 4));
        end
    endfunction

    function automatic [63:0] hash_word(
        input [63:0] hash,
        input [31:0] word
    );
        begin
            hash_word = (hash ^ {32'd0, word}) * 64'h00000100000001b3;
        end
    endfunction

    function automatic [63:0] hash_correction(
        input [63:0] hash,
        input [15:0] source,
        input [31:0] step,
        input [31:0] coordinate,
        input [31:0] direction
    );
        reg [63:0] updated;
        begin
            updated = hash_word(hash, {16'd0, source});
            updated = hash_word(updated, step);
            updated = hash_word(updated, coordinate);
            hash_correction = hash_word(updated, direction);
        end
    endfunction

    initial begin : run
        reg [15:0] source;
        reg [7:0] op;
        reg [31:0] payload0;
        reg [31:0] payload1;
        reg [31:0] payload2;
        integer reply_index;
        integer status_index;

        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1;
        send_cutoff();

        while (x_empty_count < 9 || z_empty_count < 9) begin
            receive_packet(source, op, payload0, payload1, payload2);
            if (op == 11) begin
                correction_count = correction_count + 1;
                if (source == 4)
                    x_correction_count = x_correction_count + 1;
                else if (source == 6)
                    z_correction_count = z_correction_count + 1;
                else
                    $fatal(1, "correction from endpoint %d", source);
                correction_hash = hash_correction(
                    correction_hash, source, payload0, payload1, payload2);
                apply_correction(source, payload1, payload2);
            end else if (op == 17 && payload0 == 21 && payload2 == 2) begin
                if (payload1[15:0] >= 3 || payload1[31:16] >= 3)
                    $fatal(1, "invalid empty-status coordinate %08x",
                        payload1);
                status_index = payload1[15:0] * 3 + payload1[31:16];
                if (source == 4) begin
                    if (x_empty_seen[status_index])
                        $fatal(1, "duplicate X empty status %08x", payload1);
                    x_empty_seen[status_index] = 1'b1;
                    x_empty_count = x_empty_count + 1;
                end else if (source == 6) begin
                    if (z_empty_seen[status_index])
                        $fatal(1, "duplicate Z empty status %08x", payload1);
                    z_empty_seen[status_index] = 1'b1;
                    z_empty_count = z_empty_count + 1;
                end else begin
                    $fatal(1, "status from endpoint %d", source);
                end
            end else if (op != 10 && op != 17) begin
                $fatal(1, "unexpected event op %d", op);
            end
        end

        if (correction_count != 84 ||
            x_correction_count != 45 || z_correction_count != 39)
            $fatal(1, "wrong correction counts total=%d x=%d z=%d",
                correction_count, x_correction_count, z_correction_count);
        if (correction_hash != 64'h03fd2ddce5182ca9)
            $fatal(1, "wrong ordered correction witness %016x",
                correction_hash);
        if (x_empty_seen != 9'h1ff || z_empty_seen != 9'h1ff)
            $fatal(1, "incomplete empty status sets x=%03x z=%03x",
                x_empty_seen, z_empty_seen);

        send_query();
        while (reply_count < 18) begin
            receive_packet(source, op, payload0, payload1, payload2);
            if (source != 2 || op != 14 || payload0 != 32'h00504849)
                $fatal(1, "invalid reply route/op/id");
            reply_index = payload1[15:0] * 6 + payload1[31:16];
            if (reply_index < 0 || reply_index >= 18 ||
                reply_seen[reply_index])
                $fatal(1, "duplicate or invalid reply coordinate");
            if (payload2 != expected_anticommutation(
                    payload1[15:0], payload1[31:16]))
                $fatal(1, "wrong reply at x=%d y=%d: %d",
                    payload1[15:0], payload1[31:16], payload2);
            reply_seen[reply_index] = 1;
            reply_count = reply_count + 1;
        end

        if (reply_seen != 18'h3ffff)
            $fatal(1, "incomplete measurement replies");
        $display("phi_memory_raw_d3_tb: PASS cycles=%0d corrections=%0d hash=%016x",
            cycle, correction_count, correction_hash);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "timeout");
    end
endmodule
