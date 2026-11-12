// Finite two-slot controller witnesses; stream integration separately supplies real retirement evidence.
import supervisor;
import supervisor_controller as manager;
import parent_controller as parent;
import supervisor_codes as codes;

// An already running parent has scanned both dormant compiled slots without allocating a child.
fn ready() -> supervisor::State {
  let initial = supervisor::initial_state();
  supervisor::State {
    parent: parent::ServiceState { data: parent::Controllerstate {
      lifecycle: parent::Domainstate {phase: codes::PHASE_READY, current: u64:1, target: u64:1, transition: u64:1,
        ..zero!<parent::Domainstate>()}}, ..initial.parent },
    supervisor: manager::ServiceState {data: manager::Supervisorservice {
      supervisor: manager::Supervisorstate {phase: codes::SUPERVISOR_PHASE_RUNNING,
        epoch:u64:1,first:u64:2,last:u64:16,next:u64:2,children:u16:2,started:u16:2,
        intensity:u8:2,period:u32:5,..zero!<manager::Supervisorstate>()}},
        ..initial.supervisor},
    children: manager::Supervisorchild[2]:[
      manager::Supervisorchild{phase:codes::CHILD_PHASE_VACANT,..zero!<manager::Supervisorchild>()}, ...],
    ..initial
  }
}

// Reusable is explicit physical evidence, not a host guess inferred from an empty slot.
fn inputs() -> supervisor::Inputs {
  supervisor::Inputs{child_0_observed_phase:codes::PHASE_UNBOUND,
    child_1_observed_phase:codes::PHASE_UNBOUND,
    child_0_observed_reusable:true,child_1_observed_reusable:true,
    ..zero!<supervisor::Inputs>()}
}

// Admission returns the reserved identity before readiness and preserves the next scan turn.
#[test]
fn admission_is_exact_and_retirement_gated() {
  let command = supervisor::Inputs{slot_valid:true,slot_operation:u2:0,
    slot_epoch:u64:1,slot_index:u32:1,..inputs()};
  let blocked = supervisor::tick(ready(),supervisor::Inputs{
    child_1_observed_reusable:false,..command});
  assert_eq(blocked.output.slot_status,codes::SUPERVISOR_STATUS_BUSY);
  assert_eq(blocked.state.supervisor.data.supervisor.next,u64:2);
  let accepted = supervisor::tick(ready(),command);
  assert_eq(accepted.output.slot_status,codes::SUPERVISOR_STATUS_ACCEPTED);
  assert_eq(accepted.output.slot_result_index,u32:1);
  assert_eq(accepted.output.slot_target,u64:2);
  assert_eq(accepted.output.slot_phase,codes::CHILD_PHASE_ADMITTING);
  assert_eq(accepted.output.child_0_management_valid,false);
  assert_eq(accepted.output.child_1_management_valid,true);
  assert_eq(accepted.state.cursor,u16:0);
  assert_eq(accepted.state.children[u32:0].phase,codes::CHILD_PHASE_VACANT);
  let scan = supervisor::tick(accepted.state,command);
  assert_eq(scan.output.slot_ready,false);
  assert_eq(scan.output.slot_response_valid,false);
  assert_eq(scan.state.cursor,u16:1);
}

// The parent stop on this edge excludes new admission instead of creating work behind its fence.
#[test]
fn parent_stop_wins_admission() {
  let stopped = supervisor::tick(ready(),supervisor::Inputs{
    management_valid:true,management_op:codes::OPERATION_STOP,
    expected:u64:1,target:u64:1,transition:u64:1,
    slot_valid:true,slot_operation:u2:0,slot_epoch:u64:1,slot_index:u32:0,..inputs()});
  assert_eq(stopped.output.slot_status,codes::SUPERVISOR_STATUS_STALE);
  assert_eq(stopped.state.supervisor.data.supervisor.next,u64:2);
  assert_eq(stopped.output.child_0_management_valid,false);
  assert_eq(stopped.state.parent.data.lifecycle.phase,codes::PHASE_CLOSING);
}

// Inspection has no allocation effect; stale parent identities and invalid indices reject.
#[test]
fn inspect_and_reject() {
  let inspect = supervisor::Inputs{slot_valid:true,slot_operation:u2:2,
    slot_epoch:u64:1,slot_index:u32:1,..inputs()};
  let result = supervisor::tick(ready(),inspect);
  assert_eq(result.output.slot_status,codes::SUPERVISOR_STATUS_OK);
  assert_eq(result.output.slot_phase,codes::CHILD_PHASE_VACANT);
  assert_eq(result.output.slot_target,u64:0);
  assert_eq(result.state.supervisor.data.supervisor.next,u64:2);
  assert_eq(supervisor::tick(ready(),supervisor::Inputs{slot_epoch:u64:2,..inspect}).output.slot_status,
    codes::SUPERVISOR_STATUS_STALE);
  assert_eq(supervisor::tick(ready(),supervisor::Inputs{slot_index:u32:2,..inspect}).output.slot_status,
    codes::SUPERVISOR_STATUS_INVALID);
}
