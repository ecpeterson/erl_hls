import protocol_bridge as b;
// All finite bits of this component population, including unreachable states.
type S = b::State<1,2,1>;
// Native observations are fixed by old state at the composition boundary.
type I = b::Inputs<1,2,1,1>;
// Current input beats and sink readiness cannot change a held output observation.
pub fn retained(s: S, io: I, word: u32, last: bool, valid: bool, ready: bool) -> bool {
  let a=b::tick(s,io,bits[256]:42,u16:1,u16:7);
  let c=b::tick(s,I {word,last,valid,ready,..io},bits[256]:42,u16:1,u16:7);
  a.output.word==c.output.word && a.output.last==c.output.last && a.output.valid==c.output.valid
}
// Reset clears every session/reservation and exposes no command or transfer.
pub fn reset(s: S, io: I) -> bool {
  let t=b::tick(s,I {reset:true,..io},bits[256]:42,u16:1,u16:7);
  t.state==zero!<S>() && !t.output.valid && !t.output.ready && !t.output.active &&
    !t.output.start_valid && !t.output.control_valid && !t.output.incoming_valid[u32:0] && !t.output.outgoing_ready[u32:0]
}
// An absent class credit or wrong session cannot produce a native data offer.
pub fn credit(s: S, io: I) -> bool {
  let p=b::unpack(s.rx.payload as bits[256]);
  let t=b::tick(s,io,bits[256]:42,u16:1,u16:7);
  !t.output.incoming_valid[u32:0] || (s.attached && p.session==s.session &&
    ((s.issued[u32:0] && io.credits[u32:0].free && io.credits[u32:0].link==p.link && io.credits[u32:0].slot==p.slot) ||
     (s.issued[u32:1] && io.credits[u32:1].free && io.credits[u32:1].link==p.link && io.credits[u32:1].slot==p.slot)))
}
// ACK before the final transmitted beat cannot release an outbound reservation.
pub fn early_ack(s: S, io: I) -> bool {
  let p=b::unpack(s.rx.payload as bits[256]);
  let t=b::tick(s,io,bits[256]:42,u16:1,u16:7);
  io.reset || !s.owners[u32:0].blocked || s.owners[u32:0].sent || p.kind != u8:2 || t.state.owners[u32:0].blocked
}
// The deliberately false assertion detects an admission checker that accepts everything.
pub fn wrong_accept_all(s: S, io: I) -> bool {
  !io.valid || b::tick(s,io,bits[256]:42,u16:1,u16:7).output.incoming_valid[u32:0]
}

// Cancellation is visibly terminal on the very same sampled edge.
pub fn terminal(s: S, io: I) -> bool {
  let t=b::tick(s,io,bits[256]:42,u16:1,u16:7);
  let stop=io.retire || io.child_fault || s.fault || (s.rx.full && s.rx.bad);
  io.reset || !stop || (t.output.fault && !t.output.valid && !t.output.active &&
    !t.output.start_valid && !t.output.control_valid && !t.output.incoming_valid[u32:0] && !t.output.outgoing_ready[u32:0])
}
