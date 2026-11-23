// Exact four-neighbor recurrence stages. Register boundaries are owned by the
// experiment wrapper; no actor machine or publication payload crosses them.
import phi_field;
import staged_reciprocal;
import hls_fixed;

// Widen before accumulation; four s32 neighbors fit in each signed 34-bit sum.
pub fn numerators(field0: s32, field1: s32, sum0: sN[34], sum1: sN[34])
    -> sN[37][2] {
  let a = field0 as sN[37];
  let b = field1 as sN[37];
  [sN[37]:6 * a + sN[37]:2 * b + sum0 as sN[37],
   a + sN[37]:7 * b + sum1 as sN[37]]
}

// Each reciprocal product is independent; neither needs a cascaded multiplier.
pub fn products(n: sN[37][2]) -> sN[80][6][2] {
  [staged_reciprocal::products(n[u32:0]), staged_reciprocal::products(n[u32:1])]
}

// Retain both redundant rows rather than propagating carries through the product.
pub fn reduce(rows: sN[80][6][2]) -> (sN[80], sN[80])[2] {
  [staged_reciprocal::reduce(rows[u32:0]), staged_reciprocal::reduce(rows[u32:1])]
}

// Round both components to nearest, with ties away from zero.
pub fn quotients(rows: (sN[80], sN[80])[2]) -> sN[37][2] {
  [staged_reciprocal::finish(rows[u32:0]), staged_reciprocal::finish(rows[u32:1])]
}

// Preserve the source term's full public u32 domain, then saturate independently.
pub fn saturate(q: sN[37][2], anyon: u32) -> s32[2] {
  [hls_fixed::saturate<u32:32>((q[u32:0] as s64) + ((anyon as s64) << u32:16)),
   hls_fixed::saturate<u32:32>(q[u32:1])]
}

// Use the application's current arithmetic as the unsplit hardware control.
pub fn reference(field0: s32, field1: s32, sum0: sN[34], sum1: sN[34], anyon: u32)
    -> s32[2] {
  phi_field::relax(anyon, [field0, field1], sum0 as s64, sum1 as s64)
}
