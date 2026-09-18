// A call survives both scheduler-private reduction storage and application-owned state.
#[test]
fn reduction_preserves_retained_call_test() {
  let entered = machine_step(initial_machine(), zero!<axis::Frame>(), false, true).machine;
  let request = axis::Frame { header: axis::Header { txid: u8:7, ..axis::pack(Tag::RUN as u8, u32:0).header }, ..axis::pack(Tag::RUN as u8, u32:0) };
  let started = machine_step(entered, request, true, true).machine;
  let open = machine_step(started, zero!<axis::Frame>(), false, true).machine;
  let first = machine_step(open, axis::pack(Tag::VALUE as u8, u32:11), true, true).machine;
  let second = machine_step(first, axis::pack(Tag::VALUE as u8, u32:22), true, true).machine;
  let completed = machine_step(second, zero!<axis::Frame>(), false, true).machine;
  let ready = machine_step(completed, zero!<axis::Frame>(), false, true).machine;
  assert_eq(ready.phase, Phase::READY);
  assert_eq(ready.data.total, u32:33);
  assert_eq(hls_reply::first(ready.replies.slots, true).0, true);
  let released = machine_step(ready, axis::pack(Tag::RELEASE as u8, u32:0), true, true).machine;
  let blocked = machine_step(released, zero!<axis::Frame>(), false, false);
  assert_eq(blocked.machine, released);
  assert_eq(blocked.egress_valid, false);
  let replied = machine_step(blocked.machine, zero!<axis::Frame>(), false, true);
  assert_eq(replied.egress_valid, true);
  assert_eq(replied.egress.frame.header.txid, u8:7);
  assert_eq(replied.egress.frame.payload as u32, u32:33);
  assert_eq(replied.machine.failure, hls_failure::NONE);
  assert_eq(hls_reply::first(replied.machine.replies.slots, true).0, false);
  assert_eq(machine_from_bits(bits_from_machine(shared_machine(replied.machine))), shared_machine(replied.machine));
}
