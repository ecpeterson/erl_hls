// Appended to the generated fixture by tools/test_reduction_dslx.sh so these
// tests can inspect its private canonical-machine helpers without making them
// part of the generated public API.

fn reduction_test_count(key: u32, value: u32) -> axis::Frame {
  axis::pack(
    Tag::COUNT_VALUE as u8,
    bits_from_countvalue(Countvalue { key, value }))
}

fn reduction_test_member(
    key: u32, member: u32, value: u32) -> axis::Frame {
  axis::pack(
    Tag::MEMBER_VALUE as u8,
    bits_from_membervalue(Membervalue { key, member, value }))
}

fn reduction_test_shared(
    machine: SharedMachine,
    frame: axis::Frame,
    internal: u1,
    received: u1) -> SharedExecutorResult {
  shared_execute(SharedExecutorRequest {
    slot: u32:0,
    machine: bits_from_machine(machine),
    frame,
    internal,
    received,
    mailbox_index: u8:0,
    order_index: u8:0,
    egress_ready: u1:1,
  })
}

#[test]
fn reduction_direct_machine_test() {
  let idle = zero!<axis::Frame>();
  let entered = machine_step(
    initial_machine(), idle, u1:0, u1:1).machine;
  assert_eq(entered.data.entries, u8:1);
  assert_eq(entered.reduction.status, ReductionStatus::OPEN);
  assert_eq(entered.reduction.remaining, ReductionRemaining:2);

  // A contribution for another key waits in the ordinary mailbox.
  let mismatched = machine_step(
    entered, reduction_test_count(u32:1, u32:99), u1:1, u1:1).machine;
  assert_eq(hls_failure::failed(mismatched.failure), u1:0);
  assert_eq(mismatched.occupied, u8:1);
  assert_eq(mismatched.slots[0].postponed, u1:1);
  assert_eq(mismatched.reduction.remaining, ReductionRemaining:2);

  let first = machine_step(
    entered, reduction_test_count(u32:0, u32:11), u1:1, u1:1).machine;
  assert_eq(first.reduction.accumulator,
    Sum { value: u32:11, contributions: u8:1 });
  let credited = machine_step(first, idle, u1:0, u1:1).machine;
  let complete = machine_step(
    credited, reduction_test_count(u32:0, u32:13), u1:1, u1:1).machine;
  assert_eq(complete.reduction.status, ReductionStatus::COMPLETE);
  assert_eq(complete.reduction.accumulator,
    Sum { value: u32:24, contributions: u8:2 });

  let transitioned = machine_step(
    complete, idle, u1:0, u1:1).machine;
  assert_eq(transitioned.phase, Phase::COLLECTING_MEMBERS);
  assert_eq(transitioned.data.value, u32:24);
  let member_entry = machine_step(
    transitioned, idle, u1:0, u1:1).machine;
  let one_member = machine_step(
    member_entry,
    reduction_test_member(u32:0, u32:7, u32:5),
    u1:1,
    u1:1).machine;
  let member_credit = machine_step(
    one_member, idle, u1:0, u1:1).machine;
  let duplicate = machine_step(
    member_credit,
    reduction_test_member(u32:0, u32:7, u32:8),
    u1:1,
    u1:1).machine;
  assert_eq(hls_failure::failed(duplicate.failure), u1:1);
}

#[test]
fn reduction_shared_machine_test() {
  let idle = zero!<axis::Frame>();
  let entered_result = reduction_test_shared(
    initial_shared_machine(), idle, u1:0, u1:0);
  let entered = machine_from_bits(entered_result.machine);
  assert_eq(bits_from_machine(entered), entered_result.machine);

  let first = machine_from_bits(reduction_test_shared(
    entered,
    reduction_test_count(u32:0, u32:17),
    u1:0,
    u1:1).machine);
  let counted = machine_from_bits(reduction_test_shared(
    first,
    reduction_test_count(u32:0, u32:19),
    u1:0,
    u1:1).machine);
  assert_eq(counted.reduction.status, ReductionStatus::COMPLETE);
  let members = machine_from_bits(reduction_test_shared(
    counted, idle, u1:1, u1:0).machine);
  // Shared execution completes the old reduction and performs the
  // effect-free entry into the next phase in one activation.
  assert_eq(members.phase, Phase::COLLECTING_MEMBERS);
  assert_eq(members.data.value, u32:36);
  assert_eq(members.reduction.status, ReductionStatus::OPEN);
  assert_eq(members.reduction.site, ReductionSite::COLLECTING_MEMBERS);

  let member_9 = machine_from_bits(reduction_test_shared(
    members,
    reduction_test_member(u32:0, u32:9, u32:2),
    u1:0,
    u1:1).machine);
  let member_2 = machine_from_bits(reduction_test_shared(
    member_9,
    reduction_test_member(u32:0, u32:2, u32:3),
    u1:0,
    u1:1).machine);
  let member_7 = machine_from_bits(reduction_test_shared(
    member_2,
    reduction_test_member(u32:0, u32:7, u32:5),
    u1:0,
    u1:1).machine);
  assert_eq(member_7.reduction.status, ReductionStatus::COMPLETE);
  assert_eq(member_7.reduction.seen, ReductionMembers:0b111);
  assert_eq(member_7.reduction.accumulator,
    Sum { value: u32:10, contributions: u8:3 });

  let restarted = machine_from_bits(reduction_test_shared(
    member_7, idle, u1:1, u1:0).machine);
  assert_eq(restarted.phase, Phase::COUNTING);
  assert_eq(restarted.data.value, u32:10);
  assert_eq(restarted.data.entries, u8:2);
  assert_eq(restarted.reduction.status, ReductionStatus::OPEN);
}

#[test]
fn reduction_shared_priority_and_layout_test() {
  let scheduler = SharedState<u32:3, u32:1> {
    internal_candidates: [u1:0, u1:1, u1:0],
    mail_candidates: [u1:1, u1:1, u1:0],
    entry_probes: [u1:0, u1:1, u1:0],
    egress_waiters: [u1:0, u1:1, u1:0],
    egress_busy: u1:1,
    ..zero!<SharedState<u32:3, u32:1>>()
  };
  assert_eq(
    reduction_ready_selection(
      scheduler, u32:1, [u1:0, u1:0, u1:0]),
    (u1:1, u32:1));
  assert_eq(
    reduction_ready_selection(
      scheduler, u32:0, [u1:0, u1:0, u1:0]),
    (u1:1, u32:0));

  let reduction = ReductionState {
    status: ReductionStatus::COMPLETE,
    site: ReductionSite::COLLECTING_MEMBERS,
    key: u32:0x89abcdef,
    remaining: ReductionRemaining:2,
    seen: ReductionMembers:0b101,
    accumulator: Sum {
      value: u32:0x12345678,
      contributions: u8:0x34,
    },
  };
  let packed = bits_from_reduction_state(reduction);
  assert_eq(packed[0:2], u2:2);
  assert_eq(packed[2:3], u1:1);
  assert_eq(packed[3:35], u32:0x89abcdef);
  assert_eq(packed[35:37], u2:2);
  assert_eq(packed[37:40], u3:0b101);
  assert_eq(packed[40:72], u32:0x12345678);
  assert_eq(packed[72:80], u8:0x34);
  assert_eq(reduction_state_from_bits(packed), reduction);

  let completed = SharedMachine {
    reduction,
    ..zero!<SharedMachine>()
  };
  let retired = retire_reduction_actor(
    zero!<SharedState<u32:3, u32:1>>(),
    u1:1,
    u32:2,
    completed);
  assert_eq(retired.internal_candidates, [u1:0, u1:0, u1:1]);
  let cleared = retire_reduction_actor(
    retired,
    u1:1,
    u32:2,
    SharedMachine { failure: hls_failure::REDUCTION_PROTOCOL, ..completed });
  assert_eq(cleared.internal_candidates, [u1:0, u1:0, u1:0]);
}

// Compile-only smoke top: instantiating SharedService exercises its complete
// parameterized proc/channel surface in addition to the pure helpers above.
pub proc ReductionSharedCompileTop {
  config() {
    let (request_p, request_c) =
      chan<ScheduledRequest, u32:1>[u32:1]("request");
    let (startup_p, startup_c) =
      chan<ScheduledRequest, u32:1>("startup");
    let (egress_p, egress_c) =
      chan<ScheduledEffects, u32:1>("egress");
    let (machine_read_req_p, machine_read_req_c) =
      chan<MachineRamReadReq, u32:1>("machine_read_req");
    let (machine_read_resp_p, machine_read_resp_c) =
      chan<MachineRamReadResp, u32:1>("machine_read_resp");
    let (machine_write_req_p, machine_write_req_c) =
      chan<MachineRamWriteReq, u32:1>("machine_write_req");
    let (machine_write_resp_p, machine_write_resp_c) =
      chan<MachineRamWriteResp, u32:1>("machine_write_resp");
    let (mailbox_read_req_p, mailbox_read_req_c) =
      chan<MailboxRamReadReq, u32:1>("mailbox_read_req");
    let (mailbox_read_resp_p, mailbox_read_resp_c) =
      chan<MailboxRamReadResp, u32:1>("mailbox_read_resp");
    let (mailbox_write_req_p, mailbox_write_req_c) =
      chan<MailboxRamWriteReq, u32:1>("mailbox_write_req");
    let (mailbox_write_resp_p, mailbox_write_resp_c) =
      chan<MailboxRamWriteResp, u32:1>("mailbox_write_resp");
    spawn SharedService<u32:2, u32:1, u32:0, u32:0>(
      request_c,
      startup_c,
      egress_p,
      machine_read_req_p,
      machine_read_resp_c,
      machine_write_req_p,
      machine_write_resp_c,
      mailbox_read_req_p,
      mailbox_read_resp_c,
      mailbox_write_req_p,
      mailbox_write_resp_c);
    ()
  }

  init { () }
  next(state: ()) { state }
}
