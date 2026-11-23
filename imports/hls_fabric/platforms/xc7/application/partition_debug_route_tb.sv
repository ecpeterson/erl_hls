`timescale 1ns/1ps

// Bounded witness for the one-endpoint debug routing boundary. The ingress
// removes exactly one route word, and the egress restores source 1/destination
// 0 without changing the monitor's payload boundaries.
module partition_debug_route_tb;
    reg clock = 0;
    reg reset = 1;
    always #5 clock = !clock;

    reg [31:0] host_data = 0;
    reg [3:0] host_keep = 4'hf;
    reg host_last = 0, host_valid = 0;
    wire host_ready;
    wire [31:0] local_in_data;
    wire [3:0] local_in_keep;
    wire local_in_last, local_in_valid;
    reg local_in_ready = 1;
    wire [15:0] local_in_source;
    wire [1:0] route_error;

    reg [31:0] local_out_data = 0;
    reg [3:0] local_out_keep = 4'hf;
    reg local_out_last = 0, local_out_valid = 0;
    wire local_out_ready;
    wire [31:0] host_out_data;
    wire [3:0] host_out_keep;
    wire host_out_last, host_out_valid;
    reg host_out_ready = 1;

    integer ingress_count = 0;
    integer egress_count = 0;
    reg [31:0] ingress_words [0:1];
    reg ingress_last [0:1];
    reg [31:0] egress_words [0:2];
    reg egress_last [0:2];

    hls_fabric_ingress #(.PORTS(1), .ENDPOINTS(16'd1)) ingress(
        .clk(clock), .reset(reset),
        .s_data(host_data), .s_keep(host_keep), .s_last(host_last),
        .s_valid(host_valid), .s_ready(host_ready),
        .m_data(local_in_data), .m_keep(local_in_keep), .m_last(local_in_last),
        .m_source(local_in_source), .m_valid(local_in_valid),
        .m_ready(local_in_ready), .route_error(route_error)
    );
    hls_fabric_egress #(.PORTS(1), .ENDPOINTS(16'd1)) egress(
        .clk(clock), .reset(reset),
        .s_data(local_out_data), .s_keep(local_out_keep), .s_last(local_out_last),
        .s_valid(local_out_valid), .s_destination(16'd0),
        .s_ready(local_out_ready),
        .m_data(host_out_data), .m_keep(host_out_keep), .m_last(host_out_last),
        .m_valid(host_out_valid), .m_ready(host_out_ready)
    );

    always @(posedge clock) begin
        if (!reset && local_in_valid && local_in_ready) begin
            ingress_words[ingress_count] <= local_in_data;
            ingress_last[ingress_count] <= local_in_last;
            ingress_count <= ingress_count + 1;
            if (local_in_keep != 4'hf || local_in_source != 16'd0)
                $fatal(1, "ingress metadata changed");
        end
        if (!reset && host_out_valid && host_out_ready) begin
            egress_words[egress_count] <= host_out_data;
            egress_last[egress_count] <= host_out_last;
            egress_count <= egress_count + 1;
            if (host_out_keep != 4'hf)
                $fatal(1, "egress keep changed");
        end
        if (!reset && route_error != 0)
            $fatal(1, "valid endpoint-1 route rejected");
    end

    task send_host;
        input [31:0] data;
        input last;
        begin
            @(negedge clock);
            host_data = data;
            host_last = last;
            host_valid = 1;
            @(posedge clock);
            while (!host_ready) @(posedge clock);
            @(negedge clock);
            host_valid = 0;
        end
    endtask

    task send_local;
        input [31:0] data;
        input last;
        begin
            @(negedge clock);
            local_out_data = data;
            local_out_last = last;
            local_out_valid = 1;
            @(posedge clock);
            while (!local_out_ready) @(posedge clock);
            @(negedge clock);
            local_out_valid = 0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clock);
        @(negedge clock);
        reset = 0;

        send_host(32'h00000001, 0);
        send_host(32'h05000001, 0);
        send_host(32'h12345678, 1);
        wait (ingress_count == 2);
        if (ingress_words[0] != 32'h05000001 || ingress_last[0] ||
            ingress_words[1] != 32'h12345678 || !ingress_last[1])
            $fatal(1, "ingress did not remove exactly one route word");

        send_local(32'h85000001, 0);
        send_local(32'h87654321, 1);
        wait (egress_count == 3);
        if (egress_words[0] != 32'h00010000 || egress_last[0] ||
            egress_words[1] != 32'h85000001 || egress_last[1] ||
            egress_words[2] != 32'h87654321 || !egress_last[2])
            $fatal(1, "egress did not restore the endpoint-1 route word");

        $display("PASS: debug endpoint 1 route removal and restoration");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "debug route test timed out ingress=%0d egress=%0d", ingress_count,
               egress_count);
    end
endmodule
