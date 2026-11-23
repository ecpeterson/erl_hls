#![feature(generics)]

// A bound tail is a smaller fixed array. XLS cannot carry an empty array value;
// complete-list patterns and discarded tails do not need this projection.
pub fn tail<CUT: u32, T: type, N: u32,
    REST: u32 = {if CUT < N { N-CUT } else { u32:1 }}>(values: T[N]) -> T[REST] {
  const_assert!(CUT < N);
  const_assert!(REST == N-CUT);
  type Tail = T[REST];
  array_slice(values, CUT, zero!<Tail>())
}

#[test]
fn tail_preserves_element_order() {
  assert_eq(tail<u32:1>([s8:-1, s8:2, s8:3]), [s8:2, s8:3]);
  assert_eq(tail<u32:2>([u32:1, u32:2, u32:3]), [u32:3]);
}
