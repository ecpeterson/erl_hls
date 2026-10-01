// Activation-local caller ownership. A completed token cannot name a reused transaction.
import axis;

// A live token owns one wire transaction; zero is an unallocated slot.
pub struct Slot { handle: u64, txid: u8 }

// Bounded ownership and a nonwrapping token sequence. Failure is sticky until reset.
pub struct Book<N: u32> { slots: Slot[N], sequence: u64, failure: u32 }

// Finds the first slot with the requested occupancy; found gates the index.
pub fn first<N: u32>(slots: Slot[N], live: bool) -> (bool, u32) {
  for (i, found): (u32, (bool, u32)) in u32:0..N {
    if !found.0 && (slots[i].handle != u64:0) == live { (true, i) } else { found }
  }((false, u32:0))
}

// Exact nonzero-token comparison suppresses stale and repeated completions.
pub fn lookup<N: u32>(slots: Slot[N], handle: u64) -> (bool, u32) {
  for (i, found): (u32, (bool, u32)) in u32:0..N {
    if handle != u64:0 && slots[i].handle == handle { (true, i) } else { found }
  }((false, u32:0))
}

// Service failures use the ERROR tag and one payload word.
pub fn error_frame(txid: u8, code: u32) -> axis::Frame {
  axis::Frame { header: axis::Header { op: u8:1, payload_words: u8:1, txid, flags: u8:0 }, payload: code as bits[96] }
}

// The first sequence is one; no valid handle equals zero.
pub fn initial<N: u32>() -> Book<N> { Book<N> { sequence: u64:1, ..zero!<Book<N>>() } }

// Stable private RAM encoding, independent of application-record codecs.
pub fn to_bits<N: u32>(book: Book<N>) -> bits[N * u32:72 + u32:96] {
  let slots = for (i, packed): (u32, bits[N * u32:72]) in u32:0..N {
    bit_slice_update(packed, i * u32:72, book.slots[i].handle ++ book.slots[i].txid)
  }(zero!<bits[N * u32:72]>());
  book.failure ++ book.sequence ++ slots
}

// Decodes exactly one private RAM row's caller-ownership segment.
pub fn from_bits<N: u32>(raw: bits[N * u32:72 + u32:96]) -> Book<N> {
  let slots = for (i, slots): (u32, Slot[N]) in u32:0..N {
    let row = (raw >> (i * u32:72)) as bits[72];
    update(slots, i, Slot { handle: row[8:72], txid: row[0:8] })
  }(zero!<Slot[N]>());
  Book<N> { slots, sequence: (raw >> (N * u32:72)) as u64,
    failure: (raw >> (N * u32:72 + u32:64)) as u32 }
}

// Allocates before calling the application. A zero returned handle means rejection;
// code 16 is transient fullness, while protocol/exhaustion errors fail the activation.
pub fn admit<N: u32>(book: Book<N>, frame: axis::Frame) -> (Book<N>, u64, u32) {
  let (free, index) = first(book.slots, false);
  let duplicate = for (i, found): (u32, bool) in u32:0..N {
    found || (book.slots[i].handle != u64:0 && book.slots[i].txid == frame.header.txid)
  }(false);
  let error = if duplicate || frame.header.txid == u8:255 { u32:18 }
    else if book.sequence >= u64:0x0100000000000000 { u32:17 }
    else if !free { u32:16 } else { u32:0 };
  let handle = (book.sequence << u32:8) | frame.header.op as u64;
  if error == u32:0 {
    (Book<N> { slots: update(book.slots, index, Slot { handle, txid: frame.header.txid }),
      sequence: book.sequence + u64:1, ..book }, handle, error)
  } else { (Book<N> { failure: if error == u32:16 { u32:0 } else { error }, ..book }, u64:0, error) }
}

// Checks the complete callback before publishing a reply. Unknown handles are ignored.
pub fn complete<N: u32>(book: Book<N>, handle: u64, frame: axis::Frame,
    allowed: bool, failure: u32) -> (Book<N>, axis::Frame, bool) {
  let (live, index) = lookup(book.slots, handle);
  let error = if failure != u32:0 { failure }
    else if live && frame.header.op != u8:0 && !allowed { u32:15 } else { u32:0 };
  let valid = live && frame.header.op != u8:0 && error == u32:0;
  (Book<N> { slots: if valid { update(book.slots, index, zero!<Slot>()) } else { book.slots }, failure: error, ..book },
    axis::Frame { header: axis::Header { txid: book.slots[index].txid, ..frame.header }, ..frame }, valid)
}

// Publishes one failed caller at a time; commit the returned book only with its output.
pub fn drain<N: u32>(book: Book<N>) -> (Book<N>, axis::Frame, bool) {
  let (live, index) = first(book.slots, true);
  (Book<N> { slots: if live { update(book.slots, index, zero!<Slot>()) } else { book.slots }, ..book },
    error_frame(book.slots[index].txid, book.failure), live)
}

// Reusing a physical slot and transaction must not revive its former token.
#[test]
fn allocation_completion_and_codec_test() {
  let request = axis::Frame { header: axis::Header { txid: u8:4, ..axis::pack(u8:3, u32:9).header }, ..axis::pack(u8:3, u32:9) };
  let (first_book, old, error) = admit(initial<u32:2>(), request);
  assert_eq(error, u32:0);
  assert_eq(from_bits<u32:2>(to_bits(first_book)), first_book);
  let (retired, reply, valid) = complete(first_book, old, axis::pack(u8:8, u32:42), true, u32:0);
  assert_eq(valid, true);
  assert_eq(reply.header.txid, u8:4);
  let (second_book, fresh, error) = admit(retired, request);
  assert_eq(error, u32:0);
  assert_eq(old != fresh, true);
  let (unchanged, _, stale_valid) = complete(second_book, old, reply, true, u32:0);
  assert_eq(stale_valid, false);
  assert_eq(unchanged, second_book);
}

// Fullness is transient; a callback fault retains all owners until each failure is emitted.
#[test]
fn full_and_failure_drain_test() {
  let frame = axis::Frame { header: axis::Header { op: u8:3, txid: u8:1, ..zero!<axis::Header>() }, ..zero!<axis::Frame>() };
  let (book, handle, _) = admit(initial<u32:1>(), frame);
  let (unchanged, missing, error) = admit(book, axis::Frame { header: axis::Header { txid: u8:2, ..frame.header }, ..frame });
  assert_eq((unchanged, missing, error), (book, u64:0, u32:16));
  let (failed, _, valid) = complete(book, handle, axis::pack(u8:9, u32:0), false, u32:0);
  assert_eq(valid, false);
  assert_eq(failed.failure, u32:15);
  let (empty, reply, valid) = drain(failed);
  assert_eq((valid, reply.header.txid, reply.payload as u32), (true, u8:1, u32:15));
  assert_eq(first(empty.slots, true).0, false);
}
