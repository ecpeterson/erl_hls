// Select the first eligible index at or after cursor, then wrap.
// Empty candidate sets return (false, 0). Selection does not advance cursor.

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
