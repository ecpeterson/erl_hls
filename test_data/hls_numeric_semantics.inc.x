// These tests specify where the native XLS arithmetic reference agrees with
// boundary normalization and where that weaker codec law is insufficient.

#[test]
fn wrapping_before_division() {
  let x = u8:255;
  assert_eq((x + u8:1) / u8:2, u8:0);
  assert_eq(wrap_u8(((x as sN[128]) + sN[128]:1) / sN[128]:2), u8:128);
}

#[test]
fn rounding_after_each_operation() {
  let x32 = float32::unflatten(u32:0x4b800000); // 2^24
  assert_eq(float32::flatten(float32::sub(
      float32::add(x32, float32::one(false)), x32)), u32:0);
  let x16 = hfloat16::unflatten(u16:0x6800); // 2^11
  assert_eq(hfloat16::flatten(hfloat16::sub(
      hfloat16::add(x16, hfloat16::one(false)), x16)), u16:0);
  let x64 = float64::unflatten(u64:0x4170000000000000); // 2^24
  assert_eq(float64::flatten(float64::sub(
      float64::add(x64, float64::one(false)), x64)), u64:0x3ff0000000000000);
}

#[test]
fn subnormal_wire_values_are_preserved_but_arithmetic_flushes_them() {
  let tiny16 = hfloat16::unflatten(u16:1);
  let tiny32 = float32::unflatten(u32:1);
  let tiny64 = float64::unflatten(u64:1);
  assert_eq(hfloat16::flatten(tiny16), u16:1);
  assert_eq(float32::flatten(tiny32), u32:1);
  assert_eq(float64::flatten(tiny64), u64:1);
  assert_eq(hfloat16::flatten(hfloat16::add(tiny16, tiny16)), u16:0);
  assert_eq(float32::flatten(float32::add(tiny32, tiny32)), u32:0);
  assert_eq(float64::flatten(float64::add(tiny64, tiny64)), u64:0);
}
