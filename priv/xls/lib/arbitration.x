// Select the first eligible index at or after cursor, then wrap.
// Empty candidate sets return (false, 0). Selection does not advance cursor.

import std;

pub fn select<CONTENDER_COUNT: u32, INDEX_BITS: u32>(
    pending: u1[CONTENDER_COUNT], cursor: uN[INDEX_BITS]) -> (u1, uN[INDEX_BITS]) {
  const_assert!(CONTENDER_COUNT > u32:0);
  const_assert!(INDEX_BITS > u32:0);
  const_assert!(INDEX_BITS >= std::clog2(CONTENDER_COUNT));
  // Array element zero becomes the least significant request bit. Partition
  // at the cursor without rotating or dynamically indexing the candidate set.
  let requests = rev(pending as uN[CONTENDER_COUNT]);
  let after = requests & (!uN[CONTENDER_COUNT]:0 << cursor);
  let eligible = if or_reduce(after) { after } else { requests };
  // Discard one_hot's extra "no request" bit. An empty set then selects no
  // index bits, so its conventional result is zero even for one contender.
  let grant = one_hot(eligible, true) as uN[CONTENDER_COUNT];
  let indices = unroll_for! (i, values):
      (u32, uN[INDEX_BITS][CONTENDER_COUNT]) in u32:0..CONTENDER_COUNT {
    update(values, i, i as uN[INDEX_BITS])
  }(zero!<uN[INDEX_BITS][CONTENDER_COUNT]>());
  (or_reduce(requests), one_hot_sel(grant, indices))
}

// The caller advances only after a grant/accepted activation. Test the last
// legal index before incrementing: COUNT itself need not fit in INDEX_BITS.
pub fn successor<CONTENDER_COUNT: u32, INDEX_BITS: u32>(
    index: uN[INDEX_BITS]) -> uN[INDEX_BITS] {
  const_assert!(CONTENDER_COUNT > u32:0);
  const_assert!(INDEX_BITS > u32:0);
  const_assert!(INDEX_BITS >= std::clog2(CONTENDER_COUNT));
  if index == (CONTENDER_COUNT - u32:1) as uN[INDEX_BITS] {
    uN[INDEX_BITS]:0
  } else {
    index + uN[INDEX_BITS]:1
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

#[test]
fn narrow_selection_and_successor_test() {
  assert_eq(select([true], u1:0), (true, u1:0));
  assert_eq(select([false], u1:0), (false, u1:0));
  assert_eq(successor<u32:1>(u1:0), u1:0);
  assert_eq(successor<u32:2>(u1:1), u1:0);
  assert_eq(successor<u32:4>(u2:3), u2:0);
  assert_eq(successor<u32:9>(u4:7), u4:8);
  assert_eq(successor<u32:9>(u4:8), u4:0);
  let pending = [false, true, false, false, false, false, false, false, true];
  assert_eq(select(pending, u4:7), (true, u4:8));
  assert_eq(select(pending, u4:8), (true, u4:8));
  assert_eq(select(pending, u4:9), (true, u4:1));
}
