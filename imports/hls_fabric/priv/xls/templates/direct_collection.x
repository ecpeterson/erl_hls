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

// Actor work observes only committed collector status. Its new ownership command
// cannot affect collection validation, folding or failure until the next edge.
fn direct_collection_step(stored: Machine, bank: DirectCollection, control: CollectionControl,
    frame: axis::Frame, received: bool, contribution: axis::Frame, collected: bool)
    -> DirectCollectionStep {
  let machine = direct_collection_machine(stored, bank);
  let stepped = machine_step(machine, frame, received, true);
  let consumed = !hls_failure::failed(machine.failure) && !machine.enter_pending &&
    machine.reduction.status == ReductionStatus::COMPLETE;
  let opening = (machine.reduction.status == ReductionStatus::IDLE || consumed) &&
    stepped.machine.reduction.status == ReductionStatus::OPEN;
  let command = CollectionControl { release: consumed, release_key: machine.reduction.key,
    open: opening, opening: stepped.machine.reduction };
  let controlled = collection_control(bank, control);
  DirectCollectionStep {
    machine: stepped.machine,
    collection: collection_fold(controlled, contribution, collected),
    control: command,
    egress: stepped.egress,
    egress_valid: stepped.egress_valid,
  }
}

// Producer slots preserve each physical source's order. Command registration is
// an explicit ownership boundary; outgoing effects use committed actor entry.
struct DirectCollectionState<PRODUCER_COUNT: u32> {
  machine: Machine,
  collection: DirectCollection,
  control: CollectionControl,
  pending: axis::Frame[PRODUCER_COUNT],
  valid: bool[PRODUCER_COUNT],
  ordinary_cursor: u32,
  collection_cursor: u32,
  initialized: u32,
  // One selected ordinary message crosses into the mailbox on the next activation.
  ordinary_pending: axis::Frame,
  ordinary_valid: bool,
}
