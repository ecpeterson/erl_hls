// Finite generated-wrapper witnesses for the 20-word control-frame fixture.
// The actual source-compiled Erlang kernel supplies every ownership decision.
import domain_channel;

// This fixture uses the same 32-bit tag plus twenty payload words as its generated wrapper.
type Frame = bits[672];

// Lifecycle readiness and destination mailbox readiness remain independent inputs.
fn inputs() -> domain_channel::Inputs {
  domain_channel::Inputs {
    source_incarnation: u64:10, destination_incarnation: u64:20,
    source_live: true, destination_live: true,
    ..zero!<domain_channel::Inputs>()
  }
}

// Both endpoint incarnations are explicitly bound before any source publication.
fn bound() -> domain_channel::State {
  domain_channel::tick(zero!<domain_channel::State>(),
    domain_channel::Inputs { bind_request: true, ..inputs() }).state
}

// A captured frame cannot become a transmitted frame on the same hardware edge.
fn captured() -> domain_channel::State {
  domain_channel::tick(bound(), domain_channel::Inputs {
    source_valid: true, source_frame: Frame:0xabcd, source_slot: u8:7,
    ..inputs()
  }).state
}

// Incoming transport metadata names the one currently admitted packet.
fn data(s: domain_channel::State) -> domain_channel::Inputs {
  domain_channel::Inputs {
    data_valid: true, data_generation: s.controller.data.channel.generation,
    data_sequence: s.controller.data.channel.sequence,
    data_frame: Frame:0xabcd, data_slot: u8:7, ..inputs()
  }
}

// Returning credit carries the same finite packet namespace, never an implicit current slot.
fn credit(s: domain_channel::State) -> domain_channel::Inputs {
  domain_channel::Inputs {
    credit_valid: true, credit_generation: s.controller.data.channel.generation,
    credit_sequence: s.controller.data.channel.sequence, ..inputs()
  }
}

// Control and closing edges cannot transfer application or transport traffic.
fn no_transfer(observed: domain_channel::Outputs) -> bool {
  !observed.source_ready && !observed.tx_valid && !observed.data_ready && !observed.destination_valid &&
    !observed.ack_valid && !observed.credit_ready
}

// Source publication captures one frame/slot, which remain stable under backpressure and a full source.
#[test]
fn source_capture_and_transmit_are_distinct() {
  let binding = domain_channel::tick(zero!<domain_channel::State>(),
    domain_channel::Inputs { bind_request: true, source_valid: true,
      source_frame: Frame:0xdddd, data_tx_ready: true, ..inputs() });
  assert_eq(binding.output.active, true);
  assert_eq(binding.output.generation, u64:1);
  assert_eq(no_transfer(binding.output), true);
  let take = domain_channel::tick(binding.state, domain_channel::Inputs {
    source_valid: true, source_frame: Frame:0xabcd, source_slot: u8:7,
    data_tx_ready: true, ..inputs() });
  assert_eq(take.output.source_ready, true);
  assert_eq(take.output.tx_valid, false);
  assert_eq(take.state.frame, Frame:0xabcd);
  assert_eq(take.state.slot, u8:7);
  let held = domain_channel::tick(take.state, domain_channel::Inputs {
    source_valid: true, source_frame: Frame:0xffff, source_slot: u8:9, ..inputs() });
  assert_eq(held.output.source_ready, false);
  assert_eq(held.output.tx_valid, true);
  assert_eq(held.output.tx_frame, Frame:0xabcd);
  assert_eq(held.output.tx_slot, u8:7);
  assert_eq(held.output.tx_generation, u64:1);
  assert_eq(held.output.tx_sequence, u32:1);
  assert_eq(held.state, take.state);
  let sent = domain_channel::tick(held.state,
    domain_channel::Inputs { data_tx_ready: true, ..inputs() });
  assert_eq(sent.output.tx_valid, true);
  assert_eq(sent.state.controller.data.channel.tx_pending, false);
  assert_eq(sent.state.frame, Frame:0xabcd);
  assert_eq(sent.output.fault, false);
}

// Mailbox acceptance, acknowledgement emission and credit release each need an independent edge.
#[test]
fn receive_acknowledge_and_release_are_distinct() {
  let sent = domain_channel::tick(captured(),
    domain_channel::Inputs { data_tx_ready: true, ..inputs() });
  let held = domain_channel::tick(sent.state, data(sent.state));
  assert_eq(held.output.destination_valid, true);
  assert_eq(held.output.data_ready, false);
  assert_eq(held.state, sent.state);
  let received = domain_channel::tick(sent.state, domain_channel::Inputs {
    destination_ready: true, ack_tx_ready: true, ..data(sent.state) });
  assert_eq(received.output.destination_valid, true);
  assert_eq(received.output.data_ready, true);
  assert_eq(received.output.destination_frame, Frame:0xabcd);
  assert_eq(received.output.destination_slot, u8:7);
  assert_eq(received.output.ack_valid, false);
  assert_eq(received.state.controller.data.channel.received, true);
  let early = domain_channel::tick(received.state, credit(received.state));
  assert_eq(early.output.ack_valid, true);
  assert_eq(early.output.credit_drop, true);
  assert_eq(early.state, received.state);
  let acked = domain_channel::tick(received.state,
    domain_channel::Inputs { ack_tx_ready: true, ..credit(received.state) });
  assert_eq(acked.output.ack_valid, true);
  assert_eq(acked.output.credit_drop, true);
  assert_eq(acked.state.controller.data.channel.inflight, true);
  assert_eq(acked.state.controller.data.channel.ack_pending, false);
  let released = domain_channel::tick(acked.state,
    domain_channel::Inputs { source_valid: true, ..credit(acked.state) });
  assert_eq(released.output.credit_ready, true);
  assert_eq(released.output.credit_drop, false);
  assert_eq(released.output.source_ready, false);
  assert_eq(released.state.controller.data.channel.inflight, false);
  let successor = domain_channel::tick(released.state,
    domain_channel::Inputs { source_valid: true, ..inputs() });
  assert_eq(successor.output.source_ready, true);
  assert_eq(successor.output.packet_sequence, u32:2);
  assert_eq(successor.output.tx_valid, false);
}

// Duplicate and wrong-namespace data cannot reach the mailbox or free an occupied source.
#[test]
fn stale_and_duplicate_packets_do_not_transfer() {
  let premature = domain_channel::tick(captured(), domain_channel::Inputs {
    destination_ready: true, credit_valid: true, credit_generation: u64:1,
    credit_sequence: u32:1, ..data(captured()) });
  assert_eq(premature.output.data_drop, true);
  assert_eq(premature.output.credit_drop, true);
  assert_eq(premature.output.destination_valid, false);
  let sent = domain_channel::tick(captured(),
    domain_channel::Inputs { data_tx_ready: true, ..inputs() });
  let stale = domain_channel::tick(sent.state, domain_channel::Inputs {
    data_generation: u64:0, destination_ready: true, ..data(sent.state) });
  assert_eq(stale.output.data_ready, true);
  assert_eq(stale.output.data_drop, true);
  assert_eq(stale.output.destination_valid, false);
  assert_eq(stale.state, sent.state);
  let received = domain_channel::tick(sent.state,
    domain_channel::Inputs { destination_ready: true, ..data(sent.state) });
  let duplicate = domain_channel::tick(received.state,
    domain_channel::Inputs { destination_ready: true, ..data(received.state) });
  assert_eq(duplicate.output.data_drop, true);
  assert_eq(duplicate.output.destination_valid, false);
  assert_eq(duplicate.state, received.state);
  let acked = domain_channel::tick(received.state,
    domain_channel::Inputs { ack_tx_ready: true, ..inputs() });
  let wrong = domain_channel::tick(acked.state,
    domain_channel::Inputs { credit_sequence: u32:2, ..credit(acked.state) });
  assert_eq(wrong.output.credit_drop, true);
  assert_eq(wrong.state, acked.state);
}

// Endpoint loss wins coincident ready signals; the next closed edge can drain old traffic.
#[test]
fn endpoint_retirement_closes_before_transfer() {
  let sent = domain_channel::tick(captured(),
    domain_channel::Inputs { data_tx_ready: true, ..inputs() });
  let closed = domain_channel::tick(sent.state, domain_channel::Inputs {
    destination_live: false, destination_ready: true, source_valid: true,
    data_tx_ready: true, ack_tx_ready: true, credit_valid: true,
    credit_generation: u64:1, credit_sequence: u32:1, ..data(sent.state) });
  assert_eq(no_transfer(closed.output), true);
  assert_eq(closed.output.active, false);
  assert_eq(closed.state.controller.data.channel.inflight, false);
  assert_eq(closed.state.controller.data.channel.source_incarnation, u64:10);
  assert_eq(closed.state.controller.data.channel.destination_incarnation, u64:20);
  assert_eq(closed.state.controller.data.channel.generation, u64:1);
  assert_eq(closed.state.frame, Frame:0xabcd);
  let drained = domain_channel::tick(closed.state, domain_channel::Inputs {
    destination_ready: true, credit_valid: true, credit_generation: u64:1,
    credit_sequence: u32:1, ..data(closed.state) });
  assert_eq(drained.output.data_ready, true);
  assert_eq(drained.output.data_drop, true);
  assert_eq(drained.output.credit_ready, true);
  assert_eq(drained.output.credit_drop, true);
  assert_eq(drained.output.destination_valid, false);
  assert_eq(drained.output.active, false);
}

// A new destination cannot inherit an unversioned source outbox; both must advance explicitly.
#[test]
fn rebind_requires_both_fresh_incarnations() {
  let rejected = domain_channel::tick(captured(), domain_channel::Inputs {
    bind_request: true, expected_generation: u64:1, destination_incarnation: u64:21, ..inputs() });
  assert_eq(rejected.output.active, false);
  assert_eq(rejected.output.generation, u64:1);
  assert_eq(no_transfer(rejected.output), true);
  let rebound = domain_channel::tick(rejected.state, domain_channel::Inputs {
    bind_request: true, expected_generation: u64:1,
    source_incarnation: u64:11, destination_incarnation: u64:21,
    source_valid: true, ..inputs() });
  assert_eq(rebound.output.active, true);
  assert_eq(rebound.output.generation, u64:2);
  assert_eq(rebound.output.packet_sequence, u32:0);
  assert_eq(no_transfer(rebound.output), true);
  let stale = domain_channel::tick(rebound.state, domain_channel::Inputs {
    source_incarnation: u64:11, destination_incarnation: u64:21,
    data_valid: true, data_generation: u64:1, data_sequence: u32:1,
    credit_valid: true, credit_generation: u64:1, credit_sequence: u32:1,
    destination_ready: true, ..inputs() });
  assert_eq(stale.output.destination_valid, false);
  assert_eq(stale.output.data_drop, true);
  assert_eq(stale.output.credit_drop, true);
  assert_eq(stale.state, rebound.state);
}

// Explicit fence and global cold reset suppress every coincident handshake.
#[test]
fn explicit_fence_and_cold_reset() {
  let fenced = domain_channel::tick(captured(), domain_channel::Inputs {
    fence: true, expected_generation: u64:1, source_valid: true,
    data_tx_ready: true, destination_ready: true, ack_tx_ready: true,
    credit_valid: true, credit_generation: u64:1, credit_sequence: u32:1,
    ..data(captured()) });
  assert_eq(no_transfer(fenced.output), true);
  assert_eq(fenced.state.controller.data.channel.active, false);
  assert_eq(fenced.state.controller.data.channel.sequence, u32:1);
  assert_eq(fenced.state.frame, Frame:0xabcd);
  let reset = domain_channel::tick(captured(), domain_channel::Inputs {
    reset: true, source_valid: true, data_tx_ready: true,
    destination_ready: true, ..data(captured()) });
  assert_eq(no_transfer(reset.output), true);
  assert_eq(reset.state, zero!<domain_channel::State>());
}

// All state/input bits: an incoming generation mismatch excludes destination presentation.
// This is one symbolic wrapper edge, not a progress claim or a physical-fence certificate.
pub fn stale_exclusion(s: domain_channel::State, io: domain_channel::Inputs) -> bool {
  let stale = io.data_valid && io.data_generation != s.controller.data.channel.generation;
  !stale || !domain_channel::tick(s, io).output.destination_valid
}

// With stable live endpoints, only old-state received-and-emitted acknowledgement can free credit.
// Reset, lifecycle closure, control edges and sticky service failure abandon work separately.
pub fn credit_release_exact(s: domain_channel::State, io: domain_channel::Inputs) -> bool {
  let old = s.controller.data.channel;
  let result = domain_channel::tick(s, io);
  let ordinary = !io.reset && !io.bind_request && !io.fence && s.controller.failure == u32:0 &&
    !result.output.fault && old.active && io.source_live && io.destination_live &&
    old.source_incarnation == io.source_incarnation &&
    old.destination_incarnation == io.destination_incarnation;
  let released = ordinary && old.inflight && !result.state.controller.data.channel.inflight;
  !released || (io.credit_valid && old.received && !old.tx_pending && !old.ack_pending &&
    io.credit_generation == old.generation && io.credit_sequence == old.sequence)
}

// Rejecting negative control: accepting stale generations would contradict the exclusion property.
pub fn wrong_stale_accepts(s: domain_channel::State, io: domain_channel::Inputs) -> bool {
  let old = s.controller.data.channel;
  let otherwise_deliverable = !io.reset && !io.bind_request && !io.fence &&
    s.controller.failure == u32:0 && old.active && old.inflight && !old.received &&
    !old.tx_pending && io.source_live && io.destination_live &&
    old.source_incarnation == io.source_incarnation &&
    old.destination_incarnation == io.destination_incarnation &&
    io.data_sequence == old.sequence;
  let stale = otherwise_deliverable && io.data_valid && io.data_generation != old.generation;
  !stale || domain_channel::tick(s, io).output.destination_valid
}
