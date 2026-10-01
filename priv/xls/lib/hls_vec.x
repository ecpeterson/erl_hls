// Widen before multiplying and accumulating. The caller chooses a width that
// contains every intermediate sum; element widths and vector size are inferred.
pub fn dot<OUT: u32, LEFT: u32, RIGHT: u32, COUNT: u32>
    (left: sN[LEFT][COUNT], right: sN[RIGHT][COUNT]) -> sN[OUT] {
  const_assert!(OUT >= LEFT && OUT >= RIGHT);
  unroll_for! (index, sum): (u32, sN[OUT]) in u32:0..COUNT {
    sum + (left[index] as sN[OUT]) * (right[index] as sN[OUT])
  }(sN[OUT]:0)
}

#[test]
fn widened_dot_product_test() {
  assert_eq(dot<u32:32>(s8[3]:[127, -128, 10], s16[3]:[2, -3, 4]), s32:678);
  assert_eq(dot<u32:16>(s8[1]:[-128], s8[1]:[-1]), s16:128);
}
