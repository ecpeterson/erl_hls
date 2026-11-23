import protocol_bridge as b;
import protocol_rectangle as control;
// Representative controller access population, independent of native actor payload state.
type Inputs = b::Inputs<1,3,1,3>;
// One pair in each direction and three application endpoint contenders.
type Outputs = b::Outputs<1,1,3>;
// All bridge ownership remains local to this sampled-clock proc.
type State = b::State<1,3,1>;
// Static identities match the connected fixture; native free/offer pins remain inputs.
pub proc bridge_component_clock {
  commands: chan<Inputs> in;
  observations: chan<Outputs> out;
  // Sample every clock; backpressure is explicit input data.
  config(commands: chan<Inputs> in, observations: chan<Outputs> out) { (commands,observations) }
  // No session or reservation survives reset.
  init { zero!<State>() }
  // Apply one transition with one receive and transmit frame budget.
  next(s: State) {
    let (tok,io)=recv(join(),commands);
    let command=control::decode(s.rx.payload[64+:bits[256]],s.rx.header[0+:u8]-u8:2);
    let fixed=Inputs {control_legal:command.valid,incoming_links:[u16:1],outgoing_links:[u16:3],
      credits:[b::Credit {link:u16:1,slot:u8:0,free:io.credits[u32:0].free},
               b::Credit {link:u16:1,slot:u8:1,free:io.credits[u32:1].free},
               b::Credit {link:u16:1,slot:u8:2,free:io.credits[u32:2].free}],..io};
    let step=b::tick(s,fixed,bits[256]:42,u16:1,u16:7);
    let _sent=send(tok,observations,step.output);
    step.state
  }
}
