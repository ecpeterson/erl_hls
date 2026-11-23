`timescale 1ns/1ps

module partition_link_packets_tb;
    reg clock=0, wire_clock=0, reset_n=0;
    always #20 clock=~clock;
    always #4 wire_clock=~wire_clock;

    reg [32:0] a_link_tx=0, b_link_tx=0;
    reg a_link_tx_valid=0, b_link_tx_valid=0;
    wire a_link_tx_ready, b_link_tx_ready;
    wire [32:0] a_link_rx, b_link_rx;
    wire a_link_rx_valid, b_link_rx_valid;
    reg a_link_rx_ready=0, b_link_rx_ready=0;
    wire [7:0] a_tx_data, b_tx_data;
    wire a_tx_valid, a_tx_last, a_tx_ready;
    wire b_tx_valid, b_tx_last, b_tx_ready;
    wire a_rx_ready, b_rx_ready;
    wire [31:0] a_fault, b_fault;
    wire a_tx_frame, a_rx_frame, a_link_rx_frame;
    wire b_tx_frame, b_rx_frame, b_link_rx_frame;
    integer a_tx_frames=0, a_rx_frames=0, a_delivered_frames=0;
    integer b_tx_frames=0, b_rx_frames=0, b_delivered_frames=0;

    assign a_tx_ready=b_rx_ready;
    assign b_tx_ready=a_rx_ready;

    partition_link_packets #(.ROLE(1)) a(
        .clock(clock),.reset_n(reset_n),.tx_clock(wire_clock),.rx_clock(wire_clock),
        .tx_active_n(1'b1),.rx_active_n(1'b1),
        .link_tx(a_link_tx),.link_tx_valid(a_link_tx_valid),.link_tx_ready(a_link_tx_ready),
        .link_rx(a_link_rx),.link_rx_valid(a_link_rx_valid),.link_rx_ready(a_link_rx_ready),
        .tx_data(a_tx_data),.tx_valid(a_tx_valid),.tx_last(a_tx_last),.tx_ready(a_tx_ready),
        .rx_data(b_tx_data),.rx_valid(b_tx_valid),.rx_last(b_tx_last),.rx_ready(a_rx_ready),
        .fault(a_fault),.tx_frame_accepted(a_tx_frame),
        .rx_frame_accepted(a_rx_frame),.link_rx_frame_delivered(a_link_rx_frame));
    partition_link_packets #(.ROLE(2)) b(
        .clock(clock),.reset_n(reset_n),.tx_clock(wire_clock),.rx_clock(wire_clock),
        .tx_active_n(1'b1),.rx_active_n(1'b1),
        .link_tx(b_link_tx),.link_tx_valid(b_link_tx_valid),.link_tx_ready(b_link_tx_ready),
        .link_rx(b_link_rx),.link_rx_valid(b_link_rx_valid),.link_rx_ready(b_link_rx_ready),
        .tx_data(b_tx_data),.tx_valid(b_tx_valid),.tx_last(b_tx_last),.tx_ready(b_tx_ready),
        .rx_data(a_tx_data),.rx_valid(a_tx_valid),.rx_last(a_tx_last),.rx_ready(b_rx_ready),
        .fault(b_fault),.tx_frame_accepted(b_tx_frame),
        .rx_frame_accepted(b_rx_frame),.link_rx_frame_delivered(b_link_rx_frame));

    always @(posedge clock) begin
      if (a_tx_frame) a_tx_frames <= a_tx_frames + 1;
      if (a_rx_frame) a_rx_frames <= a_rx_frames + 1;
      if (a_link_rx_frame) a_delivered_frames <= a_delivered_frames + 1;
      if (b_tx_frame) b_tx_frames <= b_tx_frames + 1;
      if (b_rx_frame) b_rx_frames <= b_rx_frames + 1;
      if (b_link_rx_frame) b_delivered_frames <= b_delivered_frames + 1;
    end

    task send_a(input [31:0] value, input last);
      begin
        @(negedge clock); a_link_tx={last,value}; a_link_tx_valid=1;
        while(!a_link_tx_ready) @(negedge clock);
        @(negedge clock); a_link_tx_valid=0;
      end
    endtask
    task send_b(input [31:0] value, input last);
      begin
        @(negedge clock); b_link_tx={last,value}; b_link_tx_valid=1;
        while(!b_link_tx_ready) @(negedge clock);
        @(negedge clock); b_link_tx_valid=0;
      end
    endtask
    task receive_a(input [31:0] value, input last);
      begin
        a_link_rx_ready=1;
        while(!a_link_rx_valid) @(negedge clock);
        if(a_link_rx !== {last,value}) $fatal(1,"A link word changed: %h",a_link_rx);
        @(negedge clock); a_link_rx_ready=0;
      end
    endtask
    task receive_b(input [31:0] value, input last);
      begin
        b_link_rx_ready=1;
        while(!b_link_rx_valid) @(negedge clock);
        if(b_link_rx !== {last,value}) $fatal(1,"B link word changed: %h",b_link_rx);
        @(negedge clock); b_link_rx_ready=0;
      end
    endtask

    initial begin
      repeat(5) @(negedge clock); reset_n=1;
      repeat(12) @(negedge clock);
      fork send_a(32'h48508000,1); receive_b(32'h48508000,1); join
      fork
        begin
          send_a(32'h48500000,0); send_a(32'h01020304,0);
          send_a(32'h11223344,0); send_a(32'h89abcdef,0); send_a(32'h55aa55aa,1);
        end
        begin
          receive_b(32'h48500000,0); receive_b(32'h01020304,0);
          receive_b(32'h11223344,0); receive_b(32'h89abcdef,0); receive_b(32'h55aa55aa,1);
        end
      join
      fork send_b(32'h48508000,1); receive_a(32'h48508000,1); join
      repeat(10) @(negedge clock);
      if(a_fault || b_fault) $fatal(1,"framing fault A=%h B=%h",a_fault,b_fault);
      if(a_tx_frames != 2 || a_rx_frames != 1 || a_delivered_frames != 1)
        $fatal(1,"A boundary counts tx=%0d rx=%0d delivered=%0d",
               a_tx_frames,a_rx_frames,a_delivered_frames);
      if(b_tx_frames != 1 || b_rx_frames != 2 || b_delivered_frames != 2)
        $fatal(1,"B boundary counts tx=%0d rx=%0d delivered=%0d",
               b_tx_frames,b_rx_frames,b_delivered_frames);
      $display("PASS: role-tagged credit packets cross Ethernet frame CDC in both directions");
      $finish;
    end
    initial begin #200000; $fatal(1,"timeout"); end
endmodule
