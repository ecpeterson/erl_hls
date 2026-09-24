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

// Divide by a positive static integer, rounding to nearest with ties away from
// zero. Includes the most negative input and divisors wider than the input.
pub fn round_ratio<DENOMINATOR: u32, WIDTH: u32,
    MAG: u32 = {if WIDTH > u32:32 { WIDTH + u32:1 } else { u32:33 }}>
    (numerator: sN[WIDTH]) -> sN[WIDTH] {
  const_assert!(DENOMINATOR > u32:0 && WIDTH > u32:0 && MAG > WIDTH && MAG >= u32:33);
  if (DENOMINATOR & (DENOMINATOR - u32:1)) == u32:0 {
    let widened = numerator as sN[MAG];
    let half = (DENOMINATOR / u32:2) as sN[MAG];
    let biased = if numerator < sN[WIDTH]:0 { widened - half } else { widened + half };
    (biased / (DENOMINATOR as sN[MAG])) as sN[WIDTH]
  } else {
    const SHIFT = WIDTH + u32:32 - clz(DENOMINATOR - u32:1);
    const PRODUCT_BITS = WIDTH + SHIFT + u32:2;
    const RECIPROCAL = ((uN[SHIFT + u32:1]:1 << SHIFT) +
        (DENOMINATOR as uN[SHIFT + u32:1]) - uN[SHIFT + u32:1]:1) /
        (DENOMINATOR as uN[SHIFT + u32:1]);
    // The reciprocal's positive error times any input is strictly < 1/(2*D).
    // Non-ties cannot cross a half integer; negative ties move below it.
    // Power-of-two divisors have zero reciprocal error, hence the branch above.
    let product = (numerator as sN[PRODUCT_BITS]) * (RECIPROCAL as sN[PRODUCT_BITS]);
    ((product + (sN[PRODUCT_BITS]:1 << (SHIFT - u32:1))) >> SHIFT) as sN[WIDTH]
  }
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

// Independent magnitude reference with enough space for any u32 divisor.
fn reference_round<D: u32, W: u32>(n: sN[W]) -> sN[W] {
  let wide = n as sN[W + u32:33];
  let magnitude = (if wide < sN[W + u32:33]:0 { -wide } else { wide }) as uN[W + u32:33];
  let q = ((magnitude + ((D / u32:2) as uN[W + u32:33])) /
           (D as uN[W + u32:33])) as sN[W + u32:33];
  (if wide < sN[W + u32:33]:0 { -q } else { q }) as sN[W]
}

// Exhaust every eight-bit input for one compile-time denominator.
fn check_small<D: u32>() {
  for (raw, _): (u32, ()) in u32:0..u32:256 {
    let n = raw as s8;
    assert_eq(round_ratio<D>(n), reference_round<D>(n));
  }(())
}

// Check extrema and zero across the widening boundary and beyond machine width.
fn check_extremes<D: u32, W: u32>() {
  let minimum = (uN[W]:1 << (W - u32:1)) as sN[W];
  let maximum = !minimum;
  for (n, _): (sN[W], ()) in [minimum, minimum + (uN[W]:1 as sN[W]),
                              sN[W]:0, maximum - (uN[W]:1 as sN[W]), maximum] {
    assert_eq(round_ratio<D>(n), reference_round<D>(n));
  }(())
}

// Odd/even divisors, powers of two, and divisors exceeding the numerator width.
#[test]
fn rounding_denominators_test() {
  check_small<u32:1>();
  check_small<u32:2>();
  check_small<u32:3>();
  check_small<u32:4>();
  check_small<u32:5>();
  check_small<u32:7>();
  check_small<u32:10>();
  check_small<u32:12>();
  check_small<u32:13>();
  check_small<u32:1000>();
  check_small<u32:2147483648>();
  check_small<u32:4294967295>();
  check_extremes<u32:1, u32:1>();
  check_extremes<u32:2, u32:1>();
  check_extremes<u32:12, u32:31>();
  check_extremes<u32:4294967295, u32:31>();
  check_extremes<u32:4294967295, u32:32>();
  check_extremes<u32:4294967295, u32:33>();
  check_extremes<u32:4294967295, u32:129>();
  check_extremes<u32:12, u32:37>();
  check_extremes<u32:3, u32:129>();
  check_extremes<u32:13, u32:129>();
}

// Exercise the recurrence width against the independent magnitude definition.
#[quickcheck(test_count=10000)]
fn recurrence_rounding_matches_magnitude(n: sN[37]) -> bool {
  round_ratio<u32:12>(n) == reference_round<u32:12>(n) &&
  round_ratio<u32:3>(n) == reference_round<u32:3>(n) &&
  round_ratio<u32:13>(n) == reference_round<u32:13>(n) &&
  round_ratio<u32:4294967295>(n) == reference_round<u32:4294967295>(n)
}
