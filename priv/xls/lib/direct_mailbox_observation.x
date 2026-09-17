// Committed direct-actor mailbox metadata; payloads are never projected.
// Slots are compacted on consumption, so only their occupied prefix counts.
// A published admission credit reserves one place until its frame is received.
import mailbox;

pub fn snapshot<DEPTH: u32>(
    slots: mailbox::Slot[DEPTH], occupied: u8, reserved: u1) -> u24 {
  let held = unroll_for! (position, count): (u32, u8) in u32:0..DEPTH {
    count + ((position < occupied as u32 && slots[position].postponed) as u8)
  }(u8:0);
  u1:1 ++ u6:0 ++ reserved ++ held ++ occupied
}

#[test]
fn only_occupied_postponed_entries_count_test() {
  let held = mailbox::Slot { postponed: true, ..zero!<mailbox::Slot>() };
  let ready = zero!<mailbox::Slot>();
  assert_eq(snapshot([held, ready, held], u8:2, true), u24:0x810102);
  assert_eq(snapshot([held, held, held], u8:0, true), u24:0x810000);
  assert_eq(snapshot([held, held, held], u8:3, false), u24:0x800303);
  assert_eq(snapshot([ready], u8:0, false), u24:0x800000);
}
