// Singleton placement of the common retained collection bank.
type DirectCollection = CollectionBank;

// Actor and collector transitions exchange a registered ownership command.
struct DirectCollectionStep {
  machine: Machine,
  collection: DirectCollection,
  control: CollectionControl,
  egress: Egress,
  egress_valid: bool,
}

// Completion is visible only to the actor which retains the matching opening.
// Other callbacks retain their immutable open descriptor, not partial progress.
fn direct_collection_machine(machine: Machine, collection: DirectCollection) -> Machine {
  let complete = machine.reduction.status == ReductionStatus::OPEN && collection.opened &&
    collection.reduction.status == ReductionStatus::COMPLETE &&
    machine.reduction.key == collection.reduction.key;
  Machine { reduction: if complete { collection.reduction } else { machine.reduction },
    failure: hls_failure::first(machine.failure, collection.failure),
    admission_pending: false, ..machine }
}

// Produce the actor's next registered release/open command without reading a
// newly folded bank. The committed grant remains the authority for consumption.
fn direct_collection_command(machine: Machine, stepped: MachineStep) -> CollectionControl {
  let consumed = !hls_failure::failed(machine.failure) && !machine.enter_pending &&
    machine.reduction.status == ReductionStatus::COMPLETE;
  let opening = (machine.reduction.status == ReductionStatus::IDLE || consumed) &&
    stepped.machine.reduction.status == ReductionStatus::OPEN;
  CollectionControl { release: consumed, release_key: machine.reduction.key,
    open: opening, opening: stepped.machine.reduction }
}

// Apply an already evaluated actor result and the collector's independent port.
fn direct_collection_finish(machine: Machine, bank: DirectCollection, control: CollectionControl,
    stepped: MachineStep, contribution: axis::Frame, collected: bool) -> DirectCollectionStep {
  let controlled = collection_control(bank, control);
  DirectCollectionStep {
    machine: stepped.machine,
    collection: collection_fold(controlled, contribution, collected),
    control: direct_collection_command(machine, stepped),
    egress: stepped.egress,
    egress_valid: stepped.egress_valid,
  }
}

// Actor work observes only committed collector status. Its new ownership command
// cannot affect collection validation, folding or failure until the next edge.
fn direct_collection_step(stored: Machine, bank: DirectCollection, control: CollectionControl,
    frame: axis::Frame, received: bool, contribution: axis::Frame, collected: bool)
    -> DirectCollectionStep {
  let machine = direct_collection_machine(stored, bank);
  let stepped = machine_step(machine, frame, received, true);
  direct_collection_finish(machine, bank, control, stepped, contribution, collected)
}

// Producer slots preserve each physical source's order. Command registration is
// an explicit ownership boundary; outgoing effects use committed actor entry.
struct DirectCollectionState<PRODUCER_COUNT: u32, STARTUP_BITS: u32 = {u32:32}> {
  machine: Machine,
  collection: DirectCollection,
  control: CollectionControl,
  pending: axis::Frame[PRODUCER_COUNT],
  valid: bool[PRODUCER_COUNT],
  ordinary_cursor: u32,
  collection_cursor: u32,
  initialized: uN[STARTUP_BITS],
  // The owner holds its machine/bank through one registered grant and execution.
  command_valid: bool,
  command_frame: axis::Frame,
  command_received: bool,
  // Independent one-slot contribution pipeline; a successor waits for release.
  contribution_frame: axis::Frame,
  contribution_valid: bool,
  command_reduction: ReductionState,
  command_failure: hls_failure::Code,
  command_failed: bool,
  publish: Egress,
  publish_valid: bool,
  // One selected ordinary message crosses into the mailbox on the next activation.
  ordinary_pending: axis::Frame,
  ordinary_valid: bool,
}

// Fault priority and completion selection are established at the registered grant.
// The checked machine remains authoritative until this command executes. A failed
// grant cannot evaluate callbacks or mutate the ordinary mailbox.
fn direct_collection_execute<PRODUCER_COUNT: u32, STARTUP_BITS: u32>(
    state: DirectCollectionState<PRODUCER_COUNT, STARTUP_BITS>) -> DirectCollectionStep {
  let machine = Machine { reduction: state.command_reduction,
    failure: state.command_failure, admission_pending: false, ..state.machine };
  let stepped = if state.command_failed {
    MachineStep { machine, ..zero!<MachineStep>() }
  } else {
    machine_step(Machine { failure: hls_failure::NONE, ..machine },
      state.command_frame, state.command_received, true)
  };
  DirectCollectionStep { machine: stepped.machine, collection: state.collection,
    control: direct_collection_command(machine, stepped),
    egress: stepped.egress, egress_valid: stepped.egress_valid }
}

// Consume a held contribution only against the committed bank. A preceding
// fold may have completed it after selection, so a successor must be rechecked.
// Registered control applies once, before folding; its new bank is not bypassed
// into this consume decision. A failed owner stops intake without dropping data.
fn direct_collection_advance(bank: DirectCollection, control: CollectionControl,
    frame: axis::Frame, valid: bool, failed: bool) -> (DirectCollection, bool) {
  let consumed = valid && !failed && collection_accepts(bank, frame);
  (collection_fold(collection_control(bank, control), frame, consumed), consumed)
}

// A combinational proposal for the existing command registers; no extra queue.
// The descriptor cannot evaluate either completion or entry callbacks.
struct DirectCollectionGrant {
  valid: bool,
  reduction: ReductionState,
  failure: hls_failure::Code,
  failed: bool,
}

// Prepare completion at bank commit, or entry at successful completion commit.
// Preserve an accepted input and any unexecuted ordinary mailbox grant. A new
// opening cannot inherit a previous bank's completion. Snapshot committed-next
// bank faults even for entry so the next callback sees the checked priority.
fn direct_collection_next_grant<PRODUCER_COUNT: u32, STARTUP_BITS: u32>(
    state: DirectCollectionState<PRODUCER_COUNT, STARTUP_BITS>,
    stepped: DirectCollectionStep, bank: DirectCollection, received: bool)
    -> DirectCollectionGrant {
  let machine = direct_collection_machine(stepped.machine, bank);
  let same_opening = !state.machine.enter_pending &&
    state.machine.reduction.status == ReductionStatus::OPEN &&
    stepped.machine.reduction.status == ReductionStatus::OPEN &&
    state.machine.reduction.key == stepped.machine.reduction.key;
  let complete = same_opening && !stepped.machine.enter_pending &&
    machine.reduction.status == ReductionStatus::COMPLETE &&
    !hls_failure::failed(machine.failure) && !received &&
    (state.command_valid || state.machine.occupied == u8:0);
  let entry = state.command_valid && !state.command_failed &&
    !state.machine.enter_pending &&
    state.command_reduction.status == ReductionStatus::COMPLETE &&
    stepped.machine.enter_pending &&
    stepped.machine.reduction.status == ReductionStatus::IDLE &&
    !hls_failure::failed(stepped.machine.failure);
  DirectCollectionGrant { valid: complete || entry, reduction: machine.reduction,
    failure: machine.failure, failed: hls_failure::failed(machine.failure) }
}
