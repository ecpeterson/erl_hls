// An owner may open a collection and later release its retained result. Both
// operations are keyed; a release may accompany a successor opening. The
// descriptor is immutable actor metadata, never a copy of the live accumulator.
struct CollectionControl {
  release: bool,
  release_key: u32,
  open: bool,
  opening: ReductionState,
}

// Authoritative collection storage. Completion retains the bank until release;
// future storage policies may retain source-indexed values under the same lease.
struct CollectionBank {
  reduction: ReductionState,
  opened: bool,
  failure: hls_failure::Code,
}

// Pure message decoding crosses the same capture edge as its raw producer slot.
// An occupied slot retains both until consumed; frame validity is checked here.
struct CollectionInput {
  contribution: ReductionContribution,
  frame_valid: bool,
}

// Only callback metadata needed for coherent debug sampling accompanies a bank.
// Application data, mailbox contents and entry effects remain in actor storage.
struct CollectionContext {
  reduction: ReductionState,
  failure: hls_failure::Code,
  phase: Phase,
  enter_pending: bool,
}

// Ownership bookkeeping is separate from the accumulator. Columnar arrays let
// issuing, retiring and controlling different actors update independent fields.
struct CollectionOwners<ACTOR_COUNT: u32> {
  initialized: bool[ACTOR_COUNT],
  opened: bool[ACTOR_COUNT],
  consuming: bool[ACTOR_COUNT],
  actor_opened: bool[ACTOR_COUNT],
}

// One callback return crosses the ownership boundary per activation. The bank
// sees this command only on the following activation, never its current result.
struct CollectionCommand {
  valid: bool,
  slot: u32,
  control: CollectionControl,
  phase: Phase,
  enter_pending: bool,
  failure: hls_failure::Code,
}
