// Independent pre-sharing aggregate dispatch: reject without changing actor data.
fn reference_aggregate(machine: ActorState,
    request: ReductionAggregateRequest, slot: u32) -> ActorDispatch {
  let applied = reduction_apply_complete_aggregate(machine.reduction, request.aggregate);
  let accepted = !hls_failure::failed(machine.failure) && !machine.enter_pending &&
    request.slot == slot && applied.outcome == ReductionOutcome::COMPLETE;
  if accepted {
    shared_machine_complete(ActorState { reduction: applied.state, ..machine })
  } else {
    ActorDispatch {
      machine: ActorState {
        failure: hls_failure::first(machine.failure, hls_failure::REDUCTION_PROTOCOL),
        ..machine
      },
      dispatched: true, directive: Directive::FAIL, ..zero!<ActorDispatch>()
    }
  }
}

// Preserve internal priority and the ordinary-mail fallback independently.
fn reference_dispatch(machine: ActorState, request: SharedExecutorRequest) -> ActorDispatch {
  if request.internal { shared_machine_complete(machine) }
  else if request.aggregate_valid {
    reference_aggregate(machine, request.aggregate_request, request.slot)
  } else { shared_machine_dispatch(machine, request.frame, request.received) }
}

// Compare all output bits, including failure state, effects and entry blocking.
pub fn completion_equivalent(request: SharedExecutorRequest) -> bool {
  shared_execute(request) == reference_execute(request)
}
