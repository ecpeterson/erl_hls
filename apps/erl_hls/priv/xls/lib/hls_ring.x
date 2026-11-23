#![feature(generics)]

// Fixed storage with one cursor. insertion=0 means traversal, otherwise a suffix shift.
// All entry points return a badarg flag where an operation can violate its contract.
pub struct Ring<T: type, N: u32> {
  values: T[N], head: u32, size: u32, position: u32, insertion: u32,
}

// Rewind a completed queue; no unfinished insertion may be discarded.
pub fn rewind<T: type, N: u32>(q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { position: u32:1, ..q }, q.insertion != u32:0)
}
// Exhaustion includes the not-yet-started cursor.
pub fn at_end<T: type, N: u32>(q: Ring<T,N>) -> (bool, bool) {
  (q.position == u32:0 || q.position > q.size, q.insertion != u32:0)
}
// A cursor names a live entry only outside insertion.
fn invalid_current<T: type, N: u32>(q: Ring<T,N>) -> bool {
  q.insertion != u32:0 || q.position == u32:0 || q.position > q.size
}
// Map a one-based logical position to a zero-based physical slot.
fn slot<T: type, N: u32>(q: Ring<T,N>, position: u32) -> u32 {
  const_assert!(N > u32:0 && N < u32:2147483648);
  (q.head + position - u32:1) % N
}
// Advance one live entry, retaining the exhausted tail position.
pub fn next<T: type, N: u32>(q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { position: q.position + u32:1, ..q }, invalid_current(q))
}
// Array access is harmless on rejected input; the failure flag prevents commit.
pub fn current<T: type, N: u32>(q: Ring<T,N>) -> (T, bool) {
  (q.values[slot(q, q.position)], invalid_current(q))
}
// Replace one live entry without changing its position.
pub fn replace<T: type, N: u32>(value: T, q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { values: update(q.values, slot(q, q.position), value), ..q }, invalid_current(q))
}
// Capacity is a static array dimension, not another state word.
pub fn full<T: type, N: u32>(q: Ring<T,N>) -> (bool, bool) {
  (q.size == N, q.insertion != u32:0)
}
// Start shifting the suffix backwards from the tail into its free slot.
pub fn begin_insert<T: type, N: u32>(q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { insertion: q.position, position: q.size, ..q },
   q.insertion != u32:0 || q.size == N || q.position == u32:0 || q.position > q.size + u32:1)
}
// Each false result moves one entry. The final true result installs value.
pub fn insert_step<T: type, N: u32>(value: T, q: Ring<T,N>) -> ((bool, Ring<T,N>), bool) {
  let shift = q.position >= q.insertion;
  let values = if shift {
    update(q.values, slot(q, q.position + u32:1), q.values[slot(q, q.position)])
  } else { update(q.values, slot(q, q.insertion), value) };
  let result = if shift {
    Ring { values, position: q.position - u32:1, ..q }
  } else {
    Ring { values, size: q.size + u32:1, position: q.insertion, insertion: u32:0, ..q }
  };
  ((!shift, result), q.insertion == u32:0)
}
// Empty/full queries are unavailable while the suffix is being moved.
pub fn empty<T: type, N: u32>(q: Ring<T,N>) -> (bool, bool) {
  (q.size == u32:0, q.insertion != u32:0)
}
// Head reads do not depend on the traversal cursor.
pub fn front<T: type, N: u32>(q: Ring<T,N>) -> (T, bool) {
  (q.values[q.head], q.insertion != u32:0 || q.size == u32:0)
}
// Retirement invalidates traversal so a stale position cannot silently name a different entry.
pub fn pop<T: type, N: u32>(q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { head: (q.head + u32:1) % N, size: q.size - u32:1, position: u32:0, ..q },
   q.insertion != u32:0 || q.size == u32:0)
}

// Append into the free tail slot; structural changes invalidate traversal.
pub fn append<T: type, N: u32>(value: T, q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { values: update(q.values, slot(q, q.size + u32:1), value),
          size: q.size + u32:1, position: u32:0, ..q },
   q.insertion != u32:0 || q.size == N)
}
// Tail access is independent of traversal, but unavailable during insertion.
pub fn back<T: type, N: u32>(q: Ring<T,N>) -> (T, bool) {
  (q.values[slot(q, q.size)], q.insertion != u32:0 || q.size == u32:0)
}
// Replacing the tail preserves the cursor, including its exhausted position.
pub fn replace_back<T: type, N: u32>(value: T, q: Ring<T,N>) -> (Ring<T,N>, bool) {
  (Ring { values: update(q.values, slot(q, q.size), value), ..q },
   q.insertion != u32:0 || q.size == u32:0)
}
