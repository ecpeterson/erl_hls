
// Observe the original wire payload and failure code for every legal active kind.
// Keep the other field arbitrary; this optimization changes no field layout.
pub fn phase_probe(four: bool, value: u8) -> (u16, bits[16], bits[128]) {
    let cell = Cell {kind: if four {u8:4} else {u8:2}, value};
    let outcome = enter(Phase::ACTIVE, Phase::ACTIVE, cell);
    (outcome.failure, bits_from_cell(outcome.data), axis::bits_from_frame(entry_effect(outcome.effects, u8:0).frame))
}

// Startup and both terminal kinds must produce the original framed masks.
#[test]
fn legal_phase_masks() {
    let two = enter(Phase::ACTIVE, Phase::ACTIVE, Cell {kind:u8:2, value:u8:17});
    let four = enter(Phase::ACTIVE, Phase::ACTIVE, Cell {kind:u8:4, value:u8:29});
    assert_eq(two.failure, hls_failure::NONE);
    assert_eq(four.failure, hls_failure::NONE);
    assert_eq(entry_effect(two.effects,u8:0).frame, axis::pack(Tag::REPORT as u8,u8:4));
    assert_eq(entry_effect(four.effects,u8:0).frame, axis::pack(Tag::REPORT as u8,u8:16));
}

// The specialization does not relax incoming command validation or explicit failure.
#[test]
fn invalid_commands_still_fail() {
    let cell = Cell {kind:u8:2, value:u8:7};
    let invalid = dispatch(axis::pack(Tag::COMMAND as u8,u8:1),Phase::ACTIVE,cell);
    let explicit = dispatch(axis::pack(Tag::COMMAND as u8,u8:9),Phase::ACTIVE,cell);
    assert_eq(invalid.2,Directive::FAIL);
    assert_eq(hls_failure::failed(invalid.4), true);
    assert_eq(explicit.2,Directive::FAIL);
    assert_eq(hls_failure::failed(explicit.4), true);
}
