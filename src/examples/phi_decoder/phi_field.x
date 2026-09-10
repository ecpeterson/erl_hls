// Two-layer Q15.16 fields, paired with phi_field.erl's BEAM implementation.
import hls_fixed;
import hls_vec;

pub type Scalar = s32;
pub type Field = Scalar[2];

// At most four scalar contributions fit in the diffusion accumulator.
pub fn accumulate(sum: s64, value: Scalar) -> s64 { sum + (value as s64) }

pub fn relax_center(anyon: u32, phi0: Scalar, phi1: Scalar, neighbor_sum: s64) -> Scalar {
  let numerator = hls_vec::dot<u32:37>([phi0, phi1], s32[2]:[6, 2]) +
    (neighbor_sum as sN[37]);
  hls_fixed::saturate<u32:32>(
    ((anyon as s64) << u32:16) + (hls_fixed::round_ratio<u32:12>(numerator) as s64))
}

pub fn relax_bulk(phi0: Scalar, phi1: Scalar, neighbor_sum: s64) -> Scalar {
  let numerator = hls_vec::dot<u32:37>([phi0, phi1], s32[2]:[1, 7]) +
    (neighbor_sum as sN[37]);
  hls_fixed::saturate<u32:32>(hls_fixed::round_ratio<u32:12>(numerator))
}

pub fn relax(anyon: u32, field: Field, sum0: s64, sum1: s64) -> Field {
  [relax_center(anyon, field[u32:0], field[u32:1], sum0),
   relax_bulk(field[u32:0], field[u32:1], sum1)]
}

#[test]
fn accumulator_preserves_four_extreme_neighbors_test() {
  let maximum = s32:2147483647;
  let minimum = s32:-2147483648;
  let high = for (_, sum): (u32, s64) in u32:0..u32:4 {
    accumulate(sum, maximum)
  }(s64:0);
  let low = for (_, sum): (u32, s64) in u32:0..u32:4 {
    accumulate(sum, minimum)
  }(s64:0);
  assert_eq(high, s64:8589934588);
  assert_eq(low, s64:-8589934592);
  assert_eq(relax_center(u32:1, maximum, maximum, high), maximum);
  assert_eq(relax_bulk(minimum, minimum, low), minimum);
}
fn reference_round(numerator: s64, denominator: s64, half: s64) -> s64 {
  if numerator < s64:0 {
    (numerator - half) / denominator
  } else {
    (numerator + half) / denominator
  }
}

fn reference_saturate(value: s64) -> s32 {
  if value > s64:2147483647 {
    s32:2147483647
  } else if value < s64:-2147483648 {
    s32:-2147483648
  } else {
    value as s32
  }
}

fn neighbor_sum(a: s32, b: s32, c: s32, d: s32) -> s64 {
  (a as s64) + (b as s64) + (c as s64) + (d as s64)
}

#[quickcheck]
fn center_matches_wide_reference(
    anyon: u1,
    phi0: s32,
    phi1: s32,
    north: s32,
    east: s32,
    west: s32,
    south: s32
) -> bool {
  let sum = neighbor_sum(north, east, west, south);
  let numerator =
    (phi0 as s64) * s64:6 + (phi1 as s64) * s64:2 + sum;
  let expected = reference_saturate(
    ((anyon as s64) << u32:16) +
      reference_round(numerator, s64:12, s64:6));
  relax_center(anyon as u32, phi0, phi1, sum) == expected
}

#[quickcheck]
fn bulk_matches_wide_reference(
    phi0: s32,
    phi1: s32,
    north: s32,
    east: s32,
    west: s32,
    south: s32
) -> bool {
  let sum = neighbor_sum(north, east, west, south);
  let numerator =
    (phi0 as s64) + (phi1 as s64) * s64:7 + sum;
  let expected = reference_saturate(
    reference_round(numerator, s64:12, s64:6));
  relax_bulk(phi0, phi1, sum) == expected
}
