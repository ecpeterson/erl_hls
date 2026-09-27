// Exact limb arithmetic. Limb widths describe a hardware decomposition, not a
// numeric format or a promise about register placement.

// Preserve the sum modulo 2^WIDTH as two rows without a carry-propagating add.
fn compress<WIDTH: u32>(a: uN[WIDTH], b: uN[WIDTH], c: uN[WIDTH])
    -> (uN[WIDTH], uN[WIDTH]) {
  (a ^ b ^ c, ((a & b) | (a & c) | (b & c)) << u32:1)
}

// Return lhs*rhs + addend modulo 2^OUT. lhs is signed and rhs is unsigned.
// Positive limb widths expose independent products to the XLS scheduler;
// LEFT=24, RIGHT=17 fit signed 25-by-18 multipliers after zero extension.
pub fn signed_unsigned_add<LEFT: u32, RIGHT: u32, A: u32, B: u32, OUT: u32,
    NA: u32 = {(A + LEFT - u32:1) / LEFT},
    NB: u32 = {(B + RIGHT - u32:1) / RIGHT},
    ROWS: u32 = {NA * NB + u32:1}>
    (lhs: sN[A], rhs: uN[B], addend: uN[OUT]) -> uN[OUT] {
  const_assert!(LEFT > u32:0 && RIGHT > u32:0 && A > u32:0 && B > u32:0 && OUT > u32:0);
  const_assert!(NA == (A + LEFT - u32:1) / LEFT && NB == (B + RIGHT - u32:1) / RIGHT);
  const_assert!(ROWS == NA * NB + u32:1);
  let a = (lhs as sN[NA * LEFT]) as uN[NA * LEFT];
  let b = rhs as uN[NB * RIGHT];
  let rows = for (i, rows): (u32, uN[OUT][ROWS]) in u32:0..NA * NB {
    let ai = i / NB;
    let bi = i % NB;
    let raw = ((a >> (ai * LEFT)) as uN[LEFT]);
    let av = if ai + u32:1 == NA { (raw as sN[LEFT]) as sN[LEFT + u32:1] }
             else { raw as sN[LEFT + u32:1] };
    let bv = ((b >> (bi * RIGHT)) as uN[RIGHT]) as sN[RIGHT + u32:1];
    let product = (av as sN[LEFT + RIGHT + u32:2]) *
                  (bv as sN[LEFT + RIGHT + u32:2]);
    update(rows, i, ((product as sN[OUT]) as uN[OUT]) << (ai * LEFT + bi * RIGHT))
  }(update(zero!<uN[OUT][ROWS]>(), ROWS - u32:1, addend));
  // Each round compacts triples into pairs. All indices/counts are static
  // after unrolling; unused rows and rounds disappear during optimization.
  let (rows, _) = for (_, state): (u32, (uN[OUT][ROWS], u32)) in u32:0..ROWS {
    let (rows, count) = state;
    let groups = count / u32:3;
    let next_count = groups * u32:2 + count % u32:3;
    let next_rows = for (i, result): (u32, uN[OUT][ROWS]) in u32:0..ROWS {
      let value = if i < groups * u32:2 {
        let base = (i / u32:2) * u32:3;
        let (sum, carry) = compress(rows[base], rows[base + u32:1], rows[base + u32:2]);
        if i % u32:2 == u32:0 { sum } else { carry }
      } else if i < next_count { rows[groups * u32:3 + i - groups * u32:2] }
      else { uN[OUT]:0 };
      update(result, i, value)
    }(zero!<uN[OUT][ROWS]>());
    (next_rows, next_count)
  }((rows, ROWS));
  rows[u32:0] + rows[u32:1]
}

// Exercise signed high limbs and truncated results with an independent multiply.
#[quickcheck(test_count=1000)]
fn small_products(a: s7, b: u5, bias: u15) -> bool {
  signed_unsigned_add<u32:3, u32:2>(a, b, bias) ==
    (((a as s15) * (b as s15)) as u15) + bias &&
  signed_unsigned_add<u32:3, u32:2>(a, b, bias as u6) ==
    (((a as s15) * (b as s15) + ((bias as u6) as s15)) as u6)
}

// Include full DSP limb boundaries, negative inputs and a wide arbitrary bias.
#[quickcheck(test_count=1000)]
fn wide_products(a: sN[37], b: uN[38], bias: uN[80]) -> bool {
  signed_unsigned_add<u32:24, u32:17>(a, b, bias) ==
    (((a as sN[80]) * (b as sN[80])) as uN[80]) + bias
}
