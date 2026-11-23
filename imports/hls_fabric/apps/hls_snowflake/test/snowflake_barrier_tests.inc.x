
// Blocked output preserves every collected contribution and the old epoch tag.
#[test]
fn completion_is_retained_until_publication() {
    let data = Barrier { source: u8:2, first: u8:12, count: u8:6,
        received: u8:6, seen: u6:63, epoch: u32:0xffffffff,
        kind: u8:4, busy: true };
    let machine = Machine { phase: Phase::PUBLISHING,
        entered_from: Phase::COLLECTING, data, enter_pending: true,
        ..zero!<Machine>() };
    for (_, ()): (u32, ()) in u32:0..u32:8 {
        let held = machine_step(machine, zero!<axis::Frame>(), false, false);
        assert_eq(held.machine, machine);
        assert_eq(held.egress_valid, false);
        assert_eq(held.admission_valid, false);
    } (());
    let released = machine_step(machine, zero!<axis::Frame>(), false, true);
    assert_eq(released.egress_valid, true);
    assert_eq(released.egress.frame.header.op, Tag::SF_DONE as u8);
    assert_eq(sfdone_from_bits(released.egress.frame.payload),
        Sfdone { source: u8:2, epoch: u32:0xffffffff, kind: u8:4, busy: true });
    assert_eq(released.machine.data,
        Barrier { epoch: u32:0, received: u8:0, seen: u6:0, busy: false, ..data });
    assert_eq(released.machine.enter_pending, false);
    let idle = machine_step(released.machine, zero!<axis::Frame>(), false, true);
    assert_eq(idle.egress_valid, false);
}

// Startup readiness obeys the same retained-entry contract as later completion.
#[test]
fn readiness_is_retained_until_publication() {
    let machine = Machine { phase: Phase::COLLECTING,
        entered_from: Phase::STARTING, enter_pending: true,
        data: Barrier { source: u8:3, first: u8:18, count: u8:6,
            ..zero!<Barrier>() }, ..zero!<Machine>() };
    let held = machine_step(machine, zero!<axis::Frame>(), false, false);
    assert_eq(held.machine, machine);
    assert_eq(held.egress_valid, false);
    let released = machine_step(machine, zero!<axis::Frame>(), false, true);
    assert_eq(released.egress_valid, true);
    assert_eq(released.egress.frame.header.op, Tag::SF_READY as u8);
    assert_eq(sfready_from_bits(released.egress.frame.payload), Sfready { source: u8:3 });
    assert_eq(released.machine.enter_pending, false);
}
