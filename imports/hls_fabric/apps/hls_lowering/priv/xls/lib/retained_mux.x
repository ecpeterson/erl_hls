#![feature(generics)]
import std;
import arbitration;
// One retained value per input; cursor identifies the next lane considered.
struct State<T: type, COUNT: u32, CURSOR_BITS: u32> {
  cursor: uN[CURSOR_BITS],
  valid: bool[COUNT],
  values: T[COUNT],
}
// Capture empty lanes and publish one round-robin selection without dropping stalled values.
pub proc Mux<T: type, COUNT: u32,
    CURSOR_BITS: u32 = {std::clog2(COUNT) + (COUNT == u32:1) as u32}> {
  incoming: chan<T>[COUNT] in;
  outgoing: chan<T> out;
  // Each input has one independent retained slot and preserves its sender's order.
  config(incoming: chan<T>[COUNT] in, outgoing: chan<T> out) {
    const_assert!(COUNT > u32:0);
    (incoming, outgoing)
  }
  // Reset owns no pending values and starts selection at lane zero.
  init { zero!<State<T, COUNT, CURSOR_BITS>>() }
  // Capture vacant slots, send one selected value, then retire only that slot.
  next(state: State<T, COUNT, CURSOR_BITS>) {
    let (tok, available, values) = unroll_for! (candidate, acc):
        (u32, (token, bool[COUNT], T[COUNT])) in u32:0..COUNT {
      let (tok, incoming, received) = recv_if_non_blocking(
        acc.0, incoming[candidate], !acc.1[candidate], zero!<T>());
      (tok, update(acc.1, candidate, acc.1[candidate] || received),
        update(acc.2, candidate, if received { incoming } else { acc.2[candidate] }))
    }((join(), state.valid, state.values));
    let (selected, index) = arbitration::select(available, state.cursor);
    let _sent = send_if(tok, outgoing, selected, values[index]);
    State<T, COUNT, CURSOR_BITS> {
      cursor: if selected { arbitration::successor<COUNT>(index) } else { state.cursor },
      valid: if selected { update(available, index, false) } else { available },
      values,
    }
  }
}
