import protocol_activation as activation;

// All control bits: readiness means exactly the old stopped, healthy setup boundary.
pub fn readiness(s: activation::State, c: activation::Conditions) -> bool {
  let a = activation::observe(s, c);
  a.start_ready == (!c.reset && !s.running && c.startup_done && c.ingress_idle && !c.ingress_valid && !c.fault) &&
    a.running == (!c.reset && s.running)
}
// All control bits: reset wins; otherwise start is monotone and requires a handshake.
pub fn transition(s: activation::State, c: activation::Conditions, valid: bool) -> bool {
  let a = activation::tick(s, c, valid);
  a.state.running == (!c.reset && (s.running || (valid && a.output.start_ready)))
}
// Changing only the live request cannot change current observations or eligibility.
pub fn registered(s: activation::State, c: activation::Conditions) -> bool {
  activation::tick(s, c, false).output == activation::tick(s, c, true).output
}
// Representative single, fixture and wider fan-in masks; all bits are quantified.
pub fn masks(s: activation::State, reset: bool, a: u1, b: u3, c: u8, d: bits[257]) -> bool {
  let active = s.running && !reset;
  activation::eligible(s, reset, a) == (if active { a } else { u1:0 }) &&
  activation::eligible(s, reset, b) == (if active { b } else { u3:0 }) &&
  activation::eligible(s, reset, c) == (if active { c } else { u8:0 }) &&
  activation::eligible(s, reset, d) == (if active { d } else { bits[257]:0 })
}
// Deliberately false: a request alone does not override unfinished/faulted setup.
pub fn wrong_start(s: activation::State, c: activation::Conditions) -> bool {
  activation::tick(s, c, true).state.running == !c.reset
}
