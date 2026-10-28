`timescale 1ns/1ps
// Check all index/value pairs, repeated-row hazards, stalls and a drained reset.
module xls_state_updates_tb;
  localparam N = 4096;
  reg clk=0; always #5 clk=~clk;
  reg reset=1;
  reg [10:0] _command=0;
  reg _command_vld=0, _result_rdy=0;
  wire _command_rdy, _result_vld;
  wire [31:0] _result;
  state_updates dut(.*);
  reg [31:0] model[0:5], expected[0:N-1], held;
  reg blocked=0;
  integer sent=0, received=0, cycle=0, epoch=0, reset_at=-1, index, i;
  initial begin
    for(i=0;i<6;i=i+1) model[i]=0;
    repeat(3) @(negedge clk);
    reset=0;
  end
  always @(negedge clk) begin
    if(reset_at>=0 && cycle>=reset_at+3) begin
      reset=0; reset_at=-1;
    end
    index=sent<2048 ? sent%8 : 0;
    _command={index[2:0],8'(sent<2048 ? sent/8 : sent)};
    _command_vld=!reset && sent<N && cycle%11!=3;
    _result_rdy=!reset && cycle%13>=4;
  end
  always @(posedge clk) begin
    cycle=cycle+1;
    if(!reset) begin
      if(blocked && (!_result_vld || _result!==held)) $fatal(1,"unstable blocked output");
      if(_command_vld && _command_rdy) begin
        expected[sent]=model[index<6 ? index : 5];
        if(index<6) model[index]={24'b0,_command[7:0]};
        sent=sent+1;
      end
      if(_result_vld && _result_rdy) begin
        if(received>=sent || _result!==expected[received])
          $fatal(1,"epoch %0d result %0d got %h expected %h",epoch,received,_result,expected[received]);
        received=received+1;
      end
      blocked=_result_vld && !_result_rdy; held=_result;
      if(received==N) begin
        if(epoch==1) begin $display("PASS: 8192 replies, including ignored writes/clamped reads at indices 6/7, stalls, repeated rows and reset"); $finish; end
        epoch=epoch+1; sent=0; received=0; blocked=0;
        for(i=0;i<6;i=i+1) model[i]=0;
        reset=1; reset_at=cycle;
      end
    end
    if(cycle>100000) $fatal(1,"timeout");
  end
endmodule
