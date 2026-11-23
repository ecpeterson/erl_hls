import protocol_ingress as ingress;

// Every three-recipient state/input bit pattern: pending removes only consumed
// recipients, ignoring new commands while full; reset/disabled/fault are separate.
pub fn retirement(s: ingress::State<u32:3>, decoded: ingress::Decoded<u32:3>, consumed: u3, valid: bool) -> bool {
  let next = ingress::tick(s, false, true, valid, decoded, consumed);
  s.fault || s.pending == u3:0 ||
    (next.pending == (s.pending & !consumed) && next.frame == s.frame && next.fault == s.fault)
}
// A ready empty boundary stores exactly the accepted canonical command; without
// valid it preserves state. Faulted/disabled boundaries are outside admission.
pub fn admission(s: ingress::State<u32:3>, d: ingress::Decoded<u32:3>, consumed: u3) -> bool {
  let next = ingress::tick(s, false, true, true, d, consumed);
  s.pending != u3:0 || s.fault || !d.canonical ||
    (next.frame == d.frame && next.pending == d.selected && !next.fault)
}
// All finite inputs: shared reset cancels ownership and malformed status.
pub fn reset_cancels(s: ingress::State<u32:3>, d: ingress::Decoded<u32:3>, consumed: u3) -> bool {
  ingress::tick(s, true, true, true, d, consumed) == zero!<ingress::State<u32:3>>()
}
// A malformed accepted packet cannot create any recipient delivery.
pub fn malformed(s: ingress::State<u32:3>, d: ingress::Decoded<u32:3>, consumed: u3) -> bool {
  let next = ingress::tick(s, false, true, true, ingress::Decoded<u32:3> { canonical: false, ..d }, consumed);
  s.pending != u3:0 || s.fault || (next.pending == u3:0 && next.fault)
}
// Deliberately false: a waiting recipient cannot be discarded without consumption.
pub fn wrong_retirement(s: ingress::State<u32:3>, d: ingress::Decoded<u32:3>, consumed: u3) -> bool {
  ingress::tick(s, false, true, false, d, consumed).pending == u3:0
}
