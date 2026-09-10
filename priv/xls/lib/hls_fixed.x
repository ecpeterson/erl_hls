// Operations on raw signed fixed-point integers. Fractional scale is unchanged
// by these operations; the caller owns the format's fractional-bit count.

pub fn saturate<OUT: u32, IN: u32>(value: sN[IN]) -> sN[OUT] {
  const_assert!(OUT > u32:0 && IN >= OUT);
  let maximum = ((uN[IN]:1 << (OUT - u32:1)) - uN[IN]:1) as sN[IN];
  let minimum = -maximum - sN[IN]:1;
  if value > maximum { maximum as sN[OUT] }
  else if value < minimum { minimum as sN[OUT] }
  else { value as sN[OUT] }
}

// Positive, static integer divisor. Unsigned magnitude handles the most
// negative signed input. The extra bit makes magnitude + half safe for every
// input, including formats narrower than the divisor.
pub fn round_ratio<DENOMINATOR: u32, WIDTH: u32,
    MAG: u32 = {if WIDTH > u32:32 { WIDTH + u32:1 } else { u32:33 }}>
    (numerator: sN[WIDTH]) -> sN[WIDTH] {
  const_assert!(DENOMINATOR > u32:0 && WIDTH > u32:0 && MAG > WIDTH && MAG >= u32:33);
  let negative = numerator < sN[WIDTH]:0;
  let widened = numerator as sN[MAG];
  let magnitude = (if negative { -widened } else { widened }) as uN[MAG];
  let rounded = magnitude + ((DENOMINATOR / u32:2) as uN[MAG]);
  let quotient = (rounded / (DENOMINATOR as uN[MAG])) as sN[MAG];
  (if negative { -quotient } else { quotient }) as sN[WIDTH]
}

#[test]
fn saturation_and_signed_rounding_test() {
  assert_eq(saturate<u32:8>(s32:128), s8:127);
  assert_eq(saturate<u32:8>(s32:-129), s8:-128);
  assert_eq(saturate<u32:8>(s8:-128), s8:-128);
  assert_eq(round_ratio<u32:12>(s8:-5), s8:0);
  assert_eq(round_ratio<u32:12>(s8:-6), s8:-1);
  assert_eq(round_ratio<u32:12>(s8:6), s8:1);
  assert_eq(round_ratio<u32:1>(s8:-128), s8:-128);
  assert_eq(round_ratio<u32:2>(s8:-128), s8:-64);
  assert_eq(round_ratio<u32:1000>(s8:-128), s8:0);
}

#[test]
fn all_small_signed_inputs_match_wide_division_test() {
  for (raw, _): (u32, ()) in u32:0..u32:256 {
    let value = (raw as s8) as s32;
    let reference = if value < s32:0 { (value - s32:6) / s32:12 }
                    else { (value + s32:6) / s32:12 };
    assert_eq(round_ratio<u32:12>(value as s8), reference as s8);
  }(())
}
