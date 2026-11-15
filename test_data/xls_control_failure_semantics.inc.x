// Observe the selected failure kind as well as successful values. Failed
// values are intentionally masked: the compiler promises no value on failure.
pub fn control_probe(mode: u32, x: u32, y: u32) -> bits[36] {
    let (value, failure) = hls_local_evaluate__3(mode, x, y);
    (hls_failure::kind(failure) as u4) ++ (if failure == hls_failure::NONE { value } else { u32:0 })
}

// Deliver one frame only after the common mailbox reserves capacity; replies
// are accepted immediately. Public-port RTL witnesses exercise actual stalls.
fn admitted_step(machine: Machine, frame: axis::Frame) -> MachineStep {
    let ready = machine_step(machine, zero!<axis::Frame>(), false, true);
    assert_eq(ready.egress_valid, false);
    assert_eq(ready.machine.admission_pending, true);
    machine_step(ready.machine, frame, true, true)
}

// A failed callback cannot publish its proposed state; the first failure is
// retained through later calls, casts and malformed requests until reset.
#[test]
fn terminal_service_history() {
    let initial = machine_step(initial_machine(), zero!<axis::Frame>(), false, true).machine;
    let changed = admitted_step(initial, axis::pack(Tag::CHANGE as u8, u32:99));
    assert_eq(changed.machine.data.value, u32:99);
    assert_eq(changed.egress_valid, false);
    let request = axis::pack(Tag::PROBE as u8,
        bits_from_probe(Probe { mode: u32:8, left: u32:1, right: u32:1 }));
    let failed = admitted_step(changed.machine, request);
    assert_eq(failed.machine.data, changed.machine.data);
    let error = hls_failure::source_error(failed.machine.failure);
    assert_eq(error & u32:0xffff000f, u32:0xc0000004);
    assert_eq(failed.machine.replies.failure, error);
    assert_eq((failed.machine.failure as u16) >> u32:4 != u16:0, true);
    assert_eq(failed.egress_valid, true);
    assert_eq(failed.egress.frame.payload as u32, error);
    let later = admitted_step(failed.machine, axis::pack(Tag::CHANGE as u8, u32:123));
    assert_eq(actor_state(later.machine), actor_state(failed.machine));
    assert_eq(later.egress_valid, true);
    assert_eq(later.egress.frame.payload as u32, error);
    let read = admitted_step(later.machine, axis::pack(Tag::READ as u8, u32:0));
    assert_eq(actor_state(read.machine), actor_state(failed.machine));
    assert_eq(read.egress_valid, true);
    assert_eq(read.egress.frame.payload as u32, error);
    assert_eq(initial_machine().data.value, u32:7);
}

// Rejection occurs before callback selection and does not retire the actor.
#[test]
fn admission_rejection_preserves_service() {
    let initial = machine_step(initial_machine(), zero!<axis::Frame>(), false, true).machine;
    let malformed = admitted_step(initial, axis::pack(Tag::PROBE as u8, u32:0));
    assert_eq(actor_state(malformed.machine), actor_state(initial));
    assert_eq(malformed.egress_valid, true);
    assert_eq(malformed.egress.frame.payload as u32, u32:3);
    let unknown = admitted_step(initial, axis::pack(u8:255, u32:0));
    assert_eq(actor_state(unknown.machine), actor_state(initial));
    assert_eq(unknown.egress_valid, true);
    assert_eq(unknown.egress.frame.payload as u32, u32:1);
    let read = admitted_step(malformed.machine, axis::pack(Tag::READ as u8, u32:0));
    assert_eq(read.egress_valid, true);
    assert_eq(read.egress.frame.header.op, Tag::REPORT as u8);
    assert_eq(read.egress.frame.payload as u32, u32:7);
}
