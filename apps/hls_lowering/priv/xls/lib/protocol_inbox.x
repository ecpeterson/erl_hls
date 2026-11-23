// Cross-sender selection only: each request already names its pair's oldest eligible head.

// A zero mask means no request; index is otherwise the chosen physical slot.
pub struct Selection<N: u32> { mask: bits[N], index: u32 }

// Requires cursor < N. Scan once, wrapping at N; advance only on acceptance.
// Fairness is bounded in accepted competing grants, not clocks or source progress.
pub fn select<N: u32>(requests: bits[N], cursor: u32) -> Selection<N> {
  const_assert!(N > u32:0 && N <= u32:256);
  unroll_for! (offset, chosen): (u32, Selection<N>) in u32:0..N {
    let sum = cursor + offset;
    let index = if sum >= N { sum - N } else { sum };
    let mask = bits[N]:1 << index;
    if chosen.mask == bits[N]:0 && (requests & mask) != bits[N]:0 {
      Selection { mask, index }
    } else { chosen }
  }(zero!<Selection<N>>())
}
