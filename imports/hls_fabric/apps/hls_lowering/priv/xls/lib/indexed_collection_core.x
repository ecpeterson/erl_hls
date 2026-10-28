// Pure two-bank indexed gather for one actor/site. An outer protocol authorizes
// every reserved key and candidate mask; numeric adjacency grants no permission.
// Payload storage is external: checked write/read intents carry bank and member
// identity without moving the payload through these metadata transitions.
// Adapters commit metadata with its write intent and flush pending memory work on
// coordinated reset before reusing a bank; this kernel has no transport queues.
// Generation comparison detects only bounded-age stale tickets. The owner must
// destroy retired tickets before 2^32 reuses of that bank; counters wrap normally.

// A completed bank remains immutable through borrowing and explicit retirement.
pub enum Status : u3 {
  FREE = 0,
  PROVISIONAL = 1,
  OPEN = 2,
  SEALED = 3,
  BORROWED = 4,
}

// All faults are protocol-terminal once eligible; this gather has no reducer.
pub enum Fault : u4 {
  NONE = 0,
  UNRESERVED_KEY = 1,
  MEMBER_RANGE = 2,
  FOREIGN_MEMBER = 3,
  DUPLICATE_MEMBER = 4,
  KEY_MISMATCH = 5,
  STALE_GENERATION = 6,
  WRONG_STATUS = 7,
  DUPLICATE_RESERVATION = 8,
  INVALID_MEMBERSHIP = 9,
  RESET_EPOCH_REUSED = 10,
}

// WAIT consumes no input; DEFERRED retains an arrival fault until opening.
pub enum Outcome : u2 {
  ACCEPTED = 0,
  WAIT = 1,
  DEFERRED = 2,
  FAILED = 3,
}

// A fault identifies the offending key and member when the operation has one.
pub struct Error {
  code: Fault,
  key: u32,
  member: u32,
}

// Tickets identify one reservation. A ticket is a read lease only after acquire.
pub struct Lease {
  bank: u1,
  key: u32,
  generation: u32,
  reset_epoch: u32,
}

// One accepted offer authorizes one external payload write; the caller retains
// its value until this intent commits together with the returned metadata.
pub struct WriteIntent {
  valid: bool,
  bank: u1,
  member: u32,
}

// A successful operation returns the ticket; failed/waiting callers must ignore it.
pub struct Result {
  outcome: Outcome,
  lease: Lease,
  write: WriteIntent,
}

// A borrowed view reads members by index; inactive physical slots are unspecified.
pub struct ReadIntent<CAPACITY: u32> {
  valid: bool,
  lease: Lease,
  members: bits[CAPACITY],
}

// Candidate membership authorizes provisional storage; open captures final membership.
pub struct Bank<CAPACITY: u32> {
  status: Status,
  key: u32,
  generation: u32,
  candidates: bits[CAPACITY],
  members: bits[CAPACITY],
  seen: bits[CAPACITY],
  deferred: Error,
}

// Failure is sticky until reset, which also invalidates all bank generations.
pub struct State<CAPACITY: u32> {
  banks: Bank<CAPACITY>[2],
  reset_epoch: u32,
  failure: Error,
}

// A checked scalar-bank transition defers array replacement until composition is complete.
struct BankStep<CAPACITY: u32> {
  changed: bool,
  bank: Bank<CAPACITY>,
  failure: Error,
  result: Result,
}

// Start an empty context. The caller supplies a reset epoch distinct from every
// still-reachable old ticket; a system-wide flush is required before epoch reuse.
pub fn init<CAPACITY: u32>(reset_epoch: u32)
    -> State<CAPACITY> {
  const_assert!(CAPACITY > u32:0);
  State<CAPACITY> { reset_epoch,
    ..zero!<State<CAPACITY>>() }
}

// Construct a lease directly from a checked bank, including a newly prepared reservation.
fn bank_ticket<CAPACITY: u32>(bank: Bank<CAPACITY>, slot: u1, reset_epoch: u32) -> Lease {
  Lease { bank: slot, key: bank.key, generation: bank.generation, reset_epoch }
}

// Preserve the first terminal failure and leave every bank available for diagnosis.
fn fail<CAPACITY: u32>(
    state: State<CAPACITY>, error: Error)
    -> (State<CAPACITY>, Result) {
  (State<CAPACITY> {
    failure: if state.failure.code == Fault::NONE { error } else { state.failure },
    ..state
  }, Result { outcome: Outcome::FAILED, ..zero!<Result>() })
}

// Check scalar identity before reading status or membership; composition supplies
// a canonical lease from this same bank, while ordinary open accepts caller leases.
fn check_bank_lease<CAPACITY: u32>(bank: Bank<CAPACITY>, reset_epoch: u32, lease: Lease)
    -> Fault {
  if reset_epoch != lease.reset_epoch || bank.generation != lease.generation {
    Fault::STALE_GENERATION
  } else if bank.key != lease.key { Fault::KEY_MISMATCH }
  else { Fault::NONE }
}

// Reject stale tickets before examining their former bank contents.
fn check_lease<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease) -> Fault {
  check_bank_lease(state.banks[lease.bank as u32], state.reset_epoch, lease)
}

// Commit one composed bank transition while preserving unrelated banks and reset identity.
fn apply_bank<CAPACITY: u32>(state: State<CAPACITY>, slot: u1, step: BankStep<CAPACITY>)
    -> State<CAPACITY> {
  State<CAPACITY> { banks: if step.changed {
    update(state.banks, slot as u32, step.bank)
  } else { state.banks }, failure: step.failure, ..state }
}

// A failed bank decision preserves metadata and the first full diagnostic error.
fn failed_bank<CAPACITY: u32>(bank: Bank<CAPACITY>, failure: Error, error: Error)
    -> BankStep<CAPACITY> {
  BankStep<CAPACITY> { changed: false, bank,
    failure: if failure.code == Fault::NONE { error } else { failure },
    result: Result { outcome: Outcome::FAILED, ..zero!<Result>() } }
}

// Reservation selection supplies canonical duplicate/free facts; all fault priorities remain checked here.
fn reserve_bank<CAPACITY: u32>(bank: Bank<CAPACITY>, slot: u1, reset_epoch: u32,
    failure: Error, key: u32, candidates: bits[CAPACITY], duplicate: bool, available: bool)
    -> BankStep<CAPACITY> {
  let fault = if failure.code != Fault::NONE { failure.code }
    else if duplicate { Fault::DUPLICATE_RESERVATION } else { Fault::NONE };
  if fault != Fault::NONE {
    failed_bank(bank, failure, Error { code: fault, key, member: u32:0 })
  } else if !available {
    BankStep<CAPACITY> { changed: false, bank, failure,
      result: Result { outcome: Outcome::WAIT, ..zero!<Result>() } }
  } else {
    let bank = Bank<CAPACITY> { status: Status::PROVISIONAL, key, candidates,
      generation: bank.generation + u32:1, ..zero!<Bank<CAPACITY>>() };
    BankStep<CAPACITY> { changed: true, bank, failure,
      result: Result { outcome: Outcome::ACCEPTED,
        lease: bank_ticket(bank, slot, reset_epoch), ..zero!<Result>() } }
  }
}

// Reserve exactly the caller-authorized key. Full capacity waits without mutation;
// a repeated reservation is a fault, so a held command must honor its acceptance.
pub fn reserve<CAPACITY: u32>(
    state: State<CAPACITY>, key: u32, candidates: bits[CAPACITY])
    -> (State<CAPACITY>, Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let duplicate = (first.status != Status::FREE && first.key == key) ||
    (second.status != Status::FREE && second.key == key);
  let available = first.status == Status::FREE || second.status == Status::FREE;
  let slot = if first.status == Status::FREE { u1:0 } else { u1:1 };
  let step = reserve_bank(state.banks[slot as u32], slot, state.reset_epoch,
    state.failure, key, candidates, duplicate, available);
  (apply_bank(state, slot, step), step.result)
}

// Return the lowest named member of a nonempty mask for stable fault diagnostics.
fn first_member<CAPACITY: u32>(members: bits[CAPACITY]) -> u32 {
  for (member, found): (u32, u32) in u32:0..CAPACITY {
    if found == CAPACITY && ((members >> member) as bool) { member } else { found }
  }(CAPACITY)
}

// Apply opening after the caller has checked lease identity. Identity faults
// precede status/membership/deferred errors; failure preserves complete metadata.
fn open_bank<CAPACITY: u32>(bank: Bank<CAPACITY>, failure: Error,
    lease: Lease, members: bits[CAPACITY], checked: Fault) -> BankStep<CAPACITY> {
  let foreign = bank.seen & !members;
  let error = if checked != Fault::NONE {
    Error { code: checked, key: lease.key, member: u32:0 }
  } else if bank.status != Status::PROVISIONAL {
    Error { code: Fault::WRONG_STATUS, key: lease.key, member: u32:0 }
  } else if (members & !bank.candidates) != bits[CAPACITY]:0 {
    Error { code: Fault::INVALID_MEMBERSHIP, key: lease.key,
      member: first_member(members & !bank.candidates) }
  } else if foreign != bits[CAPACITY]:0 {
    Error { code: Fault::FOREIGN_MEMBER, key: lease.key, member: first_member(foreign) }
  } else { bank.deferred };
  if failure.code != Fault::NONE || error.code != Fault::NONE {
    failed_bank(bank, failure, error)
  } else {
    BankStep<CAPACITY> { changed: true, failure,
      bank: Bank<CAPACITY> { members,
        status: if bank.seen == members { Status::SEALED } else { Status::OPEN }, ..bank },
      result: Result { outcome: Outcome::ACCEPTED, lease, ..zero!<Result>() } }
  }
}

// Open only the named reservation. Stored members are rechecked against the final
// subset before deferred input faults; those stored arrivals preceded that fault.
// Empty membership seals immediately. Opening never publishes a provisional view.
pub fn open<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease, members: bits[CAPACITY])
    -> (State<CAPACITY>, Result) {
  let bank = state.banks[lease.bank as u32];
  let step = open_bank(bank, state.failure, lease, members,
    check_bank_lease(bank, state.reset_epoch, lease));
  (apply_bank(state, lease.bank, step), step.result)
}

// Reuse the first occupied matching key, otherwise reserve the first free bank,
// then open only when that bank's caller-supplied flag allows it. Flags authorize
// opening, not key eligibility. Result describes reservation/reuse even if opening
// fails; State retains that failure and any new reservation. Existing-key reuse is
// ACCEPTED despite sticky failure, which checked opening preserves. No-open leaves
// existing status, deferred errors and dormant diagnostics untouched.
pub fn reserve_and_maybe_open<CAPACITY: u32>(state: State<CAPACITY>, key: u32,
    candidates: bits[CAPACITY], members: bits[CAPACITY], allow: bool[2])
    -> (State<CAPACITY>, Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let first_key_match = first.status != Status::FREE && first.key == key;
  let second_key_match = second.status != Status::FREE && second.key == key;
  let present = first_key_match || second_key_match;
  let available = first.status == Status::FREE || second.status == Status::FREE;
  let slot = if first_key_match { u1:0 } else if second_key_match { u1:1 }
    else if first.status == Status::FREE { u1:0 } else { u1:1 };
  let bank = state.banks[slot as u32];
  let prepared = if present {
    BankStep<CAPACITY> { changed: false, bank, failure: state.failure,
      result: Result { outcome: Outcome::ACCEPTED,
        lease: bank_ticket(bank, slot, state.reset_epoch), ..zero!<Result>() } }
  } else {
    reserve_bank(bank, slot, state.reset_epoch, state.failure, key, candidates, false, available)
  };
  let opened = if prepared.result.outcome == Outcome::ACCEPTED && allow[slot as u32] {
    // Both successful branches construct bank_ticket from this prepared bank and
    // reset epoch. Unlike a caller-supplied lease, its identity is known here.
    open_bank(prepared.bank, prepared.failure, prepared.result.lease, members, Fault::NONE)
  } else { prepared };
  let combined = BankStep<CAPACITY> { changed: prepared.changed || opened.changed, ..opened };
  (apply_bank(state, slot, combined), prepared.result)
}

// Check a selected or freshly reserved bank without re-reading a reconstructed bank array.
fn offer_bank<CAPACITY: u32>(bank: Bank<CAPACITY>, slot: u1, reset_epoch: u32,
    failure: Error, present: bool, key: u32, member: u32) -> BankStep<CAPACITY> {
  let lease = bank_ticket(bank, slot, reset_epoch);
  let member_bit = bits[CAPACITY]:1 << member;
  let expected = if bank.status == Status::PROVISIONAL { bank.candidates } else { bank.members };
  let fault = if member >= CAPACITY { Fault::MEMBER_RANGE }
    else if (expected & member_bit) == bits[CAPACITY]:0 { Fault::FOREIGN_MEMBER }
    else if (bank.seen & member_bit) != bits[CAPACITY]:0 { Fault::DUPLICATE_MEMBER }
    else if bank.status != Status::PROVISIONAL && bank.status != Status::OPEN { Fault::WRONG_STATUS }
    else { Fault::NONE };
  let error = Error { code: fault, key, member };
  if failure.code != Fault::NONE || !present {
    failed_bank(bank, failure, Error { code: Fault::UNRESERVED_KEY, key, member })
  } else if bank.status == Status::PROVISIONAL && bank.deferred.code != Fault::NONE {
    BankStep<CAPACITY> { changed: false, bank, failure,
      result: Result { outcome: Outcome::WAIT, lease, ..zero!<Result>() } }
  } else if fault != Fault::NONE && bank.status != Status::PROVISIONAL {
    failed_bank(bank, failure, error)
  } else if fault != Fault::NONE {
    BankStep<CAPACITY> { changed: true, bank: Bank<CAPACITY> { deferred: error, ..bank }, failure,
      result: Result { outcome: Outcome::DEFERRED, lease, ..zero!<Result>() } }
  } else {
    let seen = bank.seen | member_bit;
    let next_bank = Bank<CAPACITY> { seen,
      status: if bank.status == Status::OPEN && seen == bank.members { Status::SEALED }
        else { bank.status }, ..bank };
    BankStep<CAPACITY> { changed: true, bank: next_bank, failure,
      result: Result { outcome: Outcome::ACCEPTED, lease,
        write: WriteIntent { valid: true, bank: slot, member } } }
  }
}

// Store by explicit member index. Provisional faults retain the offending identity
// without overwriting a value; subsequent inputs to that bank wait until validation.
// Open/complete-bank faults stop immediately, including duplicates after completion.
// Unreserved keys are protocol faults, not a request to infer a future epoch.
pub fn offer<CAPACITY: u32>(
    state: State<CAPACITY>, key: u32, member: u32)
    -> (State<CAPACITY>, Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let first_key_match = first.status != Status::FREE && first.key == key;
  let second_key_match = second.status != Status::FREE && second.key == key;
  let slot = if first_key_match { u1:0 } else { u1:1 };
  let step = offer_bank(state.banks[slot as u32], slot, state.reset_epoch, state.failure,
    first_key_match || second_key_match, key, member);
  (apply_bank(state, slot, step), step.result)
}

// Reuse the first occupied matching key, or reserve before offering to that scalar bank.
// A reservation WAIT leaves state unchanged and returns a zero-lease/write WAIT offer;
// every other path preserves separate reservation/offer results and commits once.
pub fn reserve_and_offer<CAPACITY: u32>(
    state: State<CAPACITY>, key: u32, candidates: bits[CAPACITY], member: u32)
    -> (State<CAPACITY>, Result, Result) {
  let first = state.banks[u32:0];
  let second = state.banks[u32:1];
  let first_key_match = first.status != Status::FREE && first.key == key;
  let second_key_match = second.status != Status::FREE && second.key == key;
  let present = first_key_match || second_key_match;
  let free = first.status == Status::FREE || second.status == Status::FREE;
  let slot = if first_key_match { u1:0 } else if second_key_match { u1:1 }
    else if first.status == Status::FREE { u1:0 } else { u1:1 };
  let bank = state.banks[slot as u32];
  let prepared = if present {
    BankStep<CAPACITY> { changed: false, bank, failure: state.failure,
      result: Result { outcome: Outcome::ACCEPTED,
        lease: bank_ticket(bank, slot, state.reset_epoch), ..zero!<Result>() } }
  } else {
    reserve_bank(bank, slot, state.reset_epoch, state.failure, key, candidates, present, free)
  };
  if prepared.result.outcome == Outcome::WAIT {
    (state, prepared.result, Result { outcome: Outcome::WAIT, ..zero!<Result>() })
  } else {
    let offered = offer_bank(prepared.bank, slot, state.reset_epoch, prepared.failure,
      present || prepared.result.outcome == Outcome::ACCEPTED, key, member);
    let committed = BankStep<CAPACITY> {
      changed: prepared.changed || offered.changed, ..offered };
    (apply_bank(state, slot, committed), prepared.result, offered.result)
  }
}

// Apply acquisition with an established current bank status. Callers must supply
// state.banks[lease.bank].status; identity and sticky failure are still checked.
fn acquire_at_status<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease, status: Status)
    -> (State<CAPACITY>, Result) {
  let bank = state.banks[lease.bank as u32];
  let checked = check_lease(state, lease);
  if state.failure.code != Fault::NONE || checked != Fault::NONE {
    fail(state, Error { code: checked, key: lease.key, member: u32:0 })
  } else if status == Status::OPEN || status == Status::PROVISIONAL {
    (state, Result { outcome: Outcome::WAIT, lease, ..zero!<Result>() })
  } else if status != Status::SEALED {
    fail(state, Error { code: Fault::WRONG_STATUS, key: lease.key, member: u32:0 })
  } else {
    (State<CAPACITY> { banks: update(state.banks, lease.bank as u32,
      Bank<CAPACITY> { status: Status::BORROWED, ..bank }), ..state },
      Result { outcome: Outcome::ACCEPTED, lease, ..zero!<Result>() })
  }
}

// Borrow one sealed view exactly once. Incomplete valid windows wait indefinitely;
// a missing member is never interpreted as zero or as permission to release.
pub fn acquire<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease)
    -> (State<CAPACITY>, Result) {
  acquire_at_status(state, lease, state.banks[lease.bank as u32].status)
}

// PRECONDITION: state.banks[lease.bank].status == Status::SEALED, established from
// this same state by the composing caller. Lease identity and sticky failures
// retain ordinary acquire checks; only the established status is supplied here.
pub fn acquire_sealed<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease)
    -> (State<CAPACITY>, Result) {
  acquire_at_status(state, lease, Status::SEALED)
}

// Authorize reads of a borrowed immutable view while callbacks or entry are
// pending. A failed read latches a protocol fault and emits no read intent.
pub fn read<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease)
    -> (State<CAPACITY>, ReadIntent<CAPACITY>, Result) {
  let bank = state.banks[lease.bank as u32];
  let checked = check_lease(state, lease);
  let fault = if checked != Fault::NONE { checked }
    else if bank.status != Status::BORROWED { Fault::WRONG_STATUS } else { Fault::NONE };
  if state.failure.code != Fault::NONE || fault != Fault::NONE {
    let (next, result) = fail(state, Error { code: fault, key: lease.key, member: u32:0 });
    (next, zero!<ReadIntent<CAPACITY>>(), result)
  } else {
    (state, ReadIntent<CAPACITY> { valid: true, lease, members: bank.members },
      Result { outcome: Outcome::ACCEPTED, lease, ..zero!<Result>() })
  }
}

// Retire only after the final callback/entry reader commits. Merely delivering
// completion is not release; a held or retried callback must keep its lease.
pub fn release<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease)
    -> (State<CAPACITY>, Result) {
  let bank = state.banks[lease.bank as u32];
  let checked = check_lease(state, lease);
  let fault = if checked != Fault::NONE { checked }
    else if bank.status != Status::BORROWED { Fault::WRONG_STATUS } else { Fault::NONE };
  if state.failure.code != Fault::NONE || fault != Fault::NONE {
    fail(state, Error { code: fault, key: lease.key, member: u32:0 })
  } else {
    let cleared = Bank<CAPACITY> { key: bank.key, generation: bank.generation,
      ..zero!<Bank<CAPACITY>>() };
    (State<CAPACITY> { banks: update(state.banks, lease.bank as u32, cleared), ..state },
      Result { outcome: Outcome::ACCEPTED, lease, ..zero!<Result>() })
  }
}

// An outer phase decision may withdraw an empty reservation, but invalidating any
// retained arrival is an immediate wrong-key failure rather than cancellation.
pub fn invalidate<CAPACITY: u32>(
    state: State<CAPACITY>, lease: Lease)
    -> (State<CAPACITY>, Result) {
  let bank = state.banks[lease.bank as u32];
  let checked = check_lease(state, lease);
  let fault = if checked != Fault::NONE { checked }
    else if bank.status != Status::PROVISIONAL { Fault::WRONG_STATUS }
    else if bank.seen != bits[CAPACITY]:0 || bank.deferred.code != Fault::NONE { Fault::KEY_MISMATCH }
    else { Fault::NONE };
  if state.failure.code != Fault::NONE || fault != Fault::NONE {
    fail(state, Error { code: fault, key: lease.key, member: u32:0 })
  } else {
    let cleared = Bank<CAPACITY> { key: bank.key, generation: bank.generation,
      ..zero!<Bank<CAPACITY>>() };
    (State<CAPACITY> { banks: update(state.banks, lease.bank as u32, cleared), ..state },
      Result { outcome: Outcome::ACCEPTED, lease, ..zero!<Result>() })
  }
}

// Reset invalidates occupied/borrowed views and clears failure under a fresh epoch.
// The outer reset authority must not recycle an epoch while any older ticket exists.
pub fn reset<CAPACITY: u32>(
    state: State<CAPACITY>, reset_epoch: u32)
    -> (State<CAPACITY>, Result) {
  if reset_epoch == state.reset_epoch {
    fail(state, Error { code: Fault::RESET_EPOCH_REUSED, key: u32:0, member: u32:0 })
  } else {
    (init<CAPACITY>(reset_epoch),
      Result { outcome: Outcome::ACCEPTED, ..zero!<Result>() })
  }
}
