// Concrete sampled-edge witnesses for the bridge's ownership priorities.
// These schedules exercise the public transition, not private decision helpers.
import protocol_bridge as bridge;

// One incoming link, two classes, one outgoing link and one external endpoint.
type State = bridge::State<1,2,1>;
// Native observations are explicit inputs from the old-state composition boundary.
type Inputs = bridge::Inputs<1,2,1,1>;
// Every assertion distinguishes current pins from the state committed on this edge.
type Tick = bridge::Tick<1,2,1,1>;

// The fixture begins attached but not started; attachment alone enables packet traffic.
fn attached() -> State {
  State { attached: true, session: u64:7, ..zero!<State>() }
}

// Credits start unavailable, so each test names the contender it intends to exercise.
fn inputs() -> Inputs {
  Inputs {
    incoming_links: [u16:11], incoming_ready: [true], outgoing_links: [u16:22],
    credits: [bridge::Credit { link: u16:11, slot: u8:0, free: false },
              bridge::Credit { link: u16:11, slot: u8:1, free: false }],
    ..zero!<Inputs>()
  }
}

// One valid incoming packet uses class zero and a visible nonzero payload.
fn data_packet(sequence: u32) -> bridge::Packet {
  bridge::Packet { kind: u8:1, session: u64:7, sequence, link: u16:11,
    slot: u8:0, frame: bits[128]:99 }
}

// ACKs carry no frame and must match the outgoing owner's sequence and class.
fn ack_packet(sequence: u32, slot: u8) -> bridge::Packet {
  bridge::Packet { kind: u8:2, session: u64:7, sequence, link: u16:22,
    slot, frame: bits[128]:0 }
}

// A completed packet is interpreted on the edge after its final receive beat.
fn received(packet: bridge::Packet) -> bridge::Receive {
  bridge::Receive { full: true, header: u32:0x04000008,
    payload: bridge::pack(packet) as bits[320], ..zero!<bridge::Receive>() }
}

// This fixture supplies control legality separately, as the public bridge API requires.
fn command(operation: u8, words: u8, payload: bits[320]) -> bridge::Receive {
  bridge::Receive { full: true, header: ((operation as u32) << u32:24) | words as u32,
    payload, ..zero!<bridge::Receive>() }
}

// The held actor packet is positioned at the eighth and final payload word.
fn final_actor_beat() -> bridge::Transmit {
  bridge::Transmit { full: true, header: u32:0x84000008, payload: bits[256]:123,
    position: u4:9, actor: true, source: u16:0 }
}

// Keep the fixture's route and build identity constant across every sampled edge.
fn tick(state: State, io: Inputs) -> Tick {
  bridge::tick(state, io, bits[256]:42, u16:1, u16:7)
}

// Draining a held frame cannot simultaneously accept another producer's offer.
#[test]
fn final_transmit_beat_does_not_refill() {
  let owner = bridge::Owner { blocked: true, sent: false, sequence: u32:4, slot: u8:1 };
  let state = State { tx: final_actor_beat(), owners: [owner], ..attached() };
  let io = Inputs { ready: true,
    externals: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:88 }], ..inputs() };
  let drain = tick(state, io);
  assert_eq(true, drain.output.valid && drain.output.last);
  assert_eq(true, !drain.output.external_ready[u32:0]);
  assert_eq(true, !drain.state.tx.full && drain.state.owners[u32:0].sent);
  assert_eq(true, drain.state.owners[u32:0].blocked);
  let refill = tick(drain.state, io);
  assert_eq(true, !refill.output.valid && refill.output.external_ready[u32:0]);
  assert_eq(true, refill.state.tx.full && !refill.state.tx.actor);
}

// ACK releases ownership now, but arbitration cannot reuse that owner until the next edge.
#[test]
fn acknowledgement_does_not_bypass_old_reservation() {
  let owner = bridge::Owner { blocked: true, sent: true, sequence: u32:4, slot: u8:1 };
  let state = State { rx: received(ack_packet(u32:4, u8:1)), owners: [owner],
    event_sequence: u32:12, ..attached() };
  let io = Inputs { outgoing: [bridge::Offer { valid: true, slot: u8:1, frame: bits[128]:55 }], ..inputs() };
  let release = tick(state, io);
  assert_eq(true, !release.output.fault && !release.output.outgoing_ready[u32:0]);
  assert_eq(release.state.owners[u32:0], zero!<bridge::Owner>());
  assert_eq(true, !release.state.rx.full && !release.state.tx.full);
  let reserve = tick(release.state, io);
  assert_eq(true, reserve.output.outgoing_ready[u32:0]);
  assert_eq(reserve.state.owners[u32:0], bridge::Owner {
    blocked: true, sent: false, sequence: u32:12, slot: u8:1 });
}

// Even the final physical TX edge cannot make its simultaneous ACK timely.
#[test]
fn acknowledgement_on_final_beat_is_early() {
  let owner = bridge::Owner { blocked: true, sent: false, sequence: u32:4, slot: u8:1 };
  let state = State { rx: received(ack_packet(u32:4, u8:1)), tx: final_actor_beat(),
    owners: [owner], ..attached() };
  let result = tick(state, Inputs { ready: true, ..inputs() });
  assert_eq(true, result.output.fault && result.state.fault);
  assert_eq(true, !result.output.valid && !result.output.active);
  assert_eq(result.state.tx, state.tx);
  assert_eq(result.state.owners, state.owners);
}

// Consuming data frees its credit, but cannot advertise that same credit on this edge.
#[test]
fn consumed_credit_is_reissued_on_a_later_edge() {
  let state = State { rx: received(data_packet(u32:3)), incoming_sequence: [u32:3],
    issued: [true, false], ..attached() };
  let io = Inputs { credits: [bridge::Credit { link: u16:11, slot: u8:0, free: true },
                             bridge::Credit { link: u16:11, slot: u8:1, free: false }], ..inputs() };
  let consume = tick(state, io);
  assert_eq(true, consume.output.incoming_valid[u32:0] && consume.output.active);
  assert_eq(true, !consume.state.started && !consume.state.tx.full);
  assert_eq(consume.state.incoming_sequence, [u32:4]);
  assert_eq(consume.state.issued, [false, false]);
  let reissue = tick(consume.state, io);
  assert_eq(true, reissue.state.tx.full && reissue.state.issued[u32:0]);
  assert_eq(bridge::unpack(reissue.state.tx.payload), bridge::Packet {
    kind: u8:2, session: u64:7, sequence: u32:0, link: u16:11, slot: u8:0, frame: bits[128]:0 });
}

// A credited packet that cannot enter native capture faults rather than waiting like setup.
#[test]
fn unavailable_native_capture_rejects_data() {
  let state = State { rx: received(data_packet(u32:0)), issued: [true, false], ..attached() };
  let io = Inputs { incoming_ready: [false],
    credits: [bridge::Credit { link: u16:11, slot: u8:0, free: true },
              bridge::Credit { link: u16:11, slot: u8:1, free: false }], ..inputs() };
  let result = tick(state, io);
  assert_eq(true, result.output.fault && result.state.fault);
  assert_eq(true, !result.output.incoming_valid[u32:0]);
  assert_eq(result.state.issued, state.issued);
  assert_eq(result.state.incoming_sequence, state.incoming_sequence);
}

// A recognized start reserves response priority even while the child is not ready.
#[test]
fn deferred_start_suppresses_ordinary_grants() {
  let state = State { rx: command(u8:3, u8:3, bits[320]:7), ..attached() };
  let io = Inputs { externals: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:88 }], ..inputs() };
  let wait = tick(state, io);
  assert_eq(true, wait.output.start_valid && !wait.output.fault);
  assert_eq(true, !wait.output.external_ready[u32:0] && !wait.state.tx.full && !wait.state.started);
  assert_eq(wait.state.rx, state.rx);
  let start = tick(wait.state, Inputs { start_ready: true, ..io });
  assert_eq(true, start.output.start_valid && start.state.started && start.state.tx.full);
  assert_eq(true, !start.output.external_ready[u32:0] && !start.state.rx.full);
  assert_eq(start.state.tx.header, u32:0x83000003);
}

// Setup can wait or consume independently of an unrelated held transmit frame.
#[test]
fn setup_does_not_reserve_the_transmit_slot() {
  let state = State { rx: command(u8:2, u8:2, bits[320]:7), ..attached() };
  let io = Inputs { control_legal: true,
    externals: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:88 }], ..inputs() };
  let wait = tick(state, io);
  assert_eq(true, wait.output.control_valid && wait.output.external_ready[u32:0]);
  assert_eq(true, wait.state.tx.full && !wait.output.fault);
  assert_eq(wait.state.rx, state.rx);
  let consume = tick(wait.state, Inputs { control_ready: true, ..io });
  assert_eq(true, consume.output.control_valid && consume.output.valid && !consume.state.rx.full);
  assert_eq(consume.state.tx, wait.state.tx);
}

// Completion and consumption each own an edge; neither can accept the following frame too.
#[test]
fn receive_completion_and_consumption_do_not_overlap() {
  let packet = bridge::pack(data_packet(u32:0));
  let partial = bridge::Receive { stage: u2:2, header: u32:0x04000008,
    payload: packet[0+:bits[224]] as bits[320], seen: u4:7, ..zero!<bridge::Receive>() };
  let state = State { rx: partial, issued: [true, false], ..attached() };
  let io = Inputs { valid: true, last: true, word: packet[224+:u32],
    credits: [bridge::Credit { link: u16:11, slot: u8:0, free: true },
              bridge::Credit { link: u16:11, slot: u8:1, free: false }], ..inputs() };
  let complete = tick(state, io);
  assert_eq(true, complete.output.ready && complete.state.rx.full && !complete.state.rx.bad);
  assert_eq(true, !complete.output.incoming_valid[u32:0]);
  let consume = tick(complete.state, Inputs { word: u32:0x00010007, last: false, ..io });
  assert_eq(true, !consume.output.ready && consume.output.incoming_valid[u32:0]);
  assert_eq(consume.state.rx, zero!<bridge::Receive>());
  assert_eq(consume.state.incoming_sequence, [u32:1]);
}

// Reserved event sequence stops grants only after any already held frame has drained.
#[test]
fn sequence_exhaustion_preserves_the_held_frame_and_delayed_fault() {
  let state = State { event_sequence: u32:0xfffffffe, ..attached() };
  let io = Inputs { outgoing: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:55 }], ..inputs() };
  let reserve = tick(state, io);
  assert_eq(true, reserve.output.outgoing_ready[u32:0]);
  assert_eq(reserve.state.event_sequence, u32:0xffffffff);
  let stalled = tick(reserve.state, io);
  assert_eq(true, !stalled.output.fault && !stalled.state.fault);
  assert_eq(stalled.state.tx, reserve.state.tx);
  let draining = Inputs { ready: true, ..inputs() };
  let drained = for (_, s): (u32, State) in u32:0..u32:10 {
    let result = tick(s, draining);
    assert_eq(true, result.output.valid && !result.output.fault && !result.state.fault);
    result.state
  }(stalled.state);
  assert_eq(true, !drained.tx.full);
  let external = Inputs { externals: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:88 }], ..inputs() };
  let terminal_edge = tick(drained, external);
  assert_eq(true, terminal_edge.state.fault && !terminal_edge.output.fault);
  assert_eq(true, !terminal_edge.output.external_ready[u32:0] && !terminal_edge.state.tx.full);
  let terminal = tick(terminal_edge.state, external);
  assert_eq(true, terminal.output.fault && !terminal.output.active);
}

// External application frames do not consume the credit/data sequence namespace.
#[test]
fn external_grant_leaves_event_sequence_unchanged() {
  let state = State { event_sequence: u32:37, ..attached() };
  let io = Inputs { externals: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:88 }], ..inputs() };
  let result = tick(state, io);
  assert_eq(true, result.output.external_ready[u32:0] && result.state.tx.full);
  assert_eq(result.state.event_sequence, u32:37);
}

// Terminal input masks all simultaneous work; reset takes precedence over termination.
#[test]
fn cancellation_wins_over_receive_and_transmit_work() {
  let state = State { rx: received(data_packet(u32:0)), tx: final_actor_beat(),
    issued: [true, false], ..attached() };
  let io = Inputs { retire: true, ready: true, control_legal: true, control_ready: true,
    start_ready: true, outgoing: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:55 }],
    externals: [bridge::Offer { valid: true, slot: u8:0, frame: bits[128]:88 }],
    credits: [bridge::Credit { link: u16:11, slot: u8:0, free: true },
              bridge::Credit { link: u16:11, slot: u8:1, free: false }], ..inputs() };
  let retire = tick(state, io);
  assert_eq(true, retire.output.fault && retire.state.fault);
  assert_eq(true, !retire.output.ready && !retire.output.valid && !retire.output.active);
  assert_eq(true, !retire.output.incoming_valid[u32:0] && !retire.output.outgoing_ready[u32:0]);
  assert_eq(true, !retire.output.external_ready[u32:0] && !retire.output.control_valid && !retire.output.start_valid);
  assert_eq(retire.state.tx, state.tx);
  assert_eq(retire.state.incoming_sequence, state.incoming_sequence);
  let reset = tick(state, Inputs { reset: true, ..io });
  assert_eq(reset.state, zero!<State>());
  assert_eq(true, !reset.output.fault && !reset.output.ready && !reset.output.valid && !reset.output.active);
  assert_eq(true, !reset.output.incoming_valid[u32:0] && !reset.output.outgoing_ready[u32:0]);
  assert_eq(true, !reset.output.external_ready[u32:0] && !reset.output.control_valid && !reset.output.start_valid);
}
