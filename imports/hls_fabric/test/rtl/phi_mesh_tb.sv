`timescale 1ns/1ps
`include "phi_mesh_config.vh"

// Complete application graphs, independent device clocks and physical peer FIFOs.
// The host calls the ordinary Erlang reducer without advancing simulated time.
module phi_bridge_tb;
    localparam DEVICES = `MESH_DEVICES, PEERS = 4, STREAMS = 2*DEVICES;
    reg clk = 0, reset = 0, resetn = 0;
    always #5 clk = !clk;
    reg [DEVICES-1:0] device_clk = 0;
    wire [DEVICES-1:0] device_reset;
    integer half_period = 4, stalls = 0;
    initial begin
        if ($value$plusargs("HALF=%d", half_period)) begin end
        if ($value$plusargs("STALLS=%d", stalls)) begin end
    end
    integer cycles [0:DEVICES-1];
    wire [`MESH_LINK_WIDTH-1:0] tx [0:DEVICES-1][0:PEERS-1], rx [0:DEVICES-1][0:PEERS-1];
    wire tx_valid [0:DEVICES-1][0:PEERS-1], tx_ready [0:DEVICES-1][0:PEERS-1];
    wire rx_valid [0:DEVICES-1][0:PEERS-1], rx_ready [0:DEVICES-1][0:PEERS-1];
    wire [31:0] faults [0:DEVICES-1][0:PEERS-1];
    wire fault_valid [0:DEVICES-1][0:PEERS-1];

    // Application streams occupy [0,N); debug streams occupy [N,2N).
    reg [32:0] command_words [0:STREAMS-1][0:4095];
    integer command_head [0:STREAMS-1], command_tail [0:STREAMS-1];
    reg [32:0] host_in [0:STREAMS-1];
    reg host_in_valid [0:STREAMS-1];
    wire host_in_ready [0:STREAMS-1];
    wire [32:0] host_out [0:STREAMS-1];
    wire host_out_valid [0:STREAMS-1];
    wire [32:0] request_data [0:STREAMS-1], response_data [0:STREAMS-1];
    wire request_valid [0:STREAMS-1], request_ready [0:STREAMS-1];
    wire response_valid [0:STREAMS-1], response_ready [0:STREAMS-1];
    wire [3:0] debug_keep [0:DEVICES-1];
    integer activity, traffic, received_traffic, progress, host_requests, host_responses, scan;
    reg finished = 0;
    reg [31:0] response_words [0:STREAMS-1][0:15];
    integer response_size [0:STREAMS-1];

    for (genvar d = 0; d < DEVICES; d = d+1) begin: boards
        initial begin
            #(d % 8);
            forever #(half_period) device_clk[d] = !device_clk[d];
        end
        hls_clock_reset release_reset(.clk(device_clk[d]), .reset(reset), .local_reset(device_reset[d]));
        always @(posedge device_clk[d]) begin
            if (device_reset[d]) cycles[d] <= 0;
            else cycles[d] <= cycles[d]+1;
            if (resetn && !device_reset[d]) begin
                if (response_valid[d] && response_ready[d])
                    $fdisplay(progress, "1 %0d %0d %0d %08h %0d", d, cycles[d], $time,
                        response_data[d][31:0], response_data[d][32]);
                if (response_valid[d+DEVICES] && debug_keep[d] !== 4'hf)
                    $fatal(1, "partial debug word D%0d", d);
            end
        end
        for (genvar l = 0; l < PEERS; l = l+1) begin: links
            phi_mesh_stability #(.WIDTH(`MESH_LINK_WIDTH)) output_contract(
                .clk(device_clk[d]), .reset(device_reset[d]), .data(tx[d][l]),
                .valid(tx_valid[d][l]), .ready(tx_ready[d][l]));
            always @(posedge device_clk[d]) if (resetn && !device_reset[d]) begin
                if (fault_valid[d][l] !== 1'b0) $fatal(1, "link fault D%0d L%0d: %h", d, l, faults[d][l]);
                if (tx_valid[d][l] && tx_ready[d][l])
                    $fdisplay(traffic, "%0d %0d %0d %09h", $time, d, l, tx[d][l]);
                if (rx_valid[d][l] && rx_ready[d][l])
                    $fdisplay(received_traffic, "%0d %0d %0d %09h", $time, d, l, rx[d][l]);
            end
        end
        // A compact change log still reconstructs every public handshake cycle.
        wire [19:0] bits = {request_valid[d], request_ready[d], response_valid[d], response_ready[d],
            rx_valid[d][3], rx_ready[d][3], rx_valid[d][2], rx_ready[d][2],
            rx_valid[d][1], rx_ready[d][1], rx_valid[d][0], rx_ready[d][0],
            tx_valid[d][3], tx_ready[d][3], tx_valid[d][2], tx_ready[d][2],
            tx_valid[d][1], tx_ready[d][1], tx_valid[d][0], tx_ready[d][0]};
        reg [19:0] previous = 20'hfffff;
        always @(posedge device_clk[d]) if (resetn && !device_reset[d]) begin
            if ((^bits) === 1'bx) $fatal(1, "unknown public handshake D%0d", d);
            if (bits !== previous) $fdisplay(activity, "%0d %0d %0d %05h", $time, d, cycles[d], bits);
            previous = bits;
        end
    end
    for (genvar s = 0; s < STREAMS; s = s+1) begin: host_crossings
        hls_async_fifo request_fifo(.reset(reset), .wr_clk(clk), .rd_clk(device_clk[s % DEVICES]),
            .in_data(host_in[s]), .in_valid(host_in_valid[s]), .in_ready(host_in_ready[s]),
            .out_data(request_data[s]), .out_valid(request_valid[s]), .out_ready(request_ready[s]));
        hls_async_fifo response_fifo(.reset(reset), .wr_clk(device_clk[s % DEVICES]), .rd_clk(clk),
            .in_data(response_data[s]), .in_valid(response_valid[s]), .in_ready(response_ready[s]),
            .out_data(host_out[s]), .out_valid(host_out_valid[s]), .out_ready(resetn));
        phi_mesh_stability output_contract(.clk(device_clk[s % DEVICES]), .reset(device_reset[s % DEVICES]),
            .data(response_data[s]), .valid(response_valid[s]), .ready(response_ready[s]));
    end

    `include "phi_mesh_devices.vh"

    // One bounded batch is supplied for every accepted host response packet.
    task read_commands;
        integer count, d, n, p, w;
        reg [31:0] value;
        begin
            scan = $fscanf(host_responses, "%h", count);
            if (scan != 1 || count < -1 || count > 1024) $fatal(1, "invalid host batch");
            if (count == -1) finished = 1;
            for (p = 0; p < count; p = p+1) begin
                scan = $fscanf(host_responses, "%h %h", d, n);
                if (scan != 2 || d < 0 || d >= STREAMS || n < 2 || n > 15) $fatal(1, "invalid host packet");
                if (command_tail[d]-command_head[d]+n > 4096) $fatal(1, "host queue overflow");
                for (w = 0; w < n; w = w+1) begin
                    scan = $fscanf(host_responses, "%h", value);
                    if (scan != 1) $fatal(1, "truncated host packet");
                    command_words[d][command_tail[d] % 4096] = {w == n-1, value};
                    command_tail[d] = command_tail[d]+1;
                end
            end
        end
    endtask
    task accept_response(input integer d);
        integer i;
        begin
            if (response_size[d] >= 15) $fatal(1, "oversized response");
            response_words[d][response_size[d]] = host_out[d][31:0];
            response_size[d] = response_size[d]+1;
            if (host_out[d][32] && !finished) begin
                $fwrite(host_requests, "%08h %08h\n", d, response_size[d]);
                for (i = 0; i < response_size[d]; i = i+1) $fwrite(host_requests, " %08h", response_words[d][i]);
                $fwrite(host_requests, "\n"); $fflush(host_requests);
                // Make every accepted status visible before the reducer computes its final metrics.
                $fflush(progress);
                read_commands;
                response_size[d] = 0;
            end
        end
    endtask
    initial begin
        for (integer s = 0; s < STREAMS; s = s+1) begin
            command_head[s] = 0; command_tail[s] = 0; response_size[s] = 0;
            host_in_valid[s] = 0; host_in[s] = 0;
        end
        activity = $fopen("activity.log", "w"); traffic = $fopen("traffic.log", "w"); progress = $fopen("progress.log", "w");
        received_traffic = $fopen("received-traffic.log", "w");
        host_requests = $fopen("host_requests", "w"); host_responses = $fopen("host_responses", "r");
        if (!activity || !traffic || !received_traffic || !progress || !host_requests || !host_responses) $fatal(1, "cannot open profile files");
        read_commands;
        #1; reset = 1;
        repeat (16) @(negedge clk);
        reset = 0; resetn = 1;
    end
    always @(posedge clk) if (resetn) begin
        for (integer s = 0; s < STREAMS; s = s+1) begin
            if (host_in_valid[s] && host_in_ready[s]) command_head[s] = command_head[s]+1;
            if (host_out_valid[s]) accept_response(s);
        end
    end
    always @(negedge clk) begin
        for (integer s = 0; s < STREAMS; s = s+1) begin
            host_in_valid[s] = resetn && command_head[s] < command_tail[s];
            if (host_in_valid[s]) host_in[s] = command_words[s][command_head[s] % 4096];
        end
        if (finished) begin
            for (integer d = 0; d < DEVICES; d = d+1)
                if (command_head[d] != command_tail[d]) $fatal(1, "unfinished application commands");
            $display("PASS: %0d-device four-neighbor phi mesh, %0d ns device clocks", DEVICES, 2*half_period);
            $finish;
        end
    end
    initial begin #20000000; $fatal(1, "mesh timeout"); end
endmodule

// Observe ready/valid stability at the public application and query outputs.
module phi_mesh_stability #(parameter WIDTH=33)(input wire clk, reset, input wire [WIDTH-1:0] data, input wire valid, ready);
    reg stalled = 0;
    reg [WIDTH-1:0] held;
    always @(posedge clk) begin
        if (reset) stalled <= 0;
        else begin
            if (valid === 1'bx || (valid && ((^data) === 1'bx || ready === 1'bx)))
                $fatal(1, "unknown public transfer");
            if (stalled && (!valid || data !== held)) $fatal(1, "stalled response changed");
            stalled <= valid && !ready;
            held <= data;
        end
    end
endmodule
`include "phi_link_delay.svh"
