
#[test]
fn configured_actor_matches_beam() {
  let machine = initial_machine();
  assert_eq(MAILBOX_CAPACITY, EXPECTED_CAPACITY);
  assert_eq(bits_from_cell(machine.data) as u64, EXPECTED_INITIAL);
  assert_eq(hls_failure::failed(machine.failure), u1:0);
  for (i, ()): (u32, ()) in u32:0..array_size(INPUTS) {
    let message = Message { value: INPUTS[i] as Word };
    let packed = bits_from_message(message);
    assert_eq(message_from_bits(packed), message);
    let frame = axis::Frame {
      header: axis::Header { op: Tag::MESSAGE as u8, ..zero!<axis::Header>() },
      payload: packed as bits[96],
    };
    let (phase, cell, directive, repeat_phase, failure) = dispatch(frame, Phase::WAITING, machine.data);
    assert_eq(failure, hls_failure::NONE);
    assert_eq(phase, Phase::WAITING);
    assert_eq(bits_from_cell(cell) as u64, EXPECTED[i]);
    assert_eq(directive, Directive::CONSUME);
    assert_eq(repeat_phase, u1:0);
  } (());
}
