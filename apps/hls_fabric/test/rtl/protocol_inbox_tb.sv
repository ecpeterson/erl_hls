// Finite connected transport/receiver witness with independent sender-age,
// mailbox-disposition and ordinary source-value scoreboards. The first reset
// interrupts ownership; two complete incarnations must drain without duplication.
module tb;
reg clk=0,reset=1;
integer cycle=0,epoch=0,limit,push0,push1;
integer sent0=0,sent1=0,held=-1,chosen=-1,sum=0,running=0;
integer consumed=0,postponed_count=0,stalled_count=0,held_count=0;
integer state[0:5],age[0:5],oldest,oldage,selected_index;
reg [5:0] postponed=0,previous_take=0,expected_take=0,pair_pick=0;
reg [127:0] expected_frame[0:255];
integer expected_port[0:255],head=0,tail=0;
reg last_stalled=0;
reg [135:0] last_effect=0;
wire output_ready=cycle>60 && cycle%5!=0;
wire [5:0] eligible,take,released,accepted;
wire input_ready,head_done,dispatched,phase_boundary,output_valid;
wire [1:0] directive;
wire [7:0] port;
wire [127:0] effect;
wire [15:0] failure;
wire [182:0] observations;
assign {eligible,take,released,accepted,input_ready,head_done,dispatched,directive,
  phase_boundary,output_valid,port,effect,failure}=observations;
@@WIRING@@
wire [5:0] available={link_1_available,link_0_available};
wire [5:0] leased={link_1_leased,link_0_leased};


// Frames use source tags and little-endian 32-bit values independently of codecs.
task expect_output(input integer p,input integer op,input integer value);
begin
  if(tail==256) $fatal(1,"scoreboard overflow");
  expected_port[tail]=p;
  expected_frame[tail]={64'b0,32'(value),8'(op),24'h000001};
  tail=tail+1;
end
endtask

initial begin
  for(epoch=0;epoch<3;epoch=epoch+1) begin
    reset=1;#5;clk=1;#5;clk=0;#1;
    if(observations!==0) $fatal(1,"reset exposed a handshake");
    reset=0;sent0=0;sent1=0;held=-1;sum=0;running=0;consumed=0;
    postponed=0;previous_take=0;postponed_count=0;stalled_count=0;held_count=0;
    head=0;tail=0;last_stalled=0;
    for(integer k=0;k<6;k=k+1) begin state[k]=0;age[k]=0;end
    expect_output(0,3,3);expect_output(1,4,7);expect_output(2,3,5);
    limit=epoch==0 ? 40 : 500;
    for(cycle=0;cycle<limit;cycle=cycle+1) begin
      #4;
      if(cycle==0 && observations!==0) $fatal(1,"startup exposed uninitialized state");
      if(failure!==0) $fatal(1,"source fault");
      if(released!==previous_take) $fatal(1,"wrong delayed release");
      if(last_stalled && (!output_valid || {port,effect}!==last_effect)) $fatal(1,"changed stalled effect");
      if(held>=0) begin
        if(eligible!==(6'b1<<held)) $fatal(1,"lost reserved identity");
        held_count=held_count+1;
      end else if(eligible!=0 && eligible!==~postponed) $fatal(1,"wrong postponement eligibility");
      // Each pair exposes its own oldest eligible message; no cross-sender age order.
      pair_pick=0;
      for(integer pair=0;pair<2;pair=pair+1) begin
        oldest=-1;oldage=2147483647;
        for(integer j=0;j<3;j=j+1) begin
          selected_index=pair*3+j;
          if(state[selected_index]==1 && eligible[selected_index] && age[selected_index]<oldage) begin
            oldest=selected_index;oldage=age[selected_index];
          end
        end
        if(oldest>=0) pair_pick[oldest]=1;
      end
      if({link_1_selected,link_0_selected}!==pair_pick) $fatal(1,"sender order");
      if(accepted!=0) begin
        if(held>=0 || (accepted & (accepted-1))!=0 || (accepted & pair_pick)!=accepted) $fatal(1,"invalid reservation");
        for(integer k=0;k<6;k=k+1) if(accepted[k]) held=k;
      end
      expected_take=0;
      if(head_done) begin
        if(held<0 || !dispatched) $fatal(1,"retired without owned dispatch");
        chosen=held%3;
        if(!running && chosen!=2) begin
          if(directive!=1 || phase_boundary) $fatal(1,"early value not postponed");
          postponed[held]=1;postponed_count=postponed_count+1;
        end else begin
          if(directive!=0 || !phase_boundary) $fatal(1,"bad consumed boundary");
          expected_take[held]=1;consumed=consumed+1;
          if(chosen==2) running=1;else sum=sum+(chosen==0 ? 3 : 5);
          expect_output(3,5,sum);
        end
        held=-1;
      end
      if(phase_boundary) postponed=0;
      if(take!==expected_take) $fatal(1,"dequeue before commit or after postpone");
      previous_take=expected_take;
      if(output_valid && output_ready) begin
        if(head==tail || port!==expected_port[head] || effect!==expected_frame[head])
          $fatal(1,"output mismatch cycle=%0d index=%0d port=%0d frame=%h expected=%h",cycle,head,port,effect,expected_frame[head]);
        head=head+1;
      end
      last_stalled=output_valid && !output_ready;last_effect={port,effect};
      if(last_stalled) stalled_count=stalled_count+1;
      for(integer k=0;k<6;k=k+1) begin
        if(available[k] !== (state[k]==1)) $fatal(1,"availability mismatch");
        if(leased[k] !== (state[k]==2)) $fatal(1,"lease mismatch");
        if(take[k]) begin if(state[k]!=1) $fatal(1,"take without FULL");state[k]=2;end
        else if(released[k]) begin if(state[k]!=2) $fatal(1,"release without LEASED");state[k]=0;end
      end
      if(link_0_capture) begin
        if(state[link_0_capture_slot]!=0 || released[link_0_capture_slot]) $fatal(1,"capture reused live slot");
        state[link_0_capture_slot]=1;age[link_0_capture_slot]=cycle;
      end
      if(link_1_capture) begin
        if(state[3+link_1_capture_slot]!=0 || released[3+link_1_capture_slot]) $fatal(1,"capture reused live slot");
        state[3+link_1_capture_slot]=1;age[3+link_1_capture_slot]=cycle;
      end
      push0=source_0_valid && source_0_ready;
      push1=source_1_valid && source_1_ready;
      clk=1;#5;sent0=sent0+push0;sent1=sent1+push1;clk=0;#1;
    end
    if(epoch==0) begin if(held<0 || !output_valid) $fatal(1,"reset did not interrupt ownership");end
    else begin
      if(sent0!=3 || sent1!=3 || consumed!=18 || sum!=48 || held!=-1 || head!=tail || head!=21 ||
         postponed_count==0 || stalled_count<10 || held_count==0 || previous_take!=0 ||
         {link_1_available,link_0_available,link_1_leased,link_0_leased}!=0)
        $fatal(1,"incomplete witness sent=%0d,%0d consume=%0d sum=%0d outputs=%0d/%0d",sent0,sent1,consumed,sum,head,tail);
    end
  end
  $display("PROTOCOL_INBOX_PASS consumed=%0d sum=%0d outputs=%0d",consumed,sum,head);$finish;
end
endmodule
