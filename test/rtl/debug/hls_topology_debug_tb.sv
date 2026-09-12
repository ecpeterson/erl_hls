`timescale 1ns/1ps
module hls_topology_debug_tb;
    localparam integer RESOURCES = 4;
    localparam [255:0] HASH = 256'hffeeddccbbaa998877665544332211000123456789abcdef1122334455667788;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    reg [RESOURCES*32-1:0] probe_values = 0;
    reg [31:0] s_data = 0;
    reg [3:0] s_keep = 15;
    reg s_last = 0, s_valid = 0;
    wire s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_last, m_valid;
    reg m_ready = 0;
    reg hold_reply = 0;
    integer cycle = 0, consumed = 0, written = 0;
    reg [36:0] received [0:4095];
    reg [RESOURCES*32-1:0] expected [0:19999];
    reg stalled = 0;
    reg [36:0] held;
    reg [31:0] reply [0:254];
    reg [7:0] txid = 0;
    integer length;

    wire [31:0] request_data, response_data;
    wire [3:0] request_keep, response_keep;
    wire request_last, request_valid, request_ready;
    wire response_last, response_valid, response_ready;
    hls_debug_route route (.*);
    hls_topology_debug #(.RESOURCES(RESOURCES), .CHANNELS(2), .ACTORS(1), .FINGERPRINT(HASH)) dut (
        .clk(clk), .reset(reset), .probe_values(probe_values),
        .s_data(request_data), .s_keep(request_keep), .s_last(request_last),
        .s_valid(request_valid), .s_ready(request_ready),
        .m_data(response_data), .m_keep(response_keep), .m_last(response_last),
        .m_valid(response_valid), .m_ready(response_ready));
    always @(negedge clk) probe_values = {32'(cycle*4+3),32'(cycle*4+2),32'(cycle*4+1),32'(cycle*4)};

    always @(negedge clk) m_ready = !reset && !hold_reply && cycle % 7 >= 2;
    always @(posedge clk) begin
        if (reset) begin
            cycle = 0;
            stalled = 0;
        end else begin
            if (cycle >= 19999) $fatal(1, "topology debug timeout");
            expected[cycle] = probe_values;
            cycle = cycle + 1;
            if (stalled && (m_valid !== 1 || {m_keep,m_last,m_data} !== held))
                $fatal(1, "reply changed under backpressure");
            held = {m_keep,m_last,m_data};
            stalled = m_valid && !m_ready;
            if (m_valid && m_ready) begin
                if ((^{m_keep,m_last,m_data}) === 1'bx) $fatal(1, "unknown reply");
                received[written] = {m_keep,m_last,m_data};
                written = written + 1;
            end
        end
    end

    task automatic beat(input [31:0] word, input last, input [3:0] keep);
        begin
            @(negedge clk); s_data = word; s_last = last; s_keep = keep; s_valid = 1;
            @(posedge clk); while (!s_ready) @(posedge clk);
            @(negedge clk); s_valid = 0;
        end
    endtask
    task automatic receive_beat(input last, output [31:0] word);
        begin
            @(negedge clk); while (consumed == written) @(negedge clk);
            if (received[consumed][36:32] !== {4'hf,last}) $fatal(1, "reply framing");
            word = received[consumed][31:0]; consumed = consumed + 1;
        end
    endtask
    task automatic response(input [7:0] tag, input integer count);
        reg [31:0] header, word;
        integer i;
        begin
            receive_beat(0, header);
            if (header !== 32'h00020055) $fatal(1,"wrong reply route");
            receive_beat(0, header);
            if (header !== {tag,8'd0,txid,count[7:0]})
                $fatal(1, "expected reply %h/%0d/%0d, got %h",tag,txid,count,header);
            length = count;
            for (i=0; i<count; i=i+1) begin
                receive_beat(i == count-1, word);
                reply[i] = word;
            end
            txid = txid + 1;
        end
    endtask
    task automatic route_header;
        beat(32'h00550002,0,15);
    endtask
    task automatic empty(input [7:0] tag);
        begin route_header(); beat({tag,8'd0,txid,8'd0}, 1, 15); end
    endtask
    task automatic query(input [31:0] id, input [7:0] tag);
        begin
            route_header();
            beat({8'h11,8'd0,txid,8'd1},0,15);
            beat(id,1,15);
            response(tag, tag == 8'h91 ? 4 : 1);
            if (tag == 8'h91) begin
                if (reply[0] != id || reply[2] != 0) $fatal(1,"query identity/clock");
                if (reply[3] !== expected[reply[1]][id*32 +: 32])
                    $fatal(1,"query was not sampled atomically at its reported edge");
            end
        end
    endtask
    task automatic expect_error(input [31:0] code);
        begin response(8'hff,1); if (reply[0] != code) $fatal(1,"error code"); end
    endtask

    integer i, saved_cycle;
    initial begin
        repeat (5) @(negedge clk); reset = 0;
        empty(8'h10); response(8'h90,13);
        if (reply[0] != 2 || reply[1] != RESOURCES || reply[2] != 2 || reply[3] != 1 || reply[4] != 1)
            $fatal(1, "manifest geometry");
        for (i=0;i<8;i=i+1) if (reply[5+i] !== HASH[i*32+:32]) $fatal(1,"manifest hash");
        for (i=0;i<RESOURCES;i=i+1) query(i,8'h91);
        query(RESOURCES,8'hff); if(reply[0] != 2) $fatal(1,"invalid query ID");
        query(32'hffffffff,8'hff); if(reply[0] != 2) $fatal(1,"overflow query ID");
        // Malformed long request must drain to real TLAST, keeping the txid.
        route_header(); beat({8'h11,8'd0,txid,8'd1},0,15);
        for(i=0;i<300;i=i+1) beat(32'h1000bb00,0,15);
        beat(0,1,15); expect_error(1);
        route_header(); beat({8'h11,8'd0,txid,8'd1},1,15); expect_error(1);
        route_header(); beat({8'h10,8'd1,txid,8'd0},1,15); expect_error(1);
        route_header(); beat({8'h10,8'd0,txid,8'd0},1,7); expect_error(1);
        route_header(); beat({8'h11,8'd0,txid,8'd1},0,15); beat(0,1,7); expect_error(1);
        empty(8'h12); expect_error(1);
        // A wrong route or malformed route is dropped as one whole frame.
        beat(32'h00550003,0,15); beat(32'h1000cc00,1,15);
        beat(32'h00550002,0,7); beat(32'h1000cc00,1,15);
        query(0,8'h91);
        hold_reply = 1;
        route_header(); beat({8'h11,8'd0,txid,8'd1},0,15); beat(2,1,15);
        saved_cycle = cycle;
        repeat (40) @(negedge clk);
        if (cycle < saved_cycle+40 || s_ready) $fatal(1,"reply stall ownership");
        hold_reply = 0; response(8'h91,4);
        if(reply[3] !== expected[reply[1]][64+:32]) $fatal(1,"stalled reply was resampled");
        // Reset abandons a partial request and permits a fresh routed packet.
        route_header(); beat({8'h11,8'd0,txid,8'd1},0,15);
        reset = 1; repeat (5) @(negedge clk); reset = 0;
        query(3,8'h91);
        if (consumed != written) $fatal(1,"unsolicited response");
        $display("PASS: routed topology queries, edge-coherent replies, bad frames, reset and independent debug backpressure");
        $finish;
    end
endmodule
