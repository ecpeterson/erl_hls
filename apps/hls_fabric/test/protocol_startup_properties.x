import protocol_startup;

// Check every finite consumed/eligibility/valid mask without assuming a prefix.
// Only the oldest eligible pending record may be offered, and none means zero.
fn correct<N: u32>(consumed: bits[N], eligible: bits[N], valid: bits[N]) -> bool {
  let head = protocol_startup::head(consumed, eligible, valid);
  let pending = !consumed & eligible & valid;
  let members = (head & !pending) == bits[N]:0;
  let onehot = (head & (head - bits[N]:1)) == bits[N]:0;
  let present = (head == bits[N]:0) == (pending == bits[N]:0);
  let oldest = unroll_for! (i, ok): (u32, bool) in u32:0..N {
    let before = (bits[N]:1 << i) - bits[N]:1;
    ok && ((head & (bits[N]:1 << i)) == bits[N]:0 || (pending & before) == bits[N]:0)
  }(true);
  members && onehot && present && oldest
}
// One startup record, including the no-valid-record dummy representation.
pub fn selection1(c: u1, e: u1, v: u1) -> bool { correct(c,e,v) }
// The connected witness has four distinct startup identities.
pub fn selection4(c: u4, e: u4, v: u4) -> bool { correct(c,e,v) }
// A wider independent finite domain exercises non-prefix consumed/postponed sets.
pub fn selection8(c: u8, e: u8, v: u8) -> bool { correct(c,e,v) }
// Ignoring postponement must yield a counterexample, not a vacuous success.
pub fn wrong_eligibility(c: u4, e: u4, v: u4) -> bool {
  protocol_startup::head(c,e,v) == protocol_startup::head(c,u4:15,v)
}
