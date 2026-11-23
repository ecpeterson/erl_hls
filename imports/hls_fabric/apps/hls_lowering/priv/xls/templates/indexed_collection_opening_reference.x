// Frozen pre-composition open and its helpers, from core SHA-256
// 78d6336d2919fb7cba748bd79da053ba222dcccecfa9987327f6e8d9063f7e47. Only type qualification changes those bodies.
// The composition below reconstructs the adapter's separate reservation/open calls.
import indexed_collection_core as core;
import indexed_collection_admission_reference as admission;

// Preserve the frozen full-state failure result and dormant diagnostics.
fn fail<CAPACITY: u32>(
    state: core::State<CAPACITY>, error: core::Error)
    -> (core::State<CAPACITY>, core::Result) {
  (core::State<CAPACITY> {
    failure: if state.failure.code == core::Fault::NONE { error } else { state.failure },
    ..state
  }, core::Result { outcome: core::Outcome::FAILED, ..zero!<core::Result>() })
}

// Preserve the frozen external lease identity checks.
fn check_lease<CAPACITY: u32>(
    state: core::State<CAPACITY>, lease: core::Lease) -> core::Fault {
  let bank = state.banks[lease.bank as u32];
  if state.reset_epoch != lease.reset_epoch || bank.generation != lease.generation {
    core::Fault::STALE_GENERATION
  } else if bank.key != lease.key { core::Fault::KEY_MISMATCH }
  else { core::Fault::NONE }
}

// Preserve the frozen lowest-member error diagnostic.
fn first_member<CAPACITY: u32>(members: bits[CAPACITY]) -> u32 {
  for (member, found): (u32, u32) in u32:0..CAPACITY {
    if found == CAPACITY && ((members >> member) as bool) { member } else { found }
  }(CAPACITY)
}

// Preserve the frozen checked opening, independent of production scalar helpers.
pub fn open<CAPACITY: u32>(
    state: core::State<CAPACITY>, lease: core::Lease, members: bits[CAPACITY])
    -> (core::State<CAPACITY>, core::Result) {
  let bank = state.banks[lease.bank as u32];
  let checked = check_lease(state, lease);
  let foreign = bank.seen & !members;
  let error = if checked != core::Fault::NONE {
    core::Error { code: checked, key: lease.key, member: u32:0 }
  } else if bank.status != core::Status::PROVISIONAL {
    core::Error { code: core::Fault::WRONG_STATUS, key: lease.key, member: u32:0 }
  } else if (members & !bank.candidates) != bits[CAPACITY]:0 {
    core::Error { code: core::Fault::INVALID_MEMBERSHIP, key: lease.key,
      member: first_member(members & !bank.candidates) }
  } else if foreign != bits[CAPACITY]:0 {
    core::Error { code: core::Fault::FOREIGN_MEMBER, key: lease.key, member: first_member(foreign) }
  } else { bank.deferred };
  if state.failure.code != core::Fault::NONE || error.code != core::Fault::NONE {
    fail(state, error)
  } else {
    let next_bank = core::Bank<CAPACITY> { members,
      status: if bank.seen == members { core::Status::SEALED } else { core::Status::OPEN }, ..bank };
    (core::State<CAPACITY> {
      banks: update(state.banks, lease.bank as u32, next_bank), ..state },
      core::Result { outcome: core::Outcome::ACCEPTED, lease, ..zero!<core::Result>() })
  }
}

// Construct the original selected-state lease for existing-key reuse.
fn ticket<CAPACITY: u32>(state: core::State<CAPACITY>, slot: u1) -> core::Lease {
  let bank = state.banks[slot as u32];
  core::Lease { bank:slot, key:bank.key, generation:bank.generation, reset_epoch:state.reset_epoch }
}

// Reference only: reserve and rebuild State before calling the frozen ordinary open.
// Result remains the reservation result, including ACCEPTED followed by an opening fault.
pub fn reserve_and_maybe_open<CAPACITY: u32>(state: core::State<CAPACITY>, key: u32,
    candidates: bits[CAPACITY], members: bits[CAPACITY], allow: bool[2])
    -> (core::State<CAPACITY>, core::Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let a = first.status != core::Status::FREE && first.key == key;
  let b = second.status != core::Status::FREE && second.key == key;
  let reservation = if a || b {
    (state, core::Result { outcome:core::Outcome::ACCEPTED,
      lease:ticket(state, if a { u1:0 } else { u1:1 }), ..zero!<core::Result>() })
  } else { admission::reserve(state, key, candidates) };
  let next = if reservation.1.outcome == core::Outcome::ACCEPTED && allow[reservation.1.lease.bank as u32] {
    open(reservation.0, reservation.1.lease, members).0
  } else { reservation.0 };
  (next, reservation.1)
}
