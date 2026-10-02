// Scalar-array reference adapter for the payload-free ownership kernel. Production
// adapters can commit the same intents to member memories without this wide state.
import indexed_collection_core as core;

// Re-export control vocabulary so reference callers share the exact kernel types.
pub type Status = core::Status;
// Protocol fault classifications are shared with the physical control interface.
pub type Fault = core::Fault;
// Acceptance determines whether the offered input may leave its producer slot.
pub type Outcome = core::Outcome;
// Fault details never contain or substitute for payload data.
pub type Error = core::Error;
// The scalar reference uses the same generation-checked ticket as a memory adapter.
pub type Lease = core::Lease;
// The result carries the single checked write intent, when one exists.
pub type Result = core::Result;

// Presence distinguishes an inactive slot from a selected member supplying zero.
pub struct View<VALUE_BITS: u32, CAPACITY: u32> {
  members: bits[CAPACITY],
  values: bits[VALUE_BITS][CAPACITY],
}

// Payload arrays have independent storage; control operations never copy a view.
pub struct State<VALUE_BITS: u32, CAPACITY: u32> {
  metadata: core::State<CAPACITY>,
  payloads: bits[VALUE_BITS][CAPACITY][2],
}

// Initialize logical ownership and deterministic reference memory contents.
pub fn init<VALUE_BITS: u32, CAPACITY: u32>(reset_epoch: u32)
    -> State<VALUE_BITS, CAPACITY> {
  const_assert!(VALUE_BITS > u32:0);
  State<VALUE_BITS, CAPACITY> { metadata: core::init<CAPACITY>(reset_epoch),
    ..zero!<State<VALUE_BITS, CAPACITY>>() }
}

// Reserving changes metadata only; obsolete memory words need not be erased.
pub fn reserve<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, key: u32, candidates: bits[CAPACITY])
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::reserve(state.metadata, key, candidates);
  (State<VALUE_BITS, CAPACITY> { metadata, ..state }, result)
}

// Final membership validation cannot expose an unvalidated payload view.
pub fn open<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, lease: Lease, members: bits[CAPACITY])
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::open(state.metadata, lease, members);
  (State<VALUE_BITS, CAPACITY> { metadata, ..state }, result)
}

// Commit exactly one indexed payload write together with its accepted metadata.
// WAIT, DEFERRED and FAILED leave all payload words unchanged.
pub fn offer<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, key: u32, member: u32, value: bits[VALUE_BITS])
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::offer(state.metadata, key, member);
  let payloads = if result.write.valid {
    update(state.payloads, result.write.bank as u32,
      update(state.payloads[result.write.bank as u32], result.write.member, value))
  } else { state.payloads };
  (State<VALUE_BITS, CAPACITY> { metadata, payloads }, result)
}

// Acquisition gives a read lease while retaining memory ownership until retirement.
pub fn acquire<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, lease: Lease)
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::acquire(state.metadata, lease);
  (State<VALUE_BITS, CAPACITY> { metadata, ..state }, result)
}

// Materialize the member-ordered view; inactive words are zero only in this view,
// so storage reuse cannot expose a stale value and no memory clearing is needed.
pub fn read<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, lease: Lease)
    -> (State<VALUE_BITS, CAPACITY>, View<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, intent, result) = core::read(state.metadata, lease);
  let values = for (member, values): (u32, bits[VALUE_BITS][CAPACITY]) in u32:0..CAPACITY {
    let present = intent.valid && ((intent.members >> member) as bool);
    update(values, member, if present { state.payloads[intent.lease.bank as u32][member] }
      else { bits[VALUE_BITS]:0 })
  }(zero!<bits[VALUE_BITS][CAPACITY]>());
  (State<VALUE_BITS, CAPACITY> { metadata, ..state },
    View<VALUE_BITS, CAPACITY> { members: intent.members, values }, result)
}

// Retire a borrowed bank without clearing its physically inaccessible payload.
pub fn release<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, lease: Lease)
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::release(state.metadata, lease);
  (State<VALUE_BITS, CAPACITY> { metadata, ..state }, result)
}

// An invalidated populated reservation remains diagnostic state and becomes failure.
pub fn invalidate<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, lease: Lease)
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::invalidate(state.metadata, lease);
  (State<VALUE_BITS, CAPACITY> { metadata, ..state }, result)
}

// Reset invalidates every old read lease without requiring a payload-memory clear.
pub fn reset<VALUE_BITS: u32, CAPACITY: u32>(
    state: State<VALUE_BITS, CAPACITY>, reset_epoch: u32)
    -> (State<VALUE_BITS, CAPACITY>, Result) {
  let (metadata, result) = core::reset(state.metadata, reset_epoch);
  (State<VALUE_BITS, CAPACITY> { metadata, ..state }, result)
}
