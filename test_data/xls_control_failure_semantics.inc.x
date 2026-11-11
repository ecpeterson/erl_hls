// Observe the selected failure kind as well as successful values. Failed
// values are intentionally masked: the compiler promises no value on failure.
pub fn control_probe(mode: u32, x: u32, y: u32) -> bits[36] {
    let (value, failure) = hls_local_evaluate__3(mode, x, y);
    (hls_failure::kind(failure) as u4) ++ (if failure == hls_failure::NONE { value } else { u32:0 })
}

// A failed callback cannot publish its proposed state; the first failure is
// retained through later calls, casts and malformed requests until reset.
#[test]
fn terminal_service_history() {
    let initial = initial_service_state();
    let changed = service_step(initial, axis::pack(Tag::CHANGE as u8, u32:99));
    assert_eq(changed.state.data.value, u32:99);
    assert_eq(changed.response.header.op, Tag::NONE as u8);
    let request = axis::pack(Tag::PROBE as u8,
        bits_from_probe(Probe { mode: u32:8, left: u32:1, right: u32:1 }));
    let failed = service_step(changed.state, request);
    assert_eq(failed.state.data, changed.state.data);
    assert_eq(failed.state.failure & u32:0xffff000f, u32:0xc0000004);
    assert_eq((failed.state.failure as u16) >> u32:4 != u16:0, true);
    assert_eq(failed.response.payload as u32, failed.state.failure);
    let later = service_step(failed.state, axis::pack(Tag::CHANGE as u8, u32:123));
    assert_eq(later.state, failed.state);
    assert_eq(later.response.payload as u32, failed.state.failure);
    let read = service_step(later.state, axis::pack(Tag::READ as u8, u32:0));
    assert_eq(read.state, failed.state);
    assert_eq(read.response.payload as u32, failed.state.failure);
    assert_eq(initial_service_state().data.value, u32:7);
}

// Rejection occurs before callback selection and does not retire the actor.
#[test]
fn admission_rejection_preserves_service() {
    let initial = initial_service_state();
    let malformed = service_step(initial, axis::pack(Tag::PROBE as u8, u32:0));
    assert_eq(malformed.state, initial);
    assert_eq(malformed.response.payload as u32, u32:3);
    let unknown = service_step(initial, axis::pack(u8:255, u32:0));
    assert_eq(unknown.state, initial);
    assert_eq(unknown.response.payload as u32, u32:1);
    let read = service_step(malformed.state, axis::pack(Tag::READ as u8, u32:0));
    assert_eq(read.response.header.op, Tag::REPORT as u8);
    assert_eq(read.response.payload as u32, u32:7);
}
