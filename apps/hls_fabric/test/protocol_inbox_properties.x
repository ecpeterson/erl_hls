import protocol_inbox as inbox;

// A selected request has minimal circular rank among all requested slots.
// This independent relation quantifies requests and a legal cursor, not clocks.
fn valid_selection<N: u32>(requests: bits[N], cursor: u32, pick: inbox::Selection<N>) -> bool {
  let rank = if pick.index >= cursor { pick.index - cursor } else { pick.index + N - cursor };
  let earliest = for (i, ok): (u32, bool) in u32:0..N {
    let other_rank = if i >= cursor { i - cursor } else { i + N - cursor };
    ok && (!((requests >> i) as bool) || other_rank >= rank)
  }(true);
  cursor >= N || if requests == bits[N]:0 { pick.mask == bits[N]:0 }
    else { pick.index < N && pick.mask == bits[N]:1 << pick.index &&
           (pick.mask & requests) == pick.mask && earliest }
}

// All one-slot requests under cursor=0; no network fairness assumption is involved.
pub fn selection1(requests: u1, cursor: u1) -> bool {
  valid_selection(requests, cursor as u32, inbox::select(requests, cursor as u32))
}
// All three-slot requests under cursor<3, including wrap at a non-power-of-two size.
pub fn selection3(requests: u3, cursor: u2) -> bool {
  valid_selection(requests, cursor as u32, inbox::select(requests, cursor as u32))
}
// All eight-slot requests and cursor values.
pub fn selection8(requests: u8, cursor: u3) -> bool {
  valid_selection(requests, cursor as u32, inbox::select(requests, cursor as u32))
}
// A deliberately ignored cursor must produce a counterexample to circular priority.
pub fn wrong_cursor(requests: u3, cursor: u2) -> bool {
  valid_selection(requests, cursor as u32, inbox::select(requests, u32:0))
}
// Expose the actual selector for the preregistered one-input area screen.
pub fn selector1(requests: u1, cursor: u1) -> inbox::Selection<1> { inbox::select(requests, cursor as u32) }
// Expose the actual selector for the preregistered three-input area screen.
pub fn selector3(requests: u3, cursor: u2) -> inbox::Selection<3> { inbox::select(requests, cursor as u32) }
// Expose the actual selector for the preregistered eight-input area screen.
pub fn selector8(requests: u8, cursor: u3) -> inbox::Selection<8> { inbox::select(requests, cursor as u32) }
