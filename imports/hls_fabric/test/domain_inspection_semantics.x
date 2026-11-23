// Finite witnesses for domain_2 of hls_protocol_domains_tests:write_inspection/1.
// This local counter retains GLOBAL actor ID 2. Tests use ordinary lifecycle
// commands and initialization; no receiver machine or lifecycle state is forced.
import domain;
import domain_stream as stream;
import domain_codes;

// Waiting advances the actual silent counter and compiled lifecycle controller.
fn settle(initial: domain::State) -> domain::State {
  for (_, s): (u32, domain::State) in u32:0..u32:64 {
    domain::tick(s, zero!<domain::Inputs>()).state
  }(initial)
}

// Start one valid incarnation through the raw public management input.
fn ready() -> domain::State {
  let command = domain::tick(zero!<domain::State>(), domain::Inputs {
    management_valid: true, management_op: domain_codes::OPERATION_ACTIVATE,
    target: u64:1, transition: u64:1, ..zero!<domain::Inputs>()
  });
  let s = settle(command.state);
  assert_eq(s.control.data.lifecycle.phase, domain_codes::PHASE_READY);
  assert_eq(s.control.data.lifecycle.current, u64:1);
  s
}

// Presence bit 25 belongs to the established process-observation schema.
fn present(value: bits[128]) -> bool { ((value >> u32:25) as u1) == u1:1 }

// Only the exact ready lifetime and an initialized native global address are visible.
#[test]
fn native_address_and_incarnation() {
  let query = domain::Inputs { inspect_address: u32:2, inspect_incarnation: u64:1,
    ..zero!<domain::Inputs>() };
  assert_eq(domain::tick(zero!<domain::State>(), query).output.app_inspect_value, bits[128]:0);
  let s = ready();
  let sample = domain::tick(s, query);
  assert_eq(present(sample.output.app_inspect_value), true);
  assert_eq(sample.state, domain::tick(s, zero!<domain::Inputs>()).state);
  for (address, _): (u32, ()) in u32:0..u32:5 {
    let result = domain::tick(s, domain::Inputs { inspect_address: address, ..query });
    assert_eq(present(result.output.app_inspect_value), address == u32:2);
    assert_eq(result.state, sample.state);
  }(());
  assert_eq(domain::tick(s, domain::Inputs { inspect_address: u32:0xffffffff, ..query }).output.app_inspect_value, bits[128]:0);
  assert_eq(domain::tick(s, domain::Inputs { inspect_incarnation: u64:0, ..query }).output.app_inspect_value, bits[128]:0);
  assert_eq(domain::tick(s, domain::Inputs { inspect_incarnation: u64:2, ..query }).output.app_inspect_value, bits[128]:0);
  assert_eq(domain::tick(s, domain::Inputs { reset: true, ..query }).output.app_inspect_value, bits[128]:0);
}

// A query on the stop edge sees pre-edge state; subsequent queries cannot read that lifetime.
#[test]
fn retirement_and_replacement() {
  let query = domain::Inputs { inspect_address: u32:2, inspect_incarnation: u64:1,
    ..zero!<domain::Inputs>() };
  let closing = domain::tick(ready(), domain::Inputs {
    management_valid: true, management_op: domain_codes::OPERATION_STOP,
    expected: u64:1, target: u64:1, transition: u64:2, ..query
  });
  assert_eq(present(closing.output.app_inspect_value), true);
  assert_eq(domain::tick(closing.state, query).output.app_inspect_value, bits[128]:0);
  let stopped = settle(closing.state);
  assert_eq(stopped.control.data.lifecycle.phase, domain_codes::PHASE_STOPPED);
  assert_eq(domain::tick(stopped, query).output.app_inspect_value, bits[128]:0);
  let replacing = domain::tick(stopped, domain::Inputs {
    management_valid: true, management_op: domain_codes::OPERATION_REPLACE,
    expected: u64:1, target: u64:2, transition: u64:3, ..query
  });
  let next = settle(replacing.state);
  assert_eq(next.control.data.lifecycle.phase, domain_codes::PHASE_READY);
  assert_eq(next.control.data.lifecycle.current, u64:2);
  assert_eq(domain::tick(next, query).output.app_inspect_value, bits[128]:0);
  assert_eq(present(domain::tick(next, domain::Inputs {
    inspect_incarnation: u64:2, ..query
  }).output.app_inspect_value), true);
}

// The framed endpoint uses the same passive pins even without an attached host session.
#[test]
fn framed_observation_is_passive() {
  let core = ready();
  let initial = stream::State { core, ..zero!<stream::State>() };
  let query = stream::Inputs { inspect_address: u32:2, inspect_incarnation: u64:1,
    ..zero!<stream::Inputs>() };
  let sample = stream::tick(initial, query);
  assert_eq(present(sample.output.app_inspect_value), true);
  assert_eq(sample.state, stream::tick(initial, zero!<stream::Inputs>()).state);
  assert_eq(stream::tick(initial, stream::Inputs { inspect_address: u32:1, ..query }).output.app_inspect_value, bits[128]:0);
  assert_eq(stream::tick(initial, stream::Inputs { inspect_incarnation: u64:2, ..query }).output.app_inspect_value, bits[128]:0);
  assert_eq(stream::tick(initial, stream::Inputs { domain_reset: true, ..query }).output.app_inspect_value, bits[128]:0);
  assert_eq(stream::tick(initial, stream::Inputs { reset: true, ..query }).output.app_inspect_value, bits[128]:0);
  let reconnected = stream::tick(initial, stream::Inputs {
    transport_reset: true, transport_session: u64:2, ..query
  });
  assert_eq(present(reconnected.output.app_inspect_value), true);
  assert_eq(reconnected.state.core, sample.state.core);
}

// A physical crossing failure belongs to the current incarnation, not to the
// host session. Keeping the fault asserted must still permit a framed snapshot.
#[test]
fn fabric_fault_preserves_lifetime_and_host_management() {
  let initial = stream::State { core: ready(), ..zero!<stream::State>() };
  let attached = stream::tick(initial, stream::Inputs {
    transport_reset: true, transport_session: u64:7, ..zero!<stream::Inputs>()
  }).state;
  let inputs = stream::Inputs { fabric_fault: true, ..zero!<stream::Inputs>() };
  let failed = stream::tick(attached, inputs).state;
  assert_eq(failed.core.control.data.lifecycle.phase, domain_codes::PHASE_FAILED);
  assert_eq(failed.core.control.data.lifecycle.current, u64:1);
  assert_eq(failed.core.control.data.lifecycle.fault, domain_codes::FAULT_PROTOCOL_FAILURE);
  assert_eq(failed.session, u64:7);
  assert_eq(failed.attached, true);
  assert_eq(failed.fault, false);

  // Complete route/header/session/request framing, with no injected parser state.
  let words = u32[5]:[0, 3, 7, 0, 99];
  let received = for (i, s): (u32, stream::State) in u32:0..u32:5 {
    let edge = stream::tick(s, stream::Inputs {
      management_word: words[i], management_valid: true,
      management_last: i == u32:4, ..inputs
    });
    assert_eq(edge.output.management_ready, true);
    edge.state
  }(failed);
  let replying = for (_, s): (u32, stream::State) in u32:0..u32:3 {
    stream::tick(s, inputs).state
  }(received);
  let done = for (i, s): (u32, stream::State) in u32:0..u32:20 {
    let edge = stream::tick(s, stream::Inputs { management_output_ready: true, ..inputs });
    assert_eq(edge.output.management_output_valid, true);
    assert_eq(edge.output.management_output_last, i == u32:19);
    if i == u32:4 { assert_eq(edge.output.management_output_word, u32:99) } else { () };
    if i == u32:7 { assert_eq(edge.output.management_output_word, domain_codes::PHASE_FAILED as u32) } else { () };
    if i == u32:8 { assert_eq(edge.output.management_output_word, u32:1) } else { () };
    if i == u32:16 { assert_eq(edge.output.management_output_word, domain_codes::FAULT_PROTOCOL_FAILURE as u32) } else { () };
    assert_eq(edge.output.wire_fault, false);
    assert_eq(edge.output.transport_attached, true);
    edge.state
  }(replying);
  assert_eq(done.core.control.data.lifecycle.current, u64:1);
  assert_eq(done.core.control.data.lifecycle.phase, domain_codes::PHASE_FAILED);
  assert_eq(done.core.control.data.lifecycle.fault, domain_codes::FAULT_PROTOCOL_FAILURE);
}

// Optional SAT target: every finite raw-domain state/input agrees on next state
// for any alternative inspection address and expected incarnation. Other inputs
// are identical; this is a one-edge noninterference property, not progress.
pub fn inspection_does_not_mutate(s: domain::State, io: domain::Inputs,
                                 address: u32, incarnation: u64) -> bool {
  domain::tick(s, io).state == domain::tick(s, domain::Inputs {
    inspect_address: address, inspect_incarnation: incarnation, ..io
  }).state
}
