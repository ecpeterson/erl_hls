// Output pressure must not block a non-replying call or commit a reply-producing call early.
#[test]
fn call_state_and_reply_commit_together_test() {
  let entered = machine_step(initial_machine(), zero!<axis::Frame>(), false, true).machine;
  let wait = axis::Frame { header: axis::Header { txid: u8:1, ..axis::pack(Tag::WAIT as u8, u32:11).header }, ..axis::pack(Tag::WAIT as u8, u32:11) };
  let retained = machine_step(entered, wait, true, false);
  assert_eq(retained.machine.data.count, u32:1);
  assert_eq(hls_reply::first(retained.machine.replies.slots, true).0, true);
  let read = axis::Frame { header: axis::Header { txid: u8:2, ..axis::pack(Tag::READ as u8, u32:0).header }, ..axis::pack(Tag::READ as u8, u32:0) };
  let blocked = machine_step(retained.machine, read, true, false);
  assert_eq(blocked.egress_valid, false);
  assert_eq(blocked.machine.replies, retained.machine.replies);
  assert_eq(blocked.machine.occupied, u8:1);
  let replied = machine_step(blocked.machine, zero!<axis::Frame>(), false, true);
  assert_eq(replied.egress_valid, true);
  assert_eq(replied.egress.frame.header.txid, u8:2);
  assert_eq(replied.machine.occupied, u8:0);
}

// Invalid reply contracts must preserve application data and leave callers available for failure drain.
#[test]
fn bad_reply_does_not_commit_data_test() {
  let entered = shared_machine_enter(initial_shared_machine(), true).machine;
  let wait = axis::Frame { header: axis::Header { txid: u8:1, ..axis::pack(Tag::WAIT as u8, u32:11).header }, ..axis::pack(Tag::WAIT as u8, u32:11) };
  let retained = shared_machine_dispatch(entered, wait, true).machine;
  let failure = shared_machine_dispatch(retained, axis::pack(Tag::EXPLODE as u8, u32:1), true);
  assert_eq(failure.machine.data, retained.data);
  assert_eq(failure.machine.replies.failure, u32:15);
  assert_eq(failure.reply_valid, false);
  assert_eq(hls_reply::first(failure.machine.replies.slots, true).0, true);
}
