// Appended to the aggregate-only generated fixture by
// tools/test_reduction_dslx.sh.

fn aggregate_test_count(key: u32, value: u32) -> axis::Frame {
  axis::pack(
    Tag::COUNT_VALUE as u8,
    bits_from_countvalue(Countvalue { key, value }))
}

fn aggregate_test_member(
    key: u32, member: u32, value: u32) -> axis::Frame {
  axis::pack(
    Tag::MEMBER_VALUE as u8,
    bits_from_membervalue(Membervalue { key, member, value }))
}

#[test]
fn reduction_count_aggregate_test() {
  let aggregate = reduction_aggregate_batch<u32:2>([
    aggregate_test_count(u32:7, u32:11),
    aggregate_test_count(u32:7, u32:13),
  ]);
  assert_eq(aggregate.valid, u1:1);
  assert_eq(aggregate.failed, u1:0);
  assert_eq(aggregate.site, ReductionSite::COUNTING as uN[1]);
  assert_eq(aggregate.key, u32:7);
  assert_eq(aggregate.count, ReductionRemaining:2);
  assert_eq(aggregate.seen, zero!<ReductionMembers>());
  assert_eq(aggregate.accumulator,
    Sum { value: u32:24, contributions: u8:2 });

  let opened = reduction_open_site(
    ReductionSite::COUNTING,
    u32:7,
    zero!<Sum>());
  let applied = reduction_apply_complete_aggregate(opened, aggregate);
  assert_eq(applied.outcome, ReductionOutcome::COMPLETE);
  assert_eq(applied.state.status, ReductionStatus::COMPLETE);
  assert_eq(applied.state.remaining, ReductionRemaining:0);
  assert_eq(applied.state.accumulator,
    Sum { value: u32:24, contributions: u8:2 });
}

#[test]
fn reduction_member_aggregate_test() {
  let aggregate = reduction_aggregate_batch<u32:3>([
    aggregate_test_member(u32:9, u32:7, u32:2),
    aggregate_test_member(u32:9, u32:9, u32:3),
    aggregate_test_member(u32:9, u32:2, u32:5),
  ]);
  assert_eq(aggregate.failed, u1:0);
  assert_eq(aggregate.count, ReductionRemaining:3);
  assert_eq(aggregate.seen, ReductionMembers:0b111);
  let opened = reduction_open_site(
    ReductionSite::COLLECTING_MEMBERS,
    u32:9,
    zero!<Sum>());
  let applied = reduction_apply_complete_aggregate(opened, aggregate);
  assert_eq(applied.outcome, ReductionOutcome::COMPLETE);
  assert_eq(applied.state.accumulator,
    Sum { value: u32:10, contributions: u8:3 });
}

#[test]
fn malformed_reduction_aggregates_fail_closed_test() {
  let mismatched = reduction_aggregate_batch<u32:2>([
    aggregate_test_count(u32:1, u32:4),
    aggregate_test_count(u32:2, u32:5),
  ]);
  assert_eq(mismatched.failed, u1:1);

  let guarded_out = reduction_aggregate_batch<u32:2>([
    aggregate_test_count(u32:1, u32:0),
    aggregate_test_count(u32:1, u32:5),
  ]);
  assert_eq(guarded_out.failed, u1:1);

  let duplicate = reduction_aggregate_batch<u32:3>([
    aggregate_test_member(u32:1, u32:9, u32:1),
    aggregate_test_member(u32:1, u32:9, u32:2),
    aggregate_test_member(u32:1, u32:2, u32:3),
  ]);
  assert_eq(duplicate.failed, u1:1);

  let incomplete = reduction_aggregate_batch<u32:1>([
    aggregate_test_count(u32:1, u32:4),
  ]);
  let opened = reduction_open_site(
    ReductionSite::COUNTING, u32:1, zero!<Sum>());
  assert_eq(
    reduction_apply_complete_aggregate(opened, incomplete).outcome,
    ReductionOutcome::MISMATCH);
}

#[test]
fn shared_machine_aggregate_validation_test() {
  let aggregate = reduction_aggregate_batch<u32:2>([
    aggregate_test_count(u32:7, u32:11),
    aggregate_test_count(u32:7, u32:13),
  ]);
  let request = ReductionAggregateRequest { slot: u32:0, aggregate };
  let opened = reduction_open_site(
    ReductionSite::COUNTING, u32:7, zero!<Sum>());
  let machine = SharedMachine {
    reduction: opened,
    ..zero!<SharedMachine>()
  };

  let accepted = shared_machine_aggregate(machine, request, u32:0);
  assert_eq(accepted.dispatched, u1:1);
  assert_eq(accepted.directive, Directive::CONSUME);
  assert_eq(accepted.machine.failed, u1:0);
  assert_eq(accepted.machine.reduction.status, ReductionStatus::COMPLETE);
  assert_eq(accepted.machine.reduction.accumulator,
    Sum { value: u32:24, contributions: u8:2 });

  let wrong_site_aggregate = reduction_aggregate_batch<u32:3>([
    aggregate_test_member(u32:7, u32:9, u32:2),
    aggregate_test_member(u32:7, u32:2, u32:3),
    aggregate_test_member(u32:7, u32:7, u32:5),
  ]);
  let wrong_site = shared_machine_aggregate(
    machine,
    ReductionAggregateRequest {
      slot: u32:0,
      aggregate: wrong_site_aggregate,
    },
    u32:0);
  assert_eq(wrong_site.directive, Directive::FAIL);
  assert_eq(wrong_site.machine.failed, u1:1);

  let wrong_key_aggregate = reduction_aggregate_batch<u32:2>([
    aggregate_test_count(u32:8, u32:11),
    aggregate_test_count(u32:8, u32:13),
  ]);
  let wrong_key = shared_machine_aggregate(
    machine,
    ReductionAggregateRequest {
      slot: u32:0,
      aggregate: wrong_key_aggregate,
    },
    u32:0);
  assert_eq(wrong_key.directive, Directive::FAIL);
  assert_eq(wrong_key.machine.failed, u1:1);

  let enter_pending = shared_machine_aggregate(
    SharedMachine { enter_pending: u1:1, ..machine }, request, u32:0);
  assert_eq(enter_pending.directive, Directive::FAIL);
  assert_eq(enter_pending.machine.failed, u1:1);

  let stale = shared_machine_aggregate(accepted.machine, request, u32:0);
  assert_eq(stale.directive, Directive::FAIL);
  assert_eq(stale.machine.failed, u1:1);
}

#[test]
fn aggregate_receptacles_remain_ready_behind_egress_test() {
  let aggregate = reduction_aggregate_batch<u32:2>([
    aggregate_test_count(u32:7, u32:11),
    aggregate_test_count(u32:7, u32:13),
  ]);
  let state = SharedState<u32:2, u32:1> {
    aggregate_pending: [
      ReductionAggregateRequest { slot: u32:0, aggregate },
      ReductionAggregateRequest { slot: u32:1, aggregate },
    ],
    aggregate_pending_valid: [u1:1, u1:1],
    // Ordinary effect retirement may be blocked without suppressing private
    // aggregate work for either actor.
    egress_busy: u1:1,
    ..zero!<SharedState<u32:2, u32:1>>()
  };
  assert_eq(
    reduction_ready_selection(state, u32:0, [u1:0, u1:0]),
    (u1:1, u32:0));
  assert_eq(
    reduction_ready_selection(state, u32:1, [u1:0, u1:0]),
    (u1:1, u32:1));
}

// Compile-only smoke top for the aggregate-only SharedService port.
pub proc ReductionAggregateSharedCompileTop {
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
    let (aggregate_p, aggregate_c) =
      chan<ReductionAggregateRequest, u32:1>("aggregate");
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
      mailbox_write_resp_c,
      aggregate_c);
    ()
  }

  init { () }
  next(state: ()) { state }
}
