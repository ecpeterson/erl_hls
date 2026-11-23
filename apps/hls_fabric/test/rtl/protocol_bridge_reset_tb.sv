// Finite public-pin reset/error witness; no native hierarchy is read.
module tb;
reg clk=0,reset=1,retire=0,s_app_tvalid=0,s_app_tlast=0,m_app_tready=0;
reg [31:0] s_app_tdata=0;
wire s_app_tready,m_app_tvalid,m_app_tlast,fault,running;
wire [31:0] m_app_tdata;
protocol_bridge_top dut(.*);
reg [31:0] identity[0:7];
reg [63:0] session;
reg [255:0] packet;
integer i,j,k;
// Clock only after sampling the public handshake.
task tick; begin #4;clk=1;#5;clk=0;#1;end endtask
// Cancel all held ownership and mask output immediately.
task clear; begin
  reset=1;retire=0;s_app_tvalid=0;m_app_tready=0;tick;#1;
  if(m_app_tvalid||s_app_tready||fault) $fatal(1,"unmasked reset");
  reset=0;tick;
end endtask
// A beat remains immutable until the accepted rising edge.
task send(input [31:0] data,input last);integer n;begin
  s_app_tdata=data;s_app_tlast=last;s_app_tvalid=1;#1;n=0;
  while(!s_app_tready) begin tick;n=n+1;if(n>100) $fatal(1,"input blocked");end
  tick;s_app_tvalid=0;
end endtask
// Fresh attachment uses the exact build identity and a new nonzero session.
task attach(input [63:0] incarnation);begin
  session=incarnation;send(32'h00010007,0);send(32'h0100000a,0);
  send(session[31:0],0);send(session[63:32],0);
  for(j=0;j<8;j=j+1)send(identity[j],j==7);
end endtask
// Require the complete attachment receipt before the peer may send actor packets.
task attached;reg [31:0] expected;integer n;begin
  m_app_tready=1;
  for(k=0;k<4;k=k+1)begin
    n=0;#1;while(!m_app_tvalid)begin tick;n=n+1;if(n>100)$fatal(1,"missing receipt");end
    case(k)0:expected=32'h00070001;1:expected=32'h81000002;2:expected=session[31:0];3:expected=session[63:32];endcase
    if(m_app_tdata!==expected||m_app_tlast!==(k==3))$fatal(1,"wrong attachment");tick;
  end
  m_app_tready=0;
end endtask
initial begin
@@IDENTITY@@
  clear;
  // Interrupted prefix cannot contaminate a new reset-owned attachment.
  send(32'h00010007,0);send(32'h0100000a,0);send(32'hdeadbeef,0);
  clear;attach(101);attached;
  // Reset while a reverse credit or startup frame is stalled.
  repeat(20)tick;
  if(!m_app_tvalid)$fatal(1,"no held output");
  clear;attach(102);attached;
  // Partial setup and explicit retirement each require a fresh attachment.
  send(32'h00010007,0);send(32'h02000006,0);send(102,0);
  clear;attach(103);attached;retire=1;tick;#1;
  if(!fault||m_app_tvalid||s_app_tready)$fatal(1,"retirement not terminal");
  clear;attach(104);attached;
  // Stale incarnation cannot enter a native capture even with a canonical frame.
  packet={8'd1,64'd103,32'd0,16'd@@LINK@@,8'd@@SLOT@@,128'd@@FRAME@@};
  send(32'h00010007,0);send(32'h04000008,0);
  for(i=0;i<8;i=i+1)send(packet[i*32+:32],i==7);
  repeat(3)tick;if(!fault)$fatal(1,"stale session accepted");
  // Identity mismatch is terminal, not a second attach attempt.
  clear;identity[0]=identity[0]^1;attach(105);repeat(3)tick;
  if(!fault||m_app_tvalid)$fatal(1,"wrong identity accepted");
  $display("PROTOCOL_BRIDGE_RESET_PASS interruptions=3 retire=1 stale=1 identity=1");$finish;
end
endmodule
