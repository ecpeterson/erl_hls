// Immutable startup records form one ordered logical sender per destination.

// Every valid bit names a distinct declared message, even when payloads repeat.
// Select the oldest eligible unconsumed message. Postponement clears eligibility,
// not pending ownership, so later eligible records can pass it without loss.
pub fn head<N: u32>(consumed: bits[N], eligible: bits[N], valid: bits[N]) -> bits[N] {
  const_assert!(N > u32:0 && N <= u32:256);
  let requests = valid & !consumed & eligible;
  requests & (!requests + bits[N]:1)
}
