// Retained round-robin ownership for one shared lookahead resource.

pub struct State<CONTENDER_COUNT: u32> {
  owner_valid: u1,
  owner: u32,
  cursor: u32,
  pending: u1[CONTENDER_COUNT],
}

pub fn select<CONTENDER_COUNT: u32>(
    pending: u1[CONTENDER_COUNT], cursor: u32) -> (u1, u32) {
  let (after_found, after_index, before_found, before_index) =
    unroll_for! (candidate, acc):
        (u32, (u1, u32, u1, u32)) in u32:0..CONTENDER_COUNT {
      let take_after = !acc.0 && candidate >= cursor && pending[candidate];
      let take_before = !acc.2 && candidate < cursor && pending[candidate];
      (
        acc.0 || take_after,
        if take_after { candidate } else { acc.1 },
        acc.2 || take_before,
        if take_before { candidate } else { acc.3 }
      )
    }((u1:0, u32:0, u1:0, u32:0));
  (
    after_found || before_found,
    if after_found { after_index } else { before_index }
  )
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
    let (winner_valid, winner) = select(captured_pending, state.cursor);
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

#[test]
fn selection_respects_cursor_and_wraps_test() {
  let pending = [u1:1, u1:0, u1:1, u1:1];
  assert_eq(select<u32:4>(pending, u32:1), (u1:1, u32:2));
  assert_eq(select<u32:4>(pending, u32:3), (u1:1, u32:3));
  assert_eq(select<u32:4>(pending, u32:4), (u1:1, u32:0));
  assert_eq(
    select<u32:4>(zero!<u1[4]>(), u32:2),
    (u1:0, u32:0));
}
