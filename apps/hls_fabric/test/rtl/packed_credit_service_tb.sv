`timescale 1ns/1ps
// Full-duplex opaque frames, independent lane stalls, wire stalls, latency and reset.
// All checks use boundary handshakes; no DUT state is read or forced.
module packed_credit_service_tb;
  parameter WORDS=1, CREDITS=4, ACTIVE=8, DELAY=2, STALLS=0, BLOCK=0, RESTART=0, PATTERN=0;
  localparam LANES=8, WIDTH=34*WORDS, WARMUP=1024, WINDOW=8192, STOP=WARMUP+WINDOW, BIN=1024;
  reg clk=0, reset=1;
  always #4 clk=~clk;
  integer cycle=0, epoch=0;
  integer sent[0:1][0:7], received[0:1][0:7], wire_sent[0:1][0:7], credit[0:1][0:7];
  wire [127:0] frames[0:1][0:7], delivered[0:1][0:7];
  wire [7:0] frame_valid[0:1], frame_ready[0:1], delivered_valid[0:1];
  reg [7:0] delivered_ready[0:1];
  wire [WIDTH-1:0] tx[0:1], rx[0:1];
  wire tx_valid[0:1], tx_ready[0:1], rx_valid[0:1], rx_ready[0:1];
  wire [31:0] fault[0:1];
  wire fault_valid[0:1];
  integer words[0:1][0:7], beats[0:1][0:7], messages[0:1][0:7], blocked[0:1][0:7];
  reg finished[0:1][0:7], stalled[0:1];
  reg output_stalled[0:1][0:7];
  reg [127:0] previous_frame[0:1][0:7];
  integer returned[0:1][0:7];
  integer first_input[0:1], first_header[0:1], first_complete[0:1], first_delivery[0:1];
  reg [WIDTH-1:0] previous[0:1];
  integer stage[0:1], packet_lane[0:1], limit[0:1], base[0:1], short_headers[0:1], long_headers[0:1];
  reg [127:0] packet[0:1];
  integer d,lane,b,i,n,wire_lane,outstanding;
  reg [33:0] subword;
  reg hole;

  // Exercise all compact lengths/opcodes plus metadata, oversize and padding extensions.
  function automatic [127:0] sample(input integer owner, input integer lane_id, input integer ordinal, input integer generation);
    reg [95:0] payload;
    reg [7:0] opcode;
    begin
      payload={32'hdead0000+owner*32'd16+lane_id,32'hcafe0000+ordinal,32'h15926535^(ordinal*32'd65537)};
      opcode=8'ha5 ^ lane_id ^ owner ^ ordinal ^ (generation*8'h79);
      if(!PATTERN) sample={32'h03293742^(generation*32'h10101),payload};
      else case(PATTERN==2 ? 0 : ordinal%8)
        0: sample={8'd0,16'd0,opcode,96'd0};
        1: sample={8'd1,16'd0,opcode,64'd0,payload[31:0]};
        2: sample={8'd2,16'd0,opcode,32'd0,payload[63:0]};
        3: sample={8'd3,16'd0,opcode,payload};
        4: sample={8'd4,16'd0,opcode,payload};
        5: sample={8'd255,16'd0,opcode,payload};
        6: sample={8'd1,16'd0,opcode,payload};
        7: sample={8'd3,8'hfa,8'h13,opcode,payload};
      endcase
    end
  endfunction
  // DSLX flattens the header first; the wire sends its byte-reversed header least first.
  function automatic [127:0] wire_sample(input integer owner, input integer lane_id, input integer ordinal, input integer generation);
    reg [127:0] frame;
    begin
      frame=sample(owner,lane_id,ordinal,generation);
      wire_sample={frame[95:0],frame[103:96],frame[111:104],frame[119:112],frame[127:120]};
    end
  endfunction
  // Decode independently of receiver delivery, including header-only frames.
  task automatic finish_packet(input integer sender);
    begin
      if(packet[sender]!==wire_sample(sender,packet_lane[sender],wire_sent[sender][packet_lane[sender]],epoch))
        $fatal(1,"wrong wire payload/order D%0d lane%0d got %h expected %h",sender,packet_lane[sender],packet[sender],wire_sample(sender,packet_lane[sender],wire_sent[sender][packet_lane[sender]],epoch));
      if (packet_lane[sender]==0 && wire_sent[sender][0]==0) first_complete[sender]=cycle;
      wire_sent[sender][packet_lane[sender]]=wire_sent[sender][packet_lane[sender]]+1;
      stage[sender]=0;
    end
  endtask
  genvar device,j;
  generate for(device=0;device<2;device=device+1) begin
    for(j=0;j<LANES;j=j+1) begin
      assign frames[device][j]=sample(device,j,sent[device][j],epoch);
      assign frame_valid[device][j]=j<ACTIVE && !finished[device][j];
    end
    packed_link dut(.clk(clk),.reset(reset),
      ._link_in(rx[device]),._link_in_vld(rx_valid[device]),._link_in_rdy(rx_ready[device]),
      ._link_out(tx[device]),._link_out_vld(tx_valid[device]),._link_out_rdy(tx_ready[device]),
      ._fault_out(fault[device]),._fault_out_vld(fault_valid[device]),._fault_out_rdy(1'b1),
      @@CONNECTIONS@@);
    if(DELAY==0) begin
      assign rx[1-device]=tx[device];
      assign rx_valid[1-device]=tx_valid[device];
      assign tx_ready[device]=rx_ready[1-device];
    end else begin
      reg [WIDTH-1:0] data[0:DELAY-1];
      reg [DELAY-1:0] valid=0;
      wire [DELAY:0] ready;
      wire admit=!STALLS || (cycle+device)%17>=5;
      assign ready[DELAY]=rx_ready[1-device];
      assign rx[1-device]=data[DELAY-1];
      assign rx_valid[1-device]=valid[DELAY-1];
      assign tx_ready[device]=ready[0]&&admit;
      for(j=0;j<DELAY;j=j+1) begin
        assign ready[j]=!valid[j] || ready[j+1];
        always @(posedge clk) begin
          if(reset) valid[j]<=0;
          else if(ready[j]) begin
            valid[j]<=j==0 ? tx_valid[device]&&admit : valid[j>0 ? j-1 : 0];
            data[j]<=j==0 ? tx[device] : data[j>0 ? j-1 : 0];
          end
        end
      end
    end
  end endgenerate

  // Common reset interrupts a packet and differentiates subsequent payloads.
  initial begin
    if(ACTIVE<1 || ACTIVE>LANES || DELAY<0 || (STALLS&&DELAY==0)) $fatal(1,"invalid scenario");
    repeat(8) @(negedge clk);
    reset=0;
    if(RESTART) begin
      wait(cycle>=200 && (stage[0]!=0 || stage[1]!=0));
      @(negedge clk); reset=1;
      repeat(8) @(negedge clk);
      epoch=1;reset=0;
    end
    wait(cycle>=STOP+4096);
    @(negedge clk);
    outstanding=0;
    for(d=0;d<2;d=d+1) begin
      if(stage[d]!=0) $fatal(1,"incomplete wire packet");
      if(PATTERN==1 && (short_headers[d]==0 || long_headers[d]==0)) $fatal(1,"missing compact/extended coverage");
      if(PATTERN==2 && (short_headers[d]==0 || long_headers[d]!=0)) $fatal(1,"header-only traffic failed to compact");
      for(lane=0;lane<LANES;lane=lane+1) begin
        outstanding=outstanding+sent[d][lane]-received[1-d][lane];
        if(lane<ACTIVE && received[1-d][lane]<20) $fatal(1,"lane failed to progress");
        if(credit[d][lane]!=CREDITS) $fatal(1,"credit failed to return");
      end
      $display("LATENCY device=%0d input_to_wire=%0d wire_to_delivery=%0d", d,
        first_header[d]-first_input[d], first_delivery[1-d]-first_complete[d]);
      for(b=0;b<8;b=b+1) begin
        if(!PATTERN && !STALLS && !BLOCK && ACTIVE==8 && DELAY<=2 && CREDITS>=WORDS && words[d][b]!=WORDS*BIN)
          $fatal(1,"saturated short link lost useful word throughput");
        $display("METRIC device=%0d bin=%0d cycles=%0d words=%0d beats=%0d frames=%0d blocked=%0d",d,b,BIN,words[d][b],beats[d][b],messages[d][b],blocked[d][b]);
      end
    end
    if(outstanding!=0) $fatal(1,"frames failed to drain");
    $display("PASS: WORDS=%0d CREDITS=%0d ACTIVE=%0d DELAY=%0d STALLS=%0d BLOCK=%0d RESTART=%0d",WORDS,CREDITS,ACTIVE,DELAY,STALLS,BLOCK,RESTART);
    $finish;
  end

  // One lane stops for 3,000 clocks; unrelated lanes must continue before release.
  always @(negedge clk) begin
    for(integer dest=0;dest<2;dest=dest+1)
      for(integer slot=0;slot<LANES;slot=slot+1)
        delivered_ready[dest][slot]=(!BLOCK || dest!=0 || slot!=0 || cycle>=3000)
          && (!STALLS || (cycle+dest+slot)%7>=2);
  end

  // Check the decoded wire credit ledger and exact frames independently of receive delivery.
  always @(posedge clk) begin
    if(reset) begin
      cycle<=0;
      for(d=0;d<2;d=d+1) begin
        first_input[d]=-1;first_header[d]=-1;first_complete[d]=-1;first_delivery[d]=-1;
        stalled[d]<=0;stage[d]=0;packet_lane[d]=0;packet[d]=0;limit[d]=0;base[d]=0;short_headers[d]=0;long_headers[d]=0;
        for(lane=0;lane<LANES;lane=lane+1) begin
          returned[d][lane]=0;output_stalled[d][lane]<=0;
          sent[d][lane]<=0;received[d][lane]<=0;wire_sent[d][lane]=0;
          finished[d][lane]<=0;credit[d][lane]=CREDITS;
        end
        for(b=0;b<8;b=b+1) begin words[d][b]=0;beats[d][b]=0;messages[d][b]=0;blocked[d][b]=0;end
      end
    end else begin
      cycle<=cycle+1;
      for(d=0;d<2;d=d+1) begin
        if(tx_valid[d] !== 1'b0 && tx_valid[d] !== 1'b1) $fatal(1,"unknown link valid: possible combinational feedback");
        if(fault_valid[d]) $fatal(1,"bridge fault D%0d code=%0d",d,fault[d]);
        if(stalled[d] && (!tx_valid[d] || tx[d]!==previous[d])) $fatal(1,"stalled transfer changed");
        stalled[d]<=tx_valid[d]&&!tx_ready[d];previous[d]<=tx[d];
        n=0;
        if(tx_valid[d]&&tx_ready[d]) begin
          hole=0;
          for(i=0;i<WORDS;i=i+1) begin
            subword=tx[d][34*i+:34];
            if(!subword[33]) hole=1;
            else begin
              if(hole) $fatal(1,"packed valid prefix has a hole");
              n=n+1;wire_lane=subword[14:0];
              if(stage[d]==0) begin
                if(subword[31:16]==16'h4851) begin
                  wire_lane=subword[4:0];
                  if(wire_lane>=LANES || subword[7:5]>3 || subword[32]!=(subword[7:5]==0)) $fatal(1,"compact header corrupt");
                  if(wire_lane==0 && first_header[d]<0) first_header[d]=cycle;
                  credit[d][wire_lane]=credit[d][wire_lane]-1;
                  if(credit[d][wire_lane]<0) $fatal(1,"uncredited compact data");
                  packet_lane[d]=wire_lane;stage[d]=1;limit[d]=subword[7:5];base[d]=1;
                  packet[d]={96'd0,subword[15:8],16'd0,5'd0,subword[7:5]};
                  short_headers[d]=short_headers[d]+1;
                  if(subword[32]) finish_packet(d);
                end else begin
                  if(subword[31:16]!=16'h4850 || wire_lane>=LANES || subword[32]!=subword[15]) $fatal(1,"extended header corrupt");
                  if(subword[15]) begin
                    returned[d][wire_lane]=returned[d][wire_lane]+1;
                    if(returned[d][wire_lane]>received[d][wire_lane]+(delivered_valid[d][wire_lane]&&delivered_ready[d][wire_lane]))
                      $fatal(1,"credit returned before downstream delivery");
                    credit[1-d][wire_lane]=credit[1-d][wire_lane]+1;
                    if(credit[1-d][wire_lane]>CREDITS) $fatal(1,"excess returned wire credit");
                  end else begin
                    if(wire_lane==0 && first_header[d]<0) first_header[d]=cycle;
                    credit[d][wire_lane]=credit[d][wire_lane]-1;
                    if(credit[d][wire_lane]<0) $fatal(1,"uncredited extended data");
                    packet_lane[d]=wire_lane;stage[d]=1;packet[d]=0;limit[d]=4;base[d]=0;
                    long_headers[d]=long_headers[d]+1;
                  end
                end
              end else begin
                if(subword[32]!=(stage[d]==limit[d])) $fatal(1,"wire termination corrupt");
                packet[d][32*(stage[d]-1+base[d])+:32]=subword[31:0];
                if(stage[d]==limit[d]) finish_packet(d);
                else stage[d]=stage[d]+1;
              end
            end
          end
          if(n==0) $fatal(1,"empty packed transfer");
        end
        if(cycle>=WARMUP && cycle<STOP) begin
          b=(cycle-WARMUP)/BIN;
          words[d][b]=words[d][b]+n;
          beats[d][b]=beats[d][b]+(tx_valid[d]&&tx_ready[d]);
          blocked[d][b]=blocked[d][b]+(tx_valid[d]&&!tx_ready[d]);
          messages[d][b]=messages[d][b]+$countones(delivered_valid[d]&delivered_ready[d]);
        end
        for(lane=0;lane<LANES;lane=lane+1) begin
          if(output_stalled[d][lane] && (!delivered_valid[d][lane] || delivered[d][lane]!==previous_frame[d][lane]))
            $fatal(1,"stalled delivered frame changed");
          output_stalled[d][lane]<=delivered_valid[d][lane]&&!delivered_ready[d][lane];
          previous_frame[d][lane]<=delivered[d][lane];
          if(frame_valid[d][lane]&&frame_ready[d][lane]) begin
            if(lane==0 && first_input[d]<0) first_input[d]=cycle;
            sent[d][lane]<=sent[d][lane]+1;
            if(cycle>=STOP-1) finished[d][lane]<=1;
          end
          if(delivered_valid[d][lane]&&delivered_ready[d][lane]) begin
            if(delivered[d][lane]!==sample(1-d,lane,received[d][lane],epoch)) $fatal(1,"wrong delivered payload/order");
            if(lane==0 && first_delivery[d]<0) first_delivery[d]=cycle;
            received[d][lane]<=received[d][lane]+1;
          end
          if(BLOCK && cycle==2999 && lane<ACTIVE && !(d==0&&lane==0) && received[d][lane]<40)
            $fatal(1,"stopped lane blocked a bystander");
        end
      end
    end
  end
endmodule
