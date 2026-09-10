// Retained round-robin ownership for one shared lookahead resource.

import arbitration;

pub struct State<CONTENDER_COUNT: u32> {
  owner_valid: u1,
  owner: u32,
  cursor: u32,
  pending: u1[CONTENDER_COUNT],
}

// The owner is retained until its release arrives. Requests remain pending
// while another contender owns the resource, and the cursor advances after
// every grant. There is no tentative acquisition or rollback loop.
pub proc Arbiter<CONTENDER_COUNT: u32> {
  request_in: chan<u1>[CONTENDER_COUNT] in;
  grant_out: chan<u1>[CONTENDER_COUNT] out;
  release_in: chan<u1>[CONTENDER_COUNT] in;

  config(
      request_in: chan<u1>[CONTENDER_COUNT] in,
      grant_out: chan<u1>[CONTENDER_COUNT] out,
      release_in: chan<u1>[CONTENDER_COUNT] in
  ) {
    (request_in, grant_out, release_in)
  }

  init { zero!<State<CONTENDER_COUNT>>() }

  next(state: State<CONTENDER_COUNT>) {
    let (request_tok, captured_pending) =
      unroll_for! (contender, acc):
          (u32, (token, u1[CONTENDER_COUNT])) in u32:0..CONTENDER_COUNT {
        let (next_tok, _request, received) = recv_if_non_blocking(
          acc.0,
          request_in[contender],
          !acc.1[contender],
          u1:0);
        (
          next_tok,
          if received {
            update(acc.1, contender, u1:1)
          } else {
            acc.1
          }
        )
      }((join(), state.pending));
    let (release_tok, released) =
      unroll_for! (contender, acc): (u32, (token, u1)) in
          u32:0..CONTENDER_COUNT {
        let (next_tok, _release, received) = recv_if_non_blocking(
          acc.0,
          release_in[contender],
          state.owner_valid && state.owner == contender,
          u1:0);
        (next_tok, acc.1 || received)
      }((request_tok, u1:0));
    let retained_owner = state.owner_valid && !released;
    let (winner_valid, winner) = arbitration::select(captured_pending, state.cursor);
    let grant_valid = !retained_owner && winner_valid;
    let _grant_tok = unroll_for! (contender, tok):
        (u32, token) in u32:0..CONTENDER_COUNT {
      send_if(
        tok,
        grant_out[contender],
        grant_valid && winner == contender,
        u1:1)
    }(release_tok);
    let pending = if grant_valid {
      update(captured_pending, winner, u1:0)
    } else {
      captured_pending
    };
    let cursor = if grant_valid {
      if winner + u32:1 == CONTENDER_COUNT {
        u32:0
      } else {
        winner + u32:1
      }
    } else {
      state.cursor
    };
    State<CONTENDER_COUNT> {
      owner_valid: retained_owner || grant_valid,
      owner: if grant_valid { winner } else { state.owner },
      cursor,
      pending,
    }
  }
}


// Router-side ownership of a lookahead reservation. Actor-specific payloads
// and effect indices remain in the router; these flags describe its protocol.
pub struct ClientState {
  active: u1,
  window_requested: u1,
  window_granted: u1,
  credit_debt: u1,
  lookahead: u1,
}

pub struct ClientStep {
  state: ClientState,
  forward_credit: u1,
  release: u1,
  request: u1,
  carry_lookahead: u1,
  batch_continues: u1,
}

pub fn can_receive(state: ClientState, state_last: u1) -> u1 {
  !state.active || (state_last && state.credit_debt && !state.lookahead)
}

// last means the current batch completes in this activation. The caller sends
// downstream effects first, then credit, release, and request in that order.
pub fn advance_client(
    state: ClientState, incoming_valid: u1, grant_valid: u1, last: u1) -> ClientStep {
  let batch_valid = state.active || incoming_valid;
  let batch_continues = batch_valid && !last;
  // A stale grant cannot lend credit to a newly received batch: its scheduler
  // has not yet made egress_busy visible. Return that grant to the arbiter.
  let grant_usable = grant_valid && state.active && !state.lookahead && batch_continues;
  let swallow_physical = last && state.credit_debt && !state.lookahead;
  let forward_credit = grant_usable || (last && !swallow_physical);
  let carry_lookahead = last && swallow_physical && incoming_valid;
  let release = (last && state.lookahead) ||
    (last && state.credit_debt && !incoming_valid) ||
    (grant_valid && !grant_usable);
  let pending_request = state.window_requested && !grant_valid;
  let window_granted = (state.window_granted || grant_usable) && !release;
  let credit_debt = (state.credit_debt || grant_usable) && !swallow_physical;
  let next_active = carry_lookahead || batch_continues;
  let next_lookahead = if carry_lookahead { true } else {
    if batch_continues { state.lookahead } else { false }
  };
  let request = next_active && !next_lookahead && !window_granted &&
    !credit_debt && !pending_request;
  let next_state = if carry_lookahead {
    ClientState {
      active: true, window_requested: false,
      window_granted, credit_debt, lookahead: true,
    }
  } else if batch_continues {
    ClientState {
      active: true, window_requested: pending_request || request,
      window_granted, credit_debt, lookahead: state.lookahead,
    }
  } else {
    ClientState { window_requested: pending_request || request, ..zero!<ClientState>() }
  };
  ClientStep {
    state: next_state, forward_credit, release, request,
    carry_lookahead, batch_continues,
  }
}

#[test_proc]
proc ArbiterRetainsAndRoundRobinsTest {
  terminator: chan<bool> out;
  request_out: chan<u1>[u32:3] out;
  grant_in: chan<u1>[u32:3] in;
  release_out: chan<u1>[u32:3] out;

  config(terminator: chan<bool> out) {
    let (request_p, request_c) =
      chan<u1, u32:1>[u32:3]("effect_window_test_request");
    let (grant_p, grant_c) =
      chan<u1, u32:1>[u32:3]("effect_window_test_grant");
    let (release_p, release_c) =
      chan<u1, u32:1>[u32:3]("effect_window_test_release");
    spawn Arbiter<u32:3>(request_c, grant_p, release_c);
    (terminator, request_p, grant_c, release_p)
  }

  init { () }

  next(state: ()) {
    let request_1_tok = send(join(), request_out[u32:1], u1:1);
    let (grant_1_tok, grant_1) = recv(request_1_tok, grant_in[u32:1]);
    assert_eq(grant_1, u1:1);

    // Both requests become pending while contender one retains ownership.
    // The cursor then chooses contender two before wrapping to zero.
    let request_2_tok = send(grant_1_tok, request_out[u32:2], u1:1);
    let request_0_tok = send(request_2_tok, request_out[u32:0], u1:1);
    let (poll_2_tok, _early_2, early_2) = recv_non_blocking(
      request_0_tok, grant_in[u32:2], u1:0);
    let (poll_0_tok, _early_0, early_0) = recv_non_blocking(
      poll_2_tok, grant_in[u32:0], u1:0);
    assert_eq(early_2, false);
    assert_eq(early_0, false);
    let release_1_tok = send(poll_0_tok, release_out[u32:1], u1:1);
    let (grant_2_tok, grant_2) = recv(release_1_tok, grant_in[u32:2]);
    assert_eq(grant_2, u1:1);

    let release_2_tok = send(grant_2_tok, release_out[u32:2], u1:1);
    let (grant_0_tok, grant_0) = recv(release_2_tok, grant_in[u32:0]);
    assert_eq(grant_0, u1:1);
    let release_0_tok = send(grant_0_tok, release_out[u32:0], u1:1);
    let _done = send(release_0_tok, terminator, true);
    state
  }
}

#[test]
fn stale_grant_cannot_lend_credit_to_a_new_batch_test() {
  let pending = ClientState { window_requested: true, ..zero!<ClientState>() };
  let received = advance_client(pending, true, true, false);
  assert_eq(received.forward_credit, false);
  assert_eq(received.release, true);
  assert_eq(received.request, true);
  assert_eq(received.state, ClientState {
    active: true, window_requested: true, ..zero!<ClientState>() });
}

#[test]
fn lookahead_borrows_one_credit_and_repays_it_at_completion_test() {
  let active = ClientState {
    active: true, window_requested: true, ..zero!<ClientState>() };
  assert_eq(can_receive(active, true), false);
  let granted = advance_client(active, false, true, false);
  assert_eq((granted.forward_credit, granted.release, granted.request), (true, false, false));
  assert_eq(granted.state.credit_debt, true);
  assert_eq(granted.state.window_granted, true);
  assert_eq(can_receive(granted.state, false), false);
  assert_eq(can_receive(granted.state, true), true);
  let replaced = advance_client(granted.state, true, false, true);
  assert_eq((replaced.forward_credit, replaced.release, replaced.carry_lookahead), (false, false, true));
  assert_eq(replaced.state, ClientState {
    active: true, window_granted: true, lookahead: true, ..zero!<ClientState>() });
  assert_eq(can_receive(replaced.state, true), false);
  let drained = advance_client(replaced.state, false, false, true);
  assert_eq((drained.forward_credit, drained.release, drained.request), (true, true, false));
  assert_eq(drained.state, zero!<ClientState>());
}

#[test]
fn unused_grants_and_unfilled_lookahead_are_released_test() {
  let waiting = ClientState {
    active: true, window_requested: true, ..zero!<ClientState>() };
  let late = advance_client(waiting, false, true, true);
  assert_eq((late.forward_credit, late.release), (true, true));
  assert_eq(late.state, zero!<ClientState>());
  let borrowed = ClientState {
    active: true, window_granted: true, credit_debt: true, ..zero!<ClientState>() };
  let unused = advance_client(borrowed, false, false, true);
  assert_eq((unused.forward_credit, unused.release), (false, true));
  assert_eq(unused.state, zero!<ClientState>());
}

#[test]
fn requests_remain_pending_without_duplicates_after_batch_completion_test() {
  let started = advance_client(zero!<ClientState>(), true, false, false);
  assert_eq(started.request, true);
  let waiting = advance_client(started.state, false, false, false);
  assert_eq(waiting.request, false);
  assert_eq(waiting.state.window_requested, true);
  let completed = advance_client(waiting.state, false, false, true);
  assert_eq(completed.forward_credit, true);
  assert_eq(completed.state, ClientState { window_requested: true, ..zero!<ClientState>() });
  let returned = advance_client(completed.state, false, true, false);
  assert_eq(returned.release, true);
  assert_eq(returned.forward_credit, false);
  assert_eq(returned.state, zero!<ClientState>());
}
