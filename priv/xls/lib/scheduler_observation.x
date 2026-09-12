// Diagnostic projection of the metadata entering one shared-scheduler step.
// Payload RAM writes from earlier steps have been accepted; pending producer
// requests do not yet own mailbox capacity. Consumed entries leave on retirement.
// The shell must tie this output's ready high and retain samples independently.
pub fn snapshot<COUNT: u32, DEPTH: u32>(
    occupied: u8[COUNT], order: u8[DEPTH][COUNT], postponed: u1[DEPTH][COUNT],
    in_flight: u1[COUNT], mail: u1[COUNT], entry: u1[COUNT], egress: u1[COUNT],
    egress_busy: u1, phase: u2, completed_effects: u1, completed_slot: u32) -> u24[COUNT] {
  unroll_for! (slot, values): (u32, u24[COUNT]) in u32:0..COUNT {
    let held = unroll_for! (position, count): (u32, u8) in u32:0..DEPTH {
      count + ((position < occupied[slot] as u32 &&
        postponed[slot][order[slot][position] as u32]) as u8)
    }(u8:0);
    let waiting = egress[slot] ||
      (completed_effects && egress_busy && completed_slot == slot);
    let value = u1:1 ++ phase ++ egress_busy ++ waiting ++ entry[slot] ++
      mail[slot] ++ in_flight[slot] ++ held ++ occupied[slot];
    update(values, slot, value)
  }(zero!<u24[COUNT]>())
}

#[test]
fn only_occupied_postponed_entries_count_test() {
  let values = snapshot([u8:2, u8:0], [[u8:2, u8:0, u8:1], [u8:0, u8:1, u8:2]],
    [[true, true, false], [true, true, true]], [true, false], [true, false],
    [false, true], [true, false], true, u2:2, false, u32:0);
  assert_eq(values, [u24:0xdb0102, u24:0xd40000]);
}

#[test]
fn completed_effect_batch_waits_for_previous_batch_credit_test() {
  let queued = snapshot([u8:1, u8:0], [[u8:0], [u8:0]], [[false], [false]],
    [true, false], [false, false], [false, false], [false, false],
    true, u2:2, true, u32:0);
  assert_eq(queued, [u24:0xd90001, u24:0xd00000]);
  let ready = snapshot([u8:1, u8:0], [[u8:0], [u8:0]], [[false], [false]],
    [true, false], [false, false], [false, false], [false, false],
    false, u2:2, true, u32:0);
  assert_eq(ready, [u24:0xc10001, u24:0xc00000]);
}
