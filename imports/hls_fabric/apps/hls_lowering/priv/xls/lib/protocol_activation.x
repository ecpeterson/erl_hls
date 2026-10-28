// Monotone activation for one common-reset network; no pause/rearm handshake.
pub struct State { running: bool }
// Old-state setup observations. ingress_valid prevents simultaneous command/start.
pub struct Conditions {
  reset: bool,
  startup_done: bool,
  ingress_idle: bool,
  ingress_valid: bool,
  fault: bool,
}
// Pre-edge handshake and registered run state; reset masks both.
pub struct Observation { start_ready: bool, running: bool }
// One state update with its current externally visible observations.
pub struct Tick { state: State, output: Observation }

// Startup consumption and host retirement are required, not network quiescence.
// Entry actions/publications may still be pending. Faults cannot restart a run.
pub fn observe(s: State, c: Conditions) -> Observation {
  Observation { running: !c.reset && s.running,
    start_ready: !c.reset && !s.running && c.startup_done && c.ingress_idle &&
      !c.ingress_valid && !c.fault }
}

// A start takes effect after this edge; only reset can clear it. Callers must use
// old State (not this result) for capture eligibility on the handshake edge.
pub fn tick(s: State, c: Conditions, start_valid: bool) -> Tick {
  let output = observe(s, c);
  Tick { state: State { running: !c.reset && (s.running || (start_valid && output.start_ready)) }, output }
}

// Gate only internal capture slots; startup and host slots have separate offers.
pub fn eligible<N: u32>(s: State, reset: bool, mask: bits[N]) -> bits[N] {
  if !reset && s.running { mask } else { bits[N]:0 }
}
